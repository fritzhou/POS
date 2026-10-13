import {
  canonicalJson,
  decodeBase64url,
  digest,
  GrantSigner,
  integer,
  isUuid,
  type JsonObject,
  object,
  OfflineError,
  strictKeys,
  utcMicroseconds,
  utcTime,
  verifySignature,
} from "./protocol.ts";
export { OfflineError } from "./protocol.ts";
export { parseAllowedOrigins } from "../employee-invitations/core.ts";
import {
  checkedResponse,
  validateEnrollment,
  validateOutcome,
  validatePull,
  validateRelease,
  validateSnapshot,
} from "./response_validation.ts";

export interface Scope {
  organization_id: string;
  branch_id: string;
  device_id: string;
}
export interface OfflineGateway {
  verifyUser(
    token: string,
  ): Promise<{ id: string; emailVerified: boolean } | null>;
  authorize(
    token: string,
    scope: Scope,
    action: "enroll" | "prepare" | "pull" | "release",
  ): Promise<void>;
  challenge(token: string, input: JsonObject): Promise<JsonObject>;
  context(
    actor: string,
    scope: Scope,
    grantId: string | null,
    challengeId: string | null,
  ): Promise<JsonObject>;
  enroll(
    actor: string,
    scope: Scope,
    challengeId: string,
    signature: string,
  ): Promise<JsonObject>;
  prepare(
    actor: string,
    scope: Scope,
    requestId: string,
    issuer: string,
    keyId: string,
  ): Promise<JsonObject>;
  finalize(
    actor: string,
    scope: Scope,
    grantId: string,
    claims: JsonObject,
    signature: string,
  ): Promise<JsonObject>;
  ingest(
    actor: string,
    scope: Scope,
    envelope: JsonObject,
  ): Promise<JsonObject>;
  pull(
    actor: string,
    scope: Scope,
    cursor: number,
    limit: number,
  ): Promise<JsonObject>;
  release(
    actor: string,
    scope: Scope,
    grantId: string,
    sequence: number,
    signature: string,
  ): Promise<JsonObject>;
}

export interface HandlerConfig {
  gateway: OfflineGateway;
  signer: GrantSigner;
  allowedOrigins: ReadonlySet<string>;
  /** Rotation overlap keys are deployment configuration, never caller input. */
  verificationKeys?: ReadonlyMap<string, string>;
}

const COMMON = ["action", "organization_id", "branch_id", "device_id"];
const GRANT_KEYS = [
  "schema_version",
  "issuer",
  "audience",
  "key_id",
  "grant_id",
  "organization_id",
  "branch_id",
  "device_id",
  "actor_id",
  "membership_id",
  "role",
  "business_name",
  "allowed_actions",
  "issued_at",
  "expires_at",
  "shift_id",
  "currency",
  "tax_bps",
  "settings_revision",
  "snapshot_digest",
  "max_events",
  "max_total_minor",
];
const UUID_FIELDS = [
  "grant_id",
  "organization_id",
  "branch_id",
  "device_id",
  "actor_id",
  "membership_id",
  "shift_id",
];
const MAX_BYTES = 262_144;

function scopeFrom(input: JsonObject): Scope {
  for (const field of ["organization_id", "branch_id", "device_id"]) {
    if (
      !isUuid(input[field]) ||
      input[field] !== (input[field] as string).toLowerCase()
    ) throw new OfflineError("invalid");
  }
  return {
    organization_id: input.organization_id as string,
    branch_id: input.branch_id as string,
    device_id: input.device_id as string,
  };
}

function matches(value: JsonObject, actor: string, scope: Scope): void {
  if (
    value.actor_id !== actor ||
    value.organization_id !== scope.organization_id ||
    value.branch_id !== scope.branch_id || value.device_id !== scope.device_id
  ) throw new OfflineError("denied");
}

