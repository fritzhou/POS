import 'dart:async';

import 'package:flutter/material.dart';

import '../../../app/config/feature_status.dart';
import '../../../core/security/app_role.dart';
import '../../../core/widgets/status_widgets.dart';
import '../../catalog/domain/repository_support.dart';
import '../../administration/domain/administration_models.dart';
import '../domain/people_models.dart';
import '../domain/people_repository.dart';

enum PeopleKind { suppliers, customers }

/// Business records are read only in the preview. Authorization is also
/// enforced by each repository operation and by PostgreSQL.
class PeoplePage extends StatefulWidget {
  const PeoplePage({
    required this.kind,
    this.repository,
    this.role,
    this.isPreview = true,
    super.key,
  });

  final PeopleKind kind;
  final PeopleRepository? repository;
  final AppRole? role;
  final bool isPreview;

  @override
  State<PeoplePage> createState() => _PeoplePageState();
}

class _PeoplePageState extends State<PeoplePage> {
  final _search = TextEditingController();
  Timer? _debounce;
  List<_ContactView> _records = const [];
  List<BranchOption> _branches = const [];
  String? _error;
  bool _loading = false;
  bool _hasMore = false;
  bool? _active;
  int _offset = 0;
  int _generation = 0;
  static const _pageSize = 20;

  bool get _supplier => widget.kind == PeopleKind.suppliers;
  String get _plural => _supplier ? 'Suppliers' : 'Customers';
  String get _singular => _supplier ? 'Supplier' : 'Customer';
  bool get _canRead =>
      widget.role == AppRole.owner ||
      widget.role == AppRole.admin ||
      widget.role == AppRole.manager ||
      widget.role == (_supplier ? AppRole.inventoryStaff : AppRole.cashier);
  bool get _canWrite =>
      _canRead && (_supplier || widget.role != AppRole.cashier);
  bool get _connected =>
      !widget.isPreview && widget.repository != null && _canRead;

  @override
  void initState() {
    super.initState();
    if (_connected) _load();
  }

