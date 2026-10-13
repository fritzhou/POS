import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/auth/auth_models.dart';
import '../../core/security/app_role.dart';
import '../catalog/data/supabase_repository_support.dart';
import '../catalog/domain/repository_support.dart';

class EmployeePinStatus {
  const EmployeePinStatus({
    required this.membershipId,
    required this.configured,
    required this.resetRequired,
    required this.revision,
    this.lockedUntil,
    this.changedAt,
  });
  final String membershipId;
  final bool configured;
  final bool resetRequired;
  final int revision;
  final DateTime? lockedUntil;
  final DateTime? changedAt;
}

class EmployeePinResult {
  const EmployeePinResult({required this.accepted, required this.status});
  final bool accepted;
  final EmployeePinStatus status;
}

class EmployeePinResetTarget {
  const EmployeePinResetTarget({
    required this.membershipId,
    required this.fullName,
    required this.role,
    required this.status,
  });
  final String membershipId;
  final String fullName;
  final AppRole role;
  final EmployeePinStatus status;
}

abstract interface class EmployeePinRepository {
  String get organizationId;
  Future<EmployeePinStatus> status({String? membershipId});
  Future<DataPage<EmployeePinResetTarget>> resetTargets({
    PageRequest page = const PageRequest(),
  });
  Future<EmployeePinResult> setPin({
    required String requestId,
    required int expectedRevision,
    required String pin,
    String? currentPin,
  });

  /// This is a supplemental online check, not a session or operation approval.
  Future<EmployeePinResult> verifyPin({
    required String requestId,
    required int expectedRevision,
    required String pin,
  });
  Future<EmployeePinStatus> resetPin({
    required String membershipId,
    required String requestId,
    required int expectedRevision,
    required String reason,
  });
}

void validateEmployeePin(String pin) {
  if (!RegExp(r'^[0-9]{6,12}$').hasMatch(pin)) {
    throw const RepositoryFailure(
      RepositoryFailureType.validation,
      'Use a PIN with 6 to 12 digits.',
    );
  }
}

EmployeePinStatus decodeEmployeePinStatus(
  Object? value, {
  String? expectedMembershipId,
}) {
  if (value is! Map) throw const FormatException('Invalid PIN status');
  final id = value['membership_id'];
  final revision = value['revision'];
  if (id is! String ||
      revision is! int ||
      revision < 1 ||
      value['configured'] is! bool ||
      value['reset_required'] is! bool) {
    throw const FormatException('Invalid PIN status');
  }
  validateId(id);
  if (expectedMembershipId != null && id != expectedMembershipId) {
    throw const FormatException('Wrong PIN status scope');
  }
  DateTime? date(String key) {
    final raw = value[key];
    if (raw == null) return null;
    if (raw is! String) throw const FormatException('Invalid PIN time');
    final result = DateTime.tryParse(raw);
    if (result == null) throw const FormatException('Invalid PIN time');
    return result.toUtc();
  }

  return EmployeePinStatus(
    membershipId: id,
    configured: value['configured'] as bool,
    resetRequired: value['reset_required'] as bool,
    revision: revision,
    lockedUntil: date('locked_until'),
    changedAt: date('changed_at'),
  );
}

class SupabaseEmployeePinRepository implements EmployeePinRepository {
  SupabaseEmployeePinRepository({
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
  String get organizationId => _scope.organizationId;
  @override
  Future<EmployeePinStatus> status({String? membershipId}) =>
      _scope.safe(() async {
        if (membershipId != null) validateId(membershipId);
        return decodeEmployeePinStatus(
          await _scope.client.rpc(
            'get_employee_pin_status',
            params: {
              'p_organization_id': organizationId,
              'p_membership_id': membershipId,
            },
          ),
          expectedMembershipId: membershipId ?? _scope.actor.membershipId,
        );
      });
  @override
  Future<DataPage<EmployeePinResetTarget>> resetTargets({
    PageRequest page = const PageRequest(),
  }) => _scope.safe(() async {
    page.validate();
    final result = await _scope.client.rpc(
      'list_employee_pin_reset_targets',
      params: {
        'p_organization_id': organizationId,
        'p_offset': page.offset,
        'p_limit': page.limit + 1,
      },
    );
    if (result is! List || result.length > page.limit + 1) {
      throw const FormatException('Invalid PIN target page');
    }
    final targets = result
        .take(page.limit)
        .map((v) {
          if (v is! Map ||
              v['membership_id'] is! String ||
              v['full_name'] is! String ||
              v['role'] is! String) {
            throw const FormatException('Invalid PIN target');
          }
          final id = v['membership_id'] as String;
          validateId(id);
          return EmployeePinResetTarget(
            membershipId: id,
            fullName: v['full_name'] as String,
            role: AppRole.fromDatabase(v['role'] as String),
            status: decodeEmployeePinStatus(
              v['status'],
              expectedMembershipId: id,
            ),
          );
        })
        .toList(growable: false);
    return DataPage(
      items: targets,
      hasMore: result.length > page.limit,
      offset: page.offset,
    );
  });
  Future<EmployeePinResult> _operation({
    required String action,
    required String requestId,
    required int expectedRevision,
    required String pin,
    String? currentPin,
  }) => _scope.safe(() async {
    validateId(requestId);
    validateRevision(expectedRevision);
    validateEmployeePin(pin);
    if (currentPin != null) validateEmployeePin(currentPin);
    // PIN text exists only in this in-memory HTTPS request; it is never journaled.
    Object? value;
    try {
      value = (await _scope.client.functions.invoke(
        'employee-pin',
        body: {
          'action': action,
          'organization_id': organizationId,
          'request_id': requestId,
          'expected_revision': expectedRevision,
          'pin': pin,
          'current_pin': currentPin,
        },
      )).data;
    } on FunctionException catch (error) {
      if (error.status == 429) {
        throw const RepositoryFailure(
          RepositoryFailureType.unavailable,
          'Too many PIN requests. Wait before trying again.',
        );
      }
      rethrow;
    }
    if (value is! Map || value['accepted'] is! bool) {
      throw const FormatException('Invalid PIN response');
    }
    return EmployeePinResult(
      accepted: value['accepted'] as bool,
      status: decodeEmployeePinStatus(
        value['status'],
        expectedMembershipId: _scope.actor.membershipId,
      ),
    );
  });
  @override
  Future<EmployeePinResult> setPin({
    required String requestId,
    required int expectedRevision,
    required String pin,
    String? currentPin,
  }) => _operation(
    action: 'set',
    requestId: requestId,
    expectedRevision: expectedRevision,
    pin: pin,
    currentPin: currentPin,
  );
  @override
  Future<EmployeePinResult> verifyPin({
    required String requestId,
    required int expectedRevision,
    required String pin,
  }) => _operation(
    action: 'verify',
    requestId: requestId,
    expectedRevision: expectedRevision,
    pin: pin,
  );
  @override
  Future<EmployeePinStatus> resetPin({
    required String membershipId,
    required String requestId,
    required int expectedRevision,
    required String reason,
  }) => _scope.safe(() async {
    validateId(membershipId);
    validateId(requestId);
    validateRevision(expectedRevision);
    final validReason = requiredText(reason, 'Reset reason', 500, minimum: 8);
    return decodeEmployeePinStatus(
      await _scope.client.rpc(
        'reset_employee_pin',
        params: {
          'p_organization_id': organizationId,
          'p_membership_id': membershipId,
          'p_request_id': requestId,
          'p_expected_revision': expectedRevision,
          'p_reason': validReason,
        },
      ),
      expectedMembershipId: membershipId,
    );
  });
}
