import 'package:flutter/material.dart';
import 'package:uuid/uuid.dart';

import '../../../app/config/feature_status.dart';
import '../../../core/security/app_role.dart';
import '../../../core/widgets/status_widgets.dart';
import '../../administration/domain/administration_models.dart';
import '../../administration/domain/administration_repository.dart';
import '../../catalog/domain/repository_support.dart';

/// Roster data comes from a verified organization-scoped repository. The
/// preview grants no access and never makes an invitation request.
class EmployeesPage extends StatefulWidget {
  const EmployeesPage({
    this.repository,
    this.role,
    this.currentMembershipId,
    this.onOpenInvitations,
    this.isPreview = true,
    super.key,
  });
  final EmployeeRepository? repository;
  final AppRole? role;
  final String? currentMembershipId;
  final VoidCallback? onOpenInvitations;
  final bool isPreview;
  @override
  State<EmployeesPage> createState() => _EmployeesPageState();
}

class _EmployeesPageState extends State<EmployeesPage> {
  List<Employee> _employees = const [];
  List<BranchOption> _branches = const [];
  EmployeeStatus? _status;
  String? _error;
  bool _loading = false;
  bool _hasMore = false;
  int _offset = 0;
  int _generation = 0;
  static const _pageSize = 20;

  bool get _authorized =>
      widget.role == AppRole.owner || widget.role == AppRole.admin;
  bool get _connected =>
      !widget.isPreview && widget.repository != null && _authorized;
  bool _mayEdit(Employee employee) =>
      _connected &&
      employee.role != AppRole.owner &&
      employee.status != EmployeeStatus.pending &&
      widget.currentMembershipId != null &&
      (widget.role == AppRole.owner ||
          employee.branchIds.every(
            (id) => _branches.any((branch) => branch.id == id),
          )) &&
      employee.membershipId != widget.currentMembershipId &&
      (widget.role == AppRole.owner || employee.role != AppRole.admin);

  @override
  void initState() {
    super.initState();
    if (_connected) _load();
  }

