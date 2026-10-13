import 'auth_models.dart';

abstract interface class AuthRepository {
  bool get isConfigured;
  AuthIdentity? get currentIdentity;
  bool get hasVerifiedRecoverySession;
  Stream<AuthSessionEvent> get events;

  Future<void> signIn({
    required String email,
    required String password,
    required bool rememberDevice,
  });
  Future<OwnerRegistrationResult> registerOwner({
    required String businessName,
    required String fullName,
    required String email,
    required String password,
  });
  Future<void> bootstrapOwner({
    required String businessName,
    required String fullName,
  });
  Future<List<AuthenticatedUser>> loadMemberships();
  Future<void> requestPasswordRecovery(String email);
  Future<void> updateRecoveredPassword(String password);
  Future<void> signOut();
}

class NotConfiguredAuthRepository implements AuthRepository {
  const NotConfiguredAuthRepository();

  static const _failure = AuthFailure(
    'Authentication is Not Yet Connected. Configure the Supabase project first.',
  );

  @override
  bool get isConfigured => false;
  @override
  AuthIdentity? get currentIdentity => null;
  @override
  bool get hasVerifiedRecoverySession => false;
  @override
  Stream<AuthSessionEvent> get events => const Stream.empty();
  @override
  Future<void> signIn({
    required String email,
    required String password,
    required bool rememberDevice,
  }) async => throw _failure;
  @override
  Future<OwnerRegistrationResult> registerOwner({
    required String businessName,
    required String fullName,
    required String email,
    required String password,
  }) async => throw _failure;
  @override
  Future<void> bootstrapOwner({
    required String businessName,
    required String fullName,
  }) async => throw _failure;
  @override
  Future<List<AuthenticatedUser>> loadMemberships() async => throw _failure;
  @override
  Future<void> requestPasswordRecovery(String email) async => throw _failure;
  @override
  Future<void> updateRecoveredPassword(String password) async => throw _failure;
  @override
  Future<void> signOut() async {}
}
