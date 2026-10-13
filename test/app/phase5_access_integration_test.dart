import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nexapos/app/app.dart';
import 'package:nexapos/app/business_services.dart';
import 'package:nexapos/app/offline_services.dart';
import 'package:nexapos/app/shell/nexa_shell.dart';
import 'package:nexapos/core/auth/auth_models.dart';
import 'package:nexapos/core/security/access_lock.dart';
import 'package:nexapos/core/security/app_role.dart';
import 'package:nexapos/core/security/session_security_repository.dart';
import 'package:nexapos/features/administration/domain/administration_repository.dart';
import 'package:nexapos/features/authentication/domain/mfa_repository.dart';
import 'package:nexapos/features/catalog/domain/catalog_repository.dart';
import 'package:nexapos/features/people/domain/people_repository.dart';
import 'package:nexapos/features/security/domain/security_models.dart';
import 'package:nexapos/features/security/domain/security_repository.dart';
import 'package:nexapos/features/offline/presentation/offline_workspace_page.dart';

import '../auth/auth_gate_test.dart' show FakeAuthRepository;
import '../offline_widgets/offline_workspace_page_test.dart'
    show FixtureWorkspace, branch;

// Test-only repositories verify root composition. No preview data or provider
// authentication success is supplied by the production app.
const _identity = AuthIdentity(
  userId: 'security-test-actor',
  email: 'owner@example.test',
  emailVerified: true,
);

AuthenticatedUser _member({
  AppRole role = AppRole.owner,
  Set<String> branches = const {'branch-a'},
}) => AuthenticatedUser(
  userId: _identity.userId,
  email: _identity.email,
  organizationId: 'organization-a',
  membershipId: 'membership-a',
  role: role,
  branchIds: branches,
  allBranches: true,
  businessName: 'Security integration business',
);

class _UnusedRepository
    implements
        CatalogRepository,
        PeopleRepository,
        AdministrationRepository,
        EmployeeRepository {
  @override
  dynamic noSuchMethod(Invocation invocation) => throw StateError(
    'Unexpected test business operation: ${invocation.memberName}',
  );
}

class _SecurityRepository implements SecurityRepository {
  bool requireMfa = true;
  @override
  String get organizationId => 'organization-a';
  @override
  Future<SecurityPolicy> loadPolicy() async => SecurityPolicy(
    organizationId: organizationId,
    idleLockMinutes: 5,
    requirePrivilegedMfa: requireMfa,
    revision: 1,
  );
  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw StateError('Unexpected test security mutation');
}

class _MfaRepository implements MfaRepository {
  _MfaRepository(this.access);
  final AccessLock access;
  @override
  String? actorId = _identity.userId;
  MfaAssuranceLevel level = MfaAssuranceLevel.aal1;
  @override
  Future<MfaStatus> status() async {
    // Mirrors the production isRecoverySession/lock boundary.
    if (access.isLocked) throw const MfaFailure('Workspace locked.');
    return MfaStatus(
      actorId: actorId!,
      currentLevel: level,
      nextLevel: MfaAssuranceLevel.aal2,
      factors: [
        const MfaFactor(
          id: 'factor-a',
          name: 'Test authenticator',
          isVerified: true,
          isTotp: true,
        ),
      ],
    );
  }

  @override
  Future<MfaChallenge> challenge(String factorId) async => MfaChallenge(
    factorId: factorId,
    id: 'test-challenge',
    expiresAt: DateTime.now().add(const Duration(minutes: 1)),
  );
  @override
  Future<MfaStatus> verify(MfaChallenge challenge, String code) async {
    level = MfaAssuranceLevel.aal2;
    return status();
  }

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw StateError('Unexpected test MFA mutation');
}

class _SessionSecurity implements SessionSecurityRepository {
  final passwords = <String>[];
  Completer<void>? pending;
  @override
  Future<void> verifyCurrentPassword(String password) async {
    passwords.add(password);
    await pending?.future;
  }

