import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:cryptography/cryptography.dart';

import '../sync/sync_event.dart';

const offlineAudience = 'nexapos.offline.v1';
const offlineGrantDomain = 'NexaPOS:grant:v1\n';
const offlineEnrollmentDomain = 'NexaPOS:enroll:v1\n';
const offlineEventDomain = 'NexaPOS:event:v1\n';
const offlineReleaseDomain = 'NexaPOS:release:v1\n';
// Tender fragments are review evidence, never an ingestible sale event.
const offlineTenderDomain = 'NexaPOS:tender:v1\n';
const maximumOfflineEvents = 1000;
const maximumOfflineTotalMinor = 100000000;

class OfflineSecurityException implements Exception {
  const OfflineSecurityException(this.code);
  final String code;
  @override
  String toString() => 'Offline authorization could not be verified ($code).';
}

Never _invalid([String code = 'INVALID_PROTOCOL']) =>
    throw OfflineSecurityException(code);

bool _validUnicode(String text) {
  for (var i = 0; i < text.length; i++) {
    final unit = text.codeUnitAt(i);
    if (unit >= 0xd800 && unit <= 0xdbff) {
      if (++i == text.length) return false;
      final next = text.codeUnitAt(i);
      if (next < 0xdc00 || next > 0xdfff) return false;
    } else if (unit >= 0xdc00 && unit <= 0xdfff) {
      return false;
    }
  }
  return true;
}

/// The existing event canonical encoding, with strict network-boundary checks.
/// In particular, malformed UTF-16 must never be silently replaced by UTF-8.
String strictCanonicalJson(Object? value) {
  void validate(Object? item, int depth) {
    if (depth > 32) _invalid();
    if (item == null || item is bool) return;
    if (item is String) {
      if (!_validUnicode(item)) _invalid();
      return;
    }
    if (item is int) {
      if (item.abs() > 9007199254740991) _invalid();
      return;
    }
    if (item is List) {
      for (final child in item) {
        validate(child, depth + 1);
      }
      return;
    }
    if (item is Map<String, Object?>) {
      for (final entry in item.entries) {
        if (!_validUnicode(entry.key)) _invalid();
        validate(entry.value, depth + 1);
      }
      return;
    }
    _invalid();
  }

  validate(value, 0);
  return canonicalJson(value);
}

String canonicalHash(Object? value) =>
    sha256.convert(utf8.encode(strictCanonicalJson(value))).toString();

Object? immutableOfflineValue(Object? value) {
  strictCanonicalJson(value);
  if (value is Map<String, Object?>) {
    return Map<String, Object?>.unmodifiable(
      value.map((key, child) => MapEntry(key, immutableOfflineValue(child))),
    );
  }
  if (value is List) {
    return List<Object?>.unmodifiable(value.map(immutableOfflineValue));
  }
  return value;
}

String encodeOfflineBytes(List<int> bytes) =>
    base64Url.encode(bytes).replaceAll('=', '');

List<int> decodeOfflineBytes(String encoded, {required int length}) {
  if (!RegExp(r'^[A-Za-z0-9_-]+$').hasMatch(encoded)) _invalid();
  try {
    final bytes = base64Url.decode(base64Url.normalize(encoded));
    if (bytes.length != length || encodeOfflineBytes(bytes) != encoded) {
      _invalid();
    }
    return List<int>.unmodifiable(bytes);
  } on FormatException {
    _invalid();
  }
}

String offlineUuid(Object? value) {
  if (value is! String ||
      !RegExp(
        r'^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$',
      ).hasMatch(value)) {
    _invalid();
  }
  return value;
}

int offlineInteger(Object? value, {required int min, required int max}) {
  if (value is! int || value < min || value > max) _invalid();
  return value;
}

DateTime offlineUtc(Object? value) {
  if (value is! String ||
      !RegExp(
        r'^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}(?:\.\d{1,6})?(?:Z|\+00:00)$',
      ).hasMatch(value)) {
    _invalid();
  }
  final parsed = DateTime.tryParse(value);
  if (parsed == null || !parsed.isUtc) _invalid();
  // DateTime.parse normalizes impossible dates. Reject that normalization.
  final normalized = parsed.toIso8601String();
  if (normalized.substring(0, 19) != value.substring(0, 19)) _invalid();
  return parsed;
}

