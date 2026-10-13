import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../app/config/feature_status.dart';
import '../../../core/operations/operation_journal.dart';
import '../../../core/security/app_role.dart';
import '../../../core/widgets/status_widgets.dart';
import '../../administration/domain/administration_models.dart';
import '../../catalog/domain/catalog_models.dart';
import '../../catalog/domain/catalog_repository.dart';
import '../../catalog/domain/repository_support.dart';
import '../../inventory/presentation/operations_ui_support.dart';
import '../../people/domain/people_models.dart';
import '../../people/domain/people_repository.dart';
import '../domain/purchase_models.dart';
import '../domain/purchase_repository.dart';

class PurchasesPage extends StatefulWidget {
  const PurchasesPage({
    super.key,
    this.repository,
    this.peopleRepository,
    this.catalogRepository,
    this.role,
    this.isPreview = true,
  });
  final PurchaseRepository? repository;
  final PeopleRepository? peopleRepository;
  final CatalogRepository? catalogRepository;
  final AppRole? role;
  final bool isPreview;
  @override
  State<PurchasesPage> createState() => _PurchasesPageState();
}

class _FrozenAction {
  const _FrozenAction(this.requestId, this.label, this.submit);
  final String requestId, label;
  final Future<PurchaseMutationResult> Function() submit;
}

class _PurchasesPageState extends State<PurchasesPage> {
  final _query = TextEditingController();
  List<BranchOption> _branches = [];
  String? _branchId;
  PurchaseContext? _context;
  DataPage<PurchaseOrderSummary>? _orders;
  List<PendingOperation> _pending = [];
  PurchaseOrderStatus? _filter;
  PurchaseOrder? _selected;
  _FrozenAction? _frozen;
  bool _busy = false;
  String? _error, _notice;
  int _offset = 0, _generation = 0;
  bool get _connected =>
      !widget.isPreview &&
      widget.repository != null &&
      widget.peopleRepository != null &&
      widget.catalogRepository != null &&
      (widget.role?.allows(AppPermission.managePurchases) ?? false);
  bool get _hasPending => _pending.isNotEmpty || _frozen != null;

  @override
  void initState() {
    super.initState();
    if (_connected) unawaited(_load());
  }

