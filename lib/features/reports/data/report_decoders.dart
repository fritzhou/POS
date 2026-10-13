import '../../catalog/domain/repository_support.dart';
import '../domain/report_models.dart';

const reportExactMaximum = 9007199254740991;
const reportCurrencies = {'PHP', 'USD', 'EUR', 'GBP', 'AUD', 'CAD', 'SGD'};
const reportPaymentMethods = {'cash', 'card', 'gcash', 'maya', 'other'};
const reportExpenseCategories = {
  'rent',
  'utilities',
  'wages',
  'transport',
  'maintenance',
  'fees',
  'other',
};
const reportExpenseSources = {'external', 'cash_drawer'};

Map<String, dynamic> reportRow(Object? value) {
  if (value is! Map<String, dynamic>) {
    throw const FormatException('Invalid report record');
  }
  return value;
}

List<Map<String, dynamic>> reportRows(Object? value, int maximum) {
  if (value is! List || value.length > maximum) {
    throw const FormatException('Invalid report record list');
  }
  return value.map(reportRow).toList(growable: false);
}

String _text(
  Map<String, dynamic> row,
  String key,
  int maximum, {
  int minimum = 1,
}) {
  final value = row[key];
  if (value is! String || value.length < minimum || value.length > maximum) {
    throw const FormatException('Invalid report text');
  }
  return value;
}

String _id(Map<String, dynamic> row, String key) {
  final value = _text(row, key, 36, minimum: 36);
  if (!RegExp(
    r'^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$',
  ).hasMatch(value)) {
    throw const FormatException('Invalid report ID');
  }
  return value.toLowerCase();
}

int _integer(Map<String, dynamic> row, String key, {bool signed = false}) {
  final value = row[key];
  if (value is! int ||
      value > reportExactMaximum ||
      value < (signed ? -reportExactMaximum : 0)) {
    throw const FormatException('Invalid exact report integer');
  }
  return value;
}

bool _boolean(Map<String, dynamic> row, String key) {
  final value = row[key];
  if (value is! bool) throw const FormatException('Invalid report boolean');
  return value;
}

DateTime _time(Map<String, dynamic> row, String key) {
  final text = _text(row, key, 32);
  if (!RegExp(
    r'^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}(?:\.\d{1,6})?(?:Z|\+00:00)$',
  ).hasMatch(text)) {
    throw const FormatException('UTC report time required');
  }
  final parsed = DateTime.tryParse(text);
  if (parsed == null ||
      reportDate(parsed) != text.substring(0, 10) ||
      parsed.hour.toString().padLeft(2, '0') != text.substring(11, 13) ||
      parsed.minute.toString().padLeft(2, '0') != text.substring(14, 16) ||
      parsed.second.toString().padLeft(2, '0') != text.substring(17, 19)) {
    throw const FormatException('Invalid report calendar');
  }
  return parsed.toUtc();
}

ReportScope _scope(Map<String, dynamic> row, String org, String branch) {
  if (_id(row, 'organization_id') != org.toLowerCase() ||
      _id(row, 'branch_id') != branch.toLowerCase() ||
      row['source'] != 'server_posted') {
    throw const FormatException('Report scope or source mismatch');
  }
  return ReportScope(
    organizationId: org.toLowerCase(),
    branchId: branch.toLowerCase(),
    generatedAt: _time(row, 'generated_at'),
  );
}

void _window(Map<String, dynamic> row, ReportWindow window) {
  if (_time(row, 'from') != window.from || _time(row, 'to') != window.to) {
    throw const FormatException('Report activity filter mismatch');
  }
}

DateTime _day(Map<String, dynamic> row, ReportWindow window) {
  final value = _text(row, 'date', 10, minimum: 10);
  final DateTime day;
  try {
    day = parseReportDate(value);
  } on RepositoryFailure {
    throw const FormatException('Invalid report day');
  }
  if (!day.isBefore(window.to) ||
      !day.add(const Duration(days: 1)).isAfter(window.from)) {
    throw const FormatException('Report day outside activity window');
  }
  return day;
}

String _currency(Map<String, dynamic> row) {
  final value = _text(row, 'currency', 3, minimum: 3);
  if (!reportCurrencies.contains(value)) {
    throw const FormatException('Unsupported report currency');
  }
  return value;
}

