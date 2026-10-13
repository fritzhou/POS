import 'package:supabase_flutter/supabase_flutter.dart';

import '../security/app_role.dart';
import 'auth_repository.dart';
import 'invitation_inbox.dart';

class SupabaseInvitationInbox implements InvitationInbox {
  SupabaseInvitationInbox({
    required this.client,
    required AuthRepository authRepository,
  }) : _auth = authRepository;

  final SupabaseClient client;
  final AuthRepository _auth;

  void _requireEligibleSession() {
    final identity = _auth.currentIdentity;
    if (_auth.hasVerifiedRecoverySession) {
      throw const InvitationFailure(
        'Finish password recovery before accepting a business invitation.',
      );
    }
    if (identity?.emailVerified != true ||
        client.auth.currentSession == null ||
        identity?.userId != client.auth.currentUser?.id) {
      throw const InvitationFailure(
        'Sign in with your verified email to view business invitations.',
      );
    }
  }

  Future<T> _safe<T>(Future<T> Function() action) async {
    try {
      return await action();
    } on InvitationFailure {
      rethrow;
    } on PostgrestException catch (error) {
      if (error.code == '22023' || error.code == 'P0002') {
        throw const InvitationFailure(
          'This invitation is no longer available. Ask your administrator for a new invitation.',
        );
      }
      if (error.code == '42501') {
        throw const InvitationFailure(
          'This account cannot accept that invitation. Contact your administrator.',
        );
      }
      throw const InvitationFailure(
        'Business invitations are temporarily unavailable. Try again shortly.',
      );
    } on AuthException catch (error) {
      if (error.code == 'weak_password') {
        throw const InvitationFailure(
          'Choose a stronger password and try again.',
        );
      }
      throw const InvitationFailure(
        'Your password could not be updated. Try again shortly.',
      );
    } on Object {
      throw const InvitationFailure(
        'Business invitations are temporarily unavailable. Try again shortly.',
      );
    }
  }

  @override
  Future<List<PendingEmployeeInvitation>> listPending() => _safe(() async {
    _requireEligibleSession();
    final response = await client.rpc('list_pending_invitations');
    if (response is! List) {
      throw const InvitationFailure(
        'Business invitations could not be loaded.',
      );
    }
    return response.map((raw) {
      final row = Map<String, dynamic>.from(raw as Map);
      final branchNames = row['branch_names'];
      return PendingEmployeeInvitation(
        id: (row['invitation_id'] ?? row['id']) as String,
        organizationId: row['organization_id'] as String,
        businessName: row['business_name'] as String,
        fullName: row['full_name'] as String,
        role: AppRole.fromDatabase(row['requested_role'] as String),
        branchIds: (row['branch_ids'] as List).cast<String>().toSet(),
        branchNames: branchNames is List
            ? branchNames.cast<String>()
            : [if (row['branch_name'] is String) row['branch_name'] as String],
        allBranches: row['all_branches'] == true,
        // Missing password policy never becomes permission to skip setup.
        requiresPassword: row['requires_password'] != false,
        expiresAt: DateTime.parse(row['expires_at'] as String),
      );
    }).toList();
  });

  @override
  Future<void> accept(
    PendingEmployeeInvitation invitation, {
    String? newPassword,
  }) => _safe(() async {
    _requireEligibleSession();
    final identityId = _auth.currentIdentity!.userId;
    if (invitation.requiresPassword &&
        (newPassword == null || newPassword.isEmpty)) {
      throw const InvitationFailure(
        'Create and confirm your account password before accepting this invitation.',
      );
    }
    if (newPassword != null) {
      await client.auth.updateUser(UserAttributes(password: newPassword));
    }
    // A recovery callback or account switch during password update must not
    // grant access using the invitation action that was started previously.
    _requireEligibleSession();
    if (_auth.currentIdentity!.userId != identityId) {
      throw const InvitationFailure(
        'Your account changed. Sign in and try again.',
      );
    }
    // Server resolves recipient, role, branches, expiry and membership. No
    // client role, branch selection or user ID is sent to this boundary.
    await client.rpc(
      'accept_employee_invitation',
      params: {'p_invitation_id': invitation.id},
    );
  });
}
