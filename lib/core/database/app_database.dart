import 'dart:math';

import 'package:drift/drift.dart';
import '../auth/secure_session_storage.dart';

import '../sync/outbox_state.dart';
import '../sync/sync_event.dart';
import 'database_scope.dart';
import 'open_connection.dart';
import 'offline_storage.dart';
import 'sale_draft.dart';
import 'tables.dart';

export '../sync/outbox_state.dart';
export 'database_scope.dart';
export 'sale_draft.dart';
export 'offline_storage.dart';
export 'tables.dart';

part 'app_database.g.dart';

@DriftDatabase(
  tables: [
    LocalCategories,
    LocalProducts,
    LocalProductPrices,
    LocalInventorySnapshots,
    LocalCustomers,
    LocalShifts,
    LocalSales,
    LocalSaleItems,
    LocalPayments,
    SyncOutbox,
    SyncCursors,
    OfflineEventAuthorizations,
    OfflineCacheRecords,
    OfflineCacheStates,
    OfflineStockEffects,
    OfflineAcceptanceLinks,
    OfflineStockAcceptances,
    OfflinePreparations,
    OfflineGrantReleases,
  ],
)
class AppDatabase extends _$AppDatabase {
  AppDatabase(super.executor);

  factory AppDatabase.openNative({
    required DatabaseScope scope,
    SecretStore? store,
  }) => AppDatabase(openNativeDatabase(scope, store: store));

  @override
  int get schemaVersion => 2;

  @override
  MigrationStrategy get migration => MigrationStrategy(
    onCreate: (migrator) async {
      await migrator.createAll();
      for (final table in [
        'local_shifts',
        'local_sales',
        'local_sale_items',
        'local_payments',
      ]) {
        for (final operation in ['UPDATE', 'DELETE']) {
          await customStatement('''
CREATE TRIGGER ${table}_immutable_${operation.toLowerCase()}
BEFORE $operation ON $table
BEGIN SELECT RAISE(ABORT, 'Financial records are append-only'); END
''');
        }
      }
      await customStatement('''
CREATE TRIGGER sync_outbox_immutable_payload BEFORE UPDATE ON sync_outbox
WHEN NEW.organization_id != OLD.organization_id
 OR NEW.branch_id != OLD.branch_id OR NEW.id != OLD.id
 OR NEW.device_id != OLD.device_id OR NEW.actor_id != OLD.actor_id
 OR NEW.document_id != OLD.document_id OR NEW.event_type != OLD.event_type
 OR NEW.schema_version != OLD.schema_version
 OR NEW.payload_json != OLD.payload_json OR NEW.payload_digest != OLD.payload_digest
 OR NEW.occurred_at_iso != OLD.occurred_at_iso
 OR NEW.created_at != OLD.created_at
BEGIN SELECT RAISE(ABORT, 'Outbox event content is immutable'); END
''');
      await customStatement('''
CREATE TRIGGER sync_outbox_no_delete BEFORE DELETE ON sync_outbox
BEGIN SELECT RAISE(ABORT, 'Outbox events must be preserved'); END
''');
      for (final table in ['local_sale_items', 'local_payments']) {
        await customStatement('''
CREATE TRIGGER ${table}_sealed_sale BEFORE INSERT ON $table
WHEN EXISTS (
 SELECT 1 FROM sync_outbox WHERE organization_id = NEW.organization_id
 AND branch_id = NEW.branch_id AND document_id = NEW.sale_id
 AND event_type = 'sale.created'
)
BEGIN SELECT RAISE(ABORT, 'A persisted sale is complete and immutable'); END
''');
      }
      await _installOfflineGuards();
    },
    onUpgrade: (migrator, from, to) async {
      if (from < 2) {
        await migrator.createTable(offlineEventAuthorizations);
        await migrator.createTable(offlineCacheRecords);
        await migrator.createTable(offlineCacheStates);
        await migrator.createTable(offlineStockEffects);
        await migrator.createTable(offlineAcceptanceLinks);
        await migrator.createTable(offlineStockAcceptances);
        await migrator.createTable(offlinePreparations);
        await migrator.createTable(offlineGrantReleases);
        await _installOfflineGuards();
      }
    },
    beforeOpen: (_) async {
      await customStatement('PRAGMA foreign_keys = ON');
      // REPLACE's implicit DELETE must also fire append-only guards.
      await customStatement('PRAGMA recursive_triggers = ON');
      await customStatement('PRAGMA busy_timeout = 5000');
      await customStatement('PRAGMA synchronous = FULL');
    },
  );

  Future<void> _installOfflineGuards() async {
    for (final table in [
      'offline_event_authorizations',
      'offline_stock_effects',
      'offline_acceptance_links',
      'offline_stock_acceptances',
      'offline_preparations',
      'offline_grant_releases',
    ]) {
      for (final operation in ['UPDATE', 'DELETE']) {
        await customStatement('''
CREATE TRIGGER ${table}_immutable_${operation.toLowerCase()}
BEFORE $operation ON $table
BEGIN SELECT RAISE(ABORT, 'Offline financial evidence is immutable'); END
''');
      }
    }
  }

  Expression<bool> _scope(ScopedTable table, DatabaseScope scope) =>
      table.organizationId.equals(scope.organizationId) &
      table.branchId.equals(scope.branchId);

  Future<List<SaleRow>> listSales(DatabaseScope scope) =>
      (select(localSales)
            ..where((row) => _scope(row, scope))
            ..orderBy([(row) => OrderingTerm.desc(row.createdAt)]))
          .get();

  Future<List<ProductRow>> listProducts(DatabaseScope scope) =>
      (select(localProducts)..where((row) => _scope(row, scope))).get();

  Future<List<InventorySnapshotRow>> listInventory(DatabaseScope scope) =>
      (select(
        localInventorySnapshots,
      )..where((row) => _scope(row, scope))).get();

  Future<List<OutboxRow>> listOutbox(DatabaseScope scope) =>
      (select(syncOutbox)
            ..where((row) => _scope(row, scope))
            ..orderBy([(row) => OrderingTerm.asc(row.createdAt)]))
          .get();

