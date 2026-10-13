import {
  createPinHandler,
  type PinGateway,
  PinGatewayError,
  type PinInput,
} from "../../supabase/functions/employee-pin/core.ts";
import { createPinSupabaseGateway } from "../../supabase/functions/employee-pin/supabase_gateway.ts";
const user = "10000000-0000-4000-8000-000000000001";
const org = "20000000-0000-4000-8000-000000000001";
const requestId = "30000000-0000-4000-8000-000000000001";
const operation = "40000000-0000-4000-8000-000000000001";
const member = "50000000-0000-4000-8000-000000000001";
function equal(a: unknown, b: unknown) {
  if (JSON.stringify(a) !== JSON.stringify(b)) throw new Error("Values differ");
}
function assert(v: unknown): asserts v {
  if (!v) throw new Error("Assertion failed");
}
const status = {
  membership_id: member,
  configured: true,
  reset_required: false,
  revision: 2,
  locked_until: null,
  changed_at: "2026-10-11T12:00:00Z",
};
function input(overrides: Record<string, unknown> = {}) {
  return {
    action: "set",
    organization_id: org,
    request_id: requestId,
    expected_revision: 1,
    pin: "739284",
    current_pin: null,
    ...overrides,
  };
}
function request(
  value: unknown = input(),
  headers: Record<string, string> = {},
) {
  return new Request("https://functions.example.invalid/employee-pin", {
    method: "POST",
    headers: {
      authorization: "Bearer fixture-user-token",
      "content-type": "application/json",
      ...headers,
    },
    body: JSON.stringify(value),
  });
}
function fixture() {
  const calls: string[] = [];
  let actor = user;
  let verified = true;
  let fault: Error | undefined;
  let received: PinInput | undefined;
  const gateway: PinGateway = {
    verifyUser() {
      calls.push("auth");
      return Promise.resolve(verified ? { id: user } : null);
    },
    authorize(_token, value) {
      calls.push("authorize");
      assert(!("pin" in value) && !("current_pin" in value));
      if (fault) throw fault;
      return Promise.resolve({ id: operation, actor_id: actor });
    },
    complete(_operation, _actor, value) {
      calls.push("complete");
      received = value;
      return Promise.resolve({ accepted: true, status });
    },
  };
  return {
    calls,
    handler: createPinHandler({
      allowedOrigins: new Set(["https://pos.example.invalid"]),
      gateway,
    }),
    setActor(v: string) {
      actor = v;
    },
    setVerified(v: boolean) {
      verified = v;
    },
    setFault(v: Error) {
      fault = v;
    },
    received: () => received,
  };
}
Deno.test("PIN dispatch verifies Auth, obtains user-context capability, then consumes once", async () => {
  const f = fixture();
  const r = await f.handler(request());
  equal(r.status, 200);
  equal(f.calls, ["auth", "authorize", "complete"]);
  equal((await r.json()).accepted, true);
  equal(r.headers.get("cache-control"), "no-store");
  equal(f.received()?.pin, "739284");
});
Deno.test("PIN authorization requires bearer and JSON", async () => {
  const f = fixture();
  equal((await f.handler(request(input(), { authorization: "" }))).status, 401);
  equal(
    (await f.handler(request(input(), { "content-type": "text/plain" })))
      .status,
    415,
  );
  equal(f.calls, []);
});
Deno.test("PIN cross-origin request fails before reading credentials", async () => {
  const f = fixture();
  equal(
    (await f.handler(
      request(input(), { origin: "https://other.example.invalid" }),
    )).status,
    403,
  );
  equal(f.calls, []);
});
Deno.test("PIN allowed preflight is body-free and no credentials authorization", async () => {
  const f = fixture();
  const r = await f.handler(
    new Request("https://functions.example.invalid/employee-pin", {
      method: "OPTIONS",
      headers: { origin: "https://pos.example.invalid" },
    }),
  );
  equal(r.status, 204);
  equal(
    r.headers.get("access-control-allow-origin"),
    "https://pos.example.invalid",
  );
  equal(f.calls, []);
});
Deno.test("PIN rejects role or capability injection and malformed identifiers", async () => {
  const f = fixture();
  for (
    const bad of [
      { role: "owner" },
      { operation_id: operation },
      { request_id: "not-a-uuid" },
      { expected_revision: 0 },
      { expected_revision: 1.5 },
    ]
  ) equal((await f.handler(request(input(bad)))).status, 422);
  equal(f.calls, []);
});
Deno.test("PIN boundary requires six to twelve ASCII digits without trimming", async () => {
  const f = fixture();
  for (
    const pin of [
      "12345",
      "1234567890123",
      "739284 ",
      "１２３４５６",
      "73a284",
      739284,
    ]
  ) equal((await f.handler(request(input({ pin })))).status, 422);
  equal(f.calls, []);
});
Deno.test("PIN verification cannot attach current PIN replacement data", async () => {
  const f = fixture();
  equal(
    (await f.handler(
      request(input({ action: "verify", current_pin: "849275" })),
    )).status,
    422,
  );
  equal(f.calls, []);
});
Deno.test("PIN body limit counts streamed bytes rather than only declared size", async () => {
  const f = fixture();
  equal((await f.handler(request({ payload: "x".repeat(2200) }))).status, 413);
  equal(f.calls, []);
  equal(
    (await f.handler(request(input(), { "content-length": "9999" }))).status,
    413,
  );
});
Deno.test("PIN invalid UTF8 and JSON are safe validation errors", async () => {
  const f = fixture();
  const r = await f.handler(
    new Request("https://functions.example.invalid/employee-pin", {
      method: "POST",
      headers: {
        authorization: "Bearer fixture-token",
        "content-type": "application/json",
      },
      body: new Uint8Array([0xff, 0xfe]),
    }),
  );
  equal(r.status, 422);
  equal(f.calls, []);
});
Deno.test("PIN Auth rejection cannot authorize or consume SQL capability", async () => {
  const f = fixture();
  f.setVerified(false);
  equal((await f.handler(request())).status, 401);
  equal(f.calls, ["auth"]);
});
Deno.test("PIN capability actor must match live Auth actor", async () => {
  const f = fixture();
  f.setActor(org);
  equal((await f.handler(request())).status, 403);
  equal(f.calls, ["auth", "authorize"]);
});
Deno.test("PIN SQL denial and lock limit remain fixed public errors", async () => {
  for (
    const [kind, code] of [["denied", 403], ["conflict", 409], [
      "limited",
      429,
    ]] as const
  ) {
    const f = fixture();
    f.setFault(new PinGatewayError(kind));
    equal((await f.handler(request())).status, code);
    equal(f.calls, ["auth", "authorize"]);
  }
});
Deno.test("PIN provider exception never returns supplied PIN or credential text", async () => {
  const f = fixture();
  f.setFault(new Error("fixture-secret-pin-739284 bearer-token"));
  const r = await f.handler(request());
  equal(r.status, 503);
  equal(await r.json(), { error: "unavailable" });
});
function gatewayFixture(
  options: {
    invalidCapability?: boolean;
    invalidStatus?: boolean;
    denied?: boolean;
  } = {},
) {
  const calls: { url: string; init: RequestInit }[] = [];
  const gateway = createPinSupabaseGateway({
    url: "https://project.example.invalid",
    publicKey: "fixture-public",
    serviceRoleKey: "fixture-service",
    fetch: (url, init) => {
      calls.push({ url: String(url), init: init ?? {} });
      if (String(url).endsWith("/user")) {
        return Promise.resolve(Response.json({ id: user }));
      }
      if (String(url).endsWith("/prepare_employee_pin_operation")) {
        if (options.denied) {
          return Promise.resolve(Response.json({
            code: "42501",
            message: "secret-database-detail",
          }, { status: 403 }));
        }
        return Promise.resolve(Response.json({
          id: options.invalidCapability ? "invalid" : operation,
          actor_id: user,
          expires_at: "2026-10-11T12:02:00Z",
        }));
      }
      return Promise.resolve(Response.json({
        accepted: true,
        status: {
          ...status,
          revision: options.invalidStatus ? "2" : 2,
          pin_hash: "never-return",
        },
        unexpected_secret: "never-return",
      }));
    },
  });
  return { calls, gateway };
}
Deno.test("PIN gateway keeps authorization under actor JWT, hashing under service credential", async () => {
  const f = gatewayFixture();
  const data = input() as PinInput;
  await f.gateway.verifyUser("fixture-user");
  await f.gateway.authorize("fixture-user", data);
  const result = await f.gateway.complete(operation, user, data);
  equal(f.calls.length, 3);
  const auth = f.calls[1].init;
  equal(
    (auth.headers as Record<string, string>).Authorization,
    "Bearer fixture-user",
  );
  equal((auth.headers as Record<string, string>).apikey, "fixture-public");
  const authorized = JSON.parse(String(auth.body));
  assert(!("p_pin" in authorized));
  assert(!("pin" in authorized));
  equal(
    (f.calls[2].init.headers as Record<string, string>).Authorization,
    "Bearer fixture-service",
  );
  equal(JSON.parse(String(f.calls[2].init.body)).p_actor_id, user);
  equal(result, { accepted: true, status });
  assert(!JSON.stringify(result).includes("never-return"));
  equal(f.calls[2].init.redirect, "error");
});
Deno.test("PIN gateway rejects malformed capability or malformed result without leaking raw rows", async () => {
  for (
    const options of [{ invalidCapability: true }, { invalidStatus: true }]
  ) {
    const f = gatewayFixture(options);
    let threw = false;
    try {
      if (options.invalidCapability) {
        await f.gateway.authorize(
          "fixture-user",
          input() as PinInput,
        );
      } else await f.gateway.complete(operation, user, input() as PinInput);
    } catch (e) {
      threw = e instanceof PinGatewayError && e.kind === "unavailable";
    }
    assert(threw);
  }
});
Deno.test("PIN gateway translates SQL authority denial without raw metadata", async () => {
  const f = gatewayFixture({ denied: true });
  let error: unknown;
  try {
    await f.gateway.authorize("fixture-user", input() as PinInput);
  } catch (e) {
    error = e;
  }
  assert(error instanceof PinGatewayError);
  equal(error.message, "denied");
});
Deno.test("PIN gateway does not follow redirects carrying service credentials", async () => {
  let redirect: RequestRedirect | undefined;
  const gateway = createPinSupabaseGateway({
    url: "https://project.example.invalid",
    publicKey: "fixture-public",
    serviceRoleKey: "fixture-service",
    fetch: (_url, init) => {
      redirect = init?.redirect;
      throw new TypeError("redirect rejected");
    },
  });
  let threw = false;
  try {
    await gateway.complete(operation, user, input() as PinInput);
  } catch (e) {
    threw = e instanceof PinGatewayError;
  }
  assert(threw);
  equal(redirect, "error");
});
Deno.test("PIN gateway rejects remote HTTP or credential-bearing project configuration", () => {
  for (
    const url of [
      "http://project.example.invalid",
      "https://user:pass@project.example.invalid",
      "https://project.example.invalid?token=fixture",
    ]
  ) {
    let threw = false;
    try {
      createPinSupabaseGateway({
        url,
        publicKey: "fixture-public",
        serviceRoleKey: "fixture-service",
      });
    } catch {
      threw = true;
    }
    assert(threw);
  }
});
