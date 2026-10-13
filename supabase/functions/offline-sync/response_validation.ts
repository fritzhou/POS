import { type Scope } from "./core.ts";
import {
  canonicalJson,
  integer,
  isUuid,
  type JsonObject,
  object,
  OfflineError,
  strictKeys,
  utcTime,
} from "./protocol.ts";

/** A malformed service response is uncertainty, never a synthetic acceptance. */
export function checkedResponse<T>(validate: () => T): T {
  try {
    return validate();
  } catch {
    throw new OfflineError("unavailable");
  }
}

function require(value: unknown): asserts value {
  if (!value) throw new OfflineError("invalid");
}

function uuid(value: unknown): string {
  require(isUuid(value) && value === value.toLowerCase());
  return value as string;
}

function scoped(value: JsonObject, actor: string, scope: Scope) {
  require(
    value.actor_id === actor &&
      value.organization_id === scope.organization_id &&
      value.branch_id === scope.branch_id &&
      value.device_id === scope.device_id,
  );
}

function rows(value: unknown, maximum = 1000): JsonObject[] {
  require(Array.isArray(value) && value.length <= maximum);
  return (value as unknown[]).map(object);
}

export function validateSnapshot(
  snapshot: JsonObject,
  claims: JsonObject,
  actor: string,
  scope: Scope,
): void {
  canonicalJson(snapshot);
  strictKeys(snapshot, [
    "context",
    "shift",
    "products",
    "categories",
    "stock",
    "cursor",
  ], ["context", "shift", "products", "categories", "stock", "cursor"]);
  integer(snapshot.cursor, 0, Number.MAX_SAFE_INTEGER);
  const context = object(snapshot.context);
  strictKeys(context, [
    "organization_id",
    "branch_id",
    "branch_name",
    "branch_code",
    "currency",
    "tax_bps",
    "settings_revision",
    "business_name",
    "address",
    "contact",
    "receipt_footer",
  ]);
  require(
    context.organization_id === scope.organization_id &&
      context.branch_id === scope.branch_id &&
      context.currency === claims.currency &&
      context.tax_bps === claims.tax_bps &&
      context.settings_revision === claims.settings_revision &&
      context.business_name === claims.business_name,
  );
  const shift = object(snapshot.shift);
  require(
    shift.id === claims.shift_id &&
      shift.organization_id === scope.organization_id &&
      shift.branch_id === scope.branch_id && shift.actor_user_id === actor &&
      shift.currency === claims.currency && shift.closure === null,
  );
  utcTime(shift.opened_at);
  const products = rows(snapshot.products);
  const productIds = new Set<string>();
  for (const product of products) {
    strictKeys(product, [
      "id",
      "organization_id",
      "category_id",
      "sku",
      "barcode",
      "name",
      "unit",
      "price_minor",
      "currency",
      "active",
      "revision",
      "available_quantity",
    ]);
    const id = uuid(product.id);
    require(!productIds.has(id));
    productIds.add(id);
    require(
      product.organization_id === scope.organization_id &&
        product.currency === claims.currency && product.active === true &&
        typeof product.name === "string" && product.name.length > 0 &&
        typeof product.sku === "string" && typeof product.unit === "string",
    );
    if (product.category_id !== null) uuid(product.category_id);
    require(product.barcode === null || typeof product.barcode === "string");
    integer(product.price_minor, 0, Number.MAX_SAFE_INTEGER);
    integer(product.revision, 1, Number.MAX_SAFE_INTEGER);
    integer(
      product.available_quantity,
      -Number.MAX_SAFE_INTEGER,
      Number.MAX_SAFE_INTEGER,
    );
  }
  const categories = rows(snapshot.categories, Number.MAX_SAFE_INTEGER);
  const categoryIds = new Set<string>();
  for (const category of categories) {
    strictKeys(category, [
      "id",
      "organization_id",
      "name",
      "active",
      "revision",
    ]);
    const id = uuid(category.id);
    require(!categoryIds.has(id));
    categoryIds.add(id);
    require(
      category.organization_id === scope.organization_id &&
        category.active === true &&
        typeof category.name === "string" && category.name.length > 0,
    );
    integer(category.revision, 1, Number.MAX_SAFE_INTEGER);
  }
  const stock = rows(snapshot.stock);
  require(stock.length === products.length);
  const stockIds = new Set<string>();
  for (const balance of stock) {
    strictKeys(balance, ["product_id", "quantity", "revision"], [
      "product_id",
      "quantity",
      "revision",
    ]);
    const id = uuid(balance.product_id);
    require(productIds.has(id) && !stockIds.has(id));
    stockIds.add(id);
    integer(
      balance.quantity,
      -Number.MAX_SAFE_INTEGER,
      Number.MAX_SAFE_INTEGER,
    );
    integer(balance.revision, 0, Number.MAX_SAFE_INTEGER);
    require(
      products.find((product) => product.id === id)?.available_quantity ===
        balance.quantity,
    );
  }
}

