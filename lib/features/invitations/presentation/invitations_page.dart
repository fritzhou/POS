import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:uuid/uuid.dart';

import '../../../core/operations/operation_journal.dart';
import '../../../core/security/app_role.dart';
import '../../../core/widgets/status_widgets.dart';
import '../../administration/domain/administration_models.dart';
import '../../catalog/domain/repository_support.dart';
import '../domain/invitation_models.dart';
import '../domain/invitation_repository.dart';

class InvitationsPage extends StatefulWidget {
  const InvitationsPage({
    super.key,
    this.repository,
    this.role,
    this.isPreview = true,
  });
  final InvitationAdministrationRepository? repository;
  final AppRole? role;
  final bool isPreview;
  @override
  State<InvitationsPage> createState() => _InvitationsPageState();
}

class _ContextLease extends ChangeNotifier {
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

enum _DetailAction { revoke, retryDelivery }

class _InvitationsPageState extends State<InvitationsPage> {
  final _search = TextEditingController();
  ManagedInvitationStatus? _status;
  String? _appliedSearch, _error, _notice;
  List<ManagedInvitation> _records = [];
  List<PendingOperation> _pending = [];
  bool _busy = false, _hasMore = false;
  int _offset = 0, _epoch = 0;
  _ContextLease? _lease;
  bool get _connected =>
      !widget.isPreview &&
      widget.repository != null &&
      [AppRole.owner, AppRole.admin].contains(widget.role);
  bool get _mutationsBlocked => _busy || _pending.isNotEmpty;

  @override
  void initState() {
    super.initState();
    if (_connected) _load();
  }

  @override
  void didUpdateWidget(InvitationsPage old) {
    super.didUpdateWidget(old);
    if (old.repository != widget.repository ||
        old.role != widget.role ||
        old.isPreview != widget.isPreview) {
      _epoch++;
      _lease?.invalidate();
      _records = [];
      _pending = [];
      _error = null;
      _notice = null;
      _busy = false;
      _hasMore = false;
      _offset = 0;
      _search.clear();
      _appliedSearch = null;
      _status = null;
      if (_connected) _load();
    }
  }

  @override
  void dispose() {
    _epoch++;
    _lease?.invalidate();
    _search.dispose();
    super.dispose();
  }

  bool _current(int epoch, InvitationAdministrationRepository repository) =>
      mounted &&
      epoch == _epoch &&
      identical(repository, widget.repository) &&
      _connected;

  Future<void> _load() async {
    if (!_connected) return;
    final epoch = ++_epoch, repository = widget.repository!;
    setState(() {
      _busy = true;
      _error = null;
      _records = [];
    });
    try {
      final pending = await repository.pending();
      if (!_current(epoch, repository)) return;
      setState(() => _pending = pending);
      final result = await repository.listInvitations(
        filter: InvitationFilter(search: _appliedSearch, status: _status),
        page: PageRequest(offset: _offset, limit: 20),
      );
      if (!_current(epoch, repository)) return;
      setState(() {
        _pending = pending;
        _records = result.items;
        _hasMore = result.hasMore;
      });
    } catch (error) {
      if (_current(epoch, repository)) {
        setState(() {
          _error = _failure(error);
          _records = [];
          _hasMore = false;
        });
      }
    } finally {
      if (_current(epoch, repository)) setState(() => _busy = false);
    }
  }

