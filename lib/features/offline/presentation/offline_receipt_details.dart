import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../core/sync/outbox_state.dart';
import '../../catalog/domain/repository_support.dart';
import '../../inventory/presentation/operations_ui_support.dart';
import '../../receipts/data/receipt_output_service.dart';
import '../../receipts/domain/receipt_document.dart';
import '../../receipts/presentation/receipt_output_actions.dart';
import '../../receipts/presentation/receipt_output_scope.dart';
import '../domain/offline_workspace.dart';

String offlineReceiptStatus(LocalOfflineReceipt receipt) =>
    switch (receipt.status) {
      OutboxStatus.pending => 'PENDING · stored on this device',
      OutboxStatus.syncing => 'SYNCING · awaiting server response',
      OutboxStatus.synced =>
        receipt.reconciliationCode == null
            ? 'SYNCED · server receipt linked'
            : 'SYNCED · stock reconciliation required',
      OutboxStatus.failed => 'FAILED · original paid record preserved',
    };

Future<void> showOfflineReceipt(
  BuildContext context,
  LocalOfflineReceipt receipt,
  OfflineWorkspace workspace, {
  ReceiptOutputService? outputService,
  bool Function()? isCurrent,
}) => showDialog<void>(
  context: context,
  builder: (context) => _OfflineReceiptDialog(
    receipt: receipt,
    workspace: workspace,
    outputService: outputService,
    isCurrent: isCurrent,
  ),
);

class _OfflineReceiptDialog extends StatefulWidget {
  const _OfflineReceiptDialog({
    required this.receipt,
    required this.workspace,
    this.outputService,
    this.isCurrent,
  });
  final LocalOfflineReceipt receipt;
  final OfflineWorkspace workspace;
  final ReceiptOutputService? outputService;
  final bool Function()? isCurrent;

  @override
  State<_OfflineReceiptDialog> createState() => _OfflineReceiptDialogState();
}

class _OfflineReceiptDialogState extends State<_OfflineReceiptDialog> {
  bool _busy = false;
  String? _notice;
  bool Function()? _scopeCurrent;
  int _generation = 0;
  ReceiptDocument? _document;

  @override
  void initState() {
    super.initState();
    _setDocument();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _scopeCurrent ??=
        ReceiptOutputScope.maybeOf(context) == null && widget.isCurrent != null
        ? widget.isCurrent!
        : ReceiptOutputScope.capture(context);
  }

  @override
  void didUpdateWidget(covariant _OfflineReceiptDialog oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.workspace != widget.workspace ||
        oldWidget.receipt != widget.receipt ||
        oldWidget.isCurrent != widget.isCurrent) {
      _generation++;
      _busy = false;
      _notice = null;
    }
    if (oldWidget.receipt != widget.receipt) {
      _setDocument();
    }
  }

  void _setDocument() {
    try {
      _document = ReceiptDocument.fromOffline(widget.receipt);
    } on Object {
      // Uncertain or older evidence remains reviewable, but cannot be exported
      // as a customer receipt unless its original amounts validate.
      _document = null;
    }
  }

  bool _current() =>
      mounted &&
      (ModalRoute.of(context)?.isCurrent ?? true) &&
      (_scopeCurrent?.call() ?? false) &&
      (widget.isCurrent?.call() ?? true);

  Future<void> _copy() async {
    if (_busy || !_current()) return;
    final generation = _generation;
    final workspace = widget.workspace;
    final eventId = widget.receipt.draft.eventId;
    bool current() =>
        _current() &&
        generation == _generation &&
        identical(workspace, widget.workspace) &&
        eventId == widget.receipt.draft.eventId;
    setState(() => _busy = true);
    try {
      final original = await workspace.exportReceipt(eventId);
      if (!current()) return;
      await Clipboard.setData(ClipboardData(text: original));
      if (current()) {
        setState(
          () => _notice =
              'Original signed event copied. Share it only with an authorized business reviewer.',
        );
      }
    } on Object {
      if (current()) {
        setState(
          () => _notice =
              'The original record could not be copied. It remains stored on this device.',
        );
      }
    } finally {
      if (mounted && generation == _generation) {
        setState(() => _busy = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final receipt = widget.receipt;
    final draft = receipt.draft;
    String money(int minor) => '${draft.currency} ${Money.formatMinor(minor)}';
    return AlertDialog(
      title: const Text('Provisional offline receipt'),
      content: SizedBox(
        width: 480,
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(receipt.businessName ?? 'Authorized business'),
              if (receipt.branchName != null) Text(receipt.branchName!),
              const SizedBox(height: 12),
              SelectableText(draft.receiptNumber),
              Text(offlineReceiptStatus(receipt)),
              const SizedBox(height: 8),
              const Text(
                'This is the original local receipt. A server link is recorded separately after verified synchronization. Digital payments are operator verified; no provider API approval is claimed.',
                style: TextStyle(fontSize: 12, height: 1.4),
              ),
              const Divider(height: 24),
              for (final item in draft.items)
                Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('${item.quantity} × ${item.name}'),
                      Text('${item.sku} · ${money(item.totalMinor)}'),
                    ],
                  ),
                ),
              Text('Subtotal ${money(draft.subtotalMinor)}'),
              if (draft.discountMinor != 0)
                Text('Discount ${money(draft.discountMinor)}'),
              Text('Tax ${money(draft.taxMinor)}'),
              Text(
                'Total ${money(draft.totalMinor)}',
                style: const TextStyle(fontWeight: FontWeight.w700),
              ),
              const Divider(height: 24),
              for (final payment in draft.payments)
                Text(
                  '${payment.method.toUpperCase()} · ${money(payment.amountMinor)}${payment.reference == null ? '' : '\nManual reference: ${payment.reference}'}',
                ),
              const SizedBox(height: 16),
              Text('Observed ${manilaTime(draft.createdAt)} · Asia/Manila'),
              SelectableText('Event ${draft.eventId}'),
              if (receipt.serverReceiptId != null) ...[
                const SizedBox(height: 8),
                SelectableText('Server receipt ${receipt.serverReceiptId}'),
              ],
              if (receipt.failureCode != null ||
                  receipt.reconciliationCode != null)
                const Padding(
                  padding: EdgeInsets.only(top: 12),
                  child: Text(
                    'An authorized reviewer must reconcile this record. Its original items and payment evidence remain unchanged. Do not collect another payment.',
                    style: TextStyle(fontWeight: FontWeight.w600),
                  ),
                ),
              if (_notice != null) ...[
                const SizedBox(height: 12),
                Text(_notice!),
              ],
              if (_document != null)
                ReceiptOutputActions(
                  document: _document!,
                  service: widget.outputService,
                  isCurrent: _current,
                )
              else
                const Text(
                  'Printing and PDF export are unavailable for this receipt snapshot.',
                  key: Key('receipt-output-unavailable'),
                ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton.icon(
          key: const Key('export-offline-receipt'),
          onPressed: _busy || !_current() ? null : _copy,
          icon: const Icon(Icons.copy_outlined),
          label: const Text('Copy original signed record'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Close'),
        ),
      ],
    );
  }
}