  /// Includes failed records: sign-out must never discard unsynced documents.
  Future<int> unsyncedCount(DatabaseScope scope) async {
    final count = syncOutbox.id.count();
    final query = selectOnly(syncOutbox)
      ..addColumns([count])
      ..where(
        _scope(syncOutbox, scope) & syncOutbox.status.equals('SYNCED').not(),
      );
    return (await query.getSingle()).read(count) ?? 0;
  }

  /// Atomic local persistence only. It does not establish offline permission,
  /// payment-provider authorization, inventory effects, or server acceptance.
  Future<SaleRow> persistSale(SaleDraft draft) async {
    draft.validate();
    final event = draft.toEvent();
    return transaction(() async {
      final prior =
          await (select(syncOutbox)..where(
                (row) =>
                    row.organizationId.equals(draft.scope.organizationId) &
                    row.id.equals(event.eventId),
              ))
              .getSingleOrNull();
      if (prior != null) {
        if (prior.payloadDigest != event.digest ||
            prior.documentId != draft.id) {
          throw const EventConflict();
        }
        return (select(localSales)..where(
              (row) => _scope(row, draft.scope) & row.id.equals(draft.id),
            ))
            .getSingle();
      }

      final shift =
          await (select(localShifts)..where(
                (row) =>
                    _scope(row, draft.scope) & row.id.equals(draft.shiftId),
              ))
              .getSingleOrNull();
      if (shift != null &&
          (shift.deviceId != draft.deviceId ||
              shift.currency != draft.currency)) {
        throw ArgumentError('Sale device and currency must match its shift.');
      }

      await into(localSales).insert(
        LocalSalesCompanion.insert(
          organizationId: draft.scope.organizationId,
          branchId: draft.scope.branchId,
          id: draft.id,
          deviceId: draft.deviceId,
          shiftId: draft.shiftId,
          cashierId: draft.cashierId,
          customerId: Value(draft.customerId),
          receiptNumber: draft.receiptNumber,
          currency: draft.currency,
          subtotalMinor: draft.subtotalMinor,
          discountMinor: draft.discountMinor,
          taxMinor: draft.taxMinor,
          totalMinor: draft.totalMinor,
          createdAt: draft.createdAt.toUtc(),
        ),
      );
      for (final item in draft.items) {
        await into(localSaleItems).insert(
          LocalSaleItemsCompanion.insert(
            organizationId: draft.scope.organizationId,
            branchId: draft.scope.branchId,
            id: item.id,
            saleId: draft.id,
            productId: item.productId,
            skuSnapshot: item.sku,
            nameSnapshot: item.name,
            quantity: item.quantity,
            unitPriceMinor: item.unitPriceMinor,
            discountMinor: item.discountMinor,
            taxMinor: item.taxMinor,
            lineTotalMinor: item.totalMinor,
          ),
        );
      }
      for (final payment in draft.payments) {
        await into(localPayments).insert(
          LocalPaymentsCompanion.insert(
            organizationId: draft.scope.organizationId,
            branchId: draft.scope.branchId,
            id: payment.id,
            saleId: draft.id,
            method: payment.method,
            amountMinor: payment.amountMinor,
            currency: draft.currency,
            verificationMode: payment.verificationMode,
            reference: Value(payment.reference),
            recordedBy: draft.cashierId,
            recordedAt: draft.createdAt.toUtc(),
          ),
        );
      }
      await into(syncOutbox).insert(
        SyncOutboxCompanion.insert(
          organizationId: draft.scope.organizationId,
          branchId: draft.scope.branchId,
          id: event.eventId,
          deviceId: event.deviceId,
          actorId: event.actorId,
          documentId: draft.id,
          eventType: event.eventType,
          payloadJson: event.payloadJson,
          payloadDigest: event.digest,
          occurredAtIso: event.occurredAtIso,
          createdAt: draft.createdAt.toUtc(),
        ),
      );
      return (select(
            localSales,
          )..where((row) => _scope(row, draft.scope) & row.id.equals(draft.id)))
          .getSingle();
    });
  }

  /// Recover abandoned leases before claiming. A claim is local queue work;
  /// merely claiming an event never changes it to SYNCED.
  Future<OutboxLease?> claimNextEvent({
    required DatabaseScope scope,
    required String workerId,
    required DateTime now,
    Duration leaseDuration = const Duration(minutes: 1),
  }) {
    if (workerId.trim().isEmpty || leaseDuration.inSeconds < 1) {
      throw ArgumentError('Worker and a positive lease duration are required.');
    }
    final utcNow = now.toUtc();
    return transaction(() async {
      await (update(syncOutbox)..where(
            (row) =>
                _scope(row, scope) &
                row.status.equals('SYNCING') &
                row.leaseUntil.isSmallerOrEqualValue(utcNow),
          ))
          .write(
            SyncOutboxCompanion(
              status: const Value('PENDING'),
              leaseOwner: const Value(null),
              leaseToken: const Value(null),
              leaseUntil: const Value(null),
              nextAttemptAt: Value(utcNow),
              lastError: const Value('timeout'),
            ),
          );
      final candidate =
          await (select(syncOutbox)
                ..where(
                  (row) =>
                      _scope(row, scope) &
                      row.status.equals('PENDING') &
                      (row.nextAttemptAt.isNull() |
                          row.nextAttemptAt.isSmallerOrEqualValue(utcNow)),
                )
                ..orderBy([
                  (row) => OrderingTerm.asc(row.createdAt),
                  (row) => OrderingTerm.asc(row.id),
                ])
                ..limit(1))
              .getSingleOrNull();
      if (candidate == null) return null;
      final lease = OutboxLease(
        eventId: candidate.id,
        scope: scope,
        workerId: workerId,
        token: newLocalId(),
        digest: candidate.payloadDigest,
        attempt: candidate.attempts + 1,
        expiresAt: utcNow.add(leaseDuration),
      );
      final changed =
          await (update(syncOutbox)..where(
                (row) =>
                    _scope(row, scope) &
                    row.id.equals(candidate.id) &
                    row.status.equals('PENDING'),
              ))
              .write(
                SyncOutboxCompanion(
                  status: const Value('SYNCING'),
                  attempts: Value(lease.attempt),
                  leaseOwner: Value(workerId),
                  leaseToken: Value(lease.token),
                  leaseUntil: Value(lease.expiresAt),
                  nextAttemptAt: const Value(null),
                ),
              );
      if (changed != 1) throw const LostOutboxLease();
      return lease;
    });
  }

