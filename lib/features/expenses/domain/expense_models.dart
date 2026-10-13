import 'package:uuid/uuid.dart';

import '../../catalog/domain/repository_support.dart';
import '../../checkout/domain/checkout_models.dart';

enum ExpenseCategory {
  rent,
  utilities,
  wages,
  transport,
  maintenance,
  fees,
  other;

  String get label => switch (this) {
    rent => 'Rent',
    utilities => 'Utilities',
    wages => 'Wages',
    transport => 'Transport',
    maintenance => 'Maintenance',
    fees => 'Fees',
    other => 'Other',
  };
}

enum ExpenseSource {
  external,
  cashDrawer;

  String get databaseValue => this == external ? 'external' : 'cash_drawer';
  String get label =>
      this == external ? 'External funds' : 'Own shift cash drawer';
  static ExpenseSource fromDatabase(Object? value) => switch (value) {
    'external' => external,
    'cash_drawer' => cashDrawer,
    _ => throw const FormatException('Unsupported expense source'),
  };
}

String expensePaymentLabel(CheckoutPaymentMethod method) => switch (method) {
  CheckoutPaymentMethod.cash => 'Cash',
  CheckoutPaymentMethod.card => 'Card',
  CheckoutPaymentMethod.gcash => 'GCash',
  CheckoutPaymentMethod.maya => 'Maya',
  CheckoutPaymentMethod.other => 'Other',
};
String expenseInputText(
  String value,
  String label,
  int maximum, {
  int minimum = 1,
}) {
  final text = requiredText(value, label, maximum, minimum: minimum);
  if (RegExp(r'[\x00-\x08\x0b\x0c\x0e-\x1f\x7f]').hasMatch(text)) {
    throw RepositoryFailure(
      RepositoryFailureType.validation,
      '$label contains unsupported control characters.',
    );
  }
  return text;
}

String? expenseOptionalText(String? value, String label, int maximum) {
  final text = optionalText(value, label, maximum);
  return text == null ? null : expenseInputText(text, label, maximum);
}

class ExpenseDrawerShift {
  const ExpenseDrawerShift({
    required this.id,
    required this.actorUserId,
    required this.currency,
    required this.openedAt,
    required this.expectedCashMinor,
  });
  final String id, actorUserId, currency;
  final DateTime openedAt;
  final int expectedCashMinor;
}

class ExpenseContext {
  const ExpenseContext({
    required this.organizationId,
    required this.branchId,
    required this.branchName,
    required this.currency,
    required this.settingsRevision,
    this.ownOpenShift,
  });
  final String organizationId, branchId, branchName, currency;
  final int settingsRevision;
  final ExpenseDrawerShift? ownOpenShift;
  bool get canUseCashDrawer =>
      ownOpenShift != null && ownOpenShift!.currency == currency;
}

class ExpenseReversal {
  const ExpenseReversal({
    required this.id,
    required this.organizationId,
    required this.branchId,
    required this.expenseId,
    required this.actorUserId,
    required this.requestId,
    required this.createdAt,
    required this.occurredAt,
    required this.currency,
    required this.amountMinor,
    required this.source,
    required this.manualConfirmed,
    required this.reason,
    this.shiftId,
    this.reference,
  });
  final String id,
      organizationId,
      branchId,
      expenseId,
      actorUserId,
      requestId,
      currency,
      reason;
  final DateTime createdAt, occurredAt;
  final int amountMinor;
  final ExpenseSource source;
  final bool manualConfirmed;
  final String? shiftId, reference;
}

class Expense {
  const Expense({
    required this.id,
    required this.organizationId,
    required this.branchId,
    required this.actorUserId,
    required this.requestId,
    required this.createdAt,
    required this.occurredAt,
    required this.currency,
    required this.settingsRevision,
    required this.amountMinor,
    required this.category,
    required this.paymentMethod,
    required this.source,
    required this.manualConfirmed,
    required this.reason,
    this.shiftId,
    this.payee,
    this.reference,
    this.reversal,
  });
  final String id,
      organizationId,
      branchId,
      actorUserId,
      requestId,
      currency,
      reason;
  final DateTime createdAt, occurredAt;
  final int settingsRevision, amountMinor;
  final ExpenseCategory category;
  final CheckoutPaymentMethod paymentMethod;
  final ExpenseSource source;
  final bool manualConfirmed;
  final String? shiftId, payee, reference;
  final ExpenseReversal? reversal;
  int get netAmountMinor => reversal == null ? amountMinor : 0;
  Map<String, dynamic> immutableProof() => {
    'id': id,
    'organization_id': organizationId,
    'branch_id': branchId,
    'actor_user_id': actorUserId,
    'request_id': requestId,
    'created_at': createdAt.toUtc().toIso8601String(),
    'occurred_at': occurredAt.toUtc().toIso8601String(),
    'currency': currency,
    'settings_revision': settingsRevision,
    'amount_minor': amountMinor,
    'category': category.name,
    'payment_method': paymentMethod.name,
    'source': source.databaseValue,
    'manual_confirmed': manualConfirmed,
    'shift_id': shiftId,
    'payee': payee,
    'reference': reference,
    'reason': reason,
    'reversal': null,
  };
}

