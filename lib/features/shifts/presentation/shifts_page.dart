import 'package:flutter/material.dart';

import '../../../app/config/feature_status.dart';
import '../../../core/operations/operation_journal.dart';
import '../../../core/security/app_role.dart';
import '../../../core/widgets/status_widgets.dart';
import '../../administration/domain/administration_models.dart';
import '../../catalog/domain/repository_support.dart';
import '../../checkout/domain/checkout_models.dart';
import '../../checkout/domain/checkout_repository.dart';
import '../../inventory/presentation/operations_ui_support.dart';
import '../../people/domain/people_repository.dart';

class ShiftsPage extends StatefulWidget {
  const ShiftsPage({
    this.repository,
    this.peopleRepository,
    this.role,
    this.currentUserId,
    this.isPreview = true,
    super.key,
  });
  final CheckoutRepository? repository;
  final PeopleRepository? peopleRepository;
  final AppRole? role;
  final String? currentUserId;
  final bool isPreview;
  @override
  State<ShiftsPage> createState() => _ShiftsPageState();
}

class _ShiftsPageState extends State<ShiftsPage> {
  List<BranchOption> _branches = const [];
  String? _branchId, _error;
  PosContext? _context;
  Shift? _currentShift;
  DataPage<Shift>? _page;
  bool _busy = false;
  int _generation = 0;
  OpenShiftRequest? _pendingOpen;
  CloseShiftRequest? _pendingClose;
  Shift? _pendingCloseShift;
  List<PendingOperation> _savedPending = const [];
  bool get _connected =>
      !widget.isPreview &&
      widget.repository != null &&
      widget.peopleRepository != null &&
      widget.currentUserId != null &&
      (widget.role?.allows(AppPermission.viewShifts) ?? false);
  bool _mayClose(Shift shift) =>
      _connected &&
      shift.isOpen &&
      (shift.actorUserId == widget.currentUserId ||
          widget.role == AppRole.owner ||
          widget.role == AppRole.admin ||
          widget.role == AppRole.manager);
  bool get _hasPending =>
      _pendingOpen != null || _pendingClose != null || _savedPending.isNotEmpty;

  @override
  void initState() {
    super.initState();
    if (_connected) _load(0);
  }

