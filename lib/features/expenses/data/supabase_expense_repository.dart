import 'dart:async';

import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/auth/auth_models.dart';
import '../../../core/operations/operation_journal.dart';
import '../../../core/security/app_role.dart';
import '../../catalog/data/supabase_repository_support.dart';
import '../../catalog/domain/repository_support.dart';
import '../../checkout/data/operation_executor.dart';
import '../../checkout/domain/checkout_models.dart';
import '../domain/expense_models.dart';
import '../domain/expense_repository.dart';
import 'expense_decoders.dart';

const _originalKey = '_nexapos_expense_original';
const _expenseTypes = {'record_expense', 'reverse_expense'};
final _expenseMutationLanes = Expando<Future<void>>();

class SupabaseExpenseRepository implements ExpenseRepository {
  SupabaseExpenseRepository({
    required SupabaseClient client,
    required AuthenticatedUser actor,
    required this.journal,
    bool Function()? isRecoverySession,
  }) : _scope = SupabaseRepositoryScope(
         client: client,
         actor: actor,
         isRecoverySession: isRecoverySession,
       );
  final SupabaseRepositoryScope _scope;
  final OperationJournal journal;
  late final _operations = OperationExecutor(_scope, journal);
  @override
  String get organizationId => _scope.organizationId;
  @override
  String get actorUserId => _scope.actor.userId;
  void _allow(String? branchId) {
    _scope.requireIdentity();
    if (![
      AppRole.owner,
      AppRole.admin,
      AppRole.manager,
    ].contains(_scope.actor.role)) {
      throw const RepositoryFailure(
        RepositoryFailureType.permissionDenied,
        'Your account cannot manage business expenses.',
      );
    }
    if (branchId != null &&
        !_scope.actor.branchIds.contains(validateId(branchId).toLowerCase())) {
      throw const RepositoryFailure(
        RepositoryFailureType.permissionDenied,
        'Choose an authorized branch.',
      );
    }
  }

  Map<String, dynamic> _scopeParams(String branchId) {
    _allow(branchId);
    return {
      'p_organization_id': organizationId,
      'p_branch_id': branchId.toLowerCase(),
    };
  }

  Future<T> _serialize<T>(Future<T> Function() action) async {
    final prior = _expenseMutationLanes[journal];
    final gate = Completer<void>();
    _expenseMutationLanes[journal] = gate.future;
    if (prior != null) await prior;
    try {
      return await action();
    } finally {
      gate.complete();
      if (identical(_expenseMutationLanes[journal], gate.future)) {
        _expenseMutationLanes[journal] = null;
      }
    }
  }

  void _expenseScope(Expense expense, String branchId) {
    if (expense.organizationId != organizationId ||
        expense.branchId != validateId(branchId).toLowerCase()) {
      throw const FormatException('Unexpected expense scope');
    }
  }

