import 'package:flutter/material.dart';

import '../../../app/config/feature_status.dart';
import '../../../core/operations/operation_journal.dart';
import '../../../core/security/app_role.dart';
import '../../../core/widgets/status_widgets.dart';
import '../../administration/domain/administration_models.dart';
import '../../catalog/domain/repository_support.dart';
import '../../inventory/presentation/operations_ui_support.dart';
import '../../people/domain/people_repository.dart';
import '../domain/expense_models.dart';
import '../domain/expense_repository.dart';
import 'expense_details.dart';
import 'expense_dialog_session.dart';
import 'expense_record_dialog.dart';
import 'expense_reverse_dialog.dart';

class ExpensesPage extends StatefulWidget {
  const ExpensesPage({
    super.key,
    this.repository,
    this.peopleRepository,
    this.role,
    this.isPreview = true,
  });
  final ExpenseRepository? repository;
  final PeopleRepository? peopleRepository;
  final AppRole? role;
  final bool isPreview;
  @override
  State<ExpensesPage> createState() => _ExpensesPageState();
}

class _ExpensesPageState extends State<ExpensesPage> {
  List<BranchOption> _branches = [];
  String? _branchId, _error;
  ExpenseContext? _context;
  DataPage<Expense>? _page;
  List<PendingOperation> _pending = [], _drawerBlockers = [];
  RecordExpenseRequest? _pendingRecord;
  ExpenseContext? _pendingRecordContext;
  ReverseExpenseRequest? _pendingReverse;
  ExpenseCategory? _category;
  DateTimeRange? _dates;
  bool _busy = false, _dialogOpen = false;
  int _generation = 0;
  ExpenseDialogSession? _dialogSession;
  bool get _connected =>
      !widget.isPreview &&
      widget.repository != null &&
      widget.peopleRepository != null &&
      [AppRole.owner, AppRole.admin, AppRole.manager].contains(widget.role);
  bool get _hasPending =>
      _pending.isNotEmpty || _pendingRecord != null || _pendingReverse != null;
  int get _offset => _page?.offset ?? 0;
  @override
  void initState() {
    super.initState();
    if (_connected) _load(0);
  }

