import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../app/config/feature_status.dart';
import '../../../core/security/app_role.dart';
import '../../../core/widgets/status_widgets.dart';
import '../../catalog/domain/repository_support.dart';
import '../../catalog/presentation/catalog_ui_support.dart';
import '../../checkout/domain/checkout_models.dart';
import '../../checkout/domain/checkout_repository.dart';
import '../../people/domain/people_repository.dart';
import '../domain/report_csv.dart';
import '../domain/report_models.dart';
import '../domain/reports_repository.dart';

class ReportsPage extends StatefulWidget {
  const ReportsPage({
    this.repository,
    this.peopleRepository,
    this.checkoutRepository,
    this.role,
    this.currentUserId,
    this.isPreview = true,
    super.key,
  });
  final ReportsRepository? repository;
  final PeopleRepository? peopleRepository;
  final CheckoutRepository? checkoutRepository;
  final AppRole? role;
  final String? currentUserId;
  final bool isPreview;
  @override
  State<ReportsPage> createState() => _ReportsPageState();
}

class _ReportsPageState extends State<ReportsPage> {
  static const _pageSize = 20;
  final _firstDate = TextEditingController();
  final _lastDate = TextEditingController();
  final _query = TextEditingController();
  late ReportKind _kind;
  String? _branch;
  String? _shiftId;
  List<Shift> _ownShifts = const [];
  Map<String, String> _branchNames = const {};
  int? _nextShiftOffset;
  OperationalReport? _snapshot;
  bool _busy = false;
  bool _shiftBusy = false;
  bool _copying = false;
  String? _error;
  String? _shiftError;
  int _generation = 0;
  int _scopeGeneration = 0;

  bool get _connected =>
      !widget.isPreview && widget.repository != null && widget.role != null;
  bool get _cashier => widget.role == AppRole.cashier;
  List<ReportKind> get _available => switch (widget.role) {
    AppRole.owner || AppRole.admin || AppRole.manager => ReportKind.values,
    AppRole.cashier => const [ReportKind.sales],
    AppRole.inventoryStaff => const [ReportKind.inventory],
    null => const [],
  };

  @override
  void initState() {
    super.initState();
    _reset();
    if (_connected) {
      _loadBranchLabels();
      if (_cashier) {
        _loadShifts();
      } else {
        _run();
      }
    }
  }

