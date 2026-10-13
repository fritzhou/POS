import 'dart:convert';

import 'package:nexapos/core/auth/auth_models.dart';
import 'package:nexapos/core/security/app_role.dart';
import 'package:nexapos/features/purchases/data/purchase_decoders.dart';
import 'package:nexapos/features/purchases/domain/purchase_models.dart';

// Synthetic isolated-test documents. Production code never creates these rows.
const purchaseOrg = '11000000-0000-4000-8000-000000000001';
const purchaseBranch = '11000000-0000-4000-8000-000000000002';
const purchaseActor = '11000000-0000-4000-8000-000000000003';
const purchaseSupplier = '11000000-0000-4000-8000-000000000004';
const purchaseProduct = '11000000-0000-4000-8000-000000000005';
const purchaseOrderId = '11000000-0000-4000-8000-000000000006';
const purchaseOrderItem = '11000000-0000-4000-8000-000000000007';
const purchaseReceiptId = '11000000-0000-4000-8000-000000000008';
const purchaseReceiptItem = '11000000-0000-4000-8000-000000000009';
const purchaseOperation = '11000000-0000-4000-8000-000000000010';
const purchaseMovement = '11000000-0000-4000-8000-000000000011';
const purchaseCancellationId = '11000000-0000-4000-8000-000000000012';
const purchaseRequest = '11000000-0000-4000-8000-000000000013';
const otherPurchaseActor = '11000000-0000-4000-8000-000000000014';

AuthenticatedUser purchaseMembership({AppRole role = AppRole.owner}) =>
    AuthenticatedUser(
      userId: purchaseActor,
      email: 'owner@example.test',
      organizationId: purchaseOrg,
      membershipId: purchaseSupplier,
      role: role,
      branchIds: {purchaseBranch},
      allBranches: true,
      businessName: 'Purchase fixture business',
    );

Map<String, dynamic> purchaseContextWire() => {
  'organization_id': purchaseOrg,
  'branch_id': purchaseBranch,
  'branch_name': 'Fixture branch',
  'currency': 'PHP',
  'settings_revision': 4,
};

Map<String, dynamic> purchaseOrderWire({
  int received = 0,
  bool cancelled = false,
  bool changedCatalog = false,
}) => {
  'id': purchaseOrderId,
  'organization_id': purchaseOrg,
  'branch_id': purchaseBranch,
  'supplier_id': purchaseSupplier,
  'supplier_name': 'Fixture supplier',
  'supplier_revision': 3,
  'currency': 'PHP',
  'settings_revision': 4,
  'created_by': purchaseActor,
  'created_at': '2026-10-11T00:00:00Z',
  'reference': 'PO fixture',
  'reason': 'Restock shelves',
  'ordered_total_minor': 303,
  'received_total_minor': received * 101,
  'status': cancelled
      ? 'cancelled'
      : received == 3
      ? 'received'
      : received > 0
      ? 'partially_received'
      : 'ordered',
  'revision': 1 + (received > 0 ? 1 : 0) + (cancelled ? 1 : 0),
  'line_count': 1,
  'receipt_count': received > 0 ? 1 : 0,
  'items': [
    {
      'id': purchaseOrderItem,
      'order_id': purchaseOrderId,
      'product_id': purchaseProduct,
      'product_name': 'Original product',
      'sku': 'ORIGINAL-SKU',
      'unit': 'each',
      'product_revision': 2,
      'ordered_quantity': 3,
      'unit_cost_minor': 101,
      'line_cost_minor': 303,
      'received_quantity': received,
      'cancelled_quantity': cancelled ? 3 - received : 0,
      'remaining_quantity': cancelled ? 0 : 3 - received,
      'current_product_revision': changedCatalog ? 9 : 2,
      'current_product_active': true,
      'current_product_name': changedCatalog
          ? 'Renamed product'
          : 'Original product',
      'current_sku': changedCatalog ? 'NEW-SKU' : 'ORIGINAL-SKU',
      'current_unit': 'each',
      'current_currency': changedCatalog ? 'USD' : 'PHP',
    },
  ],
  'cancellation': cancelled
      ? purchaseCancellationWire(
          quantity: 3 - received,
          revision: 1 + (received > 0 ? 1 : 0) + 1,
        )
      : null,
};

