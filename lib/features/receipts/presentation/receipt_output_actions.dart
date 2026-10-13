import 'package:flutter/material.dart';

import '../data/receipt_output_service.dart';
import '../domain/receipt_document.dart';
import 'receipt_output_scope.dart';

/// Output is an explicit customer-copy action, independent of financial work.
class ReceiptOutputActions extends StatefulWidget {
  const ReceiptOutputActions({
    required this.document,
    this.service,
    this.isCurrent,
    super.key,
  });

  final ReceiptDocument document;
  final ReceiptOutputService? service;
  final bool Function()? isCurrent;

  @override
  State<ReceiptOutputActions> createState() => _ReceiptOutputActionsState();
}

class _ReceiptOutputActionsState extends State<ReceiptOutputActions> {
  ReceiptPaperFormat _paper = ReceiptPaperFormat.thermal80;
  bool _busy = false;
  bool _unsupportedCharacters = false;
  String? _notice;
  bool Function()? _scopeCurrent;
  late final ReceiptOutputService _native = NativeReceiptOutputService();
  int _generation = 0;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Capture once for this view. Unlocking or returning to an old account must
    // not revive an output that was prepared under an earlier scope.
    _scopeCurrent ??=
        ReceiptOutputScope.maybeOf(context) == null && widget.isCurrent != null
        ? widget.isCurrent!
        : ReceiptOutputScope.capture(context);
  }

  @override
  void didUpdateWidget(covariant ReceiptOutputActions oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.document, widget.document) ||
        oldWidget.service != widget.service ||
        oldWidget.isCurrent != widget.isCurrent) {
      _generation++;
      _busy = false;
      _unsupportedCharacters = false;
      _notice = null;
    }
  }

  bool get _activeScope =>
      mounted &&
      (_scopeCurrent?.call() ?? false) &&
      (widget.isCurrent?.call() ?? true);

  bool get _current =>
      _activeScope && (ModalRoute.of(context)?.isCurrent ?? true);

  Future<void> _output({required bool print}) async {
    if (_busy || _unsupportedCharacters || !_current) return;
    final generation = _generation;
    final document = widget.document;
    final paper = _paper;
    final service = widget.service ?? _native;
    bool current() =>
        _current &&
        generation == _generation &&
        identical(document, widget.document) &&
        identical(service, widget.service ?? _native);
    setState(() {
      _busy = true;
      _notice = null;
    });
    try {
      final result = print
          ? await service.printReceipt(
              document,
              paper: paper,
              isCurrent: current,
            )
          : await service.shareReceiptPdf(
              document,
              paper: paper,
              isCurrent: current,
            );
      if (!current()) return;
      if (result.status == ReceiptOutputStatus.unsupportedCharacters) {
        _unsupportedCharacters = true;
      }
      setState(
        () => _notice = switch (result.status) {
          ReceiptOutputStatus.submitted =>
            print
                ? 'Sent to the system print service.'
                : 'PDF handed to the system PDF handler. Use its save or share controls.',
          ReceiptOutputStatus.cancelled =>
            print ? 'Printing cancelled.' : 'PDF sharing cancelled.',
          ReceiptOutputStatus.unavailable =>
            'Receipt output is unavailable on this platform.',
          ReceiptOutputStatus.scopeChanged =>
            'Close this view and reopen the receipt before exporting.',
          ReceiptOutputStatus.failed =>
            'Receipt output could not be completed. Try again from this receipt.',
          ReceiptOutputStatus.unsupportedCharacters =>
            'A character in this receipt is not supported for PDF output. The original record remains readable.',
        },
      );
    } on Object {
      if (current()) {
        setState(
          () => _notice =
              'Receipt output could not be completed. Try again from this receipt.',
        );
      }
    } finally {
      if (mounted && generation == _generation) {
        setState(() => _busy = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) => Column(
    key: const Key('receipt-output-actions'),
    crossAxisAlignment: CrossAxisAlignment.stretch,
    mainAxisSize: MainAxisSize.min,
    children: [
      const Divider(height: 28),
      Text(
        'Printing and PDF export',
        style: Theme.of(context).textTheme.titleSmall,
      ),
      const SizedBox(height: 8),
      const Text(
        'Outputs are labelled COPY. The original receipt and payment record stay unchanged.',
        style: TextStyle(fontSize: 12, height: 1.4),
      ),
      if (widget.document.isProvisional) ...[
        const SizedBox(height: 6),
        const Text(
          'The customer copy remains PROVISIONAL after synchronization. Signed review evidence is excluded.',
          style: TextStyle(fontSize: 12, height: 1.4),
        ),
      ],
      const SizedBox(height: 12),
      DropdownButtonFormField<ReceiptPaperFormat>(
        key: const Key('receipt-paper-format'),
        initialValue: _paper,
        isExpanded: true,
        decoration: const InputDecoration(labelText: 'Paper size'),
        items: const [
          DropdownMenuItem(
            value: ReceiptPaperFormat.thermal80,
            child: Text('80 mm receipt'),
          ),
          DropdownMenuItem(
            value: ReceiptPaperFormat.thermal58,
            child: Text('58 mm receipt'),
          ),
          DropdownMenuItem(value: ReceiptPaperFormat.a4, child: Text('A4')),
        ],
        onChanged: _busy || _unsupportedCharacters || !_activeScope
            ? null
            : (paper) {
                if (paper != null) setState(() => _paper = paper);
              },
      ),
      const SizedBox(height: 12),
      Wrap(
        spacing: 8,
        runSpacing: 8,
        children: [
          OutlinedButton.icon(
            key: const Key('print-receipt-copy'),
            onPressed: _busy || _unsupportedCharacters || !_current
                ? null
                : () => _output(print: true),
            icon: const Icon(Icons.print_outlined),
            label: const Text('Print copy'),
          ),
          Tooltip(
            message:
                'Open the system PDF handler or share dialog. Use its controls to save or share.',
            child: OutlinedButton.icon(
              key: const Key('share-receipt-pdf'),
              onPressed: _busy || _unsupportedCharacters || !_current
                  ? null
                  : () => _output(print: false),
              icon: const Icon(Icons.picture_as_pdf_outlined),
              label: const Text('Open / share PDF'),
            ),
          ),
        ],
      ),
      if (_busy) ...[
        const SizedBox(height: 12),
        const LinearProgressIndicator(),
        const SizedBox(height: 6),
        const Text('Preparing receipt copy…'),
      ],
      if (_notice != null) ...[
        const SizedBox(height: 12),
        Text(_notice!, key: const Key('receipt-output-notice')),
      ],
    ],
  );
}
