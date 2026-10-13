import '../../catalog/domain/repository_support.dart';

class SecurityPolicy {
  const SecurityPolicy({
    required this.organizationId,
    required this.idleLockMinutes,
    required this.requirePrivilegedMfa,
    required this.revision,
  });

  final String organizationId;
  final int idleLockMinutes;
  final bool requirePrivilegedMfa;
  final int revision;
}

enum SecurityDevicePlatform { android, windows, linux, macos, ios }

class SecurityDevice {
  const SecurityDevice({
    required this.deviceId,
    required this.organizationId,
    required this.branchId,
    required this.actorId,
    required this.name,
    required this.platform,
    required this.enrolledAt,
    required this.canManage,
    this.lastSyncAt,
    this.revokedAt,
    this.revocationReason,
  });

  final String deviceId;
  final String organizationId;
  final String branchId;
  final String actorId;
  final String name;
  final SecurityDevicePlatform platform;
  final DateTime enrolledAt;
  final bool canManage;
  final DateTime? lastSyncAt;
  final DateTime? revokedAt;
  final String? revocationReason;
  bool get revoked => revokedAt != null;
}

class SecurityOfflineGrant {
  const SecurityOfflineGrant({
    required this.grantId,
    required this.organizationId,
    required this.branchId,
    required this.deviceId,
    required this.actorId,
    required this.shiftId,
    required this.issuedAt,
    required this.expiresAt,
    required this.lastSequence,
    required this.totalMinor,
    required this.maxEvents,
    required this.maxTotalMinor,
    required this.outcomeCount,
    required this.reviewCount,
    required this.remainingExposureEvents,
    required this.remainingExposureMinor,
    required this.state,
    required this.canReview,
    required this.currency,
    required this.blocksShiftClose,
    this.releasedAt,
    this.reviewedAt,
  });

  final String grantId;
  final String organizationId;
  final String branchId;
  final String deviceId;
  final String actorId;
  final String shiftId;
  final DateTime issuedAt;
  final DateTime expiresAt;
  final int lastSequence;
  final int totalMinor;
  final int maxEvents;
  final int maxTotalMinor;
  final int outcomeCount;
  final int reviewCount;
  final int remainingExposureEvents;
  final int remainingExposureMinor;
  final SecurityGrantState state;
  final bool canReview;
  final String currency;
  final bool blocksShiftClose;
  final DateTime? releasedAt;
  final DateTime? reviewedAt;
}

enum SecurityGrantState {
  unsigned,
  active,
  expired,
  released,
  administrativelyResolved,
}

/// A notice is an authorized projection of a persisted server security event.
/// It is not an email delivery acknowledgement or client login telemetry.
class SecurityNotice {
  const SecurityNotice({
    required this.id,
    required this.organizationId,
    required this.action,
    required this.title,
    required this.message,
    required this.occurredAt,
    this.branchId,
    this.readAt,
  });

  final String id;
  final String organizationId;
  final String? branchId;
  final String action;
  final String title;
  final String message;
  final DateTime occurredAt;
  final DateTime? readAt;
}

enum SecurityMutationKind { revokeDevice, renameDevice, reviewGrant, policy }

/// A single immutable administrative request retained across uncertainty.
/// Plaintext credentials, MFA codes and employee PINs never belong here.
class SecurityMutation {
  const SecurityMutation._({
    required this.requestId,
    required this.kind,
    required this.reason,
    this.branchId,
    this.recordId,
    this.deviceName,
    this.acknowledgeUnknownPaidEvents = false,
    this.expectedRevision,
    this.idleLockMinutes,
    this.requirePrivilegedMfa,
    this.expectedLastSequence,
    this.expectedOutcomeCount,
    this.expectedTotalMinor,
  });

  factory SecurityMutation.revokeDevice({
    required String requestId,
    required String branchId,
    required String deviceId,
    required String reason,
  }) => SecurityMutation._(
    requestId: requestId,
    kind: SecurityMutationKind.revokeDevice,
    branchId: branchId,
    recordId: deviceId,
    reason: reason,
  );

  factory SecurityMutation.renameDevice({
    required String requestId,
    required String branchId,
    required String deviceId,
    required String deviceName,
    required String reason,
  }) => SecurityMutation._(
    requestId: requestId,
    kind: SecurityMutationKind.renameDevice,
    branchId: branchId,
    recordId: deviceId,
    deviceName: deviceName,
    reason: reason,
  );

