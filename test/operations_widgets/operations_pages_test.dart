import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nexapos/core/operations/operation_journal.dart';
import 'package:nexapos/core/security/app_role.dart';
import 'package:nexapos/features/administration/domain/administration_models.dart';
import 'package:nexapos/features/catalog/domain/repository_support.dart';
import 'package:nexapos/features/checkout/domain/checkout_models.dart';
import 'package:nexapos/features/checkout/domain/checkout_repository.dart';
import 'package:nexapos/features/inventory/domain/inventory_models.dart';
import 'package:nexapos/features/inventory/domain/inventory_repository.dart';
import 'package:nexapos/features/inventory/presentation/inventory_page.dart';
import 'package:nexapos/features/people/domain/people_models.dart';
import 'package:nexapos/features/people/domain/people_repository.dart';
import 'package:nexapos/features/sales/presentation/receipt_details.dart';
import 'package:nexapos/features/sales/presentation/sales_page.dart';
import 'package:nexapos/features/shifts/presentation/shifts_page.dart';

const _org = '10000000-0000-0000-0000-000000000001';
const _branchId = '10000000-0000-0000-0000-000000000002';
const _actor = '10000000-0000-0000-0000-000000000003';
const _productId = '10000000-0000-0000-0000-000000000004';
const _shiftId = '10000000-0000-0000-0000-000000000005';
const _saleId = '10000000-0000-0000-0000-000000000006';
const _itemId = '10000000-0000-0000-0000-000000000007';
const _paymentId = '10000000-0000-0000-0000-000000000008';
const _requestId = '10000000-0000-0000-0000-000000000009';
const _secondPaymentId = '10000000-0000-0000-0000-000000000010';
const _freeItemId = '10000000-0000-0000-0000-000000000011';
final _time = DateTime.utc(2026, 10, 9, 0, 30);
const _branch = BranchOption(id: _branchId, name: 'Test branch', code: 'TB');
const _context = PosContext(
  branchId: _branchId,
  branchName: 'Test branch',
  businessName: 'Test business',
  currency: 'PHP',
  taxBps: 0,
  settingsRevision: 1,
);
const _product = PosProduct(
  id: _productId,
  organizationId: _org,
  name: 'Server product',
  sku: 'ACTUAL-SKU',
  priceMinor: 10000,
  currency: 'PHP',
  unit: 'each',
  revision: 7,
  availableQuantity: 12,
);

Shift _shift({
  bool closed = false,
  String actor = _actor,
  int expected = 12000,
}) => Shift(
  id: _shiftId,
  organizationId: _org,
  branchId: _branchId,
  actorUserId: actor,
  currency: 'PHP',
  openedAt: _time,
  openingCashMinor: 2000,
  expectedCashMinor: expected,
  closedAt: closed ? _time.add(const Duration(hours: 8)) : null,
  countedCashMinor: closed ? 11000 : null,
  cashDifferenceMinor: closed ? -1000 : null,
);

SaleReceipt _receipt({
  CheckoutPaymentMethod method = CheckoutPaymentMethod.cash,
  int reversed = 0,
}) => SaleReceipt(
  id: _saleId,
  organizationId: _org,
  branchId: _branchId,
  shiftId: _shiftId,
  actorUserId: _actor,
  receiptNumber: 'TB-20261009-000001',
  currency: 'PHP',
  createdAt: _time,
  businessName: 'Snapshot business',
  branchName: 'Test branch',
  subtotalMinor: 10000,
  discountMinor: 0,
  taxBps: 0,
  taxMinor: 0,
  totalMinor: 10000,
  items: [
    SaleItem(
      id: _itemId,
      productId: _productId,
      name: 'Snapshot product',
      sku: 'OLD-SKU',
      quantity: 1,
      unitPriceMinor: 10000,
      subtotalMinor: 10000,
      discountMinor: 0,
      taxMinor: 0,
      totalMinor: 10000,
      reversedQuantity: reversed,
    ),
  ],
  payments: [
    SalePayment(
      id: _paymentId,
      method: method,
      amountMinor: 10000,
      tenderedMinor: method == CheckoutPaymentMethod.cash ? 15000 : null,
      reference: method == CheckoutPaymentMethod.cash
          ? null
          : 'TERMINAL-RECORDED',
      reversedMinor: reversed == 0 ? 0 : 10000,
    ),
  ],
);

SaleReceipt _partialReceipt({int used = 1, bool freeLine = false}) =>
    SaleReceipt(
      id: _saleId,
      organizationId: _org,
      branchId: _branchId,
      shiftId: _shiftId,
      actorUserId: _actor,
      receiptNumber: 'TB-PARTIAL-000001',
      currency: 'PHP',
      createdAt: _time,
      subtotalMinor: freeLine ? 16 : 12,
      discountMinor: freeLine ? 7 : 3,
      taxBps: 1000,
      taxMinor: 1,
      totalMinor: 10,
      items: [
        SaleItem(
          id: _itemId,
          productId: _productId,
          name: 'Discounted taxed fixture',
          sku: 'REFUND-FIXTURE',
          quantity: 3,
          unitPriceMinor: 4,
          subtotalMinor: 12,
          discountMinor: 3,
          taxMinor: 1,
          totalMinor: 10,
          reversedQuantity: used,
        ),
        if (freeLine)
          const SaleItem(
            id: _freeItemId,
            productId: _freeItemId,
            name: 'Fully discounted fixture',
            sku: 'ZERO-VALUE',
            quantity: 1,
            unitPriceMinor: 4,
            subtotalMinor: 4,
            discountMinor: 4,
            taxMinor: 0,
            totalMinor: 0,
          ),
      ],
      payments: [
        SalePayment(
          id: _secondPaymentId,
          method: CheckoutPaymentMethod.gcash,
          amountMinor: 6,
          reference: 'ORIGINAL-WALLET',
          reversedMinor: used == 2 ? 2 : 0,
        ),
        SalePayment(
          id: _paymentId,
          method: CheckoutPaymentMethod.cash,
          amountMinor: 4,
          reversedMinor: used == 0
              ? 0
              : used == 1
              ? 3
              : 4,
        ),
      ],
    );

