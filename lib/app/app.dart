import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/auth/auth_models.dart';
import '../core/auth/auth_repository.dart';
import '../core/auth/invitation_inbox.dart';
import '../features/authentication/presentation/auth_gate.dart';
import '../features/authentication/presentation/membership_mfa_gate.dart';
import '../core/security/access_lock.dart';
import '../core/security/session_security_repository.dart';
import '../core/security/session_lock_guard.dart';
import '../features/offline/domain/offline_workspace.dart';
import '../features/offline/presentation/offline_workspace_page.dart';
import '../features/receipts/presentation/receipt_output_scope.dart';
import 'business_services.dart';
import 'offline_services.dart';
import 'config/app_brand.dart';
import 'shell/nexa_shell.dart';
import 'theme/app_theme.dart';

final authRepositoryProvider = Provider<AuthRepository>(
  (ref) => const NotConfiguredAuthRepository(),
);
final invitationInboxProvider = Provider<InvitationInbox?>((ref) => null);
final businessServicesFactoryProvider = Provider<BusinessServicesFactory?>(
  (ref) => null,
);
final offlineResumeFactoryProvider = Provider<OfflineResumeFactory?>(
  (ref) => null,
);
final offlineIdentityLockProvider = Provider<OfflineIdentityLock?>(
  (ref) => null,
);
final offlineMembershipReconcilerProvider =
    Provider<OfflineMembershipReconciler?>((ref) => null);
final accessLockProvider = Provider<AccessLock>((ref) {
  final access = AccessLock();
  ref.onDispose(access.dispose);
  return access;
});
final sessionSecurityProvider = Provider<SessionSecurityRepository?>(
  (ref) => null,
);

class NexaApp extends ConsumerStatefulWidget {
  const NexaApp({this.startupNotice, super.key});
  final String? startupNotice;

  @override
  ConsumerState<NexaApp> createState() => _NexaAppState();
}

class _NexaAppState extends ConsumerState<NexaApp> {
  bool _preview = false;
  bool _signingOut = false;
  BusinessServices? _services;
  BusinessServicesFactory? _servicesFactory;
  String? _servicesScope;
  final _messengerKey = GlobalKey<ScaffoldMessengerState>();
  final _navigatorKey = GlobalKey<NavigatorState>();
  AuthRepository? _observedRepository;
  StreamSubscription<AuthSessionEvent>? _authSubscription;
  String? _observedActorId;
  OfflineWorkspace? _offline;
  OfflineResumeCandidate? _resumeCandidate;
  final _offlineDeniedActors = <String>{};
  final _invalidatingActors = <String>{};
  AuthenticatedUser? _activeMember;
  int _securityRevision = 0;
  int _membershipRevision = 0;

  void _invalidateInBackground(String? actorId) {
    unawaited(
      _invalidateOffline(actorId).catchError((Object error) {
        _messengerKey.currentState?.showSnackBar(
          const SnackBar(
            content: Text(
              'Offline access is blocked. Device cleanup could not be confirmed; connect to review the stored workspace.',
            ),
          ),
        );
      }),
    );
  }

  void _observe(AuthRepository repository) {
    if (_observedRepository == repository) return;
    unawaited(_authSubscription?.cancel());
    _observedRepository = repository;
    _observedActorId = repository.currentIdentity?.userId;
    _authSubscription = repository.events.listen(
      (event) {
        final previousActor = _observedActorId;
        _observedActorId = event.identity?.userId;
        if (event.type == AuthSessionEventType.signedOut ||
            repository.hasVerifiedRecoverySession ||
            (previousActor != null && previousActor != _observedActorId)) {
          _invalidateInBackground(previousActor);
        }
        if (mounted) setState(() => _securityRevision++);
      },
      onError: (Object error, StackTrace stack) {
        if (error is AuthFailure &&
            error.kind == AuthFailureKind.authorization) {
          _invalidateInBackground(_observedActorId);
        }
      },
    );
  }

