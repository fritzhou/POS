import { base64url } from "./protocol.ts";

/** Explicit deployment helper; neither the application nor Edge startup calls it. */
const [keyId, privateEnvPath, publicDefinesPath] = Deno.args;
if (
  !keyId || !/^[A-Za-z0-9_.-]{1,80}$/.test(keyId) || !privateEnvPath ||
  !publicDefinesPath || privateEnvPath === publicDefinesPath
) {
  throw new Error(
    "Usage: generate_key.ts KEY_ID PRIVATE_ENV_FILE PUBLIC_DEFINES_FILE",
  );
}
const pair = await crypto.subtle.generateKey("Ed25519", true, [
  "sign",
  "verify",
]) as CryptoKeyPair;
const privateKey = base64url(
  new Uint8Array(await crypto.subtle.exportKey("pkcs8", pair.privateKey)),
);
const publicKey = base64url(
  new Uint8Array(await crypto.subtle.exportKey("raw", pair.publicKey)),
);
const writeNew = async (path: string, contents: string) => {
  const file = await Deno.open(path, {
    createNew: true,
    write: true,
    mode: 0o600,
  });
  try {
    const bytes = new TextEncoder().encode(contents);
    let offset = 0;
    while (offset < bytes.length) {
      offset += await file.write(bytes.subarray(offset));
    }
    await file.sync();
  } finally {
    file.close();
  }
};
await writeNew(
  privateEnvPath,
  `OFFLINE_SIGNING_KEY_ID=${keyId}\nOFFLINE_SIGNING_PRIVATE_KEY_PKCS8=${privateKey}\n`,
);
await writeNew(
  publicDefinesPath,
  JSON.stringify(
    { OFFLINE_TRUSTED_KEYS_JSON: JSON.stringify({ [keyId]: publicKey }) },
    null,
    2,
  ) + "\n",
);
console.log(
  "Created private deployment environment file and separate public Flutter defines. Keep the private file out of Flutter and source control.",
);
