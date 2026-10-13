import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nexapos/core/auth/auth_models.dart';
import 'package:nexapos/core/auth/auth_repository.dart';
import 'package:nexapos/core/auth/recovery_session_policy.dart';
import 'package:nexapos/core/security/app_role.dart';
import 'package:nexapos/features/authentication/application/auth_validation.dart';
import 'package:nexapos/features/authentication/presentation/auth_gate.dart';

const _identity = AuthIdentity(
  userId: 'real-auth-user',
  email: 'cashier@example.test',
  emailVerified: true,
);

AuthenticatedUser _membership({
  String organization = 'business-a',
  String businessName = 'Actual business',
  AppRole role = AppRole.cashier,
  Set<String> branches = const {'branch-a'},
}) => AuthenticatedUser(
  userId: _identity.userId,
  email: _identity.email,
  organizationId: organization,
  membershipId: 'membership-$organization',
  role: role,
  branchIds: branches,
  allBranches: role == AppRole.owner,
  businessName: businessName,
);

class FakeAuthRepository implements AuthRepository {
  final controller = StreamController<AuthSessionEvent>.broadcast(sync: true);
  AuthIdentity? identity;
  List<AuthenticatedUser> memberships = [];
  Object? signInError;
  Object? membershipError;
  int signInCalls = 0;
  int registrationCalls = 0;
  int bootstrapCalls = 0;
  int resetCalls = 0;
  int recoveryCalls = 0;
  int membershipCalls = 0;
  bool? remembered;
  final recoveryPolicy = RecoverySessionPolicy();

  @override
  bool get isConfigured => true;
  @override
  AuthIdentity? get currentIdentity => identity;
  @override
  bool get hasVerifiedRecoverySession =>
      recoveryPolicy.isActiveFor(identity?.userId);
  @override
  Stream<AuthSessionEvent> get events => controller.stream;

  @override
  Future<void> signIn({
    required String email,
    required String password,
    required bool rememberDevice,
  }) async {
    signInCalls++;
    remembered = rememberDevice;
    if (signInError != null) throw signInError!;
    identity = _identity;
    recoveryPolicy.clear();
    controller.add(AuthSessionEvent(AuthSessionEventType.signedIn, identity));
  }

  @override
  Future<OwnerRegistrationResult> registerOwner({
    required String businessName,
    required String fullName,
    required String email,
    required String password,
  }) async {
    registrationCalls++;
    return const OwnerRegistrationResult(requiresEmailVerification: true);
  }

  @override
  Future<void> bootstrapOwner({
    required String businessName,
    required String fullName,
  }) async {
    if (identity?.emailVerified != true) {
      throw const AuthFailure('Verified sign-in required.');
    }
    bootstrapCalls++;
  }

  @override
  Future<List<AuthenticatedUser>> loadMemberships() async {
    membershipCalls++;
    if (membershipError != null) throw membershipError!;
    return memberships;
  }

  @override
  Future<void> requestPasswordRecovery(String email) async => recoveryCalls++;

  @override
  Future<void> updateRecoveredPassword(String password) async {
    if (!hasVerifiedRecoverySession) {
      throw const AuthFailure('Recovery session required.');
    }
    resetCalls++;
    await signOut();
  }

  @override
  Future<void> signOut() async {
    identity = null;
    recoveryPolicy.clear();
    controller.add(
      const AuthSessionEvent(AuthSessionEventType.signedOut, null),
    );
  }

  void emitRecovery({required bool verified}) {
    identity = _identity;
    if (verified) {
      recoveryPolicy.beginVerifiedRecovery(_identity.userId);
    } else {
      recoveryPolicy.clear();
    }
    controller.add(
      AuthSessionEvent(AuthSessionEventType.passwordRecovery, identity),
    );
  }

  void emitTransientAuthError() {
    recoveryPolicy.retainForSession(identity?.userId);
    controller.addError(
      const AuthFailure(
        'The authentication service is temporarily unavailable.',
      ),
    );
  }

  void emitTokenRefreshed() {
    recoveryPolicy.retainForSession(identity?.userId);
    controller.add(AuthSessionEvent(AuthSessionEventType.refreshed, identity));
  }
}

