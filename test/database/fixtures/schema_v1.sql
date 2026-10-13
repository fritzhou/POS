-- Frozen literal schema v1. New tables must never be added to this fixture.
CREATE TABLE "local_categories" ("organization_id" TEXT NOT NULL, "branch_id" TEXT NOT NULL, "id" TEXT NOT NULL, "name" TEXT NOT NULL, "active" INTEGER NOT NULL DEFAULT 1 CHECK ("active" IN (0, 1)), "revision" INTEGER NOT NULL CHECK("revision" >= 0), PRIMARY KEY ("organization_id", "branch_id", "id"));
CREATE TABLE "local_customers" ("organization_id" TEXT NOT NULL, "branch_id" TEXT NOT NULL, "id" TEXT NOT NULL, "name" TEXT NOT NULL, "active" INTEGER NOT NULL DEFAULT 1 CHECK ("active" IN (0, 1)), "revision" INTEGER NOT NULL CHECK("revision" >= 0), PRIMARY KEY ("organization_id", "branch_id", "id"));
CREATE TABLE "local_inventory_snapshots" ("organization_id" TEXT NOT NULL, "branch_id" TEXT NOT NULL, "id" TEXT NOT NULL, "product_id" TEXT NOT NULL, "quantity_units" INTEGER NOT NULL, "uncertain" INTEGER NOT NULL DEFAULT 1 CHECK ("uncertain" IN (0, 1)), "observed_at" INTEGER NOT NULL, "revision" INTEGER NOT NULL CHECK("revision" >= 0), PRIMARY KEY ("organization_id", "branch_id", "id"), UNIQUE ("organization_id", "branch_id", "product_id"), FOREIGN KEY (organization_id, branch_id, product_id) REFERENCES local_products (organization_id, branch_id, id));
CREATE TABLE "local_payments" ("organization_id" TEXT NOT NULL, "branch_id" TEXT NOT NULL, "id" TEXT NOT NULL, "sale_id" TEXT NOT NULL, "method" TEXT NOT NULL, "amount_minor" INTEGER NOT NULL CHECK("amount_minor" > 0), "currency" TEXT NOT NULL, "verification_mode" TEXT NOT NULL, "reference" TEXT NULL, "recorded_by" TEXT NOT NULL, "recorded_at" INTEGER NOT NULL, PRIMARY KEY ("organization_id", "branch_id", "id"), FOREIGN KEY (organization_id, branch_id, sale_id) REFERENCES local_sales (organization_id, branch_id, id), CHECK ((method = 'cash' AND verification_mode = 'cash') OR (method IN ('card', 'gcash', 'maya', 'other') AND verification_mode = 'manual')));
CREATE TABLE "local_product_prices" ("organization_id" TEXT NOT NULL, "branch_id" TEXT NOT NULL, "id" TEXT NOT NULL, "product_id" TEXT NOT NULL, "currency" TEXT NOT NULL, "price_minor" INTEGER NOT NULL CHECK("price_minor" >= 0), "effective_at" INTEGER NOT NULL, "revision" INTEGER NOT NULL CHECK("revision" >= 0), PRIMARY KEY ("organization_id", "branch_id", "id"), FOREIGN KEY (organization_id, branch_id, product_id) REFERENCES local_products (organization_id, branch_id, id));
CREATE TABLE "local_products" ("organization_id" TEXT NOT NULL, "branch_id" TEXT NOT NULL, "id" TEXT NOT NULL, "category_id" TEXT NULL, "sku" TEXT NOT NULL, "barcode" TEXT NULL, "name" TEXT NOT NULL, "currency" TEXT NOT NULL, "cost_minor" INTEGER NOT NULL CHECK("cost_minor" >= 0), "price_minor" INTEGER NOT NULL CHECK("price_minor" >= 0), "reorder_level" INTEGER NOT NULL DEFAULT 0, "unit" TEXT NOT NULL DEFAULT 'unit', "active" INTEGER NOT NULL DEFAULT 1 CHECK ("active" IN (0, 1)), "revision" INTEGER NOT NULL CHECK("revision" >= 0), PRIMARY KEY ("organization_id", "branch_id", "id"), UNIQUE ("organization_id", "branch_id", "sku"), FOREIGN KEY (organization_id, branch_id, category_id) REFERENCES local_categories (organization_id, branch_id, id));
CREATE TABLE "local_sale_items" ("organization_id" TEXT NOT NULL, "branch_id" TEXT NOT NULL, "id" TEXT NOT NULL, "sale_id" TEXT NOT NULL, "product_id" TEXT NOT NULL, "sku_snapshot" TEXT NOT NULL, "name_snapshot" TEXT NOT NULL, "quantity" INTEGER NOT NULL CHECK("quantity" > 0), "unit_price_minor" INTEGER NOT NULL CHECK("unit_price_minor" >= 0), "discount_minor" INTEGER NOT NULL CHECK("discount_minor" >= 0), "tax_minor" INTEGER NOT NULL CHECK("tax_minor" >= 0), "line_total_minor" INTEGER NOT NULL CHECK("line_total_minor" >= 0), PRIMARY KEY ("organization_id", "branch_id", "id"), FOREIGN KEY (organization_id, branch_id, sale_id) REFERENCES local_sales (organization_id, branch_id, id), CHECK (discount_minor <= quantity * unit_price_minor), CHECK (line_total_minor = quantity * unit_price_minor - discount_minor + tax_minor));
CREATE TABLE "local_sales" ("organization_id" TEXT NOT NULL, "branch_id" TEXT NOT NULL, "id" TEXT NOT NULL, "device_id" TEXT NOT NULL, "shift_id" TEXT NOT NULL, "cashier_id" TEXT NOT NULL, "customer_id" TEXT NULL, "receipt_number" TEXT NOT NULL, "currency" TEXT NOT NULL, "subtotal_minor" INTEGER NOT NULL CHECK("subtotal_minor" >= 0), "discount_minor" INTEGER NOT NULL CHECK("discount_minor" >= 0), "tax_minor" INTEGER NOT NULL CHECK("tax_minor" >= 0), "total_minor" INTEGER NOT NULL CHECK("total_minor" >= 0), "created_at" INTEGER NOT NULL, PRIMARY KEY ("organization_id", "branch_id", "id"), UNIQUE ("organization_id", "branch_id", "receipt_number"), FOREIGN KEY (organization_id, branch_id, shift_id) REFERENCES local_shifts (organization_id, branch_id, id), CHECK (discount_minor <= subtotal_minor), CHECK (total_minor = subtotal_minor - discount_minor + tax_minor));
CREATE TABLE "local_shifts" ("organization_id" TEXT NOT NULL, "branch_id" TEXT NOT NULL, "id" TEXT NOT NULL, "device_id" TEXT NOT NULL, "opened_by" TEXT NOT NULL, "opened_at" INTEGER NOT NULL, "opening_cash_minor" INTEGER NOT NULL CHECK("opening_cash_minor" >= 0), "currency" TEXT NOT NULL, PRIMARY KEY ("organization_id", "branch_id", "id"));
CREATE TABLE "sync_cursors" ("organization_id" TEXT NOT NULL, "branch_id" TEXT NOT NULL, "id" TEXT NOT NULL, "cursor" TEXT NOT NULL, "updated_at" INTEGER NOT NULL, PRIMARY KEY ("organization_id", "branch_id", "id"));
CREATE TABLE "sync_outbox" ("organization_id" TEXT NOT NULL, "branch_id" TEXT NOT NULL, "id" TEXT NOT NULL, "device_id" TEXT NOT NULL, "actor_id" TEXT NOT NULL, "document_id" TEXT NOT NULL, "event_type" TEXT NOT NULL, "schema_version" INTEGER NOT NULL DEFAULT 1, "payload_json" TEXT NOT NULL, "payload_digest" TEXT NOT NULL, "occurred_at_iso" TEXT NOT NULL, "status" TEXT NOT NULL DEFAULT 'PENDING', "attempts" INTEGER NOT NULL DEFAULT 0, "lease_owner" TEXT NULL, "lease_token" TEXT NULL, "lease_until" INTEGER NULL, "next_attempt_at" INTEGER NULL, "last_error" TEXT NULL, "created_at" INTEGER NOT NULL, "accepted_at" INTEGER NULL, "server_receipt_id" TEXT NULL, PRIMARY KEY ("organization_id", "branch_id", "id"), UNIQUE ("organization_id", "device_id", "id"), UNIQUE ("organization_id", "branch_id", "document_id", "event_type"), CHECK (status IN ('PENDING', 'SYNCING', 'SYNCED', 'FAILED')), CHECK (attempts >= 0), CHECK (schema_version = 1), CHECK ((status = 'SYNCING' AND lease_owner IS NOT NULL AND lease_token IS NOT NULL AND lease_until IS NOT NULL) OR (status != 'SYNCING' AND lease_owner IS NULL AND lease_token IS NULL AND lease_until IS NULL)), CHECK (status != 'SYNCED' OR (accepted_at IS NOT NULL AND server_receipt_id IS NOT NULL)));
CREATE TRIGGER local_payments_immutable_delete
BEFORE DELETE ON local_payments
BEGIN SELECT RAISE(ABORT, 'Financial records are append-only'); END;
CREATE TRIGGER local_payments_immutable_update
BEFORE UPDATE ON local_payments
BEGIN SELECT RAISE(ABORT, 'Financial records are append-only'); END;
CREATE TRIGGER local_payments_sealed_sale BEFORE INSERT ON local_payments
WHEN EXISTS (
 SELECT 1 FROM sync_outbox WHERE organization_id = NEW.organization_id
 AND branch_id = NEW.branch_id AND document_id = NEW.sale_id
 AND event_type = 'sale.created'
)
BEGIN SELECT RAISE(ABORT, 'A persisted sale is complete and immutable'); END;
CREATE TRIGGER local_sale_items_immutable_delete
BEFORE DELETE ON local_sale_items
BEGIN SELECT RAISE(ABORT, 'Financial records are append-only'); END;
CREATE TRIGGER local_sale_items_immutable_update
BEFORE UPDATE ON local_sale_items
BEGIN SELECT RAISE(ABORT, 'Financial records are append-only'); END;
CREATE TRIGGER local_sale_items_sealed_sale BEFORE INSERT ON local_sale_items
WHEN EXISTS (
 SELECT 1 FROM sync_outbox WHERE organization_id = NEW.organization_id
 AND branch_id = NEW.branch_id AND document_id = NEW.sale_id
 AND event_type = 'sale.created'
)
BEGIN SELECT RAISE(ABORT, 'A persisted sale is complete and immutable'); END;
CREATE TRIGGER local_sales_immutable_delete
BEFORE DELETE ON local_sales
BEGIN SELECT RAISE(ABORT, 'Financial records are append-only'); END;
CREATE TRIGGER local_sales_immutable_update
BEFORE UPDATE ON local_sales
BEGIN SELECT RAISE(ABORT, 'Financial records are append-only'); END;
CREATE TRIGGER local_shifts_immutable_delete
BEFORE DELETE ON local_shifts
BEGIN SELECT RAISE(ABORT, 'Financial records are append-only'); END;
CREATE TRIGGER local_shifts_immutable_update
BEFORE UPDATE ON local_shifts
BEGIN SELECT RAISE(ABORT, 'Financial records are append-only'); END;
CREATE TRIGGER sync_outbox_immutable_payload BEFORE UPDATE ON sync_outbox
WHEN NEW.organization_id != OLD.organization_id
 OR NEW.branch_id != OLD.branch_id OR NEW.id != OLD.id
 OR NEW.device_id != OLD.device_id OR NEW.actor_id != OLD.actor_id
 OR NEW.document_id != OLD.document_id OR NEW.event_type != OLD.event_type
 OR NEW.schema_version != OLD.schema_version
 OR NEW.payload_json != OLD.payload_json OR NEW.payload_digest != OLD.payload_digest
 OR NEW.occurred_at_iso != OLD.occurred_at_iso
 OR NEW.created_at != OLD.created_at
BEGIN SELECT RAISE(ABORT, 'Outbox event content is immutable'); END;
CREATE TRIGGER sync_outbox_no_delete BEFORE DELETE ON sync_outbox
BEGIN SELECT RAISE(ABORT, 'Outbox events must be preserved'); END;
PRAGMA user_version = 1;
