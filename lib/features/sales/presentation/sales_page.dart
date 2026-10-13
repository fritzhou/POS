import 'package:flutter/material.dart';

import '../../../app/config/feature_status.dart';
import '../../../core/operations/operation_journal.dart';
import '../../../core/security/app_role.dart';
import '../../../core/widgets/status_widgets.dart';
import '../../administration/domain/administration_models.dart';
import '../../catalog/domain/repository_support.dart';
import '../../checkout/domain/checkout_models.dart';
import '../../checkout/domain/checkout_repository.dart';
import '../../checkout/domain/refund_selection.dart';
import '../../inventory/presentation/operations_ui_support.dart';
import '../../people/domain/people_repository.dart';
import 'receipt_details.dart';

class SalesPage extends StatefulWidget {
  const SalesPage({
    this.repository,
    this.peopleRepository,
    this.role,
    this.isPreview = true,
    super.key,
  });
  final CheckoutRepository? repository;
  final PeopleRepository? peopleRepository;
  final AppRole? role;
  final bool isPreview;
  @override
  State<SalesPage> createState() => _SalesPageState();
}

class _SalesPageState extends State<SalesPage> {
  List<BranchOption> _branches = const [];
  String? _branchId, _error;
  DataPage<SaleReceipt>? _page;
  bool _busy = false;
  int _generation = 0;
  final _receiptView = ValueNotifier<int>(0);
  int _receiptEpoch = 0;
  void _invalidateReceiptView() {
    _receiptEpoch++;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _receiptView.value++;
    });
  }

  ReversalRequest? _pendingReversal;
  SaleReceipt? _pendingReceipt;
  List<PendingOperation> _savedPending = const [];
  bool get _connected =>
      !widget.isPreview &&
      widget.repository != null &&
      widget.peopleRepository != null &&
      (widget.role?.allows(AppPermission.viewSales) ?? false);
  bool get _canReverse =>
      _connected && (widget.role?.allows(AppPermission.approveRefund) ?? false);

  @override
  void initState() {
    super.initState();
    if (_connected) _load(0);
  }

  @override
  void didUpdateWidget(covariant SalesPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.repository != widget.repository ||
        oldWidget.peopleRepository != widget.peopleRepository ||
        oldWidget.role != widget.role ||
        oldWidget.isPreview != widget.isPreview) {
      _generation++;
      _invalidateReceiptView();
      _branches = const [];
      _branchId = null;
      _page = null;
      _error = null;
      _busy = false;
      _pendingReversal = null;
      _pendingReceipt = null;
      _savedPending = const [];
      if (_connected) _load(0);
    }
  }

  @override
  void dispose() {
    _receiptEpoch++;
    _receiptView.dispose();
    super.dispose();
  }

  Future<void> _load(int offset) async {
    if (!_connected || _busy) return;
    final generation = ++_generation;
    setState(() {
      _busy = true;
      _error = null;
      _page = null;
    });
    try {
      final pending = await widget.repository!.pendingOperations();
      if (!mounted || generation != _generation) return;
      setState(() => _savedPending = pending);
      final branches = await widget.peopleRepository!.listBranches();
      final selected = branches.any((branch) => branch.id == _branchId)
          ? _branchId
          : branches.firstOrNull?.id;
      final page = selected == null
          ? null
          : await widget.repository!.listSales(
              branchId: selected,
              page: PageRequest(offset: offset, limit: 20),
            );
      if (!mounted || generation != _generation) return;
      setState(() {
        _branches = branches;
        _branchId = selected;
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

  Future<void> _details(SaleReceipt summary) async {
    if (!_connected || _busy) return;
    final generation = _generation;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final receipt = await widget.repository!.getSale(summary.id);
      if (!mounted || generation != _generation) return;
      setState(() => _busy = false);
      final epoch = _receiptEpoch;
      final repository = widget.repository;
      bool current() =>
          mounted &&
          _connected &&
          epoch == _receiptEpoch &&
          generation == _generation &&
          repository == widget.repository;
      final kind = await showDialog<SaleReversalKind>(
        context: context,
        builder: (context) => ListenableBuilder(
          listenable: _receiptView,
          builder: (context, _) => !current()
              ? AlertDialog(
                  title: const Text('Business context changed'),
                  content: const Text(
                    'Open the receipt again under the current authorized account.',
                  ),
                  actions: [
                    TextButton(
                      onPressed: () => Navigator.pop(context),
                      child: const Text('Close'),
                    ),
                  ],
                )
              : AlertDialog(
                  title: const Text('Sale receipt'),
                  content: SizedBox(
                    width: 500,
                    child: SingleChildScrollView(
                      child: ReceiptDetails(
                        receipt: receipt,
                        isCurrent: current,
                      ),
                    ),
                  ),
                  actions: [
                    if (_canReverse &&
                        _pendingReversal == null &&
                        _savedPending.isEmpty &&
                        receipt.items.any(
                          (item) => item.refundableQuantity > 0,
                        )) ...[
                      TextButton(
                        onPressed: () =>
                            Navigator.pop(context, SaleReversalKind.refund),
                        child: const Text('Refund remaining sale'),
                      ),
                      if (receipt.items.every(
                            (item) => item.reversedQuantity == 0,
                          ) &&
                          receipt.payments.every(
                            (payment) => payment.reversedMinor == 0,
                          ))
                        TextButton(
                          onPressed: () =>
                              Navigator.pop(context, SaleReversalKind.voidSale),
                          child: const Text('Void remaining sale'),
                        ),
                    ],
                    TextButton(
                      onPressed: () => Navigator.pop(context),
                      child: const Text('Close'),
                    ),
                  ],
                ),
        ),
      );
      if (current() && kind != null) await _reverse(receipt, kind);
    } catch (error) {
      if (mounted && generation == _generation) {
        setState(() => _error = operationError(error));
      }
    } finally {
      if (mounted && generation == _generation) setState(() => _busy = false);
    }
  }

  Future<void> _reverse(SaleReceipt receipt, SaleReversalKind kind) async {
    if (!_canReverse) return;
    Shift? shift;
    if (_pendingReversal == null) {
      try {
        shift = await widget.repository!.currentShift(receipt.branchId);
      } catch (error) {
        if (mounted) setState(() => _error = operationError(error));
        return;
      }
      if (!mounted) return;
      if (shift == null) {
        setState(
          () => _error =
              'Open your own shift in this branch before recording a refund or void.',
        );
        return;
      }
    }
    if (!mounted) return;
    final result = await showDialog<SaleReversal>(
      context: context,
      barrierDismissible: false,
      builder: (context) => _ReversalDialog(
        repository: widget.repository!,
        receipt: receipt,
        kind: kind,
        shift: shift,
        pending: _pendingReversal,
        onFrozen: (request) {
          _pendingReversal = request;
          _pendingReceipt = receipt;
        },
        onResolved: () {
          _pendingReversal = null;
          _pendingReceipt = null;
        },
      ),
    );
    if (!mounted) return;
    setState(() {});
    if (result != null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            '${kind == SaleReversalKind.refund ? 'Refund' : 'Void'} recorded by the server.',
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
        title: 'Sales',
        subtitle:
            'Committed sales and immutable receipts. Cashiers see only their own sales in authorized branches.',
        trailing: OutlinedButton.icon(
          key: const Key('sales-refresh'),
          onPressed: _connected && !_busy
              ? () => _load(_page?.offset ?? 0)
              : null,
          icon: const Icon(Icons.refresh),
          label: const Text('Refresh'),
        ),
      ),
      const SizedBox(height: 20),
      if (!_connected)
        const SectionCard(
          child: FeatureEmptyState(
            icon: Icons.receipt_long_outlined,
            title: 'No connected sales',
            message:
                'Connect a verified business membership to read actual committed transactions. This preview contains no sales.',
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
              _pendingReversal = null;
              _pendingReceipt = null;
              if (result is SaleReversal) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('Saved reversal confirmed by the server.'),
                  ),
                );
              }
              _load(_page?.offset ?? 0);
            },
          ),
        if (_pendingReversal != null &&
            _savedPending.every(
              (operation) => operation.requestId != _pendingReversal!.requestId,
            )) ...[
          OperationNotice(
            message:
                'A refund or void has an unconfirmed result. Resume the same request before submitting another reversal.',
            requestId: _pendingReversal!.requestId,
          ),
          const SizedBox(height: 10),
          OutlinedButton(
            key: const Key('sales-resume'),
            onPressed: !_busy
                ? () => _reverse(_pendingReceipt!, _pendingReversal!.kind)
                : null,
            child: const Text('Resume unconfirmed reversal'),
          ),
          const SizedBox(height: 16),
        ],
        SectionCard(
          child: DropdownButtonFormField<String>(
            key: ValueKey('sales-branch-$_branchId'),
            initialValue: _branchId,
            isExpanded: true,
            decoration: const InputDecoration(labelText: 'Branch'),
            items: _branches
                .map(
                  (branch) => DropdownMenuItem(
                    value: branch.id,
                    child: Text(branch.name, overflow: TextOverflow.ellipsis),
                  ),
                )
                .toList(),
            onChanged:
                !_busy && _pendingReversal == null && _savedPending.isEmpty
                ? (value) {
                    setState(() => _branchId = value);
                    _load(0);
                  }
                : null,
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
              icon: Icons.receipt_long_outlined,
              title: 'No committed sales',
              message: 'Sales appear after the server confirms checkout.',
              status: FeatureStatus.available,
            ),
          ),
        ...?_page?.items.map(
          (receipt) => Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: SectionCard(
              padding: 0,
              child: ListTile(
                key: Key('sale-${receipt.id}'),
                enabled: !_busy,
                onTap: () => _details(receipt),
                title: Text(receipt.receiptNumber),
                subtitle: Text(
                  '${manilaTime(receipt.createdAt)} · Asia/Manila\n${amountLabel(receipt.totalMinor, receipt.currency)}',
                ),
                trailing: const Icon(Icons.chevron_right),
              ),
            ),
          ),
        ),
        if (_page != null)
          OperationPager(
            prefix: 'sales',
            offset: _page!.offset,
            hasMore: _page!.hasMore,
            busy: _busy,
            onPage: _load,
          ),
      ],
    ],
  );
}