  @override
  void didUpdateWidget(PurchasesPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.repository != widget.repository ||
        oldWidget.peopleRepository != widget.peopleRepository ||
        oldWidget.catalogRepository != widget.catalogRepository ||
        oldWidget.role != widget.role ||
        oldWidget.isPreview != widget.isPreview) {
      _generation++;
      _branches = [];
      _branchId = null;
      _context = null;
      _orders = null;
      _pending = [];
      _selected = null;
      _frozen = null;
      _error = null;
      _notice = null;
      if (_connected) unawaited(_load());
    }
  }

  Future<void> _load({int? offset}) async {
    if (!_connected) return;
    final generation = ++_generation;
    final repository = widget.repository!;
    setState(() {
      _busy = true;
      _error = null;
      _orders = null;
      _context = null;
      if (offset != null) _offset = offset;
    });
    try {
      final branches = await widget.peopleRepository!.listBranches();
      if (!mounted ||
          generation != _generation ||
          repository != widget.repository) {
        return;
      }
      _branches = branches;
      if (!branches.any((branch) => branch.id == _branchId)) {
        _branchId = branches.firstOrNull?.id;
      }
      final pending = await repository.pendingMutations();
      if (!mounted ||
          generation != _generation ||
          repository != widget.repository) {
        return;
      }
      _pending = pending;
      final branch = _branchId;
      if (branch == null) {
        setState(() => _busy = false);
        return;
      }
      final context = await repository.context(branch);
      final orders = await repository.listOrders(
        branchId: branch,
        status: _filter,
        query: _query.text.trim(),
        page: PageRequest(offset: _offset, limit: 20),
      );
      final selected = _selected == null
          ? null
          : await repository.getOrder(
              branchId: branch,
              orderId: _selected!.summary.id,
            );
      if (!mounted ||
          generation != _generation ||
          branch != _branchId ||
          repository != widget.repository) {
        return;
      }
      setState(() {
        _context = context;
        _orders = orders;
        _selected = selected;
        _busy = false;
      });
    } catch (error) {
      if (mounted &&
          generation == _generation &&
          repository == widget.repository) {
        setState(() {
          _error = operationError(error);
          _busy = false;
        });
      }
    }
  }

  Future<void> _openOrder(PurchaseOrderSummary summary) async {
    if (_busy) return;
    final generation = ++_generation;
    setState(() {
      _busy = true;
      _error = null;
      _selected = null;
    });
    try {
      final order = await widget.repository!.getOrder(
        branchId: summary.branchId,
        orderId: summary.id,
      );
      if (mounted &&
          generation == _generation &&
          _branchId == summary.branchId) {
        setState(() => _selected = order);
      }
    } catch (error) {
      if (mounted && generation == _generation) {
        setState(() => _error = operationError(error));
      }
    } finally {
      if (mounted && generation == _generation) setState(() => _busy = false);
    }
  }

  Future<void> _commit(_FrozenAction action) async {
    if (_busy) return;
    final generation = _generation;
    final wasUnconfirmed = _frozen?.requestId == action.requestId;
    setState(() {
      _frozen = action;
      _busy = true;
      _error = null;
      _notice = null;
    });
    try {
      await action.submit();
      if (!mounted || generation != _generation) return;
      setState(() {
        _frozen = null;
        _notice = '${action.label} confirmed by the server.';
      });
    } catch (error) {
      if (!mounted || generation != _generation) return;
      setState(() {
        _error = operationError(error);
        // A later local authorization denial cannot resolve an earlier
        // unknown server outcome or release its original delivery request.
        if (!wasUnconfirmed && !operationMayBeUnconfirmed(error)) {
          _frozen = null;
        }
      });
    } finally {
      if (mounted && generation == _generation) setState(() => _busy = false);
    }
    if (mounted && generation == _generation) {
      final error = _error;
      await _load();
      if (mounted && error != null) setState(() => _error = error);
    }
  }

  Future<void> _create() async {
    final contextValue = _context;
    if (_busy || _hasPending || contextValue == null) return;
    final repository = widget.repository!;
    final generation = _generation;
    final request = await showDialog<CreatePurchaseRequest>(
      context: context,
      builder: (context) => _CreateOrderDialog(
        contextValue: contextValue,
        people: widget.peopleRepository!,
        catalog: widget.catalogRepository!,
      ),
    );
    if (!mounted ||
        generation != _generation ||
        request == null ||
        repository != widget.repository ||
        request.branchId != _branchId) {
      return;
    }
    await _commit(
      _FrozenAction(
        request.requestId,
        'Purchase order',
        () => repository.create(request),
      ),
    );
  }

  Future<void> _receive() async {
    final order = _selected;
    if (_busy || _hasPending || order == null || order.summary.status.closed) {
      return;
    }
    final repository = widget.repository!;
    final generation = _generation;
    final request = await showDialog<ReceivePurchaseRequest>(
      context: context,
      builder: (context) => _ReceiveOrderDialog(order: order),
    );
    if (!mounted ||
        generation != _generation ||
        request == null ||
        repository != widget.repository ||
        request.branchId != _branchId) {
      return;
    }
    await _commit(
      _FrozenAction(
        request.requestId,
        'Physical stock receipt',
        () => repository.receive(request),
      ),
    );
  }

  Future<void> _cancel() async {
    final order = _selected;
    if (_busy || _hasPending || order == null || order.summary.status.closed) {
      return;
    }
    final repository = widget.repository!;
    final generation = _generation;
    final request = await showDialog<CancelPurchaseRequest>(
      context: context,
      builder: (context) => _CancelOrderDialog(order: order),
    );
    if (!mounted ||
        generation != _generation ||
        repository != widget.repository ||
        request == null ||
        request.branchId != _branchId) {
      return;
    }
    await _commit(
      _FrozenAction(
        request.requestId,
        'Remaining quantity cancellation',
        () => repository.cancelRemaining(request),
      ),
    );
  }

  @override
  void dispose() {
    _generation++;
    _query.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => ListView(
    padding: const EdgeInsets.all(24),
    children: [
      PageHeading(
        title: 'Purchases',
        subtitle:
            'Record orders, receive physical stock and preserve delivery history.',
        trailing: StatusPill(
          status: _connected
              ? FeatureStatus.available
              : FeatureStatus.notYetConnected,
        ),
      ),
      const SizedBox(height: 20),
      if (!_connected)
        SectionCard(
          child: FeatureEmptyState(
            icon: Icons.shopping_bag_outlined,
            title: widget.role == AppRole.cashier
                ? 'Purchase access is restricted'
                : 'No connected purchase orders',
            message:
                'Connect an authorized business to record real orders and deliveries. The design preview has no suppliers, orders or stock receipts.',
            status: FeatureStatus.notYetConnected,
          ),
        )
      else ...[
        if (_notice != null)
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: OperationNotice(message: _notice!),
          ),
        if (_pending.isNotEmpty)
          PendingOperationsPanel(
            operations: _pending,
            busy: _busy,
            retry: widget.repository!.retryPending,
            onSettled: (result) {
              if (result != null) _frozen = null;
              unawaited(_load());
            },
          ),
        if (_frozen != null &&
            !_pending.any(
              (operation) => operation.requestId == _frozen!.requestId,
            )) ...[
          OperationNotice(
            message:
                'The ${_frozen!.label.toLowerCase()} result is unconfirmed. Preserve this request and do not repeat the physical delivery.',
            requestId: _frozen!.requestId,
          ),
          OutlinedButton(
            onPressed: _busy ? null : () => _commit(_frozen!),
            child: const Text('Retry original purchase request'),
          ),
        ],
        SectionCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              DropdownButtonFormField<String>(
                key: ValueKey(_branchId),
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
                onChanged: _busy
                    ? null
                    : (value) {
                        setState(() {
                          _branchId = value;
                          _selected = null;
                          _offset = 0;
                        });
                        unawaited(_load());
                      },
              ),
              const SizedBox(height: 16),
              DropdownButtonFormField<PurchaseOrderStatus>(
                key: ValueKey(_filter),
                initialValue: _filter,
                isExpanded: true,
                decoration: const InputDecoration(labelText: 'Order status'),
                items: [
                  const DropdownMenuItem(
                    value: null,
                    child: Text('All orders'),
                  ),
                  ...PurchaseOrderStatus.values.map(
                    (status) => DropdownMenuItem(
                      value: status,
                      child: Text(status.label),
                    ),
                  ),
                ],
                onChanged: _busy
                    ? null
                    : (value) {
                        setState(() => _filter = value);
                        unawaited(_load(offset: 0));
                      },
              ),
              const SizedBox(height: 16),
              TextField(
                controller: _query,
                enabled: !_busy,
                decoration: const InputDecoration(
                  labelText: 'Search supplier or order reference',
                ),
                onSubmitted: (_) => _load(offset: 0),
              ),
              const SizedBox(height: 16),
              Wrap(
                spacing: 12,
                runSpacing: 12,
                children: [
                  FilledButton.icon(
                    key: const Key('purchase-create'),
                    onPressed: _busy || _hasPending || _context == null
                        ? null
                        : _create,
                    icon: const Icon(Icons.add),
                    label: const Text('Record purchase order'),
                  ),
                  OutlinedButton.icon(
                    onPressed: _busy ? null : () => _load(),
                    icon: const Icon(Icons.refresh),
                    label: const Text('Refresh'),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              const Text(
                'Recording an order does not pay or email the supplier. Deliveries require separate physical receipt confirmation.',
              ),
            ],
          ),
        ),
        if (_busy)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 12),
            child: LinearProgressIndicator(),
          ),
        if (_error != null)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 12),
            child: OperationNotice(message: _error!, isError: true),
          ),
        if (!_busy && _orders?.items.isEmpty == true)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 20),
            child: Text('No purchase orders match this branch and search.'),
          ),
        if (_branches.isEmpty && !_busy)
          const Text('No assigned active branches are available.'),
        for (final order in _orders?.items ?? <PurchaseOrderSummary>[])
          Padding(
            padding: const EdgeInsets.only(top: 12),
            child: SectionCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    order.supplierName,
                    style: const TextStyle(fontWeight: FontWeight.bold),
                  ),
                  Text(order.status.label),
                  Text(
                    'Ordered ${amountLabel(order.orderedTotalMinor, order.currency)} · Received ${amountLabel(order.receivedTotalMinor, order.currency)}',
                  ),
                  Text('${manilaTime(order.createdAt)} · Asia/Manila'),
                  if (order.reference != null)
                    Text('Reference: ${order.reference}'),
                  OutlinedButton(
                    key: Key('purchase-open-${order.id}'),
                    onPressed: _busy ? null : () => _openOrder(order),
                    child: const Text('View order and deliveries'),
                  ),
                ],
              ),
            ),
          ),
        if (_orders != null)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 16),
            child: OperationPager(
              prefix: 'purchase',
              offset: _offset,
              hasMore: _orders!.hasMore,
              busy: _busy,
              onPage: (offset) => _load(offset: offset),
            ),
          ),
        if (_selected != null)
          _OrderDetails(
            key: ValueKey(
              '${_selected!.summary.id}:${_selected!.summary.revision}',
            ),
            order: _selected!,
            repository: widget.repository!,
            busy: _busy || _hasPending,
            onReceive: _receive,
            onCancel: _cancel,
          ),
      ],
    ],
  );
}

