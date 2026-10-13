enum LocalOperationStatus { pending, confirmed, rejected }

/// An online operation's durable intent, never offline authority or a receipt.
class PendingOperation {
  PendingOperation({
    required String requestId,
    required String organizationId,
    required String branchId,
    required String actorId,
    required this.type,
    required Map<String, dynamic> payload,
    required this.createdAt,
    required this.status,
    this.attemptCount = 0,
    Map<String, dynamic>? result,
    this.failureCode,
  }) : requestId = requestId.toLowerCase(),
       organizationId = organizationId.toLowerCase(),
       branchId = branchId.toLowerCase(),
       actorId = actorId.toLowerCase(),
       payload = _freezeMap(payload),
       result = result == null ? null : _freezeMap(result);

  final String requestId;
  final String organizationId;
  final String branchId;
  final String actorId;
  final String type;
  final Map<String, dynamic> payload;
  final DateTime createdAt;
  final LocalOperationStatus status;
  final int attemptCount;
  final Map<String, dynamic>? result;
  final String? failureCode;
}

abstract interface class OperationJournal {
  Future<PendingOperation> prepare({
    required String requestId,
    required String type,
    required String branchId,
    required Map<String, dynamic> payload,
  });
  Future<List<PendingOperation>> pending({String? type, String? branchId});

  /// Persist before issuing the HTTP request. Replays cannot treat a later
  /// server denial as proof that an earlier uncertain attempt rolled back.
  Future<int> markAttempted({required String requestId});
  Future<void> confirm({
    required String requestId,
    required Map<String, dynamic> result,
  });

  /// Only a definitive server rollback may reject an intent. Timeouts and
  /// malformed/lost success responses must remain pending for reconciliation.
  /// The precise offline_prepare/unsigned-expiry outcome can also close a
  /// reservation after retries; it must never close a paid financial operation.
  Future<void> reject({required String requestId, required String failureCode});
  Future<void> close();
}

Map<String, dynamic> _freezeMap(Map<String, dynamic> value) =>
    Map.unmodifiable(value.map((key, child) => MapEntry(key, _freeze(child))));

Object? _freeze(Object? value) {
  if (value is Map<String, dynamic>) return _freezeMap(value);
  if (value is List) return List<Object?>.unmodifiable(value.map(_freeze));
  return value;
}

class OperationJournalFailure implements Exception {
  const OperationJournalFailure(this.message);
  final String message;
  @override
  String toString() => 'OperationJournalFailure';
}