  @override
  Future<void> signOutAllSessions() async {}
}

class _Harness {
  final auth = FakeAuthRepository()
    ..identity = _identity
    ..memberships = [_member()];
  final access = AccessLock();
  final security = _SecurityRepository();
  final session = _SessionSecurity();
  late final mfa = _MfaRepository(access);

  Future<void> mount(WidgetTester tester) async {
    tester.view.physicalSize = const Size(1280, 1100);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(auth.controller.close);
    final unused = _UnusedRepository();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          authRepositoryProvider.overrideWithValue(auth),
          accessLockProvider.overrideWithValue(access),
          sessionSecurityProvider.overrideWithValue(session),
          businessServicesFactoryProvider.overrideWithValue(
            (actor) => BusinessServices(
              catalog: unused,
              people: unused,
              administration: unused,
              employees: unused,
              security: security,
              mfa: mfa,
            ),
          ),
        ],
        child: const NexaApp(),
      ),
    );
    await tester.pumpAndSettle();
  }

  Future<void> dialog(WidgetTester tester) async {
    final context = tester.element(find.byType(NexaShell));
    unawaited(
      showDialog<void>(
        context: context,
        builder: (context) => const AlertDialog(
          title: Text('Retained payment dialog'),
          content: TextField(
            decoration: InputDecoration(labelText: 'Recorded reference'),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.enterText(
      find.widgetWithText(TextField, 'Recorded reference'),
      'recorded-reference-test',
    );
  }

  Future<void> unlock(WidgetTester tester) async {
    await tester.enterText(
      find.widgetWithText(TextField, 'Account password'),
      'test-password',
    );
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('Unlock online'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Unlock online'));
    await tester.pumpAndSettle();
  }
}

void main() {
  testWidgets(
    'grant-only resume unlock rechecks known server scope and reconciles keys',
    (tester) async {
      tester.view.physicalSize = const Size(1280, 1100);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final auth = FakeAuthRepository()
        ..identity = _identity
        ..membershipError = const AuthFailure(
          'Connection unavailable.',
          kind: AuthFailureKind.unavailable,
        );
      addTearDown(auth.controller.close);
      final access = AccessLock();
      final session = _SessionSecurity();
      final workspace = FixtureWorkspace();
      var reconciliations = 0;
      final candidate = OfflineResumeCandidate(
        workspace: workspace,
        branchId: branch,
        label: 'Signed fixture grant',
        actor: _member(branches: {branch}),
        dispose: () async {},
      );
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            authRepositoryProvider.overrideWithValue(auth),
            accessLockProvider.overrideWithValue(access),
            sessionSecurityProvider.overrideWithValue(session),
            offlineResumeFactoryProvider.overrideWithValue(
              (_) async => [candidate],
            ),
            offlineMembershipReconcilerProvider.overrideWithValue(
              (identity, memberships) async => reconciliations++,
            ),
          ],
          child: const NexaApp(),
        ),
      );
      await tester.pumpAndSettle();
      final open = find.byKey(const Key('open-authorized-offline'));
      await tester.ensureVisible(open);
      await tester.tap(open);
      await tester.pumpAndSettle();
      expect(find.byType(OfflineWorkspacePage), findsOneWidget);
      access.lock();
      await tester.pumpAndSettle();
      auth.membershipError = null;
      auth.memberships = [
        _member(branches: {'changed-branch'}),
      ];
      await tester.enterText(
        find.widgetWithText(TextField, 'Account password'),
        'test-password',
      );
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('Unlock online'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Unlock online'));
      await tester.pumpAndSettle();
      expect(reconciliations, greaterThan(0));
      expect(access.isLocked, isTrue);
      expect(find.byType(OfflineWorkspacePage), findsNothing);
      expect(
        find.text('Business access changed. Sign out and sign in again.'),
        findsOneWidget,
      );
    },
  );
  testWidgets('root MFA gate admits shell only after verified AAL2 callback', (
    tester,
  ) async {
    final h = _Harness();
    await h.mount(tester);
    expect(find.byType(NexaShell), findsNothing);
    expect(find.text('Verify your authenticator'), findsOneWidget);
    await tester.enterText(
      find.widgetWithText(TextField, 'Six-digit code'),
      '123456',
    );
    await tester.tap(find.text('Verify code'));
    await tester.pumpAndSettle();
    expect(find.byType(NexaShell), findsOneWidget);
  });

  testWidgets('auth assurance downgrade removes shell and any old dialog', (
    tester,
  ) async {
    final h = _Harness()..mfa.level = MfaAssuranceLevel.aal2;
    await h.mount(tester);
    await h.dialog(tester);
    h.mfa.level = MfaAssuranceLevel.aal1;
    h.auth.emitTokenRefreshed();
    await tester.pumpAndSettle();
    expect(find.byType(NexaShell), findsNothing);
    expect(find.text('Retained payment dialog'), findsNothing);
    expect(find.text('Verify your authenticator'), findsOneWidget);
  });

  testWidgets(
    'idle lock preserves dialog and unlock rechecks policy after access restored',
    (tester) async {
      final h = _Harness()..mfa.level = MfaAssuranceLevel.aal2;
      await h.mount(tester);
      await h.dialog(tester);
      final membershipsBefore = h.auth.membershipCalls;
      h.access.lock();
      await tester.pumpAndSettle();
      expect(find.text('Workspace locked'), findsOneWidget);
      expect(find.text('Retained payment dialog'), findsNothing);
      expect(
        find.text('Retained payment dialog', skipOffstage: false),
        findsOneWidget,
      );
      await h.unlock(tester);
      expect(h.session.passwords, ['test-password']);
      expect(h.auth.membershipCalls, greaterThan(membershipsBefore));
      expect(h.access.isLocked, isFalse);
      expect(find.text('Retained payment dialog'), findsOneWidget);
      expect(find.text('recorded-reference-test'), findsOneWidget);
      expect(
        find.text(
          'Your business security requirements could not be confirmed. Reconnect and try again.',
        ),
        findsNothing,
      );
    },
  );

  testWidgets('role change during lock keeps workspace locked', (tester) async {
    final h = _Harness()..mfa.level = MfaAssuranceLevel.aal2;
    await h.mount(tester);
    h.access.lock();
    await tester.pumpAndSettle();
    h.auth.memberships = [_member(role: AppRole.cashier)];
    await h.unlock(tester);
    expect(h.access.isLocked, isTrue);
    expect(find.text('Workspace locked'), findsOneWidget);
    expect(
      find.text('Business access changed. Sign out and sign in again.'),
      findsOneWidget,
    );
  });

  testWidgets('branch access change during lock keeps workspace locked', (
    tester,
  ) async {
    final h = _Harness()..mfa.level = MfaAssuranceLevel.aal2;
    await h.mount(tester);
    h.access.lock();
    await tester.pumpAndSettle();
    h.auth.memberships = [
      _member(branches: {'branch-b'}),
    ];
    await h.unlock(tester);
    expect(h.access.isLocked, isTrue);
    expect(
      find.text('Business access changed. Sign out and sign in again.'),
      findsOneWidget,
    );
  });

  testWidgets(
    'late password verification after signout cannot unlock old workspace',
    (tester) async {
      final h = _Harness()..mfa.level = MfaAssuranceLevel.aal2;
      await h.mount(tester);
      h.access.lock();
      await tester.pumpAndSettle();
      h.session.pending = Completer<void>();
      await tester.enterText(
        find.widgetWithText(TextField, 'Account password'),
        'test-password',
      );
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('Unlock online'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Unlock online'));
      await tester.pump();
      await h.auth.signOut();
      h.session.pending!.complete();
      await tester.pumpAndSettle();
      expect(find.byType(NexaShell), findsNothing);
      expect(h.auth.currentIdentity, isNull);
      expect(find.text('Workspace locked'), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );
}
