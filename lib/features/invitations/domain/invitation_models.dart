import '../../../core/security/app_role.dart';
import '../../administration/domain/administration_models.dart';
import '../../catalog/domain/repository_support.dart';

enum ManagedInvitationStatus { pending, accepted, revoked, expired }

enum ManagedInvitationDelivery { prepared, sending, sent, failed }

String invitationId(Object? value) {
  if (value is! String) throw const FormatException('Expected identifier');
  return validateId(value).toLowerCase();
}

String invitationText(Object? value, int maximum, {int minimum = 1}) {
  if (value is! String ||
      value != value.trim() ||
      value.length < minimum ||
      value.length > maximum) {
    throw const FormatException('Expected bounded invitation text');
  }
  return value;
}

int invitationRevision(Object? value) {
  if (value is! int || value < 1 || value > 9007199254740991) {
    throw const FormatException('Expected exact revision');
  }
  return value;
}

DateTime invitationTime(Object? value) {
  if (value is! String ||
      !RegExp(
        r'^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}(?:\.\d{1,6})?(?:Z|\+00:00)$',
      ).hasMatch(value)) {
    throw const FormatException('Expected UTC invitation time');
  }
  final date = DateTime.parse(value);
  if (!date.isUtc ||
      date.toIso8601String().substring(0, 19) != value.substring(0, 19)) {
    throw const FormatException('Invalid UTC calendar');
  }
  return date;
}

Map<String, dynamic> invitationRow(Object? value) {
  if (value is! Map<String, dynamic>) {
    throw const FormatException('Expected invitation record');
  }
  return value;
}

void invitationCheck(bool condition) {
  if (!condition) {
    throw const FormatException('Inconsistent invitation evidence');
  }
}

class InvitationBranch {
  InvitationBranch.fromRow(Map<String, dynamic> row)
    : id = invitationId(row['id']),
      name = invitationText(row['name'], 120),
      active = row['active'] as bool;
  final String id, name;
  final bool active;
}