  Future<T?> _dialog<T>(Widget Function(_ContextLease lease) builder) async {
    final lease = _ContextLease();
    _lease = lease;
    try {
      return await showDialog<T>(
        context: context,
        barrierDismissible: false,
        builder: (dialogContext) => ListenableBuilder(
          listenable: lease,
          builder: (_, _) => lease.active
              ? builder(lease)
              : AlertDialog(
                  title: const Text('Business context changed'),
                  content: const Text(
                    'Private invitation details are hidden. Saved requests remain with the original account.',
                  ),
                  actions: [
                    TextButton(
                      onPressed: () => Navigator.pop(dialogContext),
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

  Future<void> _view(ManagedInvitation summary) async {
    if (!_connected || _busy) return;
    final epoch = _epoch, repository = widget.repository!;
    setState(() {
      _busy = true;
      _error = null;
    });
    ManagedInvitation detail;
    try {
      detail = await repository.invitation(summary.id);
    } catch (error) {
      if (_current(epoch, repository)) {
        setState(() {
          _busy = false;
          _error = _failure(error);
        });
      }
      return;
    }
    if (!_current(epoch, repository)) return;
    setState(() => _busy = false);
    final action = await _dialog<_DetailAction>(
      (lease) => _InvitationDetail(
        invitation: detail,
        blocked: _mutationsBlocked,
        lease: lease,
      ),
    );
    if (!_current(epoch, repository) || action == null || _mutationsBlocked) {
      return;
    }
    if (action == _DetailAction.revoke) {
      final reason = await _dialog<String>(
        (lease) => _RevocationDialog(invitation: detail, lease: lease),
      );
      if (!_current(epoch, repository) || reason == null || _mutationsBlocked) {
        return;
      }
      final request = const Uuid().v4();
      await _execute(
        repository,
        () => repository.revoke(
          original: detail,
          reason: reason,
          requestId: request,
        ),
        'Invitation revoked. Acceptance is blocked; an email already requested may still arrive.',
      );
    } else {
      final confirmed = await _dialog<bool>(
        (lease) => AlertDialog(
          title: const Text('Retry original email request?'),
          content: const SingleChildScrollView(
            child: Text(
              'Use the same invitation, original request ID and original details. This does not create a replacement invitation. Email delivery and acceptance remain unconfirmed.',
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Back'),
            ),
            FilledButton(
              onPressed: lease.active
                  ? () => Navigator.pop(context, true)
                  : null,
              child: const Text('Retry original request'),
            ),
          ],
        ),
      );
      if (!_current(epoch, repository) ||
          confirmed != true ||
          _mutationsBlocked) {
        return;
      }
      await _retryDelivery(repository, detail);
    }
  }

  Future<bool> _execute(
    InvitationAdministrationRepository repository,
    Future<Object> Function() action,
    String success,
  ) async {
    final epoch = _epoch;
    if (!_current(epoch, repository) || _busy) return false;
    setState(() {
      _busy = true;
      _error = null;
      _notice = null;
    });
    String? failure;
    try {
      await action();
    } catch (error) {
      failure = _failure(error);
    }
    if (!_current(epoch, repository)) return false;
    await _load();
    if (_current(epoch + 1, repository)) {
      setState(() {
        if (failure != null) {
          _error = failure;
        } else {
          _notice = success;
        }
      });
      return true;
    }
    return false;
  }

  Future<void> _retryDelivery(
    InvitationAdministrationRepository repository,
    ManagedInvitation detail,
  ) async {
    InvitationDelivery? delivery;
    final active = await _execute(
      repository,
      () async {
        delivery = await repository.retryDelivery(detail);
        return delivery!;
      },
      'Original email request submitted. Reloaded state shows the latest recorded outcome.',
    );
    if (!active ||
        !mounted ||
        !identical(repository, widget.repository) ||
        delivery == null) {
      return;
    }
    setState(
      () => _notice = delivery!.state == InvitationDeliveryState.sent
          ? 'Email request accepted by the authentication service. Inbox delivery and employee acceptance are unconfirmed.'
          : 'Email request in progress or outcome unknown. No replacement invitation was created.',
    );
  }

  void _apply() {
    if (_busy) return;
    try {
      _appliedSearch = InvitationFilter(search: _search.text).validatedSearch();
    } catch (error) {
      setState(() => _error = _failure(error));
      return;
    }
    _offset = 0;
    _load();
  }

  @override
  Widget build(BuildContext context) => ListView(
    padding: const EdgeInsets.all(20),
    children: [
      const PageHeading(
        title: 'Employee invitations',
        subtitle:
            'Review recorded invitations, email request states and employee acceptance.',
      ),
      const SizedBox(height: 16),
      if (!_connected)
        const SectionCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'No connected invitations',
                style: TextStyle(fontWeight: FontWeight.w700),
              ),
              SizedBox(height: 8),
              Text(
                'Sign in with an active Owner or Admin membership to view real invitations. This preview contains no employee records and cannot send or revoke invitations.',
              ),
            ],
          ),
        )
      else ...[
        const SectionCard(
          child: Text(
            'An email request marked accepted does not confirm inbox delivery, a read receipt or employee acceptance. Revocation blocks invitation acceptance but cannot recall an email already requested.',
          ),
        ),
        const SizedBox(height: 16),
        SectionCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              TextField(
                key: const Key('invitation-search'),
                controller: _search,
                enabled: !_busy,
                maxLength: 254,
                decoration: const InputDecoration(
                  labelText: 'Search email or name',
                  border: OutlineInputBorder(),
                ),
                onSubmitted: (_) => _apply(),
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<ManagedInvitationStatus?>(
                key: ValueKey(_status),
                isExpanded: true,
                initialValue: _status,
                decoration: const InputDecoration(
                  labelText: 'Invitation status',
                  border: OutlineInputBorder(),
                ),
                items: [
                  const DropdownMenuItem(
                    value: null,
                    child: Text('All invitations'),
                  ),
                  ...ManagedInvitationStatus.values.map(
                    (s) => DropdownMenuItem(
                      value: s,
                      child: Text(_statusLabel(s)),
                    ),
                  ),
                ],
                onChanged: _busy
                    ? null
                    : (status) {
                        setState(() => _status = status);
                        _offset = 0;
                        _load();
                      },
              ),
              const SizedBox(height: 12),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  FilledButton.icon(
                    onPressed: _busy ? null : _apply,
                    icon: const Icon(Icons.search),
                    label: const Text('Search'),
                  ),
                  OutlinedButton.icon(
                    onPressed: _busy ? null : _load,
                    icon: const Icon(Icons.refresh),
                    label: const Text('Reload'),
                  ),
                ],
              ),
            ],
          ),
        ),
        if (_pending.isNotEmpty) ...[
          const SizedBox(height: 16),
          const Text(
            'Saved revocations awaiting confirmation',
            style: TextStyle(fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 8),
          const Text(
            'Preserve each original request. A later permission denial does not establish whether an earlier request committed.',
          ),
          for (final operation in _pending)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: SectionCard(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    SelectableText('Request ${operation.requestId}'),
                    Text('Attempts recorded: ${operation.attemptCount}'),
                    const SizedBox(height: 8),
                    OutlinedButton(
                      onPressed: _busy
                          ? null
                          : () => _execute(
                              widget.repository!,
                              () => widget.repository!.retry(operation),
                              'Original revocation confirmed.',
                            ),
                      child: const Text('Retry original revocation'),
                    ),
                  ],
                ),
              ),
            ),
        ],
        if (_busy)
          const Padding(
            padding: EdgeInsets.all(20),
            child: Center(child: CircularProgressIndicator()),
          ),
        if (_error != null)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 12),
            child: Text(
              _error!,
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
          ),
        if (_notice != null)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 12),
            child: Text(_notice!),
          ),
        if (!_busy && _records.isEmpty && _error == null)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 20),
            child: Text('No invitations match these filters.'),
          ),
        for (final record in _records)
          Padding(
            padding: const EdgeInsets.only(top: 12),
            child: SectionCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    record.fullName,
                    style: const TextStyle(fontWeight: FontWeight.w700),
                  ),
                  SelectableText(record.email),
                  const SizedBox(height: 8),
                  Text('${_statusLabel(record.status)} · ${record.role.label}'),
                  Text(_deliveryLabel(record.delivery)),
                  Text('Expires ${_time(record.expiresAt)}'),
                  const SizedBox(height: 8),
                  OutlinedButton(
                    onPressed: _busy ? null : () => _view(record),
                    child: const Text('View invitation'),
                  ),
                ],
              ),
            ),
          ),
        const SizedBox(height: 16),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            TextButton(
              onPressed: !_busy && _offset > 0
                  ? () {
                      _offset = (_offset - 20).clamp(0, 100000);
                      _load();
                    }
                  : null,
              child: const Text('Previous'),
            ),
            TextButton(
              onPressed: !_busy && _hasMore
                  ? () {
                      _offset += 20;
                      _load();
                    }
                  : null,
              child: const Text('Next'),
            ),
          ],
        ),
      ],
    ],
  );
}