void _unique(Iterable<Object> values) {
  final list = values.toList(growable: false);
  if (list.toSet().length != list.length) {
    throw const FormatException('Duplicate report group');
  }
}

void _equal(BigInt actual, int expected) {
  if (actual != BigInt.from(expected)) {
    throw const FormatException('Inconsistent report arithmetic');
  }
}

SalesTotals _salesTotals(Map<String, dynamic> row) {
  final result = SalesTotals(
    saleCount: _integer(row, 'sale_count'),
    salesSubtotalMinor: _integer(row, 'sales_subtotal_minor'),
    salesDiscountMinor: _integer(row, 'sales_discount_minor'),
    salesTaxMinor: _integer(row, 'sales_tax_minor'),
    salesTotalMinor: _integer(row, 'sales_total_minor'),
    reversalCount: _integer(row, 'reversal_count'),
    refundTotalMinor: _integer(row, 'refund_total_minor'),
    voidTotalMinor: _integer(row, 'void_total_minor'),
    reversalTotalMinor: _integer(row, 'reversal_total_minor'),
    netSalesMinor: _integer(row, 'net_sales_minor', signed: true),
  );
  if (result.salesDiscountMinor > result.salesSubtotalMinor ||
      result.salesTotalMinor < result.saleCount ||
      result.reversalTotalMinor < result.reversalCount ||
      (result.saleCount == 0 &&
          (result.salesSubtotalMinor != 0 ||
              result.salesDiscountMinor != 0 ||
              result.salesTaxMinor != 0 ||
              result.salesTotalMinor != 0)) ||
      (result.reversalCount == 0 && result.reversalTotalMinor != 0) ||
      (result.saleCount == 0 && result.reversalCount == 0)) {
    throw const FormatException('Invalid sales activity totals');
  }
  _equal(
    BigInt.from(result.salesSubtotalMinor) -
        BigInt.from(result.salesDiscountMinor) +
        BigInt.from(result.salesTaxMinor),
    result.salesTotalMinor,
  );
  _equal(
    BigInt.from(result.refundTotalMinor) + BigInt.from(result.voidTotalMinor),
    result.reversalTotalMinor,
  );
  _equal(
    BigInt.from(result.salesTotalMinor) -
        BigInt.from(result.reversalTotalMinor),
    result.netSalesMinor,
  );
  return result;
}

List<int> _salesVector(SalesTotals totals) => [
  totals.saleCount,
  totals.salesSubtotalMinor,
  totals.salesDiscountMinor,
  totals.salesTaxMinor,
  totals.salesTotalMinor,
  totals.reversalCount,
  totals.refundTotalMinor,
  totals.voidTotalMinor,
  totals.reversalTotalMinor,
  totals.netSalesMinor,
];

void _sumVectors(Iterable<List<int>> groups, List<int> total) {
  final sums = List.filled(total.length, BigInt.zero);
  for (final group in groups) {
    for (var index = 0; index < total.length; index++) {
      sums[index] += BigInt.from(group[index]);
    }
  }
  for (var index = 0; index < total.length; index++) {
    _equal(sums[index], total[index]);
  }
}

