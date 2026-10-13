import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/auth/auth_models.dart';
import '../../../core/operations/operation_journal.dart';
import '../../../core/security/app_role.dart';
import '../../catalog/data/supabase_repository_support.dart';
import '../../catalog/domain/repository_support.dart';
import '../../checkout/data/operation_executor.dart';
import '../domain/security_models.dart';
import '../domain/security_repository.dart';
import 'security_decoders.dart';
import 'security_wire.dart';

class SupabaseSecurityRepository implements SecurityRepository {
  SupabaseSecurityRepository({
    required SupabaseClient client,
    required AuthenticatedUser actor,
    this.journal,
    bool Function()? isRecoverySession,
  }) : _scope = SupabaseRepositoryScope(
         client: client,
         actor: actor,
         isRecoverySession: isRecoverySession,
       );

  final SupabaseRepositoryScope _scope;
  final OperationJournal? journal;
  OperationExecutor get _operations => OperationExecutor(_scope, journal);
  @override
  String get organizationId => _scope.organizationId.toLowerCase();
  @override
  Set<String> get branchIds =>
      Set.unmodifiable(_scope.actor.branchIds.map((id) => id.toLowerCase()));

  @override
  Future<SecurityPolicy> loadPolicy() => _scope.safe(
    () async => securityPolicyFromRow(
      securityRow(
        await _scope.client.rpc(
          'get_security_policy',
          params: {'p_organization_id': organizationId},
        ),
      ),
      organizationId: organizationId,
    ),
  );

  @override
  Future<DataPage<SecurityDevice>> listDevices({
    required String branchId,
    PageRequest page = const PageRequest(),
  }) => _list(
    'list_security_devices',
    branchId,
    page,
    (row) => securityDeviceFromRow(
      row,
      organizationId: organizationId,
      branchId: branchId.toLowerCase(),
    ),
  );

  @override
  Future<DataPage<SecurityOfflineGrant>> listGrants({
    required String branchId,
    PageRequest page = const PageRequest(),
  }) => _list(
    'list_security_grants',
    branchId,
    page,
    (row) => securityGrantFromRow(
      row,
      organizationId: organizationId,
      branchId: branchId.toLowerCase(),
    ),
  );

  @override
  Future<DataPage<SecurityNotice>> listNotices({
    required String branchId,
    PageRequest page = const PageRequest(),
  }) => _list(
    'list_security_notifications',
    branchId,
    page,
    (row) => securityNoticeFromRow(
      row,
      organizationId: organizationId,
      branchId: branchId.toLowerCase(),
    ),
  );

  Future<DataPage<T>> _list<T>(
    String function,
    String branchId,
    PageRequest page,
    T Function(Map<String, dynamic>) decode,
  ) => _scope.safe(() async {
    _branch(branchId);
    page.validate();
    final wireLimit = page.limit < 100 ? page.limit + 1 : 100;
    final rows = securityRows(
      await _scope.client.rpc(
        function,
        params: {
          'p_organization_id': organizationId,
          'p_branch_id': branchId.toLowerCase(),
          'p_offset': page.offset,
          'p_limit': wireLimit,
        },
      ),
      maximum: wireLimit,
    );
    // Validate the overfetched record too: a cross-tenant sentinel is not a
    // harmless pagination hint. A full 100-row page may have an empty next page.
    final items = rows.map(decode).toList(growable: false);
    return DataPage(
      items: items.take(page.limit).toList(growable: false),
      hasMore:
          items.length > page.limit ||
          (page.limit == 100 && items.length == 100),
      offset: page.offset,
    );
  });

  void _branch(String branchId) {
    validateId(branchId);
    if (!branchIds.contains(branchId.toLowerCase())) {
      throw const RepositoryFailure(
        RepositoryFailureType.permissionDenied,
        'Choose a currently authorized branch.',
      );
    }
  }

  @override
  Future<SecurityMutationResult> mutate(
    SecurityMutation mutation,
  ) => _scope.safe(() async {
    if (!_scope.actor.role.allows(AppPermission.manageSecurity)) {
      throw const RepositoryFailure(
        RepositoryFailureType.permissionDenied,
        'An owner or admin must manage business security.',
      );
    }
    if (journal == null) {
      throw const RepositoryFailure(
        RepositoryFailureType.notConnected,
        'Durable security request storage is unavailable. Restore local storage before making this change.',
      );
    }
    final params = mutation.parameters(organizationId);
    final branch = mutation.branchId?.toLowerCase() ?? branchIds.first;
    _branch(branch);
    return _operations.mutate(
      function: mutation.function,
      branchId: branch,
      params: params,
      decode: (row) => _decodeMutation(mutation, row),
    );
  });

