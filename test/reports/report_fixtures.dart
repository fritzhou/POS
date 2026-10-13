import 'dart:convert';

import 'package:nexapos/core/auth/auth_models.dart';
import 'package:nexapos/core/security/app_role.dart';
import 'package:nexapos/features/catalog/domain/repository_support.dart';
import 'package:nexapos/features/reports/data/report_decoders.dart';
import 'package:nexapos/features/reports/domain/report_models.dart';

const reportOrg = '11111111-1111-1111-1111-111111111111';
const reportActor = '22222222-2222-2222-2222-222222222222';
const reportBranch = '33333333-3333-3333-3333-333333333333';
const reportOtherBranch = '44444444-4444-4444-4444-444444444444';
const reportShift = '55555555-5555-5555-5555-555555555555';
const reportProduct = '66666666-6666-6666-6666-666666666666';

final reportWindow = ReportWindow(
  from: DateTime.utc(2026, 10, 1),
  to: DateTime.utc(2026, 10, 4),
);

AuthenticatedUser reportMembership({AppRole role = AppRole.owner}) =>
    AuthenticatedUser(
      userId: reportActor,
      email: 'reports@example.test',
      organizationId: reportOrg,
      membershipId: reportProduct,
      role: role,
      branchIds: {reportBranch},
      allBranches: role == AppRole.owner,
      businessName: 'Report business',
    );

Map<String, dynamic> reportScopeWire({String branch = reportBranch}) => {
  'organization_id': reportOrg,
  'branch_id': branch,
  'generated_at': '2026-10-12T00:00:00Z',
  'source': 'server_posted',
};

Map<String, dynamic> salesTotalsWire({bool reversalOnly = false}) => {
  'sale_count': reversalOnly ? 0 : 1,
  'sales_subtotal_minor': reversalOnly ? 0 : 1100,
  'sales_discount_minor': reversalOnly ? 0 : 100,
  'sales_tax_minor': reversalOnly ? 0 : 120,
  'sales_total_minor': reversalOnly ? 0 : 1120,
  'reversal_count': 2,
  'refund_total_minor': 500,
  'void_total_minor': 620,
  'reversal_total_minor': 1120,
  'net_sales_minor': reversalOnly ? -1120 : 0,
};

Map<String, dynamic> salesCurrencyWire({
  String currency = 'PHP',
  bool reversalOnly = false,
}) => {
  'currency': currency,
  ...salesTotalsWire(reversalOnly: reversalOnly),
  'payments': [
    {
      'method': 'cash',
      'sales_minor': reversalOnly ? 0 : 420,
      'reversed_minor': 420,
      'net_minor': reversalOnly ? -420 : 0,
    },
    {
      'method': 'card',
      'sales_minor': reversalOnly ? 0 : 700,
      'reversed_minor': 700,
      'net_minor': reversalOnly ? -700 : 0,
    },
  ],
  'daily': [
    {'date': '2026-10-02', ...salesTotalsWire(reversalOnly: reversalOnly)},
  ],
};

Map<String, dynamic> salesReportWire({
  String branch = reportBranch,
  String? shift,
  bool empty = false,
  bool reversalOnly = false,
}) => {
  ...reportScopeWire(branch: branch),
  'from': reportWindow.from.toIso8601String(),
  'to': reportWindow.to.toIso8601String(),
  'shift_id': shift,
  'currencies': empty
      ? <Object>[]
      : [salesCurrencyWire(reversalOnly: reversalOnly)],
};

Map<String, dynamic> inventoryItemWire({
  String product = reportProduct,
  String name = 'Actual product',
  int quantity = -2,
  bool active = true,
  bool movement = true,
}) => {
  'product_id': product,
  'name': name,
  'sku': 'ACTUAL',
  'unit': 'each',
  'active': active,
  'reorder_level': '1.2500',
  'quantity': quantity,
  'stock_revision': movement ? 3 : 0,
  'has_movement': movement,
  'is_deficit': quantity < 0,
  'is_low_stock': active && quantity <= 1,
};

