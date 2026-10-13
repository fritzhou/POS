import 'package:uuid/uuid.dart';

import '../../catalog/domain/repository_support.dart';

const purchaseMaximumInteger = 9007199254740991;
const purchaseCurrencies = {'PHP', 'USD', 'EUR', 'GBP', 'AUD', 'CAD', 'SGD'};

int purchaseAmount(int value) => validateMinor(value);
int purchaseQuantity(int value, {bool allowZero = false}) {
  if (value < (allowZero ? 0 : 1) || value > 1000000) {
    throw const RepositoryFailure(
      RepositoryFailureType.validation,
      'Enter whole-unit quantities between 1 and 1,000,000.',
    );
  }
  return value;
}

int purchaseRevision(int value) {
  if (value < 1 || value > purchaseMaximumInteger) {
    throw const RepositoryFailure(
      RepositoryFailureType.validation,
      'Reload this record before saving.',
    );
  }
  return value;
}

String purchaseCurrency(String value) {
  if (!purchaseCurrencies.contains(value)) {
    throw const RepositoryFailure(
      RepositoryFailureType.validation,
      'Choose a supported two-decimal currency.',
    );
  }
  return value;
}

int purchaseLineCost(int quantity, int unitCost) {
  purchaseQuantity(quantity, allowZero: true);
  purchaseAmount(unitCost);
  final total = BigInt.from(quantity) * BigInt.from(unitCost);
  if (total > BigInt.from(purchaseMaximumInteger)) {
    throw const RepositoryFailure(
      RepositoryFailureType.validation,
      'The purchase cost is too large. Reduce its quantity or unit cost.',
    );
  }
  return total.toInt();
}

int purchaseTotal(Iterable<int> amounts) {
  final total = amounts.fold<BigInt>(
    BigInt.zero,
    (sum, value) => sum + BigInt.from(purchaseAmount(value)),
  );
  if (total > BigInt.from(purchaseMaximumInteger)) {
    throw const RepositoryFailure(
      RepositoryFailureType.validation,
      'The purchase total is too large.',
    );
  }
  return total.toInt();
}

enum PurchaseOrderStatus {
  ordered('ordered', 'Ordered'),
  partiallyReceived('partially_received', 'Partially received'),
  received('received', 'Received'),
  cancelled('cancelled', 'Remaining quantities cancelled');

  const PurchaseOrderStatus(this.wire, this.label);
  final String wire, label;
  bool get closed => this == received || this == cancelled;
  static PurchaseOrderStatus fromWire(String value) => values.firstWhere(
    (status) => status.wire == value,
    orElse: () => throw const FormatException('Unexpected order status'),
  );
}

class PurchaseContext {
  const PurchaseContext({
    required this.organizationId,
    required this.branchId,
    required this.branchName,
    required this.currency,
    required this.settingsRevision,
  });
  final String organizationId, branchId, branchName, currency;
  final int settingsRevision;
}

class PurchaseOrderSummary {
  const PurchaseOrderSummary({
    required this.id,
    required this.organizationId,
    required this.branchId,
    required this.supplierId,
    required this.supplierName,
    required this.currency,
    required this.createdBy,
    required this.createdAt,
    required this.orderedTotalMinor,
    required this.receivedTotalMinor,
    required this.revision,
    required this.status,
    required this.lineCount,
    this.reference,
  });
  final String id,
      organizationId,
      branchId,
      supplierId,
      supplierName,
      currency,
      createdBy;
  final DateTime createdAt;
  final int orderedTotalMinor, receivedTotalMinor, revision, lineCount;
  final PurchaseOrderStatus status;
  final String? reference;
}

class PurchaseOrderItem {
  const PurchaseOrderItem({
    required this.id,
    required this.productId,
    required this.productName,
    required this.sku,
    required this.unit,
    required this.productRevision,
    required this.currentProductRevision,
    required this.currentProductActive,
    required this.currentProductName,
    required this.currentSku,
    required this.currentUnit,
    required this.currentCurrency,
    required this.orderedQuantity,
    required this.receivedQuantity,
    required this.cancelledQuantity,
    required this.remainingQuantity,
    required this.unitCostMinor,
    required this.lineCostMinor,
  });
  final String id,
      productId,
      productName,
      sku,
      unit,
      currentProductName,
      currentSku,
      currentUnit,
      currentCurrency;
  final int currentProductRevision;
  final bool currentProductActive;
  final int productRevision,
      orderedQuantity,
      receivedQuantity,
      cancelledQuantity,
      remainingQuantity,
      unitCostMinor,
      lineCostMinor;
}

class PurchaseOrder {
  PurchaseOrder({
    required this.summary,
    required this.reason,
    required this.supplierRevision,
    required this.settingsRevision,
    required this.receiptCount,
    required List<PurchaseOrderItem> items,
    this.cancellation,
  }) : items = List.unmodifiable(items);
  final PurchaseOrderSummary summary;
  final String reason;
  final int supplierRevision, settingsRevision, receiptCount;
  final List<PurchaseOrderItem> items;
  final PurchaseCancellation? cancellation;
}

