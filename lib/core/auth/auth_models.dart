import '../security/app_role.dart';

/// Identity is distinct from tenant authorization: an Auth session alone does
/// not grant access to a business.
class AuthIdentity {
  const AuthIdentity({
    required this.userId,
    required this.email,
    required this.emailVerified,
    this.pendingBusinessName,
    this.fullName,
  });

  final String userId;
  final String email;
  final bool emailVerified;
  final String? pendingBusinessName;
  final String? fullName;
}

class AuthenticatedUser {
  AuthenticatedUser({
    required this.userId,
    required this.email,
    required this.organizationId,
    required this.membershipId,
    required this.role,
    required Set<String> branchIds,
    required this.allBranches,
    required this.businessName,
  }) : branchIds = Set.unmodifiable(branchIds);

  final String userId;
  final String email;
  final String organizationId;
  final String membershipId;
  final AppRole role;
  final Set<String> branchIds;
  final bool allBranches;
  final String businessName;
}

enum AuthSessionEventType { signedIn, signedOut, refreshed, passwordRecovery }

class AuthSessionEvent {
  const AuthSessionEvent(this.type, this.identity);

  final AuthSessionEventType type;
  final AuthIdentity? identity;
}

class OwnerRegistrationResult {
  const OwnerRegistrationResult({required this.requiresEmailVerification});

  final bool requiresEmailVerification;
}

/// Only deliberate public messages cross this boundary. Raw backend errors
/// never belong in presentation or logs.
enum AuthFailureKind { other, unavailable, authorization }

class AuthFailure implements Exception {
  const AuthFailure(this.message, {this.kind = AuthFailureKind.other});

  final String message;
  final AuthFailureKind kind;

  @override
  String toString() => 'AuthFailure';
}

const neutralRecoveryMessage =
    'If an account exists for this email, recovery instructions have been sent.';
