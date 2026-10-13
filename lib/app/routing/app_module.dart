import 'package:flutter/material.dart';

import '../../core/security/app_role.dart';

enum AppModule {
  dashboard('Dashboard', Icons.dashboard_outlined, AppPermission.viewDashboard),
  pos('POS', Icons.point_of_sale_rounded, AppPermission.usePos),
  sales('Sales', Icons.receipt_long_outlined, AppPermission.viewSales),
  products('Products', Icons.inventory_2_outlined, AppPermission.viewProducts),
  inventory('Inventory', Icons.warehouse_outlined, AppPermission.viewInventory),
  purchases(
    'Purchases',
    Icons.shopping_bag_outlined,
    AppPermission.managePurchases,
  ),
  suppliers(
    'Suppliers',
    Icons.local_shipping_outlined,
    AppPermission.viewSuppliers,
  ),
  customers('Customers', Icons.people_outline, AppPermission.lookupCustomers),
  employees('Employees', Icons.badge_outlined, AppPermission.manageEmployees),
  shifts('Shifts', Icons.schedule_outlined, AppPermission.viewShifts),
  expenses('Expenses', Icons.payments_outlined, AppPermission.manageExpenses),
  reports('Reports', Icons.bar_chart_rounded, AppPermission.viewReports),
  auditLogs('Audit Logs', Icons.policy_outlined, AppPermission.viewAuditLogs),
  notifications(
    'Notifications',
    Icons.notifications_none,
    AppPermission.viewNotifications,
  ),
  settings('Settings', Icons.settings_outlined, AppPermission.manageSettings);

  const AppModule(this.label, this.icon, this.permission);
  final String label;
  final IconData icon;
  final AppPermission permission;
}
