import 'dart:async';

import 'package:flutter/material.dart';

import '../../../core/auth/auth_models.dart';
import '../../../core/auth/auth_repository.dart';
import '../../../core/auth/invitation_inbox.dart';
import '../../../core/widgets/brand_mark.dart';
import '../application/auth_validation.dart';

enum _AuthView {
  signIn,
  ownerSetup,
  forgotPassword,
  verifyEmail,
  noAccess,
  reset,
  invitations,
}

/// Routes only identities with freshly loaded server membership into the app.
/// The design preview callback never creates an identity or membership.
class AuthGate extends StatefulWidget {
  const AuthGate({
    super.key,
    required this.repository,
    required this.authenticatedBuilder,
    required this.onPreview,
    this.invitationInbox,
    this.onOpenOffline,
    this.onAuthorizationInvalidated,
    this.onMembershipsVerified,
    this.appName = 'NexaPOS',
    this.tagline = 'Smart Retail & Cafe POS',
  });

  final AuthRepository repository;
  final Widget Function(BuildContext, AuthenticatedUser) authenticatedBuilder;
  final VoidCallback onPreview;
  final InvitationInbox? invitationInbox;

  /// Opens a separate device-grant workspace. A transport failure never sends
  /// cached membership into [authenticatedBuilder].
  final Future<void> Function(AuthIdentity)? onOpenOffline;
  final Future<void> Function(AuthIdentity)? onAuthorizationInvalidated;
  final Future<void> Function(AuthIdentity, List<AuthenticatedUser>)?
  onMembershipsVerified;
  final String appName;
  final String tagline;

  @override
  State<AuthGate> createState() => _AuthGateState();
}

class _AuthGateState extends State<AuthGate> {
  final _formKey = GlobalKey<FormState>();
  final _email = TextEditingController();
  final _password = TextEditingController();
  final _confirmation = TextEditingController();
  final _business = TextEditingController();
  final _name = TextEditingController();
  StreamSubscription<AuthSessionEvent>? _subscription;
  _AuthView _view = _AuthView.signIn;
  AuthenticatedUser? _user;
  List<AuthenticatedUser> _memberships = [];
  bool _busy = false;
  bool _loadingMemberships = false;
  bool _remember = false;
  bool _obscurePassword = true;
  bool _obscureConfirmation = true;
  String? _error;
  String? _notice;
  int _membershipRequest = 0;
  int _invitationRequest = 0;
  List<PendingEmployeeInvitation> _invitations = [];
  PendingEmployeeInvitation? _selectedInvitation;
  bool _invitationLoading = false;
  bool _showInvitationInbox = false;
  bool _invitationsDismissed = false;
  String? _invitationError;
  String? _invitationIdentityId;
  String? _offlineEligibleIdentityId;

  AuthRepository get _repository => widget.repository;

  @override
  void initState() {
    super.initState();
    _attachRepository();
  }

