import '../../catalog/domain/repository_support.dart';

enum ReportKind { sales, inventory, expenses }

class ReportWindow {
  ReportWindow({required this.from, required this.to}) {
    if (!from.isUtc ||
        !to.isUtc ||
        from.year < 1 ||
        to.year > 9999 ||
        !to.isAfter(from) ||
        to.difference(from) > const Duration(days: 366)) {
      throw const RepositoryFailure(
        RepositoryFailureType.validation,
        'Choose a UTC activity window of at most 366 days.',
      );
    }
  }

  /// Date picker fields describe UTC calendar dates. The inclusive final date
  /// becomes the next UTC midnight; no local timezone offset changes its scope.
  factory ReportWindow.inclusiveUtcDates(DateTime first, DateTime last) =>
      ReportWindow(
        from: DateTime.utc(first.year, first.month, first.day),
        to: DateTime.utc(
          last.year,
          last.month,
          last.day,
        ).add(const Duration(days: 1)),
      );

  factory ReportWindow.fromDateText(String first, String last) =>
      ReportWindow.inclusiveUtcDates(
        parseReportDate(first),
        parseReportDate(last),
      );

  final DateTime from;
  final DateTime to;
  DateTime get inclusiveLastDate =>
      to.subtract(const Duration(microseconds: 1));
}

DateTime parseReportDate(String value) {
  if (!RegExp(r'^\d{4}-\d{2}-\d{2}$').hasMatch(value)) {
    throw const RepositoryFailure(
      RepositoryFailureType.validation,
      'Enter a valid UTC date as YYYY-MM-DD.',
    );
  }
  final result = DateTime.tryParse('${value}T00:00:00Z');
  if (result == null || reportDate(result) != value) {
    throw const RepositoryFailure(
      RepositoryFailureType.validation,
      'Enter a valid UTC calendar date.',
    );
  }
  return result;
}

String reportDate(DateTime value) =>
    '${value.year.toString().padLeft(4, '0')}-'
    '${value.month.toString().padLeft(2, '0')}-'
    '${value.day.toString().padLeft(2, '0')}';

class ReportScope {
  const ReportScope({
    required this.organizationId,
    required this.branchId,
    required this.generatedAt,
  });
  final String organizationId;
  final String branchId;
  final DateTime generatedAt;
  String get source => 'server_posted';
}

abstract interface class OperationalReport {
  ReportScope get scope;
}

class SalesTotals {
  const SalesTotals({
    required this.saleCount,
    required this.salesSubtotalMinor,
    required this.salesDiscountMinor,
    required this.salesTaxMinor,
    required this.salesTotalMinor,
    required this.reversalCount,
    required this.refundTotalMinor,
    required this.voidTotalMinor,
    required this.reversalTotalMinor,
    required this.netSalesMinor,
  });
  final int saleCount;
  final int salesSubtotalMinor;
  final int salesDiscountMinor;
  final int salesTaxMinor;
  final int salesTotalMinor;
  final int reversalCount;
  final int refundTotalMinor;
  final int voidTotalMinor;
  final int reversalTotalMinor;
  final int netSalesMinor;
}

class ReportPaymentTotals {
  const ReportPaymentTotals({
    required this.method,
    required this.salesMinor,
    required this.reversedMinor,
    required this.netMinor,
  });
  final String method;
  final int salesMinor;
  final int reversedMinor;
  final int netMinor;
}

class SalesReportDay {
  const SalesReportDay({required this.date, required this.totals});
  final DateTime date;
  final SalesTotals totals;
}

class SalesReportCurrency {
  SalesReportCurrency({
    required this.currency,
    required this.totals,
    required List<ReportPaymentTotals> payments,
    required List<SalesReportDay> daily,
  }) : payments = List.unmodifiable(payments),
       daily = List.unmodifiable(daily);
  final String currency;
  final SalesTotals totals;
  final List<ReportPaymentTotals> payments;
  final List<SalesReportDay> daily;
}

class SalesReport implements OperationalReport {
  SalesReport({
    required this.scope,
    required this.window,
    required List<SalesReportCurrency> currencies,
    this.shiftId,
  }) : currencies = List.unmodifiable(currencies);
  @override
  final ReportScope scope;
  final ReportWindow window;
  final String? shiftId;
  final List<SalesReportCurrency> currencies;
}

class InventoryReportItem {
  const InventoryReportItem({
    required this.productId,
    required this.name,
    required this.sku,
    required this.unit,
    required this.active,
    required this.reorderLevel,
    required this.quantity,
    required this.stockRevision,
    required this.hasMovement,
    required this.isDeficit,
    required this.isLowStock,
  });
  final String productId;
  final String name;
  final String sku;
  final String unit;
  final bool active;
  final String reorderLevel;
  final int quantity;
  final int stockRevision;
  final bool hasMovement;
  final bool isDeficit;
  final bool isLowStock;
}

class InventoryReport implements OperationalReport {
  const InventoryReport({
    required this.scope,
    required this.query,
    required this.catalogProductCount,
    required this.stockedProductCount,
    required this.deficitProductCount,
    required this.lowStockProductCount,
    required this.items,
  });
  @override
  final ReportScope scope;
  final String query;
  final int catalogProductCount;
  final int stockedProductCount;
  final int deficitProductCount;
  final int lowStockProductCount;
  final DataPage<InventoryReportItem> items;
}

class ExpenseTotals {
  const ExpenseTotals({
    required this.expenseCount,
    required this.expenseTotalMinor,
    required this.reversalCount,
    required this.reversalTotalMinor,
    required this.netExpenseMinor,
  });
  final int expenseCount;
  final int expenseTotalMinor;
  final int reversalCount;
  final int reversalTotalMinor;
  final int netExpenseMinor;
}

class ExpenseReportGroup {
  const ExpenseReportGroup({required this.key, required this.totals});
  final String key;
  final ExpenseTotals totals;
}

class ExpenseReportDay {
  const ExpenseReportDay({required this.date, required this.totals});
  final DateTime date;
  final ExpenseTotals totals;
}

class ExpenseReportCurrency {
  ExpenseReportCurrency({
    required this.currency,
    required this.totals,
    required List<ExpenseReportGroup> categories,
    required List<ExpenseReportGroup> sources,
    required List<ExpenseReportDay> daily,
  }) : categories = List.unmodifiable(categories),
       sources = List.unmodifiable(sources),
       daily = List.unmodifiable(daily);
  final String currency;
  final ExpenseTotals totals;
  final List<ExpenseReportGroup> categories;
  final List<ExpenseReportGroup> sources;
  final List<ExpenseReportDay> daily;
}

class ExpenseReport implements OperationalReport {
  ExpenseReport({
    required this.scope,
    required this.window,
    required List<ExpenseReportCurrency> currencies,
  }) : currencies = List.unmodifiable(currencies);
  @override
  final ReportScope scope;
  final ReportWindow window;
  final List<ExpenseReportCurrency> currencies;
}
