import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/auth/auth_models.dart';
import '../../../core/operations/operation_journal.dart';
import '../../catalog/data/supabase_repository_support.dart';
import '../../catalog/domain/repository_support.dart';
import '../../checkout/data/checkout_decoders.dart';
import '../../checkout/data/operation_executor.dart';
import '../../checkout/domain/checkout_models.dart';
import '../domain/inventory_models.dart';
import '../domain/inventory_repository.dart';

class SupabaseInventoryRepository implements InventoryRepository {
  SupabaseInventoryRepository({
    required SupabaseClient client,
    required AuthenticatedUser actor,
    bool Function()? isRecoverySession,
    this.journal,
  }) : _scope = SupabaseRepositoryScope(
         client: client,
         actor: actor,
         isRecoverySession: isRecoverySession,
       );
  final SupabaseRepositoryScope _scope;
  final OperationJournal? journal;
  late final _operations = OperationExecutor(_scope, journal);

  Map<String, dynamic> _branchParams(String branchId) {
    validateId(branchId);
    if (!_scope.actor.branchIds.contains(branchId)) {
      throw const RepositoryFailure(
        RepositoryFailureType.permissionDenied,
        'Choose an authorized branch.',
      );
    }
    return {
      'p_organization_id': _scope.organizationId,
      'p_branch_id': branchId,
    };
  }

  StockOperation _operation(
    Map<String, dynamic> row,
    String branchId,
    String requestId,
  ) {
    final operation = stockOperationFromRow(row);
    if (operation.organizationId != _scope.organizationId ||
        operation.branchId != branchId ||
        operation.actorUserId != _scope.actor.userId ||
        row['request_id'] != requestId) {
      throw const FormatException('Unexpected stock operation');
    }
    return operation;
  }

  @override
  Future<DataPage<PosProduct>> listBalances({
    required String branchId,
    String query = '',
    PageRequest page = const PageRequest(),
  }) => _scope.safe(() async {
    page.validate();
    final result = await _scope.client.rpc(
      'list_inventory',
      params: {
        ..._branchParams(branchId),
        'p_query': requiredText(query, 'Search', 120, minimum: 0),
        'p_offset': page.offset,
        'p_limit': page.limit + 1,
      },
    );
    final data = pageFrom(rowsFrom(result), page, posProductFromRow);
    if (data.items.any(
      (product) => product.organizationId != _scope.organizationId,
    )) {
      throw const FormatException('Unexpected inventory scope');
    }
    return data;
  });

  @override
  Future<DataPage<StockMovement>> listMovements({
    required String branchId,
    String? productId,
    PageRequest page = const PageRequest(),
  }) => _scope.safe(() async {
    page.validate();
    final result = await _scope.client.rpc(
      'list_stock_movements',
      params: {
        ..._branchParams(branchId),
        'p_product_id': validateOptionalId(productId),
        'p_offset': page.offset,
        'p_limit': page.limit + 1,
      },
    );
    final data = pageFrom(rowsFrom(result), page, stockMovementFromRow);
    if (data.items.any(
      (movement) => movement.branchId != null && movement.branchId != branchId,
    )) {
      throw const FormatException('Unexpected inventory scope');
    }
    return data;
  });

  @override
  Future<StockOperation> receiveStock(ReceiveStockRequest request) =>
      _scope.safe(() async {
        if (request.items.isEmpty || request.items.length > 100) {
          throw const RepositoryFailure(
            RepositoryFailureType.validation,
            'Choose 1 to 100 received products.',
          );
        }
        final sorted = [...request.items]
          ..sort(
            (a, b) =>
                a.productId.toLowerCase().compareTo(b.productId.toLowerCase()),
          );
        if (sorted.map((item) => item.productId.toLowerCase()).toSet().length !=
            sorted.length) {
          throw const RepositoryFailure(
            RepositoryFailureType.validation,
            'Combine duplicate products into one receiving line.',
          );
        }
        return _operations.mutate(
          function: 'receive_stock',
          branchId: request.branchId,
          params: {
            ..._branchParams(request.branchId),
            'p_request_id': validateId(request.requestId),
            'p_items': sorted
                .map((item) => item.validatedValues())
                .toList(growable: false),
            'p_supplier_id': validateOptionalId(request.supplierId),
            'p_reference': optionalText(
              request.reference,
              'Receiving reference',
              120,
            ),
            'p_reason': requiredText(
              request.reason,
              'Receiving reason',
              1000,
              minimum: 3,
            ),
          },
          decode: (row) => _operation(row, request.branchId, request.requestId),
        );
      });

