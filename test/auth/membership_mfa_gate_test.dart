import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nexapos/core/auth/auth_models.dart';
import 'package:nexapos/core/security/app_role.dart';
import 'package:nexapos/features/authentication/domain/mfa_repository.dart';
import 'package:nexapos/features/authentication/presentation/membership_mfa_gate.dart';
import 'package:nexapos/features/security/domain/security_models.dart';
import 'package:nexapos/features/security/domain/security_repository.dart';

class _PolicyRepository implements SecurityRepository {
  bool required = true;
  Object? error;
  Completer<SecurityPolicy>? pending;
  int loads = 0;
  @override
  String organizationId = 'organization-a';
  @override
  Future<SecurityPolicy> loadPolicy() async {
    loads++;
    if (error != null) throw error!;
    return pending?.future ??
        SecurityPolicy(
          organizationId: organizationId,
          idleLockMinutes: 5,
          requirePrivilegedMfa: required,
          revision: 1,
        );
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _MfaRepository implements MfaRepository {
  @override
  String? actorId = 'actor-a';
  MfaAssuranceLevel level = MfaAssuranceLevel.aal1;
  Completer<MfaStatus>? pending;
  int loads = 0;
  @override
  Future<MfaStatus> status() async {
    loads++;
    return pending?.future ??
        MfaStatus(
          actorId: actorId!,
          currentLevel: level,
          nextLevel: MfaAssuranceLevel.aal2,
          factors: [],
        );
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

AuthenticatedUser _actor({
  String id = 'actor-a',
  AppRole role = AppRole.owner,
}) => AuthenticatedUser(
  userId: id,
  email: '$id@example.test',
  organizationId: 'organization-a',
  membershipId: 'membership-$id',
  role: role,
  branchIds: {'branch-a'},
  allBranches: true,
  businessName: 'Test business',
);

Future<void> _show(
  WidgetTester tester,
  _PolicyRepository policy,
  _MfaRepository mfa, {
  AuthenticatedUser? actor,
  Object? refresh,
  ValueChanged<SecurityPolicy>? onPolicy,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      home: MembershipMfaGate(
        actor: actor ?? _actor(),
        securityRepository: policy,
        mfaRepository: mfa,
        onSignOut: () async {},
        refreshToken: refresh,
        onPolicyLoaded: onPolicy,
        child: const Text('Verified business shell'),
      ),
    ),
  );
  await tester.pump();
  await tester.pump();
}

void main() {
  testWidgets('required owner AAL1 never builds business shell', (
    tester,
  ) async {
    final policy = _PolicyRepository();
    final mfa = _MfaRepository();
    await _show(tester, policy, mfa);
    await tester.pumpAndSettle();
    expect(find.text('Verified business shell'), findsNothing);
    expect(find.text('Verify your authenticator'), findsOneWidget);
    expect(policy.loads, 1);
  });

  testWidgets('required owner genuine AAL2 can build shell', (tester) async {
    final policy = _PolicyRepository();
    final mfa = _MfaRepository()..level = MfaAssuranceLevel.aal2;
    SecurityPolicy? loaded;
    await _show(tester, policy, mfa, onPolicy: (value) => loaded = value);
    expect(find.text('Verified business shell'), findsOneWidget);
    expect(loaded?.idleLockMinutes, 5);
  });

  testWidgets('policy disabled uses source policy without asking OTP', (
    tester,
  ) async {
    final policy = _PolicyRepository()..required = false;
    final mfa = _MfaRepository();
    await _show(tester, policy, mfa);
    expect(find.text('Verified business shell'), findsOneWidget);
    expect(mfa.loads, 0);
  });

  testWidgets('cashier and manager are outside owner admin requirement', (
    tester,
  ) async {
    final policy = _PolicyRepository();
    final mfa = _MfaRepository();
    await _show(tester, policy, mfa, actor: _actor(role: AppRole.cashier));
    expect(find.text('Verified business shell'), findsOneWidget);
    await _show(tester, policy, mfa, actor: _actor(role: AppRole.manager));
    expect(find.text('Verified business shell'), findsOneWidget);
    expect(mfa.loads, 0);
  });

  testWidgets('policy transport failure fails closed with retry', (
    tester,
  ) async {
    final policy = _PolicyRepository()
      ..error = StateError('private policy detail');
    final mfa = _MfaRepository();
    await _show(tester, policy, mfa);
    expect(find.text('Verified business shell'), findsNothing);
    expect(find.text('Retry'), findsOneWidget);
    expect(find.textContaining('private policy'), findsNothing);
    policy.error = null;
    mfa.level = MfaAssuranceLevel.aal2;
    await tester.tap(find.text('Retry'));
    await tester.pumpAndSettle();
    expect(find.text('Verified business shell'), findsOneWidget);
  });

  testWidgets('foreign organization policy never authorizes', (tester) async {
    final policy = _PolicyRepository()..organizationId = 'other-organization';
    final mfa = _MfaRepository()..level = MfaAssuranceLevel.aal2;
    await _show(tester, policy, mfa);
    expect(find.text('Verified business shell'), findsNothing);
    expect(find.text('Retry'), findsOneWidget);
  });

  testWidgets('refresh removes shell immediately while policy rechecked', (
    tester,
  ) async {
    final policy = _PolicyRepository()..required = false;
    final mfa = _MfaRepository();
    await _show(tester, policy, mfa, refresh: 1);
    expect(find.text('Verified business shell'), findsOneWidget);
    policy.pending = Completer<SecurityPolicy>();
    await _show(tester, policy, mfa, refresh: 2);
    expect(find.text('Verified business shell'), findsNothing);
    policy.pending!.complete(
      const SecurityPolicy(
        organizationId: 'organization-a',
        idleLockMinutes: 5,
        requirePrivilegedMfa: true,
        revision: 2,
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Verify your authenticator'), findsOneWidget);
    expect(find.text('Verified business shell'), findsNothing);
  });

  testWidgets('stale AAL2 result from previous actor cannot build shell', (
    tester,
  ) async {
    final policy = _PolicyRepository();
    final mfa = _MfaRepository()..pending = Completer<MfaStatus>();
    await _show(tester, policy, mfa);
    mfa.actorId = 'actor-b';
    mfa.pending!.complete(
      MfaStatus(
        actorId: 'actor-a',
        currentLevel: MfaAssuranceLevel.aal2,
        nextLevel: MfaAssuranceLevel.aal2,
        factors: [],
      ),
    );
    await tester.pump();
    expect(find.text('Verified business shell'), findsNothing);
  });
}
