import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

import '../../inventory/presentation/operations_ui_support.dart';
import '../domain/expense_models.dart';
import 'expense_dialog_session.dart';

class ExpenseDetails extends StatefulWidget {
  const ExpenseDetails({
    super.key,
    required this.expense,
    required this.session,
    required this.branchName,
    this.onReverse,
    this.reverseUnavailable,
  });
  final Expense expense;
  final ExpenseDialogSession session;
  final String branchName;
  final Future<void> Function()? onReverse;
  final String? reverseUnavailable;
  @override
  State<ExpenseDetails> createState() => _ExpenseDetailsState();
}

class _ExpenseDetailsState extends State<ExpenseDetails> {
  bool _busy = false;
  @override
  void initState() {
    super.initState();
    widget.session.listen(_invalidate);
  }

  void _invalidate() {
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
    super.dispose();
  }

  Future<void> _reverse() async {
    if (_busy || !widget.session.active || widget.onReverse == null) return;
    setState(() => _busy = true);
    try {
      await widget.onReverse!();
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  String _utc(DateTime time) => time.toUtc().toIso8601String();
  @override
  Widget build(BuildContext context) {
    if (!widget.session.active) {
      return AlertDialog(
        title: const Text('Business context changed'),
        content: const Text(
          'Close this view to continue with your current account.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Close'),
          ),
        ],
      );
    }
    final expense = widget.expense;
    final reversal = expense.reversal;
    Widget line(String name, String value) => Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Text('$name: $value'),
    );
    return AlertDialog(
      title: const Text('Expense history'),
      content: SizedBox(
        width: 620,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              line('Branch', widget.branchName),
              line(
                'Original paid amount',
                amountLabel(expense.amountMinor, expense.currency),
              ),
              line('Category', expense.category.label),
              line('Source', expense.source.label),
              line('Method', expensePaymentLabel(expense.paymentMethod)),
              line('Payee', expense.payee ?? 'Not recorded'),
              line('Reference', expense.reference ?? 'Not recorded'),
              line('Recorded (UTC)', _utc(expense.createdAt)),
              line('Reason', expense.reason),
              if (expense.shiftId != null)
                line('Original own drawer shift', expense.shiftId!),
              SelectableText('Expense: ${expense.id}'),
              SelectableText('Request: ${expense.requestId}'),
              const SizedBox(height: 16),
              if (reversal == null)
                const Text('This original expense has no recorded reversal.')
              else ...[
                const Divider(),
                Text(
                  'Full compensation',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const SizedBox(height: 8),
                line(
                  'Reversed amount',
                  amountLabel(reversal.amountMinor, reversal.currency),
                ),
                line('Recorded (UTC)', _utc(reversal.createdAt)),
                line('Reason', reversal.reason),
                line('Reference', reversal.reference ?? 'Not recorded'),
                SelectableText('Reversal: ${reversal.id}'),
                SelectableText('Request: ${reversal.requestId}'),
                const SizedBox(height: 8),
                const Text(
                  'The original record remains unchanged. Net recorded expense: 0.00 in its original currency.',
                ),
              ],
              if (widget.reverseUnavailable != null)
                Padding(
                  padding: const EdgeInsets.only(top: 12),
                  child: Text(widget.reverseUnavailable!),
                ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: _busy ? null : () => Navigator.of(context).pop(),
          child: const Text('Close'),
        ),
        if (reversal == null)
          OutlinedButton(
            key: const Key('expense-details-reverse'),
            onPressed: _busy || widget.onReverse == null ? null : _reverse,
            child: const Text('Reverse recorded expense'),
          ),
      ],
    );
  }
}
