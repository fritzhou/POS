import '../../../core/operations/operation_journal.dart';
import '../../catalog/domain/repository_support.dart';
import 'purchase_models.dart';

abstract interface class PurchaseRepository {
  Future<PurchaseContext> context(String branchId);
  Future<DataPage<PurchaseOrderSummary>> listOrders({
    required String branchId,
    PurchaseOrderStatus? status,
    String query = '',
    PageRequest page = const PageRequest(),
  });
  Future<PurchaseOrder> getOrder({
    required String branchId,
    required String orderId,
  });
  Future<DataPage<PurchaseReceiptSummary>> listReceipts({
    required String branchId,
    required String orderId,
    PageRequest page = const PageRequest(),
  });
  Future<PurchaseReceipt> getReceipt({
    required String branchId,
    required String receiptId,
  });
  Future<PurchaseMutationResult> create(CreatePurchaseRequest request);
  Future<PurchaseMutationResult> receive(ReceivePurchaseRequest request);
  Future<PurchaseMutationResult> cancelRemaining(CancelPurchaseRequest request);
  Future<List<PendingOperation>> pendingMutations({String? branchId});
  Future<PurchaseMutationResult> retryPending(PendingOperation operation);
}
