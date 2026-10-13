import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:drift/native.dart';
import 'package:nexapos/core/database/app_database.dart';
import 'package:nexapos/core/auth/secure_session_storage.dart';
import 'package:nexapos/core/operations/native_operation_journal.dart';
import 'package:nexapos/core/security/local_database_security.dart';
import 'package:sqlite3/sqlite3.dart' as sqlite;

class _Store implements SecretStore {
  final values = <String, String>{};
  bool rejectWrites = false;
  @override
  Future<String?> read(String key) async => values[key];
  @override
  Future<void> write(String key, String value) async {
    if (!rejectWrites) values[key] = value;
  }

  @override
  Future<void> delete(String key) async => values.remove(key);
}

Matcher failure(String code) => isA<LocalDatabaseSecurityFailure>().having(
  (value) => value.code,
  'code',
  code,
);

const org = 'a0000000-0000-4000-8000-000000000001';
const actor = 'a0000000-0000-4000-8000-000000000002';
const branch = 'a0000000-0000-4000-8000-000000000003';
const request = 'a0000000-0000-4000-8000-000000000004';
const paidText = 'paid transaction reference must survive shutdown';

sqlite.Database protected(File file, String hex) =>
    sqlite.sqlite3.open(file.path)..execute('PRAGMA key = "x\'$hex\'"');

