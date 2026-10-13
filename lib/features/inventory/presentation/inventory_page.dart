import 'package:flutter/material.dart';

import '../../../app/config/feature_status.dart';
import '../../../core/operations/operation_journal.dart';
import '../../../core/security/app_role.dart';
import '../../../core/widgets/status_widgets.dart';
import '../../administration/domain/administration_models.dart';
import '../../catalog/domain/repository_support.dart';
import '../../checkout/domain/checkout_models.dart';
import '../../people/domain/people_models.dart';
import '../../people/domain/people_repository.dart';
import '../domain/inventory_models.dart';
import '../domain/inventory_repository.dart';
import 'operations_ui_support.dart';

enum _InventoryView { balances, ledger }

class InventoryPage extends StatefulWidget {
  const InventoryPage({
    this.repository,
    this.peopleRepository,
    this.role,
    this.isPreview = true,
    super.key,
  });
  final InventoryRepository? repository;
  final PeopleRepository? peopleRepository;
  final AppRole? role;
  final bool isPreview;
  @override
  State<InventoryPage> createState() => _InventoryPageState();
}

class _InventoryPageState extends State<InventoryPage> {
  final _search = TextEditingController();
  List<BranchOption> _branches = const [];
  String? _branchId, _error, _productFilter, _productFilterName;
  DataPage<PosProduct>? _balances;
  DataPage<StockMovement>? _movements;
  _InventoryView _view = _InventoryView.balances;
  List<PendingOperation> _savedPending = const [];
  ReceiveStockRequest? _pendingReceive;
  AdjustStockRequest? _pendingAdjust;
  PosProduct? _pendingAdjustProduct;
  bool _busy = false;
  int _generation = 0;
  bool get _connected =>
      !widget.isPreview &&
      widget.repository != null &&
      widget.peopleRepository != null &&
      (widget.role?.allows(AppPermission.viewInventory) ?? false);
  bool get _mayAdjust =>
      _connected &&
      (widget.role == AppRole.owner ||
          widget.role == AppRole.admin ||
          widget.role == AppRole.manager);
  bool get _hasPending =>
      _savedPending.isNotEmpty ||
      _pendingReceive != null ||
      _pendingAdjust != null;
  int get _offset => _view == _InventoryView.balances
      ? (_balances?.offset ?? 0)
      : (_movements?.offset ?? 0);

  @override
  void initState() {
    super.initState();
    if (_connected) _load(0);
  }

  @override
  void didUpdateWidget(covariant InventoryPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.repository != widget.repository ||
        oldWidget.peopleRepository != widget.peopleRepository ||
        oldWidget.role != widget.role ||
        oldWidget.isPreview != widget.isPreview) {
      _generation++;
      _branches = const [];
      _branchId = null;
      _error = null;
      _balances = null;
      _movements = null;
      _productFilter = null;
      _productFilterName = null;
      _view = _InventoryView.balances;
      _savedPending = const [];
      _pendingReceive = null;
      _pendingAdjust = null;
      _pendingAdjustProduct = null;
      _busy = false;
      _search.clear();
      if (_connected) _load(0);
    }
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  Future<void> _load(int offset) async {
    if (!_connected || _busy) return;
    final generation = ++_generation;
    setState(() {
      _busy = true;
      _error = null;
      _balances = null;
      _movements = null;
    });
    try {
      final pending = await widget.repository!.pendingOperations();
      if (!mounted || generation != _generation) return;
      setState(() => _savedPending = pending);
      final branches = await widget.peopleRepository!.listBranches();
      final branch = branches.any((branch) => branch.id == _branchId)
          ? _branchId
          : branches.firstOrNull?.id;
      final repository = widget.repository!;
      final balances = branch == null || _view != _InventoryView.balances
          ? null
          : await repository.listBalances(
              branchId: branch,
              query: _search.text.trim(),
              page: PageRequest(offset: offset, limit: 20),
            );
      final movements = branch == null || _view != _InventoryView.ledger
          ? null
          : await repository.listMovements(
              branchId: branch,
              productId: _productFilter,
              page: PageRequest(offset: offset, limit: 20),
            );
      if (!mounted || generation != _generation) return;
      setState(() {
        _branches = branches;
        _branchId = branch;
        _balances = balances;
        _movements = movements;
      });
    } catch (error) {
      if (mounted && generation == _generation) {
        setState(() => _error = operationError(error));
      }
    } finally {
      if (mounted && generation == _generation) setState(() => _busy = false);
    }
  }

