import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nexapos/core/auth/auth_models.dart';
import 'package:nexapos/core/auth/invitation_inbox.dart';
import 'package:nexapos/core/security/app_role.dart';
import 'package:nexapos/features/authentication/presentation/auth_gate.dart';

import 'auth_gate_test.dart' show FakeAuthRepository;

const _identity = AuthIdentity(
  userId: 'real-auth-user',
  email: 'employee@example.test',
  emailVerified: true,
);

AuthenticatedUser _member(
  String organization, {
  AppRole role = AppRole.cashier,
}) => AuthenticatedUser(
  userId: _identity.userId,
  email: _identity.email,
  organizationId: organization,
  membershipId: 'membership-$organization',
  role: role,
  branchIds: {'branch-$organization'},
  allBranches: role == AppRole.owner,
  businessName: organization,
);

PendingEmployeeInvitation _invitation({bool passwordRequired = false}) =>
    PendingEmployeeInvitation(
      id: 'invitation-id',
      organizationId: 'invited-business',
      businessName: 'Invited business',
      fullName: 'Employee name',
      role: AppRole.manager,
      branchIds: {'branch-invited-business'},
      branchNames: ['Main Branch'],
      allBranches: false,
      requiresPassword: passwordRequired,
      expiresAt: DateTime.utc(2030),
    );

class _FakeInbox implements InvitationInbox {
  _FakeInbox(this.auth, {bool passwordRequired = false})
    : pending = [_invitation(passwordRequired: passwordRequired)];
  final FakeAuthRepository auth;
  List<PendingEmployeeInvitation> pending;
  Object? listError;
  Object? acceptError;
  bool loseAcceptedResponse = false;
  String? password;
  int listCalls = 0;
  int acceptCalls = 0;

  @override
  Future<List<PendingEmployeeInvitation>> listPending() async {
    listCalls++;
    if (listError != null) throw listError!;
    return pending;
  }

  @override
  Future<void> accept(
    PendingEmployeeInvitation invitation, {
    String? newPassword,
  }) async {
    acceptCalls++;
    password = newPassword;
    if (acceptError != null) throw acceptError!;
    // Only the refreshed membership context grants this role, not the invitation
    // preview or acceptance response. A changed server role wins.
    auth.memberships = [...auth.memberships, _member('invited-business')];
    pending = [];
    if (loseAcceptedResponse) {
      throw const InvitationFailure(
        'Acceptance response could not be confirmed.',
      );
    }
  }
}