class _OrderDetails extends StatefulWidget {
  const _OrderDetails({
    super.key,
    required this.order,
    required this.repository,
    required this.busy,
    required this.onReceive,
    required this.onCancel,
  });
  final PurchaseOrder order;
  final PurchaseRepository repository;
  final bool busy;
  final VoidCallback onReceive, onCancel;
  @override
  State<_OrderDetails> createState() => _OrderDetailsState();
}

class _OrderDetailsState extends State<_OrderDetails> {
  DataPage<PurchaseReceiptSummary>? _receipts;
  String? _error;
  bool _busy = false;
  int _offset = 0, _generation = 0;
  @override
  void initState() {
    super.initState();
    unawaited(_load(0));
  }

  Future<void> _load(int offset) async {
    final generation = ++_generation;
    setState(() {
      _busy = true;
      _error = null;
      _offset = offset;
      _receipts = null;
    });
    try {
      final page = await widget.repository.listReceipts(
        branchId: widget.order.summary.branchId,
        orderId: widget.order.summary.id,
        page: PageRequest(offset: offset, limit: 20),
      );
      if (mounted && generation == _generation) {
        setState(() => _receipts = page);
      }
    } catch (error) {
      if (mounted && generation == _generation) {
        setState(() => _error = operationError(error));
      }
    } finally {
      if (mounted && generation == _generation) setState(() => _busy = false);
    }
  }

