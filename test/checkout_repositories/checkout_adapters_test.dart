import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:nexapos/core/auth/auth_models.dart';
import 'package:nexapos/core/operations/native_operation_journal.dart';
import 'package:nexapos/core/operations/operation_journal.dart';
import 'package:nexapos/core/security/app_role.dart';
import 'package:nexapos/features/catalog/domain/repository_support.dart';
import 'package:nexapos/features/checkout/data/supabase_checkout_repository.dart';
import 'package:nexapos/features/checkout/domain/checkout_models.dart';
import 'package:nexapos/features/inventory/data/supabase_inventory_repository.dart';
import 'package:nexapos/features/inventory/domain/inventory_models.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

const org = '11111111-1111-1111-1111-111111111111';
const actorId = '22222222-2222-2222-2222-222222222222';
const branch = '33333333-3333-3333-3333-333333333333';
const shiftId = '44444444-4444-4444-4444-444444444444';
const productId = '55555555-5555-5555-5555-555555555555';
const requestId = '66666666-6666-6666-6666-666666666666';
const saleId = '77777777-7777-7777-7777-777777777777';
const lineId = '88888888-8888-8888-8888-888888888888';
const paymentId = '99999999-9999-9999-9999-999999999999';

AuthenticatedUser actor() => AuthenticatedUser(
  userId: actorId,
  email: 'test@example.test',
  organizationId: org,
  membershipId: productId,
  role: AppRole.owner,
  branchIds: {branch},
  allBranches: true,
  businessName: 'Test',
);

Map<String, dynamic> receipt({String request = requestId}) => {
  'id': saleId,
  'organization_id': org,
  'branch_id': branch,
  'shift_id': shiftId,
  'actor_user_id': actorId,
  'request_id': request,
  'receipt_number': 'TEST-0001',
  'currency': 'PHP',
  'created_at': '2026-10-09T00:00:00Z',
  'business_name': 'Test',
  'branch_name': 'Main',
  'subtotal_minor': 100,
  'discount_minor': 0,
  'tax_bps': 0,
  'tax_minor': 0,
  'total_minor': 100,
  'items': [
    {
      'id': lineId,
      'product_id': productId,
      'product_name': 'Product',
      'sku': 'SKU',
      'quantity': 1,
      'unit_price_minor': 100,
      'line_subtotal_minor': 100,
      'discount_minor': 0,
      'tax_minor': 0,
      'line_total_minor': 100,
      'reversed_quantity': 0,
    },
  ],
  'payments': [
    {
      'id': paymentId,
      'method': 'cash',
      'amount_minor': 100,
      'tendered_minor': 200,
      'reference': null,
      'reversed_minor': 0,
    },
  ],
};
Map<String, dynamic> product() => {
  'id': productId,
  'organization_id': org,
  'name': 'Product',
  'sku': 'SKU',
  'price_minor': 100,
  'currency': 'PHP',
  'unit': 'each',
  'revision': 1,
  'available_quantity': 10,
  'cost_minor': null,
  'barcode': '012345',
  'active': true,
};
Map<String, dynamic> stock() => {
  'request_id': requestId,
  'id': saleId,
  'organization_id': org,
  'branch_id': branch,
  'actor_user_id': actorId,
  'kind': 'receive',
  'created_at': '2026-10-09T00:00:00Z',
  'reason': 'Delivery',
  'reference': null,
  'supplier_id': null,
  'movements': [
    {
      'id': lineId,
      'product_id': productId,
      'quantity_delta': 2,
      'balance_after': 2,
      'created_at': '2026-10-09T00:00:00Z',
    },
  ],
};
Map<String, dynamic> shift({bool closed = false, String user = actorId}) => {
  'request_id': requestId,
  'closing_request_id': closed ? requestId : null,
  'id': shiftId,
  'organization_id': org,
  'branch_id': branch,
  'actor_user_id': user,
  'currency': 'PHP',
  'opening_cash_minor': 0,
  'expected_cash_minor': -100,
  'opened_at': '2026-10-09T00:00:00Z',
  'closure': closed
      ? {
          'id': saleId,
          'closed_by': actorId,
          'closed_at': '2026-10-09T01:00:00Z',
          'counted_cash_minor': 0,
          'expected_cash_minor': -100,
          'difference_minor': 100,
          'reason': 'Close register',
        }
      : null,
};

CheckoutRequest checkout() => CheckoutRequest(
  branchId: branch,
  shiftId: shiftId,
  requestId: requestId,
  expectedSettingsRevision: 4,
  items: [
    const CheckoutItem(productId: productId, quantity: 1, expectedRevision: 1),
  ],
  payments: [
    const CheckoutPayment(
      method: CheckoutPaymentMethod.cash,
      amountMinor: 100,
      tenderedMinor: 200,
    ),
  ],
);