  @override
  void didUpdateWidget(PeoplePage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.repository != widget.repository ||
        oldWidget.kind != widget.kind ||
        oldWidget.role != widget.role ||
        oldWidget.isPreview != widget.isPreview) {
      _offset = 0;
      _records = const [];
      _error = null;
      _generation++;
      if (_connected) _load();
    }
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _search.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    if (!_connected) return;
    final generation = ++_generation;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final repository = widget.repository!;
      final branches = await repository.listBranches();
      final page = PageRequest(offset: _offset, limit: _pageSize);
      final List<_ContactView> records;
      final bool hasMore;
      if (_supplier) {
        final result = await repository.listSuppliers(
          query: _search.text.trim(),
          active: _active,
          page: page,
        );
        records = result.items.map(_ContactView.supplier).toList();
        hasMore = result.hasMore;
      } else {
        final result = await repository.listCustomers(
          query: _search.text.trim(),
          active: _active,
          page: page,
        );
        records = result.items.map(_ContactView.customer).toList();
        hasMore = result.hasMore;
      }
      if (!mounted || generation != _generation) return;
      setState(() {
        _branches = branches;
        _records = records;
        _hasMore = hasMore;
      });
    } catch (error) {
      if (!mounted || generation != _generation) return;
      setState(() {
        _records = const [];
        _error = _publicFailure(error);
      });
    } finally {
      if (mounted && generation == _generation) {
        setState(() => _loading = false);
      }
    }
  }

  Future<void> _edit([_ContactView? record]) async {
    if (!_connected || !_canWrite) return;
    final saved = await showDialog<bool>(
      context: context,
      builder: (context) => _ContactDialog(
        supplier: _supplier,
        repository: widget.repository!,
        record: record,
        branches: _branches,
        requireBranch:
            widget.role == AppRole.manager ||
            widget.role == AppRole.inventoryStaff,
      ),
    );
    if (!mounted || saved != true) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text('$_singular saved.')));
    await _load();
  }

  @override
  Widget build(BuildContext context) => ListView(
    padding: const EdgeInsets.all(20),
    children: [
      PageHeading(
        title: _plural,
        subtitle: _supplier
            ? 'Maintain supplier contacts for your purchasing workflow.'
            : 'Find customer contacts within your authorized business scope.',
        trailing: FilledButton.icon(
          key: const Key('people-add'),
          onPressed: _connected && _canWrite && !_loading
              ? () => _edit()
              : null,
          icon: const Icon(Icons.add, size: 18),
          label: Text('Add $_singular'),
        ),
      ),
      const SizedBox(height: 20),
      if (!_connected)
        SectionCard(
          child: FeatureEmptyState(
            icon: _supplier
                ? Icons.local_shipping_outlined
                : Icons.people_outline,
            title: !widget.isPreview && widget.repository != null && !_canRead
                ? 'Access restricted'
                : 'No connected ${_plural.toLowerCase()}',
            message: !widget.isPreview && widget.repository != null && !_canRead
                ? 'Your verified role does not grant access to these records.'
                : 'Connect Supabase and sign in with an authorized membership to view or manage real contacts. This preview contains no customer or supplier records.',
            status: FeatureStatus.notYetConnected,
          ),
        )
      else ...[
        if (!_canWrite) ...[
          const StatusPill(
            label: 'Contact lookup · Read only',
            icon: Icons.lock_outline,
          ),
          const SizedBox(height: 16),
        ],
        SectionCard(
          child: Column(
            children: [
              LayoutBuilder(
                builder: (context, constraints) {
                  final search = TextField(
                    controller: _search,
                    key: const Key('people-search'),
                    decoration: InputDecoration(
                      hintText: 'Search contacts by name',
                      prefixIcon: const Icon(Icons.search),
                      border: const OutlineInputBorder(),
                    ),
                    onChanged: (_) {
                      _debounce?.cancel();
                      _debounce = Timer(const Duration(milliseconds: 300), () {
                        _offset = 0;
                        _load();
                      });
                    },
                  );
                  final filter = DropdownButtonFormField<bool?>(
                    isExpanded: true,
                    initialValue: _active,
                    decoration: const InputDecoration(
                      labelText: 'Status',
                      border: OutlineInputBorder(),
                    ),
                    items: const [
                      DropdownMenuItem(
                        value: null,
                        child: Text('All statuses'),
                      ),
                      DropdownMenuItem(value: true, child: Text('Active')),
                      DropdownMenuItem(value: false, child: Text('Inactive')),
                    ],
                    onChanged: (value) {
                      setState(() {
                        _active = value;
                        _offset = 0;
                      });
                      _load();
                    },
                  );
                  return constraints.maxWidth < 600
                      ? Column(
                          children: [
                            search,
                            const SizedBox(height: 12),
                            filter,
                          ],
                        )
                      : Row(
                          children: [
                            Expanded(child: search),
                            const SizedBox(width: 16),
                            SizedBox(width: 180, child: filter),
                          ],
                        );
                },
              ),
              const SizedBox(height: 20),
              if (_loading) const LinearProgressIndicator(),
              if (_error != null)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 24),
                  child: Column(
                    children: [
                      Text(_error!, textAlign: TextAlign.center),
                      const SizedBox(height: 12),
                      OutlinedButton.icon(
                        onPressed: _loading ? null : _load,
                        icon: const Icon(Icons.refresh),
                        label: const Text('Retry'),
                      ),
                    ],
                  ),
                )
              else if (!_loading && _records.isEmpty)
                FeatureEmptyState(
                  icon: Icons.search_off_outlined,
                  title: 'No ${_plural.toLowerCase()} found',
                  message: _search.text.trim().isEmpty
                      ? 'Create your first ${_singular.toLowerCase()} when you have a real contact to record.'
                      : 'Try a different search or status filter.',
                  status: FeatureStatus.available,
                )
              else if (_records.isNotEmpty)
                LayoutBuilder(
                  builder: (context, constraints) => constraints.maxWidth < 720
                      ? Column(children: _records.map(_mobileContact).toList())
                      : SingleChildScrollView(
                          scrollDirection: Axis.horizontal,
                          child: DataTable(
                            columns: [
                              const DataColumn(label: Text('Name')),
                              const DataColumn(label: Text('Phone / Email')),
                              const DataColumn(label: Text('Branch')),
                              const DataColumn(label: Text('Status')),
                              if (_canWrite) const DataColumn(label: Text('')),
                            ],
                            rows: _records
                                .map(
                                  (record) => DataRow(
                                    cells: [
                                      DataCell(
                                        SizedBox(
                                          width: 180,
                                          child: Text(record.name),
                                        ),
                                      ),
                                      DataCell(
                                        SizedBox(
                                          width: 210,
                                          child: Text(_contactSummary(record)),
                                        ),
                                      ),
                                      DataCell(
                                        Text(_branchLabel(record.branchId)),
                                      ),
                                      DataCell(_status(record.active)),
                                      if (_canWrite)
                                        DataCell(
                                          IconButton(
                                            tooltip: 'Edit ${record.name}',
                                            icon: const Icon(
                                              Icons.edit_outlined,
                                            ),
                                            onPressed: _loading
                                                ? null
                                                : () => _edit(record),
                                          ),
                                        ),
                                    ],
                                  ),
                                )
                                .toList(),
                          ),
                        ),
                ),
              if (_error == null) ...[
                const SizedBox(height: 12),
                Wrap(
                  alignment: WrapAlignment.center,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  spacing: 12,
                  children: [
                    IconButton(
                      tooltip: 'Previous page',
                      onPressed: !_loading && _offset > 0
                          ? () {
                              _offset = (_offset - _pageSize).clamp(0, 100000);
                              _load();
                            }
                          : null,
                      icon: const Icon(Icons.chevron_left),
                    ),
                    Text('Page ${_offset ~/ _pageSize + 1}'),
                    IconButton(
                      tooltip: 'Next page',
                      onPressed: !_loading && _hasMore
                          ? () {
                              _offset += _pageSize;
                              _load();
                            }
                          : null,
                      icon: const Icon(Icons.chevron_right),
                    ),
                    IconButton(
                      tooltip: 'Refresh contacts',
                      onPressed: _loading ? null : _load,
                      icon: const Icon(Icons.refresh),
                    ),
                  ],
                ),
              ],
            ],
          ),
        ),
      ],
    ],
  );

  Widget _mobileContact(_ContactView record) => Padding(
    padding: const EdgeInsets.only(bottom: 12),
    child: Card.outlined(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              record.name,
              style: const TextStyle(fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 8),
            Text(_contactSummary(record)),
            const SizedBox(height: 8),
            Text(_branchLabel(record.branchId)),
            const SizedBox(height: 12),
            Wrap(
              spacing: 12,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                _status(record.active),
                if (_canWrite)
                  TextButton.icon(
                    onPressed: _loading ? null : () => _edit(record),
                    icon: const Icon(Icons.edit_outlined, size: 16),
                    label: const Text('Edit'),
                  ),
              ],
            ),
          ],
        ),
      ),
    ),
  );

  String _branchLabel(String? id) => id == null
      ? 'Business wide'
      : _branches
                .where((branch) => branch.id == id)
                .map((branch) => branch.name)
                .firstOrNull ??
            'Assigned branch';
  String _contactSummary(_ContactView record) =>
      [record.phone, record.email]
          .whereType<String>()
          .where((value) => value.isNotEmpty)
          .join('\n')
          .isEmpty
      ? 'No phone or email recorded'
      : [
          record.phone,
          record.email,
        ].whereType<String>().where((value) => value.isNotEmpty).join('\n');
  Widget _status(bool active) => StatusPill(
    label: active ? 'Active' : 'Inactive',
    color: active ? const Color(0xff15803d) : const Color(0xff64748b),
  );
}

