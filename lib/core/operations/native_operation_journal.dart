import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:drift/drift.dart';
import 'package:path/path.dart' as path;
import 'package:path_provider/path_provider.dart';

import '../auth/secure_session_storage.dart';
import '../security/local_database_security.dart';
import '../sync/sync_event.dart' show canonicalJson;
import 'operation_journal.dart';

/// Separate from Phase 1 financial/outbox storage: a pending intent is not a
/// completed sale, a synchronized event or permission to transact offline.
class NativeOperationJournal implements OperationJournal {
  NativeOperationJournal({
    required QueryExecutor executor,
    required String organizationId,
    required String actorId,
  }) : organizationId = organizationId.toLowerCase(),
       actorId = actorId.toLowerCase(),
       _database = _JournalDatabase(executor) {
    _validateId(organizationId);
    _validateId(actorId);
  }

  factory NativeOperationJournal.openNative({
    required String organizationId,
    required String actorId,
    SecretStore? store,
  }) => NativeOperationJournal(
    organizationId: organizationId,
    actorId: actorId,
    executor: LazyDatabase(() async {
      final directory = await getApplicationSupportDirectory();
      await directory.create(recursive: true);
      final key = sha256.convert(
        utf8.encode(
          jsonEncode([organizationId.toLowerCase(), actorId.toLowerCase()]),
        ),
      );
      return EncryptedDatabaseFactory(
        store: store ?? PlatformSecretStore(),
      ).open(File(path.join(directory.path, 'nexapos_operations_$key.sqlite')));
    }),
  );

  final String organizationId;
  final String actorId;
  final _JournalDatabase _database;

  static void _validateId(String id) {
    if (!RegExp(
      r'^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$',
    ).hasMatch(id)) {
      throw const OperationJournalFailure('The request scope is invalid.');
    }
  }

  String _encode(Map<String, dynamic> value) {
    try {
      return canonicalJson(value);
    } on Object {
      throw const OperationJournalFailure(
        'The request contains unsupported values.',
      );
    }
  }

  String _digest(
    String requestId,
    String branchId,
    String type,
    String payloadJson,
  ) => sha256
      .convert(
        utf8.encode(
          canonicalJson({
            'request_id': requestId,
            'organization_id': organizationId,
            'actor_id': actorId,
            'branch_id': branchId,
            'type': type,
            'payload': jsonDecode(payloadJson),
          }),
        ),
      )
      .toString();

  PendingOperation _decode(QueryRow row) {
    try {
      final payloadJson = row.read<String>('payload_json');
      if (row.read<String>('payload_digest') !=
          _digest(
            row.read<String>('request_id'),
            row.read<String>('branch_id'),
            row.read<String>('operation_type'),
            payloadJson,
          )) {
        throw const OperationJournalFailure(
          'The saved request could not be verified. Preserve the journal and contact your administrator.',
        );
      }
      return PendingOperation(
        requestId: row.read<String>('request_id'),
        organizationId: row.read<String>('organization_id'),
        branchId: row.read<String>('branch_id'),
        actorId: row.read<String>('actor_id'),
        type: row.read<String>('operation_type'),
        payload: jsonDecode(payloadJson) as Map<String, dynamic>,
        createdAt: DateTime.parse(row.read<String>('created_at')),
        status: LocalOperationStatus.values.byName(row.read<String>('status')),
        attemptCount: row.read<int>('attempt_count'),
        result: row.readNullable<String>('result_json') == null
            ? null
            : jsonDecode(row.read<String>('result_json'))
                  as Map<String, dynamic>,
        failureCode: row.readNullable<String>('failure_code'),
      );
    } on OperationJournalFailure {
      rethrow;
    } on Object {
      throw const OperationJournalFailure(
        'The saved request could not be read. Preserve the journal and contact your administrator.',
      );
    }
  }

  Future<PendingOperation?> _find(String requestId) async {
    requestId = requestId.toLowerCase();
    final row = await _database
        .customSelect(
          'SELECT * FROM operation_journal WHERE organization_id = ? AND actor_id = ? AND request_id = ?',
          variables: [
            Variable(organizationId),
            Variable(actorId),
            Variable(requestId),
          ],
        )
        .getSingleOrNull();
    return row == null ? null : _decode(row);
  }