Future<void> _mount(
  WidgetTester tester,
  AuthRepository repository, {
  VoidCallback? preview,
}) async {
  tester.view.physicalSize = const Size(1280, 1200);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(
    MaterialApp(
      theme: ThemeData(useMaterial3: true),
      home: AuthGate(
        repository: repository,
        onPreview: preview ?? () {},
        authenticatedBuilder: (context, user) => Scaffold(
          body: Text('Authenticated ${user.organizationId} ${user.role.name}'),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

Future<void> _tap(WidgetTester tester, String text) async {
  final target = find.text(text).last;
  await tester.ensureVisible(target);
  await tester.tap(target);
  await tester.pumpAndSettle();
}

Future<void> _enter(WidgetTester tester, String label, String text) async {
  final target = find.widgetWithText(TextFormField, label);
  await tester.ensureVisible(target);
  await tester.enterText(target, text);
}

void main() {
  test(
    'recovery policy survives same-user failure and refresh but cannot transfer',
    () {
      final policy = RecoverySessionPolicy();
      policy.beginVerifiedRecovery('verified-recovery-user');
      policy.retainForSession('verified-recovery-user');
      expect(policy.isActiveFor('verified-recovery-user'), isTrue);
      policy.retainForSession('verified-recovery-user');
      expect(policy.isActiveFor('verified-recovery-user'), isTrue);
      policy.retainForSession('different-user');
      expect(policy.isActiveFor('different-user'), isFalse);
      expect(policy.isActiveFor('verified-recovery-user'), isFalse);
      policy.beginVerifiedRecovery('verified-recovery-user');
      policy.retainForSession(null);
      expect(policy.isActiveFor('verified-recovery-user'), isFalse);
    },
  );

  testWidgets(
    'recovery stream error then token refresh never opens owner shell',
    (tester) async {
      final repo = FakeAuthRepository()
        ..memberships = [_membership(role: AppRole.owner)];
      await _mount(tester, repo);
      repo.emitRecovery(verified: true);
      await tester.pumpAndSettle();
      expect(find.text('Choose a new password'), findsOneWidget);
      repo.emitTransientAuthError();
      await tester.pumpAndSettle();
      expect(repo.hasVerifiedRecoverySession, isTrue);
      expect(find.text('Choose a new password'), findsOneWidget);
      expect(find.textContaining('Authenticated '), findsNothing);
      repo.emitTokenRefreshed();
      await tester.pumpAndSettle();
      expect(repo.hasVerifiedRecoverySession, isTrue);
      expect(find.text('Choose a new password'), findsOneWidget);
      expect(find.textContaining('Authenticated '), findsNothing);
      expect(repo.membershipCalls, 0);
      expect(repo.resetCalls, 0);
    },
  );

  test('new password policy and email validation reject unsafe input', () {
    expect(validateNewPassword('short'), isNotNull);
    expect(validateNewPassword('alllowercase123!'), isNotNull);
    expect(validateNewPassword('LongSafePassword123!'), isNull);
    expect(validateEmail('cashier@example.test'), isNull);
    expect(validateEmail('cashier@'), isNotNull);
    expect(validateLoginIdentifier('EMP001'), contains('Coming Soon'));
  });

  testWidgets('unconfigured preview cannot establish authentication', (
    tester,
  ) async {
    var openedPreview = false;
    await _mount(
      tester,
      const NotConfiguredAuthRepository(),
      preview: () => openedPreview = true,
    );
    expect(find.text('Not Yet Connected'), findsOneWidget);
    expect(find.textContaining('Authenticated '), findsNothing);
    await _tap(tester, 'Open design preview');
    expect(openedPreview, isTrue);
    expect(find.textContaining('Authenticated '), findsNothing);
  });

  testWidgets('employee ID stays unavailable and cannot invoke sign-in', (
    tester,
  ) async {
    final repo = FakeAuthRepository();
    await _mount(tester, repo);
    await _enter(tester, 'Email or Employee ID', 'EMP001');
    await _enter(tester, 'Password', 'existing-password');
    await _tap(tester, 'Sign in');
    expect(repo.signInCalls, 0);
    expect(
      find.text('Employee ID sign-in is Coming Soon. Use your email.'),
      findsOneWidget,
    );
    expect(
      find.text('Need access? Contact your administrator.'),
      findsOneWidget,
    );
    expect(find.text('Create Account'), findsNothing);
  });

  testWidgets('sign-in controls survive narrow and short desktop resizing', (
    tester,
  ) async {
    final repo = FakeAuthRepository();
    await _mount(tester, repo);
    for (final size in const [Size(1200, 480), Size(320, 640)]) {
      tester.view.physicalSize = size;
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      await tester.ensureVisible(find.text('Sign in').last);
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(
        find.widgetWithText(TextFormField, 'Email or Employee ID'),
        findsOneWidget,
      );
    }
  });

  testWidgets(
    'login passes remember consent and enters only server membership',
    (tester) async {
      final repo = FakeAuthRepository()..memberships = [_membership()];
      await _mount(tester, repo);
      await _enter(tester, 'Email or Employee ID', _identity.email);
      await _enter(tester, 'Password', 'existing-password');
      await tester.tap(find.byType(Checkbox));
      await _tap(tester, 'Sign in');
      expect(repo.remembered, isTrue);
      expect(find.text('Authenticated business-a cashier'), findsOneWidget);
    },
  );

  testWidgets('raw backend failure is sanitized and cannot enter app', (
    tester,
  ) async {
    final repo = FakeAuthRepository()
      ..signInError = Exception('token=SECRET internal database error');
    await _mount(tester, repo);
    await _enter(tester, 'Email or Employee ID', _identity.email);
    await _enter(tester, 'Password', 'existing-password');
    await _tap(tester, 'Sign in');
    expect(find.textContaining('temporarily unavailable'), findsOneWidget);
    expect(find.textContaining('SECRET'), findsNothing);
    expect(find.textContaining('Authenticated '), findsNothing);
  });

  testWidgets('restored identity without membership or branch grants no role', (
    tester,
  ) async {
    final repo = FakeAuthRepository()
      ..identity = _identity
      ..memberships = [_membership(role: AppRole.owner, branches: {})];
    await _mount(tester, repo);
    expect(find.text('Business access needed'), findsOneWidget);
    expect(find.textContaining('Authenticated '), findsNothing);
  });

  testWidgets('network failure cannot authorize a restored session', (
    tester,
  ) async {
    final repo = FakeAuthRepository()
      ..identity = _identity
      ..memberships = [_membership(role: AppRole.owner)]
      ..membershipError = Exception('unreachable');
    await _mount(tester, repo);
    expect(find.textContaining('Authenticated '), findsNothing);
    expect(find.textContaining('temporarily unavailable'), findsOneWidget);
  });

  testWidgets('multiple memberships require explicit business choice', (
    tester,
  ) async {
    final repo = FakeAuthRepository()
      ..identity = _identity
      ..memberships = [
        _membership(role: AppRole.owner, businessName: 'Owner business'),
        _membership(
          organization: 'business-b',
          businessName: 'Cashier business',
        ),
      ];
    await _mount(tester, repo);
    expect(find.text('Choose your business'), findsOneWidget);
    expect(find.textContaining('Authenticated '), findsNothing);
    await _tap(tester, 'Cashier business');
    expect(find.text('Authenticated business-b cashier'), findsOneWidget);
  });

  testWidgets('forgot password uses the exact neutral message', (tester) async {
    final repo = FakeAuthRepository();
    await _mount(tester, repo);
    await _tap(tester, 'Forgot Password?');
    await _enter(tester, 'Email address', 'unknown@example.test');
    await _tap(tester, 'Send recovery instructions');
    expect(repo.recoveryCalls, 1);
    expect(find.text(neutralRecoveryMessage), findsOneWidget);
    expect(find.textContaining('Authenticated '), findsNothing);
  });

  testWidgets('owner signup cannot bootstrap before verified sign-in', (
    tester,
  ) async {
    final repo = FakeAuthRepository();
    await _mount(tester, repo);
    await _tap(tester, 'Set up a new business');
    await _enter(tester, 'Business name', 'New business');
    await _enter(tester, 'Full name', 'Business owner');
    await _enter(tester, 'Email address', 'owner@example.test');
    await _enter(tester, 'Password', 'LongSafePassword123!');
    await _enter(tester, 'Confirm password', 'LongSafePassword123!');
    await _tap(tester, 'Send verification email');
    expect(repo.registrationCalls, 1);
    expect(repo.bootstrapCalls, 0);
    expect(find.text('Check your email'), findsOneWidget);
    expect(find.textContaining('Authenticated '), findsNothing);
  });

  testWidgets('reset screen requires verified recovery state', (tester) async {
    final repo = FakeAuthRepository();
    await _mount(tester, repo);
    repo.emitRecovery(verified: false);
    await tester.pumpAndSettle();
    expect(find.text('Choose a new password'), findsNothing);
    expect(repo.resetCalls, 0);
    repo.emitRecovery(verified: true);
    await tester.pumpAndSettle();
    expect(find.text('Choose a new password'), findsOneWidget);
    await _enter(tester, 'New password', 'LongSafePassword123!');
    await _enter(tester, 'Confirm new password', 'LongSafePassword123!');
    await _tap(tester, 'Update password');
    expect(repo.resetCalls, 1);
    expect(
      find.text('Your password was updated. Sign in with your new password.'),
      findsOneWidget,
    );
    expect(find.textContaining('all sessions'), findsNothing);
  });
}