  Future<void> _receipt(PurchaseReceiptSummary summary) async {
    setState(() {
      _busy = true;
      _error = null;
    });
    final generation = _generation;
    try {
      final receipt = await widget.repository.getReceipt(
        branchId: summary.branchId,
        receiptId: summary.id,
      );
      if (!mounted || generation != _generation) return;
      await showDialog<void>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Confirmed delivery receipt'),
          content: SizedBox(
            width: 620,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Received ${amountLabel(receipt.summary.receivedTotalMinor, receipt.summary.currency)}',
                  ),
                  Text(
                    '${manilaTime(receipt.summary.receivedAt)} · Asia/Manila',
                  ),
                  Text('Reason: ${receipt.reason}'),
                  if (receipt.summary.reference != null)
                    Text('Reference: ${receipt.summary.reference}'),
                  const SizedBox(height: 16),
                  for (final item in receipt.items) ...[
                    Text(
                      '${widget.order.items.where((line) => line.id == item.orderItemId).firstOrNull?.productName ?? item.productId} · ${item.quantity} units',
                    ),
                    Text(
                      'Original unit cost ${amountLabel(item.unitCostMinor, receipt.summary.currency)} · ${amountLabel(item.lineCostMinor, receipt.summary.currency)}',
                    ),
                    Text(
                      'Stock balance after: ${item.balanceAfter} · revision ${item.stockRevision}',
                    ),
                    SelectableText(
                      'Movement: ${item.movementId}',
                      style: const TextStyle(fontSize: 12),
                    ),
                    const SizedBox(height: 12),
                  ],
                  const Text(
                    'This records physically received stock. It does not confirm supplier payment.',
                  ),
                ],
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
    } catch (error) {
      if (mounted && generation == _generation) {
        setState(() => _error = operationError(error));
      }
    } finally {
      if (mounted && generation == _generation) setState(() => _busy = false);
    }
  }

  @override
  void dispose() {
    _generation++;
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final order = widget.order;
    final summary = order.summary;
    return SectionCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'Order details · ${summary.supplierName}',
            style: Theme.of(context).textTheme.titleLarge,
          ),
          Text(summary.status.label),
          SelectableText(
            'Order: ${summary.id}',
            style: const TextStyle(fontSize: 12),
          ),
          Text('Reason: ${order.reason}'),
          const SizedBox(height: 16),
          for (final item in order.items)
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '${item.productName} · ${item.sku}',
                    style: const TextStyle(fontWeight: FontWeight.bold),
                  ),
                  Text(
                    'Ordered ${item.orderedQuantity} · received ${item.receivedQuantity} · cancelled ${item.cancelledQuantity} · remaining ${item.remainingQuantity} ${item.unit}',
                  ),
                  Text(
                    '${amountLabel(item.unitCostMinor, summary.currency)} per unit · ${amountLabel(item.lineCostMinor, summary.currency)} ordered',
                  ),
                ],
              ),
            ),
          if (!summary.status.closed)
            Wrap(
              spacing: 12,
              runSpacing: 12,
              children: [
                FilledButton(
                  key: const Key('purchase-receive'),
                  onPressed: widget.busy || _busy ? null : widget.onReceive,
                  child: const Text('Receive physical stock'),
                ),
                OutlinedButton(
                  key: const Key('purchase-cancel'),
                  onPressed: widget.busy || _busy ? null : widget.onCancel,
                  child: const Text('Cancel remaining quantities'),
                ),
              ],
            ),
          if (order.cancellation != null)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 12),
              child: Text(
                'Remaining quantities cancelled: ${order.cancellation!.reason}',
              ),
            ),
          const SizedBox(height: 20),
          Text(
            'Delivery history (${order.receiptCount})',
            style: Theme.of(context).textTheme.titleMedium,
          ),
          if (_busy) const LinearProgressIndicator(),
          if (_error != null) OperationNotice(message: _error!, isError: true),
          if (!_busy && _receipts?.items.isEmpty == true)
            const Text('No deliveries have been recorded.'),
          for (final receipt in _receipts?.items ?? <PurchaseReceiptSummary>[])
            ListTile(
              contentPadding: EdgeInsets.zero,
              title: Text(
                amountLabel(receipt.receivedTotalMinor, receipt.currency),
              ),
              subtitle: Text(
                '${manilaTime(receipt.receivedAt)} · ${receipt.reference ?? 'No delivery reference'}',
              ),
              trailing: const Icon(Icons.chevron_right),
              onTap: _busy ? null : () => _receipt(receipt),
            ),
          if (_receipts != null)
            OperationPager(
              prefix: 'purchase-receipts',
              offset: _offset,
              hasMore: _receipts!.hasMore,
              busy: _busy,
              onPage: _load,
            ),
        ],
      ),
    );
  }
}

