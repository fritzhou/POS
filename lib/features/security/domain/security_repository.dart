import '../../catalog/domain/repository_support.dart';
import 'security_models.dart';

abstract interface class SecurityRepository {
  String get organizationId;
  Set<String> get branchIds;
  Future<SecurityPolicy> loadPolicy();
  Future<DataPage<SecurityDevice>> listDevices({
    required String branchId,
    PageRequest page = const PageRequest(),
  });
  Future<DataPage<SecurityOfflineGrant>> listGrants({
    required String branchId,
    PageRequest page = const PageRequest(),
  });
  Future<DataPage<SecurityNotice>> listNotices({
    required String branchId,
    PageRequest page = const PageRequest(),
  });
  Future<SecurityMutationResult> mutate(SecurityMutation mutation);
  Future<List<SecurityMutation>> pendingMutations();
  Future<DateTime> markNoticeRead({
    required String branchId,
    required String noticeId,
  });
}
