import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nexapos/features/authentication/domain/mfa_repository.dart';
import 'package:nexapos/features/authentication/presentation/security_mfa_page.dart';

// Explicit test doubles exercise UI races and form behavior, not provider MFA.
class _FakeMfa implements MfaRepository {
  @override
  String? actorId = 'actor-a';
  MfaAssuranceLevel level = MfaAssuranceLevel.aal1;
  List<MfaFactor> factors = [];
  Object? error;
  Completer<MfaStatus>? pendingStatus;
  Completer<MfaEnrollment>? pendingEnrollment;
  Completer<MfaStatus>? pendingVerification;
  int enrollments = 0;
  int challenges = 0;
  final verifiedCodes = <String>[];
  final canceled = <String>[];
  final removed = <String>[];

  MfaStatus snapshot() => MfaStatus(
    actorId: actorId ?? 'signed-out',
    currentLevel: level,
    nextLevel: factors.any((factor) => factor.isVerified)
        ? MfaAssuranceLevel.aal2
        : level,
    factors: factors,
  );

  @override
  Future<MfaStatus> status() async {
    if (error != null) throw error!;
    return pendingStatus?.future ?? snapshot();
  }

  @override
  Future<MfaEnrollment> enrollTotp({required String name}) async {
    enrollments++;
    if (error != null) throw error!;
    return pendingEnrollment?.future ??
        const MfaEnrollment(factorId: 'factor-new', secret: 'JBSWY3DPEHPK3PXP');
  }

  @override
  Future<MfaChallenge> challenge(String factorId) async {
    challenges++;
    if (error != null) throw error!;
    return MfaChallenge(
      factorId: factorId,
      id: 'challenge-$challenges',
      expiresAt: DateTime.now().add(const Duration(minutes: 5)),
    );
  }

  @override
  Future<MfaStatus> verify(MfaChallenge challenge, String code) async {
    verifiedCodes.add(code);
    if (error != null) throw error!;
    if (pendingVerification != null) return pendingVerification!.future;
    level = MfaAssuranceLevel.aal2;
    factors = [
      const MfaFactor(
        id: 'factor-new',
        name: 'My authenticator',
        isVerified: true,
        isTotp: true,
      ),
    ];
    return snapshot();
  }

  @override
  Future<void> cancelEnrollment(String factorId) async =>
      canceled.add(factorId);

  @override
  Future<void> unenroll(String factorId) async {
    removed.add(factorId);
    factors = factors.where((factor) => factor.id != factorId).toList();
  }
}

const _verified = MfaFactor(
  id: 'factor-current',
  name: 'Current authenticator',
  isVerified: true,
  isTotp: true,
);

