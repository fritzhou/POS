import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:uuid/uuid.dart';

/// Version 1 canonical encoding: lexically sorted string keys, integral
/// numbers only, preserved array order, and Dart JSON string escaping.
/// A future server must implement this exact contract before ingestion exists.
String canonicalJson(Object? value) => jsonEncode(_canonicalValue(value));

Object? _canonicalValue(Object? value) {
  if (value == null || value is String || value is bool) return value;
  if (value is int) {
    if (value.abs() > 9007199254740991) {
      throw ArgumentError('Event integers must be exactly representable.');
    }
    return value;
  }
  if (value is List) return value.map(_canonicalValue).toList();
  if (value is Map<String, Object?>) {
    final keys = value.keys.toList()..sort();
    return {for (final key in keys) key: _canonicalValue(value[key])};
  }
  throw ArgumentError('Unsupported canonical event value.');
}

String newLocalId() => const Uuid().v4();

class SyncEvent {
  SyncEvent({
    required this.eventId,
    required this.organizationId,
    required this.branchId,
    required this.deviceId,
    required this.actorId,
    required this.eventType,
    required this.occurredAt,
    required Map<String, Object?> payload,
    this.schemaVersion = 1,
  }) : payloadJson = canonicalJson(payload) {
    if (!RegExp(
      r'^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$',
    ).hasMatch(eventId)) {
      throw ArgumentError('Event identifier must be a UUID.');
    }
    if ([
      organizationId,
      branchId,
      deviceId,
      actorId,
      eventType,
    ].any((value) => value.trim().isEmpty)) {
      throw ArgumentError('Event identity and scope are required.');
    }
    if (schemaVersion != 1) {
      throw ArgumentError('Only event schema version 1 is supported.');
    }
  }

  final String eventId;
  final String organizationId;
  final String branchId;
  final String deviceId;
  final String actorId;
  final String eventType;
  final int schemaVersion;
  final DateTime occurredAt;
  final String payloadJson;

  String get occurredAtIso => occurredAt.toUtc().toIso8601String();

  String get digest => sha256
      .convert(
        utf8.encode(
          canonicalJson({
            'actor_id': actorId,
            'branch_id': branchId,
            'device_id': deviceId,
            'event_id': eventId,
            'event_type': eventType,
            'occurred_at': occurredAtIso,
            'organization_id': organizationId,
            'payload': jsonDecode(payloadJson),
            'schema_version': schemaVersion,
          }),
        ),
      )
      .toString();
}

class EventConflict implements Exception {
  const EventConflict();

  @override
  String toString() => 'An event identifier already has different content.';
}
