import '../../../core/operations/operation_journal.dart';
import '../../administration/domain/administration_models.dart';
import '../../catalog/domain/repository_support.dart';
import 'invitation_models.dart';

abstract interface class InvitationAdministrationRepository {
  String get organizationId;
  Set<String> get branchIds;
  Future<DataPage<ManagedInvitation>> listInvitations({
    InvitationFilter filter = const InvitationFilter(),
    PageRequest page = const PageRequest(),
  });
  Future<ManagedInvitation> invitation(String invitationId);
  Future<InvitationRevocation> revoke({
    required ManagedInvitation original,
    required String reason,
    required String requestId,
  });
  Future<List<PendingOperation>> pending();
  Future<InvitationRevocation> retry(PendingOperation operation);
  Future<InvitationDelivery> retryDelivery(ManagedInvitation original);
}