  @override
  void didUpdateWidget(EmployeesPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.repository != widget.repository ||
        oldWidget.role != widget.role ||
        oldWidget.isPreview != widget.isPreview ||
        oldWidget.currentMembershipId != widget.currentMembershipId) {
      _offset = 0;
      _employees = const [];
      _error = null;
      _generation++;
      if (_connected) _load();
    }
  }

  Future<void> _load() async {
    if (!_connected) return;
    final generation = ++_generation;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final branches = await widget.repository!.listBranches();
      final result = await widget.repository!.listEmployees(
        status: _status,
        page: PageRequest(offset: _offset, limit: _pageSize),
      );
      if (!mounted || generation != _generation) return;
      setState(() {
        _branches = branches;
        _employees = result.items;
        _hasMore = result.hasMore;
      });
    } catch (error) {
      if (mounted && generation == _generation) {
        setState(() {
          _employees = const [];
          _error = _failure(error);
        });
      }
    } finally {
      if (mounted && generation == _generation) {
        setState(() => _loading = false);
      }
    }
  }

  Future<void> _invite() async {
    if (!_connected || _loading) return;
    final submitted = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (context) => _InvitationDialog(
        repository: widget.repository!,
        actorRole: widget.role!,
        branches: _branches,
      ),
    );
    if (submitted == true && mounted) await _load();
  }

  Future<void> _edit(Employee employee) async {
    if (!_mayEdit(employee)) return;
    final saved = await showDialog<bool>(
      context: context,
      builder: (context) => _EmployeeAccessDialog(
        repository: widget.repository!,
        actorRole: widget.role!,
        employee: employee,
        branches: _branches,
      ),
    );
    if (!mounted || saved != true) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('Employee access updated.')));
    await _load();
  }

  @override
  Widget build(BuildContext context) => ListView(
    padding: const EdgeInsets.all(20),
    children: [
      PageHeading(
        title: 'Employees',
        subtitle:
            'Invite staff and maintain their authorized roles and branches.',
        trailing: Wrap(
          spacing: 10,
          runSpacing: 8,
          children: [
            OutlinedButton.icon(
              key: const Key('employee-invitations'),
              onPressed: widget.isPreview || _authorized
                  ? widget.onOpenInvitations
                  : null,
              icon: const Icon(Icons.mail_outline, size: 18),
              label: const Text('Invitations'),
            ),
            FilledButton.icon(
              key: const Key('employee-add'),
              onPressed: _connected && !_loading ? _invite : null,
              icon: const Icon(Icons.person_add_alt_1_outlined, size: 18),
              label: const Text('Add Employee'),
            ),
          ],
        ),
      ),
      const SizedBox(height: 20),
      if (!_connected)
        SectionCard(
          child: FeatureEmptyState(
            icon: Icons.badge_outlined,
            title:
                !widget.isPreview && widget.repository != null && !_authorized
                ? 'Employee administration is restricted'
                : 'No connected employees',
            message:
                !widget.isPreview && widget.repository != null && !_authorized
                ? 'An active Owner or Admin membership is required to view this roster or invite employees.'
                : 'Connect Supabase and sign in as an authorized Owner or Admin to view real staff. This preview contains no employee records and cannot send invitations.',
            status: FeatureStatus.notYetConnected,
          ),
        )
      else ...[
        SectionCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Invitation access',
                style: TextStyle(fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 8),
              const Text(
                'Employees join through an administrator invitation and verified account. Submitting an invitation does not confirm email delivery or activate a membership.',
              ),
              const SizedBox(height: 18),
              ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 260),
                child: DropdownButtonFormField<EmployeeStatus?>(
                  isExpanded: true,
                  initialValue: _status,
                  decoration: const InputDecoration(
                    labelText: 'Roster status',
                    border: OutlineInputBorder(),
                  ),
                  items: const [
                    DropdownMenuItem(value: null, child: Text('All statuses')),
                    DropdownMenuItem(
                      value: EmployeeStatus.active,
                      child: Text('Active'),
                    ),
                    DropdownMenuItem(
                      value: EmployeeStatus.disabled,
                      child: Text('Disabled'),
                    ),
                    DropdownMenuItem(
                      value: EmployeeStatus.pending,
                      child: Text('Pending'),
                    ),
                  ],
                  onChanged: _loading
                      ? null
                      : (value) {
                          setState(() {
                            _status = value;
                            _offset = 0;
                          });
                          _load();
                        },
                ),
              ),
              const SizedBox(height: 20),
              if (_loading) const LinearProgressIndicator(),
              if (_error != null)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 24),
                  child: Column(
                    children: [
                      Text(_error!),
                      const SizedBox(height: 12),
                      OutlinedButton.icon(
                        onPressed: _loading ? null : _load,
                        icon: const Icon(Icons.refresh),
                        label: const Text('Retry'),
                      ),
                    ],
                  ),
                )
              else if (!_loading && _employees.isEmpty)
                const FeatureEmptyState(
                  icon: Icons.people_outline,
                  title: 'No employees found',
                  message:
                      'Confirmed memberships will appear here. Add Employee submits an invitation; the recipient must accept before receiving access.',
                  status: FeatureStatus.available,
                )
              else if (_employees.isNotEmpty)
                LayoutBuilder(
                  builder: (context, constraints) => constraints.maxWidth < 720
                      ? Column(children: _employees.map(_card).toList())
                      : SingleChildScrollView(
                          scrollDirection: Axis.horizontal,
                          child: DataTable(
                            columns: const [
                              DataColumn(label: Text('Employee')),
                              DataColumn(label: Text('Role')),
                              DataColumn(label: Text('Status')),
                              DataColumn(label: Text('Branches')),
                              DataColumn(label: Text('Actions')),
                            ],
                            rows: _employees
                                .map(
                                  (employee) => DataRow(
                                    cells: [
                                      DataCell(
                                        SizedBox(
                                          width: 180,
                                          child: Column(
                                            mainAxisAlignment:
                                                MainAxisAlignment.center,
                                            crossAxisAlignment:
                                                CrossAxisAlignment.start,
                                            children: [
                                              Text(
                                                employee.fullName,
                                                maxLines: 1,
                                                overflow: TextOverflow.ellipsis,
                                              ),
                                              Text(
                                                employee.employeeId ??
                                                    'ID not recorded',
                                                style: const TextStyle(
                                                  color: Color(0xff64748b),
                                                  fontSize: 11,
                                                ),
                                              ),
                                            ],
                                          ),
                                        ),
                                      ),
                                      DataCell(Text(employee.role.label)),
                                      DataCell(_statusPill(employee.status)),
                                      DataCell(
                                        SizedBox(
                                          width: 170,
                                          child: Text(
                                            _branchNames(employee),
                                            maxLines: 2,
                                            overflow: TextOverflow.ellipsis,
                                          ),
                                        ),
                                      ),
                                      DataCell(_actions(employee)),
                                    ],
                                  ),
                                )
                                .toList(),
                          ),
                        ),
                ),
              if (_error == null) ...[
                const SizedBox(height: 14),
                Wrap(
                  spacing: 12,
                  crossAxisAlignment: WrapCrossAlignment.center,
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
                      tooltip: 'Refresh roster',
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
      const SizedBox(height: 18),
      const SectionCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Employee PIN reset',
              style: TextStyle(fontWeight: FontWeight.w700),
            ),
            SizedBox(height: 8),
            Text(
              'PIN-based offline access and secure PIN reset are not implemented yet.',
            ),
            SizedBox(height: 12),
            StatusPill(status: FeatureStatus.comingSoon),
          ],
        ),
      ),
    ],
  );
  Widget _card(Employee employee) => Padding(
    padding: const EdgeInsets.only(bottom: 12),
    child: Card.outlined(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              employee.fullName,
              style: const TextStyle(fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 4),
            Text(
              employee.email ??
                  employee.employeeId ??
                  'Employee ID not recorded',
            ),
            const SizedBox(height: 8),
            Text(employee.role.label),
            const SizedBox(height: 8),
            Text(_branchNames(employee)),
            const SizedBox(height: 12),
            _statusPill(employee.status),
            const SizedBox(height: 8),
            _actions(employee),
          ],
        ),
      ),
    ),
  );
  Widget _actions(Employee employee) => TextButton.icon(
    onPressed: !_loading && _mayEdit(employee) ? () => _edit(employee) : null,
    icon: const Icon(Icons.manage_accounts_outlined, size: 17),
    label: const Text('Manage access'),
  );
  String _branchNames(Employee employee) => employee.allBranches
      ? 'All authorized branches'
      : employee.branchIds
            .map(
              (id) =>
                  _branches
                      .where((branch) => branch.id == id)
                      .map((branch) => branch.name)
                      .firstOrNull ??
                  'Assigned branch',
            )
            .join(', ')
            .isEmpty
      ? 'No branches assigned'
      : employee.branchIds
            .map(
              (id) =>
                  _branches
                      .where((branch) => branch.id == id)
                      .map((branch) => branch.name)
                      .firstOrNull ??
                  'Assigned branch',
            )
            .join(', ');
  Widget _statusPill(EmployeeStatus status) => StatusPill(
    label: switch (status) {
      EmployeeStatus.active => 'Active',
      EmployeeStatus.disabled => 'Disabled',
      EmployeeStatus.pending => 'Pending',
    },
    color: status == EmployeeStatus.active
        ? const Color(0xff15803d)
        : const Color(0xff64748b),
  );
}

