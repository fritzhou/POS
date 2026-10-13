enum AppPermission {
  viewDashboard,
  usePos,
  viewSales,
  viewProducts,
  viewInventory,
  managePurchases,
  viewSuppliers,
  lookupCustomers,
  manageEmployees,
  viewShifts,
  manageExpenses,
  viewReports,
  viewAuditLogs,
  viewNotifications,
  manageSettings,
  manageProducts,
  approveDiscount,
  approveRefund,
  approveVoid,
  assignAdmin,
  manageSecurity,
}

/// Presentation policy only. PostgreSQL independently enforces access.
enum AppRole {
  owner,
  admin,
  manager,
  cashier,
  inventoryStaff;

  static AppRole fromDatabase(String value) => switch (value) {
    'owner' => owner,
    'admin' => admin,
    'manager' => manager,
    'cashier' => cashier,
    'inventory_staff' => inventoryStaff,
    _ => throw const FormatException('Unrecognized membership role'),
  };

  String get label => switch (this) {
    owner => 'Owner',
    admin => 'Admin',
    manager => 'Manager',
    cashier => 'Cashier',
    inventoryStaff => 'Inventory Staff',
  };

  bool allows(AppPermission permission) {
    if (this == owner) return true;
    if (permission == AppPermission.assignAdmin) return false;
    if (this == admin) return true;
    return switch (permission) {
      AppPermission.viewDashboard ||
      AppPermission.viewProducts ||
      AppPermission.viewNotifications => true,
      AppPermission.usePos ||
      AppPermission.viewSales ||
      AppPermission.lookupCustomers ||
      AppPermission.viewShifts => this == manager || this == cashier,
      AppPermission.viewInventory ||
      AppPermission.viewSuppliers ||
      AppPermission.managePurchases =>
        this == manager || this == inventoryStaff,
      // Report adapters and SQL independently enforce branch, own-shift or stock scope.
      AppPermission.viewReports => true,
      AppPermission.manageProducts => this == inventoryStaff,
      AppPermission.approveDiscount ||
      AppPermission.approveRefund ||
      AppPermission.approveVoid ||
      AppPermission.manageExpenses => this == manager,
      AppPermission.viewAuditLogs => this == manager || this == inventoryStaff,
      AppPermission.manageEmployees ||
      AppPermission.manageSettings ||
      AppPermission.manageSecurity ||
      AppPermission.assignAdmin => false,
    };
  }
}