  Future<void> _invalidateOffline(String? actorId) async {
    if (actorId != null) {
      _offlineDeniedActors.add(actorId);
      _invalidatingActors.add(actorId);
    }
    final workspace = _offline;
    final candidate = _resumeCandidate;
    final services = _services;
    final lockIdentity = ref.read(offlineIdentityLockProvider);
    _offline = null;
    _resumeCandidate = null;
    _services = null;
    _servicesScope = null;
    _servicesFactory = null;
    _activeMember = null;
    if (mounted) {
      _navigatorKey.currentState?.popUntil((route) => route.isFirst);
      setState(() {});
    }
    Object? cleanupFailure;
    Future<void> attempt(Future<void> Function() operation) async {
      try {
        await operation();
      } on Object catch (error) {
        cleanupFailure ??= error;
      }
    }

    try {
      if (workspace != null) await attempt(workspace.suspend);
      if (services?.offline != null && services!.offline != workspace) {
        await attempt(services.offline!.suspend);
      }
      if (actorId != null && lockIdentity != null) {
        await attempt(() => lockIdentity(actorId));
      }
      if (candidate != null) await attempt(candidate.dispose);
      if (services != null) await attempt(services.dispose);
    } finally {
      _invalidatingActors.remove(actorId);
    }
    if (cleanupFailure != null) {
      throw const AuthFailure(
        'Offline access is blocked. Device cleanup could not be confirmed; connect to review the stored workspace.',
      );
    }
  }

  bool _sameIdentity(AuthIdentity identity) {
    final repository = ref.read(authRepositoryProvider);
    return repository.currentIdentity?.userId == identity.userId &&
        repository.currentIdentity?.emailVerified == true &&
        !repository.hasVerifiedRecoverySession &&
        !_offlineDeniedActors.contains(identity.userId);
  }

  Future<void> _resumeOffline(AuthIdentity identity) async {
    final factory = ref.read(offlineResumeFactoryProvider);
    if (factory == null || !_sameIdentity(identity)) return;
    final candidates = await factory(identity);
    OfflineResumeCandidate? selected;
    try {
      if (!mounted || !_sameIdentity(identity)) return;
      if (candidates.isEmpty) {
        throw const AuthFailure(
          'No complete authorized offline workspace is stored for this account. Connect to prepare this device.',
        );
      }
      if (candidates.length == 1) {
        selected = candidates.single;
      } else {
        selected = await showDialog<OfflineResumeCandidate>(
          context: _navigatorKey.currentContext!,
          builder: (context) => SimpleDialog(
            title: const Text('Choose an authorized offline workspace'),
            children: [
              for (final candidate in candidates)
                SimpleDialogOption(
                  onPressed: () => Navigator.pop(context, candidate),
                  child: Text(candidate.label),
                ),
            ],
          ),
        );
      }
      if (selected == null || !mounted || !_sameIdentity(identity)) {
        selected = null;
        return;
      }
      setState(() {
        _offline = selected!.workspace;
        _resumeCandidate = selected;
        _activeMember = selected.actor;
      });
    } finally {
      for (final candidate in candidates) {
        if (candidate != selected) await candidate.dispose();
      }
    }
  }

  void _openOnlineOfflineWorkspace() {
    final repository = ref.read(authRepositoryProvider);
    if (repository.currentIdentity?.emailVerified != true ||
        repository.hasVerifiedRecoverySession ||
        _offlineDeniedActors.contains(repository.currentIdentity?.userId) ||
        _services?.offline == null) {
      return;
    }
    setState(() => _offline = _services!.offline);
  }

  Future<void> _leaveOffline() async {
    final workspace = _offline;
    final candidate = _resumeCandidate;
    await workspace?.leaveOffline();
    if (!mounted || _offline != workspace) return;
    setState(() {
      _offline = null;
      _resumeCandidate = null;
    });
    await candidate?.dispose();
  }

  Future<void> _signOut() async {
    if (_signingOut) return;
    _signingOut = true;
    try {
      final repository = ref.read(authRepositoryProvider);
      try {
        await _invalidateOffline(repository.currentIdentity?.userId);
      } finally {
        await repository.signOut();
      }
      await _services?.dispose();
      _services = null;
      _servicesScope = null;
      _servicesFactory = null;
    } on AuthFailure catch (error) {
      _messengerKey.currentState?.showSnackBar(
        SnackBar(content: Text(error.message)),
      );
    } on Object {
      _messengerKey.currentState?.showSnackBar(
        const SnackBar(
          content: Text('Sign out could not complete. Try again.'),
        ),
      );
    } finally {
      _signingOut = false;
    }
  }

