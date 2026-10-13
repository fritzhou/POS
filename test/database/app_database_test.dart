import 'dart:io';
import 'dart:convert';

import 'package:drift/drift.dart' hide isNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nexapos/core/database/app_database.dart';
import 'package:nexapos/core/sync/sync_event.dart';

final _scope = DatabaseScope(organizationId: 'org-a', branchId: 'branch-a');
final _otherBranch = DatabaseScope(
  organizationId: 'org-a',
  branchId: 'branch-b',
);
final _otherOrg = DatabaseScope(organizationId: 'org-b', branchId: 'branch-a');
final _now = DateTime.utc(2026, 1, 1, 12);

Future<void> _shift(AppDatabase db, DatabaseScope scope) => db
    .into(db.localShifts)
    .insert(
      LocalShiftsCompanion.insert(
        organizationId: scope.organizationId,
        branchId: scope.branchId,
        id: 'shift-1',
        deviceId: 'device-1',
        openedBy: 'user-1',
        openedAt: _now,
        openingCashMinor: 10000,
        currency: 'PHP',
      ),
    );

SaleDraft _sale({
  String id = 'sale-1',
  String? eventId,
  String? paymentId,
  String? receipt,
  DatabaseScope? scope,
  int amount = 4500,
  int quantity = 2,
  DateTime? observedAt,
  String paymentMethod = 'gcash',
}) => SaleDraft(
  id: id,
  eventId: eventId ?? newLocalId(),
  scope: scope ?? _scope,
  deviceId: 'device-1',
  shiftId: 'shift-1',
  cashierId: 'user-1',
  receiptNumber: receipt ?? 'branch-a-device-1-$id',
  currency: 'PHP',
  createdAt: observedAt ?? _now,
  items: [
    SaleLineDraft(
      id: '$id-line-1',
      productId: 'product-1',
      sku: 'COFFEE-1',
      name: 'Coffee snapshot',
      quantity: quantity,
      unitPriceMinor: 2500,
      discountMinor: 500,
    ),
  ],
  payments: [
    SalePaymentDraft(
      id: paymentId ?? '$id-payment-1',
      method: paymentMethod,
      amountMinor: amount,
      reference: 'operator-confirmed-reference',
    ),
  ],
);