class _ReversalDialog extends StatefulWidget {
  const _ReversalDialog({
    required this.repository,
    required this.receipt,
    required this.kind,
    required this.shift,
    required this.pending,
    required this.onFrozen,
    required this.onResolved,
  });
  final CheckoutRepository repository;
  final SaleReceipt receipt;
  final SaleReversalKind kind;
  final Shift? shift;
  final ReversalRequest? pending;
  final ValueChanged<ReversalRequest> onFrozen;
  final VoidCallback onResolved;
  @override
  State<_ReversalDialog> createState() => _ReversalDialogState();
}

class _ReversalDialogState extends State<_ReversalDialog> {
  final _form = GlobalKey<FormState>();
  final _reason = TextEditingController();
  final Map<String, TextEditingController> _quantities = {};
  final Map<String, TextEditingController> _references = {};
  ReversalRequest? _request;
  RefundSelection? _selection;
  String? _selectionError;
  bool _saving = false, _confirmed = false, _returnStock = false;
  String? _error;
  @override
  void initState() {
    super.initState();
    _request = widget.pending;
    for (final item in widget.receipt.items) {
      if (item.refundableQuantity > 0) {
        _quantities[item.id] = TextEditingController(
          text: item.refundableQuantity.toString(),
        );
      }
    }
    for (final payment in widget.receipt.payments) {
      if (payment.method != CheckoutPaymentMethod.cash &&
          payment.refundableMinor > 0) {
        _references[payment.id] = TextEditingController();
      }
    }
    _refreshSelection();
  }

