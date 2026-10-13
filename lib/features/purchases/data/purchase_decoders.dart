import '../../catalog/data/supabase_repository_support.dart';
import '../domain/purchase_models.dart';

String purchaseId(Object? value) {
  if (value is! String ||
      !RegExp(
        r'^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$',
      ).hasMatch(value)) {
    throw const FormatException('Expected normalized purchase identifier');
  }
  return value;
}

int purchaseInteger(
  Object? value, {
  int minimum = 0,
  int maximum = purchaseMaximumInteger,
}) {
  if (value is! int || value < minimum || value > maximum) {
    throw const FormatException('Expected exact purchase integer');
  }
  return value;
}

String purchaseText(Object? value, {int minimum = 1, int maximum = 1000}) {
  if (value is! String ||
      value != value.trim() ||
      value.length < minimum ||
      value.length > maximum) {
    throw const FormatException('Expected bounded purchase text');
  }
  return value;
}

String? purchaseOptionalText(Object? value) =>
    value == null ? null : purchaseText(value, maximum: 120);
DateTime purchaseTime(Object? value) {
  if (value is! String) {
    throw const FormatException('Expected purchase timestamp');
  }
  final match = RegExp(
    r'^(\d{4})-(\d{2})-(\d{2})T(\d{2}):(\d{2}):(\d{2})(?:\.\d{1,6})?(?:Z|\+00:00)$',
  ).firstMatch(value);
  final time = DateTime.tryParse(value);
  if (match == null ||
      time == null ||
      !time.isUtc ||
      time.year != int.parse(match[1]!) ||
      time.month != int.parse(match[2]!) ||
      time.day != int.parse(match[3]!) ||
      time.hour != int.parse(match[4]!) ||
      time.minute != int.parse(match[5]!) ||
      time.second != int.parse(match[6]!)) {
    throw const FormatException('Expected valid UTC purchase timestamp');
  }
  return time;
}

void purchaseProof(bool condition) {
  if (!condition) {
    throw const FormatException('Purchase evidence is inconsistent');
  }
}

void purchaseUnique(Iterable<String> values) {
  final list = values.toList();
  purchaseProof(list.toSet().length == list.length);
}

PurchaseOrderSummary purchaseSummary(Map<String, dynamic> row) {
  final ordered = purchaseInteger(row['ordered_total_minor']);
  final received = purchaseInteger(row['received_total_minor']);
  purchaseProof(received <= ordered);
  return PurchaseOrderSummary(
    id: purchaseId(row['id']),
    organizationId: purchaseId(row['organization_id']),
    branchId: purchaseId(row['branch_id']),
    supplierId: purchaseId(row['supplier_id']),
    supplierName: purchaseText(row['supplier_name'], maximum: 160),
    currency: purchaseCurrency(purchaseText(row['currency'], maximum: 3)),
    createdBy: purchaseId(row['created_by']),
    createdAt: purchaseTime(row['created_at']),
    orderedTotalMinor: ordered,
    receivedTotalMinor: received,
    revision: purchaseInteger(row['revision'], minimum: 1),
    status: PurchaseOrderStatus.fromWire(
      purchaseText(row['status'], maximum: 32),
    ),
    lineCount: purchaseInteger(row['line_count'], minimum: 1, maximum: 100),
    reference: purchaseOptionalText(row['reference']),
  );
}