  @override
  void didUpdateWidget(covariant ReportsPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.repository != widget.repository ||
        oldWidget.role != widget.role ||
        oldWidget.currentUserId != widget.currentUserId ||
        oldWidget.peopleRepository != widget.peopleRepository ||
        oldWidget.checkoutRepository != widget.checkoutRepository ||
        oldWidget.isPreview != widget.isPreview) {
      _generation++;
      _scopeGeneration++;
      _reset();
      if (_connected) {
        _loadBranchLabels();
        if (_cashier) {
          _loadShifts();
        } else {
          _run();
        }
      }
    }
  }

  void _reset() {
    final now = DateTime.now().toUtc();
    final today = DateTime.utc(now.year, now.month, now.day);
    _firstDate.text = reportDate(today.subtract(const Duration(days: 29)));
    _lastDate.text = reportDate(today);
    _query.clear();
    _kind = _available.firstOrNull ?? ReportKind.sales;
    final branches = widget.repository?.branchIds.toList() ?? [];
    branches.sort();
    _branch = branches.firstOrNull;
    _shiftId = null;
    _ownShifts = const [];
    _branchNames = const {};
    _nextShiftOffset = null;
    _snapshot = null;
    _busy = false;
    _shiftBusy = false;
    _copying = false;
    _error = null;
    _shiftError = null;
  }

  @override
  void dispose() {
    _firstDate.dispose();
    _lastDate.dispose();
    _query.dispose();
    super.dispose();
  }

  Future<void> _loadBranchLabels() async {
    final repository = widget.peopleRepository;
    if (!_connected || repository == null) return;
    final generation = _scopeGeneration;
    try {
      final branches = await repository.listBranches();
      if (!mounted || generation != _scopeGeneration) return;
      setState(
        () => _branchNames = {
          for (final branch in branches)
            if (widget.repository!.branchIds.contains(branch.id))
              branch.id: branch.name,
        },
      );
    } on Object {
      // Source IDs remain available when optional display labels fail.
    }
  }

  Future<void> _loadShifts({int offset = 0}) async {
    if (!_connected || !_cashier || _branch == null || _shiftBusy) return;
    final repository = widget.checkoutRepository;
    if (repository == null || widget.currentUserId == null) {
      setState(
        () => _shiftError =
            'Own-shift choices require the connected checkout service.',
      );
      return;
    }
    final generation = _scopeGeneration;
    final branch = _branch!;
    setState(() {
      _shiftBusy = true;
      _shiftError = null;
    });
    try {
      final page = await repository.listShifts(
        branchId: branch,
        page: PageRequest(offset: offset, limit: _pageSize),
      );
      if (!mounted || generation != _scopeGeneration) return;
      final own = page.items
          .where(
            (shift) =>
                shift.organizationId == widget.repository!.organizationId &&
                shift.branchId == branch &&
                shift.actorUserId == widget.currentUserId,
          )
          .toList();
      setState(() {
        _ownShifts = List.unmodifiable([
          if (offset > 0) ..._ownShifts,
          ...own.where((shift) => !_ownShifts.any((old) => old.id == shift.id)),
        ]);
        _nextShiftOffset = page.hasMore ? page.nextOffset : null;
      });
    } on Object catch (error) {
      if (!mounted || generation != _scopeGeneration) return;
      setState(() {
        _generation++;
        _busy = false;
        _copying = false;
        _ownShifts = const [];
        _shiftId = null;
        _shiftError = _publicError(error);
        _snapshot = null;
      });
    } finally {
      if (mounted && generation == _scopeGeneration) {
        setState(() => _shiftBusy = false);
      }
    }
  }

  void _invalidate() {
    setState(() {
      _snapshot = null;
      _error = null;
    });
  }

  Future<void> _run({int offset = 0}) async {
    if (!_connected || _busy) return;
    final branch = _branch;
    if (branch == null ||
        (_cashier &&
            (_shiftId == null ||
                !_ownShifts.any(
                  (shift) =>
                      shift.id == _shiftId &&
                      shift.actorUserId == widget.currentUserId,
                )))) {
      setState(
        () => _error = _cashier
            ? 'Select your own shift to run sales activity.'
            : 'Choose an authorized branch.',
      );
      return;
    }
    final generation = ++_generation;
    setState(() {
      _busy = true;
      _snapshot = null;
      _error = null;
    });
    try {
      final repository = widget.repository!;
      final OperationalReport report;
      switch (_kind) {
        case ReportKind.sales:
          report = await repository.sales(
            branchId: branch,
            window: ReportWindow.fromDateText(
              _firstDate.text.trim(),
              _lastDate.text.trim(),
            ),
            shiftId: _cashier ? _shiftId : null,
          );
        case ReportKind.inventory:
          report = await repository.inventory(
            branchId: branch,
            query: _query.text,
            page: PageRequest(offset: offset, limit: _pageSize),
          );
        case ReportKind.expenses:
          report = await repository.expenses(
            branchId: branch,
            window: ReportWindow.fromDateText(
              _firstDate.text.trim(),
              _lastDate.text.trim(),
            ),
          );
      }
      if (!mounted || generation != _generation) return;
      setState(() => _snapshot = report);
    } on Object catch (error) {
      if (mounted && generation == _generation) {
        setState(() => _error = _publicError(error));
      }
    } finally {
      if (mounted && generation == _generation) setState(() => _busy = false);
    }
  }

  String _publicError(Object error) => error is RepositoryFailure
      ? error.message
      : 'The report could not be verified. Reload the authorized server snapshot.';

  Future<void> _copy() async {
    final snapshot = _snapshot;
    if (snapshot == null || _busy || _copying) return;
    final generation = _generation;
    setState(() => _copying = true);
    try {
      await Clipboard.setData(ClipboardData(text: reportToCsv(snapshot)));
      if (!mounted || generation != _generation) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Displayed authorized report copied as CSV.'),
        ),
      );
    } on Object {
      if (mounted && generation == _generation) {
        setState(() => _error = 'The report could not be copied. Try again.');
      }
    } finally {
      if (mounted && generation == _generation) {
        setState(() => _copying = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) => ListView(
    padding: const EdgeInsets.all(24),
    children: [
      PageHeading(
        title: 'Reports',
        subtitle:
            'Committed sales, current stock and recorded expense activity, scoped to your branch.',
        trailing: _connected
            ? null
            : const StatusPill(status: FeatureStatus.notYetConnected),
      ),
      const SizedBox(height: 20),
      if (!_connected)
        const FeatureEmptyState(
          icon: Icons.bar_chart_outlined,
          title: 'Reports require a verified business account',
          message:
              'Connect the backend and sign in to load actual posted activity. The preview contains no business metrics.',
          status: FeatureStatus.notYetConnected,
        )
      else ...[
        SectionCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final kind in _available)
                    ChoiceChip(
                      key: Key('report-kind-${kind.name}'),
                      label: Text(_kindLabel(kind)),
                      selected: _kind == kind,
                      onSelected: _busy
                          ? null
                          : (_) {
                              setState(() {
                                _kind = kind;
                                _snapshot = null;
                                _error = null;
                              });
                              _run();
                            },
                    ),
                ],
              ),
              const SizedBox(height: 16),
              DropdownButtonFormField<String>(
                key: ValueKey('report-branch-$_branch'),
                initialValue: _branch,
                isExpanded: true,
                decoration: const InputDecoration(
                  labelText: 'Authorized branch',
                ),
                items: [
                  for (final id
                      in (widget.repository!.branchIds.toList()..sort()))
                    DropdownMenuItem(
                      value: id,
                      child: Text(
                        _branchNames[id] ?? 'Branch ${id.substring(0, 8)}',
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                ],
                onChanged: (value) {
                  _scopeGeneration++;
                  _generation++;
                  setState(() {
                    _branch = value;
                    _snapshot = null;
                    _error = null;
                    _shiftId = null;
                    _ownShifts = const [];
                    _nextShiftOffset = null;
                    _shiftBusy = false;
                    _busy = false;
                    _copying = false;
                  });
                  if (_cashier) {
                    _loadShifts();
                  } else {
                    _run();
                  }
                },
              ),
              const SizedBox(height: 16),
              if (_kind == ReportKind.inventory)
                TextField(
                  key: const Key('report-product-query'),
                  controller: _query,
                  enabled: !_busy,
                  maxLength: 120,
                  decoration: const InputDecoration(
                    labelText: 'Product name or SKU',
                  ),
                  onChanged: (_) => _invalidate(),
                  onSubmitted: (_) => _run(),
                )
              else ...[
                LayoutBuilder(
                  builder: (context, constraints) {
                    final first = TextField(
                      key: const Key('report-first-date'),
                      controller: _firstDate,
                      enabled: !_busy,
                      decoration: const InputDecoration(
                        labelText: 'First UTC date',
                        hintText: 'YYYY-MM-DD',
                      ),
                      onChanged: (_) => _invalidate(),
                    );
                    final last = TextField(
                      key: const Key('report-last-date'),
                      controller: _lastDate,
                      enabled: !_busy,
                      decoration: const InputDecoration(
                        labelText: 'Last UTC date (inclusive)',
                        hintText: 'YYYY-MM-DD',
                      ),
                      onChanged: (_) => _invalidate(),
                    );
                    return constraints.maxWidth < 520
                        ? Column(
                            children: [first, const SizedBox(height: 12), last],
                          )
                        : Row(
                            children: [
                              Expanded(child: first),
                              const SizedBox(width: 16),
                              Expanded(child: last),
                            ],
                          );
                  },
                ),
                const SizedBox(height: 8),
                const Text(
                  'UTC calendar dates · At most 366 days · The final date includes its entire day.',
                ),
              ],
              if (_cashier) ...[
                const SizedBox(height: 16),
                DropdownButtonFormField<String>(
                  key: ValueKey('report-own-shift-$_shiftId'),
                  initialValue: _shiftId,
                  isExpanded: true,
                  decoration: const InputDecoration(
                    labelText: 'Your own shift',
                  ),
                  items: [
                    for (final shift in _ownShifts)
                      DropdownMenuItem(
                        value: shift.id,
                        child: Text(
                          '${reportDate(shift.openedAt.toUtc())} · ${shift.currency} · ${shift.isOpen ? 'Open' : 'Closed'} · ${shift.id.substring(0, 8)}',
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                  ],
                  onChanged: _busy || _shiftBusy
                      ? null
                      : (value) {
                          setState(() {
                            _shiftId = value;
                            _snapshot = null;
                            _error = null;
                          });
                        },
                ),
                const SizedBox(height: 8),
                const Text(
                  'Sales and reversals are filtered by the selected operation shift. A later refund can use a different payout shift from the original sale.',
                ),
                if (_shiftBusy) const LinearProgressIndicator(),
                if (_shiftError != null)
                  CatalogErrorNotice(
                    message: _shiftError!,
                    onRetry: _shiftBusy ? null : () => _loadShifts(),
                  ),
                if (!_shiftBusy && _ownShifts.isEmpty && _shiftError == null)
                  const Text('No authorized own shifts are available.'),
                if (_nextShiftOffset != null)
                  TextButton(
                    onPressed: _shiftBusy || _busy
                        ? null
                        : () => _loadShifts(offset: _nextShiftOffset!),
                    child: const Text('Load more own shifts'),
                  ),
              ],
              const SizedBox(height: 16),
              FilledButton.icon(
                key: const Key('run-report'),
                onPressed: _busy || _shiftBusy || (_cashier && _shiftId == null)
                    ? null
                    : () => _run(),
                icon: const Icon(Icons.bar_chart),
                label: const Text('Run report'),
              ),
            ],
          ),
        ),
        const SizedBox(height: 20),
        if (_busy) const LinearProgressIndicator(),
        if (_error != null) ...[
          CatalogErrorNotice(key: const Key('report-error'), message: _error!),
          const SizedBox(height: 16),
        ],
        if (_snapshot == null && !_busy && _error == null)
          SectionCard(
            child: Text(
              _cashier
                  ? 'Select your own shift and UTC dates, then run sales activity.'
                  : 'Choose the report filters and run an authorized server snapshot.',
            ),
          ),
        if (_snapshot != null) ...[
          SectionCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const StatusPill(
                  label: 'Server posted',
                  icon: Icons.cloud_done_outlined,
                ),
                const SizedBox(height: 8),
                Text(
                  'Generated ${_snapshot!.scope.generatedAt.toUtc().toIso8601String()} UTC',
                ),
                Text(
                  'Branch ${_branchNames[_snapshot!.scope.branchId] ?? _snapshot!.scope.branchId}',
                ),
                const SizedBox(height: 8),
                const Text(
                  'Pending and review-only offline payments are excluded. Each currency is reported separately.',
                ),
                TextButton.icon(
                  key: const Key('copy-report-csv'),
                  onPressed: _busy || _copying ? null : _copy,
                  icon: const Icon(Icons.copy_outlined),
                  label: const Text('Copy displayed report CSV'),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          ..._reportContent(_snapshot!),
        ],
      ],
    ],
  );

  Iterable<Widget> _reportContent(OperationalReport snapshot) sync* {
    switch (snapshot) {
      case SalesReport():
        if (snapshot.currencies.isEmpty) {
          yield const _ReportEmpty(
            title: 'No posted sales or reversals in this window',
            message:
                'The authorized server query returned no activity. Select another UTC range to inspect earlier history.',
          );
        }
        for (final currency in snapshot.currencies) {
          final totals = currency.totals;
          yield SectionCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _CurrencyHeading(
                  currency: currency.currency,
                  detail:
                      '${totals.saleCount} sales · ${totals.reversalCount} reversals',
                ),
                const SizedBox(height: 16),
                _MetricGrid(
                  values: [
                    (
                      'Posted sales',
                      _money(currency.currency, totals.salesTotalMinor),
                    ),
                    (
                      'Refunds',
                      _money(currency.currency, totals.refundTotalMinor),
                    ),
                    ('Voids', _money(currency.currency, totals.voidTotalMinor)),
                    (
                      'Net sales activity',
                      _money(currency.currency, totals.netSalesMinor),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                Text(
                  'Original sales: subtotal ${_money(currency.currency, totals.salesSubtotalMinor)} · discounts ${_money(currency.currency, totals.salesDiscountMinor)} · tax ${_money(currency.currency, totals.salesTaxMinor)}',
                ),
                const SizedBox(height: 16),
                const Text(
                  'Recorded tender activity',
                  style: TextStyle(fontWeight: FontWeight.w700),
                ),
                for (final payment in currency.payments)
                  Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: Text(
                      '${_label(payment.method)} · sales ${_money(currency.currency, payment.salesMinor)} · reversed ${_money(currency.currency, payment.reversedMinor)} · net ${_money(currency.currency, payment.netMinor)}',
                    ),
                  ),
                const SizedBox(height: 8),
                const Text(
                  'Recorded tenders include operator-verified payments; provider settlement is not connected.',
                ),
                ExpansionTile(
                  tilePadding: EdgeInsets.zero,
                  title: const Text('Daily UTC activity'),
                  children: [
                    for (final day in currency.daily)
                      _ActivityDay(
                        date: day.date,
                        activity:
                            '${day.totals.saleCount} sales · ${day.totals.reversalCount} reversals',
                        amount: _money(
                          currency.currency,
                          day.totals.netSalesMinor,
                        ),
                      ),
                  ],
                ),
              ],
            ),
          );
          yield const SizedBox(height: 16);
        }
      case InventoryReport():
        yield SectionCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Current posted stock',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 8),
              const Text(
                'Current branch observations include inactive products with stock history. Device-local pending changes are excluded.',
              ),
              const SizedBox(height: 16),
              _MetricGrid(
                values: [
                  ('Matching products', '${snapshot.catalogProductCount}'),
                  (
                    'Positive stock products',
                    '${snapshot.stockedProductCount}',
                  ),
                  ('Stock deficits', '${snapshot.deficitProductCount}'),
                  ('Low stock products', '${snapshot.lowStockProductCount}'),
                ],
              ),
            ],
          ),
        );
        yield const SizedBox(height: 16);
        if (snapshot.items.items.isEmpty) {
          yield const _ReportEmpty(
            title: 'No matching current stock products',
            message:
                'The authorized server query found no products for this filter.',
          );
        }
        for (final item in snapshot.items.items) {
          yield SectionCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  item.name,
                  style: const TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                Text('${item.sku} · ${item.active ? 'Active' : 'Inactive'}'),
                const SizedBox(height: 8),
                Text(
                  '${item.quantity} ${item.unit}',
                  style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.w700,
                    color: item.isDeficit
                        ? Theme.of(context).colorScheme.error
                        : null,
                  ),
                ),
                Text('Reorder level ${item.reorderLevel} ${item.unit}'),
                Text(
                  item.hasMovement
                      ? 'Observed stock revision ${item.stockRevision}'
                      : 'Observed zero · No recorded movement',
                ),
                if (item.isDeficit || item.isLowStock) ...[
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      if (item.isDeficit)
                        StatusPill(
                          label: 'Stock deficit',
                          color: Theme.of(context).colorScheme.error,
                        ),
                      if (item.isLowStock)
                        const StatusPill(
                          label: 'Low stock',
                          color: Color(0xffb45309),
                        ),
                    ],
                  ),
                ],
              ],
            ),
          );
          yield const SizedBox(height: 12);
        }
        yield Wrap(
          spacing: 16,
          runSpacing: 8,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            OutlinedButton(
              key: const Key('report-stock-previous'),
              onPressed: !_busy && snapshot.items.offset > 0
                  ? () => _run(
                      offset: (snapshot.items.offset - _pageSize).clamp(
                        0,
                        snapshot.items.offset,
                      ),
                    )
                  : null,
              child: const Text('Previous'),
            ),
            Text(
              'Page ${snapshot.items.offset ~/ _pageSize + 1} · CSV contains this page',
            ),
            OutlinedButton(
              key: const Key('report-stock-next'),
              onPressed: !_busy && snapshot.items.hasMore
                  ? () => _run(offset: snapshot.items.nextOffset)
                  : null,
              child: const Text('Next'),
            ),
          ],
        );
      case ExpenseReport():
        if (snapshot.currencies.isEmpty) {
          yield const _ReportEmpty(
            title: 'No recorded expenses or reversals in this window',
            message:
                'The authorized server query returned no expense activity for these UTC dates.',
          );
        }
        for (final currency in snapshot.currencies) {
          final totals = currency.totals;
          yield SectionCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _CurrencyHeading(
                  currency: currency.currency,
                  detail:
                      '${totals.expenseCount} expenses · ${totals.reversalCount} reversals',
                ),
                const SizedBox(height: 16),
                _MetricGrid(
                  values: [
                    (
                      'Recorded expenses',
                      _money(currency.currency, totals.expenseTotalMinor),
                    ),
                    (
                      'Expense reversals',
                      _money(currency.currency, totals.reversalTotalMinor),
                    ),
                    (
                      'Net expense activity',
                      _money(currency.currency, totals.netExpenseMinor),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                const Text(
                  'Payment source',
                  style: TextStyle(fontWeight: FontWeight.w700),
                ),
                for (final group in currency.sources)
                  Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: Text(
                      '${group.key == 'external' ? 'Outside POS drawer' : 'Cash drawer'} · ${_money(currency.currency, group.totals.netExpenseMinor)} net · ${group.totals.expenseCount} expenses, ${group.totals.reversalCount} reversals',
                    ),
                  ),
                const SizedBox(height: 16),
                const Text(
                  'Categories',
                  style: TextStyle(fontWeight: FontWeight.w700),
                ),
                for (final group in currency.categories)
                  Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: Text(
                      '${_label(group.key)} · ${_money(currency.currency, group.totals.netExpenseMinor)} net',
                    ),
                  ),
                const SizedBox(height: 16),
                const Text(
                  'This reports recorded expense activity. Drawer closing balance comes from the separate shift record. Purchases and inventory cost are excluded.',
                ),
                ExpansionTile(
                  tilePadding: EdgeInsets.zero,
                  title: const Text('Daily UTC activity'),
                  children: [
                    for (final day in currency.daily)
                      _ActivityDay(
                        date: day.date,
                        activity:
                            '${day.totals.expenseCount} expenses · ${day.totals.reversalCount} reversals',
                        amount: _money(
                          currency.currency,
                          day.totals.netExpenseMinor,
                        ),
                      ),
                  ],
                ),
              ],
            ),
          );
          yield const SizedBox(height: 16);
        }
      default:
        yield const Text('This report type is unavailable.');
    }
  }
}

