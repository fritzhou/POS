import 'package:uuid/uuid.dart';

import '../../catalog/domain/repository_support.dart';
import '../../checkout/domain/checkout_models.dart';

class StockMovement {
  const StockMovement({
    required this.id,
    required this.productId,
    required this.quantityDelta,
    required this.balanceAfter,
    required this.createdAt,
    this.branchId,
    this.productName,
    this.sku,
    this.kind,
    this.reason,
    this.actorUserId,
    this.sourceId,
  });
  final String id, productId;
  final int quantityDelta, balanceAfter;
  final DateTime createdAt;
  final String? branchId, productName, sku, kind, reason, actorUserId, sourceId;
}

class StockOperation {
  StockOperation({
    required this.id,
    required this.organizationId,
    required this.branchId,
    required this.actorUserId,
    required this.kind,
    required this.createdAt,
    required this.reason,
    required List<StockMovement> movements,
    this.reference,
    this.supplierId,
  }) : movements = List.unmodifiable(movements);
  final String id, organizationId, branchId, actorUserId, kind, reason;
  final DateTime createdAt;
  final String? reference, supplierId;
  final List<StockMovement> movements;
}

class StockReceiptItem {
  const StockReceiptItem({
    required this.productId,
    required this.quantity,
    required this.expectedRevision,
    this.unitCostMinor,
  });
  final String productId;
  final int quantity, expectedRevision;
  final int? unitCostMinor;
  Map<String, dynamic> validatedValues() => {
    'product_id': validateId(productId),
    'quantity': wholeQuantity(quantity),
    'expected_revision': validateRevision(expectedRevision),
    if (unitCostMinor != null) 'unit_cost_minor': validateMinor(unitCostMinor!),
  };
}

class ReceiveStockRequest {
  ReceiveStockRequest({
    required this.branchId,
    required List<StockReceiptItem> items,
    required this.reason,
    String? requestId,
    this.supplierId,
    this.reference,
  }) : requestId = requestId ?? const Uuid().v4(),
       items = List.unmodifiable(items);
  final String requestId, branchId, reason;
  final String? supplierId, reference;
  final List<StockReceiptItem> items;
}

class AdjustStockRequest {
  AdjustStockRequest({
    required this.branchId,
    required this.productId,
    required this.deltaQuantity,
    required this.reason,
    String? requestId,
  }) : requestId = requestId ?? const Uuid().v4();
  final String requestId, branchId, productId, reason;
  final int deltaQuantity;
}

int signedQuantity(int value) {
  if (value == 0 || BigInt.from(value).abs() > BigInt.from(1000000)) {
    throw const RepositoryFailure(
      RepositoryFailureType.validation,
      'Enter a nonzero whole-unit stock adjustment.',
    );
  }
  return value;
}