class _InvitationDetail extends StatelessWidget {
  const _InvitationDetail({
    required this.invitation,
    required this.blocked,
    required this.lease,
  });
  final ManagedInvitation invitation;
  final bool blocked;
  final _ContextLease lease;
  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('Invitation details'),
    content: SizedBox(
      width: 520,
      child: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              _statusLabel(invitation.status),
              style: const TextStyle(fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 8),
            Text(invitation.fullName),
            SelectableText(invitation.email),
            Text('Role: ${invitation.role.label}'),
            if (invitation.employeeId != null)
              Text('Employee ID: ${invitation.employeeId}'),
            if (invitation.phone != null) Text('Phone: ${invitation.phone}'),
            const SizedBox(height: 12),
            const Text(
              'Original branch assignments',
              style: TextStyle(fontWeight: FontWeight.w700),
            ),
            if (invitation.allBranches)
              const Text('All branches')
            else if (invitation.branches.isEmpty)
              const Text(
                'Original branch details unavailable. This historical record is read only.',
              )
            else
              for (final branch in invitation.branches)
                Text('${branch.name}${branch.active ? '' : ' (inactive)'}'),
            const SizedBox(height: 12),
            Text(_deliveryLabel(invitation.delivery)),
            if (invitation.delivery == ManagedInvitationDelivery.sending)
              const Text(
                'The email request is in flight or its outcome is unknown. No automatic resend or replacement is available.',
              ),
            if (invitation.delivery == ManagedInvitationDelivery.failed)
              const Text(
                'The authentication service recorded a failed request. An authorized original sender may retry the exact same request after its cooldown.',
              ),
            Text('Created: ${_time(invitation.createdAt)}'),
            Text('Expires: ${_time(invitation.expiresAt)}'),
            if (invitation.acceptedAt != null)
              Text('Accepted: ${_time(invitation.acceptedAt!)}'),
            if (invitation.revokedAt != null)
              Text('Revoked: ${_time(invitation.revokedAt!)}'),
            if (invitation.deliveryClaimedAt != null)
              Text(
                'Email request claimed: ${_time(invitation.deliveryClaimedAt!)}',
              ),
            if (invitation.deliveryFinishedAt != null)
              Text(
                'Email request state recorded: ${_time(invitation.deliveryFinishedAt!)}',
              ),
            const SizedBox(height: 12),
            const Text(
              'Email request acceptance does not confirm inbox delivery or activate an employee membership.',
            ),
          ],
        ),
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('Close'),
      ),
      if (invitation.canRetryDelivery && invitation.retryInput != null)
        OutlinedButton(
          onPressed: !blocked && lease.active
              ? () => Navigator.pop(context, _DetailAction.retryDelivery)
              : null,
          child: const Text('Retry original email request'),
        ),
      if (invitation.canRevoke)
        FilledButton(
          onPressed: !blocked && lease.active
              ? () => Navigator.pop(context, _DetailAction.revoke)
              : null,
          child: const Text('Revoke invitation'),
        ),
    ],
  );
}