class _PagedPicker<T> extends StatefulWidget {
  const _PagedPicker({
    required this.title,
    required this.load,
    required this.name,
    required this.subtitle,
    this.allowed,
  });
  final String title;
  final Future<DataPage<T>> Function(String, PageRequest) load;
  final String Function(T) name, subtitle;
  final bool Function(T)? allowed;
  @override
  State<_PagedPicker<T>> createState() => _PagedPickerState<T>();
}

class _PagedPickerState<T> extends State<_PagedPicker<T>> {
  final _query = TextEditingController();
  DataPage<T>? _page;
  String? _error;
  bool _busy = false;
  int _offset = 0, _generation = 0;
  @override
  void initState() {
    super.initState();
    unawaited(_load(0));
  }

  Future<void> _load(int offset) async {
    final generation = ++_generation;
    setState(() {
      _busy = true;
      _error = null;
      _page = null;
      _offset = offset;
    });
    try {
      final page = await widget.load(
        _query.text.trim(),
        PageRequest(offset: offset, limit: 20),
      );
      if (mounted && generation == _generation) setState(() => _page = page);
    } catch (error) {
      if (mounted && generation == _generation) {
        setState(() => _error = operationError(error));
      }
    } finally {
      if (mounted && generation == _generation) setState(() => _busy = false);
    }
  }

  @override
  void dispose() {
    _generation++;
    _query.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: Text(widget.title),
    content: SizedBox(
      width: 500,
      height: MediaQuery.sizeOf(context).height * .55,
      child: Column(
        children: [
          TextField(
            controller: _query,
            decoration: const InputDecoration(labelText: 'Search'),
            onSubmitted: (_) => _load(0),
          ),
          TextButton(
            onPressed: _busy ? null : () => _load(0),
            child: const Text('Search'),
          ),
          if (_busy) const LinearProgressIndicator(),
          if (_error != null) Text(_error!),
          Expanded(
            child: ListView(
              children: [
                if (!_busy && _page?.items.isEmpty == true)
                  const Text('No active matches. Try another search.'),
                for (final item in _page?.items ?? <T>[])
                  ListTile(
                    title: Text(widget.name(item)),
                    subtitle: Text(widget.subtitle(item)),
                    enabled: !_busy && (widget.allowed?.call(item) ?? true),
                    onTap: () => Navigator.pop(context, item),
                  ),
              ],
            ),
          ),
          if (_page != null)
            OperationPager(
              offset: _offset,
              hasMore: _page!.hasMore,
              busy: _busy,
              onPage: _load,
            ),
        ],
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('Cancel'),
      ),
    ],
  );
}

