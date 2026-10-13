import 'dart:convert';
import 'dart:io';

import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nexapos/core/database/app_database.dart';
import 'package:sqlite3/sqlite3.dart' as raw;

final _scope = DatabaseScope(organizationId: 'org-a', branchId: 'branch-a');
final _now = DateTime.utc(2026, 10, 10, 12, 0, 0, 123, 456);
const _actor = 'actor-a';
const _device = 'device-a';
const _grant = 'grant-a';
const _product = 'product-a';
const _event1 = 'a0000000-0000-4000-8000-000000000001';
const _event2 = 'a0000000-0000-4000-8000-000000000002';

OfflineShiftSnapshot _shift({String actor = _actor, String device = _device}) =>
    OfflineShiftSnapshot(
      scope: _scope,
      id: 'shift-a',
      actorId: actor,
      deviceId: device,
      currency: 'PHP',
      openedAt: _now.subtract(const Duration(minutes: 5)),
      openingCashMinor: 1000,
    );

SaleDraft _sale({
  String id = 'sale-a',
  String event = _event1,
  int quantity = 1,
  String paymentId = 'payment-a',
  String method = 'cash',
  String? reference,
  String currency = 'PHP',
  String actor = _actor,
  String device = _device,
  DateTime? observedAt,
}) => SaleDraft(
  id: id,
  eventId: event,
  scope: _scope,
  deviceId: device,
  shiftId: 'shift-a',
  cashierId: actor,
  receiptNumber: 'LOCAL-$id',
  currency: currency,
  createdAt: observedAt ?? _now,
  items: [
    SaleLineDraft(
      id: 'line-$id',
      productId: _product,
      sku: 'SKU-A',
      name: 'Item A',
      quantity: quantity,
      unitPriceMinor: 100,
    ),
  ],
  payments: [
    SalePaymentDraft(
      id: paymentId,
      method: method,
      amountMinor: 100 * quantity,
      reference: reference,
    ),
  ],
);

OfflineAuthorization _authorization(
  SaleDraft sale, {
  int sequence = 1,
  String signature = 'signed-device-proof',
  Map<String, Object?>? evidence,
}) => OfflineAuthorization(
  organizationId: sale.scope.organizationId,
  branchId: sale.scope.branchId,
  actorId: sale.cashierId,
  deviceId: sale.deviceId,
  eventId: sale.eventId,
  grantId: _grant,
  sequence: sequence,
  paymentEvidence:
      evidence ??
      {
        for (final payment in sale.payments)
          payment.id: payment.method == 'cash'
              ? {'tendered_minor': payment.amountMinor}
              : {'manual_confirmed': true},
      },
  signature: signature,
);

OfflineCacheBatch _batch({
  int quantity = 10,
  int revision = 10,
  int? stockRevision,
  String cursor = '10',
  bool preparation = false,
  List<OfflineCacheChange>? changes,
}) => OfflineCacheBatch(
  cursor: cursor,
  serverTime: _now,
  completeSnapshot: preparation,
  grantId: preparation ? _grant : null,
  changes:
      changes ??
      [
        OfflineCacheChange(
          kind: 'stock',
          id: _product,
          revision: revision,
          deleted: false,
          value: {
            'product_id': _product,
            'quantity': quantity,
            'revision': stockRevision ?? revision,
          },
        ),
      ],
);

Future<void> _prepare(AppDatabase db) => db.persistOfflinePreparation(
  scope: _scope,
  actorId: _actor,
  deviceId: _device,
  grantId: _grant,
  grantWire: {
    'claims': {'grant_id': _grant},
    'signature': 'verified-test-grant',
  },
  snapshot: {
    'context': {'currency': 'PHP'},
    'products': [],
  },
  batch: _batch(preparation: true),
  now: _now,
);

Future<SaleRow> _capture(
  AppDatabase db,
  SaleDraft sale, {
  int sequence = 1,
  int maxEvents = 1000,
  int maxTotalMinor = 100000000,
  OfflineAuthorization? authorization,
}) => db.persistAuthorizedSale(
  draft: sale,
  authorization: authorization ?? _authorization(sale, sequence: sequence),
  shift: _shift(),
  maxEvents: maxEvents,
  maxTotalMinor: maxTotalMinor,
);

