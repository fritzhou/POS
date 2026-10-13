import { isUuid, parseAllowedOrigins } from "../employee-invitations/core.ts";
export { parseAllowedOrigins };

export class PinGatewayError extends Error {
  constructor(
    readonly kind:
      | "denied"
      | "invalid"
      | "conflict"
      | "unavailable"
      | "limited",
  ) {
    super(kind);
  }
}
export interface PinInput {
  action: "set" | "verify";
  organization_id: string;
  request_id: string;
  expected_revision: number;
  pin: string;
  current_pin: string | null;
}
export type PinAuthorizationInput = Pick<
  PinInput,
  "action" | "organization_id" | "request_id" | "expected_revision"
>;
export interface PinGateway {
  verifyUser(token: string): Promise<{ id: string } | null>;
  authorize(
    token: string,
    input: PinAuthorizationInput,
  ): Promise<{ id: string; actor_id: string }>;
  complete(
    operationId: string,
    actorId: string,
    input: PinInput,
  ): Promise<Record<string, unknown>>;
}
const allowedKeys = new Set([
  "action",
  "organization_id",
  "request_id",
  "expected_revision",
  "pin",
  "current_pin",
]);
const pinPattern = /^[0-9]{6,12}$/;
function parseInput(value: unknown): PinInput {
  if (!value || typeof value !== "object" || Array.isArray(value)) {
    throw new PinGatewayError("invalid");
  }
  const v = value as Record<string, unknown>;
  if (
    Object.keys(v).some((k) => !allowedKeys.has(k)) ||
    !isUuid(v.organization_id) || !isUuid(v.request_id) ||
    !["set", "verify"].includes(String(v.action)) ||
    !Number.isSafeInteger(v.expected_revision) ||
    Number(v.expected_revision) < 1 || typeof v.pin !== "string" ||
    !pinPattern.test(v.pin) ||
    (v.current_pin != null &&
      (typeof v.current_pin !== "string" || !pinPattern.test(v.current_pin))) ||
    (v.action === "verify" && v.current_pin != null)
  ) throw new PinGatewayError("invalid");
  return {
    action: v.action as "set" | "verify",
    organization_id: v.organization_id.toLowerCase(),
    request_id: v.request_id.toLowerCase(),
    expected_revision: v.expected_revision as number,
    pin: v.pin,
    current_pin: v.current_pin as string | null ?? null,
  };
}
async function readBody(request: Request): Promise<unknown> {
  const declared = request.headers.get("content-length");
  if (declared && (!/^\d+$/.test(declared) || Number(declared) > 2048)) {
    throw new RangeError("body_limit");
  }
  if (!request.body) throw new PinGatewayError("invalid");
  const reader = request.body.getReader();
  const chunks: Uint8Array[] = [];
  let total = 0;
  try {
    for (;;) {
      const { done, value } = await reader.read();
      if (done) break;
      total += value.length;
      if (total > 2048) {
        await reader.cancel();
        throw new RangeError("body_limit");
      }
      chunks.push(value);
    }
  } finally {
    reader.releaseLock();
  }
  const bytes = new Uint8Array(total);
  let offset = 0;
  for (const chunk of chunks) {
    bytes.set(chunk, offset);
    offset += chunk.length;
  }
  try {
    return JSON.parse(new TextDecoder("utf-8", { fatal: true }).decode(bytes));
  } catch {
    throw new PinGatewayError("invalid");
  }
}
export function createPinHandler(
  config: { allowedOrigins: ReadonlySet<string>; gateway: PinGateway },
) {
  return async (request: Request): Promise<Response> => {
    const origin = request.headers.get("origin");
    const headers = new Headers({
      "Content-Type": "application/json; charset=utf-8",
      "Cache-Control": "no-store",
      "X-Content-Type-Options": "nosniff",
      "Vary": "Origin",
    });
    const reply = (status: number, body: Record<string, unknown>) =>
      new Response(JSON.stringify(body), { status, headers });
    if (origin && !config.allowedOrigins.has(origin)) {
      return reply(403, { error: "denied" });
    }
    if (origin) headers.set("Access-Control-Allow-Origin", origin);
    headers.set(
      "Access-Control-Allow-Headers",
      "authorization, apikey, content-type, x-client-info",
    );
    headers.set("Access-Control-Allow-Methods", "POST, OPTIONS");
    if (request.method === "OPTIONS") {
      return new Response(null, { status: 204, headers });
    }
    if (request.method !== "POST") {
      return reply(405, { error: "method_not_allowed" });
    }
    const bearer = request.headers.get("authorization")?.match(
      /^Bearer ([^\s]+)$/i,
    )?.[1];
    if (!bearer || bearer.length > 8192) {
      return reply(401, { error: "unauthenticated" });
    }
    if (
      request.headers.get("content-type")?.split(";")[0].trim()
        .toLowerCase() !== "application/json"
    ) return reply(415, { error: "content_type" });
    try {
      const input = parseInput(await readBody(request));
      const user = await config.gateway.verifyUser(bearer);
      if (!user) return reply(401, { error: "unauthenticated" });
      const operation = await config.gateway.authorize(bearer, {
        action: input.action,
        organization_id: input.organization_id,
        request_id: input.request_id,
        expected_revision: input.expected_revision,
      });
      if (operation.actor_id !== user.id) throw new PinGatewayError("denied");
      return reply(
        200,
        await config.gateway.complete(operation.id, user.id, input),
      );
    } catch (error) {
      if (error instanceof RangeError) {
        return reply(413, { error: "body_limit" });
      }
      if (error instanceof PinGatewayError) {
        return reply(
          {
            denied: 403,
            invalid: 422,
            conflict: 409,
            unavailable: 503,
            limited: 429,
          }[error.kind],
          { error: error.kind },
        );
      }
      // Neither PIN material, bearer credentials, nor raw database errors are logged or returned.
      return reply(503, { error: "unavailable" });
    }
  };
}
