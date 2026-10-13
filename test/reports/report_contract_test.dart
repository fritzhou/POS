import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:nexapos/features/catalog/domain/repository_support.dart';
import 'package:nexapos/features/reports/data/report_decoders.dart';
import 'package:nexapos/features/reports/domain/report_csv.dart';
import 'package:nexapos/features/reports/domain/report_models.dart';

import 'report_fixtures.dart';

SalesReport _sales(Map<String, dynamic> wire, {ReportWindow? window}) =>
    salesReportFromRow(
      wire,
      organizationId: reportOrg,
      branchId: reportBranch,
      window: window ?? reportWindow,
      shiftId: null,
    );

ExpenseReport _expenses(Map<String, dynamic> wire) => expenseReportFromRow(
  wire,
  organizationId: reportOrg,
  branchId: reportBranch,
  window: reportWindow,
);

InventoryReport _inventory(Map<String, dynamic> wire, {PageRequest? page}) =>
    inventoryReportFromRow(
      wire,
      organizationId: reportOrg,
      branchId: reportBranch,
      query: '',
      page: page ?? const PageRequest(),
    );

void main() {
  test(
    'inclusive UTC dates use next midnight and validate calendar/window',
    () {
      final window = ReportWindow.inclusiveUtcDates(
        DateTime(2026, 10, 1, 18),
        DateTime(2026, 10, 3, 12),
      );
      expect(window.from, DateTime.utc(2026, 10, 1));
      expect(window.to, DateTime.utc(2026, 10, 4));
      expect(reportDate(window.inclusiveLastDate), '2026-10-03');
      expect(
        () => ReportWindow.fromDateText('2026-02-30', '2026-03-01'),
        throwsA(isA<RepositoryFailure>()),
      );
      expect(
        () => ReportWindow.fromDateText('2026-10-04', '2026-10-03'),
        throwsA(isA<RepositoryFailure>()),
      );
      expect(
        () => ReportWindow(from: DateTime(2026), to: DateTime(2026, 2)),
        throwsA(isA<RepositoryFailure>()),
      );
      expect(
        () => ReportWindow(
          from: DateTime.utc(2026),
          to: DateTime.utc(2027, 1, 3),
        ),
        throwsA(isA<RepositoryFailure>()),
      );
    },
  );

  test(
    'posted split tenders sum once; independent refunds and voids go negative',
    () {
      final report = decodedSales();
      expect(report.currencies.single.totals.salesTotalMinor, 1120);
      expect(report.currencies.single.payments.length, 2);
      final reversed = decodedSales(reversalOnly: true).currencies.single;
      expect(reversed.totals.saleCount, 0);
      expect(reversed.totals.refundTotalMinor, 500);
      expect(reversed.totals.voidTotalMinor, 620);
      expect(reversed.totals.netSalesMinor, -1120);
      expect(reversed.payments.last.netMinor, -700);
    },
  );

  test('historical currencies remain separate and report lists immutable', () {
    final wire = salesReportWire();
    (wire['currencies'] as List).add(salesCurrencyWire(currency: 'USD'));
    final report = _sales(wire);
    expect(report.currencies.map((group) => group.currency), ['PHP', 'USD']);
    expect(() => report.currencies.clear(), throwsUnsupportedError);
    expect(() => report.currencies.first.daily.clear(), throwsUnsupportedError);
    expect(
      () => report.currencies.first.payments.clear(),
      throwsUnsupportedError,
    );
    expect(decodedSales(empty: true).currencies, isEmpty);
    expect(decodedExpenses(empty: true).currencies, isEmpty);
  });

  final salesFailures = <String, void Function(Map<String, dynamic>)>{
    'foreign organization': (wire) => wire['organization_id'] = reportProduct,
    'foreign branch': (wire) => wire['branch_id'] = reportOtherBranch,
    'unposted source': (wire) => wire['source'] = 'device_pending',
    'different window': (wire) => wire['from'] = '2026-09-01T00:00:00Z',
    'different shift': (wire) => wire['shift_id'] = reportShift,
    'non UTC timestamp': (wire) =>
        wire['generated_at'] = '2026-10-12T01:00:00+01:00',
    'invalid calendar timestamp': (wire) =>
        wire['generated_at'] = '2026-02-30T00:00:00Z',
    'unsupported currency': (wire) => wire['currencies'][0]['currency'] = 'JPY',
    'string money': (wire) =>
        wire['currencies'][0]['sales_total_minor'] = '1120',
    'float money': (wire) =>
        wire['currencies'][0]['sales_total_minor'] = 1120.0,
    'unsafe money': (wire) =>
        wire['currencies'][0]['sales_total_minor'] = 9007199254740992,
    'negative original money': (wire) =>
        wire['currencies'][0]['sales_tax_minor'] = -1,
    'wrong sale arithmetic': (wire) =>
        wire['currencies'][0]['sales_total_minor'] = 1121,
    'wrong reversal arithmetic': (wire) =>
        wire['currencies'][0]['refund_total_minor'] = 501,
    'payment fanout': (wire) {
      wire['currencies'][0]['payments'][1]['sales_minor'] = 1120;
      wire['currencies'][0]['payments'][1]['net_minor'] = 420;
    },
    'unknown tender': (wire) =>
        wire['currencies'][0]['payments'][0]['method'] = 'provider_paid',
    'duplicate tender': (wire) =>
        wire['currencies'][0]['payments'][1]['method'] = 'cash',
    'wrong daily sum': (wire) =>
        wire['currencies'][0]['daily'][0]['sale_count'] = 2,
    'day outside half open window': (wire) =>
        wire['currencies'][0]['daily'][0]['date'] = '2026-10-04',
    'duplicate day': (wire) {
      final days = wire['currencies'][0]['daily'] as List;
      days.add(cloneReportWire(days.first as Map<String, dynamic>));
    },
    'duplicate currency': (wire) =>
        (wire['currencies'] as List).add(salesCurrencyWire()),
  };
  for (final entry in salesFailures.entries) {
    test('sales decoder rejects ${entry.key}', () {
      final wire = cloneReportWire(salesReportWire());
      entry.value(wire);
      expect(() => _sales(wire), throwsFormatException);
    });
  }

  test(
    'exact BigInt sums reject aggregate overflow even when rows are safe',
    () {
      final wire = salesReportWire();
      final group = wire['currencies'][0] as Map<String, dynamic>;
      group.addAll({
        'sales_subtotal_minor': reportExactMaximum,
        'sales_discount_minor': 0,
        'sales_tax_minor': 1,
        'sales_total_minor': reportExactMaximum,
        'net_sales_minor': reportExactMaximum - 1120,
      });
      expect(() => _sales(wire), throwsFormatException);
      // Each tender is valid by itself; their sum is beyond the exact bound.
      final paymentWire = salesReportWire();
      final payments = paymentWire['currencies'][0]['payments'] as List;
      payments[0]['sales_minor'] = reportExactMaximum;
      payments[0]['net_minor'] = reportExactMaximum - 420;
      payments[1]['sales_minor'] = 1;
      payments[1]['net_minor'] = -699;
      expect(() => _sales(paymentWire), throwsFormatException);
    },
  );

  test(
    '366 day arbitrary window permits 367 intersecting UTC daily groups',
    () {
      final from = DateTime.utc(2025, 1, 1, 12);
      final window = ReportWindow(
        from: from,
        to: from.add(const Duration(days: 366)),
      );
      final wire = salesReportWire();
      wire['from'] = window.from.toIso8601String();
      wire['to'] = window.to.toIso8601String();
      final totals = <String, dynamic>{
        'sale_count': 1,
        'sales_subtotal_minor': 1,
        'sales_discount_minor': 0,
        'sales_tax_minor': 0,
        'sales_total_minor': 1,
        'reversal_count': 0,
        'refund_total_minor': 0,
        'void_total_minor': 0,
        'reversal_total_minor': 0,
        'net_sales_minor': 1,
      };
      wire['currencies'] = [
        {
          'currency': 'PHP',
          for (final entry in totals.entries) entry.key: entry.value * 367,
          'payments': [
            {
              'method': 'cash',
              'sales_minor': 367,
              'reversed_minor': 0,
              'net_minor': 367,
            },
          ],
          'daily': [
            for (var day = 0; day <= 366; day++)
              {
                'date': reportDate(DateTime.utc(2025).add(Duration(days: day))),
                ...totals,
              },
          ],
        },
      ];
      expect(_sales(wire, window: window).currencies.single.daily.length, 367);
    },
  );

  test(
    'inventory shows actual deficits, inactive stock, no movement and decimal reorder',
    () {
      final wire = inventoryReportWire();
      wire.addAll({
        'catalog_product_count': 3,
        'stocked_product_count': 1,
        'low_stock_product_count': 2,
      });
      wire['items'] = [
        inventoryItemWire(),
        inventoryItemWire(product: reportShift, quantity: 4, active: false),
        inventoryItemWire(
          product: reportOtherBranch,
          quantity: 0,
          movement: false,
        ),
      ];
      final items = _inventory(wire).items.items;
      expect(items.first.quantity, -2);
      expect(items.first.reorderLevel, '1.2500');
      expect(items[1].active, isFalse);
      expect(items[1].isLowStock, isFalse);
      expect(items.last.hasMovement, isFalse);
      expect(items.last.stockRevision, 0);
      expect(
        () => _inventory(inventoryReportWire(empty: true)).items.items.clear(),
        throwsUnsupportedError,
      );
    },
  );

  test('catalog text bounds match names160 SKU64 and unit32', () {
    final wire = inventoryReportWire();
    wire['items'][0].addAll({
      'name': 'n' * 160,
      'sku': 's' * 64,
      'unit': 'u' * 32,
    });
    expect(_inventory(wire).items.items.single.name.length, 160);
    for (final (key, length) in [('name', 161), ('sku', 65), ('unit', 33)]) {
      final invalid = cloneReportWire(wire);
      invalid['items'][0][key] = 'x' * length;
      expect(() => _inventory(invalid), throwsFormatException);
    }
  });

  final inventoryFailures = <String, void Function(Map<String, dynamic>)>{
    'query mismatch': (wire) => wire['query'] = 'other',
    'offset mismatch': (wire) => wire['offset'] = 1,
    'limit mismatch': (wire) => wire['limit'] = 50,
    'incomplete page': (wire) => wire['catalog_product_count'] = 2,
    'contradictory counters': (wire) => wire['stocked_product_count'] = 1,
    'page contradicts deficit count': (wire) =>
        wire['deficit_product_count'] = 0,
    'full page contradicts low count': (wire) {
      wire['items'][0]['active'] = false;
      wire['items'][0]['is_low_stock'] = false;
    },
    'negative stock not flagged': (wire) =>
        wire['items'][0]['is_deficit'] = false,
    'missing movement revision': (wire) =>
        wire['items'][0]['stock_revision'] = 0,
    'no movement but nonzero quantity': (wire) {
      wire['items'][0]['stock_revision'] = 0;
      wire['items'][0]['has_movement'] = false;
    },
    'rounded reorder': (wire) => wire['items'][0]['reorder_level'] = 1.25,
    'too precise reorder': (wire) =>
        wire['items'][0]['reorder_level'] = '1.25001',
    'wrong low stock': (wire) => wire['items'][0]['is_low_stock'] = false,
    'unsafe quantity': (wire) =>
        wire['items'][0]['quantity'] = -9007199254740992,
  };
  for (final entry in inventoryFailures.entries) {
    test('inventory decoder rejects ${entry.key}', () {
      final wire = cloneReportWire(inventoryReportWire());
      entry.value(wire);
      expect(() => _inventory(wire), throwsFormatException);
    });
  }

  test(
    'inventory lookahead is validated but never exported as displayed data',
    () {
      final wire = inventoryReportWire(limit: 2);
      wire.addAll({
        'catalog_product_count': 2,
        'deficit_product_count': 2,
        'low_stock_product_count': 2,
      });
      (wire['items'] as List).add(
        inventoryItemWire(product: reportShift, name: 'Lookahead hidden'),
      );
      final report = _inventory(wire, page: const PageRequest(limit: 1));
      expect(report.items.hasMore, isTrue);
      expect(report.items.nextOffset, 1);
      expect(reportToCsv(report), isNot(contains('Lookahead hidden')));
      expect(reportToCsv(report), contains('additional_pages_available,true'));
    },
  );

  test(
    'independent expense reversals retain negative activity and source groups',
    () {
      final report = _expenses(expenseReportWire(reversalOnly: true));
      final group = report.currencies.single;
      expect(group.totals.expenseCount, 0);
      expect(group.totals.netExpenseMinor, -600);
      expect(group.sources.single.key, 'external');
      expect(group.categories.single.key, 'rent');
      expect(reportToCsv(report), contains('PHP,total,,0,0,1,600,-600'));
    },
  );

  final expenseFailures = <String, void Function(Map<String, dynamic>)>{
    'wrong net': (wire) => wire['currencies'][0]['net_expense_minor'] = 100,
    'category fanout': (wire) =>
        wire['currencies'][0]['categories'][0]['expense_count'] = 2,
    'unsupported category': (wire) =>
        wire['currencies'][0]['categories'][0]['category'] = 'profit',
    'unsupported source': (wire) =>
        wire['currencies'][0]['sources'][0]['source'] = 'provider',
    'missing source': (wire) => wire['currencies'][0]['sources'] = <Object>[],
    'unsafe reversal': (wire) =>
        wire['currencies'][0]['reversal_total_minor'] = 9007199254740992,
    'wrong daily': (wire) =>
        wire['currencies'][0]['daily'][0]['net_expense_minor'] = 0,
  };
  for (final entry in expenseFailures.entries) {
    test('expense decoder rejects ${entry.key}', () {
      final wire = cloneReportWire(expenseReportWire());
      entry.value(wire);
      expect(() => _expenses(wire), throwsFormatException);
    });
  }

  test(
    'CSV preserves scope UTC currency and numeric sign while escaping text formulae',
    () {
      expect(reportCsvCell('=SUM(A1)'), "'=SUM(A1)");
      expect(reportCsvCell('  +123'), "'  +123");
      expect(reportCsvCell('-product'), "'-product");
      expect(reportCsvCell('@command'), "'@command");
      expect(reportCsvCell('\tformula'), "'\tformula");
      expect(reportCsvCell('A, "quoted"\nline'), '"A, ""quoted""\nline"');
      expect(reportCsvCell(-600), '-600');
      final csv = reportToCsv(decodedSales(reversalOnly: true));
      expect(csv, contains('organization_id,$reportOrg\r\n'));
      expect(csv, contains('branch_id,$reportBranch\r\n'));
      expect(csv, contains('source,server_posted\r\n'));
      expect(
        csv,
        contains('activity_to_utc_exclusive,2026-10-04T00:00:00.000Z'),
      );
      expect(csv, contains('PHP,card,0,700,-700'));
      expect(csv, isNot(contains('profit')));
      expect(csv, isNot(contains('net_tax')));
    },
  );

  test(
    'actual isolated PostgreSQL report fixture decodes without schema guesses',
    () {
      final fixture =
          jsonDecode(
                File(
                  'test/fixtures/reports_sql_contract.json',
                ).readAsStringSync(),
              )
              as Map<String, dynamic>;
      ReportWindow window(Map<String, dynamic> row) => ReportWindow(
        from: DateTime.parse(row['from'] as String).toUtc(),
        to: DateTime.parse(row['to'] as String).toUtc(),
      );
      final salesRow = fixture['sales'] as Map<String, dynamic>;
      final sales = salesReportFromRow(
        salesRow,
        organizationId: salesRow['organization_id'] as String,
        branchId: salesRow['branch_id'] as String,
        window: window(salesRow),
        shiftId: salesRow['shift_id'] as String?,
      );
      expect(sales.currencies.length, 2);
      expect(
        sales.currencies
            .firstWhere((group) => group.currency == 'PHP')
            .payments
            .length,
        greaterThan(1),
      );
      final inventoryRow = fixture['inventory'] as Map<String, dynamic>;
      final inventory = inventoryReportFromRow(
        inventoryRow,
        organizationId: inventoryRow['organization_id'] as String,
        branchId: inventoryRow['branch_id'] as String,
        query: inventoryRow['query'] as String,
        page: PageRequest(
          offset: inventoryRow['offset'] as int,
          limit: (inventoryRow['limit'] as int) - 1,
        ),
      );
      expect(inventory.items.items.any((item) => item.isDeficit), isTrue);
      expect(inventory.items.items.any((item) => !item.hasMovement), isTrue);
      final expenseRow = fixture['expenses'] as Map<String, dynamic>;
      final expenses = expenseReportFromRow(
        expenseRow,
        organizationId: expenseRow['organization_id'] as String,
        branchId: expenseRow['branch_id'] as String,
        window: window(expenseRow),
      );
      expect(
        expenses.currencies
            .firstWhere((group) => group.currency == 'PHP')
            .sources
            .map((source) => source.key),
        containsAll(['external', 'cash_drawer']),
      );
    },
  );
}
