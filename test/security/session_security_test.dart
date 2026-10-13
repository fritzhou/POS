import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:nexapos/core/auth/auth_models.dart';
import 'package:nexapos/core/auth/auth_repository.dart';
import 'package:nexapos/core/auth/secure_session_storage.dart';
import 'package:nexapos/core/security/access_lock.dart';
import 'package:nexapos/core/security/session_lock_guard.dart';
import 'package:nexapos/core/security/session_security_repository.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class _Auth extends NotConfiguredAuthRepository {
  AuthIdentity? identity = const AuthIdentity(
    userId: 'actor-a',
    email: 'a@example.test',
    emailVerified: true,
  );
  bool recovery = false;
  @override
  AuthIdentity? get currentIdentity => identity;
  @override
  bool get hasVerifiedRecoverySession => recovery;
}

class _Store implements SecretStore {
  final values = <String, String>{};
  @override
  Future<String?> read(String key) async => values[key];
  @override
  Future<void> write(String key, String value) async => values[key] = value;
  @override
  Future<void> delete(String key) async => values.remove(key);
}

class _ActivityClock extends Fake implements Stopwatch {
  Duration age = Duration.zero;
  @override
  Duration get elapsed => age;
  @override
  void reset() => age = Duration.zero;
  @override
  void start() {}
}

Map<String, dynamic> _session(String actor) => {
  'access_token': 'test-access',
  'refresh_token': 'test-refresh',
  'token_type': 'bearer',
  'expires_in': 3600,
  'user': {
    'id': actor,
    'aud': 'authenticated',
    'role': 'authenticated',
    'email': 'a@example.test',
    'email_confirmed_at': '2026-10-11T00:00:00Z',
    'created_at': '2026-10-11T00:00:00Z',
    'app_metadata': <String, dynamic>{},
    'user_metadata': <String, dynamic>{},
  },
};

