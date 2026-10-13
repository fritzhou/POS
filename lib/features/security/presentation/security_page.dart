import 'package:flutter/material.dart';
import 'package:uuid/uuid.dart';

import '../../../app/config/feature_status.dart';
import '../../../core/security/app_role.dart';
import '../../../core/widgets/status_widgets.dart';
import '../../catalog/domain/repository_support.dart';
import '../../catalog/presentation/catalog_ui_support.dart';
import '../../people/domain/people_repository.dart';
import '../domain/security_models.dart';
import '../domain/security_repository.dart';

enum SecurityPageSection { overview, devices, grants, notices }

class SecurityPage extends StatefulWidget {
  const SecurityPage({
    this.repository,
    this.role,
    this.peopleRepository,
    this.isPreview = true,
    this.onPolicyChanged,
    this.extraSections = const [],
    this.initialSection = SecurityPageSection.overview,
    super.key,
  });

  final SecurityRepository? repository;
  final AppRole? role;
  final PeopleRepository? peopleRepository;
  final bool isPreview;
  final ValueChanged<SecurityPolicy>? onPolicyChanged;
  final List<Widget> extraSections;
  final SecurityPageSection initialSection;

  @override
  State<SecurityPage> createState() => _SecurityPageState();
}

class _SecurityPageState extends State<SecurityPage> {
  static const _pageSize = 20;
  late SecurityPageSection _section;
  SecurityPolicy? _policy;
  String? _branch;
  Map<String, String> _branchNames = const {};
  List<SecurityMutation> _pending = const [];
  DataPage<SecurityDevice>? _devices;
  DataPage<SecurityOfflineGrant>? _grants;
  DataPage<SecurityNotice>? _notices;
  bool _busy = false;
  String? _error;
  String? _confirmation;
  int _generation = 0;
  bool get _connected => !widget.isPreview && widget.repository != null;
  bool get _manager =>
      _connected &&
      (widget.role?.allows(AppPermission.manageSecurity) ?? false);
  bool get _mayMutate => _manager && !_busy && _pending.isEmpty;

  @override
  void initState() {
    super.initState();
    _section = widget.initialSection;
    _resetScope();
    if (_connected) _load();
  }