class OfflineScope {
  const OfflineScope({
    required this.organizationId,
    required this.branchId,
    required this.actorId,
    required this.membershipId,
    required this.deviceId,
    required this.shiftId,
    required this.role,
  });
  final String organizationId;
  final String branchId;
  final String actorId;
  final String membershipId;
  final String deviceId;
  final String shiftId;
  final String role;

  bool matches(OfflineScope other) =>
      organizationId == other.organizationId &&
      branchId == other.branchId &&
      actorId == other.actorId &&
      membershipId == other.membershipId &&
      deviceId == other.deviceId &&
      shiftId == other.shiftId &&
      role == other.role;
}

class DeviceIdentity {
  const DeviceIdentity({
    required this.deviceId,
    required this.organizationId,
    required this.actorId,
    required this.publicKey,
  });
  final String deviceId;
  final String organizationId;
  final String actorId;
  final String publicKey;
  Map<String, Object?> toJson() => {
    'device_id': deviceId,
    'organization_id': organizationId,
    'actor_id': actorId,
    'public_key': publicKey,
  };
}

/// Parsing alone conveys no authority. Use [OfflineGrantVerifier.verify].
class OfflineGrant {
  OfflineGrant._(this.claims, this.signature, {this.isVerified = false});

  factory OfflineGrant.fromWire(Map<String, Object?> wire) {
    if (wire.length != 2 ||
        !wire.containsKey('claims') ||
        wire['signature'] is! String ||
        wire['claims'] is! Map<String, Object?>) {
      _invalid();
    }
    final claims = wire['claims']! as Map<String, Object?>;
    const keys = {
      'schema_version',
      'issuer',
      'audience',
      'key_id',
      'grant_id',
      'organization_id',
      'branch_id',
      'device_id',
      'actor_id',
      'membership_id',
      'role',
      'business_name',
      'allowed_actions',
      'issued_at',
      'expires_at',
      'shift_id',
      'currency',
      'tax_bps',
      'settings_revision',
      'snapshot_digest',
      'max_events',
      'max_total_minor',
    };
    if (claims.length != keys.length ||
        !claims.keys.every(keys.contains) ||
        claims['schema_version'] is! int ||
        claims['schema_version'] != 1 ||
        claims['audience'] != offlineAudience ||
        claims['issuer'] is! String ||
        claims['key_id'] is! String ||
        !RegExp(
          r'^[A-Za-z0-9_.-]{1,100}$',
        ).hasMatch(claims['key_id']! as String)) {
      _invalid();
    }
    for (final key in [
      'grant_id',
      'organization_id',
      'branch_id',
      'device_id',
      'actor_id',
      'membership_id',
      'shift_id',
    ]) {
      offlineUuid(claims[key]);
    }
    if (!{'owner', 'admin', 'manager', 'cashier'}.contains(claims['role']) ||
        claims['business_name'] is! String ||
        (claims['business_name']! as String).trim().isEmpty ||
        (claims['business_name']! as String).length > 200 ||
        claims['allowed_actions'] is! List ||
        (claims['allowed_actions']! as List).length != 1 ||
        (claims['allowed_actions']! as List).single != 'sale.created' ||
        !{
          'PHP',
          'USD',
          'EUR',
          'GBP',
          'AUD',
          'CAD',
          'SGD',
        }.contains(claims['currency']) ||
        claims['snapshot_digest'] is! String ||
        !RegExp(
          r'^[0-9a-f]{64}$',
        ).hasMatch(claims['snapshot_digest']! as String)) {
      _invalid();
    }
    offlineInteger(claims['tax_bps'], min: 0, max: 10000);
    offlineInteger(claims['settings_revision'], min: 1, max: 9007199254740991);
    offlineInteger(claims['max_events'], min: 1, max: maximumOfflineEvents);
    offlineInteger(
      claims['max_total_minor'],
      min: 1,
      max: maximumOfflineTotalMinor,
    );
    final issued = offlineUtc(claims['issued_at']);
    final expiry = offlineUtc(claims['expires_at']);
    if (!expiry.isAfter(issued) ||
        expiry.difference(issued) > const Duration(hours: 8)) {
      _invalid();
    }
    final signature = wire['signature']! as String;
    decodeOfflineBytes(signature, length: 64);
    return OfflineGrant._(
      immutableOfflineValue(claims)! as Map<String, Object?>,
      signature,
    );
  }