  Future<void> _receive() async {
    if (!_connected ||
        _branchId == null ||
        (_hasPending && _pendingReceive == null)) {
      return;
    }
    final result = await showDialog<StockOperation>(
      context: context,
      barrierDismissible: false,
      builder: (context) => _ReceiveStockDialog(
        repository: widget.repository!,
        peopleRepository: widget.peopleRepository!,
        branchId: _branchId!,
        pending: _pendingReceive,
        onFrozen: (request) => _pendingReceive = request,
        onResolved: () => _pendingReceive = null,
      ),
    );
    if (!mounted) return;
    setState(() {});
    if (result != null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Stock receipt recorded by the server.')),
      );
    }
    await _load(_offset);
  }

  Future<void> _adjust(PosProduct product) async {
    if (!_mayAdjust ||
        _branchId == null ||
        (_hasPending && _pendingAdjust == null)) {
      return;
    }
    final result = await showDialog<StockOperation>(
      context: context,
      barrierDismissible: false,
      builder: (context) => _AdjustStockDialog(
        repository: widget.repository!,
        branchId: _branchId!,
        product: product,
        pending: _pendingAdjust,
        onFrozen: (request) {
          _pendingAdjust = request;
          _pendingAdjustProduct = product;
        },
        onResolved: () {
          _pendingAdjust = null;
          _pendingAdjustProduct = null;
        },
      ),
    );
    if (!mounted) return;
    setState(() {});
    if (result != null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Stock adjustment recorded by the server.'),
        ),
      );
    }
    await _load(_offset);
  }

  void _ledger(PosProduct product) {
    setState(() {
      _view = _InventoryView.ledger;
      _productFilter = product.id;
      _productFilterName = product.name;
    });
    _load(0);
  }

  @override
  Widget build(BuildContext context) => ListView(
    padding: const EdgeInsets.all(20),
    children: [
      PageHeading(
        title: 'Inventory',
        subtitle:
            'Branch balances come from an immutable stock ledger. Receive stock or record an authorized counted adjustment in whole units.',
        trailing: FilledButton.icon(
          key: const Key('stock-receive'),
          onPressed: _connected && !_busy && !_hasPending && _branchId != null
              ? _receive
              : null,
          icon: const Icon(Icons.add_box_outlined),
          label: const Text('Receive stock'),
        ),
      ),
      const SizedBox(height: 20),
      if (!_connected)
        SectionCard(
          child: FeatureEmptyState(
            icon: Icons.inventory_2_outlined,
            title: !widget.isPreview && widget.role == AppRole.cashier
                ? 'Inventory access is restricted'
                : 'No connected inventory',
            message:
                'Connect an authorized business membership to read real branch stock. This preview contains no quantities and cannot receive or adjust stock.',
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
              _pendingReceive = null;
              _pendingAdjust = null;
              _pendingAdjustProduct = null;
              if (result != null) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text(
                      'Saved stock request confirmed by the server.',
                    ),
                  ),
                );
              }
              _load(_offset);
            },
          ),
        if ((_pendingReceive != null || _pendingAdjust != null) &&
            _savedPending.every(
              (operation) =>
                  operation.requestId !=
                  (_pendingReceive?.requestId ?? _pendingAdjust!.requestId),
            )) ...[
          OperationNotice(
            message:
                'A stock request has an unconfirmed result. Resume this request before recording another movement.',
            requestId: _pendingReceive?.requestId ?? _pendingAdjust!.requestId,
          ),
          const SizedBox(height: 10),
          OutlinedButton(
            key: const Key('stock-resume'),
            onPressed: !_busy
                ? () {
                    if (_pendingReceive != null) {
                      _receive();
                    } else {
                      _adjust(_pendingAdjustProduct!);
                    }
                  }
                : null,
            child: const Text('Resume unconfirmed stock request'),
          ),
          const SizedBox(height: 16),
        ],
        SectionCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              DropdownButtonFormField<String>(
                key: ValueKey('stock-branch-$_branchId'),
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
                onChanged: !_busy && !_hasPending
                    ? (value) {
                        setState(() {
                          _branchId = value;
                          _productFilter = null;
                          _productFilterName = null;
                        });
                        _load(0);
                      }
                    : null,
              ),
              const SizedBox(height: 16),
              SegmentedButton<_InventoryView>(
                segments: const [
                  ButtonSegment(
                    value: _InventoryView.balances,
                    label: Text('Balances'),
                  ),
                  ButtonSegment(
                    value: _InventoryView.ledger,
                    label: Text('Ledger'),
                  ),
                ],
                selected: {_view},
                onSelectionChanged: !_busy
                    ? (selection) {
                        setState(() => _view = selection.single);
                        _load(0);
                      }
                    : null,
              ),
              const SizedBox(height: 16),
              if (_view == _InventoryView.balances)
                TextField(
                  key: const Key('stock-search'),
                  controller: _search,
                  enabled: !_busy,
                  decoration: InputDecoration(
                    labelText: 'Search name, SKU or barcode',
                    suffixIcon: IconButton(
                      onPressed: !_busy ? () => _load(0) : null,
                      icon: const Icon(Icons.search),
                      tooltip: 'Search inventory',
                    ),
                  ),
                  onSubmitted: (_) => _load(0),
                )
              else if (_productFilter != null)
                Wrap(
                  spacing: 10,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    Text('Product: ${_productFilterName ?? _productFilter}'),
                    TextButton(
                      onPressed: !_busy
                          ? () {
                              setState(() {
                                _productFilter = null;
                                _productFilterName = null;
                              });
                              _load(0);
                            }
                          : null,
                      child: const Text('Clear product filter'),
                    ),
                  ],
                )
              else
                const Text('All authorized branch stock movements'),
              TextButton.icon(
                key: const Key('stock-refresh'),
                onPressed: !_busy ? () => _load(_offset) : null,
                icon: const Icon(Icons.refresh),
                label: const Text('Refresh inventory'),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        if (_busy) const LinearProgressIndicator(),
        if (_error != null) ...[
          OperationNotice(message: _error!, isError: true),
          const SizedBox(height: 12),
        ],
        if (!_busy &&
            _error == null &&
            (_view == _InventoryView.balances
                ? (_balances?.items.isEmpty ?? true)
                : (_movements?.items.isEmpty ?? true)))
          SectionCard(
            child: FeatureEmptyState(
              icon: Icons.inventory_2_outlined,
              title: _view == _InventoryView.balances
                  ? 'No matching products'
                  : 'No stock movements',
              message: _view == _InventoryView.balances
                  ? 'Create active products, then receive physical stock into this branch.'
                  : 'Confirmed receives, adjustments, sales and explicit returns appear here.',
              status: FeatureStatus.available,
            ),
          ),
        if (_view == _InventoryView.balances)
          ...?_balances?.items.map(
            (product) => Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: SectionCard(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      product.name,
                      style: const TextStyle(fontWeight: FontWeight.w700),
                    ),
                    Text(
                      '${product.sku} · ${product.availableQuantity} ${product.unit} available',
                    ),
                    const SizedBox(height: 10),
                    Wrap(
                      spacing: 12,
                      runSpacing: 8,
                      children: [
                        OutlinedButton(
                          key: Key('stock-ledger-${product.id}'),
                          onPressed: !_busy ? () => _ledger(product) : null,
                          child: const Text('View ledger'),
                        ),
                        if (_mayAdjust)
                          OutlinedButton(
                            key: Key('stock-adjust-${product.id}'),
                            onPressed: !_busy && !_hasPending
                                ? () => _adjust(product)
                                : null,
                            child: const Text('Adjust stock'),
                          ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
        if (_view == _InventoryView.ledger)
          ...?_movements?.items.map(
            (movement) => Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: SectionCard(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      movement.productName ?? movement.productId,
                      style: const TextStyle(fontWeight: FontWeight.w700),
                    ),
                    Text(
                      '${movement.kind ?? 'Stock movement'} · ${movement.quantityDelta > 0 ? '+' : ''}${movement.quantityDelta} units',
                    ),
                    Text('Balance after movement: ${movement.balanceAfter}'),
                    Text('${manilaTime(movement.createdAt)} · Asia/Manila'),
                    if (movement.reason != null)
                      Text('Reason: ${movement.reason}'),
                    if (movement.sourceId != null)
                      SelectableText(
                        'Source: ${movement.sourceId}',
                        style: const TextStyle(fontSize: 12),
                      ),
                  ],
                ),
              ),
            ),
          ),
        if (_balances != null || _movements != null)
          OperationPager(
            prefix: 'stock',
            offset: _offset,
            hasMore: _balances?.hasMore ?? _movements?.hasMore ?? false,
            busy: _busy,
            onPage: _load,
          ),
        const SizedBox(height: 16),
        const Text(
          'Purchase orders, stock transfers, fractional units and camera scanning are Coming Soon.',
          style: TextStyle(fontSize: 12, color: Color(0xff64748b)),
        ),
      ],
    ],
  );
}