class _ActivityDay extends StatelessWidget {
  const _ActivityDay({
    required this.date,
    required this.activity,
    required this.amount,
  });
  final DateTime date;
  final String activity, amount;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 10),
    child: LayoutBuilder(
      builder: (context, constraints) {
        final detail = Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              reportDate(date),
              style: const TextStyle(fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 4),
            Text(activity),
          ],
        );
        final total = Text(
          amount,
          style: const TextStyle(fontWeight: FontWeight.w600),
        );
        return constraints.maxWidth < 520
            ? Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [detail, const SizedBox(height: 6), total],
              )
            : Row(
                children: [
                  Expanded(child: detail),
                  const SizedBox(width: 16),
                  Flexible(child: total),
                ],
              );
      },
    ),
  );
}

class _MetricGrid extends StatelessWidget {
  const _MetricGrid({required this.values});
  final List<(String, String)> values;
  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final width = constraints.maxWidth < 520
          ? constraints.maxWidth
          : (constraints.maxWidth - 16) / 2;
      return Wrap(
        spacing: 16,
        runSpacing: 12,
        children: [
          for (final value in values)
            SizedBox(
              width: width,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: Theme.of(
                    context,
                  ).colorScheme.primary.withValues(alpha: .04),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Padding(
                  padding: const EdgeInsets.all(14),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        value.$1,
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                      const SizedBox(height: 6),
                      Text(
                        value.$2,
                        style: const TextStyle(
                          fontSize: 22,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
        ],
      );
    },
  );
}

class _CurrencyHeading extends StatelessWidget {
  const _CurrencyHeading({required this.currency, required this.detail});
  final String currency, detail;
  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(
        currency,
        style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800),
      ),
      const SizedBox(height: 4),
      Text(detail),
    ],
  );
}

class _ReportEmpty extends StatelessWidget {
  const _ReportEmpty({required this.title, required this.message});
  final String title, message;
  @override
  Widget build(BuildContext context) => SectionCard(
    child: Column(
      children: [
        const Icon(Icons.bar_chart_outlined, size: 40),
        const SizedBox(height: 12),
        Text(
          title,
          textAlign: TextAlign.center,
          style: Theme.of(context).textTheme.titleMedium,
        ),
        const SizedBox(height: 8),
        Text(message, textAlign: TextAlign.center),
      ],
    ),
  );
}

String _kindLabel(ReportKind kind) => switch (kind) {
  ReportKind.sales => 'Sales activity',
  ReportKind.inventory => 'Current inventory',
  ReportKind.expenses => 'Expense activity',
};
String _money(String currency, int minor) =>
    '$currency ${Money.formatMinor(minor)}';
String _label(String value) =>
    value.isEmpty ? value : '${value[0].toUpperCase()}${value.substring(1)}';
