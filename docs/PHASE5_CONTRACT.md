# Phase 5 security contract

This phase hardens the already signed offline workflow; it never promotes a cached role, client PIN result or pending tender to server authority.

## Account and presentation

The entire Navigator is covered during idle/manual/background locking, including a payment dialog. A lock preserves durable grants, device keys and payment records. Unlock requires the same account password online and fresh membership verification; it cannot switch accounts or resurrect a logged-out session. Logout/recovery/definite authorization denial retain Phase 4's permanent device-key lock. Global sign-out calls the real Supabase Auth API: it revokes refresh sessions, while issued access tokens may live until their configured expiry.

Owner/Admin MFA policy requires server JWT AAL2 for privileged operations. A minimal read of that policy and Auth MFA setup remain reachable at AAL1 so users can upgrade. TOTP enrollment and verification use the provider API, with setup secrets confined to the live form and an isolated Auth client to prevent a delayed response restoring an old actor.

## Devices and paid records

Device metadata is display information, never proof of possession. Administration is tenant/branch scoped and audited. Revocation blocks enrollment/new grants and normal offline capture once observed. Immediate revocation while disconnected remains impossible within a previously issued short grant.

Original signed paid records remain uploadable for explicit server review under the same currently authorized actor after revocation; exact accepted replay returns the original receipt. Administrative lost-key resolution requires a revoked device, an expired grant, a reason and acknowledgement of unknown paid exposure. It records the known sequence/count/value and remaining maximum exposure, without manufacturing a device final-sequence signature. Late records go to review and never silently post new stock or disappear. A resolved shift barrier is an audited administrative risk decision, not proof that all physical payments arrived.

## PIN and local files

PINs are separate from the account password and remain online only. Existing PINs cannot be retrieved. Reset is an audited current-authority operation; employees choose a new PIN through a server-only, salted slow verifier with persistent failed-attempt locking. Delegated approvals are deferred until financial RPCs consume exact action/request-bound proofs. Verification alone grants no financial permission or identity.

The existing sqlite3 package's SQLCipher native assets provide file encryption on Android/Windows/Linux. Random per-file keys live in OS secure storage, independent of session/device-key deletion. Existing business and operation-journal data migrate through crash-safe encrypted export and recovery; missing encrypted-file keys fail closed rather than recreating an empty database. Platform vault behavior and backup/key recovery still require physical-device acceptance.

## Partial manual tender

Offline operator-confirmed payment fragments are durably appended before the dialog reports them recorded; original checkout/tender IDs, cart, grant and evidence survive cancellation/restart. A separate immutable signature record follows the evidence. A captured fragment without a completed proof remains visible for review and blocks new collection. Only a valid current grant may authorize more tender or finalize a new sale. Expiry does not delete evidence or invent a receipt. No provider capture API is connected.

## Evidence and platform limits

In-app security notices derive from authoritative backend changes; login/failure/password events require a real Auth event pipeline and are not inferred from client claims. Device enrollment inventory does not imply every online Auth session is bound to that device. Physical scanners/camera, Windows compilation/vaults, live Auth/Edge/PostgREST, commercial backup recovery and release signing remain separate acceptance gates. Debug builds must keep their real signing status.
