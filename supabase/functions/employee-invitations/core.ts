/**
 * Invitation orchestration only. PostgreSQL owns business authorization and
 * idempotency; Supabase Auth owns single-use email credentials and callbacks.
 * This module has no runtime dependencies and accepts gateways for unit tests.
 */
export type DeliveryState = "prepared" | "sending" | "sent" | "failed";
export type EmployeeRole = "admin" | "manager" | "cashier" | "inventory_staff";

export interface InvitationInput {
  organization_id: string;
  request_id: string;
  email: string;
  full_name: string;
  role: EmployeeRole;
  branch_ids: string[];
  all_branches: boolean;
  employee_id: string | null;
  phone: string | null;
  reason: string;
}

export interface InvitationSnapshot {
  id: string;
  expires_at: string;
  delivery_state: DeliveryState;
}

export interface DeliveryClaim extends InvitationSnapshot {
  claim_id: string;
  organization_id: string;
  normalized_email: string;
  full_name: string;
}

export type AuthDeliveryResult =
  | { kind: "accepted" }
  | { kind: "email_exists" }
  | { kind: "rejected" }
  | { kind: "uncertain" };

export interface InvitationGateway {
  /** Validates the bearer JWT against Auth, rather than decoding its claims. */
  verifyUser(token: string): Promise<{ id: string } | null>;
  /** Must execute with the same user JWT, never the service-role credential. */
  prepare(token: string, input: InvitationInput): Promise<InvitationSnapshot>;
  /** Server-only SQL must recheck current inviter authority and claim atomically. */
  claim(invitationId: string): Promise<DeliveryClaim | null>;
  inviteNewUser(email: string, fullName: string): Promise<AuthDeliveryResult>;
  /** Only called after an authoritative email_exists response from Auth. */
  sendExistingUserLink(email: string): Promise<AuthDeliveryResult>;
  finish(
    invitationId: string,
    claimId: string,
    succeeded: boolean,
  ): Promise<InvitationSnapshot>;
}

/** Safe, fixed error names; raw provider/SQL messages must never leave adapters. */
export class GatewayError extends Error {
  constructor(
    readonly kind:
      | "denied"
      | "conflict"
      | "invalid"
      | "unavailable"
      | "rate_limited",
    readonly retryAfterSeconds = 600,
  ) {
    super(kind);
  }
}

export interface HandlerConfig {
  allowedOrigins: ReadonlySet<string>;
  gateway: InvitationGateway;
}

const UUID = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;
const MAX_BYTES = 8192;
const roles = new Set<EmployeeRole>([
  "admin",
  "manager",
  "cashier",
  "inventory_staff",
]);
const keys = new Set([
  "organization_id",
  "request_id",
  "email",
  "full_name",
  "role",
  "branch_ids",
  "all_branches",
  "employee_id",
  "phone",
  "reason",
]);

export function isUuid(value: unknown): value is string {
  return typeof value === "string" && UUID.test(value);
}

/** Deployment must also add this exact callback to Supabase Auth's allowlist. */
export function validateRedirect(value: string): string {
  const url = new URL(value);
  const https = url.protocol === "https:" && !!url.hostname;
  const native = url.protocol === "com.nexapos.app:" &&
    url.hostname === "auth" &&
    url.pathname === "/callback";
  if ((!https && !native) || url.username || url.password || url.hash) {
    throw new Error("Invalid invitation redirect configuration");
  }
  return url.toString();
}

export function parseAllowedOrigins(value: string): ReadonlySet<string> {
  const result = new Set<string>();
  for (
    const item of value.split(",").map((item) => item.trim()).filter(Boolean)
  ) {
    const url = new URL(item);
    const local = url.protocol === "http:" &&
      ["localhost", "127.0.0.1", "[::1]"].includes(url.hostname);
    if ((url.protocol !== "https:" && !local) || item !== url.origin) {
      throw new Error("Invalid invitation origin configuration");
    }
    result.add(url.origin);
  }
  return result;
}

function stringField(value: unknown, min: number, max: number): string {
  if (typeof value !== "string") throw new GatewayError("invalid");
  const result = value.trim();
  if (
    result.length < min || result.length > max ||
    [...result].some((character) => {
      const code = character.charCodeAt(0);
      return code < 32 || code === 127;
    })
  ) {
    throw new GatewayError("invalid");
  }
  return result;
}

function optionalString(value: unknown, max: number): string | null {
  return value === undefined || value === null
    ? null
    : stringField(value, 1, max);
}

