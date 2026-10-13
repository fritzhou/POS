import 'dart:convert';

import 'package:cryptography/cryptography.dart';

import '../auth/secure_session_storage.dart';
import '../sync/sync_event.dart';
import 'offline_protocol.dart';

class _OfflineSecurityState {
  Future<void> tail = Future<void>.value();
  bool locked = false;
}

/// Device authorization is separate from authentication. A verified online
/// actor must explicitly consent before this service creates a private key.
/// Software clocks and OS secret storage do not attest hardware-trusted time.
class OfflineDeviceSecurity {
  OfflineDeviceSecurity({
    required this.store,
    DateTime Function()? clock,
    this.namespace = 'nexapos.offline.v1',
  }) : _clock = clock ?? DateTime.now;

  final SecretStore store;
  final DateTime Function() _clock;
  final String namespace;
  // Multiple organization workspaces can share this same secure namespace.
  // Keep their state transitions serialized even when reconstructed with a new
  // service instance over the same SecretStore in this process.
  static final Expando<Map<String, _OfflineSecurityState>> _states = Expando();
  _OfflineSecurityState get _state {
    final states = _states[store] ??= <String, _OfflineSecurityState>{};
    return states[namespace] ??= _OfflineSecurityState();
  }

  String _identityKey(String org, String actor) =>
      '$namespace.identity.$org.$actor';
  String get _identityIndexKey => '$namespace.identity_index';
  String get _activeActorKey => '$namespace.active_actor';
  String _grantKey(String grantId) => '$namespace.grant.$grantId';
  String _checkpointKey(String grantId) => '$namespace.checkpoint.$grantId';
  String _branchKey(String org, String actor, String branch) =>
      '$namespace.active.$org.$actor.$branch';

  Future<T> _serial<T>(Future<T> Function() operation) {
    final state = _state;
    final result = state.tail.then((_) => operation());
    state.tail = result.then<void>(
      (_) {},
      onError: (Object _, StackTrace _) {},
    );
    return result;
  }

  Future<T> _serialWithProof<T>(
    Map<String, Object?> proof,
    Future<T> Function(Map<String, Object?> frozen) operation,
  ) {
    // Capture inputs before the queued operation yields to any secure-store or
    // signing work. The caller cannot change the proof while it is awaiting.
    try {
      final frozen = immutableOfflineValue(proof)! as Map<String, Object?>;
      return _serial(() => operation(frozen));
    } on Object catch (error, stack) {
      return Future.error(error, stack);
    }
  }

  Map<String, Object?> _decode(String encoded) {
    try {
      final value = jsonDecode(encoded);
      if (value is! Map<String, Object?>) throw const FormatException();
      strictCanonicalJson(value);
      return value;
    } on Object {
      throw const OfflineSecurityException('CORRUPT_SECURE_STATE');
    }
  }

  Future<Map<String, Object?>?> _identityRecord(
    String org,
    String actor,
  ) async {
    if (_state.locked) return null;
    if (await store.read('$namespace.locked') == 'true') return null;
    final encoded = await store.read(_identityKey(org, actor));
    if (encoded == null) return null;
    final record = _decode(encoded);
    if (record.length != 5 ||
        record['seed'] is! String ||
        record['public_key'] is! String) {
      throw const OfflineSecurityException('CORRUPT_SECURE_STATE');
    }
    offlineUuid(record['device_id']);
    offlineUuid(record['organization_id']);
    offlineUuid(record['actor_id']);
    if (record['organization_id'] != org || record['actor_id'] != actor) {
      throw const OfflineSecurityException('CORRUPT_SECURE_STATE');
    }
    final pair = await Ed25519().newKeyPairFromSeed(
      decodeOfflineBytes(record['seed']! as String, length: 32),
    );
    final public = await pair.extractPublicKey();
    if (encodeOfflineBytes(public.bytes) != record['public_key']) {
      throw const OfflineSecurityException('CORRUPT_SECURE_STATE');
    }
    return record;
  }

