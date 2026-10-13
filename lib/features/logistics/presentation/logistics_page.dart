import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:uuid/uuid.dart';
import '../../../core/operations/operation_journal.dart';
import '../../../core/security/app_role.dart';
import '../../../core/widgets/status_widgets.dart';
import '../../../app/config/feature_status.dart';
import '../../administration/domain/administration_models.dart';
import '../../catalog/domain/catalog_models.dart';
import '../../catalog/domain/catalog_repository.dart';
import '../../catalog/domain/repository_support.dart';
import '../../people/domain/people_repository.dart';
import '../../purchases/domain/purchase_models.dart';
import '../../purchases/domain/purchase_repository.dart';
import '../../inventory/presentation/operations_ui_support.dart';
import '../data/supabase_logistics_repository.dart';
import '../domain/logistics_models.dart';

class LogisticsPage extends StatefulWidget {
  const LogisticsPage({
    super.key,
    this.repository,
    this.peopleRepository,
    this.catalogRepository,
    this.purchaseRepository,
    this.role,
    this.branchesOnly = false,
    this.isPreview = true,
    this.onScopeChanged,
  });
  final SupabaseLogisticsRepository? repository;
  final PeopleRepository? peopleRepository;
  final CatalogRepository? catalogRepository;
  final PurchaseRepository? purchaseRepository;
  final AppRole? role;
  final bool branchesOnly, isPreview;
  final Future<void> Function()? onScopeChanged;
  @override
  State<LogisticsPage> createState() => _LogisticsPageState();
}

class _Lease extends ChangeNotifier {
  bool active = true, closed = false;
  void invalidate() {
    active = false;
    if (WidgetsBinding.instance.schedulerPhase ==
        SchedulerPhase.persistentCallbacks) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!closed) notifyListeners();
      });
    } else if (!closed) {
      notifyListeners();
    }
  }

  @override
  void dispose() {
    closed = true;
    super.dispose();
  }
}

class _Frozen {
  const _Frozen(this.id, this.run, this.refreshScope);
  final String id;
  final Future<Object> Function() run;
  final bool refreshScope;
}

class _LogisticsPageState extends State<LogisticsPage> {
  List<BranchOption> _choices = [];
  String? _branch, _error, _notice;
  bool _busy = false, _scopeBlocked = false;
  int _epoch = 0, _tab = 0, _offset = 0;
  DataPage<ManagedBranch>? _branches;
  DataPage<StockTransfer>? _transfers;
  DataPage<LogisticsAction>? _returns;
  List<PendingOperation> _pending = [];
  Map<String, dynamic>? _capabilities;
  _Frozen? _frozen;
  _Lease? _lease;
  bool get _connected =>
      !widget.isPreview &&
      widget.repository != null &&
      (widget.branchesOnly
          ? [AppRole.owner, AppRole.admin].contains(widget.role)
          : (widget.role?.allows(AppPermission.viewInventory) ?? false));
  bool get _blocked =>
      _busy || _scopeBlocked || _frozen != null || _pending.isNotEmpty;
  @override
  void initState() {
    super.initState();
    if (_connected) _load();
  }

  @override
  void didUpdateWidget(LogisticsPage old) {
    super.didUpdateWidget(old);
    if (old.repository != widget.repository ||
        old.role != widget.role ||
        old.isPreview != widget.isPreview ||
        old.peopleRepository != widget.peopleRepository) {
      _epoch++;
      _lease?.invalidate();
      _choices = [];
      _branch = null;
      _branches = null;
      _transfers = null;
      _returns = null;
      _pending = [];
      _frozen = null;
      _error = null;
      _notice = null;
      _busy = false;
      _scopeBlocked = false;
      _offset = 0;
      if (_connected) _load();
    }
  }

  @override
  void dispose() {
    _epoch++;
    _lease?.invalidate();
    super.dispose();
  }

  Future<T?> _dialog<T>(Widget Function(_Lease) builder) async {
    final lease = _Lease();
    _lease = lease;
    try {
      return await showDialog<T>(
        context: context,
        builder: (_) => ListenableBuilder(
          listenable: lease,
          builder: (_, _) => lease.active
              ? builder(lease)
              : AlertDialog(
                  title: const Text('Business context changed'),
                  content: const Text(
                    'The original saved request stays with its account.',
                  ),
                  actions: [
                    TextButton(
                      onPressed: () => Navigator.pop(context),
                      child: const Text('Close'),
                    ),
                  ],
                ),
        ),
      );
    } finally {
      lease.dispose();
      if (identical(_lease, lease)) _lease = null;
    }
  }