  BusinessServices? _forMembership(
    AuthenticatedUser user,
    BusinessServicesFactory? factory,
  ) {
    if (factory == null) return null;
    _activeMember = user;
    if (!_signingOut && !_invalidatingActors.contains(user.userId)) {
      _offlineDeniedActors.remove(user.userId);
    }
    final branches = user.branchIds.toList()..sort();
    final scope = [
      user.userId,
      user.organizationId,
      user.membershipId,
      user.role.name,
      user.allBranches.toString(),
      ...branches,
    ].join(':');
    if (_servicesScope != scope || _servicesFactory != factory) {
      unawaited(_services?.dispose());
      _services = factory(user);
      _servicesScope = scope;
      _servicesFactory = factory;
    }
    return _services;
  }

  Future<void> _verifyUnlock(String password) async {
    final sessionSecurity = ref.read(sessionSecurityProvider);
    final auth = ref.read(authRepositoryProvider);
    final member = _activeMember;
    final actorId = auth.currentIdentity?.userId;
    if (sessionSecurity == null || actorId == null) {
      throw const AuthFailure('Connect and sign in again to unlock.');
    }
    await sessionSecurity.verifyCurrentPassword(password);
    final memberships = await auth.loadMemberships();
    if (auth.currentIdentity?.userId != actorId ||
        auth.hasVerifiedRecoverySession ||
        memberships.isEmpty) {
      throw const AuthFailure(
        'Active business access could not be verified. Sign in again.',
      );
    }
    final identity = auth.currentIdentity!;
    await ref
        .read(offlineMembershipReconcilerProvider)
        ?.call(identity, memberships);
    if (_offline != null && member == null) {
      throw const AuthFailure(
        'Connect and sign in again to verify this offline scope.',
      );
    }
    if (member != null &&
        !memberships.any(
          (current) =>
              current.membershipId == member.membershipId &&
              current.organizationId == member.organizationId &&
              current.role == member.role &&
              current.branchIds.length == member.branchIds.length &&
              current.branchIds.containsAll(member.branchIds),
        )) {
      throw const AuthFailure(
        'Business access changed. Sign out and sign in again.',
      );
    }
    if (mounted) setState(() => _securityRevision++);
  }

  Future<void> _signOutAllSessions() async {
    final security = ref.read(sessionSecurityProvider);
    if (security == null) return;
    ref.read(accessLockProvider).lock();
    final actorId = ref.read(authRepositoryProvider).currentIdentity?.userId;
    try {
      await security.signOutAllSessions();
      await _invalidateOffline(actorId);
    } on Object {
      _messengerKey.currentState?.showSnackBar(
        const SnackBar(
          content: Text(
            'Account session revocation could not be fully confirmed. Connect and review your sessions.',
          ),
        ),
      );
    }
  }

  Widget _membershipWorkspace(
    BuildContext context,
    AuthenticatedUser user,
    BusinessServicesFactory? factory,
  ) {
    final services = _forMembership(user, factory);
    final shell = NexaShell(
      key: ValueKey('${user.organizationId}:${user.membershipId}'),
      isPreview: false,
      services: services,
      membershipId: user.membershipId,
      currentUserId: user.userId,
      role: user.role,
      businessName: user.businessName,
      userName: user.email,
      onSignOut: _signOut,
      onScopeChanged: () async {
        if (!mounted ||
            ref.read(authRepositoryProvider).currentIdentity?.userId !=
                user.userId) {
          throw const AuthFailure("Sign in again to refresh business access.");
        }
        _navigatorKey.currentState?.popUntil((route) => route.isFirst);
        setState(() => _membershipRevision++);
      },
      onLock: () => ref.read(accessLockProvider).lock(),
      onSignOutAllSessions: ref.read(sessionSecurityProvider) == null
          ? null
          : _signOutAllSessions,
      onSecurityPolicyChanged: (policy) {
        ref.read(accessLockProvider).setIdleMinutes(policy.idleLockMinutes);
        setState(() => _securityRevision++);
      },
      onOpenOffline: services?.offline == null
          ? null
          : _openOnlineOfflineWorkspace,
    );
    if (services?.security == null || services?.mfa == null) return shell;
    return MembershipMfaGate(
      actor: user,
      securityRepository: services!.security!,
      mfaRepository: services.mfa!,
      onSignOut: _signOut,
      refreshToken: _securityRevision,
      onPolicyLoaded: (policy) =>
          ref.read(accessLockProvider).setIdleMinutes(policy.idleLockMinutes),
      onAccessBlocked: () {
        _navigatorKey.currentState?.popUntil((route) => route.isFirst);
      },
      child: shell,
    );
  }

