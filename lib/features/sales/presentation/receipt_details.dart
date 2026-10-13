import 'package:flutter/material.dart';

import '../../catalog/domain/repository_support.dart';
import '../../checkout/domain/checkout_models.dart';
import '../../inventory/presentation/operations_ui_support.dart';
import '../../receipts/data/receipt_output_service.dart';
import '../../receipts/domain/receipt_document.dart';
import '../../receipts/presentation/receipt_output_actions.dart';

String paymentMethodLabel(CheckoutPaymentMethod method) => switch (method) {
  CheckoutPaymentMethod.cash => 'Cash',
  CheckoutPaymentMethod.card => 'Card',
  CheckoutPaymentMethod.gcash => 'GCash',
  CheckoutPaymentMethod.maya => 'Maya',
  CheckoutPaymentMethod.other => 'Other',
};

/// Displays only the committed server snapshot. Original totals remain visible
/// after a compensating refund or void; a reversal never rewrites a receipt.
class ReceiptDetails extends StatelessWidget {
  const ReceiptDetails({
    required this.receipt,
    this.outputService,
    this.isCurrent,
    super.key,
  });
  final SaleReceipt receipt;
  final ReceiptOutputService? outputService;
  final bool Function()? isCurrent;

  @override
  Widget build(BuildContext context) {
    ReceiptDocument? document;
    try {
      document = ReceiptDocument.fromSale(receipt);
    } on Object {
      // Preserve immutable history for review while output fails closed.
      document = null;
    }
    final reversed = receipt.payments.fold<int>(
      0,
      (amount, payment) => amount + payment.reversedMinor,
    );
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          receipt.businessName ?? 'Business receipt',
          style: Theme.of(context).textTheme.titleLarge,
          textAlign: TextAlign.center,
        ),
        if (receipt.branchName != null)
          Text(receipt.branchName!, textAlign: TextAlign.center),
        if (receipt.address != null)
          Text(receipt.address!, textAlign: TextAlign.center),
        if (receipt.contact != null)
          Text(receipt.contact!, textAlign: TextAlign.center),
        const SizedBox(height: 16),
        SelectableText('Receipt ${receipt.receiptNumber}'),
        Text('${manilaTime(receipt.createdAt)} · Asia/Manila'),
        const Divider(height: 28),
        ...receipt.items.map(
          (item) => Padding(
            padding: const EdgeInsets.only(bottom: 14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  item.name,
                  style: const TextStyle(fontWeight: FontWeight.w600),
                ),
                Text(
                  '${item.sku} · ${item.quantity} × ${amountLabel(item.unitPriceMinor, receipt.currency)}',
                ),
                Text(
                  'Line total ${amountLabel(item.totalMinor, receipt.currency)}',
                ),
                if (item.discountMinor != 0)
                  Text(
                    'Discount ${amountLabel(item.discountMinor, receipt.currency)}',
                  ),
                if (item.reversedQuantity != 0)
                  Text(
                    'Reversed units: ${item.reversedQuantity}',
                    style: const TextStyle(color: Color(0xffb45309)),
                  ),
              ],
            ),
          ),
        ),
        const Divider(),
        _amount('Subtotal', receipt.subtotalMinor),
        _amount('Discount', -receipt.discountMinor),
        _amount(
          'Tax (${Money.formatMinor(receipt.taxBps)}%)',
          receipt.taxMinor,
        ),
        _amount('Original total', receipt.totalMinor, bold: true),
        if (reversed != 0) _amount('Recorded reversals', reversed),
        const Divider(height: 28),
        Text('Payments', style: Theme.of(context).textTheme.titleSmall),
        const SizedBox(height: 8),
        ...receipt.payments.map(
          (payment) => Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _amount(
                  paymentMethodLabel(payment.method),
                  payment.amountMinor,
                ),
                if (payment.method == CheckoutPaymentMethod.cash) ...[
                  if (payment.tenderedMinor != null)
                    _amount('Cash received', payment.tenderedMinor!),
                  _amount('Change', payment.changeMinor),
                ] else ...[
                  const Text(
                    'Manual Verification · No provider authorization',
                    style: TextStyle(fontSize: 12, color: Color(0xff64748b)),
                  ),
                  if (payment.reference != null)
                    SelectableText('Reference: ${payment.reference}'),
                ],
                if (payment.reversedMinor != 0)
                  _amount('Reversed', payment.reversedMinor),
              ],
            ),
          ),
        ),
        if (receipt.receiptFooter != null) ...[
          const SizedBox(height: 8),
          Text(receipt.receiptFooter!, textAlign: TextAlign.center),
        ],
        if (document != null)
          ReceiptOutputActions(
            document: document,
            service: outputService,
            isCurrent: isCurrent,
          )
        else
          const Text(
            'Printing and PDF export are unavailable for this receipt snapshot.',
            key: Key('receipt-output-unavailable'),
          ),
      ],
    );
  }

  Widget _amount(String label, int amount, {bool bold = false}) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 3),
    child: Wrap(
      alignment: WrapAlignment.spaceBetween,
      spacing: 12,
      runSpacing: 2,
      children: [
        Text(
          label,
          style: TextStyle(fontWeight: bold ? FontWeight.w700 : null),
        ),
        Text(
          amountLabel(amount, receipt.currency),
          style: TextStyle(fontWeight: bold ? FontWeight.w700 : null),
        ),
      ],
    ),
  );
}

Future<void> showReceiptDialog(
  BuildContext context,
  SaleReceipt receipt, {
  ReceiptOutputService? outputService,
  bool Function()? isCurrent,
}) => showDialog<void>(
  context: context,
  builder: (context) => AlertDialog(
    title: const Text('Sale receipt'),
    content: SizedBox(
      width: 480,
      child: SingleChildScrollView(
        child: ReceiptDetails(
          receipt: receipt,
          outputService: outputService,
          isCurrent: isCurrent,
        ),
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('Close'),
      ),
    ],
  ),
);
