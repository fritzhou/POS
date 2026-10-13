# Offline signing and synchronization backend

Phase 4 source supplies an `offline-sync` Edge Function with native WebCrypto
Ed25519, real Auth `/user` verification, and narrow PostgreSQL RPC calls.
These are deployable integrations, not a configured live project. Signing keys,
enrollment, live PostgREST/Edge behavior and actual Windows/Android secure
storage remain deployment/platform checks.

## Deployment prerequisites

Apply all migrations, including `202610100007_offline_authorization_and_sync.sql`, to a
non-production Supabase project first. Existing accepted financial records and
local pending sales must be retained. Never reset a user's database to enable
offline mode.

Configure Edge-only secrets:

| Variable | Purpose |
| --- | --- |
| `SUPABASE_URL` | HTTPS project origin, also the signed grant issuer |
| `SUPABASE_PUBLISHABLE_KEY` or `SUPABASE_ANON_KEY` | Auth `/user` and authenticated enrollment-challenge RPC |
| `SUPABASE_SERVICE_ROLE_KEY` | Service-only enrollment, grant, ingest, pull and release RPCs |
| `OFFLINE_SIGNING_KEY_ID` | Stable deployment key identifier |
| `OFFLINE_SIGNING_PRIVATE_KEY_PKCS8` | Unpadded base64url Ed25519 PKCS8 private key |
| `OFFLINE_VERIFICATION_KEYS_JSON` | Optional old-key-ID to raw-public-key map for rotation overlap |
| `OFFLINE_ALLOWED_ORIGINS` | Comma-separated explicit HTTPS web origins; localhost HTTP is permitted for development |

An absent signing key fails startup. Startup never generates one, and no private
key, service credential, token or PIN belongs in Flutter defines, an event,
a cache snapshot or a log.

The explicit helper creates a new key pair only when an operator invokes it.
It refuses existing output files, writes with mode `0600`, and does not print
private key material. For example, after creating a local `config` directory:

```sh
source tool/dev_env.sh
deno run --allow-write=config \
  supabase/functions/offline-sync/generate_key.ts \
  offline-2026-01 config/.env.offline-signing config/offline-public.local.json
```

Keep the private environment file in the deployment secret store and exclude it
from source control. Existing `config/*.local.json` ignore rules protect the
public sample output, and `.env.*` ignores the example private file. Use a
private secret-store path for deployed keys. No deployment keys were generated as
part of the local implementation tests.

Install the private variables as Supabase function secrets. Merge **only** the
public `OFFLINE_TRUSTED_KEYS_JSON` value into the Flutter public configuration
alongside its project URL/client key. The app's public key pins must come from
that independently reviewed configuration, never from a preparation response.

Deploy with the CLI's publishable-key-compatible option when needed:

```sh
supabase functions deploy offline-sync --no-verify-jwt
```

The function still requires a bearer token validated against Auth `/user`, a
verified email, and current SQL membership/branch/device authority. Disabling
the gateway's legacy JWT precheck does not disable those checks.

## HTTP actions

POST JSON to `/functions/v1/offline-sync`. Every action includes
`organization_id`, `branch_id`, and `device_id`; IDs are lowercase UUIDs. The
actor is derived from Auth and cannot be supplied by the client.

| `action` | Additional inputs | Response |
| --- | --- | --- |
| `enroll_challenge` | `public_key`, actual `device_name`, `platform` | `{challenge}` |
| `enroll` | `challenge_id`, device `signature` | Stored enrolled-device result |
| `prepare` | Stable `request_id` | `{grant:{claims,signature},snapshot,server_time}` |
| `ingest` | Original `event`, `digest`, detached `authorization`, device `signature` | Stored `accepted` or `review` result |
| `pull` | Integral `cursor`; optional `limit` from 1 to 100 | Scoped changes, cursor, `has_more`, server time |
| `release` | `grant_id`, `final_sequence`, device `signature` | Stored release result |

Preparation selects the actor's existing open server shift. It does not open a
new shift or grant a caller-selected role. SQL freezes issuance-time settings,
products, categories and stock; the function checks the snapshot's canonical
SHA-256 before signing its retained claims and finalizing them. A lost
finalization response produces an unavailable result; retry the same request.
An already finalized retry returns the retained signature, including during a
trusted signing-key rotation or after grant expiry. Returning an expired grant
does not extend its lifetime: the client may retain it to reconcile and release
the original reservation, while new offline capture remains disabled.
An expired preparation that never received a server signature and has no events
can receive a server-owned append-only abandonment outcome. Its exact retry
returns HTTP 409 `offline_preparation_expired`, allowing the client to finish
that empty preparation journal before requesting a fresh grant. This outcome
cannot abandon a signed grant or any paid event, and it does not authorize
offline capture.

Enrollment signs the **retained** server challenge, including its public key and
actor/organization/branch/device scope. Ingestion recomputes the original v1
event digest, checks the retained grant signature under configured trusted keys,
and verifies the detached device signature before invoking service-only SQL.
SQL independently checks current authority, immutable replay content, event
sequence, time bounds, original snapshot prices/tax, limits and payment evidence.

An accepted response must echo scope, actor, device, grant, sequence, event ID,
digest and original document ID. The function checks receipt identity and
scope, original line/payment identities, amounts, manual tender evidence and
the complete set of product stock-impact revisions; it returns the receipt supplied by SQL. It never invents receipt
acceptance. A `review` response uses HTTP 202 and remains separate from
financial acceptance. Keep the paid local snapshot and its stock effects while
awaiting review. Refunds and other correction remain explicit compensating
documents.

