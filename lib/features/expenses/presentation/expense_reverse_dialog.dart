import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

import '../../inventory/presentation/operations_ui_support.dart';
import '../domain/expense_models.dart';
import '../domain/expense_repository.dart';
import 'expense_dialog_session.dart';

class ExpenseReverseDialog extends StatefulWidget {
  const ExpenseReverseDialog({
    super.key,
    required this.repository,
    required this.original,
    required this.session,
    required this.onFrozen,
    required this.onResolved,
    this.pending,
  });
  final ExpenseRepository repository;
  final Expense original;
  final ExpenseDialogSession session;
  final ReverseExpenseRequest? pending;
  final ValueChanged<ReverseExpenseRequest> onFrozen;
  final VoidCallback onResolved;
  @override
  State<ExpenseReverseDialog> createState() => _ExpenseReverseDialogState();
}

class _ExpenseReverseDialogState extends State<ExpenseReverseDialog> {
  final _reason = TextEditingController();
  final _reference = TextEditingController();
  bool _confirmed = false, _busy = false, _invalidated = false;
  String? _error;
  ReverseExpenseRequest? _frozen;
  @override
  void initState() {
    super.initState();
    widget.session.listen(_invalidate);
    _frozen = widget.pending;
    _reason.text = widget.pending?.reason ?? '';
    _reference.text = widget.pending?.reference ?? '';
    _confirmed = widget.pending?.manualConfirmed ?? false;
  }

  void _invalidate() {
    _invalidated = true;
    if (!mounted) return;
    if (WidgetsBinding.instance.schedulerPhase ==
        SchedulerPhase.persistentCallbacks) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) setState(() {});
      });
    } else {
      setState(() {});
    }
  }

  @override
  void dispose() {
    widget.session.unlisten(_invalidate);
    _reason.dispose();
    _reference.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_busy || !widget.session.active) return;
    ReverseExpenseRequest request;
    try {
      request =
          _frozen ??
          ReverseExpenseRequest(
            original: widget.original,
            reason: _reason.text,
            reference: _reference.text,
            manualConfirmed: _confirmed,
          );
      request.parameters(widget.repository.organizationId);
    } catch (error) {
      setState(() => _error = operationError(error));
      return;
    }
    final wasFrozen = _frozen != null;
    setState(() {
      _busy = true;
      _error = null;
      _frozen = request;
    });
    widget.onFrozen(request);
    try {
      final result = await widget.repository.reverseExpense(request);
      if (!mounted || !widget.session.active) return;
      widget.onResolved();
      Navigator.of(context).pop(result);
    } catch (error) {
      if (!mounted || !widget.session.active) return;
      setState(() => _error = operationError(error));
      if (!wasFrozen && !operationMayBeUnconfirmed(error)) {
        setState(() => _frozen = null);
        widget.onResolved();
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_invalidated || !widget.session.active) {
      return AlertDialog(
        title: const Text('Business context changed'),
        content: const Text(
          'The original expense request remains with its account.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Close'),
          ),
        ],
      );
    }
    final frozen = _frozen;
    final original = widget.original;
    final editable = !_busy && frozen == null;
    return PopScope(
      canPop: !_busy,
      child: AlertDialog(
        title: const Text('Reverse recorded expense'),
        content: SizedBox(
          width: 520,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Full compensation: ${amountLabel(original.amountMinor, original.currency)}',
                ),
                const SizedBox(height: 8),
                Text(
                  original.source == ExpenseSource.cashDrawer
                      ? 'Confirm all the original cash returned to the same own open drawer. A closed shift requires review.'
                      : 'Confirm the full bookkeeping correction or externally verified reimbursement.',
                ),
                const SizedBox(height: 8),
                const Text('The original expense stays in history.'),
                const SizedBox(height: 12),
                if (frozen != null) ...[
                  OperationNotice(
                    message:
                        'Retry the frozen correction without repeating a physical return or reimbursement.',
                    requestId: frozen.requestId,
                  ),
                  const SizedBox(height: 12),
                ],
                TextField(
                  key: const Key('expense-reversal-reference'),
                  controller: _reference,
                  enabled: editable,
                  maxLength: 120,
                  decoration: const InputDecoration(
                    labelText: 'Reversal reference (optional)',
                  ),
                ),
                TextField(
                  key: const Key('expense-reversal-reason'),
                  controller: _reason,
                  enabled: editable,
                  maxLength: 1000,
                  minLines: 2,
                  maxLines: 4,
                  decoration: const InputDecoration(
                    labelText: 'Reversal reason',
                  ),
                ),
                CheckboxListTile(
                  key: const Key('expense-reversal-confirmation'),
                  contentPadding: EdgeInsets.zero,
                  value: _confirmed,
                  onChanged: editable
                      ? (v) => setState(() => _confirmed = v ?? false)
                      : null,
                  title: Text(
                    original.source == ExpenseSource.cashDrawer
                        ? 'I confirm the full cash amount returned to this original drawer.'
                        : 'I confirm this full bookkeeping correction or verified reimbursement.',
                  ),
                ),
                if (_error != null)
                  OperationNotice(message: _error!, isError: true),
                if (_busy) const LinearProgressIndicator(),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: _busy ? null : () => Navigator.of(context).pop(),
            child: Text(frozen == null ? 'Cancel' : 'Close and retain request'),
          ),
          FilledButton(
            key: const Key('expense-reversal-save'),
            onPressed: _busy ? null : _save,
            child: Text(
              frozen == null ? 'Record full reversal' : 'Retry saved reversal',
            ),
          ),
        ],
      ),
    );
  }
}