  final Map<String, Object?> claims;
  final String signature;
  final bool isVerified;
  String get grantId => claims['grant_id']! as String;
  String get snapshotDigest => claims['snapshot_digest']! as String;
  DateTime get issuedAt => offlineUtc(claims['issued_at']);
  DateTime get expiresAt => offlineUtc(claims['expires_at']);
  int get maxEvents => claims['max_events']! as int;
  int get maxTotalMinor => claims['max_total_minor']! as int;
  String get currency => claims['currency']! as String;
  int get taxBps => claims['tax_bps']! as int;
  int get settingsRevision => claims['settings_revision']! as int;
  String get businessName => claims['business_name']! as String;
  OfflineScope get scope => OfflineScope(
    organizationId: claims['organization_id']! as String,
    branchId: claims['branch_id']! as String,
    actorId: claims['actor_id']! as String,
    membershipId: claims['membership_id']! as String,
    deviceId: claims['device_id']! as String,
    shiftId: claims['shift_id']! as String,
    role: claims['role']! as String,
  );
  Map<String, Object?> toWire() => {'claims': claims, 'signature': signature};
}

class OfflineGrantVerifier {
  OfflineGrantVerifier({
    required this.issuer,
    required Map<String, String> trustedKeys,
  }) : trustedKeys = Map.unmodifiable(trustedKeys);
  final String issuer;
  final Map<String, String> trustedKeys;

  Future<OfflineGrant> verify({
    required Map<String, Object?> wire,
    required Map<String, Object?> snapshot,
    required OfflineScope scope,
    required DateTime serverTime,
    bool allowExpired = false,
  }) async {
    final grant = OfflineGrant.fromWire(wire);
    final key = trustedKeys[grant.claims['key_id']];
    if (key == null || trustedKeys.isEmpty) _invalid('UNTRUSTED_KEY');
    final issuerUri = Uri.tryParse(issuer);
    if (issuerUri == null ||
        issuerUri.scheme != 'https' ||
        issuerUri.userInfo.isNotEmpty ||
        issuerUri.host.isEmpty ||
        issuerUri.hasQuery ||
        issuerUri.hasFragment ||
        grant.claims['issuer'] != issuer) {
      _invalid('WRONG_ISSUER');
    }
    if (!scope.matches(grant.scope)) _invalid('WRONG_SCOPE');
    if (!serverTime.isUtc ||
        serverTime.isBefore(grant.issuedAt) ||
        (!allowExpired && !serverTime.isBefore(grant.expiresAt))) {
      _invalid('EXPIRED_GRANT');
    }
    final valid = await Ed25519().verify(
      utf8.encode('$offlineGrantDomain${strictCanonicalJson(grant.claims)}'),
      signature: Signature(
        decodeOfflineBytes(grant.signature, length: 64),
        publicKey: SimplePublicKey(
          decodeOfflineBytes(key, length: 32),
          type: KeyPairType.ed25519,
        ),
      ),
    );
    if (!valid) _invalid('BAD_SIGNATURE');
    if (canonicalHash(snapshot) != grant.snapshotDigest) {
      _invalid('BAD_SNAPSHOT');
    }
    _verifySnapshot(snapshot, grant);
    return OfflineGrant._(grant.claims, grant.signature, isVerified: true);
  }