SalesReport salesReportFromRow(
  Map<String, dynamic> row, {
  required String organizationId,
  required String branchId,
  required ReportWindow window,
  required String? shiftId,
}) {
  final scope = _scope(row, organizationId, branchId);
  _window(row, window);
  final responseShift = row['shift_id'] == null ? null : _id(row, 'shift_id');
  if (responseShift != shiftId?.toLowerCase()) {
    throw const FormatException('Report shift mismatch');
  }
  final currencies = reportRows(row['currencies'], 7)
      .map((currencyRow) {
        final totals = _salesTotals(currencyRow);
        final payments = reportRows(currencyRow['payments'], 5)
            .map((payment) {
              final method = _text(payment, 'method', 10);
              if (!reportPaymentMethods.contains(method)) {
                throw const FormatException('Unknown payment method');
              }
              final result = ReportPaymentTotals(
                method: method,
                salesMinor: _integer(payment, 'sales_minor'),
                reversedMinor: _integer(payment, 'reversed_minor'),
                netMinor: _integer(payment, 'net_minor', signed: true),
              );
              _equal(
                BigInt.from(result.salesMinor) -
                    BigInt.from(result.reversedMinor),
                result.netMinor,
              );
              if (result.salesMinor == 0 && result.reversedMinor == 0) {
                throw const FormatException('Empty report payment group');
              }
              return result;
            })
            .toList(growable: false);
        _unique(payments.map((payment) => payment.method));
        _equal(
          payments.fold(
            BigInt.zero,
            (sum, payment) => sum + BigInt.from(payment.salesMinor),
          ),
          totals.salesTotalMinor,
        );
        _equal(
          payments.fold(
            BigInt.zero,
            (sum, payment) => sum + BigInt.from(payment.reversedMinor),
          ),
          totals.reversalTotalMinor,
        );
        final daily = reportRows(currencyRow['daily'], 367)
            .map(
              (day) => SalesReportDay(
                date: _day(day, window),
                totals: _salesTotals(day),
              ),
            )
            .toList(growable: false);
        _unique(daily.map((day) => day.date));
        _sumVectors(
          daily.map((day) => _salesVector(day.totals)),
          _salesVector(totals),
        );
        return SalesReportCurrency(
          currency: _currency(currencyRow),
          totals: totals,
          payments: payments,
          daily: daily,
        );
      })
      .toList(growable: false);
  _unique(currencies.map((currency) => currency.currency));
  return SalesReport(
    scope: scope,
    window: window,
    shiftId: responseShift,
    currencies: currencies,
  );
}

BigInt _reorderScaled(String value) {
  if (!RegExp(r'^\d{1,14}(?:\.\d{1,4})?$').hasMatch(value)) {
    throw const FormatException('Invalid exact reorder quantity');
  }
  final parts = value.split('.');
  return BigInt.parse(parts[0]) * BigInt.from(10000) +
      BigInt.parse(parts.length == 2 ? parts[1].padRight(4, '0') : '0');
}

InventoryReport inventoryReportFromRow(
  Map<String, dynamic> row, {
  required String organizationId,
  required String branchId,
  required String query,
  required PageRequest page,
}) {
  final scope = _scope(row, organizationId, branchId);
  if (_text(row, 'query', 120, minimum: 0) != query ||
      _integer(row, 'offset') != page.offset ||
      _integer(row, 'limit') != page.limit + 1) {
    throw const FormatException('Inventory report filter mismatch');
  }
  final catalog = _integer(row, 'catalog_product_count');
  final stocked = _integer(row, 'stocked_product_count');
  final deficit = _integer(row, 'deficit_product_count');
  final low = _integer(row, 'low_stock_product_count');
  if (BigInt.from(stocked) + BigInt.from(deficit) > BigInt.from(catalog) ||
      low > catalog) {
    throw const FormatException('Inventory counters exceed product scope');
  }
  final items = reportRows(row['items'], page.limit + 1)
      .map((item) {
        final quantity = _integer(item, 'quantity', signed: true);
        final revision = _integer(item, 'stock_revision');
        final active = _boolean(item, 'active');
        final movement = _boolean(item, 'has_movement');
        final isDeficit = _boolean(item, 'is_deficit');
        final isLow = _boolean(item, 'is_low_stock');
        final reorder = _text(item, 'reorder_level', 19);
        final scaled = _reorderScaled(reorder);
        if (movement != (revision > 0) ||
            (!movement && quantity != 0) ||
            isDeficit != (quantity < 0) ||
            isLow !=
                (active &&
                    BigInt.from(quantity) * BigInt.from(10000) <= scaled)) {
          throw const FormatException('Inventory observation flags disagree');
        }
        return InventoryReportItem(
          productId: _id(item, 'product_id'),
          name: _text(item, 'name', 160),
          sku: _text(item, 'sku', 64),
          unit: _text(item, 'unit', 32),
          active: active,
          reorderLevel: reorder,
          quantity: quantity,
          stockRevision: revision,
          hasMovement: movement,
          isDeficit: isDeficit,
          isLowStock: isLow,
        );
      })
      .toList(growable: false);
  _unique(items.map((item) => item.productId));
  if (items.where((item) => item.quantity > 0).length > stocked ||
      items.where((item) => item.isDeficit).length > deficit ||
      items.where((item) => item.isLowStock).length > low) {
    throw const FormatException('Inventory page exceeds observation counters');
  }
  if (page.offset == 0 &&
      items.length == catalog &&
      (items.where((item) => item.quantity > 0).length != stocked ||
          items.where((item) => item.isDeficit).length != deficit ||
          items.where((item) => item.isLowStock).length != low)) {
    throw const FormatException('Inventory counters disagree with full result');
  }
  final remaining = catalog > page.offset ? catalog - page.offset : 0;
  final expected = remaining > page.limit + 1 ? page.limit + 1 : remaining;
  if (items.length != expected) {
    throw const FormatException('Inventory report page incomplete');
  }
  return InventoryReport(
    scope: scope,
    query: query,
    catalogProductCount: catalog,
    stockedProductCount: stocked,
    deficitProductCount: deficit,
    lowStockProductCount: low,
    items: DataPage(
      items: items.take(page.limit).toList(growable: false),
      hasMore: items.length > page.limit,
      offset: page.offset,
    ),
  );
}

