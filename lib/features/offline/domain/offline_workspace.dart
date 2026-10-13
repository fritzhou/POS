import '../../../core/database/sale_draft.dart';
import '../../../core/sync/outbox_state.dart';
import '../../catalog/domain/repository_support.dart';
import '../../checkout/domain/checkout_models.dart';

/// Explicit grant-backed device workspace. Online checkout semantics stay in
/// CheckoutRepository; losing a connection never enters this workspace.
abstract interface class OfflineWorkspace {
  Future<OfflineWorkspaceStatus> status({String? branchId});
  Future<OfflineWorkspaceStatus> prepareOnline(String branchId);
  Future<OfflineWorkspaceStatus> enterOffline(String branchId);
  Future<void> leaveOffline();
  Future<PosContext> context();
  Future<Shift?> currentShift();
  Future<List<OfflineCategory>> categories();
  Future<DataPage<PosProduct>> searchProducts({
    String query = '',
    String? categoryId,
    PageRequest page = const PageRequest(),
  });
  Future<PosProduct?> lookupProductByBarcode(String barcode);
  Future<LocalOfflineReceipt> checkout(OfflineCheckoutRequest request);

  /// Append confirmed physical/manual tender before displaying it as saved.
  /// Retrying the same index must retain exactly the original evidence.
  Future<void> recordPaymentFragment({
    required String requestId,
    required List<CartLine> lines,
    required int index,
    required CheckoutPayment payment,
  });
  Future<List<LocalOfflineReceipt>> listReceipts({String? branchId});
  Future<List<OfflineCheckoutRequest>> pendingPaymentIntents({
    String? branchId,
  });
  Future<String> exportReceipt(String eventId);
  Future<OfflineSyncSummary> synchronize(String branchId);
  Future<bool> retryFailed({required String branchId, required String eventId});
  Future<OfflineWorkspaceStatus> releaseGrant(String branchId);
  Future<void> suspend();
}

class OfflineWorkspaceStatus {
  const OfflineWorkspaceStatus({
    required this.configured,
    required this.active,
    required this.pendingCount,
    required this.failedCount,
    this.branchId,
    this.branchName,
    this.grantId,
    this.expiresAt,
    this.lastServerTime,
    this.estimatedServerTime,
    this.snapshotAt,
    this.lastSyncAt,
    this.eventCount = 0,
    this.unresolvedPaymentCount = 0,
    this.totalMinor = 0,
    this.maxEvents = 1000,
    this.maxTotalMinor = 100000000,
    this.released = false,
    this.blockedReason,
  });
  final bool configured, active, released;
  final int pendingCount, failedCount, eventCount, totalMinor;
  final int unresolvedPaymentCount;
  final int maxEvents, maxTotalMinor;
  final String? branchId, branchName, grantId, blockedReason;
  final DateTime? expiresAt, lastServerTime, snapshotAt, lastSyncAt;
  final DateTime? estimatedServerTime;
  bool get prepared => grantId != null && !released;
}

class OfflineCategory {
  const OfflineCategory({required this.id, required this.name});
  final String id, name;
}

/// Freeze the intent once after the operator confirms tender. A caller retains
/// this object on uncertainty, including its request ID, instead of paying twice.
class OfflineCheckoutRequest {
  OfflineCheckoutRequest({
    required this.requestId,
    required List<CartLine> lines,
    required List<CheckoutPayment> payments,
    this.expectedTotalMinor,
  }) : lines = List.unmodifiable(lines),
       payments = List.unmodifiable(payments);
  final String requestId;
  final List<CartLine> lines;
  final List<CheckoutPayment> payments;
  final int? expectedTotalMinor;
  bool get partial =>
      expectedTotalMinor != null &&
      payments.fold<int>(0, (total, payment) => total + payment.amountMinor) <
          expectedTotalMinor!;
}

/// The paid local snapshot remains provisional even after a server link arrives.
/// It is deliberately a different type from an authoritative SaleReceipt.
class LocalOfflineReceipt {
  const LocalOfflineReceipt({
    required this.draft,
    required this.status,
    required this.sequence,
    required this.grantId,
    this.serverReceiptId,
    this.failureCode,
    this.reconciliationCode,
    this.acceptedAt,
    this.businessName,
    this.branchName,
  });
  final SaleDraft draft;
  final OutboxStatus status;
  final int sequence;
  final String grantId;
  final String? serverReceiptId, failureCode, reconciliationCode;
  final String? businessName, branchName;
  final DateTime? acceptedAt;
}

class OfflineSyncSummary {
  const OfflineSyncSummary({
    required this.accepted,
    required this.failed,
    required this.remaining,
    required this.pulled,
    this.stoppedReason,
  });
  final int accepted, failed, remaining, pulled;
  final String? stoppedReason;
}
