import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/security/app_role.dart';
import '../../core/widgets/brand_mark.dart';
import '../../core/widgets/status_widgets.dart';
import '../../features/dashboard/dashboard_page.dart';
import '../../features/administration/presentation/audit_logs_page.dart';
import '../../features/catalog/presentation/products_page.dart';
import '../../features/employees/presentation/employees_page.dart';
import '../../features/people/presentation/people_page.dart';
import '../../features/pos/pos_page.dart';
import '../../features/settings/settings_page.dart';
import '../../features/sales/presentation/sales_page.dart';
import '../../features/shifts/presentation/shifts_page.dart';
import '../../features/inventory/presentation/inventory_page.dart';
import '../../features/security/presentation/security_page.dart';
import '../../features/security/domain/security_models.dart';
import '../../features/security/pin_security_section.dart';
import '../../features/authentication/presentation/security_mfa_page.dart';
import '../../features/purchases/presentation/purchases_page.dart';
import '../../features/expenses/presentation/expenses_page.dart';
import '../../features/reports/presentation/reports_page.dart';
import '../../features/logistics/presentation/logistics_page.dart';
import '../../features/invitations/presentation/invitations_page.dart';
import '../config/app_brand.dart';
import '../business_services.dart';
import '../config/feature_status.dart';
import '../routing/app_module.dart';

/// [role] must come from a verified membership, never a user-selectable role.
/// The design preview displays layout only and grants no business capability.
class NexaShell extends StatefulWidget {
  const NexaShell({
    this.role,
    this.businessName,
    this.userName,
    this.isPreview = true,
    this.onSignOut,
    this.services,
    this.membershipId,
    this.currentUserId,
    this.onOpenOffline,
    this.onLock,
    this.onSignOutAllSessions,
    this.onSecurityPolicyChanged,
    this.onScopeChanged,
    super.key,
  });

  final AppRole? role;
  final String? businessName;
  final String? userName;
  final bool isPreview;
  final VoidCallback? onSignOut;
  final BusinessServices? services;
  final String? membershipId;
  final String? currentUserId;
  final VoidCallback? onOpenOffline;
  final VoidCallback? onLock;
  final Future<void> Function()? onSignOutAllSessions;
  final ValueChanged<SecurityPolicy>? onSecurityPolicyChanged;
  final Future<void> Function()? onScopeChanged;

  @override
  State<NexaShell> createState() => _NexaShellState();
}

class _NexaShellState extends State<NexaShell> {
  AppModule _selected = AppModule.dashboard;
  bool _showMore = false;
  String? _savedBusinessName;
  final Set<AppModule> _visited = {AppModule.dashboard};