void main() {
  late Directory directory;
  late File file;
  late _Store store;
  late EncryptedDatabaseFactory factory;
  setUp(() async {
    directory = await Directory.systemTemp.createTemp('nexapos-cipher-');
    file = File('${directory.path}/business.sqlite');
    store = _Store();
    factory = EncryptedDatabaseFactory(store: store);
  });
  tearDown(() => directory.delete(recursive: true));

  test('bundled native implementation is genuine SQLCipher', () {
    final db = sqlite.sqlite3.openInMemory();
    try {
      expect(
        db.select('PRAGMA cipher_version').single.values.single,
        startsWith('4.'),
      );
    } finally {
      db.close();
    }
  });

  test('random per-file vault keys and encrypted physical reopen', () async {
    final key = await factory.prepare(file);
    final db = protected(file, key);
    db.execute('CREATE TABLE payments (amount INTEGER, reference TEXT)');
    db.execute('INSERT INTO payments VALUES (?,?)', [1250, paidText]);
    db.close();
    expect(await factory.prepare(file), key);
    final restored = protected(file, key);
    expect(
      restored.select('SELECT * FROM payments').single['reference'],
      paidText,
    );
    restored.close();
    final bytes = await file.readAsBytes();
    expect(latin1.decode(bytes).contains(paidText), isFalse);
    expect(latin1.decode(bytes).startsWith('SQLite format 3'), isFalse);
    final raw = sqlite.sqlite3.open(file.path);
    expect(
      () => raw.select('SELECT * FROM sqlite_master'),
      throwsA(isA<sqlite.SqliteException>()),
    );
    raw.close();
    final other = await factory.prepare(File('${directory.path}/other.sqlite'));
    expect(other, isNot(key));
    expect(store.values.length, 2);
  });

  test(
    'missing and damaged vault keys preserve an existing encrypted file',
    () async {
      await factory.prepare(file);
      final before = await file.readAsBytes();
      store.values.clear();
      await expectLater(factory.prepare(file), throwsA(failure('KEY_MISSING')));
      expect(await file.readAsBytes(), before);
      expect(store.values, isEmpty);
      store.values['nexapos.local_database.v1.key.bad'] = 'not a key';
      // Obtain the correct locator from a separate normally initialized file.
      final second = File('${directory.path}/second.sqlite');
      await factory.prepare(second);
      final locator = store.values.keys.last;
      store.values[locator] = 'invalid';
      await expectLater(
        factory.prepare(second),
        throwsA(failure('KEY_CORRUPT')),
      );
    },
  );

  test(
    'a key write that cannot be read back never creates a business file',
    () async {
      store.rejectWrites = true;
      await expectLater(
        factory.prepare(file),
        throwsA(failure('KEY_NOT_DURABLE')),
      );
      expect(await file.exists(), isFalse);
    },
  );

  test(
    'plaintext export preserves exact typed rows, triggers and schema version',
    () async {
      final db = sqlite.sqlite3.open(file.path);
      db.execute('PRAGMA user_version = 2');
      db.execute(
        'CREATE TABLE paid (id INTEGER PRIMARY KEY AUTOINCREMENT, amount INTEGER, text TEXT, bytes BLOB, numeric REAL)',
      );
      db.execute(
        'INSERT INTO paid (amount,text,bytes,numeric) VALUES (?,?,?,?)',
        [
          1250,
          paidText,
          Uint8List.fromList([0, 1, 255]),
          1.25,
        ],
      );
      db.execute(
        "CREATE TRIGGER immutable_paid BEFORE DELETE ON paid BEGIN SELECT RAISE(ABORT,'paid records must survive'); END",
      );
      db.close();
      final original = await file.readAsBytes();
      final key = await factory.prepare(file);
      final copy = protected(file, key);
      expect(copy.select('PRAGMA user_version').single.values.single, 2);
      final row = copy.select('SELECT * FROM paid').single;
      expect(row['id'], 1);
      expect(row['amount'], 1250);
      expect(row['text'], paidText);
      expect(row['bytes'], [0, 1, 255]);
      expect(row['numeric'], 1.25);
      expect(
        () => copy.execute('DELETE FROM paid'),
        throwsA(isA<sqlite.SqliteException>()),
      );
      copy.close();
      expect(await file.readAsBytes(), isNot(original));
      final backup = File('${file.path}.legacy-recovery.enc');
      expect(await backup.exists(), isTrue);
      expect((await backup.readAsString()).contains(paidText), isFalse);
      expect(await File('${file.path}.encrypted-next').exists(), isFalse);
      final state = jsonDecode(
        await File('${file.path}.protection-state').readAsString(),
      );
      expect(state['state'], 'complete');
      expect(await factory.prepare(file), key);
    },
  );

  test(
    'pending native operation and durable attempt survive encryption and physical reopen',
    () async {
      var journal = NativeOperationJournal(
        executor: await factory.open(file),
        organizationId: org,
        actorId: actor,
      );
      await journal.prepare(
        requestId: request,
        type: 'checkout_sale',
        branchId: branch,
        payload: {'total_minor': 1250, 'reference': paidText},
      );
      await journal.markAttempted(requestId: request);
      await journal.close();
      journal = NativeOperationJournal(
        executor: await factory.open(file),
        organizationId: org,
        actorId: actor,
      );
      final pending = (await journal.pending()).single;
      expect(pending.requestId, request);
      expect(pending.attemptCount, 1);
      expect(pending.payload['reference'], paidText);
      await journal.close();
      expect(
        latin1.decode(await file.readAsBytes()).contains(paidText),
        isFalse,
      );
    },
  );

  test(
    'file corruption fails closed without changing its key or recreating schema',
    () async {
      await factory.prepare(file);
      final keyBefore = Map.of(store.values);
      final handle = await file.open(mode: FileMode.append);
      // Change an authenticated encrypted page byte without replacing the file.
      await handle.setPosition(120);
      await handle.writeByte(255);
      await handle.close();
      final damaged = await file.readAsBytes();
      await expectLater(
        factory.prepare(file),
        throwsA(isA<LocalDatabaseSecurityFailure>()),
      );
      expect(await file.readAsBytes(), damaged);
      expect(store.values, keyBefore);
    },
  );

  test(
    'tampered recovery archive blocks reopening and preserves the protected paid file',
    () async {
      final db = sqlite.sqlite3.open(file.path);
      db.execute('CREATE TABLE paid (reference TEXT)');
      db.execute('INSERT INTO paid VALUES (?)', [paidText]);
      db.close();
      await factory.prepare(file);
      final before = await file.readAsBytes();
      final archive = File('${file.path}.legacy-recovery.enc');
      final value =
          jsonDecode(await archive.readAsString()) as Map<String, dynamic>;
      value['mac'] = base64.encode(List.filled(16, 0));
      await archive.writeAsString(jsonEncode(value), flush: true);
      await expectLater(
        factory.prepare(file),
        throwsA(failure('RECOVERY_BACKUP_INVALID')),
      );
      expect(await file.readAsBytes(), before);
    },
  );

  test(
    'concurrent factories share one durable key and never reset the file',
    () async {
      final second = EncryptedDatabaseFactory(store: store);
      final keys = await Future.wait([
        factory.prepare(file),
        second.prepare(file),
      ]);
      expect(keys[0], keys[1]);
      expect(store.values.length, 1);
    },
  );
  test(
    'legacy native operation UUID, payload and attempts survive encrypted migration',
    () async {
      var journal = NativeOperationJournal(
        executor: NativeDatabase(file),
        organizationId: org,
        actorId: actor,
      );
      await journal.prepare(
        requestId: request,
        type: 'checkout_sale',
        branchId: branch,
        payload: {'total_minor': 1250, 'reference': paidText},
      );
      await journal.markAttempted(requestId: request);
      await journal.markAttempted(requestId: request);
      await journal.close();
      final original = await file.readAsBytes();
      journal = NativeOperationJournal(
        executor: await factory.open(file),
        organizationId: org,
        actorId: actor,
      );
      final pending = (await journal.pending()).single;
      expect(pending.requestId, request);
      expect(pending.attemptCount, 2);
      expect(pending.payload['reference'], paidText);
      await journal.close();
      final recovery = await factory.readLegacyRecovery(file);
      expect(recovery.files[''], original);
      expect(
        latin1.decode(await file.readAsBytes()).contains(paidText),
        isFalse,
      );
    },
  );

  test(
    'WAL-only committed paid rows migrate and exact original WAL is recoverable',
    () async {
      final seed = File('${directory.path}/seed.sqlite');
      final db = sqlite.sqlite3.open(seed.path);
      db.execute('PRAGMA journal_mode = WAL');
      db.execute('PRAGMA wal_autocheckpoint = 0');
      db.execute('CREATE TABLE paid (reference TEXT)');
      db.execute('INSERT INTO paid VALUES (?)', [paidText]);
      final main = await seed.readAsBytes();
      final wal = await File('${seed.path}-wal').readAsBytes();
      await file.writeAsBytes(main, flush: true);
      await File('${file.path}-wal').writeAsBytes(wal, flush: true);
      db.close();
      final key = await factory.prepare(file);
      final copy = protected(file, key);
      expect(copy.select('SELECT * FROM paid').single['reference'], paidText);
      copy.close();
      final recovery = await factory.readLegacyRecovery(file);
      expect(recovery.files[''], main);
      expect(recovery.files['-wal'], wal);
      expect(await File('${file.path}-wal').exists(), isFalse);
      expect(await File('${file.path}-shm').exists(), isFalse);
    },
  );

  test(
    'literal v1 Drift history is protected before additive upgrade',
    () async {
      final db = sqlite.sqlite3.open(file.path);
      db.execute(
        await File('test/database/fixtures/schema_v1.sql').readAsString(),
      );
      final original = await file.readAsBytes();
      db.close();
      final executor = await factory.open(file);
      final upgraded = AppDatabase(executor);
      await upgraded
          .customSelect('SELECT count(*) FROM offline_event_authorizations')
          .getSingle();
      final version = await upgraded
          .customSelect('PRAGMA user_version')
          .getSingle();
      expect(version.read<int>('user_version'), 2);
      await upgraded.close();
      final recovery = await factory.readLegacyRecovery(file);
      expect(recovery.files[''], original);
      expect(await factory.prepare(file), isNotEmpty);
    },
  );

  for (final checkpoint in ['ready', 'promoting', 'promoted']) {
    test(
      'interrupted migration at $checkpoint recovers the exact paid copy',
      () async {
        final db = sqlite.sqlite3.open(file.path);
        db.execute('CREATE TABLE paid (reference TEXT)');
        db.execute('INSERT INTO paid VALUES (?)', [paidText]);
        db.close();
        final legacy = await file.readAsBytes();
        final key = await factory.prepare(file);
        final stateFile = File('${file.path}.protection-state');
        final state =
            jsonDecode(await stateFile.readAsString()) as Map<String, dynamic>;
        state['state'] = checkpoint == 'ready' ? 'ready' : 'promoting';
        await stateFile.writeAsString(jsonEncode(state), flush: true);
        if (checkpoint != 'promoted') {
          await file.copy('${file.path}.encrypted-next');
          await file.delete();
          if (checkpoint == 'ready') {
            await file.writeAsBytes(legacy, flush: true);
          }
        }
        expect(await factory.prepare(file), key);
        final copy = protected(file, key);
        expect(copy.select('SELECT * FROM paid').single['reference'], paidText);
        copy.close();
        expect(jsonDecode(await stateFile.readAsString())['state'], 'complete');
        expect(await File('${file.path}.encrypted-next').exists(), isFalse);
      },
    );
  }

  test(
    'paid rows added to an interrupted plaintext source prevent stale promotion',
    () async {
      final db = sqlite.sqlite3.open(file.path);
      db.execute('CREATE TABLE paid (reference TEXT)');
      db.execute('INSERT INTO paid VALUES (?)', [paidText]);
      db.close();
      final legacy = await file.readAsBytes();
      await factory.prepare(file);
      await file.copy('${file.path}.encrypted-next');
      final stateFile = File('${file.path}.protection-state');
      final state =
          jsonDecode(await stateFile.readAsString()) as Map<String, dynamic>;
      await stateFile.writeAsString(jsonEncode({...state, 'state': 'ready'}));
      await file.writeAsBytes(legacy, flush: true);
      final source = sqlite.sqlite3.open(file.path);
      source.execute('INSERT INTO paid VALUES (?)', ['newly collected money']);
      source.close();
      final changed = await file.readAsBytes();
      await expectLater(
        factory.prepare(file),
        throwsA(failure('MIGRATION_SOURCE_CHANGED')),
      );
      expect(await file.readAsBytes(), changed);
      expect(await File('${file.path}.encrypted-next').exists(), isTrue);
    },
  );
  test(
    'production factory keeps temporary SQL data in memory and WAL pages encrypted',
    () async {
      final app = AppDatabase(await factory.open(file));
      expect(
        (await app.customSelect('PRAGMA temp_store').getSingle()).read<int>(
          'temp_store',
        ),
        2,
      );
      await app.customStatement('PRAGMA journal_mode = WAL');
      await app.customStatement('PRAGMA wal_autocheckpoint = 0');
      await app.customStatement(
        'CREATE TABLE payment_evidence_probe (reference TEXT)',
      );
      await app.customStatement(
        'INSERT INTO payment_evidence_probe VALUES (?)',
        [paidText],
      );
      final wal = File('${file.path}-wal');
      expect(await wal.exists(), isTrue);
      expect(
        latin1.decode(await wal.readAsBytes()).contains(paidText),
        isFalse,
      );
      expect(
        latin1.decode(await file.readAsBytes()).contains(paidText),
        isFalse,
      );
      await app.close();
      final reopened = AppDatabase(await factory.open(file));
      expect(
        (await reopened
                .customSelect('SELECT reference FROM payment_evidence_probe')
                .getSingle())
            .read<String>('reference'),
        paidText,
      );
      await reopened.close();
    },
  );
  test(
    'oversized legacy file fails closed before export and keeps source intact',
    () async {
      final db = sqlite.sqlite3.open(file.path);
      db.execute('CREATE TABLE paid (reference TEXT)');
      db.execute('INSERT INTO paid VALUES (?)', [paidText]);
      db.close();
      final header = (await file.readAsBytes()).take(16).toList();
      final handle = await file.open(mode: FileMode.append);
      await handle.truncate(128 * 1024 * 1024 + 1);
      await handle.close();
      final size = await file.length();
      await expectLater(
        factory.prepare(file),
        throwsA(failure('LEGACY_MIGRATION_TOO_LARGE')),
      );
      expect(await file.length(), size);
      final after = await file.open();
      expect(await after.read(16), header);
      await after.close();
      expect(await File('${file.path}.encrypted-next').exists(), isFalse);
      expect(await File('${file.path}.protection-state').exists(), isFalse);
    },
  );
}
