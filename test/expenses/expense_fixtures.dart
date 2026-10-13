import 'dart:convert';
import 'dart:io';

import 'package:nexapos/core/auth/auth_models.dart';
import 'package:nexapos/core/security/app_role.dart';
import 'package:nexapos/features/checkout/domain/checkout_models.dart';
import 'package:nexapos/features/expenses/data/expense_decoders.dart';
import 'package:nexapos/features/expenses/domain/expense_models.dart';

const expenseOrg = 'ab000000-0000-4000-8000-000000000001';
const expenseBranch = 'ab000000-0000-4000-8000-000000000002';
const expenseActor = 'ab000000-0000-4000-8000-000000000003';
const expenseId = 'ab000000-0000-4000-8000-000000000004';
const expenseShift = 'ab000000-0000-4000-8000-000000000005';
const expenseRequestId = 'ab000000-0000-4000-8000-000000000006';
const expenseReversalId = 'ab000000-0000-4000-8000-000000000007';
const expenseReverseRequestId = 'ab000000-0000-4000-8000-000000000008';
const otherExpenseActor = 'ab000000-0000-4000-8000-000000000009';

AuthenticatedUser expenseMembership({AppRole role = AppRole.owner}) =>
    AuthenticatedUser(
      userId: expenseActor,
      email: 'owner@example.test',
      organizationId: expenseOrg,
      membershipId: expenseId,
      role: role,
      branchIds: {expenseBranch},
      allBranches: true,
      businessName: 'Expense fixture business',
    );
Map<String, dynamic> expenseContextWire({bool drawer = true}) => {
  'organization_id': expenseOrg,
  'branch_id': expenseBranch,
  'branch_name': 'Expense fixture branch',
  'currency': 'PHP',
  'settings_revision': 1,
  'own_open_shift': drawer
      ? {
          'id': expenseShift,
          'actor_user_id': expenseActor,
          'currency': 'PHP',
          'opened_at': '2026-10-11T00:00:00Z',
          'expected_cash_minor': -300,
        }
      : null,
};
Map<String, dynamic> expenseWire({
  bool drawer = false,
  bool reversed = false,
}) => {
  'id': expenseId,
  'organization_id': expenseOrg,
  'branch_id': expenseBranch,
  'actor_user_id': expenseActor,
  'request_id': expenseRequestId,
  'created_at': '2026-10-11T01:00:00Z',
  'occurred_at': '2026-10-11T01:00:00Z',
  'currency': 'PHP',
  'settings_revision': 1,
  'amount_minor': 12345,
  'category': 'other',
  'payment_method': 'cash',
  'source': drawer ? 'cash_drawer' : 'external',
  'shift_id': drawer ? expenseShift : null,
  'manual_confirmed': true,
  'reason': 'Verified business payment',
  'payee': 'Actual supplier',
  'reference': null,
  'reversal': reversed ? expenseReversalWire(drawer: drawer) : null,
};
Map<String, dynamic> expenseReversalWire({bool drawer = false}) => {
  'id': expenseReversalId,
  'organization_id': expenseOrg,
  'branch_id': expenseBranch,
  'expense_id': expenseId,
  'actor_user_id': expenseActor,
  'request_id': expenseReverseRequestId,
  'created_at': '2026-10-11T02:00:00Z',
  'occurred_at': '2026-10-11T02:00:00Z',
  'currency': 'PHP',
  'amount_minor': 12345,
  'source': drawer ? 'cash_drawer' : 'external',
  'shift_id': drawer ? expenseShift : null,
  'manual_confirmed': true,
  'reason': 'Verified full correction',
  'reference': null,
};
Map<String, dynamic> expenseRecordAction({bool drawer = false}) => {
  'kind': 'expense.record',
  'request_id': expenseRequestId,
  'expense': expenseWire(drawer: drawer),
};
Map<String, dynamic> expenseReverseAction({bool drawer = false}) => {
  'kind': 'expense.reverse',
  'request_id': expenseReverseRequestId,
  'expense_id': expenseId,
  'reversal': expenseReversalWire(drawer: drawer),
};
RecordExpenseRequest expenseRequest({bool drawer = false, String? requestId}) =>
    RecordExpenseRequest(
      requestId: requestId ?? expenseRequestId,
      branchId: expenseBranch,
      expectedSettingsRevision: 1,
      currency: 'PHP',
      amountMinor: 12345,
      category: ExpenseCategory.other,
      paymentMethod: CheckoutPaymentMethod.cash,
      source: drawer ? ExpenseSource.cashDrawer : ExpenseSource.external,
      shiftId: drawer ? expenseShift : null,
      manualConfirmed: true,
      reason: 'Verified business payment',
      payee: 'Actual supplier',
    );
ReverseExpenseRequest expenseReverseRequest({bool drawer = false}) =>
    ReverseExpenseRequest(
      original: expenseFromRow(expenseWire(drawer: drawer)),
      requestId: expenseReverseRequestId,
      reason: 'Verified full correction',
      manualConfirmed: true,
    );
Map<String, dynamic> expenseSqlFixture() =>
    jsonDecode(
          File('test/fixtures/expenses_sql_contract.json').readAsStringSync(),
        )
        as Map<String, dynamic>;
Map<String, dynamic> cloneExpenseWire(Map<String, dynamic> value) =>
    jsonDecode(jsonEncode(value)) as Map<String, dynamic>;
