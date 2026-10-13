import { type OfflineGateway, type Scope } from "./core.ts";
import { isUuid, type JsonObject, object, OfflineError } from "./protocol.ts";

export interface SupabaseOfflineConfig {
  url: string;
  publicKey: string;
  serviceRoleKey: string;
  fetch?: typeof fetch;
}

/** Auth validation uses the user token; financial RPC credentials never reach clients. */
export function createSupabaseOfflineGateway(
  config: SupabaseOfflineConfig,
): OfflineGateway {
  const base = new URL(config.url);
  if (
    base.username || base.password || base.search || base.hash ||
    base.pathname !== "/" ||
    (base.protocol !== "https:" &&
      !(base.protocol === "http:" &&
        ["localhost", "127.0.0.1", "[::1]"].includes(base.hostname))) ||
    !config.publicKey || !config.serviceRoleKey
  ) throw new Error("Invalid offline backend configuration");
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
        headers: {
          apikey: key,
          Authorization: `Bearer ${token}`,
          Accept: "application/json",
          ...(body === undefined ? {} : { "Content-Type": "application/json" }),
        },
        body: body === undefined ? undefined : JSON.stringify(body),
        redirect: "error",
        signal: AbortSignal.timeout(15_000),
      });
    } catch {
      throw new OfflineError("unavailable");
    }
  };

  const json = async (response: Response): Promise<JsonObject> => {
    try {
      return object(await response.json());
    } catch {
      throw new OfflineError("unavailable");
    }
  };

  const rpc = async (
    name: string,
    args: unknown,
    token?: string,
  ): Promise<JsonObject> => {
    const response = await call(
      `/rest/v1/rpc/${name}`,
      token ? config.publicKey : config.serviceRoleKey,
      token ?? config.serviceRoleKey,
      args,
    );
    const data = await json(response);
    if (!response.ok) {
      if (
        data.code === "42501" || response.status === 401 ||
        response.status === 403
      ) throw new OfflineError("denied");
      if (data.code === "NX002") {
        throw new OfflineError("preparation_expired");
      }
      if (data.code === "NX001" || response.status === 429) {
        throw new OfflineError("rate_limited");
      }
      if (["22023", "22P02", "22003"].includes(String(data.code))) {
        throw new OfflineError("invalid");
      }
      if (["23505", "23514", "40001", "P0002"].includes(String(data.code))) {
        throw new OfflineError("conflict");
      }
      throw new OfflineError("unavailable");
    }
    return data;
  };

  const scoped = (actor: string, scope: Scope) => ({
    p_actor_id: actor,
    p_organization_id: scope.organization_id,
    p_branch_id: scope.branch_id,
    p_device_id: scope.device_id,
  });

  return {
    async authorize(token, scope, action) {
      const result = await rpc("authorize_offline_operation", {
        p_organization_id: scope.organization_id,
        p_branch_id: scope.branch_id,
        p_device_id: scope.device_id,
        p_action: action,
      }, token);
      if (
        result.authorized !== true || typeof result.expires_at !== "string" ||
        !Number.isFinite(Date.parse(result.expires_at))
      ) {
        throw new OfflineError("denied");
      }
    },
    async verifyUser(token) {
      const response = await call("/auth/v1/user", config.publicKey, token);
      if (response.status === 401 || response.status === 403) {
        await response.body?.cancel();
        return null;
      }
      if (!response.ok) throw new OfflineError("unavailable");
      const data = await json(response);
      if (!isUuid(data.id)) throw new OfflineError("unavailable");
      return {
        id: data.id,
        emailVerified: typeof data.email_confirmed_at === "string" &&
          Number.isFinite(Date.parse(data.email_confirmed_at)),
      };
    },
    challenge(token, input) {
      return rpc("prepare_offline_device_challenge", {
        p_organization_id: input.organization_id,
        p_branch_id: input.branch_id,
        p_device_id: input.device_id,
        p_public_key: input.public_key,
        p_device_name: input.device_name ?? null,
        p_platform: input.platform ?? null,
      }, token);
    },
    context(actor, scope, grantId, challengeId) {
      return rpc("get_offline_verification_context", {
        ...scoped(actor, scope),
        p_grant_id: grantId,
        p_challenge_id: challengeId,
      });
    },
    enroll(actor, scope, challengeId, signature) {
      return rpc("complete_offline_device_enrollment", {
        ...scoped(actor, scope),
        p_challenge_id: challengeId,
        p_signature: signature,
      });
    },
    prepare(actor, scope, requestId, issuer, keyId) {
      return rpc("prepare_offline_grant", {
        ...scoped(actor, scope),
        p_request_id: requestId,
        p_issuer: issuer,
        p_key_id: keyId,
      });
    },
    finalize(actor, scope, grantId, claims, signature) {
      return rpc("finalize_offline_grant", {
        ...scoped(actor, scope),
        p_grant_id: grantId,
        p_claims: claims,
        p_signature: signature,
      });
    },
    ingest(actor, scope, envelope) {
      return rpc("ingest_offline_event", {
        ...scoped(actor, scope),
        p_event: envelope.event,
        p_digest: envelope.digest,
        p_authorization: envelope.authorization,
        p_signature: envelope.signature,
      });
    },
    pull(actor, scope, cursor, limit) {
      return rpc("pull_offline_changes", {
        ...scoped(actor, scope),
        p_cursor: cursor,
        p_limit: limit,
      });
    },
    release(actor, scope, grantId, sequence, signature) {
      return rpc("release_offline_grant", {
        ...scoped(actor, scope),
        p_grant_id: grantId,
        p_final_sequence: sequence,
        p_signature: signature,
      });
    },
  };
}
