import '../../catalog/domain/repository_support.dart';
import '../../../core/operations/operation_journal.dart';
import 'checkout_models.dart';

abstract interface class CheckoutRepository {
  Future<PosContext> loadContext(String branchId);
  Future<DataPage<PosProduct>> searchProducts({
    required String branchId,
    String query = '',
    String? categoryId,
    PageRequest page = const PageRequest(),
  });
  Future<PosProduct?> lookupProductByBarcode({
    required String branchId,
    required String barcode,
  });
  Future<Shift?> currentShift(String branchId);
  Future<DataPage<Shift>> listShifts({
    String? branchId,
    PageRequest page = const PageRequest(),
  });
  Future<Shift> openShift(OpenShiftRequest request);
  Future<Shift> closeShift(CloseShiftRequest request);
  Future<SaleReceipt> checkout(CheckoutRequest request);
  Future<SaleReceipt?> findSaleByRequest({
    required String branchId,
    required String requestId,
  });
  Future<DataPage<SaleReceipt>> listSales({
    required String branchId,
    PageRequest page = const PageRequest(),
  });
  Future<SaleReceipt> getSale(String saleId);
  Future<SaleReversal> reverseSale(ReversalRequest request);
  Future<CheckoutRequest?> pendingCheckout(String branchId);
  Future<List<PendingOperation>> pendingOperations({String? branchId});
  Future<Object> retryPending(PendingOperation operation);
}