export function validateClaims(
  value: unknown,
  actor: string,
  scope: Scope,
  issuer: string,
): JsonObject {
  const claims = object(value);
  strictKeys(claims, GRANT_KEYS, GRANT_KEYS);
  canonicalJson(claims);
  matches(claims, actor, scope);
  if (
    UUID_FIELDS.some((field) =>
      !isUuid(claims[field]) ||
      claims[field] !== (claims[field] as string).toLowerCase()
    ) ||
    claims.schema_version !== 1 || claims.issuer !== issuer ||
    claims.audience !== "nexapos.offline.v1" ||
    !["owner", "admin", "manager", "cashier"].includes(String(claims.role)) ||
    typeof claims.business_name !== "string" ||
    claims.business_name.length < 1 || claims.business_name.length > 200 ||
    typeof claims.key_id !== "string" ||
    !/^[A-Za-z0-9_.-]{1,80}$/.test(claims.key_id) ||
    !Array.isArray(claims.allowed_actions) ||
    claims.allowed_actions.length !== 1 ||
    claims.allowed_actions[0] !== "sale.created" ||
    !["PHP", "USD", "EUR", "GBP", "AUD", "CAD", "SGD"].includes(
      String(claims.currency),
    ) || typeof claims.snapshot_digest !== "string" ||
    !/^[a-f0-9]{64}$/.test(claims.snapshot_digest) ||
    claims.max_events !== 1000 || claims.max_total_minor !== 100000000
  ) throw new OfflineError("invalid");
  integer(claims.tax_bps, 0, 10000);
  integer(claims.settings_revision, 1, Number.MAX_SAFE_INTEGER);
  const elapsed = utcMicroseconds(claims.expires_at) -
    utcMicroseconds(claims.issued_at);
  if (elapsed <= 0n || elapsed > 28_800_000_000n) {
    throw new OfflineError("invalid");
  }
  return claims;
}

async function readJson(request: Request): Promise<JsonObject> {
  const length = request.headers.get("content-length");
  if (length && (!/^\d+$/.test(length) || Number(length) > MAX_BYTES)) {
    throw new RangeError("body_limit");
  }
  if (!request.body) throw new OfflineError("invalid");
  const reader = request.body.getReader();
  const chunks: Uint8Array[] = [];
  let size = 0;
  try {
    for (;;) {
      const { done, value } = await reader.read();
      if (done) break;
      size += value.length;
      if (size > MAX_BYTES) {
        await reader.cancel();
        throw new RangeError("body_limit");
      }
      chunks.push(value);
    }
  } finally {
    reader.releaseLock();
  }
  const bytes = new Uint8Array(size);
  let offset = 0;
  for (const chunk of chunks) {
    bytes.set(chunk, offset);
    offset += chunk.length;
  }
  try {
    const value = object(
      JSON.parse(new TextDecoder("utf-8", { fatal: true }).decode(bytes)),
    );
    canonicalJson(value);
    return value;
  } catch {
    throw new OfflineError("invalid");
  }
}

function uuid(value: unknown): string {
  if (!isUuid(value) || value !== value.toLowerCase()) {
    throw new OfflineError("invalid");
  }
  return value;
}

