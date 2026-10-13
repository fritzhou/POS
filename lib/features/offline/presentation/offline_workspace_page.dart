import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:uuid/uuid.dart';

import '../../../core/auth/auth_models.dart';
import '../../../core/services/payment_service.dart';
import '../../../core/sync/outbox_state.dart';
import '../../../core/widgets/status_widgets.dart';
import '../../administration/domain/administration_models.dart';
import '../../catalog/domain/repository_support.dart';
import '../../checkout/domain/checkout_models.dart';
import '../../checkout/presentation/pos_payment_dialog.dart';
import '../../people/domain/people_repository.dart';
import '../../scanning/presentation/keyboard_scanner_capture.dart';
import '../domain/offline_workspace.dart';
import 'offline_receipt_details.dart';

/// A separate, explicitly selected grant-backed device workspace. This page
/// never changes a normal online request into a provisional offline sale.
class OfflineWorkspacePage extends StatefulWidget {
  const OfflineWorkspacePage({
    required this.workspace,
    this.initialBranchId,
    this.peopleRepository,
    this.onLeave,
    this.onLock,
    super.key,
  });

  final OfflineWorkspace workspace;
  final String? initialBranchId;
  final PeopleRepository? peopleRepository;
  final VoidCallback? onLeave, onLock;

  @override
  State<OfflineWorkspacePage> createState() => _OfflineWorkspacePageState();
}

class _OfflineWorkspacePageState extends State<OfflineWorkspacePage> {
  final _search = TextEditingController();
  final _barcode = TextEditingController();
  final _cart = <CartLine>[];
  List<BranchOption> _branches = const [];
  List<OfflineCategory> _categories = const [];
  List<LocalOfflineReceipt> _receipts = const [];
  List<OfflineCheckoutRequest> _savedIntents = const [];
  OfflineWorkspaceStatus? _status;
  PosContext? _context;
  Shift? _shift;
  DataPage<PosProduct>? _products;
  OfflineCheckoutRequest? _pending;
  final _statusElapsed = Stopwatch();
  Timer? _expiryTimer, _searchTimer;
  String? _branchId, _categoryId, _error, _notice;
  bool _busy = true, _loadingProducts = false, _barcodeBusy = false;
  bool _deviceConsent = false;
  int _tab = 0, _generation = 0, _productGeneration = 0, _offset = 0;

  bool get _expired {
    final expiry = _status?.expiresAt;
    if (expiry == null) return false;
    final anchored = _status?.estimatedServerTime;
    // This display guard follows the coordinator's durable server time anchor.
    // Only the coordinator can authorize a capture or detect clock rollback.
    final observed =
        anchored?.add(_statusElapsed.elapsed) ?? DateTime.now().toUtc();
    return !observed.isBefore(expiry);
  }

  void _setStatus(OfflineWorkspaceStatus? status) {
    _status = status;
    _statusElapsed
      ..stop()
      ..reset();
    if (status != null) _statusElapsed.start();
  }

  bool get _canCapture =>
      _status?.active == true &&
      _status?.blockedReason == null &&
      !_expired &&
      (_status?.unresolvedPaymentCount ?? 0) == 0 &&
      (_status?.eventCount ?? 0) < (_status?.maxEvents ?? 0) &&
      (_status?.totalMinor ?? 0) < (_status?.maxTotalMinor ?? 0) &&
      !_busy &&
      _pending == null &&
      _context != null;
  bool get _locked => _busy || _pending != null;
  CartTotals? get _totals {
    if (_cart.isEmpty || _context == null) return null;
    try {
      return CartTotals.calculate(lines: _cart, taxBps: _context!.taxBps);
    } on RepositoryFailure {
      return null;
    }
  }