class ExpenseFilter {
  const ExpenseFilter({this.from, this.to, this.category});
  final DateTime? from, to;
  final ExpenseCategory? category;
  void validate() {
    if ((from == null) != (to == null) ||
        (from != null &&
            (!from!.isUtc ||
                !to!.isUtc ||
                !from!.isBefore(to!) ||
                to!.difference(from!) > const Duration(days: 366)))) {
      throw const RepositoryFailure(
        RepositoryFailureType.validation,
        'Choose an ordered UTC date range of at most 366 days.',
      );
    }
  }
}

class RecordExpenseRequest {
  RecordExpenseRequest({
    required this.branchId,
    required this.expectedSettingsRevision,
    required this.currency,
    required this.amountMinor,
    required this.category,
    required this.paymentMethod,
    required this.source,
    required this.manualConfirmed,
    required this.reason,
    this.shiftId,
    this.payee,
    this.reference,
    String? requestId,
  }) : requestId = requestId ?? const Uuid().v4();
  final String requestId, branchId, currency, reason;
  final int expectedSettingsRevision, amountMinor;
  final ExpenseCategory category;
  final CheckoutPaymentMethod paymentMethod;
  final ExpenseSource source;
  final bool manualConfirmed;
  final String? shiftId, payee, reference;
  Map<String, dynamic> parameters(String organizationId) {
    if (amountMinor <= 0 ||
        !manualConfirmed ||
        source == ExpenseSource.cashDrawer &&
            (shiftId == null || paymentMethod != CheckoutPaymentMethod.cash) ||
        source == ExpenseSource.external && shiftId != null) {
      throw const RepositoryFailure(
        RepositoryFailureType.validation,
        'Confirm the paid amount and use the correct funding source and shift.',
      );
    }
    final ref = expenseOptionalText(reference, 'Payment reference', 120);
    if (paymentMethod != CheckoutPaymentMethod.cash &&
        (ref == null || ref.length < 3)) {
      throw const RepositoryFailure(
        RepositoryFailureType.validation,
        'Enter the verified payment reference with at least 3 characters.',
      );
    }
    return {
      'p_organization_id': validateId(organizationId).toLowerCase(),
      'p_branch_id': validateId(branchId).toLowerCase(),
      'p_request_id': validateId(requestId).toLowerCase(),
      'p_expected_settings_revision': validateMinor(
        validateRevision(expectedSettingsRevision),
      ),
      'p_currency': validatePosCurrency(currency),
      'p_amount_minor': validateMinor(amountMinor),
      'p_category': category.name,
      'p_source': source.databaseValue,
      'p_shift_id': shiftId == null ? null : validateId(shiftId!).toLowerCase(),
      'p_payment_method': paymentMethod.name,
      'p_manual_confirmed': manualConfirmed,
      'p_payee': expenseOptionalText(payee, 'Payee', 160),
      'p_reference': ref,
      'p_reason': expenseInputText(reason, 'Expense reason', 1000, minimum: 3),
    };
  }
}

class ReverseExpenseRequest {
  ReverseExpenseRequest({
    required this.original,
    required this.reason,
    required this.manualConfirmed,
    this.reference,
    String? requestId,
  }) : requestId = requestId ?? const Uuid().v4();
  final Expense original;
  final String requestId, reason;
  final bool manualConfirmed;
  final String? reference;
  Map<String, dynamic> parameters(String organizationId) {
    if (original.organizationId.toLowerCase() != organizationId.toLowerCase() ||
        original.reversal != null ||
        !manualConfirmed) {
      throw const RepositoryFailure(
        RepositoryFailureType.validation,
        'Confirm an unreversed expense and the full correction or returned cash.',
      );
    }
    return {
      'p_organization_id': validateId(organizationId).toLowerCase(),
      'p_branch_id': validateId(original.branchId).toLowerCase(),
      'p_request_id': validateId(requestId).toLowerCase(),
      'p_expense_id': validateId(original.id).toLowerCase(),
      'p_manual_confirmed': true,
      'p_reference': expenseOptionalText(reference, 'Reversal reference', 120),
      'p_reason': expenseInputText(reason, 'Reversal reason', 1000, minimum: 3),
    };
  }
}
