import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nexapos/core/security/app_role.dart';
import 'package:nexapos/features/catalog/domain/repository_support.dart';
import 'package:nexapos/features/checkout/domain/checkout_models.dart';
import 'package:nexapos/features/checkout/domain/checkout_repository.dart';
import 'package:nexapos/features/reports/domain/report_models.dart';
import 'package:nexapos/features/reports/domain/reports_repository.dart';
import 'package:nexapos/features/reports/presentation/reports_page.dart';

import 'report_fixtures.dart';

class _Repository implements ReportsRepository {
  _Repository({this.branches = const {reportBranch}, this.empty = false});
  final Set<String> branches;
  final bool empty;
  final salesCalls = <({String branch, ReportWindow window, String? shift})>[];
  final stockCalls = <({String branch, String query, PageRequest page})>[];
  final expenseCalls = <ReportWindow>[];
  Future<SalesReport> Function(String, ReportWindow, String?)? salesHandler;
  Future<InventoryReport> Function(String, PageRequest)? inventoryHandler;
  Object? error;
  @override
  String get organizationId => reportOrg;
  @override
  Set<String> get branchIds => branches;
  @override
  Future<SalesReport> sales({
    required String branchId,
    required ReportWindow window,
    String? shiftId,
  }) async {
    salesCalls.add((branch: branchId, window: window, shift: shiftId));
    if (error != null) throw error!;
    if (salesHandler != null) return salesHandler!(branchId, window, shiftId);
    return decodedSales(
      branch: branchId,
      window: window,
      shift: shiftId,
      empty: empty,
      reversalOnly: true,
    );
  }

  @override
  Future<InventoryReport> inventory({
    required String branchId,
    String query = '',
    PageRequest page = const PageRequest(),
  }) async {
    stockCalls.add((branch: branchId, query: query, page: page));
    if (error != null) throw error!;
    if (inventoryHandler != null) return inventoryHandler!(branchId, page);
    return decodedInventory(query: query, page: page, empty: empty);
  }

  @override
  Future<ExpenseReport> expenses({
    required String branchId,
    required ReportWindow window,
  }) async {
    expenseCalls.add(window);
    if (error != null) throw error!;
    return decodedExpenses(window: window, empty: empty);
  }
}