  Future<void> _load() async {
    if (!_connected) return;
    final epoch = ++_epoch;
    final repo = widget.repository!;
    setState(() {
      _busy = true;
      _error = null;
      _branches = null;
      _transfers = null;
      _returns = null;
    });
    try {
      final pending = await repo.pending();
      if (!mounted || epoch != _epoch) return;
      _pending = pending;
      if (widget.branchesOnly) {
        final caps = await repo.branchContext();
        final branches = await repo.branches(
          page: PageRequest(offset: _offset, limit: 20),
        );
        if (!mounted || epoch != _epoch) return;
        setState(() {
          _capabilities = caps;
          _branches = branches;
        });
      } else {
        final choices = (await widget.peopleRepository!.listBranches())
            .where((b) => repo.branchIds.contains(b.id))
            .toList();
        if (!mounted || epoch != _epoch) return;
        final branch = choices.any((b) => b.id == _branch)
            ? _branch
            : choices.firstOrNull?.id;
        final transfers = branch == null || _tab != 0
            ? null
            : await repo.transfers(
                branch,
                page: PageRequest(offset: _offset, limit: 20),
              );
        final returns = branch == null || _tab != 1
            ? null
            : await repo.returns(
                branch,
                page: PageRequest(offset: _offset, limit: 20),
              );
        if (!mounted || epoch != _epoch) return;
        setState(() {
          _choices = choices;
          _branch = branch;
          _transfers = transfers;
          _returns = returns;
        });
      }
    } catch (error) {
      if (mounted && epoch == _epoch) {
        setState(() => _error = operationError(error));
      }
    } finally {
      if (mounted && epoch == _epoch) setState(() => _busy = false);
    }
  }

  Future<void> _refreshScope() async {
    final epoch = _epoch;
    if (widget.onScopeChanged == null) {
      setState(() => _scopeBlocked = true);
      return;
    }
    try {
      await widget.onScopeChanged!();
      if (mounted && epoch == _epoch) {
        setState(() => _scopeBlocked = false);
      }
    } catch (_) {
      if (mounted && epoch == _epoch) {
        setState(() {
          _scopeBlocked = true;
          _error =
              'Branch change accepted. Refresh business access before another change.';
        });
      }
    }
  }

  Future<void> _commit(_Frozen action) async {
    if (_busy) return;
    final epoch = _epoch;
    final wasUnknown = _frozen?.id == action.id;
    setState(() {
      _busy = true;
      _frozen = action;
      _error = null;
      _notice = null;
    });
    try {
      await action.run();
      if (!mounted || epoch != _epoch) return;
      setState(() {
        _frozen = null;
        _notice =
            'Original request confirmed by the server. Do not repeat physical goods movement.';
      });
      if (action.refreshScope) await _refreshScope();
    } catch (error) {
      if (mounted && epoch == _epoch) {
        setState(() {
          _error = operationError(error);
          if (!wasUnknown && !operationMayBeUnconfirmed(error)) _frozen = null;
        });
      }
    } finally {
      if (mounted && epoch == _epoch) setState(() => _busy = false);
    }
    if (mounted && epoch == _epoch) {
      final error = _error;
      await _load();
      if (mounted && epoch + 1 == _epoch && error != null) {
        setState(() => _error = error);
      }
    }
  }

  Future<void> _editBranch([ManagedBranch? original]) async {
    if (_blocked || _capabilities == null) return;
    final epoch = _epoch, repo = widget.repository!;
    final data = await _dialog<Map<String, dynamic>>(
      (_) => _BranchForm(
        original: original,
        canSetActive: _capabilities!['can_set_active'] == true,
      ),
    );
    if (!mounted ||
        epoch != _epoch ||
        data == null ||
        repo != widget.repository) {
      return;
    }
    final id = const Uuid().v4(),
        anchor = (repo.branchIds.toList()..sort()).first;
    await _commit(
      _Frozen(
        id,
        () => repo.saveBranch(
          anchor: anchor,
          original: original,
          name: data['name'],
          code: data['code'],
          address: data['address'],
          active: data['active'],
          reason: data['reason'],
          requestId: id,
        ),
        original == null || original.active != data['active'],
      ),
    );
  }

  Future<void> _dispatch() async {
    if (_blocked ||
        _branch == null ||
        widget.catalogRepository == null ||
        _choices.length < 2) {
      return;
    }
    final epoch = _epoch, repo = widget.repository!, branch = _branch!;
    final data = await _dialog<Map<String, dynamic>>(
      (lease) => _DispatchForm(
        source: branch,
        branches: _choices,
        catalog: widget.catalogRepository!,
        lease: lease,
      ),
    );
    if (!mounted ||
        epoch != _epoch ||
        data == null ||
        repo != widget.repository) {
      return;
    }
    final id = const Uuid().v4();
    await _commit(
      _Frozen(
        id,
        () => repo.dispatch(
          source: branch,
          destination: data['destination'],
          lines: List<Map<String, dynamic>>.from(data['lines']),
          reason: data['reason'],
          reference: data['reference'],
          confirmed: true,
          requestId: id,
        ),
        false,
      ),
    );
  }

