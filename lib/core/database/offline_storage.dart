import 'dart:convert';

import '../sync/sync_event.dart';
import 'database_scope.dart';

/// Detached evidence captured and signed before local financial persistence.
/// This is not a verifier: the coordinator must verify the retained grant and
/// device signature before using the authorized storage path.
class OfflineAuthorization {
  OfflineAuthorization({
    required this.organizationId,
    required this.branchId,
    required this.actorId,
    required this.deviceId,
    required this.eventId,
    required this.grantId,
    required this.sequence,
    required Map<String, Object?> paymentEvidence,
    required this.signature,
  }) : paymentEvidenceJson = canonicalJson(paymentEvidence) {
    if ([
          organizationId,
          branchId,
          actorId,
          deviceId,
          eventId,
          grantId,
          signature,
        ].any((value) => value.trim().isEmpty) ||
        sequence < 1 ||
        sequence > 1000) {
      throw ArgumentError('Complete scoped offline authorization is required.');
    }
  }

  final String organizationId;
  final String branchId;
  final String actorId;
  final String deviceId;
  final String eventId;
  final String grantId;
  final int sequence;
  final String paymentEvidenceJson;
  final String signature;

  Map<String, Object?> get paymentEvidence =>
      decodeCanonicalObject(paymentEvidenceJson);

  Map<String, Object?> toJson() => {
    'grant_id': grantId,
    'sequence': sequence,
    'payment_evidence': paymentEvidence,
  };

  String get authorizationJson => canonicalJson(toJson());
}

/// The already-open server shift retained in a verified grant snapshot.
class OfflineShiftSnapshot {
  const OfflineShiftSnapshot({
    required this.scope,
    required this.id,
    required this.actorId,
    required this.deviceId,
    required this.currency,
    required this.openedAt,
    required this.openingCashMinor,
  });

  final DatabaseScope scope;
  final String id;
  final String actorId;
  final String deviceId;
  final String currency;
  final DateTime openedAt;
  final int openingCashMinor;
}

class OfflineCacheChange {
  OfflineCacheChange({
    required this.kind,
    required this.id,
    required this.revision,
    required this.deleted,
    Map<String, Object?>? value,
  }) : valueJson = value == null ? null : canonicalJson(value) {
    if (!{'context', 'product', 'category', 'stock', 'shift'}.contains(kind) ||
        id.trim().isEmpty ||
        revision < 0 ||
        revision > 9007199254740991 ||
        (!deleted && value == null)) {
      throw ArgumentError('Invalid scoped offline cache change.');
    }
  }

  final String kind;
  final String id;
  final int revision;
  final bool deleted;
  final String? valueJson;
  Map<String, Object?>? get value =>
      valueJson == null ? null : decodeCanonicalObject(valueJson!);
}

class OfflineCacheBatch {
  OfflineCacheBatch({
    required this.cursor,
    required this.serverTime,
    required List<OfflineCacheChange> changes,
    this.hasMore = false,
    this.completeSnapshot = false,
    this.grantId,
  }) : changes = List.unmodifiable(changes) {
    if (cursor.trim().isEmpty ||
        (completeSnapshot && (grantId == null || grantId!.trim().isEmpty))) {
      throw ArgumentError('A cursor and complete snapshot grant are required.');
    }
  }

  final String cursor;
  final DateTime serverTime;
  final List<OfflineCacheChange> changes;
  final bool hasMore;
  final bool completeSnapshot;
  final String? grantId;
}

class OfflineStockImpact {
  const OfflineStockImpact({required this.productId, required this.revision});
  final String productId;
  final int revision;
}

class AuthorizedOutboxEvent {
  const AuthorizedOutboxEvent({
    required this.event,
    required this.documentId,
    required this.authorization,
    required this.status,
  });
  final SyncEvent event;
  final String documentId;
  final OfflineAuthorization authorization;
  final String status;
}

class OfflineStorageConflict implements Exception {
  const OfflineStorageConflict();
  @override
  String toString() => 'The offline record conflicts with preserved history.';
}

class OfflineStockUnavailable implements Exception {
  const OfflineStockUnavailable();
  @override
  String toString() => 'Cached stock is missing or insufficient for this sale.';
}

// Public JSON getters decode into new objects, so modifying a returned value
// cannot alter the evidence or cache bytes that were frozen at construction.
Map<String, Object?> decodeCanonicalObject(String json) =>
    Map<String, Object?>.from(jsonDecode(json) as Map);
