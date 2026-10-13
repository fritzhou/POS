import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../app/config/feature_status.dart';
import '../../core/security/app_role.dart';
import '../../core/services/payment_service.dart';
import '../../core/widgets/status_widgets.dart';
import '../administration/domain/administration_models.dart';
import '../catalog/domain/catalog_models.dart';
import '../catalog/domain/catalog_repository.dart';
import '../catalog/domain/repository_support.dart';
import '../checkout/domain/checkout_models.dart';
import '../checkout/domain/checkout_repository.dart';
import '../checkout/presentation/pos_payment_dialog.dart';
import '../checkout/presentation/pos_discount_dialog.dart';
import '../checkout/presentation/pos_customer_dialog.dart';
import '../people/domain/people_repository.dart';
import '../people/domain/people_models.dart';
import '../sales/presentation/receipt_details.dart';
import '../scanning/presentation/keyboard_scanner_capture.dart';

class PosPage extends StatefulWidget {
  const PosPage({
    this.repository,
    this.catalogRepository,
    this.peopleRepository,
    this.role,
    this.isPreview = true,
    this.onPendingChanged,
    super.key,
  });

  final CheckoutRepository? repository;
  final CatalogRepository? catalogRepository;
  final PeopleRepository? peopleRepository;
  final AppRole? role;
  final bool isPreview;
  final ValueChanged<bool>? onPendingChanged;

  @override
  State<PosPage> createState() => _PosPageState();
}

class _PosPageState extends State<PosPage> {
  final _pageFocus = FocusNode();
  final _searchFocus = FocusNode();
  final _barcodeFocus = FocusNode();
  final _search = TextEditingController();
  final _barcode = TextEditingController();
  final _cart = <CartLine>[];
  Timer? _debounce;
  List<BranchOption> _branches = [];
  List<Category> _categories = [];
  DataPage<PosProduct>? _products;
  PosContext? _context;
  PosContext? _latestContext;
  Shift? _shift;
  Customer? _customer;
  CheckoutRequest? _pending;
  String? _branchId;
  String? _categoryId;
  String? _error;
  String? _pendingNotice;
  String? _discountReason;
  int _discountMinor = 0;
  int _offset = 0;
  int _scopeGeneration = 0;
  int _productGeneration = 0;
  int _branchChoiceGeneration = 0;
  bool _showCart = false;
  bool _loading = false;
  bool _loadingProducts = false;
  bool _busy = false;
  bool _barcodeBusy = false;
  bool _settingsStale = false;

  bool get _connected =>
      !widget.isPreview &&
      widget.repository != null &&
      widget.catalogRepository != null &&
      widget.peopleRepository != null &&
      (widget.role?.allows(AppPermission.usePos) ?? false);
  bool get _locked => _busy || _pending != null;
  bool get _canDiscard =>
      _connected && !_loading && !_locked && _context != null;
  bool get _canOrder => _canDiscard && !_settingsStale;
  CartTotals? get _totals {
    if (_cart.isEmpty || _context == null) return null;
    try {
      return CartTotals.calculate(
        lines: _cart,
        taxBps: _context!.taxBps,
        discountMinor: _discountMinor,
      );
    } on RepositoryFailure {
      return null;
    }
  }

