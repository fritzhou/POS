import '../domain/security_models.dart';
import 'security_wire.dart';

SecurityPolicy securityPolicyFromRow(
  Map<String, dynamic> row, {
  required String organizationId,
}) {
  if (securityId(row, 'organization_id') != organizationId) {
    throw const FormatException('Security policy scope mismatch');
  }
  return SecurityPolicy(
    organizationId: organizationId,
    idleLockMinutes: securityInteger(
      row,
      'idle_lock_minutes',
      minimum: 1,
      maximum: 60,
    ),
    requirePrivilegedMfa: securityBoolean(row, 'require_privileged_mfa'),
    revision: securityInteger(row, 'revision', minimum: 1),
  );
}

SecurityDevice securityDeviceFromRow(
  Map<String, dynamic> row, {
  required String organizationId,
  required String branchId,
}) {
  _scope(row, organizationId, branchId);
  final enrolled = securityTime(row, 'enrolled_at');
  final revoked = securityOptionalTime(row, 'revoked_at');
  if (revoked != null && revoked.isBefore(enrolled)) {
    throw const FormatException('Invalid device revocation time');
  }
  return SecurityDevice(
    deviceId: securityId(row, 'device_id'),
    organizationId: organizationId,
    branchId: branchId,
    actorId: securityId(row, 'actor_id'),
    name: securityText(row, 'device_name'),
    platform: SecurityDevicePlatform.values.byName(
      securityText(row, 'platform', maximum: 10),
    ),
    enrolledAt: enrolled,
    lastSyncAt: securityOptionalTime(row, 'last_sync_at'),
    revokedAt: revoked,
    revocationReason: securityOptionalText(
      row,
      'revocation_reason',
      maximum: 1000,
    ),
    canManage: securityBoolean(row, 'can_manage'),
  );
}

SecurityOfflineGrant securityGrantFromRow(
  Map<String, dynamic> row, {
  required String organizationId,
  required String branchId,
}) {
  _scope(row, organizationId, branchId);
  final issuedAt = securityTime(row, 'issued_at');
  final expiresAt = securityTime(row, 'expires_at');
  if (!expiresAt.isAfter(issuedAt) ||
      expiresAt.difference(issuedAt) > const Duration(hours: 8)) {
    throw const FormatException('Invalid offline grant lifetime');
  }
  final maxEvents = securityInteger(
    row,
    'max_events',
    minimum: 1,
    maximum: 1000,
  );
  final maxTotal = securityInteger(
    row,
    'max_total_minor',
    minimum: 1,
    maximum: 100000000,
  );
  final lastSequence = securityInteger(
    row,
    'last_sequence',
    maximum: maxEvents,
  );
  final outcomeCount = securityInteger(
    row,
    'outcome_count',
    maximum: maxEvents,
  );
  final total = securityInteger(row, 'total_minor', maximum: maxTotal);
  final state = switch (securityText(row, 'state', maximum: 40)) {
    'unsigned' => SecurityGrantState.unsigned,
    'active' => SecurityGrantState.active,
    'expired' => SecurityGrantState.expired,
    'released' => SecurityGrantState.released,
    'administratively_resolved' => SecurityGrantState.administrativelyResolved,
    _ => throw const FormatException('Invalid offline grant state'),
  };
  final releasedAt = securityOptionalTime(row, 'released_at');
  final reviewedAt = securityOptionalTime(row, 'administratively_resolved_at');
  final administrativelyResolved =
      state == SecurityGrantState.administrativelyResolved;
  final remainingEvents = securityInteger(
    row,
    'remaining_exposure_events',
    maximum: maxEvents,
  );
  final remainingMinor = securityInteger(
    row,
    'remaining_exposure_minor',
    maximum: maxTotal,
  );
  if ((state == SecurityGrantState.released) != (releasedAt != null) ||
      administrativelyResolved != (reviewedAt != null) ||
      (administrativelyResolved
          ? outcomeCount > lastSequence ||
                ((outcomeCount == 0) != (lastSequence == 0)) ||
                remainingEvents != maxEvents - outcomeCount ||
                remainingMinor != maxTotal - total
          : outcomeCount != lastSequence)) {
    throw const FormatException('Invalid offline grant outcome state');
  }
  return SecurityOfflineGrant(
    grantId: securityId(row, 'grant_id'),
    organizationId: organizationId,
    branchId: branchId,
    deviceId: securityId(row, 'device_id'),
    actorId: securityId(row, 'actor_id'),
    shiftId: securityId(row, 'shift_id'),
    issuedAt: issuedAt,
    expiresAt: expiresAt,
    maxEvents: maxEvents,
    maxTotalMinor: maxTotal,
    lastSequence: lastSequence,
    outcomeCount: outcomeCount,
    reviewCount: securityInteger(row, 'review_count', maximum: outcomeCount),
    totalMinor: total,
    remainingExposureEvents: remainingEvents,
    remainingExposureMinor: remainingMinor,
    state: state,
    canReview: securityBoolean(row, 'can_review'),
    currency: _currency(row),
    blocksShiftClose: securityBoolean(row, 'blocks_shift_close'),
    releasedAt: releasedAt,
    reviewedAt: reviewedAt,
  );
}

String _currency(Map<String, dynamic> row) {
  final currency = securityText(row, 'currency', maximum: 3, minimum: 3);
  if (!RegExp(r'^[A-Z]{3}$').hasMatch(currency)) {
    throw const FormatException('Invalid grant currency');
  }
  return currency;
}

SecurityNotice securityNoticeFromRow(
  Map<String, dynamic> row, {
  required String organizationId,
  required String branchId,
}) {
  final rowBranch = securityOptionalId(row, 'branch_id');
  if (securityId(row, 'organization_id') != organizationId ||
      (rowBranch != null && rowBranch != branchId)) {
    throw const FormatException('Security notification scope mismatch');
  }
  return SecurityNotice(
    id: securityId(row, 'id'),
    organizationId: organizationId,
    branchId: rowBranch,
    action: securityText(row, 'action', maximum: 100),
    title: securityText(row, 'title', maximum: 200),
    message: securityText(row, 'message', maximum: 2000),
    occurredAt: securityTime(row, 'created_at'),
    readAt: securityOptionalTime(row, 'read_at'),
  );
}

void _scope(Map<String, dynamic> row, String org, String branch) {
  if (securityId(row, 'organization_id') != org ||
      securityId(row, 'branch_id') != branch) {
    throw const FormatException('Security record scope mismatch');
  }
}