  Future<void> _openTransfer(StockTransfer summary) async {
    if (_busy || _branch == null) return;
    final epoch = _epoch, repo = widget.repository!, branch = _branch!;
    try {
      final original = await repo.transfer(branch, summary.id);
      if (!mounted || epoch != _epoch) return;
      final choice = await _dialog<int>(
        (_) => AlertDialog(
          title: Text('${original.sourceName} → ${original.destinationName}'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(original.status.replaceAll('_', ' ')),
                for (final line in original.lines)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    child: Text(
                      '${line.name} · ${line.sku}\n${line.quantity} ${line.unit} dispatched · ${line.received} received · ${line.returned} returned · ${line.remaining} in transit',
                    ),
                  ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Close'),
            ),
            TextButton(
              onPressed: () => Navigator.pop(context, 0),
              child: const Text('Physical history'),
            ),
            if (!_blocked && original.lines.any((l) => l.remaining > 0))
              FilledButton(
                onPressed: () => Navigator.pop(
                  context,
                  branch == original.sourceBranchId ? 2 : 1,
                ),
                child: Text(
                  branch == original.sourceBranchId
                      ? 'Record goods returned to source'
                      : 'Record physical receipt',
                ),
              ),
          ],
        ),
      );
      if (!mounted || epoch != _epoch) return;
      if (choice == null) return;
      if (choice == 0) {
        await _eventHistory(original, branch);
        return;
      }
      final data = await _dialog<Map<String, dynamic>>(
        (_) => _PhysicalForm(
          lines: original.lines,
          title: choice == 2
              ? 'Return transit goods to source'
              : 'Receive transit goods',
          explanation: choice == 2
              ? 'Confirm goods actually returned to the original source. This does not undo received quantities.'
              : 'Confirm only goods counted at this destination. Outstanding goods stay in transit.',
        ),
      );
      if (!mounted || epoch != _epoch || data == null) return;
      final id = const Uuid().v4();
      await _commit(
        _Frozen(
          id,
          () => repo.complete(
            branch: branch,
            original: original,
            returning: choice == 2,
            quantities: Map<String, int>.from(data['quantities']),
            confirmed: true,
            reason: data['reason'],
            reference: data['reference'],
            requestId: id,
          ),
          false,
        ),
      );
    } catch (error) {
      if (mounted && epoch == _epoch) {
        setState(() => _error = operationError(error));
      }
    }
  }

  Future<void> _eventHistory(StockTransfer original, String branch) async {
    final repo = widget.repository!;
    await _dialog<void>(
      (lease) => _PagedPicker<Map<String, dynamic>>(
        title: 'Physical transfer history',
        lease: lease,
        load: (page) => repo.events(branch, original.id, page: page),
        label: (r) =>
            '${r['kind'] == 'transfer.receive' ? 'Received' : 'Returned to source'} · ${r['created_at']}\n${r['reason']}',
        selectable: false,
      ),
    );
  }

  Future<void> _supplierReturn() async {
    if (_blocked || _branch == null || widget.purchaseRepository == null) {
      return;
    }
    final epoch = _epoch,
        repo = widget.repository!,
        branch = _branch!,
        purchases = widget.purchaseRepository!;
    try {
      final order = await _dialog<PurchaseOrderSummary>(
        (lease) => _PagedPicker<PurchaseOrderSummary>(
          title: 'Select original purchase order',
          lease: lease,
          load: (page) => purchases.listOrders(branchId: branch, page: page),
          label: (o) =>
              '${o.supplierName} · ${o.status.label}\n${amountLabel(o.orderedTotalMinor, o.currency)}',
        ),
      );
      if (!mounted || epoch != _epoch || order == null) return;
      final receipt = await _dialog<PurchaseReceiptSummary>(
        (lease) => _PagedPicker<PurchaseReceiptSummary>(
          title: 'Select original delivery receipt',
          lease: lease,
          load: (page) => purchases.listReceipts(
            branchId: branch,
            orderId: order.id,
            page: page,
          ),
          label: (r) =>
              '${r.receivedAt.toUtc()}\n${amountLabel(r.receivedTotalMinor, r.currency)} · ${r.reference ?? 'No reference'}',
        ),
      );
      if (!mounted || epoch != _epoch || receipt == null) return;
      final original = await repo.returnContext(branch, receipt.id);
      if (!mounted || epoch != _epoch) return;
      final data = await _dialog<Map<String, dynamic>>(
        (_) => _PhysicalForm(
          lines: original.lines,
          title: 'Record supplier return',
          currency: original.currency,
          explanation:
              'Confirm goods already returned to the original supplier. Original procurement costs are evidence only; no supplier refund, payment or email is initiated.',
        ),
      );
      if (!mounted || epoch != _epoch || data == null) return;
      final id = const Uuid().v4();
      await _commit(
        _Frozen(
          id,
          () => repo.supplierReturn(
            original: original,
            quantities: Map<String, int>.from(data['quantities']),
            confirmed: true,
            reason: data['reason'],
            reference: data['reference'],
            requestId: id,
          ),
          false,
        ),
      );
    } catch (error) {
      if (mounted && epoch == _epoch) {
        setState(() => _error = operationError(error));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final page = widget.branchesOnly
        ? _branches
        : _tab == 0
        ? _transfers
        : _returns;
    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        PageHeading(
          title: widget.branchesOnly
              ? 'Branches'
              : 'Stock transfers and supplier returns',
          subtitle: widget.branchesOnly
              ? 'Audited business locations. Codes and financial history stay unchanged.'
              : 'Record actual goods movement with original receipts and saved requests.',
          trailing: StatusPill(
            status: _connected
                ? FeatureStatus.available
                : FeatureStatus.notYetConnected,
          ),
        ),
        const SizedBox(height: 20),
        if (!_connected)
          const FeatureEmptyState(
            status: FeatureStatus.notYetConnected,
            icon: Icons.local_shipping_outlined,
            title: 'No connected branch or logistics records',
            message:
                'Connect a verified authorized business to use these workflows.',
          )
        else ...[
          if (_notice != null) OperationNotice(message: _notice!),
          if (_error != null) OperationNotice(message: _error!, isError: true),
          if (_scopeBlocked)
            OutlinedButton(
              onPressed: _refreshScope,
              child: const Text('Refresh business access'),
            ),
          if (_frozen != null) ...[
            OperationNotice(
              message:
                  'Original request remains unconfirmed. Keep the physical evidence and retry this exact request.',
              requestId: _frozen!.id,
            ),
            OutlinedButton(
              onPressed: _busy ? null : () => _commit(_frozen!),
              child: const Text('Retry original request'),
            ),
          ],
          for (final pending in _pending.where(
            (p) => p.requestId != _frozen?.id,
          ))
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: SectionCard(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    OperationNotice(
                      message:
                          'Saved request needs reconciliation. Do not repeat goods movement.',
                      requestId: pending.requestId,
                    ),
                    OutlinedButton(
                      onPressed: _busy
                          ? null
                          : () => _commit(
                              _Frozen(
                                pending.requestId,
                                () => widget.repository!.retry(pending),
                                pending.type == 'save_branch',
                              ),
                            ),
                      child: const Text('Retry saved request'),
                    ),
                  ],
                ),
              ),
            ),
          if (widget.branchesOnly)
            Wrap(
              spacing: 12,
              children: [
                FilledButton.icon(
                  key: const Key('branch-create'),
                  onPressed: _blocked || _capabilities?['can_create'] != true
                      ? null
                      : () => _editBranch(),
                  icon: const Icon(Icons.add),
                  label: const Text('Create branch'),
                ),
                TextButton(
                  onPressed: _busy ? null : _load,
                  child: const Text('Reload'),
                ),
              ],
            )
          else ...[
            DropdownButtonFormField<String>(
              key: ValueKey(_branch),
              initialValue: _branch,
              isExpanded: true,
              decoration: const InputDecoration(labelText: 'Authorized branch'),
              items: _choices
                  .map(
                    (b) => DropdownMenuItem(
                      value: b.id,
                      child: Text(b.name, overflow: TextOverflow.ellipsis),
                    ),
                  )
                  .toList(),
              onChanged: _busy || _frozen != null
                  ? null
                  : (b) {
                      _lease?.invalidate();
                      setState(() {
                        _branch = b;
                        _offset = 0;
                      });
                      _load();
                    },
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 12,
              runSpacing: 8,
              children: [
                ChoiceChip(
                  label: const Text('Transfers'),
                  selected: _tab == 0,
                  onSelected: _blocked
                      ? null
                      : (_) {
                          setState(() {
                            _tab = 0;
                            _offset = 0;
                          });
                          _load();
                        },
                ),
                ChoiceChip(
                  label: const Text('Supplier returns'),
                  selected: _tab == 1,
                  onSelected: _blocked
                      ? null
                      : (_) {
                          setState(() {
                            _tab = 1;
                            _offset = 0;
                          });
                          _load();
                        },
                ),
                FilledButton.icon(
                  onPressed:
                      _blocked ||
                          _branch == null ||
                          (_tab == 0
                              ? _choices.length < 2
                              : widget.purchaseRepository == null)
                      ? null
                      : _tab == 0
                      ? _dispatch
                      : _supplierReturn,
                  icon: const Icon(Icons.add),
                  label: Text(
                    _tab == 0 ? 'Record dispatch' : 'Record supplier return',
                  ),
                ),
                TextButton(
                  onPressed: _busy ? null : _load,
                  child: const Text('Reload'),
                ),
              ],
            ),
            if (_tab == 0 && _choices.length < 2)
              const Padding(
                padding: EdgeInsets.only(top: 12),
                child: Text(
                  'Dispatch requires access to both endpoints. Existing transfers can still be received for your branch.',
                ),
              ),
          ],
          if (_busy)
            const Padding(
              padding: EdgeInsets.all(20),
              child: LinearProgressIndicator(),
            ),
          const SizedBox(height: 16),
          if (page != null && page.items.isEmpty)
            const SectionCard(child: Text('No matching recorded activity.')),
          if (widget.branchesOnly)
            for (final b in _branches?.items ?? <ManagedBranch>[])
              Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: SectionCard(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        b.name,
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                      Text(
                        '${b.code} · ${b.active ? 'Active' : 'Inactive'} · revision ${b.revision}',
                      ),
                      if (b.address != null) Text(b.address!),
                      OutlinedButton(
                        onPressed: _blocked ? null : () => _editBranch(b),
                        child: const Text('Edit branch'),
                      ),
                    ],
                  ),
                ),
              ),
          if (!widget.branchesOnly && _tab == 0)
            for (final t in _transfers?.items ?? <StockTransfer>[])
              Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: SectionCard(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '${t.sourceName} → ${t.destinationName}',
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                      Text(
                        '${t.status.replaceAll('_', ' ')} · ${t.createdAt.toUtc()}',
                      ),
                      OutlinedButton(
                        onPressed: _busy ? null : () => _openTransfer(t),
                        child: const Text('Quantities and physical history'),
                      ),
                    ],
                  ),
                ),
              ),
          if (!widget.branchesOnly && _tab == 1)
            for (final a in _returns?.items ?? <LogisticsAction>[])
              Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: SectionCard(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Supplier return · ${amountLabel(a.document['total_minor'] as int, a.document['currency'] as String)}',
                      ),
                      Text('${a.document['created_at']}'),
                      const Text(
                        'Recorded goods and original cost evidence; no money refund claimed.',
                      ),
                      SelectableText('Request ${a.requestId}'),
                    ],
                  ),
                ),
              ),
          if (page != null)
            Wrap(
              spacing: 12,
              alignment: WrapAlignment.spaceBetween,
              children: [
                TextButton(
                  onPressed: _busy || _offset == 0
                      ? null
                      : () {
                          _offset = (_offset - 20).clamp(0, 100000);
                          _load();
                        },
                  child: const Text('Previous'),
                ),
                TextButton(
                  onPressed: _busy || !page.hasMore
                      ? null
                      : () {
                          _offset = page.nextOffset;
                          _load();
                        },
                  child: const Text('Next'),
                ),
              ],
            ),
        ],
      ],
    );
  }
}