Future<OutboxLease?> _claim(
  AppDatabase db, {
  DateTime? now,
  String actor = _actor,
  String device = _device,
  String worker = 'worker',
  Duration duration = const Duration(minutes: 1),
}) => db.claimNextAuthorizedEvent(
  scope: _scope,
  actorId: actor,
  deviceId: device,
  workerId: worker,
  now: now ?? _now,
  leaseDuration: duration,
);

Future<void> _accept(
  AppDatabase db,
  OutboxLease lease, {
  int revision = 11,
  List<OfflineStockImpact>? impacts,
  DateTime? now,
}) => db.recordAcceptance(
  lease: lease,
  acceptance: ServerAcceptance(
    eventId: lease.eventId,
    digest: lease.digest,
    serverReceiptId: 'SERVER-${lease.eventId}',
    acceptedAt: _now,
  ),
  actorId: _actor,
  deviceId: _device,
  grantId: _grant,
  sequence: lease.eventId == _event1 ? 1 : 2,
  documentId: lease.eventId == _event1 ? 'sale-a' : 'sale-b',
  receipt: {'id': lease.eventId, 'total_minor': 100},
  stockImpacts:
      impacts ?? [OfflineStockImpact(productId: _product, revision: revision)],
  now: now ?? _now,
);

Future<int?> _quantity(AppDatabase db) => db.projectedQuantity(
  scope: _scope,
  actorId: _actor,
  deviceId: _device,
  productId: _product,
);

