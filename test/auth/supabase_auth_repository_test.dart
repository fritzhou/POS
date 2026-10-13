import 'package:flutter_test/flutter_test.dart';
import 'package:nexapos/core/auth/auth_models.dart';
import 'package:nexapos/core/auth/secure_session_storage.dart';
import 'package:nexapos/core/auth/supabase_auth_repository.dart';
import 'package:nexapos/core/services/email_service.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class _MemoryStore implements SecretStore {
  final values = <String, String>{};
  @override
  Future<void> delete(String key) async => values.remove(key);
  @override
  Future<String?> read(String key) async => values[key];
  @override
  Future<void> write(String key, String value) async => values[key] = value;
}

class _FakeEmailService implements EmailService {
  int recoveryCalls = 0;
  String? email;
  String? redirect;
  Object? error;

  @override
  Future<void> requestPasswordRecovery(
    String email, {
    required String redirectTo,
  }) async {
    recoveryCalls++;
    this.email = email;
    redirect = redirectTo;
    if (error != null) throw error!;
  }

  @override
  Future<void> requestVerification(String email, {String? redirectTo}) async {}
}

void main() {
  late SupabaseClient client;
  late SecureSessionStorage storage;
  late _FakeEmailService emails;
  late SupabaseAuthRepository repository;

  setUp(() async {
    // Deliberately unreachable public configuration; these tests exercise
    // preflight gates and an injected email boundary, with no HTTP requests.
    client = SupabaseClient('https://project.example.test', 'public-test-key');
    storage = SecureSessionStorage(store: _MemoryStore());
    await storage.initialize();
    emails = _FakeEmailService();
    repository = SupabaseAuthRepository(
      client: client,
      sessionStorage: storage,
      emailService: emails,
      recoveryRedirectTo: 'https://app.example.test/recovery',
    );
  });

  tearDown(() async {
    await repository.dispose();
    await client.dispose();
  });

  test(
    'actual adapter cannot authorize or reset without Auth session',
    () async {
      expect(repository.currentIdentity, isNull);
      expect(repository.hasVerifiedRecoverySession, isFalse);
      expect(await repository.loadMemberships(), isEmpty);
      await expectLater(
        repository.updateRecoveredPassword('LongSafePassword123!'),
        throwsA(
          isA<AuthFailure>().having(
            (error) => error.message,
            'message',
            contains('recovery session'),
          ),
        ),
      );
      await expectLater(
        repository.bootstrapOwner(
          businessName: 'New business',
          fullName: 'Owner',
        ),
        throwsA(isA<AuthFailure>()),
      );
    },
  );

  test('Employee ID fails before persistence or anonymous lookup', () async {
    await expectLater(
      repository.signIn(
        email: 'EMP001',
        password: 'anything',
        rememberDevice: true,
      ),
      throwsA(
        isA<AuthFailure>().having(
          (error) => error.message,
          'message',
          contains('Coming Soon'),
        ),
      ),
    );
    expect(storage.remembersDevice, isFalse);
    expect(await storage.hasAccessToken(), isFalse);
  });

  test(
    'recovery uses replaceable email boundary and allowed destination',
    () async {
      await repository.requestPasswordRecovery('  owner@example.test  ');
      expect(emails.recoveryCalls, 1);
      expect(emails.email, 'owner@example.test');
      expect(emails.redirect, 'https://app.example.test/recovery');
      expect(repository.hasVerifiedRecoverySession, isFalse);
    },
  );

  test('account-specific recovery error does not disclose existence', () async {
    emails.error = const AuthException(
      'Raw internal account detail',
      code: 'user_not_found',
    );
    await repository.requestPasswordRecovery('unknown@example.test');
    expect(emails.recoveryCalls, 1);
  });

  test(
    'raw delivery failure becomes sanitized service availability error',
    () async {
      emails.error = Exception('SMTP password=SECRET');
      await expectLater(
        repository.requestPasswordRecovery('owner@example.test'),
        throwsA(
          isA<AuthFailure>()
              .having(
                (error) => error.message,
                'message',
                contains('temporarily unavailable'),
              )
              .having(
                (error) => error.message,
                'message',
                isNot(contains('SECRET')),
              ),
        ),
      );
    },
  );
}