ExpenseTotals _expenseTotals(Map<String, dynamic> row) {
  final result = ExpenseTotals(
    expenseCount: _integer(row, 'expense_count'),
    expenseTotalMinor: _integer(row, 'expense_total_minor'),
    reversalCount: _integer(row, 'reversal_count'),
    reversalTotalMinor: _integer(row, 'reversal_total_minor'),
    netExpenseMinor: _integer(row, 'net_expense_minor', signed: true),
  );
  if (result.expenseTotalMinor < result.expenseCount ||
      result.reversalTotalMinor < result.reversalCount ||
      (result.expenseCount == 0 && result.expenseTotalMinor != 0) ||
      (result.reversalCount == 0 && result.reversalTotalMinor != 0) ||
      (result.expenseCount == 0 && result.reversalCount == 0)) {
    throw const FormatException('Invalid expense activity totals');
  }
  _equal(
    BigInt.from(result.expenseTotalMinor) -
        BigInt.from(result.reversalTotalMinor),
    result.netExpenseMinor,
  );
  return result;
}

List<int> _expenseVector(ExpenseTotals totals) => [
  totals.expenseCount,
  totals.expenseTotalMinor,
  totals.reversalCount,
  totals.reversalTotalMinor,
  totals.netExpenseMinor,
];

ExpenseReport expenseReportFromRow(
  Map<String, dynamic> row, {
  required String organizationId,
  required String branchId,
  required ReportWindow window,
}) {
  final scope = _scope(row, organizationId, branchId);
  _window(row, window);
  final currencies = reportRows(row['currencies'], 7)
      .map((currencyRow) {
        final totals = _expenseTotals(currencyRow);
        List<ExpenseReportGroup> dimension(
          String plural,
          String key,
          Set<String> allowed,
        ) {
          final groups = reportRows(currencyRow[plural], allowed.length)
              .map((group) {
                final label = _text(group, key, 20);
                if (!allowed.contains(label)) {
                  throw const FormatException(
                    'Unknown expense report dimension',
                  );
                }
                return ExpenseReportGroup(
                  key: label,
                  totals: _expenseTotals(group),
                );
              })
              .toList(growable: false);
          _unique(groups.map((group) => group.key));
          _sumVectors(
            groups.map((group) => _expenseVector(group.totals)),
            _expenseVector(totals),
          );
          return groups;
        }

        final categories = dimension(
          'categories',
          'category',
          reportExpenseCategories,
        );
        final sources = dimension('sources', 'source', reportExpenseSources);
        final daily = reportRows(currencyRow['daily'], 367)
            .map(
              (day) => ExpenseReportDay(
                date: _day(day, window),
                totals: _expenseTotals(day),
              ),
            )
            .toList(growable: false);
        _unique(daily.map((day) => day.date));
        _sumVectors(
          daily.map((day) => _expenseVector(day.totals)),
          _expenseVector(totals),
        );
        return ExpenseReportCurrency(
          currency: _currency(currencyRow),
          totals: totals,
          categories: categories,
          sources: sources,
          daily: daily,
        );
      })
      .toList(growable: false);
  _unique(currencies.map((currency) => currency.currency));
  return ExpenseReport(scope: scope, window: window, currencies: currencies);
}
