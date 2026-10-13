import { createOfflineHandler, parseAllowedOrigins } from "./core.ts";
import { decodeBase64url, GrantSigner, object } from "./protocol.ts";
import { createSupabaseOfflineGateway } from "./supabase_gateway.ts";

// Missing deployment signing configuration fails closed; never create a runtime key.
const signer = await GrantSigner.fromPkcs8(
  Deno.env.get("SUPABASE_URL") ?? "",
  Deno.env.get("OFFLINE_SIGNING_KEY_ID") ?? "",
  Deno.env.get("OFFLINE_SIGNING_PRIVATE_KEY_PKCS8") ?? "",
);
const verificationKeys = new Map<string, string>();
const rotation = Deno.env.get("OFFLINE_VERIFICATION_KEYS_JSON");
if (rotation) {
  for (const [id, key] of Object.entries(object(JSON.parse(rotation)))) {
    if (!/^[A-Za-z0-9_.-]{1,80}$/.test(id) || typeof key !== "string") {
      throw new Error("Invalid offline verification configuration");
    }
    decodeBase64url(key, 32);
    verificationKeys.set(id, key);
  }
}
const gateway = createSupabaseOfflineGateway({
  url: Deno.env.get("SUPABASE_URL") ?? "",
  publicKey: Deno.env.get("SUPABASE_PUBLISHABLE_KEY") ??
    Deno.env.get("SUPABASE_ANON_KEY") ?? "",
  serviceRoleKey: Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? "",
});

// Deploy --no-verify-jwt for publishable-key projects. Auth /user remains mandatory.
Deno.serve(createOfflineHandler({
  signer,
  gateway,
  verificationKeys,
  allowedOrigins: parseAllowedOrigins(
    Deno.env.get("OFFLINE_ALLOWED_ORIGINS") ?? "",
  ),
}));
