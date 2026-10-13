import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nexapos/core/operations/native_operation_journal.dart';
import 'package:nexapos/core/operations/operation_journal.dart';
import 'package:sqlite3/sqlite3.dart' as sqlite;

const org = 'a0000000-0000-4000-8000-000000000001';
const actor = 'a0000000-0000-4000-8000-000000000002';
const branch = 'a0000000-0000-4000-8000-000000000003';
const request = 'a0000000-0000-4000-8000-000000000004';
Map<String, dynamic> payload() => {
  'p_request_id': request,
  'p_branch_id': branch,
  'p_values': {
    'items': [
      {'product_id': 'a0000000-0000-4000-8000-000000000005', 'quantity': 1},
    ],
    'total_minor': 1250,
  },
};

Future<PendingOperation> prepare(
  NativeOperationJournal journal, {
  String id = request,
  Map<String, dynamic>? body,
}) => journal.prepare(
  requestId: id,
  type: 'checkout_sale',
  branchId: branch,
  payload: body ?? payload(),
);

void main() {
  test(
    'only exact unsigned preparation expiry closes a multi-attempt reservation',
    () async {
      final journal = NativeOperationJournal(
        executor: NativeDatabase.memory(),
        organizationId: org,
        actorId: actor,
      );
      addTearDown(journal.close);
      final devicePayload = {
        'device_id': 'a0000000-0000-4000-8000-000000000008',
      };
      await journal.prepare(
        requestId: request,
        type: 'offline_prepare',
        branchId: branch,
        payload: devicePayload,
      );
      await journal.markAttempted(requestId: request);
      await journal.markAttempted(requestId: request);
      await expectLater(
        journal.reject(requestId: request, failureCode: '40001'),
        throwsA(isA<OperationJournalFailure>()),
      );
      await journal.reject(
        requestId: request,
        failureCode: 'offline_preparation_expired',
      );
      expect(await journal.pending(), isEmpty);
      final archived = await journal.prepare(
        requestId: request,
        type: 'offline_prepare',
        branchId: branch,
        payload: devicePayload,
      );
      expect(archived.status, LocalOperationStatus.rejected);
      expect(archived.attemptCount, 2);
      expect(archived.failureCode, 'offline_preparation_expired');
      const paidRequest = 'a0000000-0000-4000-8000-000000000009';
      await prepare(journal, id: paidRequest);
      await journal.markAttempted(requestId: paidRequest);
      await journal.markAttempted(requestId: paidRequest);
      await expectLater(
        journal.reject(
          requestId: paidRequest,
          failureCode: 'offline_preparation_expired',
        ),
        throwsA(isA<OperationJournalFailure>()),
      );
      expect((await journal.pending()).single.requestId, paidRequest);
    },
  );
  test(
    'an uncertain request and attempt count survive physical close/reopen',
    () async {
      final directory = await Directory.systemTemp.createTemp(
        'nexapos-journal-test-',
      );
      addTearDown(() => directory.delete(recursive: true));
      final file = File('${directory.path}/journal.sqlite');
      var journal = NativeOperationJournal(
        executor: NativeDatabase(file),
        organizationId: org,
        actorId: actor,
      );
      await prepare(journal);
      expect(await journal.markAttempted(requestId: request), 1);
      await journal.close();
      journal = NativeOperationJournal(
        executor: NativeDatabase(file),
        organizationId: org,
        actorId: actor,
      );
      addTearDown(journal.close);
      final saved = (await journal.pending()).single;
      expect(saved.requestId, request);
      expect(saved.payload, payload());
      expect(saved.attemptCount, 1);
      expect(await journal.markAttempted(requestId: request), 2);
      await expectLater(
        journal.reject(requestId: request, failureCode: '42501'),
        throwsA(isA<OperationJournalFailure>()),
      );
      expect((await journal.pending()).single.attemptCount, 2);
      await journal.confirm(
        requestId: request,
        result: {'id': 'actual-server-sale', 'receipt_number': 'MAIN-0001'},
      );
      expect(await journal.pending(), isEmpty);
    },
  );

  test('request content is immutable and nested values are frozen', () async {
    final journal = NativeOperationJournal(
      executor: NativeDatabase.memory(),
      organizationId: org,
      actorId: actor,
    );
    addTearDown(journal.close);
    final original = payload();
    final saved = await prepare(journal, body: original);
    (original['p_values'] as Map)['total_minor'] = 9000;
    expect((saved.payload['p_values'] as Map)['total_minor'], 1250);
    expect(
      () => (saved.payload['p_values'] as Map)['total_minor'] = 9000,
      throwsUnsupportedError,
    );
    expect(
      () => ((saved.payload['p_values'] as Map)['items'] as List).add({}),
      throwsUnsupportedError,
    );
    await expectLater(
      prepare(journal, body: original),
      throwsA(isA<OperationJournalFailure>()),
    );
    expect((await journal.pending()).single.payload, payload());
  });

  test(
    'equivalent JSON key ordering and UUID case use the same request',
    () async {
      final journal = NativeOperationJournal(
        executor: NativeDatabase.memory(),
        organizationId: org.toUpperCase(),
        actorId: actor.toUpperCase(),
      );
      addTearDown(journal.close);
      await prepare(journal, id: request.toUpperCase());
      final stored = await journal.prepare(
        requestId: request,
        type: 'checkout_sale',
        branchId: branch.toUpperCase(),
        payload: payload(),
      );
      expect(stored.organizationId, org);
      expect(stored.actorId, actor);
      expect(stored.branchId, branch);
      expect(stored.requestId, request);
      expect(
        await journal.pending(branchId: branch.toUpperCase()),
        hasLength(1),
      );
    },
  );

  test(
    'definitive first-attempt rollback is preserved as rejected history',
    () async {
      final journal = NativeOperationJournal(
        executor: NativeDatabase.memory(),
        organizationId: org,
        actorId: actor,
      );
      addTearDown(journal.close);
      await prepare(journal);
      await journal.markAttempted(requestId: request);
      await journal.reject(requestId: request, failureCode: '40001');
      expect(await journal.pending(), isEmpty);
      final stored = await prepare(journal);
      expect(stored.status, LocalOperationStatus.rejected);
      expect(stored.failureCode, '40001');
      await expectLater(
        journal.markAttempted(requestId: request),
        throwsA(isA<OperationJournalFailure>()),
      );
      await expectLater(
        journal.confirm(requestId: request, result: {'id': 'fabricated'}),
        throwsA(isA<OperationJournalFailure>()),
      );
    },
  );

  test('confirmation cannot be changed into another server receipt', () async {
    final journal = NativeOperationJournal(
      executor: NativeDatabase.memory(),
      organizationId: org,
      actorId: actor,
    );
    addTearDown(journal.close);
    await prepare(journal);
    await journal.markAttempted(requestId: request);
    await journal.confirm(requestId: request, result: {'id': 'receipt-one'});
    await journal.confirm(requestId: request, result: {'id': 'receipt-one'});
    await expectLater(
      journal.confirm(requestId: request, result: {'id': 'receipt-two'}),
      throwsA(isA<OperationJournalFailure>()),
    );
    expect((await prepare(journal)).result, {'id': 'receipt-one'});
  });

  test(
    'shared physical file cannot expose another actor or organization',
    () async {
      final directory = await Directory.systemTemp.createTemp(
        'nexapos-journal-scope-',
      );
      addTearDown(() => directory.delete(recursive: true));
      final file = File('${directory.path}/journal.sqlite');
      final first = NativeOperationJournal(
        executor: NativeDatabase(file),
        organizationId: org,
        actorId: actor,
      );
      await prepare(first);
      await first.close();
      final second = NativeOperationJournal(
        executor: NativeDatabase(file),
        organizationId: org,
        actorId: 'b0000000-0000-4000-8000-000000000002',
      );
      expect(await second.pending(), isEmpty);
      await second.close();
      final third = NativeOperationJournal(
        executor: NativeDatabase(file),
        organizationId: 'b0000000-0000-4000-8000-000000000001',
        actorId: actor,
      );
      expect(await third.pending(), isEmpty);
      await third.close();
    },
  );

  test(
    'concurrent marker calls allocate distinct durable attempt numbers',
    () async {
      final journal = NativeOperationJournal(
        executor: NativeDatabase.memory(),
        organizationId: org,
        actorId: actor,
      );
      addTearDown(journal.close);
      await prepare(journal);
      final attempts = await Future.wait([
        journal.markAttempted(requestId: request),
        journal.markAttempted(requestId: request),
      ]);
      expect(attempts..sort(), [1, 2]);
      await expectLater(
        journal.reject(requestId: request, failureCode: '42501'),
        throwsA(isA<OperationJournalFailure>()),
      );
      expect(await journal.pending(), hasLength(1));
    },
  );

  test('raw SQLite updates, deletes and replacement preserve history', () async {
    final directory = await Directory.systemTemp.createTemp(
      'nexapos-journal-history-',
    );
    addTearDown(() => directory.delete(recursive: true));
    final file = File('${directory.path}/journal.sqlite');
    final journal = NativeOperationJournal(
      executor: NativeDatabase(file),
      organizationId: org,
      actorId: actor,
    );
    await prepare(journal);
    await journal.close();
    final raw = sqlite.sqlite3.open(file.path);
    addTearDown(raw.close);
    raw.execute('PRAGMA recursive_triggers = ON');
    for (final statement in [
      "UPDATE operation_journal SET payload_json='{}'",
      'DELETE FROM operation_journal',
      'INSERT OR REPLACE INTO operation_journal SELECT * FROM operation_journal',
    ]) {
      expect(
        () => raw.execute(statement),
        throwsA(isA<sqlite.SqliteException>()),
      );
    }
    expect(
      raw
          .select('SELECT count(*) AS count FROM operation_journal')
          .single['count'],
      1,
    );
    raw.execute(
      "UPDATE operation_journal SET status='confirmed',result_json='{}'",
    );
    expect(
      () => raw.execute(
        "UPDATE operation_journal SET result_json='{\"id\":\"replacement\"}'",
      ),
      throwsA(isA<sqlite.SqliteException>()),
    );
  });

  test(
    'corrupt restored content fails closed without deleting the request',
    () async {
      final directory = await Directory.systemTemp.createTemp(
        'nexapos-journal-corruption-',
      );
      addTearDown(() => directory.delete(recursive: true));
      final file = File('${directory.path}/journal.sqlite');
      var journal = NativeOperationJournal(
        executor: NativeDatabase(file),
        organizationId: org,
        actorId: actor,
      );
      await prepare(journal);
      await journal.close();
      final raw = sqlite.sqlite3.open(file.path);
      // Deliberately damage a test copy to represent an invalid restoration.
      raw.execute('DROP TRIGGER operation_content_immutable');
      raw.execute("UPDATE operation_journal SET payload_json='{}'");
      raw.close();
      journal = NativeOperationJournal(
        executor: NativeDatabase(file),
        organizationId: org,
        actorId: actor,
      );
      addTearDown(journal.close);
      await expectLater(
        journal.pending(),
        throwsA(isA<OperationJournalFailure>()),
      );
      final inspection = sqlite.sqlite3.open(file.path);
      addTearDown(inspection.close);
      expect(
        inspection
            .select('SELECT count(*) AS count FROM operation_journal')
            .single['count'],
        1,
      );
    },
  );
}