class _ReceiveStockDialog extends StatefulWidget {
  const _ReceiveStockDialog({
    required this.repository,
    required this.peopleRepository,
    required this.branchId,
    required this.pending,
    required this.onFrozen,
    required this.onResolved,
  });
  final InventoryRepository repository;
  final PeopleRepository peopleRepository;
  final String branchId;
  final ReceiveStockRequest? pending;
  final ValueChanged<ReceiveStockRequest> onFrozen;
  final VoidCallback onResolved;
  @override
  State<_ReceiveStockDialog> createState() => _ReceiveStockDialogState();
}

class _ReceiveStockDialogState extends State<_ReceiveStockDialog> {
  final _form = GlobalKey<FormState>();
  final _productSearch = TextEditingController(),
      _supplierSearch = TextEditingController();
  final _quantity = TextEditingController(), _cost = TextEditingController();
  final _reference = TextEditingController(), _reason = TextEditingController();
  List<PosProduct> _products = const [];
  List<Supplier> _suppliers = const [];
  PosProduct? _product;
  String? _supplierId, _error;
  bool _loading = false, _saving = false, _confirmed = false;
  ReceiveStockRequest? _request;
  int _generation = 0;
  @override
  void initState() {
    super.initState();
    _request = widget.pending;
    if (_request == null) _search();
  }

