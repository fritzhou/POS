// Drift's declarative checks reference their own columns; generated table
// getters replace these declarations and evaluate the expressions safely.
// ignore_for_file: recursive_getters

import 'package:drift/drift.dart';

abstract class ScopedTable extends Table {
  TextColumn get organizationId => text()();
  TextColumn get branchId => text()();
  TextColumn get id => text()();

  @override
  Set<Column> get primaryKey => {organizationId, branchId, id};
}

@DataClassName('CategoryRow')
class LocalCategories extends ScopedTable {
  TextColumn get name => text()();
  BoolColumn get active => boolean().withDefault(const Constant(true))();
  IntColumn get revision => integer().check(revision.isBiggerOrEqualValue(0))();
}

@DataClassName('ProductRow')
class LocalProducts extends ScopedTable {
  TextColumn get categoryId => text().nullable()();
  TextColumn get sku => text()();
  TextColumn get barcode => text().nullable()();
  TextColumn get name => text()();
  TextColumn get currency => text().withLength(min: 3, max: 3)();
  IntColumn get costMinor =>
      integer().check(costMinor.isBiggerOrEqualValue(0))();
  IntColumn get priceMinor =>
      integer().check(priceMinor.isBiggerOrEqualValue(0))();
  IntColumn get reorderLevel => integer().withDefault(const Constant(0))();
  TextColumn get unit => text().withDefault(const Constant('unit'))();
  BoolColumn get active => boolean().withDefault(const Constant(true))();
  IntColumn get revision => integer().check(revision.isBiggerOrEqualValue(0))();

  @override
  List<Set<Column>> get uniqueKeys => [
    {organizationId, branchId, sku},
  ];

  @override
  List<String> get customConstraints => [
    'FOREIGN KEY (organization_id, branch_id, category_id) REFERENCES local_categories (organization_id, branch_id, id)',
  ];
}

@DataClassName('PriceRow')
class LocalProductPrices extends ScopedTable {
  TextColumn get productId => text()();
  TextColumn get currency => text().withLength(min: 3, max: 3)();
  IntColumn get priceMinor =>
      integer().check(priceMinor.isBiggerOrEqualValue(0))();
  DateTimeColumn get effectiveAt => dateTime()();
  IntColumn get revision => integer().check(revision.isBiggerOrEqualValue(0))();

  @override
  List<String> get customConstraints => [
    'FOREIGN KEY (organization_id, branch_id, product_id) REFERENCES local_products (organization_id, branch_id, id)',
  ];
}

@DataClassName('InventorySnapshotRow')
class LocalInventorySnapshots extends ScopedTable {
  TextColumn get productId => text()();
  IntColumn get quantityUnits => integer()();
  BoolColumn get uncertain => boolean().withDefault(const Constant(true))();
  DateTimeColumn get observedAt => dateTime()();
  IntColumn get revision => integer().check(revision.isBiggerOrEqualValue(0))();

  @override
  List<Set<Column>> get uniqueKeys => [
    {organizationId, branchId, productId},
  ];

  @override
  List<String> get customConstraints => [
    'FOREIGN KEY (organization_id, branch_id, product_id) REFERENCES local_products (organization_id, branch_id, id)',
  ];
}

@DataClassName('CustomerRow')
class LocalCustomers extends ScopedTable {
  TextColumn get name => text()();
  // No email, address, contact details or credential cache in this foundation.
  BoolColumn get active => boolean().withDefault(const Constant(true))();
  IntColumn get revision => integer().check(revision.isBiggerOrEqualValue(0))();
}

@DataClassName('ShiftRow')
class LocalShifts extends ScopedTable {
  TextColumn get deviceId => text()();
  TextColumn get openedBy => text()();
  DateTimeColumn get openedAt => dateTime()();
  IntColumn get openingCashMinor =>
      integer().check(openingCashMinor.isBiggerOrEqualValue(0))();
  TextColumn get currency => text().withLength(min: 3, max: 3)();
}

@DataClassName('SaleRow')
class LocalSales extends ScopedTable {
  TextColumn get deviceId => text()();
  TextColumn get shiftId => text()();
  TextColumn get cashierId => text()();
  TextColumn get customerId => text().nullable()();
  TextColumn get receiptNumber => text()();
  TextColumn get currency => text().withLength(min: 3, max: 3)();
  IntColumn get subtotalMinor =>
      integer().check(subtotalMinor.isBiggerOrEqualValue(0))();
  IntColumn get discountMinor =>
      integer().check(discountMinor.isBiggerOrEqualValue(0))();
  IntColumn get taxMinor => integer().check(taxMinor.isBiggerOrEqualValue(0))();
  IntColumn get totalMinor =>
      integer().check(totalMinor.isBiggerOrEqualValue(0))();
  DateTimeColumn get createdAt => dateTime()();

  @override
  List<Set<Column>> get uniqueKeys => [
    {organizationId, branchId, receiptNumber},
  ];