PurchaseOrder purchaseOrder(Map<String, dynamic> row) {
  final summary = purchaseSummary(row);
  final itemRows = rowsFrom(row['items']);
  purchaseProof(itemRows.length == summary.lineCount);
  final items = itemRows
      .map((item) {
        if (item['organization_id'] != null) {
          purchaseProof(item['organization_id'] == summary.organizationId);
        }
        if (item['branch_id'] != null) {
          purchaseProof(item['branch_id'] == summary.branchId);
        }
        if (item['order_id'] != null) {
          purchaseProof(item['order_id'] == summary.id);
        }
        final ordered = purchaseInteger(
          item['ordered_quantity'],
          minimum: 1,
          maximum: 1000000,
        );
        final received = purchaseInteger(
          item['received_quantity'],
          maximum: ordered,
        );
        final cancelled = purchaseInteger(
          item['cancelled_quantity'],
          maximum: ordered,
        );
        final remaining = purchaseInteger(
          item['remaining_quantity'],
          maximum: ordered,
        );
        purchaseProof(received + cancelled + remaining == ordered);
        final unitCost = purchaseInteger(item['unit_cost_minor']);
        final lineCost = purchaseInteger(item['line_cost_minor']);
        purchaseProof(
          BigInt.from(lineCost) == BigInt.from(ordered) * BigInt.from(unitCost),
        );
        return PurchaseOrderItem(
          id: purchaseId(item['id']),
          productId: purchaseId(item['product_id']),
          productName: purchaseText(item['product_name'], maximum: 160),
          sku: purchaseText(item['sku'], maximum: 64),
          unit: purchaseText(item['unit'], maximum: 32),
          productRevision: purchaseInteger(
            item['product_revision'],
            minimum: 1,
          ),
          currentProductRevision: purchaseInteger(
            item['current_product_revision'],
            minimum: 1,
          ),
          currentProductActive: switch (item['current_product_active']) {
            bool value => value,
            _ => throw const FormatException('Expected product active flag'),
          },
          currentProductName: purchaseText(
            item['current_product_name'],
            maximum: 160,
          ),
          currentSku: purchaseText(item['current_sku'], maximum: 64),
          currentUnit: purchaseText(item['current_unit'], maximum: 32),
          currentCurrency: purchaseCurrency(
            purchaseText(item['current_currency'], maximum: 3),
          ),
          orderedQuantity: ordered,
          receivedQuantity: received,
          cancelledQuantity: cancelled,
          remainingQuantity: remaining,
          unitCostMinor: unitCost,
          lineCostMinor: lineCost,
        );
      })
      .toList(growable: false);
  purchaseUnique(items.map((item) => item.id));
  purchaseUnique(items.map((item) => item.productId));
  purchaseProof(
    purchaseTotal(items.map((item) => item.lineCostMinor)) ==
        summary.orderedTotalMinor,
  );
  purchaseProof(
    purchaseTotal(
          items.map(
            (item) =>
                purchaseLineCost(item.receivedQuantity, item.unitCostMinor),
          ),
        ) ==
        summary.receivedTotalMinor,
  );
  final cancellation = row['cancellation'] == null
      ? null
      : purchaseCancellation(rowFrom(row['cancellation']));
  if (cancellation != null) {
    purchaseProof(
      cancellation.orderId == summary.id &&
          cancellation.organizationId == summary.organizationId &&
          cancellation.branchId == summary.branchId &&
          cancellation.currency == summary.currency &&
          cancellation.orderRevision == summary.revision,
    );
    for (final cancelled in cancellation.items) {
      final original = items
          .where((item) => item.id == cancelled.orderItemId)
          .firstOrNull;
      purchaseProof(
        original != null &&
            original.productId == cancelled.productId &&
            original.productName == cancelled.productName &&
            original.sku == cancelled.sku &&
            original.unit == cancelled.unit &&
            original.cancelledQuantity == cancelled.quantity &&
            original.unitCostMinor == cancelled.unitCostMinor,
      );
    }
    purchaseProof(
      items.where((item) => item.cancelledQuantity > 0).length ==
          cancellation.items.length,
    );
    purchaseProof(items.every((item) => item.remainingQuantity == 0));
  } else {
    purchaseProof(items.every((item) => item.cancelledQuantity == 0));
  }
  final receiptCount = purchaseInteger(row['receipt_count']);
  final hasReceived = items.any((item) => item.receivedQuantity > 0);
  purchaseProof((receiptCount > 0) == hasReceived);
  purchaseProof(
    summary.revision == 1 + receiptCount + (cancellation == null ? 0 : 1),
  );
  final expectedStatus = cancellation != null
      ? PurchaseOrderStatus.cancelled
      : items.every((item) => item.remainingQuantity == 0)
      ? PurchaseOrderStatus.received
      : items.any((item) => item.receivedQuantity > 0)
      ? PurchaseOrderStatus.partiallyReceived
      : PurchaseOrderStatus.ordered;
  purchaseProof(summary.status == expectedStatus);
  return PurchaseOrder(
    summary: summary,
    reason: purchaseText(row['reason'], minimum: 3),
    supplierRevision: purchaseInteger(row['supplier_revision'], minimum: 1),
    settingsRevision: purchaseInteger(row['settings_revision'], minimum: 1),
    receiptCount: receiptCount,
    items: items,
    cancellation: cancellation,
  );
}

PurchaseReceiptSummary purchaseReceiptSummary(Map<String, dynamic> row) =>
    PurchaseReceiptSummary(
      id: purchaseId(row['id']),
      organizationId: purchaseId(row['organization_id']),
      branchId: purchaseId(row['branch_id']),
      orderId: purchaseId(row['order_id']),
      operationId: purchaseId(row['operation_id']),
      receivedBy: purchaseId(row['received_by']),
      receivedAt: purchaseTime(row['received_at']),
      currency: purchaseCurrency(purchaseText(row['currency'], maximum: 3)),
      receivedTotalMinor: purchaseInteger(row['received_total_minor']),
      orderRevision: purchaseInteger(row['order_revision'], minimum: 2),
      reference: purchaseOptionalText(row['reference']),
    );
