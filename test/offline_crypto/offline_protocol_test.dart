import 'dart:convert';
import 'dart:io';

import 'package:cryptography/cryptography.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nexapos/app/config/backend_config.dart';
import 'package:nexapos/core/auth/secure_session_storage.dart';
import 'package:nexapos/core/offline/offline_device_security.dart';
import 'package:nexapos/core/offline/offline_protocol.dart';

const org = '00000000-0000-4000-8000-000000000003';
const actor = '00000000-0000-4000-8000-000000000002';
const branch = '00000000-0000-4000-8000-000000000004';
const device = '00000000-0000-4000-8000-000000000005';
const membership = '00000000-0000-4000-8000-000000000006';
const shift = '00000000-0000-4000-8000-000000000007';
const grantId = '00000000-0000-4000-8000-000000000008';
const product = '00000000-0000-4000-8000-000000000009';
const payment = '00000000-0000-4000-8000-000000000010';
const issuer = 'https://unit.supabase.co';
final now = DateTime.utc(2026, 10, 10, 12);

List<int> hex(String value) => [
  for (var i = 0; i < value.length; i += 2)
    int.parse(value.substring(i, i + 2), radix: 16),
];
const seedHex =
    '9d61b19deffd5a60ba844af492ec2cc44449c5697b326919703bac031cae7f60';
const publicHex =
    'd75a980182b10ab7d54bfed3c964073a0ee172f3daa62325af021a68f707511a';
const signatureHex =
    'e5564300c360ac729086e2cc806e828a84877f1eb8e5d974d873e065224901555f'
    'b8821590a33bacc61e39701cf9b46bd25bf5f0595bbe24655141438e7a100b';

OfflineScope scope({String deviceId = device, String actorId = actor}) =>
    OfflineScope(
      organizationId: org,
      branchId: branch,
      actorId: actorId,
      membershipId: membership,
      deviceId: deviceId,
      shiftId: shift,
      role: 'cashier',
    );

Map<String, Object?> snapshot() => {
  'context': {
    'organization_id': org,
    'branch_id': branch,
    'currency': 'PHP',
    'tax_bps': 1200,
    'settings_revision': 1,
    'business_name': 'Test business',
    'address': 'Public receipt address',
    'contact': 'Business contact',
  },
  'shift': {
    'id': shift,
    'actor_user_id': actor,
    'organization_id': org,
    'branch_id': branch,
    'currency': 'PHP',
    'closed_at': null,
  },
  'products': [
    {
      'id': product,
      'organization_id': org,
      'currency': 'PHP',
      'name': 'Café 😀',
      'sku': 'TEST-1',
      'price_minor': 100,
      'revision': 1,
    },
  ],
  'categories': <Object?>[],
  'stock': [
    {'product_id': product, 'quantity': 2, 'revision': 0},
  ],
  'cursor': 0,
};

Map<String, Object?> claims(
  Map<String, Object?> snap, {
  String deviceId = device,
}) => {
  'schema_version': 1,
  'issuer': issuer,
  'audience': offlineAudience,
  'key_id': 'unit-key',
  'grant_id': grantId,
  'organization_id': org,
  'branch_id': branch,
  'device_id': deviceId,
  'actor_id': actor,
  'membership_id': membership,
  'role': 'cashier',
  'business_name': 'Test business',
  'allowed_actions': ['sale.created'],
  'issued_at': now.toIso8601String(),
  'expires_at': now.add(const Duration(hours: 8)).toIso8601String(),
  'shift_id': shift,
  'currency': 'PHP',
  'tax_bps': 1200,
  'settings_revision': 1,
  'snapshot_digest': canonicalHash(snap),
  'max_events': 1000,
  'max_total_minor': 100000000,
};

Future<Map<String, Object?>> wire(Map<String, Object?> claims) async {
  final pair = await Ed25519().newKeyPairFromSeed(hex(seedHex));
  final signature = await Ed25519().sign(
    utf8.encode('$offlineGrantDomain${strictCanonicalJson(claims)}'),
    keyPair: pair,
  );
  return {'claims': claims, 'signature': encodeOfflineBytes(signature.bytes)};
}

