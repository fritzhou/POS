import {
  type AuthDeliveryResult,
  type DeliveryClaim,
  type DeliveryState,
  GatewayError,
  type InvitationGateway,
  type InvitationInput,
  type InvitationSnapshot,
  isUuid,
  validateRedirect,
} from "./core.ts";

export interface SupabaseGatewayConfig {
  url: string;
  publicKey: string;
  serviceRoleKey: string;
  redirectUrl: string;
  fetch?: typeof fetch;
}

const deliveryStates = new Set<DeliveryState>([
  "prepared",
  "sending",
  "sent",
  "failed",
]);

function object(value: unknown): Record<string, unknown> {
  if (!value || typeof value !== "object" || Array.isArray(value)) {
    throw new GatewayError("unavailable");
  }
  return value as Record<string, unknown>;
}

function snapshot(value: unknown): InvitationSnapshot {
  const data = object(value);
  if (
    !isUuid(data.id) || typeof data.expires_at !== "string" ||
    !Number.isFinite(Date.parse(data.expires_at)) ||
    !deliveryStates.has(data.delivery_state as DeliveryState)
  ) {
    throw new GatewayError("unavailable");
  }
  return {
    id: data.id,
    expires_at: data.expires_at,
    delivery_state: data.delivery_state as DeliveryState,
  };
}

async function responseJson(response: Response): Promise<unknown> {
  try {
    return await response.json();
  } catch {
    throw new GatewayError("unavailable");
  }
}

/** Calls supported Supabase HTTP APIs. No Auth URLs/tokens are returned or logged. */
export function createSupabaseGateway(
  config: SupabaseGatewayConfig,
): InvitationGateway {
  const base = new URL(config.url);
  if (
    base.username || base.password || base.search || base.hash ||
    (base.protocol !== "https:" && !(base.protocol === "http:" &&
      ["localhost", "127.0.0.1", "[::1]"].includes(base.hostname))) ||
    !config.publicKey || !config.serviceRoleKey
  ) {
    throw new Error("Invalid Supabase function configuration");
  }
  const baseUrl = base.toString().replace(/\/$/, "");
  const redirectUrl = validateRedirect(config.redirectUrl);
  const requestFetch = config.fetch ?? fetch;

  const call = (
    path: string,
    key: string,
    token: string | null,
    body?: unknown,
  ) => {
    const headers: Record<string, string> = {
      apikey: key,
      Accept: "application/json",
    };
    if (token) headers.Authorization = `Bearer ${token}`;
    if (body !== undefined) headers["Content-Type"] = "application/json";
    return requestFetch(`${baseUrl}${path}`, {
      method: body === undefined ? "GET" : "POST",
      headers,
      body: body === undefined ? undefined : JSON.stringify(body),
      signal: AbortSignal.timeout(10_000),
    });
  };

  const rpc = async (
    name: string,
    key: string,
    token: string,
    args: unknown,
  ) => {
    let response: Response;
    try {
      response = await call(`/rest/v1/rpc/${name}`, key, token, args);
    } catch {
      throw new GatewayError("unavailable");
    }
    const data = await responseJson(response);
    if (!response.ok) {
      const code = object(data).code;
      if (code === "42501") throw new GatewayError("denied");
      if (code === "NX001") throw new GatewayError("rate_limited", 600);
      if (code === "NX002") throw new GatewayError("rate_limited", 10);
      if (code === "22023" || code === "22P02") {
        throw new GatewayError("invalid");
      }
      if (["23505", "23514", "40001"].includes(String(code))) {
        throw new GatewayError("conflict");
      }
      throw new GatewayError("unavailable");
    }
    return data;
  };

  const dispatch = async (
    path: string,
    key: string,
    token: string | null,
    body: unknown,
    allowExists: boolean,
  ): Promise<AuthDeliveryResult> => {
    let response: Response;
    try {
      response = await call(
        `${path}?redirect_to=${encodeURIComponent(redirectUrl)}`,
        key,
        token,
        body,
      );
    } catch {
      // A timeout does not prove the provider rejected its request.
      return { kind: "uncertain" };
    }
    if (response.ok) {
      // Auth accepted the request. This does not establish inbox delivery.
      await response.body?.cancel();
      return { kind: "accepted" };
    }
    if (response.status >= 500 || response.status === 408) {
      await response.body?.cancel();
      return { kind: "uncertain" };
    }
    if (allowExists && response.status >= 400 && response.status < 500) {
      try {
        const data = object(await responseJson(response));
        if (
          data.code === "email_exists" || data.error_code === "email_exists"
        ) {
          return { kind: "email_exists" };
        }
      } catch {
        // A malformed error never authorizes the existing-account fallback.
      }
    } else {
      await response.body?.cancel();
    }
    return { kind: "rejected" };
  };

  return {
    async verifyUser(token) {
      let response: Response;
      try {
        response = await call("/auth/v1/user", config.publicKey, token);
      } catch {
        throw new GatewayError("unavailable");
      }
      if (response.status === 401 || response.status === 403) {
        await response.body?.cancel();
        return null;
      }
      if (!response.ok) throw new GatewayError("unavailable");
      const data = object(await responseJson(response));
      if (!isUuid(data.id)) throw new GatewayError("unavailable");
      return { id: data.id };
    },
    async prepare(token: string, input: InvitationInput) {
      return snapshot(
        await rpc("prepare_employee_invitation", config.publicKey, token, {
          p_organization_id: input.organization_id,
          p_request_id: input.request_id,
          p_email: input.email,
          p_full_name: input.full_name,
          p_role: input.role,
          p_branch_ids: input.branch_ids,
          p_all_branches: input.all_branches,
          p_employee_id: input.employee_id,
          p_phone: input.phone,
          p_reason: input.reason,
        }),
      );
    },
    async claim(invitationId: string) {
      const value = await rpc(
        "claim_invitation_delivery",
        config.serviceRoleKey,
        config.serviceRoleKey,
        { p_invitation_id: invitationId },
      );
      if (value === null) return null;
      const result = snapshot(value);
      const data = object(value);
      if (
        result.id !== invitationId || result.delivery_state !== "sending" ||
        !isUuid(data.claim_id) || !isUuid(data.organization_id) ||
        typeof data.normalized_email !== "string" ||
        typeof data.full_name !== "string"
      ) {
        throw new GatewayError("unavailable");
      }
      return {
        ...result,
        claim_id: data.claim_id,
        organization_id: data.organization_id,
        normalized_email: data.normalized_email,
        full_name: data.full_name,
      } satisfies DeliveryClaim;
    },
    inviteNewUser(email: string, fullName: string) {
      return dispatch(
        "/auth/v1/invite",
        config.serviceRoleKey,
        config.serviceRoleKey,
        { email, data: { full_name: fullName } },
        true,
      );
    },
    sendExistingUserLink(email: string) {
      return dispatch("/auth/v1/otp", config.publicKey, null, {
        email,
        create_user: false,
      }, false);
    },
    async finish(invitationId: string, claimId: string, succeeded: boolean) {
      return snapshot(
        await rpc(
          "finish_invitation_delivery",
          config.serviceRoleKey,
          config.serviceRoleKey,
          {
            p_invitation_id: invitationId,
            p_claim_id: claimId,
            p_succeeded: succeeded,
            p_error_code: succeeded ? null : "auth_delivery_rejected",
          },
        ),
      );
    },
  };
}
