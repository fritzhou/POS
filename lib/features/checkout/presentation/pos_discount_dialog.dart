import 'package:flutter/material.dart';

import '../../catalog/domain/repository_support.dart';
import '../domain/checkout_models.dart';

/// The caller permits this only for the operator's verified privileged role;
/// PostgreSQL independently authorizes the submitted discount and audit reason.
class PosDiscountDialog extends StatefulWidget {
  const PosDiscountDialog({
    required this.lines,
    required this.taxBps,
    this.discountMinor = 0,
    this.reason,
    super.key,
  });
  final List<CartLine> lines;
  final int taxBps;
  final int discountMinor;
  final String? reason;
  @override
  State<PosDiscountDialog> createState() => _PosDiscountDialogState();
}

class _PosDiscountDialogState extends State<PosDiscountDialog> {
  late final TextEditingController _amount;
  late final TextEditingController _reason;
  String? _error;
  @override
  void initState() {
    super.initState();
    _amount = TextEditingController(
      text: Money.formatMinor(widget.discountMinor),
    );
    _reason = TextEditingController(text: widget.reason ?? '');
  }

  @override
  void dispose() {
    _amount.dispose();
    _reason.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('Discount this order'),
    content: SizedBox(
      width: 400,
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              key: const Key('discount-amount'),
              controller: _amount,
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ),
              decoration: const InputDecoration(labelText: 'Discount amount'),
            ),
            const SizedBox(height: 12),
            TextField(
              key: const Key('discount-reason'),
              controller: _reason,
              maxLength: 500,
              decoration: const InputDecoration(
                labelText: 'Reason (required for a discount)',
              ),
            ),
            if (_error != null)
              Text(
                _error!,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
          ],
        ),
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('Cancel'),
      ),
      FilledButton(
        onPressed: () {
          try {
            final amount = Money.parseMinor(_amount.text);
            CartTotals.calculate(
              lines: widget.lines,
              taxBps: widget.taxBps,
              discountMinor: amount,
            );
            final reason = amount > 0
                ? requiredText(_reason.text, 'Discount reason', 500)
                : null;
            Navigator.pop(context, (amount, reason));
          } on RepositoryFailure catch (failure) {
            setState(() => _error = failure.message);
          }
        },
        child: const Text('Apply discount'),
      ),
    ],
  );
}
