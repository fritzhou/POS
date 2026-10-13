import '../../../core/security/app_role.dart';
import '../../catalog/domain/repository_support.dart';

class BusinessSettings {
  const BusinessSettings({
    required this.organizationId,
    required this.businessName,
    required this.currency,
    required this.taxBps,
    required this.revision,
    this.address,
    this.contact,
    this.logoPath,
    this.receiptFooter,
  });
  final String organizationId;
  final String businessName;
  final String currency;
  final int taxBps;
  final int revision;
  final String? address;
  final String? contact;
  final String? logoPath;
  final String? receiptFooter;
}

class BusinessSettingsInput {
  const BusinessSettingsInput({
    required this.businessName,
    this.currency = Money.currency,
    this.taxBps = 0,
    this.address,
    this.contact,
    this.logoPath,
    this.receiptFooter,
  });
  final String businessName;
  final String currency;
  final int taxBps;
  final String? address;
  final String? contact;
  final String? logoPath;
  final String? receiptFooter;
  Map<String, dynamic> validatedValues() {
    if (taxBps < 0 || taxBps > 10000) {
      throw const RepositoryFailure(
        RepositoryFailureType.validation,
        'Tax must be between 0% and 100%.',
      );
    }
    return {
      'business_name': requiredText(
        businessName,
        'Business name',
        120,
        minimum: 2,
      ),
      'currency': validateCurrency(currency),
      'tax_bps': taxBps,
      'address': optionalText(address, 'Address', 1000),
      'contact': optionalText(contact, 'Contact', 1000),
      'logo_path': validateImageReference(logoPath),
      'receipt_footer': optionalText(receiptFooter, 'Receipt footer', 1000),
    };
  }
}

class AuditEntry {
  AuditEntry({
    required this.id,
    required this.organizationId,
    required this.role,
    required this.action,
    required this.entity,
    required this.occurredAt,
    required Map<String, dynamic> metadata,
    this.userId,
    this.entityId,
    this.branchId,
    this.reason,
  }) : metadata = Map.unmodifiable(metadata);
  final String id;
  final String organizationId;
  final String role;
  final String action;
  final String entity;
  final DateTime occurredAt;
  final Map<String, dynamic> metadata;
  final String? userId;
  final String? entityId;
  final String? branchId;
  final String? reason;
}

class AuditFilter {
  const AuditFilter({this.entity, this.action, this.branchId});
  final String? entity;
  final String? action;
  final String? branchId;
}

enum EmployeeStatus { active, disabled, pending }

class BranchOption {
  const BranchOption({
    required this.id,
    required this.name,
    required this.code,
  });
  final String id;
  final String name;
  final String code;
}

class Employee {
  Employee({
    required this.membershipId,
    required this.userId,
    required this.fullName,
    required this.role,
    required this.status,
    required this.allBranches,
    required List<String> branchIds,
    required this.revision,
    this.email,
    this.phone,
    this.employeeId,
  }) : branchIds = List.unmodifiable(branchIds);
  final String membershipId;
  final String userId;
  final String fullName;
  final AppRole role;
  final EmployeeStatus status;
  final bool allBranches;
  final List<String> branchIds;
  final int revision;
  final String? email;
  final String? phone;
  final String? employeeId;
}

class EmployeeAccessInput {
  EmployeeAccessInput({
    required this.role,
    required this.status,
    required this.allBranches,
    required List<String> branchIds,
    required this.reason,
  }) : branchIds = List.unmodifiable(branchIds);
  final AppRole role;
  final EmployeeStatus status;
  final bool allBranches;
  final List<String> branchIds;
  final String reason;
}

class EmployeeInvitationInput {
  EmployeeInvitationInput({
    required this.requestId,
    required this.email,
    required this.fullName,
    required this.role,
    required List<String> branchIds,
    this.allBranches = false,
    this.employeeId,
    this.phone,
    this.reason = 'Employee invitation',
  }) : branchIds = List.unmodifiable(branchIds);

  /// A UUID retained across retries prevents duplicate invitation delivery.
  final String requestId;
  final String email;
  final String fullName;
  final AppRole role;
  final List<String> branchIds;
  final bool allBranches;
  final String? employeeId;
  final String? phone;
  final String reason;
}

enum InvitationDeliveryState { sent, sending }

class InvitationDelivery {
  const InvitationDelivery({
    required this.invitationId,
    required this.expiresAt,
    required this.state,
  });
  final String invitationId;
  final DateTime expiresAt;
  final InvitationDeliveryState state;
}

String databaseRole(AppRole role) =>
    role == AppRole.inventoryStaff ? 'inventory_staff' : role.name;