  Expression<bool> _ownsLease(
    SyncOutbox row,
    OutboxLease lease,
    DateTime now,
  ) =>
      _scope(row, lease.scope) &
      row.id.equals(lease.eventId) &
      row.status.equals('SYNCING') &
      row.leaseOwner.equals(lease.workerId) &
      row.leaseToken.equals(lease.token) &
      row.payloadDigest.equals(lease.digest) &
      row.attempts.equals(lease.attempt) &
      row.leaseUntil.isBiggerThanValue(now.toUtc());

  Future<void> acknowledgeEvent(
    OutboxLease lease,
    ServerAcceptance acceptance, {
    required DateTime now,
  }) async {
    if (acceptance.eventId != lease.eventId ||
        acceptance.digest != lease.digest ||
        acceptance.serverReceiptId.trim().isEmpty) {
      throw ArgumentError('Server acceptance must match the immutable event.');
    }
    final changed =
        await (update(
          syncOutbox,
        )..where((row) => _ownsLease(row, lease, now))).write(
          SyncOutboxCompanion(
            status: const Value('SYNCED'),
            leaseOwner: const Value(null),
            leaseToken: const Value(null),
            leaseUntil: const Value(null),
            nextAttemptAt: const Value(null),
            lastError: const Value(null),
            acceptedAt: Value(acceptance.acceptedAt.toUtc()),
            serverReceiptId: Value(acceptance.serverReceiptId),
          ),
        );
    if (changed != 1) throw const LostOutboxLease();
  }

  Future<void> failEvent(
    OutboxLease lease, {
    required SyncFailureCode code,
    required DateTime now,
    double? retryJitter,
  }) async {
    final retryable =
        code == SyncFailureCode.timeout || code == SyncFailureCode.unavailable;
    final next = retryable
        ? now.toUtc().add(
            retryDelay(
              lease.attempt,
              jitter: retryJitter ?? Random().nextDouble(),
            ),
          )
        : null;
    final changed =
        await (update(
          syncOutbox,
        )..where((row) => _ownsLease(row, lease, now))).write(
          SyncOutboxCompanion(
            status: Value(retryable ? 'PENDING' : 'FAILED'),
            leaseOwner: const Value(null),
            leaseToken: const Value(null),
            leaseUntil: const Value(null),
            nextAttemptAt: Value(next),
            // Store only a finite, sanitized code, never a raw transport exception.
            lastError: Value(code.name),
          ),
        );
    if (changed != 1) throw const LostOutboxLease();
  }

  /// Explicit repair/retry action; does not alter financial data or event IDs.
  Future<bool> retryFailedEvent({
    required DatabaseScope scope,
    required String eventId,
    required DateTime now,
  }) async =>
      await (update(syncOutbox)..where(
            (row) =>
                _scope(row, scope) &
                row.id.equals(eventId) &
                row.status.equals('FAILED'),
          ))
          .write(
            SyncOutboxCompanion(
              status: const Value('PENDING'),
              nextAttemptAt: Value(now.toUtc()),
              lastError: const Value(null),
            ),
          ) ==
      1;

  /// Apply a previously validated pull batch and its opaque feed cursor in
  /// one transaction. A thrown callback preserves both the old cache/cursor.
  /// No remote download transport or authorization is supplied by this method.
  Future<void> applyPullBatch({
    required DatabaseScope scope,
    required String feed,
    required String cursor,
    required DateTime now,
    required Future<void> Function() applyChanges,
  }) {
    if (feed.trim().isEmpty || cursor.trim().isEmpty) {
      throw ArgumentError('Feed and cursor are required.');
    }
    return transaction(() async {
      await applyChanges();
      await into(syncCursors).insertOnConflictUpdate(
        SyncCursorsCompanion.insert(
          organizationId: scope.organizationId,
          branchId: scope.branchId,
          id: feed,
          cursor: cursor,
          updatedAt: now.toUtc(),
        ),
      );
    });
  }

  Future<CursorRow?> readCursor(DatabaseScope scope, String feed) =>
      (select(syncCursors)
            ..where((row) => _scope(row, scope) & row.id.equals(feed)))
          .getSingleOrNull();

  void _requireOfflineIdentity(
    DatabaseScope scope,
    String actorId,
    String deviceId,
  ) {
    if (actorId.trim().isEmpty || deviceId.trim().isEmpty) {
      throw ArgumentError('An offline actor and device are required.');
    }
  }

  Future<List<OfflineCacheRow>> readOfflineCache({
    required DatabaseScope scope,
    required String actorId,
    required String deviceId,
    String? kind,
    bool includeDeleted = false,
  }) {
    _requireOfflineIdentity(scope, actorId, deviceId);
    return (select(offlineCacheRecords)..where(
          (row) =>
              _scope(row, scope) &
              row.actorId.equals(actorId) &
              row.deviceId.equals(deviceId) &
              (kind == null ? const Constant(true) : row.kind.equals(kind)) &
              (includeDeleted
                  ? const Constant(true)
                  : row.deleted.equals(false)),
        ))
        .get();
  }

  Future<OfflineCacheRow?> readOfflineCacheRecord({
    required DatabaseScope scope,
    required String actorId,
    required String deviceId,
    required String kind,
    required String id,
  }) =>
      (select(offlineCacheRecords)..where(
            (row) =>
                _scope(row, scope) &
                row.actorId.equals(actorId) &
                row.deviceId.equals(deviceId) &
                row.kind.equals(kind) &
                row.id.equals(id),
          ))
          .getSingleOrNull();

  Future<OfflineCacheStateRow?> readOfflineCacheState({
    required DatabaseScope scope,
    required String actorId,
    required String deviceId,
  }) =>
      (select(offlineCacheStates)..where(
            (row) =>
                _scope(row, scope) &
                row.actorId.equals(actorId) &
                row.deviceId.equals(deviceId) &
                row.id.equals('offline'),
          ))
          .getSingleOrNull();