  @override
  void dispose() {
    _reason.dispose();
    for (final controller in _quantities.values) {
      controller.dispose();
    }
    for (final controller in _references.values) {
      controller.dispose();
    }
    super.dispose();
  }

  int _quantity(SaleItem item) {
    final text = _quantities[item.id]!.text.trim();
    if (!RegExp(r'^(0|[1-9]\d{0,6})$').hasMatch(text)) {
      throw const RepositoryFailure(
        RepositoryFailureType.validation,
        'Enter a whole-unit quantity, using 0 to skip this item.',
      );
    }
    final quantity = int.parse(text);
    if (quantity > item.refundableQuantity) {
      throw RepositoryFailure(
        RepositoryFailureType.validation,
        'At most ${item.refundableQuantity} remaining ${item.refundableQuantity == 1 ? 'unit' : 'units'} can be returned.',
      );
    }
    return quantity;
  }

  void _refreshSelection() {
    try {
      _selection = RefundSelection.calculate(
        receipt: widget.receipt,
        quantities: {
          for (final item in widget.receipt.items)
            if (item.refundableQuantity > 0) item.id: _quantity(item),
        },
      );
      _selectionError = null;
    } on RepositoryFailure catch (error) {
      _selection = null;
      _selectionError = error.message;
    }
  }

  void _selectionChanged(String _) => setState(() {
    _confirmed = false;
    _returnStock = false;
    _error = null;
    _refreshSelection();
  });