PurchaseReceipt purchaseReceipt(Map<String, dynamic> row) {
  final summary = purchaseReceiptSummary(row);
  final itemRows = rowsFrom(row['items']);
  purchaseProof(
    itemRows.length ==
        purchaseInteger(row['line_count'], minimum: 1, maximum: 100),
  );
  final items = itemRows
      .map((item) {
        for (final key in [
          'organization_id',
          'branch_id',
          'order_id',
          'receipt_id',
          'operation_id',
        ]) {
          final expected = switch (key) {
            'organization_id' => summary.organizationId,
            'branch_id' => summary.branchId,
            'order_id' => summary.orderId,
            'operation_id' => summary.operationId,
            _ => summary.id,
          };
          if (item[key] != null) purchaseProof(item[key] == expected);
        }
        final quantity = purchaseInteger(
          item['quantity'],
          minimum: 1,
          maximum: 1000000,
        );
        final cost = purchaseInteger(item['unit_cost_minor']);
        final line = purchaseInteger(item['line_cost_minor']);
        purchaseProof(
          BigInt.from(line) == BigInt.from(quantity) * BigInt.from(cost),
        );
        return PurchaseReceiptItem(
          id: purchaseId(item['id']),
          orderItemId: purchaseId(item['order_item_id']),
          productId: purchaseId(item['product_id']),
          movementId: purchaseId(item['movement_id']),
          productName: purchaseText(item['product_name'], maximum: 160),
          sku: purchaseText(item['sku'], maximum: 64),
          unit: purchaseText(item['unit'], maximum: 32),
          quantity: quantity,
          unitCostMinor: cost,
          lineCostMinor: line,
          productRevision: purchaseInteger(
            item['product_revision'],
            minimum: 1,
          ),
          balanceAfter: purchaseInteger(
            item['balance_after'],
            minimum: -purchaseMaximumInteger,
          ),
          stockRevision: purchaseInteger(item['stock_revision'], minimum: 1),
        );
      })
      .toList(growable: false);
  purchaseUnique(items.map((item) => item.id));
  purchaseUnique(items.map((item) => item.orderItemId));
  purchaseUnique(items.map((item) => item.productId));
  purchaseUnique(items.map((item) => item.movementId));
  purchaseProof(
    purchaseTotal(items.map((item) => item.lineCostMinor)) ==
        summary.receivedTotalMinor,
  );
  return PurchaseReceipt(
    summary: summary,
    reason: purchaseText(row['reason'], minimum: 3),
    items: items,
  );
}

PurchaseCancellation purchaseCancellation(Map<String, dynamic> row) {
  final itemRows = rowsFrom(row['items']);
  purchaseProof(itemRows.isNotEmpty && itemRows.length <= 100);
  final items = itemRows
      .map((item) {
        final quantity = purchaseInteger(
          item['cancelled_quantity'],
          minimum: 1,
          maximum: 1000000,
        );
        final cost = purchaseInteger(item['unit_cost_minor']);
        final line = purchaseInteger(item['line_cost_minor']);
        purchaseProof(
          BigInt.from(line) == BigInt.from(quantity) * BigInt.from(cost),
        );
        return PurchaseCancelledItem(
          orderItemId: purchaseId(item['order_item_id']),
          productId: purchaseId(item['product_id']),
          productName: purchaseText(item['product_name'], maximum: 160),
          sku: purchaseText(item['sku'], maximum: 64),
          unit: purchaseText(item['unit'], maximum: 32),
          quantity: quantity,
          unitCostMinor: cost,
          lineCostMinor: line,
        );
      })
      .toList(growable: false);
  purchaseUnique(items.map((item) => item.orderItemId));
  purchaseUnique(items.map((item) => item.productId));
  final total = purchaseInteger(row['cancelled_total_minor']);
  purchaseProof(
    purchaseTotal(items.map((item) => item.lineCostMinor)) == total,
  );
  return PurchaseCancellation(
    id: purchaseId(row['id']),
    organizationId: purchaseId(row['organization_id']),
    branchId: purchaseId(row['branch_id']),
    orderId: purchaseId(row['order_id']),
    actorUserId: purchaseId(row['actor_user_id']),
    createdAt: purchaseTime(row['created_at']),
    orderRevision: purchaseInteger(row['order_revision'], minimum: 2),
    reason: purchaseText(row['reason'], minimum: 3),
    currency: purchaseCurrency(purchaseText(row['currency'], maximum: 3)),
    cancelledTotalMinor: total,
    items: items,
  );
}