class _CancelOrderDialog extends StatefulWidget {
  const _CancelOrderDialog({required this.order});
  final PurchaseOrder order;

  @override
  State<_CancelOrderDialog> createState() => _CancelOrderDialogState();
}

class _CancelOrderDialogState extends State<_CancelOrderDialog> {
  final _reason = TextEditingController();
  String? _error;

  void _submit() {
    try {
      final reason = requiredText(
        _reason.text,
        'Cancellation reason',
        1000,
        minimum: 3,
      );
      Navigator.pop(
        context,
        CancelPurchaseRequest(
          branchId: widget.order.summary.branchId,
          orderId: widget.order.summary.id,
          expectedRevision: widget.order.summary.revision,
          reason: reason,
        ),
      );
    } on RepositoryFailure catch (failure) {
      setState(() => _error = failure.message);
    }
  }

  @override
  void dispose() {
    _reason.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('Cancel remaining quantities'),
    content: SizedBox(
      width: 440,
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text(
              'This closes only the quantities still outstanding. Previously received stock and its receipts remain recorded. No supplier payment is refunded.',
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _reason,
              maxLength: 1000,
              decoration: const InputDecoration(
                labelText: 'Cancellation reason',
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
        child: const Text('Keep order'),
      ),
      FilledButton(onPressed: _submit, child: const Text('Cancel remaining')),
    ],
  );
}

class _DraftLine {
  _DraftLine(this.product)
    : cost = TextEditingController(
        text: Money.formatMinor(product.costMinor ?? 0),
      );
  final Product product;
  final quantity = TextEditingController(text: '1');
  final TextEditingController cost;
  void dispose() {
    quantity.dispose();
    cost.dispose();
  }
}

class _CreateOrderDialog extends StatefulWidget {
  const _CreateOrderDialog({
    required this.contextValue,
    required this.people,
    required this.catalog,
  });
  final PurchaseContext contextValue;
  final PeopleRepository people;
  final CatalogRepository catalog;
  @override
  State<_CreateOrderDialog> createState() => _CreateOrderDialogState();
}

class _CreateOrderDialogState extends State<_CreateOrderDialog> {
  Supplier? _supplier;
  final _lines = <_DraftLine>[];
  final _reference = TextEditingController(), _reason = TextEditingController();
  String? _error;
  bool _confirmed = false;
  Future<void> _supplierPick() async {
    final supplier = await showDialog<Supplier>(
      context: context,
      builder: (context) => _PagedPicker<Supplier>(
        title: 'Choose active supplier',
        load: (query, page) => widget.people.listSuppliers(
          query: query,
          active: true,
          branchId: widget.contextValue.branchId,
          page: page,
        ),
        name: (supplier) => supplier.name,
        subtitle: (supplier) => supplier.contactName ?? 'Active supplier',
      ),
    );
    if (mounted && supplier != null) setState(() => _supplier = supplier);
  }

  Future<void> _productPick() async {
    final product = await showDialog<Product>(
      context: context,
      builder: (context) => _PagedPicker<Product>(
        title: 'Choose active product',
        load: (query, page) => widget.catalog.searchProducts(
          filter: ProductFilter(query: query, active: true),
          page: page,
        ),
        name: (product) => product.name,
        subtitle: (product) => '${product.sku} · ${product.currency}',
        allowed: (product) => product.currency == widget.contextValue.currency,
      ),
    );
    if (!mounted || product == null) return;
    if (_lines.any((line) => line.product.id == product.id)) {
      setState(
        () => _error =
            'This product is already listed. Adjust its existing quantity.',
      );
      return;
    }
    setState(() {
      _error = null;
      _lines.add(_DraftLine(product));
    });
  }

