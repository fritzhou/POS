import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/auth/auth_models.dart';
import '../../../core/operations/operation_journal.dart';
import '../../../core/security/app_role.dart';
import '../../catalog/data/supabase_repository_support.dart';
import '../../catalog/domain/repository_support.dart';
import '../../checkout/data/operation_executor.dart';
import '../domain/purchase_models.dart';
import '../domain/purchase_repository.dart';
import 'purchase_decoders.dart';

const purchaseRpcTypes = {
  'create_purchase_order',
  'receive_purchase_order',
  'cancel_purchase_order_remaining',
};

class SupabasePurchaseRepository implements PurchaseRepository {
  SupabasePurchaseRepository({
    required SupabaseClient client,
    required AuthenticatedUser actor,
    required this._journal,
    bool Function()? isRecoverySession,
  }) : _scope = SupabaseRepositoryScope(
         client: client,
         actor: actor,
         isRecoverySession: isRecoverySession,
       );
  final SupabaseRepositoryScope _scope;
  final OperationJournal _journal;
  late final _operations = OperationExecutor(_scope, _journal);

  Map<String, dynamic> _branch(String branchId) {
    final branch = validateId(branchId).toLowerCase();
    if (!_scope.actor.role.allows(AppPermission.managePurchases) ||
        !_scope.actor.branchIds.contains(branch)) {
      throw const RepositoryFailure(
        RepositoryFailureType.permissionDenied,
        'Choose an authorized purchase branch.',
      );
    }
    return {'p_organization_id': _scope.organizationId, 'p_branch_id': branch};
  }

  void _proofScope(String organization, String branch, String expectedBranch) =>
      purchaseProof(
        organization == _scope.organizationId &&
            branch == expectedBranch.toLowerCase(),
      );

  @override
  Future<PurchaseContext> context(String branchId) => _scope.safe(() async {
    final row = rowFrom(
      await _scope.client.rpc(
        'get_purchase_context',
        params: _branch(branchId),
      ),
    );
    final result = PurchaseContext(
      organizationId: purchaseId(row['organization_id']),
      branchId: purchaseId(row['branch_id']),
      branchName: purchaseText(row['branch_name'], maximum: 160),
      currency: purchaseCurrency(purchaseText(row['currency'], maximum: 3)),
      settingsRevision: purchaseInteger(row['settings_revision'], minimum: 1),
    );
    _proofScope(result.organizationId, result.branchId, branchId);
    return result;
  });
  @override
  Future<DataPage<PurchaseOrderSummary>> listOrders({
    required String branchId,
    PurchaseOrderStatus? status,
    String query = '',
    PageRequest page = const PageRequest(),
  }) => _scope.safe(() async {
    page.validate();
    final rows = rowsFrom(
      await _scope.client.rpc(
        'list_purchase_orders',
        params: {
          ..._branch(branchId),
          'p_status': status?.wire,
          'p_query': requiredText(query, 'Search', 120, minimum: 0),
          'p_offset': page.offset,
          'p_limit': page.limit + 1,
        },
      ),
    );
    final summaries = rows.map(purchaseSummary).toList(growable: false);
    purchaseProof(summaries.length <= page.limit + 1);
    purchaseUnique(summaries.map((row) => row.id));
    for (final row in summaries) {
      _proofScope(row.organizationId, row.branchId, branchId);
      if (status != null) purchaseProof(row.status == status);
    }
    return DataPage(
      items: summaries.take(page.limit).toList(),
      hasMore: summaries.length > page.limit,
      offset: page.offset,
    );
  });
  Future<PurchaseOrder> _order(String branchId, String orderId) async {
    final order = purchaseOrder(
      rowFrom(
        await _scope.client.rpc(
          'get_purchase_order',
          params: {
            ..._branch(branchId),
            'p_order_id': validateId(orderId).toLowerCase(),
          },
        ),
      ),
    );
    _scope.requireIdentity();
    _proofScope(order.summary.organizationId, order.summary.branchId, branchId);
    purchaseProof(order.summary.id == orderId.toLowerCase());
    return order;
  }

