# Authorized offline checkout and durable synchronization

Phase 4 implements a separate, explicitly selected device workspace. It requires
an online-opened own shift, current verified membership, proof-of-possession
enrollment, an independently pinned server key, a signed grant and a complete
cost-free catalog/settings snapshot. Missing configuration leaves this feature
**Not Yet Connected**. The read-only preview remains empty.

The implementation contract is [PHASE4_CONTRACT.md](PHASE4_CONTRACT.md).
Deployment instructions are [OFFLINE_BACKEND.md](OFFLINE_BACKEND.md); operator
behavior is [OFFLINE_UI.md](OFFLINE_UI.md). Local tests do not establish a live
Supabase deployment, platform vault behavior or provider payment success.

## Authorization and scope

Each signed grant binds actor, membership/role, organization, branch, device,
already-open shift, currency, tax and issuance-time snapshot. It permits only
`sale.created`, for at most eight hours, 1,000 events and 100,000,000 minor units.
Snapshot preparation refuses more than 1,000 saleable products. Products include
no costs; snapshots include no customer contacts. Whole-unit quantities and the
existing two-decimal currency rules apply.

A remembered verified identity can explicitly resume the same stored grant
workspace. This is distinct from a new password/PIN sign-in and from loading a
fresh server membership into the online shell. Recovery, explicit logout, known
server denial, wrong identity/scope, incomplete cache, an untrusted signature,
missing secure key or clock rollback prohibit new offline capture. Expiry
prohibits new sales; preserved receipts and payment evidence remain available
for review. Normal online checkout never falls back automatically.

Private Ed25519 seeds remain exclusively in OS `SecretStore`. Signed public
grants and durable server-time/high-water checkpoints survive restart. Software
keys and clocks do not provide hardware attestation or tamper-proof offline
time. Immediate remote revocation while disconnected is impossible; current
server authority is checked on every ingestion, including accepted replay.

Offline discounts, refunds, inventory administration, employee/security changes,
shift opening and shift closing remain online. Any uncertain online checkout
blocks offline entry until its original request is reconciled.

## Financial capture and recovery

After the operator confirms the complete tender, preserve the request UUID,
frozen cart and payment evidence in the separate native operation journal before
rechecking expiry or attempting local capture. Unknown outcomes retain that
same intent, with no second physical payment. Preparation also journals its
stable request UUID so a lost response cannot create another grant.

Authorized capture atomically writes immutable sale/items/payments, unchanged
v1 event/digest, detached authorization, device signature, grant sequence and
negative local stock effects. Receipt identity is provisional; accepted cloud
receipt links are separate append-only records. Never reprice a paid sale from
a later catalog. Unknown/failed/review outcomes preserve the original financial
record and stock effect.

Phase 5 durably appends every operator-confirmed partial tender before display,
then retains its separate scoped proof and a final committed-event seal. Closing
the dialog or restarting preserves the original checkout and remaining amount.
Expiry/key loss preserves review/export evidence rather than inventing a receipt;
unfinalizable fragments require explicit authorized review. See
[PARTIAL_TENDER_RECOVERY.md](PARTIAL_TENDER_RECOVERY.md). Printing and provider
capture/refunds remain later work.

## Storage and migration

`AppDatabase.openNative(scope: ...)` retains the existing organization/branch
hashed SQLite file. Schema v2 is additive: immutable event authorization,
actor/device-scoped public cache/preparation records, stock effects, acceptance
links/revisions and grant releases. All v1 rows, exact event strings/digests,
financial triggers, statuses, attempts and leases remain unchanged. An existing
legacy event cannot acquire a synthetic authorization envelope or be uploaded
through the authorized queue.

Caches and new receipt reads require organization/branch/actor/device scope.
Public signed grants may be retained in the database; private seeds, passwords,
PIN verifiers and Auth tokens never belong there. Phase 5 native factories use
genuine SQLCipher and per-file OS-vault keys, with encrypted legacy recovery.
Database keys survive logout to preserve paid records; they grant no business
authority. See [LOCAL_SECURITY.md](LOCAL_SECURITY.md) for migration and physical
platform/key-recovery gates.

The native operation journal also retains online checkout/stock/shift requests.
An intent digest is local retry integrity, not financial acceptance or grant
provenance. A later permission/stock failure cannot establish that an earlier
unknown online attempt rolled back. Keep its original UUID and full input.

## Synchronization and stock

The coordinator explicitly synchronizes at most 100 eligible events per run,
using scoped leases and existing bounded exponential retry/backoff. Stale
workers cannot acknowledge another lease. It sends original event bytes/digest,
detached evidence and the signature captured at payment time. Legacy unsigned
events remain untouched and excluded.

Edge verifies the current bearer identity, configured grant signature and device
proof, then calls service-only SQL. SQL rechecks current membership/branch/device,
retained claims/snapshot, sequence, time bounds, exact financial calculations and
manual evidence. New captured events have a 72-hour ingestion grace after grant
expiry. Exact accepted replay returns its original result subject to current
authority; changed content conflicts. Failed proofs/review outcomes never become
financial acceptance.

The client validates every acceptance identity, immutable original receipt
amount/item/payment and complete product impact revisions before constructing a
`ServerAcceptance`. A lost/malformed response leaves the original event pending
or visibly failed; connectivity alone never marks it synced.

Observed stock is cached server quantity plus all unabsorbed local effects.
Even after acceptance, a local effect remains until a pulled authoritative
**stock revision** includes that impact. Feed cursors and stock revisions are
separate values. Catalog/stock pulls commit bounded revisions/tombstones and
cursor atomically. Server cursor allocation uses an organization lock held
through commit so a later transaction cannot hide an earlier uncommitted change.

Ordinary online checkout refuses insufficient stock. Only verified source-backed
offline posting can create a deficit; its original paid sale and reconciliation
code remain visible. Physical positive receipts/returns can reduce a deficit.
Resolving operational deficits is explicit review, not a last-write-wins edit.

## Shift release and lost keys

An unreleased grant blocks normal shift closing even after grant expiry. Sync
all sequences, then release with a device proof of the final sequence. Released
grants cannot capture new sales. A forced external closure produces a review
outcome rather than rewriting a closed drawer.

Logout/denial removes signing authority while preserving original public grants,
receipts and signed events. After the same actor signs in online, retained
signatures can be inspected/exported/uploaded without resigning. A lost private
key cannot sign a final release. Phase 5 provides an audited Owner/Admin review
for a revoked device and expired grant, recording known paid outcomes and maximum
unknown exposure. Late original signatures remain reviewable; no device release
proof is fabricated. Never delete pending records or silently remove a barrier.
See [SECURITY_BACKEND.md](SECURITY_BACKEND.md).

## Validation

```sh
source tool/dev_env.sh
dart run build_runner build
flutter test --no-pub test/database test/offline_crypto test/offline_workspace test/offline_widgets
deno check supabase/functions/offline-sync/index.ts
deno test --allow-read=test/fixtures test/functions
bash test/sql/run.sh nexapos-postgres-test
```

The SQL harness requires its inspected isolated test container; never point it at
a user database or deploy its mock Auth fixtures. See [VALIDATION.md](VALIDATION.md)
for final actual counts, concurrency outcomes and unrun platform/live checks.
