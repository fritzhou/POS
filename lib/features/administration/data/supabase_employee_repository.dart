import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/auth/auth_models.dart';
import '../../../core/security/app_role.dart';
import '../../catalog/data/supabase_repository_support.dart';
import '../../catalog/domain/repository_support.dart';
import '../domain/administration_models.dart';
import '../domain/administration_repository.dart';

class SupabaseEmployeeRepository implements EmployeeRepository {
  SupabaseEmployeeRepository({
    required SupabaseClient client,
    required AuthenticatedUser actor,
    bool Function()? isRecoverySession,
  }) : _scope = SupabaseRepositoryScope(
         client: client,
         actor: actor,
         isRecoverySession: isRecoverySession,
       );
  final SupabaseRepositoryScope _scope;

  @override
  Future<DataPage<Employee>> listEmployees({
    EmployeeStatus? status,
    PageRequest page = const PageRequest(),
  }) => _scope.safe(() async {
    page.validate();
    final result = await _scope.client.rpc(
      'employee_roster',
      params: {
        'p_organization_id': _scope.organizationId,
        'p_status': status?.name,
        'p_offset': page.offset,
        'p_limit': page.limit + 1,
      },
    );
    return pageFrom(rowsFrom(result), page, employeeFromRow);
  });

  @override
  Future<List<BranchOption>> listBranches() => _scope.safe(() async {
    final result = await _scope.client
        .from('branches')
        .select('id,name,code')
        .eq('organization_id', _scope.organizationId)
        .eq('active', true)
        .order('name', ascending: true)
        .limit(100);
    return rowsFrom(result)
        .map(
          (row) => BranchOption(
            id: row['id'] as String,
            name: row['name'] as String,
            code: row['code'] as String,
          ),
        )
        .toList(growable: false);
  });

  List<String> _validatedBranches(
    AppRole role,
    bool allBranches,
    List<String> branchIds,
  ) {
    if (role == AppRole.owner ||
        (allBranches && role != AppRole.admin) ||
        (allBranches && branchIds.isNotEmpty) ||
        (!allBranches && branchIds.isEmpty) ||
        branchIds.length > 100 ||
        branchIds.toSet().length != branchIds.length) {
      throw const RepositoryFailure(
        RepositoryFailureType.validation,
        'Choose an employee role and valid branch assignments.',
      );
    }
    return branchIds.map(validateId).toList(growable: false);
  }

  @override
  Future<Employee> updateEmployee({
    required String membershipId,
    required int expectedRevision,
    required EmployeeAccessInput input,
  }) => _scope.safe(() async {
    if (membershipId == _scope.actor.membershipId) {
      throw const RepositoryFailure(
        RepositoryFailureType.permissionDenied,
        'Ask another authorized administrator to change your access.',
      );
    }
    final result = await _scope.client.rpc(
      'change_employee_access',
      params: {
        'p_organization_id': _scope.organizationId,
        'p_membership_id': validateId(membershipId),
        'p_role': databaseRole(input.role),
        'p_status': input.status.name,
        'p_all_branches': input.allBranches,
        'p_branch_ids': _validatedBranches(
          input.role,
          input.allBranches,
          input.branchIds,
        ),
        'p_expected_revision': validateRevision(expectedRevision),
        'p_reason': requiredText(input.reason, 'Reason', 1000),
      },
    );
    return employeeFromRow(rowFrom(result));
  });

  @override
  Future<InvitationDelivery> createInvitation(
    EmployeeInvitationInput input,
  ) => _scope.safe(() async {
    final email = requiredText(input.email, 'Email', 254).toLowerCase();
    if (!RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]+$').hasMatch(email)) {
      throw const RepositoryFailure(
        RepositoryFailureType.validation,
        'Enter a valid employee email address.',
      );
    }
    final result = await _scope.client.functions.invoke(
      'employee-invitations',
      body: {
        'organization_id': _scope.organizationId,
        'request_id': validateId(input.requestId),
        'email': email,
        'full_name': requiredText(input.fullName, 'Full name', 120, minimum: 2),
        'role': databaseRole(input.role),
        'branch_ids': _validatedBranches(
          input.role,
          input.allBranches,
          input.branchIds,
        ),
        'all_branches': input.allBranches,
        'employee_id': optionalText(input.employeeId, 'Employee ID', 64),
        'phone': optionalText(input.phone, 'Phone', 40),
        'reason': requiredText(input.reason, 'Reason', 1000),
      },
    );
    final row = rowFrom(result.data);
    final state = switch ((result.status, row['delivery_state'])) {
      (200, 'sent') => InvitationDeliveryState.sent,
      (202, 'sending') => InvitationDeliveryState.sending,
      _ => throw const RepositoryFailure(
        RepositoryFailureType.unavailable,
        'Employee email delivery could not be confirmed. Retry the same invitation request shortly.',
      ),
    };
    return InvitationDelivery(
      invitationId: row['invitation_id'] as String,
      expiresAt: DateTime.parse(row['expires_at'] as String),
      state: state,
    );
  });
}

Employee employeeFromRow(Map<String, dynamic> row) => Employee(
  membershipId: row['id'] as String,
  userId: row['user_id'] as String,
  fullName: row['full_name'] as String,
  role: AppRole.fromDatabase(row['role'] as String),
  status: EmployeeStatus.values.byName(row['status'] as String),
  allBranches: row['all_branches'] as bool,
  branchIds: (row['branch_ids'] as List).cast<String>(),
  revision: integerFrom(row['revision']),
  email: row['email'] as String?,
  phone: row['phone'] as String?,
  employeeId: row['employee_id'] as String?,
);
