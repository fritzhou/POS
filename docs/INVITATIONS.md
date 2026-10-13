# Employee invitation deployment and lifecycle

The `employee-invitations` Supabase Edge Function calls Supabase Auth's administrative invitation endpoint for a new Auth identity. When Auth returns the machine error `email_exists`, it requests a magic link for the existing identity using `create_user: false`. It does not create a duplicate account, reset another user's password, inspect arbitrary Auth users, or expose service credentials to Flutter. Human error messages are never used to determine whether an account exists.

PostgreSQL creates the business invitation under the verified actor's JWT. That RPC checks the active Owner/Admin membership, requested role and every requested branch. An Owner can invite an Admin or a lower role. An Admin can invite lower roles within their current branch authority. The server never accepts an actor user ID or actor role from the request. The invitation's requested role and branch assignments are server-stored business data, not authority taken from Auth metadata.

## Required deployment configuration

Apply all fifteen migrations in filename order before deploying the function. The function requires the platform's `SUPABASE_URL`, public client key (`SUPABASE_PUBLISHABLE_KEY` or legacy `SUPABASE_ANON_KEY`) and server-only `SUPABASE_SERVICE_ROLE_KEY`. The public client key cannot replace the service-role key. Store keys in secured Supabase function settings, never application configuration, Git, chat, or an installation script.

Set `INVITE_REDIRECT_URL` to the intended HTTPS callback or `com.nexapos.app://auth/callback`. Add that **exact URL** to the Supabase Auth redirect allowlist and configure the app's callback handler before deployment. The function validates the URL's scheme and rejects embedded credentials and fragments; this validation cannot read or certify the dashboard allowlist. Other custom schemes and remote HTTP redirects are rejected.

Set `INVITE_ALLOWED_ORIGINS` to a comma-separated list of exact browser origins such as `https://pos.example.com`. An empty list permits native clients without an `Origin` header but blocks browser origins. Explicit local development origins such as `http://localhost:8080` are supported. Wildcards, paths and remote HTTP origins are rejected. CORS uses bearer authentication and never enables browser credential cookies.

Enable Supabase email authentication and confirmation, configure Auth email rate limits and production SMTP, and customize both the Auth **Invite user** and **Magic link** templates. These are two different built-in Auth delivery paths. The HTML files in `supabase/templates/` remain static design previews; they are not evidence of configured delivery.

Deploy from the repository with an authenticated Supabase CLI and the intended non-production project selected:

```sh
supabase functions deploy employee-invitations --no-verify-jwt
```

`--no-verify-jwt` allows compatibility with newer public-key projects; the handler still validates every bearer token through Supabase Auth's `GET /auth/v1/user` before invoking its actor-context SQL RPC. Native and browser clients must send a live user access token. No JWT is trusted merely because it decodes successfully.

## Function request and response

Send `POST /functions/v1/employee-invitations` with `Authorization: Bearer <user access token>`, the project public `apikey` header and `Content-Type: application/json`. The body is limited to 8 KiB. Unknown fields and malformed values are rejected.

```json
{
  "organization_id": "10000000-0000-0000-0000-000000000001",
  "request_id": "40000000-0000-0000-0000-000000000001",
  "email": "employee@example.com",
  "full_name": "New Employee",
  "role": "cashier",
  "branch_ids": ["20000000-0000-0000-0000-000000000001"],
  "all_branches": false,
  "employee_id": "CASH-007",
  "phone": null,
  "reason": "Add a cashier for Main Branch"
}
```

Generate one UUID `request_id` for one intended invitation and retain it while retrying that operation. Reusing the ID with a different payload fails; a new ID represents a new operation and should not be generated automatically on a timeout. Branch order is normalized for idempotency. SQL fixes the business invitation's expiry at seven days; Supabase Auth separately controls its own email action credential expiry. The example identifiers are fixtures and have no live authority.

An HTTP 200 response contains `{invitation_id, expires_at, delivery_state: "sent"}` only after Auth accepted an email request and the SQL delivery receipt was saved. It establishes provider acceptance, not inbox arrival. The UI must describe that limited confirmation accurately. HTTP 202 with `delivery_state: "sending"` means an outcome remains unresolved and must not be presented as sent. HTTP 503 with `delivery_state: "failed"` records a known rejection. Authentication, input, permission and request-conflict errors use sanitized 401/400/403/409 responses; throttling uses HTTP 429 with `error: "invitation_rate_limited"`. Raw SQL/Auth messages, emails, Auth URLs and credentials are not returned or logged.

## Delivery and acceptance security

