import {
  type AuthDeliveryResult,
  createInvitationHandler,
  GatewayError,
  type InvitationGateway,
  type InvitationInput,
  type InvitationSnapshot,
  parseAllowedOrigins,
  validateRedirect,
} from "../../supabase/functions/employee-invitations/core.ts";
import { createSupabaseGateway } from "../../supabase/functions/employee-invitations/supabase_gateway.ts";

// All identities/keys/providers below are deterministic fixtures, never a live
// Supabase project or evidence of actual email/inbox delivery.
const organizationId = "10000000-0000-0000-0000-000000000001";
const branchId = "20000000-0000-0000-0000-000000000001";
const userId = "30000000-0000-0000-0000-000000000001";
const requestId = "40000000-0000-0000-0000-000000000001";
const invitationId = "50000000-0000-0000-0000-000000000001";
const claimId = "60000000-0000-0000-0000-000000000001";
const expiresAt = "2030-10-09T12:00:00.000Z";

function equal(actual: unknown, expected: unknown): void {
  if (JSON.stringify(actual) !== JSON.stringify(expected)) {
    throw new Error(
      `Expected ${JSON.stringify(expected)}, got ${JSON.stringify(actual)}`,
    );
  }
}

function assert(value: unknown, message = "Assertion failed"): asserts value {
  if (!value) throw new Error(message);
}

function throws(callback: () => unknown): void {
  let threw = false;
  try {
    callback();
  } catch {
    threw = true;
  }
  assert(threw, "Expected rejection");
}

function body(
  overrides: Record<string, unknown> = {},
): Record<string, unknown> {
  return {
    organization_id: organizationId,
    request_id: requestId,
    email: "employee@example.test",
    full_name: "Employee Fixture",
    role: "cashier",
    branch_ids: [branchId],
    all_branches: false,
    employee_id: "CASH-007",
    phone: null,
    reason: "Add a cashier for Main Branch",
    ...overrides,
  };
}

function request(
  value: unknown = body(),
  headers: Record<string, string> = {},
): Request {
  return new Request("https://functions.example.test/employee-invitations", {
    method: "POST",
    headers: {
      authorization: "Bearer fixture-user-jwt",
      "content-type": "application/json",
      ...headers,
    },
    body: JSON.stringify(value),
  });
}

function fixture() {
  const calls: string[] = [];
  let state: InvitationSnapshot["delivery_state"] = "prepared";
  let delivery: AuthDeliveryResult = { kind: "accepted" };
  let existing: AuthDeliveryResult = { kind: "accepted" };
  let receivedInput: InvitationInput | undefined;
  const snapshot = (): InvitationSnapshot => ({
    id: invitationId,
    expires_at: expiresAt,
    delivery_state: state,
  });
  const gateway: InvitationGateway = {
    verifyUser(token) {
      calls.push("verify");
      equal(token, "fixture-user-jwt");
      return Promise.resolve({ id: userId });
    },
    prepare(token, input) {
      calls.push("prepare");
      equal(token, "fixture-user-jwt");
      receivedInput = input;
      return Promise.resolve(snapshot());
    },
    claim(id) {
      calls.push("claim");
      equal(id, invitationId);
      if (state === "sent" || state === "sending") return Promise.resolve(null);
      state = "sending";
      return Promise.resolve({
        ...snapshot(),
        claim_id: claimId,
        organization_id: organizationId,
        normalized_email: "employee@example.test",
        full_name: "Employee Fixture",
      });
    },
    inviteNewUser(email, name) {
      calls.push("invite");
      equal(email, "employee@example.test");
      equal(name, "Employee Fixture");
      return Promise.resolve(delivery);
    },
    sendExistingUserLink(email) {
      calls.push("existing");
      equal(email, "employee@example.test");
      return Promise.resolve(existing);
    },
    finish(id, claim, succeeded) {
      calls.push("finish");
      equal(id, invitationId);
      equal(claim, claimId);
      state = succeeded ? "sent" : "failed";
      return Promise.resolve(snapshot());
    },
  };
  return {
    gateway,
    calls,
    input: () => receivedInput,
    handler: () =>
      createInvitationHandler({
        gateway,
        allowedOrigins: new Set(["https://app.example.test"]),
      }),
    setState: (value: typeof state) => state = value,
    setDelivery: (value: AuthDeliveryResult) => delivery = value,
    setExisting: (value: AuthDeliveryResult) => existing = value,
  };
}