  @override
  Future<PurchaseOrder> getOrder({
    required String branchId,
    required String orderId,
  }) => _scope.safe(() => _order(branchId, orderId));
  @override
  Future<DataPage<PurchaseReceiptSummary>> listReceipts({
    required String branchId,
    required String orderId,
    PageRequest page = const PageRequest(),
  }) => _scope.safe(() async {
    page.validate();
    final rows = rowsFrom(
      await _scope.client.rpc(
        'list_purchase_receipts',
        params: {
          ..._branch(branchId),
          'p_order_id': validateId(orderId).toLowerCase(),
          'p_offset': page.offset,
          'p_limit': page.limit + 1,
        },
      ),
    );
    final receipts = rows.map(purchaseReceiptSummary).toList(growable: false);
    purchaseProof(receipts.length <= page.limit + 1);
    purchaseUnique(receipts.map((row) => row.id));
    for (final row in receipts) {
      _proofScope(row.organizationId, row.branchId, branchId);
      purchaseProof(row.orderId == orderId.toLowerCase());
    }
    return DataPage(
      items: receipts.take(page.limit).toList(),
      hasMore: receipts.length > page.limit,
      offset: page.offset,
    );
  });
  @override
  Future<PurchaseReceipt> getReceipt({
    required String branchId,
    required String receiptId,
  }) => _scope.safe(() async {
    final result = purchaseReceipt(
      rowFrom(
        await _scope.client.rpc(
          'get_purchase_receipt',
          params: {
            ..._branch(branchId),
            'p_receipt_id': validateId(receiptId).toLowerCase(),
          },
        ),
      ),
    );
    _proofScope(
      result.summary.organizationId,
      result.summary.branchId,
      branchId,
    );
    purchaseProof(result.summary.id == receiptId.toLowerCase());
    final order = await _order(branchId, result.summary.orderId);
    purchaseProof(result.summary.orderRevision <= order.summary.revision);
    _receiptOriginalProof(result, order);
    return result;
  });

  @override
  Future<PurchaseMutationResult> create(
    CreatePurchaseRequest request,
  ) => _scope.safe(() async {
    final items = [...request.items]
      ..sort(
        (a, b) =>
            a.productId.toLowerCase().compareTo(b.productId.toLowerCase()),
      );
    _lines(items.map((item) => item.productId.toLowerCase()).toList());
    purchaseTotal(
      items.map((item) => purchaseLineCost(item.quantity, item.unitCostMinor)),
    );
    return _mutate('create_purchase_order', request.branchId, {
      ..._branch(request.branchId),
      'p_request_id': validateId(request.requestId).toLowerCase(),
      'p_supplier_id': validateId(request.supplierId).toLowerCase(),
      'p_expected_supplier_revision': purchaseRevision(
        request.expectedSupplierRevision,
      ),
      'p_expected_settings_revision': purchaseRevision(
        request.expectedSettingsRevision,
      ),
      'p_currency': purchaseCurrency(request.currency),
      'p_items': items.map((item) => item.values()).toList(),
      'p_reference': optionalText(request.reference, 'Order reference', 120),
      'p_reason': requiredText(
        request.reason,
        'Order reason',
        1000,
        minimum: 3,
      ),
    });
  });
  @override
  Future<PurchaseMutationResult> receive(
    ReceivePurchaseRequest request,
  ) => _scope.safe(() async {
    final items = [...request.items]
      ..sort(
        (a, b) =>
            a.orderItemId.toLowerCase().compareTo(b.orderItemId.toLowerCase()),
      );
    _lines(items.map((item) => item.orderItemId.toLowerCase()).toList());
    return _mutate('receive_purchase_order', request.branchId, {
      ..._branch(request.branchId),
      'p_request_id': validateId(request.requestId).toLowerCase(),
      'p_order_id': validateId(request.orderId).toLowerCase(),
      'p_expected_revision': purchaseRevision(request.expectedRevision),
      'p_items': items.map((item) => item.values()).toList(),
      'p_reference': optionalText(request.reference, 'Delivery reference', 120),
      'p_reason': requiredText(
        request.reason,
        'Receiving reason',
        1000,
        minimum: 3,
      ),
    });
  });
  @override
  Future<PurchaseMutationResult> cancelRemaining(
    CancelPurchaseRequest request,
  ) => _scope.safe(
    () => _mutate('cancel_purchase_order_remaining', request.branchId, {
      ..._branch(request.branchId),
      'p_request_id': validateId(request.requestId).toLowerCase(),
      'p_order_id': validateId(request.orderId).toLowerCase(),
      'p_expected_revision': purchaseRevision(request.expectedRevision),
      'p_reason': requiredText(
        request.reason,
        'Cancellation reason',
        1000,
        minimum: 3,
      ),
    }),
  );