  Future<void> applyOfflinePullBatch({
    required DatabaseScope scope,
    required String actorId,
    required String deviceId,
    required OfflineCacheBatch batch,
    required DateTime now,
    String? expectedCursor,
  }) {
    _requireOfflineIdentity(scope, actorId, deviceId);
    if (batch.changes.length > 5000 ||
        batch.changes
                .map((row) => '${row.kind}\u0000${row.id}')
                .toSet()
                .length !=
            batch.changes.length) {
      throw ArgumentError('Offline cache batches must be bounded and unique.');
    }
    return transaction(() async {
      final state = await readOfflineCacheState(
        scope: scope,
        actorId: actorId,
        deviceId: deviceId,
      );
      if (expectedCursor != null && state?.cursor != expectedCursor) {
        throw const OfflineStorageConflict();
      }
      for (final change in batch.changes) {
        if (change.valueJson != null && change.valueJson!.length > 262144) {
          throw ArgumentError('An offline cache record is too large.');
        }
        if (change.kind == 'product' && _hasRestrictedCostField(change.value)) {
          throw ArgumentError(
            'Offline products must not contain restricted costs.',
          );
        }
        if (change.kind == 'stock' && !change.deleted) {
          _stockObservationRevision(change.value!);
        }
        final prior = await readOfflineCacheRecord(
          scope: scope,
          actorId: actorId,
          deviceId: deviceId,
          kind: change.kind,
          id: change.id,
        );
        if (prior != null && prior.revision > change.revision) continue;
        if (prior != null && prior.revision == change.revision) {
          if (prior.deleted != change.deleted ||
              prior.valueJson != change.valueJson) {
            throw const OfflineStorageConflict();
          }
          continue;
        }
        await into(offlineCacheRecords).insertOnConflictUpdate(
          OfflineCacheRecordsCompanion.insert(
            organizationId: scope.organizationId,
            branchId: scope.branchId,
            actorId: actorId,
            deviceId: deviceId,
            kind: change.kind,
            id: change.id,
            revision: change.revision,
            deleted: Value(change.deleted),
            valueJson: Value(change.valueJson),
          ),
        );
      }
      await into(offlineCacheStates).insertOnConflictUpdate(
        OfflineCacheStatesCompanion.insert(
          organizationId: scope.organizationId,
          branchId: scope.branchId,
          actorId: actorId,
          deviceId: deviceId,
          id: 'offline',
          cursor: batch.cursor,
          serverTime: batch.serverTime.toUtc(),
          observedAt: now.toUtc(),
          completeSnapshot: Value(
            batch.completeSnapshot || (state?.completeSnapshot ?? false),
          ),
          grantId: Value(batch.grantId ?? state?.grantId),
        ),
      );
    });
  }

  Future<void> persistOfflinePreparation({
    required DatabaseScope scope,
    required String actorId,
    required String deviceId,
    required String grantId,
    required Map<String, Object?> grantWire,
    required Map<String, Object?> snapshot,
    required OfflineCacheBatch batch,
    required DateTime now,
  }) {
    if (!batch.completeSnapshot || batch.grantId != grantId || batch.hasMore) {
      throw ArgumentError('A complete verified grant snapshot is required.');
    }
    final grantJson = canonicalJson(grantWire);
    final snapshotJson = canonicalJson(snapshot);
    return transaction(() async {
      final prior = await readOfflinePreparation(
        scope: scope,
        actorId: actorId,
        deviceId: deviceId,
        grantId: grantId,
      );
      if (prior != null) {
        if (prior.grantJson != grantJson ||
            prior.snapshotJson != snapshotJson) {
          throw const OfflineStorageConflict();
        }
        final state = await readOfflineCacheState(
          scope: scope,
          actorId: actorId,
          deviceId: deviceId,
        );
        // A lost preparation response may be retried after pull has advanced
        // the observation. The immutable issuance snapshot is already stored;
        // replay must not rewind that current cache or its feed cursor.
        if (state?.completeSnapshot == true && state?.grantId == grantId) {
          return;
        }
        if (state?.completeSnapshot == true && state?.grantId != grantId) {
          throw const OfflineStorageConflict();
        }
      } else {
        await into(offlinePreparations).insert(
          OfflinePreparationsCompanion.insert(
            organizationId: scope.organizationId,
            branchId: scope.branchId,
            id: grantId,
            actorId: actorId,
            deviceId: deviceId,
            grantJson: grantJson,
            snapshotJson: snapshotJson,
            preparedAt: now.toUtc(),
          ),
        );
      }
      await applyOfflinePullBatch(
        scope: scope,
        actorId: actorId,
        deviceId: deviceId,
        batch: batch,
        now: now,
      );
    });
  }

  Future<OfflinePreparationRow?> readOfflinePreparation({
    required DatabaseScope scope,
    required String actorId,
    required String deviceId,
    String? grantId,
  }) async {
    final id =
        grantId ??
        (await readOfflineCacheState(
          scope: scope,
          actorId: actorId,
          deviceId: deviceId,
        ))?.grantId;
    if (id == null) return null;
    return (select(offlinePreparations)..where(
          (row) =>
              _scope(row, scope) &
              row.actorId.equals(actorId) &
              row.deviceId.equals(deviceId) &
              row.id.equals(id),
        ))
        .getSingleOrNull();
  }

  bool _hasRestrictedCostField(Object? value) {
    if (value is Map) {
      return value.entries.any(
        (entry) =>
            entry.key.toString().toLowerCase().contains('cost') ||
            _hasRestrictedCostField(entry.value),
      );
    }
    return value is List && value.any(_hasRestrictedCostField);
  }

  int _stockObservationRevision(Map<String, Object?> value) {
    final revision = value['revision'];
    if (revision is! int || revision < 0 || revision > 9007199254740991) {
      throw const OfflineStorageConflict();
    }
    return revision;
  }

  Future<OfflineGrantReleaseRow?> readOfflineGrantRelease({
    required DatabaseScope scope,
    required String actorId,
    required String deviceId,
    required String grantId,
  }) =>
      (select(offlineGrantReleases)..where(
            (row) =>
                _scope(row, scope) &
                row.actorId.equals(actorId) &
                row.deviceId.equals(deviceId) &
                row.id.equals(grantId),
          ))
          .getSingleOrNull();