  @override
  void didUpdateWidget(covariant ExpensesPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.repository != widget.repository ||
        oldWidget.peopleRepository != widget.peopleRepository ||
        oldWidget.role != widget.role ||
        oldWidget.isPreview != widget.isPreview) {
      _generation++;
      _dialogSession?.invalidate();
      _branches = [];
      _branchId = null;
      _context = null;
      _page = null;
      _error = null;
      _pending = [];
      _drawerBlockers = [];
      _pendingRecord = null;
      _pendingRecordContext = null;
      _pendingReverse = null;
      _category = null;
      _dates = null;
      _busy = false;
      if (_connected) _load(0);
    }
  }

  @override
  void dispose() {
    _generation++;
    _dialogSession?.invalidate();
    super.dispose();
  }

  ExpenseFilter get _filter => ExpenseFilter(
    from: _dates == null
        ? null
        : DateTime.utc(
            _dates!.start.year,
            _dates!.start.month,
            _dates!.start.day,
          ),
    to: _dates == null
        ? null
        : DateTime.utc(
            _dates!.end.year,
            _dates!.end.month,
            _dates!.end.day,
          ).add(const Duration(days: 1)),
    category: _category,
  );
  Future<void> _load(int offset) async {
    if (!_connected || _busy) return;
    final epoch = ++_generation;
    final repository = widget.repository!;
    final people = widget.peopleRepository!;
    setState(() {
      _busy = true;
      _error = null;
      _page = null;
      _context = null;
    });
    try {
      final pending = await repository.pendingOperations();
      if (!mounted || epoch != _generation) return;
      setState(() => _pending = pending);
      final branches = await people.listBranches();
      final branch = branches.any((e) => e.id == _branchId)
          ? _branchId
          : branches.firstOrNull?.id;
      final context = branch == null
          ? null
          : await repository.loadContext(branch);
      final blockers = branch == null
          ? <PendingOperation>[]
          : await repository.drawerBlockers(branch);
      final page = branch == null
          ? null
          : await repository.listExpenses(
              branchId: branch,
              filter: _filter,
              page: PageRequest(offset: offset, limit: 20),
            );
      if (!mounted || epoch != _generation) return;
      setState(() {
        _branches = branches;
        _branchId = branch;
        _context = context;
        _drawerBlockers = blockers;
        _page = page;
      });
    } catch (error) {
      if (mounted && epoch == _generation) {
        setState(() => _error = operationError(error));
      }
    } finally {
      if (mounted && epoch == _generation) setState(() => _busy = false);
    }
  }

  Future<void> _record() async {
    if (!_connected ||
        _dialogOpen ||
        _busy ||
        _context == null ||
        _hasPending && _pendingRecord == null) {
      return;
    }
    final epoch = _generation;
    final repository = widget.repository!;
    final context = _pendingRecordContext ?? _context!;
    final session = ExpenseDialogSession();
    _dialogSession = session;
    _dialogOpen = true;
    try {
      final result = await showDialog<Expense>(
        context: this.context,
        barrierDismissible: false,
        builder: (dialogContext) => ExpenseRecordDialog(
          repository: repository,
          expenseContext: context,
          session: session,
          drawerBlocked: _drawerBlockers.isNotEmpty,
          pending: _pendingRecord,
          onFrozen: (request) {
            if (mounted && epoch == _generation) {
              _pendingRecord = request;
              _pendingRecordContext = context;
            }
          },
          onResolved: () {
            if (mounted && epoch == _generation) {
              _pendingRecord = null;
              _pendingRecordContext = null;
            }
          },
        ),
      );
      if (!mounted || epoch != _generation) return;
      if (result != null) {
        ScaffoldMessenger.of(this.context).showSnackBar(
          const SnackBar(content: Text('Expense recorded by the server.')),
        );
      }
    } finally {
      if (identical(_dialogSession, session)) _dialogSession = null;
      _dialogOpen = false;
    }
    if (mounted && epoch == _generation) await _load(_offset);
  }

  Future<void> _reverse(Expense original, ExpenseDialogSession session) async {
    final epoch = _generation;
    final repository = widget.repository!;
    final result = await showDialog<ExpenseReversal>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => ExpenseReverseDialog(
        repository: repository,
        original: original,
        session: session,
        pending: _pendingReverse,
        onFrozen: (request) {
          if (mounted && epoch == _generation) _pendingReverse = request;
        },
        onResolved: () {
          if (mounted && epoch == _generation) _pendingReverse = null;
        },
      ),
    );
    if (result != null && mounted && epoch == _generation) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Full expense compensation recorded by the server.'),
        ),
      );
    }
  }

  Future<void> _details(Expense displayed) async {
    if (!_connected || _busy || _dialogOpen) return;
    final epoch = _generation;
    final repository = widget.repository!;
    setState(() => _busy = true);
    try {
      final original = await repository.getExpense(
        branchId: displayed.branchId,
        expenseId: displayed.id,
      );
      final current = await repository.loadContext(displayed.branchId);
      if (!mounted || epoch != _generation) return;
      final session = ExpenseDialogSession();
      _dialogSession = session;
      _dialogOpen = true;
      String? blocked;
      if (_hasPending) {
        blocked =
            'Resolve the saved expense request before recording another correction.';
      } else if (original.source == ExpenseSource.cashDrawer &&
          (original.actorUserId != repository.actorUserId ||
              current.ownOpenShift?.id != original.shiftId ||
              current.ownOpenShift?.currency != original.currency)) {
        blocked =
            'This original own drawer shift is closed or unavailable. Ask an authorized manager to review the expense.';
      } else if (original.source == ExpenseSource.cashDrawer &&
          _drawerBlockers.isNotEmpty) {
        blocked =
            'Confirm the saved checkout or shift closure before recording returned drawer cash.';
      }
      await showDialog<void>(
        context: context,
        builder: (dialogContext) => ExpenseDetails(
          expense: original,
          branchName: current.branchName,
          session: session,
          reverseUnavailable: blocked,
          onReverse: blocked != null
              ? null
              : () async {
                  await _reverse(original, session);
                  if (dialogContext.mounted && session.active) {
                    Navigator.of(dialogContext).pop();
                  }
                },
        ),
      );
      if (identical(_dialogSession, session)) _dialogSession = null;
      _dialogOpen = false;
    } catch (error) {
      if (mounted && epoch == _generation) {
        setState(() => _error = operationError(error));
      }
    } finally {
      if (mounted && epoch == _generation) setState(() => _busy = false);
    }
    if (mounted && epoch == _generation) await _load(_offset);
  }

  Future<void> _resumeReverse() async {
    if (_pendingReverse == null || _busy || _dialogOpen) return;
    final epoch = _generation;
    final session = ExpenseDialogSession();
    _dialogSession = session;
    _dialogOpen = true;
    try {
      await _reverse(_pendingReverse!.original, session);
    } finally {
      if (identical(_dialogSession, session)) _dialogSession = null;
      _dialogOpen = false;
    }
    if (mounted && epoch == _generation) await _load(_offset);
  }

  Future<void> _selectDates() async {
    final epoch = _generation;
    final now = DateTime.now().toUtc();
    final range = await showDateRangePicker(
      context: context,
      firstDate: DateTime.utc(2000),
      lastDate: DateTime.utc(now.year + 1, 12, 31),
      initialDateRange: _dates,
      helpText: 'Expense activity dates (UTC)',
    );
    if (!mounted || epoch != _generation || range == null) return;
    final filter = ExpenseFilter(
      from: DateTime.utc(range.start.year, range.start.month, range.start.day),
      to: DateTime.utc(
        range.end.year,
        range.end.month,
        range.end.day,
      ).add(const Duration(days: 1)),
      category: _category,
    );
    try {
      filter.validate();
    } catch (error) {
      setState(() => _error = operationError(error));
      return;
    }
    setState(() => _dates = range);
    await _load(0);
  }

  String _date(DateTime value) => value.toUtc().toIso8601String();
  Widget _list() {
    final items = _page!.items;
    return LayoutBuilder(
      builder: (context, box) {
        if (box.maxWidth >= 760) {
          return SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: DataTable(
              columns: const [
                DataColumn(label: Text('Recorded (UTC)')),
                DataColumn(label: Text('Category / payee')),
                DataColumn(label: Text('Source')),
                DataColumn(label: Text('Original amount')),
                DataColumn(label: Text('Status')),
                DataColumn(label: Text('History')),
              ],
              rows: items
                  .map(
                    (e) => DataRow(
                      cells: [
                        DataCell(Text(_date(e.occurredAt))),
                        DataCell(
                          Text(
                            '${e.category.label}\n${e.payee ?? 'Not recorded'}',
                          ),
                        ),
                        DataCell(Text(e.source.label)),
                        DataCell(Text(amountLabel(e.amountMinor, e.currency))),
                        DataCell(
                          Text(
                            e.reversal == null ? 'Recorded' : 'Fully reversed',
                          ),
                        ),
                        DataCell(
                          TextButton(
                            onPressed: _busy ? null : () => _details(e),
                            child: const Text('View'),
                          ),
                        ),
                      ],
                    ),
                  )
                  .toList(),
            ),
          );
        }
        return Column(
          children: items
              .map(
                (e) => Card(
                  child: Padding(
                    padding: const EdgeInsets.all(14),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          amountLabel(e.amountMinor, e.currency),
                          style: Theme.of(context).textTheme.titleMedium,
                        ),
                        const SizedBox(height: 4),
                        Text(
                          '${e.category.label} · ${e.payee ?? 'Payee not recorded'}',
                        ),
                        Text(e.source.label),
                        Text(_date(e.occurredAt)),
                        Wrap(
                          spacing: 8,
                          crossAxisAlignment: WrapCrossAlignment.center,
                          children: [
                            Text(
                              e.reversal == null
                                  ? 'Recorded'
                                  : 'Fully reversed',
                            ),
                            TextButton(
                              onPressed: _busy ? null : () => _details(e),
                              child: const Text('View history'),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
              )
              .toList(),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) => ListView(
    padding: const EdgeInsets.all(20),
    children: [
      PageHeading(
        title: 'Expenses',
        subtitle:
            'Record verified business payments and retain their original history with full compensating reversals.',
        trailing: FilledButton.icon(
          key: const Key('expense-record'),
          onPressed: _connected && !_busy && !_hasPending && _context != null
              ? _record
              : null,
          icon: const Icon(Icons.add),
          label: const Text('Record paid expense'),
        ),
      ),
      const SizedBox(height: 20),
      if (!_connected)
        SectionCard(
          child: FeatureEmptyState(
            icon: Icons.receipt_long_outlined,
            title: widget.isPreview
                ? 'No connected expense history'
                : 'Expense access is restricted',
            message:
                'An authorized connected business account is required to read or record actual expenses.',
            status: FeatureStatus.notYetConnected,
          ),
        )
      else ...[
        if (_pending.isNotEmpty) ...[
          PendingOperationsPanel(
            operations: _pending,
            retry: widget.repository!.retryPending,
            busy: _busy,
            onSettled: (result) {
              if (!mounted) return;
              if (result is Expense &&
                  result.requestId == _pendingRecord?.requestId) {
                _pendingRecord = null;
                _pendingRecordContext = null;
              }
              if (result is ExpenseReversal &&
                  result.requestId == _pendingReverse?.requestId) {
                _pendingReverse = null;
              }
              _load(_offset);
            },
          ),
          const SizedBox(height: 12),
        ],
        if (_pendingRecord != null &&
            _pending.every(
              (e) => e.requestId != _pendingRecord!.requestId,
            )) ...[
          OperationNotice(
            message:
                'The paid expense record is unconfirmed. Resume its frozen request and keep the original payment evidence.',
            requestId: _pendingRecord!.requestId,
          ),
          OutlinedButton(
            key: const Key('expense-resume'),
            onPressed: _busy ? null : _record,
            child: const Text('Resume saved expense'),
          ),
          const SizedBox(height: 12),
        ],
        if (_pendingReverse != null &&
            _pending.every(
              (e) => e.requestId != _pendingReverse!.requestId,
            )) ...[
          OperationNotice(
            message:
                'The full correction is unconfirmed. Preserve the original returned-cash or external correction evidence.',
            requestId: _pendingReverse!.requestId,
          ),
          OutlinedButton(
            key: const Key('expense-reversal-resume'),
            onPressed: _busy ? null : _resumeReverse,
            child: const Text('Resume saved reversal'),
          ),
          const SizedBox(height: 12),
        ],
        SectionCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              DropdownButtonFormField<String>(
                key: ValueKey('expense-branch-$_branchId'),
                initialValue: _branchId,
                isExpanded: true,
                decoration: const InputDecoration(labelText: 'Branch'),
                items: _branches
                    .map(
                      (e) => DropdownMenuItem(
                        value: e.id,
                        child: Text(e.name, overflow: TextOverflow.ellipsis),
                      ),
                    )
                    .toList(),
                onChanged: _busy || _hasPending
                    ? null
                    : (value) {
                        setState(() => _branchId = value);
                        _load(0);
                      },
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<String>(
                key: ValueKey('expense-filter-$_category'),
                initialValue: _category?.name ?? 'all',
                isExpanded: true,
                decoration: const InputDecoration(
                  labelText: 'Expense category',
                ),
                items: [
                  const DropdownMenuItem(
                    value: 'all',
                    child: Text('All categories'),
                  ),
                  ...ExpenseCategory.values.map(
                    (e) =>
                        DropdownMenuItem(value: e.name, child: Text(e.label)),
                  ),
                ],
                onChanged: _busy
                    ? null
                    : (value) {
                        setState(
                          () => _category = value == 'all'
                              ? null
                              : ExpenseCategory.values.firstWhere(
                                  (e) => e.name == value,
                                ),
                        );
                        _load(0);
                      },
              ),
              const SizedBox(height: 12),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  OutlinedButton(
                    onPressed: _busy ? null : _selectDates,
                    child: const Text('Select UTC dates'),
                  ),
                  if (_dates != null)
                    TextButton(
                      onPressed: _busy
                          ? null
                          : () {
                              setState(() => _dates = null);
                              _load(0);
                            },
                      child: const Text('Clear dates'),
                    ),
                  TextButton(
                    key: const Key('expenses-reload'),
                    onPressed: _busy ? null : () => _load(_offset),
                    child: const Text('Reload history'),
                  ),
                ],
              ),
              Text(
                _dates == null
                    ? 'All posted dates (UTC)'
                    : '${_date(_filter.from!)} to ${_date(_filter.to!)} (exclusive UTC end)',
              ),
              if (_context?.ownOpenShift case final shift?) ...[
                const SizedBox(height: 8),
                Text(
                  'Own open drawer expected cash: ${amountLabel(shift.expectedCashMinor, shift.currency)}',
                ),
                const Text(
                  'This is a server projection. Confirm actual physical payouts and returns separately.',
                ),
              ],
            ],
          ),
        ),
        const SizedBox(height: 16),
        if (_busy) const LinearProgressIndicator(),
        if (_error != null) ...[
          OperationNotice(message: _error!, isError: true),
          const SizedBox(height: 12),
        ],
        if (!_busy && _page != null && _page!.items.isEmpty)
          const SectionCard(
            child: FeatureEmptyState(
              icon: Icons.receipt_long_outlined,
              title: 'No recorded expenses',
              message:
                  'The server returned no expense history for this branch and selected filters.',
              status: FeatureStatus.available,
            ),
          ),
        if (_page != null && _page!.items.isNotEmpty) _list(),
        const SizedBox(height: 12),
        OperationPager(
          prefix: 'expenses',
          offset: _offset,
          hasMore: _page?.hasMore ?? false,
          busy: _busy,
          onPage: _load,
        ),
      ],
    ],
  );
}
