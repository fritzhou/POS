import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nexapos/app/app.dart';
import 'package:nexapos/app/offline_services.dart';
import 'package:nexapos/core/auth/auth_models.dart';
import 'package:nexapos/features/offline/presentation/offline_workspace_page.dart';

import '../auth/auth_gate_test.dart' show FakeAuthRepository;
import '../offline_widgets/offline_workspace_page_test.dart'
    show FixtureWorkspace, branch;

const identity = AuthIdentity(
  userId: 'remembered-resume-actor',
  email: 'actor@example.test',
  emailVerified: true,
);

class Harness {
  final auth = FakeAuthRepository()
    ..identity = identity
    ..membershipError = const AuthFailure(
      'Connection unavailable.',
      kind: AuthFailureKind.unavailable,
    );
  final workspace = FixtureWorkspace()..active = false;
  final lockedActors = <String>[];
  int disposed = 0, onlineConstructions = 0;

  OfflineResumeCandidate candidate({String label = 'Stored branch'}) =>
      OfflineResumeCandidate(
        workspace: workspace,
        branchId: branch,
        label: label,
        dispose: () async => disposed++,
      );

  Future<void> mount(
    WidgetTester tester, {
    OfflineResumeFactory? resume,
    OfflineIdentityLock? lock,
  }) async {
    tester.view.physicalSize = const Size(1280, 1200);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(auth.controller.close);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          authRepositoryProvider.overrideWithValue(auth),
          offlineResumeFactoryProvider.overrideWithValue(
            resume ?? (_) async => [candidate()],
          ),
          offlineIdentityLockProvider.overrideWithValue(
            lock ?? (actorId) async => lockedActors.add(actorId),
          ),
          businessServicesFactoryProvider.overrideWithValue((_) {
            onlineConstructions++;
            throw StateError('Offline grant cannot construct the online shell');
          }),
        ],
        child: const NexaApp(),
      ),
    );
    await tester.pumpAndSettle();
  }

  Future<void> open(WidgetTester tester, {bool settle = true}) async {
    final target = find.byKey(const Key('open-authorized-offline'));
    await tester.ensureVisible(target);
    await tester.tap(target);
    if (settle) {
      await tester.pumpAndSettle();
    } else {
      await tester.pump(const Duration(milliseconds: 350));
    }
  }
}

void main() {
  testWidgets('grant-only resume opens separate page with explicit branch', (
    tester,
  ) async {
    final h = Harness();
    await h.mount(tester);
    expect(find.byType(OfflineWorkspacePage), findsNothing);
    await h.open(tester);
    final page = tester.widget<OfflineWorkspacePage>(
      find.byType(OfflineWorkspacePage),
    );
    expect(page.initialBranchId, branch);
    expect(page.peopleRepository, isNull);
    expect(h.onlineConstructions, 0);
    expect(h.workspace.active, isFalse);
    expect(tester.takeException(), isNull);
  });

  testWidgets('multiple retained grants require scope choice', (tester) async {
    final h = Harness();
    await h.mount(
      tester,
      resume: (_) async => [
        h.candidate(label: 'Branch one'),
        h.candidate(label: 'Branch two'),
      ],
    );
    await h.open(tester, settle: false);
    expect(find.byType(OfflineWorkspacePage), findsNothing);
    await tester.tap(find.text('Branch two'));
    await tester.pumpAndSettle();
    expect(find.byType(OfflineWorkspacePage), findsOneWidget);
    expect(h.disposed, 1);
    expect(h.onlineConstructions, 0);
  });

  testWidgets('recovery removes page and locks remembered device', (
    tester,
  ) async {
    final h = Harness();
    await h.mount(tester);
    await h.open(tester);
    h.auth.recoveryPolicy.beginVerifiedRecovery(identity.userId);
    h.auth.controller.add(
      const AuthSessionEvent(AuthSessionEventType.passwordRecovery, identity),
    );
    await tester.pumpAndSettle();
    expect(find.byType(OfflineWorkspacePage), findsNothing);
    expect(find.text('Choose a new password'), findsOneWidget);
    expect(h.workspace.suspendCalls, 1);
    expect(h.lockedActors, contains(identity.userId));
    expect(h.disposed, 1);
  });

  testWidgets('same-actor refresh preserves active grant page', (tester) async {
    final h = Harness();
    await h.mount(tester);
    await h.open(tester);
    h.auth.emitTokenRefreshed();
    await tester.pumpAndSettle();
    expect(find.byType(OfflineWorkspacePage), findsOneWidget);
    expect(h.workspace.suspendCalls, 0);
    expect(h.onlineConstructions, 0);
  });

  testWidgets('account change removes old page without exposing new actor', (
    tester,
  ) async {
    final h = Harness();
    await h.mount(tester);
    await h.open(tester);
    const changed = AuthIdentity(
      userId: 'different-actor',
      email: 'different@example.test',
      emailVerified: true,
    );
    h.auth.identity = changed;
    h.auth.controller.add(
      const AuthSessionEvent(AuthSessionEventType.signedIn, changed),
    );
    await tester.pumpAndSettle();
    expect(find.byType(OfflineWorkspacePage), findsNothing);
    expect(h.lockedActors, contains(identity.userId));
    expect(h.workspace.suspendCalls, 1);
  });

  testWidgets('late resolver response cannot resume a signed-out actor', (
    tester,
  ) async {
    final h = Harness();
    final pending = Completer<List<OfflineResumeCandidate>>();
    await h.mount(tester, resume: (_) => pending.future);
    final target = find.byKey(const Key('open-authorized-offline'));
    await tester.ensureVisible(target);
    await tester.tap(target);
    await tester.pump();
    await h.auth.signOut();
    pending.complete([h.candidate()]);
    await tester.pumpAndSettle();
    expect(find.byType(OfflineWorkspacePage), findsNothing);
    expect(h.disposed, 1);
    expect(h.onlineConstructions, 0);
  });

  testWidgets('definitive empty authority clears persisted device access', (
    tester,
  ) async {
    final h = Harness();
    h.auth.membershipError = null;
    await h.mount(tester);
    expect(h.lockedActors, contains(identity.userId));
    expect(find.byKey(const Key('open-authorized-offline')), findsNothing);
    expect(h.onlineConstructions, 0);
  });

  testWidgets(
    'device cleanup failure still signs out Auth and closes resources',
    (tester) async {
      final h = Harness();
      await h.mount(
        tester,
        lock: (_) async => throw StateError('vault unavailable'),
      );
      await h.open(tester);
      await tester.tap(find.byTooltip('Lock offline workspace'));
      await tester.pumpAndSettle();
      expect(h.auth.currentIdentity, isNull);
      expect(find.byType(OfflineWorkspacePage), findsNothing);
      expect(find.byKey(const Key('open-authorized-offline')), findsNothing);
      expect(h.disposed, 1);
      expect(tester.takeException(), isNull);
    },
  );
}
