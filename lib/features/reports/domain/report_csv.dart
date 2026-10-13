import 'report_models.dart';

/// Spreadsheet controls are neutralized only for textual cells. Numeric signed
/// amounts retain their exact integer CSV representation and original meaning.
String reportCsvCell(Object? value) {
  if (value == null) return '';
  var text = value.toString();
  if (value is String &&
      (RegExp(r'^[=+\-@]').hasMatch(text.trimLeft()) ||
          text.startsWith('\t') ||
          text.startsWith('\r') ||
          text.startsWith('\n'))) {
    text = "'$text";
  }
  if (text.contains(',') ||
      text.contains('"') ||
      text.contains('\r') ||
      text.contains('\n')) {
    return '"${text.replaceAll('"', '""')}"';
  }
  return text;
}

String reportToCsv(OperationalReport report) {
  final rows = <List<Object?>>[
    ['NexaPOS authorized operational report'],
    ['organization_id', report.scope.organizationId],
    ['branch_id', report.scope.branchId],
    ['generated_at_utc', report.scope.generatedAt.toUtc().toIso8601String()],
    ['source', report.scope.source],
  ];
  void window(ReportWindow value) {
    rows.add(['activity_from_utc_inclusive', value.from.toIso8601String()]);
    rows.add(['activity_to_utc_exclusive', value.to.toIso8601String()]);
  }

  List<Object?> salesValues(SalesTotals values) => [
    values.saleCount,
    values.salesSubtotalMinor,
    values.salesDiscountMinor,
    values.salesTaxMinor,
    values.salesTotalMinor,
    values.reversalCount,
    values.refundTotalMinor,
    values.voidTotalMinor,
    values.reversalTotalMinor,
    values.netSalesMinor,
  ];
  List<Object?> expenseValues(ExpenseTotals values) => [
    values.expenseCount,
    values.expenseTotalMinor,
    values.reversalCount,
    values.reversalTotalMinor,
    values.netExpenseMinor,
  ];
  switch (report) {
    case SalesReport():
      rows.add(['report', 'sales_activity']);
      window(report.window);
      rows.add(['operation_shift_id', report.shiftId]);
      rows.add([
        'currency',
        'group',
        'date_or_payment_method',
        'sale_count',
        'sales_subtotal_minor',
        'sales_discount_minor',
        'sales_tax_minor',
        'sales_total_minor',
        'reversal_count',
        'refund_total_minor',
        'void_total_minor',
        'reversal_total_minor',
        'net_sales_minor',
      ]);
      for (final currency in report.currencies) {
        rows.add([
          currency.currency,
          'total',
          '',
          ...salesValues(currency.totals),
        ]);
        for (final day in currency.daily) {
          rows.add([
            currency.currency,
            'daily_utc',
            reportDate(day.date),
            ...salesValues(day.totals),
          ]);
        }
      }
      rows.add([
        'currency',
        'payment_method',
        'sales_minor',
        'reversed_minor',
        'net_minor',
      ]);
      for (final currency in report.currencies) {
        for (final payment in currency.payments) {
          rows.add([
            currency.currency,
            payment.method,
            payment.salesMinor,
            payment.reversedMinor,
            payment.netMinor,
          ]);
        }
      }
    case InventoryReport():
      rows.add(['report', 'current_inventory_page']);
      rows.add(['product_query', report.query]);
      rows.add(['displayed_page_offset', report.items.offset]);
      rows.add(['additional_pages_available', report.items.hasMore]);
      rows.add(['matching_product_count', report.catalogProductCount]);
      rows.add(['positive_stock_product_count', report.stockedProductCount]);
      rows.add(['deficit_product_count', report.deficitProductCount]);
      rows.add(['low_stock_product_count', report.lowStockProductCount]);
      rows.add([
        'product_id',
        'name',
        'sku',
        'unit',
        'active',
        'quantity',
        'reorder_level',
        'stock_revision',
        'has_movement',
        'is_deficit',
        'is_low_stock',
      ]);
      for (final item in report.items.items) {
        rows.add([
          item.productId,
          item.name,
          item.sku,
          item.unit,
          item.active,
          item.quantity,
          item.reorderLevel,
          item.stockRevision,
          item.hasMovement,
          item.isDeficit,
          item.isLowStock,
        ]);
      }
    case ExpenseReport():
      rows.add(['report', 'expense_activity']);
      window(report.window);
      rows.add([
        'currency',
        'group',
        'date_category_or_source',
        'expense_count',
        'expense_total_minor',
        'reversal_count',
        'reversal_total_minor',
        'net_expense_minor',
      ]);
      for (final currency in report.currencies) {
        rows.add([
          currency.currency,
          'total',
          '',
          ...expenseValues(currency.totals),
        ]);
        for (final group in currency.categories) {
          rows.add([
            currency.currency,
            'category',
            group.key,
            ...expenseValues(group.totals),
          ]);
        }
        for (final group in currency.sources) {
          rows.add([
            currency.currency,
            'payment_source',
            group.key,
            ...expenseValues(group.totals),
          ]);
        }
        for (final day in currency.daily) {
          rows.add([
            currency.currency,
            'daily_utc',
            reportDate(day.date),
            ...expenseValues(day.totals),
          ]);
        }
      }
    default:
      throw const FormatException('Unsupported report snapshot');
  }
  return '${rows.map((row) => row.map(reportCsvCell).join(',')).join('\r\n')}\r\n';
}
