// Test gateways intentionally return promises while simulating immediate responses.
// deno-lint-ignore-file require-await
import {
  createOfflineHandler,
  type OfflineGateway,
  type Scope,
} from "../../supabase/functions/offline-sync/core.ts";
import {
  base64url,
  canonicalJson,
  decodeBase64url,
  digest,
  GrantSigner,
  type JsonObject,
  object,
  OfflineError,
  signatureBytes,
  utcMicroseconds,
  utcTime,
  verifySignature,
} from "../../supabase/functions/offline-sync/protocol.ts";
import { createSupabaseOfflineGateway } from "../../supabase/functions/offline-sync/supabase_gateway.ts";

function assert(value: unknown, message = "assertion failed"): asserts value {
  if (!value) throw new Error(message);
}
function equal(actual: unknown, expected: unknown) {
  assert(
    JSON.stringify(actual) === JSON.stringify(expected),
    `${JSON.stringify(actual)} != ${JSON.stringify(expected)}`,
  );
}
function hex(value: string): Uint8Array<ArrayBuffer> {
  return Uint8Array.from(
    value.match(/../g) ?? [],
    (byte) => parseInt(byte, 16),
  );
}
function throws(action: () => unknown) {
  let failed = false;
  try {
    action();
  } catch {
    failed = true;
  }
  assert(failed);
}
const seed = "9d61b19deffd5a60ba844af492ec2cc44449c5697b326919703bac031cae7f60";
const pkcs8 = hex(`302e020100300506032b657004220420${seed}`);
const publicKey = base64url(
  hex("d75a980182b10ab7d54bfed3c964073a0ee172f3daa62325af021a68f707511a"),
);
const signer = await GrantSigner.fromPkcs8(
  "https://project.supabase.co",
  "test-v1",
  base64url(pkcs8),
);
const deviceKey = await crypto.subtle.importKey(
  "pkcs8",
  pkcs8,
  "Ed25519",
  false,
  ["sign"],
);
const actor = "11111111-1111-4111-8111-111111111111";
const scope: Scope = {
  organization_id: "22222222-2222-4222-8222-222222222222",
  branch_id: "33333333-3333-4333-8333-333333333333",
  device_id: "44444444-4444-4444-8444-444444444444",
};
const grantId = "55555555-5555-4555-8555-555555555555";
const requestId = "66666666-6666-4666-8666-666666666666";
const paymentId = "77777777-7777-4777-8777-777777777777";
const eventId = "88888888-8888-4888-8888-888888888888";
const saleId = "99999999-9999-4999-8999-999999999999";
const serverId = "aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa";
const challengeId = "bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb";
const productId = "cccccccc-cccc-4ccc-8ccc-cccccccccccc";
const lineId = "dddddddd-dddd-4ddd-8ddd-dddddddddddd";
const snapshot = {
  context: {
    organization_id: scope.organization_id,
    branch_id: scope.branch_id,
    branch_name: "Unit test branch",
    branch_code: "TEST",
    currency: "PHP",
    tax_bps: 1200,
    settings_revision: 1,
    business_name: "Test fixture",
    address: null,
    contact: null,
    receipt_footer: null,
  },
  shift: {
    id: requestId,
    organization_id: scope.organization_id,
    branch_id: scope.branch_id,
    actor_user_id: actor,
    currency: "PHP",
    closure: null,
    opened_at: "2026-10-09T23:59:00.000Z",
  },
  products: [{
    id: productId,
    organization_id: scope.organization_id,
    category_id: null,
    sku: "TEST",
    barcode: null,
    name: "Unit test product",
    unit: "each",
    price_minor: 100,
    currency: "PHP",
    active: true,
    revision: 1,
    available_quantity: 2,
  }],
  categories: [],
  stock: [{ product_id: productId, quantity: 2, revision: 1 }],
  cursor: 0,
};
const claims: JsonObject = {
  schema_version: 1,
  issuer: signer.issuer,
  audience: "nexapos.offline.v1",
  key_id: signer.keyId,
  grant_id: grantId,
  ...scope,
  actor_id: actor,
  membership_id: requestId,
  role: "cashier",
  business_name: "Test fixture",
  allowed_actions: ["sale.created"],
  issued_at: "2026-10-10T00:00:00.000Z",
  expires_at: "2026-10-10T08:00:00.000Z",
  shift_id: requestId,
  currency: "PHP",
  tax_bps: 1200,
  settings_revision: 1,
  snapshot_digest: await digest(snapshot),
  max_events: 1000,
  max_total_minor: 100000000,
};
const grant = { claims, signature: await signer.sign(claims) };
const challenge: JsonObject = {
  challenge_id: challengeId,
  nonce: base64url(new Uint8Array(32).fill(9)),
  ...scope,
  actor_id: actor,
  public_key: publicKey,
  expires_at: "2026-10-10T00:05:00.000Z",
};
async function sign(
  domain: "enroll" | "event" | "release",
  value: unknown,
): Promise<string> {
  return base64url(
    new Uint8Array(
      await crypto.subtle.sign(
        "Ed25519",
        deviceKey,
        signatureBytes(domain, value),
      ),
    ),
  );
}
const event: JsonObject = {
  ...scope,
  actor_id: actor,
  event_id: eventId,
  event_type: "sale.created",
  occurred_at: "2026-10-10T01:02:03.123456Z",
  schema_version: 1,
  payload: {
    id: saleId,
    shift_id: requestId,
    customer_id: null,
    receipt_number: "OFF-TEST",
    currency: "PHP",
    subtotal_minor: 100,
    discount_minor: 0,
    tax_minor: 12,
    total_minor: 112,
    items: [{
      id: lineId,
      product_id: productId,
      sku_snapshot: "TEST",
      name_snapshot: "Unit test product",
      quantity: 1,
      unit_price_minor: 100,
      discount_minor: 0,
      tax_minor: 12,
      line_total_minor: 112,
    }],
    payments: [{
      id: paymentId,
      method: "cash",
      amount_minor: 112,
      reference: null,
      verification_mode: "cash",
    }],
  },
};
const authorization = {
  grant_id: grantId,
  sequence: 1,
  payment_evidence: { [paymentId]: { tendered_minor: 10000 } },
};
const eventDigest = await digest(event);
const envelope = {
  event,
  digest: eventDigest,
  authorization,
  signature: await sign("event", {
    event_digest: eventDigest,
    ...authorization,
  }),
};
const acceptance: JsonObject = {
  status: "accepted",
  ...scope,
  actor_id: actor,
  grant_id: grantId,
  sequence: 1,
  event_id: eventId,
  digest: eventDigest,
  document_id: saleId,
  server_receipt_id: serverId,
  accepted_at: "2026-10-10T01:03:00.000Z",
  receipt: {
    id: serverId,
    organization_id: scope.organization_id,
    branch_id: scope.branch_id,
    actor_user_id: actor,
    request_id: eventId,
    shift_id: requestId,
    currency: "PHP",
    tax_bps: 1200,
    settings_revision: 1,
    customer_id: null,
    subtotal_minor: 100,
    discount_minor: 0,
    tax_minor: 12,
    total_minor: 112,
    created_at: event.occurred_at,
    items: [{
      id: lineId,
      product_id: productId,
      sku: "TEST",
      product_name: "Unit test product",
      quantity: 1,
      unit_price_minor: 100,
      discount_minor: 0,
      tax_minor: 12,
      line_total_minor: 112,
      sale_id: serverId,
      organization_id: scope.organization_id,
    }],
    payments: [{
      id: paymentId,
      method: "cash",
      amount_minor: 112,
      reference: null,
      tendered_minor: 10000,
      change_minor: 9888,
      manual_confirmed: false,
      sale_id: serverId,
      organization_id: scope.organization_id,
    }],
  },
  stock_impacts: [{ product_id: productId, revision: 2 }],
};

