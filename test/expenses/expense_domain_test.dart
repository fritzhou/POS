import 'package:flutter_test/flutter_test.dart';
import 'package:nexapos/features/catalog/domain/repository_support.dart';
import 'package:nexapos/features/checkout/domain/checkout_models.dart';
import 'package:nexapos/features/expenses/data/expense_decoders.dart';
import 'package:nexapos/features/expenses/domain/expense_models.dart';

import 'expense_fixtures.dart';

RecordExpenseRequest requestWith({
  int amount = 1,
  int revision = 1,
  String currency = 'PHP',
  ExpenseSource source = ExpenseSource.external,
  String? shift,
  CheckoutPaymentMethod method = CheckoutPaymentMethod.cash,
  bool confirmed = true,
  String? reference,
  String reason = 'Physical evidence',
}) => RecordExpenseRequest(
  branchId: expenseBranch,
  expectedSettingsRevision: revision,
  currency: currency,
  amountMinor: amount,
  category: ExpenseCategory.other,
  paymentMethod: method,
  source: source,
  shiftId: shift,
  manualConfirmed: confirmed,
  reason: reason,
  reference: reference,
);
void main() {
  test(
    'SQL context original reversal and current detail decode actual output',
    () {
      final fixture = expenseSqlFixture();
      expect(fixture['version'], 1);
      final context = expenseContextFromRow(fixture['context']);
      final original = expenseFromRow(fixture['record_action']['expense']);
      final reversal = expenseReversalFromRow(
        fixture['reversal_action']['reversal'],
      );
      final current = expenseFromRow(fixture['current_expense']);
      expect(context.organizationId, original.organizationId);
      expect(context.ownOpenShift?.id, original.shiftId);
      expect(context.ownOpenShift?.actorUserId, original.actorUserId);
      expect(original.reversal, isNull);
      expect(current.reversal?.id, reversal.id);
      expect(current.netAmountMinor, 0);
      expect(current.immutableProof(), original.immutableProof());
      expect(reversal.amountMinor, original.amountMinor);
      expect(reversal.createdAt.isUtc, isTrue);
    },
  );
  test(
    'positive exact money permits maximum and rejects zero negative overflow',
    () {
      expect(
        requestWith(
          amount: maximumExactInteger,
        ).parameters(expenseOrg)['p_amount_minor'],
        maximumExactInteger,
      );
      for (final amount in [0, -1, maximumExactInteger + 1]) {
        expect(
          () => requestWith(amount: amount).parameters(expenseOrg),
          throwsA(isA<RepositoryFailure>()),
        );
      }
      expect(
        () => requestWith(
          revision: maximumExactInteger + 1,
        ).parameters(expenseOrg),
        throwsA(isA<RepositoryFailure>()),
      );
      expect(Money.parseMinor('90071992547409.91'), maximumExactInteger);
      expect(
        () => Money.parseMinor('90071992547409.92'),
        throwsA(isA<RepositoryFailure>()),
      );
      expect(
        () => Money.parseMinor('1.001'),
        throwsA(isA<RepositoryFailure>()),
      );
    },
  );
  test('supported currencies and physically confirmed source are required', () {
    for (final currency in ['PHP', 'USD', 'EUR', 'GBP', 'AUD', 'CAD', 'SGD']) {
      expect(
        requestWith(currency: currency).parameters(expenseOrg)['p_currency'],
        currency,
      );
    }
    for (final request in [
      requestWith(currency: 'JPY'),
      requestWith(confirmed: false),
      requestWith(source: ExpenseSource.cashDrawer),
      requestWith(shift: expenseShift),
      requestWith(
        source: ExpenseSource.cashDrawer,
        shift: expenseShift,
        method: CheckoutPaymentMethod.card,
        reference: 'CARD-REF',
      ),
    ]) {
      expect(
        () => request.parameters(expenseOrg),
        throwsA(isA<RepositoryFailure>()),
      );
    }
    expect(
      requestWith(
        source: ExpenseSource.cashDrawer,
        shift: expenseShift,
      ).parameters(expenseOrg)['p_shift_id'],
      expenseShift,
    );
    expect(requestWith().parameters(expenseOrg)['p_shift_id'], isNull);
  });
  test(
    'noncash uses a verified reference and ordinary multiline reasons roundtrip',
    () {
      for (final reference in [null, '', 'ab']) {
        expect(
          () => requestWith(
            method: CheckoutPaymentMethod.gcash,
            reference: reference,
          ).parameters(expenseOrg),
          throwsA(isA<RepositoryFailure>()),
        );
      }
      final params = requestWith(
        method: CheckoutPaymentMethod.gcash,
        reference: '  REF-123  ',
        reason: ' Receipt checked\nCash paid\tconfirmed ',
      ).parameters(expenseOrg);
      final wire = expenseWire()
        ..['reason'] = params['p_reason']
        ..['payment_method'] = 'gcash'
        ..['reference'] = params['p_reference'];
      expect(
        expenseFromRow(wire).reason,
        'Receipt checked\nCash paid\tconfirmed',
      );
      expect(params['p_reference'], 'REF-123');
      expect(
        () => requestWith(reason: 'bad\u0000reason').parameters(expenseOrg),
        throwsA(isA<RepositoryFailure>()),
      );
      wire['reason'] = 'bad\u0000reason';
      expect(() => expenseFromRow(wire), throwsFormatException);
    },
  );
  final invalidIntegers = <Object?>[
    null,
    '12345',
    12345.0,
    0,
    -1,
    maximumExactInteger + 1,
  ];
  for (final value in invalidIntegers) {
    test('decoder rejects nonpositive or inexact amount $value', () {
      final wire = expenseWire()..['amount_minor'] = value;
      expect(() => expenseFromRow(wire), throwsFormatException);
    });
  }
  test('UTC calendar and exact evidence are strict', () {
    for (final time in [
      '2026-02-31T00:00:00Z',
      '2026-10-11T00:00:00+08:00',
      '2026-10-11T24:00:00Z',
      '2026-10-11',
    ]) {
      expect(() => expenseUtcTime(time), throwsFormatException);
    }
    expect(expenseUtcTime('2026-10-11T01:00:00.123456+00:00').microsecond, 456);
    for (final edit in <void Function(Map<String, dynamic>)>[
      (w) => w['manual_confirmed'] = false,
      (w) => w['source'] = 'cash_drawer',
      (w) => w['currency'] = 'JPY',
      (w) => w['unknown'] = 'value',
      (w) => w['occurred_at'] = '2026-10-11T02:00:00Z',
    ]) {
      final wire = expenseWire();
      edit(wire);
      expect(
        () => expenseFromRow(wire),
        throwsA(anyOf(isA<FormatException>(), isA<RepositoryFailure>())),
      );
    }
  });
  test(
    'full compensation matches scope currency original amount source shift actor',
    () {
      for (final edit in <void Function(Map<String, dynamic>)>[
        (w) => w['reversal']['amount_minor'] = 1,
        (w) => w['reversal']['currency'] = 'USD',
        (w) => w['reversal']['branch_id'] = otherExpenseActor,
        (w) => w['reversal']['shift_id'] = otherExpenseActor,
        (w) => w['reversal']['actor_user_id'] = otherExpenseActor,
      ]) {
        final wire = expenseWire(drawer: true, reversed: true);
        edit(wire);
        expect(() => expenseFromRow(wire), throwsFormatException);
      }
      expect(
        () => ReverseExpenseRequest(
          original: expenseFromRow(expenseWire(reversed: true)),
          reason: 'Correction',
          manualConfirmed: true,
        ).parameters(expenseOrg),
        throwsA(isA<RepositoryFailure>()),
      );
      expect(
        () => ReverseExpenseRequest(
          original: expenseFromRow(expenseWire()),
          reason: 'Correction',
          manualConfirmed: false,
        ).parameters(expenseOrg),
        throwsA(isA<RepositoryFailure>()),
      );
    },
  );
  test('UTC half open date filter validates bounded ordered paired window', () {
    ExpenseFilter(
      from: DateTime.utc(2026),
      to: DateTime.utc(2026).add(const Duration(days: 366)),
    ).validate();
    for (final filter in [
      ExpenseFilter(from: DateTime.utc(2026)),
      ExpenseFilter(from: DateTime.utc(2026), to: DateTime.utc(2026)),
      ExpenseFilter(
        from: DateTime.utc(2026),
        to: DateTime.utc(2026).add(const Duration(days: 367)),
      ),
      ExpenseFilter(from: DateTime(2026), to: DateTime(2026, 2)),
    ]) {
      expect(filter.validate, throwsA(isA<RepositoryFailure>()));
    }
  });
}