  @override
  void didUpdateWidget(covariant SecurityPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.repository != widget.repository ||
        oldWidget.peopleRepository != widget.peopleRepository ||
        oldWidget.role != widget.role ||
        oldWidget.isPreview != widget.isPreview) {
      _generation++;
      _busy = false;
      _section = widget.initialSection;
      _resetScope();
      if (_connected) _load();
    }
  }

  void _resetScope() {
    final branches = widget.repository?.branchIds.toList() ?? [];
    branches.sort();
    _branch = branches.firstOrNull;
    _branchNames = const {};
    _policy = null;
    _devices = null;
    _grants = null;
    _notices = null;
    _pending = const [];
    _error = null;
    _confirmation = null;
  }

  Future<void> _load({int offset = 0}) async {
    if (!_connected || _busy) return;
    final generation = ++_generation;
    final repository = widget.repository!;
    final branch = _branch;
    setState(() {
      _busy = true;
      _error = null;
      _policy = null;
      _devices = null;
      _grants = null;
      _notices = null;
    });
    try {
      // Policy and the saved request inventory must succeed before presenting
      // management controls. Current PostgreSQL authority is checked again.
      final policy = await repository.loadPolicy();
      final pending = await repository.pendingMutations();
      if (!mounted || generation != _generation) return;
      if (branch == null) {
        throw const RepositoryFailure(
          RepositoryFailureType.permissionDenied,
          'This account has no authorized branch.',
        );
      }
      final page = PageRequest(offset: offset, limit: _pageSize);
      DataPage<SecurityDevice>? devices;
      DataPage<SecurityOfflineGrant>? grants;
      DataPage<SecurityNotice>? notices;
      switch (_section) {
        case SecurityPageSection.overview:
          break;
        case SecurityPageSection.devices:
          devices = await repository.listDevices(branchId: branch, page: page);
        case SecurityPageSection.grants:
          grants = await repository.listGrants(branchId: branch, page: page);
        case SecurityPageSection.notices:
          notices = await repository.listNotices(branchId: branch, page: page);
      }
      if (!mounted || generation != _generation) return;
      setState(() {
        _policy = policy;
        _pending = pending;
        _devices = devices;
        _grants = grants;
        _notices = notices;
      });
      if (_branchNames.isEmpty && widget.peopleRepository != null) {
        try {
          final branches = await widget.peopleRepository!.listBranches();
          if (!mounted || generation != _generation) return;
          setState(() {
            _branchNames = {
              for (final option in branches)
                if (repository.branchIds.contains(option.id))
                  option.id: option.name,
            };
          });
        } on Object {
          // Authoritative branch IDs remain usable if display labels fail.
        }
      }
    } on Object catch (error) {
      if (!mounted || generation != _generation) return;
      setState(() {
        _error = _publicError(error);
        if (error is RepositoryFailure &&
            (error.type == RepositoryFailureType.unauthenticated ||
                error.type == RepositoryFailureType.permissionDenied)) {
          _pending = const [];
          _confirmation = null;
        }
      });
    } finally {
      if (mounted && generation == _generation) setState(() => _busy = false);
    }
  }

  Future<void> _mutate(SecurityMutation mutation) async {
    if (!_manager || _busy) return;
    final generation = ++_generation;
    setState(() {
      _busy = true;
      _error = null;
      _confirmation = null;
      _pending = [mutation];
    });
    try {
      final result = await widget.repository!.mutate(mutation);
      if (!mounted || generation != _generation) return;
      setState(() {
        _pending = const [];
        _confirmation = switch (result.kind) {
          SecurityMutationKind.policy => 'Security policy saved by the server.',
          SecurityMutationKind.renameDevice =>
            'Device name saved by the server.',
          SecurityMutationKind.revokeDevice =>
            'Device revocation confirmed by the server.',
          SecurityMutationKind.reviewGrant =>
            'Administrative grant resolution recorded. Unknown paid events remain a reconciliation risk.',
        };
      });
      if (result.policy != null) widget.onPolicyChanged?.call(result.policy!);
    } on Object catch (error) {
      if (!mounted || generation != _generation) return;
      setState(() {
        _error = _publicError(error);
        if (error is RepositoryFailure &&
            error.type != RepositoryFailureType.unavailable) {
          _pending = const [];
          if (error.type == RepositoryFailureType.unauthenticated ||
              error.type == RepositoryFailureType.permissionDenied) {
            _policy = null;
            _devices = null;
            _grants = null;
            _notices = null;
          }
        }
      });
      return;
    } finally {
      if (mounted && generation == _generation) setState(() => _busy = false);
    }
    if (mounted && generation == _generation) await _load();
  }

  String _publicError(Object error) => error is RepositoryFailure
      ? error.message
      : 'Security records could not be confirmed. Preserve the request and reload or retry it.';

  Future<void> _editDevice(
    SecurityDevice device, {
    required bool revoke,
  }) async {
    if (!_mayMutate || !device.canManage) return;
    final generation = _generation;
    final repository = widget.repository;
    final mutation = await showDialog<SecurityMutation>(
      context: context,
      builder: (context) => _SecurityMutationDialog(
        device: device,
        kind: revoke
            ? SecurityMutationKind.revokeDevice
            : SecurityMutationKind.renameDevice,
      ),
    );
    if (mutation != null &&
        mounted &&
        generation == _generation &&
        repository == widget.repository) {
      await _mutate(mutation);
    }
  }

  Future<void> _reviewGrant(SecurityOfflineGrant grant) async {
    if (!_mayMutate || !grant.canReview) return;
    final generation = _generation;
    final repository = widget.repository;
    final mutation = await showDialog<SecurityMutation>(
      context: context,
      builder: (context) => _SecurityMutationDialog(
        kind: SecurityMutationKind.reviewGrant,
        grant: grant,
      ),
    );
    if (mutation != null &&
        mounted &&
        generation == _generation &&
        repository == widget.repository) {
      await _mutate(mutation);
    }
  }

  Future<void> _editPolicy() async {
    if (!_mayMutate || _policy == null) return;
    final policy = _policy!;
    final generation = _generation;
    final repository = widget.repository;
    final mutation = await showDialog<SecurityMutation>(
      context: context,
      builder: (context) => _SecurityMutationDialog(
        kind: SecurityMutationKind.policy,
        policy: policy,
      ),
    );
    if (mutation != null &&
        mounted &&
        generation == _generation &&
        repository == widget.repository) {
      await _mutate(mutation);
    }
  }

  Future<void> _readNotice(SecurityNotice notice) async {
    if (!_connected || _busy || notice.readAt != null || _branch == null) {
      return;
    }
    final generation = ++_generation;
    setState(() => _busy = true);
    try {
      await widget.repository!.markNoticeRead(
        branchId: _branch!,
        noticeId: notice.id,
      );
      if (!mounted || generation != _generation) return;
    } on Object catch (error) {
      if (mounted && generation == _generation) {
        setState(() {
          _error = _publicError(error);
          if (error is RepositoryFailure &&
              (error.type == RepositoryFailureType.unauthenticated ||
                  error.type == RepositoryFailureType.permissionDenied)) {
            _policy = null;
            _devices = null;
            _grants = null;
            _notices = null;
            _confirmation = null;
          }
        });
      }
      return;
    } finally {
      if (mounted && generation == _generation) setState(() => _busy = false);
    }
    if (mounted && generation == _generation) {
      await _load(offset: _notices?.offset ?? 0);
    }
  }

  @override
  Widget build(BuildContext context) => ListView(
    padding: const EdgeInsets.all(24),
    children: [
      PageHeading(
        title: 'Security and devices',
        subtitle:
            'Review server security policy, enrolled offline devices and recorded security notices.',
        trailing: _connected
            ? IconButton(
                key: const Key('security-reload'),
                tooltip: 'Reload security records',
                onPressed: _busy ? null : () => _load(),
                icon: const Icon(Icons.refresh),
              )
            : const StatusPill(status: FeatureStatus.notYetConnected),
      ),
      const SizedBox(height: 20),
      if (!_connected)
        const FeatureEmptyState(
          icon: Icons.security_outlined,
          title: 'Security management requires a verified account',
          message:
              'Connect the backend and sign in to load your actual device inventory, policy and security notices.',
          status: FeatureStatus.notYetConnected,
        )
      else ...[
        if (widget.repository!.branchIds.isNotEmpty) ...[
          DropdownButtonFormField<String>(
            key: ValueKey('security-branch-$_branch'),
            initialValue: _branch,
            isExpanded: true,
            decoration: const InputDecoration(labelText: 'Authorized branch'),
            items: [
              for (final id in (widget.repository!.branchIds.toList()..sort()))
                DropdownMenuItem(
                  value: id,
                  child: Text(
                    _branchNames[id] ?? 'Branch ${id.substring(0, 8)}',
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
            ],
            onChanged: _busy
                ? null
                : (value) {
                    setState(() {
                      _branch = value;
                      _confirmation = null;
                    });
                    _load();
                  },
          ),
          const SizedBox(height: 16),
        ],
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final section in SecurityPageSection.values)
              ChoiceChip(
                key: Key('security-section-${section.name}'),
                label: Text(_sectionLabel(section)),
                selected: _section == section,
                onSelected: _busy
                    ? null
                    : (_) {
                        setState(() => _section = section);
                        _load();
                      },
              ),
          ],
        ),
        const SizedBox(height: 20),
        if (_busy) const LinearProgressIndicator(),
        if (_error != null) ...[
          CatalogErrorNotice(
            key: const Key('security-error'),
            message: _error!,
            onRetry: _busy ? null : () => _load(),
          ),
          const SizedBox(height: 16),
        ],
        if (_confirmation != null) ...[
          Semantics(liveRegion: true, child: Text(_confirmation!)),
          const SizedBox(height: 16),
        ],
        if (_pending.isNotEmpty) ...[
          SectionCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Unconfirmed security requests',
                  style: TextStyle(fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 8),
                const Text(
                  'Retry the original request to learn its server outcome. Its ID and details are retained; new management changes are paused.',
                ),
                for (final mutation in _pending) ...[
                  const SizedBox(height: 12),
                  Text(
                    '${_mutationLabel(mutation.kind)} · ${mutation.requestId}',
                  ),
                  Text(mutation.reason),
                  TextButton.icon(
                    key: Key('security-retry-${mutation.requestId}'),
                    onPressed: _manager && !_busy
                        ? () => _mutate(mutation)
                        : null,
                    icon: const Icon(Icons.refresh),
                    label: const Text('Retry original request'),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(height: 20),
        ],
        if (_policy != null && _section == SecurityPageSection.overview) ...[
          _policyCard(),
          const SizedBox(height: 20),
          ...widget.extraSections.expand(
            (section) => [section, const SizedBox(height: 20)],
          ),
        ],
        if (_devices != null && _section == SecurityPageSection.devices)
          ..._deviceCards(),
        if (_grants != null && _section == SecurityPageSection.grants)
          ..._grantCards(),
        if (_notices != null && _section == SecurityPageSection.notices)
          ..._noticeCards(),
      ],
    ],
  );

  Widget _policyCard() => SectionCard(
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Organization policy',
          style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: 12),
        Text('Idle lock: ${_policy!.idleLockMinutes} minutes'),
        const SizedBox(height: 8),
        Text(
          _policy!.requirePrivilegedMfa
              ? 'Privileged MFA policy: required'
              : 'Privileged MFA policy: optional',
        ),
        const SizedBox(height: 8),
        const Text(
          'Owner and admin actions are subject to the current server MFA policy. Idle lock requires fresh account verification to reopen the workspace.',
        ),
        const SizedBox(height: 8),
        Text('Saved revision ${_policy!.revision}'),
        if (_manager) ...[
          const SizedBox(height: 12),
          OutlinedButton.icon(
            key: const Key('security-edit-policy'),
            onPressed: _mayMutate ? _editPolicy : null,
            icon: const Icon(Icons.edit_outlined),
            label: const Text('Edit security policy'),
          ),
        ],
      ],
    ),
  );

  Iterable<Widget> _deviceCards() sync* {
    final page = _devices!;
    if (page.items.isEmpty) {
      yield const _SecurityEmpty(
        icon: Icons.devices_outlined,
        title: 'No enrolled offline devices',
        message:
            'Only devices enrolled with a verified public key appear here. This inventory does not represent all Auth sessions.',
      );
    }
    for (final device in page.items) {
      yield SectionCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              device.name,
              style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 6),
            Text(
              '${device.platform.name.toUpperCase()} · ${device.revoked ? 'Revoked' : 'Enrolled'}',
            ),
            Text('Device ${device.deviceId}'),
            Text('Account ${device.actorId}'),
            Text('Enrolled ${_time(device.enrolledAt)}'),
            Text(
              device.lastSyncAt == null
                  ? 'No recorded synchronization'
                  : 'Last recorded payment upload ${_time(device.lastSyncAt!)}',
            ),
            if (device.revokedAt != null)
              Text('Revoked ${_time(device.revokedAt!)}'),
            if (device.revocationReason != null)
              Text('Reason: ${device.revocationReason}'),
            if (_manager && device.canManage) ...[
              const SizedBox(height: 12),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  OutlinedButton(
                    onPressed: _mayMutate && !device.revoked
                        ? () => _editDevice(device, revoke: false)
                        : null,
                    child: const Text('Rename device'),
                  ),
                  OutlinedButton(
                    onPressed: _mayMutate && !device.revoked
                        ? () => _editDevice(device, revoke: true)
                        : null,
                    child: const Text('Revoke device'),
                  ),
                ],
              ),
            ],
          ],
        ),
      );
      yield const SizedBox(height: 12);
    }
    yield _pager(page.offset, page.items.length, page.hasMore);
  }

  Iterable<Widget> _grantCards() sync* {
    final page = _grants!;
    if (page.items.isEmpty) {
      yield const _SecurityEmpty(
        icon: Icons.offline_bolt_outlined,
        title: 'No offline grants',
        message:
            'Prepare an authorized device and an online opened shift to receive a bounded offline grant.',
      );
    }
    for (final grant in page.items) {
      yield SectionCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              _grantLabel(grant.state),
              style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 6),
            Text('Grant ${grant.grantId}'),
            Text('Device ${grant.deviceId}'),
            Text('Shift ${grant.shiftId}'),
            Text('Issued ${_time(grant.issuedAt)}'),
            Text('Expires ${_time(grant.expiresAt)}'),
            const SizedBox(height: 10),
            Text(
              '${grant.outcomeCount} recorded outcomes · ${grant.reviewCount} reconciliation cases',
            ),
            Text(
              'Highest recorded sequence ${grant.lastSequence} · Recorded total ${grant.currency} ${Money.formatMinor(grant.totalMinor)}',
            ),
            Text(
              'Remaining exposure: up to ${grant.remainingExposureEvents} events and ${grant.currency} ${Money.formatMinor(grant.remainingExposureMinor)}',
            ),
            Text(
              grant.blocksShiftClose
                  ? 'Blocks normal shift closure'
                  : 'Normal shift closure barrier resolved',
            ),
            if (grant.reviewedAt != null) ...[
              const SizedBox(height: 10),
              const Text(
                'Administrative resolution permits shift closure; it does not prove all paid events were recovered. Preserve device exports and reconcile any later signed payment proof.',
              ),
            ],
            if (_manager && grant.canReview) ...[
              const SizedBox(height: 12),
              OutlinedButton.icon(
                key: Key('security-review-${grant.grantId}'),
                onPressed: _mayMutate ? () => _reviewGrant(grant) : null,
                icon: const Icon(Icons.assignment_late_outlined),
                label: const Text('Review lost-key grant'),
              ),
            ],
          ],
        ),
      );
      yield const SizedBox(height: 12);
    }
    yield _pager(page.offset, page.items.length, page.hasMore);
  }

  Iterable<Widget> _noticeCards() sync* {
    final page = _notices!;
    if (page.items.isEmpty) {
      yield const _SecurityEmpty(
        icon: Icons.notifications_none,
        title: 'No security notices',
        message:
            'Persisted server security events appear here. Email delivery and all-session login tracking are separate services.',
      );
    }
    for (final notice in page.items) {
      yield SectionCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              notice.title,
              style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 8),
            Text(notice.message),
            const SizedBox(height: 8),
            Text(
              '${_time(notice.occurredAt)} · ${notice.readAt == null ? 'Unread' : 'Read'}',
            ),
            Text(notice.action, style: Theme.of(context).textTheme.bodySmall),
            if (notice.readAt == null)
              TextButton(
                key: Key('security-read-${notice.id}'),
                onPressed: _busy ? null : () => _readNotice(notice),
                child: const Text('Mark read'),
              ),
          ],
        ),
      );
      yield const SizedBox(height: 12);
    }
    yield _pager(page.offset, page.items.length, page.hasMore);
  }

  Widget _pager(int offset, int count, bool hasMore) => Wrap(
    spacing: 16,
    runSpacing: 8,
    crossAxisAlignment: WrapCrossAlignment.center,
    children: [
      OutlinedButton(
        key: const Key('security-previous'),
        onPressed: !_busy && offset > 0
            ? () => _load(offset: (offset - _pageSize).clamp(0, 100000))
            : null,
        child: const Text('Previous'),
      ),
      Text('Page ${offset ~/ _pageSize + 1}'),
      OutlinedButton(
        key: const Key('security-next'),
        onPressed: !_busy && hasMore
            ? () => _load(offset: offset + count)
            : null,
        child: const Text('Next'),
      ),
    ],
  );
}

