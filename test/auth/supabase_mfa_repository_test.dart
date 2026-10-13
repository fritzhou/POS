import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:nexapos/features/authentication/data/supabase_mfa_repository.dart';
import 'package:nexapos/features/authentication/domain/mfa_repository.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

// Synthetic sessions and an injected HTTP boundary exercise the real installed
// GoTrue MFA APIs. They are not live Supabase account/provider evidence.
String _token(String actor, String aal) {
  String encode(Object value) =>
      base64Url.encode(utf8.encode(jsonEncode(value))).replaceAll('=', '');
  return '${encode({'alg': 'HS256', 'typ': 'JWT'})}.${encode({'sub': actor, 'aal': aal, 'iat': DateTime.now().millisecondsSinceEpoch ~/ 1000, 'exp': DateTime.now().millisecondsSinceEpoch ~/ 1000 + 3600})}.test-signature';
}

Map<String, Object?> _factor({bool verified = true}) => {
  'id': 'factor-test',
  'friendly_name': 'Test authenticator',
  'factor_type': 'totp',
  'status': verified ? 'verified' : 'unverified',
  'created_at': '2026-10-11T10:00:00Z',
  'updated_at': '2026-10-11T10:00:00Z',
};

Map<String, Object?> _user(String actor, {bool verified = true}) => {
  'id': actor,
  'aud': 'authenticated',
  'role': 'authenticated',
  'email': '$actor@example.test',
  'email_confirmed_at': '2026-10-11T10:00:00Z',
  'app_metadata': <String, Object?>{},
  'user_metadata': <String, Object?>{},
  'created_at': '2026-10-11T10:00:00Z',
  'factors': [_factor(verified: verified)],
};

Session _session(String actor, String aal, {bool verified = true}) =>
    Session.fromJson({
      'access_token': _token(actor, aal),
      'refresh_token': 'test-refresh-$actor',
      'token_type': 'bearer',
      'expires_in': 3600,
      'user': _user(actor, verified: verified),
    })!;

http.Response _json(Object value, {int status = 200}) => http.Response(
  jsonEncode(value),
  status,
  headers: {'content-type': 'application/json'},
);