  SecurityMutationResult _decodeMutation(
    SecurityMutation mutation,
    Map<String, dynamic> row,
  ) {
    final branch = mutation.branchId?.toLowerCase();
    if (mutation.kind == SecurityMutationKind.policy) {
      final policy = securityPolicyFromRow(row, organizationId: organizationId);
      if (policy.idleLockMinutes != mutation.idleLockMinutes ||
          policy.requirePrivilegedMfa != mutation.requirePrivilegedMfa ||
          policy.revision < mutation.expectedRevision! + 1) {
        throw const FormatException('Policy result does not match request');
      }
      return SecurityMutationResult(
        requestId: mutation.requestId,
        kind: mutation.kind,
        policy: policy,
      );
    }
    if (mutation.kind == SecurityMutationKind.reviewGrant) {
      final grant = securityGrantFromRow(
        row,
        organizationId: organizationId,
        branchId: branch!,
      );
      if (grant.grantId != mutation.recordId!.toLowerCase() ||
          grant.state != SecurityGrantState.administrativelyResolved ||
          grant.reviewedAt == null ||
          grant.lastSequence != mutation.expectedLastSequence ||
          grant.outcomeCount != mutation.expectedOutcomeCount ||
          grant.totalMinor != mutation.expectedTotalMinor) {
        throw const FormatException('Grant result does not match review');
      }
      return SecurityMutationResult(
        requestId: mutation.requestId,
        kind: mutation.kind,
        grant: grant,
      );
    }
    final device = securityDeviceFromRow(
      row,
      organizationId: organizationId,
      branchId: branch!,
    );
    if (device.deviceId != mutation.recordId!.toLowerCase() ||
        (mutation.kind == SecurityMutationKind.renameDevice &&
            device.name != mutation.deviceName!.trim()) ||
        (mutation.kind == SecurityMutationKind.revokeDevice &&
            device.revokedAt == null)) {
      throw const FormatException('Device result does not match request');
    }
    return SecurityMutationResult(
      requestId: mutation.requestId,
      kind: mutation.kind,
      device: device,
    );
  }

  @override
  Future<List<SecurityMutation>> pendingMutations() => _scope.safe(() async {
    final pending = await _operations.pending();
    final result = <SecurityMutation>[];
    for (final operation in pending) {
      if (!const {
        'revoke_security_device',
        'update_security_device',
        'review_offline_grant',
        'update_security_policy',
      }.contains(operation.type)) {
        continue;
      }
      final values = operation.payload;
      if (values['p_organization_id'] != organizationId ||
          values['p_request_id'] != operation.requestId) {
        throw const FormatException('Saved security request scope mismatch');
      }
      _branch(operation.branchId);
      final mutation = _restore(operation.type, values);
      // Validate restored values before showing a recovery action.
      mutation.parameters(organizationId);
      result.add(mutation);
    }
    return List.unmodifiable(result);
  });

  SecurityMutation _restore(String type, Map<String, dynamic> values) {
    final requestId = securityId(values, 'p_request_id');
    final reason = securityText(values, 'p_reason', maximum: 1000, minimum: 3);
    if (type == 'update_security_policy') {
      return SecurityMutation.policy(
        requestId: requestId,
        expectedRevision: securityInteger(
          values,
          'p_expected_revision',
          minimum: 1,
        ),
        idleLockMinutes: securityInteger(
          values,
          'p_idle_lock_minutes',
          minimum: 1,
          maximum: 60,
        ),
        requirePrivilegedMfa: securityBoolean(
          values,
          'p_require_privileged_mfa',
        ),
        reason: reason,
      );
    }
    final branch = securityId(values, 'p_branch_id');
    _branch(branch);
    if (type == 'review_offline_grant') {
      return SecurityMutation.reviewGrant(
        requestId: requestId,
        branchId: branch,
        grantId: securityId(values, 'p_grant_id'),
        reason: reason,
        acknowledgeUnknownPaidEvents: securityBoolean(
          values,
          'p_acknowledge_unknown_paid_events',
        ),
        expectedLastSequence: securityInteger(
          values,
          'p_expected_last_sequence',
          maximum: 1000,
        ),
        expectedOutcomeCount: securityInteger(
          values,
          'p_expected_outcome_count',
          maximum: 1000,
        ),
        expectedTotalMinor: securityInteger(
          values,
          'p_expected_total_minor',
          maximum: 100000000,
        ),
      );
    }
    final device = securityId(values, 'p_device_id');
    return type == 'revoke_security_device'
        ? SecurityMutation.revokeDevice(
            requestId: requestId,
            branchId: branch,
            deviceId: device,
            reason: reason,
          )
        : SecurityMutation.renameDevice(
            requestId: requestId,
            branchId: branch,
            deviceId: device,
            deviceName: securityText(values, 'p_device_name'),
            reason: reason,
          );
  }

  @override
  Future<DateTime> markNoticeRead({
    required String branchId,
    required String noticeId,
  }) => _scope.safe(() async {
    _branch(branchId);
    final id = validateId(noticeId).toLowerCase();
    final row = securityRow(
      await _scope.client.rpc(
        'mark_security_notification_read',
        params: {
          'p_organization_id': organizationId,
          'p_branch_id': branchId.toLowerCase(),
          'p_notification_id': id,
        },
      ),
    );
    if (securityId(row, 'id') != id) {
      throw const FormatException('Security notification response mismatch');
    }
    return securityTime(row, 'read_at');
  });
}