class _SecurityEmpty extends StatelessWidget {
  const _SecurityEmpty({
    required this.icon,
    required this.title,
    required this.message,
  });
  final IconData icon;
  final String title;
  final String message;
  @override
  Widget build(BuildContext context) => SectionCard(
    child: Padding(
      padding: const EdgeInsets.symmetric(vertical: 20),
      child: Column(
        children: [
          Icon(icon, size: 40),
          const SizedBox(height: 12),
          Text(title, style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 8),
          Text(message, textAlign: TextAlign.center),
        ],
      ),
    ),
  );
}

class _SecurityMutationDialog extends StatefulWidget {
  const _SecurityMutationDialog({
    required this.kind,
    this.device,
    this.grant,
    this.policy,
  });
  final SecurityMutationKind kind;
  final SecurityDevice? device;
  final SecurityOfflineGrant? grant;
  final SecurityPolicy? policy;
  @override
  State<_SecurityMutationDialog> createState() =>
      _SecurityMutationDialogState();
}

class _SecurityMutationDialogState extends State<_SecurityMutationDialog> {
  final _form = GlobalKey<FormState>();
  final _reason = TextEditingController();
  late final TextEditingController _value;
  late bool _requireMfa;
  bool _acknowledge = false;
  @override
  void initState() {
    super.initState();
    _value = TextEditingController(
      text: widget.kind == SecurityMutationKind.policy
          ? '${widget.policy!.idleLockMinutes}'
          : widget.device?.name ?? '',
    );
    _requireMfa = widget.policy?.requirePrivilegedMfa ?? false;
  }

