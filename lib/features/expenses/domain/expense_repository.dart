import '../../../core/operations/operation_journal.dart';
import '../../catalog/domain/repository_support.dart';
import 'expense_models.dart';

abstract interface class ExpenseRepository {
  String get organizationId;
  String get actorUserId;
  Future<ExpenseContext> loadContext(String branchId);
  Future<DataPage<Expense>> listExpenses({
    required String branchId,
    ExpenseFilter filter = const ExpenseFilter(),
    PageRequest page = const PageRequest(),
  });
  Future<Expense> getExpense({
    required String branchId,
    required String expenseId,
  });
  Future<Expense> recordExpense(RecordExpenseRequest request);
  Future<ExpenseReversal> reverseExpense(ReverseExpenseRequest request);
  Future<List<PendingOperation>> pendingOperations({String? branchId});

  /// Same-branch unknown checkout/shift closure prevents a new drawer payout.
  Future<List<PendingOperation>> drawerBlockers(String branchId);
  Future<Object> retryPending(PendingOperation operation);
}