void main() {
  late SupabaseClient client;
  late SupabaseMfaRepository repository;
  late List<http.Request> requests;
  late Future<http.Response> Function(http.Request) handler;
  var recovery = false;
  var verified = true;
  final now = DateTime.utc(2026, 10, 11, 12);

  setUp(() async {
    requests = [];
    recovery = false;
    verified = true;
    handler = (request) async {
      requests.add(request);
      if (request.url.path.endsWith('/user')) {
        return _json(_user('actor-a', verified: verified));
      }
      if (request.url.path.endsWith('/challenge')) {
        return _json({
          'id': 'challenge-test',
          'expires_at':
              now.add(const Duration(minutes: 5)).millisecondsSinceEpoch ~/
              1000,
        });
      }
      if (request.url.path.endsWith('/verify')) {
        return _json({
          'access_token': _token('actor-a', 'aal2'),
          'refresh_token': 'test-upgraded-refresh',
          'token_type': 'bearer',
          'expires_in': 3600,
          'user': _user('actor-a'),
        });
      }
      if (request.method == 'DELETE') return _json({'id': 'factor-test'});
      if (request.url.path.endsWith('/factors')) {
        return _json({
          'id': 'factor-test',
          'type': 'totp',
          'totp': {
            'secret': 'JBSWY3DPEHPK3PXP',
            'qr_code': '<svg/>',
            'uri': 'otpauth://totp/test',
          },
        });
      }
      return _json({});
    };
    client = SupabaseClient(
      'https://project.example.test',
      'public-test-key',
      authOptions: const AuthClientOptions(autoRefreshToken: false),
      httpClient: MockClient((request) => handler(request)),
    );
    await client.auth.setInitialSession(
      jsonEncode(_session('actor-a', 'aal1').toJson()),
    );
    repository = SupabaseMfaRepository(
      client: client,
      authUrl: 'https://project.example.test/auth/v1',
      publicApiKey: 'public-test-key',
      isRecoverySession: () => recovery,
      clock: () => now,
      isolatedClientFactory: () => GoTrueClient(
        url: 'https://project.example.test/auth/v1',
        headers: {'apikey': 'public-test-key'},
        autoRefreshToken: false,
        httpClient: MockClient((request) => handler(request)),
      ),
    );
    // Let the initial session replay reach the guard before asynchronous tests.
    await Future<void>.delayed(Duration.zero);
  });

  tearDown(() async {
    await repository.dispose();
    await client.dispose();
  });

  test('reads live factors without rotating shared refresh token', () async {
    final status = await repository.status();
    expect(status.actorId, 'actor-a');
    expect(status.currentLevel, MfaAssuranceLevel.aal1);
    expect(status.nextLevel, MfaAssuranceLevel.aal2);
    expect(status.verifiedTotpFactors.single.name, 'Test authenticator');
    expect(requests.single.url.path, '/auth/v1/user');
    expect(client.auth.currentSession?.refreshToken, 'test-refresh-actor-a');
    expect(requests.single.headers['authorization'], startsWith('Bearer '));
  });

  test(
    'enrolls TOTP with live secret and redacted string representation',
    () async {
      final result = await repository.enrollTotp(name: '  Phone  ');
      expect(result.secret, 'JBSWY3DPEHPK3PXP');
      expect(result.toString(), 'MfaEnrollment');
      expect(jsonDecode(requests.single.body), {
        'friendly_name': 'Phone',
        'factor_type': 'totp',
        'issuer': 'NexaPOS',
      });
    },
  );

  test(
    'only genuine AAL2 verify installs new shared session and emits event',
    () async {
      final events = <AuthChangeEvent>[];
      final subscription = client.auth.onAuthStateChange.listen(
        (state) => events.add(state.event),
      );
      final challenge = await repository.challenge('factor-test');
      final result = await repository.verify(challenge, '123456');
      await Future<void>.delayed(Duration.zero);
      expect(result.currentLevel, MfaAssuranceLevel.aal2);
      expect(
        client.auth.mfa.getAuthenticatorAssuranceLevel().currentLevel,
        AuthenticatorAssuranceLevels.aal2,
      );
      expect(client.auth.currentSession?.refreshToken, 'test-upgraded-refresh');
      expect(events, contains(AuthChangeEvent.initialSession));
      final verifyRequest = requests.last;
      expect(jsonDecode(verifyRequest.body), {
        'challenge_id': 'challenge-test',
        'code': '123456',
      });
      await subscription.cancel();
    },
  );

  test('malformed OTP and expired challenge fail before transport', () async {
    for (final code in ['12345', '1234567', '12345a', ' 123456']) {
      await expectLater(
        Future.sync(
          () => repository.verify(
            MfaChallenge(
              factorId: 'factor-test',
              id: 'challenge-test',
              expiresAt: now.add(const Duration(minutes: 1)),
            ),
            code,
          ),
        ),
        throwsA(isA<MfaFailure>()),
      );
    }
    await expectLater(
      Future.sync(
        () => repository.verify(
          MfaChallenge(
            factorId: 'factor-test',
            id: 'challenge-test',
            expiresAt: now,
          ),
          '123456',
        ),
      ),
      throwsA(
        isA<MfaFailure>().having((e) => e.kind, 'kind', MfaFailureKind.expired),
      ),
    );
    expect(requests, isEmpty);
  });

  test('server expired challenge is sanitized and cannot authorize', () async {
    final base = handler;
    handler = (request) async {
      if (request.url.path.endsWith('/verify')) {
        return _json({
          'error_code': 'mfa_challenge_expired',
          'message': 'raw secret server detail',
        }, status: 400);
      }
      return base(request);
    };
    final challenge = await repository.challenge('factor-test');
    await expectLater(
      repository.verify(challenge, '123456'),
      throwsA(
        isA<MfaFailure>()
            .having((e) => e.kind, 'kind', MfaFailureKind.expired)
            .having((e) => e.message, 'message', isNot(contains('raw secret'))),
      ),
    );
    expect(
      client.auth.mfa.getAuthenticatorAssuranceLevel().currentLevel,
      AuthenticatorAssuranceLevels.aal1,
    );
  });

  test('AAL1 response cannot masquerade as completed verification', () async {
    final base = handler;
    handler = (request) async {
      if (request.url.path.endsWith('/verify')) {
        return _json({
          'access_token': _token('actor-a', 'aal1'),
          'refresh_token': 'test-unverified-refresh',
          'token_type': 'bearer',
          'expires_in': 3600,
          'user': _user('actor-a'),
        });
      }
      return base(request);
    };
    final challenge = await repository.challenge('factor-test');
    await expectLater(
      repository.verify(challenge, '123456'),
      throwsA(isA<MfaFailure>()),
    );
    expect(client.auth.currentSession?.refreshToken, 'test-refresh-actor-a');
  });

  test('delayed verification cannot restore signed-out session', () async {
    final pending = Completer<http.Response>();
    final dispatched = Completer<void>();
    final base = handler;
    handler = (request) async {
      if (request.url.path.endsWith('/verify')) {
        dispatched.complete();
        return pending.future;
      }
      return base(request);
    };
    final challenge = await repository.challenge('factor-test');
    final result = repository.verify(challenge, '123456');
    final assertion = expectLater(
      result,
      throwsA(
        isA<MfaFailure>().having(
          (e) => e.kind,
          'kind',
          MfaFailureKind.authorization,
        ),
      ),
    );
    await dispatched.future;
    await client.auth.signOut(scope: SignOutScope.local);
    await Future<void>.delayed(Duration.zero);
    pending.complete(
      _json({
        'access_token': _token('actor-a', 'aal2'),
        'refresh_token': 'test-upgraded-refresh',
        'token_type': 'bearer',
        'expires_in': 3600,
        'user': _user('actor-a'),
      }),
    );
    await assertion;
    expect(client.auth.currentSession, isNull);
  });

  test('delayed verification cannot overwrite switched actor', () async {
    final pending = Completer<http.Response>();
    final dispatched = Completer<void>();
    final base = handler;
    handler = (request) async {
      if (request.url.path.endsWith('/verify')) {
        dispatched.complete();
        return pending.future;
      }
      return base(request);
    };
    final challenge = await repository.challenge('factor-test');
    final assertion = expectLater(
      repository.verify(challenge, '123456'),
      throwsA(isA<MfaFailure>()),
    );
    await dispatched.future;
    await client.auth.setInitialSession(
      jsonEncode(_session('actor-b', 'aal1').toJson()),
    );
    await Future<void>.delayed(Duration.zero);
    pending.complete(
      _json({
        'access_token': _token('actor-a', 'aal2'),
        'refresh_token': 'test-upgraded-refresh',
        'token_type': 'bearer',
        'expires_in': 3600,
        'user': _user('actor-a'),
      }),
    );
    await assertion;
    expect(client.auth.currentSession?.user.id, 'actor-b');
    expect(client.auth.currentSession?.refreshToken, 'test-refresh-actor-b');
  });

  test(
    'recovery and disposed repository fail closed before transport',
    () async {
      recovery = true;
      await expectLater(repository.status(), throwsA(isA<MfaFailure>()));
      recovery = false;
      await repository.dispose();
      await expectLater(repository.status(), throwsA(isA<MfaFailure>()));
      expect(requests, isEmpty);
    },
  );

  test('verified removal requires current AAL2', () async {
    await expectLater(
      repository.unenroll('factor-test'),
      throwsA(
        isA<MfaFailure>().having(
          (e) => e.kind,
          'kind',
          MfaFailureKind.authorization,
        ),
      ),
    );
    expect(requests.where((request) => request.method == 'DELETE'), isEmpty);
    await client.auth.setInitialSession(
      jsonEncode(_session('actor-a', 'aal2').toJson()),
    );
    await repository.unenroll('factor-test');
    expect(requests.last.method, 'DELETE');
    expect(requests.last.url.path, '/auth/v1/factors/factor-test');
  });

  test('cancel only removes unverified enrollment', () async {
    await expectLater(
      repository.cancelEnrollment('factor-test'),
      throwsA(isA<MfaFailure>()),
    );
    expect(requests.where((request) => request.method == 'DELETE'), isEmpty);
    verified = false;
    await repository.cancelEnrollment('factor-test');
    expect(requests.last.method, 'DELETE');
  });

  test('unknown factor never dispatches verification or challenge', () async {
    await expectLater(
      repository.challenge('missing'),
      throwsA(isA<MfaFailure>()),
    );
    expect(requests.single.url.path, '/auth/v1/user');
  });

  test(
    'transport errors expose neutral message without raw backend payload',
    () async {
      handler = (_) async =>
          _json({'message': 'private backend token diagnostic'}, status: 503);
      await expectLater(
        repository.status(),
        throwsA(
          isA<MfaFailure>().having(
            (e) => e.message,
            'message',
            isNot(contains('private backend')),
          ),
        ),
      );
    },
  );
}