  Future<void> recordOfflineRelease({
    required DatabaseScope scope,
    required String actorId,
    required String deviceId,
    required String grantId,
    required int finalSequence,
    required DateTime now,
  }) => transaction(() async {
    final current =
        await nextOfflineSequence(
          scope: scope,
          actorId: actorId,
          deviceId: deviceId,
          grantId: grantId,
        ) -
        1;
    if (finalSequence != current) throw const OfflineStorageConflict();
    final prior = await readOfflineGrantRelease(
      scope: scope,
      actorId: actorId,
      deviceId: deviceId,
      grantId: grantId,
    );
    if (prior != null) {
      if (prior.finalSequence != finalSequence) {
        throw const OfflineStorageConflict();
      }
      return;
    }
    await into(offlineGrantReleases).insert(
      OfflineGrantReleasesCompanion.insert(
        organizationId: scope.organizationId,
        branchId: scope.branchId,
        id: grantId,
        actorId: actorId,
        deviceId: deviceId,
        finalSequence: finalSequence,
        releasedAt: now.toUtc(),
      ),
    );
  });

  Future<int> nextOfflineSequence({
    required DatabaseScope scope,
    required String actorId,
    required String deviceId,
    required String grantId,
  }) async {
    final result = await customSelect(
      '''
SELECT COALESCE(MAX(sequence),0) AS last_sequence FROM offline_event_authorizations
WHERE organization_id=? AND branch_id=? AND actor_id=? AND device_id=? AND grant_id=?
''',
      variables: [
        Variable(scope.organizationId),
        Variable(scope.branchId),
        Variable(actorId),
        Variable(deviceId),
        Variable(grantId),
      ],
      readsFrom: {offlineEventAuthorizations},
    ).getSingle();
    return result.read<int>('last_sequence') + 1;
  }

  Future<int> grantCapturedTotal({
    required DatabaseScope scope,
    required String actorId,
    required String deviceId,
    required String grantId,
  }) async {
    final result = await customSelect(
      '''
SELECT COALESCE(SUM(s.total_minor),0) AS total FROM offline_event_authorizations a
JOIN sync_outbox o ON o.organization_id=a.organization_id AND o.branch_id=a.branch_id AND o.id=a.id
JOIN local_sales s ON s.organization_id=o.organization_id AND s.branch_id=o.branch_id AND s.id=o.document_id
WHERE a.organization_id=? AND a.branch_id=? AND a.actor_id=? AND a.device_id=? AND a.grant_id=?
''',
      variables: [
        Variable(scope.organizationId),
        Variable(scope.branchId),
        Variable(actorId),
        Variable(deviceId),
        Variable(grantId),
      ],
      readsFrom: {offlineEventAuthorizations, syncOutbox, localSales},
    ).getSingle();
    return result.read<int>('total');
  }

  Future<int?> projectedQuantity({
    required DatabaseScope scope,
    required String actorId,
    required String deviceId,
    required String productId,
  }) async {
    final stock = await readOfflineCacheRecord(
      scope: scope,
      actorId: actorId,
      deviceId: deviceId,
      kind: 'stock',
      id: productId,
    );
    if (stock == null || stock.deleted || stock.valueJson == null) return null;
    final value = decodeCanonicalObject(stock.valueJson!);
    final observedRevision = _stockObservationRevision(value);
    final quantity = value['quantity'] ?? value['quantity_units'];
    if (quantity is! int || quantity.abs() > 9007199254740991) {
      throw const OfflineStorageConflict();
    }
    final result = await customSelect(
      '''
SELECT COALESCE(SUM(e.quantity_delta),0) AS delta FROM offline_stock_effects e
LEFT JOIN offline_stock_acceptances a ON a.organization_id=e.organization_id AND a.branch_id=e.branch_id
 AND a.actor_id=e.actor_id AND a.device_id=e.device_id AND a.event_id=e.event_id AND a.product_id=e.product_id
WHERE e.organization_id=? AND e.branch_id=? AND e.actor_id=? AND e.device_id=? AND e.product_id=?
 AND (a.id IS NULL OR a.revision > ?)
''',
      variables: [
        Variable(scope.organizationId),
        Variable(scope.branchId),
        Variable(actorId),
        Variable(deviceId),
        Variable(productId),
        Variable(observedRevision),
      ],
      readsFrom: {offlineStockEffects, offlineStockAcceptances},
    ).getSingle();
    final projected =
        BigInt.from(quantity) + BigInt.from(result.read<int>('delta'));
    if (projected.abs() > BigInt.from(9007199254740991)) {
      throw const OfflineStorageConflict();
    }
    return projected.toInt();
  }

