import '../core/auth/auth_models.dart';
import '../features/offline/domain/offline_workspace.dart';

/// A device-grant resume target, never a freshly verified online membership.
class OfflineResumeCandidate {
  const OfflineResumeCandidate({
    required this.workspace,
    required this.branchId,
    required this.label,
    required this.dispose,
    this.actor,
  });
  final OfflineWorkspace workspace;
  final String branchId, label;
  final Future<void> Function() dispose;
  final AuthenticatedUser? actor;
}

typedef OfflineResumeFactory =
    Future<List<OfflineResumeCandidate>> Function(AuthIdentity identity);
typedef OfflineIdentityLock = Future<void> Function(String actorId);
typedef OfflineMembershipReconciler =
    Future<void> Function(
      AuthIdentity identity,
      List<AuthenticatedUser> memberships,
    );
