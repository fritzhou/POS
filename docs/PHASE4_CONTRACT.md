# Phase 4 implementation contract

This design precedes implementation. Phase 4 adds explicit, bounded offline sale creation and authenticated synchronization. A configured signing key, deployed backend, verified enrollment, complete cached snapshot and previously opened online shift are prerequisites. Disconnected preview remains empty. No external payment provider is connected.

## Scope and invariants

- One grant authorizes `sale.created` only, for one verified actor/membership, organization, branch, enrolled device public key and already-open own server shift. Offline discounts, refunds, inventory administration and shift opening/closing remain online. A separate offline workspace exposes cached POS, provisional receipts and sync/reconciliation only.
- Enter offline explicitly. Never turn an unknown online checkout into an offline sale. Persisted uncertain online checkout requests block entry. Recovery, explicit logout, account changes, definite server permission denial and incomplete caches block entry. Grant-backed workspace resume is a device authorization, not password/PIN authentication; no new account signs in offline.
- Grants last at most eight hours, allow at most 1,000 sales and 100,000,000 minor units in total, and expire locally using server-time anchoring and a durable high-water checkpoint. Clock rollback fails closed. Software clocks/keys cannot prove secure offline time.
- Paid offline receipts, snapshots, event bytes/digests, authorization evidence and device signatures are immutable. Preserve them through logout, restart, grant expiry, migration and rejected synchronization. Store provisional receipt separately from a later server receipt link.
- Use the signed issuance-time catalog/settings snapshot to validate prices and tax; never reprice a paid sale from today's catalog. Snapshot includes no product costs or customer contacts. Grant snapshot is bounded to 1,000 saleable products; exceeding that bound refuses preparation explicitly.
- Ordinary online stock stays nonnegative. Verified offline sales that oversell may create a signed stock deficit through a source-backed trusted ingestion path, with an explicit reconciliation record. Positive physical receipts/returns may reduce a deficit. Ordinary clients cannot authorize negative stock with a session variable.
- Normal shift close is blocked while any unreleased offline grant could have unsubmitted sales, including expired grants. Sync then release a grant with a signed final sequence. A forced external close or other posting conflict preserves the original paid event for explicit review; do not silently alter old closures or discard the sale.

## Encoding and signatures

Keep existing `SyncEvent` schema version 1 and canonical SHA-256 unchanged. Lexically sorted object keys, preserved arrays, exact safe integers, JSON strings/booleans/null only. Serialize object entries directly in TypeScript so numeric-looking keys do not reorder. Preserve the exact Dart UTC observation string, including microseconds. Reject invalid Unicode and nonintegral/unsafe numbers at the network boundary.

Grant wire form: `{claims, signature}`. Claims contain `schema_version:1`, `issuer` (configured Supabase URL), `audience:'nexapos.offline.v1'`, `key_id`, `grant_id`, `organization_id`, `branch_id`, `device_id`, `actor_id`, `membership_id`, `role`, `business_name`, `allowed_actions:['sale.created']`, `issued_at`, `expires_at`, `shift_id`, `currency`, `tax_bps`, `settings_revision`, `snapshot_digest`, `max_events:1000`, `max_total_minor:100000000`. Sign UTF-8 `NexaPOS:grant:v1\n` plus canonical claims. Client trust comes from `OFFLINE_TRUSTED_KEYS_JSON`, never a key bundled with a response.

Device enrollment uses an authenticated server challenge with a UUID, random nonce, actor/org/device/public-key scope and expiry. Device signs `NexaPOS:enroll:v1\n` plus canonical challenge. Ed25519 raw public keys are 32 bytes, signatures 64 bytes, and all wire binary values use unpadded base64url. Device private seed belongs exclusively to `SecretStore`.

New local authorized sales preserve the existing SaleDraft event payload. Detached immutable authorization is `{grant_id, sequence, payment_evidence}`; payment evidence keys original local payment IDs and includes cash `tendered_minor` or digital `manual_confirmed:true` plus reference already in the sale snapshot. Device signs `NexaPOS:event:v1\n` plus canonical `{event_digest, grant_id, sequence, payment_evidence}`. Store proof when creating the local sale, not when uploading it. Legacy events without a genuine envelope remain untouched and excluded from upload.