class _BranchForm extends StatefulWidget {
  const _BranchForm({this.original, required this.canSetActive});
  final ManagedBranch? original;
  final bool canSetActive;
  @override
  State<_BranchForm> createState() => _BranchFormState();
}

class _BranchFormState extends State<_BranchForm> {
  late final name = TextEditingController(text: widget.original?.name),
      code = TextEditingController(text: widget.original?.code),
      address = TextEditingController(text: widget.original?.address);
  final reason = TextEditingController();
  late bool active = widget.original?.active ?? true;
  String? error;
  @override
  void dispose() {
    name.dispose();
    code.dispose();
    address.dispose();
    reason.dispose();
    super.dispose();
  }

  void save() {
    try {
      Navigator.pop(context, {
        'name': requiredText(name.text, 'Name', 120),
        'code': requiredText(code.text, 'Code', 32),
        'address': optionalText(address.text, 'Address', 500),
        'active': active,
        'reason': requiredText(reason.text, 'Reason', 1000, minimum: 3),
      });
    } catch (_) {
      setState(() => error = 'Enter a name, code and a meaningful reason.');
    }
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: Text(
      widget.original == null ? 'Create active branch' : 'Edit branch',
    ),
    content: SizedBox(
      width: 500,
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            TextField(
              controller: name,
              maxLength: 120,
              decoration: const InputDecoration(labelText: 'Branch name'),
            ),
            TextField(
              controller: code,
              enabled: widget.original == null,
              maxLength: 32,
              decoration: const InputDecoration(
                labelText: 'Immutable branch code',
              ),
            ),
            TextField(
              controller: address,
              maxLength: 500,
              decoration: const InputDecoration(
                labelText: 'Address (optional)',
              ),
            ),
            if (widget.original != null)
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                value: active,
                onChanged: widget.canSetActive
                    ? (v) => setState(() => active = v)
                    : null,
                title: const Text('Branch active'),
              ),
            if (!active)
              const Text(
                'Stock, open shifts, outstanding orders, transit goods and retained offline grants must be resolved first. Existing operational views require reactivation.',
              ),
            TextField(
              controller: reason,
              maxLength: 1000,
              decoration: const InputDecoration(labelText: 'Reason'),
            ),
            if (error != null) Text(error!),
          ],
        ),
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('Cancel'),
      ),
      FilledButton(onPressed: save, child: const Text('Save branch')),
    ],
  );
}