Deno.test("verified user, actor-context prepare, atomic claim precede Auth invite and confirmed finish", async () => {
  const test = fixture();
  const response = await test.handler()(
    request(body({ email: "  Employee@Example.test  " })),
  );
  equal(response.status, 200);
  equal(await response.json(), {
    invitation_id: invitationId,
    expires_at: expiresAt,
    delivery_state: "sent",
  });
  equal(test.calls, ["verify", "prepare", "claim", "invite", "finish"]);
  equal(test.input()?.email, "employee@example.test");
  equal(response.headers.get("cache-control"), "no-store");
});

Deno.test("existing Auth identity fallback occurs only after authoritative email_exists", async () => {
  const test = fixture();
  test.setDelivery({ kind: "email_exists" });
  equal((await test.handler()(request())).status, 200);
  equal(test.calls, [
    "verify",
    "prepare",
    "claim",
    "invite",
    "existing",
    "finish",
  ]);
});

Deno.test("known provider rejection records failed and never confirms or sends existing-user OTP", async () => {
  const test = fixture();
  test.setDelivery({ kind: "rejected" });
  const response = await test.handler()(request());
  equal(response.status, 503);
  equal((await response.json()).delivery_state, "failed");
  assert(!test.calls.includes("existing"));
});

Deno.test("existing-user OTP rejection does not claim sent", async () => {
  const test = fixture();
  test.setDelivery({ kind: "email_exists" });
  test.setExisting({ kind: "rejected" });
  const response = await test.handler()(request());
  equal(response.status, 503);
  equal((await response.json()).delivery_state, "failed");
});

Deno.test("ambiguous provider outcome stays sending and repetition cannot dispatch again", async () => {
  const test = fixture();
  test.setDelivery({ kind: "uncertain" });
  const handler = test.handler();
  const first = await handler(request());
  equal(first.status, 202);
  equal((await first.json()).delivery_state, "sending");
  equal((await handler(request())).status, 202);
  equal(test.calls.filter((call) => call === "invite").length, 1);
  assert(!test.calls.includes("finish"));
});

Deno.test("accepted Auth plus failed finish remains unresolved and never automatically resends", async () => {
  const test = fixture();
  test.gateway.finish = () =>
    Promise.reject(new Error("sensitive raw provider failure"));
  const response = await test.handler()(request());
  equal(response.status, 202);
  equal((await response.json()).delivery_state, "sending");
  await test.handler()(request());
  equal(test.calls.filter((call) => call === "invite").length, 1);
});

Deno.test("sent request idempotency returns existing confirmation without a new email", async () => {
  const test = fixture();
  test.setState("sent");
  const response = await test.handler()(request());
  equal(response.status, 200);
  equal(test.calls, ["verify", "prepare"]);
});

Deno.test("concurrent requests share the atomic SQL claim and dispatch once", async () => {
  const test = fixture();
  const handler = test.handler();
  const responses = await Promise.all([handler(request()), handler(request())]);
  assert(
    responses.every((response) =>
      response.status === 200 || response.status === 202
    ),
  );
  equal(test.calls.filter((call) => call === "invite").length, 1);
});

Deno.test("invalid JWT is verified against Auth and cannot prepare or email", async () => {
  const test = fixture();
  test.gateway.verifyUser = () => Promise.resolve(null);
  const response = await test.handler()(request());
  equal(response.status, 401);
  equal(test.calls, []);
});

Deno.test("server SQL permission denial occurs before privileged dispatch", async () => {
  const test = fixture();
  test.gateway.prepare = () => Promise.reject(new GatewayError("denied"));
  const response = await test.handler()(request());
  equal(response.status, 403);
  equal(test.calls, ["verify"]);
});