StockOperation _stockOperation() => StockOperation(
  id: _requestId,
  organizationId: _org,
  branchId: _branchId,
  actorUserId: _actor,
  kind: 'receive',
  createdAt: _time,
  reason: 'Physical delivery',
  movements: [
    StockMovement(
      id: _itemId,
      productId: _productId,
      quantityDelta: 5,
      balanceAfter: 17,
      createdAt: _time,
    ),
  ],
);

PendingOperation _pending(String type) => PendingOperation(
  requestId: _requestId,
  organizationId: _org,
  branchId: _branchId,
  actorId: _actor,
  type: type,
  payload: const {'frozen': 'original'},
  createdAt: _time,
  status: LocalOperationStatus.pending,
);

Future<void> _show(
  WidgetTester tester,
  Widget child, {
  Size size = const Size(1280, 1100),
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(MaterialApp(home: Scaffold(body: child)));
  await tester.pumpAndSettle();
}

Future<void> _check(WidgetTester tester, String title) async {
  final finder = find.widgetWithText(CheckboxListTile, title);
  await tester.ensureVisible(finder);
  await tester.tap(finder);
  await tester.pumpAndSettle();
}

Future<void> _text(WidgetTester tester, String key, String text) async {
  final finder = find.byKey(Key(key));
  await tester.ensureVisible(finder);
  await tester.enterText(finder, text);
}

void main() {
  testWidgets('all operation previews reject injected data and mutations', (
    tester,
  ) async {
    final checkout = _CheckoutFake(),
        inventory = _InventoryFake(),
        people = _PeopleFake();
    final pages = <Widget>[
      SalesPage(
        repository: checkout,
        peopleRepository: people,
        role: AppRole.owner,
      ),
      ShiftsPage(
        repository: checkout,
        peopleRepository: people,
        role: AppRole.owner,
        currentUserId: _actor,
      ),
      InventoryPage(
        repository: inventory,
        peopleRepository: people,
        role: AppRole.owner,
      ),
    ];
    for (final page in pages) {
      await _show(tester, page);
      expect(find.text('Not Yet Connected'), findsOneWidget);
      expect(find.text('Server product'), findsNothing);
    }
    expect(checkout.reads, 0);
    expect(inventory.reads, 0);
    expect(people.reads, 0);
    expect(checkout.mutations, 0);
    expect(inventory.mutations, 0);
  });

  testWidgets('inventory staff cannot read sales or shifts', (tester) async {
    final repo = _CheckoutFake(), people = _PeopleFake();
    await _show(
      tester,
      SalesPage(
        repository: repo,
        peopleRepository: people,
        role: AppRole.inventoryStaff,
        isPreview: false,
      ),
    );
    await _show(
      tester,
      ShiftsPage(
        repository: repo,
        peopleRepository: people,
        role: AppRole.inventoryStaff,
        currentUserId: _actor,
        isPreview: false,
      ),
    );
    expect(repo.reads, 0);
    expect(people.reads, 0);
  });

  testWidgets('cashier inventory route is blocked before reads', (
    tester,
  ) async {
    final repo = _InventoryFake(), people = _PeopleFake();
    await _show(
      tester,
      InventoryPage(
        repository: repo,
        peopleRepository: people,
        role: AppRole.cashier,
        isPreview: false,
      ),
    );
    expect(repo.reads, 0);
    expect(people.reads, 0);
    expect(find.text('Inventory access is restricted'), findsOneWidget);
  });

  testWidgets('connected operations pages fit a 320 pixel phone', (
    tester,
  ) async {
    final repo = _CheckoutFake()..current = _shift();
    final pages = <Widget>[
      SalesPage(
        repository: repo,
        peopleRepository: _PeopleFake(),
        role: AppRole.owner,
        isPreview: false,
      ),
      ShiftsPage(
        repository: repo,
        peopleRepository: _PeopleFake(),
        role: AppRole.owner,
        currentUserId: _actor,
        isPreview: false,
      ),
      InventoryPage(
        repository: _InventoryFake(),
        peopleRepository: _PeopleFake(),
        role: AppRole.inventoryStaff,
        isPreview: false,
      ),
    ];
    for (final page in pages) {
      await _show(tester, page, size: const Size(320, 1000));
      expect(tester.takeException(), isNull);
    }
  });

  testWidgets('sale history sends bounded server branch pagination', (
    tester,
  ) async {
    final repo = _CheckoutFake()..hasMore = true;
    await _show(
      tester,
      SalesPage(
        repository: repo,
        peopleRepository: _PeopleFake(),
        role: AppRole.cashier,
        isPreview: false,
      ),
    );
    expect(repo.branchRead, _branchId);
    expect(repo.limit, 20);
    expect(repo.offset, 0);
    await tester.tap(find.byKey(const Key('sales-next')));
    await tester.pumpAndSettle();
    expect(repo.offset, 20);
    expect(find.text('Page 2'), findsOneWidget);
  });

  testWidgets(
    'cashier reads actual snapshot receipt without reversal actions',
    (tester) async {
      final repo = _CheckoutFake();
      await _show(
        tester,
        SalesPage(
          repository: repo,
          peopleRepository: _PeopleFake(),
          role: AppRole.cashier,
          isPreview: false,
        ),
      );
      await tester.tap(find.byKey(const Key('sale-$_saleId')));
      await tester.pumpAndSettle();
      expect(find.text('Snapshot business'), findsOneWidget);
      expect(find.text('Snapshot product'), findsOneWidget);
      expect(find.text('PHP 50.00'), findsOneWidget);
      expect(find.text('Refund remaining sale'), findsNothing);
      expect(find.text('Void remaining sale'), findsNothing);
    },
  );

  testWidgets('manual receipt does not claim wallet provider authorization', (
    tester,
  ) async {
    await _show(
      tester,
      SingleChildScrollView(
        child: ReceiptDetails(
          receipt: _receipt(method: CheckoutPaymentMethod.gcash),
        ),
      ),
    );
    expect(find.text('GCash'), findsOneWidget);
    expect(
      find.text('Manual Verification · No provider authorization'),
      findsOneWidget,
    );
    expect(find.text('Reference: TERMINAL-RECORDED'), findsOneWidget);
    expect(find.textContaining('PDF export'), findsOneWidget);
  });

  testWidgets('original totals survive server recorded reversal counters', (
    tester,
  ) async {
    await _show(
      tester,
      SingleChildScrollView(
        child: ReceiptDetails(receipt: _receipt(reversed: 1)),
      ),
    );
    expect(find.text('Original total'), findsOneWidget);
    expect(find.text('Recorded reversals'), findsOneWidget);
    expect(find.text('Reversed units: 1'), findsOneWidget);
    expect(find.text('PHP 100.00'), findsWidgets);
  });

  testWidgets('refund requires active own shift and does not fake a payout', (
    tester,
  ) async {
    final repo = _CheckoutFake();
    await _show(
      tester,
      SalesPage(
        repository: repo,
        peopleRepository: _PeopleFake(),
        role: AppRole.manager,
        isPreview: false,
      ),
    );
    await tester.tap(find.byKey(const Key('sale-$_saleId')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Refund remaining sale'));
    await tester.pumpAndSettle();
    expect(find.textContaining('Open your own shift'), findsOneWidget);
    expect(repo.mutations, 0);
  });

  testWidgets(
    'refund waits for server and defaults physical stock return off',
    (tester) async {
      final repo = _CheckoutFake()
        ..current = _shift()
        ..reversalResult = Completer<SaleReversal>();
      await _show(
        tester,
        SalesPage(
          repository: repo,
          peopleRepository: _PeopleFake(),
          role: AppRole.manager,
          isPreview: false,
        ),
      );
      await tester.tap(find.byKey(const Key('sale-$_saleId')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Refund remaining sale'));
      await tester.pumpAndSettle();
      await _text(
        tester,
        'reversal-reason',
        'Customer cancelled after payment',
      );
      await _check(tester, 'All listed payouts have been completed manually');
      await tester.tap(find.byKey(const Key('reversal-submit')));
      await tester.pump();
      expect(repo.reversals.single.returnStock, isFalse);
      expect(repo.reversals.single.branchId, _branchId);
      expect(repo.reversals.single.shiftId, _shiftId);
      expect(repo.reversals.single.payments.single.amountMinor, 10000);
      expect(find.text('Refund recorded by the server.'), findsNothing);
      repo.reversalResult!.complete(
        SaleReversal(
          id: _requestId,
          saleId: _saleId,
          kind: SaleReversalKind.refund,
          totalMinor: 10000,
          createdAt: _time,
          reason: 'Server reason',
          returnStock: false,
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Refund recorded by the server.'), findsOneWidget);
    },
  );

  testWidgets('unconfirmed refund retries the same frozen evidence and UUID', (
    tester,
  ) async {
    final repo = _CheckoutFake()
      ..current = _shift()
      ..reversalFailures = 1;
    await _show(
      tester,
      SalesPage(
        repository: repo,
        peopleRepository: _PeopleFake(),
        role: AppRole.owner,
        isPreview: false,
      ),
    );
    await tester.tap(find.byKey(const Key('sale-$_saleId')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Refund remaining sale'));
    await tester.pumpAndSettle();
    await _text(tester, 'reversal-reason', 'Goods returned by customer');
    await _check(tester, 'All listed payouts have been completed manually');
    await _check(
      tester,
      'Every selected unit physically returned to this branch',
    );
    await tester.tap(find.byKey(const Key('reversal-submit')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('reversal-reason')), findsNothing);
    await tester.tap(find.byKey(const Key('reversal-submit')));
    await tester.pumpAndSettle();
    expect(repo.reversals.length, 2);
    expect(identical(repo.reversals[0], repo.reversals[1]), isTrue);
    expect(repo.reversals[0].requestId, repo.reversals[1].requestId);
    expect(repo.reversals[1].returnStock, isTrue);
  });

  testWidgets(
    'partial taxed discounted refund respects original split payment caps',
    (tester) async {
      final repo = _CheckoutFake()
        ..current = _shift()
        ..sale = _partialReceipt();
      await _openRefund(tester, repo);
      expect(find.text('Selected refund total: PHP 0.07'), findsOneWidget);
      await _text(tester, 'reversal-quantity-$_itemId', '1');
      await tester.pumpAndSettle();
      expect(find.text('Selected refund total: PHP 0.03'), findsOneWidget);
      expect(
        find.text('Cash payout: PHP 0.01 · remaining source cap PHP 0.01'),
        findsOneWidget,
      );
      expect(
        find.text('GCash payout: PHP 0.02 · remaining source cap PHP 0.06'),
        findsOneWidget,
      );
      await _text(tester, 'reversal-reason', 'One damaged unit returned');
      await tester.ensureVisible(find.byKey(const Key('reversal-submit')));
      await tester.tap(find.byKey(const Key('reversal-submit')));
      await tester.pumpAndSettle();
      expect(find.textContaining('Reversal reference'), findsOneWidget);
      expect(repo.reversals, isEmpty);
      await _text(
        tester,
        'reversal-reference-$_secondPaymentId',
        'WALLET-PAYOUT-001',
      );
      await _check(tester, 'All listed payouts have been completed manually');
      await tester.ensureVisible(find.byKey(const Key('reversal-submit')));
      await tester.tap(find.byKey(const Key('reversal-submit')));
      await tester.pumpAndSettle();
      final request = repo.reversals.single;
      expect(request.items.single.quantity, 1);
      expect(request.payments.map((payment) => payment.amountMinor), [1, 2]);
      expect(request.payments.first.originalPaymentId, _paymentId);
      expect(request.payments.last.originalPaymentId, _secondPaymentId);
      expect(request.payments.last.reference, 'WALLET-PAYOUT-001');
      expect(request.returnStock, isFalse);
    },
  );

  testWidgets(
    'last remaining unit releases final cent only to remaining source',
    (tester) async {
      final repo = _CheckoutFake()
        ..current = _shift()
        ..sale = _partialReceipt(used: 2);
      await _openRefund(tester, repo);
      expect(find.text('Selected refund total: PHP 0.04'), findsOneWidget);
      expect(
        find.byKey(const Key('reversal-payout-$_paymentId')),
        findsNothing,
      );
      await _text(tester, 'reversal-quantity-$_itemId', '2');
      await _text(tester, 'reversal-reason', 'Final damaged unit returned');
      await tester.ensureVisible(find.byKey(const Key('reversal-submit')));
      await tester.tap(find.byKey(const Key('reversal-submit')));
      await tester.pumpAndSettle();
      expect(
        find.text('At most 1 remaining unit can be returned.'),
        findsWidgets,
      );
      expect(repo.reversals, isEmpty);
      await _text(tester, 'reversal-quantity-$_itemId', '1');
      await tester.pumpAndSettle();
      await _text(
        tester,
        'reversal-reference-$_secondPaymentId',
        'FINAL-WALLET-PAYOUT',
      );
      await _check(tester, 'All listed payouts have been completed manually');
      await tester.ensureVisible(find.byKey(const Key('reversal-submit')));
      await tester.tap(find.byKey(const Key('reversal-submit')));
      await tester.pumpAndSettle();
      expect(repo.reversals.single.items.single.quantity, 1);
      expect(repo.reversals.single.payments.single.amountMinor, 4);
      expect(
        repo.reversals.single.payments.single.originalPaymentId,
        _secondPaymentId,
      );
    },
  );

  testWidgets('fully discounted selected units need no payout or reference', (
    tester,
  ) async {
    final repo = _CheckoutFake()
      ..current = _shift()
      ..sale = _partialReceipt(used: 0, freeLine: true);
    await _openRefund(tester, repo);
    await _text(tester, 'reversal-quantity-$_itemId', '0');
    await tester.pumpAndSettle();
    expect(find.text('Selected refund total: PHP 0.00'), findsOneWidget);
    expect(
      find.byKey(const Key('reversal-reference-$_secondPaymentId')),
      findsNothing,
    );
    expect(
      find.text('All listed payouts have been completed manually'),
      findsNothing,
    );
    await _text(
      tester,
      'reversal-reason',
      'Free damaged unit physically returned',
    );
    await _check(
      tester,
      'Every selected unit physically returned to this branch',
    );
    await tester.ensureVisible(find.byKey(const Key('reversal-submit')));
    await tester.tap(find.byKey(const Key('reversal-submit')));
    await tester.pumpAndSettle();
    final request = repo.reversals.single;
    expect(request.items.single.saleItemId, _freeItemId);
    expect(request.items.single.quantity, 1);
    expect(request.payments, isEmpty);
    expect(request.returnStock, isTrue);
  });

  testWidgets(
    'closing uncertain partial refund preserves quantities and evidence',
    (tester) async {
      final repo = _CheckoutFake()
        ..current = _shift()
        ..sale = _partialReceipt()
        ..reversalFailures = 1;
      await _openRefund(tester, repo);
      await _text(tester, 'reversal-quantity-$_itemId', '1');
      await tester.pumpAndSettle();
      await _text(tester, 'reversal-reason', 'Single returned damaged unit');
      await _text(
        tester,
        'reversal-reference-$_secondPaymentId',
        'FROZEN-WALLET-REF',
      );
      await _check(tester, 'All listed payouts have been completed manually');
      await tester.ensureVisible(find.byKey(const Key('reversal-submit')));
      await tester.tap(find.byKey(const Key('reversal-submit')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('reversal-quantity-$_itemId')), findsNothing);
      expect(find.text('Selected refund total: PHP 0.03'), findsOneWidget);
      await tester.tap(find.text('Keep pending and close'));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('sales-resume')));
      await tester.pumpAndSettle();
      expect(find.textContaining('FROZEN-WALLET-REF'), findsOneWidget);
      expect(find.byKey(const Key('reversal-quantity-$_itemId')), findsNothing);
      await tester.tap(find.byKey(const Key('reversal-submit')));
      await tester.pumpAndSettle();
      expect(repo.reversals.length, 2);
      expect(identical(repo.reversals.first, repo.reversals.last), isTrue);
      expect(repo.reversals.last.items.single.quantity, 1);
      expect(
        repo.reversals.last.payments.map((payment) => payment.amountMinor),
        [1, 2],
      );
      expect(repo.reversals.last.payments.last.reference, 'FROZEN-WALLET-REF');
    },
  );

  testWidgets(
    'partial refund selection and manual evidence fit a 320 pixel phone',
    (tester) async {
      final repo = _CheckoutFake()
        ..current = _shift()
        ..sale = _partialReceipt();
      await _openRefund(tester, repo, size: const Size(320, 850));
      await _text(tester, 'reversal-quantity-$_itemId', '1');
      await tester.pumpAndSettle();
      await _text(
        tester,
        'reversal-reason',
        'Returned unit from original receipt',
      );
      await _text(
        tester,
        'reversal-reference-$_secondPaymentId',
        'PHONE-MANUAL-PAYOUT',
      );
      await _check(tester, 'All listed payouts have been completed manually');
      await tester.ensureVisible(find.byKey(const Key('reversal-submit')));
      expect(tester.takeException(), isNull);
      await tester.tap(find.byKey(const Key('reversal-submit')));
      await tester.pumpAndSettle();
      expect(repo.reversals.single.items.single.quantity, 1);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'quantity changes require fresh payout and physical confirmations',
    (tester) async {
      final repo = _CheckoutFake()
        ..current = _shift()
        ..sale = _partialReceipt();
      await _openRefund(tester, repo);
      await _text(tester, 'reversal-quantity-$_itemId', '1');
      await tester.pumpAndSettle();
      await _check(tester, 'All listed payouts have been completed manually');
      await _check(
        tester,
        'Every selected unit physically returned to this branch',
      );
      await _text(tester, 'reversal-quantity-$_itemId', '2');
      await tester.pumpAndSettle();
      for (final label in [
        'All listed payouts have been completed manually',
        'Every selected unit physically returned to this branch',
      ]) {
        expect(
          tester
              .widget<CheckboxListTile>(
                find.widgetWithText(CheckboxListTile, label),
              )
              .value,
          isFalse,
        );
      }
      expect(repo.reversals, isEmpty);
    },
  );

  testWidgets('shift opening validates exact cash and counted confirmation', (
    tester,
  ) async {
    final repo = _CheckoutFake();
    await _show(
      tester,
      ShiftsPage(
        repository: repo,
        peopleRepository: _PeopleFake(),
        role: AppRole.cashier,
        currentUserId: _actor,
        isPreview: false,
      ),
    );
    await tester.tap(find.byKey(const Key('shift-open')));
    await tester.pumpAndSettle();
    await _text(tester, 'shift-cash', '12.345');
    await tester.tap(find.byKey(const Key('shift-submit')));
    await tester.pumpAndSettle();
    expect(find.textContaining('at most two decimal'), findsOneWidget);
    await _text(tester, 'shift-cash', '20.00');
    await tester.tap(find.byKey(const Key('shift-submit')));
    await tester.pumpAndSettle();
    expect(
      find.text('Confirm that you counted the physical cash.'),
      findsOneWidget,
    );
    expect(repo.mutations, 0);
  });

  testWidgets(
    'shift opening waits for actual server confirmation and freezes currency',
    (tester) async {
      final repo = _CheckoutFake()..openResult = Completer<Shift>();
      await _show(
        tester,
        ShiftsPage(
          repository: repo,
          peopleRepository: _PeopleFake(),
          role: AppRole.cashier,
          currentUserId: _actor,
          isPreview: false,
        ),
      );
      await tester.tap(find.byKey(const Key('shift-open')));
      await tester.pumpAndSettle();
      await _text(tester, 'shift-cash', '20.01');
      await _check(tester, 'I counted and confirmed this physical cash amount');
      await tester.tap(find.byKey(const Key('shift-submit')));
      await tester.pump();
      expect(repo.opens.single.openingCashMinor, 2001);
      expect(repo.opens.single.expectedCurrency, 'PHP');
      expect(find.text('Shift opened by the server.'), findsNothing);
      repo.openResult!.complete(_shift());
      await tester.pumpAndSettle();
      expect(find.text('Shift opened by the server.'), findsOneWidget);
    },
  );

  testWidgets('shift opening timeout preserves identical UUID and cash', (
    tester,
  ) async {
    final repo = _CheckoutFake()..openFailures = 1;
    await _show(
      tester,
      ShiftsPage(
        repository: repo,
        peopleRepository: _PeopleFake(),
        role: AppRole.cashier,
        currentUserId: _actor,
        isPreview: false,
      ),
    );
    await tester.tap(find.byKey(const Key('shift-open')));
    await tester.pumpAndSettle();
    await _text(tester, 'shift-cash', '40.00');
    await _check(tester, 'I counted and confirmed this physical cash amount');
    await tester.tap(find.byKey(const Key('shift-submit')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('shift-cash')), findsNothing);
    await tester.tap(find.byKey(const Key('shift-submit')));
    await tester.pumpAndSettle();
    expect(repo.opens.length, 2);
    expect(identical(repo.opens[0], repo.opens[1]), isTrue);
    expect(repo.opens[1].openingCashMinor, 4000);
  });

  testWidgets(
    'cashier cannot close another drawer; manager can review its count',
    (tester) async {
      final repo = _CheckoutFake()..shifts = [_shift(actor: 'other-actor')];
      await _show(
        tester,
        ShiftsPage(
          repository: repo,
          peopleRepository: _PeopleFake(),
          role: AppRole.cashier,
          currentUserId: _actor,
          isPreview: false,
        ),
      );
      expect(find.byKey(const Key('shift-close-$_shiftId')), findsNothing);
      await _show(
        tester,
        ShiftsPage(
          repository: repo,
          peopleRepository: _PeopleFake(),
          role: AppRole.manager,
          currentUserId: _actor,
          isPreview: false,
        ),
      );
      expect(find.byKey(const Key('shift-close-$_shiftId')), findsOneWidget);
      await tester.tap(find.byKey(const Key('shift-close-$_shiftId')));
      await tester.pumpAndSettle();
      expect(find.text('Count cash and close shift'), findsOneWidget);
    },
  );

  testWidgets(
    'shift close uses nonnegative physical count and server difference',
    (tester) async {
      final repo = _CheckoutFake()
        ..current = _shift()
        ..closeResult = Completer<Shift>();
      await _show(
        tester,
        ShiftsPage(
          repository: repo,
          peopleRepository: _PeopleFake(),
          role: AppRole.cashier,
          currentUserId: _actor,
          isPreview: false,
        ),
      );
      await tester.tap(find.byKey(const Key('shift-close-current')));
      await tester.pumpAndSettle();
      await _text(tester, 'shift-cash', '-10');
      await _text(tester, 'shift-close-reason', 'Closing count');
      await _check(tester, 'I counted and confirmed this physical cash amount');
      await tester.tap(find.byKey(const Key('shift-submit')));
      await tester.pumpAndSettle();
      expect(repo.closes, isEmpty);
      await _text(tester, 'shift-cash', '110.00');
      await tester.tap(find.byKey(const Key('shift-submit')));
      await tester.pump();
      expect(repo.closes.single.countedCashMinor, 11000);
      expect(repo.closes.single.branchId, _branchId);
      expect(
        find.textContaining('Shift closed. Server cash difference'),
        findsNothing,
      );
      repo.closeResult!.complete(_shift(closed: true));
      await tester.pumpAndSettle();
      expect(
        find.text('Shift closed. Server cash difference: PHP -10.00.'),
        findsOneWidget,
      );
    },
  );

  testWidgets('negative expected cash is shown as a drawer deficit', (
    tester,
  ) async {
    final repo = _CheckoutFake()..current = _shift(expected: -10000);
    await _show(
      tester,
      ShiftsPage(
        repository: repo,
        peopleRepository: _PeopleFake(),
        role: AppRole.cashier,
        currentUserId: _actor,
        isPreview: false,
      ),
    );
    expect(find.text('Expected cash: PHP -100.00'), findsWidgets);
    expect(find.textContaining('Expected cash is below zero'), findsOneWidget);
    expect(find.textContaining('Drawer deficit'), findsOneWidget);
    await tester.tap(find.byKey(const Key('shift-close-current')));
    await tester.pumpAndSettle();
    expect(find.text('Last loaded expected cash: PHP -100.00'), findsOneWidget);
    expect(find.textContaining('recorded cash deficit'), findsOneWidget);
    await _text(tester, 'shift-cash', '0.00');
    await _text(tester, 'shift-close-reason', 'Drawer deficit verified');
    await _check(tester, 'I counted and confirmed this physical cash amount');
    await tester.tap(find.byKey(const Key('shift-submit')));
    await tester.pumpAndSettle();
    expect(repo.closes.single.countedCashMinor, 0);
  });

  testWidgets('shift page needs current server-authenticated user identity', (
    tester,
  ) async {
    final repo = _CheckoutFake();
    await _show(
      tester,
      ShiftsPage(
        repository: repo,
        peopleRepository: _PeopleFake(),
        role: AppRole.owner,
        isPreview: false,
      ),
    );
    expect(repo.reads, 0);
    expect(
      tester
          .widget<FilledButton>(find.byKey(const Key('shift-open')))
          .onPressed,
      isNull,
    );
  });

  testWidgets(
    'saved checkout blocks creating a new reversal from sale details',
    (tester) async {
      final repo = _CheckoutFake()..pending = [_pending('checkout_sale')];
      await _show(
        tester,
        SalesPage(
          repository: repo,
          peopleRepository: _PeopleFake(),
          role: AppRole.owner,
          isPreview: false,
        ),
      );
      await tester.tap(find.byKey(const Key('sale-$_saleId')));
      await tester.pumpAndSettle();
      expect(find.text('Refund remaining sale'), findsNothing);
      expect(find.text('Void remaining sale'), findsNothing);
    },
  );

  testWidgets(
    'persisted unknown shift blocks new shift and retries saved payload',
    (tester) async {
      final repo = _CheckoutFake()..pending = [_pending('open_shift')];
      await _show(
        tester,
        ShiftsPage(
          repository: repo,
          peopleRepository: _PeopleFake(),
          role: AppRole.cashier,
          currentUserId: _actor,
          isPreview: false,
        ),
      );
      expect(
        tester
            .widget<FilledButton>(find.byKey(const Key('shift-open')))
            .onPressed,
        isNull,
      );
      await tester.tap(find.byKey(const Key('pending-retry-$_requestId')));
      await tester.pumpAndSettle();
      expect(repo.retried?.payload, const {'frozen': 'original'});
      expect(
        find.text('Saved financial request confirmed by the server.'),
        findsOneWidget,
      );
      expect(repo.opens, isEmpty);
    },
  );

  testWidgets(
    'later permission failure keeps durable ambiguous shift blocked',
    (tester) async {
      final repo = _CheckoutFake()
        ..pending = [_pending('open_shift')]
        ..retryFailure = const RepositoryFailure(
          RepositoryFailureType.permissionDenied,
          'Access changed.',
        );
      await _show(
        tester,
        ShiftsPage(
          repository: repo,
          peopleRepository: _PeopleFake(),
          role: AppRole.cashier,
          currentUserId: _actor,
          isPreview: false,
        ),
      );
      await tester.tap(find.byKey(const Key('pending-retry-$_requestId')));
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<FilledButton>(find.byKey(const Key('shift-open')))
            .onPressed,
        isNull,
      );
      expect(
        find.textContaining('Unconfirmed open shift request'),
        findsOneWidget,
      );
      expect(repo.opens, isEmpty);
    },
  );

  testWidgets('inventory server search and ledger filters stay bounded', (
    tester,
  ) async {
    final repo = _InventoryFake()..hasMore = true;
    await _show(
      tester,
      InventoryPage(
        repository: repo,
        peopleRepository: _PeopleFake(),
        role: AppRole.inventoryStaff,
        isPreview: false,
      ),
    );
    expect(repo.limit, 20);
    await tester.enterText(find.byKey(const Key('stock-search')), 'ACTUAL');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pumpAndSettle();
    expect(repo.query, 'ACTUAL');
    await tester.ensureVisible(find.byKey(const Key('stock-next')));
    await tester.tap(find.byKey(const Key('stock-next')));
    await tester.pumpAndSettle();
    expect(repo.offset, 20);
    await tester.tap(find.byKey(const Key('stock-ledger-$_productId')));
    await tester.pumpAndSettle();
    expect(repo.productFilter, _productId);
    expect(repo.offset, 0);
    expect(find.text('Balance after movement: 17'), findsOneWidget);
    expect(find.text('Adjust stock'), findsNothing);
  });

  testWidgets(
    'receiving validates whole quantities and actual physical confirmation',
    (tester) async {
      final repo = _InventoryFake();
      await _show(
        tester,
        InventoryPage(
          repository: repo,
          peopleRepository: _PeopleFake(),
          role: AppRole.inventoryStaff,
          isPreview: false,
        ),
      );
      await tester.tap(find.byKey(const Key('stock-receive')));
      await tester.pumpAndSettle();
      await _selectProduct(tester);
      await _text(tester, 'receive-quantity', '1.5');
      await _text(tester, 'receive-reference', 'DELIVERY-001');
      await _text(tester, 'receive-reason', 'Physical delivery');
      await tester.tap(find.byKey(const Key('receive-submit')));
      await tester.pumpAndSettle();
      expect(
        find.text('Enter a positive whole-unit quantity.'),
        findsOneWidget,
      );
      await _text(tester, 'receive-quantity', '5');
      await tester.tap(find.byKey(const Key('receive-submit')));
      await tester.pumpAndSettle();
      expect(
        find.textContaining('confirm the units were physically received'),
        findsOneWidget,
      );
      expect(repo.mutations, 0);
    },
  );

  testWidgets(
    'stock receipt waits for server and records exact private cost evidence',
    (tester) async {
      final repo = _InventoryFake()
        ..receiveResult = Completer<StockOperation>();
      await _show(
        tester,
        InventoryPage(
          repository: repo,
          peopleRepository: _PeopleFake(),
          role: AppRole.owner,
          isPreview: false,
        ),
      );
      await tester.tap(find.byKey(const Key('stock-receive')));
      await tester.pumpAndSettle();
      await _selectProduct(tester);
      await _text(tester, 'receive-quantity', '5');
      await _text(tester, 'receive-cost', '9.99');
      await _text(tester, 'receive-reference', 'DELIVERY-001');
      await _text(tester, 'receive-reason', 'Physical delivery');
      await _check(
        tester,
        'These units were physically received into this branch',
      );
      await tester.tap(find.byKey(const Key('receive-submit')));
      await tester.pump();
      expect(repo.receives.single.items.single.quantity, 5);
      expect(repo.receives.single.items.single.unitCostMinor, 999);
      expect(repo.receives.single.items.single.expectedRevision, 7);
      expect(find.text('Stock receipt recorded by the server.'), findsNothing);
      repo.receiveResult!.complete(_stockOperation());
      await tester.pumpAndSettle();
      expect(
        find.text('Stock receipt recorded by the server.'),
        findsOneWidget,
      );
    },
  );

  testWidgets(
    'receiving timeout retries original frozen product revision and quantity',
    (tester) async {
      final repo = _InventoryFake()..receiveFailures = 1;
      await _show(
        tester,
        InventoryPage(
          repository: repo,
          peopleRepository: _PeopleFake(),
          role: AppRole.owner,
          isPreview: false,
        ),
      );
      await tester.tap(find.byKey(const Key('stock-receive')));
      await tester.pumpAndSettle();
      await _selectProduct(tester);
      await _text(tester, 'receive-quantity', '5');
      await _text(tester, 'receive-reference', 'DELIVERY-001');
      await _text(tester, 'receive-reason', 'Physical delivery');
      await _check(
        tester,
        'These units were physically received into this branch',
      );
      await tester.tap(find.byKey(const Key('receive-submit')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('receive-quantity')), findsNothing);
      await tester.tap(find.byKey(const Key('receive-submit')));
      await tester.pumpAndSettle();
      expect(repo.receives.length, 2);
      expect(identical(repo.receives[0], repo.receives[1]), isTrue);
    },
  );

  testWidgets('manager signed adjustment validates nonzero whole units', (
    tester,
  ) async {
    final repo = _InventoryFake();
    await _show(
      tester,
      InventoryPage(
        repository: repo,
        peopleRepository: _PeopleFake(),
        role: AppRole.manager,
        isPreview: false,
      ),
    );
    await tester.tap(find.byKey(const Key('stock-adjust-$_productId')));
    await tester.pumpAndSettle();
    await _text(tester, 'adjust-delta', '0');
    await _text(tester, 'adjust-reason', 'Physical count discrepancy');
    await _check(
      tester,
      'This signed change matches a counted physical discrepancy',
    );
    await tester.tap(find.byKey(const Key('adjust-submit')));
    await tester.pumpAndSettle();
    expect(repo.adjustments, isEmpty);
    await _text(tester, 'adjust-delta', '-2');
    await tester.tap(find.byKey(const Key('adjust-submit')));
    await tester.pumpAndSettle();
    expect(repo.adjustments.single.deltaQuantity, -2);
    expect(
      find.text('Stock adjustment recorded by the server.'),
      findsOneWidget,
    );
  });

  testWidgets('persisted stock request blocks new receives and adjustments', (
    tester,
  ) async {
    final repo = _InventoryFake()..pending = [_pending('adjust_stock')];
    await _show(
      tester,
      InventoryPage(
        repository: repo,
        peopleRepository: _PeopleFake(),
        role: AppRole.manager,
        isPreview: false,
      ),
    );
    expect(
      tester
          .widget<FilledButton>(find.byKey(const Key('stock-receive')))
          .onPressed,
      isNull,
    );
    expect(
      tester
          .widget<OutlinedButton>(
            find.byKey(const Key('stock-adjust-$_productId')),
          )
          .onPressed,
      isNull,
    );
    await tester.tap(find.byKey(const Key('pending-retry-$_requestId')));
    await tester.pumpAndSettle();
    expect(repo.retried?.requestId, _requestId);
    expect(repo.receives, isEmpty);
    expect(repo.adjustments, isEmpty);
    expect(
      find.text('Saved stock request confirmed by the server.'),
      findsOneWidget,
    );
  });

  testWidgets('receiving and closing forms fit a 320 pixel phone', (
    tester,
  ) async {
    await _show(
      tester,
      InventoryPage(
        repository: _InventoryFake(),
        peopleRepository: _PeopleFake(),
        role: AppRole.owner,
        isPreview: false,
      ),
      size: const Size(320, 1000),
    );
    await tester.tap(find.byKey(const Key('stock-receive')));
    await tester.pumpAndSettle();
    await _selectProduct(tester);
    await _text(tester, 'receive-reason', 'Phone receiving');
    expect(tester.takeException(), isNull);
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    await _show(
      tester,
      ShiftsPage(
        repository: _CheckoutFake()..current = _shift(),
        peopleRepository: _PeopleFake(),
        role: AppRole.cashier,
        currentUserId: _actor,
        isPreview: false,
      ),
      size: const Size(320, 1000),
    );
    await tester.ensureVisible(find.byKey(const Key('shift-close-current')));
    await tester.tap(find.byKey(const Key('shift-close-current')));
    await tester.pumpAndSettle();
    await _text(tester, 'shift-close-reason', 'Phone closing count');
    expect(tester.takeException(), isNull);
  });
}

Future<void> _selectProduct(WidgetTester tester) async {
  final finder = find.byWidgetPredicate(
    (widget) =>
        widget is DropdownButtonFormField<String> &&
        widget.decoration.labelText == 'Product',
  );
  await tester.ensureVisible(finder);
  await tester.tap(finder);
  await tester.pumpAndSettle();
  await tester.tap(find.text('Server product · ACTUAL-SKU').last);
  await tester.pumpAndSettle();
}

const _unavailable = RepositoryFailure(
  RepositoryFailureType.unavailable,
  'Connection interrupted.',
);

Future<void> _openRefund(
  WidgetTester tester,
  _CheckoutFake repo, {
  Size size = const Size(1280, 1100),
}) async {
  await _show(
    tester,
    SalesPage(
      repository: repo,
      peopleRepository: _PeopleFake(),
      role: AppRole.manager,
      isPreview: false,
    ),
    size: size,
  );
  await tester.tap(find.byKey(const Key('sale-$_saleId')));
  await tester.pumpAndSettle();
  await tester.tap(find.text('Refund remaining sale'));
  await tester.pumpAndSettle();
}

class _CheckoutFake implements CheckoutRepository {
  int reads = 0, mutations = 0, offset = 0, limit = 0;
  String? branchRead;
  bool hasMore = false;
  Shift? current;
  List<Shift> shifts = [];
  List<PendingOperation> pending = [];
  PendingOperation? retried;
  RepositoryFailure? retryFailure;
  int openFailures = 0, reversalFailures = 0;
  Completer<Shift>? openResult, closeResult;
  Completer<SaleReversal>? reversalResult;
  SaleReceipt? sale;
  List<OpenShiftRequest> opens = [];
  List<CloseShiftRequest> closes = [];
  List<ReversalRequest> reversals = [];
  @override
  Future<PosContext> loadContext(String branchId) async {
    reads++;
    return _context;
  }

  @override
  Future<Shift?> currentShift(String branchId) async {
    reads++;
    return current;
  }

  @override
  Future<DataPage<Shift>> listShifts({
    String? branchId,
    PageRequest page = const PageRequest(),
  }) async {
    reads++;
    branchRead = branchId;
    offset = page.offset;
    limit = page.limit;
    return DataPage(
      items: shifts.isEmpty && current != null ? [current!] : shifts,
      hasMore: hasMore,
      offset: page.offset,
    );
  }

  @override
  Future<DataPage<SaleReceipt>> listSales({
    required String branchId,
    PageRequest page = const PageRequest(),
  }) async {
    reads++;
    branchRead = branchId;
    offset = page.offset;
    limit = page.limit;
    return DataPage(
      items: [sale ?? _receipt()],
      hasMore: hasMore,
      offset: page.offset,
    );
  }

  @override
  Future<SaleReceipt> getSale(String saleId) async {
    reads++;
    return sale ?? _receipt();
  }

  @override
  Future<Shift> openShift(OpenShiftRequest request) async {
    mutations++;
    opens.add(request);
    if (openFailures-- > 0) throw _unavailable;
    final result = openResult == null ? _shift() : await openResult!.future;
    current = result;
    return result;
  }

  @override
  Future<Shift> closeShift(CloseShiftRequest request) async {
    mutations++;
    closes.add(request);
    final result = closeResult == null
        ? _shift(closed: true)
        : await closeResult!.future;
    current = null;
    shifts = [result];
    return result;
  }

  @override
  Future<SaleReversal> reverseSale(ReversalRequest request) async {
    mutations++;
    reversals.add(request);
    if (reversalFailures-- > 0) throw _unavailable;
    return reversalResult == null
        ? SaleReversal(
            id: _requestId,
            saleId: request.saleId,
            kind: request.kind,
            totalMinor: 10000,
            createdAt: _time,
            reason: request.reason,
            returnStock: request.returnStock,
          )
        : await reversalResult!.future;
  }

  @override
  Future<List<PendingOperation>> pendingOperations({String? branchId}) async =>
      pending;
  @override
  Future<Object> retryPending(PendingOperation operation) async {
    retried = operation;
    if (retryFailure != null) throw retryFailure!;
    pending = [];
    return _shift();
  }

  @override
  Future<DataPage<PosProduct>> searchProducts({
    required String branchId,
    String query = '',
    String? categoryId,
    PageRequest page = const PageRequest(),
  }) async => DataPage(items: [_product], hasMore: false, offset: page.offset);
  @override
  Future<PosProduct?> lookupProductByBarcode({
    required String branchId,
    required String barcode,
  }) async => _product;
  @override
  Future<SaleReceipt> checkout(CheckoutRequest request) async => _receipt();
  @override
  Future<SaleReceipt?> findSaleByRequest({
    required String branchId,
    required String requestId,
  }) async => null;
  @override
  Future<CheckoutRequest?> pendingCheckout(String branchId) async => null;
}

class _InventoryFake implements InventoryRepository {
  int reads = 0, mutations = 0, offset = 0, limit = 0, receiveFailures = 0;
  String? query, productFilter;
  bool hasMore = false;
  Completer<StockOperation>? receiveResult;
  List<ReceiveStockRequest> receives = [];
  List<AdjustStockRequest> adjustments = [];
  List<PendingOperation> pending = [];
  PendingOperation? retried;
  @override
  Future<DataPage<PosProduct>> listBalances({
    required String branchId,
    String query = '',
    PageRequest page = const PageRequest(),
  }) async {
    reads++;
    this.query = query;
    offset = page.offset;
    limit = page.limit;
    return DataPage(items: [_product], hasMore: hasMore, offset: page.offset);
  }

  @override
  Future<DataPage<StockMovement>> listMovements({
    required String branchId,
    String? productId,
    PageRequest page = const PageRequest(),
  }) async {
    reads++;
    productFilter = productId;
    offset = page.offset;
    limit = page.limit;
    return DataPage(
      items: [
        StockMovement(
          id: _itemId,
          productId: _productId,
          quantityDelta: 5,
          balanceAfter: 17,
          createdAt: _time,
          productName: 'Server product',
          kind: 'receive',
          reason: 'Physical delivery',
        ),
      ],
      hasMore: hasMore,
      offset: page.offset,
    );
  }

  @override
  Future<StockOperation> receiveStock(ReceiveStockRequest request) async {
    mutations++;
    receives.add(request);
    if (receiveFailures-- > 0) throw _unavailable;
    return receiveResult == null
        ? _stockOperation()
        : await receiveResult!.future;
  }

  @override
  Future<StockOperation> adjustStock(AdjustStockRequest request) async {
    mutations++;
    adjustments.add(request);
    return _stockOperation();
  }

  @override
  Future<List<PendingOperation>> pendingOperations({String? branchId}) async =>
      pending;
  @override
  Future<StockOperation> retryPending(PendingOperation operation) async {
    retried = operation;
    pending = [];
    return _stockOperation();
  }
}

class _PeopleFake implements PeopleRepository {
  int reads = 0;
  @override
  Future<List<BranchOption>> listBranches() async {
    reads++;
    return [_branch];
  }

  @override
  Future<DataPage<Supplier>> listSuppliers({
    String query = '',
    bool? active,
    String? branchId,
    PageRequest page = const PageRequest(),
  }) async {
    reads++;
    return DataPage(items: [], hasMore: false, offset: page.offset);
  }

  @override
  Future<DataPage<Customer>> listCustomers({
    String query = '',
    bool? active,
    String? branchId,
    PageRequest page = const PageRequest(),
  }) async => DataPage(items: [], hasMore: false, offset: page.offset);
  @override
  Future<Supplier> createSupplier(SupplierInput input) =>
      throw UnimplementedError();
  @override
  Future<Supplier> updateSupplier({
    required String id,
    required int expectedRevision,
    required SupplierInput input,
  }) => throw UnimplementedError();
  @override
  Future<Supplier> setSupplierActive({
    required String id,
    required int expectedRevision,
    required bool active,
  }) => throw UnimplementedError();
  @override
  Future<Customer> createCustomer(CustomerInput input) =>
      throw UnimplementedError();
  @override
  Future<Customer> updateCustomer({
    required String id,
    required int expectedRevision,
    required CustomerInput input,
  }) => throw UnimplementedError();
  @override
  Future<Customer> setCustomerActive({
    required String id,
    required int expectedRevision,
    required bool active,
  }) => throw UnimplementedError();
}
