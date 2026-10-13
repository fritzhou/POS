import 'package:flutter_test/flutter_test.dart';
import 'package:nexapos/features/catalog/domain/repository_support.dart';
import 'package:nexapos/features/checkout/domain/checkout_models.dart';

const _first = '10000000-0000-4000-8000-000000000001';
const _second = '10000000-0000-4000-8000-000000000002';
const _third = '10000000-0000-4000-8000-000000000003';
const _organization = '20000000-0000-4000-8000-000000000001';

CartLine _line(String id, int price, {int quantity = 1}) => CartLine(
  product: PosProduct(
    id: id,
    organizationId: _organization,
    name: 'Contract fixture',
    sku: id,
    priceMinor: price,
    currency: 'PHP',
    unit: 'each',
    revision: 1,
    availableQuantity: quantity,
  ),
  quantity: quantity,
);

void main() {
  group('Independent financial golden cases', () {
    test('half a minor unit of line tax rounds up', () {
      final totals = CartTotals.calculate(
        lines: [_line(_first, 5)],
        taxBps: 1000,
      );
      expect(totals.subtotalMinor, 5);
      expect(totals.taxMinor, 1);
      expect(totals.totalMinor, 6);
    });

    test('tax rounds on each line rather than the whole basket', () {
      final totals = CartTotals.calculate(
        lines: [_line(_first, 1), _line(_second, 1)],
        taxBps: 5000,
      );
      expect(totals.lines.map((line) => line.taxMinor), [1, 1]);
      expect(totals.taxMinor, 2);
      expect(totals.totalMinor, 4);
    });

    test(
      'discount allocation and tax match the published integer contract',
      () {
        final totals = CartTotals.calculate(
          lines: [_line(_third, 999), _line(_first, 333), _line(_second, 667)],
          discountMinor: 333,
          taxBps: 1200,
        );
        expect(totals.lines.map((line) => line.line.product.id), [
          _first,
          _second,
          _third,
        ]);
        expect(totals.lines.map((line) => line.discountMinor), [55, 111, 167]);
        expect(totals.lines.map((line) => line.taxMinor), [33, 67, 100]);
        expect(totals.lines.map((line) => line.totalMinor), [311, 623, 932]);
        expect(totals.subtotalMinor, 1999);
        expect(totals.discountMinor, 333);
        expect(totals.taxMinor, 200);
        expect(totals.totalMinor, 1866);
      },
    );

    test('a tiny final line receives its exact discount remainder', () {
      final totals = CartTotals.calculate(
        lines: [_line(_first, 999), _line(_second, 1)],
        discountMinor: 999,
        taxBps: 5000,
      );
      expect(totals.lines.map((line) => line.discountMinor), [998, 1]);
      expect(totals.lines.map((line) => line.taxMinor), [1, 0]);
      expect(totals.totalMinor, 2);
    });

    test('discount products larger than exact integer range remain exact', () {
      final totals = CartTotals.calculate(
        lines: [
          _line(_first, 4503599627370495),
          _line(_second, 4503599627370496),
        ],
        discountMinor: 9007199254740990,
        taxBps: 5000,
      );
      expect(totals.subtotalMinor, maximumExactInteger);
      expect(totals.lines.map((line) => line.discountMinor), [
        4503599627370494,
        4503599627370496,
      ]);
      expect(totals.taxMinor, 1);
      expect(totals.totalMinor, 2);
    });

    test('price multiplied by quantity accepts the last safe product', () {
      final totals = CartTotals.calculate(
        lines: [_line(_first, 3002399751580330, quantity: 3)],
        taxBps: 0,
      );
      expect(totals.totalMinor, 9007199254740990);
    });

    test('a proportion just below a large integer never rounds up', () {
      // PostgreSQL floor(numeric / numeric) can round this ratio up before
      // floor runs. The server must use exact div(numeric, numeric).
      final totals = CartTotals.calculate(
        lines: [
          _line(_first, 4503599627370496),
          _line(_second, 4503599627370495),
        ],
        discountMinor: 9007199254740989,
        taxBps: 5000,
      );
      expect(totals.lines.map((line) => line.discountMinor), [
        4503599627370494,
        4503599627370495,
      ]);
      expect(totals.lines.map((line) => line.taxMinor), [1, 0]);
      expect(totals.totalMinor, 3);
    });

    test(
      'quantity multiplication cannot cross the transport integer limit',
      () {
        expect(
          () => CartTotals.calculate(
            lines: [_line(_first, maximumExactInteger, quantity: 2)],
            taxBps: 0,
          ),
          throwsA(isA<RepositoryFailure>()),
        );
      },
    );

    test('tax cannot make a valid subtotal overflow the transport limit', () {
      expect(
        () => CartTotals.calculate(
          lines: [_line(_first, maximumExactInteger)],
          taxBps: 1,
        ),
        throwsA(isA<RepositoryFailure>()),
      );
    });
  });
}
