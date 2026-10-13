import '../../catalog/domain/repository_support.dart';
import 'administration_models.dart';

abstract interface class AdministrationRepository {
  Future<BusinessSettings> loadSettings();
  Future<BusinessSettings> updateSettings({
    required int expectedRevision,
    required BusinessSettingsInput input,
  });
  Future<DataPage<AuditEntry>> listAudit({
    AuditFilter filter = const AuditFilter(),
    PageRequest page = const PageRequest(),
  });
}

abstract interface class EmployeeRepository {
  Future<DataPage<Employee>> listEmployees({
    EmployeeStatus? status,
    PageRequest page = const PageRequest(),
  });
  Future<List<BranchOption>> listBranches();
  Future<Employee> updateEmployee({
    required String membershipId,
    required int expectedRevision,
    required EmployeeAccessInput input,
  });
  Future<InvitationDelivery> createInvitation(EmployeeInvitationInput input);
}