void main() {
  late AppDatabase db;

  setUp(() {
    db = AppDatabase(NativeDatabase.memory());
  });

  tearDown(() async {
    await db.close();
  });

  test('sale snapshots, manual payments and outbox commit together', () async {
    await _shift(db, _scope);
    final draft = _sale();
    final sale = await db.persistSale(draft);
    expect(sale.totalMinor, 4500);
    expect(
      (await db.select(db.localSaleItems).get()).single.nameSnapshot,
      'Coffee snapshot',
    );
    final payment = (await db.select(db.localPayments).get()).single;
    expect(payment.verificationMode, 'manual');
    final outbox = (await db.listOutbox(_scope)).single;
    expect(outbox.status, 'PENDING');
    expect(outbox.payloadDigest, draft.toEvent().digest);
    expect(outbox.serverReceiptId, isNull);
    expect(await db.unsyncedCount(_scope), 1);
  });

  test(
    'Other manual payment retains reference in snapshot and event',
    () async {
      await _shift(db, _scope);
      await db.persistSale(_sale(paymentMethod: 'other'));
      final payment = (await db.select(db.localPayments).get()).single;
      expect(payment.method, 'other');
      expect(payment.verificationMode, 'manual');
      expect(payment.reference, 'operator-confirmed-reference');
      final event = (await db.listOutbox(_scope)).single;
      final payload = jsonDecode(event.payloadJson) as Map<String, dynamic>;
      final recorded =
          (payload['payments'] as List<dynamic>).single as Map<String, dynamic>;
      expect(recorded['method'], 'other');
      expect(recorded['verification_mode'], 'manual');
      expect(recorded['reference'], payment.reference);
    },
  );

  test(
    'late payment constraint failure rolls back header, lines and event',
    () async {
      await _shift(db, _scope);
      await db.persistSale(_sale(paymentId: 'already-used-payment'));
      await expectLater(
        db.persistSale(_sale(id: 'sale-2', paymentId: 'already-used-payment')),
        throwsA(isA<Exception>()),
      );
      expect((await db.listSales(_scope)).map((row) => row.id), ['sale-1']);
      expect(await db.select(db.localSaleItems).get(), hasLength(1));
      expect(await db.select(db.localPayments).get(), hasLength(1));
      expect(await db.listOutbox(_scope), hasLength(1));
    },
  );

  test(
    'stable duplicate event is idempotent; changed content is rejected',
    () async {
      await _shift(db, _scope);
      final draft = _sale();
      expect((await db.persistSale(draft)).id, 'sale-1');
      expect((await db.persistSale(draft)).id, 'sale-1');
      expect(await db.listOutbox(_scope), hasLength(1));
      await expectLater(
        db.persistSale(
          _sale(eventId: draft.eventId, receipt: 'changed-receipt'),
        ),
        throwsA(isA<EventConflict>()),
      );
      expect(
        (await db.listSales(_scope)).single.receiptNumber,
        draft.receiptNumber,
      );
    },
  );

  test(
    'invalid money and quantities cannot write any local transaction',
    () async {
      await _shift(db, _scope);
      await expectLater(
        db.persistSale(_sale(amount: 4499)),
        throwsA(isA<ArgumentError>()),
      );
      await expectLater(
        db.persistSale(_sale(quantity: 0)),
        throwsA(isA<ArgumentError>()),
      );
      expect(await db.listSales(_scope), isEmpty);
      expect(await db.listOutbox(_scope), isEmpty);
    },
  );

  test(
    'reads and foreign keys retain organization and branch boundaries',
    () async {
      await _shift(db, _scope);
      await db.persistSale(_sale());
      expect(await db.listSales(_otherBranch), isEmpty);
      expect(await db.listOutbox(_otherOrg), isEmpty);
      await expectLater(
        db.persistSale(_sale(id: 'foreign-branch-sale', scope: _otherBranch)),
        throwsA(isA<Exception>()),
      );
      await _shift(db, _otherBranch);
      await db.persistSale(_sale(scope: _otherBranch));
      expect(await db.listSales(_scope), hasLength(1));
      expect(await db.listSales(_otherBranch), hasLength(1));
    },
  );

  test('financial records and outbox event content are append-only', () async {
    await _shift(db, _scope);
    await db.persistSale(_sale());
    await expectLater(
      db
          .update(db.localSales)
          .write(const LocalSalesCompanion(receiptNumber: Value('edited'))),
      throwsA(isA<Exception>()),
    );
    await expectLater(
      db.delete(db.localSaleItems).go(),
      throwsA(isA<Exception>()),
    );
    await expectLater(
      db
          .update(db.syncOutbox)
          .write(
            const SyncOutboxCompanion(payloadJson: Value('{"changed":true}')),
          ),
      throwsA(isA<Exception>()),
    );
    await expectLater(db.delete(db.syncOutbox).go(), throwsA(isA<Exception>()));
    expect(await db.listSales(_scope), hasLength(1));
    expect(await db.listOutbox(_scope), hasLength(1));
  });

  test('SQLite REPLACE cannot bypass append-only delete triggers', () async {
    await _shift(db, _scope);
    final sale = await db.persistSale(_sale());
    final event = (await db.listOutbox(_scope)).single;
    await expectLater(
      db.into(db.localSales).insert(sale, mode: InsertMode.insertOrReplace),
      throwsA(isA<Exception>()),
    );
    await expectLater(
      db.into(db.syncOutbox).insert(event, mode: InsertMode.insertOrReplace),
      throwsA(isA<Exception>()),
    );
    expect(await db.listSales(_scope), hasLength(1));
    expect(await db.listOutbox(_scope), hasLength(1));
  });

  test('completed sale cannot gain extra item or payment snapshots', () async {
    await _shift(db, _scope);
    await db.persistSale(_sale());
    final item = (await db.select(db.localSaleItems).get()).single;
    final payment = (await db.select(db.localPayments).get()).single;
    await expectLater(
      db.into(db.localSaleItems).insert(item.copyWith(id: 'extra-line')),
      throwsA(isA<Exception>()),
    );
    await expectLater(
      db.into(db.localPayments).insert(payment.copyWith(id: 'extra-payment')),
      throwsA(isA<Exception>()),
    );
    expect(await db.select(db.localSaleItems).get(), hasLength(1));
    expect(await db.select(db.localPayments).get(), hasLength(1));
  });

  test(
    'overflowing quantity-price products are rejected before integer wrap',
    () {
      const line = SaleLineDraft(
        id: 'line',
        productId: 'product',
        sku: 'SKU',
        name: 'Unsafe price',
        quantity: 4294967296,
        unitPriceMinor: 4294967296,
      );
      expect(line.validate, throwsArgumentError);
    },
  );

  test('cache batch and cursor commit or roll back together', () async {
    Future<void> cacheProduct(String id) => db
        .into(db.localProducts)
        .insert(
          LocalProductsCompanion.insert(
            organizationId: _scope.organizationId,
            branchId: _scope.branchId,
            id: id,
            sku: id,
            name: 'Cached product',
            currency: 'PHP',
            costMinor: 1500,
            priceMinor: 2500,
            revision: 1,
          ),
        );
    await db.applyPullBatch(
      scope: _scope,
      feed: 'catalog',
      cursor: 'server-cursor-1',
      now: _now,
      applyChanges: () => cacheProduct('product-1'),
    );
    await expectLater(
      db.applyPullBatch(
        scope: _scope,
        feed: 'catalog',
        cursor: 'server-cursor-2',
        now: _now,
        applyChanges: () async {
          await cacheProduct('product-2');
          throw StateError('Rejected pull batch');
        },
      ),
      throwsStateError,
    );
    expect(await db.listProducts(_scope), hasLength(1));
    expect((await db.readCursor(_scope, 'catalog'))?.cursor, 'server-cursor-1');
    expect(await db.readCursor(_otherBranch, 'catalog'), isNull);
  });

  test('sale and claimed outbox survive physical close/reopen', () async {
    final directory = await Directory.systemTemp.createTemp(
      'nexapos-durability-',
    );
    final file = File('${directory.path}/local.sqlite');
    await db.close();
    db = AppDatabase(NativeDatabase(file));
    try {
      await _shift(db, _scope);
      final draft = _sale(
        observedAt: DateTime.utc(2026, 1, 1, 12, 0, 0, 123, 456),
      );
      await db.persistSale(draft);
      final original = await db.claimNextEvent(
        scope: _scope,
        workerId: 'worker-before-crash',
        now: _now,
        leaseDuration: const Duration(seconds: 10),
      );
      await db.close();
      db = AppDatabase(NativeDatabase(file));
      expect((await db.listSales(_scope)).single.totalMinor, 4500);
      expect((await db.listOutbox(_scope)).single.status, 'SYNCING');
      final recovered = await db.claimNextEvent(
        scope: _scope,
        workerId: 'worker-after-restart',
        now: _now.add(const Duration(seconds: 11)),
      );
      expect(recovered?.eventId, original?.eventId);
      expect(recovered?.attempt, 2);
      expect(recovered?.token, isNot(original?.token));
      expect(
        (await db.listOutbox(_scope)).single.payloadDigest,
        draft.toEvent().digest,
      );
      final stored = (await db.listOutbox(_scope)).single;
      expect(stored.occurredAtIso, '2026-01-01T12:00:00.123456Z');
      final reconstructed = SyncEvent(
        eventId: stored.id,
        organizationId: stored.organizationId,
        branchId: stored.branchId,
        deviceId: stored.deviceId,
        actorId: stored.actorId,
        eventType: stored.eventType,
        occurredAt: DateTime.parse(stored.occurredAtIso),
        schemaVersion: stored.schemaVersion,
        payload: jsonDecode(stored.payloadJson) as Map<String, Object?>,
      );
      expect(reconstructed.digest, stored.payloadDigest);
    } finally {
      await db.close();
      // tearDown still owns a fresh in-memory instance, avoiding double close.
      db = AppDatabase(NativeDatabase.memory());
      await directory.delete(recursive: true);
    }
  });
}
