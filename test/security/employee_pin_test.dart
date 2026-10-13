import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:nexapos/core/auth/auth_models.dart';
import 'package:nexapos/core/security/app_role.dart';
import 'package:nexapos/features/catalog/domain/repository_support.dart';
import 'package:nexapos/features/security/pin_security.dart';
import 'package:nexapos/features/security/pin_security_section.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

const org = '11111111-1111-4111-8111-111111111111';
const user = '22222222-2222-4222-8222-222222222222';
const member = '33333333-3333-4333-8333-333333333333';
const branch = '44444444-4444-4444-8444-444444444444';
const requestId = '55555555-5555-4555-8555-555555555555';
const other = '99999999-9999-4999-8999-999999999999';
Map<String, Object?> wire({
  String id = member,
  int revision = 1,
  bool configured = false,
}) => {
  'membership_id': id,
  'configured': configured,
  'reset_required': !configured,
  'revision': revision,
  'locked_until': null,
  'changed_at': null,
};
const fixtureStatus = EmployeePinStatus(
  membershipId: member,
  configured: false,
  resetRequired: true,
  revision: 1,
);

class Harness {
  Harness() {
    client = SupabaseClient(
      'https://project.example.invalid',
      'fixture-public-key',
      authOptions: const AuthClientOptions(autoRefreshToken: false),
      httpClient: MockClient((request) async {
        requests.add(request);
        if (handler != null) return handler!(request);
        return http.Response(
          jsonEncode(payload),
          responseStatus,
          headers: {'content-type': 'application/json'},
          request: request,
        );
      }),
    );
  }
  late final SupabaseClient client;
  final requests = <http.Request>[];
  Object? payload;
  int responseStatus = 200;
  Future<http.Response> Function(http.Request)? handler;
  bool recovery = false;
  Future<void> signIn({String id = user, bool verified = true}) async {
    String part(Object v) =>
        base64Url.encode(utf8.encode(jsonEncode(v))).replaceAll('=', '');
    await client.auth.recoverSession(
      jsonEncode({
        'access_token':
            '${part({'alg': 'HS256'})}.${part({'sub': id, 'exp': 4102444800})}.fixture-signature',
        'refresh_token': 'fixture-refresh',
        'token_type': 'bearer',
        'user': {
          'id': id,
          'aud': 'authenticated',
          'email': 'pin@example.invalid',
          'email_confirmed_at': verified ? '2026-10-11T00:00:00Z' : null,
          'created_at': '2026-10-11T00:00:00Z',
          'app_metadata': {},
          'user_metadata': {},
        },
      }),
    );
  }

  SupabaseEmployeePinRepository get repository => SupabaseEmployeePinRepository(
    client: client,
    actor: AuthenticatedUser(
      userId: user,
      email: 'pin@example.invalid',
      organizationId: org,
      membershipId: member,
      role: AppRole.owner,
      branchIds: {branch},
      allBranches: true,
      businessName: 'Fixture business',
    ),
    isRecoverySession: () => recovery,
  );
}

class FakePinRepository implements EmployeePinRepository {
  @override
  String get organizationId => org;
  EmployeePinStatus current = fixtureStatus;
  List<EmployeePinResetTarget> targets = [];
  final requests = <String>[];
  final resetReasons = <String>[];
  bool failSet = false;
  Completer<EmployeePinStatus>? statusCompleter;
  @override
  Future<EmployeePinStatus> status({String? membershipId}) async =>
      statusCompleter != null ? statusCompleter!.future : current;
  @override
  Future<DataPage<EmployeePinResetTarget>> resetTargets({
    PageRequest page = const PageRequest(),
  }) async => DataPage(items: targets, hasMore: false, offset: page.offset);
  @override
  Future<EmployeePinResult> setPin({
    required String requestId,
    required int expectedRevision,
    required String pin,
    String? currentPin,
  }) async {
    requests.add(requestId);
    if (failSet) {
      throw const RepositoryFailure(
        RepositoryFailureType.unavailable,
        'PIN service unavailable. Retry.',
      );
    }
    current = const EmployeePinStatus(
      membershipId: member,
      configured: true,
      resetRequired: false,
      revision: 2,
    );
    return EmployeePinResult(accepted: true, status: current);
  }

  @override
  Future<EmployeePinResult> verifyPin({
    required String requestId,
    required int expectedRevision,
    required String pin,
  }) async => EmployeePinResult(accepted: false, status: current);
  @override
  Future<EmployeePinStatus> resetPin({
    required String membershipId,
    required String requestId,
    required int expectedRevision,
    required String reason,
  }) async {
    resetReasons.add(reason);
    return current;
  }
}