  Future<SaleRow> persistAuthorizedSale({
    required SaleDraft draft,
    required OfflineAuthorization authorization,
    required OfflineShiftSnapshot shift,
    int maxEvents = 1000,
    int maxTotalMinor = 100000000,
  }) async {
    draft.validate();
    _validateAuthorizedDraft(
      draft,
      authorization,
      shift,
      maxEvents,
      maxTotalMinor,
    );
    return transaction(() async {
      final a = authorization;
      final prior =
          await (select(offlineEventAuthorizations)..where(
                (row) =>
                    _scope(row, draft.scope) & row.id.equals(draft.eventId),
              ))
              .getSingleOrNull();
      if (prior != null) {
        if (prior.actorId != a.actorId ||
            prior.deviceId != a.deviceId ||
            prior.authorizationJson != a.authorizationJson ||
            prior.signature != a.signature) {
          throw const OfflineStorageConflict();
        }
        return persistSale(draft);
      }
      // A schema v1 record without a retained capture-time proof is legacy
      // evidence. Even an identical SaleDraft must never gain authorization
      // later, because that would rewrite the event's financial provenance.
      final existingEvent =
          await (select(syncOutbox)..where(
                (row) =>
                    row.organizationId.equals(draft.scope.organizationId) &
                    row.id.equals(draft.eventId),
              ))
              .getSingleOrNull();
      if (existingEvent != null) throw const OfflineStorageConflict();
      if (await readOfflinePreparation(
                scope: draft.scope,
                actorId: a.actorId,
                deviceId: a.deviceId,
                grantId: a.grantId,
              ) ==
              null ||
          await readOfflineGrantRelease(
                scope: draft.scope,
                actorId: a.actorId,
                deviceId: a.deviceId,
                grantId: a.grantId,
              ) !=
              null) {
        throw const OfflineStorageConflict();
      }
      final sequence = await nextOfflineSequence(
        scope: draft.scope,
        actorId: a.actorId,
        deviceId: a.deviceId,
        grantId: a.grantId,
      );
      final total = await grantCapturedTotal(
        scope: draft.scope,
        actorId: a.actorId,
        deviceId: a.deviceId,
        grantId: a.grantId,
      );
      if (a.sequence != sequence ||
          sequence > maxEvents ||
          BigInt.from(total) + BigInt.from(draft.totalMinor) >
              BigInt.from(maxTotalMinor)) {
        throw const OfflineStorageConflict();
      }
      for (final item in draft.items) {
        final available = await projectedQuantity(
          scope: draft.scope,
          actorId: a.actorId,
          deviceId: a.deviceId,
          productId: item.productId,
        );
        if (available == null || available < item.quantity) {
          throw const OfflineStockUnavailable();
        }
      }
      final currentShift =
          await (select(localShifts)..where(
                (row) => _scope(row, draft.scope) & row.id.equals(shift.id),
              ))
              .getSingleOrNull();
      if (currentShift == null) {
        await into(localShifts).insert(
          LocalShiftsCompanion.insert(
            organizationId: draft.scope.organizationId,
            branchId: draft.scope.branchId,
            id: shift.id,
            deviceId: shift.deviceId,
            openedBy: shift.actorId,
            openedAt: shift.openedAt.toUtc(),
            openingCashMinor: shift.openingCashMinor,
            currency: shift.currency,
          ),
        );
      } else if (currentShift.deviceId != shift.deviceId ||
          currentShift.openedBy != shift.actorId ||
          currentShift.currency != shift.currency ||
          currentShift.openingCashMinor != shift.openingCashMinor ||
          currentShift.openedAt.millisecondsSinceEpoch ~/ 1000 !=
              shift.openedAt.millisecondsSinceEpoch ~/ 1000) {
        throw const OfflineStorageConflict();
      }
      final sale = await persistSale(draft);
      await into(offlineEventAuthorizations).insert(
        OfflineEventAuthorizationsCompanion.insert(
          organizationId: draft.scope.organizationId,
          branchId: draft.scope.branchId,
          id: draft.eventId,
          actorId: a.actorId,
          deviceId: a.deviceId,
          grantId: a.grantId,
          sequence: a.sequence,
          authorizationJson: a.authorizationJson,
          signature: a.signature,
        ),
      );
      for (final item in draft.items) {
        final observed = await readOfflineCacheRecord(
          scope: draft.scope,
          actorId: a.actorId,
          deviceId: a.deviceId,
          kind: 'stock',
          id: item.productId,
        );
        await into(offlineStockEffects).insert(
          OfflineStockEffectsCompanion.insert(
            organizationId: draft.scope.organizationId,
            branchId: draft.scope.branchId,
            id: '${draft.eventId}:${item.productId}',
            actorId: a.actorId,
            deviceId: a.deviceId,
            eventId: draft.eventId,
            productId: item.productId,
            observedRevision: _stockObservationRevision(
              decodeCanonicalObject(observed!.valueJson!),
            ),
            quantityDelta: -item.quantity,
          ),
        );
      }
      return sale;
    });
  }

  void _validateAuthorizedDraft(
    SaleDraft draft,
    OfflineAuthorization a,
    OfflineShiftSnapshot shift,
    int maxEvents,
    int maxTotalMinor,
  ) {
    if (a.organizationId != draft.scope.organizationId ||
        a.branchId != draft.scope.branchId ||
        a.actorId != draft.cashierId ||
        a.deviceId != draft.deviceId ||
        a.eventId != draft.eventId ||
        shift.scope.organizationId != draft.scope.organizationId ||
        shift.scope.branchId != draft.scope.branchId ||
        shift.id != draft.shiftId ||
        shift.actorId != draft.cashierId ||
        shift.deviceId != draft.deviceId ||
        shift.currency != draft.currency ||
        shift.openingCashMinor < 0 ||
        shift.openingCashMinor > 9007199254740991 ||
        !{
          'PHP',
          'USD',
          'EUR',
          'GBP',
          'AUD',
          'CAD',
          'SGD',
        }.contains(draft.currency) ||
        draft.totalMinor <= 0 ||
        draft.discountMinor != 0 ||
        draft.items.map((row) => row.productId).toSet().length !=
            draft.items.length ||
        draft.items.any((row) => row.quantity > 1000000) ||
        draft.payments.isEmpty ||
        draft.payments.length > 5 ||
        maxEvents < 1 ||
        maxEvents > 1000 ||
        maxTotalMinor < 1 ||
        maxTotalMinor > 100000000) {
      throw ArgumentError(
        'The offline sale does not match its bounded authorization.',
      );
    }
    final evidence = a.paymentEvidence;
    if (evidence.length != draft.payments.length) {
      throw ArgumentError('Every payment requires evidence.');
    }
    for (final payment in draft.payments) {
      final proof = evidence[payment.id];
      if (proof is! Map) {
        throw ArgumentError('Every payment requires evidence.');
      }
      if (payment.method == 'cash') {
        final tendered = proof['tendered_minor'];
        if (proof.length != 1 ||
            tendered is! int ||
            tendered < payment.amountMinor ||
            tendered > 9007199254740991) {
          throw ArgumentError('Cash tender evidence is invalid.');
        }
      } else if (proof.length != 1 ||
          proof['manual_confirmed'] != true ||
          payment.reference == null ||
          payment.reference!.trim().isEmpty) {
        throw ArgumentError(
          'Manual payment evidence and reference are required.',
        );
      }
    }
  }

