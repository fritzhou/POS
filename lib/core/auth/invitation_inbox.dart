import '../security/app_role.dart';

/// Invitation details are server-owned. They describe proposed access, not an
/// authenticated membership. Accepting the RPC still requires a fresh reload.
class PendingEmployeeInvitation {
  PendingEmployeeInvitation({
    required this.id,
    required this.organizationId,
    required this.businessName,
    required this.fullName,
    required this.role,
    required Set<String> branchIds,
    required List<String> branchNames,
    required this.allBranches,
    required this.requiresPassword,
    required this.expiresAt,
  }) : branchIds = Set.unmodifiable(branchIds),
       branchNames = List.unmodifiable(branchNames);

  final String id;
  final String organizationId;
  final String businessName;
  final String fullName;
  final AppRole role;
  final Set<String> branchIds;
  final List<String> branchNames;
  final bool allBranches;
  final bool requiresPassword;
  final DateTime expiresAt;
}

abstract interface class InvitationInbox {
  Future<List<PendingEmployeeInvitation>> listPending();
  Future<void> accept(
    PendingEmployeeInvitation invitation, {
    String? newPassword,
  });
}

class InvitationFailure implements Exception {
  const InvitationFailure(this.message);
  final String message;

  @override
  String toString() => 'InvitationFailure';
}