Deno.test("SQL permission revoked during delivery claim prevents email", async () => {
  const test = fixture();
  test.gateway.claim = () => Promise.reject(new GatewayError("denied"));
  equal((await test.handler()(request())).status, 403);
  equal(test.calls, ["verify", "prepare"]);
});

Deno.test("immutable request-id conflict is a safe 409", async () => {
  const test = fixture();
  test.gateway.prepare = () => Promise.reject(new GatewayError("conflict"));
  const response = await test.handler()(request());
  equal(response.status, 409);
  equal(await response.json(), { error: "invitation_conflict" });
});

Deno.test("new invitation rate rejection is a sanitized 429 without email dispatch", async () => {
  const test = fixture();
  test.gateway.prepare = () =>
    Promise.reject(new GatewayError("rate_limited", 600));
  const response = await test.handler()(request());
  equal(response.status, 429);
  equal(response.headers.get("retry-after"), "600");
  equal(await response.json(), { error: "invitation_rate_limited" });
  equal(test.calls, ["verify"]);
});

Deno.test("known rejected delivery cooldown is a 429 and cannot dispatch", async () => {
  const test = fixture();
  test.setState("failed");
  test.gateway.claim = () =>
    Promise.reject(new GatewayError("rate_limited", 10));
  const response = await test.handler()(request());
  equal(response.status, 429);
  equal(response.headers.get("retry-after"), "10");
  equal(test.calls, ["verify", "prepare"]);
});

Deno.test("raw gateway messages are never returned", async () => {
  const test = fixture();
  test.gateway.prepare = () =>
    Promise.reject(new Error("fixture-secret-key/raw-auth-url"));
  const response = await test.handler()(request());
  equal(response.status, 503);
  assert(!(await response.text()).includes("fixture-secret"));
});

Deno.test("client cannot supply user authority or owner role", async () => {
  for (
    const overrides of [{ user_id: userId }, { actor_role: "owner" }, {
      role: "owner",
    }]
  ) {
    const test = fixture();
    equal((await test.handler()(request(body(overrides)))).status, 400);
    equal(test.calls, []);
  }
});

Deno.test("required scopes, valid UUIDs, distinct branches and field limits are enforced", async () => {
  for (
    const overrides of [
      { branch_ids: [] },
      { branch_ids: [branchId, branchId.toUpperCase()] },
      { organization_id: "not-a-uuid" },
      { request_id: "not-a-uuid" },
      { email: "invalid" },
      { full_name: "x" },
      { phone: "1".repeat(41) },
      { reason: "x".repeat(501) },
      { all_branches: "true" },
      { all_branches: true, role: "admin", branch_ids: [branchId] },
    ]
  ) {
    const test = fixture();
    equal((await test.handler()(request(body(overrides)))).status, 400);
    equal(test.calls, []);
  }
});

Deno.test("streamed oversized input is rejected without reading an unbounded body", async () => {
  const test = fixture();
  const response = await test.handler()(
    request(body({ reason: "x".repeat(9000) })),
  );
  equal(response.status, 413);
  equal(test.calls, []);
});

Deno.test("malformed JSON and wrong content type are rejected", async () => {
  const test = fixture();
  const malformed = new Request("https://functions.example.test", {
    method: "POST",
    headers: {
      authorization: "Bearer fixture-user-jwt",
      "content-type": "application/json",
    },
    body: "{",
  });
  equal((await test.handler()(malformed)).status, 400);
  equal(
    (await test.handler()(request(body(), { "content-type": "text/plain" })))
      .status,
    415,
  );
  equal(test.calls, []);
});

Deno.test("CORS accepts exact configured origins and never allows credentialed wildcard", async () => {
  const test = fixture();
  const allowed = await test.handler()(
    new Request("https://functions.example.test", {
      method: "OPTIONS",
      headers: { origin: "https://app.example.test" },
    }),
  );
  equal(allowed.status, 204);
  equal(
    allowed.headers.get("access-control-allow-origin"),
    "https://app.example.test",
  );
  equal(allowed.headers.get("access-control-allow-credentials"), null);
  const rejected = await test.handler()(
    request(body(), { origin: "https://app.example.test.evil.test" }),
  );
  equal(rejected.status, 403);
  equal(rejected.headers.get("access-control-allow-origin"), null);
  equal(test.calls, []);
});