function fixture() {
  const calls: string[] = [];
  const gateway: OfflineGateway = {
    authorize: async () => {},
    verifyUser: async () => {
      calls.push("auth");
      return { id: actor, emailVerified: true };
    },
    challenge: async () => {
      calls.push("challenge");
      return challenge;
    },
    context: async () => {
      calls.push("context");
      return { public_key: publicKey, grant, challenge };
    },
    enroll: async () => {
      calls.push("enroll");
      return {
        ...scope,
        actor_id: actor,
        public_key: publicKey,
        enrolled_at: claims.issued_at,
      };
    },
    prepare: async () => {
      calls.push("prepare");
      return { claims, snapshot, server_time: claims.issued_at };
    },
    finalize: async (_actor, _scope, _grantId, retainedClaims, signature) => {
      calls.push("finalize");
      return {
        grant: { claims: retainedClaims, signature },
        snapshot,
        server_time: claims.issued_at,
      };
    },
    ingest: async () => {
      calls.push("ingest");
      return acceptance;
    },
    pull: async () => {
      calls.push("pull");
      return {
        cursor: 1,
        has_more: false,
        changes: [],
        server_time: claims.issued_at,
      };
    },
    release: async (_actor, _scope, _grant, sequence) => {
      calls.push("release");
      return {
        ...scope,
        actor_id: actor,
        grant_id: grantId,
        status: "released",
        final_sequence: sequence,
        released_at: claims.issued_at,
      };
    },
  };
  const handler = createOfflineHandler({
    gateway,
    signer,
    allowedOrigins: new Set(["https://pos.example"]),
  });
  const request = (
    input: unknown,
    options?: { token?: string; origin?: string },
  ) =>
    new Request("https://project.supabase.co/functions/v1/offline-sync", {
      method: "POST",
      headers: {
        "Content-Type": "application/json",
        Authorization: `Bearer ${options?.token ?? "user-token"}`,
        ...(options?.origin ? { Origin: options.origin } : {}),
      },
      body: JSON.stringify(input),
    });
  const call = (
    action: string,
    fields: JsonObject = {},
    options?: { token?: string; origin?: string },
  ) => handler(request({ action, ...scope, ...fields }, options));
  return { calls, gateway, handler, request, call };
}

