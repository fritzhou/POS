import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

import '../../catalog/domain/repository_support.dart';
import '../../checkout/domain/checkout_models.dart';
import '../../inventory/presentation/operations_ui_support.dart';
import '../domain/expense_models.dart';
import '../domain/expense_repository.dart';
import 'expense_dialog_session.dart';

class ExpenseRecordDialog extends StatefulWidget {
  const ExpenseRecordDialog({
    super.key,
    required this.repository,
    required this.expenseContext,
    required this.session,
    required this.onFrozen,
    required this.onResolved,
    this.pending,
    this.drawerBlocked = false,
  });
  final ExpenseRepository repository;
  final ExpenseContext expenseContext;
  final ExpenseDialogSession session;
  final RecordExpenseRequest? pending;
  final bool drawerBlocked;
  final ValueChanged<RecordExpenseRequest> onFrozen;
  final VoidCallback onResolved;
  @override
  State<ExpenseRecordDialog> createState() => _ExpenseRecordDialogState();
}

class _ExpenseRecordDialogState extends State<ExpenseRecordDialog> {
  final _amount = TextEditingController();
  final _payee = TextEditingController();
  final _reference = TextEditingController();
  final _reason = TextEditingController();
  ExpenseCategory _category = ExpenseCategory.other;
  ExpenseSource _source = ExpenseSource.external;
  CheckoutPaymentMethod _method = CheckoutPaymentMethod.cash;
  bool _confirmed = false, _busy = false, _invalidated = false;
  String? _error;
  RecordExpenseRequest? _frozen;
  @override
  void initState() {
    super.initState();
    widget.session.listen(_invalidate);
    final pending = widget.pending;
    _frozen = pending;
    if (pending != null) {
      _amount.text = Money.formatMinor(pending.amountMinor);
      _payee.text = pending.payee ?? '';
      _reference.text = pending.reference ?? '';
      _reason.text = pending.reason;
      _category = pending.category;
      _source = pending.source;
      _method = pending.paymentMethod;
      _confirmed = pending.manualConfirmed;
    }
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
    _amount.dispose();
    _payee.dispose();
    _reference.dispose();
    _reason.dispose();
    super.dispose();
  }