The SQL delivery state is `prepared → sending → sent` or `prepared → sending → failed`. A server-only atomic claim allows one dispatcher. Permission checks run before preparation and again before claiming. `sent` and `sending` repetitions do not send another email. A known rejected dispatch may be retried with the same request ID after a ten-second cooldown. Network timeouts and HTTP 5xx responses remain `sending`, because Auth may already have accepted the email. If Auth succeeds but recording the receipt fails, the state also remains `sending`. There is no timed automatic reclaim; administrative reconciliation of ambiguous delivery is deferred. This preserves protection against duplicate accepted dispatches.

PostgreSQL caps new invitations at 20 per organization in a rolling ten-minute window and 200 per organization in a rolling 24-hour window. An organization-wide advisory lock prevents different administrators or concurrent request IDs from bypassing the count. Known idempotent requests return before these new-operation limits, so a status retry remains available at the cap. The Edge Function normalizes SQL rate and cooldown codes into HTTP 429; `Retry-After` is 600 seconds for a new-operation limit and 10 seconds for a rejected-delivery cooldown. The ten-minute hint does not guarantee a daily cap has cleared. Supabase Auth's own project/email rate limits remain a separate requirement.

Set `all_branches: true` only for an Owner-created Admin invitation and send an empty `branch_ids` array in that case. Other invitations require one or more distinct branches. Invitation audit records store the complete immutable branch snapshot and the all-branch flag; a scoped Admin cannot read a multi-branch invitation's audit merely by having access to its first branch.

Supabase Auth owns the invitation/magic-link credential, expiry, replay protections and verified email proof. The earlier architecture's custom invitation-secret digest is superseded by this Auth-owned credential boundary. A business invitation UUID is a lookup identifier, not a bearer credential. Flutter lists pending invitations only under a verified identity, and acceptance checks that identity's current verified email against the stored normalized email. It transactionally rechecks expiry, delivery state, inviter authority and branch eligibility before creating membership and assignments. Changing email, replaying another invitation UUID, or submitting an Auth metadata role cannot confer access. `list_pending_invitations(p_limit)` defaults to 100 and accepts limits from 1 through 100; it returns a JSON array without granting direct recipient access to business tables.

An invited account must finish its supported password setup before business acceptance when the SQL password requirement applies. Adding membership to an existing organization must not automatically bootstrap a new Owner organization. Revoked/expired invitations and changed inviter roles or branch assignments fail closed. Acceptance consumes the invitation once and denies replay. If the acceptance response is lost, reload current memberships rather than assuming the operation failed or blindly replaying it. A pending invitation does not provide business access or offline authorization.

## Administrator workflow

Phase 6D implements **Employees → Invitations** for the current verified Owner/Admin. History supports literal search, status filters, pages and detail; pending does not grant employee access. The new history RPCs check configured MFA and the entire original branch assignment, including inactive branches. Only an Owner can mutate an Admin invitation. Missing legacy branch evidence remains read only for an all-branch administrator and inaccessible to a scoped Admin.

Only the original inviter can retry an eligible `prepared` or known `failed` request. Current detail supplies the exact original UUID and payload, including phone/reason; the client compares it again before using the existing Edge endpoint. `sent` means accepted by Auth, and `sending` remains uncertain without a new dispatcher or automatic replacement. Legacy accepted records may retain `prepared` because migration 5 supplied that default; they remain accepted history without fabricated delivery facts.

Revocation uses `revoke_employee_invitation_action`, a stable UUID/revision/reason and the encrypted actor/organization journal. Current authorization precedes successful replay; the invitation row serializes acceptance, revocation and dispatch. One immutable action/request receipt and audit commit atomically. A claimed email may still arrive after revocation, while business acceptance is denied. Lost/malformed responses and later denial after an uncertain attempt retain the original pending request. Read [PHASE6D_CONTRACT.md](PHASE6D_CONTRACT.md) for the complete wire, scope and recovery rules.

## Validation and remaining deployment checks

Run the deterministic function tests without network or secret permissions:

```sh
deno check supabase/functions/employee-invitations/index.ts
deno test --allow-read=test/fixtures test/functions
```

Tests exercise actual handler and REST adapter code using injected test gateways. They verify ordering, JWT and service-key separation, new/existing-account API paths, duplicate prevention, uncertain delivery, SQL denials, CORS, redirect validation, payload limits and sanitized failures. They do not send email or claim live service connectivity.

Before production, exercise a new email and an existing Auth account in a real test project, verify each actual template/callback, set the password when needed, accept the business invitation, and confirm that role/branch restrictions apply. Also test a revoked invitation, an expired invitation, inviter disable/role change, an out-of-scope branch and a repeated request ID. Confirm the allowed browser origin and native Android/Windows callback on target platforms. Until those checks run, live delivery and callback behavior remain unverified.
