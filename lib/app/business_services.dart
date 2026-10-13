import '../core/auth/auth_models.dart';
import '../features/administration/domain/administration_repository.dart';
import '../features/catalog/domain/catalog_repository.dart';
import '../features/people/domain/people_repository.dart';
import '../features/checkout/domain/checkout_repository.dart';
import '../features/inventory/domain/inventory_repository.dart';
import '../features/offline/domain/offline_workspace.dart';
import '../features/security/domain/security_repository.dart';
import '../features/security/pin_security.dart';
import '../features/authentication/domain/mfa_repository.dart';
import '../features/purchases/domain/purchase_repository.dart';
import '../features/expenses/domain/expense_repository.dart';
import '../features/reports/domain/reports_repository.dart';
import '../features/logistics/data/supabase_logistics_repository.dart';
import '../features/invitations/domain/invitation_repository.dart';

/// Repositories belong to a verified membership and one organization.
/// Recreate this group when the selected membership changes.
class BusinessServices {
  const BusinessServices({
    required this.catalog,
    required this.people,
    required this.administration,
    required this.employees,
    this.checkout,
    this.inventory,
    this.offline,
    this.security,
    this.mfa,
    this.pin,
    this.purchases,
    this.expenses,
    this.reports,
    this.logistics,
    this.invitationAdministration,
    this.onDispose,
  });

  final CatalogRepository catalog;
  final PeopleRepository people;
  final AdministrationRepository administration;
  final EmployeeRepository employees;
  final CheckoutRepository? checkout;
  final InventoryRepository? inventory;
  final OfflineWorkspace? offline;
  final SecurityRepository? security;
  final MfaRepository? mfa;
  final EmployeePinRepository? pin;
  final PurchaseRepository? purchases;
  final ExpenseRepository? expenses;
  final ReportsRepository? reports;
  final SupabaseLogisticsRepository? logistics;
  final InvitationAdministrationRepository? invitationAdministration;
  final Future<void> Function()? onDispose;
  Future<void> dispose() async => onDispose?.call();
}

typedef BusinessServicesFactory =
    BusinessServices Function(AuthenticatedUser user);