  @override
  Future<PendingOperation> prepare({
    required String requestId,
    required String type,
    required String branchId,
    required Map<String, dynamic> payload,
  }) async {
    requestId = requestId.toLowerCase();
    branchId = branchId.toLowerCase();
    _validateId(requestId);
    _validateId(branchId);
    if (!RegExp(r'^[a-z][a-z0-9_]{2,79}$').hasMatch(type)) {
      throw const OperationJournalFailure('The request type is invalid.');
    }
    final encoded = _encode(payload);
    if (utf8.encode(encoded).length > 262144) {
      throw const OperationJournalFailure('The request is too large.');
    }
    final digest = _digest(requestId, branchId, type, encoded);
    await _database.customStatement(
      '''INSERT INTO operation_journal
      (organization_id, actor_id, request_id, branch_id, operation_type, payload_json, payload_digest, created_at, status)
      VALUES (?, ?, ?, ?, ?, ?, ?, ?, 'pending') ON CONFLICT(organization_id,actor_id,request_id) DO NOTHING''',
      [
        organizationId,
        actorId,
        requestId,
        branchId,
        type,
        encoded,
        digest,
        DateTime.now().toUtc().toIso8601String(),
      ],
    );
    final stored = await _find(requestId);
    if (stored == null ||
        stored.branchId != branchId ||
        stored.type != type ||
        _encode(stored.payload) != encoded) {
      throw const OperationJournalFailure(
        'This request ID already has different details. Reconcile the saved request first.',
      );
    }
    return stored;
  }

  @override
  Future<List<PendingOperation>> pending({
    String? type,
    String? branchId,
  }) async {
    branchId = branchId?.toLowerCase();
    if (branchId != null) _validateId(branchId);
    final rows = await _database
        .customSelect(
          '''SELECT * FROM operation_journal WHERE organization_id = ? AND actor_id = ? AND status = 'pending'
      AND (? IS NULL OR operation_type = ?) AND (? IS NULL OR branch_id = ?)
      ORDER BY created_at, request_id''',
          variables: [
            Variable(organizationId),
            Variable(actorId),
            Variable(type),
            Variable(type),
            Variable(branchId),
            Variable(branchId),
          ],
        )
        .get();
    return rows.map(_decode).toList(growable: false);
  }

  @override
  Future<int> markAttempted({required String requestId}) async {
    requestId = requestId.toLowerCase();
    final row = await _database
        .customSelect(
          "UPDATE operation_journal SET attempt_count=attempt_count+1 WHERE organization_id=? AND actor_id=? AND request_id=? AND status='pending' RETURNING attempt_count",
          variables: [
            Variable(organizationId),
            Variable(actorId),
            Variable(requestId),
          ],
        )
        .getSingleOrNull();
    if (row == null) {
      throw const OperationJournalFailure(
        'The saved request cannot be submitted again.',
      );
    }
    return row.read<int>('attempt_count');
  }

  @override
  Future<void> confirm({
    required String requestId,
    required Map<String, dynamic> result,
  }) async {
    requestId = requestId.toLowerCase();
    final encoded = _encode(result);
    await _database.transaction(() async {
      final operation = await _find(requestId);
      if (operation == null ||
          operation.status == LocalOperationStatus.rejected) {
        throw const OperationJournalFailure(
          'The saved request cannot be confirmed.',
        );
      }
      if (operation.status == LocalOperationStatus.confirmed) {
        if (_encode(operation.result!) != encoded) {
          throw const OperationJournalFailure(
            'The saved server result does not match.',
          );
        }
        return;
      }
      await _database.customStatement(
        "UPDATE operation_journal SET status='confirmed', result_json=? WHERE organization_id=? AND actor_id=? AND request_id=? AND status='pending'",
        [encoded, organizationId, actorId, requestId],
      );
    });
  }

