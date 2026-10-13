import 'package:flutter/material.dart';

import '../../catalog/domain/repository_support.dart';
import '../../../../core/services/payment_service.dart';

/// Collects operator tender evidence. A result is not a completed sale; the
/// calling POS must submit it and wait for a server receipt.
class PosPaymentDialog extends StatefulWidget {
  const PosPaymentDialog({
    required this.totalMinor,
    required this.currency,
    this.completionNotice =
        'The sale is saved only after the server confirms checkout. Cash is counted by you. Card, GCash, Maya and Other use Manual Payment Verification; provider APIs are not connected.',
    this.submitLabel = 'Submit checkout',
    this.initialTenders = const [],
    this.onRecordTender,
    super.key,
  });

  final int totalMinor;
  final String currency;
  final String completionNotice;
  final String submitLabel;
  final List<TenderEvidence> initialTenders;
  final Future<void> Function(int index, TenderEvidence tender)? onRecordTender;

  @override
  State<PosPaymentDialog> createState() => _PosPaymentDialogState();
}

class _PosPaymentDialogState extends State<PosPaymentDialog> {
  final _amount = TextEditingController();
  final _received = TextEditingController();
  final _reference = TextEditingController();
  final _tenders = <TenderEvidence>[];
  PaymentMethod _method = PaymentMethod.cash;
  bool _confirmed = false;
  String? _error;
  bool _saving = false;
  TenderEvidence? _staged;
  bool get _durable => widget.onRecordTender != null;
  bool get _fieldsLocked => _saving || _staged != null;

  int get _remaining =>
      widget.totalMinor -
      _tenders.fold(0, (sum, tender) => sum + tender.appliedMinor);

  @override
  void initState() {
    super.initState();
    _tenders.addAll(widget.initialTenders);
    _resetFields();
  }

  @override
  void dispose() {
    _amount.dispose();
    _received.dispose();
    _reference.dispose();
    super.dispose();
  }

  void _resetFields() {
    _amount.text = Money.formatMinor(_remaining);
    _received.text = _method == PaymentMethod.cash ? '' : _amount.text;
    _reference.clear();
    _confirmed = false;
  }

