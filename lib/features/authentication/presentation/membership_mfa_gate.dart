import 'dart:async';

import 'package:flutter/material.dart';

import '../../../core/auth/auth_models.dart';
import '../../../core/security/app_role.dart';
import '../../security/domain/security_models.dart';
import '../../security/domain/security_repository.dart';
import '../domain/mfa_repository.dart';
import 'security_mfa_page.dart';

/// Fresh policy discovery is available at AAL1; ordinary privileged business
/// RPCs independently enforce AAL2 when this policy is enabled on the server.
class MembershipMfaGate extends StatefulWidget {
  const MembershipMfaGate({
    super.key,
    required this.actor,
    required this.securityRepository,
    required this.mfaRepository,
    required this.child,
    required this.onSignOut,
    this.onPolicyLoaded,
    this.onAccessBlocked,
    this.refreshToken,
  });

  final AuthenticatedUser actor;
  final SecurityRepository securityRepository;
  final MfaRepository mfaRepository;
  final Widget child;
  final Future<void> Function() onSignOut;
  final ValueChanged<SecurityPolicy>? onPolicyLoaded;
  final VoidCallback? onAccessBlocked;
  final Object? refreshToken;

  @override
  State<MembershipMfaGate> createState() => _MembershipMfaGateState();
}

class _MembershipMfaGateState extends State<MembershipMfaGate> {
  bool _loading = true;
  bool _allowed = false;
  bool _requiresMfa = false;
  String? _error;
  int _generation = 0;

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  @override
  void didUpdateWidget(MembershipMfaGate oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.actor.userId != widget.actor.userId ||
        oldWidget.actor.organizationId != widget.actor.organizationId ||
        oldWidget.actor.membershipId != widget.actor.membershipId ||
        oldWidget.actor.role != widget.actor.role ||
        oldWidget.securityRepository != widget.securityRepository ||
        oldWidget.mfaRepository != widget.mfaRepository ||
        oldWidget.refreshToken != widget.refreshToken) {
      unawaited(_load());
    }
  }

  bool _current(
    int generation,
    String actorId,
    String organizationId,
    SecurityRepository security,
    MfaRepository mfa,
  ) =>
      mounted &&
      generation == _generation &&
      widget.actor.userId == actorId &&
      widget.actor.organizationId == organizationId &&
      widget.securityRepository == security &&
      widget.mfaRepository == mfa &&
      mfa.actorId == actorId;

  Future<void> _load() async {
    final generation = ++_generation;
    final actor = widget.actor;
    final security = widget.securityRepository;
    final mfa = widget.mfaRepository;
    setState(() {
      _loading = true;
      _allowed = false;
      _requiresMfa = false;
      _error = null;
    });
    try {
      final policy = await security.loadPolicy();
      if (!_current(
        generation,
        actor.userId,
        actor.organizationId,
        security,
        mfa,
      )) {
        return;
      }
      if (policy.organizationId != actor.organizationId) {
        throw const MfaFailure('Security policy could not be confirmed.');
      }
      final privileged =
          actor.role == AppRole.owner || actor.role == AppRole.admin;
      final required = privileged && policy.requirePrivilegedMfa;
      var allowed = !required;
      if (required) {
        final status = await mfa.status();
        if (!_current(
          generation,
          actor.userId,
          actor.organizationId,
          security,
          mfa,
        )) {
          return;
        }
        if (status.actorId != actor.userId) {
          throw const MfaFailure('Sign in again to confirm your account.');
        }
        allowed = status.currentLevel == MfaAssuranceLevel.aal2;
      }
      setState(() {
        _loading = false;
        _allowed = allowed;
        _requiresMfa = required && !allowed;
      });
      widget.onPolicyLoaded?.call(policy);
      if (!allowed) widget.onAccessBlocked?.call();
    } catch (_) {
      if (_current(
        generation,
        actor.userId,
        actor.organizationId,
        security,
        mfa,
      )) {
        setState(() {
          _loading = false;
          _allowed = false;
          _error =
              'Your business security requirements could not be confirmed. '
              'Reconnect and try again.';
        });
        widget.onAccessBlocked?.call();
      }
    }
  }

  @override
  void dispose() {
    _generation++;
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_allowed && !_loading) return widget.child;
    if (_requiresMfa && !_loading) {
      return Scaffold(
        appBar: AppBar(title: const Text('Account verification')),
        body: SecurityMfaPage(
          repository: widget.mfaRepository,
          requireVerification: true,
          onAssuranceChanged: _load,
          onSignOut: widget.onSignOut,
        ),
      );
    }
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 480),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (_loading) ...[
                    const CircularProgressIndicator(),
                    const SizedBox(height: 20),
                    const Text('Checking business security requirements…'),
                  ] else ...[
                    Text(_error ?? 'Sign in again to confirm your account.'),
                    const SizedBox(height: 20),
                    FilledButton(onPressed: _load, child: const Text('Retry')),
                  ],
                  const SizedBox(height: 12),
                  TextButton(
                    onPressed: widget.onSignOut,
                    child: const Text('Sign out'),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