Grant release proof signs `NexaPOS:release:v1\n` plus canonical `{grant_id, final_sequence}`. The server releases only when every sequence through that final value has a recorded accepted/review outcome. Exact duplicate release is idempotent; later new events are denied.

## Backend protocol

One `offline-sync` Edge Function verifies bearer JWT via Auth `/user` and public-key proofs, then uses service-only RPCs. SQL independently rechecks current verified actor/membership/branch/device, retained grant/snapshot, sequence, payload invariants and replay content. No signing/private service credential enters Flutter.

JSON actions: `enroll_challenge`, `enroll`, `prepare`, `ingest`, `pull`, `release`. Common caller inputs include `organization_id`, `branch_id`, `device_id`; actor always comes from verified Auth. `prepare` returns `{grant, snapshot, server_time}`. Snapshot contains `context`, `shift`, `products`, `categories`, `stock`, and `cursor`; its canonical SHA-256 is signed in the grant. Ingest receives `{event, digest, authorization, signature}`. Authorization includes grant identity/sequence/evidence; SQL registry supplies retained grant claims and snapshot.

Suggested SQL boundary names: authenticated `prepare_offline_device_challenge`; service-only `complete_offline_device_enrollment`, `prepare_offline_grant`, `finalize_offline_grant`, `get_offline_verification_context`, `ingest_offline_event`, `pull_offline_changes`, `release_offline_grant`. Service-only calls accept `p_actor_id` derived by Edge from Auth, and explicit scope; normal authenticated/anon roles cannot execute them.

Accepted response echoes `status:'accepted'`, organization/branch/actor/device/grant/sequence/event ID/digest/document ID, `server_receipt_id`, `accepted_at`, immutable `receipt`, `stock_impacts:[{product_id, revision}]`, and optional `reconciliation_code`. Validate every identity before constructing `ServerAcceptance`. Review/conflict responses do not become financial acceptance. Same event ID plus changed event/evidence conflicts; identical retry returns original acceptance even after prices change or grant expiry, subject to current authority/device checks.

New ingestion requires observation within grant lifetime, an ingestion grace bound of 72 hours after expiry, sequential grant event numbers, exact original-snapshot financial math and manual tender evidence. Expiry blocks new local sales; an already captured event can be ingested during the bounded grace. Software timestamps are not tamper-proof: limits, current authority and server review bound this trust.

Pull changes are bounded, actor/device/branch scoped and cost-free. Return `{cursor, has_more, server_time, changes:[{kind,id,revision,deleted,value}]}` with explicit tombstones. Sequence allocation uses a transaction-held organization counter lock, not a naive bigserial that can skip late commits. Snapshot/pull cursor consistency must use the same lock. Stock movements advance authoritative product stock revision; acknowledgments expose it.

## Local database and runtime interfaces

Drift schema v2 is additive: authorization envelopes, actor/device public cache records/state, append-only stock effects and acceptance links/stock revisions. Preserve all schema v1 financial rows, event bytes/digests, pending/failed records, attempts and leases. Scope new caches by organization/branch/actor/device, and never invent zero as a hidden cost.

Atomically persist sale/items/payments/event + signed authorization + sequence + local negative stock effect. Local available stock uses frozen/recent server observation plus every unabsorbed local delta. A synchronized delta remains applied until a pulled stock revision includes its accepted impact, preventing transient stock restoration after acknowledgment. Failed/unknown paid events keep their effects and remain visible.

Storage owns `OfflineAuthorization`, `OfflineCacheChange/Batch`, authorized queue claims/reads, immutable acceptance links and projected quantity. Crypto owns `DeviceIdentity`, `OfflineGrant`, signature verifier/signer, secure checkpoint and protocol envelope. Coordinator owns preparation, explicit entry, scoped cached reads, atomic local checkout, bounded sync/leases, pull and release. UI owns separate offline page and explicit entry controls; online `CheckoutRepository` semantics remain unchanged.

Local crypto public interfaces are in `lib/core/offline/`; storage interfaces in `lib/core/database/offline_storage.dart`; coordinator interface in `lib/features/offline/domain/offline_workspace.dart`. Agents coordinate exact typed signatures directly before dependent edits. Main/app/shell composition belongs to root. No automatic background acceptance or fabricated fixtures in application code.
