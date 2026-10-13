import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:nexapos/core/auth/auth_models.dart';
import 'package:nexapos/core/operations/native_operation_journal.dart';
import 'package:nexapos/core/security/app_role.dart';
import 'package:nexapos/features/catalog/domain/repository_support.dart';
import 'package:nexapos/features/purchases/data/purchase_decoders.dart';
import 'package:nexapos/features/purchases/data/supabase_purchase_repository.dart';
import 'package:nexapos/features/purchases/domain/purchase_models.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'purchase_fixtures.dart';

class _Harness {
  _Harness({NativeOperationJournal? journal, this.membership}) {
    this.journal =
        journal ??
        NativeOperationJournal(
          executor: NativeDatabase.memory(),
          organizationId: membership?.organizationId ?? purchaseOrg,
          actorId: membership?.userId ?? purchaseActor,
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
  Map<String, dynamic> order = purchaseOrderWire(changedCatalog: true);
  Map<String, dynamic> result = purchaseCreateResult();
  late Future<http.Response> Function(http.Request) handler = (request) async =>
      response(
        request.url.path.endsWith('/get_purchase_order') ? order : result,
      );
  static http.Response response(Object value, {int status = 200}) =>
      http.Response(
        jsonEncode(value),
        status,
        headers: {'content-type': 'application/json'},
      );
  SupabasePurchaseRepository repository({
    AppRole role = AppRole.owner,
    bool recovery = false,
  }) => SupabasePurchaseRepository(
    client: client,
    actor: membership ?? purchaseMembership(role: role),
    journal: journal,
    isRecoverySession: () => recovery,
  );
  Future<void> signIn({String? actor}) async {
    actor ??= membership?.userId ?? purchaseActor;
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

Matcher _failure(RepositoryFailureType type) => isA<RepositoryFailure>().having(
  (failure) => failure.type,
  'failure type',
  type,
);

void main() {
  late _Harness h;
  setUp(() => h = _Harness());
  tearDown(() => h.close());

  test(
    'signed-out recovery cashier and foreign branch cannot create intent',
    () async {
      await expectLater(
        h.repository().create(createPurchaseRequest()),
        throwsA(_failure(RepositoryFailureType.unauthenticated)),
      );
      await h.signIn();
      await expectLater(
        h.repository(recovery: true).create(createPurchaseRequest()),
        throwsA(_failure(RepositoryFailureType.unauthenticated)),
      );
      await expectLater(
        h.repository(role: AppRole.cashier).create(createPurchaseRequest()),
        throwsA(_failure(RepositoryFailureType.permissionDenied)),
      );
      final request = createPurchaseRequest();
      await expectLater(
        h.repository().create(
          CreatePurchaseRequest(
            branchId: otherPurchaseActor,
            supplierId: request.supplierId,
            expectedSupplierRevision: 3,
            expectedSettingsRevision: 4,
            currency: 'PHP',
            items: request.items,
            reason: request.reason,
          ),
        ),
        throwsA(_failure(RepositoryFailureType.permissionDenied)),
      );
      expect(h.requests, isEmpty);
      expect(await h.journal.pending(), isEmpty);
    },
  );
  test(
    'original create intent and dispatch attempt exist before RPC',
    () async {
      await h.signIn();
      h.handler = (request) async {
        final pending = (await h.journal.pending()).single;
        expect(pending.requestId, purchaseRequest);
        expect(pending.attemptCount, 1);
        expect(pending.payload['p_items'], [
          {
            'product_id': purchaseProduct,
            'expected_revision': 2,
            'quantity': 3,
            'unit_cost_minor': 101,
          },
        ]);
        return _Harness.response(purchaseCreateResult());
      };
      final result = await h.repository().create(createPurchaseRequest());
      expect(result.order?.summary.orderedTotalMinor, 303);
      expect(await h.journal.pending(), isEmpty);
    },
  );
  test(
    'inventory staff can record real order and cost without POS shift',
    () async {
      await h.signIn();
      final result = await h
          .repository(role: AppRole.inventoryStaff)
          .create(createPurchaseRequest());
      expect(result.kind, 'purchase.create');
      expect(h.requests.single.url.path, '/rest/v1/rpc/create_purchase_order');
    },
  );
  test(
    'validated active purchase context is scoped independent of POS',
    () async {
      await h.signIn();
      h.result = purchaseContextWire();
      final result = await h
          .repository(role: AppRole.inventoryStaff)
          .context(purchaseBranch);
      expect(result.currency, 'PHP');
      expect(h.requests.single.url.path, '/rest/v1/rpc/get_purchase_context');
    },
  );
  test(
    'receipt proves original cost after current product rename and currency change',
    () async {
      await h.signIn();
      h.result = purchaseReceiveResult();
      final result = await h.repository().receive(receivePurchaseRequest());
      expect(result.receipt?.summary.currency, 'PHP');
      expect(result.receipt?.items.single.unitCostMinor, 101);
      expect(result.receipt?.items.single.balanceAfter, -1);
      expect(h.requests.map((request) => request.url.path), [
        '/rest/v1/rpc/get_purchase_order',
        '/rest/v1/rpc/receive_purchase_order',
      ]);
      expect(await h.journal.pending(), isEmpty);
    },
  );

  final corruptions = <String, void Function(Map<String, dynamic>)>{
    'selfconsistent wrong receipt cost': (row) {
      row['receipt']['received_total_minor'] = 102;
      row['receipt']['items'][0]['unit_cost_minor'] = 102;
      row['receipt']['items'][0]['line_cost_minor'] = 102;
    },
    'foreign receipt actor': (row) =>
        row['receipt']['received_by'] = otherPurchaseActor,
    'foreign receipt scope': (row) =>
        row['receipt']['organization_id'] = otherPurchaseActor,
    'different original product': (row) =>
        row['receipt']['items'][0]['product_id'] = otherPurchaseActor,
    'different original product name': (row) =>
        row['receipt']['items'][0]['product_name'] = 'Invented product',
    'wrong response UUID': (row) => row['request_id'] = otherPurchaseActor,
    'wrong action kind': (row) => row['kind'] = 'purchase.create',
    'wrong accepted revision': (row) {
      row['order_revision'] = 3;
      row['receipt']['order_revision'] = 3;
    },
    'different requested quantity': (row) {
      row['receipt']['items'][0]['quantity'] = 2;
      row['receipt']['items'][0]['line_cost_minor'] = 202;
      row['receipt']['received_total_minor'] = 202;
    },
    'unsafe stock integer': (row) =>
        row['receipt']['items'][0]['stock_revision'] =
            purchaseMaximumInteger + 1,
    'floating receipt amount': (row) =>
        row['receipt']['received_total_minor'] = 101.0,
    'duplicate receipt movement': (row) {
      row['receipt']['items'].add(
        clonePurchaseWire(row['receipt']['items'][0] as Map<String, dynamic>),
      );
      row['receipt']['received_total_minor'] = 202;
    },
  };
  for (final entry in corruptions.entries) {
    test('${entry.key} remains unconfirmed in durable journal', () async {
      await h.signIn();
      h.result = clonePurchaseWire(purchaseReceiveResult());
      entry.value(h.result);
      await expectLater(
        h.repository().receive(receivePurchaseRequest()),
        throwsA(_failure(RepositoryFailureType.unavailable)),
      );
      expect((await h.journal.pending()).single.requestId, purchaseRequest);
    });
  }

  test(
    'lost response exact retry accepts original action after later receipt state',
    () async {
      await h.signIn();
      var lost = true;
      h.handler = (request) async {
        if (request.url.path.endsWith('/get_purchase_order')) {
          return _Harness.response(
            purchaseOrderWire(received: 1, changedCatalog: true),
          );
        }
        if (lost) throw const SocketException('test transport interrupted');
        return _Harness.response(purchaseReceiveResult());
      };
      await expectLater(
        h.repository().receive(receivePurchaseRequest()),
        throwsA(_failure(RepositoryFailureType.unavailable)),
      );
      final pending = (await h.repository().pendingMutations()).single;
      lost = false;
      final result = await h.repository().retryPending(pending);
      expect(result.receipt?.summary.orderRevision, 2);
      expect(await h.journal.pending(), isEmpty);
      final posts = h.requests
          .where(
            (request) => request.url.path.endsWith('/receive_purchase_order'),
          )
          .toList();
      expect(posts.length, 2);
      expect(jsonDecode(posts[0].body), jsonDecode(posts[1].body));
    },
  );
  test(
    'later SQL denial cannot reject earlier uncertain purchase receipt',
    () async {
      await h.signIn();
      var lost = true;
      h.handler = (request) async {
        if (request.url.path.endsWith('/get_purchase_order')) {
          return _Harness.response(h.order);
        }
        if (lost) throw const SocketException('test transport interrupted');
        return _Harness.response({
          'code': '42501',
          'message': 'PRIVATE denial detail',
        }, status: 403);
      };
      await expectLater(
        h.repository().receive(receivePurchaseRequest()),
        throwsA(_failure(RepositoryFailureType.unavailable)),
      );
      final pending = (await h.journal.pending()).single;
      lost = false;
      await expectLater(
        h.repository().retryPending(pending),
        throwsA(_failure(RepositoryFailureType.unavailable)),
      );
      expect((await h.journal.pending()).single.attemptCount, 2);
    },
  );
  test(
    'first definitive SQL rollback releases intent for corrected new request',
    () async {
      await h.signIn();
      h.handler = (request) async => _Harness.response({
        'code': '40001',
        'message': 'PRIVATE revision detail',
      }, status: 409);
      await expectLater(
        h.repository().create(createPurchaseRequest()),
        throwsA(_failure(RepositoryFailureType.conflict)),
      );
      expect(await h.journal.pending(), isEmpty);
    },
  );
  test(
    'cancel snapshots exactly unreceived quantities and keeps received stock',
    () async {
      await h.signIn();
      h.order = purchaseOrderWire(received: 1, changedCatalog: true);
      h.result = purchaseCancelResult();
      final result = await h.repository().cancelRemaining(
        cancelPurchaseRequest(),
      );
      expect(result.cancellation?.items.single.quantity, 2);
      expect(result.cancellation?.cancelledTotalMinor, 202);
      expect(await h.journal.pending(), isEmpty);
    },
  );
  test(
    'cancel replay after close uses immutable cancellation not current zero remainder',
    () async {
      await h.signIn();
      h.order = purchaseOrderWire(
        received: 1,
        cancelled: true,
        changedCatalog: true,
      );
      h.result = purchaseCancelResult();
      final result = await h.repository().cancelRemaining(
        cancelPurchaseRequest(),
      );
      expect(result.cancellation?.items.single.quantity, 2);
      expect(await h.journal.pending(), isEmpty);
    },
  );
  test('selfconsistent wrong canceled cost remains unresolved', () async {
    await h.signIn();
    h.order = purchaseOrderWire(received: 1);
    h.result = purchaseCancelResult();
    h.result['cancellation']['cancelled_total_minor'] = 204;
    h.result['cancellation']['items'][0]['unit_cost_minor'] = 102;
    h.result['cancellation']['items'][0]['line_cost_minor'] = 204;
    await expectLater(
      h.repository().cancelRemaining(cancelPurchaseRequest()),
      throwsA(_failure(RepositoryFailureType.unavailable)),
    );
    expect(await h.journal.pending(), hasLength(1));
  });
  test(
    'malformed create initial-state snapshot cannot confirm order',
    () async {
      await h.signIn();
      h.result = purchaseCreateResult();
      h.result['order'] = purchaseOrderWire(received: 1);
      await expectLater(
        h.repository().create(createPurchaseRequest()),
        throwsA(_failure(RepositoryFailureType.unavailable)),
      );
      expect(await h.journal.pending(), hasLength(1));
    },
  );
  test(
    'late success after actor switch stays pending and never exposes old order',
    () async {
      await h.signIn();
      final dispatched = Completer<void>();
      final response = Completer<http.Response>();
      h.handler = (_) async {
        dispatched.complete();
        return response.future;
      };
      final assertion = expectLater(
        h.repository().create(createPurchaseRequest()),
        throwsA(_failure(RepositoryFailureType.unauthenticated)),
      );
      await dispatched.future;
      await h.signIn(actor: otherPurchaseActor);
      response.complete(_Harness.response(purchaseCreateResult()));
      await assertion;
      expect(await h.journal.pending(), hasLength(1));
    },
  );
  test('foreign-scope pending object cannot be dispatched', () async {
    await h.signIn();
    await h.journal.prepare(
      requestId: purchaseRequest,
      type: 'create_purchase_order',
      branchId: purchaseBranch,
      payload: {
        'p_request_id': purchaseRequest,
        'p_organization_id': otherPurchaseActor,
        'p_branch_id': purchaseBranch,
      },
    );
    final operation = (await h.journal.pending()).single;
    await expectLater(
      h.repository().retryPending(operation),
      throwsA(_failure(RepositoryFailureType.permissionDenied)),
    );
    expect(h.requests, isEmpty);
  });
  test(
    'money multiplication exact bounds zero cost and request collections frozen',
    () {
      expect(
        purchaseLineCost(1, purchaseMaximumInteger),
        purchaseMaximumInteger,
      );
      expect(
        () => purchaseLineCost(2, purchaseMaximumInteger),
        throwsA(isA<RepositoryFailure>()),
      );
      expect(purchaseLineCost(1000000, 0), 0);
      final items = [
        const PurchaseCreateItem(
          productId: purchaseProduct,
          expectedRevision: 2,
          quantity: 3,
          unitCostMinor: 101,
        ),
      ];
      final request = CreatePurchaseRequest(
        branchId: purchaseBranch,
        supplierId: purchaseSupplier,
        expectedSupplierRevision: 3,
        expectedSettingsRevision: 4,
        currency: 'PHP',
        items: items,
        reason: 'Restock',
      );
      items.clear();
      expect(request.items, hasLength(1));
      expect(() => request.items.clear(), throwsUnsupportedError);
    },
  );
  test(
    'unsafe totals duplicate lines unsupported currencies never prepare or dispatch',
    () async {
      await h.signIn();
      final base = createPurchaseRequest();
      for (final request in [
        CreatePurchaseRequest(
          branchId: purchaseBranch,
          supplierId: purchaseSupplier,
          expectedSupplierRevision: 3,
          expectedSettingsRevision: 4,
          currency: 'JPY',
          items: base.items,
          reason: base.reason,
        ),
        CreatePurchaseRequest(
          branchId: purchaseBranch,
          supplierId: purchaseSupplier,
          expectedSupplierRevision: 3,
          expectedSettingsRevision: 4,
          currency: 'PHP',
          items: [...base.items, ...base.items],
          reason: base.reason,
        ),
        CreatePurchaseRequest(
          branchId: purchaseBranch,
          supplierId: purchaseSupplier,
          expectedSupplierRevision: 3,
          expectedSettingsRevision: 4,
          currency: 'PHP',
          items: [
            const PurchaseCreateItem(
              productId: purchaseProduct,
              expectedRevision: 2,
              quantity: 2,
              unitCostMinor: purchaseMaximumInteger,
            ),
          ],
          reason: base.reason,
        ),
      ]) {
        await expectLater(
          h.repository().create(request),
          throwsA(_failure(RepositoryFailureType.validation)),
        );
      }
      expect(h.requests, isEmpty);
      expect(await h.journal.pending(), isEmpty);
    },
  );
  test(
    'server invalid calendar normalized UUID and fractional fields fail parsing',
    () {
      final wire = purchaseOrderWire();
      wire['created_at'] = '2026-02-31T00:00:00Z';
      expect(() => purchaseOrder(wire), throwsFormatException);
      wire['created_at'] = '2026-10-11T00:00:00Z';
      wire['ordered_total_minor'] = 303.0;
      expect(() => purchaseOrder(wire), throwsFormatException);
    },
  );
  test(
    'real PostgreSQL documents preserve initial and later action snapshots',
    () async {
      final fixture =
          jsonDecode(
                await File(
                  'test/fixtures/purchases_sql_contract.json',
                ).readAsString(),
              )
              as Map<String, dynamic>;
      final creation = fixture['creation'] as Map<String, dynamic>;
      final finalWire = fixture['final_order'] as Map<String, dynamic>;
      final initial = purchaseOrder(creation['order'] as Map<String, dynamic>);
      final finalOrder = purchaseOrder(finalWire);
      final partial = purchaseReceipt(
        fixture['partial_receipt']['receipt'] as Map<String, dynamic>,
      );
      final second = purchaseReceipt(
        fixture['second_receipt']['receipt'] as Map<String, dynamic>,
      );
      expect(initial.summary.status, PurchaseOrderStatus.ordered);
      expect(initial.summary.revision, 1);
      expect(initial.items.map((item) => item.remainingQuantity), [5, 3]);
      expect(partial.summary.orderRevision, 2);
      expect(partial.items.single.quantity, 2);
      expect(second.summary.orderRevision, 3);
      expect(second.items.single.productRevision, 2);
      expect(finalOrder.summary.revision, 4);
      expect(finalOrder.summary.status, PurchaseOrderStatus.cancelled);
      expect(finalOrder.receiptCount, 2);
      expect(finalOrder.items.first.currentCurrency, 'USD');
      expect(finalOrder.summary.currency, 'PHP');
      expect(finalOrder.items.first.productName, 'Original product 1');
      expect(finalOrder.items.first.currentProductName, 'Renamed product');
      expect(finalOrder.items.map((item) => item.receivedQuantity), [3, 0]);
      expect(finalOrder.cancellation!.items.map((item) => item.quantity), [
        2,
        3,
      ]);
      expect(finalOrder.items.last.unitCostMinor, 0);

      await h.close();
      h = _Harness(
        membership: AuthenticatedUser(
          userId: initial.summary.createdBy,
          email: 'sql-fixture@example.test',
          organizationId: initial.summary.organizationId,
          membershipId: initial.summary.supplierId,
          role: AppRole.owner,
          branchIds: {initial.summary.branchId},
          allBranches: true,
          businessName: 'SQL fixture',
        ),
      );
      await h.signIn();
      h.order = finalWire;
      h.result = creation;
      final create = fixture['create_request'] as Map<String, dynamic>;
      final created = await h.repository().create(
        CreatePurchaseRequest(
          requestId: create['p_request_id'] as String,
          branchId: create['p_branch_id'] as String,
          supplierId: create['p_supplier_id'] as String,
          expectedSupplierRevision:
              create['p_expected_supplier_revision'] as int,
          expectedSettingsRevision:
              create['p_expected_settings_revision'] as int,
          currency: create['p_currency'] as String,
          reason: create['p_reason'] as String,
          reference: create['p_reference'] as String?,
          items: (create['p_items'] as List)
              .map(
                (item) => PurchaseCreateItem(
                  productId: item['product_id'] as String,
                  expectedRevision: item['expected_revision'] as int,
                  quantity: item['quantity'] as int,
                  unitCostMinor: item['unit_cost_minor'] as int,
                ),
              )
              .toList(),
        ),
      );
      expect(created.order!.summary.revision, 1);
      expect(created.order!.items.first.remainingQuantity, 5);
      final receive = fixture['receive_request'] as Map<String, dynamic>;
      h.result = fixture['partial_receipt'] as Map<String, dynamic>;
      final received = await h.repository().receive(
        ReceivePurchaseRequest(
          requestId: receive['p_request_id'] as String,
          branchId: receive['p_branch_id'] as String,
          orderId: receive['p_order_id'] as String,
          expectedRevision: receive['p_expected_revision'] as int,
          reason: receive['p_reason'] as String,
          reference: receive['p_reference'] as String?,
          items: (receive['p_items'] as List)
              .map(
                (item) => PurchaseReceiveItem(
                  orderItemId: item['order_item_id'] as String,
                  quantity: item['quantity'] as int,
                  expectedProductRevision:
                      item['expected_product_revision'] as int,
                ),
              )
              .toList(),
        ),
      );
      expect(received.receipt!.summary.orderRevision, 2);
      expect(received.receipt!.items.single.unitCostMinor, 125);
      final cancel = fixture['cancel_request'] as Map<String, dynamic>;
      h.result = fixture['cancellation'] as Map<String, dynamic>;
      final cancelled = await h.repository().cancelRemaining(
        CancelPurchaseRequest(
          requestId: cancel['p_request_id'] as String,
          branchId: cancel['p_branch_id'] as String,
          orderId: cancel['p_order_id'] as String,
          expectedRevision: cancel['p_expected_revision'] as int,
          reason: cancel['p_reason'] as String,
        ),
      );
      expect(cancelled.cancellation!.cancelledTotalMinor, 250);
      expect(await h.journal.pending(), isEmpty);
      h.result = fixture['partial_receipt']['receipt'] as Map<String, dynamic>;
      final read = await h.repository().getReceipt(
        branchId: initial.summary.branchId.toUpperCase(),
        receiptId: partial.summary.id.toUpperCase(),
      );
      expect(read.summary.currency, 'PHP');
      final current = await h.repository().getOrder(
        branchId: initial.summary.branchId.toUpperCase(),
        orderId: initial.summary.id.toUpperCase(),
      );
      expect(current.summary.revision, 4);
      expect(current.summary.receivedTotalMinor, 375);
    },
  );
  test(
    'bounded order and delivery history fetch an extra row for paging',
    () async {
      await h.signIn();
      h.result = {};
      h.handler = (request) async {
        final params = jsonDecode(request.body) as Map<String, dynamic>;
        expect(params['p_offset'], 20);
        expect(params['p_limit'], 21);
        final receipts = request.url.path.endsWith('/list_purchase_receipts');
        final rows = List.generate(21, (index) {
          final row = receipts ? purchaseReceiptWire() : purchaseOrderWire();
          row['id'] =
              '12000000-0000-4000-8000-${(index + 1).toString().padLeft(12, '0')}';
          return row;
        });
        return _Harness.response(rows);
      };
      final orders = await h.repository().listOrders(
        branchId: purchaseBranch,
        page: const PageRequest(offset: 20, limit: 20),
      );
      final receipts = await h.repository().listReceipts(
        branchId: purchaseBranch,
        orderId: purchaseOrderId,
        page: const PageRequest(offset: 20, limit: 20),
      );
      expect(orders.items, hasLength(20));
      expect(orders.hasMore, true);
      expect(receipts.items, hasLength(20));
      expect(receipts.hasMore, true);
      expect(receipts.offset, 20);
    },
  );
  test('closed order evidence requires exact balances and receipt count', () {
    final wire = purchaseOrderWire(received: 1, cancelled: true);
    wire['receipt_count'] = 2;
    expect(() => purchaseOrder(wire), throwsFormatException);
    wire['receipt_count'] = 1;
    wire['cancellation']['items'][0]['product_name'] = 'Wrong snapshot';
    expect(() => purchaseOrder(wire), throwsFormatException);
    final receipt = purchaseReceiptWire();
    receipt['items'][0]['operation_id'] = otherPurchaseActor;
    expect(() => purchaseReceipt(receipt), throwsFormatException);
    receipt['items'][0]['operation_id'] = purchaseOperation;
    receipt['line_count'] = 2;
    expect(() => purchaseReceipt(receipt), throwsFormatException);
  });
  test('whole-unit and 100-line bounds fail before dispatch', () async {
    await h.signIn();
    for (final quantity in [-1, 0, 1000001]) {
      expect(
        () => purchaseQuantity(quantity),
        throwsA(_failure(RepositoryFailureType.validation)),
      );
    }
    expect(() => purchaseInteger(1.5), throwsFormatException);
    final lines = List.generate(
      101,
      (index) => PurchaseCreateItem(
        productId:
            '13000000-0000-4000-8000-${(index + 1).toString().padLeft(12, '0')}',
        expectedRevision: 1,
        quantity: 1,
        unitCostMinor: 0,
      ),
    );
    await expectLater(
      h.repository().create(
        CreatePurchaseRequest(
          branchId: purchaseBranch,
          supplierId: purchaseSupplier,
          expectedSupplierRevision: 3,
          expectedSettingsRevision: 4,
          currency: 'PHP',
          items: lines,
          reason: 'Restock shelves',
        ),
      ),
      throwsA(_failure(RepositoryFailureType.validation)),
    );
    expect(h.requests, isEmpty);
    expect(await h.journal.pending(), isEmpty);
  });
  test(
    'durable receipt intent reopens and retries exactly after process-like restart',
    () async {
      await h.close();
      final directory = await Directory.systemTemp.createTemp(
        'nexapos-purchase-journal-test-',
      );
      final file = File('${directory.path}/test-journal.sqlite');
      final first = _Harness(
        journal: NativeOperationJournal(
          executor: NativeDatabase(file),
          organizationId: purchaseOrg,
          actorId: purchaseActor,
        ),
      );
      await first.signIn();
      first.handler = (request) async {
        if (request.url.path.endsWith('/get_purchase_order')) {
          return _Harness.response(first.order);
        }
        throw const SocketException('test interrupted');
      };
      await expectLater(
        first.repository().receive(receivePurchaseRequest()),
        throwsA(_failure(RepositoryFailureType.unavailable)),
      );
      final payload = (await first.journal.pending()).single.payload;
      await first.close();
      final second = _Harness(
        journal: NativeOperationJournal(
          executor: NativeDatabase(file),
          organizationId: purchaseOrg,
          actorId: purchaseActor,
        ),
      );
      try {
        await second.signIn();
        second.order = purchaseOrderWire(received: 1, changedCatalog: true);
        second.result = purchaseReceiveResult();
        final pending = (await second.repository().pendingMutations()).single;
        expect(pending.payload, payload);
        await second.repository().retryPending(pending);
        expect(await second.journal.pending(), isEmpty);
      } finally {
        await second.close();
        await directory.delete(recursive: true);
      }
    },
  );
}
