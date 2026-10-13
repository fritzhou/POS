import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:cryptography/cryptography.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:nexapos/core/auth/auth_models.dart';
import 'package:nexapos/core/auth/secure_session_storage.dart';
import 'package:nexapos/core/database/app_database.dart';
import 'package:nexapos/core/offline/offline_device_security.dart';
import 'package:nexapos/core/offline/offline_protocol.dart';
import 'package:nexapos/core/operations/native_operation_journal.dart';
import 'package:nexapos/core/operations/operation_journal.dart';
import 'package:nexapos/core/security/app_role.dart';
import 'package:nexapos/features/catalog/domain/repository_support.dart';
import 'package:nexapos/features/checkout/domain/checkout_models.dart';
import 'package:nexapos/features/offline/data/supabase_offline_workspace.dart';
import 'package:nexapos/features/offline/domain/offline_workspace.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

const org = 'a0000000-0000-4000-8000-000000000001';
const actorId = 'a0000000-0000-4000-8000-000000000002';
const branch = 'a0000000-0000-4000-8000-000000000003';
const membership = 'a0000000-0000-4000-8000-000000000004';
const shift = 'a0000000-0000-4000-8000-000000000005';
const productId = 'a0000000-0000-4000-8000-000000000006';
const grantId = 'a0000000-0000-4000-8000-000000000007';
const requestId = 'a0000000-0000-4000-8000-000000000008';
const issuer = 'https://unit.supabase.co';
final issuedAt = DateTime.utc(2026, 10, 10, 12, 0, 0, 123, 456);

class MemorySecrets implements SecretStore {
  final values = <String, String>{};
  @override
  Future<String?> read(String key) async => values[key];
  @override
  Future<void> write(String key, String value) async => values[key] = value;
  @override
  Future<void> delete(String key) async => values.remove(key);
}

class BlockingJournal implements OperationJournal {
  BlockingJournal(this.delegate);
  final OperationJournal delegate;
  final entered = Completer<void>();
  final release = Completer<void>();
  @override
  Future<List<PendingOperation>> pending({
    String? type,
    String? branchId,
  }) async {
    if (type == 'checkout_sale') {
      entered.complete();
      await release.future;
    }
    return delegate.pending(type: type, branchId: branchId);
  }

  @override
  Future<PendingOperation> prepare({
    required String requestId,
    required String type,
    required String branchId,
    required Map<String, dynamic> payload,
  }) => delegate.prepare(
    requestId: requestId,
    type: type,
    branchId: branchId,
    payload: payload,
  );
  @override
  Future<int> markAttempted({required String requestId}) =>
      delegate.markAttempted(requestId: requestId);
  @override
  Future<void> confirm({
    required String requestId,
    required Map<String, dynamic> result,
  }) => delegate.confirm(requestId: requestId, result: result);
  @override
  Future<void> reject({
    required String requestId,
    required String failureCode,
  }) => delegate.reject(requestId: requestId, failureCode: failureCode);
  @override
  Future<void> close() => delegate.close();
}

class LoseFragmentResponseJournal implements OperationJournal {
  LoseFragmentResponseJournal(
    this.delegate, {
    this.type = 'offline_payment_fragment',
    this.beforeWrite = false,
  });
  final OperationJournal delegate;
  final String type;
  final bool beforeWrite;
  bool lose = true;
  @override
  Future<PendingOperation> prepare({
    required String requestId,
    required String type,
    required String branchId,
    required Map<String, dynamic> payload,
  }) async {
    if (type == this.type && beforeWrite && lose) {
      lose = false;
      throw StateError('local write unavailable');
    }
    final row = await delegate.prepare(
      requestId: requestId,
      type: type,
      branchId: branchId,
      payload: payload,
    );
    if (type == this.type && lose) {
      lose = false;
      throw StateError('lost local write response');
    }
    return row;
  }

  @override
  Future<List<PendingOperation>> pending({String? type, String? branchId}) =>
      delegate.pending(type: type, branchId: branchId);
  @override
  Future<int> markAttempted({required String requestId}) =>
      delegate.markAttempted(requestId: requestId);
  @override
  Future<void> confirm({
    required String requestId,
    required Map<String, dynamic> result,
  }) => delegate.confirm(requestId: requestId, result: result);
  @override
  Future<void> reject({
    required String requestId,
    required String failureCode,
  }) => delegate.reject(requestId: requestId, failureCode: failureCode);
  @override
  Future<void> close() => delegate.close();
}

class Harness {
  Harness({this.directory});
  final Directory? directory;
  final secrets = MemorySecrets();
  final actions = <Map<String, dynamic>>[];
  late SupabaseClient client;
  late NativeOperationJournal journal;
  late AppDatabase db;
  late OfflineDeviceSecurity security;
  late OfflineGrantVerifier verifier;
  late SimpleKeyPair signingKey;
  late SupabaseOfflineWorkspace workspace;
  Future<void>? _closeFuture;
  DateTime wall = issuedAt;
  bool recovery = false, signedOut = false;
  int prepareDrops = 0, ingestDrops = 0;
  int? ingestDenial;
  bool unsignedPreparationExpired = false;
  bool pullFails = false;
  String? corruptAck;
  Map<String, Object?>? preparedWire;
  Map<String, dynamic>? accepted;
  Map<String, dynamic>? pullOverride;
  final actor = AuthenticatedUser(
    userId: actorId,
    email: 'actor@example.test',
    organizationId: org,
    membershipId: membership,
    role: AppRole.cashier,
    branchIds: {branch},
    allBranches: false,
    businessName: 'Test business',
  );

  Future<void> initialize() async {
    signingKey = await Ed25519().newKeyPairFromSeed(
      List.generate(32, (i) => i),
    );
    verifier = OfflineGrantVerifier(
      issuer: issuer,
      trustedKeys: {
        'unit-key': encodeOfflineBytes(
          (await signingKey.extractPublicKey()).bytes,
        ),
      },
    );
    client = SupabaseClient(
      issuer,
      'public-unit-key',
      authOptions: const AuthClientOptions(autoRefreshToken: false),
      httpClient: MockClient(_handle),
    );
    _openStorage();
    await signIn();
  }