Future<void> _mount(
  WidgetTester tester,
  FakeAuthRepository auth,
  _FakeInbox inbox,
) async {
  tester.view.physicalSize = const Size(1280, 1200);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(
    MaterialApp(
      home: AuthGate(
        repository: auth,
        invitationInbox: inbox,
        onPreview: () {},
        authenticatedBuilder: (context, member) => Scaffold(
          body: Text('Live ${member.organizationId} ${member.role.name}'),
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

Future<void> _enter(WidgetTester tester, String label, String value) async {
  final target = find.widgetWithText(TextFormField, label);
  await tester.ensureVisible(target);
  await tester.enterText(target, value);
}

void main() {
  testWidgets(
    'invitation role and branches are read-only and explicit acceptance joins actual membership',
    (tester) async {
      final auth = FakeAuthRepository()..identity = _identity;
      final inbox = _FakeInbox(auth);
      await _mount(tester, auth, inbox);
      expect(find.text('Invited role: Manager'), findsOneWidget);
      expect(find.text('Branches: Main Branch'), findsOneWidget);
      expect(find.byType(DropdownButtonFormField<AppRole>), findsNothing);
      expect(find.textContaining('Live '), findsNothing);
      expect(inbox.acceptCalls, 0);
      await _tap(tester, 'Review invitation');
      expect(
        find.text('Your existing account password will be kept.'),
        findsOneWidget,
      );
      await _tap(tester, 'Accept invitation');
      expect(inbox.password, isNull);
      expect(find.text('Live invited-business cashier'), findsOneWidget);
      expect(auth.membershipCalls, greaterThan(1));
    },
  );

  testWidgets(
    'failed acceptance cannot grant proposed business or expose raw error',
    (tester) async {
      final auth = FakeAuthRepository()..identity = _identity;
      final inbox = _FakeInbox(auth)
        ..acceptError = Exception('private token=SECRET');
      await _mount(tester, auth, inbox);
      await _tap(tester, 'Review invitation');
      await _tap(tester, 'Accept invitation');
      expect(find.textContaining('Live '), findsNothing);
      expect(find.textContaining('SECRET'), findsNothing);
      expect(find.textContaining('temporarily unavailable'), findsOneWidget);
      expect(auth.memberships, isEmpty);
    },
  );

  testWidgets('unverified identity cannot list or accept invitations', (
    tester,
  ) async {
    final auth = FakeAuthRepository()
      ..identity = const AuthIdentity(
        userId: 'real-auth-user',
        email: 'employee@example.test',
        emailVerified: false,
      );
    final inbox = _FakeInbox(auth);
    await _mount(tester, auth, inbox);
    expect(inbox.listCalls, 0);
    expect(inbox.acceptCalls, 0);
    expect(find.text('Review invitation'), findsNothing);
    expect(find.textContaining('Live '), findsNothing);
  });

  testWidgets(
    'recovery event removes invitation actions even after pending was loaded',
    (tester) async {
      final auth = FakeAuthRepository()..identity = _identity;
      final inbox = _FakeInbox(auth);
      await _mount(tester, auth, inbox);
      await _tap(tester, 'Review invitation');
      auth.emitRecovery(verified: true);
      await tester.pumpAndSettle();
      expect(find.text('Choose a new password'), findsOneWidget);
      expect(find.text('Accept invitation'), findsNothing);
      expect(inbox.acceptCalls, 0);
    },
  );

  testWidgets(
    'new invited account requires a strong matching password before accept',
    (tester) async {
      final auth = FakeAuthRepository()..identity = _identity;
      final inbox = _FakeInbox(auth, passwordRequired: true);
      await _mount(tester, auth, inbox);
      await _tap(tester, 'Review invitation');
      await _enter(tester, 'Create password', 'LongSafePassword123!');
      await _enter(tester, 'Confirm password', 'different');
      await _tap(tester, 'Accept invitation');
      expect(inbox.acceptCalls, 0);
      expect(find.text('Passwords do not match.'), findsOneWidget);
      await _enter(tester, 'Confirm password', 'LongSafePassword123!');
      await _tap(tester, 'Accept invitation');
      expect(inbox.password, 'LongSafePassword123!');
      expect(find.text('Live invited-business cashier'), findsOneWidget);
    },
  );

  testWidgets(
    'existing owner can view or defer invitation and continue original business',
    (tester) async {
      final auth = FakeAuthRepository()
        ..identity = _identity
        ..memberships = [_member('original-business', role: AppRole.owner)];
      final inbox = _FakeInbox(auth);
      await _mount(tester, auth, inbox);
      expect(find.text('Live original-business owner'), findsOneWidget);
      expect(find.text('1 pending business invitation'), findsOneWidget);
      await _tap(tester, 'View invitations');
      expect(find.text('Review invitation'), findsOneWidget);
      await _tap(tester, 'Continue to original-business');
      expect(find.text('Live original-business owner'), findsOneWidget);
      expect(find.text('View invitations'), findsNothing);
      expect(inbox.acceptCalls, 0);
    },
  );

  testWidgets(
    'accepting second business requires explicit choice among real memberships',
    (tester) async {
      final auth = FakeAuthRepository()
        ..identity = _identity
        ..memberships = [_member('original-business', role: AppRole.owner)];
      final inbox = _FakeInbox(auth);
      await _mount(tester, auth, inbox);
      await _tap(tester, 'View invitations');
      await _tap(tester, 'Review invitation');
      await _tap(tester, 'Accept invitation');
      expect(find.text('Choose your business'), findsOneWidget);
      expect(find.textContaining('Live '), findsNothing);
      await _tap(tester, 'invited-business');
      expect(find.text('Live invited-business cashier'), findsOneWidget);
    },
  );

  testWidgets(
    'lost acceptance response reloads committed membership without blind retry',
    (tester) async {
      final auth = FakeAuthRepository()..identity = _identity;
      final inbox = _FakeInbox(auth)..loseAcceptedResponse = true;
      await _mount(tester, auth, inbox);
      await _tap(tester, 'Review invitation');
      await _tap(tester, 'Accept invitation');
      expect(inbox.acceptCalls, 1);
      expect(find.text('Accept invitation'), findsNothing);
      expect(find.text('Continue to invited-business'), findsOneWidget);
      expect(find.textContaining('Live '), findsNothing);
      await _tap(tester, 'Continue to invited-business');
      expect(find.text('Live invited-business cashier'), findsOneWidget);
    },
  );

  testWidgets('inbox failure does not lock an existing owner out of business', (
    tester,
  ) async {
    final auth = FakeAuthRepository()
      ..identity = _identity
      ..memberships = [_member('original-business', role: AppRole.owner)];
    final inbox = _FakeInbox(auth)
      ..listError = const InvitationFailure(
        'Invitations temporarily unavailable.',
      );
    await _mount(tester, auth, inbox);
    expect(find.text('Live original-business owner'), findsOneWidget);
    await _tap(tester, 'View invitations');
    expect(find.text('Invitations temporarily unavailable.'), findsOneWidget);
    await _tap(tester, 'Continue to original-business');
    expect(find.text('Live original-business owner'), findsOneWidget);
  });
}
