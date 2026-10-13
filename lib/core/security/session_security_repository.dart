import 'package:supabase_flutter/supabase_flutter.dart';

import '../auth/auth_models.dart';
import '../auth/auth_repository.dart';
import '../auth/secure_session_storage.dart';

abstract interface class SessionSecurityRepository {
  /// Verifies the current account password online, without replacing its session.
  Future<void> verifyCurrentPassword(String password);
  Future<void> signOutAllSessions();
}

class SupabaseSessionSecurityRepository implements SessionSecurityRepository {
  SupabaseSessionSecurityRepository({
    required this.client,
    required this.auth,
    required this.sessionStorage,
    required this.authUrl,
    required this.publicApiKey,
    this.isolatedClientFactory,
  });

  final SupabaseClient client;
  final AuthRepository auth;
  final SecureSessionStorage sessionStorage;
  final String authUrl, publicApiKey;
  final GoTrueClient Function()? isolatedClientFactory;

  @override
  Future<void> verifyCurrentPassword(String password) async {
    final actor = auth.currentIdentity;
    if (actor == null ||
        !actor.emailVerified ||
        auth.hasVerifiedRecoverySession ||
        password.isEmpty) {
      throw const AuthFailure('Sign in online to unlock this workspace.');
    }
    // Password verification gets its own memory-only Auth client: a delayed
    // request cannot sign the shared client back in after logout/account change.
    final isolated =
        isolatedClientFactory?.call() ??
        GoTrueClient(
          url: authUrl,
          headers: {'apikey': publicApiKey},
          autoRefreshToken: false,
        );
    try {
      final response = await isolated.signInWithPassword(
        email: actor.email,
        password: password,
      );
      if (response.session == null ||
          response.user?.id != actor.userId ||
          response.user?.emailConfirmedAt == null ||
          auth.currentIdentity?.userId != actor.userId ||
          auth.hasVerifiedRecoverySession) {
        throw const AuthFailure('The account changed. Sign in again.');
      }
    } on AuthFailure {
      rethrow;
    } on Object {
      throw const AuthFailure(
        'Unlock could not be verified. Check your password and connection.',
      );
    } finally {
      // Revoke the temporary verification session; shared AAL2 remains intact.
      try {
        await isolated.signOut(scope: SignOutScope.local);
      } on Object {
        // No temporary session is persisted; provider expiry/revocation applies.
      }
      isolated.dispose();
    }
  }

  @override
  Future<void> signOutAllSessions() async {
    bool revoked = false;
    try {
      if (auth.currentIdentity == null || auth.hasVerifiedRecoverySession) {
        throw const AuthFailure('Sign in online to revoke account sessions.');
      }
      final token = client.auth.currentSession?.accessToken;
      if (token == null) {
        throw const AuthFailure('Sign in online to revoke account sessions.');
      }
      // The SDK's shared signOut clears its local session even on a failed
      // network request. Verify provider revocation first so uncertainty can
      // be retried with the original session instead of claiming success.
      await client.auth.admin.signOut(token, scope: SignOutScope.global);
      revoked = true;
      await client.auth.signOut(scope: SignOutScope.local);
    } on AuthFailure {
      rethrow;
    } on Object {
      throw const AuthFailure(
        'Account session revocation could not be confirmed. Try again online.',
      );
    } finally {
      if (revoked) await sessionStorage.removePersistedSession();
    }
  }
}