Deno.test("RFC8032 Ed25519 vector verifies against native WebCrypto", async () => {
  const key = await crypto.subtle.importKey(
    "raw",
    decodeBase64url(publicKey, 32),
    "Ed25519",
    false,
    ["verify"],
  );
  assert(
    await crypto.subtle.verify(
      "Ed25519",
      key,
      hex(
        "e5564300c360ac729086e2cc806e828a84877f1eb8e5d974d873e065224901555fb8821590a33bacc61e39701cf9b46bd25bf5f0595bbe24655141438e7a100b",
      ),
      new Uint8Array(),
    ),
  );
  equal(signer.publicKey, publicKey);
});
Deno.test("canonical encoding preserves lexical numeric keys and exact Unicode", () => {
  equal(
    canonicalJson({
      "2": 2,
      "10": 10,
      z: ["café 👩🏽‍💻", 'line\nquote"', 9007199254740991],
      a: true,
    }),
    '{"10":10,"2":2,"a":true,"z":["café 👩🏽‍💻","line\\nquote\\"",9007199254740991]}',
  );
  for (
    const bad of [-0, 0.1, Infinity, 9007199254740992, "\ud800", {
      invalid: undefined,
    }]
  ) throws(() => canonicalJson(bad));
});
Deno.test("binary encoding rejects padding and noncanonical trailing bits", () => {
  equal([...decodeBase64url("_w", 1)], [255]);
  for (const bad of ["_w==", "_x", "a", "+w"]) {
    throws(() => decodeBase64url(bad));
  }
});
Deno.test("UTC validation preserves microseconds and rejects normalized calendar dates", () => {
  equal(
    utcMicroseconds("2026-10-10T00:00:00.123456Z").toString(),
    "1791590400123456",
  );
  equal(utcTime("2026-10-10T00:00:00.123Z"), 1791590400123);
  for (
    const invalid of [
      "2026-02-30T00:00:00Z",
      "2026-01-01T24:00:00Z",
      "2026-13-01T00:00:00Z",
      "2026-01-01T00:00:60Z",
    ]
  ) {
    throws(() => utcTime(invalid));
  }
});
Deno.test("grant signatures bind issuer and domain", async () => {
  assert(await verifySignature(publicKey, grant.signature, "grant", claims));
  assert(!await verifySignature(publicKey, grant.signature, "event", claims));
  assert(
    !await verifySignature(publicKey, grant.signature, "grant", {
      ...claims,
      issuer: "https://other.supabase.co",
    }),
  );
});
Deno.test("CORS and method checks run before privileged calls", async () => {
  const f = fixture();
  equal(
    (await f.call("prepare", { request_id: requestId }, {
      origin: "https://evil.example",
    })).status,
    403,
  );
  equal(
    (await f.handler(new Request("https://example.test", { method: "GET" })))
      .status,
    405,
  );
  const preflight = await f.handler(
    new Request("https://example.test", {
      method: "OPTIONS",
      headers: { Origin: "https://pos.example" },
    }),
  );
  equal(preflight.status, 204);
  equal(
    preflight.headers.get("access-control-allow-origin"),
    "https://pos.example",
  );
  equal(f.calls, []);
});
Deno.test("unverified or unavailable Auth never grants business access", async () => {
  const f = fixture();
  f.gateway.verifyUser = async () => ({ id: actor, emailVerified: false });
  equal((await f.call("prepare", { request_id: requestId })).status, 401);
  f.gateway.verifyUser = async () => null;
  equal((await f.call("prepare", { request_id: requestId })).status, 401);
  equal(f.calls, []);
});
Deno.test("request schema rejects caller actor, bad UUID, and oversized streaming body", async () => {
  const f = fixture();
  equal(
    (await f.call("prepare", { request_id: requestId, actor_id: actor }))
      .status,
    400,
  );
  equal((await f.call("prepare", { request_id: "bad" })).status, 400);
  const body = new ReadableStream<Uint8Array>({
    start(controller) {
      controller.enqueue(new Uint8Array(262145));
      controller.close();
    },
  });
  equal(
    (await f.handler(
      new Request("https://example.test", {
        method: "POST",
        headers: {
          Authorization: "Bearer token",
          "Content-Type": "application/json",
        },
        body,
      }),
    )).status,
    413,
  );
});
Deno.test("enrollment verifies the retained challenge rather than caller-supplied identity", async () => {
  const f = fixture();
  equal(
    (await f.call("enroll_challenge", {
      public_key: publicKey,
      device_name: "Unit test device",
      platform: "linux",
    })).status,
    200,
  );
  equal(
    (await f.call("enroll", {
      challenge_id: challengeId,
      signature: await sign("enroll", challenge),
    })).status,
    200,
  );
  equal(f.calls.filter((name) => name === "enroll").length, 1);
  equal(
    (await f.call("enroll", {
      challenge_id: challengeId,
      signature: await sign("enroll", { ...challenge, branch_id: requestId }),
    })).status,
    403,
  );
  equal(f.calls.filter((name) => name === "enroll").length, 1);
});
Deno.test("preparation signs only retained scope-matched snapshot after finalization", async () => {
  const f = fixture();
  const response = await f.call("prepare", { request_id: requestId });
  equal(response.status, 200);
  const data = await response.json();
  assert(
    await verifySignature(
      publicKey,
      data.grant.signature,
      "grant",
      data.grant.claims,
    ),
  );
  equal(f.calls, ["auth", "prepare", "finalize"]);
  f.gateway.finalize = async () => {
    throw new OfflineError("unavailable");
  };
  equal((await f.call("prepare", { request_id: requestId })).status, 503);
});
Deno.test("changed snapshot and oversized grant lifetime cannot be signed", async () => {
  const f = fixture();
  f.gateway.prepare = async () => ({
    claims,
    snapshot: { ...snapshot, cursor: 1 },
    server_time: claims.issued_at,
  });
  equal((await f.call("prepare", { request_id: requestId })).status, 503);
  f.gateway.prepare = async () => ({
    claims: { ...claims, expires_at: "2026-10-11T08:00:00.000Z" },
    snapshot,
    server_time: claims.issued_at,
  });
  equal((await f.call("prepare", { request_id: requestId })).status, 400);
  assert(!f.calls.includes("finalize"));
});
Deno.test("one microsecond beyond eight hours and malformed finalization fail closed", async () => {
  const f = fixture();
  f.gateway.prepare = async () => ({
    claims: { ...claims, expires_at: "2026-10-10T08:00:00.000001Z" },
    snapshot,
    server_time: claims.issued_at,
  });
  equal((await f.call("prepare", { request_id: requestId })).status, 400);
  f.gateway.prepare = async () => ({
    claims,
    snapshot,
    server_time: claims.issued_at,
  });
  f.gateway.finalize = async () => ({
    grant: { ...grant, signature: "changed" },
    snapshot,
    server_time: claims.issued_at,
  });
  equal((await f.call("prepare", { request_id: requestId })).status, 503);
});
Deno.test("preparation never signs a hidden-cost or foreign-scope snapshot", async () => {
  for (
    const changed of [
      { ...snapshot, products: [{ ...snapshot.products[0], cost_minor: 99 }] },
      { ...snapshot, context: { ...snapshot.context, organization_id: actor } },
      { ...snapshot, stock: [] },
    ]
  ) {
    const f = fixture();
    f.gateway.prepare = async () => ({
      claims: { ...claims, snapshot_digest: await digest(changed) },
      snapshot: changed,
      server_time: claims.issued_at,
    });
    equal((await f.call("prepare", { request_id: requestId })).status, 503);
    assert(!f.calls.includes("finalize"));
  }
});
Deno.test("lost preparation recovers retained expired grant across trusted key rotation", async () => {
  const f = fixture();
  f.gateway.prepare = async () => ({
    claims,
    snapshot,
    signature: grant.signature,
    server_time: "2026-10-10T09:00:00.000Z",
  });
  const rotated = await GrantSigner.fromPkcs8(
    signer.issuer,
    "test-v2",
    base64url(
      hex(
        "302e020100300506032b6570042204204ccd089b28ff96da9db6c346ec114e0f5b8a319f35aba624da8cf6ed4fb8a6fb",
      ),
    ),
  );
  const handler = createOfflineHandler({
    gateway: f.gateway,
    signer: rotated,
    allowedOrigins: new Set(),
    verificationKeys: new Map([[signer.keyId, publicKey]]),
  });
  const response = await handler(
    f.request({ action: "prepare", ...scope, request_id: requestId }),
  );
  equal(response.status, 200);
  const data = await response.json();
  equal(data.grant.signature, grant.signature);
  equal(data.grant.claims.expires_at, claims.expires_at);
  equal(data.server_time, "2026-10-10T09:00:00.000Z");
  const withoutTrust = createOfflineHandler({
    gateway: f.gateway,
    signer: rotated,
    allowedOrigins: new Set(),
  });
  equal(
    (await withoutTrust(
      f.request({ action: "prepare", ...scope, request_id: requestId }),
    )).status,
    503,
  );
  f.gateway.prepare = async () => ({
    claims,
    snapshot,
    server_time: claims.issued_at,
  });
  equal(
    (await handler(
      f.request({ action: "prepare", ...scope, request_id: requestId }),
    )).status,
    503,
  );
});
Deno.test("definitive unsigned preparation abandonment cannot issue a grant", async () => {
  const f = fixture();
  f.gateway.prepare = () =>
    Promise.reject(new OfflineError("preparation_expired"));
  const response = await f.call("prepare", { request_id: requestId });
  equal(response.status, 409);
  equal(await response.json(), { error: "offline_preparation_expired" });
  equal(f.calls, ["auth"]);
  assert(!f.calls.includes("finalize"));
});
Deno.test("ingest verifies original event hash and detached payment proof", async () => {
  const f = fixture();
  equal((await f.call("ingest", envelope)).status, 200);
  equal(
    (await f.call("ingest", {
      ...envelope,
      event: { ...event, occurred_at: "2026-10-10T01:02:03.123457Z" },
    })).status,
    400,
  );
  equal(
    (await f.call("ingest", {
      ...envelope,
      authorization: { ...authorization, sequence: 2 },
    })).status,
    403,
  );
  equal(f.calls.filter((name) => name === "ingest").length, 1);
});
Deno.test("invalid grant key or signature never invokes ingestion", async () => {
  const f = fixture();
  f.gateway.context = async () => ({
    public_key: publicKey,
    grant: { claims, signature: base64url(new Uint8Array(64)) },
  });
  equal((await f.call("ingest", envelope)).status, 403);
  assert(!f.calls.includes("ingest"));
});
Deno.test("expired grant replay is decided by current SQL authority, not client time", async () => {
  const f = fixture();
  equal((await f.call("ingest", envelope)).status, 200);
  f.gateway.context = async () => {
    throw new OfflineError("denied");
  };
  equal((await f.call("ingest", envelope)).status, 403);
  equal(f.calls.filter((name) => name === "ingest").length, 1);
});
Deno.test("lost ingestion response returns unavailable; exact retry preserves acceptance identity", async () => {
  const f = fixture();
  let first = true;
  f.gateway.ingest = async (_actor, _scope, input) => {
    equal(input.digest, eventDigest);
    if (first) {
      first = false;
      throw new OfflineError("unavailable");
    }
    return acceptance;
  };
  equal((await f.call("ingest", envelope)).status, 503);
  const retry = await f.call("ingest", envelope);
  equal(retry.status, 200);
  equal((await retry.json()).server_receipt_id, serverId);
});
Deno.test("mismatched server acceptance cannot fabricate a matching receipt", async () => {
  const f = fixture();
  f.gateway.ingest = async () => ({ ...acceptance, digest: "0".repeat(64) });
  equal((await f.call("ingest", envelope)).status, 503);
});
Deno.test("receipt amount, line, tender and stock revision uncertainty never completes", async () => {
  const receipt = object(acceptance.receipt);
  const items = receipt.items as JsonObject[];
  const payments = receipt.payments as JsonObject[];
  for (
    const result of [
      { ...acceptance, receipt: { ...receipt, total_minor: 113 } },
      { ...acceptance, receipt: { ...receipt, request_id: requestId } },
      { ...acceptance, receipt: { ...receipt, items: [] } },
      {
        ...acceptance,
        receipt: { ...receipt, items: [{ ...items[0], quantity: 2 }] },
      },
      {
        ...acceptance,
        receipt: {
          ...receipt,
          payments: [{ ...payments[0], tendered_minor: 112 }],
        },
      },
      { ...acceptance, stock_impacts: [] },
      {
        ...acceptance,
        stock_impacts: [{ product_id: productId, revision: 9007199254740992 }],
      },
      {
        ...acceptance,
        stock_impacts: [{ product_id: productId, revision: 2 }, {
          product_id: productId,
          revision: 2,
        }],
      },
    ]
  ) {
    const f = fixture();
    f.gateway.ingest = async () => result;
    equal((await f.call("ingest", envelope)).status, 503);
  }
});
Deno.test("review outcomes remain separate from financial acceptance", async () => {
  const f = fixture();
  f.gateway.ingest = async () => ({
    ...scope,
    actor_id: actor,
    event_id: eventId,
    digest: eventDigest,
    grant_id: grantId,
    sequence: 1,
    document_id: saleId,
    status: "review",
    reconciliation_code: "SHIFT_CLOSED",
    reconciliation_id: serverId,
    recorded_at: claims.issued_at,
  });
  const response = await f.call("ingest", envelope);
  equal(response.status, 202);
  equal((await response.json()).status, "review");
});
Deno.test("release binds final sequence and requires exact device signature", async () => {
  const f = fixture();
  const signature = await sign("release", {
    grant_id: grantId,
    final_sequence: 1,
  });
  equal(
    (await f.call("release", {
      grant_id: grantId,
      final_sequence: 1,
      signature,
    })).status,
    200,
  );
  equal(
    (await f.call("release", {
      grant_id: grantId,
      final_sequence: 2,
      signature,
    })).status,
    403,
  );
  equal(f.calls.filter((name) => name === "release").length, 1);
});
Deno.test("pull limits and server failures are sanitized", async () => {
  const f = fixture();
  equal((await f.call("pull", { cursor: 0, limit: 101 })).status, 400);
  f.gateway.pull = async () => {
    throw new Error("private backend credential must not escape");
  };
  const response = await f.call("pull", { cursor: 0 });
  equal(response.status, 503);
  equal(await response.json(), { error: "offline_unavailable" });
});
Deno.test("malformed pull cursors and secret-cost fields remain unavailable", async () => {
  for (
    const result of [
      {
        cursor: -1,
        has_more: false,
        changes: [],
        server_time: claims.issued_at,
      },
      { cursor: 1, has_more: true, changes: [], server_time: claims.issued_at },
      {
        cursor: 1,
        has_more: false,
        changes: [{
          kind: "product",
          id: productId,
          revision: 1,
          deleted: false,
          value: { ...snapshot.products[0], cost_minor: 99 },
        }],
        server_time: claims.issued_at,
      },
    ]
  ) {
    const f = fixture();
    f.gateway.pull = async () => result;
    equal((await f.call("pull", { cursor: 0 })).status, 503);
  }
});
Deno.test("REST gateway keeps service privilege off Auth and challenge requests", async () => {
  const requests: {
    path: string;
    token: string | null;
    key: string | null;
    body: Record<string, unknown> | null;
  }[] = [];
  const gateway = createSupabaseOfflineGateway({
    url: signer.issuer,
    publicKey: "public-key",
    serviceRoleKey: "service-only-secret",
    fetch: async (input, init) => {
      const headers = new Headers(init?.headers);
      const path = new URL(String(input)).pathname;
      equal(init?.redirect, "error");
      requests.push({
        path,
        token: headers.get("authorization"),
        key: headers.get("apikey"),
        body: init?.body ? JSON.parse(String(init.body)) : null,
      });
      return new Response(
        JSON.stringify(
          path.endsWith("/user")
            ? { id: actor, email_confirmed_at: claims.issued_at }
            : {},
        ),
        { status: 200 },
      );
    },
  });
  assert((await gateway.verifyUser("verified-user-token"))?.emailVerified);
  await gateway.challenge("verified-user-token", {
    ...scope,
    public_key: publicKey,
  });
  await gateway.prepare(actor, scope, requestId, signer.issuer, signer.keyId);
  await gateway.ingest(actor, scope, envelope);
  equal(requests[0].token, "Bearer verified-user-token");
  equal(requests[0].key, "public-key");
  equal(requests[1].token, "Bearer verified-user-token");
  equal(requests[1].key, "public-key");
  assert(!("p_actor_id" in requests[1].body!));
  equal(requests[2].token, "Bearer service-only-secret");
  equal(requests[2].body?.p_actor_id, actor);
  equal(requests[3].body?.p_event, event);
  equal(requests[3].body?.p_authorization, authorization);
});
Deno.test("REST adapter maps authority and rate errors without provider detail", async () => {
  for (
    const [code, expected] of [
      ["42501", "denied"],
      ["NX001", "rate_limited"],
      ["NX002", "preparation_expired"],
      ["23505", "conflict"],
      ["22023", "invalid"],
      ["XX000", "unavailable"],
    ]
  ) {
    const gateway = createSupabaseOfflineGateway({
      url: signer.issuer,
      publicKey: "public",
      serviceRoleKey: "secret",
      fetch: async () =>
        new Response(
          JSON.stringify({ code, message: "sensitive SQL detail" }),
          { status: 400 },
        ),
    });
    try {
      await gateway.pull(actor, scope, 0, 10);
      throw new Error("expected failure");
    } catch (error) {
      assert(error instanceof OfflineError);
      equal(error.kind, expected);
    }
  }
});

