import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:uuid/uuid.dart';

import '../../core/security/app_role.dart';
import '../catalog/domain/repository_support.dart';
import 'pin_security.dart';

class PinSecuritySection extends StatefulWidget {
  const PinSecuritySection({
    super.key,
    required this.repository,
    required this.role,
  });
  final EmployeePinRepository repository;
  final AppRole role;
  @override
  State<PinSecuritySection> createState() => _PinSecuritySectionState();
}

class _PinSecuritySectionState extends State<PinSecuritySection> {
  EmployeePinStatus? _status;
  List<EmployeePinResetTarget> _targets = [];
  bool _hasMore = false;
  bool _busy = false;
  String? _error;
  String? _message;
  final _pin = TextEditingController();
  final _confirm = TextEditingController();
  final _current = TextEditingController();
  String? _setRequestId;
  int _generation = 0;
  bool get _canReset =>
      [AppRole.owner, AppRole.admin, AppRole.manager].contains(widget.role);
  @override
  void initState() {
    super.initState();
    _reload();
  }

  @override
  void didUpdateWidget(covariant PinSecuritySection oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.repository != widget.repository ||
        oldWidget.role != widget.role) {
      _pin.clear();
      _generation++;
      _confirm.clear();
      _current.clear();
      _setRequestId = null;
      _status = null;
      _targets = [];
      _reload();
    }
  }

  @override
  void dispose() {
    _pin.dispose();
    _confirm.dispose();
    _current.dispose();
    super.dispose();
  }

  String _failure(Object error) => error is RepositoryFailure
      ? error.message
      : 'PIN security could not be confirmed. Try again online.';
  Future<void> _reload() async {
    final generation = _generation;
    final repository = widget.repository;
    final canReset = _canReset;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final status = await repository.status();
      final targets = canReset ? await repository.resetTargets() : null;
      if (!mounted || generation != _generation) return;
      setState(() {
        _status = status;
        _targets = targets?.items ?? [];
        _hasMore = targets?.hasMore ?? false;
      });
    } catch (error) {
      if (mounted && generation == _generation) {
        setState(() => _error = _failure(error));
      }
    } finally {
      if (mounted && generation == _generation) setState(() => _busy = false);
    }
  }

  Future<void> _loadMore() async {
    final generation = _generation;
    final repository = widget.repository;
    setState(() => _busy = true);
    try {
      final page = await repository.resetTargets(
        page: PageRequest(offset: _targets.length),
      );
      if (mounted && generation == _generation) {
        setState(() {
          _targets = [..._targets, ...page.items];
          _hasMore = page.hasMore;
        });
      }
    } catch (error) {
      if (mounted && generation == _generation) {
        setState(() => _error = _failure(error));
      }
    } finally {
      if (mounted && generation == _generation) setState(() => _busy = false);
    }
  }

  Future<void> _setPin() async {
    final generation = _generation;
    final repository = widget.repository;
    final status = _status;
    if (status == null) return;
    try {
      validateEmployeePin(_pin.text);
      if (_pin.text != _confirm.text) {
        throw const RepositoryFailure(
          RepositoryFailureType.validation,
          'The new PINs do not match.',
        );
      }
      if (status.configured) validateEmployeePin(_current.text);
    } catch (error) {
      setState(() => _error = _failure(error));
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
      _message = null;
    });
    final id = _setRequestId ??= const Uuid().v4();
    try {
      final result = await repository.setPin(
        requestId: id,
        expectedRevision: status.revision,
        pin: _pin.text,
        currentPin: status.configured ? _current.text : null,
      );
      if (!mounted || generation != _generation) return;
      setState(() {
        _status = result.status;
        _setRequestId = null;
        _message = result.accepted
            ? 'PIN saved.'
            : 'PIN check failed. Repeated attempts can temporarily lock PIN changes.';
      });
      _pin.clear();
      _confirm.clear();
      _current.clear();
    } catch (error) {
      if (mounted && generation == _generation) {
        setState(() => _error = _failure(error));
      }
    } finally {
      if (mounted && generation == _generation) setState(() => _busy = false);
    }
  }

  Future<void> _reset(EmployeePinResetTarget target) async {
    final generation = _generation;
    final repository = widget.repository;
    final requestId = const Uuid().v4();
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => _PinResetDialog(
        name: target.fullName,
        onReset: (reason) async {
          // A retry of this dialog retains one immutable request and revision.
          return repository.resetPin(
            membershipId: target.membershipId,
            requestId: requestId,
            expectedRevision: target.status.revision,
            reason: reason,
          );
        },
      ),
    );
    if (mounted && generation == _generation) await _reload();
  }

  Widget _secretField(TextEditingController controller, String label) =>
      TextField(
        controller: controller,
        enabled: !_busy,
        obscureText: true,
        enableSuggestions: false,
        autocorrect: false,
        keyboardType: TextInputType.number,
        autofillHints: const [],
        maxLength: 12,
        inputFormatters: [FilteringTextInputFormatter.digitsOnly],
        onChanged: (_) => _setRequestId = null,
        decoration: InputDecoration(labelText: label, counterText: ''),
      );
  @override
  Widget build(BuildContext context) => Card(
    child: Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Employee PIN', style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 8),
          const Text(
            'A PIN supplements your signed-in account. Changing a PIN requires an online connection. Use 6 to 12 digits.',
          ),
          const SizedBox(height: 12),
          if (_busy) const LinearProgressIndicator(),
          if (_error != null)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: Text(
                _error!,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            ),
          if (_message != null)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: Text(_message!),
            ),
          if (_status case final status?) ...[
            Text(
              status.configured
                  ? 'Your PIN is configured.'
                  : 'Set a new PIN for your account.',
            ),
            if (status.lockedUntil != null)
              Text('PIN checks locked until ${status.lockedUntil!.toLocal()}.'),
            const SizedBox(height: 8),
            if (status.configured) _secretField(_current, 'Current PIN'),
            _secretField(_pin, 'New PIN'),
            const SizedBox(height: 8),
            _secretField(_confirm, 'Confirm new PIN'),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                FilledButton(
                  onPressed: _busy ? null : _setPin,
                  child: Text(status.configured ? 'Change PIN' : 'Set PIN'),
                ),
                TextButton(
                  onPressed: _busy ? null : _reload,
                  child: const Text('Reload PIN status'),
                ),
              ],
            ),
          ] else if (!_busy)
            TextButton(
              onPressed: _reload,
              child: const Text('Load PIN status'),
            ),
          if (_canReset) ...[
            const Divider(height: 32),
            Text(
              'Reset employee PIN',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const Text(
              'A reset removes the previous PIN and records your reason. The employee must sign in online to set a new PIN.',
            ),
            for (final target in _targets)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Wrap(
                  alignment: WrapAlignment.spaceBetween,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  spacing: 12,
                  runSpacing: 4,
                  children: [
                    Text('${target.fullName} · ${target.role.label}'),
                    OutlinedButton(
                      onPressed: _busy ? null : () => _reset(target),
                      child: const Text('Reset PIN'),
                    ),
                  ],
                ),
              ),
            if (_targets.isEmpty && !_busy)
              const Padding(
                padding: EdgeInsets.only(top: 8),
                child: Text('No employees available in your reset scope.'),
              ),
            if (_hasMore)
              TextButton(
                onPressed: _busy ? null : _loadMore,
                child: const Text('Load more employees'),
              ),
          ],
        ],
      ),
    ),
  );
}

