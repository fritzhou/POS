import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nexapos/core/operations/operation_journal.dart';
import 'package:nexapos/core/security/app_role.dart';
import 'package:nexapos/features/administration/domain/administration_models.dart';
import 'package:nexapos/features/catalog/domain/repository_support.dart';
import 'package:nexapos/features/expenses/data/expense_decoders.dart';
import 'package:nexapos/features/expenses/domain/expense_models.dart';
import 'package:nexapos/features/expenses/domain/expense_repository.dart';
import 'package:nexapos/features/expenses/presentation/expense_dialog_session.dart';
import 'package:nexapos/features/expenses/presentation/expense_record_dialog.dart';
import 'package:nexapos/features/expenses/presentation/expense_reverse_dialog.dart';
import 'package:nexapos/features/expenses/presentation/expenses_page.dart';
import 'package:nexapos/features/people/domain/people_repository.dart';

import 'expense_fixtures.dart';

class _People implements PeopleRepository {
  @override
  Future<List<BranchOption>> listBranches() async => const [
    BranchOption(id: expenseBranch, name: 'Expense fixture branch', code: 'EF'),
  ];
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Expenses implements ExpenseRepository {
  @override
  String get organizationId => expenseOrg;
  @override
  String get actorUserId => expenseActor;
  ExpenseContext context = expenseContextFromRow(expenseContextWire());
  List<Expense> items = [];
  List<PendingOperation> pending = [], blockers = [];
  RepositoryFailure? listError;
  Completer<DataPage<Expense>>? delayedList;
  Completer<Expense>? delayedRecord;
  RecordExpenseRequest? lastRecord;
  ReverseExpenseRequest? lastReverse;
  bool loseRecord = false;
  RepositoryFailure? recordError;
  RepositoryFailure? reverseError;
  int retryCount = 0;
  @override
  Future<ExpenseContext> loadContext(String branchId) async => context;
  @override
  Future<DataPage<Expense>> listExpenses({
    required String branchId,
    ExpenseFilter filter = const ExpenseFilter(),
    PageRequest page = const PageRequest(),
  }) async {
    if (delayedList != null) return delayedList!.future;
    if (listError != null) throw listError!;
    return DataPage(items: items, hasMore: false, offset: page.offset);
  }

  @override
  Future<Expense> getExpense({
    required String branchId,
    required String expenseId,
  }) async => items.single;
  @override
  Future<List<PendingOperation>> pendingOperations({String? branchId}) async =>
      pending;
  @override
  Future<List<PendingOperation>> drawerBlockers(String branchId) async =>
      blockers;
  @override
  Future<Expense> recordExpense(RecordExpenseRequest request) async {
    lastRecord = request;
    if (recordError != null) throw recordError!;
    if (delayedRecord != null) return delayedRecord!.future;
    if (loseRecord) {
      throw const RepositoryFailure(
        RepositoryFailureType.unavailable,
        'Payment record remains unconfirmed.',
      );
    }
    return expenseFromRow(
      expenseWire(drawer: request.source == ExpenseSource.cashDrawer),
    );
  }

  @override
  Future<ExpenseReversal> reverseExpense(ReverseExpenseRequest request) async {
    lastReverse = request;
    if (reverseError != null) throw reverseError!;
    return expenseReversalFromRow(
      expenseReversalWire(
        drawer: request.original.source == ExpenseSource.cashDrawer,
      ),
    );
  }

  @override
  Future<Object> retryPending(PendingOperation operation) async {
    retryCount++;
    pending = [];
    return expenseFromRow(expenseWire());
  }
}

PendingOperation _pending({String type = 'record_expense'}) => PendingOperation(
  requestId: expenseRequestId,
  organizationId: expenseOrg,
  branchId: expenseBranch,
  actorId: expenseActor,
  type: type,
  payload: expenseRequest().parameters(expenseOrg),
  createdAt: DateTime.utc(2026, 10, 11),
  status: LocalOperationStatus.pending,
  attemptCount: 1,
);
Future<void> _size(WidgetTester tester, double width) async {
  tester.view.physicalSize = Size(width, 900);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
}

Widget _page(_Expenses repository, _People people) => MaterialApp(
  home: Scaffold(
    body: ExpensesPage(
      repository: repository,
      peopleRepository: people,
      role: AppRole.owner,
      isPreview: false,
    ),
  ),
);
Future<void> _visibleTap(WidgetTester tester, Finder finder) async {
  await tester.ensureVisible(finder);
  await tester.tap(finder);
  await tester.pumpAndSettle();
}

Future<void> _dialog(WidgetTester tester, Widget dialog) async {
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: Builder(
          builder: (context) => TextButton(
            onPressed: () => showDialog<void>(
              context: context,
              barrierDismissible: false,
              builder: (_) => dialog,
            ),
            child: const Text('Open'),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('Open'));
  await tester.pumpAndSettle();
}

Future<void> _fillRecord(
  WidgetTester tester, {
  bool confirmation = true,
}) async {
  await tester.enterText(find.byKey(const Key('expense-amount')), '123.45');
  await tester.enterText(
    find.byKey(const Key('expense-payee')),
    'Private payee',
  );
  await tester.enterText(
    find.byKey(const Key('expense-reason')),
    'Verified receipt\nManual payment',
  );
  if (confirmation) {
    await _visibleTap(
      tester,
      find.byKey(const Key('expense-manual-confirmation')),
    );
  }
}

void main() {
  for (final width in [320.0, 1200.0]) {
    testWidgets(
      'preview and authorized empty have truthful adaptive states at $width',
      (tester) async {
        await _size(tester, width);
        await tester.pumpWidget(
          const MaterialApp(home: Scaffold(body: ExpensesPage())),
        );
        await tester.pumpAndSettle();
        expect(find.text('No connected expense history'), findsOneWidget);
        expect(
          tester
              .widget<FilledButton>(find.byKey(const Key('expense-record')))
              .onPressed,
          isNull,
        );
        final repository = _Expenses();
        await tester.pumpWidget(_page(repository, _People()));
        await tester.pumpAndSettle();
        expect(find.text('No recorded expenses'), findsOneWidget);
        expect(tester.takeException(), isNull);
      },
    );
    testWidgets('data history error reload and recovery adapt at $width', (
      tester,
    ) async {
      await _size(tester, width);
      final repository = _Expenses()..items = [expenseFromRow(expenseWire())];
      final people = _People();
      await tester.pumpWidget(_page(repository, people));
      await tester.pumpAndSettle();
      expect(find.text('PHP 123.45'), findsOneWidget);
      expect(find.text('External funds'), findsOneWidget);
      expect(tester.takeException(), isNull);
      repository.listError = const RepositoryFailure(
        RepositoryFailureType.unavailable,
        'Expense service temporarily unavailable.',
      );
      await _visibleTap(tester, find.byKey(const Key('expenses-reload')));
      expect(
        find.text('Expense service temporarily unavailable.'),
        findsOneWidget,
      );
      expect(find.text('PHP 123.45'), findsNothing);
      expect(tester.takeException(), isNull);
      repository.listError = null;
      repository.pending = [_pending()];
      await _visibleTap(tester, find.byKey(const Key('expenses-reload')));
      expect(
        tester
            .widget<FilledButton>(find.byKey(const Key('expense-record')))
            .onPressed,
        isNull,
      );
      await _visibleTap(
        tester,
        find.byKey(const Key('pending-retry-$expenseRequestId')),
      );
      expect(repository.retryCount, 1);
      expect(find.text('PHP 123.45'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
    testWidgets(
      'record form needs explicit manual confirmation and retains unknown intent at $width',
      (tester) async {
        await _size(tester, width);
        final repository = _Expenses()..loseRecord = true;
        final session = ExpenseDialogSession();
        RecordExpenseRequest? frozen;
        var resolved = false;
        await _dialog(
          tester,
          ExpenseRecordDialog(
            repository: repository,
            expenseContext: repository.context,
            session: session,
            onFrozen: (r) => frozen = r,
            onResolved: () => resolved = true,
          ),
        );
        await _fillRecord(tester, confirmation: false);
        await _visibleTap(tester, find.byKey(const Key('expense-save')));
        expect(repository.lastRecord, isNull);
        expect(find.textContaining('Confirm the paid amount'), findsOneWidget);
        await _visibleTap(
          tester,
          find.byKey(const Key('expense-manual-confirmation')),
        );
        await _visibleTap(tester, find.byKey(const Key('expense-save')));
        expect(frozen, isNotNull);
        expect(resolved, isFalse);
        expect(frozen!.source, ExpenseSource.external);
        expect(frozen!.shiftId, isNull);
        expect(
          find.textContaining('without repeating the physical payment'),
          findsOneWidget,
        );
        expect(
          tester
              .widget<TextField>(find.byKey(const Key('expense-amount')))
              .enabled,
          isFalse,
        );
        expect(tester.takeException(), isNull);
        final requestId = frozen!.requestId;
        repository.loseRecord = false;
        await _visibleTap(tester, find.byKey(const Key('expense-save')));
        expect(repository.lastRecord?.requestId, requestId);
        expect(resolved, isTrue);
        expect(find.byType(ExpenseRecordDialog), findsNothing);
      },
    );
    testWidgets('full drawer return form needs actual confirmation at $width', (
      tester,
    ) async {
      await _size(tester, width);
      final repository = _Expenses();
      await _dialog(
        tester,
        ExpenseReverseDialog(
          repository: repository,
          original: expenseFromRow(expenseWire(drawer: true)),
          session: ExpenseDialogSession(),
          onFrozen: (_) {},
          onResolved: () {},
        ),
      );
      await tester.enterText(
        find.byKey(const Key('expense-reversal-reason')),
        'Cash physically returned',
      );
      await _visibleTap(tester, find.byKey(const Key('expense-reversal-save')));
      expect(repository.lastReverse, isNull);
      expect(
        find.text(
          'I confirm the full cash amount returned to this original drawer.',
        ),
        findsOneWidget,
      );
      await _visibleTap(
        tester,
        find.byKey(const Key('expense-reversal-confirmation')),
      );
      await _visibleTap(tester, find.byKey(const Key('expense-reversal-save')));
      expect(repository.lastReverse?.manualConfirmed, isTrue);
      expect(repository.lastReverse?.original.shiftId, expenseShift);
      expect(tester.takeException(), isNull);
    });
  }
  testWidgets('same branch pending checkout disables drawer source option', (
    tester,
  ) async {
    final repository = _Expenses();
    await _dialog(
      tester,
      ExpenseRecordDialog(
        repository: repository,
        expenseContext: repository.context,
        session: ExpenseDialogSession(),
        drawerBlocked: true,
        onFrozen: (_) {},
        onResolved: () {},
      ),
    );
    final dropdown = tester.widget<DropdownButtonFormField<ExpenseSource>>(
      find.byWidgetPredicate(
        (w) => w is DropdownButtonFormField<ExpenseSource>,
      ),
    );
    expect(dropdown.onChanged, isNotNull);
    await tester.tap(find.text('External funds').first);
    await tester.pumpAndSettle();
    final drawerItem = tester.widget<DropdownMenuItem<ExpenseSource>>(
      find
          .byWidgetPredicate(
            (w) =>
                w is DropdownMenuItem<ExpenseSource> &&
                w.value == ExpenseSource.cashDrawer,
          )
          .last,
    );
    expect(drawerItem.enabled, isFalse);
    expect(find.textContaining('Confirm the pending checkout'), findsOneWidget);
  });
  testWidgets('closed or another actor drawer cannot offer new full return', (
    tester,
  ) async {
    final repository = _Expenses()
      ..items = [expenseFromRow(expenseWire(drawer: true))]
      ..context = expenseContextFromRow(expenseContextWire(drawer: false));
    await tester.pumpWidget(_page(repository, _People()));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('View'));
    await tester.tap(find.text('View'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(
      find.textContaining('original own drawer shift is closed'),
      findsOneWidget,
    );
    expect(
      tester
          .widget<OutlinedButton>(
            find.byKey(const Key('expense-details-reverse')),
          )
          .onPressed,
      isNull,
    );
    await tester.tap(find.text('Close'));
    await tester.pumpAndSettle();
  });
  testWidgets(
    'actor or business repository change invalidates same branch dialog and private form',
    (tester) async {
      final repository = _Expenses();
      final replacement = _Expenses();
      final people = _People();
      final selected = ValueNotifier<_Expenses>(repository);
      addTearDown(selected.dispose);
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ValueListenableBuilder<_Expenses>(
              valueListenable: selected,
              builder: (_, value, child) => ExpensesPage(
                repository: value,
                peopleRepository: people,
                role: AppRole.owner,
                isPreview: false,
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await _visibleTap(tester, find.byKey(const Key('expense-record')));
      await _fillRecord(tester);
      selected.value = replacement;
      await tester.pumpAndSettle();
      expect(find.text('Business context changed'), findsOneWidget);
      expect(find.text('Private payee'), findsNothing);
      expect(find.text('Verified receipt\nManual payment'), findsNothing);
      expect(find.byKey(const Key('expense-save')), findsNothing);
      expect(tester.takeException(), isNull);
      await tester.tap(find.text('Close'));
      await tester.pumpAndSettle();
      expect(find.byType(ExpenseRecordDialog), findsNothing);
    },
  );
  testWidgets(
    'old expense list response never renders after same branch account change',
    (tester) async {
      final repository = _Expenses()
        ..delayedList = Completer<DataPage<Expense>>();
      final replacement = _Expenses();
      final people = _People();
      final selected = ValueNotifier<_Expenses>(repository);
      addTearDown(selected.dispose);
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ValueListenableBuilder<_Expenses>(
              valueListenable: selected,
              builder: (_, value, child) => ExpensesPage(
                repository: value,
                peopleRepository: people,
                role: AppRole.owner,
                isPreview: false,
              ),
            ),
          ),
        ),
      );
      await tester.pump();
      await tester.pump();
      selected.value = replacement;
      await tester.pumpAndSettle();
      repository.delayedList!.complete(
        DataPage(
          items: [expenseFromRow(expenseWire())],
          hasMore: false,
          offset: 0,
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('PHP 123.45'), findsNothing);
      expect(find.text('No recorded expenses'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'own open drawer payout requires its source and physical confirmation',
    (tester) async {
      final repository = _Expenses();
      await _dialog(
        tester,
        ExpenseRecordDialog(
          repository: repository,
          expenseContext: repository.context,
          session: ExpenseDialogSession(),
          onFrozen: (_) {},
          onResolved: () {},
        ),
      );
      await tester.tap(find.text('External funds').first);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Own shift cash drawer').last);
      await tester.pumpAndSettle();
      expect(
        find.text('I confirm this cash was paid from my own open drawer.'),
        findsOneWidget,
      );
      await _fillRecord(tester);
      await _visibleTap(tester, find.byKey(const Key('expense-save')));
      expect(repository.lastRecord?.source, ExpenseSource.cashDrawer);
      expect(repository.lastRecord?.shiftId, expenseShift);
      expect(repository.lastRecord?.manualConfirmed, isTrue);
    },
  );
  testWidgets(
    'same branch repository change invalidates details and nested reversal',
    (tester) async {
      final repository = _Expenses()..items = [expenseFromRow(expenseWire())];
      final replacement = _Expenses();
      final people = _People();
      final selected = ValueNotifier<_Expenses>(repository);
      addTearDown(selected.dispose);
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ValueListenableBuilder<_Expenses>(
              valueListenable: selected,
              builder: (_, value, child) => ExpensesPage(
                repository: value,
                peopleRepository: people,
                role: AppRole.owner,
                isPreview: false,
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('View'));
      await tester.tap(find.text('View'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.text('Payee: Actual supplier'), findsOneWidget);
      await tester.ensureVisible(
        find.byKey(const Key('expense-details-reverse')),
      );
      await tester.tap(find.byKey(const Key('expense-details-reverse')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      await tester.enterText(
        find.byKey(const Key('expense-reversal-reason')),
        'Private correction evidence',
      );
      selected.value = replacement;
      await tester.pumpAndSettle();
      expect(find.text('Business context changed'), findsNWidgets(2));
      expect(find.text('Private correction evidence'), findsNothing);
      expect(find.byKey(const Key('expense-reversal-save')), findsNothing);
      expect(tester.takeException(), isNull);
      await tester.tap(find.text('Close').last);
      await tester.pumpAndSettle();
      expect(find.text('Payee: Actual supplier'), findsNothing);
      expect(find.text('Business context changed'), findsOneWidget);
      await tester.tap(find.text('Close'));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'later local denial cannot release a previously unknown payment form',
    (tester) async {
      final repository = _Expenses()..loseRecord = true;
      final session = ExpenseDialogSession();
      var resolved = false;
      await _dialog(
        tester,
        ExpenseRecordDialog(
          repository: repository,
          expenseContext: repository.context,
          session: session,
          onFrozen: (_) {},
          onResolved: () => resolved = true,
        ),
      );
      await _fillRecord(tester);
      await _visibleTap(tester, find.byKey(const Key('expense-save')));
      final originalId = repository.lastRecord!.requestId;
      repository.recordError = const RepositoryFailure(
        RepositoryFailureType.permissionDenied,
        'Current access denied.',
      );
      await _visibleTap(tester, find.byKey(const Key('expense-save')));
      expect(repository.lastRecord!.requestId, originalId);
      expect(resolved, isFalse);
      expect(
        tester
            .widget<TextField>(find.byKey(const Key('expense-amount')))
            .enabled,
        isFalse,
      );
      expect(find.text('Retry saved expense'), findsOneWidget);
    },
  );
  testWidgets(
    'later local denial cannot release an unknown full compensation form',
    (tester) async {
      final repository = _Expenses()
        ..reverseError = const RepositoryFailure(
          RepositoryFailureType.unavailable,
          'Original correction unconfirmed.',
        );
      var resolved = false;
      await _dialog(
        tester,
        ExpenseReverseDialog(
          repository: repository,
          original: expenseFromRow(expenseWire()),
          session: ExpenseDialogSession(),
          onFrozen: (_) {},
          onResolved: () => resolved = true,
        ),
      );
      await tester.enterText(
        find.byKey(const Key('expense-reversal-reason')),
        'Verified correction',
      );
      await _visibleTap(
        tester,
        find.byKey(const Key('expense-reversal-confirmation')),
      );
      await _visibleTap(tester, find.byKey(const Key('expense-reversal-save')));
      final originalId = repository.lastReverse!.requestId;
      repository.reverseError = const RepositoryFailure(
        RepositoryFailureType.permissionDenied,
        'Current access denied.',
      );
      await _visibleTap(tester, find.byKey(const Key('expense-reversal-save')));
      expect(repository.lastReverse!.requestId, originalId);
      expect(resolved, isFalse);
      expect(
        tester
            .widget<TextField>(find.byKey(const Key('expense-reversal-reason')))
            .enabled,
        isFalse,
      );
      expect(find.text('Retry saved reversal'), findsOneWidget);
    },
  );
  testWidgets(
    'late accepted mutation stays private after session invalidation',
    (tester) async {
      final repository = _Expenses()..delayedRecord = Completer<Expense>();
      final session = ExpenseDialogSession();
      var resolved = false;
      await _dialog(
        tester,
        ExpenseRecordDialog(
          repository: repository,
          expenseContext: repository.context,
          session: session,
          onFrozen: (_) {},
          onResolved: () => resolved = true,
        ),
      );
      await _fillRecord(tester);
      await tester.ensureVisible(find.byKey(const Key('expense-save')));
      await tester.tap(find.byKey(const Key('expense-save')));
      await tester.pump();
      session.invalidate();
      await tester.pump();
      repository.delayedRecord!.complete(expenseFromRow(expenseWire()));
      await tester.pumpAndSettle();
      expect(resolved, isFalse);
      expect(find.text('Business context changed'), findsOneWidget);
      expect(find.text('Private payee'), findsNothing);
    },
  );
}