  bool get _editable => !_busy && _frozen == null;
  Future<void> _save() async {
    if (_busy || !widget.session.active) return;
    RecordExpenseRequest request;
    try {
      request =
          _frozen ??
          RecordExpenseRequest(
            branchId: widget.expenseContext.branchId,
            expectedSettingsRevision: widget.expenseContext.settingsRevision,
            currency: widget.expenseContext.currency,
            amountMinor: Money.parseMinor(_amount.text),
            category: _category,
            paymentMethod: _method,
            source: _source,
            shiftId: _source == ExpenseSource.cashDrawer
                ? widget.expenseContext.ownOpenShift?.id
                : null,
            manualConfirmed: _confirmed,
            payee: _payee.text,
            reference: _reference.text,
            reason: _reason.text,
          );
      request.parameters(widget.repository.organizationId);
      if (_frozen == null &&
          _source == ExpenseSource.cashDrawer &&
          (!widget.expenseContext.canUseCashDrawer || widget.drawerBlocked)) {
        throw const RepositoryFailure(
          RepositoryFailureType.conflict,
          'An own open shift in this currency and confirmed drawer requests are required.',
        );
      }
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
      final result = await widget.repository.recordExpense(request);
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
    final current = widget.expenseContext;
    final frozen = _frozen;
    return PopScope(
      canPop: !_busy,
      child: AlertDialog(
        title: const Text('Record paid expense'),
        content: SizedBox(
          width: 560,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '${current.branchName} · ${frozen?.currency ?? current.currency}',
                ),
                const SizedBox(height: 8),
                const Text(
                  'Record a payment already completed. Keep its receipt or verified reference.',
                ),
                const SizedBox(height: 12),
                if (frozen != null) ...[
                  OperationNotice(
                    message:
                        'This request is frozen. Retry its saved record without repeating the physical payment.',
                    requestId: frozen.requestId,
                  ),
                  const SizedBox(height: 12),
                ],
                DropdownButtonFormField<ExpenseSource>(
                  key: ValueKey('expense-source-$_source'),
                  initialValue: _source,
                  isExpanded: true,
                  decoration: const InputDecoration(
                    labelText: 'Funding source',
                  ),
                  items: ExpenseSource.values
                      .map(
                        (source) => DropdownMenuItem(
                          value: source,
                          enabled:
                              source == ExpenseSource.external ||
                              current.canUseCashDrawer && !widget.drawerBlocked,
                          child: Text(
                            source.label,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      )
                      .toList(),
                  onChanged: _editable
                      ? (value) => setState(() {
                          _source = value!;
                          _confirmed = false;
                          if (_source == ExpenseSource.cashDrawer) {
                            _method = CheckoutPaymentMethod.cash;
                          }
                        })
                      : null,
                ),
                const SizedBox(height: 8),
                if (_source == ExpenseSource.external)
                  const Text(
                    'External funds include cash paid outside the POS drawer.',
                  )
                else
                  Text(
                    'Original own shift: ${frozen?.shiftId ?? current.ownOpenShift?.id ?? 'Unavailable'}',
                  ),
                if (!current.canUseCashDrawer && frozen == null)
                  const Text(
                    'Open your own same-currency shift to record a drawer payout.',
                  ),
                if (widget.drawerBlocked && frozen == null)
                  const Text(
                    'Confirm the pending checkout or shift closure before using the drawer.',
                  ),
                const SizedBox(height: 12),
                TextField(
                  key: const Key('expense-amount'),
                  controller: _amount,
                  enabled: _editable,
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                  decoration: InputDecoration(
                    labelText:
                        'Paid amount (${frozen?.currency ?? current.currency})',
                  ),
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<ExpenseCategory>(
                  key: ValueKey('expense-category-$_category'),
                  initialValue: _category,
                  isExpanded: true,
                  decoration: const InputDecoration(labelText: 'Category'),
                  items: ExpenseCategory.values
                      .map(
                        (e) => DropdownMenuItem(value: e, child: Text(e.label)),
                      )
                      .toList(),
                  onChanged: _editable
                      ? (value) => setState(() => _category = value!)
                      : null,
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<CheckoutPaymentMethod>(
                  key: ValueKey('expense-method-$_method'),
                  initialValue: _method,
                  isExpanded: true,
                  decoration: const InputDecoration(
                    labelText: 'Payment method',
                  ),
                  items: CheckoutPaymentMethod.values
                      .map(
                        (e) => DropdownMenuItem(
                          value: e,
                          child: Text(expensePaymentLabel(e)),
                        ),
                      )
                      .toList(),
                  onChanged: _editable && _source == ExpenseSource.external
                      ? (value) => setState(() {
                          _method = value!;
                          _confirmed = false;
                        })
                      : null,
                ),
                const SizedBox(height: 12),
                TextField(
                  key: const Key('expense-payee'),
                  controller: _payee,
                  enabled: _editable,
                  maxLength: 160,
                  decoration: const InputDecoration(
                    labelText: 'Payee (optional)',
                  ),
                ),
                TextField(
                  key: const Key('expense-reference'),
                  controller: _reference,
                  enabled: _editable,
                  maxLength: 120,
                  decoration: InputDecoration(
                    labelText: _method == CheckoutPaymentMethod.cash
                        ? 'Payment reference (optional)'
                        : 'Verified payment reference',
                  ),
                ),
                TextField(
                  key: const Key('expense-reason'),
                  controller: _reason,
                  enabled: _editable,
                  maxLength: 1000,
                  minLines: 2,
                  maxLines: 4,
                  decoration: const InputDecoration(
                    labelText: 'Expense reason',
                  ),
                ),
                CheckboxListTile(
                  key: const Key('expense-manual-confirmation'),
                  contentPadding: EdgeInsets.zero,
                  value: _confirmed,
                  onChanged: _editable
                      ? (value) => setState(() => _confirmed = value ?? false)
                      : null,
                  title: Text(
                    _source == ExpenseSource.cashDrawer
                        ? 'I confirm this cash was paid from my own open drawer.'
                        : 'I verified the payment completed using external funds.',
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
            key: const Key('expense-save'),
            onPressed: _busy ? null : _save,
            child: Text(
              frozen == null ? 'Record expense' : 'Retry saved expense',
            ),
          ),
        ],
      ),
    );
  }
}