Map<String, dynamic> purchaseReceiptWire({
  int quantity = 1,
  int revision = 2,
}) => {
  'id': purchaseReceiptId,
  'organization_id': purchaseOrg,
  'branch_id': purchaseBranch,
  'order_id': purchaseOrderId,
  'operation_id': purchaseOperation,
  'order_revision': revision,
  'received_by': purchaseActor,
  'received_at': '2026-10-11T01:00:00Z',
  'currency': 'PHP',
  'received_total_minor': quantity * 101,
  'reference': 'Delivery fixture',
  'reason': 'Counted delivery',
  'line_count': 1,
  'items': [
    {
      'id': purchaseReceiptItem,
      'organization_id': purchaseOrg,
      'branch_id': purchaseBranch,
      'receipt_id': purchaseReceiptId,
      'order_id': purchaseOrderId,
      'order_item_id': purchaseOrderItem,
      'operation_id': purchaseOperation,
      'product_id': purchaseProduct,
      'product_name': 'Original product',
      'sku': 'ORIGINAL-SKU',
      'unit': 'each',
      'quantity': quantity,
      'unit_cost_minor': 101,
      'line_cost_minor': quantity * 101,
      'product_revision': 9,
      'movement_id': purchaseMovement,
      'balance_after': -1,
      'stock_revision': 3,
    },
  ],
};

Map<String, dynamic> purchaseCancellationWire({
  int quantity = 2,
  int revision = 3,
}) => {
  'id': purchaseCancellationId,
  'organization_id': purchaseOrg,
  'branch_id': purchaseBranch,
  'order_id': purchaseOrderId,
  'order_revision': revision,
  'actor_user_id': purchaseActor,
  'created_at': '2026-10-11T02:00:00Z',
  'reason': 'Supplier discontinued',
  'currency': 'PHP',
  'cancelled_total_minor': quantity * 101,
  'items': [
    {
      'order_item_id': purchaseOrderItem,
      'product_id': purchaseProduct,
      'product_name': 'Original product',
      'sku': 'ORIGINAL-SKU',
      'unit': 'each',
      'cancelled_quantity': quantity,
      'unit_cost_minor': 101,
      'line_cost_minor': quantity * 101,
    },
  ],
};

Map<String, dynamic> purchaseCreateResult() => {
  'request_id': purchaseRequest,
  'kind': 'purchase.create',
  'order_id': purchaseOrderId,
  'order_revision': 1,
  'order': purchaseOrderWire(),
};
Map<String, dynamic> purchaseReceiveResult() => {
  'request_id': purchaseRequest,
  'kind': 'purchase.receive',
  'order_id': purchaseOrderId,
  'order_revision': 2,
  'receipt': purchaseReceiptWire(),
};
Map<String, dynamic> purchaseCancelResult() => {
  'request_id': purchaseRequest,
  'kind': 'purchase.cancel_remaining',
  'order_id': purchaseOrderId,
  'order_revision': 3,
  'cancellation': purchaseCancellationWire(),
};

CreatePurchaseRequest createPurchaseRequest() => CreatePurchaseRequest(
  requestId: purchaseRequest,
  branchId: purchaseBranch,
  supplierId: purchaseSupplier,
  expectedSupplierRevision: 3,
  expectedSettingsRevision: 4,
  currency: 'PHP',
  reason: 'Restock shelves',
  reference: 'PO fixture',
  items: [
    const PurchaseCreateItem(
      productId: purchaseProduct,
      expectedRevision: 2,
      quantity: 3,
      unitCostMinor: 101,
    ),
  ],
);
ReceivePurchaseRequest receivePurchaseRequest() => ReceivePurchaseRequest(
  requestId: purchaseRequest,
  branchId: purchaseBranch,
  orderId: purchaseOrderId,
  expectedRevision: 1,
  reason: 'Counted delivery',
  reference: 'Delivery fixture',
  items: [
    const PurchaseReceiveItem(
      orderItemId: purchaseOrderItem,
      quantity: 1,
      expectedProductRevision: 9,
    ),
  ],
);
CancelPurchaseRequest cancelPurchaseRequest() => CancelPurchaseRequest(
  requestId: purchaseRequest,
  branchId: purchaseBranch,
  orderId: purchaseOrderId,
  expectedRevision: 2,
  reason: 'Supplier discontinued',
);
PurchaseOrder purchaseFixtureOrder({
  int received = 0,
  bool cancelled = false,
  bool changedCatalog = true,
}) => purchaseOrder(
  purchaseOrderWire(
    received: received,
    cancelled: cancelled,
    changedCatalog: changedCatalog,
  ),
);
Map<String, dynamic> clonePurchaseWire(Map<String, dynamic> value) =>
    jsonDecode(jsonEncode(value)) as Map<String, dynamic>;