Deno.test("AAL authorization denial stops every fresh offline privileged action", async () => {
  for (
    const action of ["enroll_challenge", "enroll", "prepare", "pull", "release"]
  ) {
    const f = fixture();
    f.gateway.authorize = (token, receivedScope, receivedAction) => {
      equal(token, "user-token");
      equal(receivedScope, scope);
      equal(receivedAction, action.startsWith("enroll") ? "enroll" : action);
      return Promise.reject(new OfflineError("denied"));
    };
    const response = await f.call(action);
    equal(response.status, 403);
    equal(f.calls, ["auth"]);
  }
});

Deno.test("original signed paid ingest remains reachable for review at AAL1", async () => {
  const f = fixture();
  f.gateway.authorize = () =>
    Promise.reject(new Error("Must not require new capture assurance"));
  const response = await f.call("ingest", envelope);
  equal(response.status, 200);
  assert(f.calls.includes("ingest"));
});

Deno.test("authorization lease uses actual user bearer and excludes service actor claims", async () => {
  let sent: RequestInit | undefined;
  const gateway = createSupabaseOfflineGateway({
    url: signer.issuer,
    publicKey: "public-test-key",
    serviceRoleKey: "service-test-key",
    fetch: (input, init) => {
      equal(
        new URL(String(input)).pathname,
        "/rest/v1/rpc/authorize_offline_operation",
      );
      sent = init;
      return Promise.resolve(
        new Response(
          JSON.stringify({ authorized: true, expires_at: claims.expires_at }),
          { status: 200 },
        ),
      );
    },
  });
  await gateway.authorize("verified-user-token", scope, "prepare");
  const headers = new Headers(sent!.headers);
  equal(headers.get("authorization"), "Bearer verified-user-token");
  equal(headers.get("apikey"), "public-test-key");
  equal(sent!.redirect, "error");
  equal(JSON.parse(String(sent!.body)), {
    p_organization_id: scope.organization_id,
    p_branch_id: scope.branch_id,
    p_device_id: scope.device_id,
    p_action: "prepare",
  });
});

Deno.test("malformed or false user-context authorization lease fails closed", async () => {
  for (
    const response of [
      {},
      { authorized: false, expires_at: claims.expires_at },
      { authorized: true, expires_at: "invalid" },
    ]
  ) {
    const gateway = createSupabaseOfflineGateway({
      url: signer.issuer,
      publicKey: "public-test-key",
      serviceRoleKey: "service-test-key",
      fetch: () =>
        Promise.resolve(
          new Response(JSON.stringify(response), { status: 200 }),
        ),
    });
    let denied = false;
    try {
      await gateway.authorize("verified-user-token", scope, "prepare");
    } catch (error) {
      denied = error instanceof OfflineError;
    }
    assert(denied);
  }
});