  Future<void> _addTender() async {
    if (_saving) return;
    try {
      final applied = Money.parseMinor(_amount.text);
      if (applied <= 0 || applied > _remaining) {
        throw const RepositoryFailure(
          RepositoryFailureType.validation,
          'The applied amount must be positive and no more than the remaining total.',
        );
      }
      final received = _method == PaymentMethod.cash
          ? Money.parseMinor(_received.text)
          : applied;
      final service = _method == PaymentMethod.cash
          ? CashPaymentService()
          : ManualDigitalPaymentService(_method);
      final evidence =
          _staged ??
          service.recordTender(
            TenderRequest(
              amountDueMinor: applied,
              receivedMinor: received,
              currency: widget.currency,
              operatorConfirmed: _confirmed,
              reference: _reference.text,
            ),
          );
      if (_durable) {
        setState(() {
          _saving = true;
          _staged = evidence;
          _error = null;
        });
        try {
          await widget.onRecordTender!(_tenders.length, evidence);
        } catch (error) {
          if (!mounted) return;
          setState(() {
            _saving = false;
            _error = error is RepositoryFailure
                ? error.message
                : 'Saving this payment could not be confirmed. Retry its original evidence; do not collect it again. Confirmed evidence remains available for review when it reached the journal.';
          });
          return;
        }
        if (!mounted) return;
      }
      setState(() {
        _saving = false;
        _staged = null;
        _tenders.add(evidence);
        _error = null;
        _resetFields();
      });
    } on RepositoryFailure catch (error) {
      setState(() => _error = error.message);
    } on FormatException {
      setState(
        () => _error = _method == PaymentMethod.cash
            ? 'Count and confirm enough cash for this payment.'
            : 'Confirm the payment in the actual provider or terminal and enter its reference.',
      );
    }
  }

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: !_saving,
    child: AlertDialog(
      title: const Text('Record payment'),
      content: SizedBox(
        width: 480,
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                '${widget.currency} ${Money.formatMinor(widget.totalMinor)} due',
                style: Theme.of(context).textTheme.titleLarge,
              ),
              const SizedBox(height: 8),
              Text(
                widget.completionNotice,
                style: const TextStyle(fontSize: 12, height: 1.4),
              ),
              for (var index = 0; index < _tenders.length; index++)
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  title: Text(
                    '${_methodLabel(_tenders[index].method)} · ${widget.currency} ${Money.formatMinor(_tenders[index].appliedMinor)}',
                  ),
                  subtitle: Text(
                    _tenders[index].method == PaymentMethod.cash
                        ? 'Cash counted · Change ${Money.formatMinor(_tenders[index].changeMinor)}'
                        : 'Manual Payment Verification · ${_tenders[index].reference}',
                  ),
                  trailing: _durable
                      ? const Icon(Icons.lock_outline)
                      : IconButton(
                          tooltip: 'Remove payment',
                          onPressed: () => setState(() {
                            _tenders.removeAt(index);
                            _resetFields();
                          }),
                          icon: const Icon(Icons.close),
                        ),
                ),
              const Divider(height: 24),
              Text(
                'Remaining: ${widget.currency} ${Money.formatMinor(_remaining)}',
              ),
              if (_remaining > 0 && _tenders.length >= 5)
                const Padding(
                  padding: EdgeInsets.only(top: 12),
                  child: Text(
                    'An order supports at most five payments. Keep confirmed tender evidence and review an incomplete allocation before continuing.',
                  ),
                ),
              if (_remaining > 0 && _tenders.length < 5) ...[
                const SizedBox(height: 16),
                DropdownButtonFormField<PaymentMethod>(
                  key: const Key('payment-method'),
                  initialValue: _method,
                  decoration: const InputDecoration(
                    labelText: 'Payment method',
                  ),
                  items: [
                    for (final method in PaymentMethod.values)
                      DropdownMenuItem(
                        value: method,
                        child: Text(_methodLabel(method)),
                      ),
                  ],
                  onChanged: _fieldsLocked
                      ? null
                      : (method) {
                          if (method == null) return;
                          setState(() {
                            _method = method;
                            _error = null;
                            _resetFields();
                          });
                        },
                ),
                const SizedBox(height: 12),
                TextField(
                  key: const Key('payment-applied-amount'),
                  controller: _amount,
                  enabled: !_fieldsLocked,
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                  decoration: const InputDecoration(
                    labelText: 'Amount applied to this order',
                  ),
                ),
                if (_method == PaymentMethod.cash) ...[
                  const SizedBox(height: 12),
                  TextField(
                    key: const Key('cash-received'),
                    controller: _received,
                    enabled: !_fieldsLocked,
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                    ),
                    decoration: const InputDecoration(
                      labelText: 'Cash received',
                    ),
                  ),
                ] else ...[
                  const SizedBox(height: 12),
                  TextField(
                    key: const Key('payment-reference'),
                    controller: _reference,
                    enabled: !_fieldsLocked,
                    maxLength: 160,
                    decoration: const InputDecoration(
                      labelText: 'Verified payment / terminal reference',
                    ),
                  ),
                ],
                CheckboxListTile(
                  key: const Key('payment-confirmed'),
                  value: _confirmed,
                  contentPadding: EdgeInsets.zero,
                  controlAffinity: ListTileControlAffinity.leading,
                  title: Text(
                    _method == PaymentMethod.cash
                        ? 'I counted and received this cash.'
                        : 'I verified this amount in the provider app, terminal or other payment record.',
                  ),
                  onChanged: _fieldsLocked
                      ? null
                      : (value) => setState(() => _confirmed = value ?? false),
                ),
                OutlinedButton.icon(
                  key: const Key('add-payment'),
                  onPressed: _saving ? null : _addTender,
                  icon: const Icon(Icons.add),
                  label: Text(
                    _saving
                        ? 'Saving original payment…'
                        : _staged != null
                        ? 'Retry saving original payment'
                        : _durable
                        ? 'Save confirmed payment'
                        : 'Add payment',
                  ),
                ),
              ],
              if (_durable && _tenders.isNotEmpty)
                const Padding(
                  padding: EdgeInsets.only(top: 12),
                  child: Text(
                    'Confirmed payments are saved individually. Closing this dialog preserves the original order and payment evidence for recovery. Saved payments cannot be removed.',
                  ),
                ),
              if (_error != null) ...[
                const SizedBox(height: 12),
                Text(
                  _error!,
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
              ],
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: _saving ? null : () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        FilledButton(
          key: const Key('submit-payment'),
          onPressed:
              !_saving &&
                  _staged == null &&
                  _remaining == 0 &&
                  _tenders.isNotEmpty
              ? () => Navigator.pop(
                  context,
                  List<TenderEvidence>.unmodifiable(_tenders),
                )
              : null,
          child: Text(widget.submitLabel),
        ),
      ],
    ),
  );
}

String _methodLabel(PaymentMethod method) => switch (method) {
  PaymentMethod.cash => 'Cash',
  PaymentMethod.card => 'Card',
  PaymentMethod.gcash => 'GCash',
  PaymentMethod.maya => 'Maya',
  PaymentMethod.other => 'Other',
};