  @override
  Future<ExpenseContext> loadContext(String branchId) => _scope.safe(() async {
    final context = expenseContextFromRow(
      rowFrom(
        await _scope.client.rpc(
          'get_expense_context',
          params: _scopeParams(branchId),
        ),
      ),
    );
    if (context.organizationId != organizationId ||
        context.branchId != validateId(branchId).toLowerCase() ||
        context.ownOpenShift != null &&
            context.ownOpenShift!.actorUserId != actorUserId) {
      throw const FormatException('Unexpected expense context');
    }
    return context;
  });
  @override
  Future<DataPage<Expense>> listExpenses({
    required String branchId,
    ExpenseFilter filter = const ExpenseFilter(),
    PageRequest page = const PageRequest(),
  }) => _scope.safe(() async {
    page.validate();
    filter.validate();
    final rows = rowsFrom(
      await _scope.client.rpc(
        'list_expenses',
        params: {
          ..._scopeParams(branchId),
          'p_from': filter.from?.toIso8601String(),
          'p_to': filter.to?.toIso8601String(),
          'p_category': filter.category?.name,
          'p_offset': page.offset,
          'p_limit': page.limit + 1,
        },
      ),
    );
    if (rows.length > page.limit + 1) {
      throw const FormatException('Oversized expense page');
    }
    final expenses = rows.map(expenseFromRow).toList(growable: false);
    if (expenses.map((e) => e.id).toSet().length != expenses.length) {
      throw const FormatException('Duplicate expense document');
    }
    for (final expense in expenses) {
      _expenseScope(expense, branchId);
      if (filter.category != null && expense.category != filter.category ||
          filter.from != null &&
              (expense.occurredAt.isBefore(filter.from!) ||
                  !expense.occurredAt.isBefore(filter.to!))) {
        throw const FormatException('Unexpected expense filter');
      }
    }
    return DataPage(
      items: expenses.take(page.limit).toList(growable: false),
      hasMore: expenses.length > page.limit,
      offset: page.offset,
    );
  });
  @override
  Future<Expense> getExpense({
    required String branchId,
    required String expenseId,
  }) => _scope.safe(() async {
    final expense = expenseFromRow(
      rowFrom(
        await _scope.client.rpc(
          'get_expense',
          params: {
            ..._scopeParams(branchId),
            'p_expense_id': validateId(expenseId).toLowerCase(),
          },
        ),
      ),
    );
    _expenseScope(expense, branchId);
    if (expense.id != validateId(expenseId).toLowerCase()) {
      throw const FormatException('Unexpected expense document');
    }
    return expense;
  });
  @override
  Future<List<PendingOperation>> pendingOperations({String? branchId}) =>
      _scope.safe(() async {
        _allow(branchId);
        return (await _operations.pending(
          branchId: branchId,
        )).where((e) => _expenseTypes.contains(e.type)).toList(growable: false);
      });
  @override
  Future<List<PendingOperation>> drawerBlockers(String branchId) => _scope.safe(
    () async {
      _allow(branchId);
      return (await _operations.pending(branchId: branchId))
          .where((e) => const {'checkout_sale', 'close_shift'}.contains(e.type))
          .toList(growable: false);
    },
  );
  Future<void> _guardNew(
    String requestId,
    String branchId,
    ExpenseSource source,
  ) async {
    final pending = await _operations.pending();
    // Retrying a frozen request resolves its original action and performs no new payout.
    if (pending.any(
      (e) => e.requestId == requestId && _expenseTypes.contains(e.type),
    )) {
      return;
    }
    if (pending.any((e) => _expenseTypes.contains(e.type))) {
      throw const RepositoryFailure(
        RepositoryFailureType.conflict,
        'An expense request is unconfirmed. Resolve the saved request before recording another expense. Do not repeat the physical payment.',
      );
    }
    if (source == ExpenseSource.cashDrawer &&
        pending.any(
          (e) =>
              e.branchId == branchId &&
              const {'checkout_sale', 'close_shift'}.contains(e.type),
        )) {
      throw const RepositoryFailure(
        RepositoryFailureType.conflict,
        'Confirm the saved checkout or shift closure before recording a drawer payout.',
      );
    }
  }

  Expense _recordResult(Map<String, dynamic> row, Map<String, dynamic> params) {
    if (row.length != 3 ||
        row.keys.any(
          (key) => !const {'kind', 'request_id', 'expense'}.contains(key),
        ) ||
        row['kind'] != 'expense.record' ||
        row['request_id'] != params['p_request_id']) {
      throw const FormatException('Unexpected expense action');
    }
    final expense = expenseFromRow(rowFrom(row['expense']));
    _expenseScope(expense, params['p_branch_id'] as String);
    if (expense.actorUserId != actorUserId ||
        expense.requestId != params['p_request_id'] ||
        expense.settingsRevision != params['p_expected_settings_revision'] ||
        expense.currency != params['p_currency'] ||
        expense.amountMinor != params['p_amount_minor'] ||
        expense.category.name != params['p_category'] ||
        expense.paymentMethod.name != params['p_payment_method'] ||
        expense.source.databaseValue != params['p_source'] ||
        expense.shiftId != params['p_shift_id'] ||
        expense.manualConfirmed != params['p_manual_confirmed'] ||
        expense.payee != params['p_payee'] ||
        expense.reference != params['p_reference'] ||
        expense.reason != params['p_reason'] ||
        expense.reversal != null) {
      throw const FormatException('Inconsistent immutable expense action');
    }
    return expense;
  }