  @override
  List<String> get customConstraints => [
    'FOREIGN KEY (organization_id, branch_id, shift_id) REFERENCES local_shifts (organization_id, branch_id, id)',
    'CHECK (discount_minor <= subtotal_minor)',
    'CHECK (total_minor = subtotal_minor - discount_minor + tax_minor)',
  ];
}

@DataClassName('SaleItemRow')
class LocalSaleItems extends ScopedTable {
  TextColumn get saleId => text()();
  TextColumn get productId => text()();
  TextColumn get skuSnapshot => text()();
  TextColumn get nameSnapshot => text()();
  IntColumn get quantity => integer().check(quantity.isBiggerThanValue(0))();
  IntColumn get unitPriceMinor =>
      integer().check(unitPriceMinor.isBiggerOrEqualValue(0))();
  IntColumn get discountMinor =>
      integer().check(discountMinor.isBiggerOrEqualValue(0))();
  IntColumn get taxMinor => integer().check(taxMinor.isBiggerOrEqualValue(0))();
  IntColumn get lineTotalMinor =>
      integer().check(lineTotalMinor.isBiggerOrEqualValue(0))();

  @override
  List<String> get customConstraints => [
    'FOREIGN KEY (organization_id, branch_id, sale_id) REFERENCES local_sales (organization_id, branch_id, id)',
    'CHECK (discount_minor <= quantity * unit_price_minor)',
    'CHECK (line_total_minor = quantity * unit_price_minor - discount_minor + tax_minor)',
  ];
}

@DataClassName('PaymentRow')
class LocalPayments extends ScopedTable {
  TextColumn get saleId => text()();
  TextColumn get method => text()();
  IntColumn get amountMinor =>
      integer().check(amountMinor.isBiggerThanValue(0))();
  TextColumn get currency => text().withLength(min: 3, max: 3)();
  TextColumn get verificationMode => text()();
  TextColumn get reference => text().nullable()();
  TextColumn get recordedBy => text()();
  DateTimeColumn get recordedAt => dateTime()();

  @override
  List<String> get customConstraints => [
    'FOREIGN KEY (organization_id, branch_id, sale_id) REFERENCES local_sales (organization_id, branch_id, id)',
    "CHECK ((method = 'cash' AND verification_mode = 'cash') OR (method IN ('card', 'gcash', 'maya', 'other') AND verification_mode = 'manual'))",
  ];
}

@DataClassName('OutboxRow')
class SyncOutbox extends ScopedTable {
  TextColumn get deviceId => text()();
  TextColumn get actorId => text()();
  TextColumn get documentId => text()();
  TextColumn get eventType => text()();
  IntColumn get schemaVersion => integer().withDefault(const Constant(1))();
  TextColumn get payloadJson => text()();
  TextColumn get payloadDigest => text().withLength(min: 64, max: 64)();
  // Preserve hash-bound subsecond precision; Drift dateTime stores seconds.
  TextColumn get occurredAtIso => text()();
  TextColumn get status => text().withDefault(const Constant('PENDING'))();
  IntColumn get attempts => integer().withDefault(const Constant(0))();
  TextColumn get leaseOwner => text().nullable()();
  TextColumn get leaseToken => text().nullable()();
  DateTimeColumn get leaseUntil => dateTime().nullable()();
  DateTimeColumn get nextAttemptAt => dateTime().nullable()();
  TextColumn get lastError => text().nullable()();
  DateTimeColumn get createdAt => dateTime()();
  DateTimeColumn get acceptedAt => dateTime().nullable()();
  TextColumn get serverReceiptId => text().nullable()();

  @override
  List<Set<Column>> get uniqueKeys => [
    {organizationId, deviceId, id},
    {organizationId, branchId, documentId, eventType},
  ];

  @override
  List<String> get customConstraints => [
    "CHECK (status IN ('PENDING', 'SYNCING', 'SYNCED', 'FAILED'))",
    'CHECK (attempts >= 0)',
    'CHECK (schema_version = 1)',
    "CHECK ((status = 'SYNCING' AND lease_owner IS NOT NULL AND lease_token IS NOT NULL AND lease_until IS NOT NULL) OR (status != 'SYNCING' AND lease_owner IS NULL AND lease_token IS NULL AND lease_until IS NULL))",
    "CHECK (status != 'SYNCED' OR (accepted_at IS NOT NULL AND server_receipt_id IS NOT NULL))",
  ];
}

@DataClassName('CursorRow')
class SyncCursors extends ScopedTable {
  TextColumn get cursor => text()();
  DateTimeColumn get updatedAt => dateTime()();
}

@DataClassName('OfflineAuthorizationRow')
class OfflineEventAuthorizations extends ScopedTable {
  TextColumn get actorId => text()();
  TextColumn get deviceId => text()();
  TextColumn get grantId => text()();
  IntColumn get sequence =>
      integer().check(sequence.isBetweenValues(1, 1000))();
  TextColumn get authorizationJson => text()();
  TextColumn get signature => text()();

