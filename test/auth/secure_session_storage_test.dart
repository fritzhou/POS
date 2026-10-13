import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:nexapos/core/auth/secure_session_storage.dart';

const _session =
    '{"access_token":"test-access-token","refresh_token":"test-refresh-token"}';
const _verifierKey = 'auth-token-code-verifier';
const _verifier = 'test-pkce-verifier';

void main() {
  group('SecureSessionStorage', () {
    test('default session and PKCE remain in memory only', () async {
      final vault = _MemorySecretStore();
      final storage = SecureSessionStorage(store: vault);
      await storage.initialize();

      await storage.persistSession(_session);
      await storage.setItem(key: _verifierKey, value: _verifier);

      expect(storage.remembersDevice, isFalse);
      expect(await storage.hasAccessToken(), isTrue);
      expect(await storage.accessToken(), _session);
      expect(await storage.getItem(key: _verifierKey), _verifier);
      expect(vault.entries, isEmpty);

      final restarted = SecureSessionStorage(store: vault);
      await restarted.initialize();
      expect(await restarted.hasAccessToken(), isFalse);
      expect(await restarted.getItem(key: _verifierKey), isNull);
    });

    test('remembered session and PKCE restore after restart', () async {
      final vault = _MemorySecretStore();
      final storage = SecureSessionStorage(store: vault);
      await storage.initialize();
      await storage.setRememberDevice(true);
      await storage.persistSession(_session);
      await storage.setItem(key: _verifierKey, value: _verifier);

      final restarted = SecureSessionStorage(store: vault);
      await restarted.initialize();

      expect(restarted.remembersDevice, isTrue);
      expect(await restarted.hasAccessToken(), isTrue);
      expect(await restarted.accessToken(), _session);
      expect(await restarted.getItem(key: _verifierKey), _verifier);
    });

    test(
      'disabling remember removes vault secrets but keeps current session',
      () async {
        final vault = _MemorySecretStore();
        final storage = SecureSessionStorage(store: vault);
        await storage.initialize();
        await storage.setRememberDevice(true);
        await storage.persistSession(_session);
        await storage.setItem(key: _verifierKey, value: _verifier);

        await storage.setRememberDevice(false);

        expect(storage.remembersDevice, isFalse);
        expect(await storage.accessToken(), _session);
        expect(await storage.getItem(key: _verifierKey), _verifier);
        expect(vault.entries, isEmpty);

        final restarted = SecureSessionStorage(store: vault);
        await restarted.initialize();
        expect(restarted.remembersDevice, isFalse);
        expect(await restarted.hasAccessToken(), isFalse);
        expect(await restarted.getItem(key: _verifierKey), isNull);
      },
    );

    test('logout clears session, PKCE and remembered-device state', () async {
      final vault = _MemorySecretStore();
      final storage = SecureSessionStorage(store: vault);
      await storage.initialize();
      await storage.setRememberDevice(true);
      await storage.persistSession(_session);
      await storage.setItem(key: _verifierKey, value: _verifier);

      await storage.removePersistedSession();

      expect(await storage.hasAccessToken(), isFalse);
      expect(await storage.accessToken(), isNull);
      expect(await storage.getItem(key: _verifierKey), isNull);
      expect(storage.remembersDevice, isFalse);
      expect(vault.entries, isEmpty);

      final restarted = SecureSessionStorage(store: vault);
      await restarted.initialize();
      expect(await restarted.accessToken(), isNull);
      expect(await restarted.getItem(key: _verifierKey), isNull);
    });

    test(
      'in-flight persistence cannot recreate secrets after remember disable',
      () async {
        final vault = _MemorySecretStore();
        final storage = SecureSessionStorage(store: vault);
        await storage.initialize();
        await storage.setRememberDevice(true);
        vault.holdNextWrite();

        final persistence = storage.persistSession(_session);
        await vault.writeStarted.future;
        final disable = storage.setRememberDevice(false);
        vault.releaseWrite();
        await Future.wait([persistence, disable]);

        expect(storage.remembersDevice, isFalse);
        expect(await storage.accessToken(), _session);
        expect(vault.entries, isEmpty);
        final restarted = SecureSessionStorage(store: vault);
        await restarted.initialize();
        expect(await restarted.hasAccessToken(), isFalse);
      },
    );

    test(
      'logout leaves secrets belonging to another namespace untouched',
      () async {
        final vault = _MemorySecretStore();
        final first = SecureSessionStorage(namespace: 'first', store: vault);
        final second = SecureSessionStorage(namespace: 'second', store: vault);
        await first.initialize();
        await second.initialize();
        await first.setRememberDevice(true);
        await second.setRememberDevice(true);
        await first.persistSession(_session);
        await second.persistSession('other-session');
        await second.setItem(key: _verifierKey, value: 'other-verifier');

        await first.removePersistedSession();

        final restartedSecond = SecureSessionStorage(
          namespace: 'second',
          store: vault,
        );
        await restartedSecond.initialize();
        expect(restartedSecond.remembersDevice, isTrue);
        expect(await restartedSecond.accessToken(), 'other-session');
        expect(
          await restartedSecond.getItem(key: _verifierKey),
          'other-verifier',
        );
        expect(
          vault.entries.keys.where((key) => key.startsWith('first.')),
          isEmpty,
        );
      },
    );
  });
}

class _MemorySecretStore implements SecretStore {
  final entries = <String, String>{};
  Completer<void> writeStarted = Completer<void>();
  Completer<void>? _release;
  bool _holdNextWrite = false;

  void holdNextWrite() {
    writeStarted = Completer<void>();
    _release = Completer<void>();
    _holdNextWrite = true;
  }

  void releaseWrite() => _release!.complete();

  @override
  Future<String?> read(String key) async => entries[key];

  @override
  Future<void> write(String key, String value) async {
    if (_holdNextWrite) {
      _holdNextWrite = false;
      writeStarted.complete();
      await _release!.future;
    }
    entries[key] = value;
  }

  @override
  Future<void> delete(String key) async {
    entries.remove(key);
  }
}