  @override
  void dispose() {
    unawaited(_authSubscription?.cancel());
    unawaited(_resumeCandidate?.dispose());
    unawaited(_services?.dispose());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final repository = ref.watch(authRepositoryProvider);
    _observe(repository);
    final invitations = ref.watch(invitationInboxProvider);
    final servicesFactory = ref.watch(businessServicesFactoryProvider);
    return MaterialApp(
      title: AppBrand.appName,
      theme: AppTheme.light,
      debugShowCheckedModeBanner: false,
      scaffoldMessengerKey: _messengerKey,
      navigatorKey: _navigatorKey,
      builder: (context, child) => Column(
        children: [
          if (widget.startupNotice != null)
            Material(
              color: const Color(0xfffff4dd),
              child: SafeArea(
                bottom: false,
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Text(
                    widget.startupNotice!,
                    textAlign: TextAlign.center,
                  ),
                ),
              ),
            ),
          Expanded(
            child: SessionLockGuard(
              access: ref.watch(accessLockProvider),
              actorId: repository.hasVerifiedRecoverySession || _preview
                  ? null
                  : repository.currentIdentity?.userId,
              onVerifyPassword: ref.watch(sessionSecurityProvider) == null
                  ? null
                  : _verifyUnlock,
              onSignOut: () => unawaited(_signOut()),
              child: ReceiptOutputScope(
                identity: (
                  repository,
                  _offline,
                  _membershipRevision,
                  _securityRevision,
                  _preview,
                ),
                access: ref.watch(accessLockProvider),
                currentIdentity: () => (
                  _activeMember,
                  _offline,
                  repository.currentIdentity?.userId,
                  _membershipRevision,
                  _securityRevision,
                ),
                isAllowed: () =>
                    mounted &&
                    !_preview &&
                    !repository.hasVerifiedRecoverySession &&
                    repository.currentIdentity?.emailVerified == true &&
                    repository.currentIdentity?.userId ==
                        _activeMember?.userId &&
                    _activeMember != null &&
                    !_offlineDeniedActors.contains(_activeMember?.userId),
                child: child ?? const SizedBox.shrink(),
              ),
            ),
          ),
        ],
      ),
      home: _offline != null
          ? OfflineWorkspacePage(
              key: ValueKey(_offline),
              workspace: _offline!,
              initialBranchId: _resumeCandidate?.branchId,
              peopleRepository: _resumeCandidate == null
                  ? _services?.people
                  : null,
              onLeave: () => unawaited(_leaveOffline()),
              onLock: () => unawaited(_signOut()),
            )
          : _preview
          ? NexaShell(
              isPreview: true,
              onSignOut: () => setState(() => _preview = false),
            )
          : AuthGate(
              key: ValueKey(_membershipRevision),
              repository: repository,
              invitationInbox: invitations,
              appName: AppBrand.appName,
              tagline: AppBrand.tagline,
              onPreview: () => setState(() => _preview = true),
              onOpenOffline: ref.watch(offlineResumeFactoryProvider) == null
                  ? null
                  : _resumeOffline,
              onAuthorizationInvalidated: (identity) =>
                  _invalidateOffline(identity.userId),
              onMembershipsVerified: ref.watch(
                offlineMembershipReconcilerProvider,
              ),
              authenticatedBuilder: (context, user) =>
                  _membershipWorkspace(context, user, servicesFactory),
            ),
    );
  }
}