function validateEnvelope(
  input: JsonObject,
  actor: string,
  scope: Scope,
): {
  event: JsonObject;
  authorization: JsonObject;
  signature: string;
  digest: string;
} {
  const event = object(input.event);
  const keys = [
    "actor_id",
    "branch_id",
    "device_id",
    "event_id",
    "event_type",
    "occurred_at",
    "organization_id",
    "payload",
    "schema_version",
  ];
  strictKeys(event, keys, keys);
  matches(event, actor, scope);
  uuid(event.event_id);
  if (event.schema_version !== 1 || event.event_type !== "sale.created") {
    throw new OfflineError("invalid");
  }
  // Preserve hash-bound timestamp bytes; conversion to Date is validation only.
  utcTime(event.occurred_at);
  object(event.payload);
  const authorization = object(input.authorization);
  strictKeys(authorization, ["grant_id", "sequence", "payment_evidence"], [
    "grant_id",
    "sequence",
    "payment_evidence",
  ]);
  uuid(authorization.grant_id);
  integer(authorization.sequence, 1, 1000);
  const evidence = object(authorization.payment_evidence);
  if (Object.keys(evidence).length < 1 || Object.keys(evidence).length > 5) {
    throw new OfflineError("invalid");
  }
  for (const [id, value] of Object.entries(evidence)) {
    uuid(id);
    const payment = object(value);
    strictKeys(payment, ["tendered_minor", "manual_confirmed"]);
    if (Object.keys(payment).length !== 1) throw new OfflineError("invalid");
    if ("tendered_minor" in payment) {
      integer(payment.tendered_minor, 1, Number.MAX_SAFE_INTEGER);
    } else if (payment.manual_confirmed !== true) {
      throw new OfflineError("invalid");
    }
  }
  decodeBase64url(input.signature, 64);
  if (
    typeof input.digest !== "string" || !/^[a-f0-9]{64}$/.test(input.digest)
  ) throw new OfflineError("invalid");
  return {
    event,
    authorization,
    signature: input.signature as string,
    digest: input.digest,
  };
}