  void _openStorage() {
    db = AppDatabase(
      directory == null
          ? NativeDatabase.memory()
          : NativeDatabase(File('${directory!.path}/device.sqlite')),
    );
    journal = NativeOperationJournal(
      executor: directory == null
          ? NativeDatabase.memory()
          : NativeDatabase(File('${directory!.path}/journal.sqlite')),
      organizationId: org,
      actorId: actorId,
    );
    security = OfflineDeviceSecurity(store: secrets, clock: () => wall);
    workspace = SupabaseOfflineWorkspace(
      client: client,
      actor: actor,
      database: (_) async => db,
      security: security,
      verifier: verifier,
      journal: journal,
      clock: () => wall,
      isRecoverySession: () => recovery,
      isExplicitlySignedOut: () => signedOut,
    );
  }

  Future<void> restart() async {
    await db.close();
    await journal.close();
    _openStorage();
  }

  Future<void> signIn({String id = actorId}) async {
    String encode(Object value) =>
        base64Url.encode(utf8.encode(jsonEncode(value))).replaceAll('=', '');
    await client.auth.recoverSession(
      jsonEncode({
        'access_token':
            '${encode({'alg': 'HS256'})}.${encode({'sub': id, 'exp': 4102444800})}.test',
        'refresh_token': 'unit-refresh',
        'token_type': 'bearer',
        'user': {
          'id': id,
          'aud': 'authenticated',
          'email': 'actor@example.test',
          'email_confirmed_at': '2026-10-09T00:00:00Z',
          'created_at': '2026-10-09T00:00:00Z',
          'app_metadata': <String, Object?>{},
          'user_metadata': <String, Object?>{},
        },
      }),
    );
  }

  Map<String, Object?> snapshot() => {
    'context': {
      'organization_id': org,
      'branch_id': branch,
      'branch_name': 'Main',
      'currency': 'PHP',
      'tax_bps': 1250,
      'settings_revision': 10,
      'business_name': 'Test business',
    },
    'shift': {
      'id': shift,
      'actor_user_id': actorId,
      'organization_id': org,
      'branch_id': branch,
      'currency': 'PHP',
      'closure': null,
      'opened_at': issuedAt
          .subtract(const Duration(minutes: 5))
          .toIso8601String(),
      'opening_cash_minor': 1000,
      'expected_cash_minor': 1000,
    },
    'products': [
      {
        'id': productId,
        'organization_id': org,
        'currency': 'PHP',
        'name': 'Café 😀',
        'sku': 'TEST-1',
        'price_minor': 100,
        'revision': 20,
        'unit': 'each',
        'barcode': '012345',
        'active': true,
      },
    ],
    'categories': <Object?>[],
    'stock': [
      {'product_id': productId, 'quantity': 2, 'revision': 50},
    ],
    'cursor': 4,
  };

  Future<Map<String, Object?>> grant(String deviceId) async {
    final snapshotValue = snapshot();
    final claims = <String, Object?>{
      'schema_version': 1,
      'issuer': issuer,
      'audience': offlineAudience,
      'key_id': 'unit-key',
      'grant_id': grantId,
      'organization_id': org,
      'branch_id': branch,
      'device_id': deviceId,
      'actor_id': actorId,
      'membership_id': membership,
      'role': 'cashier',
      'business_name': 'Test business',
      'allowed_actions': ['sale.created'],
      'issued_at': issuedAt.toIso8601String(),
      'expires_at': issuedAt.add(const Duration(hours: 8)).toIso8601String(),
      'shift_id': shift,
      'currency': 'PHP',
      'tax_bps': 1250,
      'settings_revision': 10,
      'snapshot_digest': canonicalHash(snapshotValue),
      'max_events': 1000,
      'max_total_minor': 100000000,
    };
    final signature = await Ed25519().sign(
      utf8.encode('$offlineGrantDomain${strictCanonicalJson(claims)}'),
      keyPair: signingKey,
    );
    return {
      'grant': {
        'claims': claims,
        'signature': encodeOfflineBytes(signature.bytes),
      },
      'snapshot': snapshotValue,
      'server_time': issuedAt.toIso8601String(),
    };
  }

  Future<http.Response> _handle(http.Request request) async {
    final body = jsonDecode(request.body) as Map<String, dynamic>;
    actions.add(body);
    Object? data;
    switch (body['action']) {
      case 'enroll_challenge':
        data = {
          'challenge': {
            'challenge_id': requestId,
            'nonce': encodeOfflineBytes(List.filled(32, 7)),
            'organization_id': org,
            'branch_id': branch,
            'device_id': body['device_id'],
            'actor_id': actorId,
            'public_key': body['public_key'],
            'expires_at': issuedAt
                .add(const Duration(minutes: 5))
                .toIso8601String(),
          },
        };
      case 'enroll':
        data = <String, Object?>{};
      case 'prepare':
        if (unsignedPreparationExpired) {
          return http.Response(
            jsonEncode({'error': 'offline_preparation_expired'}),
            409,
            headers: {'content-type': 'application/json'},
            request: request,
          );
        }
        preparedWire ??= await grant(body['device_id'] as String);
        if (prepareDrops-- > 0) throw const SocketException('Dropped prepare');
        data = preparedWire;
      case 'ingest':
        if (ingestDenial != null) {
          return http.Response(
            jsonEncode({'message': 'Authorization denied'}),
            ingestDenial!,
            headers: {'content-type': 'application/json'},
            request: request,
          );
        }
        accepted ??= acceptance(body);
        if (ingestDrops-- > 0) {
          throw const SocketException('Dropped accepted response');
        }
        final copy = jsonDecode(jsonEncode(accepted)) as Map<String, dynamic>;
        if (corruptAck != null) {
          switch (corruptAck) {
            case 'tender':
              ((copy['receipt'] as Map)['payments'] as List)
                      .first['tendered_minor'] =
                  999;
            case 'receipt_id':
              (copy['receipt'] as Map)['id'] = requestId;
              copy['server_receipt_id'] = requestId;
            case 'stock':
              copy['stock_impacts'] = <Object?>[];
            case 'tax':
              (copy['receipt'] as Map)['tax_bps'] = 1251;
            case 'reverse_payments':
              (copy['receipt'] as Map)['payments'] =
                  ((copy['receipt'] as Map)['payments'] as List).reversed
                      .toList();
            default:
              copy[corruptAck!] = 'a0000000-0000-4000-8000-000000000099';
          }
        }
        data = copy;
      case 'pull':
        if (pullFails) throw const SocketException('Dropped pull');
        data =
            pullOverride ??
            {
              'cursor': 5,
              'has_more': false,
              'server_time': wall.toIso8601String(),
              'changes': [
                {
                  'kind': 'stock',
                  'id': productId,
                  'revision': 5,
                  'deleted': false,
                  'value': {
                    'product_id': productId,
                    'quantity': 1,
                    'revision': 51,
                  },
                },
              ],
            };
      case 'release':
        data = {
          'status': 'released',
          'grant_id': body['grant_id'],
          'final_sequence': body['final_sequence'],
          'organization_id': org,
          'branch_id': branch,
          'actor_id': actorId,
          'device_id': body['device_id'],
        };
      default:
        throw StateError('Unexpected HTTP action: ${body['action']}');
    }
    return http.Response(
      jsonEncode(data),
      200,
      headers: {'content-type': 'application/json'},
      request: request,
    );
  }

