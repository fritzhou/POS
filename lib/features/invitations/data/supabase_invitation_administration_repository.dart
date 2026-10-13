import 'dart:convert';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/auth/auth_models.dart';
import '../../../core/operations/operation_journal.dart';
import '../../../core/security/app_role.dart';
import '../../administration/data/supabase_employee_repository.dart';
import '../../administration/domain/administration_models.dart';
import '../../administration/domain/administration_repository.dart';
import '../../catalog/data/supabase_repository_support.dart';
import '../../catalog/domain/repository_support.dart';
import '../../checkout/data/operation_executor.dart';
import '../domain/invitation_models.dart';
import '../domain/invitation_repository.dart';

class SupabaseInvitationAdministrationRepository
    implements InvitationAdministrationRepository {
  SupabaseInvitationAdministrationRepository({
    required SupabaseClient client,
    required AuthenticatedUser actor,
    required OperationJournal journal,
    bool Function()? isRecoverySession,
    EmployeeRepository? employeeRepository,
  }) : _scope = SupabaseRepositoryScope(
         client: client,
         actor: actor,
         isRecoverySession: isRecoverySession,
       ),
       _employees =
           employeeRepository ??
           SupabaseEmployeeRepository(
             client: client,
             actor: actor,
             isRecoverySession: isRecoverySession,
           ) {
    _operations = OperationExecutor(
      _scope,
      journal,
      allowHistoricalJournalBranch: true,
    );
  }
  final SupabaseRepositoryScope _scope;
  final EmployeeRepository _employees;
  late final OperationExecutor _operations;
  static const operationType = 'revoke_employee_invitation_action';

  @override
  String get organizationId => _scope.organizationId;
  @override
  Set<String> get branchIds => Set.unmodifiable(_scope.actor.branchIds);

  void _requireAdmin() {
    _scope.requireIdentity();
    if (![AppRole.owner, AppRole.admin].contains(_scope.actor.role)) {
      throw const RepositoryFailure(
        RepositoryFailureType.permissionDenied,
        'An active Owner or Admin membership is required.',
      );
    }
  }

  ManagedInvitation _decodeInvitation(Object? data) {
    final record = ManagedInvitation.fromRow(rowFrom(data));
    invitationCheck(record.organizationId == organizationId);
    invitationCheck(
      !record.canRetryDelivery || record.invitedBy == _scope.actor.userId,
    );
    if (_scope.actor.role != AppRole.owner) {
      invitationCheck(record.role != AppRole.admin || !record.canRevoke);
    }
    return record;
  }

  @override
  Future<DataPage<ManagedInvitation>> listInvitations({
    InvitationFilter filter = const InvitationFilter(),
    PageRequest page = const PageRequest(),
  }) => _scope.safe(() async {
    _requireAdmin();
    page.validate();
    if (page.limit > 99) {
      throw const RepositoryFailure(
        RepositoryFailureType.validation,
        'Choose an invitation page size between 1 and 99.',
      );
    }
    final response = await _scope.client.rpc(
      'list_managed_employee_invitations',
      params: {
        'p_organization_id': organizationId,
        'p_search': filter.validatedSearch(),
        'p_status': filter.status?.name,
        'p_offset': page.offset,
        'p_limit': page.limit + 1,
      },
    );
    final rows = rowsFrom(response);
    invitationCheck(rows.length <= page.limit + 1);
    final records = rows.map(_decodeInvitation).toList(growable: false);
    invitationCheck(records.map((r) => r.id).toSet().length == records.length);
    return DataPage(
      items: records.take(page.limit).toList(growable: false),
      hasMore: records.length > page.limit,
      offset: page.offset,
    );
  });

  @override
  Future<ManagedInvitation> invitation(String invitationId) =>
      _scope.safe(() async {
        _requireAdmin();
        final id = validateId(invitationId).toLowerCase();
        final response = await _scope.client.rpc(
          'get_managed_employee_invitation',
          params: {'p_organization_id': organizationId, 'p_invitation_id': id},
        );
        final record = _decodeInvitation(response);
        invitationCheck(
          record.id == id &&
              (!record.canRetryDelivery || record.retryInput != null),
        );
        return record;
      });

  @override
  Future<List<PendingOperation>> pending() => _scope.safe(() async {
    _requireAdmin();
    return _operations.pending(type: operationType);
  });

  @override
  Future<InvitationRevocation> revoke({
    required ManagedInvitation original,
    required String reason,
    required String requestId,
  }) => _scope.safe(() async {
    _requireAdmin();
    if (original.organizationId != organizationId ||
        !original.canRevoke ||
        original.status != ManagedInvitationStatus.pending ||
        (_scope.actor.role == AppRole.admin &&
            original.role == AppRole.admin)) {
      throw const RepositoryFailure(
        RepositoryFailureType.permissionDenied,
        'This invitation cannot be revoked by your current account.',
      );
    }
    final id = validateId(requestId).toLowerCase();
    final unresolved = await pending();
    if (unresolved.any((op) => op.requestId != id)) {
      throw const RepositoryFailure(
        RepositoryFailureType.conflict,
        'Resolve the original saved invitation request first.',
      );
    }
    final anchor = branchIds.toList()..sort();
    return _revoke(anchor.first, {
      'p_organization_id': organizationId,
      'p_invitation_id': original.id,
      'p_request_id': id,
      'p_expected_revision': original.revision,
      'p_reason': requiredText(reason, 'Reason', 500, minimum: 3),
    });
  });

  Future<InvitationRevocation> _revoke(
    String anchor,
    Map<String, dynamic> params,
  ) async {
    final id = invitationId(params['p_invitation_id']);
    final request = invitationId(params['p_request_id']);
    final revision = invitationRevision(params['p_expected_revision']);
    invitationCheck(
      params.length == 5 && params['p_organization_id'] == organizationId,
    );
    requiredText(params['p_reason'] as String, 'Reason', 500, minimum: 3);
    return _operations.mutate(
      function: operationType,
      branchId: anchor,
      params: params,
      decode: (row) {
        final result = InvitationRevocation.fromRow(row);
        invitationCheck(
          result.requestId == request &&
              result.organizationId == organizationId &&
              result.actorId == _scope.actor.userId &&
              result.invitation.id == id &&
              result.invitation.revision == revision + 1,
        );
        return result;
      },
    );
  }

  @override
  Future<InvitationRevocation> retry(PendingOperation operation) =>
      _scope.safe(() async {
        _requireAdmin();
        if (operation.type != operationType ||
            operation.status != LocalOperationStatus.pending ||
            operation.organizationId != organizationId ||
            operation.actorId != _scope.actor.userId ||
            operation.payload['p_request_id'] != operation.requestId) {
          throw const RepositoryFailure(
            RepositoryFailureType.permissionDenied,
            'This saved request belongs to its original account.',
          );
        }
        return _revoke(operation.branchId, Map.of(operation.payload));
      });

  @override
  Future<InvitationDelivery> retryDelivery(
    ManagedInvitation original,
  ) => _scope.safe(() async {
    _requireAdmin();
    if (original.organizationId != organizationId ||
        original.invitedBy != _scope.actor.userId ||
        !original.canRetryDelivery ||
        original.retryInput == null ||
        (await pending()).isNotEmpty) {
      throw const RepositoryFailure(
        RepositoryFailureType.permissionDenied,
        'This invitation cannot be retried by your current account.',
      );
    }
    // Hydrate current authority and preserve the exact original Edge payload.
    // Never infer a replacement request from display metadata.
    final current = await invitation(original.id);
    if (!current.canRetryDelivery ||
        current.retryInput == null ||
        jsonEncode(current.retryInput) != jsonEncode(original.retryInput)) {
      throw const RepositoryFailure(
        RepositoryFailureType.conflict,
        'Reload this invitation before retrying its original email request.',
      );
    }
    final input = current.retryInput!;
    final result = await _employees.createInvitation(
      EmployeeInvitationInput(
        requestId: input['request_id'] as String,
        email: input['email'] as String,
        fullName: input['full_name'] as String,
        role: current.role,
        branchIds: (input['branch_ids'] as List).cast<String>(),
        allBranches: input['all_branches'] as bool,
        employeeId: input['employee_id'] as String?,
        phone: input['phone'] as String?,
        reason: input['reason'] as String,
      ),
    );
    invitationCheck(
      result.invitationId == original.id &&
          result.expiresAt.toUtc() == original.expiresAt,
    );
    return result;
  });
}