void main() {
  late AppDatabase db;
  setUp(() async {
    db = AppDatabase(NativeDatabase.memory());
    await _prepare(db);
  });
  tearDown(() => db.close());

  test(
    'preexisting legacy event cannot acquire a new authorization envelope',
    () async {
      final sale = _sale();
      final shift = _shift();
      await db
          .into(db.localShifts)
          .insert(
            LocalShiftsCompanion.insert(
              organizationId: _scope.organizationId,
              branchId: _scope.branchId,
              id: shift.id,
              deviceId: shift.deviceId,
              openedBy: shift.actorId,
              openedAt: shift.openedAt,
              openingCashMinor: shift.openingCashMinor,
              currency: shift.currency,
            ),
          );
      await db.persistSale(sale);
      final before = await db.listOutbox(_scope);
      await expectLater(
        _capture(db, sale),
        throwsA(isA<OfflineStorageConflict>()),
      );
      expect(await db.listOutbox(_scope), before);
      expect(await db.select(db.offlineEventAuthorizations).get(), isEmpty);
      expect(await db.select(db.offlineStockEffects).get(), isEmpty);
      expect(await _claim(db), isNull);
      expect(await _quantity(db), 10);
    },
  );

  test(
    'authorized capture atomically preserves v1 event plus proof and stock',
    () async {
      final sale = _sale();
      await _capture(db, sale);
      expect((await db.listSales(_scope)).single.totalMinor, 100);
      expect(
        (await db.listOutbox(_scope)).single.payloadDigest,
        sale.toEvent().digest,
      );
      expect(
        (await db.listOutbox(_scope)).single.occurredAtIso,
        '2026-10-10T12:00:00.123456Z',
      );
      expect(await _quantity(db), 9);
      expect(
        await db.nextOfflineSequence(
          scope: _scope,
          actorId: _actor,
          deviceId: _device,
          grantId: _grant,
        ),
        2,
      );
      expect((await db.select(db.localShifts).get()).single.openedBy, _actor);
      final preserved = await db.readAuthorizedEvent(
        scope: _scope,
        actorId: _actor,
        deviceId: _device,
        eventId: sale.eventId,
      );
      expect(preserved!.event.digest, sale.toEvent().digest);
      expect(preserved.authorization.paymentEvidence, {
        'payment-a': {'tendered_minor': 100},
      });
    },
  );

  test(
    'identical replay adds no second sale, sequence or stock delta',
    () async {
      final sale = _sale();
      await _capture(db, sale);
      await _capture(db, sale);
      expect(await db.listSales(_scope), hasLength(1));
      expect(await _quantity(db), 9);
      await expectLater(
        _capture(
          db,
          sale,
          authorization: _authorization(sale, signature: 'changed-proof'),
        ),
        throwsA(isA<OfflineStorageConflict>()),
      );
      await expectLater(
        _capture(db, _sale(quantity: 2)),
        throwsA(isA<OfflineStorageConflict>()),
      );
    },
  );

  test(
    'missing or insufficient stock rolls back all financial state',
    () async {
      await expectLater(
        _capture(db, _sale(quantity: 11)),
        throwsA(isA<OfflineStockUnavailable>()),
      );
      expect(await db.listSales(_scope), isEmpty);
      expect(await db.listOutbox(_scope), isEmpty);
      expect(await db.select(db.localShifts).get(), isEmpty);
      expect(await _quantity(db), 10);
    },
  );

  test(
    'late payment collision rolls back sale, event, sequence and effects',
    () async {
      await _capture(db, _sale());
      await expectLater(
        _capture(db, _sale(id: 'sale-b', event: _event2), sequence: 2),
        throwsA(isA<Exception>()),
      );
      expect(await db.listSales(_scope), hasLength(1));
      expect(await db.listOutbox(_scope), hasLength(1));
      expect(await _quantity(db), 9);
      expect(
        await db.nextOfflineSequence(
          scope: _scope,
          actorId: _actor,
          deviceId: _device,
          grantId: _grant,
        ),
        2,
      );
    },
  );

  test(
    'sequence and captured amount caps retain existing paid history',
    () async {
      await _capture(db, _sale());
      final next = _sale(id: 'sale-b', event: _event2, paymentId: 'payment-b');
      await expectLater(
        _capture(db, next, sequence: 3),
        throwsA(isA<OfflineStorageConflict>()),
      );
      await expectLater(
        _capture(db, next, sequence: 2, maxEvents: 1),
        throwsA(isA<OfflineStorageConflict>()),
      );
      await expectLater(
        _capture(db, next, sequence: 2, maxTotalMinor: 150),
        throwsA(isA<OfflineStorageConflict>()),
      );
      expect(
        await db.grantCapturedTotal(
          scope: _scope,
          actorId: _actor,
          deviceId: _device,
          grantId: _grant,
        ),
        100,
      );
    },
  );

  test(
    'manual payment needs explicit evidence and reference; cash needs tender',
    () async {
      final digital = _sale(method: 'card');
      await expectLater(_capture(db, digital), throwsA(isA<ArgumentError>()));
      final cash = _sale();
      await expectLater(
        _capture(
          db,
          cash,
          authorization: _authorization(
            cash,
            evidence: {
              'payment-a': {'tendered_minor': 99},
            },
          ),
        ),
        throwsA(isA<ArgumentError>()),
      );
      await _capture(
        db,
        _sale(method: 'gcash', reference: 'verified-reference'),
      );
      expect(
        (await db.select(db.localPayments).get()).single.verificationMode,
        'manual',
      );
    },
  );

  test(
    'currency and shift actor/device mismatches fail before local persistence',
    () async {
      await expectLater(
        _capture(db, _sale(currency: 'JPY')),
        throwsA(isA<ArgumentError>()),
      );
      await expectLater(
        _capture(db, _sale(quantity: 1000001)),
        throwsA(isA<ArgumentError>()),
      );
      final sale = _sale();
      await expectLater(
        db.persistAuthorizedSale(
          draft: sale,
          authorization: _authorization(sale),
          shift: _shift(actor: 'other-actor'),
        ),
        throwsA(isA<ArgumentError>()),
      );
      expect(await db.listSales(_scope), isEmpty);
    },
  );

  test(
    'legacy events remain excluded and expired legacy leases are untouched',
    () async {
      await _capture(db, _sale());
      final legacy = _sale(
        id: 'legacy-sale',
        event: 'a0000000-0000-4000-8000-000000000003',
        paymentId: 'legacy-payment',
      );
      await db.persistSale(legacy);
      final oldLease = (await db.claimNextEvent(
        scope: _scope,
        workerId: 'legacy-worker',
        now: _now,
        leaseDuration: const Duration(seconds: 1),
      ))!;
      // Recover whichever row the legacy worker took, then reserve the legacy row.
      if (oldLease.eventId != legacy.eventId) {
        await db.failEvent(
          oldLease,
          code: SyncFailureCode.unavailable,
          now: _now,
        );
        await (db.update(
          db.syncOutbox,
        )..where((row) => row.id.equals(_event1))).write(
          SyncOutboxCompanion(
            nextAttemptAt: Value(_now.add(const Duration(hours: 1))),
          ),
        );
        await db.claimNextEvent(
          scope: _scope,
          workerId: 'legacy-worker',
          now: _now,
          leaseDuration: const Duration(seconds: 1),
        );
      }
      final before = (await db.listOutbox(
        _scope,
      )).firstWhere((row) => row.id == legacy.eventId);
      expect(before.status, 'SYNCING');
      await _claim(db, now: _now.add(const Duration(seconds: 2)));
      final after = (await db.listOutbox(
        _scope,
      )).firstWhere((row) => row.id == legacy.eventId);
      expect(after, before);
      expect(
        await db.listActorDeviceOutbox(
          scope: _scope,
          actorId: _actor,
          deviceId: _device,
        ),
        hasLength(1),
      );
    },
  );

  test(
    'grant sequence ordering blocks later events through unknown or failed outcome',
    () async {
      await _capture(db, _sale());
      await _capture(
        db,
        _sale(id: 'sale-b', event: _event2, paymentId: 'payment-b'),
        sequence: 2,
      );
      final first = (await _claim(db))!;
      expect(first.eventId, _event1);
      expect(await _claim(db, worker: 'other'), isNull);
      await db.failEvent(first, code: SyncFailureCode.conflict, now: _now);
      expect(await _claim(db), isNull);
      await db.retryFailedEvent(scope: _scope, eventId: _event1, now: _now);
      final retried = (await _claim(db))!;
      await _accept(db, retried);
      expect((await _claim(db))!.eventId, _event2);
    },
  );

  test(
    'acknowledgment retains overlay until pulled stock revision absorbs it',
    () async {
      await _capture(db, _sale());
      final lease = (await _claim(db))!;
      await _accept(db, lease);
      expect((await db.listOutbox(_scope)).single.status, 'SYNCED');
      expect(await _quantity(db), 9);
      await db.applyOfflinePullBatch(
        scope: _scope,
        actorId: _actor,
        deviceId: _device,
        batch: _batch(quantity: 9, revision: 11, cursor: '11'),
        now: _now,
        expectedCursor: '10',
      );
      expect(await _quantity(db), 9);
      expect(
        (await db.readOfflineAcceptance(
          scope: _scope,
          actorId: _actor,
          deviceId: _device,
          eventId: _event1,
        ))!.serverReceiptId,
        'SERVER-$_event1',
      );
    },
  );

  test(
    'invalid acceptance is atomic and does not mark a paid event synced',
    () async {
      await _capture(db, _sale());
      final lease = (await _claim(db))!;
      await expectLater(
        _accept(db, lease, impacts: []),
        throwsA(isA<OfflineStorageConflict>()),
      );
      expect((await db.listOutbox(_scope)).single.status, 'SYNCING');
      expect(await db.select(db.offlineAcceptanceLinks).get(), isEmpty);
      expect(await _quantity(db), 9);
    },
  );

  test(
    'stock overlay compares stock revision independently of feed cursor',
    () async {
      await db.applyOfflinePullBatch(
        scope: _scope,
        actorId: _actor,
        deviceId: _device,
        batch: _batch(
          quantity: 10,
          revision: 20,
          stockRevision: 10,
          cursor: '20',
        ),
        now: _now,
      );
      await _capture(db, _sale());
      final lease = (await _claim(db))!;
      // The effect observed authoritative stock revision 10, not feed cursor 20.
      await _accept(db, lease, revision: 11);
      expect(await _quantity(db), 9);
      await db.applyOfflinePullBatch(
        scope: _scope,
        actorId: _actor,
        deviceId: _device,
        batch: _batch(
          quantity: 10,
          revision: 21,
          stockRevision: 10,
          cursor: '21',
        ),
        now: _now,
      );
      // A newer unrelated feed position still does not include our sale effect.
      expect(await _quantity(db), 9);
      await db.applyOfflinePullBatch(
        scope: _scope,
        actorId: _actor,
        deviceId: _device,
        batch: _batch(
          quantity: 9,
          revision: 22,
          stockRevision: 11,
          cursor: '22',
        ),
        now: _now,
      );
      expect(await _quantity(db), 9);
    },
  );

  test(
    'proof, effect, preparation and acceptance are append-only including REPLACE',
    () async {
      await _capture(db, _sale());
      final lease = (await _claim(db))!;
      await _accept(db, lease);
      for (final table in [
        'offline_event_authorizations',
        'offline_stock_effects',
        'offline_preparations',
        'offline_acceptance_links',
        'offline_stock_acceptances',
      ]) {
        await expectLater(
          db.customStatement('DELETE FROM $table'),
          throwsA(isA<Exception>()),
        );
        await expectLater(
          db.customStatement('UPDATE $table SET actor_id=\'changed\''),
          throwsA(isA<Exception>()),
        );
      }
      final evidence =
          (await db.select(db.offlineEventAuthorizations).get()).single;
      await expectLater(
        db
            .into(db.offlineEventAuthorizations)
            .insert(evidence, mode: InsertMode.insertOrReplace),
        throwsA(isA<Exception>()),
      );
      expect(await _quantity(db), 9);
    },
  );

  test(
    'cache tombstones and revisions prevent resurrection; cursor rolls back on conflict',
    () async {
      final product = OfflineCacheChange(
        kind: 'product',
        id: _product,
        revision: 12,
        deleted: true,
      );
      await db.applyOfflinePullBatch(
        scope: _scope,
        actorId: _actor,
        deviceId: _device,
        batch: _batch(cursor: '12', changes: [product]),
        now: _now,
      );
      await db.applyOfflinePullBatch(
        scope: _scope,
        actorId: _actor,
        deviceId: _device,
        batch: _batch(
          cursor: '13',
          changes: [
            OfflineCacheChange(
              kind: 'product',
              id: _product,
              revision: 11,
              deleted: false,
              value: {'id': _product, 'name': 'old'},
            ),
          ],
        ),
        now: _now,
      );
      expect(
        await db.readOfflineCache(
          scope: _scope,
          actorId: _actor,
          deviceId: _device,
          kind: 'product',
        ),
        isEmpty,
      );
      await expectLater(
        db.applyOfflinePullBatch(
          scope: _scope,
          actorId: _actor,
          deviceId: _device,
          batch: _batch(
            cursor: '14',
            changes: [
              OfflineCacheChange(
                kind: 'stock',
                id: _product,
                revision: 10,
                deleted: false,
                value: {'quantity': 999},
              ),
            ],
          ),
          now: _now,
        ),
        throwsA(isA<OfflineStorageConflict>()),
      );
      expect(
        (await db.readOfflineCacheState(
          scope: _scope,
          actorId: _actor,
          deviceId: _device,
        ))!.cursor,
        '13',
      );
      expect(await _quantity(db), 10);
    },
  );

  test(
    'mutable pull cannot alter retained issuance snapshot or leak caches across actor/device',
    () async {
      final original = await db.readOfflinePreparation(
        scope: _scope,
        actorId: _actor,
        deviceId: _device,
      );
      await db.applyOfflinePullBatch(
        scope: _scope,
        actorId: _actor,
        deviceId: _device,
        batch: _batch(
          cursor: '20',
          changes: [
            OfflineCacheChange(
              kind: 'context',
              id: 'context',
              revision: 20,
              deleted: false,
              value: {'currency': 'USD'},
            ),
          ],
        ),
        now: _now,
      );
      expect(
        (await db.readOfflinePreparation(
          scope: _scope,
          actorId: _actor,
          deviceId: _device,
        ))!.snapshotJson,
        original!.snapshotJson,
      );
      expect(
        await db.readOfflinePreparation(
          scope: _scope,
          actorId: 'other',
          deviceId: _device,
        ),
        isNull,
      );
      expect(
        await db.readOfflineCache(
          scope: _scope,
          actorId: _actor,
          deviceId: 'other',
        ),
        isEmpty,
      );
      await _capture(db, _sale());
      expect(await _claim(db, actor: 'other'), isNull);
      expect(
        await db.readAuthorizedEvent(
          scope: _scope,
          actorId: 'other',
          deviceId: _device,
          eventId: _event1,
        ),
        isNull,
      );
    },
  );

  test('preparation replay preserves newer stock and pull cursor', () async {
    final prepared = await db.readOfflinePreparation(
      scope: _scope,
      actorId: _actor,
      deviceId: _device,
    );
    await db.applyOfflinePullBatch(
      scope: _scope,
      actorId: _actor,
      deviceId: _device,
      batch: _batch(quantity: 7, revision: 20, cursor: '20'),
      now: _now.add(const Duration(minutes: 1)),
      expectedCursor: '10',
    );
    await _prepare(db);
    expect(
      (await db.readOfflineCacheState(
        scope: _scope,
        actorId: _actor,
        deviceId: _device,
      ))!.cursor,
      '20',
    );
    expect(await _quantity(db), 7);
    expect(
      await db.readOfflinePreparation(
        scope: _scope,
        actorId: _actor,
        deviceId: _device,
      ),
      prepared,
    );
  });

  test('old preparation replay cannot reactivate a replaced grant', () async {
    await db.recordOfflineRelease(
      scope: _scope,
      actorId: _actor,
      deviceId: _device,
      grantId: _grant,
      finalSequence: 0,
      now: _now,
    );
    final priorBatch = _batch(preparation: true);
    await db.persistOfflinePreparation(
      scope: _scope,
      actorId: _actor,
      deviceId: _device,
      grantId: 'grant-b',
      grantWire: {
        'claims': {'grant_id': 'grant-b'},
        'signature': 'verified-test-grant-b',
      },
      snapshot: {
        'context': {'currency': 'PHP'},
        'products': [],
      },
      batch: OfflineCacheBatch(
        cursor: '11',
        serverTime: _now,
        changes: priorBatch.changes,
        completeSnapshot: true,
        grantId: 'grant-b',
      ),
      now: _now,
    );
    await expectLater(_prepare(db), throwsA(isA<OfflineStorageConflict>()));
    final current = await db.readOfflineCacheState(
      scope: _scope,
      actorId: _actor,
      deviceId: _device,
    );
    expect(current!.grantId, 'grant-b');
    expect(current.cursor, '11');
  });

  test(
    'cache rejects restricted product costs and leaves cursor unchanged',
    () async {
      await expectLater(
        db.applyOfflinePullBatch(
          scope: _scope,
          actorId: _actor,
          deviceId: _device,
          batch: _batch(
            cursor: '20',
            changes: [
              OfflineCacheChange(
                kind: 'product',
                id: _product,
                revision: 20,
                deleted: false,
                value: {'id': _product, 'cost_minor': 500},
              ),
            ],
          ),
          now: _now,
        ),
        throwsA(isA<ArgumentError>()),
      );
      expect(
        (await db.readOfflineCacheState(
          scope: _scope,
          actorId: _actor,
          deviceId: _device,
        ))!.cursor,
        '10',
      );
      await expectLater(
        db.applyOfflinePullBatch(
          scope: _scope,
          actorId: _actor,
          deviceId: _device,
          batch: _batch(
            cursor: '20',
            changes: [
              OfflineCacheChange(
                kind: 'product',
                id: _product,
                revision: 20,
                deleted: false,
                value: {
                  'id': _product,
                  'metadata': [
                    {'purchase_cost_minor': 500},
                  ],
                },
              ),
            ],
          ),
          now: _now,
        ),
        throwsA(isA<ArgumentError>()),
      );
      expect(
        await db.readOfflineCache(
          scope: _scope,
          actorId: _actor,
          deviceId: _device,
          kind: 'product',
        ),
        isEmpty,
      );
    },
  );

  test(
    'released grant remains recorded and cannot capture a new sale',
    () async {
      await db.recordOfflineRelease(
        scope: _scope,
        actorId: _actor,
        deviceId: _device,
        grantId: _grant,
        finalSequence: 0,
        now: _now,
      );
      await expectLater(
        _capture(db, _sale()),
        throwsA(isA<OfflineStorageConflict>()),
      );
      expect(
        (await db.readOfflineGrantRelease(
          scope: _scope,
          actorId: _actor,
          deviceId: _device,
          grantId: _grant,
        ))!.finalSequence,
        0,
      );
      await expectLater(
        db.customStatement('DELETE FROM offline_grant_releases'),
        throwsA(isA<Exception>()),
      );
    },
  );

  test(
    'authorized proof, pending effect and high precision event survive physical restart',
    () async {
      final directory = await Directory.systemTemp.createTemp(
        'nexapos-phase4-',
      );
      final file = File('${directory.path}/db.sqlite');
      await db.close();
      db = AppDatabase(NativeDatabase(file));
      try {
        await _prepare(db);
        await _capture(db, _sale());
        final before = (await _claim(
          db,
          duration: const Duration(seconds: 1),
        ))!;
        await db.close();
        db = AppDatabase(NativeDatabase(file));
        final after = (await _claim(
          db,
          now: _now.add(const Duration(seconds: 2)),
        ))!;
        expect(after.digest, before.digest);
        expect(after.token, isNot(before.token));
        expect(after.attempt, 2);
        expect(
          (await db.loadAuthorizedEvent(after))!.event.occurredAtIso,
          '2026-10-10T12:00:00.123456Z',
        );
        expect(await _quantity(db), 9);
        expect(
          await db.readOfflinePreparation(
            scope: _scope,
            actorId: _actor,
            deviceId: _device,
          ),
          isNotNull,
        );
      } finally {
        await db.close();
        db = AppDatabase(NativeDatabase.memory());
        await directory.delete(recursive: true);
      }
    },
  );

  test('literal v1 migration preserves all financial bytes, states and leases', () async {
    final directory = await Directory.systemTemp.createTemp(
      'nexapos-v1-upgrade-',
    );
    final file = File('${directory.path}/db.sqlite');
    final legacy = raw.sqlite3.open(file.path);
    try {
      legacy.execute(
        await File('test/database/fixtures/schema_v1.sql').readAsString(),
      );
      legacy.execute(
        "INSERT INTO local_categories VALUES ('org-a','branch-a','category-a','Old category',1,7)",
      );
      legacy.execute(
        "INSERT INTO local_products VALUES ('org-a','branch-a','product-a','category-a','SKU-A','123','Old catalog name','PHP',321,100,4,'unit',1,8)",
      );
      legacy.execute(
        "INSERT INTO local_product_prices VALUES ('org-a','branch-a','price-a','product-a','PHP',100,1234567890,8)",
      );
      legacy.execute(
        "INSERT INTO local_inventory_snapshots VALUES ('org-a','branch-a','stock-a','product-a',9,1,1234567890,9)",
      );
      legacy.execute(
        "INSERT INTO local_customers VALUES ('org-a','branch-a','customer-a','Old customer',0,6)",
      );
      legacy.execute(
        "INSERT INTO sync_cursors VALUES ('org-a','branch-a','catalog','legacy-cursor',1234567890)",
      );
      legacy.execute(
        "INSERT INTO local_shifts VALUES ('org-a','branch-a','shift-a','device-a','actor-a',?,1000,'PHP')",
        [
          _now.subtract(const Duration(minutes: 5)).millisecondsSinceEpoch ~/
              1000,
        ],
      );
      for (var i = 1; i <= 4; i++) {
        final sale = _sale(
          id: 'legacy-$i',
          event: 'b0000000-0000-4000-8000-00000000000$i',
          paymentId: 'payment-$i',
        );
        final event = sale.toEvent();
        final status = ['PENDING', 'FAILED', 'SYNCING', 'SYNCED'][i - 1];
        legacy.execute(
          'INSERT INTO local_sales VALUES (?,?,?,?,?,?,?,?,?,?,?,?,?,?)',
          [
            _scope.organizationId,
            _scope.branchId,
            sale.id,
            _device,
            'shift-a',
            _actor,
            null,
            sale.receiptNumber,
            'PHP',
            100,
            0,
            0,
            100,
            _now.millisecondsSinceEpoch ~/ 1000,
          ],
        );
        legacy.execute(
          'INSERT INTO local_sale_items VALUES (?,?,?,?,?,?,?,?,?,?,?,?)',
          [
            _scope.organizationId,
            _scope.branchId,
            'line-${sale.id}',
            sale.id,
            _product,
            'SKU-A',
            'Item A',
            1,
            100,
            0,
            0,
            100,
          ],
        );
        legacy.execute(
          'INSERT INTO local_payments VALUES (?,?,?,?,?,?,?,?,?,?,?)',
          [
            _scope.organizationId,
            _scope.branchId,
            'payment-$i',
            sale.id,
            'cash',
            100,
            'PHP',
            'cash',
            null,
            _actor,
            _now.millisecondsSinceEpoch ~/ 1000,
          ],
        );
        legacy.execute(
          'INSERT INTO sync_outbox VALUES (?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?)',
          [
            _scope.organizationId,
            _scope.branchId,
            event.eventId,
            _device,
            _actor,
            sale.id,
            'sale.created',
            1,
            event.payloadJson,
            event.digest,
            event.occurredAtIso,
            status,
            7,
            status == 'SYNCING' ? 'old-worker' : null,
            status == 'SYNCING' ? 'old-lease' : null,
            status == 'SYNCING'
                ? (_now.add(const Duration(days: 1)).millisecondsSinceEpoch ~/
                      1000)
                : null,
            status == 'PENDING'
                ? (_now.add(const Duration(hours: 2)).millisecondsSinceEpoch ~/
                      1000)
                : null,
            status == 'FAILED' ? 'conflict' : null,
            _now.millisecondsSinceEpoch ~/ 1000,
            status == 'SYNCED' ? _now.millisecondsSinceEpoch ~/ 1000 : null,
            status == 'SYNCED' ? 'original-receipt' : null,
          ],
        );
      }
      const legacyTables = [
        'local_categories',
        'local_products',
        'local_product_prices',
        'local_inventory_snapshots',
        'local_customers',
        'local_shifts',
        'local_sales',
        'local_sale_items',
        'local_payments',
        'sync_outbox',
        'sync_cursors',
      ];
      final beforeTables = {
        for (final table in legacyTables)
          table: legacy
              .select('SELECT * FROM $table ORDER BY id')
              .map((row) => Map<String, Object?>.from(row))
              .toList(),
      };
      final before = beforeTables['sync_outbox'];
      final beforeTriggers = legacy
          .select(
            "SELECT name,sql FROM sqlite_master WHERE type='trigger' ORDER BY name",
          )
          .map((row) => Map<String, Object?>.from(row))
          .toList();
      legacy.close();
      await db.close();
      db = AppDatabase(NativeDatabase(file));
      expect(
        await db
            .customSelect('PRAGMA user_version')
            .getSingle()
            .then((row) => row.read<int>('user_version')),
        2,
      );
      final after =
          (await db.customSelect('SELECT * FROM sync_outbox ORDER BY id').get())
              .map((row) => row.data)
              .toList();
      expect(after, before);
      for (final table in legacyTables) {
        expect(
          (await db.customSelect('SELECT * FROM $table ORDER BY id').get())
              .map((row) => row.data)
              .toList(),
          beforeTables[table],
          reason: 'Migration must preserve every legacy $table value.',
        );
      }
      final afterTriggers =
          (await db
                  .customSelect(
                    "SELECT name,sql FROM sqlite_master WHERE type='trigger' ORDER BY name",
                  )
                  .get())
              .map((row) => row.data)
              .toList();
      for (final trigger in beforeTriggers) {
        expect(
          afterTriggers.singleWhere((row) => row['name'] == trigger['name']),
          trigger,
        );
      }
      for (final table in [
        'offline_event_authorizations',
        'offline_stock_effects',
        'offline_acceptance_links',
        'offline_stock_acceptances',
        'offline_preparations',
        'offline_grant_releases',
        'offline_cache_records',
        'offline_cache_states',
      ]) {
        expect(await db.customSelect('SELECT * FROM $table').get(), isEmpty);
      }
      expect(await db.listSales(_scope), hasLength(4));
      expect(await db.unsyncedCount(_scope), 3);
      expect(
        await db.listActorDeviceOutbox(
          scope: _scope,
          actorId: _actor,
          deviceId: _device,
        ),
        isEmpty,
      );
      expect(await _claim(db, now: _now.add(const Duration(days: 2))), isNull);
      expect(
        (await db.customSelect('SELECT * FROM sync_outbox ORDER BY id').get())
            .map((row) => row.data)
            .toList(),
        before,
      );
      await expectLater(
        db.customStatement("UPDATE local_sales SET total_minor=0"),
        throwsA(isA<Exception>()),
      );
      expect(
        jsonDecode((await db.listOutbox(_scope)).first.payloadJson),
        isA<Map>(),
      );
    } finally {
      await db.close();
      db = AppDatabase(NativeDatabase.memory());
      await directory.delete(recursive: true);
    }
  });
}