class _InvitationDialog extends StatefulWidget {
  const _InvitationDialog({
    required this.repository,
    required this.actorRole,
    required this.branches,
  });
  final EmployeeRepository repository;
  final AppRole actorRole;
  final List<BranchOption> branches;
  @override
  State<_InvitationDialog> createState() => _InvitationDialogState();
}

class _InvitationDialogState extends State<_InvitationDialog> {
  final _form = GlobalKey<FormState>();
  final _name = TextEditingController();
  final _email = TextEditingController();
  final _employeeId = TextEditingController();
  final _phone = TextEditingController();
  final _reason = TextEditingController();
  final _requestId = const Uuid().v4();
  AppRole _role = AppRole.cashier;
  final Set<String> _branchIds = {};
  bool _allBranches = false;
  bool _saving = false;
  bool _attempted = false;
  String? _error;
  InvitationDelivery? _delivery;
  @override
  void dispose() {
    for (final controller in [_name, _email, _employeeId, _phone, _reason]) {
      controller.dispose();
    }
    super.dispose();
  }

  Future<void> _submit() async {
    if (_saving || !_form.currentState!.validate()) return;
    if (!_allBranches && _branchIds.isEmpty) {
      setState(() => _error = 'Choose at least one authorized branch.');
      return;
    }
    setState(() {
      _saving = true;
      _attempted = true;
      _error = null;
    });
    try {
      final delivery = await widget.repository.createInvitation(
        EmployeeInvitationInput(
          requestId: _requestId,
          email: _email.text.trim(),
          fullName: _name.text.trim(),
          role: _role,
          branchIds: _branchIds.toList(),
          allBranches: _allBranches,
          employeeId: _employeeId.text.trim(),
          phone: _phone.text.trim(),
          reason: _reason.text.trim(),
        ),
      );
      if (mounted) setState(() => _delivery = delivery);
    } catch (error) {
      if (mounted) {
        setState(() {
          // Local validation fails before an Edge Function request is made.
          // Permit correction while transport failures retain immutable inputs.
          if (error is RepositoryFailure &&
              error.type == RepositoryFailureType.validation) {
            _attempted = false;
          }
          _error =
              error is RepositoryFailure &&
                  (error.type == RepositoryFailureType.validation ||
                      error.type == RepositoryFailureType.permissionDenied ||
                      error.type == RepositoryFailureType.notConnected ||
                      error.type == RepositoryFailureType.unauthenticated)
              ? error.message
              : 'The invitation status could not be confirmed. Retry this same request or ask an administrator to check its status. Email delivery has not been confirmed.';
        });
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final delivery = _delivery;
    return PopScope(
      canPop: !_saving,
      child: AlertDialog(
        title: Text(
          delivery == null
              ? 'Add Employee'
              : delivery.state == InvitationDeliveryState.sent
              ? 'Invitation submitted'
              : 'Invitation pending',
        ),
        content: SizedBox(
          width: 480,
          child: SingleChildScrollView(
            child: delivery != null
                ? Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(
                        delivery.state == InvitationDeliveryState.sent
                            ? Icons.outgoing_mail
                            : Icons.pending_actions_outlined,
                        color: Theme.of(context).colorScheme.primary,
                        size: 36,
                      ),
                      const SizedBox(height: 16),
                      Text(
                        delivery.state == InvitationDeliveryState.sent
                            ? 'Invitation submitted to Supabase Auth. Email delivery has not been confirmed.'
                            : 'The invitation is pending. Delivery status needs manual review; do not send a duplicate request.',
                      ),
                      const SizedBox(height: 12),
                      const Text(
                        'The employee receives access only after signing in with the invited verified email and accepting the invitation.',
                      ),
                    ],
                  )
                : Form(
                    key: _form,
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'An invitation requests access for this business. There is no public employee sign-up.',
                        ),
                        const SizedBox(height: 18),
                        _field(
                          _name,
                          'Full name',
                          120,
                          required: true,
                          minimum: 2,
                        ),
                        _field(
                          _email,
                          'Email',
                          254,
                          required: true,
                          email: true,
                        ),
                        _field(_employeeId, 'Employee ID (optional)', 64),
                        _field(_phone, 'Phone (optional)', 40),
                        _roleSelector(
                          _role,
                          widget.actorRole,
                          enabled: !_saving && !_attempted,
                          onChanged: (role) => setState(() {
                            _role = role;
                            if (role != AppRole.admin) _allBranches = false;
                          }),
                        ),
                        const SizedBox(height: 16),
                        _branchSelector(
                          widget.branches,
                          _branchIds,
                          enabled: !_saving && !_attempted && !_allBranches,
                          onChanged: () => setState(() {}),
                        ),
                        if (widget.actorRole == AppRole.owner &&
                            _role == AppRole.admin)
                          CheckboxListTile(
                            contentPadding: EdgeInsets.zero,
                            title: const Text('All branches'),
                            value: _allBranches,
                            onChanged: _saving || _attempted
                                ? null
                                : (value) => setState(() {
                                    _allBranches = value ?? false;
                                    if (_allBranches) _branchIds.clear();
                                  }),
                          ),
                        const SizedBox(height: 16),
                        _field(
                          _reason,
                          'Reason for invitation',
                          500,
                          required: true,
                          lines: 2,
                        ),
                        if (_attempted && !_saving)
                          const Padding(
                            padding: EdgeInsets.only(top: 6),
                            child: Text(
                              'This request is retained for a safe retry. Close this form to start a different invitation.',
                            ),
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
        actions: delivery != null
            ? [
                FilledButton(
                  onPressed: () => Navigator.pop(context, true),
                  child: const Text('Done'),
                ),
              ]
            : [
                TextButton(
                  onPressed: _saving ? null : () => Navigator.pop(context),
                  child: const Text('Cancel'),
                ),
                FilledButton(
                  onPressed: _saving ? null : _submit,
                  child: Text(
                    _saving
                        ? 'Submitting…'
                        : _attempted
                        ? 'Retry same request'
                        : 'Submit invitation',
                  ),
                ),
              ],
      ),
    );
  }

  Widget _field(
    TextEditingController controller,
    String label,
    int maximum, {
    bool required = false,
    int minimum = 1,
    bool email = false,
    int lines = 1,
  }) => Padding(
    padding: const EdgeInsets.only(bottom: 14),
    child: TextFormField(
      controller: controller,
      enabled: !_saving && !_attempted,
      maxLength: maximum,
      maxLines: lines,
      keyboardType: email ? TextInputType.emailAddress : TextInputType.text,
      decoration: InputDecoration(
        labelText: label,
        border: const OutlineInputBorder(),
        counterText: '',
      ),
      validator: (value) {
        final text = value?.trim() ?? '';
        if (required && text.isEmpty) return '$label is required.';
        if (required && text.length < minimum) {
          return '$label must contain at least $minimum characters.';
        }
        if (text.length > maximum) return '$label is too long.';
        if (email && !RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]+$').hasMatch(text)) {
          return 'Enter a valid email address.';
        }
        return null;
      },
    ),
  );
}

class _EmployeeAccessDialog extends StatefulWidget {
  const _EmployeeAccessDialog({
    required this.repository,
    required this.actorRole,
    required this.employee,
    required this.branches,
  });
  final EmployeeRepository repository;
  final AppRole actorRole;
  final Employee employee;
  final List<BranchOption> branches;
  @override
  State<_EmployeeAccessDialog> createState() => _EmployeeAccessDialogState();
}

class _EmployeeAccessDialogState extends State<_EmployeeAccessDialog> {
  final _form = GlobalKey<FormState>();
  final _reason = TextEditingController();
  late AppRole _role;
  late EmployeeStatus _status;
  late bool _allBranches;
  late Set<String> _branchIds;
  bool _saving = false;
  String? _error;
  @override
  void initState() {
    super.initState();
    _role = widget.employee.role;
    _status = widget.employee.status;
    _allBranches = widget.employee.allBranches;
    _branchIds = widget.employee.branchIds.toSet();
  }

  @override
  void dispose() {
    _reason.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_saving || !_form.currentState!.validate()) return;
    if (!_allBranches && _branchIds.isEmpty) {
      setState(() => _error = 'Choose at least one authorized branch.');
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await widget.repository.updateEmployee(
        membershipId: widget.employee.membershipId,
        expectedRevision: widget.employee.revision,
        input: EmployeeAccessInput(
          role: _role,
          status: _status,
          allBranches: _allBranches,
          branchIds: _branchIds.toList(),
          reason: _reason.text.trim(),
        ),
      );
      if (mounted) Navigator.pop(context, true);
    } catch (error) {
      if (mounted) {
        setState(
          () => _error =
              error is RepositoryFailure &&
                  error.type == RepositoryFailureType.conflict
              ? 'This employee changed since you opened the form. Close it, refresh the roster and review the current access before trying again.'
              : _failure(error),
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: Text('Manage ${widget.employee.fullName}'),
    content: SizedBox(
      width: 480,
      child: SingleChildScrollView(
        child: Form(
          key: _form,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Role, status and branch changes require a reason and are verified by the server.',
              ),
              const SizedBox(height: 18),
              _roleSelector(
                _role,
                widget.actorRole,
                enabled: !_saving,
                onChanged: (role) => setState(() {
                  _role = role;
                  if (role != AppRole.admin) _allBranches = false;
                }),
              ),
              const SizedBox(height: 14),
              DropdownButtonFormField<EmployeeStatus>(
                initialValue: _status,
                isExpanded: true,
                decoration: const InputDecoration(
                  labelText: 'Status',
                  border: OutlineInputBorder(),
                ),
                items: [
                  const DropdownMenuItem(
                    value: EmployeeStatus.active,
                    child: Text('Active'),
                  ),
                  const DropdownMenuItem(
                    value: EmployeeStatus.disabled,
                    child: Text('Disabled'),
                  ),
                  if (_status == EmployeeStatus.pending)
                    const DropdownMenuItem(
                      value: EmployeeStatus.pending,
                      child: Text('Pending'),
                    ),
                ],
                onChanged: _saving
                    ? null
                    : (status) => setState(() => _status = status!),
              ),
              const SizedBox(height: 16),
              _branchSelector(
                widget.branches,
                _branchIds,
                enabled: !_saving && !_allBranches,
                onChanged: () => setState(() {}),
              ),
              if (widget.actorRole == AppRole.owner && _role == AppRole.admin)
                CheckboxListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('All branches'),
                  value: _allBranches,
                  onChanged: _saving
                      ? null
                      : (value) => setState(() {
                          _allBranches = value ?? false;
                          if (_allBranches) _branchIds.clear();
                        }),
                ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _reason,
                enabled: !_saving,
                maxLength: 500,
                maxLines: 2,
                decoration: const InputDecoration(
                  labelText: 'Reason for access change',
                  border: OutlineInputBorder(),
                ),
                validator: (value) => (value?.trim().isEmpty ?? true)
                    ? 'A reason is required.'
                    : null,
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
        child: Text(_saving ? 'Saving…' : 'Save access'),
      ),
    ],
  );
}

Widget _roleSelector(
  AppRole selected,
  AppRole actorRole, {
  required bool enabled,
  required ValueChanged<AppRole> onChanged,
}) => DropdownButtonFormField<AppRole>(
  initialValue: selected,
  isExpanded: true,
  decoration: const InputDecoration(
    labelText: 'Role',
    border: OutlineInputBorder(),
  ),
  items: [
    if (actorRole == AppRole.owner)
      const DropdownMenuItem(value: AppRole.admin, child: Text('Admin')),
    const DropdownMenuItem(value: AppRole.manager, child: Text('Manager')),
    const DropdownMenuItem(value: AppRole.cashier, child: Text('Cashier')),
    const DropdownMenuItem(
      value: AppRole.inventoryStaff,
      child: Text('Inventory Staff'),
    ),
  ],
  onChanged: enabled
      ? (role) {
          if (role != null) onChanged(role);
        }
      : null,
);

Widget _branchSelector(
  List<BranchOption> branches,
  Set<String> selected, {
  required bool enabled,
  required VoidCallback onChanged,
}) => Column(
  crossAxisAlignment: CrossAxisAlignment.start,
  children: [
    const Text(
      'Authorized branches',
      style: TextStyle(fontWeight: FontWeight.w600),
    ),
    const SizedBox(height: 8),
    if (branches.isEmpty)
      const Text(
        'No authorized active branches are available. A branch is required for staff access.',
      ),
    ...branches.map(
      (branch) => CheckboxListTile(
        contentPadding: EdgeInsets.zero,
        controlAffinity: ListTileControlAffinity.leading,
        title: Text(branch.name),
        subtitle: Text(branch.code),
        value: selected.contains(branch.id),
        onChanged: enabled
            ? (value) {
                value == true
                    ? selected.add(branch.id)
                    : selected.remove(branch.id);
                onChanged();
              }
            : null,
      ),
    ),
  ],
);

String _failure(Object error) => error is RepositoryFailure
    ? error.message
    : 'Employee records could not be loaded or changed. Check your connection and try again.';