  Future<List<OutboxRow>> listActorDeviceOutbox({
    required DatabaseScope scope,
    required String actorId,
    required String deviceId,
  }) async {
    final rows = await customSelect(
      '''
SELECT o.* FROM sync_outbox o JOIN offline_event_authorizations a
ON a.organization_id=o.organization_id AND a.branch_id=o.branch_id AND a.id=o.id
WHERE o.organization_id=? AND o.branch_id=? AND o.actor_id=? AND o.device_id=?
ORDER BY o.created_at,o.id
''',
      variables: [
        Variable(scope.organizationId),
        Variable(scope.branchId),
        Variable(actorId),
        Variable(deviceId),
      ],
      readsFrom: {syncOutbox, offlineEventAuthorizations},
    ).get();
    return rows.map((row) => syncOutbox.map(row.data)).toList(growable: false);
  }

  Future<int> actorDeviceUnsyncedCount({
    required DatabaseScope scope,
    required String actorId,
    required String deviceId,
  }) async => (await listActorDeviceOutbox(
    scope: scope,
    actorId: actorId,
    deviceId: deviceId,
  )).where((row) => row.status != 'SYNCED').length;

  Future<OutboxLease?> claimNextAuthorizedEvent({
    required DatabaseScope scope,
    required String actorId,
    required String deviceId,
    required String workerId,
    required DateTime now,
    Duration leaseDuration = const Duration(minutes: 1),
  }) {
    _requireOfflineIdentity(scope, actorId, deviceId);
    if (workerId.trim().isEmpty || leaseDuration.inSeconds < 1) {
      throw ArgumentError('A worker and positive lease duration are required.');
    }
    return transaction(() async {
      await customUpdate(
        '''
UPDATE sync_outbox SET status='PENDING',lease_owner=NULL,lease_token=NULL,
lease_until=NULL,next_attempt_at=?,last_error='timeout'
WHERE organization_id=? AND branch_id=? AND actor_id=? AND device_id=?
AND status='SYNCING' AND lease_until<=?
AND EXISTS(SELECT 1 FROM offline_event_authorizations a WHERE
 a.organization_id=sync_outbox.organization_id AND a.branch_id=sync_outbox.branch_id
 AND a.id=sync_outbox.id AND a.actor_id=sync_outbox.actor_id AND a.device_id=sync_outbox.device_id)
''',
        variables: [
          Variable(now.toUtc().millisecondsSinceEpoch ~/ 1000),
          Variable(scope.organizationId),
          Variable(scope.branchId),
          Variable(actorId),
          Variable(deviceId),
          Variable(now.toUtc().millisecondsSinceEpoch ~/ 1000),
        ],
        updates: {syncOutbox},
      );
      final candidates = await customSelect(
        '''
SELECT o.* FROM sync_outbox o JOIN offline_event_authorizations a
ON a.organization_id=o.organization_id AND a.branch_id=o.branch_id AND a.id=o.id
WHERE o.organization_id=? AND o.branch_id=? AND o.actor_id=? AND o.device_id=?
AND o.status='PENDING' AND (o.next_attempt_at IS NULL OR o.next_attempt_at<=?)
AND NOT EXISTS (
 SELECT 1 FROM offline_event_authorizations previous JOIN sync_outbox earlier
 ON earlier.organization_id=previous.organization_id AND earlier.branch_id=previous.branch_id AND earlier.id=previous.id
 WHERE previous.organization_id=a.organization_id AND previous.branch_id=a.branch_id
 AND previous.actor_id=a.actor_id AND previous.device_id=a.device_id AND previous.grant_id=a.grant_id
 AND previous.sequence<a.sequence AND earlier.status!='SYNCED'
) ORDER BY o.created_at,a.sequence,o.id LIMIT 1
''',
        variables: [
          Variable(scope.organizationId),
          Variable(scope.branchId),
          Variable(actorId),
          Variable(deviceId),
          Variable(now.toUtc().millisecondsSinceEpoch ~/ 1000),
        ],
        readsFrom: {syncOutbox, offlineEventAuthorizations},
      ).get();
      if (candidates.isEmpty) return null;
      final candidate = syncOutbox.map(candidates.single.data);
      final lease = OutboxLease(
        eventId: candidate.id,
        scope: scope,
        workerId: workerId,
        token: newLocalId(),
        digest: candidate.payloadDigest,
        attempt: candidate.attempts + 1,
        expiresAt: now.toUtc().add(leaseDuration),
      );
      final changed =
          await (update(syncOutbox)..where(
                (row) =>
                    _scope(row, scope) &
                    row.id.equals(candidate.id) &
                    row.status.equals('PENDING'),
              ))
              .write(
                SyncOutboxCompanion(
                  status: const Value('SYNCING'),
                  attempts: Value(lease.attempt),
                  leaseOwner: Value(workerId),
                  leaseToken: Value(lease.token),
                  leaseUntil: Value(lease.expiresAt),
                  nextAttemptAt: const Value(null),
                ),
              );
      if (changed != 1) throw const LostOutboxLease();
      return lease;
    });
  }

  Future<AuthorizedOutboxEvent?> loadAuthorizedEvent(OutboxLease lease) async {
    final outbox =
        await (select(syncOutbox)..where(
              (row) => _scope(row, lease.scope) & row.id.equals(lease.eventId),
            ))
            .getSingleOrNull();
    final proof =
        await (select(offlineEventAuthorizations)..where(
              (row) => _scope(row, lease.scope) & row.id.equals(lease.eventId),
            ))
            .getSingleOrNull();
    if (outbox == null || proof == null) return null;
    if (outbox.payloadDigest != lease.digest ||
        proof.actorId != outbox.actorId ||
        proof.deviceId != outbox.deviceId) {
      throw const OfflineStorageConflict();
    }
    final decoded = decodeCanonicalObject(proof.authorizationJson);
    final event = SyncEvent(
      eventId: outbox.id,
      organizationId: outbox.organizationId,
      branchId: outbox.branchId,
      deviceId: outbox.deviceId,
      actorId: outbox.actorId,
      eventType: outbox.eventType,
      occurredAt: DateTime.parse(outbox.occurredAtIso),
      payload: decodeCanonicalObject(outbox.payloadJson),
      schemaVersion: outbox.schemaVersion,
    );
    if (event.digest != outbox.payloadDigest ||
        decoded['grant_id'] != proof.grantId ||
        decoded['sequence'] != proof.sequence) {
      throw const OfflineStorageConflict();
    }
    return AuthorizedOutboxEvent(
      event: event,
      documentId: outbox.documentId,
      status: outbox.status,
      authorization: OfflineAuthorization(
        organizationId: proof.organizationId,
        branchId: proof.branchId,
        actorId: proof.actorId,
        deviceId: proof.deviceId,
        eventId: proof.id,
        grantId: proof.grantId,
        sequence: proof.sequence,
        paymentEvidence: Map<String, Object?>.from(
          decoded['payment_evidence'] as Map,
        ),
        signature: proof.signature,
      ),
    );
  }

