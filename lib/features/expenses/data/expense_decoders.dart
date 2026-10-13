import '../../catalog/data/supabase_repository_support.dart';
import '../../catalog/domain/repository_support.dart';
import '../../checkout/domain/checkout_models.dart';
import '../domain/expense_models.dart';

int expenseInteger(
  Object? value, {
  bool signed = false,
  bool positive = false,
}) {
  if (value is! int ||
      BigInt.from(value).abs() > BigInt.from(maximumExactInteger) ||
      !signed && value < 0 ||
      positive && value < 1) {
    throw const FormatException('Invalid exact expense integer');
  }
  return value;
}

DateTime expenseUtcTime(Object? value) {
  if (value is! String) throw const FormatException('Invalid UTC expense time');
  final match = RegExp(
    r'^(\d{4})-(\d{2})-(\d{2})T(\d{2}):(\d{2}):(\d{2})(?:\.(\d{1,6}))?(?:Z|\+00:00)$',
  ).firstMatch(value);
  final result = DateTime.tryParse(value);
  if (match == null ||
      result == null ||
      !result.isUtc ||
      result.year < 1 ||
      [
        result.year,
        result.month,
        result.day,
        result.hour,
        result.minute,
        result.second,
      ].indexed.any((e) => e.$2 != int.parse(match.group(e.$1 + 1)!))) {
    throw const FormatException('Invalid UTC expense time');
  }
  return result;
}

String _id(Object? value) {
  if (value is! String) {
    throw const FormatException('Invalid expense identifier');
  }
  return validateId(value).toLowerCase();
}

String _text(Object? value, String label, int max, {int min = 1}) {
  if (value is! String ||
      value.trim() != value ||
      value.length < min ||
      value.length > max ||
      RegExp(r'[\x00-\x08\x0b\x0c\x0e-\x1f\x7f]').hasMatch(value)) {
    throw FormatException('Invalid $label');
  }
  return value;
}

String? _optional(Object? value, String label, int max) =>
    value == null ? null : _text(value, label, max);
T _enum<T extends Enum>(List<T> values, Object? value) => values.firstWhere(
  (e) => e.name == value,
  orElse: () => throw const FormatException('Unsupported expense label'),
);
void _shape(Map<String, dynamic> row, Set<String> keys) {
  if (row.length != keys.length || row.keys.any((k) => !keys.contains(k))) {
    throw const FormatException('Unexpected expense fields');
  }
}

ExpenseContext expenseContextFromRow(Map<String, dynamic> row) {
  _shape(row, {
    'organization_id',
    'branch_id',
    'branch_name',
    'currency',
    'settings_revision',
    'own_open_shift',
  });
  final shift = row['own_open_shift'] == null
      ? null
      : rowFrom(row['own_open_shift']);
  if (shift != null) {
    _shape(shift, {
      'id',
      'actor_user_id',
      'currency',
      'opened_at',
      'expected_cash_minor',
    });
  }
  return ExpenseContext(
    organizationId: _id(row['organization_id']),
    branchId: _id(row['branch_id']),
    branchName: _text(row['branch_name'], 'branch name', 120),
    currency: validatePosCurrency(row['currency'] as String),
    settingsRevision: expenseInteger(row['settings_revision'], positive: true),
    ownOpenShift: shift == null
        ? null
        : ExpenseDrawerShift(
            id: _id(shift['id']),
            actorUserId: _id(shift['actor_user_id']),
            currency: validatePosCurrency(shift['currency'] as String),
            openedAt: expenseUtcTime(shift['opened_at']),
            expectedCashMinor: expenseInteger(
              shift['expected_cash_minor'],
              signed: true,
            ),
          ),
  );
}

