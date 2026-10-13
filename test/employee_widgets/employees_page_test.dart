import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nexapos/core/security/app_role.dart';
import 'package:nexapos/features/administration/domain/administration_models.dart';
import 'package:nexapos/features/administration/domain/administration_repository.dart';
import 'package:nexapos/features/catalog/domain/repository_support.dart';
import 'package:nexapos/features/employees/presentation/employees_page.dart';

const _branch = BranchOption(
  id: '00000000-0000-0000-0000-000000000003',
  name: 'Downtown',
  code: 'DT',
);
Employee _employee(
  String name,
  String id,
  AppRole role, {
  EmployeeStatus status = EmployeeStatus.active,
}) => Employee(
  membershipId: id,
  userId: 'user-$id',
  fullName: name,
  role: role,
  status: status,
  allBranches: role == AppRole.owner,
  branchIds: role == AppRole.owner ? [] : [_branch.id],
  revision: 9,
  employeeId: 'EMP-$id',
);
InvitationDelivery _delivery(InvitationDeliveryState state) =>
    InvitationDelivery(
      invitationId: '00000000-0000-0000-0000-000000000009',
      expiresAt: DateTime.utc(2026, 10, 16),
      state: state,
    );

void main() {
  Future<void> show(
    WidgetTester tester,
    _EmployeeFake repo, {
    AppRole role = AppRole.owner,
    bool preview = false,
    Size size = const Size(1280, 1000),
  }) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: EmployeesPage(
            repository: repo,
            role: role,
            currentMembershipId: 'self',
            isPreview: preview,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  Future<void> fillInvitation(WidgetTester tester) async {
    await tester.tap(find.byKey(const Key('employee-add')));
    await tester.pumpAndSettle();
    await tester.enterText(_field('Full name'), 'New employee');
    await tester.enterText(_field('Email'), 'staff@example.test');
    await tester.ensureVisible(
      find.widgetWithText(CheckboxListTile, 'Downtown'),
    );
    await tester.tap(find.widgetWithText(CheckboxListTile, 'Downtown'));
    await tester.enterText(
      _field('Reason for invitation'),
      'New cashier position',
    );
  }

  testWidgets('preview cannot load employees or send invitations', (
    tester,
  ) async {
    final repo = _EmployeeFake();
    await show(tester, repo, preview: true);
    expect(repo.reads, 0);
    expect(find.text('No connected employees'), findsOneWidget);
    expect(
      tester
          .widget<FilledButton>(find.byKey(const Key('employee-add')))
          .onPressed,
      isNull,
    );
    expect(find.text('Coming Soon'), findsOneWidget);
  });
  testWidgets('manager cannot view roster or invite staff', (tester) async {
    final repo = _EmployeeFake();
    await show(tester, repo, role: AppRole.manager);
    expect(repo.reads, 0);
    expect(find.text('Employee administration is restricted'), findsOneWidget);
    expect(
      tester
          .widget<FilledButton>(find.byKey(const Key('employee-add')))
          .onPressed,
      isNull,
    );
  });
  testWidgets('Admin cannot manage Owner, Admin or own membership', (
    tester,
  ) async {
    final repo = _EmployeeFake()
      ..employees = [
        _employee('Owner account', 'owner', AppRole.owner),
        _employee('Admin account', 'admin', AppRole.admin),
        _employee('Self account', 'self', AppRole.cashier),
        _employee('Cashier account', 'staff', AppRole.cashier),
      ];
    await show(tester, repo, role: AppRole.admin);
    final buttons = tester
        .widgetList<TextButton>(
          find.widgetWithText(TextButton, 'Manage access'),
        )
        .toList();
    expect(buttons.map((button) => button.onPressed != null), [
      false,
      false,
      false,
      true,
    ]);
  });
  testWidgets('Admin invitation only offers permitted employee roles', (
    tester,
  ) async {
    await show(tester, _EmployeeFake(), role: AppRole.admin);
    await tester.tap(find.byKey(const Key('employee-add')));
    await tester.pumpAndSettle();
    final dropdown = tester.widget<DropdownButtonFormField<AppRole>>(
      find.byWidgetPredicate(
        (widget) => widget is DropdownButtonFormField<AppRole>,
      ),
    );
    // The opened menu exposes exactly the same role choices as the field.
    await tester.ensureVisible(find.text('Cashier').last);
    await tester.tap(find.text('Cashier').last);
    await tester.pumpAndSettle();
    expect(dropdown.enabled, isTrue);
    expect(find.text('Owner'), findsNothing);
    expect(find.text('Admin'), findsNothing);
    expect(find.text('Manager'), findsWidgets);
    expect(find.text('Inventory Staff'), findsWidgets);
  });
  testWidgets('invitation requires name, valid email and real branches', (
    tester,
  ) async {
    final repo = _EmployeeFake();
    await show(tester, repo);
    await tester.tap(find.byKey(const Key('employee-add')));
    await tester.pumpAndSettle();
    await tester.enterText(_field('Email'), 'bad-email');
    await tester.tap(find.text('Submit invitation'));
    await tester.pumpAndSettle();
    expect(repo.invitations, isEmpty);
    expect(find.text('Full name is required.'), findsOneWidget);
    expect(find.text('Enter a valid email address.'), findsOneWidget);
  });
  testWidgets('200 invitation states submission, not delivery', (tester) async {
    final repo = _EmployeeFake();
    await show(tester, repo);
    await fillInvitation(tester);
    await tester.tap(find.text('Submit invitation'));
    await tester.pumpAndSettle();
    expect(find.text('Invitation submitted'), findsOneWidget);
    expect(
      find.text(
        'Invitation submitted to Supabase Auth. Email delivery has not been confirmed.',
      ),
      findsOneWidget,
    );
    expect(find.text('New employee'), findsNothing);
    expect(repo.invitations.single.reason, 'New cashier position');
    expect(repo.invitations.single.branchIds, [_branch.id]);
  });
  testWidgets('202 invitation shows pending manual review', (tester) async {
    final repo = _EmployeeFake()
      ..delivery = _delivery(InvitationDeliveryState.sending);
    await show(tester, repo);
    await fillInvitation(tester);
    await tester.tap(find.text('Submit invitation'));
    await tester.pumpAndSettle();
    expect(find.text('Invitation pending'), findsOneWidget);
    expect(find.textContaining('manual review'), findsOneWidget);
    expect(find.text('Invitation submitted'), findsNothing);
  });
  testWidgets(
    'pending transport displays no fake success and retains request ID',
    (tester) async {
      final repo = _EmployeeFake()
        ..invitationFailure = StateError('private backend detail');
      await show(tester, repo);
      await fillInvitation(tester);
      await tester.tap(find.text('Submit invitation'));
      await tester.pumpAndSettle();
      expect(
        find.textContaining('status could not be confirmed'),
        findsOneWidget,
      );
      expect(find.textContaining('private backend detail'), findsNothing);
      expect(find.text('Invitation submitted'), findsNothing);
      expect(
        tester.widget<TextFormField>(_field('Full name')).enabled,
        isFalse,
      );
      final firstId = repo.invitations.single.requestId;
      repo.invitationFailure = null;
      await tester.tap(find.text('Retry same request'));
      await tester.pumpAndSettle();
      expect(repo.invitations.length, 2);
      expect(repo.invitations.last.requestId, firstId);
      expect(find.text('Invitation submitted'), findsOneWidget);
    },
  );
  testWidgets('unresolved invitation cannot report a result or close', (
    tester,
  ) async {
    final repo = _EmployeeFake()
      ..invitationResult = Completer<InvitationDelivery>();
    await show(tester, repo);
    await fillInvitation(tester);
    await tester.tap(find.text('Submit invitation'));
    await tester.pump();
    expect(find.text('Submitting…'), findsOneWidget);
    expect(find.text('Invitation submitted'), findsNothing);
    expect(
      tester
          .widget<TextButton>(find.widgetWithText(TextButton, 'Cancel'))
          .onPressed,
      isNull,
    );
    repo.invitationResult!.complete(_delivery(InvitationDeliveryState.sent));
    await tester.pumpAndSettle();
    expect(find.text('Invitation submitted'), findsOneWidget);
  });
  testWidgets('employee CAS conflict keeps access form open', (tester) async {
    final repo = _EmployeeFake()
      ..employees = [_employee('Cashier account', 'staff', AppRole.cashier)]
      ..updateFailure = const RepositoryFailure(
        RepositoryFailureType.conflict,
        'Conflict',
      );
    await show(tester, repo);
    await tester.tap(find.text('Manage access'));
    await tester.pumpAndSettle();
    await tester.enterText(
      _field('Reason for access change'),
      'Deactivate departed employee',
    );
    await tester.tap(find.text('Save access'));
    await tester.pumpAndSettle();
    expect(repo.expectedRevision, 9);
    expect(find.textContaining('This employee changed'), findsOneWidget);
    expect(find.text('Employee access updated.'), findsNothing);
  });
  testWidgets('employee cards fit 320 pixel phones', (tester) async {
    final repo = _EmployeeFake()
      ..employees = [_employee('Cashier account', 'staff', AppRole.cashier)];
    await show(tester, repo, size: const Size(320, 900));
    expect(find.byType(DataTable), findsNothing);
    expect(find.text('Cashier account'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
  testWidgets(
    'disconnected invitation reports explicit status without success',
    (tester) async {
      final repo = _EmployeeFake()
        ..invitationFailure = const RepositoryFailure(
          RepositoryFailureType.notConnected,
          'Invitations are Not Yet Connected.',
        );
      await show(tester, repo);
      await fillInvitation(tester);
      await tester.tap(find.text('Submit invitation'));
      await tester.pumpAndSettle();
      expect(find.text('Invitations are Not Yet Connected.'), findsOneWidget);
      expect(find.text('Invitation submitted'), findsNothing);
    },
  );
  testWidgets('invitation form fits a 320 pixel phone', (tester) async {
    final repo = _EmployeeFake();
    await show(tester, repo, size: const Size(320, 900));
    await fillInvitation(tester);
    expect(tester.takeException(), isNull);
    await tester.tap(find.text('Submit invitation'));
    await tester.pumpAndSettle();
    expect(find.text('Invitation submitted'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}

Finder _field(String label) => find.widgetWithText(TextFormField, label);

class _EmployeeFake implements EmployeeRepository {
  int reads = 0;
  int? expectedRevision;
  List<Employee> employees = [];
  List<EmployeeInvitationInput> invitations = [];
  InvitationDelivery delivery = _delivery(InvitationDeliveryState.sent);
  Object? invitationFailure;
  RepositoryFailure? updateFailure;
  Completer<InvitationDelivery>? invitationResult;
  @override
  Future<List<BranchOption>> listBranches() async => [_branch];
  @override
  Future<DataPage<Employee>> listEmployees({
    EmployeeStatus? status,
    PageRequest page = const PageRequest(),
  }) async {
    reads++;
    return DataPage(items: employees, hasMore: false, offset: page.offset);
  }

  @override
  Future<Employee> updateEmployee({
    required String membershipId,
    required int expectedRevision,
    required EmployeeAccessInput input,
  }) async {
    this.expectedRevision = expectedRevision;
    if (updateFailure != null) throw updateFailure!;
    return employees.single;
  }

  @override
  Future<InvitationDelivery> createInvitation(
    EmployeeInvitationInput input,
  ) async {
    invitations.add(input);
    if (invitationFailure != null) throw invitationFailure!;
    return invitationResult == null ? delivery : await invitationResult!.future;
  }
}