Map<String, dynamic> inventoryReportWire({
  String branch = reportBranch,
  String query = '',
  int offset = 0,
  int limit = 51,
  bool empty = false,
}) => {
  ...reportScopeWire(branch: branch),
  'query': query,
  'offset': offset,
  'limit': limit,
  'catalog_product_count': empty ? 0 : 1,
  'stocked_product_count': 0,
  'deficit_product_count': empty ? 0 : 1,
  'low_stock_product_count': empty ? 0 : 1,
  'items': empty ? <Object>[] : [inventoryItemWire()],
};

Map<String, dynamic> expenseTotalsWire({bool reversalOnly = false}) => {
  'expense_count': reversalOnly ? 0 : 1,
  'expense_total_minor': reversalOnly ? 0 : 500,
  'reversal_count': 1,
  'reversal_total_minor': 600,
  'net_expense_minor': reversalOnly ? -600 : -100,
};

Map<String, dynamic> expenseCurrencyWire({bool reversalOnly = false}) => {
  'currency': 'PHP',
  ...expenseTotalsWire(reversalOnly: reversalOnly),
  'categories': [
    {'category': 'rent', ...expenseTotalsWire(reversalOnly: reversalOnly)},
  ],
  'sources': [
    {'source': 'external', ...expenseTotalsWire(reversalOnly: reversalOnly)},
  ],
  'daily': [
    {'date': '2026-10-02', ...expenseTotalsWire(reversalOnly: reversalOnly)},
  ],
};

Map<String, dynamic> expenseReportWire({
  String branch = reportBranch,
  bool empty = false,
  bool reversalOnly = false,
}) => {
  ...reportScopeWire(branch: branch),
  'from': reportWindow.from.toIso8601String(),
  'to': reportWindow.to.toIso8601String(),
  'currencies': empty
      ? <Object>[]
      : [expenseCurrencyWire(reversalOnly: reversalOnly)],
};

Map<String, dynamic> cloneReportWire(Map<String, dynamic> value) =>
    jsonDecode(jsonEncode(value)) as Map<String, dynamic>;

SalesReport decodedSales({
  String branch = reportBranch,
  bool empty = false,
  bool reversalOnly = false,
  ReportWindow? window,
  String? shift,
}) {
  final wire = salesReportWire(
    branch: branch,
    empty: empty,
    reversalOnly: reversalOnly,
    shift: shift,
  );
  if (window != null) {
    wire['from'] = window.from.toIso8601String();
    wire['to'] = window.to.toIso8601String();
    for (final currency in wire['currencies'] as List) {
      currency['daily'][0]['date'] = reportDate(window.from);
    }
  }
  return salesReportFromRow(
    wire,
    organizationId: reportOrg,
    branchId: branch,
    window: window ?? reportWindow,
    shiftId: shift,
  );
}

ExpenseReport decodedExpenses({ReportWindow? window, bool empty = false}) {
  final wire = expenseReportWire(empty: empty);
  if (window != null) {
    wire['from'] = window.from.toIso8601String();
    wire['to'] = window.to.toIso8601String();
    for (final currency in wire['currencies'] as List) {
      currency['daily'][0]['date'] = reportDate(window.from);
    }
  }
  return expenseReportFromRow(
    wire,
    organizationId: reportOrg,
    branchId: reportBranch,
    window: window ?? reportWindow,
  );
}

InventoryReport decodedInventory({
  String query = '',
  PageRequest page = const PageRequest(),
  bool empty = false,
}) => inventoryReportFromRow(
  inventoryReportWire(
    query: query,
    offset: page.offset,
    limit: page.limit + 1,
    empty: empty,
  ),
  organizationId: reportOrg,
  branchId: reportBranch,
  query: query,
  page: page,
);