class _RevocationDialog extends StatefulWidget {
  const _RevocationDialog({required this.invitation, required this.lease});
  final ManagedInvitation invitation;
  final _ContextLease lease;
  @override
  State<_RevocationDialog> createState() => _RevocationDialogState();
}

class _RevocationDialogState extends State<_RevocationDialog> {
  final _reason = TextEditingController();
  String? _error;
  @override
  void dispose() {
    _reason.dispose();
    super.dispose();
  }

  void _submit() {
    if (!widget.lease.active) return;
    try {
      final reason = requiredText(_reason.text, 'Reason', 500, minimum: 3);
      Navigator.pop(context, reason);
    } catch (error) {
      setState(() => _error = _failure(error));
    }
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('Revoke invitation'),
    content: SizedBox(
      width: 480,
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(widget.invitation.email),
            const SizedBox(height: 12),
            const Text(
              'Block this invitation from being accepted. An email already requested may still arrive. Employee access and financial records are unchanged.',
            ),
            const SizedBox(height: 12),
            TextField(
              key: const Key('invitation-revoke-reason'),
              controller: _reason,
              maxLength: 500,
              minLines: 2,
              maxLines: 4,
              decoration: const InputDecoration(
                labelText: 'Reason',
                border: OutlineInputBorder(),
              ),
            ),
            if (_error != null)
              Text(
                _error!,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
          ],
        ),
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('Back'),
      ),
      FilledButton(
        onPressed: widget.lease.active ? _submit : null,
        child: const Text('Confirm revocation'),
      ),
    ],
  );
}

String _statusLabel(ManagedInvitationStatus status) => switch (status) {
  ManagedInvitationStatus.pending => 'Awaiting employee acceptance',
  ManagedInvitationStatus.accepted => 'Accepted by employee',
  ManagedInvitationStatus.revoked => 'Revoked',
  ManagedInvitationStatus.expired => 'Expired',
};
String _deliveryLabel(ManagedInvitationDelivery delivery) => switch (delivery) {
  ManagedInvitationDelivery.prepared => 'Email request not yet claimed',
  ManagedInvitationDelivery.sending =>
    'Email request in progress or outcome unknown',
  ManagedInvitationDelivery.sent =>
    'Email request accepted by authentication service',
  ManagedInvitationDelivery.failed => 'Email request failed',
};
String _time(DateTime date) =>
    '${date.toUtc().toIso8601String().replaceFirst('T', ' ').replaceFirst(RegExp(r'\.\d+Z$'), '')} UTC';
String _failure(Object error) => error is RepositoryFailure
    ? error.message
    : 'Invitation data could not be confirmed. Reload or preserve the original saved request.';