  @override
  void dispose() {
    for (final controller in [
      _productSearch,
      _supplierSearch,
      _quantity,
      _cost,
      _reference,
      _reason,
    ]) {
      controller.dispose();
    }
    super.dispose();
  }

  Future<void> _search() async {
    if (_loading || _saving || _request != null) return;
    final generation = ++_generation;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final products = await widget.repository.listBalances(
        branchId: widget.branchId,
        query: _productSearch.text.trim(),
        page: const PageRequest(limit: 50),
      );
      final suppliers = await widget.peopleRepository.listSuppliers(
        branchId: widget.branchId,
        query: _supplierSearch.text.trim(),
        active: true,
        page: const PageRequest(limit: 50),
      );
      if (!mounted || generation != _generation) return;
      setState(() {
        _products = products.items;
        _suppliers = suppliers.items;
        if (_product != null) {
          _product = _products
              .where((product) => product.id == _product!.id)
              .firstOrNull;
        }
        if (!_suppliers.any((supplier) => supplier.id == _supplierId)) {
          _supplierId = null;
        }
      });
    } catch (error) {
      if (mounted && generation == _generation) {
        setState(() => _error = operationError(error));
      }
    } finally {
      if (mounted && generation == _generation) {
        setState(() => _loading = false);
      }
    }
  }

  Future<void> _submit() async {
    if (_saving || _loading) return;
    if (_request == null) {
      if (!_form.currentState!.validate()) return;
      if (_product == null || !_confirmed) {
        setState(
          () => _error =
              'Choose an actual product and confirm the units were physically received.',
        );
        return;
      }
      _request = ReceiveStockRequest(
        branchId: widget.branchId,
        supplierId: _supplierId,
        reference: _reference.text.trim(),
        reason: _reason.text.trim(),
        items: [
          StockReceiptItem(
            productId: _product!.id,
            expectedRevision: _product!.revision,
            quantity: wholeUnits(_quantity.text),
            unitCostMinor: _cost.text.trim().isEmpty
                ? null
                : Money.parseMinor(_cost.text),
          ),
        ],
      );
      widget.onFrozen(_request!);
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      final result = await widget.repository.receiveStock(_request!);
      widget.onResolved();
      if (mounted) Navigator.pop(context, result);
    } catch (error) {
      if (mounted) {
        setState(() {
          _error = operationMayBeUnconfirmed(error)
              ? '${operationError(error)} Do not receive the same delivery twice. Retry this saved request.'
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
  Widget build(BuildContext context) => PopScope(
    canPop: !_saving,
    child: AlertDialog(
      title: const Text('Receive stock'),
      content: SizedBox(
        width: 520,
        child: SingleChildScrollView(
          child: Form(
            key: _form,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Record one physically received product into this branch. The server appends a ledger entry and returns its confirmed balance.',
                ),
                const SizedBox(height: 16),
                if (_request == null) ...[
                  TextField(
                    key: const Key('receive-product-search'),
                    controller: _productSearch,
                    enabled: !_saving && !_loading,
                    decoration: const InputDecoration(
                      labelText: 'Search product name, SKU or barcode',
                    ),
                    onSubmitted: (_) => _search(),
                  ),
                  const SizedBox(height: 10),
                  TextField(
                    key: const Key('receive-supplier-search'),
                    controller: _supplierSearch,
                    enabled: !_saving && !_loading,
                    decoration: const InputDecoration(
                      labelText: 'Search supplier (optional)',
                    ),
                    onSubmitted: (_) => _search(),
                  ),
                  TextButton.icon(
                    onPressed: !_saving && !_loading ? _search : null,
                    icon: const Icon(Icons.search),
                    label: const Text('Search products and suppliers'),
                  ),
                  if (_loading) const LinearProgressIndicator(),
                  const Text(
                    'Each search shows up to 50 records. Refine the search if a record is missing.',
                    style: TextStyle(fontSize: 12),
                  ),
                  const SizedBox(height: 12),
                  DropdownButtonFormField<String>(
                    key: ValueKey(
                      'receive-product-${_product?.id}-${_products.length}',
                    ),
                    initialValue: _product?.id,
                    isExpanded: true,
                    decoration: const InputDecoration(labelText: 'Product'),
                    items: _products
                        .map(
                          (product) => DropdownMenuItem(
                            value: product.id,
                            child: Text(
                              '${product.name} · ${product.sku}',
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        )
                        .toList(),
                    onChanged: !_saving && !_loading
                        ? (id) => setState(() {
                            _product = _products.firstWhere(
                              (product) => product.id == id,
                            );
                            _cost.clear();
                          })
                        : null,
                    validator: (value) =>
                        value == null ? 'Choose an actual product.' : null,
                  ),
                  const SizedBox(height: 12),
                  DropdownButtonFormField<String>(
                    key: ValueKey(
                      'receive-supplier-$_supplierId-${_suppliers.length}',
                    ),
                    initialValue: _supplierId,
                    isExpanded: true,
                    decoration: const InputDecoration(
                      labelText: 'Supplier (optional)',
                    ),
                    items: [
                      const DropdownMenuItem<String>(
                        value: null,
                        child: Text('No supplier selected'),
                      ),
                      ..._suppliers.map(
                        (supplier) => DropdownMenuItem(
                          value: supplier.id,
                          child: Text(
                            supplier.name,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ),
                    ],
                    onChanged: !_saving && !_loading
                        ? (value) => setState(() => _supplierId = value)
                        : null,
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    key: const Key('receive-quantity'),
                    controller: _quantity,
                    enabled: !_saving,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(
                      labelText: 'Whole units received',
                    ),
                    validator: (value) =>
                        operationValidation(() => wholeUnits(value ?? '')),
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    key: const Key('receive-cost'),
                    controller: _cost,
                    enabled: !_saving && _product != null,
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                    ),
                    decoration: InputDecoration(
                      labelText:
                          'Unit cost (${_product?.currency ?? 'select product'}, optional)',
                      helperText:
                          'Private receiving evidence; catalog cost stays unchanged.',
                      helperMaxLines: 2,
                    ),
                    validator: (value) => value?.trim().isEmpty ?? true
                        ? null
                        : operationValidation(() => Money.parseMinor(value!)),
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    key: const Key('receive-reference'),
                    controller: _reference,
                    enabled: !_saving,
                    maxLength: 120,
                    decoration: const InputDecoration(
                      labelText: 'Delivery reference',
                    ),
                    validator: (value) => operationValidation(
                      () => requiredText(
                        value ?? '',
                        'Delivery reference',
                        120,
                        minimum: 3,
                      ),
                    ),
                  ),
                  TextFormField(
                    key: const Key('receive-reason'),
                    controller: _reason,
                    enabled: !_saving,
                    maxLength: 500,
                    maxLines: 2,
                    decoration: const InputDecoration(
                      labelText: 'Receiving reason',
                    ),
                    validator: (value) => operationValidation(
                      () => requiredText(
                        value ?? '',
                        'Receiving reason',
                        500,
                        minimum: 3,
                      ),
                    ),
                  ),
                  CheckboxListTile(
                    contentPadding: EdgeInsets.zero,
                    controlAffinity: ListTileControlAffinity.leading,
                    value: _confirmed,
                    onChanged: !_saving
                        ? (value) => setState(() => _confirmed = value ?? false)
                        : null,
                    title: const Text(
                      'These units were physically received into this branch',
                    ),
                  ),
                ] else
                  OperationNotice(
                    message:
                        'This receipt request is frozen. Retry uses the original product revision, units, supplier, cost evidence and reference.',
                    requestId: _request!.requestId,
                  ),
                if (_error != null) ...[
                  const SizedBox(height: 12),
                  OperationNotice(message: _error!, isError: true),
                ],
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
          key: const Key('receive-submit'),
          onPressed: !_saving && !_loading ? _submit : null,
          child: Text(
            _saving
                ? 'Confirming…'
                : _request != null
                ? 'Retry same request'
                : 'Record stock receipt',
          ),
        ),
      ],
    ),
  );
}

class _AdjustStockDialog extends StatefulWidget {
  const _AdjustStockDialog({
    required this.repository,
    required this.branchId,
    required this.product,
    required this.pending,
    required this.onFrozen,
    required this.onResolved,
  });
  final InventoryRepository repository;
  final String branchId;
  final PosProduct product;
  final AdjustStockRequest? pending;
  final ValueChanged<AdjustStockRequest> onFrozen;
  final VoidCallback onResolved;
  @override
  State<_AdjustStockDialog> createState() => _AdjustStockDialogState();
}

class _AdjustStockDialogState extends State<_AdjustStockDialog> {
  final _form = GlobalKey<FormState>();
  final _delta = TextEditingController(), _reason = TextEditingController();
  AdjustStockRequest? _request;
  bool _saving = false, _confirmed = false;
  String? _error;
  @override
  void initState() {
    super.initState();
    _request = widget.pending;
  }

  @override
  void dispose() {
    _delta.dispose();
    _reason.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_saving) return;
    if (_request == null) {
      if (!_form.currentState!.validate()) return;
      if (!_confirmed) {
        setState(
          () => _error =
              'Confirm that this signed change matches the physical count.',
        );
        return;
      }
      _request = AdjustStockRequest(
        branchId: widget.branchId,
        productId: widget.product.id,
        deltaQuantity: wholeUnits(_delta.text, signed: true),
        reason: _reason.text.trim(),
      );
      widget.onFrozen(_request!);
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      final result = await widget.repository.adjustStock(_request!);
      widget.onResolved();
      if (mounted) Navigator.pop(context, result);
    } catch (error) {
      if (mounted) {
        setState(() {
          _error = operationMayBeUnconfirmed(error)
              ? '${operationError(error)} Retry this same adjustment before recording another change.'
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
  Widget build(BuildContext context) => PopScope(
    canPop: !_saving,
    child: AlertDialog(
      title: const Text('Adjust stock'),
      content: SizedBox(
        width: 480,
        child: SingleChildScrollView(
          child: Form(
            key: _form,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  widget.product.name,
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
                Text(
                  'Last loaded balance: ${widget.product.availableQuantity} ${widget.product.unit}',
                ),
                const SizedBox(height: 10),
                const Text(
                  'Enter a signed change, not a replacement balance. A minus sign removes units. The server locks the current balance and rejects changes that would make it negative.',
                ),
                const SizedBox(height: 16),
                if (_request == null) ...[
                  TextFormField(
                    key: const Key('adjust-delta'),
                    controller: _delta,
                    enabled: !_saving,
                    keyboardType: const TextInputType.numberWithOptions(
                      signed: true,
                    ),
                    decoration: const InputDecoration(
                      labelText: 'Whole-unit change (e.g. -2 or 5)',
                    ),
                    validator: (value) => operationValidation(
                      () => wholeUnits(value ?? '', signed: true),
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    key: const Key('adjust-reason'),
                    controller: _reason,
                    enabled: !_saving,
                    maxLength: 500,
                    maxLines: 2,
                    decoration: const InputDecoration(
                      labelText: 'Adjustment reason',
                    ),
                    validator: (value) => operationValidation(
                      () => requiredText(
                        value ?? '',
                        'Adjustment reason',
                        500,
                        minimum: 3,
                      ),
                    ),
                  ),
                  CheckboxListTile(
                    contentPadding: EdgeInsets.zero,
                    controlAffinity: ListTileControlAffinity.leading,
                    title: const Text(
                      'This signed change matches a counted physical discrepancy',
                    ),
                    value: _confirmed,
                    onChanged: !_saving
                        ? (value) => setState(() => _confirmed = value ?? false)
                        : null,
                  ),
                ] else
                  OperationNotice(
                    message:
                        'This adjustment is frozen. Retry uses the same product, signed change and reason.',
                    requestId: _request!.requestId,
                  ),
                if (_error != null) ...[
                  const SizedBox(height: 12),
                  OperationNotice(message: _error!, isError: true),
                ],
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
          key: const Key('adjust-submit'),
          onPressed: !_saving ? _submit : null,
          child: Text(
            _saving
                ? 'Confirming…'
                : _request != null
                ? 'Retry same request'
                : 'Record adjustment',
          ),
        ),
      ],
    ),
  );
}