  factory SecurityMutation.reviewGrant({
    required String requestId,
    required String branchId,
    required String grantId,
    required String reason,
    required bool acknowledgeUnknownPaidEvents,
    required int expectedLastSequence,
    required int expectedOutcomeCount,
    required int expectedTotalMinor,
  }) => SecurityMutation._(
    requestId: requestId,
    kind: SecurityMutationKind.reviewGrant,
    branchId: branchId,
    recordId: grantId,
    reason: reason,
    acknowledgeUnknownPaidEvents: acknowledgeUnknownPaidEvents,
    expectedLastSequence: expectedLastSequence,
    expectedOutcomeCount: expectedOutcomeCount,
    expectedTotalMinor: expectedTotalMinor,
  );

  factory SecurityMutation.policy({
    required String requestId,
    required int expectedRevision,
    required int idleLockMinutes,
    required bool requirePrivilegedMfa,
    required String reason,
  }) => SecurityMutation._(
    requestId: requestId,
    kind: SecurityMutationKind.policy,
    expectedRevision: expectedRevision,
    idleLockMinutes: idleLockMinutes,
    requirePrivilegedMfa: requirePrivilegedMfa,
    reason: reason,
  );

  final String requestId;
  final SecurityMutationKind kind;
  final String reason;
  final String? branchId;
  final String? recordId;
  final String? deviceName;
  final bool acknowledgeUnknownPaidEvents;
  final int? expectedRevision;
  final int? idleLockMinutes;
  final bool? requirePrivilegedMfa;
  final int? expectedLastSequence;
  final int? expectedOutcomeCount;
  final int? expectedTotalMinor;

  String get function => switch (kind) {
    SecurityMutationKind.revokeDevice => 'revoke_security_device',
    SecurityMutationKind.renameDevice => 'update_security_device',
    SecurityMutationKind.reviewGrant => 'review_offline_grant',
    SecurityMutationKind.policy => 'update_security_policy',
  };

  Map<String, dynamic> parameters(String organizationId) {
    final values = <String, dynamic>{
      'p_organization_id': validateId(organizationId).toLowerCase(),
      'p_request_id': validateId(requestId).toLowerCase(),
      'p_reason': requiredText(reason, 'Reason', 1000, minimum: 3),
    };
    if (kind == SecurityMutationKind.policy) {
      if (expectedRevision == null ||
          expectedRevision! < 1 ||
          expectedRevision! >= 9007199254740991) {
        throw const RepositoryFailure(
          RepositoryFailureType.validation,
          'Reload the current security policy before saving.',
        );
      }
      final minutes = idleLockMinutes;
      if (minutes == null || minutes < 1 || minutes > 60) {
        throw const RepositoryFailure(
          RepositoryFailureType.validation,
          'Idle lock must be between 1 and 60 minutes.',
        );
      }
      values.addAll({
        'p_expected_revision': validateRevision(expectedRevision!),
        'p_idle_lock_minutes': minutes,
        'p_require_privileged_mfa': requirePrivilegedMfa!,
      });
    } else {
      values['p_branch_id'] = validateId(branchId!).toLowerCase();
      if (kind == SecurityMutationKind.reviewGrant) {
        if (!acknowledgeUnknownPaidEvents) {
          throw const RepositoryFailure(
            RepositoryFailureType.validation,
            'Acknowledge the unresolved payment risk before reviewing this grant.',
          );
        }
        values['p_grant_id'] = validateId(recordId!).toLowerCase();
        values['p_acknowledge_unknown_paid_events'] = true;
        if (expectedLastSequence == null ||
            expectedLastSequence! < 0 ||
            expectedLastSequence! > 1000 ||
            expectedOutcomeCount == null ||
            expectedOutcomeCount! < 0 ||
            expectedOutcomeCount! > 1000 ||
            expectedTotalMinor == null ||
            expectedTotalMinor! < 0 ||
            expectedTotalMinor! > 100000000) {
          throw const RepositoryFailure(
            RepositoryFailureType.validation,
            'Reload the paid outcome summary before reviewing this grant.',
          );
        }
        values['p_expected_last_sequence'] = expectedLastSequence;
        values['p_expected_outcome_count'] = expectedOutcomeCount;
        values['p_expected_total_minor'] = expectedTotalMinor;
      } else {
        values['p_device_id'] = validateId(recordId!).toLowerCase();
        if (kind == SecurityMutationKind.renameDevice) {
          values['p_device_name'] = requiredText(
            deviceName!,
            'Device name',
            120,
          );
        }
      }
    }
    return Map.unmodifiable(values);
  }
}

class SecurityMutationResult {
  const SecurityMutationResult({
    required this.requestId,
    required this.kind,
    this.policy,
    this.device,
    this.grant,
  });
  final String requestId;
  final SecurityMutationKind kind;
  final SecurityPolicy? policy;
  final SecurityDevice? device;
  final SecurityOfflineGrant? grant;
}