Deno.test("missing authentication and unsupported methods cannot invoke gateway", async () => {
  const test = fixture();
  equal(
    (await test.handler()(request(body(), { authorization: "" }))).status,
    401,
  );
  equal(
    (await test.handler()(new Request("https://functions.example.test")))
      .status,
    405,
  );
  equal(test.calls, []);
});

Deno.test("redirect configuration accepts HTTPS or exact application callback and rejects unsafe redirects", () => {
  equal(
    validateRedirect("https://app.example.test/auth/callback"),
    "https://app.example.test/auth/callback",
  );
  equal(
    validateRedirect("com.nexapos.app://auth/callback"),
    "com.nexapos.app://auth/callback",
  );
  for (
    const value of [
      "http://app.example.test/callback",
      "javascript:alert(1)",
      "com.other.app://auth/callback",
      "com.nexapos.app://evil/callback",
      "https://user:password@example.test/callback",
      "https://example.test/#token",
    ]
  ) {
    throws(() => validateRedirect(value));
  }
});

Deno.test("origin configuration requires exact origins and allows explicit localhost development", () => {
  equal([
    ...parseAllowedOrigins("https://app.example.test,http://localhost:8080"),
  ], ["https://app.example.test", "http://localhost:8080"]);
  for (
    const value of [
      "*",
      "https://app.example.test/path",
      "http://app.example.test",
      "https://app.example.test/",
    ]
  ) {
    throws(() => parseAllowedOrigins(value));
  }
});

function json(value: unknown, status = 200): Response {
  return new Response(JSON.stringify(value), {
    status,
    headers: { "content-type": "application/json" },
  });
}

function promisedJson(value: unknown, status = 200): Promise<Response> {
  return Promise.resolve(json(value, status));
}

Deno.test("REST adapter separates actor JWT from service role and uses real supported Auth APIs", async () => {
  const calls: string[] = [];
  const gateway = createSupabaseGateway({
    url: "https://supabase.example.test",
    publicKey: "fixture-public-key",
    serviceRoleKey: "fixture-service-key",
    redirectUrl: "com.nexapos.app://auth/callback",
    fetch: (input, init) => {
      const url = new URL(input.toString());
      const headers = new Headers(init?.headers);
      const value = init?.body ? JSON.parse(init.body.toString()) : null;
      calls.push(url.pathname);
      switch (url.pathname) {
        case "/auth/v1/user":
          equal(headers.get("authorization"), "Bearer fixture-user-jwt");
          equal(headers.get("apikey"), "fixture-public-key");
          return promisedJson({ id: userId });
        case "/rest/v1/rpc/prepare_employee_invitation":
          equal(headers.get("authorization"), "Bearer fixture-user-jwt");
          equal(headers.get("apikey"), "fixture-public-key");
          equal(value.p_role, "cashier");
          equal(value.p_request_id, requestId);
          assert(!("p_user_id" in value));
          return promisedJson({
            id: invitationId,
            expires_at: expiresAt,
            delivery_state: "prepared",
          });
        case "/rest/v1/rpc/claim_invitation_delivery":
          equal(headers.get("authorization"), "Bearer fixture-service-key");
          equal(value, { p_invitation_id: invitationId });
          return promisedJson({
            id: invitationId,
            expires_at: expiresAt,
            delivery_state: "sending",
            claim_id: claimId,
            organization_id: organizationId,
            normalized_email: "employee@example.test",
            full_name: "Employee Fixture",
          });
        case "/auth/v1/invite":
          equal(headers.get("authorization"), "Bearer fixture-service-key");
          equal(
            url.searchParams.get("redirect_to"),
            "com.nexapos.app://auth/callback",
          );
          equal(value, {
            email: "employee@example.test",
            data: { full_name: "Employee Fixture" },
          });
          return promisedJson({ code: "email_exists" }, 422);
        case "/auth/v1/otp":
          equal(headers.get("authorization"), null);
          equal(headers.get("apikey"), "fixture-public-key");
          equal(value, { email: "employee@example.test", create_user: false });
          return promisedJson({});
        case "/rest/v1/rpc/finish_invitation_delivery":
          equal(headers.get("authorization"), "Bearer fixture-service-key");
          equal(value, {
            p_invitation_id: invitationId,
            p_claim_id: claimId,
            p_succeeded: true,
            p_error_code: null,
          });
          return promisedJson({
            id: invitationId,
            expires_at: expiresAt,
            delivery_state: "sent",
          });
        default:
          throw new Error("Unexpected fixture route");
      }
    },
  });
  const handler = createInvitationHandler({
    gateway,
    allowedOrigins: new Set(),
  });
  const response = await handler(request());
  equal(response.status, 200);
  equal(calls, [
    "/auth/v1/user",
    "/rest/v1/rpc/prepare_employee_invitation",
    "/rest/v1/rpc/claim_invitation_delivery",
    "/auth/v1/invite",
    "/auth/v1/otp",
    "/rest/v1/rpc/finish_invitation_delivery",
  ]);
});

