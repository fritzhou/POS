import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/auth/auth_models.dart';
import '../../../core/operations/operation_journal.dart';
import '../../catalog/data/supabase_repository_support.dart';
import '../../catalog/domain/repository_support.dart';
import '../domain/checkout_models.dart';
import '../domain/checkout_repository.dart';
import 'checkout_decoders.dart';
import 'operation_executor.dart';

class SupabaseCheckoutRepository implements CheckoutRepository {
  SupabaseCheckoutRepository({
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

  void _verifyScope(String organizationId, String? branchId) {
    if (organizationId != _scope.organizationId ||
        (branchId != null && !_scope.actor.branchIds.contains(branchId))) {
      throw const FormatException('Unexpected response scope');
    }
  }

  @override
  Future<PosContext> loadContext(String branchId) => _scope.safe(() async {
    final row = rowFrom(
      await _scope.client.rpc(
        'get_pos_context',
        params: _branchParams(branchId),
      ),
    );
    final result = contextFromRow(row);
    if (result.branchId != branchId) {
      throw const FormatException('Unexpected branch');
    }
    return result;
  });

  @override
  Future<DataPage<PosProduct>> searchProducts({
    required String branchId,
    String query = '',
    String? categoryId,
    PageRequest page = const PageRequest(),
  }) => _scope.safe(() async {
    page.validate();
    final result = await _scope.client.rpc(
      'list_pos_products',
      params: {
        ..._branchParams(branchId),
        'p_query': requiredText(
          query.isEmpty ? ' ' : query,
          'Search',
          120,
          minimum: 0,
        ),
        'p_category_id': validateOptionalId(categoryId),
        'p_offset': page.offset,
        'p_limit': page.limit + 1,
      },
    );
    final data = pageFrom(rowsFrom(result), page, posProductFromRow);
    for (final product in data.items) {
      _verifyScope(product.organizationId, branchId);
    }
    return data;
  });

  @override
  Future<PosProduct?> lookupProductByBarcode({
    required String branchId,
    required String barcode,
  }) => _scope.safe(() async {
    final result = await _scope.client.rpc(
      'lookup_pos_product_by_barcode',
      params: {
        ..._branchParams(branchId),
        'p_barcode': requiredText(barcode, 'Barcode', 128),
      },
    );
    if (result == null) return null;
    final product = posProductFromRow(rowFrom(result));
    _verifyScope(product.organizationId, branchId);
    if (product.barcode != barcode.trim()) {
      throw const FormatException('Unexpected barcode');
    }
    return product;
  });

  @override
  Future<Shift?> currentShift(String branchId) => _scope.safe(() async {
    final result = await _scope.client.rpc(
      'get_current_shift',
      params: _branchParams(branchId),
    );
    if (result == null) return null;
    final shift = shiftFromRow(rowFrom(result));
    _verifyScope(shift.organizationId, shift.branchId);
    if (shift.branchId != branchId ||
        shift.actorUserId != _scope.actor.userId ||
        !shift.isOpen) {
      throw const FormatException('Unexpected current shift');
    }
    return shift;
  });

  @override
  Future<DataPage<Shift>> listShifts({
    String? branchId,
    PageRequest page = const PageRequest(),
  }) => _scope.safe(() async {
    page.validate();
    final result = await _scope.client.rpc(
      'list_shifts',
      params: {
        'p_organization_id': _scope.organizationId,
        'p_branch_id': validateOptionalId(branchId),
        'p_offset': page.offset,
        'p_limit': page.limit + 1,
      },
    );
    final data = pageFrom(rowsFrom(result), page, shiftFromRow);
    for (final shift in data.items) {
      _verifyScope(shift.organizationId, shift.branchId);
    }
    return data;
  });

  @override
  Future<Shift> openShift(OpenShiftRequest request) => _scope.safe(() async {
    return _operations.mutate(
      function: 'open_shift',
      branchId: request.branchId,
      params: {
        ..._branchParams(request.branchId),
        'p_request_id': validateId(request.requestId),
        'p_opening_cash_minor': validateMinor(request.openingCashMinor),
        'p_expected_currency': validatePosCurrency(request.expectedCurrency),
      },
      decode: (row) {
        final result = shiftFromRow(row);
        _verifyScope(result.organizationId, result.branchId);
        if (result.branchId != request.branchId ||
            result.actorUserId != _scope.actor.userId ||
            row['request_id'] != request.requestId) {
          throw const FormatException('Unexpected shift');
        }
        return result;
      },
    );
  });

  @override
  Future<Shift> closeShift(CloseShiftRequest request) => _scope.safe(() async {
    return _operations.mutate(
      function: 'close_shift',
      branchId: request.branchId,
      params: {
        'p_organization_id': _scope.organizationId,
        'p_shift_id': validateId(request.shiftId),
        'p_request_id': validateId(request.requestId),
        'p_counted_cash_minor': validateMinor(request.countedCashMinor),
        'p_reason': requiredText(
          request.reason,
          'Closing reason',
          1000,
          minimum: 3,
        ),
      },
      decode: (row) {
        final result = shiftFromRow(row);
        _verifyScope(result.organizationId, result.branchId);
        if (result.id != request.shiftId ||
            result.branchId != request.branchId ||
            result.isOpen ||
            result.closedBy != _scope.actor.userId ||
            row['request_id'] != request.requestId) {
          throw const FormatException('Unexpected closure');
        }
        return result;
      },
    );
  });

  @override
  Future<SaleReceipt> checkout(CheckoutRequest request) =>
      _scope.safe(() async {
        return _operations.mutate(
          function: 'checkout_sale',
          branchId: request.branchId,
          params: {
            ..._branchParams(request.branchId),
            'p_request_id': validateId(request.requestId),
            'p_payload': request.validatedPayload(),
          },
          decode: (row) {
            final result = receiptFromRow(row);
            _verifyScope(result.organizationId, result.branchId);
            if (result.branchId != request.branchId ||
                result.requestId != request.requestId ||
                result.actorUserId != _scope.actor.userId ||
                result.shiftId != request.shiftId) {
              throw const FormatException('Unexpected checkout confirmation');
            }
            return result;
          },
        );
      });

  @override
  Future<SaleReceipt?> findSaleByRequest({
    required String branchId,
    required String requestId,
  }) => _scope.safe(() async {
    final result = await _scope.client.rpc(
      'get_sale_by_request',
      params: {
        ..._branchParams(branchId),
        'p_request_id': validateId(requestId),
      },
    );
    if (result == null) return null;
    final row = rowFrom(result);
    final receipt = receiptFromRow(row);
    _verifyScope(receipt.organizationId, receipt.branchId);
    if (receipt.branchId != branchId ||
        receipt.requestId != requestId ||
        receipt.actorUserId != _scope.actor.userId) {
      throw const FormatException('Unexpected sale confirmation');
    }
    final pending = await _operations.pending(
      type: 'checkout_sale',
      branchId: branchId,
    );
    if (pending.any((op) => op.requestId == requestId)) {
      _scope.requireIdentity();
      await journal?.confirm(requestId: requestId, result: row);
    }
    return receipt;
  });

  @override
  Future<DataPage<SaleReceipt>> listSales({
    required String branchId,
    PageRequest page = const PageRequest(),
  }) => _scope.safe(() async {
    page.validate();
    final result = await _scope.client.rpc(
      'list_sales',
      params: {
        ..._branchParams(branchId),
        'p_query': '',
        'p_offset': page.offset,
        'p_limit': page.limit + 1,
      },
    );
    final data = pageFrom(rowsFrom(result), page, receiptFromRow);
    for (final receipt in data.items) {
      _verifyScope(receipt.organizationId, receipt.branchId);
    }
    return data;
  });

  @override
  Future<SaleReceipt> getSale(String saleId) => _scope.safe(() async {
    final receipt = receiptFromRow(
      rowFrom(
        await _scope.client.rpc(
          'get_sale',
          params: {
            'p_organization_id': _scope.organizationId,
            'p_sale_id': validateId(saleId),
          },
        ),
      ),
    );
    _verifyScope(receipt.organizationId, receipt.branchId);
    if (receipt.id != saleId) throw const FormatException('Unexpected sale');
    return receipt;
  });

  @override
  Future<SaleReversal> reverseSale(
    ReversalRequest request,
  ) => _scope.safe(() async {
    if (request.items.isEmpty ||
        request.items.length > 100 ||
        request.payments.length > 5) {
      throw const RepositoryFailure(
        RepositoryFailureType.validation,
        'Choose the returned items and original payment reversals.',
      );
    }
    final itemIds = <String>{};
    final paymentIds = <String>{};
    final items = request.items
        .map((item) {
          final id = validateId(item.saleItemId).toLowerCase();
          if (!itemIds.add(id)) {
            throw const RepositoryFailure(
              RepositoryFailureType.validation,
              'Choose each sale item once.',
            );
          }
          return {'sale_item_id': id, 'quantity': wholeQuantity(item.quantity)};
        })
        .toList(growable: false);
    final payments = request.payments
        .map((payment) {
          final id = validateId(payment.originalPaymentId).toLowerCase();
          if (!paymentIds.add(id) ||
              !payment.manualConfirmed ||
              payment.amountMinor <= 0) {
            throw const RepositoryFailure(
              RepositoryFailureType.validation,
              'Confirm each original payment reversal manually.',
            );
          }
          return {
            'original_payment_id': id,
            'amount_minor': validateMinor(payment.amountMinor),
            'manual_confirmed': true,
            'reference': optionalText(
              payment.reference,
              'Reversal reference',
              120,
            ),
          };
        })
        .toList(growable: false);
    return _operations.mutate(
      function: 'reverse_sale',
      branchId: request.branchId,
      params: {
        'p_organization_id': _scope.organizationId,
        'p_sale_id': validateId(request.saleId),
        'p_request_id': validateId(request.requestId),
        'p_payload': {
          'kind': request.kind == SaleReversalKind.refund ? 'refund' : 'void',
          'shift_id': validateId(request.shiftId),
          'items': items,
          'payments': payments,
          'reason': requiredText(
            request.reason,
            'Reversal reason',
            1000,
            minimum: 3,
          ),
          'return_stock': request.returnStock,
        },
      },
      decode: (row) {
        final reversal = reversalFromRow(row);
        if (reversal.saleId != request.saleId ||
            reversal.kind != request.kind ||
            reversal.returnStock != request.returnStock ||
            row['request_id'] != request.requestId ||
            row['actor_user_id'] != _scope.actor.userId ||
            row['shift_id'] != request.shiftId ||
            row['organization_id'] != _scope.organizationId ||
            row['branch_id'] != request.branchId ||
            reversal.sale == null) {
          throw const FormatException('Unexpected reversal');
        }
        if (reversal.sale != null) {
          _verifyScope(reversal.sale!.organizationId, reversal.sale!.branchId);
        }
        return reversal;
      },
    );
  });

  @override
  Future<List<PendingOperation>> pendingOperations({String? branchId}) =>
      _scope.safe(
        () async => (await _operations.pending(branchId: branchId))
            .where(
              (op) => const {
                'checkout_sale',
                'open_shift',
                'close_shift',
                'reverse_sale',
              }.contains(op.type),
            )
            .toList(growable: false),
      );

  @override
  Future<CheckoutRequest?> pendingCheckout(String branchId) =>
      _scope.safe(() async {
        final operations = await _operations.pending(
          type: 'checkout_sale',
          branchId: branchId,
        );
        if (operations.isEmpty) return null;
        final operation = operations.first;
        final payload = rowFrom(operation.payload['p_payload']);
        return CheckoutRequest(
          branchId: operation.branchId,
          requestId: operation.requestId,
          shiftId: payload['shift_id'] as String,
          expectedSettingsRevision: integerFrom(
            payload['expected_settings_revision'],
          ),
          discountMinor: integerFrom(payload['discount_minor']),
          reason: payload['reason'] as String?,
          customerId: payload['customer_id'] as String?,
          items: rowsFrom(payload['items'])
              .map(
                (i) => CheckoutItem(
                  productId: i['product_id'] as String,
                  quantity: integerFrom(i['quantity']),
                  expectedRevision: integerFrom(i['expected_revision']),
                ),
              )
              .toList(growable: false),
          payments: rowsFrom(payload['payments'])
              .map(
                (p) => CheckoutPayment(
                  method: paymentMethodFrom(p['method']),
                  amountMinor: integerFrom(p['amount_minor']),
                  tenderedMinor: p['tendered_minor'] == null
                      ? null
                      : integerFrom(p['tendered_minor']),
                  reference: p['reference'] as String?,
                  manualConfirmed: p['manual_confirmed'] == true,
                ),
              )
              .toList(growable: false),
        );
      });

  @override
  Future<Object> retryPending(PendingOperation operation) => _scope.safe(
    () async {
      if (!const {
            'checkout_sale',
            'open_shift',
            'close_shift',
            'reverse_sale',
          }.contains(operation.type) ||
          operation.organizationId != _scope.organizationId ||
          operation.actorId != _scope.actor.userId ||
          operation.payload['p_organization_id'] != _scope.organizationId ||
          operation.payload['p_request_id'] != operation.requestId ||
          !_scope.actor.branchIds.contains(operation.branchId)) {
        throw const RepositoryFailure(
          RepositoryFailureType.permissionDenied,
          'This pending operation belongs to another account or branch.',
        );
      }
      return _operations.mutate<Object>(
        function: operation.type,
        branchId: operation.branchId,
        params: Map<String, dynamic>.from(operation.payload),
        decode: (row) {
          switch (operation.type) {
            case 'checkout_sale':
              final receipt = receiptFromRow(row);
              _verifyScope(receipt.organizationId, receipt.branchId);
              if (receipt.requestId != operation.requestId ||
                  receipt.branchId != operation.branchId ||
                  receipt.actorUserId != _scope.actor.userId) {
                throw const FormatException('Unexpected checkout');
              }
              return receipt;
            case 'open_shift':
            case 'close_shift':
              final shift = shiftFromRow(row);
              _verifyScope(shift.organizationId, shift.branchId);
              if (shift.branchId != operation.branchId ||
                  (operation.type == 'open_shift' &&
                      (shift.actorUserId != _scope.actor.userId ||
                          row['request_id'] != operation.requestId)) ||
                  (operation.type == 'close_shift' &&
                      (shift.isOpen ||
                          shift.id != operation.payload['p_shift_id'] ||
                          shift.closedBy != _scope.actor.userId ||
                          row['request_id'] != operation.requestId))) {
                throw const FormatException('Unexpected shift');
              }
              return shift;
            case 'reverse_sale':
              final reversal = reversalFromRow(row);
              if (reversal.saleId != operation.payload['p_sale_id'] ||
                  reversal.sale == null ||
                  row['request_id'] != operation.requestId ||
                  row['actor_user_id'] != _scope.actor.userId ||
                  row['shift_id'] !=
                      rowFrom(operation.payload['p_payload'])['shift_id'] ||
                  row['kind'] !=
                      rowFrom(operation.payload['p_payload'])['kind'] ||
                  row['return_stock'] !=
                      rowFrom(operation.payload['p_payload'])['return_stock']) {
                throw const FormatException('Unexpected reversal');
              }
              _verifyScope(
                reversal.sale!.organizationId,
                reversal.sale!.branchId,
              );
              return reversal;
            default:
              throw const RepositoryFailure(
                RepositoryFailureType.validation,
                'This pending operation cannot be retried here.',
              );
          }
        },
      );
    },
  );
}