  @override
  Future<void> reject({
    required String requestId,
    required String failureCode,
  }) async {
    requestId = requestId.toLowerCase();
    const unsignedPreparationExpired = 'offline_preparation_expired';
    if (!RegExp(r'^[A-Z0-9_]{1,40}$').hasMatch(failureCode) &&
        failureCode != unsignedPreparationExpired) {
      throw const OperationJournalFailure('The failure code is invalid.');
    }
    await _database.transaction(() async {
      final operation = await _find(requestId);
      // Only the trusted Edge NX002 outcome proves an expired unsigned,
      // zero-event reservation never conferred financial authority. A paid
      // operation can never use this exception, even with the same code.
      final definitiveUnsignedPreparation =
          operation?.type == 'offline_prepare' &&
          failureCode == unsignedPreparationExpired &&
          operation!.attemptCount >= 1;
      if (operation == null ||
          operation.status == LocalOperationStatus.confirmed ||
          (operation.attemptCount != 1 && !definitiveUnsignedPreparation)) {
        throw const OperationJournalFailure(
          'An uncertain request cannot be marked as rejected.',
        );
      }
      if (operation.status == LocalOperationStatus.rejected) return;
      await _database.customStatement(
        "UPDATE operation_journal SET status='rejected', failure_code=? WHERE organization_id=? AND actor_id=? AND request_id=? AND status='pending'",
        [failureCode, organizationId, actorId, requestId],
      );
    });
  }

  bool _closed = false;
  @override
  Future<void> close() async {
    if (_closed) return;
    _closed = true;
    await _database.close();
  }
}

class _JournalDatabase extends GeneratedDatabase {
  _JournalDatabase(super.executor);
  @override
  int get schemaVersion => 1;
  @override
  Iterable<TableInfo<Table, Object?>> get allTables => const [];
  @override
  List<DatabaseSchemaEntity> get allSchemaEntities => const [];
  @override
  MigrationStrategy get migration => MigrationStrategy(
    onCreate: (_) async {
      await customStatement('''CREATE TABLE operation_journal (
        organization_id TEXT NOT NULL, actor_id TEXT NOT NULL, request_id TEXT NOT NULL,
        branch_id TEXT NOT NULL, operation_type TEXT NOT NULL, payload_json TEXT NOT NULL,
        payload_digest TEXT NOT NULL, created_at TEXT NOT NULL,
        status TEXT NOT NULL CHECK(status IN ('pending','confirmed','rejected')),
        result_json TEXT, failure_code TEXT, attempt_count INTEGER NOT NULL DEFAULT 0 CHECK(attempt_count >= 0),
        PRIMARY KEY(organization_id,actor_id,request_id),
        CHECK((status='pending' AND result_json IS NULL AND failure_code IS NULL)
          OR (status='confirmed' AND result_json IS NOT NULL AND failure_code IS NULL)
          OR (status='rejected' AND result_json IS NULL AND failure_code IS NOT NULL))
      )''');
      await customStatement(
        '''CREATE TRIGGER operation_content_immutable BEFORE UPDATE ON operation_journal
        WHEN NEW.organization_id != OLD.organization_id OR NEW.actor_id != OLD.actor_id
          OR NEW.request_id != OLD.request_id OR NEW.branch_id != OLD.branch_id
          OR NEW.operation_type != OLD.operation_type OR NEW.payload_json != OLD.payload_json
          OR NEW.payload_digest != OLD.payload_digest OR NEW.created_at != OLD.created_at
          OR OLD.status != 'pending' OR NEW.attempt_count < OLD.attempt_count
          OR NEW.attempt_count > OLD.attempt_count + 1
        BEGIN SELECT RAISE(ABORT, 'Operation history is immutable'); END''',
      );
      await customStatement(
        '''CREATE TRIGGER operation_no_delete BEFORE DELETE ON operation_journal
        BEGIN SELECT RAISE(ABORT, 'Operation history must be preserved'); END''',
      );
    },
    beforeOpen: (_) async {
      await customStatement('PRAGMA recursive_triggers = ON');
      await customStatement('PRAGMA busy_timeout = 5000');
      await customStatement('PRAGMA synchronous = FULL');
    },
  );
}
