import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:crypto/crypto.dart' as crypto;
import 'package:cryptography/cryptography.dart';
import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:sqlite3/sqlite3.dart' as sqlite;

import '../auth/secure_session_storage.dart';

/// Sanitized failures never include SQL statements, paths, keys or paid payloads.
class LocalDatabaseSecurityFailure implements Exception {
  const LocalDatabaseSecurityFailure(this.code);
  final String code;
  @override
  String toString() =>
      'Local database protection failed ($code). '
      'Preserve the local files and contact your administrator.';
}

/// Exact pre-migration bytes, authenticated before being exposed to an explicit
/// administrator recovery/export tool. The runtime never restores plaintext.
class LocalDatabaseRecovery {
  LocalDatabaseRecovery(Map<String, List<int>> files)
    : files = Map.unmodifiable({
        for (final entry in files.entries)
          entry.key: List<int>.unmodifiable(entry.value),
      });
  final Map<String, List<int>> files;
}

/// SQLCipher file protection, independent of Auth tokens and offline signing.
/// Database keys must survive logout: deleting them would strand paid records.
class EncryptedDatabaseFactory {
  EncryptedDatabaseFactory({
    required this.store,
    this.namespace = 'nexapos.local_database.v1',
  });

  final SecretStore store;
  final String namespace;
  static final Map<String, Future<void>> _tails = {};
  static const _sqliteHeader = 'SQLite format 3\u0000';
  static const _maximumLegacyBytes = 128 * 1024 * 1024;

  String _scope(File file) =>
      crypto.sha256.convert(utf8.encode(file.absolute.path)).toString();
  String _vaultKey(File file) => '$namespace.key.${_scope(file)}';

  /// The only production file-opening path. Memory-only test executors do not
  /// need a vault key. No plaintext fallback exists if the hook is misconfigured.
  Future<QueryExecutor> open(File file) async {
    final key = await prepare(file);
    // Capture only the key text for Drift's background isolate, never a plugin
    // instance or a Flutter binding. Statement logging is explicitly disabled.
    return NativeDatabase.createInBackground(
      file,
      logStatements: false,
      setup: (database) => _configure(database, key),
    );
  }

  /// Read recovery bytes into memory only; no new key, schema, overwrite or
  /// automatic plaintext export is permitted by this operation.
  Future<LocalDatabaseRecovery> readLegacyRecovery(File file) async {
    final encoded = await store.read(_vaultKey(file));
    if (encoded == null) {
      throw const LocalDatabaseSecurityFailure('KEY_MISSING');
    }
    final record = await _readRecovery(file, _decodeKey(encoded));
    final files = record['files']! as Map<String, dynamic>;
    return LocalDatabaseRecovery({
      for (final entry in files.entries)
        entry.key: base64.decode(entry.value as String),
    });
  }

  /// Establishes/validates a durable key and performs legacy protection before
  /// allowing Drift to run its additive schema migration.
  Future<String> prepare(File file) {
    final path = file.absolute.path;
    final previous = _tails[path] ?? Future<void>.value();
    final result = previous.then((_) => _prepare(file));
    final tail = result.then<void>(
      (_) {},
      onError: (Object _, StackTrace _) {},
    );
    _tails[path] = tail;
    tail.whenComplete(() {
      if (identical(_tails[path], tail)) _tails.remove(path);
    });
    return result;
  }