class Harness {
  Harness() {
    journal = NativeOperationJournal(
      executor: NativeDatabase.memory(),
      organizationId: org,
      actorId: actorId,
    );
    client = SupabaseClient(
      'https://project.example.test',
      'public-test-key',
      authOptions: const AuthClientOptions(autoRefreshToken: false),
      httpClient: MockClient((request) async {
        requests.add(request);
        if (handler != null) return handler!(request);
        return response(data, status, request);
      }),
    );
  }
  late final SupabaseClient client;
  late final NativeOperationJournal journal;
  final requests = <http.Request>[];
  Object? data = receipt();
  int status = 200;
  Future<http.Response> Function(http.Request)? handler;
  SupabaseCheckoutRepository repository({bool recovery = false}) =>
      SupabaseCheckoutRepository(
        client: client,
        actor: actor(),
        journal: journal,
        isRecoverySession: () => recovery,
      );
  SupabaseInventoryRepository inventory() => SupabaseInventoryRepository(
    client: client,
    actor: actor(),
    journal: journal,
  );
  Future<void> signIn({String user = actorId}) async {
    String encode(Object data) =>
        base64Url.encode(utf8.encode(jsonEncode(data))).replaceAll('=', '');
    await client.auth.recoverSession(
      jsonEncode({
        'access_token':
            '${encode({'alg': 'HS256'})}.${encode({'sub': user, 'exp': 4102444800})}.test',
        'refresh_token': 'test-refresh',
        'token_type': 'bearer',
        'user': {
          'id': user,
          'aud': 'authenticated',
          'email': 'test@example.test',
          'email_confirmed_at': '2026-10-09T00:00:00Z',
          'created_at': '2026-10-09T00:00:00Z',
          'app_metadata': {},
          'user_metadata': {},
        },
      }),
    );
  }

  static http.Response response(
    Object? data,
    int status,
    http.Request request,
  ) => http.Response(
    jsonEncode(data),
    status,
    request: request,
    headers: {'content-type': 'application/json'},
  );
  Map<String, dynamic> get lastBody =>
      jsonDecode(requests.last.body) as Map<String, dynamic>;
  Future<void> close() async {
    await client.dispose();
    await journal.close();
  }
}

Matcher failure(RepositoryFailureType type) => isA<RepositoryFailure>()
    .having((e) => e.type, 'type', type)
    .having((e) => e.message, 'sanitized message', isNot(contains('PRIVATE')));