  void _lines(List<String> ids) {
    if (ids.isEmpty || ids.length > 100 || ids.toSet().length != ids.length) {
      throw const RepositoryFailure(
        RepositoryFailureType.validation,
        'Choose 1 to 100 unique purchase lines.',
      );
    }
  }

  Future<PurchaseMutationResult> _mutate(
    String function,
    String branchId,
    Map<String, dynamic> params,
  ) async {
    branchId = branchId.toLowerCase();
    // Current order is read only for immutable item/cost provenance. Current
    // remaining state is deliberately not a replay gate after lost success.
    final original = function == 'create_purchase_order'
        ? null
        : await _order(branchId, params['p_order_id'] as String);
    return _operations.mutate(
      function: function,
      branchId: branchId,
      params: params,
      decode: (row) => _mutation(row, function, branchId, params, original),
    );
  }

  PurchaseMutationResult _mutation(
    Map<String, dynamic> row,
    String function,
    String branch,
    Map<String, dynamic> params,
    PurchaseOrder? original,
  ) {
    final requestId = purchaseId(row['request_id']);
    final orderId = purchaseId(row['order_id']);
    final revision = purchaseInteger(row['order_revision'], minimum: 1);
    final kind = switch (function) {
      'create_purchase_order' => 'purchase.create',
      'receive_purchase_order' => 'purchase.receive',
      _ => 'purchase.cancel_remaining',
    };
    purchaseProof(requestId == params['p_request_id'] && row['kind'] == kind);
    if (function == 'create_purchase_order') {
      final order = purchaseOrder(rowFrom(row['order']));
      final summary = order.summary;
      _proofScope(summary.organizationId, summary.branchId, branch);
      purchaseProof(
        summary.id == orderId &&
            summary.createdBy == _scope.actor.userId &&
            summary.supplierId == params['p_supplier_id'] &&
            order.supplierRevision == params['p_expected_supplier_revision'] &&
            order.settingsRevision == params['p_expected_settings_revision'] &&
            summary.currency == params['p_currency'] &&
            summary.reference == params['p_reference'] &&
            order.reason == params['p_reason'] &&
            summary.revision == 1 &&
            revision == 1 &&
            summary.status == PurchaseOrderStatus.ordered &&
            summary.receivedTotalMinor == 0 &&
            order.receiptCount == 0 &&
            order.cancellation == null,
      );
      final requested = rowsFrom(params['p_items']);
      purchaseProof(requested.length == order.items.length);
      for (final item in requested) {
        final actual = order.items
            .where((line) => line.productId == item['product_id'])
            .firstOrNull;
        purchaseProof(
          actual != null &&
              actual.orderedQuantity == item['quantity'] &&
              actual.unitCostMinor == item['unit_cost_minor'] &&
              actual.productRevision == item['expected_revision'] &&
              actual.receivedQuantity == 0 &&
              actual.cancelledQuantity == 0,
        );
      }
      return PurchaseMutationResult(
        requestId: requestId,
        kind: kind,
        orderId: orderId,
        orderRevision: revision,
        order: order,
      );
    }
    purchaseProof(
      original != null &&
          orderId == params['p_order_id'] &&
          revision == (params['p_expected_revision'] as int) + 1,
    );
    if (function == 'receive_purchase_order') {
      final receipt = purchaseReceipt(rowFrom(row['receipt']));
      final summary = receipt.summary;
      _proofScope(summary.organizationId, summary.branchId, branch);
      purchaseProof(
        summary.orderId == orderId &&
            summary.receivedBy == _scope.actor.userId &&
            summary.orderRevision == revision &&
            summary.reference == params['p_reference'] &&
            receipt.reason == params['p_reason'],
      );
      _receiptOriginalProof(receipt, original!);
      final requested = rowsFrom(params['p_items']);
      purchaseProof(requested.length == receipt.items.length);
      for (final item in requested) {
        final actual = receipt.items
            .where((line) => line.orderItemId == item['order_item_id'])
            .firstOrNull;
        purchaseProof(
          actual != null &&
              actual.quantity == item['quantity'] &&
              actual.productRevision == item['expected_product_revision'],
        );
      }
      return PurchaseMutationResult(
        requestId: requestId,
        kind: kind,
        orderId: orderId,
        orderRevision: revision,
        receipt: receipt,
      );
    }
    final cancellation = purchaseCancellation(rowFrom(row['cancellation']));
    _proofScope(cancellation.organizationId, cancellation.branchId, branch);
    purchaseProof(
      cancellation.orderId == orderId &&
          cancellation.actorUserId == _scope.actor.userId &&
          cancellation.orderRevision == revision &&
          cancellation.reason == params['p_reason'] &&
          cancellation.currency == original!.summary.currency,
    );
    final knownCancellation = original!.cancellation;
    final expected =
        knownCancellation != null && knownCancellation.orderRevision == revision
        ? knownCancellation.items
        : original.items
              .where((line) => line.remainingQuantity > 0)
              .map(
                (line) => PurchaseCancelledItem(
                  orderItemId: line.id,
                  productId: line.productId,
                  productName: line.productName,
                  sku: line.sku,
                  unit: line.unit,
                  quantity: line.remainingQuantity,
                  unitCostMinor: line.unitCostMinor,
                  lineCostMinor: purchaseLineCost(
                    line.remainingQuantity,
                    line.unitCostMinor,
                  ),
                ),
              )
              .toList();
    purchaseProof(expected.length == cancellation.items.length);
    for (final item in expected) {
      final actual = cancellation.items
          .where((line) => line.orderItemId == item.orderItemId)
          .firstOrNull;
      purchaseProof(
        actual != null &&
            actual.productId == item.productId &&
            actual.productName == item.productName &&
            actual.sku == item.sku &&
            actual.unit == item.unit &&
            actual.quantity == item.quantity &&
            actual.unitCostMinor == item.unitCostMinor &&
            actual.lineCostMinor == item.lineCostMinor,
      );
    }
    return PurchaseMutationResult(
      requestId: requestId,
      kind: kind,
      orderId: orderId,
      orderRevision: revision,
      cancellation: cancellation,
    );
  }