  @override
  void didUpdateWidget(covariant ShiftsPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.repository != widget.repository ||
        oldWidget.peopleRepository != widget.peopleRepository ||
        oldWidget.role != widget.role ||
        oldWidget.currentUserId != widget.currentUserId ||
        oldWidget.isPreview != widget.isPreview) {
      _generation++;
      _branches = const [];
      _branchId = null;
      _page = null;
      _currentShift = null;
      _context = null;
      _error = null;
      _busy = false;
      _pendingOpen = null;
      _pendingClose = null;
      _pendingCloseShift = null;
      _savedPending = const [];
      if (_connected) _load(0);
    }
  }

  Future<void> _load(int offset) async {
    if (!_connected || _busy) return;
    final generation = ++_generation;
    setState(() {
      _busy = true;
      _error = null;
      _page = null;
      _context = null;
      _currentShift = null;
    });
    try {
      final pending = await widget.repository!.pendingOperations();
      if (!mounted || generation != _generation) return;
      setState(() => _savedPending = pending);
      final branches = await widget.peopleRepository!.listBranches();
      final branch = branches.any((branch) => branch.id == _branchId)
          ? _branchId
          : branches.firstOrNull?.id;
      final repository = widget.repository!;
      final context = branch == null
          ? null
          : await repository.loadContext(branch);
      final current = branch == null
          ? null
          : await repository.currentShift(branch);
      final page = branch == null
          ? null
          : await repository.listShifts(
              branchId: branch,
              page: PageRequest(offset: offset, limit: 20),
            );
      if (!mounted || generation != _generation) return;
      setState(() {
        _branches = branches;
        _branchId = branch;
        _context = context;
        _currentShift = current;
        _page = page;
      });
    } catch (error) {
      if (mounted && generation == _generation) {
        setState(() => _error = operationError(error));
      }
    } finally {
      if (mounted && generation == _generation) setState(() => _busy = false);
    }
  }

  Future<void> _open() async {
    if (!_connected || _branchId == null || _context == null) return;
    final result = await showDialog<Shift>(
      context: context,
      barrierDismissible: false,
      builder: (context) => _ShiftCashDialog(
        repository: widget.repository!,
        branchId: _branchId!,
        currency: _context!.currency,
        pendingOpen: _pendingOpen,
        onOpenFrozen: (request) => _pendingOpen = request,
        onCloseFrozen: (_) {},
        onResolved: () => _pendingOpen = null,
      ),
    );
    if (!mounted) return;
    setState(() {});
    if (result != null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Shift opened by the server.')),
      );
    }
    await _load(_page?.offset ?? 0);
  }

  Future<void> _close(Shift shift) async {
    if (!_mayClose(shift) && _pendingClose == null) return;
    final result = await showDialog<Shift>(
      context: context,
      barrierDismissible: false,
      builder: (context) => _ShiftCashDialog(
        repository: widget.repository!,
        branchId: shift.branchId,
        currency: shift.currency,
        shift: shift,
        pendingClose: _pendingClose,
        onOpenFrozen: (_) {},
        onCloseFrozen: (request) {
          _pendingClose = request;
          _pendingCloseShift = shift;
        },
        onResolved: () {
          _pendingClose = null;
          _pendingCloseShift = null;
        },
      ),
    );
    if (!mounted) return;
    setState(() {});
    if (result != null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Shift closed. Server cash difference: ${amountLabel(result.cashDifferenceMinor ?? 0, result.currency)}.',
          ),
        ),
      );
    }
    await _load(_page?.offset ?? 0);
  }

  @override
  Widget build(BuildContext context) => ListView(
    padding: const EdgeInsets.all(20),
    children: [
      PageHeading(
        title: 'Shifts',
        subtitle:
            'Count opening and closing cash. The server calculates expected cash from committed cash sales and recorded cash payouts.',
        trailing: FilledButton.icon(
          key: const Key('shift-open'),
          onPressed:
              _connected &&
                  !_busy &&
                  !_hasPending &&
                  _currentShift == null &&
                  _context != null
              ? _open
              : null,
          icon: const Icon(Icons.play_circle_outline),
          label: const Text('Open shift'),
        ),
      ),
      const SizedBox(height: 20),
      if (!_connected)
        const SectionCard(
          child: FeatureEmptyState(
            icon: Icons.lock_clock_outlined,
            title: 'No connected shifts',
            message:
                'Connect a verified POS membership to count cash and read actual shifts. This preview cannot open or close a shift.',
            status: FeatureStatus.notYetConnected,
          ),
        )
      else ...[
        if (_savedPending.isNotEmpty)
          PendingOperationsPanel(
            operations: _savedPending,
            retry: widget.repository!.retryPending,
            busy: _busy,
            onSettled: (result) {
              _pendingOpen = null;
              _pendingClose = null;
              _pendingCloseShift = null;
              if (result != null) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text(
                      'Saved financial request confirmed by the server.',
                    ),
                  ),
                );
              }
              _load(_page?.offset ?? 0);
            },
          ),
        if ((_pendingOpen != null || _pendingClose != null) &&
            _savedPending.every(
              (operation) =>
                  operation.requestId !=
                  (_pendingOpen?.requestId ?? _pendingClose!.requestId),
            )) ...[
          OperationNotice(
            message:
                'A shift request has an unconfirmed result. Resume it before starting another cash-count action.',
            requestId: _pendingOpen?.requestId ?? _pendingClose!.requestId,
          ),
          const SizedBox(height: 10),
          OutlinedButton(
            key: const Key('shift-resume'),
            onPressed: !_busy
                ? () {
                    if (_pendingOpen != null) {
                      _open();
                    } else {
                      _close(_pendingCloseShift!);
                    }
                  }
                : null,
            child: const Text('Resume unconfirmed shift request'),
          ),
          const SizedBox(height: 16),
        ],
        SectionCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              DropdownButtonFormField<String>(
                key: ValueKey('shift-branch-$_branchId'),
                initialValue: _branchId,
                isExpanded: true,
                decoration: const InputDecoration(labelText: 'Branch'),
                items: _branches
                    .map(
                      (branch) => DropdownMenuItem(
                        value: branch.id,
                        child: Text(
                          branch.name,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    )
                    .toList(),
                onChanged: !_busy && !_hasPending
                    ? (value) {
                        setState(() => _branchId = value);
                        _load(0);
                      }
                    : null,
              ),
              const SizedBox(height: 16),
              if (_currentShift != null) ...[
                const Text(
                  'Your open shift',
                  style: TextStyle(fontWeight: FontWeight.w700),
                ),
                Text(
                  'Opened ${manilaTime(_currentShift!.openedAt)} · Asia/Manila',
                ),
                Text(
                  'Opening cash: ${amountLabel(_currentShift!.openingCashMinor, _currentShift!.currency)}',
                ),
                Text(
                  'Expected cash: ${amountLabel(_currentShift!.expectedCashMinor, _currentShift!.currency)}',
                ),
                if (_currentShift!.expectedCashMinor < 0) ...[
                  const SizedBox(height: 10),
                  const OperationNotice(
                    message:
                        'Expected cash is below zero. Recorded cash payouts exceed the opening float and cash sales in this drawer. Review the deficit and record the actual nonnegative cash count.',
                    isError: true,
                  ),
                ],
                const SizedBox(height: 12),
                OutlinedButton(
                  key: const Key('shift-close-current'),
                  onPressed: !_busy && !_hasPending
                      ? () => _close(_currentShift!)
                      : null,
                  child: const Text('Count cash and close'),
                ),
              ] else
                const Text('You have no open shift in this branch.'),
              const SizedBox(height: 12),
              TextButton.icon(
                key: const Key('shifts-refresh'),
                onPressed: !_busy ? () => _load(_page?.offset ?? 0) : null,
                icon: const Icon(Icons.refresh),
                label: const Text('Refresh shifts'),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        if (_busy) const LinearProgressIndicator(),
        if (_error != null) ...[
          OperationNotice(message: _error!, isError: true),
          const SizedBox(height: 12),
        ],
        if (!_busy && _error == null && (_page?.items.isEmpty ?? true))
          const SectionCard(
            child: FeatureEmptyState(
              icon: Icons.history_outlined,
              title: 'No shift history',
              message: 'Confirmed shift records appear here.',
              status: FeatureStatus.available,
            ),
          ),
        ...?_page?.items.map(
          (shift) => Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: SectionCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Wrap(
                    spacing: 12,
                    runSpacing: 8,
                    children: [
                      Text(
                        shift.isOpen ? 'Open shift' : 'Closed shift',
                        style: const TextStyle(fontWeight: FontWeight.w700),
                      ),
                      StatusPill(
                        label: shift.actorUserId == widget.currentUserId
                            ? 'Your shift'
                            : 'Branch staff shift',
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  Text('Opened: ${manilaTime(shift.openedAt)} · Asia/Manila'),
                  if (shift.closedAt != null)
                    Text(
                      'Closed: ${manilaTime(shift.closedAt!)} · Asia/Manila',
                    ),
                  Text(
                    'Opening cash: ${amountLabel(shift.openingCashMinor, shift.currency)}',
                  ),
                  Text(
                    'Expected cash: ${amountLabel(shift.expectedCashMinor, shift.currency)}',
                  ),
                  if (shift.countedCashMinor != null)
                    Text(
                      'Counted cash: ${amountLabel(shift.countedCashMinor!, shift.currency)}',
                    ),
                  if (shift.cashDifferenceMinor != null)
                    Text(
                      'Cash difference: ${amountLabel(shift.cashDifferenceMinor!, shift.currency)}',
                      style: TextStyle(
                        color: shift.cashDifferenceMinor == 0
                            ? null
                            : Theme.of(context).colorScheme.error,
                      ),
                    ),
                  if (shift.expectedCashMinor < 0) ...[
                    const SizedBox(height: 10),
                    const Text(
                      'Drawer deficit: recorded cash payouts exceed this shift’s opening float and cash sales.',
                      style: TextStyle(color: Color(0xffb45309)),
                    ),
                  ],
                  if (_mayClose(shift)) ...[
                    const SizedBox(height: 10),
                    OutlinedButton(
                      key: Key('shift-close-${shift.id}'),
                      onPressed: !_busy && !_hasPending
                          ? () => _close(shift)
                          : null,
                      child: const Text('Count cash and close'),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
        if (_page != null)
          OperationPager(
            prefix: 'shifts',
            offset: _page!.offset,
            hasMore: _page!.hasMore,
            busy: _busy,
            onPage: _load,
          ),
      ],
    ],
  );
}

class _ShiftCashDialog extends StatefulWidget {
  const _ShiftCashDialog({
    required this.repository,
    required this.branchId,
    required this.currency,
    required this.onOpenFrozen,
    required this.onCloseFrozen,
    required this.onResolved,
    this.shift,
    this.pendingOpen,
    this.pendingClose,
  });
  final CheckoutRepository repository;
  final String branchId, currency;
  final Shift? shift;
  final OpenShiftRequest? pendingOpen;
  final CloseShiftRequest? pendingClose;
  final ValueChanged<OpenShiftRequest> onOpenFrozen;
  final ValueChanged<CloseShiftRequest> onCloseFrozen;
  final VoidCallback onResolved;
  @override
  State<_ShiftCashDialog> createState() => _ShiftCashDialogState();
}

class _ShiftCashDialogState extends State<_ShiftCashDialog> {
  final _form = GlobalKey<FormState>();
  final _cash = TextEditingController(), _reason = TextEditingController();
  OpenShiftRequest? _open;
  CloseShiftRequest? _close;
  bool _saving = false, _checked = false;
  String? _error;
  bool get _closing => widget.shift != null;
  bool get _frozen => _open != null || _close != null;
  @override
  void initState() {
    super.initState();
    _open = widget.pendingOpen;
    _close = widget.pendingClose;
  }

  @override
  void dispose() {
    _cash.dispose();
    _reason.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_saving) return;
    if (!_frozen) {
      if (!_form.currentState!.validate()) return;
      if (!_checked) {
        setState(() => _error = 'Confirm that you counted the physical cash.');
        return;
      }
      if (_closing) {
        _close = CloseShiftRequest(
          branchId: widget.branchId,
          shiftId: widget.shift!.id,
          countedCashMinor: Money.parseMinor(_cash.text),
          reason: _reason.text.trim(),
        );
        widget.onCloseFrozen(_close!);
      } else {
        _open = OpenShiftRequest(
          branchId: widget.branchId,
          expectedCurrency: widget.currency,
          openingCashMinor: Money.parseMinor(_cash.text),
        );
        widget.onOpenFrozen(_open!);
      }
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      final result = _closing
          ? await widget.repository.closeShift(_close!)
          : await widget.repository.openShift(_open!);
      widget.onResolved();
      if (mounted) Navigator.pop(context, result);
    } catch (error) {
      if (mounted) {
        setState(() {
          _error = operationMayBeUnconfirmed(error)
              ? '${operationError(error)} Retry the same cash-count request to confirm its result.'
              : operationError(error);
          if (!operationMayBeUnconfirmed(error)) {
            _open = null;
            _close = null;
            widget.onResolved();
          }
        });
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: !_saving,
    child: AlertDialog(
      title: Text(_closing ? 'Count cash and close shift' : 'Open shift'),
      content: SizedBox(
        width: 460,
        child: SingleChildScrollView(
          child: Form(
            key: _form,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _closing
                      ? 'Count the cash physically present. The server calculates the final expected amount and discrepancy.'
                      : 'Count the opening cash float physically present in this drawer.',
                ),
                if (_closing) ...[
                  const SizedBox(height: 12),
                  Text(
                    'Last loaded expected cash: ${amountLabel(widget.shift!.expectedCashMinor, widget.shift!.currency)}',
                  ),
                  if (widget.shift!.expectedCashMinor < 0) ...[
                    const SizedBox(height: 8),
                    const OperationNotice(
                      message:
                          'This drawer has a recorded cash deficit. Count the physical cash that is actually present; the server calculates the final difference.',
                      isError: true,
                    ),
                  ],
                ],
                const SizedBox(height: 16),
                if (!_frozen) ...[
                  TextFormField(
                    key: const Key('shift-cash'),
                    controller: _cash,
                    enabled: !_saving,
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                    ),
                    decoration: InputDecoration(
                      labelText:
                          '${_closing ? 'Counted closing' : 'Opening'} cash (${widget.currency})',
                    ),
                    validator: (value) => operationValidation(
                      () => Money.parseMinor(value ?? ''),
                    ),
                  ),
                  if (_closing) ...[
                    const SizedBox(height: 14),
                    TextFormField(
                      key: const Key('shift-close-reason'),
                      controller: _reason,
                      enabled: !_saving,
                      maxLength: 500,
                      maxLines: 2,
                      decoration: const InputDecoration(
                        labelText: 'Closing reason or cash-count note',
                      ),
                      validator: (value) => operationValidation(
                        () => requiredText(
                          value ?? '',
                          'Closing note',
                          500,
                          minimum: 3,
                        ),
                      ),
                    ),
                  ],
                  CheckboxListTile(
                    contentPadding: EdgeInsets.zero,
                    controlAffinity: ListTileControlAffinity.leading,
                    value: _checked,
                    onChanged: !_saving
                        ? (value) => setState(() => _checked = value ?? false)
                        : null,
                    title: const Text(
                      'I counted and confirmed this physical cash amount',
                    ),
                  ),
                ] else
                  OperationNotice(
                    message:
                        'The cash-count request is frozen. Retry uses the same amount and request identifier.',
                    requestId: _open?.requestId ?? _close!.requestId,
                  ),
                if (_error != null) ...[
                  const SizedBox(height: 12),
                  OperationNotice(message: _error!, isError: true),
                ],
              ],
            ),
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: !_saving ? () => Navigator.pop(context) : null,
          child: Text(_frozen ? 'Keep pending and close' : 'Cancel'),
        ),
        FilledButton(
          key: const Key('shift-submit'),
          onPressed: !_saving ? _submit : null,
          child: Text(
            _saving
                ? 'Confirming…'
                : _frozen
                ? 'Retry same request'
                : _closing
                ? 'Close shift'
                : 'Open shift',
          ),
        ),
      ],
    ),
  );
}