  Future<void> _submit() async {
    if (_saving) return;
    if (_request == null) {
      if (!_form.currentState!.validate()) return;
      _refreshSelection();
      if (_selection == null) {
        setState(() => _error = _selectionError);
        return;
      }
      if (_selection!.allocations.isNotEmpty && !_confirmed) {
        setState(
          () => _error =
              'Confirm that all listed payouts have been completed manually.',
        );
        return;
      }
      _request = ReversalRequest(
        branchId: widget.receipt.branchId,
        saleId: widget.receipt.id,
        kind: widget.kind,
        shiftId: widget.shift!.id,
        returnStock: _returnStock,
        reason: _reason.text.trim(),
        items: _selection!.items,
        payments: _selection!.allocations
            .map(
              (allocation) => ReversalPayment(
                originalPaymentId: allocation.originalPayment.id,
                amountMinor: allocation.amountMinor,
                manualConfirmed: true,
                reference: _references[allocation.originalPayment.id]?.text
                    .trim(),
              ),
            )
            .toList(),
      );
      widget.onFrozen(_request!);
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      final result = await widget.repository.reverseSale(_request!);
      widget.onResolved();
      if (mounted) Navigator.pop(context, result);
    } catch (error) {
      if (mounted) {
        setState(() {
          _error = operationMayBeUnconfirmed(error)
              ? '${operationError(error)} The payout may already be recorded. Retry this same request to recover the server result.'
              : operationError(error);
          if (!operationMayBeUnconfirmed(error)) {
            _request = null;
            widget.onResolved();
          }
        });
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final payoutTotal = _request == null
        ? _selection?.totalMinor
        : _request!.payments.fold<int>(
            0,
            (total, payment) => total + payment.amountMinor,
          );
    return PopScope(
      canPop: !_saving,
      child: AlertDialog(
        title: Text(
          widget.kind == SaleReversalKind.refund
              ? 'Refund sale items'
              : 'Void untouched sale',
        ),
        content: SizedBox(
          width: 520,
          child: SingleChildScrollView(
            child: Form(
              key: _form,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    widget.kind == SaleReversalKind.refund
                        ? 'Choose units from this original receipt. Enter 0 to skip an item. The original receipt stays unchanged.'
                        : 'Void returns every unit of this untouched sale. The original receipt stays unchanged.',
                  ),
                  const SizedBox(height: 12),
                  if (_request == null &&
                      widget.kind == SaleReversalKind.refund)
                    ...widget.receipt.items
                        .where((item) => item.refundableQuantity > 0)
                        .map(
                          (item) => Padding(
                            padding: const EdgeInsets.only(bottom: 12),
                            child: TextFormField(
                              key: Key('reversal-quantity-${item.id}'),
                              controller: _quantities[item.id],
                              enabled: !_saving,
                              keyboardType: TextInputType.number,
                              decoration: InputDecoration(
                                labelText: '${item.name} · return quantity',
                                helperText:
                                    '${item.refundableQuantity} of ${item.quantity} original units remain',
                              ),
                              validator: (_) =>
                                  operationValidation(() => _quantity(item)),
                              onChanged: _selectionChanged,
                            ),
                          ),
                        ),
                  if (_request != null)
                    ..._request!.items.map((selected) {
                      final original = widget.receipt.items.firstWhere(
                        (item) => item.id == selected.saleItemId,
                      );
                      return Text(
                        '${original.name} · ${selected.quantity} units',
                      );
                    }),
                  if (payoutTotal != null)
                    Text(
                      'Selected refund total: ${amountLabel(payoutTotal, widget.receipt.currency)}',
                      key: const Key('reversal-total'),
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                  const SizedBox(height: 8),
                  const Text(
                    'Amounts use the original tax-inclusive line totals. Final returned units receive any remaining cents.',
                    style: TextStyle(fontSize: 12),
                  ),
                  const SizedBox(height: 8),
                  if (_request == null) ...[
                    ...?_selection?.allocations.map(
                      (allocation) => Padding(
                        padding: const EdgeInsets.only(bottom: 10),
                        child: Text(
                          '${paymentMethodLabel(allocation.originalPayment.method)} payout: ${amountLabel(allocation.amountMinor, widget.receipt.currency)} · remaining source cap ${amountLabel(allocation.originalPayment.refundableMinor, widget.receipt.currency)}',
                          key: Key(
                            'reversal-payout-${allocation.originalPayment.id}',
                          ),
                        ),
                      ),
                    ),
                    if (_selection?.allocations.isNotEmpty ?? false)
                      const Text(
                        'Payouts use the original payment sources in payment ID order, within each remaining amount.',
                        style: TextStyle(fontSize: 12),
                      ),
                    if (_selection?.totalMinor == 0)
                      const Text(
                        'These selected units have no remaining financial value. No payout or payment reference is recorded.',
                      ),
                    if (_selectionError != null)
                      OperationNotice(message: _selectionError!, isError: true),
                  ] else ...[
                    ..._request!.payments.map((payment) {
                      final original = widget.receipt.payments.firstWhere(
                        (original) => original.id == payment.originalPaymentId,
                      );
                      return Text(
                        '${paymentMethodLabel(original.method)} payout: ${amountLabel(payment.amountMinor, widget.receipt.currency)}${payment.reference == null ? '' : ' · ${payment.reference}'}',
                      );
                    }),
                    Text('Reason: ${_request!.reason}'),
                    Text(
                      _request!.returnStock
                          ? 'Stock return confirmed for all selected units.'
                          : 'No stock return recorded.',
                    ),
                  ],
                  if (_request == null) ...[
                    const SizedBox(height: 12),
                    TextFormField(
                      key: const Key('reversal-reason'),
                      controller: _reason,
                      enabled: !_saving,
                      maxLength: 500,
                      maxLines: 2,
                      decoration: const InputDecoration(labelText: 'Reason'),
                      validator: (value) => operationValidation(
                        () => requiredText(
                          value ?? '',
                          'Reason',
                          500,
                          minimum: 8,
                        ),
                      ),
                    ),
                    ...?_selection?.allocations
                        .where(
                          (allocation) =>
                              allocation.originalPayment.method !=
                              CheckoutPaymentMethod.cash,
                        )
                        .map(
                          (allocation) => Padding(
                            padding: const EdgeInsets.only(top: 12),
                            child: TextFormField(
                              key: Key(
                                'reversal-reference-${allocation.originalPayment.id}',
                              ),
                              controller:
                                  _references[allocation.originalPayment.id],
                              enabled: !_saving,
                              maxLength: 120,
                              decoration: InputDecoration(
                                labelText:
                                    '${paymentMethodLabel(allocation.originalPayment.method)} manual reversal reference',
                              ),
                              validator: (value) => operationValidation(
                                () => requiredText(
                                  value ?? '',
                                  'Reversal reference',
                                  120,
                                  minimum: 3,
                                ),
                              ),
                            ),
                          ),
                        ),
                    if (_selection?.allocations.isNotEmpty ?? false)
                      CheckboxListTile(
                        contentPadding: EdgeInsets.zero,
                        controlAffinity: ListTileControlAffinity.leading,
                        title: const Text(
                          'All listed payouts have been completed manually',
                        ),
                        subtitle: const Text(
                          'No card or wallet provider reversal is requested by this app.',
                        ),
                        value: _confirmed,
                        onChanged: !_saving
                            ? (value) =>
                                  setState(() => _confirmed = value ?? false)
                            : null,
                      ),
                    CheckboxListTile(
                      contentPadding: EdgeInsets.zero,
                      controlAffinity: ListTileControlAffinity.leading,
                      title: const Text(
                        'Every selected unit physically returned to this branch',
                      ),
                      subtitle: const Text(
                        'Leave unchecked when the merchandise is not returned. Stock changes only when confirmed.',
                      ),
                      value: _returnStock,
                      onChanged: !_saving
                          ? (value) =>
                                setState(() => _returnStock = value ?? false)
                          : null,
                    ),
                  ] else ...[
                    OperationNotice(
                      message:
                          'This request is frozen. Retry sends the same quantities, payout evidence, reason and stock-return decision.',
                      requestId: _request!.requestId,
                    ),
                  ],
                  if (_error != null) ...[
                    const SizedBox(height: 12),
                    OperationNotice(message: _error!, isError: true),
                  ],
                  const SizedBox(height: 8),
                  const Text(
                    'Provider refunds and separate refund/void document output are Coming Soon.',
                    style: TextStyle(fontSize: 12),
                  ),
                ],
              ),
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: !_saving ? () => Navigator.pop(context) : null,
            child: Text(_request == null ? 'Cancel' : 'Keep pending and close'),
          ),
          FilledButton(
            key: const Key('reversal-submit'),
            onPressed: !_saving ? _submit : null,
            child: Text(
              _saving
                  ? 'Confirming…'
                  : _request != null
                  ? 'Retry same request'
                  : 'Record reversal',
            ),
          ),
        ],
      ),
    );
  }
}
