import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:nexapos/app/config/backend_config.dart';
import 'package:nexapos/core/security/app_role.dart';

String syntheticKey(String role) =>
    '${base64Url.encode(utf8.encode('{}'))}.'
    '${base64Url.encode(utf8.encode(jsonEncode({'role': role})))}.fixture';

void main() {
  test('missing configuration cannot initialize authentication', () {
    const config = BackendConfig(url: '', clientKey: '');
    expect(config.isConfigured, isFalse);
    expect(config.validationError, contains('Not Yet Connected'));
  });

  test(
    'private keys and unsafe URLs are rejected before Supabase initialization',
    () {
      for (final key in [
        'sb_secret_fixture',
        syntheticKey('service_role'),
        syntheticKey('owner'),
      ]) {
        expect(
          BackendConfig(
            url: 'https://example.supabase.co',
            clientKey: key,
          ).validationError,
          isNotNull,
        );
      }
      for (final url in [
        'http://example.supabase.co',
        'https://user:password@example.supabase.co',
        'https://example.supabase.co?token=fixture',
      ]) {
        expect(
          BackendConfig(
            url: url,
            clientKey: syntheticKey('anon'),
          ).validationError,
          isNotNull,
        );
      }
      expect(
        BackendConfig(
          url: 'https://example.supabase.co',
          clientKey: syntheticKey('anon'),
        ).validationError,
        isNull,
      );
    },
  );

  test('unknown role never defaults to an authorized role', () {
    expect(() => AppRole.fromDatabase('super_admin'), throwsFormatException);
    expect(AppRole.admin.allows(AppPermission.assignAdmin), isFalse);
    expect(AppRole.cashier.allows(AppPermission.approveRefund), isFalse);
    expect(AppRole.inventoryStaff.allows(AppPermission.usePos), isFalse);
    expect(AppRole.manager.allows(AppPermission.approveRefund), isTrue);
  });
}