  void _receiptOriginalProof(PurchaseReceipt receipt, PurchaseOrder order) {
    purchaseProof(
      receipt.summary.currency == order.summary.currency &&
          receipt.summary.orderId == order.summary.id,
    );
    for (final item in receipt.items) {
      final original = order.items
          .where((line) => line.id == item.orderItemId)
          .firstOrNull;
      purchaseProof(
        original != null &&
            original.productId == item.productId &&
            original.productName == item.productName &&
            original.sku == item.sku &&
            original.unit == item.unit &&
            original.unitCostMinor == item.unitCostMinor &&
            item.quantity <= original.orderedQuantity,
      );
    }
  }

  @override
  Future<List<PendingOperation>> pendingMutations({String? branchId}) =>
      _scope.safe(() async {
        if (!_scope.actor.role.allows(AppPermission.managePurchases)) {
          throw const RepositoryFailure(
            RepositoryFailureType.permissionDenied,
            'Purchase access is restricted.',
          );
        }
        if (branchId != null) _branch(branchId);
        return (await _operations.pending(branchId: branchId))
            .where(
              (operation) =>
                  purchaseRpcTypes.contains(operation.type) &&
                  _scope.actor.branchIds.contains(operation.branchId),
            )
            .toList(growable: false);
      });
  @override
  Future<PurchaseMutationResult> retryPending(PendingOperation operation) =>
      _scope.safe(() async {
        if (!purchaseRpcTypes.contains(operation.type) ||
            operation.organizationId != _scope.organizationId ||
            operation.actorId != _scope.actor.userId ||
            operation.payload['p_organization_id'] != _scope.organizationId ||
            operation.payload['p_branch_id'] != operation.branchId ||
            operation.payload['p_request_id'] != operation.requestId) {
          throw const RepositoryFailure(
            RepositoryFailureType.permissionDenied,
            'This purchase request belongs to another account or branch.',
          );
        }
        _branch(operation.branchId);
        return _mutate(
          operation.type,
          operation.branchId,
          Map<String, dynamic>.from(operation.payload),
        );
      });
}