export function validateEnrollment(
  result: JsonObject,
  actor: string,
  scope: Scope,
  publicKey: unknown,
): void {
  canonicalJson(result);
  scoped(result, actor, scope);
  require(result.public_key === publicKey);
  utcTime(result.enrolled_at);
}

export function validateOutcome(
  result: JsonObject,
  actor: string,
  scope: Scope,
  envelope: { event: JsonObject; authorization: JsonObject; digest: string },
  claims: JsonObject,
): void {
  canonicalJson(result);
  scoped(result, actor, scope);
  const payload = object(envelope.event.payload);
  require(
    ["accepted", "review"].includes(String(result.status)) &&
      result.event_id === envelope.event.event_id &&
      result.digest === envelope.digest &&
      result.grant_id === envelope.authorization.grant_id &&
      result.sequence === envelope.authorization.sequence &&
      result.document_id === payload.id,
  );
  uuid(result.document_id);
  if (result.reconciliation_code !== undefined) {
    require(
      typeof result.reconciliation_code === "string" &&
        /^[A-Z_]{1,80}$/.test(result.reconciliation_code),
    );
    uuid(result.reconciliation_id);
  }
  if (result.status === "review") {
    require(
      result.reconciliation_code !== undefined &&
        result.server_receipt_id === undefined && result.receipt === undefined,
    );
    utcTime(result.recorded_at);
    return;
  }
  const receiptId = uuid(result.server_receipt_id);
  const receipt = object(result.receipt);
  require(
    receipt.id === receiptId &&
      receipt.organization_id === scope.organization_id &&
      receipt.branch_id === scope.branch_id &&
      receipt.actor_user_id === actor &&
      receipt.request_id === envelope.event.event_id &&
      receipt.shift_id === claims.shift_id &&
      receipt.currency === claims.currency &&
      receipt.tax_bps === claims.tax_bps &&
      receipt.settings_revision === claims.settings_revision &&
      receipt.customer_id === null,
  );
  for (
    const field of [
      "subtotal_minor",
      "discount_minor",
      "tax_minor",
      "total_minor",
    ]
  ) {
    integer(receipt[field], 0, Number.MAX_SAFE_INTEGER);
    require(receipt[field] === payload[field]);
  }
  utcTime(result.accepted_at);
  utcTime(receipt.created_at);
  const originals = rows(payload.items, 100);
  const items = rows(receipt.items, 100);
  require(items.length === originals.length && items.length > 0);
  const itemIds = new Set<string>();
  const productIds = new Set<string>();
  for (const item of items) {
    const id = uuid(item.id);
    const original = originals.find((line) => line.id === id);
    require(original && !itemIds.has(id));
    itemIds.add(id);
    require(
      item.sale_id === receiptId &&
        item.organization_id === scope.organization_id,
    );
    for (
      const field of [
        "product_id",
        "quantity",
        "unit_price_minor",
        "discount_minor",
        "tax_minor",
        "line_total_minor",
      ]
    ) {
      require(item[field] === original[field]);
    }
    require(
      item.sku === original.sku_snapshot &&
        item.product_name === original.name_snapshot,
    );
    productIds.add(uuid(item.product_id));
  }
  const originalPayments = rows(payload.payments, 5);
  const payments = rows(receipt.payments, 5);
  const evidence = object(envelope.authorization.payment_evidence);
  require(payments.length === originalPayments.length && payments.length > 0);
  const paymentIds = new Set<string>();
  for (const payment of payments) {
    const id = uuid(payment.id);
    const original = originalPayments.find((tender) => tender.id === id);
    require(original && !paymentIds.has(id));
    paymentIds.add(id);
    require(
      payment.sale_id === receiptId &&
        payment.organization_id === scope.organization_id,
    );
    for (const field of ["method", "amount_minor", "reference"]) {
      require(payment[field] === original[field]);
    }
    const proof = object(evidence[id]);
    if (original.method === "cash") {
      require(
        payment.tendered_minor === proof.tendered_minor &&
          payment.manual_confirmed === false,
      );
      require(
        payment.change_minor ===
          integer(proof.tendered_minor, 1, Number.MAX_SAFE_INTEGER) -
            integer(original.amount_minor, 1, Number.MAX_SAFE_INTEGER),
      );
    } else {require(
        payment.manual_confirmed === true && proof.manual_confirmed === true,
      );}
  }
  const impacts = rows(result.stock_impacts, 100);
  require(impacts.length === productIds.size);
  const impactIds = new Set<string>();
  for (const impact of impacts) {
    strictKeys(impact, ["product_id", "revision"], ["product_id", "revision"]);
    const id = uuid(impact.product_id);
    require(productIds.has(id) && !impactIds.has(id));
    impactIds.add(id);
    integer(impact.revision, 1, Number.MAX_SAFE_INTEGER);
  }
}