class _ContactView {
  const _ContactView({
    required this.id,
    required this.name,
    required this.active,
    required this.revision,
    this.contactName,
    this.email,
    this.phone,
    this.address,
    this.notes,
    this.branchId,
  });
  factory _ContactView.supplier(Supplier value) => _ContactView(
    id: value.id,
    name: value.name,
    active: value.active,
    revision: value.revision,
    contactName: value.contactName,
    email: value.email,
    phone: value.phone,
    address: value.address,
    notes: value.notes,
    branchId: value.branchId,
  );
  factory _ContactView.customer(Customer value) => _ContactView(
    id: value.id,
    name: value.name,
    active: value.active,
    revision: value.revision,
    email: value.email,
    phone: value.phone,
    address: value.address,
    notes: value.notes,
    branchId: value.branchId,
  );
  final String id;
  final String name;
  final bool active;
  final int revision;
  final String? contactName, email, phone, address, notes, branchId;
}

class _ContactDialog extends StatefulWidget {
  const _ContactDialog({
    required this.supplier,
    required this.repository,
    required this.branches,
    required this.requireBranch,
    this.record,
  });
  final bool supplier;
  final PeopleRepository repository;
  final List<BranchOption> branches;
  final bool requireBranch;
  final _ContactView? record;
  @override
  State<_ContactDialog> createState() => _ContactDialogState();
}

class _ContactDialogState extends State<_ContactDialog> {
  final _form = GlobalKey<FormState>();
  late final TextEditingController _name,
      _contactName,
      _email,
      _phone,
      _address,
      _notes;
  String? _branchId, _error;
  bool _active = true;
  bool _saving = false;
  @override
  void initState() {
    super.initState();
    final record = widget.record;
    _name = TextEditingController(text: record?.name);
    _contactName = TextEditingController(text: record?.contactName);
    _email = TextEditingController(text: record?.email);
    _phone = TextEditingController(text: record?.phone);
    _address = TextEditingController(text: record?.address);
    _notes = TextEditingController(text: record?.notes);
    _active = record?.active ?? true;
    _branchId = record?.branchId;
    if (_branchId == null &&
        widget.requireBranch &&
        widget.branches.length == 1) {
      _branchId = widget.branches.first.id;
    }
  }

  @override
  void dispose() {
    for (final controller in [
      _name,
      _contactName,
      _email,
      _phone,
      _address,
      _notes,
    ]) {
      controller.dispose();
    }
    super.dispose();
  }

