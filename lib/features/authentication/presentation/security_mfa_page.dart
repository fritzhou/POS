import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../domain/mfa_repository.dart';

/// Real Auth-backed TOTP management. The setup secret is held only by this
/// live form, hidden initially, and discarded when setup completes or closes.
class SecurityMfaPage extends StatefulWidget {
  const SecurityMfaPage({
    super.key,
    required this.repository,
    this.requireVerification = false,
    this.onAssuranceChanged,
    this.onSignOut,
  });

  final MfaRepository repository;
  final bool requireVerification;
  final Future<void> Function()? onAssuranceChanged;
  final Future<void> Function()? onSignOut;

  @override
  State<SecurityMfaPage> createState() => _SecurityMfaPageState();
}

class _SecurityMfaPageState extends State<SecurityMfaPage> {
  final _code = TextEditingController();
  final _name = TextEditingController(text: 'My authenticator');
  final _secret = TextEditingController();
  MfaStatus? _status;
  MfaEnrollment? _enrollment;
  String? _factorId;
  String? _error;
  String? _notice;
  bool _busy = true;
  bool _showSecret = false;
  int _generation = 0;
  String? _actor;

  @override
  void initState() {
    super.initState();
    _actor = widget.repository.actorId;
    unawaited(_load());
  }

  @override
  void didUpdateWidget(SecurityMfaPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.repository != widget.repository ||
        _actor != widget.repository.actorId) {
      _generation++;
      _clearSetup();
      _status = null;
      _factorId = null;
      _actor = widget.repository.actorId;
      unawaited(_load());
    }
  }

  bool _current(int generation, MfaRepository repository, String? actor) =>
      mounted &&
      generation == _generation &&
      repository == widget.repository &&
      actor != null &&
      actor == repository.actorId &&
      actor == _actor;

  void _clearSetup() {
    _enrollment = null;
    _secret.clear();
    _showSecret = false;
    _code.clear();
  }

  Future<void> _load() async {
    final generation = ++_generation;
    final repository = widget.repository;
    final actor = repository.actorId;
    if (mounted) {
      setState(() {
        _busy = true;
        _error = null;
        _status = null;
      });
    }
    try {
      final status = await repository.status();
      if (!_current(generation, repository, actor) || status.actorId != actor) {
        return;
      }
      setState(() {
        _status = status;
        final factors = status.verifiedTotpFactors;
        if (!factors.any((factor) => factor.id == _factorId)) {
          _factorId = factors.isEmpty ? null : factors.first.id;
        }
      });
    } catch (error) {
      if (_current(generation, repository, actor)) {
        setState(() => _error = _message(error));
      }
    } finally {
      if (_current(generation, repository, actor)) {
        setState(() => _busy = false);
      }
    }
  }

  Future<void> _enroll() async {
    if (_busy) return;
    final generation = _generation;
    final repository = widget.repository;
    final actor = repository.actorId;
    setState(() {
      _busy = true;
      _error = null;
      _notice = null;
    });
    try {
      final enrollment = await repository.enrollTotp(name: _name.text);
      if (!_current(generation, repository, actor)) {
        // Only the original still-signed-in actor may clean up a delayed setup.
        if (repository.actorId == actor && actor != null) {
          unawaited(_cancelQuietly(repository, enrollment.factorId));
        }
        return;
      }
      setState(() {
        _enrollment = enrollment;
        _secret.text = enrollment.secret;
        _showSecret = false;
        _code.clear();
      });
    } catch (error) {
      if (_current(generation, repository, actor)) {
        setState(() => _error = _message(error));
      }
    } finally {
      if (_current(generation, repository, actor)) {
        setState(() => _busy = false);
      }
    }
  }

  Future<void> _verify() async {
    if (_busy) return;
    if (!RegExp(r'^\d{6}$').hasMatch(_code.text)) {
      setState(() => _error = 'Enter the six-digit authenticator code.');
      return;
    }
    final factorId = _enrollment?.factorId ?? _factorId;
    if (factorId == null) return;
    final code = _code.text;
    final generation = _generation;
    final repository = widget.repository;
    final actor = repository.actorId;
    setState(() {
      _busy = true;
      _error = null;
      _notice = null;
      _code.clear();
    });
    try {
      // Each attempt requests a fresh server challenge; a failed or expired
      // attempt never reuses a code or grants access optimistically.
      final challenge = await repository.challenge(factorId);
      if (!_current(generation, repository, actor)) return;
      final status = await repository.verify(challenge, code);
      if (!_current(generation, repository, actor) || status.actorId != actor) {
        return;
      }
      if (status.currentLevel != MfaAssuranceLevel.aal2) {
        throw const MfaFailure('Two-step verification was not confirmed.');
      }
      setState(() {
        _clearSetup();
        _status = status;
        final factors = status.verifiedTotpFactors;
        _factorId = factors.any((factor) => factor.id == factorId)
            ? factorId
            : (factors.isEmpty ? null : factors.first.id);
        _notice = 'Two-step verification confirmed for this session.';
      });
      await widget.onAssuranceChanged?.call();
    } catch (error) {
      if (_current(generation, repository, actor)) {
        setState(() => _error = _message(error));
      }
    } finally {
      if (_current(generation, repository, actor)) {
        setState(() => _busy = false);
      }
    }
  }

  Future<void> _cancel() async {
    final enrollment = _enrollment;
    if (_busy || enrollment == null) return;
    final generation = _generation;
    final repository = widget.repository;
    final actor = repository.actorId;
    setState(() {
      _busy = true;
      _error = null;
      _clearSetup();
    });
    try {
      await repository.cancelEnrollment(enrollment.factorId);
      if (_current(generation, repository, actor)) {
        setState(() => _notice = 'Authenticator setup canceled.');
      }
    } catch (error) {
      if (_current(generation, repository, actor)) {
        setState(() => _error = _message(error));
      }
    } finally {
      if (_current(generation, repository, actor)) {
        setState(() => _busy = false);
      }
    }
  }

  Future<void> _remove(MfaFactor factor) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Remove authenticator?'),
        content: const Text(
          'You will need to set up an authenticator again if your business '
          'requires two-step verification.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Keep authenticator'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Remove'),
          ),
        ],
      ),
    );
    if (!mounted || confirmed != true || _busy) return;
    final generation = _generation;
    final repository = widget.repository;
    final actor = repository.actorId;
    setState(() {
      _busy = true;
      _error = null;
      _notice = null;
    });
    try {
      await repository.unenroll(factor.id);
      if (!_current(generation, repository, actor)) return;
      await _load();
      if (!mounted || repository != widget.repository) return;
      await widget.onAssuranceChanged?.call();
    } catch (error) {
      if (_current(generation, repository, actor)) {
        setState(() => _error = _message(error));
      }
    } finally {
      if (_current(generation, repository, actor)) {
        setState(() => _busy = false);
      }
    }
  }

  String _message(Object error) => error is MfaFailure
      ? error.message
      : 'Two-step verification could not be completed.';

  Future<void> _cancelQuietly(MfaRepository repository, String factorId) async {
    try {
      await repository.cancelEnrollment(factorId);
    } catch (_) {
      // A disconnected setup can remain unverified in Auth. It never grants
      // AAL2; the same actor can cancel it after reconnecting.
    }
  }

  @override
  void dispose() {
    _generation++;
    final enrollment = _enrollment;
    if (enrollment != null && widget.repository.actorId == _actor) {
      unawaited(_cancelQuietly(widget.repository, enrollment.factorId));
    }
    _enrollment = null;
    _secret.dispose();
    _code.dispose();
    _name.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final status = _status;
    final factors = status?.verifiedTotpFactors ?? const <MfaFactor>[];
    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 560),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                widget.requireVerification
                    ? 'Verify your authenticator'
                    : 'Two-step verification',
                style: Theme.of(context).textTheme.headlineSmall,
              ),
              const SizedBox(height: 12),
              Text(
                widget.requireVerification
                    ? 'Your business requires an authenticator code for owner '
                          'and administrator access. Verify your current code '
                          'or set up an authenticator app to continue.'
                    : 'Use an authenticator app to protect your account with '
                          'a time-based six-digit code.',
              ),
              if (_busy) ...[
                const SizedBox(height: 16),
                const LinearProgressIndicator(),
              ],
              if (_error != null) ...[
                const SizedBox(height: 16),
                Semantics(
                  liveRegion: true,
                  child: Text(
                    _error!,
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.error,
                    ),
                  ),
                ),
              ],
              if (_notice != null) ...[
                const SizedBox(height: 16),
                Semantics(liveRegion: true, child: Text(_notice!)),
              ],
              if (status == null && !_busy)
                TextButton(onPressed: _load, child: const Text('Retry')),
              if (status != null) ...[
                const SizedBox(height: 20),
                Text(
                  status.currentLevel == MfaAssuranceLevel.aal2
                      ? 'This session has verified an authenticator.'
                      : 'This session needs an authenticator code for protected actions.',
                ),
                if (_enrollment == null && factors.isNotEmpty) ...[
                  const SizedBox(height: 20),
                  DropdownButtonFormField<String>(
                    key: ValueKey(_factorId),
                    initialValue: _factorId,
                    isExpanded: true,
                    decoration: const InputDecoration(
                      labelText: 'Authenticator',
                    ),
                    items: factors
                        .map(
                          (factor) => DropdownMenuItem(
                            value: factor.id,
                            child: Text(
                              factor.name,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        )
                        .toList(growable: false),
                    onChanged: _busy
                        ? null
                        : (value) => setState(() => _factorId = value),
                  ),
                ],
                if (_enrollment != null) ...[
                  const SizedBox(height: 20),
                  const Text(
                    'In your authenticator app, choose to enter a setup key '
                    'manually. Use your account email and select time-based codes.',
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _secret,
                    readOnly: true,
                    obscureText: !_showSecret,
                    enableInteractiveSelection: false,
                    autocorrect: false,
                    enableSuggestions: false,
                    decoration: InputDecoration(
                      labelText: 'Authenticator setup key',
                      suffixIcon: IconButton(
                        tooltip: _showSecret
                            ? 'Hide setup key'
                            : 'Show setup key',
                        onPressed: _busy
                            ? null
                            : () => setState(() => _showSecret = !_showSecret),
                        icon: Icon(
                          _showSecret ? Icons.visibility_off : Icons.visibility,
                        ),
                      ),
                    ),
                  ),
                ],
                if (_enrollment != null || factors.isNotEmpty) ...[
                  const SizedBox(height: 20),
                  TextField(
                    controller: _code,
                    enabled: !_busy,
                    keyboardType: TextInputType.number,
                    obscureText: true,
                    enableSuggestions: false,
                    autocorrect: false,
                    autofillHints: const [AutofillHints.oneTimeCode],
                    inputFormatters: [
                      FilteringTextInputFormatter.digitsOnly,
                      LengthLimitingTextInputFormatter(6),
                    ],
                    decoration: const InputDecoration(
                      labelText: 'Six-digit code',
                    ),
                    onSubmitted: (_) => _verify(),
                  ),
                  const SizedBox(height: 16),
                  FilledButton(
                    onPressed: _busy ? null : _verify,
                    child: Text(
                      _enrollment == null ? 'Verify code' : 'Finish setup',
                    ),
                  ),
                  if (_enrollment != null)
                    TextButton(
                      onPressed: _busy ? null : _cancel,
                      child: const Text('Cancel setup'),
                    ),
                ],
                if (_enrollment == null &&
                    (!widget.requireVerification || factors.isEmpty)) ...[
                  const SizedBox(height: 24),
                  TextField(
                    controller: _name,
                    enabled: !_busy,
                    maxLength: 64,
                    decoration: const InputDecoration(
                      labelText: 'Authenticator name',
                    ),
                  ),
                  OutlinedButton.icon(
                    onPressed: _busy ? null : _enroll,
                    icon: const Icon(Icons.add),
                    label: const Text('Set up authenticator'),
                  ),
                ],
                if (!widget.requireVerification && _enrollment == null)
                  for (final factor in factors)
                    ListTile(
                      contentPadding: EdgeInsets.zero,
                      title: Text(factor.name),
                      subtitle: const Text('Verified authenticator'),
                      trailing: IconButton(
                        tooltip: 'Remove authenticator',
                        onPressed:
                            _busy ||
                                status.currentLevel != MfaAssuranceLevel.aal2
                            ? null
                            : () => _remove(factor),
                        icon: const Icon(Icons.delete_outline),
                      ),
                    ),
                if (factors.isEmpty &&
                    status.nextLevel == MfaAssuranceLevel.aal2 &&
                    _enrollment == null) ...[
                  const SizedBox(height: 16),
                  const Text(
                    'Your account has another factor type. Use its supported '
                    'sign-in flow or set up an authenticator app here.',
                  ),
                ],
                for (final factor in status.factors.where(
                  (factor) =>
                      factor.isTotp &&
                      !factor.isVerified &&
                      factor.id != _enrollment?.factorId,
                ))
                  TextButton(
                    onPressed: _busy ? null : () => _discardUnverified(factor),
                    child: Text('Cancel unfinished setup: ${factor.name}'),
                  ),
              ],
              if (widget.onSignOut != null) ...[
                const SizedBox(height: 24),
                TextButton(
                  onPressed: widget.onSignOut,
                  child: const Text('Sign out'),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _discardUnverified(MfaFactor factor) async {
    if (_busy) return;
    final generation = _generation;
    final repository = widget.repository;
    final actor = repository.actorId;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await repository.cancelEnrollment(factor.id);
      if (!_current(generation, repository, actor)) return;
      await _load();
    } catch (error) {
      if (_current(generation, repository, actor)) {
        setState(() => _error = _message(error));
      }
    } finally {
      if (_current(generation, repository, actor)) {
        setState(() => _busy = false);
      }
    }
  }
}