  Future<void> _lockKeys() async {
    // Deny further in-process use even if the first secure-store write fails.
    // A durable marker cannot be promised when the OS store rejects writes.
    _state.locked = true;
    // The lock marker is durable before deleting keys. Even a partial secret
    // store deletion failure cannot recreate offline authority after restart.
    await store.write('$namespace.locked', 'true');
    final encoded = await store.read(_identityIndexKey);
    if (encoded != null) {
      final index = _decode(encoded);
      for (final entry in index.entries) {
        final scope = entry.key.split('.');
        if (scope.length != 2 || entry.value != true) {
          throw const OfflineSecurityException('CORRUPT_SECURE_STATE');
        }
        await store.delete(
          _identityKey(offlineUuid(scope[0]), offlineUuid(scope[1])),
        );
      }
    }
    await store.delete(_identityIndexKey);
    await store.delete(_activeActorKey);
  }

  Future<void> _switchActor(String actor) async {
    final previous = await store.read(_activeActorKey);
    if (previous != null && previous != actor) await _lockKeys();
  }

  DeviceIdentity _publicIdentity(Map<String, Object?> record) => DeviceIdentity(
    deviceId: record['device_id']! as String,
    organizationId: record['organization_id']! as String,
    actorId: record['actor_id']! as String,
    publicKey: record['public_key']! as String,
  );

  Future<DeviceIdentity> enable({
    required String organizationId,
    required String actorId,
    required bool explicitConsent,
  }) => _serial(() async {
    offlineUuid(organizationId);
    offlineUuid(actorId);
    if (!explicitConsent) {
      throw const OfflineSecurityException('CONSENT_REQUIRED');
    }
    await _switchActor(actorId);
    if (_state.locked || await store.read('$namespace.locked') == 'true') {
      await _lockKeys();
    }
    final previous = await _identityRecord(organizationId, actorId);
    if (previous != null) {
      if (previous['organization_id'] == organizationId &&
          previous['actor_id'] == actorId) {
        return _publicIdentity(previous);
      }
    }
    final pair = await Ed25519().newKeyPair();
    final private = await pair.extractPrivateKeyBytes();
    final public = await pair.extractPublicKey();
    final record = <String, Object?>{
      'device_id': newLocalId(),
      'organization_id': organizationId,
      'actor_id': actorId,
      'public_key': encodeOfflineBytes(public.bytes),
      'seed': encodeOfflineBytes(private),
    };
    // Keep the namespace locked until every key locator is durable. Recording
    // the index before the private seed means interrupted enrollment can still
    // delete every key when the account is locked on its next launch.
    _state.locked = true;
    await store.write('$namespace.locked', 'true');
    final encodedIndex = await store.read(_identityIndexKey);
    final index = encodedIndex == null
        ? <String, Object?>{}
        : _decode(encodedIndex);
    index['$organizationId.$actorId'] = true;
    await store.write(_identityIndexKey, strictCanonicalJson(index));
    await store.write(_activeActorKey, actorId);
    await store.write(
      _identityKey(organizationId, actorId),
      strictCanonicalJson(record),
    );
    await store.delete('$namespace.locked');
    _state.locked = false;
    return _publicIdentity(record);
  });

  Future<DeviceIdentity?> restore({
    required String organizationId,
    required String actorId,
  }) => _serial(() async {
    offlineUuid(organizationId);
    offlineUuid(actorId);
    await _switchActor(actorId);
    final record = await _identityRecord(organizationId, actorId);
    if (record == null) return null;
    if (record['organization_id'] != organizationId ||
        record['actor_id'] != actorId) {
      // Account change locks the old identity without touching paid rows.
      await _lockKeys();
      return null;
    }
    return _publicIdentity(record);
  });

  Future<Map<String, Object?>> _requireIdentity(OfflineGrant grant) async {
    final identity = await _identityRecord(
      grant.scope.organizationId,
      grant.scope.actorId,
    );
    if (identity == null ||
        identity['organization_id'] != grant.scope.organizationId ||
        identity['actor_id'] != grant.scope.actorId ||
        identity['device_id'] != grant.scope.deviceId) {
      throw const OfflineSecurityException('DEVICE_LOCKED');
    }
    if (!grant.isVerified) {
      throw const OfflineSecurityException('UNVERIFIED_GRANT');
    }
    return identity;
  }

