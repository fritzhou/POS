import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:nexapos/features/catalog/domain/repository_support.dart';
import 'package:nexapos/features/checkout/domain/checkout_models.dart';
import 'package:nexapos/features/inventory/domain/inventory_models.dart';

const org = '11111111-1111-1111-1111-111111111111';
const branch = '22222222-2222-2222-2222-222222222222';
const shift = '33333333-3333-3333-3333-333333333333';
const first = 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa';
const second = 'bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb';

PosProduct product(String id, int price, {String currency = 'PHP'}) =>
    PosProduct(
      id: id,
      organizationId: org,
      name: 'Test product',
      sku: id,
      priceMinor: price,
      currency: currency,
      unit: 'each',
      revision: 2,
      availableQuantity: 100,
    );

void main() {
  test('tax-exclusive totals and proportional discounts use integer cents', () {
    final totals = CartTotals.calculate(
      lines: [
        CartLine(product: product(second, 199), quantity: 2),
        CartLine(product: product(first, 105), quantity: 3),
      ],
      taxBps: 1200,
      discountMinor: 100,
    );
    expect(totals.subtotalMinor, 713);
    expect(totals.lines.map((line) => line.discountMinor), [44, 56]);
    expect(totals.lines.map((line) => line.taxMinor), [33, 41]);
    expect(totals.totalMinor, 687);
    expect(
      totals.lines.fold<int>(0, (sum, line) => sum + line.totalMinor),
      totals.totalMinor,
    );
  });
  test('one tiny last line never absorbs an invalid discount remainder', () {
    final totals = CartTotals.calculate(
      lines: [
        CartLine(product: product(first, 10000), quantity: 1),
        CartLine(product: product(second, 1), quantity: 1),
      ],
      taxBps: 0,
      discountMinor: 10000,
    );
    expect(totals.lines.map((line) => line.discountMinor), [9999, 1]);
    expect(totals.lines.every((line) => line.totalMinor >= 0), isTrue);
    expect(totals.totalMinor, 1);
  });
  test('tax rounds half-up separately per discounted line', () {
    final totals = CartTotals.calculate(
      lines: [
        CartLine(product: product(first, 5), quantity: 1),
        CartLine(product: product(second, 4), quantity: 1),
      ],
      taxBps: 1000,
    );
    expect(totals.lines.map((line) => line.taxMinor), [1, 0]);
    expect(totals.taxMinor, 1);
  });
  test('UUID case cannot change allocation or create a duplicate line', () {
    expect(
      () => CartTotals.calculate(
        lines: [
          CartLine(product: product(first, 5), quantity: 1),
          CartLine(product: product(first.toUpperCase(), 5), quantity: 1),
        ],
        taxBps: 0,
      ),
      throwsA(isA<RepositoryFailure>()),
    );
    final request = CheckoutRequest(
      branchId: branch,
      shiftId: shift,
      expectedSettingsRevision: 1,
      items: [
        CheckoutItem(
          productId: first.toUpperCase(),
          quantity: 1,
          expectedRevision: 1,
        ),
      ],
      payments: [
        const CheckoutPayment(
          method: CheckoutPaymentMethod.cash,
          amountMinor: 5,
          tenderedMinor: 5,
        ),
      ],
    );
    expect(
      (request.validatedPayload()['items'] as List).single['product_id'],
      first,
    );
  });
  test('zero total and over-discount cannot open a payment flow', () {
    for (final discount in [10, 11]) {
      expect(
        () => CartTotals.calculate(
          lines: [CartLine(product: product(first, 10), quantity: 1)],
          taxBps: 0,
          discountMinor: discount,
        ),
        throwsA(isA<RepositoryFailure>()),
      );
    }
  });
  test(
    'overflow is rejected without floating point intermediate arithmetic',
    () {
      expect(
        () => CartTotals.calculate(
          lines: [
            CartLine(product: product(first, maximumExactInteger), quantity: 2),
          ],
          taxBps: 0,
        ),
        throwsA(isA<RepositoryFailure>()),
      );
      expect(
        () => CartTotals.calculate(
          lines: [
            CartLine(product: product(first, maximumExactInteger), quantity: 1),
          ],
          taxBps: 1,
        ),
        throwsA(isA<RepositoryFailure>()),
      );
    },
  );
  test('mixed or unsupported precision currencies are rejected', () {
    expect(
      () => CartTotals.calculate(
        lines: [
          CartLine(product: product(first, 100), quantity: 1),
          CartLine(product: product(second, 100, currency: 'USD'), quantity: 1),
        ],
        taxBps: 0,
      ),
      throwsA(isA<RepositoryFailure>()),
    );
    expect(
      () => CartTotals.calculate(
        lines: [
          CartLine(product: product(first, 100, currency: 'JPY'), quantity: 1),
        ],
        taxBps: 0,
      ),
      throwsA(isA<RepositoryFailure>()),
    );
  });
  test('quantities are whole positive units with bounded transaction size', () {
    for (final quantity in [0, -1, 1000001]) {
      expect(() => wholeQuantity(quantity), throwsA(isA<RepositoryFailure>()));
    }
    expect(wholeQuantity(1000000), 1000000);
    expect(signedQuantity(-1000000), -1000000);
    expect(() => signedQuantity(0), throwsA(isA<RepositoryFailure>()));
  });
  test('cash requires counted tender covering applied payment', () {
    expect(
      () => const CheckoutPayment(
        method: CheckoutPaymentMethod.cash,
        amountMinor: 500,
        tenderedMinor: 499,
      ).validatedValues(),
      throwsA(isA<RepositoryFailure>()),
    );
    expect(
      const CheckoutPayment(
        method: CheckoutPaymentMethod.cash,
        amountMinor: 500,
        tenderedMinor: 1000,
      ).validatedValues(),
      {'method': 'cash', 'amount_minor': 500, 'tendered_minor': 1000},
    );
  });
  test(
    'digital methods require operator confirmation and actual reference',
    () {
      for (final method in CheckoutPaymentMethod.values.where(
        (m) => m != CheckoutPaymentMethod.cash,
      )) {
        expect(
          () => CheckoutPayment(
            method: method,
            amountMinor: 100,
            reference: 'ref-123',
          ).validatedValues(),
          throwsA(isA<RepositoryFailure>()),
        );
        expect(
          () => CheckoutPayment(
            method: method,
            amountMinor: 100,
            manualConfirmed: true,
            reference: 'x',
          ).validatedValues(),
          throwsA(isA<RepositoryFailure>()),
        );
        final values = CheckoutPayment(
          method: method,
          amountMinor: 100,
          manualConfirmed: true,
          reference: ' ref-123 ',
        ).validatedValues();
        expect(values['manual_confirmed'], true);
        expect(values['reference'], 'ref-123');
        expect(values.containsKey('provider_authorized'), false);
      }
    },
  );
  test('request freezes lists and stable sorted payload across retries', () {
    final items = [
      const CheckoutItem(productId: second, quantity: 1, expectedRevision: 2),
      const CheckoutItem(productId: first, quantity: 2, expectedRevision: 2),
    ];
    final payments = [
      const CheckoutPayment(
        method: CheckoutPaymentMethod.cash,
        amountMinor: 100,
        tenderedMinor: 100,
      ),
    ];
    final request = CheckoutRequest(
      branchId: branch,
      shiftId: shift,
      expectedSettingsRevision: 3,
      items: items,
      payments: payments,
    );
    final before = jsonEncode(request.validatedPayload());
    items.clear();
    payments.clear();
    expect(jsonEncode(request.validatedPayload()), before);
    expect(request.requestId, isNotEmpty);
    expect(() => request.items.clear(), throwsUnsupportedError);
  });
  test('discount request requires a meaningful explanation', () {
    final request = CheckoutRequest(
      branchId: branch,
      shiftId: shift,
      expectedSettingsRevision: 3,
      items: [
        const CheckoutItem(productId: first, quantity: 1, expectedRevision: 2),
      ],
      discountMinor: 1,
      reason: 'x',
      payments: [
        const CheckoutPayment(
          method: CheckoutPaymentMethod.cash,
          amountMinor: 99,
          tenderedMinor: 99,
        ),
      ],
    );
    expect(request.validatedPayload, throwsA(isA<RepositoryFailure>()));
  });
}
