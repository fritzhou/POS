import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

abstract interface class SecretStore {
  Future<String?> read(String key);
  Future<void> write(String key, String value);
  Future<void> delete(String key);
}

class PlatformSecretStore implements SecretStore {
  PlatformSecretStore({FlutterSecureStorage? storage})
    : _storage = storage ?? const FlutterSecureStorage();

  final FlutterSecureStorage _storage;

  @override
  Future<String?> read(String key) => _storage.read(key: key);
  @override
  Future<void> write(String key, String value) =>
      _storage.write(key: key, value: value);
  @override
  Future<void> delete(String key) => _storage.delete(key: key);
}

/// Supabase session and PKCE secrets remain memory-only without explicit
/// "Remember this device" consent. Supabase refreshes the live session itself.
class SecureSessionStorage extends LocalStorage implements GotrueAsyncStorage {
  SecureSessionStorage({this.namespace = 'nexapos.auth', SecretStore? store})
    : _store = store ?? PlatformSecretStore();

  final String namespace;
  final SecretStore _store;
  Future<void> _pending = Future.value();
  bool _remember = false;
  String? _session;
  final Map<String, String> _pkce = {};

  bool get remembersDevice => _remember;
  String get _sessionKey => '$namespace.session';
  String get _consentKey => '$namespace.remember';
  String get _pkceKey => '$namespace.pkce';

  // Serialized writes prevent an older refresh write from recreating secrets
  // after persistence consent is removed or the user signs out.
  Future<T> _serial<T>(Future<T> Function() operation) {
    final next = _pending.then((_) => operation());
    _pending = next.then<void>((_) {}, onError: (Object _, StackTrace _) {});
    return next;
  }

  @override
  Future<void> initialize() => _serial(() async {
    _remember = await _store.read(_consentKey) == 'true';
    if (_remember) {
      _session = await _store.read(_sessionKey);
      final encoded = await _store.read(_pkceKey);
      if (encoded != null) {
        try {
          final decoded = jsonDecode(encoded) as Map<String, dynamic>;
          _pkce.addAll(
            decoded.map((key, value) => MapEntry(key, value as String)),
          );
        } on Object {
          await _store.delete(_pkceKey);
        }
      }
    } else {
      await _store.delete(_sessionKey);
      await _store.delete(_pkceKey);
    }
  });

  Future<void> setRememberDevice(bool remember) => _serial(() async {
    _remember = remember;
    if (!remember) {
      await _store.delete(_sessionKey);
      await _store.delete(_pkceKey);
      await _store.delete(_consentKey);
    } else {
      await _store.write(_consentKey, 'true');
      if (_session != null) await _store.write(_sessionKey, _session!);
      if (_pkce.isNotEmpty) await _store.write(_pkceKey, jsonEncode(_pkce));
    }
  });

  @override
  Future<bool> hasAccessToken() => _serial(() async => _session != null);
  @override
  Future<String?> accessToken() => _serial(() async => _session);
  @override
  Future<void> persistSession(String persistSessionString) => _serial(() async {
    _session = persistSessionString;
    if (_remember) await _store.write(_sessionKey, persistSessionString);
  });

  @override
  Future<void> removePersistedSession() => _serial(() async {
    _session = null;
    _pkce.clear();
    _remember = false;
    await _store.delete(_sessionKey);
    await _store.delete(_pkceKey);
    await _store.delete(_consentKey);
  });

  @override
  Future<String?> getItem({required String key}) =>
      _serial(() async => _pkce[key]);
  @override
  Future<void> setItem({required String key, required String value}) =>
      _serial(() async {
        _pkce[key] = value;
        if (_remember) await _store.write(_pkceKey, jsonEncode(_pkce));
      });
  @override
  Future<void> removeItem({required String key}) => _serial(() async {
    _pkce.remove(key);
    if (_remember && _pkce.isNotEmpty) {
      await _store.write(_pkceKey, jsonEncode(_pkce));
    } else {
      await _store.delete(_pkceKey);
    }
  });
}