  Future<String> _sign(
    Map<String, Object?> identity,
    String domain,
    Object? payload,
  ) async {
    final pair = await Ed25519().newKeyPairFromSeed(
      decodeOfflineBytes(identity['seed']! as String, length: 32),
    );
    final signature = await Ed25519().sign(
      utf8.encode('$domain${strictCanonicalJson(payload)}'),
      keyPair: pair,
    );
    return encodeOfflineBytes(signature.bytes);
  }

  Future<String> signEnrollment(Map<String, Object?> proof) =>
      _serialWithProof(proof, (challenge) async {
        final org = offlineUuid(challenge['organization_id']);
        final actor = offlineUuid(challenge['actor_id']);
        final identity = await _identityRecord(org, actor);
        if (identity == null) {
          throw const OfflineSecurityException('DEVICE_LOCKED');
        }
        const keys = {
          'challenge_id',
          'nonce',
          'organization_id',
          'branch_id',
          'device_id',
          'actor_id',
          'public_key',
          'expires_at',
        };
        if (challenge.length != keys.length ||
            !challenge.keys.every(keys.contains) ||
            challenge['organization_id'] != identity['organization_id'] ||
            challenge['actor_id'] != identity['actor_id'] ||
            challenge['device_id'] != identity['device_id'] ||
            challenge['public_key'] != identity['public_key']) {
          throw const OfflineSecurityException('WRONG_SCOPE');
        }
        offlineUuid(challenge['challenge_id']);
        offlineUuid(challenge['branch_id']);
        offlineUtc(challenge['expires_at']);
        if (challenge['nonce'] is! String) {
          throw const OfflineSecurityException('INVALID_CHALLENGE');
        }
        decodeOfflineBytes(challenge['nonce']! as String, length: 32);
        return _sign(identity, offlineEnrollmentDomain, challenge);
      });

  Future<void> retainGrant(OfflineGrant grant) => _serial(() async {
    await _requireIdentity(grant);
    final encoded = strictCanonicalJson(grant.toWire());
    final previous = await store.read(_grantKey(grant.grantId));
    if (previous != null && previous != encoded) {
      throw const OfflineSecurityException('GRANT_CHANGED');
    }
    await store.write(_grantKey(grant.grantId), encoded);
    await store.write(
      _branchKey(
        grant.scope.organizationId,
        grant.scope.actorId,
        grant.scope.branchId,
      ),
      grant.grantId,
    );
    final indexKey = '$namespace.grant_index.${grant.scope.actorId}';
    final previousIndex = await store.read(indexKey);
    final index = previousIndex == null
        ? <String, Object?>{}
        : _decode(previousIndex);
    index['${grant.scope.organizationId}.${grant.scope.branchId}'] =
        grant.grantId;
    await store.write(indexKey, strictCanonicalJson(index));
  });

  /// Public locator records are untrusted until the pinned verifier checks the
  /// corresponding immutable database snapshot. They never authenticate users.
  Future<List<OfflineGrant>> retainedScopes({required String actorId}) =>
      _serial(() async {
        offlineUuid(actorId);
        final encoded = await store.read('$namespace.grant_index.$actorId');
        if (encoded == null) return const [];
        final index = _decode(encoded);
        final grants = <OfflineGrant>[];
        for (final entry in index.entries) {
          final id = offlineUuid(entry.value);
          final wire = await store.read(_grantKey(id));
          if (wire == null) {
            throw const OfflineSecurityException('CORRUPT_SECURE_STATE');
          }
          final grant = OfflineGrant.fromWire(_decode(wire));
          if (grant.grantId != id ||
              grant.scope.actorId != actorId ||
              entry.key !=
                  '${grant.scope.organizationId}.${grant.scope.branchId}') {
            throw const OfflineSecurityException('CORRUPT_SECURE_STATE');
          }
          grants.add(grant);
        }
        return List.unmodifiable(grants);
      });