/// Server capabilities are current authorization hints. Every mutation repeats
/// the current membership, branch and MFA checks in PostgreSQL.
class ManagedInvitation {
  ManagedInvitation.fromRow(Map<String, dynamic> row)
    : id = invitationId(row['id']),
      organizationId = invitationId(row['organization_id']),
      invitedBy = invitationId(row['invited_by']),
      revision = invitationRevision(row['revision']),
      email = invitationText(row['normalized_email'], 254),
      fullName = invitationText(row['full_name'], 120, minimum: 2),
      role = AppRole.fromDatabase(invitationText(row['requested_role'], 32)),
      employeeId = row['employee_id'] == null
          ? null
          : invitationText(row['employee_id'], 64),
      phone = row['phone'] == null ? null : invitationText(row['phone'], 40),
      allBranches = row['all_branches'] as bool,
      branchIds = List.unmodifiable(
        (row['branch_ids'] as List).map(invitationId),
      ),
      branches = List.unmodifiable(
        (row['branches'] as List).map(
          (r) => InvitationBranch.fromRow(invitationRow(r)),
        ),
      ),
      createdAt = invitationTime(row['created_at']),
      expiresAt = invitationTime(row['expires_at']),
      acceptedAt = row['accepted_at'] == null
          ? null
          : invitationTime(row['accepted_at']),
      revokedAt = row['revoked_at'] == null
          ? null
          : invitationTime(row['revoked_at']),
      delivery = ManagedInvitationDelivery.values.byName(
        invitationText(row['delivery_state'], 16),
      ),
      deliveryClaimedAt = row['delivery_claimed_at'] == null
          ? null
          : invitationTime(row['delivery_claimed_at']),
      deliveryFinishedAt = row['delivery_finished_at'] == null
          ? null
          : invitationTime(row['delivery_finished_at']),
      status = ManagedInvitationStatus.values.byName(
        invitationText(row['status'], 16),
      ),
      canRevoke = row['can_revoke'] as bool,
      canRetryDelivery = row['can_retry_delivery'] as bool,
      retryInput = row['retry_input'] == null
          ? null
          : _retryInput(invitationRow(row['retry_input'])) {
    invitationCheck(
      role != AppRole.owner &&
          email == email.toLowerCase() &&
          RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]+$').hasMatch(email),
    );
    invitationCheck(
      branchIds.length <= 100 &&
          branches.length <= 100 &&
          branchIds.toSet().length == branchIds.length &&
          branches.map((b) => b.id).toSet().length == branches.length,
    );
    invitationCheck(
      branchIds.toSet().containsAll(branches.map((b) => b.id)) &&
          branchIds.length == branches.length,
    );
    invitationCheck(
      allBranches
          ? role == AppRole.admin && branchIds.isEmpty
          : branchIds.isNotEmpty || !canRevoke && !canRetryDelivery,
    );
    invitationCheck(expiresAt.isAfter(createdAt));
    invitationCheck(acceptedAt == null || !acceptedAt!.isBefore(createdAt));
    invitationCheck(revokedAt == null || !revokedAt!.isBefore(createdAt));
    invitationCheck(switch (delivery) {
      ManagedInvitationDelivery.prepared =>
        deliveryClaimedAt == null && deliveryFinishedAt == null,
      ManagedInvitationDelivery.sending =>
        deliveryClaimedAt != null && deliveryFinishedAt == null,
      ManagedInvitationDelivery.sent || ManagedInvitationDelivery.failed =>
        deliveryClaimedAt != null && deliveryFinishedAt != null,
    });
    invitationCheck(
      deliveryClaimedAt == null || !deliveryClaimedAt!.isBefore(createdAt),
    );
    invitationCheck(
      deliveryFinishedAt == null ||
          !deliveryFinishedAt!.isBefore(deliveryClaimedAt!),
    );
    invitationCheck(switch (status) {
      ManagedInvitationStatus.accepted =>
        acceptedAt != null && revokedAt == null,
      ManagedInvitationStatus.revoked =>
        revokedAt != null && acceptedAt == null,
      _ => acceptedAt == null && revokedAt == null,
    });
    invitationCheck(!canRevoke || status == ManagedInvitationStatus.pending);
    invitationCheck(
      !canRetryDelivery ||
          status == ManagedInvitationStatus.pending &&
              [
                ManagedInvitationDelivery.prepared,
                ManagedInvitationDelivery.failed,
              ].contains(delivery),
    );
    if (retryInput != null) {
      final input = retryInput!;
      invitationCheck(
        canRetryDelivery &&
            input['organization_id'] == organizationId &&
            input['email'] == email &&
            input['full_name'] == fullName &&
            input['role'] == databaseRole(role) &&
            input['all_branches'] == allBranches &&
            input['employee_id'] == employeeId &&
            input['phone'] == phone,
      );
      final retryBranches = (input['branch_ids'] as List).cast<String>();
      invitationCheck(
        retryBranches.length == branchIds.length &&
            retryBranches.toSet().containsAll(branchIds),
      );
    }
  }

  final String id, organizationId, invitedBy, email, fullName;
  final String? employeeId, phone;
  final int revision;
  final AppRole role;
  final bool allBranches, canRevoke, canRetryDelivery;
  final List<String> branchIds;
  final List<InvitationBranch> branches;
  final DateTime createdAt, expiresAt;
  final DateTime? acceptedAt, revokedAt, deliveryClaimedAt, deliveryFinishedAt;
  final ManagedInvitationDelivery delivery;
  final ManagedInvitationStatus status;
  final Map<String, dynamic>? retryInput;

  static Map<String, dynamic> _retryInput(Map<String, dynamic> row) {
    const keys = {
      'organization_id',
      'request_id',
      'email',
      'full_name',
      'role',
      'branch_ids',
      'all_branches',
      'employee_id',
      'phone',
      'reason',
    };
    invitationCheck(row.length == keys.length && keys.containsAll(row.keys));
    return Map.unmodifiable({
      'organization_id': invitationId(row['organization_id']),
      'request_id': invitationId(row['request_id']),
      'email': invitationText(row['email'], 254),
      'full_name': invitationText(row['full_name'], 120, minimum: 2),
      'role': invitationText(row['role'], 32),
      'branch_ids': List.unmodifiable(
        (row['branch_ids'] as List).map(invitationId),
      ),
      'all_branches': row['all_branches'] as bool,
      'employee_id': row['employee_id'] == null
          ? null
          : invitationText(row['employee_id'], 64),
      'phone': row['phone'] == null ? null : invitationText(row['phone'], 40),
      'reason': invitationText(row['reason'], 500, minimum: 2),
    });
  }
}

class InvitationFilter {
  const InvitationFilter({this.search, this.status});
  final String? search;
  final ManagedInvitationStatus? status;
  String? validatedSearch() {
    final value = optionalText(search, 'Search', 254);
    if (value != null && RegExp(r'[\x00-\x1f\x7f]').hasMatch(value)) {
      throw const RepositoryFailure(
        RepositoryFailureType.validation,
        'Search cannot contain control characters.',
      );
    }
    return value;
  }
}

class InvitationRevocation {
  InvitationRevocation.fromRow(Map<String, dynamic> row)
    : requestId = invitationId(row['request_id']),
      organizationId = invitationId(row['organization_id']),
      actorId = invitationId(row['actor_id']),
      invitation = ManagedInvitation.fromRow(invitationRow(row['invitation'])) {
    invitationCheck(
      row['kind'] == 'invitation.revoke' &&
          invitation.organizationId == organizationId &&
          invitation.status == ManagedInvitationStatus.revoked,
    );
  }
  final String requestId, organizationId, actorId;
  final ManagedInvitation invitation;
}