  ExpenseReversal _reversalResult(
    Map<String, dynamic> row,
    Map<String, dynamic> params,
    Expense original,
  ) {
    if (row.length != 4 ||
        row.keys.any(
          (key) => !const {
            'kind',
            'request_id',
            'expense_id',
            'reversal',
          }.contains(key),
        ) ||
        row['kind'] != 'expense.reverse' ||
        row['request_id'] != params['p_request_id'] ||
        row['expense_id'] != original.id) {
      throw const FormatException('Unexpected reversal action');
    }
    final reversal = expenseReversalFromRow(rowFrom(row['reversal']));
    if (reversal.organizationId != organizationId ||
        reversal.branchId != original.branchId ||
        reversal.actorUserId != actorUserId ||
        reversal.requestId != params['p_request_id'] ||
        reversal.expenseId != original.id ||
        reversal.amountMinor != original.amountMinor ||
        reversal.currency != original.currency ||
        reversal.source != original.source ||
        reversal.shiftId != original.shiftId ||
        reversal.manualConfirmed != params['p_manual_confirmed'] ||
        reversal.reason != params['p_reason'] ||
        reversal.reference != params['p_reference'] ||
        reversal.createdAt.isBefore(original.createdAt) ||
        reversal.source == ExpenseSource.cashDrawer &&
            original.actorUserId != actorUserId) {
      throw const FormatException(
        'Inconsistent immutable expense compensation',
      );
    }
    return reversal;
  }

  @override
  Future<Expense> recordExpense(RecordExpenseRequest request) => _scope.safe(
    () => _serialize(() async {
      _allow(request.branchId);
      final params = request.parameters(organizationId);
      await _guardNew(
        params['p_request_id'] as String,
        params['p_branch_id'] as String,
        request.source,
      );
      return _operations.mutate(
        function: 'record_expense',
        branchId: params['p_branch_id'] as String,
        params: params,
        decode: (row) => _recordResult(row, params),
      );
    }),
  );
  @override
  Future<ExpenseReversal> reverseExpense(
    ReverseExpenseRequest request,
  ) => _scope.safe(
    () => _serialize(() async {
      _allow(request.original.branchId);
      final params = request.parameters(organizationId);
      _expenseScope(request.original, request.original.branchId);
      if (request.original.source == ExpenseSource.cashDrawer &&
          request.original.actorUserId != actorUserId) {
        throw const RepositoryFailure(
          RepositoryFailureType.permissionDenied,
          'Only the original drawer actor can record returned cash to that same open shift.',
        );
      }
      await _guardNew(
        params['p_request_id'] as String,
        params['p_branch_id'] as String,
        request.original.source,
      );
      return OperationExecutor(
        _scope,
        _OriginalExpenseJournal(journal, request.original.immutableProof()),
      ).mutate(
        function: 'reverse_expense',
        branchId: params['p_branch_id'] as String,
        params: params,
        decode: (row) => _reversalResult(row, params, request.original),
      );
    }),
  );
  @override
  Future<Object> retryPending(PendingOperation operation) => _scope.safe(
    () => _serialize(() async {
      _allow(operation.branchId);
      if (!_expenseTypes.contains(operation.type) ||
          operation.status != LocalOperationStatus.pending ||
          operation.organizationId != organizationId ||
          operation.actorId != actorUserId ||
          operation.payload['p_organization_id'] != organizationId ||
          operation.payload['p_branch_id'] != operation.branchId ||
          operation.payload['p_request_id'] != operation.requestId) {
        throw const RepositoryFailure(
          RepositoryFailureType.permissionDenied,
          'This saved expense belongs to another account or branch.',
        );
      }
      final params = Map<String, dynamic>.from(operation.payload);
      if (operation.type == 'record_expense') {
        _validateRecordPayload(params);
        return _operations.mutate(
          function: operation.type,
          branchId: operation.branchId,
          params: params,
          decode: (row) => _recordResult(row, params),
        );
      }
      final original = expenseFromRow(rowFrom(params.remove(_originalKey)));
      _expenseScope(original, operation.branchId);
      if (original.id != params['p_expense_id'] || original.reversal != null) {
        throw const FormatException('Invalid frozen original expense');
      }
      final reconstructed = ReverseExpenseRequest(
        original: original,
        requestId: operation.requestId,
        manualConfirmed: params['p_manual_confirmed'] == true,
        reason: params['p_reason'] as String,
        reference: params['p_reference'] as String?,
      ).parameters(organizationId);
      _samePayload(params, reconstructed);
      return OperationExecutor(
        _scope,
        _OriginalExpenseJournal(journal, original.immutableProof()),
      ).mutate(
        function: operation.type,
        branchId: operation.branchId,
        params: params,
        decode: (row) => _reversalResult(row, params, original),
      );
    }),
  );
  void _samePayload(
    Map<String, dynamic> params,
    Map<String, dynamic> expected,
  ) {
    if (params.length != expected.length ||
        params.entries.any(
          (e) => !expected.containsKey(e.key) || expected[e.key] != e.value,
        )) {
      throw const FormatException('Saved expense intent changed');
    }
  }

