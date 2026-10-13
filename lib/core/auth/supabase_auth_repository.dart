import 'dart:async';
import 'dart:io' show SocketException;

import 'package:supabase_flutter/supabase_flutter.dart';

import '../security/app_role.dart';
import '../services/email_service.dart';
import 'auth_models.dart';
import 'auth_repository.dart';
import 'recovery_session_policy.dart';
import 'secure_session_storage.dart';

class SupabaseAuthRepository implements AuthRepository {
  SupabaseAuthRepository({
    required SupabaseClient client,
    required this.sessionStorage,
    EmailService? emailService,
    this.recoveryRedirectTo,
    this.ownerRedirectTo,
  }) : _client = client,
       _emailService = emailService ?? SupabaseEmailService(client) {
    _subscription = _client.auth.onAuthStateChange.listen(
      _onAuthState,
      onError: (Object error, StackTrace stack) {
        // GoTrue keeps the current session after retryable refresh failures.
        // Such an error must not turn a recovery session into normal access.
        _recoveryPolicy.retainForSession(_client.auth.currentSession?.user.id);
        _events.addError(AuthFailure(_unavailable, kind: _failureKind(error)));
      },
    );
  }

  final SupabaseClient _client;
  final SecureSessionStorage sessionStorage;
  final EmailService _emailService;
  final String? recoveryRedirectTo;
  final String? ownerRedirectTo;
  final _events = StreamController<AuthSessionEvent>.broadcast();
  late final StreamSubscription<AuthState> _subscription;
  final _recoveryPolicy = RecoverySessionPolicy();

  static const _unavailable =
      'The authentication service is temporarily unavailable. Try again shortly.';

  static AuthFailureKind _failureKind(Object error) {
    if (error is AuthRetryableFetchException ||
        error is SocketException ||
        error is TimeoutException) {
      return AuthFailureKind.unavailable;
    }
    if (error is AuthException &&
        const {
          'session_not_found',
          'refresh_token_not_found',
          'refresh_token_already_used',
          'bad_jwt',
          'user_banned',
        }.contains(error.code)) {
      return AuthFailureKind.authorization;
    }
    return AuthFailureKind.other;
  }

  @override
  bool get isConfigured => true;
  @override
  Stream<AuthSessionEvent> get events => _events.stream;
  @override
  AuthIdentity? get currentIdentity => _identity(_client.auth.currentUser);
  @override
  bool get hasVerifiedRecoverySession =>
      _client.auth.currentSession != null &&
      _recoveryPolicy.isActiveFor(_client.auth.currentSession?.user.id);

  AuthIdentity? _identity(User? user) => user == null
      ? null
      : AuthIdentity(
          userId: user.id,
          email: user.email ?? '',
          emailVerified: user.emailConfirmedAt != null,
          pendingBusinessName: _metadataString(
            user,
            'owner_setup_business_name',
          ),
          fullName: _metadataString(user, 'full_name'),
        );

  String? _metadataString(User user, String key) {
    final value = user.userMetadata?[key];
    return value is String ? value : null;
  }

  void _onAuthState(AuthState state) {
    final identity = _identity(state.session?.user);
    switch (state.event) {
      case AuthChangeEvent.passwordRecovery:
        // Only Supabase's validated recovery event can enable a password reset.
        if (state.session != null && identity != null) {
          _recoveryPolicy.beginVerifiedRecovery(identity.userId);
        } else {
          _recoveryPolicy.clear();
        }
        _events.add(
          AuthSessionEvent(AuthSessionEventType.passwordRecovery, identity),
        );
      case AuthChangeEvent.signedOut:
        _recoveryPolicy.clear();
        _events.add(
          const AuthSessionEvent(AuthSessionEventType.signedOut, null),
        );
      case AuthChangeEvent.signedIn:
        _recoveryPolicy.clear();
        _events.add(AuthSessionEvent(AuthSessionEventType.signedIn, identity));
      case AuthChangeEvent.tokenRefreshed:
      case AuthChangeEvent.initialSession:
        _recoveryPolicy.retainForSession(identity?.userId);
        _events.add(AuthSessionEvent(AuthSessionEventType.refreshed, identity));
      default:
        break;
    }
  }

  Future<T> _safe<T>(Future<T> Function() operation) async {
    try {
      return await operation();
    } on AuthFailure {
      rethrow;
    } on AuthRetryableFetchException {
      throw const AuthFailure(_unavailable, kind: AuthFailureKind.unavailable);
    } on SocketException {
      throw const AuthFailure(_unavailable, kind: AuthFailureKind.unavailable);
    } on TimeoutException {
      throw const AuthFailure(_unavailable, kind: AuthFailureKind.unavailable);
    } on PostgrestException catch (error) {
      throw AuthFailure(
        _unavailable,
        kind: const {'42501', 'PGRST301', 'PGRST302'}.contains(error.code)
            ? AuthFailureKind.authorization
            : AuthFailureKind.other,
      );
    } on AuthException catch (error) {
      if (error.code == 'invalid_credentials') {
        throw const AuthFailure('Email or password is incorrect.');
      }
      if (error.code == 'email_not_confirmed') {
        throw const AuthFailure(
          'Verify your email before signing in. Check your verification email.',
        );
      }
      if (error.code == 'weak_password') {
        throw const AuthFailure(
          'Choose a stronger password that meets your business password policy.',
        );
      }
      throw AuthFailure(_unavailable, kind: _failureKind(error));
    } on Object {
      throw const AuthFailure(_unavailable);
    }
  }

