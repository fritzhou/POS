import 'dart:convert';

import 'package:flutter/material.dart';

import '../../../app/config/feature_status.dart';
import '../../../core/security/app_role.dart';
import '../../../core/widgets/status_widgets.dart';
import '../../catalog/domain/repository_support.dart';
import '../../people/domain/people_repository.dart';
import '../domain/administration_models.dart';
import '../domain/administration_repository.dart';

class AuditLogsPage extends StatefulWidget {
  const AuditLogsPage({
    this.repository,
    this.peopleRepository,
    this.role,
    this.isPreview = true,
    super.key,
  });
  final AdministrationRepository? repository;
  final PeopleRepository? peopleRepository;
  final AppRole? role;
  final bool isPreview;
  @override
  State<AuditLogsPage> createState() => _AuditLogsPageState();
}

class _AuditLogsPageState extends State<AuditLogsPage> {
  final _entity = TextEditingController();
  final _action = TextEditingController();
  String? _selectedBranch;
  List<BranchOption> _branches = const [];
  String? _branchError;
  int _scopeGeneration = 0;
  static const _pageSize = 20;
  DataPage<AuditEntry>? _page;
  bool _busy = false;
  String? _error;
  int _generation = 0;
  AuditFilter _filter = const AuditFilter();
  bool get _authorized =>
      !widget.isPreview &&
      widget.repository != null &&
      (widget.role?.allows(AppPermission.viewAuditLogs) ?? false);

  @override
  void initState() {
    super.initState();
    if (_authorized) {
      _loadBranches();
      _load(0);
    }
  }