OfflineGrantVerifier verifier({
  Map<String, String>? keys,
  String url = issuer,
}) => OfflineGrantVerifier(
  issuer: url,
  trustedKeys: keys ?? {'unit-key': encodeOfflineBytes(hex(publicHex))},
);

Matcher failure(String code) =>
    isA<OfflineSecurityException>().having((error) => error.code, 'code', code);

class MemorySecrets implements SecretStore {
  final values = <String, String>{};
  @override
  Future<String?> read(String key) async => values[key];
  @override
  Future<void> write(String key, String value) async {
    values[key] = value;
  }

  @override
  Future<void> delete(String key) async {
    values.remove(key);
  }
}

class FailingSecrets extends MemorySecrets {
  String? failedWrite;
  String? failedDelete;

  @override
  Future<void> write(String key, String value) async {
    if (key == failedWrite) throw StateError('Secret store write interrupted.');
    await super.write(key, value);
  }

  @override
  Future<void> delete(String key) async {
    if (key == failedDelete) {
      throw StateError('Secret store delete interrupted.');
    }
    await super.delete(key);
  }
}

void main() {
  test('RFC 8032 raw seed, public key and empty-message signature', () async {
    final pair = await Ed25519().newKeyPairFromSeed(hex(seedHex));
    expect((await pair.extractPublicKey()).bytes, hex(publicHex));
    expect((await pair.extractPrivateKeyBytes()), hex(seedHex));
    final signature = await Ed25519().sign([], keyPair: pair);
    expect(signature.bytes, hex(signatureHex));
  });

  test(
    'canonical cross-platform fixture preserves numeric keys and microseconds',
    () async {
      final fixture =
          jsonDecode(
                File(
                  'test/fixtures/offline_crypto_contract.json',
                ).readAsStringSync(),
              )
              as Map<String, dynamic>;
      final value = fixture['event'] as Map<String, Object?>;
      expect(
        canonicalHash(value),
        'd007dcd5a26cb15aac332be4316591162e63c4a0249228b1ad46c6ab2d6d28cb',
      );
      expect(strictCanonicalJson(value), fixture['canonical_event']);
      final public = SimplePublicKey(
        decodeOfflineBytes(fixture['public_key'] as String, length: 32),
        type: KeyPairType.ed25519,
      );
      for (final sample in fixture['signatures'] as List) {
        final item = sample as Map<String, dynamic>;
        expect(
          await Ed25519().verify(
            utf8.encode(
              '${item['domain']}${strictCanonicalJson(item['payload'])}',
            ),
            signature: Signature(
              decodeOfflineBytes(item['signature'] as String, length: 64),
              publicKey: public,
            ),
          ),
          isTrue,
        );
      }
    },
  );

  test(
    'canonical rejects malformed Unicode, floats, unsafe integers and padding',
    () {
      for (final value in [
        String.fromCharCode(0xd800),
        {'bad': String.fromCharCode(0xdc00)},
        {String.fromCharCode(0xd800): 1},
        1.0,
        -0.0,
        double.nan,
        9007199254740992,
      ]) {
        expect(
          () => strictCanonicalJson(value),
          throwsA(failure('INVALID_PROTOCOL')),
        );
      }
      expect(
        () => decodeOfflineBytes(
          '${encodeOfflineBytes(hex(publicHex))}=',
          length: 32,
        ),
        throwsA(failure('INVALID_PROTOCOL')),
      );
      expect(
        () => offlineUtc('2026-02-30T00:00:00Z'),
        throwsA(failure('INVALID_PROTOCOL')),
      );
      expect(
        () => offlineUtc('2026-10-10T12:00:00+08:00'),
        throwsA(failure('INVALID_PROTOCOL')),
      );
      for (final date in [
        '2026-13-01T00:00:00Z',
        '2026-01-01T24:00:00Z',
        '2026-01-01T00:60:00Z',
        '2026-01-01T00:00:60Z',
        '2026-01-01T00:00:00.1234567Z',
      ]) {
        expect(() => offlineUtc(date), throwsA(failure('INVALID_PROTOCOL')));
      }
      expect(offlineUtc('2026-10-10T12:13:14.123456Z').microsecond, 456);
    },
  );

  test('verified grant binds signed issuer, scope and full snapshot', () async {
    final snap = snapshot();
    final grant = await verifier().verify(
      wire: await wire(claims(snap)),
      snapshot: snap,
      scope: scope(),
      serverTime: now,
    );
    expect(grant.isVerified, isTrue);
    expect(grant.scope.matches(scope()), isTrue);
    expect(grant.snapshotDigest, canonicalHash(snap));
    expect(() => grant.claims['role'] = 'owner', throwsUnsupportedError);
    expect(
      () => (grant.claims['allowed_actions'] as List).add('refund'),
      throwsUnsupportedError,
    );
    snap['cursor'] = 1;
    expect(grant.snapshotDigest, isNot(canonicalHash(snap)));
    expect(OfflineGrant.fromWire(grant.toWire()).isVerified, isFalse);
  });

  test(
    'response keys cannot supply trust; wrong scope, issuer and signatures fail',
    () async {
      final snap = snapshot();
      final envelope = await wire(claims(snap));
      expect(
        verifier(keys: {}).verify(
          wire: envelope,
          snapshot: snap,
          scope: scope(),
          serverTime: now,
        ),
        throwsA(failure('UNTRUSTED_KEY')),
      );
      expect(
        verifier(url: 'https://other.supabase.co').verify(
          wire: envelope,
          snapshot: snap,
          scope: scope(),
          serverTime: now,
        ),
        throwsA(failure('WRONG_ISSUER')),
      );
      expect(
        verifier().verify(
          wire: envelope,
          snapshot: snap,
          scope: scope(actorId: membership),
          serverTime: now,
        ),
        throwsA(failure('WRONG_SCOPE')),
      );
      final changed = {
        ...envelope,
        'signature': encodeOfflineBytes(List.filled(64, 0)),
      };
      expect(
        verifier().verify(
          wire: changed,
          snapshot: snap,
          scope: scope(),
          serverTime: now,
        ),
        throwsA(failure('BAD_SIGNATURE')),
      );
      expect(
        verifier().verify(
          wire: envelope,
          snapshot: {...snap, 'cursor': 1},
          scope: scope(),
          serverTime: now,
        ),
        throwsA(failure('BAD_SNAPSHOT')),
      );
    },
  );

  test(
    'grant schema enforces action, role, duration and finite ceilings',
    () async {
      final snap = snapshot();
      for (final change in <Map<String, Object?>>[
        {'extra': true},
        {'schema_version': 1.0},
        {
          'allowed_actions': ['sale.created', 'sale.refund'],
        },
        {'role': 'inventory_staff'},
        {'max_events': 1001},
        {'max_total_minor': 100000001},
        {
          'expires_at': now
              .add(const Duration(hours: 8, microseconds: 1))
              .toIso8601String(),
        },
        {'tax_bps': -1},
        {'settings_revision': 1.0},
        {'currency': 'JPY'},
      ]) {
        final body = {...claims(snap), ...change};
        expect(
          () => OfflineGrant.fromWire({
            'claims': body,
            'signature': encodeOfflineBytes(List.filled(64, 0)),
          }),
          throwsA(failure('INVALID_PROTOCOL')),
        );
      }
    },
  );

  test(
    'signed incomplete or restricted snapshots still fail verification',
    () async {
      for (final snap in [
        {...snapshot(), 'stock': <Object?>[]},
        {
          ...snapshot(),
          'categories': [
            {
              'id': membership,
              'organization_id': branch,
              'name': 'Other organization category',
              'active': true,
              'revision': 1,
            },
          ],
        },
        {
          ...snapshot(),
          'products': [
            {
              'id': product,
              'organization_id': org,
              'currency': 'PHP',
              'name': 'Inactive product',
              'sku': 'TEST',
              'price_minor': 1,
              'revision': 1,
              'active': false,
            },
          ],
        },
        {
          ...snapshot(),
          'products': [
            {
              'id': product,
              'organization_id': org,
              'currency': 'PHP',
              'name': 'X',
              'sku': 'X',
              'price_minor': 1,
              'revision': 1,
              'cost_minor': null,
            },
          ],
        },
        {
          ...snapshot(),
          'shift': {
            'id': shift,
            'organization_id': org,
            'branch_id': branch,
            'currency': 'PHP',
            'actor_user_id': membership,
          },
        },
      ]) {
        await expectLater(
          verifier().verify(
            wire: await wire(claims(snap)),
            snapshot: snap,
            scope: scope(),
            serverTime: now,
          ),
          throwsA(isA<OfflineSecurityException>()),
        );
      }
    },
  );

  test(
    'expiry is strict for new entry; retained history can verify later',
    () async {
      final snap = snapshot();
      final envelope = await wire(claims(snap));
      expect(
        verifier().verify(
          wire: envelope,
          snapshot: snap,
          scope: scope(),
          serverTime: now.add(const Duration(hours: 8)),
        ),
        throwsA(failure('EXPIRED_GRANT')),
      );
      expect(
        (await verifier().verify(
          wire: envelope,
          snapshot: snap,
          scope: scope(),
          serverTime: now.add(const Duration(hours: 8, microseconds: -1)),
        )).isVerified,
        isTrue,
      );
      expect(
        (await verifier().verify(
          wire: envelope,
          snapshot: snap,
          scope: scope(),
          serverTime: now.add(const Duration(days: 8)),
          allowExpired: true,
        )).isVerified,
        isTrue,
      );
    },
  );

  test(
    'public key config remains optional and cannot alter Auth validation',
    () {
      const disabled = BackendConfig(
        url: issuer,
        clientKey: 'sb_publishable_unit',
      );
      expect(disabled.validationError, isNull);
      expect(disabled.offlineTrustedKeys, isEmpty);
      final configured = BackendConfig(
        url: issuer,
        clientKey: 'sb_publishable_unit',
        offlineTrustedKeysJson: jsonEncode({
          'key-v1': encodeOfflineBytes(hex(publicHex)),
        }),
      );
      expect(configured.offlineValidationError, isNull);
      expect(
        () => configured.offlineTrustedKeys['bad'] = 'x',
        throwsUnsupportedError,
      );
      const invalid = BackendConfig(
        url: issuer,
        clientKey: 'sb_publishable_unit',
        offlineTrustedKeysJson: '{"key":"private material"}',
      );
      expect(invalid.validationError, isNull);
      expect(invalid.offlineValidationError, isNotNull);
      expect(() => invalid.offlineTrustedKeys, throwsFormatException);
    },
  );

  test(
    'private seed requires consent and remains solely in secret store',
    () async {
      final secrets = MemorySecrets();
      final service = OfflineDeviceSecurity(store: secrets, clock: () => now);
      expect(
        service.enable(
          organizationId: org,
          actorId: actor,
          explicitConsent: false,
        ),
        throwsA(failure('CONSENT_REQUIRED')),
      );
      expect(secrets.values, isEmpty);
      final identity = await service.enable(
        organizationId: org,
        actorId: actor,
        explicitConsent: true,
      );
      expect(identity.toJson().containsKey('seed'), isFalse);
      expect(decodeOfflineBytes(identity.publicKey, length: 32), hasLength(32));
      expect(
        (await service.restore(organizationId: org, actorId: actor))?.deviceId,
        identity.deviceId,
      );
      expect(
        (await service.enable(
          organizationId: org,
          actorId: actor,
          explicitConsent: true,
        )).deviceId,
        identity.deviceId,
      );
      expect(
        await service.restore(organizationId: org, actorId: membership),
        isNull,
      );
      expect(
        await service.restore(organizationId: org, actorId: actor),
        isNull,
      );
    },
  );

  test(
    'secure high-water survives restart and detects clock rollback',
    () async {
      final secrets = MemorySecrets();
      var wall = now.add(
        const Duration(hours: 2),
      ); // Host clock offset is anchored.
      var service = OfflineDeviceSecurity(store: secrets, clock: () => wall);
      final identity = await service.enable(
        organizationId: org,
        actorId: actor,
        explicitConsent: true,
      );
      final snap = snapshot();
      final grant = await verifier().verify(
        wire: await wire(claims(snap, deviceId: identity.deviceId)),
        snapshot: snap,
        scope: scope(deviceId: identity.deviceId),
        serverTime: now,
      );
      await service.retainGrant(grant);
      expect(
        service.authorize(grant: grant, scope: grant.scope),
        throwsA(failure('MISSING_TIME_ANCHOR')),
      );
      await service.anchor(grant: grant, serverTime: now);
      wall = wall.add(const Duration(minutes: 12));
      expect(
        await service.authorize(grant: grant, scope: grant.scope),
        now.add(const Duration(minutes: 12)),
      );
      service = OfflineDeviceSecurity(store: secrets, clock: () => wall);
      expect(
        await service.estimatedTime(grant),
        now.add(const Duration(minutes: 12)),
      );
      wall = wall.subtract(const Duration(microseconds: 1));
      expect(
        service.authorize(grant: grant, scope: grant.scope),
        throwsA(failure('CLOCK_ROLLBACK')),
      );
      expect(
        service.anchor(
          grant: grant,
          serverTime: now.add(const Duration(minutes: 13)),
        ),
        throwsA(failure('CLOCK_ROLLBACK')),
      );
    },
  );

  test('interrupted key installation fails closed through restart', () async {
    final secrets = FailingSecrets();
    const namespace = 'interrupted';
    secrets.failedWrite = '$namespace.identity.$org.$actor';
    var service = OfflineDeviceSecurity(store: secrets, namespace: namespace);
    await expectLater(
      service.enable(
        organizationId: org,
        actorId: actor,
        explicitConsent: true,
      ),
      throwsStateError,
    );
    expect(secrets.values['$namespace.locked'], 'true');
    expect(secrets.values['$namespace.identity_index'], contains(org));
    service = OfflineDeviceSecurity(store: secrets, namespace: namespace);
    expect(await service.restore(organizationId: org, actorId: actor), isNull);
    secrets.failedWrite = null;
    final fresh = await service.enable(
      organizationId: org,
      actorId: actor,
      explicitConsent: true,
    );
    expect(
      (await service.restore(organizationId: org, actorId: actor))?.deviceId,
      fresh.deviceId,
    );
    expect(secrets.values.containsKey('$namespace.locked'), isFalse);
  });

  test(
    'failed lock-marker write still denies every in-process key use',
    () async {
      final secrets = FailingSecrets();
      const namespace = 'failed-marker';
      final service = OfflineDeviceSecurity(
        store: secrets,
        namespace: namespace,
        clock: () => now,
      );
      final identity = await service.enable(
        organizationId: org,
        actorId: actor,
        explicitConsent: true,
      );
      final snap = snapshot();
      final grant = await verifier().verify(
        wire: await wire(claims(snap, deviceId: identity.deviceId)),
        snapshot: snap,
        scope: scope(deviceId: identity.deviceId),
        serverTime: now,
      );
      await service.retainGrant(grant);
      await service.anchor(grant: grant, serverTime: now);
      final proof = await service.signEvent(
        grant: grant,
        eventDigest: 'a' * 64,
        sequence: 1,
        paymentEvidence: {
          payment: {'tendered_minor': 200},
        },
      );
      final retainedGrant = secrets.values['$namespace.grant.$grantId'];
      final retainedCheckpoint =
          secrets.values['$namespace.checkpoint.$grantId'];
      secrets.failedWrite = '$namespace.locked';
      await expectLater(service.lock(), throwsStateError);
      expect(secrets.values.containsKey('$namespace.locked'), isFalse);
      expect(
        await service.restore(organizationId: org, actorId: actor),
        isNull,
      );
      await expectLater(
        service.authorize(grant: grant, scope: grant.scope),
        throwsA(failure('DEVICE_LOCKED')),
      );
      await expectLater(
        service.signEvent(
          grant: grant,
          eventDigest: 'b' * 64,
          sequence: 2,
          paymentEvidence: {
            payment: {'tendered_minor': 200},
          },
        ),
        throwsA(failure('DEVICE_LOCKED')),
      );
      await expectLater(
        service.signRelease(grantId: grantId, finalSequence: 1),
        throwsA(failure('DEVICE_LOCKED')),
      );
      await expectLater(
        service.signEnrollment({
          'challenge_id': membership,
          'nonce': encodeOfflineBytes(List.filled(32, 7)),
          'organization_id': org,
          'branch_id': branch,
          'device_id': identity.deviceId,
          'actor_id': actor,
          'public_key': identity.publicKey,
          'expires_at': now.add(const Duration(minutes: 5)).toIso8601String(),
        }),
        throwsA(failure('DEVICE_LOCKED')),
      );
      final otherInstance = OfflineDeviceSecurity(
        store: secrets,
        namespace: namespace,
      );
      expect(
        await otherInstance.restore(organizationId: org, actorId: actor),
        isNull,
      );
      await expectLater(
        otherInstance.enable(
          organizationId: org,
          actorId: actor,
          explicitConsent: true,
        ),
        throwsStateError,
      );
      expect(secrets.values['$namespace.grant.$grantId'], retainedGrant);
      expect(
        secrets.values['$namespace.checkpoint.$grantId'],
        retainedCheckpoint,
      );
      expect(
        (await service.retainedScopes(actorId: actor)).single.grantId,
        grantId,
      );
      expect(decodeOfflineBytes(proof, length: 64), hasLength(64));

      // Only a successful, explicitly consented new preparation unlocks a new
      // identity; an old grant cannot use that replacement identity.
      secrets.failedWrite = null;
      final replacement = await service.enable(
        organizationId: org,
        actorId: actor,
        explicitConsent: true,
      );
      expect(replacement.deviceId, isNot(identity.deviceId));
      expect(
        (await service.restore(organizationId: org, actorId: actor))?.deviceId,
        replacement.deviceId,
      );
      await expectLater(
        service.authorize(grant: grant, scope: grant.scope),
        throwsA(failure('DEVICE_LOCKED')),
      );
    },
  );

  test('organization keys are distinct and logout locks every key', () async {
    final secrets = FailingSecrets();
    const namespace = 'multi-org';
    const otherOrg = '00000000-0000-4000-8000-000000000011';
    final service = OfflineDeviceSecurity(
      store: secrets,
      namespace: namespace,
      clock: () => now,
    );
    final first = await service.enable(
      organizationId: org,
      actorId: actor,
      explicitConsent: true,
    );
    final second = await service.enable(
      organizationId: otherOrg,
      actorId: actor,
      explicitConsent: true,
    );
    expect(second.deviceId, isNot(first.deviceId));
    expect(second.publicKey, isNot(first.publicKey));
    expect(
      (await service.restore(organizationId: org, actorId: actor))?.deviceId,
      first.deviceId,
    );
    expect(
      (await service.restore(
        organizationId: otherOrg,
        actorId: actor,
      ))?.deviceId,
      second.deviceId,
    );
    final snap = snapshot();
    final grant = await verifier().verify(
      wire: await wire(claims(snap, deviceId: first.deviceId)),
      snapshot: snap,
      scope: scope(deviceId: first.deviceId),
      serverTime: now,
    );
    await service.retainGrant(grant);
    await service.anchor(grant: grant, serverTime: now);
    final release = await service.signRelease(
      grantId: grantId,
      finalSequence: 0,
    );
    expect(
      await Ed25519().verify(
        utf8.encode(
          '$offlineReleaseDomain${strictCanonicalJson({'grant_id': grantId, 'final_sequence': 0})}',
        ),
        signature: Signature(
          decodeOfflineBytes(release, length: 64),
          publicKey: SimplePublicKey(
            decodeOfflineBytes(first.publicKey, length: 32),
            type: KeyPairType.ed25519,
          ),
        ),
      ),
      isTrue,
    );
    final resumed = await service.retainedScopes(actorId: actor);
    expect(resumed.single.grantId, grant.grantId);
    expect(resumed.single.isVerified, isFalse);

    // A failed physical deletion cannot unlock surviving keys after restart.
    secrets.failedDelete = '$namespace.identity.$org.$actor';
    await expectLater(service.lock(), throwsStateError);
    final restarted = OfflineDeviceSecurity(
      store: secrets,
      namespace: namespace,
    );
    expect(
      await restarted.restore(organizationId: org, actorId: actor),
      isNull,
    );
    expect(
      await restarted.restore(organizationId: otherOrg, actorId: actor),
      isNull,
    );
    expect(
      (await restarted.retainedScopes(actorId: actor)).single.grantId,
      grantId,
    );
    expect(
      secrets.values.containsKey('$namespace.checkpoint.$grantId'),
      isTrue,
    );
    secrets.failedDelete = null;
    await restarted.lock();
    expect(
      secrets.values.keys.where(
        (key) => key.startsWith('$namespace.identity.'),
      ),
      isEmpty,
    );
  });

  test('instances serialize shared namespace enrollment and lock', () async {
    final secrets = MemorySecrets();
    const otherOrg = '00000000-0000-4000-8000-000000000011';
    final first = OfflineDeviceSecurity(store: secrets);
    final second = OfflineDeviceSecurity(store: secrets);
    await Future.wait([
      first.enable(organizationId: org, actorId: actor, explicitConsent: true),
      second.enable(
        organizationId: otherOrg,
        actorId: actor,
        explicitConsent: true,
      ),
    ]);
    final index = jsonDecode(
      secrets.values['nexapos.offline.v1.identity_index']!,
    );
    expect(index, {'$org.$actor': true, '$otherOrg.$actor': true});
    final locking = first.lock();
    final restoring = second.restore(organizationId: otherOrg, actorId: actor);
    await locking;
    expect(await restoring, isNull);
    expect(
      secrets.values.keys.where(
        (key) => key.startsWith('nexapos.offline.v1.identity.'),
      ),
      isEmpty,
    );
  });

  test('retained locators reject altered actor or missing grant', () async {
    final secrets = MemorySecrets();
    const namespace = 'locators';
    final service = OfflineDeviceSecurity(
      store: secrets,
      namespace: namespace,
      clock: () => now,
    );
    final identity = await service.enable(
      organizationId: org,
      actorId: actor,
      explicitConsent: true,
    );
    final snap = snapshot();
    final grant = await verifier().verify(
      wire: await wire(claims(snap, deviceId: identity.deviceId)),
      snapshot: snap,
      scope: scope(deviceId: identity.deviceId),
      serverTime: now,
    );
    await service.retainGrant(grant);
    secrets.values['$namespace.grant_index.$membership'] =
        secrets.values['$namespace.grant_index.$actor']!;
    await expectLater(
      service.retainedScopes(actorId: membership),
      throwsA(failure('CORRUPT_SECURE_STATE')),
    );
    secrets.values.remove('$namespace.grant.$grantId');
    await expectLater(
      service.retainedScopes(actorId: actor),
      throwsA(failure('CORRUPT_SECURE_STATE')),
    );
  });

  test(
    'device signatures use immutable proofs and distinct domains; logout locks key',
    () async {
      final secrets = MemorySecrets();
      var wall = now;
      final service = OfflineDeviceSecurity(store: secrets, clock: () => wall);
      final identity = await service.enable(
        organizationId: org,
        actorId: actor,
        explicitConsent: true,
      );
      final snap = snapshot();
      final grant = await verifier().verify(
        wire: await wire(claims(snap, deviceId: identity.deviceId)),
        snapshot: snap,
        scope: scope(deviceId: identity.deviceId),
        serverTime: now,
      );
      await service.retainGrant(grant);
      await service.anchor(grant: grant, serverTime: now);
      final evidence = <String, Object?>{
        payment: {'tendered_minor': 200},
      };
      final digest = 'a' * 64;
      final pendingSignature = service.signEvent(
        grant: grant,
        eventDigest: digest,
        sequence: 1,
        paymentEvidence: evidence,
      );
      (evidence[payment]! as Map<String, Object?>)['tendered_minor'] = 300;
      final signed = await pendingSignature;
      final proof = {
        'event_digest': digest,
        'grant_id': grantId,
        'sequence': 1,
        'payment_evidence': {
          payment: {'tendered_minor': 200},
        },
      };
      final signature = Signature(
        decodeOfflineBytes(signed, length: 64),
        publicKey: SimplePublicKey(
          decodeOfflineBytes(identity.publicKey, length: 32),
          type: KeyPairType.ed25519,
        ),
      );
      expect(
        await Ed25519().verify(
          utf8.encode('$offlineEventDomain${strictCanonicalJson(proof)}'),
          signature: signature,
        ),
        isTrue,
      );
      expect(
        await Ed25519().verify(
          utf8.encode('$offlineGrantDomain${strictCanonicalJson(proof)}'),
          signature: signature,
        ),
        isFalse,
      );
      final unsigned = OfflineGrant.fromWire(grant.toWire());
      expect(
        service.authorize(grant: unsigned, scope: unsigned.scope),
        throwsA(failure('UNVERIFIED_GRANT')),
      );
      wall = wall.add(const Duration(hours: 8));
      expect(
        service.signEvent(
          grant: grant,
          eventDigest: digest,
          sequence: 2,
          paymentEvidence: evidence,
        ),
        throwsA(failure('EXPIRED_GRANT')),
      );
      expect(
        await service.signRelease(grantId: grantId, finalSequence: 1),
        isNotEmpty,
      );
      await service.lock();
      expect(
        service.signRelease(grantId: grantId, finalSequence: 1),
        throwsA(failure('DEVICE_LOCKED')),
      );
      expect(
        await service.restoreGrant(
          organizationId: org,
          actorId: actor,
          branchId: branch,
        ),
        isNotNull,
      );
    },
  );

  test(
    'enrollment signs a frozen challenge with the scoped device key',
    () async {
      final service = OfflineDeviceSecurity(store: MemorySecrets());
      final identity = await service.enable(
        organizationId: org,
        actorId: actor,
        explicitConsent: true,
      );
      final challenge = <String, Object?>{
        'challenge_id': membership,
        'nonce': encodeOfflineBytes(List.filled(32, 7)),
        'organization_id': org,
        'branch_id': branch,
        'device_id': identity.deviceId,
        'actor_id': actor,
        'public_key': identity.publicKey,
        'expires_at': now.add(const Duration(minutes: 5)).toIso8601String(),
      };
      final original = Map<String, Object?>.from(challenge);
      final signing = service.signEnrollment(challenge);
      challenge['nonce'] = encodeOfflineBytes(List.filled(32, 8));
      final signed = await signing;
      expect(
        await Ed25519().verify(
          utf8.encode(
            '$offlineEnrollmentDomain${strictCanonicalJson(original)}',
          ),
          signature: Signature(
            decodeOfflineBytes(signed, length: 64),
            publicKey: SimplePublicKey(
              decodeOfflineBytes(identity.publicKey, length: 32),
              type: KeyPairType.ed25519,
            ),
          ),
        ),
        isTrue,
      );
      await expectLater(
        service.signEnrollment({...original, 'device_id': device}),
        throwsA(failure('WRONG_SCOPE')),
      );
      await expectLater(
        service.signEnrollment({...original, 'nonce': '${original['nonce']}='}),
        throwsA(failure('INVALID_PROTOCOL')),
      );
    },
  );

  test(
    'released grant denies new sales and frozen grant cannot be changed',
    () async {
      final secrets = MemorySecrets();
      final service = OfflineDeviceSecurity(store: secrets, clock: () => now);
      final identity = await service.enable(
        organizationId: org,
        actorId: actor,
        explicitConsent: true,
      );
      final snap = snapshot();
      final grant = await verifier().verify(
        wire: await wire(claims(snap, deviceId: identity.deviceId)),
        snapshot: snap,
        scope: scope(deviceId: identity.deviceId),
        serverTime: now,
      );
      await service.retainGrant(grant);
      await service.anchor(grant: grant, serverTime: now);
      await service.markReleased(grantId);
      expect(await service.isReleased(grantId), isTrue);
      expect(
        service.authorize(grant: grant, scope: grant.scope),
        throwsA(failure('GRANT_RELEASED')),
      );
      final body = {
        ...claims(snap, deviceId: identity.deviceId),
        'max_events': 10,
      };
      final different = await verifier().verify(
        wire: await wire(body),
        snapshot: snap,
        scope: grant.scope,
        serverTime: now,
      );
      expect(service.retainGrant(different), throwsA(failure('GRANT_CHANGED')));
    },
  );
}
