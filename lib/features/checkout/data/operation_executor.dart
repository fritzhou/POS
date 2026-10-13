import '../../../core/operations/operation_journal.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../catalog/data/supabase_repository_support.dart';
import '../../catalog/domain/repository_support.dart';

/// Never turns transport uncertainty into a new request. The journal is scoped
/// to the authenticated actor/business and contains no authentication secrets.
class OperationExecutor {
  const OperationExecutor(
    this.scope,
    this.journal, {
    this.allowHistoricalJournalBranch = false,
  });
  final SupabaseRepositoryScope scope;
  final OperationJournal? journal;

  /// Maintenance/history RPCs independently validate current raw assignments.
  /// This only preserves the original journal locator after branch deactivation.
  final bool allowHistoricalJournalBranch;

  Future<T> mutate<T>({
    required String function,
    required String branchId,
    required Map<String, dynamic> params,
    required T Function(Map<String, dynamic>) decode,
    Map<String, dynamic>? journalPayload,
  }) async {
    scope.requireIdentity();
    validateId(branchId);
    if (!allowHistoricalJournalBranch &&
        !scope.actor.branchIds.contains(branchId)) {
      throw const RepositoryFailure(
        RepositoryFailureType.permissionDenied,
        'Choose an authorized branch.',
      );
    }
    final requestId = validateId(params['p_request_id'] as String);
    final intent = await journal?.prepare(
      requestId: requestId,
      type: function,
      branchId: branchId,
      payload: journalPayload ?? params,
    );
    if (intent?.status == LocalOperationStatus.rejected) {
      throw const RepositoryFailure(
        RepositoryFailureType.conflict,
        'The server rejected this request. Correct the information and confirm a new request.',
      );
    }
    final attemptCount = intent?.status == LocalOperationStatus.pending
        ? await journal!.markAttempted(requestId: requestId)
        : 0;
    scope.requireIdentity();
    // SQL exceptions roll back atomically. A malformed success or missing
    // response remains pending, so reconciliation cannot fabricate a receipt.
    final Object? data;
    try {
      data = await scope.client.rpc(function, params: params);
    } on PostgrestException catch (error) {
      if (intent?.status == LocalOperationStatus.pending &&
          attemptCount == 1 &&
          const {
            '42501',
            '40001',
            'P0002',
            '23505',
            '22023',
            '23514',
            '23503',
            '22P02',
          }.contains(error.code)) {
        await journal?.reject(requestId: requestId, failureCode: error.code!);
      }
      if (intent?.status == LocalOperationStatus.pending && attemptCount > 1) {
        throw const RepositoryFailure(
          RepositoryFailureType.unavailable,
          'The earlier request remains unconfirmed. Preserve it and ask an authorized manager to reconcile it.',
        );
      }
      rethrow;
    }
    final Map<String, dynamic> row;
    final T decoded;
    try {
      row = rowFrom(data);
      decoded = decode(row);
    } on Object {
      throw const RepositoryFailure(
        RepositoryFailureType.unavailable,
        'The server response could not confirm this request. Reconcile or retry the same request.',
      );
    }
    scope.requireIdentity();
    if (intent?.status != LocalOperationStatus.confirmed) {
      await journal?.confirm(requestId: requestId, result: row);
    }
    return decoded;
  }

  Future<List<PendingOperation>> pending({
    String? type,
    String? branchId,
  }) async {
    scope.requireIdentity();
    if (branchId != null) validateId(branchId);
    final result =
        await journal?.pending(type: type, branchId: branchId) ??
        <PendingOperation>[];
    scope.requireIdentity();
    return result
        .where(
          (op) =>
              op.organizationId == scope.organizationId &&
              op.actorId == scope.actor.userId,
        )
        .toList(growable: false);
  }
}
