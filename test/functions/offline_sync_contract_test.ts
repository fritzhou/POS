import {
  base64url,
  canonicalJson,
  digest,
  GrantSigner,
  object,
  verifySignature,
} from "../../supabase/functions/offline-sync/protocol.ts";
import {
  createOfflineHandler,
  type OfflineGateway,
  type Scope,
} from "../../supabase/functions/offline-sync/core.ts";
import { validateOutcome } from "../../supabase/functions/offline-sync/response_validation.ts";

function assert(value: unknown, message: string): asserts value {
  if (!value) throw new Error(message);
}

Deno.test("Dart, independent Python and native Deno share event digest and Ed25519 domains", async () => {
  const fixture = JSON.parse(
    await Deno.readTextFile(
      new URL("../fixtures/offline_crypto_contract.json", import.meta.url),
    ),
  );
  assert(
    canonicalJson(fixture.event) === fixture.canonical_event,
    "Dart canonical event bytes diverged",
  );
  assert(
    await digest(fixture.event) === fixture.event_digest,
    "Independent digest diverged",
  );
  for (const sample of fixture.signatures) {
    const match = /^NexaPOS:(grant|enroll|event|release):v1\n$/.exec(
      sample.domain,
    );
    assert(match, "Signature domain must contain one actual newline");
    assert(
      await verifySignature(
        fixture.public_key,
        sample.signature,
        match[1] as "grant" | "enroll" | "event" | "release",
        sample.payload,
      ),
      `Dart ${match[1]} signature diverged`,
    );
  }
});

Deno.test("actual PostgreSQL prepare, accepted deficit receipt and pull decode through Edge", async () => {
  const fixture = JSON.parse(
    await Deno.readTextFile(
      new URL("../fixtures/offline_sql_signed_contract.json", import.meta.url),
    ),
  );
  const prepared = fixture.prepare;
  const claims = prepared.grant.claims;
  const scope: Scope = {
    organization_id: fixture.organization_id,
    branch_id: fixture.branch_id,
    device_id: fixture.device_id,
  };
  assert(
    await digest(prepared.snapshot) === claims.snapshot_digest,
    "Actual SQL snapshot canonical digest diverged",
  );
  assert(
    await digest(fixture.event) === fixture.digest,
    "Actual SQL event canonical digest diverged",
  );
  const pkcs8 = Uint8Array.from(
    "302e020100300506032b6570042204209d61b19deffd5a60ba844af492ec2cc44449c5697b326919703bac031cae7f60"
      .match(/../g)!,
    (byte) => parseInt(byte, 16),
  );
  const signer = await GrantSigner.fromPkcs8(
    claims.issuer,
    claims.key_id,
    base64url(pkcs8),
  );
  const gateway: OfflineGateway = {
    authorize: () => Promise.resolve(),
    verifyUser: () =>
      Promise.resolve({ id: fixture.actor_id, emailVerified: true }),
    challenge: () => Promise.reject(new Error("Not used by this fixture")),
    context: () =>
      Promise.resolve({
        public_key: fixture.public_test_key,
        grant: prepared.grant,
      }),
    enroll: () => Promise.reject(new Error("Not used by this fixture")),
    prepare: () =>
      Promise.resolve({
        claims,
        snapshot: prepared.snapshot,
        server_time: prepared.server_time,
      }),
    finalize: () => Promise.resolve(prepared),
    ingest: () => Promise.resolve(fixture.accepted),
    pull: () => Promise.resolve(fixture.pull),
    release: () => Promise.reject(new Error("Not used by this fixture")),
  };
  const handler = createOfflineHandler({
    gateway,
    signer,
    allowedOrigins: new Set(),
  });
  const call = (action: string, values: object) =>
    handler(
      new Request("https://example.invalid/functions/v1/offline-sync", {
        method: "POST",
        headers: {
          authorization: "Bearer verified-test-token",
          "content-type": "application/json",
        },
        body: JSON.stringify({ action, ...scope, ...values }),
      }),
    );
  const prepareResponse = await call("prepare", {
    request_id: "a4200000-0000-4000-8000-000000000001",
  });
  assert(
    prepareResponse.status === 200,
    `Actual SQL preparation failed: ${await prepareResponse.clone().text()}`,
  );
  const signed = await prepareResponse.json();
  assert(
    signed.grant.signature === prepared.grant.signature,
    "Stable SQL claims must sign identically",
  );
  const acceptedResponse = await call("ingest", {
    event: fixture.event,
    digest: fixture.digest,
    authorization: fixture.authorization,
    signature: fixture.signature,
  });
  assert(
    acceptedResponse.status === 200,
    `Actual SQL acceptance failed: ${await acceptedResponse.clone().text()}`,
  );
  const accepted = await acceptedResponse.json();
  assert(
    canonicalJson(accepted) === canonicalJson(fixture.accepted),
    "Edge altered immutable SQL receipt",
  );
  assert(
    accepted.receipt.total_minor === 113 &&
      accepted.reconciliation_code === "STOCK_DEFICIT",
    "Original paid total or deficit classification lost",
  );
  const pullResponse = await call("pull", {
    cursor: prepared.snapshot.cursor,
    limit: 100,
  });
  assert(
    pullResponse.status === 200,
    `Actual SQL pull failed: ${await pullResponse.clone().text()}`,
  );
  const pulled = await pullResponse.json();
  assert(
    canonicalJson(pulled) === canonicalJson(fixture.pull),
    "Edge altered SQL feed",
  );
  assert(
    pulled.changes.at(-1).value.quantity === -1 &&
      pulled.changes.at(-1).value.revision === 3,
    "Signed deficit impact revision lost",
  );
  assert(
    pulled.changes[0].value.price_minor === 5000 &&
      accepted.receipt.items[0].unit_price_minor === 100,
    "Paid receipt was repriced from pulled catalog",
  );
});

Deno.test("actual PostgreSQL review is preserved and cannot acquire financial acceptance", async () => {
  const fixture = JSON.parse(
    await Deno.readTextFile(
      new URL("../fixtures/offline_sql_signed_contract.json", import.meta.url),
    ),
  );
  const scope: Scope = {
    organization_id: fixture.organization_id,
    branch_id: fixture.branch_id,
    device_id: fixture.device_id,
  };
  const review = object(fixture.review);
  const envelope = {
    event: object(fixture.review_event),
    digest: review.digest as string,
    authorization: object(fixture.review_authorization),
  };
  assert(
    await digest(envelope.event) === envelope.digest,
    "Actual SQL review event digest diverged",
  );
  assert(
    await verifySignature(
      fixture.public_test_key,
      fixture.review_signature,
      "event",
      {
        event_digest: envelope.digest,
        ...envelope.authorization,
      },
    ),
    "Actual SQL review event proof diverged",
  );
  validateOutcome(
    review,
    fixture.actor_id,
    scope,
    envelope,
    fixture.prepare.grant.claims,
  );
  let rejected = false;
  try {
    validateOutcome(
      {
        ...review,
        server_receipt_id: fixture.accepted.server_receipt_id,
        receipt: fixture.accepted.receipt,
      },
      fixture.actor_id,
      scope,
      envelope,
      fixture.prepare.grant.claims,
    );
  } catch {
    rejected = true;
  }
  assert(rejected, "Review must not carry invented financial acceptance");
});