function parseInput(value: unknown): InvitationInput {
  if (!value || typeof value !== "object" || Array.isArray(value)) {
    throw new GatewayError("invalid");
  }
  const data = value as Record<string, unknown>;
  if (
    Object.keys(data).some((key) => !keys.has(key)) ||
    !isUuid(data.organization_id) || !isUuid(data.request_id) ||
    typeof data.all_branches !== "boolean" ||
    !roles.has(data.role as EmployeeRole) ||
    !Array.isArray(data.branch_ids) || data.branch_ids.length > 100 ||
    data.branch_ids.some((id) => !isUuid(id)) ||
    new Set(data.branch_ids.map((id: string) => id.toLowerCase())).size !==
      data.branch_ids.length ||
    (data.all_branches &&
      (data.role !== "admin" || data.branch_ids.length !== 0)) ||
    (!data.all_branches && data.branch_ids.length === 0)
  ) {
    throw new GatewayError("invalid");
  }
  const email = stringField(data.email, 3, 254).toLowerCase();
  if (
    !/^[^\s<>(),;:\[\]"\\]+@[^\s<>(),;:\[\]"\\]+\.[^\s<>(),;:\[\]"\\]+$/.test(
      email,
    )
  ) {
    throw new GatewayError("invalid");
  }
  return {
    organization_id: data.organization_id.toLowerCase(),
    request_id: data.request_id.toLowerCase(),
    email,
    full_name: stringField(data.full_name, 2, 120),
    role: data.role as EmployeeRole,
    branch_ids: data.branch_ids.map((id: string) => id.toLowerCase()),
    all_branches: data.all_branches,
    employee_id: optionalString(data.employee_id, 64),
    phone: optionalString(data.phone, 40),
    reason: stringField(data.reason, 2, 500),
  };
}

async function readJson(request: Request): Promise<unknown> {
  const length = request.headers.get("content-length");
  if (length && (!/^\d+$/.test(length) || Number(length) > MAX_BYTES)) {
    throw new RangeError("body_limit");
  }
  if (!request.body) throw new GatewayError("invalid");
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
    return JSON.parse(new TextDecoder("utf-8", { fatal: true }).decode(bytes));
  } catch {
    throw new GatewayError("invalid");
  }
}

export function createInvitationHandler(config: HandlerConfig) {
  return async (request: Request): Promise<Response> => {
    const origin = request.headers.get("origin");
    const headers = new Headers({
      "Content-Type": "application/json; charset=utf-8",
      "Cache-Control": "no-store",
      "Vary": "Origin",
      "X-Content-Type-Options": "nosniff",
    });
    const reply = (status: number, body: Record<string, unknown>) =>
      new Response(JSON.stringify(body), { status, headers });
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
    const authorization = request.headers.get("authorization") || "";
    const match = /^Bearer ([^\s,]+)$/i.exec(authorization);
    if (!match || match[1].length > 8192) {
      return reply(401, { error: "authentication_required" });
    }
    if (
      request.headers.get("content-type")?.split(";", 1)[0].trim()
        .toLowerCase() !== "application/json"
    ) {
      return reply(415, { error: "json_required" });
    }
    try {
      const input = parseInput(await readJson(request));
      const user = await config.gateway.verifyUser(match[1]);
      if (!user || !isUuid(user.id)) {
        return reply(401, { error: "authentication_required" });
      }
      let invitation = await config.gateway.prepare(match[1], input);
      const statusReply = (snapshot: InvitationSnapshot) =>
        reply(
          snapshot.delivery_state === "sent" ? 200 : 202,
          {
            invitation_id: snapshot.id,
            expires_at: snapshot.expires_at,
            delivery_state: snapshot.delivery_state,
          },
        );
      if (
        invitation.delivery_state === "sent" ||
        invitation.delivery_state === "sending"
      ) {
        return statusReply(invitation);
      }
      const claim = await config.gateway.claim(invitation.id);
      if (!claim) {
        // A concurrent request may have claimed or finished after prepare.
        invitation = await config.gateway.prepare(match[1], input);
        return statusReply(invitation);
      }
      let delivery = await config.gateway.inviteNewUser(
        claim.normalized_email,
        claim.full_name,
      );
      if (delivery.kind === "email_exists") {
        delivery = await config.gateway.sendExistingUserLink(
          claim.normalized_email,
        );
      }
      if (delivery.kind === "uncertain") return statusReply(claim);
      const succeeded = delivery.kind === "accepted";
      let finished: InvitationSnapshot;
      try {
        finished = await config.gateway.finish(
          claim.id,
          claim.claim_id,
          succeeded,
        );
      } catch {
        // Auth may already have accepted email; never retry its dispatch here.
        return statusReply(claim);
      }
      if (!succeeded) {
        return reply(503, {
          error: "email_delivery_not_confirmed",
          invitation_id: finished.id,
          expires_at: finished.expires_at,
          delivery_state: finished.delivery_state,
        });
      }
      return statusReply(finished);
    } catch (error) {
      if (error instanceof RangeError) {
        return reply(413, { error: "request_too_large" });
      }
      if (error instanceof GatewayError) {
        const mapping = {
          denied: [403, "invitation_not_permitted"],
          conflict: [409, "invitation_conflict"],
          invalid: [400, "invalid_request"],
          unavailable: [503, "invitation_service_unavailable"],
          rate_limited: [429, "invitation_rate_limited"],
        } as const;
        const [status, code] = mapping[error.kind];
        if (error.kind === "rate_limited") {
          headers.set("Retry-After", String(error.retryAfterSeconds));
        }
        return reply(status, { error: code });
      }
      return reply(503, { error: "invitation_service_unavailable" });
    }
  };
}