  Future<OfflineGrant?> restoreGrant({
    required String organizationId,
    required String actorId,
    required String branchId,
  }) => _serial(() async {
    offlineUuid(organizationId);
    offlineUuid(actorId);
    offlineUuid(branchId);
    final id = await store.read(_branchKey(organizationId, actorId, branchId));
    if (id == null) return null;
    offlineUuid(id);
    final encoded = await store.read(_grantKey(id));
    if (encoded == null) {
      throw const OfflineSecurityException('CORRUPT_SECURE_STATE');
    }
    final grant = OfflineGrant.fromWire(_decode(encoded));
    if (grant.grantId != id ||
        grant.scope.organizationId != organizationId ||
        grant.scope.actorId != actorId ||
        grant.scope.branchId != branchId) {
      throw const OfflineSecurityException('WRONG_SCOPE');
    }
    return grant;
  });

  DateTime _wall() => _clock().toUtc();
  Future<void> anchor({
    required OfflineGrant grant,
    required DateTime serverTime,
  }) => _serial(() async {
    await _requireIdentity(grant);
    if (!serverTime.isUtc ||
        serverTime.isBefore(grant.issuedAt) ||
        !serverTime.isBefore(grant.expiresAt)) {
      throw const OfflineSecurityException('INVALID_SERVER_TIME');
    }
    final wall = _wall();
    final previous = await store.read(_checkpointKey(grant.grantId));
    if (previous != null) {
      final checkpoint = _decode(previous);
      _checkBinding(checkpoint, grant);
      if (wall.isBefore(offlineUtc(checkpoint['high_water_wall'])) ||
          serverTime.isBefore(offlineUtc(checkpoint['high_water_server']))) {
        throw const OfflineSecurityException('CLOCK_ROLLBACK');
      }
    }
    final checkpoint = <String, Object?>{
      'grant_id': grant.grantId,
      'grant_digest': canonicalHash(grant.toWire()),
      'anchored_server': serverTime.toIso8601String(),
      'anchored_wall': wall.toIso8601String(),
      'high_water_wall': wall.toIso8601String(),
      'high_water_server': serverTime.toIso8601String(),
    };
    await store.write(
      _checkpointKey(grant.grantId),
      strictCanonicalJson(checkpoint),
    );
  });

  void _checkBinding(Map<String, Object?> checkpoint, OfflineGrant grant) {
    if (checkpoint.length != 6 ||
        checkpoint['grant_id'] != grant.grantId ||
        checkpoint['grant_digest'] != canonicalHash(grant.toWire())) {
      throw const OfflineSecurityException('CORRUPT_SECURE_STATE');
    }
  }

  Future<DateTime> _estimatedTime(OfflineGrant grant) async {
    await _requireIdentity(grant);
    final encoded = await store.read(_checkpointKey(grant.grantId));
    if (encoded == null) {
      throw const OfflineSecurityException('MISSING_TIME_ANCHOR');
    }
    final checkpoint = _decode(encoded);
    _checkBinding(checkpoint, grant);
    final wall = _wall();
    final anchoredWall = offlineUtc(checkpoint['anchored_wall']);
    final highWall = offlineUtc(checkpoint['high_water_wall']);
    if (wall.isBefore(highWall) || wall.isBefore(anchoredWall)) {
      throw const OfflineSecurityException('CLOCK_ROLLBACK');
    }
    final estimated = offlineUtc(
      checkpoint['anchored_server'],
    ).add(wall.difference(anchoredWall));
    if (estimated.isBefore(offlineUtc(checkpoint['high_water_server']))) {
      throw const OfflineSecurityException('CLOCK_ROLLBACK');
    }
    checkpoint['high_water_wall'] = wall.toIso8601String();
    checkpoint['high_water_server'] = estimated.toIso8601String();
    await store.write(
      _checkpointKey(grant.grantId),
      strictCanonicalJson(checkpoint),
    );
    return estimated;
  }

  /// Read-only status can inspect expired grants, but rollback always fails.
  Future<DateTime> estimatedTime(OfflineGrant grant) =>
      _serial(() => _estimatedTime(grant));

  Future<DateTime> _authorize(OfflineGrant grant, OfflineScope scope) async {
    if (!scope.matches(grant.scope)) {
      throw const OfflineSecurityException('WRONG_SCOPE');
    }
    if (await store.read('$namespace.released.${grant.grantId}') == 'true') {
      throw const OfflineSecurityException('GRANT_RELEASED');
    }
    final now = await _estimatedTime(grant);
    if (now.isBefore(grant.issuedAt) || !now.isBefore(grant.expiresAt)) {
      throw const OfflineSecurityException('EXPIRED_GRANT');
    }
    return now;
  }