  void _validateRecordPayload(Map<String, dynamic> params) {
    final expected = RecordExpenseRequest(
      requestId: params['p_request_id'] as String,
      branchId: params['p_branch_id'] as String,
      expectedSettingsRevision: expenseInteger(
        params['p_expected_settings_revision'],
        positive: true,
      ),
      currency: params['p_currency'] as String,
      amountMinor: expenseInteger(params['p_amount_minor'], positive: true),
      category: ExpenseCategory.values.firstWhere(
        (e) => e.name == params['p_category'],
      ),
      paymentMethod: CheckoutPaymentMethod.values.firstWhere(
        (e) => e.name == params['p_payment_method'],
      ),
      source: ExpenseSource.fromDatabase(params['p_source']),
      shiftId: params['p_shift_id'] as String?,
      manualConfirmed: params['p_manual_confirmed'] == true,
      payee: params['p_payee'] as String?,
      reference: params['p_reference'] as String?,
      reason: params['p_reason'] as String,
    ).parameters(organizationId);
    _samePayload(params, expected);
  }
}

/// Adds encrypted local proof while the executor sends only approved RPC args.
class _OriginalExpenseJournal implements OperationJournal {
  const _OriginalExpenseJournal(this.delegate, this.original);
  final OperationJournal delegate;
  final Map<String, dynamic> original;
  @override
  Future<PendingOperation> prepare({
    required String requestId,
    required String type,
    required String branchId,
    required Map<String, dynamic> payload,
  }) => delegate.prepare(
    requestId: requestId,
    type: type,
    branchId: branchId,
    payload: {...payload, _originalKey: original},
  );
  @override
  Future<List<PendingOperation>> pending({String? type, String? branchId}) =>
      delegate.pending(type: type, branchId: branchId);
  @override
  Future<int> markAttempted({required String requestId}) =>
      delegate.markAttempted(requestId: requestId);
  @override
  Future<void> confirm({
    required String requestId,
    required Map<String, dynamic> result,
  }) => delegate.confirm(requestId: requestId, result: result);
  @override
  Future<void> reject({
    required String requestId,
    required String failureCode,
  }) => delegate.reject(requestId: requestId, failureCode: failureCode);
  @override
  Future<void> close() async {}
}