void main() {
  testWidgets(
    'shorter remote policy uses last activity instead of renewing idle time',
    (tester) async {
      final access = AccessLock();
      final clock = _ActivityClock();
      await tester.pumpWidget(
        MaterialApp(
          home: SessionLockGuard(
            access: access,
            actorId: 'actor-a',
            activityClock: clock,
            onVerifyPassword: null,
            onSignOut: () {},
            child: const Scaffold(body: Text('business')),
          ),
        ),
      );
      clock.age = const Duration(minutes: 2);
      access.setIdleMinutes(1);
      await tester.pump(const Duration(milliseconds: 1));
      expect(access.isLocked, isTrue);
      expect(find.text('business'), findsNothing);
      await tester.pumpWidget(const SizedBox());
      access.dispose();
    },
  );
  group('actual provider boundary with synthetic test sessions', () {
    late SupabaseClient client;
    late _Auth auth;
    late SecureSessionStorage storage;
    late SupabaseSessionSecurityRepository repository;
    late Future<http.Response> Function(http.Request) handler;
    late List<http.Request> requests;
    setUp(() async {
      requests = [];
      auth = _Auth();
      storage = SecureSessionStorage(store: _Store());
      await storage.initialize();
      handler = (request) async {
        requests.add(request);
        return http.Response(
          request.url.path.endsWith('/token')
              ? jsonEncode(_session('actor-a'))
              : '{}',
          200,
        );
      };
      final mock = MockClient((request) => handler(request));
      client = SupabaseClient(
        'https://project.example.test',
        'public-test-key',
        httpClient: mock,
      );
      repository = SupabaseSessionSecurityRepository(
        client: client,
        auth: auth,
        sessionStorage: storage,
        authUrl: 'https://project.example.test/auth/v1',
        publicApiKey: 'public-test-key',
        isolatedClientFactory: () => GoTrueClient(
          url: 'https://project.example.test/auth/v1',
          headers: {'apikey': 'public-test-key'},
          autoRefreshToken: false,
          httpClient: mock,
        ),
      );
    });
    tearDown(() async => client.dispose());
    test(
      'password check uses isolated provider session and revokes it',
      () async {
        await repository.verifyCurrentPassword('account-password-test');
        expect(client.auth.currentSession, isNull);
        expect(requests.map((r) => r.url.path), [
          '/auth/v1/token',
          '/auth/v1/logout',
        ]);
        expect(requests.last.url.queryParameters['scope'], 'local');
        expect(await storage.hasAccessToken(), isFalse);
      },
    );
    test('failed verification sanitizes provider detail', () async {
      handler = (request) async => http.Response(
        '{"msg":"secret-provider-detail","code":"invalid_credentials"}',
        400,
      );
      await expectLater(
        repository.verifyCurrentPassword('wrong'),
        throwsA(
          isA<AuthFailure>().having(
            (e) => e.message,
            'message',
            isNot(contains('secret-provider-detail')),
          ),
        ),
      );
      expect(client.auth.currentSession, isNull);
    });
    test(
      'delayed password verification cannot restore logged-out actor',
      () async {
        final response = Completer<http.Response>();
        handler = (request) async {
          requests.add(request);
          return request.url.path.endsWith('/token')
              ? response.future
              : http.Response('{}', 200);
        };
        final pending = repository.verifyCurrentPassword('test-password');
        await Future<void>.delayed(Duration.zero);
        auth.identity = null;
        response.complete(http.Response(jsonEncode(_session('actor-a')), 200));
        await expectLater(pending, throwsA(isA<AuthFailure>()));
        expect(client.auth.currentSession, isNull);
        expect(requests.last.url.path, '/auth/v1/logout');
      },
    );
    test(
      'provider identity mismatch never verifies current workspace',
      () async {
        handler = (request) async => http.Response(
          request.url.path.endsWith('/token')
              ? jsonEncode(_session('actor-b'))
              : '{}',
          200,
        );
        await expectLater(
          repository.verifyCurrentPassword('test'),
          throwsA(isA<AuthFailure>()),
        );
        expect(auth.currentIdentity?.userId, 'actor-a');
        expect(client.auth.currentSession, isNull);
      },
    );
    test('recovery cannot verify password or globally revoke', () async {
      auth.recovery = true;
      await expectLater(
        repository.verifyCurrentPassword('test'),
        throwsA(isA<AuthFailure>()),
      );
      await expectLater(
        repository.signOutAllSessions(),
        throwsA(isA<AuthFailure>()),
      );
      expect(requests, isEmpty);
    });
    test(
      'global sign-out calls provider global scope and clears consent',
      () async {
        client.auth.setInitialSession(jsonEncode(_session('actor-a')));
        await storage.setRememberDevice(true);
        await storage.persistSession('synthetic-test-session');
        await repository.signOutAllSessions();
        expect(requests.first.url.queryParameters['scope'], 'global');
        expect(client.auth.currentSession, isNull);
        expect(storage.remembersDevice, isFalse);
        expect(await storage.hasAccessToken(), isFalse);
      },
    );
    test(
      'unconfirmed global revocation keeps current session for retry',
      () async {
        client.auth.setInitialSession(jsonEncode(_session('actor-a')));
        handler = (request) async =>
            http.Response('{"msg":"provider-private","code":"failure"}', 500);
        await storage.setRememberDevice(true);
        await storage.persistSession('synthetic-test-session');
        await expectLater(
          repository.signOutAllSessions(),
          throwsA(isA<AuthFailure>()),
        );
        expect(client.auth.currentSession, isNotNull);
        expect(storage.remembersDevice, isTrue);
      },
    );
  });

  testWidgets(
    'idle lock hides navigator content and unlock verifies password',
    (tester) async {
      final access = AccessLock();
      var verified = 0;
      await tester.pumpWidget(
        MaterialApp(
          home: SessionLockGuard(
            access: access,
            actorId: 'actor-a',
            onVerifyPassword: (password) async {
              expect(password, 'test-password');
              verified++;
            },
            onSignOut: () {},
            child: const Scaffold(body: Text('private payment details')),
          ),
        ),
      );
      expect(find.text('private payment details'), findsOneWidget);
      await tester.pump(const Duration(minutes: 5));
      expect(find.text('private payment details'), findsNothing);
      expect(find.text('Workspace locked'), findsOneWidget);
      await tester.enterText(find.byType(TextField), 'test-password');
      await tester.tap(find.text('Unlock online'));
      await tester.pumpAndSettle();
      expect(verified, 1);
      expect(access.isLocked, isFalse);
      expect(find.text('private payment details'), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
      access.dispose();
    },
  );
  testWidgets('manual lock hides route dialogs as well as home', (
    tester,
  ) async {
    final access = AccessLock();
    await tester.pumpWidget(
      MaterialApp(
        builder: (context, child) => SessionLockGuard(
          access: access,
          actorId: 'actor-a',
          onVerifyPassword: null,
          onSignOut: () {},
          child: child!,
        ),
        home: Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              onPressed: () => showDialog<void>(
                context: context,
                builder: (_) =>
                    const AlertDialog(content: Text('private pending tender')),
              ),
              child: const Text('Open'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();
    expect(find.text('private pending tender'), findsOneWidget);
    access.lock();
    await tester.pump();
    expect(find.text('private pending tender'), findsNothing);
    expect(find.text('Workspace locked'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
    access.dispose();
  });
  testWidgets(
    'background lock retains original generation and cannot unlock changed actor',
    (tester) async {
      final access = AccessLock();
      final response = Completer<void>();
      Widget app(String actor) => MaterialApp(
        builder: (context, child) => SessionLockGuard(
          access: access,
          actorId: actor,
          onVerifyPassword: (_) => response.future,
          onSignOut: () {},
          child: child!,
        ),
        home: const Scaffold(body: Text('protected scope')),
      );
      await tester.pumpWidget(app('actor-a'));
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
      await tester.pump();
      expect(access.isLocked, isTrue);
      await tester.enterText(find.byType(TextField), 'test');
      await tester.tap(find.text('Unlock online'));
      await tester.pump();
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pumpWidget(app('actor-b'));
      access.lock();
      await tester.pump();
      response.complete();
      await tester.pumpAndSettle();
      expect(access.actorId, 'actor-b');
      expect(access.isLocked, isTrue);
      await tester.pumpWidget(const SizedBox());
      access.dispose();
    },
  );
}
