import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nexapos/core/operations/operation_journal.dart';
import 'package:nexapos/core/security/app_role.dart';
import 'package:nexapos/features/administration/domain/administration_models.dart';
import 'package:nexapos/features/catalog/domain/catalog_models.dart';
import 'package:nexapos/features/catalog/domain/catalog_repository.dart';
import 'package:nexapos/features/catalog/domain/repository_support.dart';
import 'package:nexapos/features/people/domain/people_models.dart';
import 'package:nexapos/features/people/domain/people_repository.dart';
import 'package:nexapos/features/purchases/data/purchase_decoders.dart';
import 'package:nexapos/features/purchases/domain/purchase_models.dart';
import 'package:nexapos/features/purchases/domain/purchase_repository.dart';
import 'package:nexapos/features/purchases/presentation/purchases_page.dart';

import 'purchase_fixtures.dart';

const _otherBranch = '11000000-0000-4000-8000-000000000020';
const _branches = [
  BranchOption(id: purchaseBranch, name: 'Fixture branch', code: 'FIX'),
  BranchOption(id: _otherBranch, name: 'Second branch', code: 'SEC'),
];
const _supplier = Supplier(
  id: purchaseSupplier,
  organizationId: purchaseOrg,
  name: 'Fixture supplier',
  active: true,
  revision: 3,
  branchId: purchaseBranch,
);
const _product = Product(
  id: purchaseProduct,
  organizationId: purchaseOrg,
  name: 'Original product',
  sku: 'ORIGINAL-SKU',
  priceMinor: 199,
  costMinor: 101,
  currency: 'PHP',
  reorderLevel: '0',
  unit: 'each',
  active: true,
  revision: 2,
);

