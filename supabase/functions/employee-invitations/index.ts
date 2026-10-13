import { createInvitationHandler, parseAllowedOrigins } from "./core.ts";
import { createSupabaseGateway } from "./supabase_gateway.ts";

// JWT signature verification also occurs through Auth /user in the handler.
// Deploy with --no-verify-jwt when using newer publishable-key projects; this
// does not authorize requests without a live verified user and SQL permission.
const gateway = createSupabaseGateway({
  url: Deno.env.get("SUPABASE_URL") ?? "",
  publicKey: Deno.env.get("SUPABASE_PUBLISHABLE_KEY") ??
    Deno.env.get("SUPABASE_ANON_KEY") ?? "",
  serviceRoleKey: Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? "",
  redirectUrl: Deno.env.get("INVITE_REDIRECT_URL") ?? "",
});

Deno.serve(createInvitationHandler({
  gateway,
  allowedOrigins: parseAllowedOrigins(
    Deno.env.get("INVITE_ALLOWED_ORIGINS") ?? "",
  ),
}));