  String get _currency => _context?.currency ?? 'PHP';

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _pageFocus.requestFocus();
    });
    if (_connected) unawaited(_initialize());
  }

  @override
  void didUpdateWidget(covariant PosPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.repository != widget.repository ||
        oldWidget.catalogRepository != widget.catalogRepository ||
        oldWidget.peopleRepository != widget.peopleRepository ||
        oldWidget.role != widget.role ||
        oldWidget.isPreview != widget.isPreview) {
      _scopeGeneration++;
      _productGeneration++;
      _debounce?.cancel();
      _cart.clear();
      _customer = null;
      _pending = null;
      _products = null;
      _context = null;
      _latestContext = null;
      _settingsStale = false;
      _shift = null;
      _branchId = null;
      _categoryId = null;
      _branches = [];
      _categories = [];
      _discountMinor = 0;
      _discountReason = null;
      _error = null;
      _pendingNotice = null;
      _search.clear();
      _barcode.clear();
      _busy = false;
      _barcodeBusy = false;
      _loading = false;
      _loadingProducts = false;
      widget.onPendingChanged?.call(false);
      if (_connected) unawaited(_initialize());
    }
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _pageFocus.dispose();
    _searchFocus.dispose();
    _barcodeFocus.dispose();
    _search.dispose();
    _barcode.dispose();
    super.dispose();
  }

  Future<void> _initialize() async {
    final generation = ++_scopeGeneration;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final branches = await widget.peopleRepository!.listBranches();
      final categories = await widget.catalogRepository!.listCategories(
        active: true,
        page: const PageRequest(limit: 100),
      );
      if (!mounted || generation != _scopeGeneration) return;
      setState(() {
        _branches = branches;
        _categories = categories.items;
        _loading = false;
      });
      if (branches.length == 1) await _selectBranch(branches.single.id);
    } catch (error) {
      if (mounted && generation == _scopeGeneration) {
        setState(() {
          _loading = false;
          _error = _publicError(error);
        });
      }
    }
  }

  Future<void> _selectBranch(String? branchId) async {
    if (branchId == null || branchId == _branchId || _locked) return;
    final initialScope = _scopeGeneration;
    if (_cart.isNotEmpty) {
      final discard = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Discard this order?'),
          content: const Text(
            'Changing branch clears the current cart and discount. No sale has been submitted.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Keep order'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Discard and change branch'),
            ),
          ],
        ),
      );
      if (!mounted || initialScope != _scopeGeneration || _locked) return;
      if (discard != true) {
        // Form-field selections update before this asynchronous confirmation.
        // Recreate the field so its displayed branch stays authoritative.
        setState(() => _branchChoiceGeneration++);
        return;
      }
    }
    final generation = ++_scopeGeneration;
    _productGeneration++;
    setState(() {
      _branchId = branchId;
      _cart.clear();
      _customer = null;
      _discountMinor = 0;
      _discountReason = null;
      _context = null;
      _latestContext = null;
      _settingsStale = false;
      _shift = null;
      _products = null;
      _pending = null;
      _pendingNotice = null;
      _loading = true;
      _error = null;
      _offset = 0;
    });
    try {
      final pending = await widget.repository!.pendingCheckout(branchId);
      if (!mounted || generation != _scopeGeneration) return;
      setState(() => _pending = pending);
      widget.onPendingChanged?.call(pending != null);
      final loadedContext = await widget.repository!.loadContext(branchId);
      final shift = await widget.repository!.currentShift(branchId);
      if (!mounted || generation != _scopeGeneration) return;
      setState(() {
        _context = loadedContext;
        _shift = shift;
        _pending = pending;
        _loading = false;
        if (pending != null) {
          _pendingNotice =
              'A previous checkout needs reconciliation. Its original request and payment evidence are retained.';
        }
      });
      widget.onPendingChanged?.call(pending != null);
      await _loadProducts();
    } catch (error) {
      if (mounted && generation == _scopeGeneration) {
        setState(() {
          _loading = false;
          _error = _publicError(error);
        });
      }
    }
  }

  Future<void> _loadProducts() async {
    if (!_connected || _branchId == null || _context == null) return;
    final generation = ++_productGeneration;
    final scope = _scopeGeneration;
    setState(() {
      _loadingProducts = true;
      _error = null;
    });
    try {
      final products = await widget.repository!.searchProducts(
        branchId: _branchId!,
        query: _search.text.trim(),
        categoryId: _categoryId,
        page: PageRequest(offset: _offset, limit: 20),
      );
      if (mounted &&
          scope == _scopeGeneration &&
          generation == _productGeneration) {
        setState(() {
          _products = products;
          _loadingProducts = false;
        });
      }
    } catch (error) {
      if (mounted &&
          scope == _scopeGeneration &&
          generation == _productGeneration) {
        setState(() {
          _loadingProducts = false;
          _error = _publicError(error);
        });
      }
    }
  }

  Future<void> _lookupBarcode(
    String value, {
    bool Function()? scanCurrent,
  }) async {
    if (!_canOrder || _barcodeBusy || value.trim().isEmpty) return;
    final scope = _scopeGeneration;
    setState(() {
      _barcodeBusy = true;
      _error = null;
    });
    try {
      final product = await widget.repository!.lookupProductByBarcode(
        branchId: _branchId!,
        barcode: scanCurrent == null ? value.trim() : value,
      );
      if (!mounted ||
          scope != _scopeGeneration ||
          (scanCurrent != null && !scanCurrent())) {
        return;
      }
      if (product == null) {
        setState(
          () => _error =
              'No active product has this exact barcode in this branch.',
        );
      } else {
        _addProduct(product);
        _barcode.clear();
      }
    } catch (error) {
      if (mounted &&
          scope == _scopeGeneration &&
          (scanCurrent?.call() ?? true)) {
        setState(() => _error = _publicError(error));
      }
    } finally {
      if (mounted && scope == _scopeGeneration) {
        setState(() => _barcodeBusy = false);
      }
    }
  }

  void _addProduct(PosProduct product) {
    if (!_canOrder) return;
    if (product.currency != _currency) {
      setState(
        () => _error =
            'This product uses a different currency. Update it before sale.',
      );
      return;
    }
    final index = _cart.indexWhere((line) => line.product.id == product.id);
    final quantity = index < 0 ? 1 : _cart[index].quantity + 1;
    if (quantity > product.availableQuantity) {
      setState(
        () => _error = 'There is not enough recorded stock for this quantity.',
      );
      return;
    }
    if (index < 0 && _cart.length >= 100) {
      setState(
        () => _error = 'An order can contain at most 100 different products.',
      );
      return;
    }
    final next = [..._cart];
    if (index < 0) {
      next.add(CartLine(product: product, quantity: 1));
    } else {
      next[index] = CartLine(product: product, quantity: quantity);
    }
    _replaceCart(next);
  }

  void _quantity(int index, int quantity) {
    if (!_canOrder) return;
    if (quantity > _cart[index].product.availableQuantity) {
      setState(
        () => _error = 'There is not enough recorded stock for this quantity.',
      );
      return;
    }
    final next = [..._cart];
    if (quantity <= 0) {
      next.removeAt(index);
    } else {
      next[index] = next[index].withQuantity(quantity);
    }
    _replaceCart(next);
  }

  void _replaceCart(List<CartLine> next) {
    try {
      if (next.isNotEmpty) {
        CartTotals.calculate(
          lines: next,
          taxBps: _context!.taxBps,
          discountMinor: _discountMinor,
        );
      }
      setState(() {
        _cart
          ..clear()
          ..addAll(next);
        if (next.isEmpty) {
          _discountMinor = 0;
          _discountReason = null;
        }
        _error = null;
      });
    } on RepositoryFailure catch (error) {
      setState(() => _error = error.message);
    }
  }

  Future<void> _chooseCustomer() async {
    if (!_canOrder || _branchId == null) return;
    final scope = _scopeGeneration;
    final customer = await showDialog<Customer>(
      context: context,
      builder: (context) => PosCustomerDialog(
        repository: widget.peopleRepository!,
        branchId: _branchId!,
      ),
    );
    if (mounted && scope == _scopeGeneration && customer != null && !_locked) {
      setState(() => _customer = customer);
    }
  }

  Future<void> _discount() async {
    if (!_canOrder ||
        _cart.isEmpty ||
        !(widget.role?.allows(AppPermission.approveDiscount) ?? false)) {
      return;
    }
    final scope = _scopeGeneration;
    final result = await showDialog<(int, String?)>(
      context: context,
      builder: (context) => PosDiscountDialog(
        lines: List.unmodifiable(_cart),
        taxBps: _context!.taxBps,
        discountMinor: _discountMinor,
        reason: _discountReason,
      ),
    );
    if (mounted && scope == _scopeGeneration && result != null && !_locked) {
      setState(() {
        _discountMinor = result.$1;
        _discountReason = result.$2;
      });
    }
  }

  Future<void> _checkout() async {
    if (!_canOrder || _cart.isEmpty) return;
    final totals = _totals;
    if (totals == null) {
      setState(
        () => _error =
            'This order cannot be calculated safely. Clear it and reload current products.',
      );
      return;
    }
    if (totals.totalMinor <= 0) {
      setState(() => _error = 'The payable total must be positive.');
      return;
    }
    setState(() => _busy = true);
    final scope = _scopeGeneration;
    try {
      final latestContext = await widget.repository!.loadContext(_branchId!);
      final shift = await widget.repository!.currentShift(_branchId!);
      if (!mounted || scope != _scopeGeneration) return;
      setState(() => _shift = shift);
      if (_context!.settingsRevision != latestContext.settingsRevision ||
          _context!.currency != latestContext.currency ||
          _context!.taxBps != latestContext.taxBps) {
        setState(() {
          _busy = false;
          _latestContext = latestContext;
          _settingsStale = true;
          _error =
              'Business settings changed. Clear this order and reload products before recording any payment.';
        });
        return;
      }
      if (shift?.isOpen != true) {
        setState(() {
          _busy = false;
          _error = 'Open your shift in Shifts before checkout.';
        });
        return;
      }
      if (shift!.currency != _currency ||
          _cart.any((line) => line.product.currency != _currency)) {
        setState(() {
          _busy = false;
          _error =
              'The shift, business and order must use the same currency. Resolve the shift and rebuild the order before payment.';
        });
        return;
      }
    } catch (error) {
      if (mounted && scope == _scopeGeneration) {
        setState(() {
          _busy = false;
          _error = _publicError(error);
        });
      }
      return;
    }
    final tenders = await showDialog<List<TenderEvidence>>(
      context: context,
      barrierDismissible: false,
      builder: (context) =>
          PosPaymentDialog(totalMinor: totals.totalMinor, currency: _currency),
    );
    if (!mounted || scope != _scopeGeneration) return;
    if (tenders == null) {
      setState(() => _busy = false);
      return;
    }
    final request = CheckoutRequest(
      branchId: _branchId!,
      shiftId: _shift!.id,
      expectedSettingsRevision: _context!.settingsRevision,
      customerId: _customer?.id,
      items: _cart.map(CheckoutItem.fromCart).toList(),
      discountMinor: _discountMinor,
      reason: _discountReason,
      payments: tenders
          .map(
            (tender) => CheckoutPayment(
              method: CheckoutPaymentMethod.values.byName(tender.method.name),
              amountMinor: tender.appliedMinor,
              tenderedMinor: tender.method == PaymentMethod.cash
                  ? tender.receivedMinor
                  : null,
              manualConfirmed: tender.method != PaymentMethod.cash,
              reference: tender.reference,
            ),
          )
          .toList(),
    );
    try {
      request.validatedPayload();
    } on RepositoryFailure catch (failure) {
      setState(() {
        _busy = false;
        _error = failure.message;
      });
      return;
    }
    setState(() {
      _pending = request;
      _pendingNotice =
          'Waiting for the server to confirm checkout. Keep this order open.';
      _error = null;
    });
    widget.onPendingChanged?.call(true);
    await _submitPending();
  }

  Future<void> _submitPending() async {
    final request = _pending;
    if (request == null) return;
    final scope = _scopeGeneration;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final receipt = await widget.repository!.checkout(request);
      if (mounted && scope == _scopeGeneration) {
        await _complete(receipt, request);
      }
    } catch (error) {
      if (!mounted || scope != _scopeGeneration) return;
      try {
        // The repository clears an intent only after a definitive, atomic
        // rejection. Unknown outcomes remain in its durable operation journal.
        final retained = await widget.repository!.pendingCheckout(
          request.branchId,
        );
        if (!mounted || scope != _scopeGeneration) return;
        setState(() {
          _error = _publicError(error);
          _pending = retained;
          _pendingNotice = retained == null
              ? null
              : 'Checkout is unresolved. Reconcile with the server, or retry this same request. The cart and payment evidence are frozen.';
        });
        widget.onPendingChanged?.call(retained != null);
        if (retained == null &&
            error is RepositoryFailure &&
            error.type == RepositoryFailureType.conflict) {
          setState(
            () => _error =
                '${error.message} Clear this order and add the current products again before taking payment.',
          );
        }
      } catch (_) {
        if (!mounted || scope != _scopeGeneration) return;
        setState(() {
          _error = _publicError(error);
          _pendingNotice =
              'Checkout is unresolved. Its original request and payment evidence are retained.';
        });
      }
    } finally {
      if (mounted && scope == _scopeGeneration) setState(() => _busy = false);
    }
  }

  Future<void> _reconcile() async {
    final request = _pending;
    if (request == null || _busy) return;
    final scope = _scopeGeneration;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final receipt = await widget.repository!.findSaleByRequest(
        branchId: request.branchId,
        requestId: request.requestId,
      );
      if (!mounted || scope != _scopeGeneration) return;
      if (receipt == null) {
        setState(
          () => _pendingNotice =
              'No receipt is visible for this request yet. Retry the original checkout; do not take another payment.',
        );
      } else {
        await _complete(receipt, request);
      }
    } catch (error) {
      if (mounted && scope == _scopeGeneration) {
        setState(() => _error = _publicError(error));
      }
    } finally {
      if (mounted && scope == _scopeGeneration) setState(() => _busy = false);
    }
  }

  Future<void> _retryPending() async {
    final request = _pending;
    if (request == null || _busy) return;
    final scope = _scopeGeneration;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final receipt = await widget.repository!.findSaleByRequest(
        branchId: request.branchId,
        requestId: request.requestId,
      );
      if (!mounted || scope != _scopeGeneration) return;
      if (receipt != null) {
        await _complete(receipt, request);
      } else {
        await _submitPending();
      }
    } catch (error) {
      if (mounted && scope == _scopeGeneration) {
        setState(() => _error = _publicError(error));
      }
    } finally {
      if (mounted && scope == _scopeGeneration) setState(() => _busy = false);
    }
  }

  Future<void> _complete(SaleReceipt receipt, CheckoutRequest request) async {
    if (receipt.branchId != request.branchId ||
        receipt.requestId != request.requestId) {
      throw const RepositoryFailure(
        RepositoryFailureType.unavailable,
        'The server receipt could not be matched to this checkout. Reconcile before continuing.',
      );
    }
    setState(() {
      _pending = null;
      _pendingNotice = null;
      _cart.clear();
      _customer = null;
      _discountMinor = 0;
      _discountReason = null;
      _error = null;
      _busy = false;
      _settingsStale = false;
      _latestContext = null;
    });
    widget.onPendingChanged?.call(false);
    final receiptScope = _scopeGeneration;
    final receiptRepository = widget.repository;
    final receiptBranch = _branchId;
    bool receiptCurrent() =>
        mounted &&
        receiptScope == _scopeGeneration &&
        identical(receiptRepository, widget.repository) &&
        receiptBranch == _branchId;
    await showReceiptDialog(context, receipt, isCurrent: receiptCurrent);
    if (!receiptCurrent()) return;
    await _refreshBranch();
  }

  Future<void> _refreshBranch() async {
    if (_branchId == null || _locked) return;
    final scope = _scopeGeneration;
    try {
      final loadedContext = await widget.repository!.loadContext(_branchId!);
      final shift = await widget.repository!.currentShift(_branchId!);
      if (mounted && scope == _scopeGeneration) {
        setState(() {
          if (_cart.isNotEmpty &&
              (_context!.settingsRevision != loadedContext.settingsRevision ||
                  _context!.currency != loadedContext.currency ||
                  _context!.taxBps != loadedContext.taxBps)) {
            _latestContext = loadedContext;
            _settingsStale = true;
            _error =
                'Business settings changed. Clear this order and reload products before recording any payment.';
          } else {
            _context = loadedContext;
            _latestContext = null;
            _settingsStale = false;
          }
          _shift = shift;
        });
      }
      await _loadProducts();
      if (mounted && scope == _scopeGeneration && _settingsStale) {
        setState(
          () => _error =
              'Business settings changed. Clear this order and reload products before recording any payment.',
        );
      }
    } catch (error) {
      if (mounted && scope == _scopeGeneration) {
        setState(() => _error = _publicError(error));
      }
    }
  }

  void _clearCart() {
    if (!_canDiscard) return;
    setState(() {
      _cart.clear();
      _customer = null;
      _discountMinor = 0;
      _discountReason = null;
      if (_latestContext != null) _context = _latestContext;
      _latestContext = null;
      _settingsStale = false;
      _error = null;
    });
    unawaited(_loadProducts());
  }

  @override
  Widget build(BuildContext context) => KeyboardScannerCapture(
    available: _canOrder,
    scopeToken: (widget.repository, _scopeGeneration, widget.role),
    onBarcode: (barcode, current) =>
        _lookupBarcode(barcode, scanCurrent: current),
    builder: (context, scannerControls) => CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.keyF, control: true): () =>
            _searchFocus.requestFocus(),
        const SingleActivator(LogicalKeyboardKey.keyB, control: true): () =>
            _barcodeFocus.requestFocus(),
      },
      child: Focus(
        focusNode: _pageFocus,
        child: LayoutBuilder(
          builder: (context, constraints) {
            final split = constraints.maxWidth >= 860;
            return Padding(
              padding: EdgeInsets.all(constraints.maxWidth < 500 ? 16 : 24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  PageHeading(
                    title: 'Point of sale',
                    subtitle:
                        'Find products. Build an order. Keep checkout clear.',
                    trailing: StatusPill(
                      label: _connected
                          ? 'Server-confirmed checkout'
                          : 'Checkout · Not Yet Connected',
                    ),
                  ),
                  const SizedBox(height: 16),
                  if (_connected) ...[_branchBar(), const SizedBox(height: 12)],
                  if (!split) ...[
                    SegmentedButton<bool>(
                      expandedInsets: EdgeInsets.zero,
                      segments: const [
                        ButtonSegment(
                          value: false,
                          label: Text('Products'),
                          icon: Icon(Icons.grid_view_outlined),
                        ),
                        ButtonSegment(
                          value: true,
                          label: Text('Cart'),
                          icon: Icon(Icons.shopping_cart_outlined),
                        ),
                      ],
                      selected: {_showCart},
                      onSelectionChanged: (value) =>
                          setState(() => _showCart = value.single),
                    ),
                    const SizedBox(height: 12),
                  ],
                  Expanded(
                    child: split
                        ? Row(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              Expanded(child: _catalog(scannerControls)),
                              const SizedBox(width: 20),
                              SizedBox(
                                width: 340,
                                child: _cartPanel(pinTotals: true),
                              ),
                            ],
                          )
                        : _showCart
                        ? _cartPanel()
                        : _catalog(scannerControls),
                  ),
                ],
              ),
            );
          },
        ),
      ),
    ),
  );

  Widget _branchBar() => Row(
    key: const Key('pos-branch-selector'),
    children: [
      Expanded(
        child: DropdownButtonFormField<String>(
          key: ValueKey('pos-branch-$_branchId-$_branchChoiceGeneration'),
          initialValue: _branchId,
          isExpanded: true,
          decoration: const InputDecoration(
            labelText: 'Active branch',
            isDense: true,
          ),
          items: [
            for (final branch in _branches)
              DropdownMenuItem(
                value: branch.id,
                child: Text(branch.name, overflow: TextOverflow.ellipsis),
              ),
          ],
          onChanged: _locked || _loading ? null : _selectBranch,
        ),
      ),
      const SizedBox(width: 8),
      IconButton(
        tooltip: 'Refresh branch, shift and stock',
        onPressed: _locked || _loading
            ? null
            : () {
                if (_branchId == null) {
                  unawaited(_initialize());
                } else {
                  unawaited(_refreshBranch());
                }
              },
        icon: const Icon(Icons.refresh),
      ),
    ],
  );

  Widget _catalog(Widget scannerControls) => SectionCard(
    padding: 16,
    child: LayoutBuilder(
      builder: (context, constraints) => SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            TextField(
              key: const Key('product-search'),
              controller: _search,
              focusNode: _searchFocus,
              textInputAction: TextInputAction.search,
              decoration: InputDecoration(
                hintText: 'Search name or SKU',
                prefixIcon: const Icon(Icons.search),
                helperText: _connected
                    ? 'Search this branch · Ctrl+F'
                    : 'Not Yet Connected · Ctrl+F to focus',
              ),
              onChanged: _connected
                  ? (_) {
                      _debounce?.cancel();
                      _debounce = Timer(const Duration(milliseconds: 300), () {
                        _offset = 0;
                        unawaited(_loadProducts());
                      });
                    }
                  : null,
              onSubmitted: _connected
                  ? (_) {
                      _debounce?.cancel();
                      _offset = 0;
                      unawaited(_loadProducts());
                    }
                  : null,
            ),
            const SizedBox(height: 12),
            TextField(
              key: const Key('manual-barcode'),
              controller: _barcode,
              focusNode: _barcodeFocus,
              textInputAction: TextInputAction.done,
              decoration: InputDecoration(
                hintText: 'Enter a barcode',
                prefixIcon: const Icon(Icons.qr_code_2_outlined),
                helperText: _connected
                    ? 'Exact manual lookup · Enter / Ctrl+B'
                    : 'Manual entry · Product lookup Not Yet Connected',
                suffixIcon: IconButton(
                  tooltip: 'Find exact barcode',
                  onPressed: _canOrder && !_barcodeBusy
                      ? () => _lookupBarcode(_barcode.text)
                      : null,
                  icon: _barcodeBusy
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.arrow_forward),
                ),
              ),
              onSubmitted: _canOrder ? _lookupBarcode : null,
            ),
            const SizedBox(height: 12),
            scannerControls,
            const SizedBox(height: 12),
            if (_categories.isNotEmpty) ...[
              DropdownButtonFormField<String>(
                key: ValueKey('pos-category-$_categoryId'),
                initialValue: _categoryId,
                isExpanded: true,
                decoration: const InputDecoration(labelText: 'Category'),
                items: [
                  const DropdownMenuItem(
                    value: null,
                    child: Text('All products'),
                  ),
                  for (final category in _categories)
                    DropdownMenuItem(
                      value: category.id,
                      child: Text(
                        category.name,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                ],
                onChanged: _connected
                    ? (value) {
                        setState(() {
                          _categoryId = value;
                          _offset = 0;
                        });
                        unawaited(_loadProducts());
                      }
                    : null,
              ),
              const SizedBox(height: 12),
            ],
            const Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                StatusPill(
                  label: 'Camera scanner · Coming Soon',
                  icon: Icons.qr_code_scanner_outlined,
                ),
              ],
            ),
            if (_error != null)
              Padding(
                padding: const EdgeInsets.only(top: 12),
                child: Text(
                  _error!,
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
              ),
            if (_loading || _loadingProducts)
              const Padding(
                padding: EdgeInsets.all(24),
                child: Center(child: CircularProgressIndicator()),
              ),
            if (!_connected)
              FeatureEmptyState(
                icon: Icons.inventory_2_outlined,
                title: 'Your product catalog belongs here',
                message: widget.isPreview
                    ? 'This design preview is read-only. There are no sample products or connected stock quantities.'
                    : 'Connect an authorized business and its catalog before taking orders.',
                status: FeatureStatus.notYetConnected,
                compact: true,
              ),
            if (_connected && !_loading && _branchId == null)
              const Padding(
                padding: EdgeInsets.all(24),
                child: Text(
                  'Choose an authorized branch to load its products and current shift.',
                ),
              ),
            if (_connected &&
                !_loadingProducts &&
                _products != null &&
                _products!.items.isEmpty)
              const Padding(
                padding: EdgeInsets.all(24),
                child: Text('No active products match this search.'),
              ),
            if (_products != null) ...[
              const SizedBox(height: 16),
              GridView.builder(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                itemCount: _products!.items.length,
                gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: (constraints.maxWidth / 210).floor().clamp(
                    1,
                    5,
                  ),
                  mainAxisSpacing: 12,
                  crossAxisSpacing: 12,
                  mainAxisExtent: 190,
                ),
                itemBuilder: (context, index) =>
                    _productCard(_products!.items[index]),
              ),
              const SizedBox(height: 12),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  TextButton(
                    onPressed: !_loadingProducts && _offset > 0
                        ? () {
                            _offset = (_offset - 20).clamp(0, 100000);
                            unawaited(_loadProducts());
                          }
                        : null,
                    child: const Text('Previous'),
                  ),
                  TextButton(
                    onPressed: !_loadingProducts && _products!.hasMore
                        ? () {
                            _offset = _products!.nextOffset;
                            unawaited(_loadProducts());
                          }
                        : null,
                    child: const Text('Next'),
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    ),
  );

  Widget _productCard(PosProduct product) => Card(
    margin: EdgeInsets.zero,
    child: Padding(
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            product.name,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 4),
          Text(
            product.sku,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontSize: 12),
          ),
          const Spacer(),
          Text(
            '${product.currency} ${Money.formatMinor(product.priceMinor)}',
            style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
          ),
          Text(
            '${product.availableQuantity} ${product.unit} available',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontSize: 12),
          ),
          const SizedBox(height: 8),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              key: Key('add-product-${product.id}'),
              onPressed: _canOrder && product.availableQuantity > 0
                  ? () => _addProduct(product)
                  : null,
              icon: const Icon(Icons.add, size: 16),
              label: const Text('Add'),
            ),
          ),
        ],
      ),
    ),
  );

  Widget _cartPanel({bool pinTotals = false}) => SectionCard(
    padding: 16,
    child: LayoutBuilder(
      builder: (context, constraints) {
        final content = <Widget>[
          Row(
            children: [
              const Icon(Icons.shopping_cart_outlined, size: 22),
              const SizedBox(width: 10),
              const Expanded(
                child: Text(
                  'Current order',
                  style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700),
                ),
              ),
              if (_cart.isNotEmpty)
                IconButton(
                  key: const Key('clear-order'),
                  tooltip: 'Clear cart',
                  onPressed: _canDiscard ? _clearCart : null,
                  icon: const Icon(Icons.delete_outline),
                ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            _shift?.isOpen == true
                ? 'Active shift · ${_context?.branchName ?? ""}'
                : _connected
                ? 'No active shift · Open one in Shifts before checkout'
                : 'No active shift · Not Yet Connected',
            style: const TextStyle(fontSize: 12, color: Color(0xff64748b)),
          ),
          const SizedBox(height: 12),
          if (_connected)
            Row(
              children: [
                Expanded(
                  child: TextButton.icon(
                    key: const Key('select-order-customer'),
                    onPressed: _canOrder ? _chooseCustomer : null,
                    icon: const Icon(Icons.person_outline, size: 18),
                    label: Text(
                      _customer?.name ??
                          (_pending?.customerId == null
                              ? 'Walk-in customer'
                              : 'Customer ${_pending!.customerId!.substring(0, 8)}'),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ),
                if (_customer != null)
                  IconButton(
                    tooltip: 'Use walk-in customer',
                    onPressed: _canOrder
                        ? () => setState(() => _customer = null)
                        : null,
                    icon: const Icon(Icons.close, size: 18),
                  ),
              ],
            ),
          if (_settingsStale)
            const Padding(
              padding: EdgeInsets.only(bottom: 12),
              child: Text(
                'Business settings changed. Clear this order before taking payment. Its existing amounts still use the original currency and tax rate.',
              ),
            ),
          if (_pending != null) ...[
            Text(
              _pendingNotice ?? 'Checkout needs reconciliation.',
              style: const TextStyle(fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 8),
            Text(
              'Request ${_pending!.requestId}',
              style: const TextStyle(fontSize: 11),
            ),
            if (_cart.isEmpty)
              for (final item in _pending!.items)
                Text(
                  '${item.quantity} × Product ${item.productId.substring(0, 8)}',
                ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                OutlinedButton(
                  key: const Key('reconcile-checkout'),
                  onPressed: _busy ? null : _reconcile,
                  child: const Text('Reconcile'),
                ),
                OutlinedButton(
                  key: const Key('retry-checkout'),
                  onPressed: _busy ? null : _retryPending,
                  child: const Text('Retry same checkout'),
                ),
              ],
            ),
          ] else if (_cart.isEmpty)
            FeatureEmptyState(
              icon: Icons.shopping_bag_outlined,
              title: 'Your cart is empty',
              message: _connected
                  ? 'Add an in-stock product. Checkout requires your active shift.'
                  : 'Connect the authorized catalog before taking an order.',
              status: _connected
                  ? FeatureStatus.available
                  : FeatureStatus.notYetConnected,
              compact: true,
            ),
          for (var index = 0; index < _cart.length; index++) _cartLine(index),
          if (_cart.isNotEmpty && _pending == null) ...[
            const Divider(height: 24),
            TextButton.icon(
              key: const Key('order-discount'),
              onPressed:
                  _canOrder &&
                      (widget.role?.allows(AppPermission.approveDiscount) ??
                          false)
                  ? _discount
                  : null,
              icon: const Icon(Icons.discount_outlined, size: 18),
              label: Text(
                (widget.role?.allows(AppPermission.approveDiscount) ?? false)
                    ? 'Order discount'
                    : 'Manager PIN approval · Coming Soon',
              ),
            ),
            if (_discountReason != null)
              Text(
                'Reason: $_discountReason',
                style: const TextStyle(fontSize: 12),
              ),
          ],
          const Divider(height: 24),
          _totalRow('Subtotal', _totals?.subtotalMinor),
          _totalRow('Discount', _totals?.discountMinor),
          _totalRow('Tax', _totals?.taxMinor),
          if (_cart.isNotEmpty && (_totals?.totalMinor ?? 0) == 0)
            const Text(
              'A payable total above zero is required. Free orders are Coming Soon.',
              style: TextStyle(fontSize: 12),
            ),
          const SizedBox(height: 10),
          const Text(
            'Cash / Card / GCash / Maya / Other',
            style: TextStyle(fontSize: 12),
          ),
          const SizedBox(height: 6),
          const Text(
            'Digital tenders require Manual Payment Verification. Provider APIs are not connected.',
            style: TextStyle(
              fontSize: 11,
              height: 1.4,
              color: Color(0xff64748b),
            ),
          ),
          if (_showCart && _error != null)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(
                _error!,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            ),
        ];
        final footer = <Widget>[
          _totalRow(
            'Total',
            _totals?.totalMinor ??
                _pending?.payments.fold<int>(
                  0,
                  (sum, payment) => sum + payment.amountMinor,
                ),
            isTotal: true,
          ),
          const SizedBox(height: 12),
          FilledButton.icon(
            key: const Key('checkout-button'),
            onPressed:
                _canOrder &&
                    _cart.isNotEmpty &&
                    _shift?.isOpen == true &&
                    (_totals?.totalMinor ?? 0) > 0
                ? _checkout
                : null,
            icon: _busy && _pending != null
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.lock_outline, size: 18),
            label: Text(
              _pending != null
                  ? 'Checkout unresolved'
                  : _connected
                  ? 'Checkout'
                  : 'Checkout · Not Yet Connected',
            ),
          ),
        ];
        if (pinTotals && constraints.maxHeight >= 240) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(
                child: ListView(
                  key: const Key('order-cart-scroll'),
                  children: content,
                ),
              ),
              const Divider(height: 20),
              ...footer,
            ],
          );
        }
        return ListView(
          key: const Key('order-cart-scroll'),
          children: [...content, const Divider(height: 20), ...footer],
        );
      },
    ),
  );

  Widget _cartLine(int index) {
    final line = _cart[index];
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            line.product.name,
            style: const TextStyle(fontWeight: FontWeight.w600),
          ),
          Row(
            children: [
              Expanded(
                child: Text(
                  '$_currency ${Money.formatMinor(line.product.priceMinor)} each',
                  style: const TextStyle(fontSize: 12),
                ),
              ),
              IconButton(
                key: Key('decrease-${line.product.id}'),
                tooltip: 'Decrease quantity',
                onPressed: _canOrder
                    ? () => _quantity(index, line.quantity - 1)
                    : null,
                icon: const Icon(Icons.remove_circle_outline),
              ),
              Text('${line.quantity}', key: Key('quantity-${line.product.id}')),
              IconButton(
                key: Key('increase-${line.product.id}'),
                tooltip: 'Increase quantity',
                onPressed: _canOrder
                    ? () => _quantity(index, line.quantity + 1)
                    : null,
                icon: const Icon(Icons.add_circle_outline),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _totalRow(String label, int? minor, {bool isTotal = false}) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 5),
    child: Row(
      children: [
        Expanded(
          child: Text(
            label,
            style: TextStyle(
              fontSize: isTotal ? 20 : 13,
              fontWeight: isTotal ? FontWeight.w700 : FontWeight.w400,
              color: const Color(0xff64748b),
            ),
          ),
        ),
        Flexible(
          child: Text(
            minor == null ? '—' : '$_currency ${Money.formatMinor(minor)}',
            textAlign: TextAlign.end,
            style: TextStyle(
              fontSize: isTotal ? 23 : 14,
              fontWeight: isTotal ? FontWeight.w800 : FontWeight.w500,
              color: const Color(0xff10223f),
            ),
          ),
        ),
      ],
    ),
  );
}

String _publicError(Object error) => error is RepositoryFailure
    ? error.message
    : 'The server could not confirm this action. Check the connection and try again.';