  Future<String> _prepare(File file) async {
    await file.parent.create(recursive: true);
    final lock = await File(
      '${file.path}.protection-lock',
    ).open(mode: FileMode.append);
    try {
      await lock.lock(FileLock.exclusive);
      _requireCipher();
      final artifacts = await _hasArtifacts(file);
      final exists = await file.exists();
      final plaintext = exists && await _isPlaintext(file);
      var encoded = await store.read(_vaultKey(file));
      if (encoded == null) {
        // A previously protected file/recovery artifact can never acquire a new
        // key. Legacy plaintext alone can be explicitly upgraded in place.
        if (artifacts || (exists && !plaintext)) {
          throw const LocalDatabaseSecurityFailure('KEY_MISSING');
        }
        final random = Random.secure();
        encoded = base64Url.encode(
          List<int>.generate(32, (_) => random.nextInt(256)),
        );
        await store.write(_vaultKey(file), encoded);
        if (await store.read(_vaultKey(file)) != encoded) {
          throw const LocalDatabaseSecurityFailure('KEY_NOT_DURABLE');
        }
      }
      final key = _decodeKey(encoded);
      final hex = _hex(key);
      final state = File('${file.path}.protection-state');
      if (await state.exists()) {
        await _resume(file, key, hex);
      } else if (plaintext) {
        await _migrate(file, key, hex);
      } else if (artifacts) {
        // An incomplete export remains source-backed and can be retried only
        // with its original plaintext source. Never silently create a new DB.
        if (!exists) {
          throw const LocalDatabaseSecurityFailure('RECOVERY_REQUIRED');
        }
        await _validateProtected(file, hex);
      } else if (exists) {
        await _validateProtected(file, hex);
      } else {
        // Materialize encrypted schema before returning: an empty unprotected
        // file would otherwise be indistinguishable from lost key metadata.
        final db = sqlite.sqlite3.open(file.path);
        try {
          _configure(db, hex);
          db.execute('PRAGMA user_version = 0');
          db.execute('CREATE TABLE __nexapos_protection_probe (id INTEGER)');
          db.execute('DROP TABLE __nexapos_protection_probe');
        } finally {
          db.close();
        }
        await _validateProtected(file, hex);
      }
      return hex;
    } on LocalDatabaseSecurityFailure {
      rethrow;
    } on Object catch (_, stack) {
      Error.throwWithStackTrace(
        const LocalDatabaseSecurityFailure('PROTECTION_UNAVAILABLE'),
        stack,
      );
    } finally {
      await lock.close();
    }
  }

  static Uint8List _decodeKey(String encoded) {
    try {
      final key = base64Url.decode(encoded);
      if (key.length != 32 || base64Url.encode(key) != encoded) {
        throw const FormatException();
      }
      return key;
    } on Object {
      throw const LocalDatabaseSecurityFailure('KEY_CORRUPT');
    }
  }

  static String _hex(List<int> bytes) =>
      bytes.map((value) => value.toRadixString(16).padLeft(2, '0')).join();

  static void _requireCipher() {
    final db = sqlite.sqlite3.openInMemory();
    try {
      final version = db.select('PRAGMA cipher_version');
      if (version.isEmpty || version.first.values.single is! String) {
        throw const LocalDatabaseSecurityFailure('SQLCIPHER_REQUIRED');
      }
    } finally {
      db.close();
    }
  }

  static void _configure(sqlite.Database db, String key) {
    try {
      // Raw 256-bit random keys avoid a user password/KDF as the storage key.
      // Key syntax only accepts the internally generated lowercase hex string.
      if (!RegExp(r'^[0-9a-f]{64}$').hasMatch(key)) {
        throw const LocalDatabaseSecurityFailure('KEY_CORRUPT');
      }
      final version = db.select('PRAGMA cipher_version');
      if (version.isEmpty) {
        throw const LocalDatabaseSecurityFailure('SQLCIPHER_REQUIRED');
      }
      db.execute('PRAGMA key = "x\'$key\'"');
      db.execute('PRAGMA cipher_memory_security = ON');
      db.execute('PRAGMA trusted_schema = OFF');
      db.execute('PRAGMA temp_store = MEMORY');
      db.execute('PRAGMA synchronous = FULL');
      db.execute('PRAGMA busy_timeout = 5000');
      // Force decryption now, before Drift migration or any caller sees data.
      db.select('SELECT count(*) FROM sqlite_master');
    } on LocalDatabaseSecurityFailure {
      rethrow;
    } on Object {
      throw const LocalDatabaseSecurityFailure('KEY_OR_FILE_INVALID');
    }
  }

  Future<bool> _isPlaintext(File file) async {
    final handle = await file.open();
    try {
      final header = await handle.read(16);
      return latin1.decode(header) == _sqliteHeader;
    } finally {
      await handle.close();
    }
  }