Future<void> pumpSection(
  WidgetTester tester,
  FakePinRepository repository, {
  AppRole role = AppRole.cashier,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: SingleChildScrollView(
          child: PinSecuritySection(repository: repository, role: role),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  group('PIN repository boundary', () {
    late Harness h;
    setUp(() {
      h = Harness();
    });
    tearDown(() async {
      await h.client.dispose();
    });
    test('PIN validation accepts only 6–12 ASCII digits', () {
      validateEmployeePin('739284');
      validateEmployeePin('739284675849');
      for (final value in [
        '12345',
        '739284 ',
        '７３９２８４',
        '1234567890123',
        '73a284',
      ]) {
        expect(
          () => validateEmployeePin(value),
          throwsA(isA<RepositoryFailure>()),
        );
      }
    });
    test(
      'own status decodes exact member and rejects a foreign response',
      () async {
        await h.signIn();
        h.payload = wire();
        expect((await h.repository.status()).configured, isFalse);
        expect(jsonDecode(h.requests.single.body)['p_organization_id'], org);
        h.payload = wire(id: other);
        await expectLater(
          h.repository.status(),
          throwsA(isA<RepositoryFailure>()),
        );
      },
    );
    test(
      'set PIN uses authenticated Edge boundary with stable operation and no client hash',
      () async {
        await h.signIn();
        h.payload = {
          'accepted': true,
          'status': wire(revision: 2, configured: true),
        };
        final result = await h.repository.setPin(
          requestId: requestId,
          expectedRevision: 1,
          pin: '739284',
        );
        expect(result.accepted, isTrue);
        final request = h.requests.single;
        expect(request.url.path, '/functions/v1/employee-pin');
        final body = jsonDecode(request.body) as Map;
        expect(body['request_id'], requestId);
        expect(body['pin'], '739284');
        expect(body['current_pin'], isNull);
        expect(body.containsKey('pin_hash'), isFalse);
        expect(body.containsKey('role'), isFalse);
      },
    );
    test(
      'verify returns denial as explicit result and never creates authenticated session',
      () async {
        await h.signIn();
        final original = h.client.auth.currentSession;
        h.payload = {
          'accepted': false,
          'status': wire(revision: 2, configured: true),
        };
        expect(
          (await h.repository.verifyPin(
            requestId: requestId,
            expectedRevision: 2,
            pin: '739284',
          )).accepted,
          isFalse,
        );
        expect(jsonDecode(h.requests.single.body)['action'], 'verify');
        expect(h.client.auth.currentSession, same(original));
      },
    );
    test(
      'reset sends target revision and reason under selected organization',
      () async {
        await h.signIn();
        h.payload = wire(id: other, revision: 3);
        await h.repository.resetPin(
          membershipId: other,
          requestId: requestId,
          expectedRevision: 2,
          reason: 'Employee forgot previous PIN',
        );
        final body = jsonDecode(h.requests.single.body);
        expect(body['p_membership_id'], other);
        expect(body['p_expected_revision'], 2);
        expect(body['p_reason'], 'Employee forgot previous PIN');
        expect(h.requests.single.url.path, '/rest/v1/rpc/reset_employee_pin');
      },
    );
    test(
      'reset list strictly scopes nested statuses and validates returned role',
      () async {
        await h.signIn();
        h.payload = [
          {
            'membership_id': other,
            'full_name': 'Fixture cashier',
            'role': 'cashier',
            'status': wire(id: other),
          },
        ];
        expect(
          (await h.repository.resetTargets()).items.single.role,
          AppRole.cashier,
        );
        h.payload = [
          {
            'membership_id': other,
            'full_name': 'Fixture cashier',
            'role': 'cashier',
            'status': wire(),
          },
        ];
        await expectLater(
          h.repository.resetTargets(),
          throwsA(isA<RepositoryFailure>()),
        );
      },
    );
    test(
      'anonymous, recovery and switched actor are blocked before sending PIN',
      () async {
        await expectLater(
          h.repository.setPin(
            requestId: requestId,
            expectedRevision: 1,
            pin: '739284',
          ),
          throwsA(isA<RepositoryFailure>()),
        );
        await h.signIn();
        h.recovery = true;
        await expectLater(
          h.repository.setPin(
            requestId: requestId,
            expectedRevision: 1,
            pin: '739284',
          ),
          throwsA(isA<RepositoryFailure>()),
        );
        h.recovery = false;
        await h.signIn(id: other);
        await expectLater(
          h.repository.setPin(
            requestId: requestId,
            expectedRevision: 1,
            pin: '739284',
          ),
          throwsA(isA<RepositoryFailure>()),
        );
        expect(h.requests, isEmpty);
      },
    );
    test(
      'malformed or provider failure never returns raw PIN/hashes',
      () async {
        await h.signIn();
        h.payload = {
          'accepted': 'true',
          'status': wire(),
          'pin_hash': 'PRIVATE',
        };
        await expectLater(
          h.repository.setPin(
            requestId: requestId,
            expectedRevision: 1,
            pin: '739284',
          ),
          throwsA(
            isA<RepositoryFailure>().having(
              (e) => e.message,
              'message',
              isNot(contains('PRIVATE')),
            ),
          ),
        );
        h.responseStatus = 403;
        h.payload = {'message': 'PRIVATE 739284'};
        await expectLater(
          h.repository.setPin(
            requestId: requestId,
            expectedRevision: 1,
            pin: '739284',
          ),
          throwsA(
            isA<RepositoryFailure>().having(
              (e) => e.message,
              'message',
              isNot(contains('739284')),
            ),
          ),
        );
      },
    );
    test(
      'delayed response cannot expose PIN status to changed account',
      () async {
        await h.signIn();
        final response = Completer<http.Response>();
        h.handler = (_) => response.future;
        final pending = h.repository.status();
        await Future<void>.delayed(Duration.zero);
        await h.signIn(id: other);
        response.complete(
          http.Response(
            jsonEncode(wire()),
            200,
            headers: {'content-type': 'application/json'},
            request: h.requests.single,
          ),
        );
        await expectLater(
          pending,
          throwsA(
            isA<RepositoryFailure>().having(
              (e) => e.type,
              'type',
              RepositoryFailureType.unauthenticated,
            ),
          ),
        );
      },
    );
  });
  testWidgets(
    'PIN section has empty truthful status and obscured fields at 320px',
    (tester) async {
      tester.view.physicalSize = const Size(320, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final repository = FakePinRepository();
      await pumpSection(tester, repository);
      expect(find.text('Set a new PIN for your account.'), findsOneWidget);
      expect(find.text('Reset employee PIN'), findsNothing);
      for (final field in tester.widgetList<TextField>(
        find.byType(TextField),
      )) {
        expect(field.obscureText, isTrue);
        expect(field.enableSuggestions, isFalse);
      }
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets('PIN confirmation mismatch makes no backend call', (
    tester,
  ) async {
    final repository = FakePinRepository();
    await pumpSection(tester, repository);
    await tester.enterText(find.widgetWithText(TextField, 'New PIN'), '739284');
    await tester.enterText(
      find.widgetWithText(TextField, 'Confirm new PIN'),
      '849275',
    );
    await tester.tap(find.widgetWithText(FilledButton, 'Set PIN'));
    await tester.pumpAndSettle();
    expect(repository.requests, isEmpty);
    expect(find.text('The new PINs do not match.'), findsOneWidget);
  });
  testWidgets(
    'uncertain PIN request retries same UUID and clears secrets after success',
    (tester) async {
      final repository = FakePinRepository()..failSet = true;
      await pumpSection(tester, repository);
      await tester.enterText(
        find.widgetWithText(TextField, 'New PIN'),
        '739284',
      );
      await tester.enterText(
        find.widgetWithText(TextField, 'Confirm new PIN'),
        '739284',
      );
      await tester.tap(find.widgetWithText(FilledButton, 'Set PIN'));
      await tester.pumpAndSettle();
      repository.failSet = false;
      await tester.tap(find.widgetWithText(FilledButton, 'Set PIN'));
      await tester.pumpAndSettle();
      expect(repository.requests.length, 2);
      expect(repository.requests.toSet().length, 1);
      expect(find.text('PIN saved.'), findsOneWidget);
      for (final field in tester.widgetList<TextField>(
        find.byType(TextField),
      )) {
        expect(field.controller!.text, isEmpty);
      }
    },
  );
  testWidgets('manager reset requires reason before server operation', (
    tester,
  ) async {
    final repository = FakePinRepository()
      ..targets = [
        const EmployeePinResetTarget(
          membershipId: member,
          fullName: 'Fixture cashier',
          role: AppRole.cashier,
          status: fixtureStatus,
        ),
      ];
    await pumpSection(tester, repository, role: AppRole.manager);
    await tester.ensureVisible(find.text('Reset PIN'));
    await tester.tap(find.text('Reset PIN'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Reset PIN'));
    await tester.pumpAndSettle();
    expect(repository.resetReasons, isEmpty);
    await tester.enterText(
      find.widgetWithText(TextField, 'Reset reason'),
      'Employee forgot previous PIN',
    );
    await tester.tap(find.widgetWithText(FilledButton, 'Reset PIN'));
    await tester.pumpAndSettle();
    expect(repository.resetReasons, ['Employee forgot previous PIN']);
  });
  testWidgets('late PIN status does not replace new repository context', (
    tester,
  ) async {
    final old = FakePinRepository()
      ..statusCompleter = Completer<EmployeePinStatus>();
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: PinSecuritySection(repository: old, role: AppRole.cashier),
        ),
      ),
    );
    await tester.pump();
    final next = FakePinRepository();
    await pumpSection(tester, next);
    old.statusCompleter!.complete(
      const EmployeePinStatus(
        membershipId: other,
        configured: true,
        resetRequired: false,
        revision: 99,
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Set a new PIN for your account.'), findsOneWidget);
    expect(find.text('Your PIN is configured.'), findsNothing);
  });
}