export function validatePull(
  result: JsonObject,
  scope: Scope,
  cursor: number,
  limit: number,
): void {
  canonicalJson(result);
  strictKeys(result, ["cursor", "has_more", "server_time", "changes"], [
    "cursor",
    "has_more",
    "server_time",
    "changes",
  ]);
  const next = integer(result.cursor, cursor, Number.MAX_SAFE_INTEGER);
  require(typeof result.has_more === "boolean");
  utcTime(result.server_time);
  let previous = cursor;
  const changes = rows(result.changes, limit);
  for (const change of changes) {
    strictKeys(change, ["kind", "id", "revision", "deleted", "value"], [
      "kind",
      "id",
      "revision",
      "deleted",
      "value",
    ]);
    uuid(change.id);
    require(
      typeof change.deleted === "boolean" &&
        ["product", "category", "stock", "context"].includes(
          String(change.kind),
        ),
    );
    previous = integer(change.revision, previous + 1, next);
    const value = object(change.value);
    if (change.kind === "stock") {
      strictKeys(value, ["product_id", "quantity", "revision"], [
        "product_id",
        "quantity",
        "revision",
      ]);
      require(value.product_id === change.id);
      integer(
        value.quantity,
        -Number.MAX_SAFE_INTEGER,
        Number.MAX_SAFE_INTEGER,
      );
      integer(value.revision, 1, Number.MAX_SAFE_INTEGER);
    } else {
      require(value.organization_id === scope.organization_id);
      if (change.kind === "context") {
        strictKeys(value, [
          "organization_id",
          "branch_id",
          "branch_name",
          "branch_code",
          "currency",
          "tax_bps",
          "settings_revision",
          "business_name",
          "address",
          "contact",
          "receipt_footer",
        ]);
        require(
          change.id === scope.branch_id && value.branch_id === scope.branch_id,
        );
        integer(value.tax_bps, 0, 10000);
        integer(value.settings_revision, 1, Number.MAX_SAFE_INTEGER);
      } else {
        require(value.id === change.id && value.active === !change.deleted);
        integer(value.revision, 1, Number.MAX_SAFE_INTEGER);
        if (change.kind === "product") {
          strictKeys(value, [
            "id",
            "organization_id",
            "category_id",
            "sku",
            "barcode",
            "name",
            "unit",
            "price_minor",
            "currency",
            "active",
            "revision",
          ]);
          integer(value.price_minor, 0, Number.MAX_SAFE_INTEGER);
        } else {strictKeys(value, [
            "id",
            "organization_id",
            "name",
            "active",
            "revision",
          ]);}
      }
    }
  }
  if (result.has_more) require(changes.length > 0 && next === previous);
}

export function validateRelease(
  result: JsonObject,
  actor: string,
  scope: Scope,
  grantId: string,
  sequence: number,
): void {
  canonicalJson(result);
  scoped(result, actor, scope);
  require(
    result.status === "released" && result.grant_id === grantId &&
      result.final_sequence === sequence,
  );
  utcTime(result.released_at);
}
