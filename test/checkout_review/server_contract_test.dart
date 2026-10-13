import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:nexapos/features/checkout/data/checkout_decoders.dart';
import 'package:nexapos/features/checkout/domain/checkout_models.dart';
import 'package:nexapos/features/inventory/data/supabase_inventory_repository.dart';

// Captured from real migrated PostgreSQL RPC calls using test-only Auth mocks.
// collect_server_contract.sql creates fresh records in a rollback-only
// transaction. This fixture is never loaded by the application.
final _fixture =
    jsonDecode(
          File('test/fixtures/phase3_rpc_contract.json').readAsStringSync(),
        )
        as Map<String, dynamic>;
Map<String, dynamic> _row(String name) =>
    _fixture[name] as Map<String, dynamic>;
List<Map<String, dynamic>> _rows(String name) =>
    (_fixture[name] as List).cast<Map<String, dynamic>>();

void main() {
  group('Actual PostgreSQL Phase 3 response contracts', () {
    test('cashier context and product responses decode with masked costs', () {
      final context = contextFromRow(_row('context'));
      final cashierContext = contextFromRow(_row('cashier_context'));
      expect(context.branchId, _row('meta')['branch_id']);
      expect(context.businessName, 'Server contract fixture');
      expect(context.taxBps, 5000);
      expect(context.settingsRevision, 2);
      expect(context.receiptFooter, 'Contract footer');
      expect(cashierContext.businessName, context.businessName);
      final products = _rows(
        'products_before_sale',
      ).map(posProductFromRow).toList();
      expect(products, hasLength(2));
      expect(products.every((product) => product.costMinor != null), isTrue);
      expect(products.every((product) => product.revision == 2), isTrue);
      final cashierProducts = _rows(
        'cashier_products',
      ).map(posProductFromRow).toList();
      expect(cashierProducts, hasLength(1));
      expect(cashierProducts.single.costMinor, isNull);
      expect(
        posProductFromRow(_row('barcode_product')).barcode,
        'CONTRACT-FIRST',
      );
    });

    test(
      'actual stock mutation responses retain scope and request identity',
      () {
        for (final name in ['stock_receive', 'stock_adjust']) {
          final row = _row(name);
          final operation = stockOperationFromRow(row);
          expect(operation.organizationId, _row('meta')['organization_id']);
          expect(operation.branchId, _row('meta')['branch_id']);
          expect(operation.actorUserId, _row('meta')['owner_id']);
          expect(row['request_id'], isNotNull);
          expect(operation.movements, isNotEmpty);
          expect(
            operation.movements.every((movement) => movement.quantityDelta > 0),
            isTrue,
          );
        }
        expect(
          stockOperationFromRow(_row('stock_receive')).movements,
          hasLength(2),
        );
        expect(stockOperationFromRow(_row('stock_adjust')).kind, 'adjust');
      },
    );

    test('shift open and close decode the server cash projection', () {
      final opened = shiftFromRow(_row('shift_open'));
      final closed = shiftFromRow(_row('shift_closed'));
      expect(opened.isOpen, isTrue);
      expect(opened.openingCashMinor, 0);
      expect(opened.expectedCashMinor, 0);
      expect(closed.id, opened.id);
      expect(closed.isOpen, isFalse);
      expect(closed.expectedCashMinor, 3);
      expect(closed.countedCashMinor, 3);
      expect(closed.cashDifferenceMinor, 0);
      expect(
        _row('shift_closed')['request_id'],
        '91000000-0000-4000-8000-000000000005',
      );
    });

    test('historical cash refund preserves a signed drawer deficit', () {
      final negative = shiftFromRow(_row('shift_negative'));
      final counted = shiftFromRow(_row('shift_closed_after_refund'));
      expect(negative.openingCashMinor, 0);
      expect(negative.expectedCashMinor, -3);
      expect(counted.expectedCashMinor, -3);
      expect(counted.countedCashMinor, 0);
      expect(counted.cashDifferenceMinor, 3);
      expect(counted.isOpen, isFalse);
    });

    test('large exact SQL discount agrees with Dart integer calculations', () {
      final receipt = receiptFromRow(_row('sale'));
      final recalculated = CartTotals.calculate(
        lines: [
          for (final item in receipt.items)
            CartLine(
              product: PosProduct(
                id: item.productId,
                organizationId: receipt.organizationId,
                name: item.name,
                sku: item.sku,
                priceMinor: item.unitPriceMinor,
                currency: receipt.currency,
                unit: 'each',
                revision: 2,
                availableQuantity: item.quantity,
              ),
              quantity: item.quantity,
            ),
        ],
        discountMinor: receipt.discountMinor,
        taxBps: receipt.taxBps,
      );
      expect(receipt.requestId, '91000000-0000-4000-8000-000000000004');
      expect(receipt.receiptNumber, 'MAIN-000001');
      expect(receipt.subtotalMinor, maximumExactInteger);
      expect(receipt.items.map((item) => item.discountMinor), [
        4503599627370494,
        4503599627370495,
      ]);
      expect(receipt.items.map((item) => item.taxMinor), [1, 0]);
      expect(receipt.taxMinor, 1);
      expect(receipt.totalMinor, 3);
      expect(recalculated.totalMinor, receipt.totalMinor);
      expect(recalculated.taxMinor, receipt.taxMinor);
      expect(receipt.payments.single.tenderedMinor, 5);
      expect(receipt.payments.single.changeMinor, 2);
      expect(receipt.payments.single.amountMinor, 3);
      expect(_row('sale_by_request')['id'], receipt.id);
      expect(
        (_row('sale')['items'] as List).every(
          (item) => !(item as Map).containsKey('cost_minor'),
        ),
        isTrue,
      );
    });

    test(
      'reversal decodes while the original sale snapshot stays unchanged',
      () {
        final original = receiptFromRow(_row('sale'));
        final reversal = reversalFromRow(_row('reversal'));
        final updated = receiptFromRow(_row('sale_after_refund'));
        expect(reversal.kind, SaleReversalKind.refund);
        expect(reversal.saleId, original.id);
        expect(reversal.totalMinor, 3);
        expect(reversal.returnStock, isTrue);
        expect(reversal.sale?.id, original.id);
        expect(updated.totalMinor, original.totalMinor);
        expect(updated.businessName, original.businessName);
        expect(updated.receiptFooter, original.receiptFooter);
        expect(
          updated.items.every((item) => item.refundableQuantity == 0),
          isTrue,
        );
        expect(updated.payments.single.refundableMinor, 0);
        expect(
          _row('reversal')['request_id'],
          '91000000-0000-4000-8000-000000000007',
        );
      },
    );

    test('ledger projection keeps positive inactive stock visible', () {
      final inventory = _rows('inventory').map(posProductFromRow).toList();
      expect(inventory, hasLength(2));
      final inactive = inventory.singleWhere((product) => !product.active);
      expect(inactive.id, _row('meta')['low_product_id']);
      expect(inactive.availableQuantity, 2);
      final movements = _rows('movements').map(stockMovementFromRow).toList();
      expect(movements, hasLength(7));
      expect(
        movements.where((movement) => movement.quantityDelta < 0),
        hasLength(2),
      );
      expect(
        movements.fold<int>(0, (sum, movement) => sum + movement.quantityDelta),
        3,
      );
      expect(
        inventory.fold<int>(
          0,
          (sum, product) => sum + product.availableQuantity,
        ),
        3,
      );
      expect(movements.every((movement) => movement.kind != null), isTrue);
    });

    test(
      'list responses decode and cashier history excludes another actor',
      () {
        final sales = _rows('sales_list').map(receiptFromRow).toList();
        final shifts = _rows('shifts_list').map(shiftFromRow).toList();
        expect(sales, hasLength(1));
        expect(shifts, hasLength(2));
        expect(shifts.every((shift) => !shift.isOpen), isTrue);
        expect(_rows('cashier_sales'), isEmpty);
      },
    );
  });
}