  Future<void> _save() async {
    if (_saving || !_form.currentState!.validate()) return;
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      final record = widget.record;
      if (widget.supplier) {
        final input = SupplierInput(
          name: _name.text,
          contactName: _contactName.text,
          email: _email.text,
          phone: _phone.text,
          address: _address.text,
          notes: _notes.text,
          branchId: _branchId,
          active: _active,
        );
        if (record == null) {
          await widget.repository.createSupplier(input);
        } else {
          await widget.repository.updateSupplier(
            id: record.id,
            expectedRevision: record.revision,
            input: input,
          );
        }
      } else {
        final input = CustomerInput(
          name: _name.text,
          email: _email.text,
          phone: _phone.text,
          address: _address.text,
          notes: _notes.text,
          branchId: _branchId,
          active: _active,
        );
        if (record == null) {
          await widget.repository.createCustomer(input);
        } else {
          await widget.repository.updateCustomer(
            id: record.id,
            expectedRevision: record.revision,
            input: input,
          );
        }
      }
      if (mounted) Navigator.of(context).pop(true);
    } catch (error) {
      if (mounted) {
        setState(
          () => _error =
              error is RepositoryFailure &&
                  error.type == RepositoryFailureType.conflict
              ? 'This contact changed since you opened it. Close this form, refresh the list and review the latest record before saving again.'
              : _publicFailure(error),
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Widget _field(
    TextEditingController controller,
    String label,
    int maximum, {
    bool required = false,
    bool email = false,
    int lines = 1,
  }) => Padding(
    padding: const EdgeInsets.only(bottom: 14),
    child: TextFormField(
      controller: controller,
      enabled: !_saving,
      maxLength: maximum,
      maxLines: lines,
      keyboardType: email
          ? TextInputType.emailAddress
          : label == 'Phone'
          ? TextInputType.phone
          : TextInputType.text,
      decoration: InputDecoration(
        labelText: label,
        border: const OutlineInputBorder(),
        counterText: '',
      ),
      validator: (value) {
        final text = value?.trim() ?? '';
        if (required && text.isEmpty) return '$label is required.';
        if (text.length > maximum) return '$label is too long.';
        if (email &&
            text.isNotEmpty &&
            !RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]+$').hasMatch(text)) {
          return 'Enter a valid email address.';
        }
        return null;
      },
    ),
  );
  @override
  Widget build(BuildContext context) => AlertDialog(
    title: Text(
      '${widget.record == null ? 'Add' : 'Edit'} ${widget.supplier ? 'Supplier' : 'Customer'}',
    ),
    content: SizedBox(
      width: 480,
      child: SingleChildScrollView(
        child: Form(
          key: _form,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              _field(_name, 'Name', 160, required: true),
              if (widget.supplier) _field(_contactName, 'Contact name', 120),
              _field(_phone, 'Phone', 40),
              _field(_email, 'Email', 254, email: true),
              _field(_address, 'Address', 1000, lines: 2),
              _field(_notes, 'Notes', 2000, lines: 2),
              DropdownButtonFormField<String>(
                initialValue:
                    widget.branches.any((branch) => branch.id == _branchId)
                    ? _branchId
                    : null,
                isExpanded: true,
                decoration: const InputDecoration(
                  labelText: 'Branch scope',
                  border: OutlineInputBorder(),
                ),
                items: [
                  if (!widget.requireBranch)
                    const DropdownMenuItem(
                      value: null,
                      child: Text('Business wide'),
                    ),
                  ...widget.branches.map(
                    (branch) => DropdownMenuItem(
                      value: branch.id,
                      child: Text(branch.name, overflow: TextOverflow.ellipsis),
                    ),
                  ),
                ],
                onChanged: _saving
                    ? null
                    : (value) => setState(() => _branchId = value),
                validator: (value) => widget.requireBranch && value == null
                    ? 'Choose an authorized branch.'
                    : null,
              ),
              const SizedBox(height: 10),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Active'),
                value: _active,
                onChanged: _saving
                    ? null
                    : (value) => setState(() => _active = value),
              ),
              if (_error != null)
                Padding(
                  padding: const EdgeInsets.only(top: 12),
                  child: Text(
                    _error!,
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.error,
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    ),
    actions: [
      TextButton(
        onPressed: _saving ? null : () => Navigator.pop(context),
        child: const Text('Cancel'),
      ),
      FilledButton(
        onPressed: _saving ? null : _save,
        child: Text(_saving ? 'Saving…' : 'Save contact'),
      ),
    ],
  );
}

String _publicFailure(Object error) => error is RepositoryFailure
    ? error.message
    : 'Contacts could not be loaded or saved. Check your connection and try again.';
