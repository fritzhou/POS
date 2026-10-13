import { isUuid } from "../employee-invitations/core.ts";
import {
  type PinAuthorizationInput,
  type PinGateway,
  PinGatewayError,
  type PinInput,
} from "./core.ts";

function object(value: unknown): Record<string, unknown> {
  if (!value || typeof value !== "object" || Array.isArray(value)) {
    throw new PinGatewayError("unavailable");
  }
  return value as Record<string, unknown>;
}
function status(value: unknown): Record<string, unknown> {
  const v = object(value);
  if (
    !isUuid(v.membership_id) || typeof v.configured !== "boolean" ||
    typeof v.reset_required !== "boolean" ||
    !Number.isSafeInteger(v.revision) || Number(v.revision) < 1 ||
    (v.locked_until !== null &&
      (typeof v.locked_until !== "string" ||
        !Number.isFinite(Date.parse(v.locked_until)))) ||
    (v.changed_at !== null &&
      (typeof v.changed_at !== "string" ||
        !Number.isFinite(Date.parse(v.changed_at))))
  ) throw new PinGatewayError("unavailable");
  // Explicit safe projection: no unexpectedly returned hash or capability reaches clients.
  return {
    membership_id: v.membership_id,
    configured: v.configured,
    reset_required: v.reset_required,
    revision: v.revision,
    locked_until: v.locked_until,
    changed_at: v.changed_at,
  };
}
export function createPinSupabaseGateway(
  config: {
    url: string;
    publicKey: string;
    serviceRoleKey: string;
    fetch?: typeof fetch;
  },
): PinGateway {
  const base = new URL(config.url);
  if (
    base.username || base.password || base.hash || base.search ||
    (base.protocol !== "https:" &&
      !(base.protocol === "http:" &&
        ["localhost", "127.0.0.1", "[::1]"].includes(base.hostname))) ||
    !config.publicKey || !config.serviceRoleKey
  ) throw new Error("Invalid PIN gateway configuration");
  const baseUrl = base.toString().replace(/\/$/, "");
  const requestFetch = config.fetch ?? fetch;
  const call = async (
    path: string,
    key: string,
    token: string,
    body?: unknown,
  ): Promise<Response> => {
    try {
      return await requestFetch(`${baseUrl}${path}`, {
        method: body === undefined ? "GET" : "POST",
        redirect: "error",
        headers: {
          apikey: key,
          Authorization: `Bearer ${token}`,
          Accept: "application/json",
          ...(body === undefined ? {} : { "Content-Type": "application/json" }),
        },
        body: body === undefined ? undefined : JSON.stringify(body),
        signal: AbortSignal.timeout(10000),
      });
    } catch {
      throw new PinGatewayError("unavailable");
    }
  };
  const json = async (response: Response): Promise<unknown> => {
    try {
      return await response.json();
    } catch {
      throw new PinGatewayError("unavailable");
    }
  };
  const rpc = async (
    name: string,
    key: string,
    token: string,
    args: unknown,
  ): Promise<unknown> => {
    const response = await call(`/rest/v1/rpc/${name}`, key, token, args);
    const data = await json(response);
    if (!response.ok) {
      const code = object(data).code;
      if (code === "42501") throw new PinGatewayError("denied");
      if (["22023", "22P02"].includes(String(code))) {
        throw new PinGatewayError("invalid");
      }
      if (["23505", "40001"].includes(String(code))) {
        throw new PinGatewayError("conflict");
      }
      if (code === "NX001") throw new PinGatewayError("limited");
      throw new PinGatewayError("unavailable");
    }
    return data;
  };
  return {
    async verifyUser(token: string) {
      const response = await call("/auth/v1/user", config.publicKey, token);
      if (response.status === 401 || response.status === 403) {
        await response.body?.cancel();
        return null;
      }
      if (!response.ok) throw new PinGatewayError("unavailable");
      const data = object(await json(response));
      if (!isUuid(data.id)) throw new PinGatewayError("unavailable");
      return { id: data.id };
    },
    async authorize(token: string, input: PinAuthorizationInput) {
      const data = object(
        await rpc("prepare_employee_pin_operation", config.publicKey, token, {
          p_organization_id: input.organization_id,
          p_request_id: input.request_id,
          p_action: input.action,
          p_expected_revision: input.expected_revision,
        }),
      );
      if (
        !isUuid(data.id) || !isUuid(data.actor_id) ||
        typeof data.expires_at !== "string" ||
        !Number.isFinite(Date.parse(data.expires_at))
      ) throw new PinGatewayError("unavailable");
      return { id: data.id, actor_id: data.actor_id };
    },
    async complete(operationId: string, actorId: string, input: PinInput) {
      const data = object(
        await rpc(
          "complete_employee_pin_operation",
          config.serviceRoleKey,
          config.serviceRoleKey,
          {
            p_operation_id: operationId,
            p_actor_id: actorId,
            p_pin: input.pin,
            p_current_pin: input.current_pin,
          },
        ),
      );
      if (typeof data.accepted !== "boolean") {
        throw new PinGatewayError("unavailable");
      }
      return { accepted: data.accepted, status: status(data.status) };
    },
  };
}