  Future<AuthorizedOutboxEvent?> readAuthorizedEvent({
    required DatabaseScope scope,
    required String actorId,
    required String deviceId,
    required String eventId,
  }) async {
    final row =
        await (select(syncOutbox)..where(
              (row) =>
                  _scope(row, scope) &
                  row.actorId.equals(actorId) &
                  row.deviceId.equals(deviceId) &
                  row.id.equals(eventId),
            ))
            .getSingleOrNull();
    if (row == null) return null;
    return loadAuthorizedEvent(
      OutboxLease(
        eventId: row.id,
        scope: scope,
        workerId: 'read',
        token: 'read',
        digest: row.payloadDigest,
        attempt: row.attempts,
        expiresAt: row.createdAt,
      ),
    );
  }

  Future<void> recordAcceptance({
    required OutboxLease lease,
    required ServerAcceptance acceptance,
    required String actorId,
    required String deviceId,
    required String grantId,
    required int sequence,
    required String documentId,
    required Map<String, Object?> receipt,
    required List<OfflineStockImpact> stockImpacts,
    String? reconciliationCode,
    required DateTime now,
  }) => transaction(() async {
    final preserved = await loadAuthorizedEvent(lease);
    if (preserved == null ||
        preserved.event.actorId != actorId ||
        preserved.event.deviceId != deviceId ||
        preserved.authorization.grantId != grantId ||
        preserved.authorization.sequence != sequence ||
        preserved.documentId != documentId ||
        acceptance.eventId != lease.eventId ||
        acceptance.digest != lease.digest ||
        acceptance.serverReceiptId.trim().isEmpty ||
        stockImpacts.map((row) => row.productId).toSet().length !=
            stockImpacts.length ||
        stockImpacts.any(
          (row) =>
              row.productId.trim().isEmpty ||
              row.revision < 0 ||
              row.revision > 9007199254740991,
        )) {
      throw const OfflineStorageConflict();
    }
    final effects =
        await (select(offlineStockEffects)..where(
              (row) =>
                  _scope(row, lease.scope) & row.eventId.equals(lease.eventId),
            ))
            .get();
    if (effects
            .map((row) => row.productId)
            .toSet()
            .difference(stockImpacts.map((row) => row.productId).toSet())
            .isNotEmpty ||
        effects.length != stockImpacts.length) {
      throw const OfflineStorageConflict();
    }
    for (final effect in effects) {
      if (stockImpacts
              .singleWhere((impact) => impact.productId == effect.productId)
              .revision <=
          effect.observedRevision) {
        throw const OfflineStorageConflict();
      }
    }
    final receiptJson = canonicalJson(receipt);
    final prior = await readOfflineAcceptance(
      scope: lease.scope,
      actorId: actorId,
      deviceId: deviceId,
      eventId: lease.eventId,
    );
    if (prior != null) {
      if (prior.serverReceiptId != acceptance.serverReceiptId ||
          prior.eventDigest != acceptance.digest ||
          prior.receiptJson != receiptJson ||
          prior.acceptedAtIso !=
              acceptance.acceptedAt.toUtc().toIso8601String() ||
          prior.reconciliationCode != reconciliationCode) {
        throw const OfflineStorageConflict();
      }
      final oldImpacts =
          await (select(offlineStockAcceptances)..where(
                (row) =>
                    _scope(row, lease.scope) &
                    row.eventId.equals(lease.eventId),
              ))
              .get();
      if (oldImpacts.length != stockImpacts.length ||
          oldImpacts.any(
            (old) =>
                stockImpacts
                    .singleWhere((impact) => impact.productId == old.productId)
                    .revision !=
                old.revision,
          )) {
        throw const OfflineStorageConflict();
      }
      return;
    }
    await acknowledgeEvent(lease, acceptance, now: now);
    await into(offlineAcceptanceLinks).insert(
      OfflineAcceptanceLinksCompanion.insert(
        organizationId: lease.scope.organizationId,
        branchId: lease.scope.branchId,
        id: lease.eventId,
        actorId: actorId,
        deviceId: deviceId,
        grantId: grantId,
        sequence: sequence,
        documentId: documentId,
        eventDigest: acceptance.digest,
        serverReceiptId: acceptance.serverReceiptId,
        acceptedAtIso: acceptance.acceptedAt.toUtc().toIso8601String(),
        receiptJson: receiptJson,
        reconciliationCode: Value(reconciliationCode),
      ),
    );
    for (final impact in stockImpacts) {
      await into(offlineStockAcceptances).insert(
        OfflineStockAcceptancesCompanion.insert(
          organizationId: lease.scope.organizationId,
          branchId: lease.scope.branchId,
          id: '${lease.eventId}:${impact.productId}',
          actorId: actorId,
          deviceId: deviceId,
          eventId: lease.eventId,
          productId: impact.productId,
          revision: impact.revision,
        ),
      );
    }
  });

  Future<OfflineAcceptanceRow?> readOfflineAcceptance({
    required DatabaseScope scope,
    required String actorId,
    required String deviceId,
    required String eventId,
  }) =>
      (select(offlineAcceptanceLinks)..where(
            (row) =>
                _scope(row, scope) &
                row.actorId.equals(actorId) &
                row.deviceId.equals(deviceId) &
                row.id.equals(eventId),
          ))
          .getSingleOrNull();

  Future<List<SaleRow>> listActorDeviceSales({
    required DatabaseScope scope,
    required String actorId,
    required String deviceId,
  }) =>
      (select(localSales)
            ..where(
              (row) =>
                  _scope(row, scope) &
                  row.cashierId.equals(actorId) &
                  row.deviceId.equals(deviceId),
            )
            ..orderBy([(row) => OrderingTerm.desc(row.createdAt)]))
          .get();
}