  Future<bool> _hasArtifacts(File file) async {
    for (final suffix in [
      '.protection-state',
      '.legacy-recovery.enc',
      '.encrypted-next',
    ]) {
      if (await File('${file.path}$suffix').exists()) return true;
    }
    return false;
  }

  Future<void> _validateProtected(File file, String hex) async {
    if (!await file.exists() || await _isPlaintext(file)) {
      throw const LocalDatabaseSecurityFailure('PROTECTED_FILE_MISSING');
    }
    final db = sqlite.sqlite3.open(file.path, mode: sqlite.OpenMode.readOnly);
    try {
      _configure(db, hex);
      _integrity(db);
    } finally {
      db.close();
    }
  }

  static void _integrity(sqlite.Database db) {
    final structural = db.select('PRAGMA integrity_check');
    if (structural.length != 1 ||
        structural.single.values.single != 'ok' ||
        db.select('PRAGMA cipher_integrity_check').isNotEmpty) {
      throw const LocalDatabaseSecurityFailure('FILE_CORRUPT');
    }
  }

  // Full schema, user_version, exact typed table values and duplicate rows are
  // compared. Sorting row encodings also supports WITHOUT ROWID tables.
  static String _fingerprint(sqlite.Database db) {
    final entities = db.select(
      "SELECT type,name,tbl_name,sql FROM sqlite_master WHERE name NOT LIKE 'sqlite_%' ORDER BY type,name",
    );
    final tables = db.select(
      "SELECT name FROM sqlite_master WHERE type='table' ORDER BY name",
    );
    final records = <Object?>[
      db.select('PRAGMA user_version').single.values.single,
      for (final row in entities) row.values.toList(),
    ];
    for (final table in tables) {
      final name = table['name']! as String;
      final escaped = name.replaceAll('"', '""');
      final rows = db.select('SELECT * FROM "$escaped"');
      final encoded =
          rows
              .map(
                (row) => jsonEncode([
                  for (final value in row.values)
                    if (value is Uint8List)
                      ['blob', base64.encode(value)]
                    else if (value is int)
                      ['integer', value.toString()]
                    else if (value is double)
                      ['real', value.toString()]
                    else if (value is String)
                      ['text', value]
                    else
                      ['null'],
                ]),
              )
              .toList()
            ..sort();
      records.add([name, rows.columnNames, encoded]);
    }
    return crypto.sha256.convert(utf8.encode(jsonEncode(records))).toString();
  }

  Future<SecretKey> _archiveKey(List<int> key) =>
      Hkdf(hmac: Hmac.sha256(), outputLength: 32).deriveKey(
        secretKey: SecretKey(key),
        nonce: const [],
        info: utf8.encode('NexaPOS:legacy-recovery:v1'),
      );

  List<int> _archiveAad(File file) =>
      utf8.encode('NexaPOS:legacy-recovery:v1:${_scope(file)}');

  Future<Map<String, Object?>> _readRecovery(File file, List<int> key) async {
    try {
      final record =
          jsonDecode(
                await File('${file.path}.legacy-recovery.enc').readAsString(),
              )
              as Map<String, dynamic>;
      if (record.length != 4 || record['version'] != 1) {
        throw const FormatException();
      }
      final box = SecretBox(
        base64.decode(record['ciphertext'] as String),
        nonce: base64.decode(record['nonce'] as String),
        mac: Mac(base64.decode(record['mac'] as String)),
      );
      final bytes = await AesGcm.with256bits().decrypt(
        box,
        secretKey: await _archiveKey(key),
        aad: _archiveAad(file),
      );
      final value = jsonDecode(utf8.decode(bytes)) as Map<String, Object?>;
      if (value['scope'] != _scope(file) ||
          value['format'] != 1 ||
          value['files'] is! Map<String, dynamic> ||
          value['fingerprint'] is! String) {
        throw const FormatException();
      }
      final files = value['files']! as Map<String, dynamic>;
      if (!files.containsKey('') ||
          files.keys.any(
            (suffix) => !const ['', '-wal', '-journal'].contains(suffix),
          )) {
        throw const FormatException();
      }
      for (final encoded in files.values) {
        base64.decode(encoded as String);
      }
      return value;
    } on Object {
      throw const LocalDatabaseSecurityFailure('RECOVERY_BACKUP_INVALID');
    }
  }