class _PinResetDialog extends StatefulWidget {
  const _PinResetDialog({required this.name, required this.onReset});
  final String name;
  final Future<EmployeePinStatus> Function(String reason) onReset;
  @override
  State<_PinResetDialog> createState() => _PinResetDialogState();
}

class _PinResetDialogState extends State<_PinResetDialog> {
  bool _busy = false;
  String? _error;
  final _reason = TextEditingController();
  String? _submittedReason;
  @override
  void dispose() {
    _reason.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    try {
      requiredText(_reason.text, 'Reset reason', 500, minimum: 8);
    } catch (error) {
      setState(
        () => _error = error is RepositoryFailure
            ? error.message
            : 'Enter a reason.',
      );
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      _submittedReason ??= _reason.text;
      await widget.onReset(_submittedReason!);
      if (mounted) Navigator.of(context).pop();
    } catch (error) {
      if (mounted) {
        setState(
          () => _error = error is RepositoryFailure
              ? error.message
              : 'PIN reset could not be confirmed. Retry this request.',
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: !_busy,
    child: AlertDialog(
      title: Text('Reset ${widget.name}’s PIN?'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'The old PIN will stop working. The employee sets a replacement after signing in online.',
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _reason,
              enabled: !_busy && _submittedReason == null,
              maxLength: 500,
              maxLines: 3,
              decoration: const InputDecoration(labelText: 'Reset reason'),
            ),
            if (_error != null)
              Text(
                _error!,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            if (_busy) const LinearProgressIndicator(),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: _busy ? null : () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: _busy ? null : _submit,
          child: const Text('Reset PIN'),
        ),
      ],
    ),
  );
}
