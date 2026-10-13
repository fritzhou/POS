import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nexapos/core/database/app_database.dart';
import 'package:nexapos/core/sync/sync_event.dart';

void main() {
  late AppDatabase db;
  final scope = DatabaseScope(organizationId: 'org-a', branchId: 'branch-a');
  final now = DateTime.utc(2026, 1, 1, 12);
  late SaleDraft sale;

  setUp(() async {
    db = AppDatabase(NativeDatabase.memory());
    await db
        .into(db.localShifts)
        .insert(
          LocalShiftsCompanion.insert(
            organizationId: scope.organizationId,
            branchId: scope.branchId,
            id: 'shift-1',
            deviceId: 'device-1',
            openedBy: 'user-1',
            openedAt: now,
            openingCashMinor: 0,
            currency: 'PHP',
          ),
        );
    sale = SaleDraft(
      id: 'sale-1',
      eventId: newLocalId(),
      scope: scope,
      deviceId: 'device-1',
      shiftId: 'shift-1',
      cashierId: 'user-1',
      receiptNumber: 'branch-a-device-1-sale-1',
      currency: 'PHP',
      createdAt: now,
      items: const [
        SaleLineDraft(
          id: 'line-1',
          productId: 'product-1',
          sku: 'ITEM-1',
          name: 'Item',
          quantity: 1,
          unitPriceMinor: 100,
        ),
      ],
      payments: const [
        SalePaymentDraft(id: 'payment-1', method: 'cash', amountMinor: 100),
      ],
    );
    await db.persistSale(sale);
  });

  tearDown(() => db.close());

  ServerAcceptance acceptance(OutboxLease lease) => ServerAcceptance(
    eventId: lease.eventId,
    digest: lease.digest,
    serverReceiptId: 'test-server-receipt',
    acceptedAt: now,
  );

  test(
    'leases require current ownership and real matching acceptance',
    () async {
      final first = (await db.claimNextEvent(
        scope: scope,
        workerId: 'worker-1',
        now: now,
        leaseDuration: const Duration(seconds: 10),
      ))!;
      expect((await db.listOutbox(scope)).single.status, 'SYNCING');
      expect(
        await db.claimNextEvent(scope: scope, workerId: 'worker-2', now: now),
        isNull,
      );
      await expectLater(
        db.acknowledgeEvent(
          first,
          ServerAcceptance(
            eventId: first.eventId,
            digest: 'different',
            serverReceiptId: 'test-receipt',
            acceptedAt: now,
          ),
          now: now,
        ),
        throwsA(isA<ArgumentError>()),
      );
      final later = now.add(const Duration(seconds: 11));
      final second = (await db.claimNextEvent(
        scope: scope,
        workerId: 'worker-2',
        now: later,
      ))!;
      await expectLater(
        db.acknowledgeEvent(first, acceptance(first), now: later),
        throwsA(isA<LostOutboxLease>()),
      );
      await expectLater(
        db.failEvent(first, code: SyncFailureCode.timeout, now: later),
        throwsA(isA<LostOutboxLease>()),
      );
      await db.acknowledgeEvent(second, acceptance(second), now: later);
      final record = (await db.listOutbox(scope)).single;
      expect(record.status, 'SYNCED');
      expect(record.serverReceiptId, 'test-server-receipt');
      expect(await db.unsyncedCount(scope), 0);
      expect(
        await db.claimNextEvent(scope: scope, workerId: 'worker-3', now: later),
        isNull,
      );
    },
  );

  test(
    'expired lease cannot acknowledge even before another worker claims',
    () async {
      final lease = (await db.claimNextEvent(
        scope: scope,
        workerId: 'worker-1',
        now: now,
        leaseDuration: const Duration(seconds: 5),
      ))!;
      await expectLater(
        db.acknowledgeEvent(
          lease,
          acceptance(lease),
          now: now.add(const Duration(seconds: 5)),
        ),
        throwsA(isA<LostOutboxLease>()),
      );
      expect((await db.listOutbox(scope)).single.status, 'SYNCING');
    },
  );

  test(
    'transient failures back off; permanent failures require explicit retry',
    () async {
      final lease = (await db.claimNextEvent(
        scope: scope,
        workerId: 'worker-1',
        now: now,
      ))!;
      await db.failEvent(
        lease,
        code: SyncFailureCode.unavailable,
        now: now,
        retryJitter: 0.5,
      );
      final queued = (await db.listOutbox(scope)).single;
      expect(queued.status, 'PENDING');
      expect(queued.lastError, 'unavailable');
      expect(queued.payloadDigest, sale.toEvent().digest);
      expect(
        await db.claimNextEvent(scope: scope, workerId: 'worker-2', now: now),
        isNull,
      );
      final retryTime = now.add(retryDelay(1));
      final retry = (await db.claimNextEvent(
        scope: scope,
        workerId: 'worker-2',
        now: retryTime,
      ))!;
      expect(retry.attempt, 2);
      await db.failEvent(
        retry,
        code: SyncFailureCode.unauthorized,
        now: retryTime,
      );
      expect((await db.listOutbox(scope)).single.status, 'FAILED');
      expect(await db.unsyncedCount(scope), 1);
      expect(
        await db.claimNextEvent(
          scope: scope,
          workerId: 'worker-3',
          now: retryTime.add(const Duration(days: 1)),
        ),
        isNull,
      );
      expect(
        await db.retryFailedEvent(
          scope: scope,
          eventId: sale.eventId,
          now: retryTime,
        ),
        isTrue,
      );
      expect(
        (await db.claimNextEvent(
          scope: scope,
          workerId: 'worker-3',
          now: retryTime,
        ))?.attempt,
        3,
      );
    },
  );

  test(
    'workers cannot claim queues in another organization or branch',
    () async {
      expect(
        await db.claimNextEvent(
          scope: DatabaseScope(organizationId: 'org-b', branchId: 'branch-a'),
          workerId: 'other-tenant',
          now: now,
        ),
        isNull,
      );
      expect(
        await db.claimNextEvent(
          scope: DatabaseScope(organizationId: 'org-a', branchId: 'branch-b'),
          workerId: 'other-branch',
          now: now,
        ),
        isNull,
      );
      expect((await db.listOutbox(scope)).single.status, 'PENDING');
    },
  );
}
