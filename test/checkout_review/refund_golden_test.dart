import 'package:flutter_test/flutter_test.dart';
import 'package:nexapos/features/checkout/domain/checkout_models.dart';
import 'package:nexapos/features/checkout/domain/refund_selection.dart';

const _item = '10000000-0000-4000-8000-000000000001';
const _cash = '10000000-0000-4000-8000-000000000002';
const _card = '10000000-0000-4000-8000-000000000003';
const _paidItem = '10000000-0000-4000-8000-000000000004';
const _sale = '20000000-0000-4000-8000-000000000001';
const _organization = '20000000-0000-4000-8000-000000000002';
const _branch = '20000000-0000-4000-8000-000000000003';
const _shift = '20000000-0000-4000-8000-000000000004';
const _actor = '20000000-0000-4000-8000-000000000005';

SaleReceipt _receipt({
  int used = 0,
  int reversed = 0,
  int quantity = 3,
  int unitPrice = 4,
  int subtotal = 12,
  int discount = 3,
  int tax = 1,
  int total = 10,
  int taxBps = 1000,
  List<SaleItem>? items,
  List<SalePayment>? payments,
}) => SaleReceipt(
  id: _sale,
  organizationId: _organization,
  branchId: _branch,
  shiftId: _shift,
  actorUserId: _actor,
  receiptNumber: 'CONTRACT-1',
  currency: 'PHP',
  createdAt: DateTime.utc(2026, 10, 9),
  subtotalMinor: subtotal,
  discountMinor: discount,
  taxBps: taxBps,
  taxMinor: tax,
  totalMinor: total,
  items:
      items ??
      [
        SaleItem(
          id: _item,
          productId: _item,
          name: 'Original receipt fixture',
          sku: 'CONTRACT',
          quantity: quantity,
          unitPriceMinor: unitPrice,
          subtotalMinor: subtotal,
          discountMinor: discount,
          taxMinor: tax,
          totalMinor: total,
          reversedQuantity: used,
        ),
      ],
  payments:
      payments ??
      [
        SalePayment(
          id: _cash,
          method: CheckoutPaymentMethod.cash,
          amountMinor: total,
          reversedMinor: reversed,
        ),
      ],
);

void main() {
  group('Independent original-receipt refund golden cases', () {
    test('discounted taxed units release the final minor-unit remainder', () {
      final amounts = <int>[];
      for (final state in [(0, 0), (1, 3), (2, 6)]) {
        final selection = RefundSelection.calculate(
          receipt: _receipt(used: state.$1, reversed: state.$2),
          quantities: {_item: 1},
        );
        amounts.add(selection.totalMinor);
        expect(selection.allocations.single.amountMinor, selection.totalMinor);
        expect(selection.items.single.quantity, 1);
      }
      expect(amounts, [3, 3, 4]);
      expect(amounts.reduce((sum, amount) => sum + amount), 10);
    });

    test('allocation uses the original tax-inclusive amount as one total', () {
      // Net 5 + original tax 1, divided over three units. Separately dividing
      // net and tax would produce [1, 2, 3]; the server contract is [2, 2, 2].
      final amounts = <int>[];
      for (final state in [(0, 0), (1, 2), (2, 4)]) {
        final selection = RefundSelection.calculate(
          receipt: _receipt(
            used: state.$1,
            reversed: state.$2,
            unitPrice: 2,
            subtotal: 6,
            discount: 1,
            tax: 1,
            total: 6,
            taxBps: 1200,
          ),
          quantities: {_item: 1},
        );
        amounts.add(selection.totalMinor);
      }
      expect(amounts, [2, 2, 2]);
    });

    test(
      'returning all remaining units pays the complete original balance',
      () {
        final selection = RefundSelection.calculate(
          receipt: _receipt(used: 1, reversed: 3),
          quantities: {_item: 2},
        );
        expect(selection.totalMinor, 7);
        expect(selection.allocations.single.amountMinor, 7);
      },
    );

    test(
      'split payouts stay within each original payment remaining amount',
      () {
        final selection = RefundSelection.calculate(
          receipt: _receipt(
            used: 1,
            payments: const [
              SalePayment(
                id: _card,
                method: CheckoutPaymentMethod.card,
                amountMinor: 6,
                reference: 'Original manual terminal reference',
              ),
              SalePayment(
                id: _cash,
                method: CheckoutPaymentMethod.cash,
                amountMinor: 4,
                reversedMinor: 3,
              ),
            ],
          ),
          quantities: {_item: 1},
        );
        expect(selection.totalMinor, 3);
        expect(
          selection.allocations.map((allocation) => allocation.amountMinor),
          [1, 2],
        );
        expect(
          selection.allocations.map(
            (allocation) => allocation.originalPayment.id,
          ),
          [_cash, _card],
        );
        expect(
          selection.allocations.last.originalPayment.method,
          CheckoutPaymentMethod.card,
        );
      },
    );

    test('a fully discounted item can return stock without a money payout', () {
      final selection = RefundSelection.calculate(
        receipt: _receipt(
          quantity: 1,
          unitPrice: 1,
          subtotal: 6,
          discount: 1,
          tax: 0,
          total: 5,
          taxBps: 0,
          items: const [
            SaleItem(
              id: _item,
              productId: _item,
              name: 'Fully discounted fixture',
              sku: 'FREE-LINE',
              quantity: 1,
              unitPriceMinor: 1,
              subtotalMinor: 1,
              discountMinor: 1,
              taxMinor: 0,
              totalMinor: 0,
            ),
            SaleItem(
              id: _paidItem,
              productId: _paidItem,
              name: 'Paid fixture',
              sku: 'PAID-LINE',
              quantity: 1,
              unitPriceMinor: 5,
              subtotalMinor: 5,
              discountMinor: 0,
              taxMinor: 0,
              totalMinor: 5,
            ),
          ],
        ),
        quantities: {_item: 1},
      );
      expect(selection.items.single.saleItemId, _item);
      expect(selection.totalMinor, 0);
      expect(selection.allocations, isEmpty);
    });

    test(
      'large cumulative quantities never overflow an integer intermediate',
      () {
        final selection = RefundSelection.calculate(
          receipt: _receipt(
            used: 999999,
            reversed: 9007190246600746,
            quantity: 1000000,
            unitPrice: 8188362958,
            subtotal: 8188362958000000,
            discount: 0,
            tax: 818836295800000,
            total: 9007199253800000,
          ),
          quantities: {_item: 1},
        );
        expect(selection.totalMinor, 9007199254);
        expect(selection.allocations.single.amountMinor, 9007199254);
      },
    );
  });
}
