import { createPinHandler, parseAllowedOrigins } from "./core.ts";
import { createPinSupabaseGateway } from "./supabase_gateway.ts";

// Auth /user and actor-JWT SQL authorization are mandatory even if this function
// is deployed with --no-verify-jwt for publishable-key projects.
Deno.serve(createPinHandler({
  allowedOrigins: parseAllowedOrigins(
    Deno.env.get("PIN_ALLOWED_ORIGINS") ?? "",
  ),
  gateway: createPinSupabaseGateway({
    url: Deno.env.get("SUPABASE_URL") ?? "",
    publicKey: Deno.env.get("SUPABASE_PUBLISHABLE_KEY") ??
      Deno.env.get("SUPABASE_ANON_KEY") ?? "",
    serviceRoleKey: Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? "",
  }),
}));