  Map<String, dynamic> acceptance(Map<String, dynamic> body) {
    final event = body['event'] as Map<String, dynamic>;
    final payload = event['payload'] as Map<String, dynamic>;
    final auth = body['authorization'] as Map<String, dynamic>;
    final evidence = auth['payment_evidence'] as Map<String, dynamic>;
    return {
      'status': 'accepted',
      'organization_id': org,
      'branch_id': branch,
      'actor_id': actorId,
      'device_id': body['device_id'],
      'grant_id': grantId,
      'sequence': auth['sequence'],
      'event_id': event['event_id'],
      'digest': body['digest'],
      'document_id': payload['id'],
      'server_receipt_id': payload['id'],
      'accepted_at': wall.toIso8601String(),
      'stock_impacts': [
        {'product_id': productId, 'revision': 51},
      ],
      'receipt': {
        'id': payload['id'],
        'organization_id': org,
        'branch_id': branch,
        'shift_id': shift,
        'actor_user_id': actorId,
        'request_id': event['event_id'],
        'receipt_number': 'MAIN-0001',
        'currency': 'PHP',
        'created_at': event['occurred_at'],
        'business_name': 'Test business',
        'branch_name': 'Main',
        'subtotal_minor': payload['subtotal_minor'],
        'discount_minor': payload['discount_minor'],
        'tax_bps': 1250,
        'tax_minor': payload['tax_minor'],
        'total_minor': payload['total_minor'],
        'items': (payload['items'] as List)
            .map(
              (item) => {
                ...item as Map,
                'product_name': item['name_snapshot'],
                'sku': item['sku_snapshot'],
                'line_subtotal_minor':
                    item['unit_price_minor'] * item['quantity'],
              },
            )
            .toList(),
        'payments': (payload['payments'] as List)
            .map(
              (payment) => {
                ...payment as Map,
                if (payment['method'] == 'cash')
                  'tendered_minor': evidence[payment['id']]['tendered_minor']
                else
                  'manual_confirmed': true,
              },
            )
            .toList(),
      },
    };
  }

  Future<OfflineCheckoutRequest> checkoutRequest({
    String id = requestId,
    int tender = 200,
  }) async {
    final product = (await workspace.searchProducts()).items.single;
    return OfflineCheckoutRequest(
      requestId: id,
      lines: [CartLine(product: product, quantity: 1)],
      payments: [
        CheckoutPayment(
          method: CheckoutPaymentMethod.cash,
          amountMinor: 113,
          tenderedMinor: tender,
        ),
      ],
    );
  }

  Future<void> ready() async {
    await workspace.prepareOnline(branch);
    await workspace.enterOffline(branch);
  }

  Future<void> close() => _closeFuture ??= _close();

  Future<void> _close() async {
    try {
      await client.dispose();
    } finally {
      await Future.wait([db.close(), journal.close()]);
    }
  }
}

Matcher permissionDenied() => isA<RepositoryFailure>().having(
  (error) => error.type,
  'type',
  RepositoryFailureType.permissionDenied,
);

