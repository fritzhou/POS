import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:nexapos/core/auth/auth_models.dart';
import 'package:nexapos/core/auth/secure_session_storage.dart';
import 'package:nexapos/core/auth/supabase_auth_repository.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class Store implements SecretStore {
  bool failDeletion = false;
  final values = <String, String>{};
  @override
  Future<String?> read(String key) async => values[key];
  @override
  Future<void> write(String key, String value) async => values[key] = value;
  @override
  Future<void> delete(String key) async {
    if (failDeletion) throw StateError('vault unavailable');
    values.remove(key);
  }
}

Future<void> restore(SupabaseClient client) async {
  String encode(Object value) =>
      base64Url.encode(utf8.encode(jsonEncode(value))).replaceAll('=', '');
  const actor = '10000000-0000-4000-8000-000000000001';
  await client.auth.recoverSession(
    jsonEncode({
      'access_token':
          '${encode({'alg': 'HS256'})}.${encode({'sub': actor, 'exp': 4102444800})}.test',
      'refresh_token': 'test-only-refresh',
      'token_type': 'bearer',
      'user': {
        'id': actor,
        'aud': 'authenticated',
        'email': 'actor@example.test',
        'email_confirmed_at': '2026-10-10T00:00:00Z',
        'created_at': '2026-10-10T00:00:00Z',
        'app_metadata': {},
        'user_metadata': {},
      },
    }),
  );
}

void main() {
  for (final sample in [
    (
      name: 'socket transport loss',
      error: const SocketException('raw sensitive transport detail'),
      code: null,
      kind: AuthFailureKind.unavailable,
    ),
    (
      name: 'server permission denial',
      error: null,
      code: '42501',
      kind: AuthFailureKind.authorization,
    ),
    (
      name: 'invalid JWT denial',
      error: null,
      code: 'PGRST301',
      kind: AuthFailureKind.authorization,
    ),
    (
      name: 'invalid database response',
      error: null,
      code: '22P02',
      kind: AuthFailureKind.other,
    ),
  ]) {
    test('actual membership adapter classifies ${sample.name}', () async {
      final client = SupabaseClient(
        'https://project.example.test',
        'public-test-key',
        authOptions: const AuthClientOptions(autoRefreshToken: false),
        httpClient: MockClient((request) async {
          expect(request.url.path, '/rest/v1/organization_memberships');
          if (sample.error != null) throw sample.error!;
          return http.Response(
            jsonEncode({
              'message': 'raw sensitive detail',
              'code': sample.code,
            }),
            403,
            headers: {'content-type': 'application/json'},
            request: request,
          );
        }),
      );
      final storage = SecureSessionStorage(store: Store());
      await storage.initialize();
      final repository = SupabaseAuthRepository(
        client: client,
        sessionStorage: storage,
      );
      await restore(client);
      addTearDown(() async {
        await repository.dispose();
        await client.dispose();
      });
      await expectLater(
        repository.loadMemberships(),
        throwsA(
          isA<AuthFailure>()
              .having((failure) => failure.kind, 'failure kind', sample.kind)
              .having(
                (failure) => failure.message,
                'sanitized message',
                isNot(contains('sensitive')),
              ),
        ),
      );
      expect(repository.currentIdentity?.emailVerified, isTrue);
    });
  }

  test(
    'vault cleanup failure cannot keep live Auth session signed in',
    () async {
      final client = SupabaseClient(
        'https://project.example.test',
        'public-test-key',
        authOptions: const AuthClientOptions(autoRefreshToken: false),
        httpClient: MockClient(
          (request) async => http.Response('', 204, request: request),
        ),
      );
      final store = Store();
      final storage = SecureSessionStorage(store: store);
      await storage.initialize();
      final repository = SupabaseAuthRepository(
        client: client,
        sessionStorage: storage,
      );
      await restore(client);
      addTearDown(() async {
        await repository.dispose();
        await client.dispose();
      });
      store.failDeletion = true;
      await expectLater(repository.signOut(), throwsA(isA<AuthFailure>()));
      expect(repository.currentIdentity, isNull);
      expect(client.auth.currentSession, isNull);
      expect(await storage.hasAccessToken(), isFalse);
    },
  );
}