## Protocol, expiry and key rotation

[PHASE4_CONTRACT.md](PHASE4_CONTRACT.md) specifies canonical bytes and signature
domains. TypeScript writes sorted object entries directly, preserving lexical
ordering even for numeric-looking keys. It rejects unsafe/nonintegral numbers,
unpaired UTF-16 surrogates, noncanonical/padded base64url and unknown request
fields. Request bodies are limited to 256 KiB, including streamed bodies.
Responses have no-store headers, bounded explicit CORS, and fixed sanitized
error names. UTC validation rejects normalized invalid calendar dates and
retains microseconds when checking the eight-hour grant bound. Negative zero
is rejected at the JSON boundary. Service HTTP requests reject redirects so
neither user tokens nor service credentials follow another origin.
SQL enforces durable preparation/enrollment limits; each Edge
instance is not treated as an authoritative rate counter.

Grant expiry blocks new local sales. Already captured sales have a bounded
72-hour ingestion grace, and exact already-accepted retries can return their
stored identity after expiry, subject to current authority/device checks.
Software keys and wall clocks cannot prove an unmodified offline creation time.
Counts/value ceilings, retained snapshots, clock rollback checks and server
review bound that trust; hardware-backed keys/time are later hardening work.

Logout, recovery and definite permission denial delete the local device seed.
Original paid-event proofs remain eligible for the same actor's verified online
upload without re-signing. A deleted seed cannot prove a signed final release,
so the shift barrier remains in force and the workspace must show that
administrator review is required. Explicit lost-key administration and closure
resolution are Phase 5 production work; this implementation neither fabricates
a replacement proof nor silently releases a signed grant.

For signing-key rotation, keep old public keys in both the Flutter trusted-key
map and `OFFLINE_VERIFICATION_KEYS_JSON` while their legitimate queued events
and releases remain eligible. The active key is always derived from the
configured private key; a rotation map cannot replace it. Removing a public key
can strand pending financial events, so reconcile queues before removing trust.

## PostgreSQL durability and concurrency

Migration 007 retains one device key identity per actor and organization. Each
branch needs a separately verified enrollment challenge; a fresh same-key proof
also supports retrying preparation after a lost response. Proofs and branch
bindings append to history. A replacement actor, organization or public key
conflicts, and device revocation applies to every branch binding. One unreleased
grant per device limits preparation across branches.

The signed issuance instant and retained SQL bounds use the same millisecond
precision. Existing preparation requests return their original claims/snapshot;
a finalized request also returns its original signature, so an overlapping
trusted public key can recover the response during signing-key rotation.
Changing the issuer or scope conflicts. An unfinished preparation whose old
private signing key is unavailable remains a deployment recovery case.

Normal checkout, receiving, adjustment, reversal, catalog/settings writes and
offline preparation/ingestion acquire the organization change-counter lock
before financial/catalog row locks. Revision allocation holds that lock through
commit, and snapshot/pull use the same lock. This prevents both skipped late
commits and a counter/product lock cycle between overlapping writers. Scoped
pulls preserve tombstones and safely advance past other-branch changes only
after their visible page is exhausted. Stock revision counts actual movements;
accepted offline acknowledgments expose the precise impact revision.

Every signed unreleased grant, including an expired one, blocks normal shift
closure until its signed final sequence is retained. An unsigned reservation
can also block closure while it is still finalizable. Once expired, SQL may
append `EXPIRED_UNSIGNED` abandonment only if there is no retained signature,
no event outcome, and zero retained sequence/paid total. Edge never returns
authorization before signature finalization, so this narrow cleanup cannot
abandon a valid paid authorization. It preserves the original reservation and
forbids later finalization. Retrying its original preparation returns SQLSTATE
`NX002`, exposed as HTTP 409 `offline_preparation_expired`; the client can then
resolve that never-authorized preparation before requesting a new grant.

The disposable SQL harness passes 563 assertions: 425 existing assertions,
128 Phase 4 authority/financial/feed checks, and 10 additional concurrency
assertions. Independent PostgreSQL connections exercise a late-committing feed
writer with a competing writer/pull, duplicate upload of one signed paid event,
and preparation racing normal shift close. The harness also retains the earlier
owner-bootstrap, catalog-CAS, last-unit checkout and online retry races.

## Local validation

```sh
source tool/dev_env.sh
deno check supabase/functions/offline-sync/index.ts
deno lint supabase/functions/offline-sync test/functions
deno test --allow-read=test/fixtures test/functions
```

Tests use public RFC8032 material and isolated in-memory/HTTP test doubles;
they do not create production signing keys, users, sales or email delivery.
The actual isolated PostgreSQL prepare, accepted receipt, signed stock deficit,
and pull responses are retained in `test/fixtures/offline_sql_contract.json`.
Its signed companion replaces SQL service-boundary placeholder signatures with
public RFC8032 test material while preserving the original SQL event/snapshot
hashes and receipt/feed bytes. The Edge contract test validates those real SQL
wire shapes: the paid original total stays 113 minor units after the catalog
price/tax change, and stock-impact revision 3 matches the pulled deficit.

Tests cover native Ed25519 verification, canonical encoding, signature domain
separation, scope/tender tampering, current authorization on replay, expiry,
lost responses, review separation, release proofs, CORS/body bounds, and
separation of user and service credentials, malformed receipt/stock metadata,
and recovery of a retained grant across trusted signing-key rotation. Run the SQL harness and shared
Flutter/Deno contract tests as documented in `VALIDATION.md` before deployment.