  @override
  Future<void> signIn({
    required String email,
    required String password,
    required bool rememberDevice,
  }) => _safe(() async {
    if (!email.contains('@')) {
      throw const AuthFailure(
        'Employee ID sign-in is Coming Soon. Use your email address.',
      );
    }
    await sessionStorage.setRememberDevice(rememberDevice);
    await _client.auth.signInWithPassword(
      email: email.trim(),
      password: password,
    );
  });

  @override
  Future<OwnerRegistrationResult> registerOwner({
    required String businessName,
    required String fullName,
    required String email,
    required String password,
  }) => _safe(() async {
    // Signup does not grant membership; server bootstrap follows verification.
    await sessionStorage.setRememberDevice(false);
    final response = await _client.auth.signUp(
      email: email.trim(),
      password: password,
      emailRedirectTo: ownerRedirectTo,
      data: {
        'full_name': fullName.trim(),
        'owner_setup_business_name': businessName.trim(),
      },
    );
    return OwnerRegistrationResult(
      requiresEmailVerification:
          response.session == null || response.user?.emailConfirmedAt == null,
    );
  });

  @override
  Future<void> bootstrapOwner({
    required String businessName,
    required String fullName,
  }) => _safe(() async {
    if (currentIdentity?.emailVerified != true ||
        _client.auth.currentSession == null ||
        hasVerifiedRecoverySession) {
      throw const AuthFailure(
        'Sign in with your verified email before setting up a business.',
      );
    }
    await _client.rpc(
      'bootstrap_organization',
      params: {
        'p_business_name': businessName.trim(),
        'p_full_name': fullName.trim(),
      },
    );
  });

  @override
  Future<List<AuthenticatedUser>> loadMemberships() => _safe(() async {
    final identity = currentIdentity;
    if (identity == null || !identity.emailVerified) return [];
    if (_client.auth.currentSession == null || hasVerifiedRecoverySession) {
      return [];
    }
    final memberships = await _client
        .from('organization_memberships')
        .select(
          'id,organization_id,role,status,all_branches,organizations(business_name)',
        )
        .eq('user_id', identity.userId)
        .eq('status', 'active');
    final result = <AuthenticatedUser>[];
    for (final membership in memberships) {
      final organization = membership['organizations'];
      if (organization is! Map<String, dynamic>) continue;
      final organizationId = membership['organization_id'] as String;
      final membershipId = membership['id'] as String;
      final role = AppRole.fromDatabase(membership['role'] as String);
      final allBranches =
          role == AppRole.owner ||
          (role == AppRole.admin && membership['all_branches'] == true);
      final branchRows = allBranches
          ? await _client
                .from('branches')
                .select('id')
                .eq('organization_id', organizationId)
                .eq('active', true)
          : await _client
                .from('membership_branches')
                .select('branch_id,branches!inner(active)')
                .eq('membership_id', membershipId)
                .eq('organization_id', organizationId)
                .eq('branches.active', true);
      final branchIds = branchRows
          .map((row) => row[allBranches ? 'id' : 'branch_id'] as String)
          .toSet();
      // Missing branch assignments never become all-branch permission.
      if (branchIds.isEmpty) continue;
      result.add(
        AuthenticatedUser(
          userId: identity.userId,
          email: identity.email,
          organizationId: organizationId,
          membershipId: membershipId,
          role: role,
          branchIds: branchIds,
          allBranches: allBranches,
          businessName: organization['business_name'] as String,
        ),
      );
    }
    return result;
  });

  @override
  Future<void> requestPasswordRecovery(String email) async {
    final redirect = recoveryRedirectTo;
    if (redirect == null || redirect.isEmpty) {
      throw const AuthFailure(
        'Password recovery is Not Yet Connected. Your administrator must configure an allowed recovery destination.',
      );
    }
    try {
      await _emailService.requestPasswordRecovery(
        email.trim(),
        redirectTo: redirect,
      );
    } on AuthException catch (error) {
      // Keep an account's existence private even if an Auth deployment exposes
      // these account-specific error codes.
      if (error.code == 'user_not_found' ||
          error.code == 'email_not_confirmed') {
        return;
      }
      throw const AuthFailure(_unavailable);
    } on Object {
      throw const AuthFailure(_unavailable);
    }
  }

  @override
  Future<void> updateRecoveredPassword(String password) => _safe(() async {
    if (!hasVerifiedRecoverySession) {
      throw const AuthFailure(
        'This recovery session is unavailable or expired. Request a new recovery email.',
      );
    }
    await _client.auth.updateUser(UserAttributes(password: password));
    _recoveryPolicy.clear();
    await sessionStorage.removePersistedSession();
    try {
      await _client.auth.signOut(scope: SignOutScope.local);
    } on Object {
      throw const AuthFailure(
        'Your password was updated, but sign-out could not complete. Try signing out again.',
      );
    }
  });

  @override
  Future<void> signOut() => _safe(() async {
    // A local sign-out is not advertised as global session revocation.
    try {
      await sessionStorage.removePersistedSession();
    } finally {
      try {
        await _client.auth.signOut(scope: SignOutScope.local);
      } finally {
        _recoveryPolicy.clear();
      }
    }
  });

  Future<void> dispose() async {
    await _subscription.cancel();
    await _events.close();
  }
}