ExpenseReversal expenseReversalFromRow(Map<String, dynamic> row) {
  _shape(row, {
    'id',
    'organization_id',
    'branch_id',
    'expense_id',
    'actor_user_id',
    'request_id',
    'created_at',
    'occurred_at',
    'currency',
    'amount_minor',
    'source',
    'shift_id',
    'manual_confirmed',
    'reason',
    'reference',
  });
  final source = ExpenseSource.fromDatabase(row['source']);
  final shiftId = row['shift_id'] == null ? null : _id(row['shift_id']);
  final created = expenseUtcTime(row['created_at']);
  final occurred = expenseUtcTime(row['occurred_at']);
  if (row['manual_confirmed'] != true ||
      created != occurred ||
      (source == ExpenseSource.external) != (shiftId == null)) {
    throw const FormatException('Invalid reversal evidence');
  }
  return ExpenseReversal(
    id: _id(row['id']),
    organizationId: _id(row['organization_id']),
    branchId: _id(row['branch_id']),
    expenseId: _id(row['expense_id']),
    actorUserId: _id(row['actor_user_id']),
    requestId: _id(row['request_id']),
    createdAt: created,
    occurredAt: occurred,
    currency: validatePosCurrency(row['currency'] as String),
    amountMinor: expenseInteger(row['amount_minor'], positive: true),
    source: source,
    shiftId: shiftId,
    manualConfirmed: true,
    reason: _text(row['reason'], 'reversal reason', 1000, min: 3),
    reference: _optional(row['reference'], 'reversal reference', 120),
  );
}

Expense expenseFromRow(Map<String, dynamic> row) {
  _shape(row, {
    'id',
    'organization_id',
    'branch_id',
    'actor_user_id',
    'request_id',
    'created_at',
    'occurred_at',
    'currency',
    'settings_revision',
    'amount_minor',
    'category',
    'payment_method',
    'source',
    'shift_id',
    'manual_confirmed',
    'reason',
    'payee',
    'reference',
    'reversal',
  });
  final source = ExpenseSource.fromDatabase(row['source']);
  final shiftId = row['shift_id'] == null ? null : _id(row['shift_id']);
  final method = _enum(CheckoutPaymentMethod.values, row['payment_method']);
  final ref = _optional(row['reference'], 'payment reference', 120);
  final created = expenseUtcTime(row['created_at']);
  final occurred = expenseUtcTime(row['occurred_at']);
  if (row['manual_confirmed'] != true ||
      created != occurred ||
      (source == ExpenseSource.external) != (shiftId == null) ||
      source == ExpenseSource.cashDrawer &&
          method != CheckoutPaymentMethod.cash ||
      method != CheckoutPaymentMethod.cash && (ref == null || ref.length < 3)) {
    throw const FormatException('Invalid expense payment evidence');
  }
  final expense = Expense(
    id: _id(row['id']),
    organizationId: _id(row['organization_id']),
    branchId: _id(row['branch_id']),
    actorUserId: _id(row['actor_user_id']),
    requestId: _id(row['request_id']),
    createdAt: created,
    occurredAt: occurred,
    currency: validatePosCurrency(row['currency'] as String),
    settingsRevision: expenseInteger(row['settings_revision'], positive: true),
    amountMinor: expenseInteger(row['amount_minor'], positive: true),
    category: _enum(ExpenseCategory.values, row['category']),
    paymentMethod: method,
    source: source,
    shiftId: shiftId,
    manualConfirmed: true,
    reason: _text(row['reason'], 'expense reason', 1000, min: 3),
    payee: _optional(row['payee'], 'payee', 160),
    reference: ref,
    reversal: row['reversal'] == null
        ? null
        : expenseReversalFromRow(rowFrom(row['reversal'])),
  );
  final reversal = expense.reversal;
  if (reversal != null &&
      (reversal.expenseId != expense.id ||
          reversal.organizationId != expense.organizationId ||
          reversal.branchId != expense.branchId ||
          reversal.amountMinor != expense.amountMinor ||
          reversal.currency != expense.currency ||
          reversal.source != expense.source ||
          reversal.shiftId != expense.shiftId ||
          reversal.createdAt.isBefore(expense.createdAt) ||
          reversal.source == ExpenseSource.cashDrawer &&
              reversal.actorUserId != expense.actorUserId)) {
    throw const FormatException('Contradictory expense compensation');
  }
  return expense;
}
