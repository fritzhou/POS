import 'dart:convert';
import 'dart:io';
import 'package:drift/native.dart';
import 'package:nexapos/core/security/local_database_security.dart';
import 'package:nexapos/core/auth/secure_session_storage.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:nexapos/core/auth/auth_models.dart';
import 'package:nexapos/core/operations/operation_journal.dart';
import 'package:nexapos/features/catalog/domain/repository_support.dart';
import 'package:nexapos/core/operations/native_operation_journal.dart';
import 'package:nexapos/core/security/app_role.dart';
import 'package:nexapos/features/logistics/domain/logistics_models.dart';
import 'package:nexapos/features/logistics/data/supabase_logistics_repository.dart';
import 'package:nexapos/features/logistics/presentation/logistics_page.dart';
import 'package:nexapos/app/theme/app_theme.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

final fixture =
    jsonDecode(
          File('test/fixtures/logistics_sql_contract.json').readAsStringSync(),
        )
        as Map<String, dynamic>;
AuthenticatedUser actor({
  Set<String>? branches,
  AppRole role = AppRole.owner,
}) => AuthenticatedUser(
  userId: fixture['dispatch']['actor_id'] as String,
  email: 'owner@example.test',
  organizationId: fixture['organization_id'] as String,
  membershipId: '11000000-0000-4000-8000-000000000004',
  role: role,
  branchIds:
      branches ??
      {
        fixture['source_branch_id'] as String,
        fixture['destination_branch_id'] as String,
      },
  allBranches: true,
  businessName: 'Isolated logistics fixture',
);

class _Harness {
  _Harness({NativeOperationJournal? journal, this.membership}) {
    this.journal =
        journal ??
        NativeOperationJournal(
          executor: NativeDatabase.memory(),
          organizationId:
              membership?.organizationId ??
              fixture['organization_id'] as String,
          actorId:
              membership?.userId ??
              (fixture['dispatch'] as Map)['actor_id'] as String,
        );
    client = SupabaseClient(
      'https://project.example.test',
      'public-test-key',
      authOptions: const AuthClientOptions(autoRefreshToken: false),
      httpClient: MockClient((request) async {
        requests.add(request);
        final response = await handler(request);
        return http.Response(
          response.body,
          response.statusCode,
          headers: response.headers,
          request: request,
        );
      }),
    );
  }
  late final NativeOperationJournal journal;
  final AuthenticatedUser? membership;
  bool _closed = false;
  late final SupabaseClient client;
  final requests = <http.Request>[];

  Map<String, dynamic> result = Map.from(fixture['branch_action'] as Map);
  late Future<http.Response> Function(http.Request) handler = (request) async =>
      response(result);
  static http.Response response(Object value, {int status = 200}) =>
      http.Response(
        jsonEncode(value),
        status,
        headers: {'content-type': 'application/json'},
      );
  SupabaseLogisticsRepository repository({bool recovery = false}) =>
      SupabaseLogisticsRepository(
        client: client,
        actor: membership ?? actor(),
        journal: journal,
        isRecoverySession: () => recovery,
      );
  Future<void> signIn({String? actor}) async {
    actor ??=
        membership?.userId ??
        (fixture['dispatch'] as Map)['actor_id'] as String;
    String encode(Object value) =>
        base64Url.encode(utf8.encode(jsonEncode(value))).replaceAll('=', '');
    await client.auth.setInitialSession(
      jsonEncode({
        'access_token':
            '${encode({'alg': 'HS256'})}.${encode({'sub': actor, 'exp': 4102444800})}.test',
        'refresh_token': 'test-refresh',
        'token_type': 'bearer',
        'user': {
          'id': actor,
          'aud': 'authenticated',
          'email': 'owner@example.test',
          'email_confirmed_at': '2026-10-11T00:00:00Z',
          'created_at': '2026-10-11T00:00:00Z',
          'app_metadata': {},
          'user_metadata': {},
        },
      }),
    );
  }

