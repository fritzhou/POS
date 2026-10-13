import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nexapos/core/auth/auth_models.dart';
import 'package:nexapos/features/authentication/presentation/auth_gate.dart';

import 'auth_gate_test.dart' show FakeAuthRepository;

const identity = AuthIdentity(
  userId: 'same-remembered-actor',
  email: 'actor@example.test',
  emailVerified: true,
);

Future<void> mount(
  WidgetTester tester,
  FakeAuthRepository repository, {
  Future<void> Function(AuthIdentity)? open,
}) async {
  tester.view.physicalSize = const Size(1280, 1200);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(
    MaterialApp(
      home: AuthGate(
        repository: repository,
        onPreview: () {},
        onOpenOffline: open,
        authenticatedBuilder: (_, _) => const Text('ONLINE AUTHORIZED'),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('transport loss offers explicit separate grant resume', (
    tester,
  ) async {
    final repository = FakeAuthRepository()
      ..identity = identity
      ..membershipError = const AuthFailure(
        'Connection unavailable.',
        kind: AuthFailureKind.unavailable,
      );
    addTearDown(repository.controller.close);
    AuthIdentity? resumed;
    await mount(tester, repository, open: (actor) async => resumed = actor);
    expect(find.text('ONLINE AUTHORIZED'), findsNothing);
    final entry = find.byKey(const Key('open-authorized-offline'));
    expect(entry, findsOneWidget);
    expect(resumed, isNull);
    await tester.ensureVisible(entry);
    await tester.tap(entry);
    await tester.pumpAndSettle();
    expect(resumed?.userId, identity.userId);
    expect(find.text('ONLINE AUTHORIZED'), findsNothing);
  });

  for (final failure in <Object?>[
    null,
    const AuthFailure(
      'Permission denied.',
      kind: AuthFailureKind.authorization,
    ),
    const AuthFailure('The authentication service is temporarily unavailable.'),
    const FormatException('Invalid server response'),
  ]) {
    testWidgets('only typed transport failures offer grant resume: $failure', (
      tester,
    ) async {
      final repository = FakeAuthRepository()
        ..identity = identity
        ..membershipError = failure;
      addTearDown(repository.controller.close);
      await mount(tester, repository, open: (_) async {});
      expect(find.byKey(const Key('open-authorized-offline')), findsNothing);
      expect(find.text('ONLINE AUTHORIZED'), findsNothing);
    });
  }

  testWidgets('recovery never offers grant resume during network loss', (
    tester,
  ) async {
    final repository = FakeAuthRepository()
      ..identity = identity
      ..membershipError = const AuthFailure(
        'Connection unavailable.',
        kind: AuthFailureKind.unavailable,
      );
    repository.recoveryPolicy.beginVerifiedRecovery(identity.userId);
    addTearDown(repository.controller.close);
    await mount(tester, repository, open: (_) async {});
    expect(find.text('Choose a new password'), findsOneWidget);
    expect(find.byKey(const Key('open-authorized-offline')), findsNothing);
  });

  testWidgets('definitive empty refresh removes previously available resume', (
    tester,
  ) async {
    final repository = FakeAuthRepository()
      ..identity = identity
      ..membershipError = const AuthFailure(
        'Connection unavailable.',
        kind: AuthFailureKind.unavailable,
      );
    addTearDown(repository.controller.close);
    await mount(tester, repository, open: (_) async {});
    expect(find.byKey(const Key('open-authorized-offline')), findsOneWidget);
    repository.membershipError = null;
    repository.emitTokenRefreshed();
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('open-authorized-offline')), findsNothing);
  });
}
