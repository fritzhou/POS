enum MfaAssuranceLevel { none, aal1, aal2 }

class MfaFactor {
  const MfaFactor({
    required this.id,
    required this.name,
    required this.isVerified,
    required this.isTotp,
  });

  final String id;
  final String name;
  final bool isVerified;
  final bool isTotp;
}

class MfaStatus {
  MfaStatus({
    required this.actorId,
    required this.currentLevel,
    required this.nextLevel,
    required List<MfaFactor> factors,
  }) : factors = List.unmodifiable(factors);

  final String actorId;
  final MfaAssuranceLevel currentLevel;
  final MfaAssuranceLevel nextLevel;
  final List<MfaFactor> factors;

  List<MfaFactor> get verifiedTotpFactors => factors
      .where((factor) => factor.isVerified && factor.isTotp)
      .toList(growable: false);
}

/// An enrollment secret exists only while the live enrollment form is open.
/// Never put this object in application state persistence, logs or an outbox.
class MfaEnrollment {
  const MfaEnrollment({required this.factorId, required this.secret});

  final String factorId;
  final String secret;

  @override
  String toString() => 'MfaEnrollment';
}

class MfaChallenge {
  const MfaChallenge({
    required this.factorId,
    required this.id,
    required this.expiresAt,
  });

  final String factorId;
  final String id;
  final DateTime expiresAt;
}

enum MfaFailureKind { other, unavailable, authorization, expired, invalidCode }

class MfaFailure implements Exception {
  const MfaFailure(this.message, {this.kind = MfaFailureKind.other});

  final String message;
  final MfaFailureKind kind;

  @override
  String toString() => 'MfaFailure';
}

abstract interface class MfaRepository {
  String? get actorId;
  Future<MfaStatus> status();
  Future<MfaEnrollment> enrollTotp({required String name});
  Future<MfaChallenge> challenge(String factorId);
  Future<MfaStatus> verify(MfaChallenge challenge, String code);
  Future<void> cancelEnrollment(String factorId);
  Future<void> unenroll(String factorId);
}