  @override
  void dispose() {
    _reason.dispose();
    _value.dispose();
    super.dispose();
  }

  void _submit() {
    if (!_form.currentState!.validate()) return;
    if (widget.kind == SecurityMutationKind.reviewGrant && !_acknowledge) {
      return;
    }
    final id = const Uuid().v4();
    final reason = _reason.text.trim();
    final mutation = switch (widget.kind) {
      SecurityMutationKind.policy => SecurityMutation.policy(
        requestId: id,
        expectedRevision: widget.policy!.revision,
        idleLockMinutes: int.parse(_value.text.trim()),
        requirePrivilegedMfa: _requireMfa,
        reason: reason,
      ),
      SecurityMutationKind.renameDevice => SecurityMutation.renameDevice(
        requestId: id,
        branchId: widget.device!.branchId,
        deviceId: widget.device!.deviceId,
        deviceName: _value.text.trim(),
        reason: reason,
      ),
      SecurityMutationKind.revokeDevice => SecurityMutation.revokeDevice(
        requestId: id,
        branchId: widget.device!.branchId,
        deviceId: widget.device!.deviceId,
        reason: reason,
      ),
      SecurityMutationKind.reviewGrant => SecurityMutation.reviewGrant(
        requestId: id,
        branchId: widget.grant!.branchId,
        grantId: widget.grant!.grantId,
        reason: reason,
        acknowledgeUnknownPaidEvents: true,
        expectedLastSequence: widget.grant!.lastSequence,
        expectedOutcomeCount: widget.grant!.outcomeCount,
        expectedTotalMinor: widget.grant!.totalMinor,
      ),
    };
    Navigator.of(context).pop(mutation);
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: Text(_mutationLabel(widget.kind)),
    content: SizedBox(
      width: 520,
      child: SingleChildScrollView(
        child: Form(
          key: _form,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              if (widget.kind == SecurityMutationKind.revokeDevice) ...[
                Text('Revoke ${widget.device!.name}?'),
                const SizedBox(height: 10),
                const Text(
                  'This permanently prevents new server-authorized offline use. An already disconnected device can continue until its signed grant expires. Original paid proofs must be preserved for reconciliation. This action does not revoke every Auth session.',
                ),
              ],
              if (widget.kind == SecurityMutationKind.reviewGrant) ...[
                const Text(
                  'Resolve an expired grant after its device was revoked and its signing key was lost. This is an audited exception that permits shift closure without a signed final device sequence.',
                ),
                const SizedBox(height: 10),
                Text(
                  'Known server outcomes: ${widget.grant!.outcomeCount}; last sequence: ${widget.grant!.lastSequence}; total: ${widget.grant!.currency} ${Money.formatMinor(widget.grant!.totalMinor)}.',
                ),
                Text(
                  'Unobserved exposure remains up to ${widget.grant!.remainingExposureEvents} events and ${widget.grant!.currency} ${Money.formatMinor(widget.grant!.remainingExposureMinor)}.',
                ),
                const SizedBox(height: 10),
                const Text(
                  'Unknown sales may already have been paid. Recover and preserve local receipts, payment records and signed exports before proceeding. Later payment proof remains subject to reconciliation.',
                ),
                CheckboxListTile(
                  key: const Key('security-acknowledge-risk'),
                  contentPadding: EdgeInsets.zero,
                  value: _acknowledge,
                  onChanged: (value) =>
                      setState(() => _acknowledge = value ?? false),
                  title: const Text(
                    'I acknowledge unknown paid events may remain and this resolution cannot recover or erase them.',
                  ),
                  controlAffinity: ListTileControlAffinity.leading,
                ),
              ],
              if (widget.kind == SecurityMutationKind.renameDevice ||
                  widget.kind == SecurityMutationKind.policy) ...[
                TextFormField(
                  key: const Key('security-mutation-value'),
                  controller: _value,
                  keyboardType: widget.kind == SecurityMutationKind.policy
                      ? TextInputType.number
                      : TextInputType.text,
                  decoration: InputDecoration(
                    labelText: widget.kind == SecurityMutationKind.policy
                        ? 'Idle lock minutes'
                        : 'Device name',
                  ),
                  validator: (value) {
                    if (widget.kind == SecurityMutationKind.policy) {
                      final minutes = int.tryParse(value?.trim() ?? '');
                      return minutes == null || minutes < 1 || minutes > 60
                          ? 'Enter 1 to 60 minutes.'
                          : null;
                    }
                    return validateCatalogField(
                      () => requiredText(value ?? '', 'Device name', 120),
                    );
                  },
                ),
                const SizedBox(height: 14),
              ],
              if (widget.kind == SecurityMutationKind.policy) ...[
                SwitchListTile.adaptive(
                  key: const Key('security-require-mfa'),
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Require MFA for privileged accounts'),
                  subtitle: const Text(
                    'Owner and admin accounts must verify an Auth MFA factor for protected work. Enabling requires your own verified second factor.',
                  ),
                  value: _requireMfa,
                  onChanged: (value) => setState(() => _requireMfa = value),
                ),
                const SizedBox(height: 12),
              ],
              TextFormField(
                key: const Key('security-mutation-reason'),
                controller: _reason,
                maxLines: 3,
                maxLength: 1000,
                decoration: const InputDecoration(
                  labelText: 'Reason for the audit record',
                ),
                validator: (value) => validateCatalogField(
                  () => requiredText(value ?? '', 'Reason', 1000, minimum: 3),
                ),
              ),
            ],
          ),
        ),
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.of(context).pop(),
        child: const Text('Cancel'),
      ),
      FilledButton(
        key: const Key('security-confirm-mutation'),
        onPressed:
            widget.kind == SecurityMutationKind.reviewGrant && !_acknowledge
            ? null
            : _submit,
        child: Text(
          widget.kind == SecurityMutationKind.reviewGrant
              ? 'Record resolution'
              : 'Confirm',
        ),
      ),
    ],
  );
}

String _sectionLabel(SecurityPageSection section) => switch (section) {
  SecurityPageSection.overview => 'Policy and account',
  SecurityPageSection.devices => 'Offline devices',
  SecurityPageSection.grants => 'Offline grants',
  SecurityPageSection.notices => 'Security notices',
};
String _mutationLabel(SecurityMutationKind kind) => switch (kind) {
  SecurityMutationKind.policy => 'Edit security policy',
  SecurityMutationKind.renameDevice => 'Rename device',
  SecurityMutationKind.revokeDevice => 'Revoke device',
  SecurityMutationKind.reviewGrant => 'Review lost-key grant',
};
String _grantLabel(SecurityGrantState state) => switch (state) {
  SecurityGrantState.unsigned => 'Unsigned preparation',
  SecurityGrantState.active => 'Active signed grant',
  SecurityGrantState.expired => 'Expired grant awaiting resolution',
  SecurityGrantState.released => 'Released by device',
  SecurityGrantState.administrativelyResolved => 'Administratively resolved',
};
String _time(DateTime value) => '${value.toUtc().toIso8601String()} UTC';