class _Checkout implements CheckoutRepository {
  final calls = <({String? branch, PageRequest page})>[];
  Future<DataPage<Shift>> Function(String?, PageRequest)? handler;
  List<Shift> items = [];
  @override
  Future<DataPage<Shift>> listShifts({
    String? branchId,
    PageRequest page = const PageRequest(),
  }) async {
    calls.add((branch: branchId, page: page));
    if (handler != null) return handler!(branchId, page);
    return DataPage(items: items, hasMore: false, offset: page.offset);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

Shift _shift({
  String id = reportShift,
  String branch = reportBranch,
  String actor = reportActor,
  String org = reportOrg,
}) => Shift(
  id: id,
  organizationId: org,
  branchId: branch,
  actorUserId: actor,
  openedAt: DateTime.utc(2026, 10, 1),
  openingCashMinor: 0,
  expectedCashMinor: 0,
  currency: 'PHP',
);

Future<void> _pump(
  WidgetTester tester, {
  double width = 320,
  _Repository? repository,
  AppRole role = AppRole.owner,
  bool preview = false,
  _Checkout? checkout,
  String actor = reportActor,
}) async {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = Size(width, 1400);
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: ReportsPage(
          key: const Key('reports-page'),
          repository: repository,
          role: role,
          checkoutRepository: checkout,
          currentUserId: actor,
          isPreview: preview,
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

Future<void> _tap(WidgetTester tester, Finder finder) async {
  if (finder.evaluate().isEmpty) {
    final scroll = find.byType(Scrollable).first;
    tester.state<ScrollableState>(scroll).position.jumpTo(0);
    await tester.pumpAndSettle();
    if (finder.evaluate().isEmpty) {
      await tester.scrollUntilVisible(
        finder,
        700,
        scrollable: scroll,
        maxScrolls: 30,
      );
    }
  }
  await tester.ensureVisible(finder);
  await tester.pumpAndSettle();
  await tester.tap(finder);
  await tester.pumpAndSettle();
}

Future<void> _scrollAll(WidgetTester tester) async {
  final scroll = find.byType(Scrollable).first;
  for (var count = 0; count < 15; count++) {
    await tester.drag(scroll, const Offset(0, -700));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  }
}

void main() {
  for (final width in [320.0, 1280.0]) {
    testWidgets(
      'preview at ${width.toInt()}px has explanatory state and no invented metrics',
      (tester) async {
        final repository = _Repository();
        await _pump(
          tester,
          width: width,
          repository: repository,
          preview: true,
        );
        expect(
          find.text('Reports require a verified business account'),
          findsOneWidget,
        );
        expect(
          find.textContaining('preview contains no business metrics'),
          findsOneWidget,
        );
        expect(find.text('Posted sales'), findsNothing);
        expect(find.text('PHP 0.00'), findsNothing);
        expect(repository.salesCalls, isEmpty);
        expect(find.byKey(const Key('copy-report-csv')), findsNothing);
        expect(tester.takeException(), isNull);
      },
    );

    testWidgets(
      'authorized sales, expense and inventory data fit ${width.toInt()}px',
      (tester) async {
        final repository = _Repository();
        await _pump(tester, width: width, repository: repository);
        await _scrollAll(tester);
        expect(find.text('Net sales activity'), findsOneWidget);
        expect(find.text('PHP -11.20'), findsOneWidget);
        expect(
          find.text(
            'Original sales: subtotal PHP 0.00 · discounts PHP 0.00 · tax PHP 0.00',
          ),
          findsOneWidget,
        );
        await _tap(tester, find.byKey(const Key('report-kind-expenses')));
        await _scrollAll(tester);
        expect(find.text('Net expense activity'), findsOneWidget);
        expect(find.text('PHP -1.00'), findsOneWidget);
        await _tap(tester, find.byKey(const Key('report-kind-inventory')));
        await _scrollAll(tester);
        expect(find.text('Actual product'), findsOneWidget);
        expect(find.text('-2 each'), findsOneWidget);
        expect(find.text('Reorder level 1.2500 each'), findsOneWidget);
        expect(find.text('Stock deficit'), findsOneWidget);
        expect(tester.takeException(), isNull);
      },
    );

    testWidgets(
      'authorized empty and service error states fit ${width.toInt()}px',
      (tester) async {
        final repository = _Repository(empty: true);
        await _pump(tester, width: width, repository: repository);
        await _scrollAll(tester);
        expect(
          find.text('No posted sales or reversals in this window'),
          findsOneWidget,
        );
        await _tap(tester, find.byKey(const Key('report-kind-expenses')));
        await _scrollAll(tester);
        expect(
          find.text('No recorded expenses or reversals in this window'),
          findsOneWidget,
        );
        await _tap(tester, find.byKey(const Key('report-kind-inventory')));
        await _scrollAll(tester);
        expect(find.text('No matching current stock products'), findsOneWidget);
        repository.error = const RepositoryFailure(
          RepositoryFailureType.unavailable,
          'Server temporarily unavailable.',
        );
        await _tap(tester, find.byKey(const Key('run-report')));
        expect(find.text('Server temporarily unavailable.'), findsOneWidget);
        expect(find.byKey(const Key('copy-report-csv')), findsNothing);
        expect(tester.takeException(), isNull);
      },
    );
  }

  testWidgets(
    'inventory staff sees only current stock; cashier must explicitly select own scoped shift',
    (tester) async {
      final staff = _Repository();
      await _pump(tester, repository: staff, role: AppRole.inventoryStaff);
      expect(find.byKey(const Key('report-kind-inventory')), findsOneWidget);
      expect(find.byKey(const Key('report-kind-sales')), findsNothing);
      expect(find.byKey(const Key('report-kind-expenses')), findsNothing);
      expect(staff.stockCalls.length, 1);
      expect(staff.salesCalls, isEmpty);
      final cashier = _Repository();
      final checkout = _Checkout()
        ..items = [
          _shift(),
          _shift(id: reportProduct, actor: reportOtherBranch),
          _shift(id: reportOtherBranch, branch: reportOtherBranch),
          _shift(id: reportOrg, org: reportOtherBranch),
        ];
      await _pump(
        tester,
        repository: cashier,
        role: AppRole.cashier,
        checkout: checkout,
      );
      expect(cashier.salesCalls, isEmpty);
      expect(find.byKey(const Key('report-kind-inventory')), findsNothing);
      expect(find.byKey(const Key('report-kind-expenses')), findsNothing);
      final shiftFinder = find.byWidgetPredicate(
        (widget) =>
            widget is DropdownButtonFormField<String> &&
            widget.key == const ValueKey('report-own-shift-null'),
      );
      final dropdown = tester.widget<DropdownButton<String>>(
        find.descendant(
          of: shiftFinder,
          matching: find.byType(DropdownButton<String>),
        ),
      );
      expect(dropdown.items!.map((item) => item.value), [reportShift]);
      expect(
        tester
            .widget<FilledButton>(find.byKey(const Key('run-report')))
            .onPressed,
        isNull,
      );
      await _tap(tester, shiftFinder);
      await _tap(tester, find.textContaining('2026-10-01 · PHP · Open').last);
      await _tap(tester, find.byKey(const Key('run-report')));
      expect(cashier.salesCalls.single.shift, reportShift);
      expect(checkout.calls.single.branch, reportBranch);
      expect(find.textContaining('selected operation shift'), findsOneWidget);
    },
  );

  testWidgets(
    'UTC inclusive filter is sent exactly and edits discard the displayed export',
    (tester) async {
      final repository = _Repository();
      await _pump(tester, width: 1280, repository: repository);
      await tester.enterText(
        find.byKey(const Key('report-first-date')),
        '2026-10-01',
      );
      await tester.enterText(
        find.byKey(const Key('report-last-date')),
        '2026-10-03',
      );
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('copy-report-csv')), findsNothing);
      await _tap(tester, find.byKey(const Key('run-report')));
      expect(repository.salesCalls.last.window.from, DateTime.utc(2026, 10, 1));
      expect(repository.salesCalls.last.window.to, DateTime.utc(2026, 10, 4));
      await tester.enterText(
        find.byKey(const Key('report-last-date')),
        '2026-02-30',
      );
      await _tap(tester, find.byKey(const Key('run-report')));
      expect(find.text('Enter a valid UTC calendar date.'), findsOneWidget);
      expect(repository.salesCalls.length, 2);
    },
  );

  testWidgets(
    'account and recovery changes discard old in-flight report responses',
    (tester) async {
      final old = _Repository();
      final completion = Completer<SalesReport>();
      old.salesHandler = (_, _, _) => completion.future;
      // A pending future must not be pumped to settle.
      tester.view.physicalSize = const Size(1280, 1400);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      Widget page(
        _Repository repository, {
        bool preview = false,
        String actor = reportActor,
      }) => MaterialApp(
        home: Scaffold(
          body: ReportsPage(
            key: const Key('same-report-page'),
            repository: repository,
            role: AppRole.owner,
            currentUserId: actor,
            isPreview: preview,
          ),
        ),
      );
      await tester.pumpWidget(page(old));
      await tester.pump();
      final replacement = _Repository(empty: true);
      await tester.pumpWidget(page(replacement, actor: reportOtherBranch));
      await tester.pumpAndSettle();
      completion.complete(decodedSales());
      await tester.pumpAndSettle();
      expect(
        find.text('No posted sales or reversals in this window'),
        findsOneWidget,
      );
      expect(find.text('Net sales activity'), findsNothing);
      await tester.pumpWidget(page(replacement, preview: true));
      await tester.pumpAndSettle();
      expect(
        find.text('Reports require a verified business account'),
        findsOneWidget,
      );
      expect(find.byKey(const Key('copy-report-csv')), findsNothing);
    },
  );

  testWidgets(
    'branch can change during loading and old branch result cannot replace it',
    (tester) async {
      final repository = _Repository(
        branches: {reportBranch, reportOtherBranch},
      );
      final completion = Completer<SalesReport>();
      repository.salesHandler = (branch, window, shift) =>
          branch == reportBranch
          ? completion.future
          : Future.value(
              decodedSales(branch: branch, window: window, empty: true),
            );
      tester.view.physicalSize = const Size(1280, 1400);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ReportsPage(
              repository: repository,
              role: AppRole.owner,
              currentUserId: reportActor,
              isPreview: false,
            ),
          ),
        ),
      );
      await tester.pump();
      final branch = tester.widget<DropdownButtonFormField<String>>(
        find.byKey(const ValueKey('report-branch-$reportBranch')),
      );
      expect(branch.onChanged, isNotNull);
      branch.onChanged!(reportOtherBranch);
      await tester.pumpAndSettle();
      expect(repository.salesCalls.map((call) => call.branch), [
        reportBranch,
        reportOtherBranch,
      ]);
      completion.complete(decodedSales());
      await tester.pumpAndSettle();
      expect(find.text('Branch $reportOtherBranch'), findsOneWidget);
      expect(
        find.text('No posted sales or reversals in this window'),
        findsOneWidget,
      );
      expect(find.text('Net sales activity'), findsNothing);
    },
  );

  testWidgets('cashier shift paging cannot leak an earlier branch response', (
    tester,
  ) async {
    final repository = _Repository(branches: {reportBranch, reportOtherBranch});
    final checkout = _Checkout();
    final completion = Completer<DataPage<Shift>>();
    checkout.handler = (branch, page) => branch == reportBranch
        ? completion.future
        : Future.value(
            DataPage(
              items: [_shift(branch: reportOtherBranch, id: reportProduct)],
              hasMore: false,
              offset: 0,
            ),
          );
    tester.view.physicalSize = const Size(1280, 1400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ReportsPage(
            repository: repository,
            checkoutRepository: checkout,
            role: AppRole.cashier,
            currentUserId: reportActor,
            isPreview: false,
          ),
        ),
      ),
    );
    await tester.pump();
    final branch = tester.widget<DropdownButtonFormField<String>>(
      find.byKey(const ValueKey('report-branch-$reportBranch')),
    );
    branch.onChanged!(reportOtherBranch);
    await tester.pumpAndSettle();
    completion.complete(DataPage(items: [_shift()], hasMore: true, offset: 0));
    await tester.pumpAndSettle();
    final shifts = tester.widget<DropdownButton<String>>(
      find.descendant(
        of: find.byKey(const ValueKey('report-own-shift-null')),
        matching: find.byType(DropdownButton<String>),
      ),
    );
    expect(shifts.items!.map((item) => item.value), [reportProduct]);
    expect(find.text('Load more own shifts'), findsNothing);
    expect(repository.salesCalls, isEmpty);
  });

  testWidgets(
    'inventory paging changes displayed rows and CSV copies only authorized snapshot',
    (tester) async {
      final repository = _Repository();
      repository.inventoryHandler = (branch, page) async => InventoryReport(
        scope: ReportScope(
          organizationId: reportOrg,
          branchId: branch,
          generatedAt: DateTime.utc(2026, 10, 12),
        ),
        query: '',
        catalogProductCount: 21,
        stockedProductCount: 0,
        deficitProductCount: 21,
        lowStockProductCount: 21,
        items: DataPage(
          items: [
            for (
              var index = page.offset;
              index < (page.offset == 0 ? 20 : 21);
              index++
            )
              InventoryReportItem(
                productId:
                    '66666666-6666-6666-6666-${index.toString().padLeft(12, '0')}',
                name: 'Actual product $index',
                sku: 'SKU-$index',
                unit: 'each',
                active: true,
                reorderLevel: '1.2500',
                quantity: -2,
                stockRevision: 3,
                hasMovement: true,
                isDeficit: true,
                isLowStock: true,
              ),
          ],
          hasMore: page.offset == 0,
          offset: page.offset,
        ),
      );
      String? copied;
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        (call) async {
          if (call.method == 'Clipboard.setData') {
            copied = (call.arguments as Map)['text'] as String;
          }
          return null;
        },
      );
      addTearDown(
        () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          SystemChannels.platform,
          null,
        ),
      );
      await _pump(
        tester,
        width: 1280,
        repository: repository,
        role: AppRole.inventoryStaff,
      );
      await _tap(tester, find.byKey(const Key('report-stock-next')));
      expect(repository.stockCalls.last.page.offset, 20);
      await _tap(tester, find.byKey(const Key('copy-report-csv')));
      expect(copied, contains('branch_id,$reportBranch\r\n'));
      expect(copied, contains('displayed_page_offset,20\r\n'));
      expect(copied, contains('Actual product 20'));
      expect(copied, isNot(contains('Actual product 0,')));
      expect(copied, contains('source,server_posted\r\n'));
      expect(
        find.text('Displayed authorized report copied as CSV.'),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('daily UTC rows fit 320px at the exact maximum amount', (
    tester,
  ) async {
    final repository = _Repository();
    repository.salesHandler = (branch, window, shift) async {
      const totals = SalesTotals(
        saleCount: 1,
        salesSubtotalMinor: 9007199254740991,
        salesDiscountMinor: 0,
        salesTaxMinor: 0,
        salesTotalMinor: 9007199254740991,
        reversalCount: 0,
        refundTotalMinor: 0,
        voidTotalMinor: 0,
        reversalTotalMinor: 0,
        netSalesMinor: 9007199254740991,
      );
      return SalesReport(
        scope: ReportScope(
          organizationId: reportOrg,
          branchId: branch,
          generatedAt: DateTime.utc(2026, 10, 12),
        ),
        window: window,
        currencies: [
          SalesReportCurrency(
            currency: 'PHP',
            totals: totals,
            payments: [
              const ReportPaymentTotals(
                method: 'cash',
                salesMinor: 9007199254740991,
                reversedMinor: 0,
                netMinor: 9007199254740991,
              ),
            ],
            daily: [SalesReportDay(date: window.from, totals: totals)],
          ),
        ],
      );
    };
    await _pump(tester, repository: repository);
    await _tap(tester, find.text('Daily UTC activity'));
    await _scrollAll(tester);
    expect(
      find.text(reportDate(repository.salesCalls.single.window.from)),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'cashier loads additional own shift pages without automatic sales access',
    (tester) async {
      final repository = _Repository();
      final checkout = _Checkout();
      String shiftId(int index) =>
          '77777777-7777-7777-7777-${index.toString().padLeft(12, '0')}';
      checkout.handler = (_, page) async => DataPage(
        items: page.offset == 0
            ? [
                for (var index = 0; index < 20; index++)
                  _shift(id: shiftId(index)),
              ]
            : [_shift(id: shiftId(0)), _shift(id: shiftId(20))],
        hasMore: page.offset == 0,
        offset: page.offset,
      );
      await _pump(
        tester,
        width: 1280,
        repository: repository,
        role: AppRole.cashier,
        checkout: checkout,
      );
      expect(repository.salesCalls, isEmpty);
      await _tap(tester, find.text('Load more own shifts'));
      expect(checkout.calls.last.page.offset, 20);
      final formFinder = find.byKey(const ValueKey('report-own-shift-null'));
      final dropdown = tester.widget<DropdownButton<String>>(
        find.descendant(
          of: formFinder,
          matching: find.byType(DropdownButton<String>),
        ),
      );
      expect(dropdown.items!.length, 21);
      expect(dropdown.items!.map((item) => item.value).toSet().length, 21);
      tester.widget<DropdownButtonFormField<String>>(formFinder).onChanged!(
        shiftId(20),
      );
      await tester.pumpAndSettle();
      expect(repository.salesCalls, isEmpty);
      await _tap(tester, find.byKey(const Key('run-report')));
      expect(repository.salesCalls.single.shift, shiftId(20));
    },
  );
}