  void _submit() {
    try {
      if (_supplier == null || _lines.isEmpty || !_confirmed) {
        throw const RepositoryFailure(
          RepositoryFailureType.validation,
          'Choose a supplier and at least one product, then confirm this records an unpaid order.',
        );
      }
      final items = _lines
          .map(
            (line) => PurchaseCreateItem(
              productId: line.product.id,
              expectedRevision: line.product.revision,
              quantity: wholeUnits(line.quantity.text),
              unitCostMinor: Money.parseMinor(line.cost.text),
            ),
          )
          .toList();
      purchaseTotal(
        items.map(
          (item) => purchaseLineCost(item.quantity, item.unitCostMinor),
        ),
      );
      Navigator.pop(
        context,
        CreatePurchaseRequest(
          branchId: widget.contextValue.branchId,
          supplierId: _supplier!.id,
          expectedSupplierRevision: _supplier!.revision,
          expectedSettingsRevision: widget.contextValue.settingsRevision,
          currency: widget.contextValue.currency,
          items: items,
          reference: optionalText(_reference.text, 'Order reference', 120),
          reason: requiredText(_reason.text, 'Order reason', 1000, minimum: 3),
        ),
      );
    } on RepositoryFailure catch (error) {
      setState(() => _error = error.message);
    }
  }

  @override
  void dispose() {
    for (final line in _lines) {
      line.dispose();
    }
    _reference.dispose();
    _reason.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('Record purchase order'),
    content: SizedBox(
      width: 680,
      height: MediaQuery.sizeOf(context).height * .65,
      child: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              '${widget.contextValue.branchName} · ${widget.contextValue.currency}',
            ),
            const Text(
              'Submitted lines and costs are permanent. This does not pay or email the supplier.',
            ),
            const SizedBox(height: 16),
            OutlinedButton(
              onPressed: _supplierPick,
              child: Text(_supplier?.name ?? 'Choose supplier'),
            ),
            const SizedBox(height: 12),
            for (final line in _lines)
              Padding(
                padding: const EdgeInsets.only(bottom: 16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text('${line.product.name} · ${line.product.sku}'),
                    TextField(
                      controller: line.quantity,
                      keyboardType: TextInputType.number,
                      inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                      decoration: const InputDecoration(
                        labelText: 'Ordered whole units',
                      ),
                    ),
                    TextField(
                      controller: line.cost,
                      keyboardType: const TextInputType.numberWithOptions(
                        decimal: true,
                      ),
                      decoration: InputDecoration(
                        labelText:
                            'Recorded unit cost (${widget.contextValue.currency})',
                      ),
                    ),
                    TextButton(
                      onPressed: () {
                        setState(() => _lines.remove(line));
                        line.dispose();
                      },
                      child: const Text('Remove product'),
                    ),
                  ],
                ),
              ),
            OutlinedButton.icon(
              onPressed: _lines.length < 100 ? _productPick : null,
              icon: const Icon(Icons.add),
              label: const Text('Add product'),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _reference,
              maxLength: 120,
              decoration: const InputDecoration(
                labelText: 'Order reference (optional)',
              ),
            ),
            TextField(
              controller: _reason,
              maxLength: 1000,
              decoration: const InputDecoration(labelText: 'Order reason'),
            ),
            CheckboxListTile(
              contentPadding: EdgeInsets.zero,
              value: _confirmed,
              onChanged: (value) => setState(() => _confirmed = value ?? false),
              title: const Text(
                'I confirm this records an unpaid order; no supplier payment or email is sent.',
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
        child: const Text('Discard unsaved order'),
      ),
      FilledButton(
        onPressed: _submit,
        child: const Text('Submit immutable order'),
      ),
    ],
  );
}

class _ReceiveOrderDialog extends StatefulWidget {
  const _ReceiveOrderDialog({required this.order});
  final PurchaseOrder order;
  @override
  State<_ReceiveOrderDialog> createState() => _ReceiveOrderDialogState();
}

class _ReceiveOrderDialogState extends State<_ReceiveOrderDialog> {
  final _quantities = <String, TextEditingController>{};
  final _reviewed = <String>{};
  final _reference = TextEditingController(), _reason = TextEditingController();
  String? _error;
  bool _confirmed = false;
  @override
  void initState() {
    super.initState();
    for (final line in widget.order.items.where(
      (line) => line.remainingQuantity > 0,
    )) {
      _quantities[line.id] = TextEditingController(text: '0');
    }
  }