  Future<void> close() async {
    if (_closed) return;
    _closed = true;
    await client.dispose();
    await journal.close();
  }
}

class _Store implements SecretStore {
  final values = <String, String>{};
  @override
  Future<String?> read(String key) async => values[key];
  @override
  Future<void> write(String key, String value) async {
    values[key] = value;
  }

  @override
  Future<void> delete(String key) async {
    values.remove(key);
  }
}

class _BranchRepo extends SupabaseLogisticsRepository {
  _BranchRepo(_Harness h)
    : super(client: h.client, actor: actor(), journal: h.journal);
  @override
  Future<List<PendingOperation>> pending() async => [];
  @override
  Future<Map<String, dynamic>> branchContext() async => {
    'organization_id': organizationId,
    'actor_id': actor().userId,
    'can_create': true,
    'can_set_active': true,
    'maximum_active_branches': 100,
  };
  @override
  Future<DataPage<ManagedBranch>> branches({
    PageRequest page = const PageRequest(),
  }) async => DataPage(
    items: [
      ManagedBranch.fromRow(
        Map.from(fixture['branch_action']['branch'] as Map),
      ),
    ],
    hasMore: false,
    offset: 0,
  );
}

void main() {
  for (final invalid in ['currency', 'line_cost_minor', 'duplicate']) {
    test('supplier history rejects inconsistent $invalid evidence', () async {
      final h = _Harness();
      addTearDown(h.close);
      await h.signIn();
      final row =
          jsonDecode(jsonEncode(fixture['supplier_return']))
              as Map<String, dynamic>;
      if (invalid == 'currency') {
        row['document']['currency'] = 'JPY';
      } else if (invalid == 'line_cost_minor') {
        row['document']['items'][0]['line_cost_minor'] = 1;
      }
      h.handler = (_) async =>
          _Harness.response(invalid == 'duplicate' ? [row, row] : [row]);
      await expectLater(
        h.repository().returns(fixture['source_branch_id'] as String),
        throwsA(anything),
      );
    });
  }
  test('valid original supplier history decodes exact costs', () async {
    final h = _Harness();
    addTearDown(h.close);
    await h.signIn();
    h.handler = (_) async => _Harness.response([fixture['supplier_return']]);
    expect(
      (await h.repository().returns(
        fixture['source_branch_id'] as String,
      )).items.single.document['total_minor'],
      375,
    );
  });
  test('invalid branch paging is refused before network dispatch', () async {
    final h = _Harness();
    addTearDown(h.close);
    await h.signIn();
    expect(
      () => h.repository().branches(page: const PageRequest(limit: 101)),
      throwsA(isA<RepositoryFailure>()),
    );
    expect(h.requests, isEmpty);
  });

  for (final width in [320.0, 1440.0]) {
    testWidgets(
      'connected branch form and stale account invalidation at $width',
      (tester) async {
        final h = (await tester.runAsync(() async {
          final h = _Harness();
          await h.signIn();
          return h;
        }))!;
        addTearDown(() async {
          await tester.runAsync(h.close);
        });

        final repository = _BranchRepo(h);
        h.handler = (request) async => _Harness.response(
          request.url.path.endsWith('/get_branch_management_context')
              ? {
                  'organization_id': fixture['organization_id'],
                  'actor_id': fixture['dispatch']['actor_id'],
                  'can_create': true,
                  'can_set_active': true,
                  'maximum_active_branches': 100,
                }
              : [fixture['branch_action']['branch']],
        );
        tester.view.devicePixelRatio = 1;
        tester.view.physicalSize = Size(width, 900);
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        Widget page(bool preview) => MaterialApp(
          theme: AppTheme.light,
          home: Scaffold(
            body: LogisticsPage(
              repository: repository,
              role: AppRole.owner,
              branchesOnly: true,
              isPreview: preview,
            ),
          ),
        );
        await tester.pumpWidget(page(false));
        await tester.pumpAndSettle();
        expect(find.text('Destination'), findsOneWidget);
        await tester.ensureVisible(find.byKey(const Key('branch-create')));
        await tester.tap(find.byKey(const Key('branch-create')));
        await tester.pumpAndSettle();
        expect(find.text('Create active branch'), findsOneWidget);
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(page(true));
        await tester.pumpAndSettle();
        expect(find.text('Business context changed'), findsOneWidget);
        expect(find.text('Save branch'), findsNothing);
        expect(tester.takeException(), isNull);
        await tester.tap(find.text('Close'));
        await tester.pumpAndSettle();
        expect(
          h.requests.where((r) => r.url.path.endsWith('/save_branch')),
          isEmpty,
        );
      },
    );
  }

  for (final key in ['receipt', 'transit_return']) {
    test('actual $key mutation validates all ledger evidence', () async {
      final h = _Harness();
      addTearDown(h.close);
      await h.signIn();
      h.result = Map.from(fixture[key] as Map);
      final row =
          jsonDecode(jsonEncode(fixture['transfer'])) as Map<String, dynamic>;
      final line = (row['items'] as List).single as Map;
      final returning = key == 'transit_return';
      row['revision'] = returning ? 2 : 1;
      row['status'] = returning ? 'partially_completed' : 'in_transit';
      line['received'] = returning ? 4 : 0;
      line['returned'] = 0;
      line['remaining'] = returning ? 2 : 6;
      expect(
        await h.repository().complete(
          branch:
              fixture[returning ? 'source_branch_id' : 'destination_branch_id']
                  as String,
          original: StockTransfer.fromRow(row),
          returning: returning,
          quantities: {line['id'] as String: returning ? 2 : 4},
          confirmed: true,
          reason: 'Physical quantity confirmed',
          requestId: h.result['request_id'] as String,
        ),
        isA<LogisticsAction>(),
      );
      expect(await h.repository().pending(), isEmpty);
    });
  }
  test(
    'supplier return verifies original cost and exact original receipt',
    () async {
      final h = _Harness();
      addTearDown(h.close);
      await h.signIn();
      h.result = Map.from(fixture['supplier_return'] as Map);
      final row =
          jsonDecode(jsonEncode(fixture['return_context']))
              as Map<String, dynamic>;
      final line = (row['items'] as List).single as Map;
      line['returned'] = 0;
      expect(
        await h.repository().supplierReturn(
          original: PurchaseReturnContext.fromRow(row),
          quantities: {line['item_id'] as String: 3},
          confirmed: true,
          reason: 'Three physically returned goods',
          requestId: h.result['request_id'] as String,
        ),
        isA<LogisticsAction>(),
      );
      expect(await h.repository().pending(), isEmpty);
    },
  );
  test(
    'SQLCipher close reopen preserves original unit proof and exact retry',
    () async {
      final directory = await Directory.systemTemp.createTemp(
        'nexapos-logistics-',
      );
      addTearDown(() => directory.delete(recursive: true));
      final file = File('${directory.path}/journal.sqlite');
      final factory = EncryptedDatabaseFactory(store: _Store());
      NativeOperationJournal journal(dynamic executor) =>
          NativeOperationJournal(
            executor: executor,
            organizationId: fixture['organization_id'] as String,
            actorId: fixture['dispatch']['actor_id'] as String,
          );
      final first = _Harness(journal: journal(await factory.open(file)));
      await first.signIn();
      first.result = Map.from(fixture['dispatch'] as Map);
      final d = first.result['document'] as Map;
      final line = (d['items'] as List).single as Map;
      first.result['actor_id'] = '11000000-0000-4000-8000-000000000099';
      await expectLater(
        first.repository().dispatch(
          source: fixture['source_branch_id'] as String,
          destination: fixture['destination_branch_id'] as String,
          lines: [
            {
              'product_id': line['product_id'],
              'quantity': line['quantity'],
              'expected_revision': line['expected_revision'],
              'unit': line['unit'],
            },
          ],
          reason: 'Six goods physically dispatched',
          confirmed: true,
          requestId: first.result['request_id'] as String,
        ),
        throwsA(anything),
      );
      await first.close();
      expect(
        utf8.decode(await file.readAsBytes(), allowMalformed: true),
        isNot(contains('_nexapos_logistics_proof')),
      );
      final second = _Harness(journal: journal(await factory.open(file)));
      addTearDown(second.close);
      await second.signIn();
      second.result = Map.from(fixture['dispatch'] as Map);
      final pending = (await second.repository().pending()).single;
      expect(pending.payload['_nexapos_logistics_proof'], isNotNull);
      expect(pending.attemptCount, 1);
      expect(await second.repository().retry(pending), isA<LogisticsAction>());
      expect(
        jsonDecode(second.requests.single.body)['p_request_id'],
        pending.requestId,
      );
      expect(await second.repository().pending(), isEmpty);
    },
  );

  test('actual PostgreSQL branch and transfer contracts decode', () {
    final b = ManagedBranch.fromRow(
      Map.from(fixture['branch_action']['branch'] as Map),
    );
    expect(b.active, true);
    expect(b.revision, 1);
    final t = StockTransfer.fromRow(Map.from(fixture['transfer'] as Map));
    expect(t.status, 'completed');
    expect(t.lines.single.received, 4);
    expect(t.lines.single.returned, 2);
    expect(t.lines.single.remaining, 0);
    final c = PurchaseReturnContext.fromRow(
      Map.from(fixture['return_context'] as Map),
    );
    expect(c.currency, 'PHP');
    expect(c.lines.single.unitCostMinor, 125);
    expect(c.lines.single.returned, 3);
  });
  for (final key in [
    'dispatch',
    'receipt',
    'transit_return',
    'supplier_return',
  ]) {
    test('actual $key action envelope decodes', () {
      expect(
        LogisticsAction.fromRow(Map.from(fixture[key] as Map)).document['id'],
        isNotEmpty,
      );
    });
  }
  for (final invalid in [1.0, -1, 9007199254740992, '1', null]) {
    test('exact integer rejects $invalid', () {
      expect(() => logisticsInteger(invalid), throwsFormatException);
    });
  }
  for (final time in [
    '2026-02-30T00:00:00Z',
    '2026-10-12T00:00:00+08:00',
    '2026-10-12',
  ]) {
    test('timestamp rejects $time', () {
      expect(() => logisticsTime(time), throwsFormatException);
    });
  }
  for (final field in ['status', 'line_count', 'source_branch_id']) {
    test('transfer rejects inconsistent $field', () {
      final row =
          jsonDecode(jsonEncode(fixture['transfer'])) as Map<String, dynamic>;
      row[field] = field == 'line_count'
          ? 2
          : field == 'status'
          ? 'received'
          : row['destination_branch_id'];
      expect(() => StockTransfer.fromRow(row), throwsFormatException);
    });
  }
  for (final field in [
    'received',
    'remaining',
    'returned',
    'unit_cost_minor',
  ]) {
    test('line evidence rejects invalid $field', () {
      final purchase = field == 'unit_cost_minor';
      final row = Map<String, dynamic>.from(
        (fixture[purchase ? 'return_context' : 'transfer']['items'] as List)
                .first
            as Map,
      );
      row[field] = 9007199254740991;
      expect(
        () => LogisticsLine.fromRow(row, purchase: purchase),
        throwsFormatException,
      );
    });
  }
  Future<Object> create(_Harness h) => h.repository().saveBranch(
    anchor: fixture['source_branch_id'] as String,
    name: 'Destination',
    code: 'DEST',
    active: true,
    reason: 'Create delivery destination',
    requestId: fixture['branch_action']['request_id'] as String,
  );
  test(
    'branch success validates server evidence before journal confirmation',
    () async {
      final h = _Harness();
      addTearDown(h.close);
      await h.signIn();
      expect(await create(h), isA<ManagedBranch>());
      expect(await h.repository().pending(), isEmpty);
    },
  );
  test(
    'malformed success preserves intent and later denial remains uncertain',
    () async {
      final h = _Harness();
      addTearDown(h.close);
      await h.signIn();
      h.result['actor_id'] = '11000000-0000-4000-8000-000000000099';
      await expectLater(create(h), throwsA(anything));
      final pending = await h.repository().pending();
      expect(pending.single.attemptCount, 1);
      h.handler = (_) async => _Harness.response({
        'code': '42501',
        'message': 'Current access denied',
      }, status: 403);
      await expectLater(
        h.repository().retry(pending.single),
        throwsA(anything),
      );
      expect((await h.repository().pending()).single.attemptCount, 2);
    },
  );
  test(
    'historical journal anchor retries under fresh identity without stale branch authorization',
    () async {
      final h = _Harness(
        membership: actor(
          branches: {fixture['destination_branch_id'] as String},
        ),
      );
      addTearDown(h.close);
      await h.signIn();
      final action = fixture['branch_action'] as Map;
      final p = await h.journal.prepare(
        requestId: action['request_id'] as String,
        type: 'save_branch',
        branchId: fixture['source_branch_id'] as String,
        payload: {
          'p_organization_id': fixture['organization_id'],
          'p_request_id': action['request_id'],
          'p_branch_id': null,
          'p_expected_revision': null,
          'p_name': 'Destination',
          'p_code': 'DEST',
          'p_address': null,
          'p_active': true,
          'p_reason': 'Create delivery destination',
        },
      );
      expect(await h.repository().retry(p), isA<ManagedBranch>());
      expect(h.requests.single.url.path, endsWith('/save_branch'));
    },
  );
  test(
    'dispatch persists local original unit proof and strips it from RPC',
    () async {
      final h = _Harness();
      addTearDown(h.close);
      await h.signIn();
      h.result = Map.from(fixture['dispatch'] as Map);
      final d = h.result['document'] as Map;
      final line = (d['items'] as List).single as Map;
      final action = await h.repository().dispatch(
        source: fixture['source_branch_id'] as String,
        destination: fixture['destination_branch_id'] as String,
        lines: [
          {
            'product_id': line['product_id'],
            'quantity': line['quantity'],
            'expected_revision': line['expected_revision'],
            'unit': line['unit'],
          },
        ],
        reason: 'Six goods physically dispatched',
        confirmed: true,
        requestId: h.result['request_id'] as String,
      );
      expect(action, isA<LogisticsAction>());
      expect(
        jsonDecode(
          h.requests.single.body,
        ).containsKey('_nexapos_logistics_proof'),
        false,
      );
      expect(await h.repository().pending(), isEmpty);
    },
  );
  for (final recovery in [false, true]) {
    test('missing or recovery identity refuses RPC $recovery', () async {
      final h = _Harness();
      addTearDown(h.close);
      if (recovery) await h.signIn();
      await expectLater(
        h.repository(recovery: recovery).branches(),
        throwsA(anything),
      );
      expect(h.requests, isEmpty);
    });
  }
  for (final size in [const Size(320, 740), const Size(1440, 1000)]) {
    for (final branches in [false, true]) {
      testWidgets('empty logistics layout $size branches=$branches', (
        tester,
      ) async {
        tester.view.devicePixelRatio = 1;
        tester.view.physicalSize = size;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        await tester.pumpWidget(
          MaterialApp(
            theme: AppTheme.light,
            home: Scaffold(body: LogisticsPage(branchesOnly: branches)),
          ),
        );
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        expect(find.byType(LogisticsPage), findsOneWidget);
      });
    }
  }
}