  void _verifySnapshot(Map<String, Object?> snapshot, OfflineGrant grant) {
    const keys = {
      'context',
      'shift',
      'products',
      'categories',
      'stock',
      'cursor',
    };
    if (snapshot.length != keys.length ||
        !snapshot.keys.every(keys.contains) ||
        snapshot['context'] is! Map<String, Object?> ||
        snapshot['shift'] is! Map<String, Object?> ||
        snapshot['products'] is! List ||
        snapshot['categories'] is! List ||
        snapshot['stock'] is! List ||
        (snapshot['products']! as List).length > 1000) {
      _invalid('INCOMPLETE_SNAPSHOT');
    }
    void noRestrictedData(Object? value) {
      if (value is Map<String, Object?>) {
        for (final entry in value.entries) {
          if ({
            'cost',
            'cost_minor',
            'unit_cost_minor',
            'password',
            'private_key',
            'service_role',
            'customer_contacts',
            'customer_email',
            'customer_phone',
          }.contains(entry.key)) {
            _invalid('RESTRICTED_SNAPSHOT');
          }
          noRestrictedData(entry.value);
        }
      } else if (value is List) {
        value.forEach(noRestrictedData);
      }
    }

    noRestrictedData(snapshot);
    final context = snapshot['context']! as Map<String, Object?>;
    final shift = snapshot['shift']! as Map<String, Object?>;
    if (context['organization_id'] != grant.scope.organizationId ||
        context['branch_id'] != grant.scope.branchId ||
        context['currency'] != grant.currency ||
        context['tax_bps'] != grant.taxBps ||
        context['settings_revision'] != grant.settingsRevision ||
        context['business_name'] != grant.businessName ||
        shift['id'] != grant.scope.shiftId ||
        shift['actor_user_id'] != grant.scope.actorId ||
        shift['organization_id'] != grant.scope.organizationId ||
        shift['branch_id'] != grant.scope.branchId ||
        shift['currency'] != grant.currency ||
        (shift['closed_at'] != null) ||
        (shift['closure'] != null) ||
        (shift['status'] != null && shift['status'] != 'open')) {
      _invalid('WRONG_SNAPSHOT_SCOPE');
    }
    offlineInteger(snapshot['cursor'], min: 0, max: 9007199254740991);
    final categoryIds = <String>{};
    for (final category in snapshot['categories']! as List) {
      if (category is! Map<String, Object?> ||
          !categoryIds.add(offlineUuid(category['id']))) {
        _invalid('INCOMPLETE_SNAPSHOT');
      }
      if (category['organization_id'] != grant.scope.organizationId ||
          category['name'] is! String ||
          (category['name']! as String).trim().isEmpty ||
          category['active'] != true) {
        _invalid('WRONG_SNAPSHOT_SCOPE');
      }
      offlineInteger(category['revision'], min: 1, max: 9007199254740991);
    }
    final ids = <String>{};
    for (final product in snapshot['products']! as List) {
      if (product is! Map<String, Object?> ||
          !ids.add(offlineUuid(product['id']))) {
        _invalid('INCOMPLETE_SNAPSHOT');
      }
      if (product['organization_id'] != grant.scope.organizationId ||
          product['currency'] != grant.currency ||
          product['name'] is! String ||
          (product['name']! as String).trim().isEmpty ||
          product['sku'] is! String ||
          (product['sku']! as String).trim().isEmpty ||
          (product.containsKey('active') && product['active'] != true)) {
        _invalid('WRONG_SNAPSHOT_SCOPE');
      }
      offlineInteger(product['price_minor'], min: 0, max: 9007199254740991);
      offlineInteger(product['revision'], min: 1, max: 9007199254740991);
    }
    final stockIds = <String>{};
    for (final stock in snapshot['stock']! as List) {
      if (stock is! Map<String, Object?> ||
          !stockIds.add(offlineUuid(stock['product_id'])) ||
          !ids.contains(stock['product_id'])) {
        _invalid('INCOMPLETE_SNAPSHOT');
      }
      offlineInteger(
        stock['quantity'],
        min: -9007199254740991,
        max: 9007199254740991,
      );
      offlineInteger(stock['revision'], min: 0, max: 9007199254740991);
    }
    if (stockIds.length != ids.length) _invalid('INCOMPLETE_SNAPSHOT');
  }
}