  void _submit() {
    try {
      if (!_confirmed) {
        throw const RepositoryFailure(
          RepositoryFailureType.validation,
          'Confirm that the entered quantities were physically received.',
        );
      }
      final items = <PurchaseReceiveItem>[];
      for (final line in widget.order.items.where(
        (line) => line.remainingQuantity > 0,
      )) {
        final text = _quantities[line.id]!.text.trim();
        if (text == '0' || text.isEmpty) continue;
        final quantity = wholeUnits(text);
        if (quantity > line.remainingQuantity) {
          throw RepositoryFailure(
            RepositoryFailureType.validation,
            'Receive at most ${line.remainingQuantity} units of ${line.productName}.',
          );
        }
        if (!_reviewed.contains(line.id) || !line.currentProductActive) {
          throw RepositoryFailure(
            RepositoryFailureType.validation,
            'Review the current catalog product for ${line.productName} before receiving it.',
          );
        }
        items.add(
          PurchaseReceiveItem(
            orderItemId: line.id,
            quantity: quantity,
            expectedProductRevision: line.currentProductRevision,
          ),
        );
      }
      if (items.isEmpty) {
        throw const RepositoryFailure(
          RepositoryFailureType.validation,
          'Enter at least one physically received quantity.',
        );
      }
      Navigator.pop(
        context,
        ReceivePurchaseRequest(
          branchId: widget.order.summary.branchId,
          orderId: widget.order.summary.id,
          expectedRevision: widget.order.summary.revision,
          items: items,
          reference: optionalText(_reference.text, 'Delivery reference', 120),
          reason: requiredText(
            _reason.text,
            'Receiving reason',
            1000,
            minimum: 3,
          ),
        ),
      );
    } on RepositoryFailure catch (error) {
      setState(() => _error = error.message);
    }
  }

  @override
  void dispose() {
    for (final value in _quantities.values) {
      value.dispose();
    }
    _reference.dispose();
    _reason.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('Receive physical stock'),
    content: SizedBox(
      width: 680,
      height: MediaQuery.sizeOf(context).height * .65,
      child: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text(
              'Enter only goods physically counted in this delivery. Original order costs and currency remain fixed. This does not pay the supplier.',
            ),
            const SizedBox(height: 16),
            for (final line in widget.order.items.where(
              (line) => line.remainingQuantity > 0,
            ))
              Padding(
                padding: const EdgeInsets.only(bottom: 20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text('${line.productName} · ${line.sku}'),
                    Text(
                      '${line.remainingQuantity} ${line.unit} remaining · original unit cost ${amountLabel(line.unitCostMinor, widget.order.summary.currency)}',
                    ),
                    Text(
                      'Current catalog: ${line.currentProductName} · ${line.currentSku} · ${line.currentUnit} · ${line.currentCurrency} · revision ${line.currentProductRevision}',
                    ),
                    if (!line.currentProductActive)
                      const Text(
                        'This product is inactive and cannot be received.',
                      ),
                    CheckboxListTile(
                      contentPadding: EdgeInsets.zero,
                      value: _reviewed.contains(line.id),
                      onChanged: !line.currentProductActive
                          ? null
                          : (value) => setState(() {
                              if (value == true) {
                                _reviewed.add(line.id);
                              } else {
                                _reviewed.remove(line.id);
                              }
                            }),
                      title: const Text(
                        'I reviewed this current catalog product.',
                      ),
                    ),
                    TextField(
                      key: Key('purchase-receive-quantity-${line.id}'),
                      controller: _quantities[line.id],
                      keyboardType: TextInputType.number,
                      inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                      decoration: const InputDecoration(
                        labelText: 'Physically received whole units',
                      ),
                    ),
                  ],
                ),
              ),
            TextField(
              controller: _reference,
              maxLength: 120,
              decoration: const InputDecoration(
                labelText: 'Delivery reference (optional)',
              ),
            ),
            TextField(
              controller: _reason,
              maxLength: 1000,
              decoration: const InputDecoration(labelText: 'Receiving reason'),
            ),
            CheckboxListTile(
              contentPadding: EdgeInsets.zero,
              value: _confirmed,
              onChanged: (value) => setState(() => _confirmed = value ?? false),
              title: const Text(
                'I counted and physically received these goods. I will not record this delivery twice.',
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
        onPressed: _submit,
        child: const Text('Confirm physical receipt'),
      ),
    ],
  );
}
