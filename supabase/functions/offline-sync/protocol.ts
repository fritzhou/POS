/** Canonical bytes are shared with Dart SyncEvent v1. No runtime packages. */
export type Json = null | boolean | number | string | Json[] | {
  [key: string]: Json;
};
export type JsonObject = { [key: string]: Json };

export class OfflineError extends Error {
  constructor(
    readonly kind:
      | "invalid"
      | "denied"
      | "conflict"
      | "preparation_expired"
      | "unavailable"
      | "rate_limited",
  ) {
    super(kind);
  }
}

export function object(value: unknown): JsonObject {
  if (!value || typeof value !== "object" || Array.isArray(value)) {
    throw new OfflineError("invalid");
  }
  return value as JsonObject;
}

export function isUuid(value: unknown): value is string {
  return typeof value === "string" &&
    /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i.test(
      value,
    );
}

export function validUnicode(value: string): boolean {
  for (let index = 0; index < value.length; index++) {
    const unit = value.charCodeAt(index);
    if (unit >= 0xd800 && unit <= 0xdbff) {
      const next = value.charCodeAt(++index);
      if (!(next >= 0xdc00 && next <= 0xdfff)) return false;
    } else if (unit >= 0xdc00 && unit <= 0xdfff) return false;
  }
  return true;
}

export function canonicalJson(value: unknown, depth = 0): string {
  if (depth > 30) throw new OfflineError("invalid");
  if (value === null || typeof value === "boolean") {
    return JSON.stringify(value);
  }
  if (typeof value === "string") {
    if (!validUnicode(value)) throw new OfflineError("invalid");
    return JSON.stringify(value);
  }
  if (typeof value === "number") {
    if (!Number.isSafeInteger(value) || Object.is(value, -0)) {
      throw new OfflineError("invalid");
    }
    return JSON.stringify(value);
  }
  if (Array.isArray(value)) {
    return `[${value.map((item) => canonicalJson(item, depth + 1)).join(",")}]`;
  }
  if (
    value && typeof value === "object" &&
    Object.getPrototypeOf(value) === Object.prototype
  ) {
    const data = value as Record<string, unknown>;
    return `{${
      Object.keys(data).sort().map((key) =>
        `${canonicalJson(key, depth + 1)}:${
          canonicalJson(data[key], depth + 1)
        }`
      ).join(",")
    }}`;
  }
  throw new OfflineError("invalid");
}

export function base64url(bytes: Uint8Array): string {
  return btoa(String.fromCharCode(...bytes)).replace(/\+/g, "-").replace(
    /\//g,
    "_",
  ).replace(/=+$/, "");
}

export function decodeBase64url(
  value: unknown,
  size?: number,
): Uint8Array<ArrayBuffer> {
  if (
    typeof value !== "string" || !/^[A-Za-z0-9_-]+$/.test(value) ||
    value.length > 1024
  ) throw new OfflineError("invalid");
  let bytes: Uint8Array<ArrayBuffer>;
  try {
    bytes = Uint8Array.from(
      atob(value.replace(/-/g, "+").replace(/_/g, "/")),
      (item) => item.charCodeAt(0),
    );
  } catch {
    throw new OfflineError("invalid");
  }
  if (
    (size !== undefined && bytes.length !== size) || base64url(bytes) !== value
  ) throw new OfflineError("invalid");
  return bytes;
}

export async function digest(value: unknown): Promise<string> {
  const bytes = await crypto.subtle.digest(
    "SHA-256",
    new TextEncoder().encode(canonicalJson(value)),
  );
  return [...new Uint8Array(bytes)].map((item) =>
    item.toString(16).padStart(2, "0")
  ).join("");
}

export function signatureBytes(
  domain: "grant" | "enroll" | "event" | "release",
  value: unknown,
): Uint8Array<ArrayBuffer> {
  return new TextEncoder().encode(
    `NexaPOS:${domain}:v1\n${canonicalJson(value)}`,
  );
}

export async function verifySignature(
  publicKey: unknown,
  signature: unknown,
  domain: "grant" | "enroll" | "event" | "release",
  value: unknown,
): Promise<boolean> {
  const key = await crypto.subtle.importKey(
    "raw",
    decodeBase64url(publicKey, 32),
    "Ed25519",
    false,
    ["verify"],
  );
  return crypto.subtle.verify(
    "Ed25519",
    key,
    decodeBase64url(signature, 64),
    signatureBytes(domain, value),
  );
}

/** Only deployment supplies this private key. Its public key must be pinned independently in Flutter. */
export class GrantSigner {
  private constructor(
    readonly issuer: string,
    readonly keyId: string,
    readonly publicKey: string,
    private readonly key: CryptoKey,
  ) {}

  static async fromPkcs8(
    issuer: string,
    keyId: string,
    encoded: string,
  ): Promise<GrantSigner> {
    const url = new URL(issuer);
    if (
      url.username || url.password || url.search || url.hash ||
      url.pathname !== "/" ||
      (url.protocol !== "https:" &&
        !(url.protocol === "http:" &&
          ["localhost", "127.0.0.1", "[::1]"].includes(url.hostname))) ||
      !/^[A-Za-z0-9_.-]{1,80}$/.test(keyId)
    ) throw new Error("Invalid offline signing configuration");
    const imported = await crypto.subtle.importKey(
      "pkcs8",
      decodeBase64url(encoded),
      "Ed25519",
      true,
      ["sign"],
    );
    const jwk = await crypto.subtle.exportKey("jwk", imported);
    if (!jwk.x) throw new Error("Invalid offline signing configuration");
    const key = await crypto.subtle.importKey(
      "pkcs8",
      decodeBase64url(encoded),
      "Ed25519",
      false,
      ["sign"],
    );
    return new GrantSigner(issuer.replace(/\/$/, ""), keyId, jwk.x, key);
  }

  async sign(claims: JsonObject): Promise<string> {
    return base64url(
      new Uint8Array(
        await crypto.subtle.sign(
          "Ed25519",
          this.key,
          signatureBytes("grant", claims),
        ),
      ),
    );
  }
}

export function strictKeys(
  value: JsonObject,
  allowed: readonly string[],
  required: readonly string[] = [],
): void {
  if (
    Object.keys(value).some((key) => !allowed.includes(key)) ||
    required.some((key) => !(key in value))
  ) throw new OfflineError("invalid");
}

export function integer(value: unknown, min: number, max: number): number {
  if (
    typeof value !== "number" || !Number.isSafeInteger(value) ||
    Object.is(value, -0) || value < min ||
    value > max
  ) throw new OfflineError("invalid");
  return value;
}

export function utcTime(value: unknown): number {
  return Number(utcMicroseconds(value)) / 1000;
}

/** Validate the calendar without Date.parse's silent February/day rollovers. */
export function utcMicroseconds(value: unknown): bigint {
  if (
    typeof value !== "string" ||
    !/^\d{4}-\d\d-\d\dT\d\d:\d\d:\d\d(?:\.\d{1,6})?(?:Z|\+00:00)$/.test(value)
  ) throw new OfflineError("invalid");
  const seconds = value.slice(0, 19);
  const time = Date.parse(`${seconds}.000Z`);
  if (
    !Number.isFinite(time) ||
    new Date(time).toISOString().slice(0, 19) !== seconds
  ) throw new OfflineError("invalid");
  const fraction = /\.(\d{1,6})/.exec(value)?.[1] ?? "";
  return BigInt(time) * 1000n + BigInt(fraction.padEnd(6, "0"));
}