Deno.test("REST adapter never infers email_exists from provider human text", async () => {
  const gateway = createSupabaseGateway({
    url: "https://supabase.example.test",
    publicKey: "fixture-public",
    serviceRoleKey: "fixture-service",
    redirectUrl: "https://app.example.test/callback",
    fetch: () =>
      Promise.resolve(json({ message: "User already registered" }, 422)),
  });
  equal(
    await gateway.inviteNewUser("employee@example.test", "Employee Fixture"),
    { kind: "rejected" },
  );
});

Deno.test("REST adapter treats HTTP 5xx and network timeouts as ambiguous", async () => {
  for (
    const fetchFixture of [
      () => Promise.resolve(json({ message: "upstream failure" }, 503)),
      () => Promise.reject(new Error("network fixture")),
    ]
  ) {
    const gateway = createSupabaseGateway({
      url: "https://supabase.example.test",
      publicKey: "fixture-public",
      serviceRoleKey: "fixture-service",
      redirectUrl: "https://app.example.test/callback",
      fetch: fetchFixture,
    });
    equal(
      await gateway.inviteNewUser("employee@example.test", "Employee Fixture"),
      { kind: "uncertain" },
    );
    equal(await gateway.sendExistingUserLink("employee@example.test"), {
      kind: "uncertain",
    });
  }
});

Deno.test("REST adapter refuses missing service credentials and insecure remote project URL", () => {
  const config = {
    url: "https://supabase.example.test",
    publicKey: "fixture-public",
    serviceRoleKey: "fixture-service",
    redirectUrl: "https://app.example.test/callback",
  };
  throws(() => createSupabaseGateway({ ...config, serviceRoleKey: "" }));
  throws(() =>
    createSupabaseGateway({ ...config, url: "http://supabase.example.test" })
  );
});

Deno.test("REST adapter maps SQL rate and cooldown machine codes without exposing raw details", async () => {
  for (const [code, seconds] of [["NX001", 600], ["NX002", 10]] as const) {
    const gateway = createSupabaseGateway({
      url: "https://supabase.example.test",
      publicKey: "fixture-public",
      serviceRoleKey: "fixture-service",
      redirectUrl: "https://app.example.test/callback",
      fetch: () =>
        promisedJson({ code, message: "raw internal fixture detail" }, 500),
    });
    let caught: unknown;
    try {
      await gateway.prepare(
        "fixture-user-jwt",
        body() as unknown as InvitationInput,
      );
    } catch (error) {
      caught = error;
    }
    assert(caught instanceof GatewayError);
    equal(caught.kind, "rate_limited");
    equal(caught.retryAfterSeconds, seconds);
    assert(!caught.message.includes("raw internal"));
  }
});