class _PagedPicker<T> extends StatefulWidget {
  const _PagedPicker({
    required this.title,
    required this.lease,
    required this.load,
    required this.label,
    this.selectable = true,
  });
  final String title;
  final _Lease lease;
  final Future<DataPage<T>> Function(PageRequest) load;
  final String Function(T) label;
  final bool selectable;
  @override
  State<_PagedPicker<T>> createState() => _PagedPickerState<T>();
}

class _PagedPickerState<T> extends State<_PagedPicker<T>> {
  DataPage<T>? page;
  String? error;
  bool busy = false;
  int generation = 0;
  @override
  void initState() {
    super.initState();
    load(0);
  }

  Future<void> load(int offset) async {
    final e = ++generation;
    setState(() {
      busy = true;
      error = null;
      page = null;
    });
    try {
      final result = await widget.load(PageRequest(offset: offset, limit: 20));
      if (mounted && e == generation && widget.lease.active) {
        setState(() => page = result);
      }
    } catch (e) {
      if (mounted && widget.lease.active) {
        setState(() => error = operationError(e));
      }
    } finally {
      if (mounted && widget.lease.active) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: widget.lease,
    builder: (_, _) => AlertDialog(
      title: Text(
        widget.lease.active ? widget.title : 'Business context changed',
      ),
      content: SizedBox(
        width: 580,
        height: MediaQuery.sizeOf(context).height * .5,
        child: !widget.lease.active
            ? const Text(
                'Close this view to continue with your current account.',
              )
            : Column(
                children: [
                  if (busy) const LinearProgressIndicator(),
                  if (error != null) Text(error!),
                  Expanded(
                    child: ListView(
                      children: [
                        if (page?.items.isEmpty == true)
                          const Text('No matching records.'),
                        for (final item in page?.items ?? <T>[])
                          ListTile(
                            title: Text(widget.label(item)),
                            onTap: widget.selectable
                                ? () => Navigator.pop(context, item)
                                : null,
                          ),
                      ],
                    ),
                  ),
                  if (page != null)
                    Wrap(
                      spacing: 16,
                      children: [
                        TextButton(
                          onPressed: busy || page!.offset == 0
                              ? null
                              : () =>
                                    load((page!.offset - 20).clamp(0, 100000)),
                          child: const Text('Previous'),
                        ),
                        TextButton(
                          onPressed: busy || !page!.hasMore
                              ? null
                              : () => load(page!.nextOffset),
                          child: const Text('Next'),
                        ),
                      ],
                    ),
                ],
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
}

class _PhysicalForm extends StatefulWidget {
  const _PhysicalForm({
    required this.lines,
    required this.title,
    required this.explanation,
    this.currency,
  });
  final List<LogisticsLine> lines;
  final String title, explanation;
  final String? currency;
  @override
  State<_PhysicalForm> createState() => _PhysicalFormState();
}

class _PhysicalFormState extends State<_PhysicalForm> {
  final quantities = <String, TextEditingController>{};
  final reason = TextEditingController(), reference = TextEditingController();
  bool confirmed = false;
  String? error;
  @override
  void initState() {
    super.initState();
    for (final l in widget.lines.where((l) => l.remaining > 0)) {
      quantities[l.id] = TextEditingController();
    }
  }

  @override
  void dispose() {
    for (final c in quantities.values) {
      c.dispose();
    }
    reason.dispose();
    reference.dispose();
    super.dispose();
  }

  void save() {
    try {
      final chosen = <String, int>{};
      for (final l in widget.lines) {
        final text = quantities[l.id]?.text.trim() ?? '';
        if (text.isEmpty) continue;
        final n = int.tryParse(text);
        if (n == null ||
            n < 1 ||
            n > l.remaining ||
            n > 1000000 ||
            (l.onHand != null && n > l.onHand!) ||
            l.unit != l.currentUnit) {
          throw const FormatException();
        }
        chosen[l.id] = n;
      }
      if (chosen.isEmpty || !confirmed) throw const FormatException();
      Navigator.pop(context, {
        'quantities': chosen,
        'reason': requiredText(reason.text, 'Reason', 1000, minimum: 3),
        'reference': optionalText(reference.text, 'Reference', 120),
      });
    } catch (_) {
      setState(
        () => error =
            'Confirm physical goods, enter valid remaining whole quantities and a reason.',
      );
    }
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: Text(widget.title),
    content: SizedBox(
      width: 600,
      height: MediaQuery.sizeOf(context).height * .6,
      child: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(widget.explanation),
            const SizedBox(height: 16),
            for (final l in widget.lines.where((l) => l.remaining > 0))
              Padding(
                padding: const EdgeInsets.only(bottom: 16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('${l.name} · ${l.sku}'),
                    Text(
                      '${l.remaining} ${l.unit} remaining${l.onHand == null ? '' : ' · ${l.onHand} on hand'}',
                    ),
                    if (l.unitCostMinor != null)
                      Text(
                        'Original cost: ${amountLabel(l.unitCostMinor!, widget.currency!)} per ${l.unit}',
                      ),
                    if (l.currentUnit != l.unit)
                      const Text(
                        'Stock unit differs. Review is required; no automatic conversion.',
                      ),
                    TextField(
                      controller: quantities[l.id],
                      enabled: l.currentUnit == l.unit,
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(
                        labelText: 'Physically counted whole units',
                      ),
                    ),
                  ],
                ),
              ),
            TextField(
              controller: reference,
              maxLength: 120,
              decoration: const InputDecoration(
                labelText: 'Evidence reference (optional)',
              ),
            ),
            TextField(
              controller: reason,
              maxLength: 1000,
              decoration: const InputDecoration(labelText: 'Reason'),
            ),
            CheckboxListTile(
              contentPadding: EdgeInsets.zero,
              value: confirmed,
              onChanged: (v) => setState(() => confirmed = v ?? false),
              title: const Text(
                'I confirmed these goods physically moved. I will not record them twice.',
              ),
            ),
            if (error != null) Text(error!),
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
        onPressed: save,
        child: const Text('Record physical movement'),
      ),
    ],
  );
}

class _DispatchForm extends StatefulWidget {
  const _DispatchForm({
    required this.source,
    required this.branches,
    required this.catalog,
    required this.lease,
  });
  final String source;
  final List<BranchOption> branches;
  final CatalogRepository catalog;
  final _Lease lease;
  @override
  State<_DispatchForm> createState() => _DispatchFormState();
}

class _DispatchFormState extends State<_DispatchForm> {
  String? destination, error;
  final products = <Product>[];
  final quantities = <String, TextEditingController>{};
  final reason = TextEditingController(), reference = TextEditingController();
  bool confirmed = false, busy = false;
  @override
  void initState() {
    super.initState();
    destination = widget.branches.firstWhere((b) => b.id != widget.source).id;
  }

  @override
  void dispose() {
    for (final q in quantities.values) {
      q.dispose();
    }
    reason.dispose();
    reference.dispose();
    super.dispose();
  }

  Future<void> add() async {
    setState(() => busy = true);
    try {
      final p = await showDialog<Product>(
        context: context,
        builder: (_) =>
            _CatalogPicker(catalog: widget.catalog, lease: widget.lease),
      );
      if (mounted &&
          widget.lease.active &&
          p != null &&
          !quantities.containsKey(p.id)) {
        setState(() {
          products.add(p);
          quantities[p.id] = TextEditingController();
        });
      }
    } finally {
      if (mounted && widget.lease.active) setState(() => busy = false);
    }
  }

  void save() {
    try {
      if (!confirmed || products.isEmpty || products.length > 100) {
        throw const FormatException();
      }
      final lines = products.map((p) {
        final n = int.tryParse(quantities[p.id]!.text);
        if (n == null || n < 1 || n > 1000000) throw const FormatException();
        return {
          'product_id': p.id,
          'quantity': n,
          'expected_revision': p.revision,
          'unit': p.unit,
        };
      }).toList();
      Navigator.pop(context, {
        'destination': destination,
        'lines': lines,
        'reason': requiredText(reason.text, 'Reason', 1000, minimum: 3),
        'reference': optionalText(reference.text, 'Reference', 120),
      });
    } catch (_) {
      setState(
        () => error =
            'Select unique products, enter positive whole quantities and confirm the actual dispatch.',
      );
    }
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('Record goods dispatched'),
    content: SizedBox(
      width: 600,
      height: MediaQuery.sizeOf(context).height * .6,
      child: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Goods already left the source. Destination stock increases only after a separately confirmed physical receipt.',
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<String>(
              initialValue: destination,
              isExpanded: true,
              decoration: const InputDecoration(
                labelText: 'Authorized destination',
              ),
              items: widget.branches
                  .where((b) => b.id != widget.source)
                  .map(
                    (b) => DropdownMenuItem(
                      value: b.id,
                      child: Text(b.name, overflow: TextOverflow.ellipsis),
                    ),
                  )
                  .toList(),
              onChanged: (v) => setState(() => destination = v),
            ),
            OutlinedButton(
              onPressed: busy || products.length >= 100 ? null : add,
              child: const Text('Select active product'),
            ),
            for (final p in products)
              Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('${p.name} · ${p.sku}'),
                    TextField(
                      controller: quantities[p.id],
                      keyboardType: TextInputType.number,
                      decoration: InputDecoration(
                        labelText: 'Dispatched whole ${p.unit}',
                      ),
                    ),
                    TextButton(
                      onPressed: () {
                        setState(() {
                          products.remove(p);
                          quantities.remove(p.id)?.dispose();
                        });
                      },
                      child: const Text('Remove line'),
                    ),
                  ],
                ),
              ),
            TextField(
              controller: reference,
              maxLength: 120,
              decoration: const InputDecoration(
                labelText: 'Reference (optional)',
              ),
            ),
            TextField(
              controller: reason,
              maxLength: 1000,
              decoration: const InputDecoration(labelText: 'Reason'),
            ),
            CheckboxListTile(
              contentPadding: EdgeInsets.zero,
              value: confirmed,
              onChanged: (v) => setState(() => confirmed = v ?? false),
              title: const Text(
                'I counted and physically dispatched these goods. No destination receipt is implied.',
              ),
            ),
            if (error != null) Text(error!),
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
        onPressed: busy ? null : save,
        child: const Text('Record dispatch'),
      ),
    ],
  );
}