void main() {
  for (final size in [const Size(320, 900), const Size(1280, 1100)]) {
    final width = size.width.toInt();

    testWidgets('$width px preview never reads injected business data', (
      tester,
    ) async {
      final repository = _PurchasesFake();
      final people = _PeopleFake();
      await _show(
        tester,
        repository,
        people: people,
        preview: true,
        size: size,
      );
      expect(repository.contextBranches, isEmpty);
      expect(people.branchReads, 0);
      expect(find.text('No connected purchase orders'), findsOneWidget);
      expect(find.text('Fixture supplier'), findsNothing);
      expect(find.byKey(const Key('purchase-create')), findsNothing);
      expect(tester.takeException(), isNull);
    });

    testWidgets('$width px authorized empty/error states preserve branch', (
      tester,
    ) async {
      final repository = _PurchasesFake()..empty = true;
      await _show(tester, repository, size: size);
      await _reveal(
        tester,
        find.text('No purchase orders match this branch and search.'),
      );
      expect(repository.contextBranches.single, purchaseBranch);
      expect(find.text('Fixture supplier'), findsNothing);
      expect(find.textContaining('Ordered PHP'), findsNothing);
      repository.readError = const RepositoryFailure(
        RepositoryFailureType.unavailable,
        'Purchase service unavailable for this branch.',
      );
      await _tap(tester, find.text('Refresh'));
      await _reveal(
        tester,
        find.text('Purchase service unavailable for this branch.'),
      );
      expect(
        find.text('Purchase service unavailable for this branch.'),
        findsOneWidget,
      );
      expect(find.text('Fixture branch'), findsOneWidget);
      expect(find.text('Fixture supplier'), findsNothing);
      expect(tester.takeException(), isNull);
    });

    testWidgets(
      '$width px real order, quantities and receipt evidence render',
      (tester) async {
        final repository = _PurchasesFake()
          ..order = purchaseFixtureOrder(received: 1);
        await _show(tester, repository, size: size);
        await _openOrder(tester);
        await _reveal(tester, find.text('Original product · ORIGINAL-SKU'));
        expect(find.text('Order details · Fixture supplier'), findsOneWidget);
        expect(
          find.text('Ordered 3 · received 1 · cancelled 0 · remaining 2 each'),
          findsOneWidget,
        );
        expect(
          find.text('PHP 1.01 per unit · PHP 3.03 ordered'),
          findsOneWidget,
        );
        await _tap(tester, find.textContaining('Delivery fixture'));
        expect(find.text('Confirmed delivery receipt'), findsOneWidget);
        expect(find.text('Received PHP 1.01'), findsOneWidget);
        expect(find.text('Original product · 1 units'), findsOneWidget);
        expect(
          find.text('Stock balance after: -1 · revision 3'),
          findsOneWidget,
        );
        await _reveal(tester, find.text('Movement: $purchaseMovement'));
        expect(find.text('Movement: $purchaseMovement'), findsOneWidget);
        expect(repository.receiptReads.single, purchaseReceiptId);
        expect(tester.takeException(), isNull);
      },
    );

    testWidgets(
      '$width px receive validates review and preserves original cost',
      (tester) async {
        final repository = _PurchasesFake();
        await _show(tester, repository, size: size);
        await _openOrder(tester);
        await _tap(tester, find.byKey(const Key('purchase-receive')));
        expect(
          find.textContaining(
            'Renamed product · NEW-SKU · each · USD · revision 9',
          ),
          findsOneWidget,
        );
        await _tap(tester, find.text('Confirm physical receipt'));
        await _reveal(
          tester,
          find.text(
            'Confirm that the entered quantities were physically received.',
          ),
        );
        expect(repository.receives, isEmpty);
        await _fillReceive(tester, quantity: '4', reviewed: false);
        await _tap(tester, find.text('Confirm physical receipt'));
        await _reveal(
          tester,
          find.text('Receive at most 3 units of Original product.'),
        );
        expect(repository.receives, isEmpty);
        await tester.enterText(
          find.byKey(const Key('purchase-receive-quantity-$purchaseOrderItem')),
          '1',
        );
        await _tap(tester, find.text('Confirm physical receipt'));
        await _reveal(
          tester,
          find.text(
            'Review the current catalog product for Original product before receiving it.',
          ),
        );
        await _tap(
          tester,
          find.text('I reviewed this current catalog product.'),
        );
        await _tap(tester, find.text('Confirm physical receipt'));
        final request = repository.receives.single;
        expect(request.branchId, purchaseBranch);
        expect(request.orderId, purchaseOrderId);
        expect(request.expectedRevision, 1);
        expect(request.items.single.quantity, 1);
        expect(request.items.single.expectedProductRevision, 9);
        await _reveal(
          tester,
          find.text('Ordered 3 · received 1 · cancelled 0 · remaining 2 each'),
        );
        expect(
          find.text('PHP 1.01 per unit · PHP 3.03 ordered'),
          findsOneWidget,
        );
        expect(find.text('Partially received'), findsWidgets);
        expect(tester.takeException(), isNull);
      },
    );

    testWidgets(
      '$width px cancellation closes remaining units and retains receipt',
      (tester) async {
        final repository = _PurchasesFake()
          ..order = purchaseFixtureOrder(received: 1);
        await _show(tester, repository, size: size);
        await _openOrder(tester);
        await _tap(tester, find.byKey(const Key('purchase-cancel')));
        await _tap(tester, find.text('Cancel remaining'));
        expect(repository.cancellations, isEmpty);
        expect(
          find.text('Cancellation reason must contain 3 to 1000 characters.'),
          findsOneWidget,
        );
        await tester.enterText(
          _field('Cancellation reason'),
          'Supplier discontinued',
        );
        await _tap(tester, find.text('Cancel remaining'));
        expect(repository.cancellations.single.expectedRevision, 2);
        expect(repository.cancellations.single.reason, 'Supplier discontinued');
        await _reveal(
          tester,
          find.text('Ordered 3 · received 1 · cancelled 2 · remaining 0 each'),
        );
        expect(
          find.text('Remaining quantities cancelled: Supplier discontinued'),
          findsOneWidget,
        );
        expect(find.byKey(const Key('purchase-receive')), findsNothing);
        expect(find.byKey(const Key('purchase-cancel')), findsNothing);
        await _tap(tester, find.textContaining('Delivery fixture'));
        expect(find.text('Received PHP 1.01'), findsOneWidget);
        expect(tester.takeException(), isNull);
      },
    );

    testWidgets('$width px unpaid create form records explicit quantities/cost', (
      tester,
    ) async {
      final repository = _PurchasesFake();
      final people = _PeopleFake();
      final catalog = _CatalogFake();
      await _show(
        tester,
        repository,
        people: people,
        catalog: catalog,
        size: size,
      );
      await _tap(tester, find.byKey(const Key('purchase-create')));
      await _tap(tester, find.text('Submit immutable order'));
      expect(repository.creates, isEmpty);
      await _tap(tester, find.text('Choose supplier'));
      await _tap(tester, find.text('Fixture supplier').last);
      await _tap(tester, find.text('Add product'));
      await _tap(tester, find.text('Original product'));
      await _reveal(tester, _field('Ordered whole units'));
      await tester.enterText(_field('Ordered whole units'), '3');
      await tester.enterText(_field('Recorded unit cost (PHP)'), '0');
      await _reveal(tester, _field('Order reason'));
      await tester.enterText(_field('Order reason'), 'Free sample stock');
      await _tap(
        tester,
        find.text(
          'I confirm this records an unpaid order; no supplier payment or email is sent.',
        ),
      );
      await _tap(tester, find.text('Submit immutable order'));
      final request = repository.creates.single;
      expect(request.branchId, purchaseBranch);
      expect(request.supplierId, purchaseSupplier);
      expect(request.expectedSupplierRevision, 3);
      expect(request.expectedSettingsRevision, 4);
      expect(request.currency, 'PHP');
      expect(request.items.single.quantity, 3);
      expect(request.items.single.unitCostMinor, 0);
      expect(request.items.single.expectedRevision, 2);
      expect(people.supplierReads.single.$1, purchaseBranch);
      expect(people.supplierReads.single.$2, isTrue);
      expect(catalog.searches.single.$1.active, isTrue);
      expect(
        repository.creates.single.requestId,
        matches(RegExp(r'^[0-9a-f-]{36}$')),
      );
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('cashier purchase access fails before any branch/data read', (
    tester,
  ) async {
    final repository = _PurchasesFake();
    final people = _PeopleFake();
    await _show(tester, repository, people: people, role: AppRole.cashier);
    expect(find.text('Purchase access is restricted'), findsOneWidget);
    expect(repository.contextBranches, isEmpty);
    expect(people.branchReads, 0);
  });

  testWidgets('no assigned branches exposes no order authoring', (
    tester,
  ) async {
    final repository = _PurchasesFake();
    await _show(tester, repository, people: _PeopleFake()..branches = []);
    expect(
      find.text('No assigned active branches are available.'),
      findsOneWidget,
    );
    expect(repository.contextBranches, isEmpty);
    expect(
      tester
          .widget<FilledButton>(find.byKey(const Key('purchase-create')))
          .onPressed,
      isNull,
    );
  });

  testWidgets(
    'orders and receipts page independently with stable server scope',
    (tester) async {
      final repository = _PurchasesFake()
        ..order = purchaseFixtureOrder(received: 1)
        ..moreOrders = true
        ..moreReceipts = true;
      await _show(tester, repository);
      await _tap(tester, find.byKey(const Key('purchase-next')));
      expect(repository.orderReads.last.$4.offset, 20);
      expect(repository.orderReads.last.$4.limit, 20);
      await _openOrder(tester);
      await _tap(tester, find.byKey(const Key('purchase-receipts-next')));
      expect(repository.receiptPages.map((page) => page.offset), [0, 20]);
      expect(repository.receiptPages.last.limit, 20);
      await _tap(tester, find.byKey(const Key('purchase-receipts-previous')));
      expect(repository.receiptPages.last.offset, 0);
      expect(repository.orderReads.last.$4.offset, 20);
    },
  );

  testWidgets('search/status selection uses server filters and resets paging', (
    tester,
  ) async {
    final repository = _PurchasesFake()..moreOrders = true;
    await _show(tester, repository);
    await _tap(tester, find.byKey(const Key('purchase-next')));
    await _reveal(tester, _field('Search supplier or order reference'));
    await tester.enterText(
      _field('Search supplier or order reference'),
      '  PO fixture  ',
    );
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pumpAndSettle();
    expect(repository.orderReads.last.$3, 'PO fixture');
    expect(repository.orderReads.last.$4.offset, 0);
    await _tap(
      tester,
      find.byType(DropdownButtonFormField<PurchaseOrderStatus>),
    );
    await _tap(tester, find.text('Partially received').last);
    expect(
      repository.orderReads.last.$2,
      PurchaseOrderStatus.partiallyReceived,
    );
    expect(repository.orderReads.last.$1, purchaseBranch);
  });

  testWidgets(
    'unconfirmed delivery freezes request across editing and branch switch',
    (tester) async {
      final repository = _PurchasesFake()
        ..writeError = const RepositoryFailure(
          RepositoryFailureType.unavailable,
          'Delivery outcome unknown.',
        );
      await _show(tester, repository, size: const Size(320, 900));
      await _openOrder(tester);
      await _tap(tester, find.byKey(const Key('purchase-receive')));
      await _fillReceive(tester);
      await _tap(tester, find.text('Confirm physical receipt'));
      final original = repository.receives.single;
      await _reveal(tester, find.textContaining('result is unconfirmed'));
      expect(find.text('Request: ${original.requestId}'), findsOneWidget);
      await _reveal(tester, find.byKey(const Key('purchase-create')));
      expect(
        tester
            .widget<FilledButton>(find.byKey(const Key('purchase-create')))
            .onPressed,
        isNull,
      );
      await tester.enterText(
        _field('Search supplier or order reference'),
        'Changed search',
      );
      await _tap(tester, find.byType(DropdownButtonFormField<String>));
      await _tap(tester, find.text('Second branch').last);
      expect(repository.contextBranches.last, _otherBranch);
      repository.writeError = null;
      await _tap(tester, find.text('Retry original purchase request'));
      expect(repository.receives, hasLength(2));
      expect(
        identical(repository.receives.first, repository.receives.last),
        isTrue,
      );
      expect(repository.receives.last.requestId, original.requestId);
      expect(repository.receives.last.branchId, purchaseBranch);
      expect(repository.receives.last.reason, 'Counted delivery');
      expect(find.textContaining('result is unconfirmed'), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'local auth denial preserves an earlier unknown delivery until original retry succeeds',
    (tester) async {
      final repository = _PurchasesFake()
        ..writeError = const RepositoryFailure(
          RepositoryFailureType.unavailable,
          'Delivery outcome unknown.',
        );
      await _show(tester, repository, size: const Size(320, 900));
      await _openOrder(tester);
      await _tap(tester, find.byKey(const Key('purchase-receive')));
      await _fillReceive(tester);
      await _tap(tester, find.text('Confirm physical receipt'));
      final original = repository.receives.single;

      repository.writeError = const RepositoryFailure(
        RepositoryFailureType.unauthenticated,
        'Sign in again before retrying.',
      );
      repository.readError = const RepositoryFailure(
        RepositoryFailureType.unauthenticated,
        'This session cannot load purchase context.',
      );
      await _tap(tester, find.text('Retry original purchase request'));
      await _reveal(tester, find.text('Request: ${original.requestId}'));
      expect(find.text('Request: ${original.requestId}'), findsOneWidget);
      expect(find.text('Retry original purchase request'), findsOneWidget);
      expect(repository.receives.last, same(original));
      expect(find.textContaining('confirmed by the server.'), findsNothing);

      repository.writeError = null;
      repository.readError = null;
      await _tap(tester, find.text('Refresh'));
      await _reveal(tester, find.byKey(const Key('purchase-create')));
      expect(
        tester
            .widget<FilledButton>(find.byKey(const Key('purchase-create')))
            .onPressed,
        isNull,
      );
      await _tap(tester, find.text('Retry original purchase request'));
      expect(repository.receives, hasLength(3));
      expect(
        repository.receives.every((request) => identical(request, original)),
        isTrue,
      );
      expect(repository.receives.last.requestId, original.requestId);
      expect(repository.receives.last.items.single.quantity, 1);
      expect(repository.receives.last.reason, 'Counted delivery');
      expect(find.text('Request: ${original.requestId}'), findsNothing);
      await _reveal(tester, find.byKey(const Key('purchase-create')));
      expect(
        tester
            .widget<FilledButton>(find.byKey(const Key('purchase-create')))
            .onPressed,
        isNotNull,
      );
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'persisted unknown intent blocks replacement and retries saved UUID',
    (tester) async {
      final pending = PendingOperation(
        requestId: purchaseRequest,
        organizationId: purchaseOrg,
        branchId: purchaseBranch,
        actorId: purchaseActor,
        type: 'receive_purchase_order',
        payload: {
          'p_order_id': purchaseOrderId,
          'p_items': [
            {'quantity': 1},
          ],
        },
        createdAt: DateTime.utc(2026, 10, 11),
        status: LocalOperationStatus.pending,
        attemptCount: 1,
      );
      final repository = _PurchasesFake()..pending = [pending];
      await _show(tester, repository, size: const Size(320, 900));
      expect(find.text('Request: $purchaseRequest'), findsOneWidget);
      await _reveal(tester, find.byKey(const Key('purchase-create')));
      expect(
        tester
            .widget<FilledButton>(find.byKey(const Key('purchase-create')))
            .onPressed,
        isNull,
      );
      await _openOrder(tester);
      await _reveal(tester, find.byKey(const Key('purchase-receive')));
      expect(
        tester
            .widget<FilledButton>(find.byKey(const Key('purchase-receive')))
            .onPressed,
        isNull,
      );
      await _tap(
        tester,
        find.byKey(const Key('pending-retry-$purchaseRequest')),
      );
      expect(repository.retries.single, same(pending));
      expect(repository.receives, isEmpty);
      expect(repository.creates, isEmpty);
      expect(find.text('Request: $purchaseRequest'), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );

  for (final change in ['actor repository', 'same repository generation']) {
    testWidgets('cancellation dialog cannot submit after $change changes', (
      tester,
    ) async {
      final old = _PurchasesFake()..order = purchaseFixtureOrder(received: 1);
      final oldPeople = _PeopleFake();
      final catalog = _CatalogFake();
      await _show(tester, old, people: oldPeople, catalog: catalog);
      await _openOrder(tester);
      await _tap(tester, find.byKey(const Key('purchase-cancel')));
      await tester.enterText(
        _field('Cancellation reason'),
        'Supplier discontinued',
      );
      final replacement = change == 'actor repository' ? _PurchasesFake() : old;
      final newPeople = _PeopleFake()..branches = [_branches.last];
      await tester.pumpWidget(_app(replacement, newPeople, catalog));
      await tester.pumpAndSettle();
      expect(find.text('Cancel remaining quantities'), findsOneWidget);
      await _tap(tester, find.text('Cancel remaining'));
      expect(old.cancellations, isEmpty);
      expect(replacement.cancellations, isEmpty);
      expect(
        find.text('Remaining quantity cancellation confirmed by the server.'),
        findsNothing,
      );
      expect(replacement.contextBranches.last, _otherBranch);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('late old actor order load cannot replace new branch results', (
    tester,
  ) async {
    final old = _PurchasesFake()
      ..listCompleter = Completer<DataPage<PurchaseOrderSummary>>();
    final catalog = _CatalogFake();
    await _show(tester, old, catalog: catalog, settle: false);
    await tester.pump();
    expect(old.orderReads, hasLength(1));
    final replacement = _PurchasesFake()..empty = true;
    await tester.pumpWidget(
      _app(replacement, _PeopleFake()..branches = [_branches.last], catalog),
    );
    await tester.pumpAndSettle();
    old.listCompleter!.complete(
      DataPage(items: [old.order.summary], hasMore: false, offset: 0),
    );
    await tester.pumpAndSettle();
    expect(find.text('Fixture supplier'), findsNothing);
    expect(find.text('Second branch'), findsOneWidget);
    expect(
      find.text('No purchase orders match this branch and search.'),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('late order detail disappears after account replacement', (
    tester,
  ) async {
    final old = _PurchasesFake()..detailCompleter = Completer<PurchaseOrder>();
    final catalog = _CatalogFake();
    await _show(tester, old, catalog: catalog);
    await _reveal(
      tester,
      find.byKey(const Key('purchase-open-$purchaseOrderId')),
    );
    await tester.tap(find.byKey(const Key('purchase-open-$purchaseOrderId')));
    await tester.pump();
    final replacement = _PurchasesFake()..empty = true;
    await tester.pumpWidget(_app(replacement, _PeopleFake(), catalog));
    await tester.pumpAndSettle();
    old.detailCompleter!.complete(purchaseFixtureOrder(received: 1));
    await tester.pumpAndSettle();
    expect(find.text('Order details · Fixture supplier'), findsNothing);
    expect(old.receiptPages, isEmpty);
    expect(
      find.text('No purchase orders match this branch and search.'),
      findsOneWidget,
    );
  });

  testWidgets(
    'receipt details from an old account never open after replacement',
    (tester) async {
      final old = _PurchasesFake()
        ..order = purchaseFixtureOrder(received: 1)
        ..receiptCompleter = Completer<PurchaseReceipt>();
      final catalog = _CatalogFake();
      await _show(tester, old, catalog: catalog);
      await _openOrder(tester);
      await _tap(tester, find.textContaining('Delivery fixture'));
      expect(old.receiptReads, [purchaseReceiptId]);
      expect(find.text('Confirmed delivery receipt'), findsNothing);
      final replacement = _PurchasesFake()..empty = true;
      await tester.pumpWidget(_app(replacement, _PeopleFake(), catalog));
      await tester.pumpAndSettle();
      old.receiptCompleter!.complete(purchaseReceipt(purchaseReceiptWire()));
      await tester.pumpAndSettle();
      expect(find.text('Confirmed delivery receipt'), findsNothing);
      expect(find.textContaining('Stock balance after:'), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('physical receipt waits for authoritative response', (
    tester,
  ) async {
    final repository = _PurchasesFake()
      ..receiveCompleter = Completer<PurchaseMutationResult>();
    await _show(tester, repository);
    await _openOrder(tester);
    await _tap(tester, find.byKey(const Key('purchase-receive')));
    await _fillReceive(tester);
    await _tap(tester, find.text('Confirm physical receipt'));
    expect(repository.receives, hasLength(1));
    expect(
      find.text('Physical stock receipt confirmed by the server.'),
      findsNothing,
    );
    expect(
      tester
          .widget<FilledButton>(find.byKey(const Key('purchase-receive')))
          .onPressed,
      isNull,
    );
    repository.order = purchaseFixtureOrder(received: 1);
    repository.receiveCompleter!.complete(
      repository._result(
        repository.receives.single.requestId,
        'purchase.receive',
      ),
    );
    await tester.pumpAndSettle();
    await _reveal(
      tester,
      find.text('Physical stock receipt confirmed by the server.'),
    );
    expect(
      find.text('Physical stock receipt confirmed by the server.'),
      findsOneWidget,
    );
    expect(find.textContaining('result is unconfirmed'), findsNothing);
  });

  testWidgets(
    'old actor mutation completion cannot claim success for new actor',
    (tester) async {
      final old = _PurchasesFake()
        ..receiveCompleter = Completer<PurchaseMutationResult>();
      final catalog = _CatalogFake();
      await _show(tester, old, catalog: catalog);
      await _openOrder(tester);
      await _tap(tester, find.byKey(const Key('purchase-receive')));
      await _fillReceive(tester);
      await _tap(tester, find.text('Confirm physical receipt'));
      final replacement = _PurchasesFake()..empty = true;
      await tester.pumpWidget(
        _app(replacement, _PeopleFake()..branches = [_branches.last], catalog),
      );
      await tester.pumpAndSettle();
      old.receiveCompleter!.complete(
        old._result(old.receives.single.requestId, 'purchase.receive'),
      );
      await tester.pumpAndSettle();
      expect(
        find.text('Physical stock receipt confirmed by the server.'),
        findsNothing,
      );
      expect(replacement.receives, isEmpty);
      expect(find.text('Second branch'), findsOneWidget);
      expect(
        find.text('No purchase orders match this branch and search.'),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
    },
  );
}

Widget _app(
  _PurchasesFake repository,
  _PeopleFake people,
  _CatalogFake catalog, {
  bool preview = false,
  AppRole role = AppRole.owner,
}) => MaterialApp(
  home: Scaffold(
    body: PurchasesPage(
      repository: repository,
      peopleRepository: people,
      catalogRepository: catalog,
      role: role,
      isPreview: preview,
    ),
  ),
);

Future<void> _show(
  WidgetTester tester,
  _PurchasesFake repository, {
  _PeopleFake? people,
  _CatalogFake? catalog,
  bool preview = false,
  AppRole role = AppRole.owner,
  Size size = const Size(1280, 1100),
  bool settle = true,
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(
    _app(
      repository,
      people ?? _PeopleFake(),
      catalog ?? _CatalogFake(),
      preview: preview,
      role: role,
    ),
  );
  if (settle) await tester.pumpAndSettle();
}

Finder _field(String label) => find.byWidgetPredicate(
  (widget) => widget is TextField && widget.decoration?.labelText == label,
);

Future<void> _reveal(WidgetTester tester, Finder finder) async {
  if (finder.evaluate().isEmpty) {
    tester
        .state<ScrollableState>(find.byType(Scrollable).first)
        .position
        .jumpTo(0);
    await _pump(tester);
    await tester.scrollUntilVisible(
      finder,
      350,
      scrollable: find.byType(Scrollable).first,
      maxScrolls: 35,
    );
  } else {
    await tester.ensureVisible(finder);
  }
  await _pump(tester);
}

Future<void> _tap(WidgetTester tester, Finder finder) async {
  await _reveal(tester, finder);
  await tester.tap(finder);
  await _pump(tester);
}

Future<void> _pump(WidgetTester tester) async {
  // Receipt inspection keeps its loading indicator active until the dialog
  // closes, so advance route animations without waiting for that indicator.
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 350));
  await tester.pump();
}

Future<void> _openOrder(WidgetTester tester) =>
    _tap(tester, find.byKey(const Key('purchase-open-$purchaseOrderId')));

Future<void> _fillReceive(
  WidgetTester tester, {
  String quantity = '1',
  bool reviewed = true,
}) async {
  await _reveal(
    tester,
    find.byKey(const Key('purchase-receive-quantity-$purchaseOrderItem')),
  );
  await tester.enterText(
    find.byKey(const Key('purchase-receive-quantity-$purchaseOrderItem')),
    quantity,
  );
  if (reviewed) {
    await _tap(tester, find.text('I reviewed this current catalog product.'));
  }
  await _reveal(tester, _field('Receiving reason'));
  await tester.enterText(_field('Receiving reason'), 'Counted delivery');
  await _tap(
    tester,
    find.text(
      'I counted and physically received these goods. I will not record this delivery twice.',
    ),
  );
}

class _PurchasesFake implements PurchaseRepository {
  PurchaseOrder order = purchaseFixtureOrder();
  bool empty = false, moreOrders = false, moreReceipts = false;
  Object? readError, writeError;
  Completer<DataPage<PurchaseOrderSummary>>? listCompleter;
  Completer<PurchaseOrder>? detailCompleter;
  Completer<PurchaseReceipt>? receiptCompleter;
  Completer<PurchaseMutationResult>? receiveCompleter;
  List<PendingOperation> pending = [];
  final contextBranches = <String>[];
  final orderReads = <(String, PurchaseOrderStatus?, String, PageRequest)>[];
  final receiptPages = <PageRequest>[];
  final receiptReads = <String>[];
  final creates = <CreatePurchaseRequest>[];
  final receives = <ReceivePurchaseRequest>[];
  final cancellations = <CancelPurchaseRequest>[];
  final retries = <PendingOperation>[];

  @override
  Future<PurchaseContext> context(String branchId) async {
    contextBranches.add(branchId);
    if (readError != null) throw readError!;
    return PurchaseContext(
      organizationId: purchaseOrg,
      branchId: branchId,
      branchName: branchId == purchaseBranch
          ? 'Fixture branch'
          : 'Second branch',
      currency: 'PHP',
      settingsRevision: 4,
    );
  }

  @override
  Future<DataPage<PurchaseOrderSummary>> listOrders({
    required String branchId,
    PurchaseOrderStatus? status,
    String query = '',
    PageRequest page = const PageRequest(),
  }) async {
    orderReads.add((branchId, status, query, page));
    if (readError != null) throw readError!;
    if (listCompleter != null) return listCompleter!.future;
    return DataPage(
      items: empty || branchId != purchaseBranch ? [] : [order.summary],
      hasMore: moreOrders && page.offset == 0,
      offset: page.offset,
    );
  }

  @override
  Future<PurchaseOrder> getOrder({
    required String branchId,
    required String orderId,
  }) async => detailCompleter?.future ?? Future.value(order);

  @override
  Future<DataPage<PurchaseReceiptSummary>> listReceipts({
    required String branchId,
    required String orderId,
    PageRequest page = const PageRequest(),
  }) async {
    expect(branchId, purchaseBranch);
    expect(orderId, purchaseOrderId);
    receiptPages.add(page);
    return DataPage(
      items: order.receiptCount == 0
          ? []
          : [purchaseReceipt(purchaseReceiptWire()).summary],
      hasMore: moreReceipts && page.offset == 0,
      offset: page.offset,
    );
  }

  @override
  Future<PurchaseReceipt> getReceipt({
    required String branchId,
    required String receiptId,
  }) async {
    expect(branchId, purchaseBranch);
    receiptReads.add(receiptId);
    if (receiptCompleter != null) return receiptCompleter!.future;
    return purchaseReceipt(purchaseReceiptWire());
  }

  @override
  Future<PurchaseMutationResult> create(CreatePurchaseRequest request) async {
    creates.add(request);
    if (writeError != null) throw writeError!;
    return _result(request.requestId, 'purchase.create');
  }

  @override
  Future<PurchaseMutationResult> receive(ReceivePurchaseRequest request) async {
    receives.add(request);
    if (writeError != null) throw writeError!;
    if (receiveCompleter != null) return receiveCompleter!.future;
    order = purchaseFixtureOrder(received: request.items.single.quantity);
    return _result(request.requestId, 'purchase.receive');
  }

  @override
  Future<PurchaseMutationResult> cancelRemaining(
    CancelPurchaseRequest request,
  ) async {
    cancellations.add(request);
    if (writeError != null) throw writeError!;
    order = purchaseFixtureOrder(received: 1, cancelled: true);
    return _result(request.requestId, 'purchase.cancel_remaining');
  }

  @override
  Future<List<PendingOperation>> pendingMutations({String? branchId}) async =>
      pending;

  @override
  Future<PurchaseMutationResult> retryPending(
    PendingOperation operation,
  ) async {
    retries.add(operation);
    pending = [];
    return _result(operation.requestId, 'purchase.receive');
  }

  PurchaseMutationResult _result(String requestId, String kind) =>
      PurchaseMutationResult(
        requestId: requestId,
        kind: kind,
        orderId: purchaseOrderId,
        orderRevision: order.summary.revision,
      );
}

class _PeopleFake implements PeopleRepository {
  List<BranchOption> branches = _branches;
  int branchReads = 0;
  final supplierReads = <(String?, bool?, PageRequest)>[];
  @override
  Future<List<BranchOption>> listBranches() async {
    branchReads++;
    return branches;
  }

  @override
  Future<DataPage<Supplier>> listSuppliers({
    String query = '',
    bool? active,
    String? branchId,
    PageRequest page = const PageRequest(),
  }) async {
    supplierReads.add((branchId, active, page));
    return DataPage(items: [_supplier], hasMore: false, offset: page.offset);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _CatalogFake implements CatalogRepository {
  final searches = <(ProductFilter, PageRequest)>[];
  @override
  Future<DataPage<Product>> searchProducts({
    ProductFilter filter = const ProductFilter(),
    PageRequest page = const PageRequest(),
  }) async {
    searches.add((filter, page));
    return DataPage(items: [_product], hasMore: false, offset: page.offset);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