  @override
  Future<StockOperation> adjustStock(AdjustStockRequest request) => _scope.safe(
    () async => _operations.mutate(
      function: 'adjust_stock',
      branchId: request.branchId,
      params: {
        ..._branchParams(request.branchId),
        'p_request_id': validateId(request.requestId),
        'p_product_id': validateId(request.productId),
        'p_delta_quantity': signedQuantity(request.deltaQuantity),
        'p_reason': requiredText(
          request.reason,
          'Adjustment reason',
          1000,
          minimum: 3,
        ),
      },
      decode: (row) => _operation(row, request.branchId, request.requestId),
    ),
  );

  @override
  Future<List<PendingOperation>> pendingOperations({String? branchId}) =>
      _scope.safe(
        () async => (await _operations.pending(branchId: branchId))
            .where(
              (operation) => const {
                'receive_stock',
                'adjust_stock',
              }.contains(operation.type),
            )
            .toList(growable: false),
      );

  @override
  Future<StockOperation> retryPending(PendingOperation operation) =>
      _scope.safe(() async {
        if (!const {'receive_stock', 'adjust_stock'}.contains(operation.type) ||
            operation.organizationId != _scope.organizationId ||
            operation.actorId != _scope.actor.userId ||
            operation.payload['p_organization_id'] != _scope.organizationId ||
            operation.payload['p_branch_id'] != operation.branchId ||
            operation.payload['p_request_id'] != operation.requestId ||
            !_scope.actor.branchIds.contains(operation.branchId)) {
          throw const RepositoryFailure(
            RepositoryFailureType.permissionDenied,
            'This pending operation belongs to another account or branch.',
          );
        }
        return _operations.mutate(
          function: operation.type,
          branchId: operation.branchId,
          params: Map<String, dynamic>.from(operation.payload),
          decode: (row) =>
              _operation(row, operation.branchId, operation.requestId),
        );
      });
}

StockMovement stockMovementFromRow(Map<String, dynamic> row) => StockMovement(
  id: validateId(row['id'] as String),
  productId: validateId(row['product_id'] as String),
  quantityDelta: signedQuantity(integerFrom(row['quantity_delta'])),
  balanceAfter: amountFrom(row['balance_after']),
  createdAt: DateTime.parse(row['created_at'] as String),
  branchId: row['branch_id'] as String?,
  productName: row['product_name'] as String?,
  sku: row['sku'] as String?,
  kind: row['kind'] as String?,
  reason: row['reason'] as String?,
  actorUserId: row['actor_user_id'] as String?,
  sourceId: row['source_id'] as String?,
);

StockOperation stockOperationFromRow(Map<String, dynamic> row) =>
    StockOperation(
      id: validateId(row['id'] as String),
      organizationId: validateId(row['organization_id'] as String),
      branchId: validateId(row['branch_id'] as String),
      actorUserId: validateId(row['actor_user_id'] as String),
      kind: row['kind'] as String,
      createdAt: DateTime.parse(row['created_at'] as String),
      reason: row['reason'] as String,
      reference: row['reference'] as String?,
      supplierId: row['supplier_id'] as String?,
      movements: rowsFrom(
        row['movements'],
      ).map(stockMovementFromRow).toList(growable: false),
    );