  Future<void> _writeRecovery(
    File file,
    List<int> key,
    String fingerprint,
  ) async {
    final files = <String, String>{};
    var size = 0;
    for (final suffix in ['', '-wal', '-journal']) {
      final source = File('${file.path}$suffix');
      if (!await source.exists()) continue;
      size += await source.length();
      if (size > _maximumLegacyBytes) {
        throw const LocalDatabaseSecurityFailure('LEGACY_MIGRATION_TOO_LARGE');
      }
      files[suffix] = base64.encode(await source.readAsBytes());
    }
    final clear = utf8.encode(
      jsonEncode({
        'format': 1,
        'scope': _scope(file),
        'fingerprint': fingerprint,
        'files': files,
      }),
    );
    final box = await AesGcm.with256bits().encrypt(
      clear,
      secretKey: await _archiveKey(key),
      aad: _archiveAad(file),
    );
    await _atomicWrite(
      File('${file.path}.legacy-recovery.enc'),
      jsonEncode({
        'version': 1,
        'nonce': base64.encode(box.nonce),
        'ciphertext': base64.encode(box.cipherText),
        'mac': base64.encode(box.mac.bytes),
      }),
    );
    final verified = await _readRecovery(file, key);
    if (verified['fingerprint'] != fingerprint) {
      throw const LocalDatabaseSecurityFailure('RECOVERY_BACKUP_INVALID');
    }
  }

  Future<void> _migrate(File file, List<int> key, String hex) async {
    final target = File('${file.path}.encrypted-next');
    if (!await file.exists() || !await _isPlaintext(file)) {
      throw const LocalDatabaseSecurityFailure('MIGRATION_SOURCE_CHANGED');
    }
    var legacyBytes = 0;
    for (final suffix in ['', '-wal', '-journal']) {
      final legacy = File('${file.path}$suffix');
      if (await legacy.exists()) legacyBytes += await legacy.length();
    }
    if (legacyBytes > _maximumLegacyBytes) {
      throw const LocalDatabaseSecurityFailure('LEGACY_MIGRATION_TOO_LARGE');
    }
    final source = sqlite.sqlite3.open(
      file.path,
      // SQLite inherits CREATE for ATTACH. The existing main file was checked
      // above; this flag allows only the separately named encrypted target.
      mode: sqlite.OpenMode.readWriteCreate,
    );
    String? fingerprint;
    try {
      source.execute('PRAGMA temp_store = MEMORY');
      source.execute('PRAGMA trusted_schema = OFF');
      source.execute('PRAGMA busy_timeout = 5000');
      source.execute('PRAGMA locking_mode = EXCLUSIVE');
      // Without a durable promotion marker the target was never exposed to a
      // caller, so an interrupted incomplete export can be rebuilt from source.
      for (final suffix in ['-wal', '-shm', '-journal', '']) {
        final incomplete = File('${target.path}$suffix');
        if (await incomplete.exists()) await incomplete.delete();
      }
      source.execute('ATTACH DATABASE ? AS encrypted KEY ?', [
        target.path,
        "x'$hex'",
      ]);
      source.execute('PRAGMA encrypted.synchronous = FULL');
      source.execute('BEGIN EXCLUSIVE');
      fingerprint = _fingerprint(source);
      await _writeRecovery(file, key, fingerprint);
      source.select("SELECT sqlcipher_export('encrypted')");
      final version = source.select('PRAGMA user_version').single.values.single;
      source.execute('PRAGMA encrypted.user_version = $version');
      source.execute('COMMIT');
      source.execute('DETACH DATABASE encrypted');
      final copy = sqlite.sqlite3.open(
        target.path,
        mode: sqlite.OpenMode.readOnly,
      );
      try {
        _configure(copy, hex);
        _integrity(copy);
        if (_fingerprint(copy) != fingerprint) {
          throw const LocalDatabaseSecurityFailure('MIGRATION_MISMATCH');
        }
      } finally {
        copy.close();
      }
      await _flush(target);
      await _atomicWrite(
        File('${file.path}.protection-state'),
        jsonEncode({
          'format': 1,
          'scope': _scope(file),
          'fingerprint': fingerprint,
          'state': 'ready',
        }),
      );
    } finally {
      source.close();
    }
    // Original handles are closed before promotion for Windows compatibility.
    // The durable encrypted backup plus verified target precede every deletion.
    await _resume(file, key, hex);
  }