  Future<DateTime> authorize({
    required OfflineGrant grant,
    required OfflineScope scope,
  }) => _serial(() => _authorize(grant, scope));

  Future<String> signEvent({
    required OfflineGrant grant,
    required String eventDigest,
    required int sequence,
    required Map<String, Object?> paymentEvidence,
  }) => _serialWithProof(paymentEvidence, (evidence) async {
    await _authorize(grant, grant.scope);
    if (!RegExp(r'^[0-9a-f]{64}$').hasMatch(eventDigest) ||
        sequence < 1 ||
        sequence > grant.maxEvents) {
      throw const OfflineSecurityException('INVALID_EVENT_PROOF');
    }
    if (evidence.isEmpty || evidence.length > 5) {
      throw const OfflineSecurityException('INVALID_PAYMENT_EVIDENCE');
    }
    for (final entry in evidence.entries) {
      offlineUuid(entry.key);
      final value = entry.value;
      if (value is! Map<String, Object?>) {
        throw const OfflineSecurityException('INVALID_PAYMENT_EVIDENCE');
      }
      if (value.length == 1 && value.containsKey('tendered_minor')) {
        offlineInteger(value['tendered_minor'], min: 1, max: 9007199254740991);
      } else if (value.length == 1 && value['manual_confirmed'] == true) {
        // The reference lives exclusively in the immutable payment snapshot.
      } else {
        throw const OfflineSecurityException('INVALID_PAYMENT_EVIDENCE');
      }
    }
    return _sign(await _requireIdentity(grant), offlineEventDomain, {
      'event_digest': eventDigest,
      'grant_id': grant.grantId,
      'sequence': sequence,
      'payment_evidence': evidence,
    });
  });

  Future<String> signTenderFragment({
    required OfflineGrant grant,
    required String fragmentDigest,
    required String requestId,
    required int index,
  }) => _serial(() async {
    await _authorize(grant, grant.scope);
    offlineUuid(requestId);
    offlineInteger(index, min: 0, max: 4);
    if (!RegExp(r'^[0-9a-f]{64}$').hasMatch(fragmentDigest)) {
      throw const OfflineSecurityException('INVALID_TENDER_PROOF');
    }
    return _sign(await _requireIdentity(grant), offlineTenderDomain, {
      'fragment_digest': fragmentDigest,
      'request_id': requestId,
      'grant_id': grant.grantId,
      'index': index,
    });
  });

  Future<String> signRelease({
    required String grantId,
    required int finalSequence,
  }) => _serial(() async {
    offlineUuid(grantId);
    offlineInteger(finalSequence, min: 0, max: maximumOfflineEvents);
    final wire = await store.read(_grantKey(grantId));
    if (wire == null) {
      throw const OfflineSecurityException('DEVICE_LOCKED');
    }
    final grant = OfflineGrant.fromWire(_decode(wire));
    final identity = await _identityRecord(
      grant.scope.organizationId,
      grant.scope.actorId,
    );
    if (identity == null) {
      throw const OfflineSecurityException('DEVICE_LOCKED');
    }
    if (grant.grantId != grantId ||
        grant.scope.deviceId != identity['device_id'] ||
        grant.scope.actorId != identity['actor_id'] ||
        grant.scope.organizationId != identity['organization_id'] ||
        finalSequence > grant.maxEvents) {
      throw const OfflineSecurityException('WRONG_SCOPE');
    }
    // Release may follow expiry: it creates no new financial authorization.
    return _sign(identity, offlineReleaseDomain, {
      'grant_id': grantId,
      'final_sequence': finalSequence,
    });
  });

  Future<void> markReleased(String grantId) => _serial(() async {
    offlineUuid(grantId);
    await store.write('$namespace.released.$grantId', 'true');
  });

  Future<bool> isReleased(String grantId) => _serial(() async {
    offlineUuid(grantId);
    return await store.read('$namespace.released.$grantId') == 'true';
  });

  /// Explicit logout/recovery/account changes destroy the unlock key. Public
  /// grants and paid immutable proof/outbox records are retained for review.
  Future<void> lock() => _serial(_lockKeys);
}