Future<void> _show(
  WidgetTester tester,
  _FakeMfa repository, {
  bool required = false,
  Future<void> Function()? onChanged,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: SecurityMfaPage(
          repository: repository,
          requireVerification: required,
          onAssuranceChanged: onChanged,
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

Finder _codeField() => find.widgetWithText(TextField, 'Six-digit code');

void main() {
  testWidgets('signout remains available during delayed provider operation', (
    tester,
  ) async {
    final repository = _FakeMfa()..pendingStatus = Completer<MfaStatus>();
    var signouts = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SecurityMfaPage(
            repository: repository,
            onSignOut: () async => signouts++,
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.tap(find.text('Sign out'));
    await tester.pump();
    expect(signouts, 1);
    await tester.pumpWidget(const SizedBox.shrink());
    repository.pendingStatus!.complete(repository.snapshot());
    await tester.pump();
    expect(tester.takeException(), isNull);
  });
  testWidgets(
    'empty real factor response offers enrollment without claiming protected',
    (tester) async {
      final repository = _FakeMfa();
      await _show(tester, repository);
      expect(find.text('Set up authenticator'), findsOneWidget);
      expect(
        find.text('This session has verified an authenticator.'),
        findsNothing,
      );
      expect(find.text('Verified authenticator'), findsNothing);
    },
  );

  testWidgets(
    'setup key is hidden until explicit reveal and cleared on cancel',
    (tester) async {
      final repository = _FakeMfa();
      await _show(tester, repository);
      await tester.tap(find.text('Set up authenticator'));
      await tester.pumpAndSettle();
      final keyField = find.widgetWithText(
        TextField,
        'Authenticator setup key',
      );
      expect(tester.widget<TextField>(keyField).obscureText, isTrue);
      await tester.tap(find.byTooltip('Show setup key'));
      await tester.pumpAndSettle();
      expect(tester.widget<TextField>(keyField).obscureText, isFalse);
      await tester.ensureVisible(find.text('Cancel setup'));
      await tester.tap(find.text('Cancel setup'));
      await tester.pumpAndSettle();
      expect(repository.canceled, ['factor-new']);
      expect(keyField, findsNothing);
      expect(find.text('JBSWY3DPEHPK3PXP'), findsNothing);
    },
  );

  testWidgets('incomplete code never requests a provider challenge', (
    tester,
  ) async {
    final repository = _FakeMfa()..factors = [_verified];
    await _show(tester, repository);
    await tester.enterText(_codeField(), '12345');
    await tester.tap(find.text('Verify code'));
    await tester.pumpAndSettle();
    expect(repository.challenges, 0);
    expect(
      find.text('Enter the six-digit authenticator code.'),
      findsOneWidget,
    );
  });

  testWidgets('code input accepts only six digits and clears before dispatch', (
    tester,
  ) async {
    final repository = _FakeMfa()..factors = [_verified];
    var changed = 0;
    await _show(tester, repository, onChanged: () async => changed++);
    await tester.enterText(_codeField(), '12a34567');
    expect(tester.widget<TextField>(_codeField()).controller!.text, '123456');
    await tester.tap(find.text('Verify code'));
    await tester.pumpAndSettle();
    expect(repository.verifiedCodes, ['123456']);
    expect(tester.widget<TextField>(_codeField()).controller!.text, isEmpty);
    expect(changed, 1);
    expect(
      find.text('Two-step verification confirmed for this session.'),
      findsOneWidget,
    );
  });

  testWidgets(
    'expired challenge stays blocked and fresh retry creates new challenge',
    (tester) async {
      final repository = _FakeMfa()..factors = [_verified];
      var changed = 0;
      await _show(
        tester,
        repository,
        required: true,
        onChanged: () async => changed++,
      );
      repository.error = const MfaFailure(
        'Challenge expired. Try a new code.',
        kind: MfaFailureKind.expired,
      );
      await tester.enterText(_codeField(), '123456');
      await tester.tap(find.text('Verify code'));
      await tester.pumpAndSettle();
      expect(changed, 0);
      expect(find.text('Challenge expired. Try a new code.'), findsOneWidget);
      repository.error = null;
      await tester.enterText(_codeField(), '234567');
      await tester.tap(find.text('Verify code'));
      await tester.pumpAndSettle();
      expect(repository.challenges, 2);
      expect(changed, 1);
    },
  );

  testWidgets('verification result lacking AAL2 never calls success callback', (
    tester,
  ) async {
    final repository = _FakeMfa()
      ..factors = [_verified]
      ..pendingVerification = Completer<MfaStatus>();
    var changed = 0;
    await _show(
      tester,
      repository,
      required: true,
      onChanged: () async => changed++,
    );
    await tester.enterText(_codeField(), '123456');
    await tester.tap(find.text('Verify code'));
    await tester.pump();
    repository.pendingVerification!.complete(repository.snapshot());
    await tester.pumpAndSettle();
    expect(changed, 0);
    expect(
      find.text('Two-step verification was not confirmed.'),
      findsOneWidget,
    );
  });

  testWidgets('closing live setup removes only its unfinished factor', (
    tester,
  ) async {
    final repository = _FakeMfa();
    await _show(tester, repository);
    await tester.tap(find.text('Set up authenticator'));
    await tester.pumpAndSettle();
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
    expect(repository.canceled, ['factor-new']);
    expect(repository.removed, isEmpty);
  });

  testWidgets(
    'delayed enrollment after close cleans up without rendering secret',
    (tester) async {
      final repository = _FakeMfa()
        ..pendingEnrollment = Completer<MfaEnrollment>();
      await _show(tester, repository);
      await tester.tap(find.text('Set up authenticator'));
      await tester.pump();
      await tester.pumpWidget(const SizedBox.shrink());
      repository.pendingEnrollment!.complete(
        const MfaEnrollment(factorId: 'delayed', secret: 'JBSWY3DPEHPK3PXP'),
      );
      await tester.pump();
      expect(repository.canceled, ['delayed']);
      expect(find.text('JBSWY3DPEHPK3PXP'), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'delayed verification from switched actor cannot signal success',
    (tester) async {
      final repository = _FakeMfa()
        ..factors = [_verified]
        ..pendingVerification = Completer<MfaStatus>();
      var changed = 0;
      await _show(
        tester,
        repository,
        required: true,
        onChanged: () async => changed++,
      );
      await tester.enterText(_codeField(), '123456');
      await tester.tap(find.text('Verify code'));
      await tester.pump();
      repository.actorId = 'actor-b';
      repository.pendingVerification!.complete(
        MfaStatus(
          actorId: 'actor-a',
          currentLevel: MfaAssuranceLevel.aal2,
          nextLevel: MfaAssuranceLevel.aal2,
          factors: [_verified],
        ),
      );
      await tester.pump();
      expect(changed, 0);
      expect(
        find.text('Two-step verification confirmed for this session.'),
        findsNothing,
      );
    },
  );

  testWidgets('verified removal is disabled before AAL2', (tester) async {
    final repository = _FakeMfa()..factors = [_verified];
    await _show(tester, repository);
    expect(
      tester
          .widget<IconButton>(
            find.byWidgetPredicate(
              (widget) =>
                  widget is IconButton &&
                  widget.tooltip == 'Remove authenticator',
            ),
          )
          .onPressed,
      isNull,
    );
  });

  testWidgets('verified removal at AAL2 requires explicit confirmation', (
    tester,
  ) async {
    final repository = _FakeMfa()
      ..factors = [_verified]
      ..level = MfaAssuranceLevel.aal2;
    await _show(tester, repository);
    await tester.ensureVisible(find.byTooltip('Remove authenticator'));
    await tester.tap(find.byTooltip('Remove authenticator'));
    await tester.pumpAndSettle();
    expect(repository.removed, isEmpty);
    await tester.tap(find.text('Remove'));
    await tester.pumpAndSettle();
    expect(repository.removed, ['factor-current']);
  });

  testWidgets('required flow offers enrollment if no verified TOTP exists', (
    tester,
  ) async {
    await _show(tester, _FakeMfa(), required: true);
    expect(find.text('Verify your authenticator'), findsOneWidget);
    expect(find.text('Set up authenticator'), findsOneWidget);
  });

  testWidgets('raw failure details never reach the live setup form', (
    tester,
  ) async {
    final repository = _FakeMfa()
      ..error = StateError('private secret diagnostic');
    await _show(tester, repository);
    expect(
      find.text('Two-step verification could not be completed.'),
      findsOneWidget,
    );
    expect(find.textContaining('private secret'), findsNothing);
  });

  testWidgets(
    '320 pixel setup and code form remains scrollable without overflow',
    (tester) async {
      tester.view.physicalSize = const Size(320, 640);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final repository = _FakeMfa();
      await _show(tester, repository);
      await tester.ensureVisible(find.text('Set up authenticator'));
      await tester.tap(find.text('Set up authenticator'));
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('Finish setup'));
      expect(tester.takeException(), isNull);
    },
  );
}