  Future<void> _resume(File file, List<int> key, String hex) async {
    final stateFile = File('${file.path}.protection-state');
    final Map<String, dynamic> state;
    try {
      state =
          jsonDecode(await stateFile.readAsString()) as Map<String, dynamic>;
      if (state.length != 4 ||
          state['format'] != 1 ||
          state['scope'] != _scope(file) ||
          state['fingerprint'] is! String ||
          !const ['ready', 'promoting', 'complete'].contains(state['state'])) {
        throw const FormatException();
      }
    } on Object {
      throw const LocalDatabaseSecurityFailure('MIGRATION_STATE_INVALID');
    }
    final backup = await _readRecovery(file, key);
    if (backup['fingerprint'] != state['fingerprint']) {
      throw const LocalDatabaseSecurityFailure('MIGRATION_STATE_INVALID');
    }
    if (state['state'] == 'complete') {
      await _validateProtected(file, hex);
      return;
    }
    final target = File('${file.path}.encrypted-next');
    if (await target.exists()) {
      await _validateProtected(target, hex);
      final db = sqlite.sqlite3.open(
        target.path,
        mode: sqlite.OpenMode.readOnly,
      );
      try {
        _configure(db, hex);
        if (_fingerprint(db) != state['fingerprint']) {
          throw const LocalDatabaseSecurityFailure('MIGRATION_MISMATCH');
        }
      } finally {
        db.close();
      }
      if (state['state'] == 'ready') {
        // Detect an older process writing to the source between an interrupted
        // export and this launch. Never promote a stale paid-record snapshot.
        if (!await file.exists() || !await _isPlaintext(file)) {
          throw const LocalDatabaseSecurityFailure('MIGRATION_SOURCE_CHANGED');
        }
        final original = sqlite.sqlite3.open(
          file.path,
          mode: sqlite.OpenMode.readOnly,
        );
        try {
          original.execute('PRAGMA temp_store = MEMORY');
          if (_fingerprint(original) != state['fingerprint']) {
            throw const LocalDatabaseSecurityFailure(
              'MIGRATION_SOURCE_CHANGED',
            );
          }
        } finally {
          original.close();
        }
        await _atomicWrite(
          stateFile,
          jsonEncode({...state, 'state': 'promoting'}),
        );
      }
      // A ready marker is written only after both encrypted copies are durable.
      // Sidecars must disappear before the encrypted main file takes this path.
      for (final suffix in ['-wal', '-shm', '-journal', '']) {
        final old = File('${file.path}$suffix');
        if (await old.exists()) await old.delete();
      }
      await target.rename(file.path);
    } else {
      // Crash after promotion but before updating the marker: verify exact copy.
      await _validateProtected(file, hex);
      final db = sqlite.sqlite3.open(file.path, mode: sqlite.OpenMode.readOnly);
      try {
        _configure(db, hex);
        if (_fingerprint(db) != state['fingerprint']) {
          throw const LocalDatabaseSecurityFailure('MIGRATION_MISMATCH');
        }
      } finally {
        db.close();
      }
    }
    await _atomicWrite(stateFile, jsonEncode({...state, 'state': 'complete'}));
  }

  static Future<void> _flush(File file) async {
    final handle = await file.open(mode: FileMode.append);
    try {
      await handle.flush();
    } finally {
      await handle.close();
    }
  }

  static Future<void> _atomicWrite(File target, String value) async {
    final staging = File('${target.path}.writing');
    await staging.writeAsString(value, flush: true);
    await staging.rename(target.path);
  }
}