void main() {
  late Harness h;
  setUp(() => h = Harness());
  tearDown(() => h.close());
  test(
    'absent identity and recovery cannot create durable financial intent',
    () async {
      await expectLater(
        h.repository().checkout(checkout()),
        throwsA(failure(RepositoryFailureType.unauthenticated)),
      );
      await h.signIn();
      await expectLater(
        h.repository(recovery: true).checkout(checkout()),
        throwsA(failure(RepositoryFailureType.unauthenticated)),
      );
      expect(h.requests, isEmpty);
      expect(await h.journal.pending(), isEmpty);
    },
  );
  test(
    'barcode lookup uses exact scoped RPC and returns current available quantity',
    () async {
      await h.signIn();
      h.data = product();
      final actual = await h.repository().lookupProductByBarcode(
        branchId: branch,
        barcode: '012345',
      );
      expect(actual!.availableQuantity, 10);
      expect(actual.costMinor, isNull);
      expect(
        h.requests.single.url.path,
        '/rest/v1/rpc/lookup_pos_product_by_barcode',
      );
      expect(h.lastBody, {
        'p_organization_id': org,
        'p_branch_id': branch,
        'p_barcode': '012345',
      });
    },
  );
  test(
    'lookup cannot silently accept a substring barcode or another branch',
    () async {
      await h.signIn();
      h.data = product();
      await expectLater(
        h.repository().lookupProductByBarcode(branchId: branch, barcode: '123'),
        throwsA(failure(RepositoryFailureType.unavailable)),
      );
      await expectLater(
        h.repository().searchProducts(branchId: productId),
        throwsA(failure(RepositoryFailureType.permissionDenied)),
      );
      expect(h.requests.length, 1);
    },
  );
  test(
    'successful checkout returns actual immutable receipt and confirms journal',
    () async {
      await h.signIn();
      final actual = await h.repository().checkout(checkout());
      expect(actual.id, saleId);
      expect(actual.requestId, requestId);
      expect(actual.items.single.name, 'Product');
      expect(actual.payments.single.changeMinor, 100);
      expect(await h.journal.pending(), isEmpty);
      expect(h.lastBody['p_payload'], checkout().validatedPayload());
      expect(h.lastBody['p_organization_id'], org);
    },
  );
  test(
    'network timeout retains exact checkout payload and UUID for restart restoration',
    () async {
      await h.signIn();
      h.handler = (_) => throw const SocketException('PRIVATE timeout');
      await expectLater(
        h.repository().checkout(checkout()),
        throwsA(failure(RepositoryFailureType.unavailable)),
      );
      final pending = await h.repository().pendingCheckout(branch);
      expect(pending!.requestId, requestId);
      expect(pending.validatedPayload(), checkout().validatedPayload());
      expect((await h.journal.pending()).single.attemptCount, 1);
      h.handler = null;
      h.data = receipt();
      await h.repository().checkout(pending);
      expect(h.requests.map((r) => jsonDecode(r.body)['p_request_id']), [
        requestId,
        requestId,
      ]);
      expect(await h.journal.pending(), isEmpty);
    },
  );
  test(
    'lost response followed by replay permission denial remains unresolved',
    () async {
      await h.signIn();
      h.handler = (_) => throw const SocketException('PRIVATE lost response');
      await expectLater(
        h.repository().checkout(checkout()),
        throwsA(failure(RepositoryFailureType.unavailable)),
      );
      h.handler = null;
      h.status = 403;
      h.data = {
        'code': '42501',
        'message': 'PRIVATE denied',
        'details': null,
        'hint': null,
      };
      await expectLater(
        h.repository().checkout(checkout()),
        throwsA(failure(RepositoryFailureType.unavailable)),
      );
      final pending = (await h.journal.pending()).single;
      expect(pending.status, LocalOperationStatus.pending);
      expect(pending.attemptCount, 2);
      expect(await h.repository().pendingCheckout(branch), isNotNull);
    },
  );
  test(
    'first definitive SQL rollback rejects intent and prevents same UUID mutation',
    () async {
      await h.signIn();
      h.status = 409;
      h.data = {
        'code': '40001',
        'message': 'PRIVATE revision conflict',
        'details': null,
        'hint': null,
      };
      await expectLater(
        h.repository().checkout(checkout()),
        throwsA(failure(RepositoryFailureType.conflict)),
      );
      expect(await h.repository().pendingCheckout(branch), isNull);
      h.status = 200;
      h.data = receipt();
      await expectLater(
        h.repository().checkout(checkout()),
        throwsA(failure(RepositoryFailureType.conflict)),
      );
      expect(h.requests.length, 1);
    },
  );
  test(
    'malformed 200 success never confirms a receipt or releases its intent',
    () async {
      await h.signIn();
      h.data = {'id': saleId, 'private': 'PRIVATE'};
      await expectLater(
        h.repository().checkout(checkout()),
        throwsA(failure(RepositoryFailureType.unavailable)),
      );
      expect(
        (await h.journal.pending()).single.status,
        LocalOperationStatus.pending,
      );
    },
  );
  test('a different request receipt cannot confirm a checkout', () async {
    await h.signIn();
    h.data = receipt(request: productId);
    await expectLater(
      h.repository().checkout(checkout()),
      throwsA(failure(RepositoryFailureType.unavailable)),
    );
    expect(await h.journal.pending(), hasLength(1));
  });
  test(
    'inconsistent financial totals cannot confirm a successful HTTP response',
    () async {
      await h.signIn();
      h.data = {...receipt(), 'total_minor': 101};
      await expectLater(
        h.repository().checkout(checkout()),
        throwsA(failure(RepositoryFailureType.unavailable)),
      );
      expect(await h.journal.pending(), hasLength(1));
    },
  );
  test(
    'digital receipt without operator confirmation remains unconfirmed',
    () async {
      await h.signIn();
      h.data = {
        ...receipt(),
        'payments': [
          {
            'id': paymentId,
            'method': 'gcash',
            'amount_minor': 100,
            'reference': 'ref-123',
            'manual_confirmed': false,
          },
        ],
      };
      await expectLater(
        h.repository().checkout(checkout()),
        throwsA(failure(RepositoryFailureType.unavailable)),
      );
      expect(await h.journal.pending(), hasLength(1));
    },
  );
  test(
    'changed session while response is in flight cannot expose or confirm it',
    () async {
      await h.signIn();
      final response = Completer<http.Response>();
      final sent = Completer<void>();
      h.handler = (request) {
        sent.complete();
        return response.future;
      };
      final result = h.repository().checkout(checkout());
      await sent.future;
      await h.signIn(user: productId);
      response.complete(Harness.response(receipt(), 200, h.requests.single));
      await expectLater(
        result,
        throwsA(failure(RepositoryFailureType.unauthenticated)),
      );
      expect(await h.journal.pending(), hasLength(1));
    },
  );
  test(
    'get by original request reconciles a lost response without another checkout',
    () async {
      await h.signIn();
      h.handler = (_) => throw const SocketException('PRIVATE lost');
      await expectLater(
        h.repository().checkout(checkout()),
        throwsA(failure(RepositoryFailureType.unavailable)),
      );
      h.handler = null;
      h.data = receipt();
      final actual = await h.repository().findSaleByRequest(
        branchId: branch,
        requestId: requestId,
      );
      expect(actual!.receiptNumber, 'TEST-0001');
      expect(await h.journal.pending(), isEmpty);
      expect(h.requests.last.url.path, '/rest/v1/rpc/get_sale_by_request');
    },
  );
  test('pending operation from another actor cannot reach the RPC', () async {
    await h.signIn();
    final op = PendingOperation(
      requestId: requestId,
      organizationId: org,
      branchId: branch,
      actorId: productId,
      type: 'checkout_sale',
      payload: {'p_organization_id': org, 'p_request_id': requestId},
      createdAt: DateTime.utc(2026),
      status: LocalOperationStatus.pending,
    );
    await expectLater(
      h.repository().retryPending(op),
      throwsA(failure(RepositoryFailureType.permissionDenied)),
    );
    expect(h.requests, isEmpty);
  });
  test(
    'receiving submits real stock evidence without rewriting catalog prices',
    () async {
      await h.signIn();
      h.data = stock();
      final result = await h.inventory().receiveStock(
        ReceiveStockRequest(
          branchId: branch,
          requestId: requestId,
          reason: 'Delivery',
          items: [
            const StockReceiptItem(
              productId: productId,
              quantity: 2,
              expectedRevision: 3,
              unitCostMinor: 42,
            ),
          ],
        ),
      );
      expect(result.movements.single.balanceAfter, 2);
      expect(h.lastBody['p_items'], [
        {
          'product_id': productId,
          'quantity': 2,
          'expected_revision': 3,
          'unit_cost_minor': 42,
        },
      ]);
      expect(h.requests.single.url.path, '/rest/v1/rpc/receive_stock');
      expect(await h.journal.pending(), isEmpty);
    },
  );
  test(
    'negative stock adjustment is frozen and loss can retry same server request',
    () async {
      await h.signIn();
      h.handler = (_) => throw const SocketException('PRIVATE timeout');
      final request = AdjustStockRequest(
        branchId: branch,
        productId: productId,
        deltaQuantity: -2,
        reason: 'Damaged item',
        requestId: requestId,
      );
      await expectLater(
        h.inventory().adjustStock(request),
        throwsA(failure(RepositoryFailureType.unavailable)),
      );
      final pending = (await h.inventory().pendingOperations(
        branchId: branch,
      )).single;
      expect(pending.payload['p_delta_quantity'], -2);
      h.handler = null;
      h.data = {
        ...stock(),
        'kind': 'adjust',
        'movements': [
          {
            'id': lineId,
            'product_id': productId,
            'quantity_delta': -2,
            'balance_after': 2,
            'created_at': '2026-10-09T00:00:00Z',
          },
        ],
      };
      final confirmed = await h.inventory().retryPending(pending);
      expect(confirmed.kind, 'adjust');
      expect(await h.journal.pending(), isEmpty);
    },
  );
  test('shift decoder preserves legitimate negative expected cash', () async {
    await h.signIn();
    h.data = shift();
    final current = await h.repository().currentShift(branch);
    expect(current!.expectedCashMinor, -100);
    expect(current.currency, 'PHP');
  });
  test(
    'privileged branch shift closure accepts server-confirmed closer and target',
    () async {
      await h.signIn();
      h.data = shift(closed: true, user: productId);
      final closed = await h.repository().closeShift(
        CloseShiftRequest(
          branchId: branch,
          shiftId: shiftId,
          requestId: requestId,
          countedCashMinor: 0,
          reason: 'Close register',
        ),
      );
      expect(closed.actorUserId, productId);
      expect(closed.closedBy, actorId);
      expect(closed.cashDifferenceMinor, 100);
    },
  );
  test(
    'open shift freezes expected currency to prevent money reinterpretation',
    () async {
      await h.signIn();
      h.data = shift();
      await h.repository().openShift(
        OpenShiftRequest(
          branchId: branch,
          requestId: requestId,
          openingCashMinor: 0,
          expectedCurrency: 'PHP',
        ),
      );
      expect(h.lastBody['p_expected_currency'], 'PHP');
    },
  );
}