  @override
  void didUpdateWidget(covariant NexaShell oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.businessName != widget.businessName) {
      _savedBusinessName = null;
    }
    if (oldWidget.services != widget.services ||
        oldWidget.role != widget.role ||
        oldWidget.membershipId != widget.membershipId ||
        oldWidget.isPreview != widget.isPreview) {
      _visited.clear();
      _visited.add(_selected);
    }
  }

  List<AppModule> get _modules => widget.isPreview
      ? AppModule.values
      : AppModule.values
            .where((module) => widget.role?.allows(module.permission) ?? false)
            .toList();

  void _select(AppModule module) {
    if (!_modules.contains(module)) return;
    setState(() {
      _selected = module;
      _visited.add(module);
      _showMore = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final modules = _modules;
    if (!modules.contains(_selected) && modules.isNotEmpty) {
      _selected = modules.first;
    }
    return CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.digit1, control: true): () =>
            _select(AppModule.dashboard),
        const SingleActivator(LogicalKeyboardKey.digit2, control: true): () =>
            _select(AppModule.pos),
      },
      child: Focus(
        autofocus: true,
        child: LayoutBuilder(
          builder: (context, constraints) {
            final desktop = constraints.maxWidth >= 1100;
            final tablet = constraints.maxWidth >= 720 && !desktop;
            final phone = !desktop && !tablet;
            return Scaffold(
              backgroundColor: const Color(0xfff5f7fb),
              body: SafeArea(
                child: Row(
                  children: [
                    if (!phone) _navigation(modules, compact: tablet),
                    Expanded(
                      child: Column(
                        children: [
                          _header(phone: phone),
                          if (widget.isPreview) _previewBanner(),
                          Expanded(
                            child: modules.isEmpty
                                ? const Center(
                                    child: FeatureEmptyState(
                                      icon: Icons.lock_outline,
                                      title: 'Verified membership required',
                                      message:
                                          'Sign in with an active business membership to access authorized modules.',
                                      status: FeatureStatus.notYetConnected,
                                    ),
                                  )
                                : IndexedStack(
                                    index: _showMore && phone
                                        ? AppModule.values.length
                                        : _selected.index,
                                    children: [
                                      for (final module in AppModule.values)
                                        _visited.contains(module) &&
                                                modules.contains(module)
                                            ? TickerMode(
                                                enabled:
                                                    _selected == module &&
                                                    !_showMore,
                                                child: KeyedSubtree(
                                                  key: ValueKey(
                                                    '${widget.services.hashCode}:${widget.role}:${module.name}',
                                                  ),
                                                  child: _page(module),
                                                ),
                                              )
                                            : const SizedBox.shrink(),
                                      if (_showMore && phone)
                                        _morePage(modules)
                                      else
                                        const SizedBox.shrink(),
                                    ],
                                  ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              bottomNavigationBar: phone && modules.isNotEmpty
                  ? _bottomNavigation(modules)
                  : null,
            );
          },
        ),
      ),
    );
  }

  Widget _navigation(List<AppModule> modules, {required bool compact}) =>
      Container(
        key: Key(compact ? 'tablet-navigation' : 'desktop-navigation'),
        width: compact ? 76 : 224,
        color: AppBrand.navyColor,
        child: Column(
          children: [
            Padding(
              padding: EdgeInsets.fromLTRB(compact ? 15 : 22, 25, 15, 25),
              child: Row(
                children: [
                  const BrandMark(size: 38),
                  if (!compact) ...[
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        AppBrand.appName,
                        style: const TextStyle(
                          fontSize: 22,
                          fontWeight: FontWeight.w800,
                          color: Colors.white,
                          letterSpacing: -.5,
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),
            Expanded(
              child: ListView(
                padding: EdgeInsets.symmetric(horizontal: compact ? 12 : 14),
                children: [
                  if (!compact) ...[
                    const Padding(
                      padding: EdgeInsets.fromLTRB(12, 0, 0, 13),
                      child: Text(
                        'WORKSPACE',
                        style: TextStyle(
                          color: Color(0xff7e90ab),
                          fontSize: 10,
                          fontWeight: FontWeight.w700,
                          letterSpacing: 1.4,
                        ),
                      ),
                    ),
                  ],
                  ...modules.map((module) {
                    final active = module == _selected;
                    return Padding(
                      padding: const EdgeInsets.only(bottom: 4),
                      child: Tooltip(
                        message: module == AppModule.dashboard
                            ? '${module.label} · Ctrl+1'
                            : module == AppModule.pos
                            ? '${module.label} · Ctrl+2'
                            : module.label,
                        child: Material(
                          color: active
                              ? AppBrand.primaryColor
                              : Colors.transparent,
                          borderRadius: BorderRadius.circular(10),
                          child: InkWell(
                            key: Key('navigate-${module.name}'),
                            onTap: () => _select(module),
                            borderRadius: BorderRadius.circular(10),
                            child: Padding(
                              padding: EdgeInsets.symmetric(
                                horizontal: compact ? 0 : 12,
                                vertical: 13,
                              ),
                              child: Row(
                                mainAxisAlignment: compact
                                    ? MainAxisAlignment.center
                                    : MainAxisAlignment.start,
                                children: [
                                  Icon(
                                    module.icon,
                                    size: 20,
                                    color: active
                                        ? Colors.white
                                        : const Color(0xffaab8cd),
                                  ),
                                  if (!compact) ...[
                                    const SizedBox(width: 12),
                                    Expanded(
                                      child: Text(
                                        module.label,
                                        style: TextStyle(
                                          color: active
                                              ? Colors.white
                                              : const Color(0xffc5cfdd),
                                          fontWeight: active
                                              ? FontWeight.w600
                                              : FontWeight.w400,
                                          fontSize: 13,
                                        ),
                                      ),
                                    ),
                                  ],
                                ],
                              ),
                            ),
                          ),
                        ),
                      ),
                    );
                  }),
                ],
              ),
            ),
            if (!compact)
              Padding(
                padding: const EdgeInsets.fromLTRB(26, 18, 20, 24),
                child: Text(
                  AppBrand.tagline,
                  style: const TextStyle(
                    color: Color(0xff7e90ab),
                    height: 1.5,
                    fontSize: 11,
                  ),
                ),
              ),
          ],
        ),
      );

  Widget _header({required bool phone}) => Container(
    padding: EdgeInsets.symmetric(horizontal: phone ? 16 : 24, vertical: 16),
    decoration: const BoxDecoration(
      color: Colors.white,
      border: Border(bottom: BorderSide(color: Color(0xffe7edf5))),
    ),
    child: Row(
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                widget.isPreview
                    ? AppBrand.appName
                    : _savedBusinessName ??
                          widget.businessName ??
                          'Business not selected',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontWeight: FontWeight.w700,
                  color: Color(0xff10223f),
                  fontSize: 16,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                widget.isPreview
                    ? 'Design workspace · No active session'
                    : widget.userName ?? 'Signed-in account',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(color: Color(0xff64748b), fontSize: 11),
              ),
            ],
          ),
        ),
        if (!widget.isPreview && widget.onOpenOffline != null)
          IconButton(
            key: const Key('open-offline-workspace'),
            tooltip: 'Authorized offline workspace',
            onPressed: widget.onOpenOffline,
            icon: const Icon(Icons.offline_bolt_outlined, size: 20),
          ),
        if (!widget.isPreview && widget.services?.security != null)
          IconButton(
            tooltip: 'Account and device security',
            onPressed: _openSecurity,
            icon: const Icon(Icons.shield_outlined, size: 20),
          ),
        if (!widget.isPreview && widget.onLock != null)
          IconButton(
            tooltip: 'Lock workspace',
            onPressed: widget.onLock,
            icon: const Icon(Icons.lock_outline, size: 20),
          ),
        if (widget.onSignOut != null) ...[
          const SizedBox(width: 12),
          IconButton(
            tooltip: widget.isPreview ? 'Exit design preview' : 'Sign out',
            onPressed: widget.onSignOut,
            icon: Icon(
              widget.isPreview ? Icons.close : Icons.logout_outlined,
              size: 20,
            ),
          ),
        ],
      ],
    ),
  );

  Widget _previewBanner() => Container(
    key: const Key('design-preview-banner'),
    width: double.infinity,
    color: const Color(0xffeff6ff),
    padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 11),
    child: const Row(
      children: [
        Icon(Icons.visibility_outlined, size: 17, color: Color(0xff2563eb)),
        SizedBox(width: 10),
        Expanded(
          child: Text(
            'DESIGN PREVIEW · Not Yet Connected',
            style: TextStyle(
              color: Color(0xff2563eb),
              fontSize: 11,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
      ],
    ),
  );

  static const _primaryMobileModules = [
    AppModule.dashboard,
    AppModule.pos,
    AppModule.sales,
    AppModule.inventory,
  ];

  Widget _bottomNavigation(List<AppModule> modules) {
    final primary = _primaryMobileModules.where(modules.contains).toList();
    final hasMore = modules.any((module) => !primary.contains(module));
    final selected = _showMore || !primary.contains(_selected)
        ? primary.length
        : primary.indexOf(_selected);
    final destinations = [
      ...primary.map(
        (module) => NavigationDestination(
          icon: Icon(module.icon),
          label: module == AppModule.dashboard ? 'Home' : module.label,
        ),
      ),
      if (hasMore)
        const NavigationDestination(icon: Icon(Icons.apps), label: 'More'),
    ];
    return NavigationBar(
      key: const Key('mobile-navigation'),
      height: 72,
      selectedIndex: selected.clamp(0, destinations.length - 1),
      destinations: destinations,
      onDestinationSelected: (index) {
        if (index < primary.length) {
          _select(primary[index]);
        } else {
          setState(() => _showMore = true);
        }
      },
    );
  }

  Widget _morePage(List<AppModule> modules) => ListView(
    padding: const EdgeInsets.all(20),
    children: [
      const PageHeading(
        title: 'More',
        subtitle: 'Everything you need to manage your business.',
      ),
      const SizedBox(height: 24),
      ...modules
          .where((module) => !_primaryMobileModules.contains(module))
          .map(
            (module) => Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: SectionCard(
                padding: 0,
                child: ListTile(
                  key: Key('navigate-${module.name}'),
                  onTap: () => _select(module),
                  leading: Icon(
                    module.icon,
                    color: Theme.of(context).colorScheme.primary,
                  ),
                  title: Text(module.label),
                  trailing: const Icon(Icons.chevron_right, size: 20),
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 18,
                    vertical: 5,
                  ),
                ),
              ),
            ),
          ),
    ],
  );

  Widget _page(AppModule selected) => switch (selected) {
    AppModule.dashboard => DashboardPage(isPreview: widget.isPreview),
    AppModule.pos => PosPage(
      repository: widget.services?.checkout,
      catalogRepository: widget.services?.catalog,
      peopleRepository: widget.services?.people,
      role: widget.role,
      isPreview: widget.isPreview,
    ),
    AppModule.sales => SalesPage(
      repository: widget.services?.checkout,
      peopleRepository: widget.services?.people,
      role: widget.role,
      isPreview: widget.isPreview,
    ),
    AppModule.shifts => ShiftsPage(
      repository: widget.services?.checkout,
      peopleRepository: widget.services?.people,
      role: widget.role,
      currentUserId: widget.currentUserId,
      isPreview: widget.isPreview,
    ),
    AppModule.inventory => Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 0),
          child: Align(
            alignment: Alignment.centerRight,
            child: OutlinedButton.icon(
              onPressed: () => _openLogistics(),
              icon: const Icon(Icons.local_shipping_outlined),
              label: const Text("Transfers and supplier returns"),
            ),
          ),
        ),
        Expanded(
          child: InventoryPage(
            repository: widget.services?.inventory,
            peopleRepository: widget.services?.people,
            role: widget.role,
            isPreview: widget.isPreview,
          ),
        ),
      ],
    ),
    AppModule.purchases => PurchasesPage(
      repository: widget.services?.purchases,
      peopleRepository: widget.services?.people,
      catalogRepository: widget.services?.catalog,
      role: widget.role,
      isPreview: widget.isPreview,
    ),
    AppModule.expenses => ExpensesPage(
      repository: widget.services?.expenses,
      peopleRepository: widget.services?.people,
      role: widget.role,
      isPreview: widget.isPreview,
    ),
    AppModule.reports => ReportsPage(
      repository: widget.services?.reports,
      peopleRepository: widget.services?.people,
      checkoutRepository: widget.services?.checkout,
      role: widget.role,
      currentUserId: widget.currentUserId,
      isPreview: widget.isPreview,
    ),
    AppModule.products => ProductsPage(
      repository: widget.services?.catalog,
      peopleRepository: widget.services?.people,
      role: widget.role,
      isPreview: widget.isPreview,
    ),
    AppModule.suppliers => PeoplePage(
      kind: PeopleKind.suppliers,
      repository: widget.services?.people,
      role: widget.role,
      isPreview: widget.isPreview,
    ),
    AppModule.customers => PeoplePage(
      kind: PeopleKind.customers,
      repository: widget.services?.people,
      role: widget.role,
      isPreview: widget.isPreview,
    ),
    AppModule.employees => EmployeesPage(
      repository: widget.services?.employees,
      role: widget.role,
      currentMembershipId: widget.membershipId,
      onOpenInvitations: _openInvitations,
      isPreview: widget.isPreview,
    ),
    AppModule.auditLogs => AuditLogsPage(
      repository: widget.services?.administration,
      peopleRepository: widget.services?.people,
      role: widget.role,
      isPreview: widget.isPreview,
    ),
    AppModule.settings => SettingsPage(
      repository: widget.services?.administration,
      role: widget.role,
      isPreview: widget.isPreview,
      onBusinessNameSaved: (name) => setState(() => _savedBusinessName = name),
      onOpenBranches: () => _openLogistics(branchesOnly: true),
      onOpenSecurity: widget.isPreview || widget.services?.security == null
          ? null
          : _openSecurity,
    ),
    AppModule.notifications => _securityPage(notices: true),
  };

  void _openInvitations() {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => Scaffold(
          appBar: AppBar(title: const Text('Employee invitations')),
          body: InvitationsPage(
            repository: widget.services?.invitationAdministration,
            role: widget.role,
            isPreview: widget.isPreview,
          ),
        ),
      ),
    );
  }

  void _openLogistics({bool branchesOnly = false}) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => Scaffold(
          appBar: AppBar(
            title: Text(branchesOnly ? 'Branch management' : 'Stock logistics'),
          ),
          body: LogisticsPage(
            repository: widget.services?.logistics,
            peopleRepository: widget.services?.people,
            catalogRepository: widget.services?.catalog,
            purchaseRepository: widget.services?.purchases,
            role: widget.role,
            branchesOnly: branchesOnly,
            isPreview: widget.isPreview,
            onScopeChanged: widget.onScopeChanged,
          ),
        ),
      ),
    );
  }

  void _openSecurity() {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => Scaffold(
          appBar: AppBar(title: const Text('Account and device security')),
          body: _securityPage(),
        ),
      ),
    );
  }

  Widget _securityPage({bool notices = false}) => SecurityPage(
    repository: widget.services?.security,
    role: widget.role,
    peopleRepository: widget.services?.people,
    isPreview: widget.isPreview,
    initialSection: notices
        ? SecurityPageSection.notices
        : SecurityPageSection.overview,
    onPolicyChanged: widget.onSecurityPolicyChanged,
    extraSections: notices
        ? const []
        : [
            if (widget.services?.mfa != null)
              SecurityMfaPage(repository: widget.services!.mfa!),
            if (widget.services?.pin != null && widget.role != null)
              PinSecuritySection(
                repository: widget.services!.pin!,
                role: widget.role!,
              ),
            if (widget.onSignOutAllSessions != null)
              SectionCard(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Account sessions',
                      style: TextStyle(fontWeight: FontWeight.w700),
                    ),
                    const SizedBox(height: 8),
                    const Text(
                      'Revoke refresh sessions on every device. Already issued access tokens may remain valid until their configured expiry.',
                    ),
                    const SizedBox(height: 12),
                    OutlinedButton(
                      onPressed: () async {
                        final confirmed = await showDialog<bool>(
                          context: context,
                          builder: (context) => AlertDialog(
                            title: const Text('Sign out all account sessions?'),
                            content: const Text(
                              'This ends remembered account sessions. Paid records remain stored for reconciliation. Access tokens expire according to the Auth project policy.',
                            ),
                            actions: [
                              TextButton(
                                onPressed: () => Navigator.pop(context, false),
                                child: const Text('Cancel'),
                              ),
                              FilledButton(
                                onPressed: () => Navigator.pop(context, true),
                                child: const Text('Revoke sessions'),
                              ),
                            ],
                          ),
                        );
                        if (confirmed == true && mounted) {
                          await widget.onSignOutAllSessions!();
                        }
                      },
                      child: const Text('Sign out all sessions'),
                    ),
                  ],
                ),
              ),
          ],
  );
}