export function createOfflineHandler(config: HandlerConfig) {
  const verificationKeys = new Map(config.verificationKeys ?? []);
  verificationKeys.set(config.signer.keyId, config.signer.publicKey);
  return async (request: Request): Promise<Response> => {
    const headers = new Headers({
      "Content-Type": "application/json; charset=utf-8",
      "Cache-Control": "no-store",
      "Vary": "Origin",
      "X-Content-Type-Options": "nosniff",
    });
    const reply = (status: number, body: unknown) =>
      new Response(JSON.stringify(body), { status, headers });
    const origin = request.headers.get("origin");
    if (origin && !config.allowedOrigins.has(origin)) {
      return reply(403, { error: "origin_not_allowed" });
    }
    if (origin) headers.set("Access-Control-Allow-Origin", origin);
    if (request.method === "OPTIONS") {
      headers.set("Access-Control-Allow-Methods", "POST, OPTIONS");
      headers.set(
        "Access-Control-Allow-Headers",
        "authorization, apikey, content-type, x-client-info",
      );
      headers.set("Access-Control-Max-Age", "600");
      return new Response(null, { status: 204, headers });
    }
    if (request.method !== "POST") {
      headers.set("Allow", "POST, OPTIONS");
      return reply(405, { error: "method_not_allowed" });
    }
    const match = /^Bearer ([^\s,]+)$/i.exec(
      request.headers.get("authorization") ?? "",
    );
    if (!match || match[1].length > 8192) {
      return reply(401, { error: "authentication_required" });
    }
    if (
      request.headers.get("content-type")?.split(";", 1)[0].trim()
        .toLowerCase() !== "application/json"
    ) return reply(415, { error: "json_required" });
    try {
      const input = await readJson(request);
      const scope = scopeFrom(input);
      const user = await config.gateway.verifyUser(match[1]);
      if (!user || !isUuid(user.id) || !user.emailVerified) {
        return reply(401, { error: "authentication_required" });
      }
      const actor = user.id.toLowerCase();
      const contextFor = (
        grantId: string | null,
        challengeId: string | null,
      ) => config.gateway.context(actor, scope, grantId, challengeId);
      const grantContext = async (grantId: string) => {
        const context = await contextFor(grantId, null);
        const retained = object(context.grant);
        const claims = validateClaims(
          retained.claims,
          actor,
          scope,
          config.signer.issuer,
        );
        if (claims.grant_id !== grantId) throw new OfflineError("denied");
        const key = verificationKeys.get(claims.key_id as string);
        if (
          !key ||
          !await verifySignature(key, retained.signature, "grant", claims)
        ) throw new OfflineError("denied");
        decodeBase64url(context.public_key, 32);
        return { context, claims };
      };
      switch (input.action) {
        case "enroll_challenge": {
          await config.gateway.authorize(match[1], scope, "enroll");
          strictKeys(input, [
            ...COMMON,
            "public_key",
            "device_name",
            "platform",
          ], [...COMMON, "public_key", "device_name", "platform"]);
          decodeBase64url(input.public_key, 32);
          if (
            typeof input.device_name !== "string" ||
            input.device_name.trim().length < 1 ||
            input.device_name.length > 120 ||
            !["windows", "android", "linux", "macos", "ios"].includes(
              String(input.platform),
            )
          ) throw new OfflineError("invalid");
          const challenge = await config.gateway.challenge(match[1], input);
          strictKeys(challenge, [
            "challenge_id",
            "nonce",
            "organization_id",
            "branch_id",
            "device_id",
            "actor_id",
            "public_key",
            "expires_at",
          ], [
            "challenge_id",
            "nonce",
            "organization_id",
            "branch_id",
            "device_id",
            "actor_id",
            "public_key",
            "expires_at",
          ]);
          matches(challenge, actor, scope);
          uuid(challenge.challenge_id);
          if (challenge.public_key !== input.public_key) {
            throw new OfflineError("unavailable");
          }
          decodeBase64url(challenge.nonce, 32);
          utcTime(challenge.expires_at);
          return reply(200, { challenge });
        }
        case "enroll": {
          await config.gateway.authorize(match[1], scope, "enroll");
          strictKeys(input, [...COMMON, "challenge_id", "signature"], [
            ...COMMON,
            "challenge_id",
            "signature",
          ]);
          const challengeId = uuid(input.challenge_id);
          const context = await contextFor(null, challengeId);
          const challenge = object(context.challenge);
          canonicalJson(challenge);
          strictKeys(challenge, [
            "challenge_id",
            "nonce",
            "organization_id",
            "branch_id",
            "device_id",
            "actor_id",
            "public_key",
            "expires_at",
          ], [
            "challenge_id",
            "nonce",
            "organization_id",
            "branch_id",
            "device_id",
            "actor_id",
            "public_key",
            "expires_at",
          ]);
          decodeBase64url(challenge.nonce, 32);
          utcTime(challenge.expires_at);
          matches(challenge, actor, scope);
          if (
            challenge.challenge_id !== challengeId ||
            !await verifySignature(
              challenge.public_key,
              input.signature,
              "enroll",
              challenge,
            )
          ) throw new OfflineError("denied");
          const enrolled = await config.gateway.enroll(
            actor,
            scope,
            challengeId,
            input.signature as string,
          );
          checkedResponse(() =>
            validateEnrollment(enrolled, actor, scope, challenge.public_key)
          );
          return reply(200, enrolled);
        }
        case "prepare": {
          await config.gateway.authorize(match[1], scope, "prepare");
          strictKeys(input, [...COMMON, "request_id"], [
            ...COMMON,
            "request_id",
          ]);
          const prepared = await config.gateway.prepare(
            actor,
            scope,
            uuid(input.request_id),
            config.signer.issuer,
            config.signer.keyId,
          );
          const claims = validateClaims(
            prepared.claims,
            actor,
            scope,
            config.signer.issuer,
          );
          const snapshot = object(prepared.snapshot);
          checkedResponse(() =>
            validateSnapshot(snapshot, claims, actor, scope)
          );
          if (claims.snapshot_digest !== await digest(snapshot)) {
            throw new OfflineError("unavailable");
          }
          const serverTime = utcTime(prepared.server_time);
          if (utcTime(claims.issued_at) > serverTime + 1000) {
            throw new OfflineError("conflict");
          }
          let signature: string;
          if (prepared.signature !== undefined) {
            // Recover the exact completed request after a lost response, even
            // after expiry or a signing-key rotation. This never extends expiry.
            const key = verificationKeys.get(claims.key_id as string);
            if (
              !key || typeof prepared.signature !== "string" ||
              !await verifySignature(key, prepared.signature, "grant", claims)
            ) {
              throw new OfflineError("unavailable");
            }
            signature = prepared.signature;
          } else {
            if (claims.key_id !== config.signer.keyId) {
              throw new OfflineError("unavailable");
            }
            if (utcTime(claims.expires_at) <= serverTime) {
              throw new OfflineError("conflict");
            }
            signature = await config.signer.sign(claims);
          }
          const finalized = await config.gateway.finalize(
            actor,
            scope,
            claims.grant_id as string,
            claims,
            signature,
          );
          checkedResponse(() => {
            canonicalJson(finalized);
            const retained = object(finalized.grant);
            if (
              canonicalJson(retained.claims) !== canonicalJson(claims) ||
              retained.signature !== signature ||
              canonicalJson(finalized.snapshot) !== canonicalJson(snapshot)
            ) {
              throw new OfflineError("invalid");
            }
            utcTime(finalized.server_time);
          });
          return reply(200, {
            grant: { claims, signature },
            snapshot,
            server_time: prepared.server_time,
          });
        }
        case "ingest": {
          strictKeys(input, [
            ...COMMON,
            "event",
            "digest",
            "authorization",
            "signature",
          ], [...COMMON, "event", "digest", "authorization", "signature"]);
          const envelope = validateEnvelope(input, actor, scope);
          if (await digest(envelope.event) !== envelope.digest) {
            throw new OfflineError("invalid");
          }
          const { context, claims } = await grantContext(
            envelope.authorization.grant_id as string,
          );
          const proof = {
            event_digest: envelope.digest,
            ...envelope.authorization,
          };
          if (
            !await verifySignature(
              context.public_key,
              envelope.signature,
              "event",
              proof,
            )
          ) throw new OfflineError("denied");
          const result = await config.gateway.ingest(actor, scope, envelope);
          checkedResponse(() =>
            validateOutcome(result, actor, scope, envelope, claims)
          );
          // SQL returns immutable stored acceptance. Edge never invents a receipt.
          return reply(result.status === "review" ? 202 : 200, result);
        }
        case "pull": {
          await config.gateway.authorize(match[1], scope, "pull");
          strictKeys(input, [...COMMON, "cursor", "limit"], [
            ...COMMON,
            "cursor",
          ]);
          const cursor = integer(input.cursor, 0, Number.MAX_SAFE_INTEGER);
          const limit = input.limit === undefined
            ? 100
            : integer(input.limit, 1, 100);
          const result = await config.gateway.pull(actor, scope, cursor, limit);
          checkedResponse(() => validatePull(result, scope, cursor, limit));
          return reply(200, result);
        }
        case "release": {
          await config.gateway.authorize(match[1], scope, "release");
          strictKeys(input, [
            ...COMMON,
            "grant_id",
            "final_sequence",
            "signature",
          ], [...COMMON, "grant_id", "final_sequence", "signature"]);
          const grantId = uuid(input.grant_id);
          const sequence = integer(input.final_sequence, 0, 1000);
          const { context } = await grantContext(grantId);
          if (
            !await verifySignature(
              context.public_key,
              input.signature,
              "release",
              { grant_id: grantId, final_sequence: sequence },
            )
          ) throw new OfflineError("denied");
          const released = await config.gateway.release(
            actor,
            scope,
            grantId,
            sequence,
            input.signature as string,
          );
          checkedResponse(() =>
            validateRelease(released, actor, scope, grantId, sequence)
          );
          return reply(200, released);
        }
        default:
          throw new OfflineError("invalid");
      }
    } catch (error) {
      if (error instanceof RangeError) {
        return reply(413, { error: "request_too_large" });
      }
      if (error instanceof OfflineError) {
        const statuses = {
          invalid: 400,
          denied: 403,
          conflict: 409,
          preparation_expired: 409,
          unavailable: 503,
          rate_limited: 429,
        };
        if (error.kind === "rate_limited") headers.set("Retry-After", "600");
        return reply(statuses[error.kind], { error: `offline_${error.kind}` });
      }
      return reply(503, { error: "offline_unavailable" });
    }
  };
}