  @override
  void didUpdateWidget(covariant AuditLogsPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.repository != widget.repository ||
        oldWidget.role != widget.role ||
        oldWidget.isPreview != widget.isPreview ||
        oldWidget.peopleRepository != widget.peopleRepository) {
      _generation++;
      _scopeGeneration++;
      _page = null;
      _error = null;
      _busy = false;
      _filter = const AuditFilter();
      _entity.clear();
      _action.clear();
      _selectedBranch = null;
      _branches = const [];
      _branchError = null;
      if (_authorized) {
        _loadBranches();
        _load(0);
      }
    }
  }

  @override
  void dispose() {
    _entity.dispose();
    _action.dispose();
    super.dispose();
  }

  Future<void> _loadBranches() async {
    final repository = widget.peopleRepository;
    if (!_authorized || repository == null) return;
    final generation = _scopeGeneration;
    try {
      final branches = await repository.listBranches();
      if (!mounted || generation != _scopeGeneration) return;
      setState(() => _branches = branches);
    } on Object {
      if (!mounted || generation != _scopeGeneration) return;
      setState(
        () => _branchError =
            'Branch choices could not be loaded. All authorized events remain available.',
      );
    }
  }

  Future<void> _load(int offset) async {
    if (!_authorized || _busy) return;
    final generation = ++_generation;
    setState(() {
      _busy = true;
      _error = null;
      _page = null;
    });
    try {
      final page = await widget.repository!.listAudit(
        filter: _filter,
        page: PageRequest(offset: offset, limit: _pageSize),
      );
      if (!mounted || generation != _generation) return;
      setState(() => _page = page);
    } on RepositoryFailure catch (error) {
      if (mounted && generation == _generation) {
        setState(() => _error = error.message);
      }
    } on Object {
      if (mounted && generation == _generation) {
        setState(
          () => _error = 'Audit records could not be loaded. Try again.',
        );
      }
    } finally {
      if (mounted && generation == _generation) setState(() => _busy = false);
    }
  }

  void _search() {
    try {
      _filter = AuditFilter(
        entity: optionalText(_entity.text, 'Entity filter', 80),
        action: optionalText(_action.text, 'Action filter', 80),
        branchId: _selectedBranch,
      );
      _load(0);
    } on RepositoryFailure catch (error) {
      setState(() => _error = error.message);
    }
  }

  String _time(DateTime value) {
    final time = value.toUtc().add(const Duration(hours: 8));
    String pad(int n) => n.toString().padLeft(2, '0');
    return '${time.year}-${pad(time.month)}-${pad(time.day)} ${pad(time.hour)}:${pad(time.minute)}:${pad(time.second)}';
  }

  void _details(AuditEntry entry) => showDialog<void>(
    context: context,
    builder: (context) => AlertDialog(
      title: const Text('Audit event'),
      content: SizedBox(
        width: 600,
        child: SingleChildScrollView(
          child: SelectableText(
            'Time: ${_time(entry.occurredAt)} (Asia/Manila)\nAction: ${entry.action}\nEntity: ${entry.entity}\nEntity ID: ${entry.entityId ?? '—'}\nActor ID: ${entry.userId ?? 'System'}\nRole: ${entry.role}\nBranch ID: ${entry.branchId ?? 'Organization'}\nReason: ${entry.reason ?? '—'}\n\nMetadata\n${const JsonEncoder.withIndent('  ').convert(entry.metadata)}',
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

  @override
  Widget build(BuildContext context) => ListView(
    padding: const EdgeInsets.all(24),
    children: [
      PageHeading(
        title: 'Audit Logs',
        subtitle:
            'Read-only server events. Times use Asia/Manila (UTC+08). Managers see authorized branch events.',
        trailing: !_authorized
            ? const StatusPill(status: FeatureStatus.notYetConnected)
            : null,
      ),
      const SizedBox(height: 24),
      SectionCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            LayoutBuilder(
              builder: (context, constraints) {
                final fields = [
                  TextField(
                    key: const Key('audit-entity'),
                    controller: _entity,
                    enabled: _authorized && !_busy,
                    decoration: const InputDecoration(labelText: 'Entity'),
                    onSubmitted: (_) => _search(),
                  ),
                  TextField(
                    key: const Key('audit-action'),
                    controller: _action,
                    enabled: _authorized && !_busy,
                    decoration: const InputDecoration(labelText: 'Action'),
                    onSubmitted: (_) => _search(),
                  ),
                  DropdownButtonFormField<String>(
                    key: ValueKey('audit-branch-$_scopeGeneration'),
                    initialValue: _selectedBranch,
                    isExpanded: true,
                    decoration: const InputDecoration(labelText: 'Branch'),
                    items: [
                      const DropdownMenuItem<String>(
                        value: null,
                        child: Text('All authorized branches'),
                      ),
                      ..._branches.map(
                        (branch) => DropdownMenuItem(
                          value: branch.id,
                          child: Text(
                            branch.name,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ),
                    ],
                    onChanged: _authorized && !_busy && _branches.isNotEmpty
                        ? (value) => setState(() => _selectedBranch = value)
                        : null,
                  ),
                ];
                return Wrap(
                  spacing: 12,
                  runSpacing: 12,
                  children: fields
                      .map(
                        (field) => SizedBox(
                          width: constraints.maxWidth < 760
                              ? constraints.maxWidth
                              : (constraints.maxWidth - 24) / 3,
                          child: field,
                        ),
                      )
                      .toList(),
                );
              },
            ),
            const SizedBox(height: 16),
            if (_branchError != null)
              Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: Text(_branchError!),
              ),
            FilledButton.icon(
              key: const Key('filter-audit'),
              onPressed: _authorized && !_busy ? _search : null,
              icon: const Icon(Icons.filter_alt_outlined),
              label: const Text('Apply filters'),
            ),
          ],
        ),
      ),
      const SizedBox(height: 16),
      if (_busy) const LinearProgressIndicator(),
      if (_error != null)
        SectionCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                _error!,
                key: const Key('audit-error'),
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
              const SizedBox(height: 12),
              OutlinedButton(
                onPressed: !_busy && _authorized ? () => _load(0) : null,
                child: const Text('Retry'),
              ),
            ],
          ),
        ),
      if (!_busy && _error == null && (_page?.items.isEmpty ?? true))
        SectionCard(
          child: FeatureEmptyState(
            icon: Icons.policy_outlined,
            title: _authorized
                ? 'No matching audit events'
                : 'Audit viewer is Not Yet Connected',
            message: _authorized
                ? 'Try another filter. Records appear after authorized server actions.'
                : 'Connect a verified business membership to read authorized audit records.',
            status: _authorized
                ? FeatureStatus.available
                : FeatureStatus.notYetConnected,
          ),
        ),
      ...?_page?.items.map(
        (entry) => Padding(
          padding: const EdgeInsets.only(bottom: 10),
          child: SectionCard(
            padding: 0,
            child: ListTile(
              onTap: () => _details(entry),
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 18,
                vertical: 8,
              ),
              title: Text('${entry.action} · ${entry.entity}'),
              subtitle: Text(
                '${_time(entry.occurredAt)}\n${entry.role} · ${entry.reason ?? 'Server event'}',
              ),
              trailing: const Icon(Icons.chevron_right),
            ),
          ),
        ),
      ),
      if (_page != null)
        Wrap(
          spacing: 12,
          runSpacing: 12,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            OutlinedButton(
              key: const Key('audit-previous'),
              onPressed: !_busy && _page!.offset > 0
                  ? () => _load((_page!.offset - _pageSize).clamp(0, 100000))
                  : null,
              child: const Text('Previous'),
            ),
            Text('Page ${_page!.offset ~/ _pageSize + 1}'),
            OutlinedButton(
              key: const Key('audit-next'),
              onPressed: !_busy && _page!.hasMore
                  ? () => _load(_page!.nextOffset)
                  : null,
              child: const Text('Next'),
            ),
          ],
        ),
    ],
  );
}