  @override
  void initState() {
    super.initState();
    _branchId = widget.initialBranchId;
    unawaited(_load());
    _expiryTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted && _status?.active == true && _expired) setState(() {});
    });
  }

  @override
  void didUpdateWidget(covariant OfflineWorkspacePage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.workspace != widget.workspace ||
        oldWidget.initialBranchId != widget.initialBranchId) {
      _generation++;
      _productGeneration++;
      _searchTimer?.cancel();
      _search.clear();
      _barcode.clear();
      _cart.clear();
      _pending = null;
      _barcodeBusy = false;
      _context = null;
      _setStatus(null);
      _receipts = const [];
      _savedIntents = const [];
      _products = null;
      _categories = const [];
      _branches = const [];
      _shift = null;
      _categoryId = null;
      _offset = 0;
      _deviceConsent = false;
      _branchId = widget.initialBranchId;
      unawaited(_load());
    }
  }

  @override
  void dispose() {
    _expiryTimer?.cancel();
    _searchTimer?.cancel();
    _statusElapsed.stop();
    _search.dispose();
    _barcode.dispose();
    super.dispose();
  }

  String _publicError(Object error) => error is RepositoryFailure
      ? error.message
      : error is AuthFailure
      ? error.message
      : 'This operation could not be confirmed. Stored receipts and original payment evidence are preserved.';

  Future<void> _load() async {
    final generation = ++_generation;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final status = await widget.workspace.status(branchId: _branchId);
      List<BranchOption> branches = const [];
      if (status.branchId == null &&
          status.configured &&
          widget.peopleRepository != null) {
        branches = await widget.peopleRepository!.listBranches();
      }
      if (!mounted || generation != _generation) return;
      setState(() {
        _setStatus(status);
        _branchId ??= status.branchId;
        if (branches.isNotEmpty) _branches = branches;
      });
      await _loadCachedScope(generation);
    } catch (error) {
      if (mounted && generation == _generation) {
        setState(() => _error = _publicError(error));
      }
    } finally {
      if (mounted && generation == _generation) setState(() => _busy = false);
    }
  }

  Future<void> _loadCachedScope(int generation) async {
    final branchId = _branchId;
    if (branchId == null) return;
    final receipts = await widget.workspace.listReceipts(branchId: branchId);
    final intents = await widget.workspace.pendingPaymentIntents(
      branchId: branchId,
    );
    if (!mounted || generation != _generation) return;
    setState(() {
      _receipts = receipts;
      _savedIntents = intents;
      _pending ??= intents.firstOrNull;
      if (_pending != null && _cart.isEmpty) _cart.addAll(_pending!.lines);
    });
    if (_status?.active != true) return;
    final context = await widget.workspace.context();
    final categories = await widget.workspace.categories();
    final shift = await widget.workspace.currentShift();
    if (!mounted || generation != _generation) return;
    setState(() {
      _context = context;
      _categories = categories;
      _shift = shift;
    });
    await _loadProducts();
  }

  Future<void> _loadProducts() async {
    if (_context == null || _status?.active != true) return;
    final generation = ++_productGeneration;
    final scope = _generation;
    setState(() => _loadingProducts = true);
    try {
      final result = await widget.workspace.searchProducts(
        query: _search.text.trim(),
        categoryId: _categoryId,
        page: PageRequest(offset: _offset, limit: 20),
      );
      if (mounted && generation == _productGeneration && scope == _generation) {
        setState(() => _products = result);
      }
    } catch (error) {
      if (mounted && generation == _productGeneration && scope == _generation) {
        setState(() => _error = _publicError(error));
      }
    } finally {
      if (mounted && generation == _productGeneration && scope == _generation) {
        setState(() => _loadingProducts = false);
      }
    }
  }

  Future<void> _action(
    Future<void> Function() action, {
    bool allowPending = false,
  }) async {
    if (_busy || (!allowPending && _pending != null)) return;
    final generation = _generation;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await action();
    } catch (error) {
      if (mounted && generation == _generation) {
        setState(() => _error = _publicError(error));
      }
    } finally {
      if (mounted && generation == _generation) setState(() => _busy = false);
    }
  }

  Future<void> _prepare() => _action(() async {
    if (_branchId == null) return;
    final generation = _generation;
    final workspace = widget.workspace;
    final status = await workspace.prepareOnline(_branchId!);
    if (!mounted || generation != _generation) return;
    setState(() {
      _setStatus(status);
      _notice =
          'Signed authorization and a complete branch snapshot are saved. Select Enter offline workspace explicitly.';
    });
  });

  Future<void> _enter() => _action(() async {
    if (_branchId == null) return;
    final generation = _generation;
    final workspace = widget.workspace;
    final status = await workspace.enterOffline(_branchId!);
    if (!mounted || generation != _generation) return;
    setState(() {
      _setStatus(status);
      _notice = null;
    });
    await _loadCachedScope(generation);
  }, allowPending: true);

  Future<void> _changeBranch(String? branchId) async {
    if (branchId == null || branchId == _branchId || _locked) return;
    final generation = ++_generation;
    _productGeneration++;
    _searchTimer?.cancel();
    setState(() {
      _busy = true;
      _branchId = branchId;
      _context = null;
      _receipts = const [];
      _savedIntents = const [];
      _pending = null;
      _cart.clear();
      _products = null;
      _categories = const [];
      _shift = null;
      _categoryId = null;
      _offset = 0;
      _error = null;
      _notice = null;
    });
    try {
      final status = await widget.workspace.status(branchId: branchId);
      if (!mounted || generation != _generation) return;
      setState(() => _setStatus(status));
      await _loadCachedScope(generation);
    } catch (error) {
      if (mounted && generation == _generation) {
        setState(() => _error = _publicError(error));
      }
    } finally {
      if (mounted && generation == _generation) setState(() => _busy = false);
    }
  }

  void _add(PosProduct product) {
    if (!_canCapture) return;
    final index = _cart.indexWhere((line) => line.product.id == product.id);
    final quantity = index < 0 ? 1 : _cart[index].quantity + 1;
    if (quantity > product.availableQuantity) {
      setState(
        () => _error =
            'This device has insufficient projected stock. Cached stock is uncertain; refresh and reconcile online.',
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

  void _replaceCart(List<CartLine> next) {
    if (!_canCapture) return;
    try {
      if (next.isNotEmpty) {
        CartTotals.calculate(lines: next, taxBps: _context!.taxBps);
      }
      setState(() {
        _cart
          ..clear()
          ..addAll(next);
        _error = null;
      });
    } on RepositoryFailure catch (error) {
      setState(() => _error = error.message);
    }
  }

  Future<void> _barcodeLookup() => _lookupBarcode(_barcode.text.trim());

  Future<void> _lookupBarcode(
    String value, {
    bool Function()? scanCurrent,
  }) async {
    if (!_canCapture || _barcodeBusy || value.isEmpty) return;
    final generation = _generation;
    final workspace = widget.workspace;
    setState(() {
      _barcodeBusy = true;
      _error = null;
    });
    try {
      final product = await workspace.lookupProductByBarcode(value);
      if (!mounted ||
          generation != _generation ||
          !_canCapture ||
          (scanCurrent != null && !scanCurrent())) {
        return;
      }
      if (product == null) {
        setState(
          () => _error =
              'No product in this signed snapshot has that exact barcode.',
        );
      } else {
        _add(product);
        _barcode.clear();
      }
    } catch (error) {
      if (mounted && generation == _generation) {
        setState(() => _error = _publicError(error));
      }
    } finally {
      if (mounted && generation == _generation) {
        setState(() => _barcodeBusy = false);
      }
    }
  }

  CheckoutPayment _payment(TenderEvidence payment) => CheckoutPayment(
    method: CheckoutPaymentMethod.values.byName(payment.method.name),
    amountMinor: payment.appliedMinor,
    tenderedMinor: payment.method == PaymentMethod.cash
        ? payment.receivedMinor
        : null,
    manualConfirmed: payment.method != PaymentMethod.cash,
    reference: payment.reference,
  );

  TenderEvidence _tender(CheckoutPayment payment, String currency) =>
      TenderEvidence(
        method: PaymentMethod.values.byName(payment.method.name),
        verification: payment.method == CheckoutPaymentMethod.cash
            ? PaymentVerification.cashCounted
            : PaymentVerification.manual,
        appliedMinor: payment.amountMinor,
        receivedMinor: payment.tenderedMinor ?? payment.amountMinor,
        changeMinor:
            (payment.tenderedMinor ?? payment.amountMinor) -
            payment.amountMinor,
        currency: currency,
        reference: payment.reference,
      );

  Future<void> _checkout() async {
    if (!_canCapture || _totals == null || _totals!.totalMinor <= 0) return;
    await _collectPayments();
  }

  Future<void> _collectPayments({OfflineCheckoutRequest? original}) async {
    if (_busy || _context == null) return;
    final generation = _generation;
    final workspace = widget.workspace;
    final branchId = _branchId;
    final lines = List<CartLine>.unmodifiable(original?.lines ?? _cart);
    final total =
        original?.expectedTotalMinor ??
        CartTotals.calculate(lines: lines, taxBps: _context!.taxBps).totalMinor;
    final currency = _context!.currency;
    final requestId = original?.requestId ?? const Uuid().v4();
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final status = await workspace.status(branchId: branchId);
      if (!mounted || generation != _generation) return;
      setState(() => _setStatus(status));
      if (!status.active || status.blockedReason != null || _expired) {
        setState(
          () => _error =
              'Offline authorization is unavailable or expired. Do not collect payment for a new offline sale. Preserved partial payments remain available for review.',
        );
        return;
      }
      if ((status.unresolvedPaymentCount > 0 && original == null) ||
          status.eventCount >= status.maxEvents ||
          status.totalMinor + total > status.maxTotalMinor) {
        setState(
          () => _error =
              'Resolve pending payment evidence or prepare a new authorized grant before collecting payment. This order exceeds the remaining grant allowance.',
        );
        return;
      }
      final payments = await showDialog<List<TenderEvidence>>(
        context: context,
        barrierDismissible: false,
        builder: (context) => PosPaymentDialog(
          totalMinor: total,
          currency: currency,
          initialTenders:
              original?.payments.map((p) => _tender(p, currency)).toList() ??
              const [],
          onRecordTender: (index, tender) async {
            if (!mounted || generation != _generation) {
              throw const RepositoryFailure(
                RepositoryFailureType.permissionDenied,
                'This workspace was locked. Do not collect another payment.',
              );
            }
            await workspace.recordPaymentFragment(
              requestId: requestId,
              lines: lines,
              index: index,
              payment: _payment(tender),
            );
            final intents = await workspace.pendingPaymentIntents(
              branchId: branchId,
            );
            if (mounted && generation == _generation) {
              setState(() {
                _savedIntents = intents;
                _pending = intents
                    .where((intent) => intent.requestId == requestId)
                    .firstOrNull;
              });
            }
          },
          completionNotice:
              'Each confirmed tender is saved before appearing in this list. Closing preserves partial payments and the original order; continue only its remaining amount. This creates a provisional device receipt awaiting synchronization. Cash must be counted by you. Digital payment requires verification in the actual provider or terminal; provider APIs are not connected.',
          submitLabel: 'Save provisional receipt',
        ),
      );
      if (!mounted || generation != _generation || payments == null) return;
      setState(
        () => _pending = OfflineCheckoutRequest(
          requestId: requestId,
          lines: lines,
          payments: payments.map(_payment).toList(),
          expectedTotalMinor: total,
        ),
      );
      await _persistPending();
    } catch (error) {
      if (mounted && generation == _generation) {
        setState(() => _error = _publicError(error));
      }
    } finally {
      if (mounted && generation == _generation) {
        try {
          final intents = await workspace.pendingPaymentIntents(
            branchId: branchId,
          );
          final status = await workspace.status(branchId: branchId);
          if (mounted && generation == _generation) {
            setState(() {
              _savedIntents = intents;
              _pending ??= intents
                  .where((intent) => intent.requestId == requestId)
                  .firstOrNull;
              _setStatus(status);
            });
          }
        } catch (_) {
          // A prior error already explains uncertainty; never clear evidence.
        }
        if (mounted && generation == _generation) setState(() => _busy = false);
      }
    }
  }

  Future<void> _persistPending() async {
    final generation = _generation;
    final pending = _pending;
    if (pending == null) return;
    final receipt = await widget.workspace.checkout(pending);
    if (receipt.draft.eventId != pending.requestId ||
        receipt.draft.scope.branchId != _branchId) {
      throw const RepositoryFailure(
        RepositoryFailureType.unavailable,
        'The saved receipt could not be matched to this order. Keep the original payment evidence and reconcile it.',
      );
    }
    if (!mounted || generation != _generation) return;
    setState(() {
      _pending = null;
      _cart.clear();
      _savedIntents = _savedIntents
          .where((intent) => intent.requestId != pending.requestId)
          .toList();
      _notice =
          'Provisional receipt recorded locally · PENDING synchronization. No server or provider acceptance is claimed.';
    });
    await _showReceipt(receipt);
    if (!mounted || generation != _generation) return;
    final status = await widget.workspace.status(branchId: _branchId);
    if (!mounted || generation != _generation) return;
    setState(() => _setStatus(status));
    await _loadCachedScope(_generation);
  }

  Future<void> _copyPending() => _action(() async {
    final generation = _generation;
    final request = _pending;
    if (request == null) return;
    await Clipboard.setData(
      ClipboardData(
        text: request.expectedTotalMinor != null
            ? await widget.workspace.exportReceipt(request.requestId)
            : jsonEncode({
                'type': 'unresolved_offline_payment_intent',
                'request_id': request.requestId,
                'branch_id': _branchId,
                'grant_id': _status?.grantId,
                'items': request.lines
                    .map(
                      (line) => {
                        'product_id': line.product.id,
                        'quantity': line.quantity,
                        'unit_price_minor': line.product.priceMinor,
                        'currency': line.product.currency,
                      },
                    )
                    .toList(),
                'payments': request.payments
                    .map(
                      (payment) => {
                        'method': payment.method.name,
                        'amount_minor': payment.amountMinor,
                        'tendered_minor': payment.tenderedMinor,
                        'manual_confirmed': payment.manualConfirmed,
                        'reference': payment.reference,
                      },
                    )
                    .toList(),
              }),
      ),
    );
    if (mounted && generation == _generation) {
      setState(
        () => _notice =
            'Unresolved payment evidence copied for an authorized reviewer. It is not a signed or confirmed receipt.',
      );
    }
  }, allowPending: true);

  Future<void> _sync() => _action(() async {
    if (_branchId == null) return;
    final generation = _generation;
    final workspace = widget.workspace;
    final branchId = _branchId!;
    final summary = await workspace.synchronize(branchId);
    final status = await workspace.status(branchId: branchId);
    final receipts = await workspace.listReceipts(branchId: branchId);
    if (!mounted || generation != _generation) return;
    setState(() {
      _setStatus(status);
      _receipts = receipts;
      _notice =
          '${summary.accepted} accepted · ${summary.failed} need review · ${summary.remaining} remain queued · ${summary.pulled} changes downloaded.${summary.stoppedReason == null ? '' : ' Synchronization stopped before all records were confirmed.'}';
    });
    await _loadProducts();
  }, allowPending: true);

  Future<void> _leave({bool lock = false}) => _action(() async {
    final generation = _generation;
    final workspace = widget.workspace;
    if (lock) {
      await workspace.suspend();
    } else {
      await workspace.leaveOffline();
    }
    if (mounted && generation == _generation) {
      (lock ? widget.onLock : widget.onLeave)?.call();
    }
  }, allowPending: lock);

  @override
  Widget build(BuildContext context) => KeyboardScannerCapture(
    available: _canCapture && _tab == 0,
    scopeToken: (widget.workspace, _generation, _branchId),
    onBarcode: (barcode, current) =>
        _lookupBarcode(barcode, scanCurrent: current),
    builder: (context, scannerControls) => Scaffold(
      backgroundColor: const Color(0xfff5f7fb),
      appBar: AppBar(
        title: const Text('Offline workspace'),
        automaticallyImplyLeading: false,
        actions: [
          if (widget.onLock != null)
            IconButton(
              tooltip: 'Lock offline workspace',
              onPressed: _busy ? null : () => _leave(lock: true),
              icon: const Icon(Icons.lock_outline),
            ),
          if (widget.onLeave != null)
            IconButton(
              tooltip: 'Leave offline workspace',
              onPressed: _locked ? null : _leave,
              icon: const Icon(Icons.close),
            ),
        ],
      ),
      body: SafeArea(
        child: ListView(
          key: const Key('offline-workspace-scroll'),
          padding: const EdgeInsets.all(16),
          children: [
            _statusCard(),
            if (_error != null)
              Padding(
                padding: const EdgeInsets.only(top: 12),
                child: Text(
                  _error!,
                  key: const Key('offline-error'),
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
              ),
            if (_notice != null)
              Padding(
                padding: const EdgeInsets.only(top: 12),
                child: Text(_notice!),
              ),
            if (_busy)
              const Padding(
                padding: EdgeInsets.all(12),
                child: LinearProgressIndicator(),
              ),
            const SizedBox(height: 16),
            if (_status?.active != true) _preparation(),
            if (_pending != null) _pendingCard(),
            const SizedBox(height: 16),
            if (_branchId != null) ...[
              SegmentedButton<int>(
                key: const Key('offline-tabs'),
                segments: const [
                  ButtonSegment(value: 0, label: Text('POS')),
                  ButtonSegment(value: 1, label: Text('Receipts')),
                  ButtonSegment(value: 2, label: Text('Sync')),
                ],
                selected: {_tab},
                onSelectionChanged: (value) =>
                    setState(() => _tab = value.single),
              ),
              const SizedBox(height: 16),
              if (_tab == 0 && _context != null) _pos(scannerControls),
              if (_tab == 1) _receiptList(),
              if (_tab == 2) _syncPanel(),
            ],
          ],
        ),
      ),
    ),
  );

  Widget _statusCard() => SectionCard(
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Explicit offline mode',
          style: TextStyle(fontWeight: FontWeight.w700, fontSize: 18),
        ),
        const SizedBox(height: 8),
        const Text(
          'Sales use a signed branch snapshot and are provisional until verified synchronization. Stock is cached and uncertain; another device may sell the same items.',
        ),
        const SizedBox(height: 12),
        StatusPill(
          label: _status?.configured != true
              ? 'Offline signing · Not Yet Connected'
              : _expired
              ? 'Authorization expired · new sales blocked'
              : _status != null &&
                    (_status!.eventCount >= _status!.maxEvents ||
                        _status!.totalMinor >= _status!.maxTotalMinor)
              ? 'Grant allowance exhausted · new sales blocked'
              : _status?.active == true
              ? 'Grant-backed local checkout'
              : 'Offline preparation required',
        ),
        if (_status?.branchName != null)
          Padding(
            padding: const EdgeInsets.only(top: 12),
            child: Text('Branch: ${_status!.branchName}'),
          ),
        if (_status?.expiresAt != null)
          Text('Grant expires: ${_status!.expiresAt!.toLocal()}'),
        Text('Snapshot: ${_status?.snapshotAt?.toLocal() ?? 'Not prepared'}'),
        Text(
          'Last successful sync: ${_status?.lastSyncAt?.toLocal() ?? 'Never'}',
        ),
        Text(
          'Pending: ${_status?.pendingCount ?? 0} · Failed: ${_status?.failedCount ?? 0}',
        ),
        if ((_status?.unresolvedPaymentCount ?? 0) > 0)
          Text(
            'Unresolved payment evidence: ${_status!.unresolvedPaymentCount} · new payments blocked',
          ),
        if (_status?.prepared == true)
          Text(
            'Grant usage: ${_status!.eventCount}/${_status!.maxEvents} sales',
          ),
        if (_status?.prepared == true && _context != null)
          Text(
            'Captured amount: ${_context!.currency} ${Money.formatMinor(_status!.totalMinor)} / ${Money.formatMinor(_status!.maxTotalMinor)} authorized',
          ),
        if (_status?.blockedReason != null)
          const Padding(
            padding: EdgeInsets.only(top: 12),
            child: Text(
              'Offline entry or new sales are blocked. Resolve authorization or an uncertain online operation first.',
            ),
          ),
        if (_shift != null)
          Padding(
            padding: const EdgeInsets.only(top: 12),
            child: Text(
              'Cached shift opened online: ${_shift!.openedAt.toLocal()} · ${_shift!.currency}. Synchronize and release the grant before closing online.',
            ),
          ),
      ],
    ),
  );

  Widget _preparation() => SectionCard(
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Text(
          'Prepare while online',
          style: TextStyle(fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: 8),
        const Text(
          'Use your verified account on this enrolled device. Open your own shift online first. Preparation verifies device proof, signed authorization and a complete cost-free catalog snapshot. No password or PIN sign-in is available offline.',
        ),
        if (_branches.isNotEmpty) ...[
          const SizedBox(height: 16),
          DropdownButtonFormField<String>(
            key: const Key('offline-branch'),
            initialValue: _branchId,
            isExpanded: true,
            decoration: const InputDecoration(
              labelText: 'Choose branch explicitly',
            ),
            items: _branches
                .map(
                  (branch) => DropdownMenuItem(
                    value: branch.id,
                    child: Text(branch.name, overflow: TextOverflow.ellipsis),
                  ),
                )
                .toList(),
            onChanged: _locked ? null : _changeBranch,
          ),
        ],
        CheckboxListTile(
          key: const Key('offline-device-consent'),
          value: _deviceConsent,
          contentPadding: EdgeInsets.zero,
          controlAffinity: ListTileControlAffinity.leading,
          title: const Text('Authorize offline sales on this device'),
          subtitle: const Text(
            'Save device enrollment keys securely for bounded offline access. Restarting also requires the same remembered account. Locking or signing out ends offline access and preserves paid records.',
          ),
          onChanged: _locked
              ? null
              : (consent) => setState(() => _deviceConsent = consent ?? false),
        ),
        const SizedBox(height: 16),
        FilledButton.icon(
          key: const Key('prepare-offline'),
          onPressed:
              !_locked &&
                  _status?.configured == true &&
                  _deviceConsent &&
                  _branchId != null &&
                  _status?.active != true
              ? _prepare
              : null,
          icon: const Icon(Icons.cloud_download_outlined),
          label: const Text('Prepare offline access online'),
        ),
        if (_status?.prepared == true) ...[
          const SizedBox(height: 8),
          OutlinedButton(
            key: const Key('enter-offline'),
            onPressed:
                !_busy &&
                    !_expired &&
                    _status?.blockedReason == null &&
                    _status?.branchId == _branchId
                ? _enter
                : null,
            child: const Text('Enter offline workspace'),
          ),
        ],
      ],
    ),
  );

  Widget _pendingCard() => Padding(
    padding: const EdgeInsets.only(top: 16),
    child: SectionCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text(
            'Local checkout needs reconciliation',
            style: TextStyle(fontWeight: FontWeight.w700),
          ),
          const Text(
            'The original order and saved payment evidence are frozen. Continue only an incomplete payment allocation under valid authorization, or retry the original completed save. Do not collect saved payments again or create a replacement sale.',
          ),
          SelectableText(_pending!.requestId),
          if (_pending!.expectedTotalMinor != null)
            Text(
              'Saved ${Money.formatMinor(_pending!.payments.fold<int>(0, (sum, payment) => sum + payment.amountMinor))} of ${Money.formatMinor(_pending!.expectedTotalMinor!)} · ${_pending!.payments.length} immutable payment(s)',
            ),
          if (_savedIntents.length > 1)
            DropdownButtonFormField<String>(
              initialValue: _pending!.requestId,
              isExpanded: true,
              decoration: const InputDecoration(
                labelText: 'Preserved payment intent',
              ),
              items: _savedIntents
                  .map(
                    (intent) => DropdownMenuItem(
                      value: intent.requestId,
                      child: Text(
                        intent.requestId,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  )
                  .toList(),
              onChanged: _busy
                  ? null
                  : (id) => setState(() {
                      _pending = _savedIntents.firstWhere(
                        (intent) => intent.requestId == id,
                      );
                      _cart
                        ..clear()
                        ..addAll(_pending!.lines);
                    }),
            ),
          const SizedBox(height: 12),
          OutlinedButton(
            key: const Key('retry-local-checkout'),
            onPressed: _busy
                ? null
                : _pending!.partial
                ? (_status?.active == true &&
                          !_expired &&
                          _status?.blockedReason == null
                      ? () => _collectPayments(original: _pending)
                      : null)
                : () => _action(_persistPending, allowPending: true),
            child: Text(
              _pending!.partial
                  ? 'Continue remaining payment'
                  : 'Retry original local save',
            ),
          ),
          TextButton(
            onPressed: _busy ? null : _copyPending,
            child: const Text('Copy unresolved payment evidence'),
          ),
        ],
      ),
    ),
  );

  Widget _pos(Widget scannerControls) => LayoutBuilder(
    builder: (context, constraints) {
      if (constraints.maxWidth < 820) {
        return Column(
          children: [
            _catalog(scannerControls),
            const SizedBox(height: 16),
            _cartCard(),
          ],
        );
      }
      return Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(flex: 3, child: _catalog(scannerControls)),
          const SizedBox(width: 16),
          Expanded(flex: 2, child: _cartCard()),
        ],
      );
    },
  );

  Widget _catalog(Widget scannerControls) => SectionCard(
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        TextField(
          key: const Key('offline-product-search'),
          controller: _search,
          decoration: const InputDecoration(
            labelText: 'Search cached products',
            prefixIcon: Icon(Icons.search),
          ),
          onChanged: (_) {
            _searchTimer?.cancel();
            _searchTimer = Timer(const Duration(milliseconds: 250), () {
              _offset = 0;
              unawaited(_loadProducts());
            });
          },
        ),
        const SizedBox(height: 12),
        TextField(
          key: const Key('offline-barcode'),
          controller: _barcode,
          decoration: InputDecoration(
            labelText: 'Exact cached barcode',
            suffixIcon: IconButton(
              tooltip: 'Look up exact barcode',
              onPressed: _canCapture && !_barcodeBusy ? _barcodeLookup : null,
              icon: const Icon(Icons.qr_code_scanner),
            ),
          ),
          onSubmitted: (_) {
            if (_canCapture) unawaited(_barcodeLookup());
          },
        ),
        const SizedBox(height: 12),
        scannerControls,
        if (_categories.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 12),
            child: DropdownButtonFormField<String>(
              key: const Key('offline-category'),
              initialValue: _categoryId,
              decoration: const InputDecoration(labelText: 'Category'),
              items: [
                const DropdownMenuItem(
                  value: null,
                  child: Text('All categories'),
                ),
                ..._categories.map(
                  (category) => DropdownMenuItem(
                    value: category.id,
                    child: Text(category.name),
                  ),
                ),
              ],
              onChanged: (category) {
                setState(() {
                  _categoryId = category;
                  _offset = 0;
                });
                unawaited(_loadProducts());
              },
            ),
          ),
        const SizedBox(height: 16),
        if (_loadingProducts) const LinearProgressIndicator(),
        if (_products?.items.isEmpty ?? true)
          const Padding(
            padding: EdgeInsets.all(16),
            child: Text('No cached products match.'),
          ),
        for (final product in _products?.items ?? <PosProduct>[])
          ListTile(
            contentPadding: EdgeInsets.zero,
            title: Text(product.name),
            subtitle: Text(
              '${product.sku} · ${product.currency} ${Money.formatMinor(product.priceMinor)}\nProjected quantity ${product.availableQuantity} · uncertain',
            ),
            isThreeLine: true,
            trailing: IconButton(
              key: Key('offline-add-${product.id}'),
              tooltip: 'Add ${product.name}',
              onPressed: _canCapture && product.availableQuantity > 0
                  ? () => _add(product)
                  : null,
              icon: const Icon(Icons.add_circle_outline),
            ),
          ),
        if (_offset > 0 || _products?.hasMore == true)
          Wrap(
            spacing: 8,
            children: [
              TextButton(
                onPressed: _offset > 0 && !_loadingProducts
                    ? () {
                        _offset = (_offset - 20).clamp(0, 1000);
                        unawaited(_loadProducts());
                      }
                    : null,
                child: const Text('Previous'),
              ),
              TextButton(
                onPressed: _products?.hasMore == true && !_loadingProducts
                    ? () {
                        _offset += 20;
                        unawaited(_loadProducts());
                      }
                    : null,
                child: const Text('Next'),
              ),
            ],
          ),
      ],
    ),
  );

  Widget _cartCard() => SectionCard(
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Text(
          'Offline order',
          style: TextStyle(fontWeight: FontWeight.w700, fontSize: 18),
        ),
        const SizedBox(height: 12),
        if (_cart.isEmpty) const Text('Add cached products to begin.'),
        for (final line in _cart)
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(line.product.name),
                Wrap(
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    IconButton(
                      tooltip: 'Reduce ${line.product.name}',
                      onPressed: _canCapture
                          ? () {
                              final next = [..._cart];
                              final index = next.indexOf(line);
                              if (line.quantity == 1) {
                                next.removeAt(index);
                              } else {
                                next[index] = line.withQuantity(
                                  line.quantity - 1,
                                );
                              }
                              _replaceCart(next);
                            }
                          : null,
                      icon: const Icon(Icons.remove_circle_outline),
                    ),
                    Text('${line.quantity}'),
                    IconButton(
                      tooltip: 'Increase ${line.product.name}',
                      onPressed: _canCapture ? () => _add(line.product) : null,
                      icon: const Icon(Icons.add_circle_outline),
                    ),
                    Text(
                      '${line.product.currency} ${Money.formatMinor(line.product.priceMinor * line.quantity)}',
                    ),
                  ],
                ),
              ],
            ),
          ),
        const Divider(height: 24),
        Text(
          'Tax ${_context!.currency} ${Money.formatMinor(_totals?.taxMinor ?? 0)}',
        ),
        Text(
          'Total ${_context!.currency} ${Money.formatMinor(_totals?.totalMinor ?? 0)}',
          style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 18),
        ),
        const SizedBox(height: 16),
        FilledButton.icon(
          key: const Key('offline-checkout'),
          onPressed: _canCapture && (_totals?.totalMinor ?? 0) > 0
              ? _checkout
              : null,
          icon: const Icon(Icons.receipt_long_outlined),
          label: const Text('Record provisional sale'),
        ),
        TextButton(
          onPressed: _canCapture && _cart.isNotEmpty
              ? () => _replaceCart([])
              : null,
          child: const Text('Clear unpaid order'),
        ),
        const Text(
          'Discounts, customer changes, refunds, voids and shift changes require online authorization.',
          style: TextStyle(fontSize: 12),
        ),
      ],
    ),
  );

  Widget _receiptList() => SectionCard(
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Text(
          'Original provisional receipts',
          style: TextStyle(fontWeight: FontWeight.w700, fontSize: 18),
        ),
        const Text(
          'Synchronization adds a server link without rewriting the original paid snapshot.',
        ),
        if (_receipts.isEmpty)
          const Padding(
            padding: EdgeInsets.all(16),
            child: Text('No offline receipts are stored for this scope.'),
          ),
        for (final receipt in _receipts)
          ListTile(
            contentPadding: EdgeInsets.zero,
            title: Text(receipt.draft.receiptNumber),
            subtitle: Text(
              '${offlineReceiptStatus(receipt)}\n${receipt.draft.currency} ${Money.formatMinor(receipt.draft.totalMinor)}',
            ),
            isThreeLine: true,
            onTap: () => _showReceipt(receipt),
          ),
      ],
    ),
  );

  Future<void> _showReceipt(LocalOfflineReceipt receipt) {
    final workspace = widget.workspace;
    final generation = _generation;
    final branch = _branchId;
    return showOfflineReceipt(
      context,
      receipt,
      workspace,
      isCurrent: () =>
          mounted &&
          generation == _generation &&
          identical(workspace, widget.workspace) &&
          branch == _branchId,
    );
  }

  Widget _syncPanel() => SectionCard(
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Text(
          'Synchronize and reconcile',
          style: TextStyle(fontWeight: FontWeight.w700, fontSize: 18),
        ),
        const SizedBox(height: 8),
        const Text(
          'Reconnect with this verified account. Each original event is retried with its saved identity, digest and signature. Unconfirmed or failed records remain on this device. A mismatch is never treated as acceptance.',
        ),
        const SizedBox(height: 16),
        FilledButton.icon(
          key: const Key('synchronize-offline'),
          onPressed: !_busy && _status?.configured == true ? _sync : null,
          icon: const Icon(Icons.sync),
          label: const Text('Synchronize original events'),
        ),
        const SizedBox(height: 8),
        OutlinedButton(
          key: const Key('release-offline-grant'),
          onPressed:
              !_locked &&
                  _status?.prepared == true &&
                  _status?.pendingCount == 0 &&
                  _status?.failedCount == 0 &&
                  _status?.unresolvedPaymentCount == 0
              ? () => _action(() async {
                  final generation = _generation;
                  final workspace = widget.workspace;
                  final status = await workspace.releaseGrant(_branchId!);
                  if (mounted && generation == _generation) {
                    setState(() {
                      _setStatus(status);
                      _notice =
                          'Grant released. Return online to close your shift.';
                    });
                  }
                })
              : null,
          child: const Text('Release grant to allow online shift close'),
        ),
        for (final receipt in _receipts.where(
          (receipt) =>
              receipt.status == OutboxStatus.failed ||
              receipt.reconciliationCode != null,
        ))
          Padding(
            padding: const EdgeInsets.only(top: 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  receipt.draft.receiptNumber,
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
                Text(offlineReceiptStatus(receipt)),
                const Text(
                  'Retain the original paid event. An authorized reviewer must resolve any posting or stock conflict.',
                ),
                TextButton(
                  onPressed: () => _showReceipt(receipt),
                  child: const Text('Review and copy original record'),
                ),
                if (receipt.status == OutboxStatus.failed)
                  OutlinedButton(
                    onPressed: !_locked
                        ? () => _action(() async {
                            final generation = _generation;
                            final workspace = widget.workspace;
                            final branchId = _branchId!;
                            final retry = await workspace.retryFailed(
                              branchId: branchId,
                              eventId: receipt.draft.eventId,
                            );
                            final status = await workspace.status(
                              branchId: branchId,
                            );
                            final receipts = await workspace.listReceipts(
                              branchId: branchId,
                            );
                            if (mounted && generation == _generation) {
                              setState(() {
                                _setStatus(status);
                                _receipts = receipts;
                                _notice = retry
                                    ? 'Original event queued for a bounded retry. Synchronize to confirm its outcome.'
                                    : 'This record needs manual review and cannot be silently retried.';
                              });
                            }
                          })
                        : null,
                    child: const Text('Request retry of original event'),
                  ),
              ],
            ),
          ),
      ],
    ),
  );
}
