import '../database/database_scope.dart';

enum OutboxStatus {
  pending('PENDING'),
  syncing('SYNCING'),
  synced('SYNCED'),
  failed('FAILED');

  const OutboxStatus(this.storageValue);
  final String storageValue;
}

/// A claim token changes on every lease, including for the same worker.
/// Stale workers cannot acknowledge or fail a newly claimed event.
class OutboxLease {
  const OutboxLease({
    required this.eventId,
    required this.scope,
    required this.workerId,
    required this.token,
    required this.digest,
    required this.attempt,
    required this.expiresAt,
  });

  final String eventId;
  final DatabaseScope scope;
  final String workerId;
  final String token;
  final String digest;
  final int attempt;
  final DateTime expiresAt;
}

/// An adapter may construct this only from a validated server response.
/// There is deliberately no cloud adapter or simulated acceptance in Phase 1.
class ServerAcceptance {
  const ServerAcceptance({
    required this.eventId,
    required this.digest,
    required this.serverReceiptId,
    required this.acceptedAt,
  });

  final String eventId;
  final String digest;
  final String serverReceiptId;
  final DateTime acceptedAt;
}

enum SyncFailureCode {
  unavailable,
  timeout,
  unauthorized,
  invalidEvent,
  unsupportedSchema,
  conflict,
}

class LostOutboxLease implements Exception {
  const LostOutboxLease();

  @override
  String toString() => 'The event lease has expired or changed ownership.';
}

/// Exponential backoff with caller-provided jitter, for deterministic tests.
Duration retryDelay(int attempt, {double jitter = 0.5}) {
  if (attempt < 1 || jitter < 0 || jitter > 1 || !jitter.isFinite) {
    throw ArgumentError('Invalid retry attempt or jitter.');
  }
  final power = attempt > 10 ? 10 : attempt;
  final seconds = (1 << power).clamp(2, 1800);
  return Duration(milliseconds: (seconds * 1000 * (0.75 + jitter / 2)).round());
}