  @override
  void didUpdateWidget(covariant AuthGate oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.repository != widget.repository) {
      unawaited(_subscription?.cancel());
      _membershipRequest++;
      _clearInvitations();
      _user = null;
      _memberships = [];
      _offlineEligibleIdentityId = null;
      _attachRepository();
    } else if (oldWidget.invitationInbox != widget.invitationInbox) {
      _clearInvitations();
      unawaited(_refreshInvitations());
    }
  }

  void _attachRepository() {
    _subscription = _repository.events.listen(
      _onSessionEvent,
      onError: (Object error, StackTrace stack) {
        if (!mounted) return;
        _membershipRequest++;
        _invitationRequest++;
        setState(() {
          _user = null;
          _memberships = [];
          _loadingMemberships = false;
          _invitationLoading = false;
          _view = _repository.hasVerifiedRecoverySession
              ? _AuthView.reset
              : _AuthView.signIn;
          _error = _publicMessage(error);
          _offlineEligibleIdentityId = _eligibleOfflineIdentity(error);
        });
      },
    );
    if (_repository.hasVerifiedRecoverySession) {
      _view = _AuthView.reset;
    } else if (_repository.currentIdentity != null) {
      unawaited(_loadMemberships());
    }
  }

  void _onSessionEvent(AuthSessionEvent event) {
    if (!mounted) return;
    _offlineEligibleIdentityId = null;
    if (_invitationIdentityId != null &&
        event.identity?.userId != _invitationIdentityId) {
      _clearInvitations();
    }
    if (_repository.hasVerifiedRecoverySession &&
        event.type != AuthSessionEventType.signedOut) {
      _membershipRequest++;
      _clearInvitations();
      setState(() {
        _user = null;
        _memberships = [];
        _view = _AuthView.reset;
        _loadingMemberships = false;
        _error = null;
        _offlineEligibleIdentityId = null;
        _notice = null;
      });
    } else if (event.identity == null) {
      _membershipRequest++;
      _clearInvitations();
      setState(() {
        _user = null;
        _memberships = [];
        _loadingMemberships = false;
        _view = _AuthView.signIn;
        _email.clear();
        _password.clear();
        _confirmation.clear();
        _business.clear();
        _name.clear();
        _remember = false;
      });
    } else {
      unawaited(_loadMemberships());
    }
  }

  Future<void> _loadMemberships() async {
    final request = ++_membershipRequest;
    final previousOrganization = _user?.organizationId;
    if (mounted) {
      setState(() {
        _user = null;
        _memberships = [];
        _loadingMemberships = true;
        _error = null;
        _offlineEligibleIdentityId = null;
      });
    }
    try {
      final identity = _repository.currentIdentity;
      final memberships = identity?.emailVerified == true
          ? await _repository.loadMemberships()
          : <AuthenticatedUser>[];
      if (!mounted || request != _membershipRequest) return;
      if (_repository.currentIdentity?.userId != identity?.userId) {
        setState(() {
          _user = null;
          _memberships = [];
          _loadingMemberships = false;
          _view = _AuthView.signIn;
        });
        return;
      }
      // A repository response for a different identity never authorizes this
      // session. Membership/branch policy remains enforced again by the server.
      final authorized = memberships
          .where((member) => member.userId == identity?.userId)
          .where((member) => member.branchIds.isNotEmpty)
          .toList();
      if (authorized.isEmpty && identity?.emailVerified == true) {
        await widget.onAuthorizationInvalidated?.call(identity!);
        if (!mounted || request != _membershipRequest) return;
      } else if (identity?.emailVerified == true) {
        await widget.onMembershipsVerified?.call(
          identity!,
          List.unmodifiable(authorized),
        );
        if (!mounted || request != _membershipRequest) return;
      }
      setState(() {
        _memberships = authorized;
        _user = authorized.length == 1
            ? authorized.single
            : authorized
                  .where(
                    (member) => member.organizationId == previousOrganization,
                  )
                  .firstOrNull;
        _loadingMemberships = false;
        _view = _showInvitationInbox
            ? _AuthView.invitations
            : _AuthView.noAccess;
        if (identity?.pendingBusinessName != null) {
          _business.text = identity!.pendingBusinessName!;
          _name.text = identity.fullName ?? '';
        }
      });
      unawaited(_refreshInvitations());
    } on Object catch (error) {
      if (!mounted || request != _membershipRequest) return;
      if (error is AuthFailure &&
          error.kind == AuthFailureKind.authorization &&
          _repository.currentIdentity != null) {
        await widget.onAuthorizationInvalidated?.call(
          _repository.currentIdentity!,
        );
        if (!mounted || request != _membershipRequest) return;
      }
      setState(() {
        _user = null;
        _memberships = [];
        _loadingMemberships = false;
        _view = _AuthView.noAccess;
        _error = _publicMessage(error);
        _offlineEligibleIdentityId = _eligibleOfflineIdentity(error);
      });
    }
  }

  String? _eligibleOfflineIdentity(Object error) {
    final identity = _repository.currentIdentity;
    return error is AuthFailure &&
            error.kind == AuthFailureKind.unavailable &&
            identity?.emailVerified == true &&
            !_repository.hasVerifiedRecoverySession &&
            widget.onOpenOffline != null
        ? identity!.userId
        : null;
  }

  bool get _canOpenOffline =>
      _offlineEligibleIdentityId != null &&
      _repository.currentIdentity?.userId == _offlineEligibleIdentityId &&
      _repository.currentIdentity?.emailVerified == true &&
      !_repository.hasVerifiedRecoverySession &&
      widget.onOpenOffline != null;

  Future<void> _openOffline() async {
    if (!_canOpenOffline || _busy) return;
    final identity = _repository.currentIdentity!;
    await _run(() async {
      if (!_canOpenOffline ||
          _repository.currentIdentity?.userId != identity.userId) {
        return;
      }
      await widget.onOpenOffline!(identity);
    });
  }

  Widget _offlineEntry() => Padding(
    padding: const EdgeInsets.only(top: 12),
    child: OutlinedButton.icon(
      key: const Key('open-authorized-offline'),
      onPressed: _busy ? null : _openOffline,
      icon: const Icon(Icons.offline_bolt_outlined),
      label: const Text('Open authorized offline workspace'),
    ),
  );

  String _publicMessage(Object error) => error is AuthFailure
      ? error.message
      : error is InvitationFailure
      ? error.message
      : 'The authentication service is temporarily unavailable. Try again shortly.';

  void _clearInvitations() {
    _invitationRequest++;
    _invitations = [];
    _selectedInvitation = null;
    _showInvitationInbox = false;
    _invitationLoading = false;
    _invitationsDismissed = false;
    _invitationError = null;
    _invitationIdentityId = null;
  }

  Future<void> _refreshInvitations() async {
    final inbox = widget.invitationInbox;
    final identity = _repository.currentIdentity;
    if (inbox == null ||
        identity?.emailVerified != true ||
        _repository.hasVerifiedRecoverySession) {
      return;
    }
    final request = ++_invitationRequest;
    _invitationIdentityId = identity!.userId;
    if (mounted) {
      setState(() {
        _invitationLoading = true;
        _invitationError = null;
      });
    }
    try {
      final pending = await inbox.listPending();
      if (!mounted ||
          request != _invitationRequest ||
          _repository.currentIdentity?.userId != identity.userId ||
          _repository.hasVerifiedRecoverySession) {
        return;
      }
      setState(() {
        _invitations = pending;
        _invitationLoading = false;
        if (_selectedInvitation != null) {
          _selectedInvitation = pending
              .where((item) => item.id == _selectedInvitation!.id)
              .firstOrNull;
        }
        if (_memberships.isEmpty &&
            pending.isNotEmpty &&
            !_invitationsDismissed) {
          _showInvitationInbox = true;
          _view = _AuthView.invitations;
        }
      });
    } on Object catch (error) {
      if (!mounted || request != _invitationRequest) return;
      setState(() {
        _invitationLoading = false;
        _invitationError = _publicMessage(error);
      });
    }
  }

  void _openInvitations() {
    if (_busy ||
        _repository.hasVerifiedRecoverySession ||
        _repository.currentIdentity?.emailVerified != true) {
      return;
    }
    _changeView(_AuthView.invitations);
    setState(() {
      _showInvitationInbox = true;
      _invitationsDismissed = false;
    });
  }

  void _closeInvitations() {
    if (_busy) return;
    _password.clear();
    _confirmation.clear();
    setState(() {
      _selectedInvitation = null;
      _showInvitationInbox = false;
      _invitationsDismissed = true;
      _view = _AuthView.noAccess;
      _error = null;
    });
  }

  Future<void> _acceptInvitation() async {
    final invitation = _selectedInvitation;
    final inbox = widget.invitationInbox;
    if (invitation == null || inbox == null || _busy) return;
    if (_repository.currentIdentity?.emailVerified != true ||
        _repository.hasVerifiedRecoverySession) {
      setState(
        () => _error =
            'Sign in with your verified email and finish password recovery first.',
      );
      return;
    }
    if (invitation.requiresPassword && !_formKey.currentState!.validate()) {
      return;
    }
    final acceptingUserId = _repository.currentIdentity!.userId;
    await _run(() async {
      try {
        await inbox.accept(
          invitation,
          newPassword: invitation.requiresPassword ? _password.text : null,
        );
      } on Object {
        // An acceptance can commit even when its response is lost. Consult
        // authoritative memberships rather than retrying or fabricating access.
        if (mounted &&
            _repository.currentIdentity?.userId == acceptingUserId &&
            !_repository.hasVerifiedRecoverySession) {
          await _loadMemberships();
        }
        rethrow;
      }
      if (!mounted || _repository.hasVerifiedRecoverySession) return;
      setState(() {
        _user = null;
        _memberships = [];
        _selectedInvitation = null;
        _showInvitationInbox = false;
        _view = _AuthView.noAccess;
      });
      // RPC success alone is not an authenticated tenant context.
      await _loadMemberships();
    });
  }

  Future<void> _run(Future<void> Function() action) async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _error = null;
      _notice = null;
    });
    try {
      await action();
    } on Object catch (error) {
      if (mounted) setState(() => _error = _publicMessage(error));
    } finally {
      // Passwords are only kept in these short-lived in-memory controllers.
      if (mounted) {
        _password.clear();
        _confirmation.clear();
        setState(() => _busy = false);
      }
    }
  }

  void _changeView(_AuthView view) {
    if (_busy) return;
    _password.clear();
    _confirmation.clear();
    setState(() {
      _view = view;
      _error = null;
      _notice = null;
      _obscurePassword = true;
      _obscureConfirmation = true;
    });
  }

  Future<void> _signIn() async {
    if (!_formKey.currentState!.validate()) return;
    await _run(() async {
      await _repository.signIn(
        email: _email.text.trim(),
        password: _password.text,
        rememberDevice: _remember,
      );
      // A real repository emits a session event; this explicit refresh also
      // prevents an adapter event timing race from leaving the sign-in view.
      if (!_repository.hasVerifiedRecoverySession) await _loadMemberships();
    });
  }

  Future<void> _registerOwner() async {
    if (!_formKey.currentState!.validate()) return;
    final alreadySignedIn = _repository.currentIdentity?.emailVerified == true;
    await _run(() async {
      if (alreadySignedIn) {
        await _repository.bootstrapOwner(
          businessName: _business.text,
          fullName: _name.text,
        );
        await _loadMemberships();
      } else {
        final result = await _repository.registerOwner(
          businessName: _business.text,
          fullName: _name.text,
          email: _email.text,
          password: _password.text,
        );
        if (!mounted) return;
        if (result.requiresEmailVerification) {
          setState(() => _view = _AuthView.verifyEmail);
        } else {
          await _loadMemberships();
        }
      }
    });
  }

  Future<void> _requestRecovery() async {
    if (!_formKey.currentState!.validate()) return;
    await _run(() async {
      await _repository.requestPasswordRecovery(_email.text.trim());
      if (mounted) setState(() => _notice = neutralRecoveryMessage);
    });
  }

  Future<void> _resetPassword() async {
    if (!_repository.hasVerifiedRecoverySession) {
      setState(() {
        _view = _AuthView.signIn;
        _error = 'Request a new recovery email to reset your password.';
      });
      return;
    }
    if (!_formKey.currentState!.validate()) return;
    await _run(() async {
      await _repository.updateRecoveredPassword(_password.text);
      if (mounted) {
        setState(() {
          _view = _AuthView.signIn;
          _notice =
              'Your password was updated. Sign in with your new password.';
        });
      }
    });
  }

  @override
  void dispose() {
    unawaited(_subscription?.cancel());
    _membershipRequest++;
    _invitationRequest++;
    _email.dispose();
    _password.dispose();
    _confirmation.dispose();
    _business.dispose();
    _name.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_user != null &&
        _repository.currentIdentity?.userId == _user!.userId &&
        _repository.currentIdentity?.emailVerified == true &&
        !_repository.hasVerifiedRecoverySession &&
        !_showInvitationInbox) {
      final shell = widget.authenticatedBuilder(context, _user!);
      if (_invitations.isEmpty &&
          (_invitationError == null || _invitationsDismissed)) {
        return shell;
      }
      return Column(
        children: [
          Material(
            color: const Color(0xffeaf4ff),
            child: SafeArea(
              bottom: false,
              child: _invitationsDismissed
                  ? Align(
                      alignment: Alignment.centerRight,
                      child: TextButton.icon(
                        onPressed: _openInvitations,
                        icon: const Icon(Icons.mail_outline_rounded),
                        label: Text(
                          'Business invitations (${_invitations.length})',
                        ),
                      ),
                    )
                  : _invitationBanner(),
            ),
          ),
          Expanded(child: shell),
        ],
      );
    }
    return Scaffold(
      backgroundColor: const Color(0xfff3f6fa),
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) {
            final desktop = constraints.maxWidth >= 1000;
            final form = Center(
              child: SingleChildScrollView(
                padding: EdgeInsets.all(desktop ? 48 : 24),
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 460),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      if (!desktop) ...[
                        _brand(context),
                        const SizedBox(height: 32),
                      ],
                      Card(
                        elevation: 0,
                        color: Colors.white,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(24),
                          side: const BorderSide(color: Color(0xffe3e9f1)),
                        ),
                        child: Padding(
                          padding: const EdgeInsets.all(28),
                          child: _loadingMemberships
                              ? const Padding(
                                  padding: EdgeInsets.symmetric(vertical: 72),
                                  child: Column(
                                    children: [
                                      CircularProgressIndicator(),
                                      SizedBox(height: 24),
                                      Text('Checking business access…'),
                                    ],
                                  ),
                                )
                              : _formContent(context),
                        ),
                      ),
                      const SizedBox(height: 24),
                      Text(
                        'Built for your counter. Ready for your next chapter.',
                        textAlign: TextAlign.center,
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: const Color(0xff64748b),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            );
            return desktop
                ? Row(
                    children: [
                      Expanded(child: _hero(context)),
                      Expanded(child: form),
                    ],
                  )
                : form;
          },
        ),
      ),
    );
  }

  Widget _brand(BuildContext context, {bool inverse = false}) => Row(
    mainAxisAlignment: MainAxisAlignment.center,
    children: [
      BrandMark(size: 54, light: inverse),
      const SizedBox(width: 14),
      Flexible(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              widget.appName,
              style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                fontWeight: FontWeight.w800,
                color: inverse ? Colors.white : const Color(0xff14233d),
              ),
            ),
            Text(
              widget.tagline,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: inverse
                    ? const Color(0xffbbcee8)
                    : const Color(0xff64748b),
              ),
            ),
          ],
        ),
      ),
    ],
  );

  Widget _hero(BuildContext context) => Container(
    padding: const EdgeInsets.all(64),
    decoration: const BoxDecoration(
      gradient: LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [Color(0xff0f1d35), Color(0xff173d69)],
      ),
    ),
    child: Center(
      child: SingleChildScrollView(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 450),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _brand(context, inverse: true),
              const SizedBox(height: 72),
              Container(
                padding: const EdgeInsets.all(24),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.06),
                  borderRadius: BorderRadius.circular(28),
                  border: Border.all(
                    color: Colors.white.withValues(alpha: 0.12),
                  ),
                ),
                child: const Icon(
                  Icons.point_of_sale_rounded,
                  color: Color(0xff6fbbff),
                  size: 90,
                ),
              ),
              const SizedBox(height: 32),
              Text(
                'A clearer view.\nA smoother day.',
                style: Theme.of(context).textTheme.displaySmall?.copyWith(
                  color: Colors.white,
                  fontWeight: FontWeight.w700,
                  height: 1.15,
                ),
              ),
              const SizedBox(height: 20),
              Text(
                'One workspace for your retail counter and cafe.\nSign in to your business and pick up where your team left off.',
                style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                  color: const Color(0xffbbcee8),
                  height: 1.6,
                ),
              ),
            ],
          ),
        ),
      ),
    ),
  );

  Widget _formContent(BuildContext context) {
    if (!_repository.isConfigured) return _notConnected(context);
    if (_view == _AuthView.invitations) return _invitationContent(context);
    if (_view == _AuthView.noAccess) return _accessContent(context);
    final verifiedOwner = _repository.currentIdentity?.emailVerified == true;
    final heading = switch (_view) {
      _AuthView.signIn => 'Welcome back',
      _AuthView.ownerSetup =>
        verifiedOwner ? 'Finish business setup' : 'Set up a new business',
      _AuthView.forgotPassword => 'Forgot your password?',
      _AuthView.verifyEmail => 'Check your email',
      _AuthView.reset => 'Choose a new password',
      _AuthView.noAccess => 'Business access',
      _AuthView.invitations => 'Business invitations',
    };
    final subtitle = switch (_view) {
      _AuthView.signIn => 'Sign in to your business workspace.',
      _AuthView.ownerSetup =>
        'Create the first owner account for a new business. Employees are invited by an administrator.',
      _AuthView.forgotPassword =>
        'Enter your email and we’ll help you get back in. Recovery requires an internet connection.',
      _AuthView.verifyEmail =>
        'Check your email for verification instructions. If you already have an account, sign in or request password recovery.',
      _AuthView.reset =>
        'This recovery session was verified by Supabase. Choose a password you haven’t used before.',
      _AuthView.noAccess => '',
      _AuthView.invitations => '',
    };
    return AutofillGroup(
      child: Form(
        key: _formKey,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _heading(context, heading, subtitle),
            if (_error != null) _message(context, _error!, error: true),
            if (_notice != null) _message(context, _notice!),
            if (_canOpenOffline) _offlineEntry(),
            if (_view == _AuthView.ownerSetup) ...[
              _textField(
                _business,
                'Business name',
                Icons.storefront_outlined,
                validator: (value) =>
                    validateRequiredName(value, 'business name'),
              ),
              const SizedBox(height: 18),
              _textField(
                _name,
                'Full name',
                Icons.person_outline_rounded,
                validator: (value) => validateRequiredName(value, 'full name'),
                autofillHints: const [AutofillHints.name],
              ),
              const SizedBox(height: 18),
            ],
            if (_view == _AuthView.signIn ||
                _view == _AuthView.forgotPassword ||
                (_view == _AuthView.ownerSetup && !verifiedOwner)) ...[
              _textField(
                _email,
                _view == _AuthView.signIn
                    ? 'Email or Employee ID'
                    : 'Email address',
                Icons.mail_outline_rounded,
                validator: _view == _AuthView.signIn
                    ? validateLoginIdentifier
                    : validateEmail,
                keyboardType: TextInputType.emailAddress,
                autofillHints: const [
                  AutofillHints.email,
                  AutofillHints.username,
                ],
                helper: _view == _AuthView.signIn
                    ? 'Email supported • Employee ID Coming Soon'
                    : null,
              ),
              const SizedBox(height: 18),
            ],
            if (_view == _AuthView.signIn ||
                _view == _AuthView.reset ||
                (_view == _AuthView.ownerSetup && !verifiedOwner)) ...[
              _passwordField(
                confirm: false,
                label: _view == _AuthView.reset ? 'New password' : 'Password',
              ),
              if (_view != _AuthView.signIn) ...[
                const SizedBox(height: 18),
                _passwordField(
                  confirm: true,
                  label: _view == _AuthView.reset
                      ? 'Confirm new password'
                      : 'Confirm password',
                ),
                const SizedBox(height: 12),
                const Text(
                  'At least 12 characters with uppercase, lowercase, a number and a symbol.',
                  style: TextStyle(fontSize: 12, color: Color(0xff64748b)),
                ),
              ],
              const SizedBox(height: 18),
            ],
            if (_view == _AuthView.signIn) ...[
              CheckboxListTile(
                value: _remember,
                onChanged: _busy
                    ? null
                    : (value) => setState(() => _remember = value ?? false),
                contentPadding: EdgeInsets.zero,
                controlAffinity: ListTileControlAffinity.leading,
                title: const Text(
                  'Remember this device',
                  style: TextStyle(fontSize: 14),
                ),
                subtitle: const Text(
                  'Keep your session in secure storage.',
                  style: TextStyle(fontSize: 12),
                ),
                dense: true,
              ),
              Align(
                alignment: Alignment.centerRight,
                child: TextButton(
                  onPressed: _busy
                      ? null
                      : () => _changeView(_AuthView.forgotPassword),
                  child: const Text('Forgot Password?'),
                ),
              ),
            ],
            const SizedBox(height: 8),
            if (_view != _AuthView.verifyEmail)
              _submitButton(
                switch (_view) {
                  _AuthView.signIn => 'Sign in',
                  _AuthView.ownerSetup =>
                    verifiedOwner
                        ? 'Create business workspace'
                        : 'Send verification email',
                  _AuthView.forgotPassword => 'Send recovery instructions',
                  _AuthView.reset => 'Update password',
                  _ => 'Continue',
                },
                switch (_view) {
                  _AuthView.signIn => _signIn,
                  _AuthView.ownerSetup => _registerOwner,
                  _AuthView.forgotPassword => _requestRecovery,
                  _AuthView.reset => _resetPassword,
                  _ => () async {},
                },
              ),
            if (_view == _AuthView.signIn) ...[
              const SizedBox(height: 20),
              const Text(
                'Need access? Contact your administrator.',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 13, color: Color(0xff64748b)),
              ),
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 20),
                child: Divider(),
              ),
              TextButton(
                onPressed: _busy
                    ? null
                    : () => _changeView(_AuthView.ownerSetup),
                child: const Text('Set up a new business'),
              ),
            ] else if (_view != _AuthView.reset) ...[
              const SizedBox(height: 14),
              TextButton.icon(
                onPressed: _busy ? null : () => _changeView(_AuthView.signIn),
                icon: const Icon(Icons.arrow_back_rounded, size: 18),
                label: const Text('Back to sign in'),
              ),
            ] else ...[
              const SizedBox(height: 14),
              TextButton(
                onPressed: _busy ? null : () => _run(_repository.signOut),
                child: const Text('Cancel and sign out'),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _notConnected(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      const Icon(Icons.cloud_off_rounded, size: 48, color: Color(0xff2563eb)),
      const SizedBox(height: 24),
      _heading(
        context,
        'Not Yet Connected',
        'Connect a Supabase project to sign in and access your business.',
      ),
      const Text(
        'Add the public project URL and client key through runtime configuration. Business data and authentication become available after the backend is deployed.',
        style: TextStyle(height: 1.6, color: Color(0xff64748b)),
      ),
      const SizedBox(height: 28),
      FilledButton.icon(
        onPressed: widget.onPreview,
        icon: const Icon(Icons.visibility_outlined),
        label: const Text('Open design preview'),
      ),
      const SizedBox(height: 12),
      const Text(
        'DESIGN PREVIEW • Read-only layouts with empty business data.',
        textAlign: TextAlign.center,
        style: TextStyle(fontSize: 12, color: Color(0xff64748b)),
      ),
    ],
  );

  Widget _accessContent(BuildContext context) {
    if (_memberships.length > 1) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _heading(
            context,
            'Choose your business',
            'Your verified account belongs to more than one business.',
          ),
          if (_invitations.isNotEmpty || _invitationError != null)
            _invitationBanner(),
          for (final member in _memberships)
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: OutlinedButton(
                onPressed: () => setState(() => _user = member),
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  child: Text(member.businessName),
                ),
              ),
            ),
          TextButton(
            onPressed: _busy ? null : () => _run(_repository.signOut),
            child: const Text('Sign out'),
          ),
        ],
      );
    }
    final identity = _repository.currentIdentity;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _heading(
          context,
          identity?.emailVerified == true
              ? 'Business access needed'
              : 'Verify your email',
          identity?.emailVerified == true
              ? 'No active business membership with an assigned branch is available. Contact your administrator if you are joining an existing business.'
              : 'Check your verification email, then sign in again to continue.',
        ),
        if (_invitationLoading)
          const Padding(
            padding: EdgeInsets.only(bottom: 16),
            child: LinearProgressIndicator(),
          ),
        if (_invitations.isNotEmpty || _invitationError != null)
          _invitationBanner(),
        if (_error != null) _message(context, _error!, error: true),
        if (_canOpenOffline) _offlineEntry(),
        _submitButton('Check access again', _loadMemberships),
        if (identity?.emailVerified == true) ...[
          const SizedBox(height: 12),
          TextButton(
            onPressed: _busy ? null : () => _changeView(_AuthView.ownerSetup),
            child: Text(
              identity?.pendingBusinessName != null
                  ? 'Finish setting up your new business'
                  : 'Set up a separate new business',
            ),
          ),
        ],
        TextButton(
          onPressed: _busy ? null : () => _run(_repository.signOut),
          child: const Text('Sign out'),
        ),
      ],
    );
  }

  Widget _invitationBanner() => Padding(
    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
    child: Wrap(
      crossAxisAlignment: WrapCrossAlignment.center,
      spacing: 12,
      runSpacing: 4,
      children: [
        const Icon(Icons.mail_outline_rounded, size: 20),
        Text(
          _invitationError != null
              ? 'Business invitations could not be checked.'
              : '${_invitations.length} pending business invitation${_invitations.length == 1 ? '' : 's'}',
        ),
        TextButton(
          onPressed: _openInvitations,
          child: const Text('View invitations'),
        ),
        TextButton(
          onPressed: () => setState(() => _invitationsDismissed = true),
          child: const Text('Not now'),
        ),
      ],
    ),
  );

  Widget _invitationContent(BuildContext context) {
    // A stale view cannot present an invitation action during recovery.
    if (_repository.currentIdentity?.emailVerified != true ||
        _repository.hasVerifiedRecoverySession) {
      return _heading(
        context,
        'Verified sign-in required',
        'Sign in with your verified email and finish password recovery before reviewing invitations.',
      );
    }
    final invitation = _selectedInvitation;
    return AutofillGroup(
      child: Form(
        key: _formKey,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _heading(
              context,
              invitation == null
                  ? 'Business invitations'
                  : 'Review your invitation',
              'Access is assigned by your administrator. Accepting an invitation never lets you choose your own role.',
            ),
            if (_error != null) _message(context, _error!, error: true),
            if (_invitationError != null)
              _message(context, _invitationError!, error: true),
            if (_invitationLoading) const LinearProgressIndicator(),
            if (invitation == null) ...[
              if (!_invitationLoading && _invitations.isEmpty)
                const Text(
                  'No pending business invitations for your verified email.',
                ),
              for (final item in _invitations)
                Container(
                  margin: const EdgeInsets.only(bottom: 16),
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    border: Border.all(color: const Color(0xffe3e9f1)),
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Text(
                        item.businessName,
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                      const SizedBox(height: 8),
                      _invitationScope(item),
                      const SizedBox(height: 12),
                      OutlinedButton(
                        onPressed: _busy
                            ? null
                            : () {
                                _password.clear();
                                _confirmation.clear();
                                setState(() {
                                  _selectedInvitation = item;
                                  _error = null;
                                });
                              },
                        child: const Text('Review invitation'),
                      ),
                    ],
                  ),
                ),
              TextButton.icon(
                onPressed: _invitationLoading
                    ? null
                    : () => unawaited(_refreshInvitations()),
                icon: const Icon(Icons.refresh_rounded),
                label: const Text('Refresh invitations'),
              ),
            ] else ...[
              Text(
                invitation.businessName,
                style: Theme.of(context).textTheme.titleLarge,
              ),
              const SizedBox(height: 16),
              _invitationScope(invitation),
              const SizedBox(height: 20),
              if (invitation.requiresPassword) ...[
                const Text(
                  'Create your account password before joining this business. Your password is handled by Supabase Auth.',
                ),
                const SizedBox(height: 20),
                _passwordField(confirm: false, label: 'Create password'),
                const SizedBox(height: 18),
                _passwordField(confirm: true, label: 'Confirm password'),
                const SizedBox(height: 18),
              ] else ...[
                const Text('Your existing account password will be kept.'),
                const SizedBox(height: 20),
              ],
              _submitButton('Accept invitation', _acceptInvitation),
              TextButton(
                onPressed: _busy
                    ? null
                    : () => setState(() => _selectedInvitation = null),
                child: const Text('Back to invitations'),
              ),
            ],
            const SizedBox(height: 12),
            TextButton(
              onPressed: _busy ? null : _closeInvitations,
              child: Text(
                _user != null
                    ? 'Continue to ${_user!.businessName}'
                    : 'Not now — back to business access',
              ),
            ),
            TextButton(
              onPressed: _busy ? null : () => _run(_repository.signOut),
              child: const Text('Sign out'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _invitationScope(PendingEmployeeInvitation invitation) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text('Invited role: ${invitation.role.label}'),
      const SizedBox(height: 6),
      Text(
        invitation.allBranches
            ? 'Branches: All branches (administrator permission)'
            : 'Branches: ${invitation.branchNames.join(', ')}',
      ),
    ],
  );

  Widget _heading(BuildContext context, String title, String subtitle) =>
      Padding(
        padding: const EdgeInsets.only(bottom: 28),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              title,
              style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                fontWeight: FontWeight.w700,
                color: const Color(0xff14233d),
              ),
            ),
            const SizedBox(height: 10),
            Text(
              subtitle,
              style: const TextStyle(color: Color(0xff64748b), height: 1.5),
            ),
          ],
        ),
      );

  Widget _message(BuildContext context, String message, {bool error = false}) =>
      Semantics(
        liveRegion: true,
        child: Container(
          margin: const EdgeInsets.only(bottom: 20),
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: error ? const Color(0xfffff0f0) : const Color(0xffeaf4ff),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Text(
            message,
            style: TextStyle(
              color: error ? const Color(0xffa32828) : const Color(0xff174d85),
              height: 1.5,
            ),
          ),
        ),
      );

  Widget _textField(
    TextEditingController controller,
    String label,
    IconData icon, {
    required String? Function(String?) validator,
    TextInputType? keyboardType,
    Iterable<String>? autofillHints,
    String? helper,
  }) => TextFormField(
    key: ValueKey('$_view:$label'),
    controller: controller,
    validator: validator,
    enabled: !_busy,
    keyboardType: keyboardType,
    autofillHints: autofillHints,
    textInputAction: TextInputAction.next,
    decoration: InputDecoration(
      labelText: label,
      prefixIcon: Icon(icon, size: 20),
      helperText: helper,
      errorMaxLines: 3,
    ),
  );

  Widget _passwordField({required bool confirm, required String label}) =>
      TextFormField(
        key: ValueKey('$_view:$label'),
        controller: confirm ? _confirmation : _password,
        enabled: !_busy,
        obscureText: confirm ? _obscureConfirmation : _obscurePassword,
        enableSuggestions: false,
        autocorrect: false,
        autofillHints: [
          (_view == _AuthView.signIn)
              ? AutofillHints.password
              : AutofillHints.newPassword,
        ],
        textInputAction: confirm || _view == _AuthView.signIn
            ? TextInputAction.done
            : TextInputAction.next,
        onFieldSubmitted: (_) {
          if (_view == _AuthView.signIn) {
            unawaited(_signIn());
          }
          if (_view == _AuthView.reset && confirm) {
            unawaited(_resetPassword());
          }
          if (_view == _AuthView.invitations && confirm) {
            unawaited(_acceptInvitation());
          }
        },
        validator: (value) {
          if (confirm) {
            return value == _password.text ? null : 'Passwords do not match.';
          }
          if (_view == _AuthView.signIn) {
            return (value ?? '').isEmpty ? 'Enter your password.' : null;
          }
          return validateNewPassword(value);
        },
        decoration: InputDecoration(
          labelText: label,
          prefixIcon: const Icon(Icons.lock_outline_rounded, size: 20),
          errorMaxLines: 3,
          suffixIcon: IconButton(
            tooltip: (confirm ? _obscureConfirmation : _obscurePassword)
                ? 'Show password'
                : 'Hide password',
            onPressed: () => setState(() {
              if (confirm) {
                _obscureConfirmation = !_obscureConfirmation;
              } else {
                _obscurePassword = !_obscurePassword;
              }
            }),
            icon: Icon(
              (confirm ? _obscureConfirmation : _obscurePassword)
                  ? Icons.visibility_outlined
                  : Icons.visibility_off_outlined,
              size: 20,
            ),
          ),
        ),
      );

  Widget _submitButton(String label, Future<void> Function() action) =>
      SizedBox(
        height: 52,
        child: FilledButton(
          onPressed: _busy ? null : () => unawaited(action()),
          child: _busy
              ? const SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : Text(label),
        ),
      );
}