void main() {
  late Harness h;
  setUp(() async {
    h = Harness();
    await h.initialize();
  });
  tearDown(() => h.close());

  test(
    'partial split evidence reopens with original UUID and finalizes only once',
    () async {
      await h.close();
      final directory = await Directory.systemTemp.createTemp(
        'nexapos-partial-reopen-',
      );
      h = Harness(directory: directory);
      final fileHarness = h;
      addTearDown(() async {
        await fileHarness.close();
        await directory.delete(recursive: true);
      });
      await h.initialize();
      await h.ready();
      final original = await h.checkoutRequest();
      const cash = CheckoutPayment(
        method: CheckoutPaymentMethod.cash,
        amountMinor: 50,
        tenderedMinor: 60,
      );
      await h.workspace.recordPaymentFragment(
        requestId: requestId,
        lines: original.lines,
        index: 0,
        payment: cash,
      );
      final firstBytes = (await h.journal.pending(
        type: 'offline_payment_fragment',
      )).single.payload;
      expect(
        (await h.workspace.pendingPaymentIntents()).single.partial,
        isTrue,
      );
      expect((await h.workspace.status()).unresolvedPaymentCount, 1);
      await h.restart();
      final restored = (await h.workspace.pendingPaymentIntents(
        branchId: branch,
      )).single;
      expect(restored.requestId, requestId);
      expect(restored.expectedTotalMinor, 113);
      expect(restored.payments.single.tenderedMinor, 60);
      expect(
        (await h.journal.pending(
          type: 'offline_payment_fragment',
        )).single.payload,
        firstBytes,
      );
      await h.workspace.enterOffline(branch);
      await h.workspace.recordPaymentFragment(
        requestId: requestId,
        lines: restored.lines,
        index: 1,
        payment: const CheckoutPayment(
          method: CheckoutPaymentMethod.card,
          amountMinor: 63,
          manualConfirmed: true,
          reference: 'terminal-original-63',
        ),
      );
      final complete = (await h.workspace.pendingPaymentIntents()).single;
      expect(complete.partial, isFalse);
      final receipt = await h.workspace.checkout(complete);
      expect(receipt.draft.eventId, requestId);
      expect(receipt.draft.payments.map((payment) => payment.amountMinor), [
        50,
        63,
      ]);
      expect(await h.workspace.pendingPaymentIntents(), isEmpty);
      expect(
        await h.journal.pending(type: 'offline_tender_finalization'),
        hasLength(1),
      );
      expect(
        await h.journal.pending(type: 'offline_payment_fragment'),
        hasLength(2),
      );
      await h.restart();
      expect(
        await h.workspace.pendingPaymentIntents(branchId: branch),
        isEmpty,
      );
      expect(await h.workspace.listReceipts(branchId: branch), hasLength(1));
    },
  );

  test(
    'same fragment replay after expiry retains bytes and rejects replacement evidence',
    () async {
      await h.ready();
      final original = await h.checkoutRequest();
      final payment = original.payments.single;
      await h.workspace.recordPaymentFragment(
        requestId: requestId,
        lines: original.lines,
        index: 0,
        payment: payment,
      );
      final bytes = strictCanonicalJson(
        (await h.journal.pending(
          type: 'offline_payment_fragment',
        )).single.payload,
      );
      h.wall = issuedAt.add(const Duration(hours: 9));
      await h.workspace.recordPaymentFragment(
        requestId: requestId,
        lines: original.lines,
        index: 0,
        payment: payment,
      );
      expect(
        strictCanonicalJson(
          (await h.journal.pending(
            type: 'offline_payment_fragment',
          )).single.payload,
        ),
        bytes,
      );
      await expectLater(
        h.workspace.recordPaymentFragment(
          requestId: requestId,
          lines: original.lines,
          index: 0,
          payment: const CheckoutPayment(
            method: CheckoutPaymentMethod.cash,
            amountMinor: 113,
            tenderedMinor: 999,
          ),
        ),
        throwsA(
          isA<RepositoryFailure>().having(
            (error) => error.type,
            'type',
            RepositoryFailureType.conflict,
          ),
        ),
      );
      expect(
        (await h.workspace.pendingPaymentIntents())
            .single
            .payments
            .single
            .tenderedMinor,
        200,
      );
    },
  );

  test(
    'expiry after dialog opening preserves unsigned paid fragment without a receipt',
    () async {
      await h.ready();
      final original = await h.checkoutRequest();
      h.wall = issuedAt.add(const Duration(hours: 9));
      await expectLater(
        h.workspace.recordPaymentFragment(
          requestId: requestId,
          lines: original.lines,
          index: 0,
          payment: original.payments.single,
        ),
        throwsA(isA<OfflineSecurityException>()),
      );
      final recovered = (await h.workspace.pendingPaymentIntents()).single;
      expect(recovered.requestId, requestId);
      expect(recovered.payments.single.tenderedMinor, 200);
      expect(await h.journal.pending(type: 'offline_tender_proof'), isEmpty);
      await expectLater(
        h.workspace.checkout(recovered),
        throwsA(anyOf(permissionDenied(), isA<OfflineSecurityException>())),
      );
      expect(await h.workspace.listReceipts(branchId: branch), isEmpty);
      final exported =
          jsonDecode(await h.workspace.exportReceipt(requestId)) as Map;
      expect(exported['status'], 'unresolved_payment_fragments');
      expect(
        (exported['fragments'] as List).single['payment']['tendered_minor'],
        200,
      );
      expect((await h.workspace.prepareOnline(branch)).grantId, grantId);
      expect(await h.workspace.pendingPaymentIntents(), hasLength(1));
      await expectLater(
        h.workspace.releaseGrant(branch),
        throwsA(permissionDenied()),
      );
    },
  );

  test(
    'lost fragment response retries its exact UUID and original timestamp',
    () async {
      await h.ready();
      final original = await h.checkoutRequest();
      final journal = LoseFragmentResponseJournal(h.journal);
      h.workspace = SupabaseOfflineWorkspace(
        client: h.client,
        actor: h.actor,
        database: (_) async => h.db,
        security: h.security,
        verifier: h.verifier,
        journal: journal,
        clock: () => h.wall,
        isRecoverySession: () => h.recovery,
        isExplicitlySignedOut: () => h.signedOut,
      );
      await h.workspace.enterOffline(branch);
      await expectLater(
        h.workspace.recordPaymentFragment(
          requestId: requestId,
          lines: original.lines,
          index: 0,
          payment: original.payments.single,
        ),
        throwsStateError,
      );
      final saved = (await h.journal.pending(
        type: 'offline_payment_fragment',
      )).single;
      h.wall = issuedAt.add(const Duration(minutes: 5));
      await h.workspace.recordPaymentFragment(
        requestId: requestId,
        lines: original.lines,
        index: 0,
        payment: original.payments.single,
      );
      final replay = (await h.journal.pending(
        type: 'offline_payment_fragment',
      )).single;
      expect(replay.requestId, saved.requestId);
      expect(replay.payload, saved.payload);
      expect(
        await h.journal.pending(type: 'offline_tender_proof'),
        hasLength(1),
      );
      final receipt = await h.workspace.checkout(
        (await h.workspace.pendingPaymentIntents()).single,
      );
      expect(receipt.draft.eventId, requestId);
    },
  );

  test(
    'completed fragment with missing proof retries without collecting payment again',
    () async {
      await h.ready();
      final original = await h.checkoutRequest();
      final journal = LoseFragmentResponseJournal(
        h.journal,
        type: 'offline_tender_proof',
        beforeWrite: true,
      );
      h.workspace = SupabaseOfflineWorkspace(
        client: h.client,
        actor: h.actor,
        database: (_) async => h.db,
        security: h.security,
        verifier: h.verifier,
        journal: journal,
        clock: () => h.wall,
      );
      await h.workspace.enterOffline(branch);
      await expectLater(
        h.workspace.recordPaymentFragment(
          requestId: requestId,
          lines: original.lines,
          index: 0,
          payment: original.payments.single,
        ),
        throwsStateError,
      );
      expect(await h.journal.pending(type: 'offline_tender_proof'), isEmpty);
      final saved = (await h.workspace.pendingPaymentIntents()).single;
      expect(saved.partial, isFalse);
      final receipt = await h.workspace.checkout(saved);
      expect(receipt.draft.eventId, requestId);
      expect(receipt.draft.payments.single.amountMinor, 113);
      expect(
        await h.journal.pending(type: 'offline_payment_fragment'),
        hasLength(1),
      );
      expect(
        await h.journal.pending(type: 'offline_tender_proof'),
        hasLength(1),
      );
      expect(await h.workspace.pendingPaymentIntents(), isEmpty);
    },
  );

  test(
    'committed sale with interrupted finalization seal recovers after restart and expiry',
    () async {
      await h.close();
      final directory = await Directory.systemTemp.createTemp(
        'nexapos-partial-seal-reopen-',
      );
      h = Harness(directory: directory);
      final fileHarness = h;
      addTearDown(() async {
        await fileHarness.close();
        await directory.delete(recursive: true);
      });
      await h.initialize();
      await h.ready();
      final original = await h.checkoutRequest();
      final journal = LoseFragmentResponseJournal(
        h.journal,
        type: 'offline_tender_finalization',
        beforeWrite: true,
      );
      h.workspace = SupabaseOfflineWorkspace(
        client: h.client,
        actor: h.actor,
        database: (_) async => h.db,
        security: h.security,
        verifier: h.verifier,
        journal: journal,
        clock: () => h.wall,
      );
      await h.workspace.enterOffline(branch);
      await h.workspace.recordPaymentFragment(
        requestId: requestId,
        lines: original.lines,
        index: 0,
        payment: original.payments.single,
      );
      await expectLater(
        h.workspace.checkout(
          (await h.workspace.pendingPaymentIntents()).single,
        ),
        throwsStateError,
      );
      expect(await h.workspace.listReceipts(branchId: branch), hasLength(1));
      expect(await h.workspace.pendingPaymentIntents(), hasLength(1));
      expect(
        await h.journal.pending(type: 'offline_tender_finalization'),
        isEmpty,
      );
      h.wall = issuedAt.add(const Duration(hours: 9));
      await h.restart();
      await h.workspace.status(branchId: branch);
      final saved = (await h.workspace.pendingPaymentIntents()).single;
      final receipt = await h.workspace.checkout(saved);
      expect(receipt.draft.eventId, requestId);
      expect(await h.workspace.listReceipts(branchId: branch), hasLength(1));
      expect(await h.workspace.pendingPaymentIntents(), isEmpty);
      expect(
        await h.journal.pending(type: 'offline_tender_finalization'),
        hasLength(1),
      );
    },
  );

  test(
    'stale cart price evidence is preserved but cannot gain a signed tender proof',
    () async {
      await h.ready();
      final original = await h.checkoutRequest();
      final product = original.lines.single.product;
      final stale = PosProduct(
        id: product.id,
        organizationId: product.organizationId,
        name: product.name,
        sku: product.sku,
        priceMinor: 900,
        currency: product.currency,
        unit: product.unit,
        revision: product.revision,
        availableQuantity: product.availableQuantity,
      );
      await expectLater(
        h.workspace.recordPaymentFragment(
          requestId: requestId,
          lines: [CartLine(product: stale, quantity: 1)],
          index: 0,
          payment: const CheckoutPayment(
            method: CheckoutPaymentMethod.cash,
            amountMinor: 50,
            tenderedMinor: 50,
          ),
        ),
        throwsA(
          isA<RepositoryFailure>().having(
            (error) => error.type,
            'type',
            RepositoryFailureType.conflict,
          ),
        ),
      );
      expect(
        (await h.workspace.pendingPaymentIntents()).single.partial,
        isTrue,
      );
      expect(await h.journal.pending(type: 'offline_tender_proof'), isEmpty);
      await expectLater(
        h.workspace.recordPaymentFragment(
          requestId: 'a0000000-0000-4000-8000-000000000099',
          lines: original.lines,
          index: 0,
          payment: original.payments.single,
        ),
        throwsA(permissionDenied()),
      );
    },
  );

  test(
    'device key removal retains partial evidence and never signs a new tender',
    () async {
      await h.ready();
      final original = await h.checkoutRequest();
      await h.workspace.recordPaymentFragment(
        requestId: requestId,
        lines: original.lines,
        index: 0,
        payment: const CheckoutPayment(
          method: CheckoutPaymentMethod.cash,
          amountMinor: 50,
          tenderedMinor: 50,
        ),
      );
      await h.workspace.suspend();
      final recovered = (await h.workspace.pendingPaymentIntents()).single;
      expect(recovered.partial, isTrue);
      expect(
        await h.workspace.exportReceipt(requestId),
        contains('unresolved_payment_fragments'),
      );
      await expectLater(
        h.workspace.recordPaymentFragment(
          requestId: requestId,
          lines: original.lines,
          index: 1,
          payment: const CheckoutPayment(
            method: CheckoutPaymentMethod.cash,
            amountMinor: 63,
            tenderedMinor: 63,
          ),
        ),
        throwsA(permissionDenied()),
      );
      expect(
        await h.journal.pending(type: 'offline_tender_proof'),
        hasLength(1),
      );
      expect(await h.workspace.listReceipts(branchId: branch), isEmpty);
    },
  );

  test(
    'explicit entry creates exact signed provisional receipt and local stock effect',
    () async {
      await h.ready();
      final receipt = await h.workspace.checkout(await h.checkoutRequest());
      expect(receipt.draft.totalMinor, 113);
      expect(
        receipt.draft.createdAt.toIso8601String(),
        '2026-10-10T12:00:00.123456Z',
      );
      expect(receipt.status, OutboxStatus.pending);
      expect(receipt.serverReceiptId, isNull);
      expect(
        (await h.workspace.searchProducts()).items.single.availableQuantity,
        1,
      );
      expect(await h.journal.pending(), isEmpty);
      final exported =
          jsonDecode(await h.workspace.exportReceipt(requestId))
              as Map<String, dynamic>;
      final enrollment = h.actions.first;
      expect(
        await Ed25519().verify(
          utf8.encode(
            '$offlineEventDomain${strictCanonicalJson({'event_digest': exported['digest'], ...exported['authorization'] as Map<String, dynamic>})}',
          ),
          signature: Signature(
            decodeOfflineBytes(exported['signature'], length: 64),
            publicKey: SimplePublicKey(
              decodeOfflineBytes(enrollment['public_key'], length: 32),
              type: KeyPairType.ed25519,
            ),
          ),
        ),
        isTrue,
      );
    },
  );

  test(
    'expiry after physical tender retains intent before refusing a new sale',
    () async {
      await h.ready();
      final intent = await h.checkoutRequest();
      h.wall = issuedAt.add(const Duration(hours: 8));
      await expectLater(
        h.workspace.checkout(intent),
        throwsA(isA<OfflineSecurityException>()),
      );
      expect(
        await h.db.listSales(
          DatabaseScope(organizationId: org, branchId: branch),
        ),
        isEmpty,
      );
      final saved = (await h.workspace.pendingPaymentIntents()).single;
      expect(saved.requestId, requestId);
      expect(saved.payments.single.tenderedMinor, 200);
      expect(
        jsonDecode(await h.workspace.exportReceipt(requestId))['status'],
        'unresolved_payment_intent',
      );
      expect((await h.workspace.status()).unresolvedPaymentCount, 1);
    },
  );

  test(
    'committed original request replays after expiry while changed tender conflicts',
    () async {
      await h.ready();
      final intent = await h.checkoutRequest();
      final original = await h.workspace.checkout(intent);
      h.wall = issuedAt.add(const Duration(hours: 9));
      expect((await h.workspace.checkout(intent)).draft.id, original.draft.id);
      await expectLater(
        h.workspace.checkout(await h.checkoutRequest(tender: 300)),
        throwsA(isA<OfflineStorageConflict>()),
      );
      expect((await h.workspace.listReceipts()).length, 1);
    },
  );

  test(
    'unknown online checkout blocks preparation and explicit offline entry',
    () async {
      await h.ready();
      await h.journal.prepare(
        requestId: 'a0000000-0000-4000-8000-000000000099',
        type: 'checkout_sale',
        branchId: branch,
        payload: {'original': 'online'},
      );
      await h.workspace.leaveOffline();
      await expectLater(
        h.workspace.enterOffline(branch),
        throwsA(permissionDenied()),
      );
    },
  );

  test(
    'recovery and account changes block cached products and checkout',
    () async {
      await h.ready();
      final intent = await h.checkoutRequest();
      h.recovery = true;
      await expectLater(
        h.workspace.checkout(intent),
        throwsA(permissionDenied()),
      );
      expect(await h.journal.pending(), isEmpty);
      h.recovery = false;
      await h.signIn(id: 'a0000000-0000-4000-8000-000000000099');
      await expectLater(
        h.workspace.searchProducts(),
        throwsA(permissionDenied()),
      );
    },
  );

  test(
    'acknowledgment alone never restores stock before its impact is pulled',
    () async {
      await h.ready();
      await h.workspace.checkout(await h.checkoutRequest());
      h.pullFails = true;
      expect((await h.workspace.synchronize(branch)).accepted, 1);
      expect(
        (await h.workspace.searchProducts()).items.single.availableQuantity,
        1,
      );
      expect(
        (await h.workspace.listReceipts()).single.status,
        OutboxStatus.synced,
      );
      h.pullFails = false;
      await h.workspace.synchronize(branch);
      expect(
        (await h.workspace.searchProducts()).items.single.availableQuantity,
        1,
      );
    },
  );

  test(
    'earlier stock revision in a later feed entry cannot absorb a newer impact',
    () async {
      await h.ready();
      await h.workspace.checkout(await h.checkoutRequest());
      h.pullOverride = {
        'cursor': 100,
        'has_more': false,
        'server_time': h.wall.toIso8601String(),
        'changes': [
          {
            'kind': 'stock',
            'id': productId,
            'revision': 100,
            'deleted': false,
            'value': {'product_id': productId, 'quantity': 2, 'revision': 50},
          },
        ],
      };
      await h.workspace.synchronize(branch);
      expect(
        (await h.workspace.searchProducts()).items.single.availableQuantity,
        1,
      );
    },
  );

  test(
    'duplicate product feed observations coalesce only after ordered validation',
    () async {
      await h.ready();
      await h.workspace.checkout(await h.checkoutRequest());
      h.pullOverride = {
        'cursor': 6,
        'has_more': false,
        'server_time': h.wall.toIso8601String(),
        'changes': [
          {
            'kind': 'stock',
            'id': productId,
            'revision': 5,
            'deleted': false,
            'value': {'product_id': productId, 'quantity': 2, 'revision': 50},
          },
          {
            'kind': 'stock',
            'id': productId,
            'revision': 6,
            'deleted': false,
            'value': {'product_id': productId, 'quantity': 1, 'revision': 51},
          },
        ],
      };
      final summary = await h.workspace.synchronize(branch);
      expect(summary.pulled, 2);
      expect(summary.stoppedReason, isNull);
      expect(
        (await h.workspace.searchProducts()).items.single.availableQuantity,
        1,
      );
    },
  );

  for (final corrupt in [
    'actor_id',
    'device_id',
    'event_id',
    'grant_id',
    'digest',
    'document_id',
    'receipt_id',
    'tender',
    'stock',
    'tax',
  ]) {
    test(
      'false acknowledgment $corrupt preserves failed paid event and stock',
      () async {
        await h.ready();
        await h.workspace.checkout(await h.checkoutRequest());
        h.corruptAck = corrupt;
        final result = await h.workspace.synchronize(branch);
        expect(result.accepted, 0);
        expect(result.failed, 1);
        final receipt = (await h.workspace.listReceipts()).single;
        expect(receipt.status, OutboxStatus.failed);
        expect(receipt.serverReceiptId, isNull);
        expect(
          (await h.workspace.searchProducts()).items.single.availableQuantity,
          1,
        );
      },
    );
  }

  test(
    'pending events block release; exact accepted grant release blocks future captures',
    () async {
      await h.ready();
      await h.workspace.checkout(await h.checkoutRequest());
      await expectLater(
        h.workspace.releaseGrant(branch),
        throwsA(permissionDenied()),
      );
      await h.workspace.synchronize(branch);
      expect((await h.workspace.releaseGrant(branch)).released, isTrue);
      await expectLater(
        h.workspace.enterOffline(branch),
        throwsA(permissionDenied()),
      );
    },
  );

  test(
    'manual split tender keeps evidence by immutable payment ID when server rows reorder',
    () async {
      await h.ready();
      final original = await h.checkoutRequest();
      final intent = OfflineCheckoutRequest(
        requestId: requestId,
        lines: original.lines,
        payments: const [
          CheckoutPayment(
            method: CheckoutPaymentMethod.cash,
            amountMinor: 60,
            tenderedMinor: 100,
          ),
          CheckoutPayment(
            method: CheckoutPaymentMethod.card,
            amountMinor: 53,
            reference: 'MANUAL-REFERENCE',
            manualConfirmed: true,
          ),
        ],
      );
      await h.workspace.checkout(intent);
      h.corruptAck = 'reverse_payments';
      expect((await h.workspace.synchronize(branch)).accepted, 1);
      final receipt = (await h.workspace.listReceipts()).single;
      expect(receipt.draft.payments.map((payment) => payment.method), [
        'cash',
        'card',
      ]);
      expect(receipt.draft.totalMinor, 113);
    },
  );

  test(
    'cold resume derives scoped actor only from verified complete grant and secure key',
    () async {
      await h.ready();
      final descriptors = await SupabaseOfflineWorkspace.resumeDescriptors(
        identity: const AuthIdentity(
          userId: actorId,
          email: 'actor@example.test',
          emailVerified: true,
        ),
        security: h.security,
        verifier: h.verifier,
        database: (_) async => h.db,
      );
      final descriptor = descriptors.single;
      expect(descriptor.actor.membershipId, membership);
      expect(descriptor.actor.branchIds, {branch});
      expect(descriptor.actor.allBranches, isFalse);
      h.wall = issuedAt.add(const Duration(hours: 9));
      expect(
        await SupabaseOfflineWorkspace.resumeDescriptors(
          identity: const AuthIdentity(
            userId: actorId,
            email: 'actor@example.test',
            emailVerified: true,
          ),
          security: h.security,
          verifier: h.verifier,
          database: (_) async => h.db,
        ),
        hasLength(1),
      );
      h.wall = issuedAt;
      expect(
        await SupabaseOfflineWorkspace.resumeDescriptors(
          identity: const AuthIdentity(
            userId: actorId,
            email: 'actor@example.test',
            emailVerified: true,
          ),
          security: h.security,
          verifier: h.verifier,
          database: (_) async => h.db,
        ),
        isEmpty,
      );
    },
  );

  for (final status in [401, 403]) {
    test(
      'definitive server $status locks new capture durably while preserving history',
      () async {
        await h.ready();
        await h.workspace.checkout(await h.checkoutRequest());
        h.ingestDenial = status;
        expect((await h.workspace.synchronize(branch)).accepted, 0);
        expect((await h.workspace.listReceipts()).single.draft.totalMinor, 113);
        expect(
          jsonDecode(await h.workspace.exportReceipt(requestId))['digest'],
          isNotNull,
        );
        await expectLater(
          h.workspace.enterOffline(branch),
          throwsA(permissionDenied()),
        );
        final device = await h.security.restore(
          organizationId: org,
          actorId: actorId,
        );
        expect(device, isNull);
        final resumed = SupabaseOfflineWorkspace(
          client: h.client,
          actor: h.actor,
          database: (_) async => h.db,
          security: OfflineDeviceSecurity(
            store: h.secrets,
            clock: () => h.wall,
          ),
          verifier: h.verifier,
          journal: h.journal,
          isExplicitlySignedOut: () => false,
        );
        expect(
          (await resumed.listReceipts(branchId: branch)).single.status,
          OutboxStatus.failed,
        );
        h.ingestDenial = null;
        expect(
          await resumed.retryFailed(branchId: branch, eventId: requestId),
          isTrue,
        );
        expect((await resumed.synchronize(branch)).accepted, 1);
        await expectLater(
          resumed.releaseGrant(branch),
          throwsA(
            isA<RepositoryFailure>().having(
              (error) => error.message,
              'removed key',
              contains('This device signing key was removed'),
            ),
          ),
        );
        await expectLater(
          resumed.enterOffline(branch),
          throwsA(isA<OfflineSecurityException>()),
        );
        expect(
          await SupabaseOfflineWorkspace.resumeDescriptors(
            identity: const AuthIdentity(
              userId: actorId,
              email: 'actor@example.test',
              emailVerified: true,
            ),
            security: h.security,
            verifier: h.verifier,
            database: (_) async => h.db,
          ),
          isEmpty,
        );
      },
    );
  }

  test(
    'lost prepare response reuses same durable request and device after physical restart',
    () async {
      await h.close();
      final directory = await Directory.systemTemp.createTemp(
        'nexapos-offline-prepare-',
      );
      h = Harness(directory: directory);
      final fileHarness = h;
      addTearDown(() async {
        await fileHarness.close();
        await directory.delete(recursive: true);
      });
      await h.initialize();
      h.prepareDrops = 1;
      await expectLater(
        h.workspace.prepareOnline(branch),
        throwsA(isA<RepositoryFailure>()),
      );
      final original = (await h.journal.pending(
        type: 'offline_prepare',
      )).single;
      expect(original.attemptCount, 1);
      await h.restart();
      await h.workspace.prepareOnline(branch);
      final prepareBodies = h.actions
          .where((body) => body['action'] == 'prepare')
          .toList();
      expect(prepareBodies, hasLength(2));
      expect(prepareBodies.last['request_id'], original.requestId);
      expect(prepareBodies.last['device_id'], prepareBodies.first['device_id']);
      expect(await h.journal.pending(type: 'offline_prepare'), isEmpty);
      expect((await h.workspace.enterOffline(branch)).active, isTrue);
    },
  );

  test(
    'lost accepted response replays exact signed paid event after physical restart',
    () async {
      await h.close();
      final directory = await Directory.systemTemp.createTemp(
        'nexapos-offline-ingest-',
      );
      h = Harness(directory: directory);
      final fileHarness = h;
      addTearDown(() async {
        await fileHarness.close();
        await directory.delete(recursive: true);
      });
      await h.initialize();
      await h.ready();
      await h.workspace.checkout(await h.checkoutRequest());
      h.ingestDrops = 1;
      expect((await h.workspace.synchronize(branch)).accepted, 0);
      final original = h.actions.lastWhere(
        (body) => body['action'] == 'ingest',
      );
      expect(
        (await h.workspace.listReceipts()).single.status,
        OutboxStatus.pending,
      );
      await h.restart();
      h.wall = issuedAt.add(const Duration(minutes: 5));
      expect((await h.workspace.synchronize(branch)).accepted, 1);
      final repeated = h.actions.lastWhere(
        (body) => body['action'] == 'ingest',
      );
      expect(strictCanonicalJson(repeated), strictCanonicalJson(original));
      expect((await h.workspace.listReceipts(branchId: branch)), hasLength(1));
    },
  );

  test(
    'expired tender intent survives physical restart without fabricating a sale',
    () async {
      await h.close();
      final directory = await Directory.systemTemp.createTemp(
        'nexapos-offline-tender-',
      );
      h = Harness(directory: directory);
      final fileHarness = h;
      addTearDown(() async {
        await fileHarness.close();
        await directory.delete(recursive: true);
      });
      await h.initialize();
      await h.ready();
      final intent = await h.checkoutRequest();
      h.wall = issuedAt.add(const Duration(hours: 8));
      await expectLater(
        h.workspace.checkout(intent),
        throwsA(isA<OfflineSecurityException>()),
      );
      await h.restart();
      final restored = (await h.workspace.pendingPaymentIntents(
        branchId: branch,
      )).single;
      expect(restored.requestId, requestId);
      expect(restored.payments.single.amountMinor, 113);
      expect(await h.workspace.listReceipts(branchId: branch), isEmpty);
    },
  );

  test(
    'suspension during awaited journal lookup cannot reenable device keys or issue enrollment',
    () async {
      final journal = BlockingJournal(h.journal);
      final workspace = SupabaseOfflineWorkspace(
        client: h.client,
        actor: h.actor,
        database: (_) async => h.db,
        security: h.security,
        verifier: h.verifier,
        journal: journal,
        isExplicitlySignedOut: () => false,
      );
      final preparing = workspace.prepareOnline(branch);
      final expectation = expectLater(preparing, throwsA(permissionDenied()));
      await journal.entered.future;
      await workspace.suspend();
      journal.release.complete();
      await expectation;
      expect(h.actions, isEmpty);
      expect(
        await h.security.restore(organizationId: org, actorId: actorId),
        isNull,
      );
      expect(h.secrets.values['nexapos.offline.v1.locked'], 'true');
    },
  );

  test(
    'only precise unsigned expiry resolves unknown prepare and permits a new request',
    () async {
      h.prepareDrops = 1;
      await expectLater(
        h.workspace.prepareOnline(branch),
        throwsA(isA<RepositoryFailure>()),
      );
      final original = (await h.journal.pending(
        type: 'offline_prepare',
      )).single.requestId;
      h.unsignedPreparationExpired = true;
      await expectLater(
        h.workspace.prepareOnline(branch),
        throwsA(isA<RepositoryFailure>()),
      );
      expect(await h.journal.pending(type: 'offline_prepare'), isEmpty);
      h.unsignedPreparationExpired = false;
      await h.workspace.prepareOnline(branch);
      expect(
        h.actions.lastWhere(
          (body) => body['action'] == 'prepare',
        )['request_id'],
        isNot(original),
      );
    },
  );

  test(
    'changed membership role preserves original history and signed upload but blocks capture',
    () async {
      await h.ready();
      await h.workspace.checkout(await h.checkoutRequest());
      final originalExport = await h.workspace.exportReceipt(requestId);
      final changed = SupabaseOfflineWorkspace(
        client: h.client,
        actor: AuthenticatedUser(
          userId: actorId,
          email: h.actor.email,
          organizationId: org,
          membershipId: membership,
          role: AppRole.manager,
          branchIds: {branch},
          allBranches: false,
          businessName: 'Current name',
        ),
        database: (_) async => h.db,
        security: h.security,
        verifier: h.verifier,
        journal: h.journal,
        clock: () => h.wall,
      );
      await changed.status(branchId: branch);
      expect(
        (await changed.listReceipts()).single.businessName,
        'Test business',
      );
      expect(await changed.exportReceipt(requestId), originalExport);
      await expectLater(
        changed.enterOffline(branch),
        throwsA(permissionDenied()),
      );
      expect((await changed.synchronize(branch)).accepted, 1);
    },
  );
}