  @override
  List<Set<Column>> get uniqueKeys => [
    {organizationId, branchId, actorId, deviceId, grantId, sequence},
  ];
  @override
  List<String> get customConstraints => [
    'FOREIGN KEY (organization_id, branch_id, id) REFERENCES sync_outbox (organization_id, branch_id, id)',
  ];
}

@DataClassName('OfflineCacheRow')
class OfflineCacheRecords extends ScopedTable {
  TextColumn get actorId => text()();
  TextColumn get deviceId => text()();
  TextColumn get kind => text()();
  IntColumn get revision => integer().check(revision.isBiggerOrEqualValue(0))();
  BoolColumn get deleted => boolean().withDefault(const Constant(false))();
  TextColumn get valueJson => text().nullable()();
  @override
  Set<Column> get primaryKey => {
    organizationId,
    branchId,
    actorId,
    deviceId,
    kind,
    id,
  };
  @override
  List<String> get customConstraints => [
    "CHECK (kind IN ('context','product','category','stock','shift'))",
    'CHECK (deleted = 1 OR value_json IS NOT NULL)',
  ];
}

@DataClassName('OfflineCacheStateRow')
class OfflineCacheStates extends ScopedTable {
  TextColumn get actorId => text()();
  TextColumn get deviceId => text()();
  TextColumn get cursor => text()();
  DateTimeColumn get serverTime => dateTime()();
  DateTimeColumn get observedAt => dateTime()();
  BoolColumn get completeSnapshot =>
      boolean().withDefault(const Constant(false))();
  TextColumn get grantId => text().nullable()();
  @override
  Set<Column> get primaryKey => {
    organizationId,
    branchId,
    actorId,
    deviceId,
    id,
  };
}

@DataClassName('OfflineStockEffectRow')
class OfflineStockEffects extends ScopedTable {
  TextColumn get actorId => text()();
  TextColumn get deviceId => text()();
  TextColumn get eventId => text()();
  TextColumn get productId => text()();
  IntColumn get observedRevision =>
      integer().check(observedRevision.isBiggerOrEqualValue(0))();
  IntColumn get quantityDelta =>
      integer().check(quantityDelta.isSmallerThanValue(0))();
  @override
  List<Set<Column>> get uniqueKeys => [
    {organizationId, branchId, actorId, deviceId, eventId, productId},
  ];
  @override
  List<String> get customConstraints => [
    'FOREIGN KEY (organization_id, branch_id, event_id) REFERENCES offline_event_authorizations (organization_id, branch_id, id)',
  ];
}

@DataClassName('OfflineAcceptanceRow')
class OfflineAcceptanceLinks extends ScopedTable {
  TextColumn get actorId => text()();
  TextColumn get deviceId => text()();
  TextColumn get grantId => text()();
  IntColumn get sequence => integer()();
  TextColumn get documentId => text()();
  TextColumn get eventDigest => text().withLength(min: 64, max: 64)();
  TextColumn get serverReceiptId => text()();
  TextColumn get acceptedAtIso => text()();
  TextColumn get receiptJson => text()();
  TextColumn get reconciliationCode => text().nullable()();
  @override
  List<String> get customConstraints => [
    'FOREIGN KEY (organization_id, branch_id, id) REFERENCES offline_event_authorizations (organization_id, branch_id, id)',
  ];
}

@DataClassName('OfflineStockAcceptanceRow')
class OfflineStockAcceptances extends ScopedTable {
  TextColumn get actorId => text()();
  TextColumn get deviceId => text()();
  TextColumn get eventId => text()();
  TextColumn get productId => text()();
  IntColumn get revision => integer().check(revision.isBiggerOrEqualValue(0))();
  @override
  List<Set<Column>> get uniqueKeys => [
    {organizationId, branchId, actorId, deviceId, eventId, productId},
  ];
  @override
  List<String> get customConstraints => [
    'FOREIGN KEY (organization_id, branch_id, event_id) REFERENCES offline_acceptance_links (organization_id, branch_id, id)',
  ];
}

@DataClassName('OfflinePreparationRow')
class OfflinePreparations extends ScopedTable {
  TextColumn get actorId => text()();
  TextColumn get deviceId => text()();
  TextColumn get grantJson => text()();
  TextColumn get snapshotJson => text()();
  DateTimeColumn get preparedAt => dateTime()();
}

@DataClassName('OfflineGrantReleaseRow')
class OfflineGrantReleases extends ScopedTable {
  TextColumn get actorId => text()();
  TextColumn get deviceId => text()();
  IntColumn get finalSequence =>
      integer().check(finalSequence.isBetweenValues(0, 1000))();
  DateTimeColumn get releasedAt => dateTime()();
  @override
  List<String> get customConstraints => [
    'FOREIGN KEY (organization_id, branch_id, id) REFERENCES offline_preparations (organization_id, branch_id, id)',
  ];
}
