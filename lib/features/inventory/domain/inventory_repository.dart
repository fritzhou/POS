import '../../catalog/domain/repository_support.dart';
import '../../checkout/domain/checkout_models.dart';
import 'inventory_models.dart';
import '../../../core/operations/operation_journal.dart';

abstract interface class InventoryRepository {
  Future<DataPage<PosProduct>> listBalances({
    required String branchId,
    String query = '',
    PageRequest page = const PageRequest(),
  });
  Future<DataPage<StockMovement>> listMovements({
    required String branchId,
    String? productId,
    PageRequest page = const PageRequest(),
  });
  Future<StockOperation> receiveStock(ReceiveStockRequest request);
  Future<StockOperation> adjustStock(AdjustStockRequest request);
  Future<List<PendingOperation>> pendingOperations({String? branchId});
  Future<StockOperation> retryPending(PendingOperation operation);
}