class _CatalogPicker extends StatefulWidget {
  const _CatalogPicker({required this.catalog, required this.lease});
  final CatalogRepository catalog;
  final _Lease lease;
  @override
  State<_CatalogPicker> createState() => _CatalogPickerState();
}

class _CatalogPickerState extends State<_CatalogPicker> {
  final query = TextEditingController();
  DataPage<Product>? page;
  String? error;
  bool busy = false;
  int generation = 0;
  @override
  void initState() {
    super.initState();
    load(0);
  }

  @override
  void dispose() {
    query.dispose();
    super.dispose();
  }

  Future<void> load(int offset) async {
    final e = ++generation;
    setState(() => busy = true);
    try {
      final p = await widget.catalog.searchProducts(
        filter: ProductFilter(query: query.text, active: true),
        page: PageRequest(offset: offset, limit: 20),
      );
      if (mounted && e == generation && widget.lease.active) {
        setState(() {
          page = p;
          error = null;
        });
      }
    } catch (e) {
      if (mounted && widget.lease.active) {
        setState(() => error = operationError(e));
      }
    } finally {
      if (mounted && e == generation && widget.lease.active) {
        setState(() => busy = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: widget.lease,
    builder: (_, _) => AlertDialog(
      title: Text(
        widget.lease.active
            ? 'Select active product'
            : 'Business context changed',
      ),
      content: SizedBox(
        width: 540,
        height: MediaQuery.sizeOf(context).height * .5,
        child: widget.lease.active
            ? Column(
                children: [
                  TextField(
                    controller: query,
                    onSubmitted: (_) => load(0),
                    decoration: const InputDecoration(
                      labelText: 'Search name or SKU',
                    ),
                  ),
                  TextButton(
                    onPressed: busy ? null : () => load(0),
                    child: const Text('Search'),
                  ),
                  if (busy) const LinearProgressIndicator(),
                  if (error != null) Text(error!),
                  Expanded(
                    child: ListView(
                      children: [
                        for (final p in page?.items ?? <Product>[])
                          ListTile(
                            title: Text(p.name),
                            subtitle: Text('${p.sku} · ${p.unit}'),
                            onTap: () => Navigator.pop(context, p),
                          ),
                      ],
                    ),
                  ),
                  if (page != null)
                    Wrap(
                      spacing: 16,
                      children: [
                        TextButton(
                          onPressed: busy || page!.offset == 0
                              ? null
                              : () =>
                                    load((page!.offset - 20).clamp(0, 100000)),
                          child: const Text('Previous'),
                        ),
                        TextButton(
                          onPressed: busy || !page!.hasMore
                              ? null
                              : () => load(page!.nextOffset),
                          child: const Text('Next'),
                        ),
                      ],
                    ),
                ],
              )
            : const Text('Close this view to continue.'),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Close'),
        ),
      ],
    ),
  );
}