class PurchaseReceiptSummary {
  const PurchaseReceiptSummary({
    required this.id,
    required this.organizationId,
    required this.branchId,
    required this.orderId,
    required this.operationId,
    required this.receivedBy,
    required this.receivedAt,
    required this.currency,
    required this.receivedTotalMinor,
    required this.orderRevision,
    this.reference,
  });
  final String id,
      organizationId,
      branchId,
      orderId,
      operationId,
      receivedBy,
      currency;
  final DateTime receivedAt;
  final int receivedTotalMinor, orderRevision;
  final String? reference;
}

class PurchaseReceiptItem {
  const PurchaseReceiptItem({
    required this.id,
    required this.orderItemId,
    required this.productId,
    required this.movementId,
    required this.productName,
    required this.sku,
    required this.unit,
    required this.quantity,
    required this.unitCostMinor,
    required this.lineCostMinor,
    required this.productRevision,
    required this.balanceAfter,
    required this.stockRevision,
  });
  final String id, orderItemId, productId, movementId, productName, sku, unit;
  final int quantity,
      unitCostMinor,
      lineCostMinor,
      productRevision,
      balanceAfter,
      stockRevision;
}

class PurchaseReceipt {
  PurchaseReceipt({
    required this.summary,
    required this.reason,
    required List<PurchaseReceiptItem> items,
  }) : items = List.unmodifiable(items);
  final PurchaseReceiptSummary summary;
  final String reason;
  final List<PurchaseReceiptItem> items;
}

class PurchaseCancelledItem {
  const PurchaseCancelledItem({
    required this.orderItemId,
    required this.productId,
    required this.productName,
    required this.sku,
    required this.unit,
    required this.quantity,
    required this.unitCostMinor,
    required this.lineCostMinor,
  });
  final String orderItemId, productId, productName, sku, unit;
  final int quantity, unitCostMinor, lineCostMinor;
}

class PurchaseCancellation {
  PurchaseCancellation({
    required this.id,
    required this.organizationId,
    required this.branchId,
    required this.orderId,
    required this.actorUserId,
    required this.createdAt,
    required this.orderRevision,
    required this.reason,
    required this.currency,
    required this.cancelledTotalMinor,
    required List<PurchaseCancelledItem> items,
  }) : items = List.unmodifiable(items);
  final String id,
      organizationId,
      branchId,
      orderId,
      actorUserId,
      reason,
      currency;
  final DateTime createdAt;
  final int orderRevision, cancelledTotalMinor;
  final List<PurchaseCancelledItem> items;
}

class PurchaseCreateItem {
  const PurchaseCreateItem({
    required this.productId,
    required this.expectedRevision,
    required this.quantity,
    required this.unitCostMinor,
  });
  final String productId;
  final int expectedRevision, quantity, unitCostMinor;
  Map<String, dynamic> values() => {
    'product_id': validateId(productId).toLowerCase(),
    'expected_revision': purchaseRevision(expectedRevision),
    'quantity': purchaseQuantity(quantity),
    'unit_cost_minor': purchaseAmount(unitCostMinor),
  };
}

class CreatePurchaseRequest {
  CreatePurchaseRequest({
    required this.branchId,
    required this.supplierId,
    required this.expectedSupplierRevision,
    required this.expectedSettingsRevision,
    required this.currency,
    required List<PurchaseCreateItem> items,
    required this.reason,
    this.reference,
    String? requestId,
  }) : requestId = requestId ?? const Uuid().v4(),
       items = List.unmodifiable(items);
  final String requestId, branchId, supplierId, currency, reason;
  final String? reference;
  final int expectedSupplierRevision, expectedSettingsRevision;
  final List<PurchaseCreateItem> items;
}

class PurchaseReceiveItem {
  const PurchaseReceiveItem({
    required this.orderItemId,
    required this.quantity,
    required this.expectedProductRevision,
  });
  final String orderItemId;
  final int quantity, expectedProductRevision;
  Map<String, dynamic> values() => {
    'order_item_id': validateId(orderItemId).toLowerCase(),
    'quantity': purchaseQuantity(quantity),
    'expected_product_revision': purchaseRevision(expectedProductRevision),
  };
}

class ReceivePurchaseRequest {
  ReceivePurchaseRequest({
    required this.branchId,
    required this.orderId,
    required this.expectedRevision,
    required List<PurchaseReceiveItem> items,
    required this.reason,
    this.reference,
    String? requestId,
  }) : requestId = requestId ?? const Uuid().v4(),
       items = List.unmodifiable(items);
  final String requestId, branchId, orderId, reason;
  final String? reference;
  final int expectedRevision;
  final List<PurchaseReceiveItem> items;
}

class CancelPurchaseRequest {
  CancelPurchaseRequest({
    required this.branchId,
    required this.orderId,
    required this.expectedRevision,
    required this.reason,
    String? requestId,
  }) : requestId = requestId ?? const Uuid().v4();
  final String requestId, branchId, orderId, reason;
  final int expectedRevision;
}

class PurchaseMutationResult {
  const PurchaseMutationResult({
    required this.requestId,
    required this.kind,
    required this.orderId,
    required this.orderRevision,
    this.order,
    this.receipt,
    this.cancellation,
  });
  final String requestId, kind, orderId;
  final int orderRevision;
  final PurchaseOrder? order;
  final PurchaseReceipt? receipt;
  final PurchaseCancellation? cancellation;
}
