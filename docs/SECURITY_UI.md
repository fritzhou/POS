# Security management UI

`SecurityPage` loads current organization policy and a verified branch-scoped
inventory through `SecurityRepository`. Production uses
`SupabaseSecurityRepository`, the verified membership actor, the actor-scoped
operation journal, and the recovery/access-lock guard. A design preview makes
no security requests and supplies no device, grant or notification records.

The page has four views: policy and account, enrolled offline devices, offline
grants, and security notices. Optional account sections are supplied by the
composition root. Branch labels come from the authorized branch repository;
when those labels cannot load, actual authorized IDs remain available. A page
loads at most 20 displayed records and overfetches one additional validated
record. All rows, including the overfetched record, must match the selected
organization and branch before any of the page is shown.

## Authority and changes

Owners and admins can request device rename, permanent offline-device
revocation, security-policy changes, and eligible lost-key grant reviews.
Server `can_manage` and `can_review` capabilities additionally control displayed
actions. PostgreSQL rechecks current membership, complete affected device
branch scope, role hierarchy, and required MFA for every mutation and replay.
Other current roles see only the server-authorized device/grant inventory and
notices. The UI never selects or elevates a role.

Administrative changes require an audit reason and a stable UUID. The exact
request is saved before dispatch, and its attempt is saved before every RPC.
Success is shown only after the canonical returned entity matches the request.
Lost, malformed or ambiguous responses retain the original request for retry
and restart recovery. A later denial cannot establish that an earlier uncertain
attempt rolled back. Durable storage must be present before a management
mutation can be sent. While an unconfirmed request is visible, further changes
are paused so its outcome can be resolved explicitly.

A first definitive SQL rollback can reject an uncommitted request. Policy and
grant reviews use server revision/paid-outcome comparisons; stale state must be
reloaded before a new confirmation. A dialog retains the displayed source
snapshot and is discarded if its membership/repository changes before the
operator confirms. Access denial clears displayed security records.

## Lost-key review and notices

Review requires an expired signed grant on a revoked device, owner/admin
authority, a reason, explicit acknowledgement of unknown paid events, and the
displayed sequence, outcome count and total. The dialog shows both known paid
outcomes and the remaining signed financial exposure. The server rejects the
request if those known outcomes changed before confirmation.

Administrative resolution removes the normal shift-close barrier without
creating a final device signature. It does not prove payment recovery, erase
local evidence, or turn later signed paid proof into an ordinary accepted sale.
The UI keeps the unresolved exposure visible and directs the operator to retain
recovered receipts and signed exports for reconciliation.

After administrative resolution, original paid proofs may be recovered with
missing earlier sequences. The server retains unique proofs within the original
event and total limits for review; a missing sequence must not prevent the next
recoverable paid event from being preserved. The displayed highest observed
sequence is distinct from the actual outcome count. Remaining event exposure
uses the authorized event limit minus that count, so a gap cannot conceal
unknown payments. Unresolved grants still require contiguous sequences.

Device inventory represents verified offline-key enrollment, not every Supabase
Auth session. Last upload is derived from recorded paid-event outcomes.
Revocation cannot reach an already disconnected device immediately, and does
not itself revoke every Auth session. Security notices project persisted server
audit events; they do not claim email delivery or full login telemetry. Read
acknowledgements affect only the currently authorized reader.

## Validation

The focused repository and widget tests exercise tenant/branch rejection,
strict wire decoding, missing/recovery/replaced identities, durable lost-response
replay, uncertain-attempt preservation, first definitive rollback, paid-summary
review binding, risk acknowledgement, revocation access clearing, scope changes
while a dialog is open, and 320-pixel layouts. These tests use isolated fixtures
and an in-memory native journal. The Dart decoder also consumes
`test/fixtures/security_sql_contract.json`, actual security RPC projections from
the isolated mock-Auth PostgreSQL suite, preserving administrative resolution,
unknown exposure, later paid-review outcomes and source audit notifications.
Live Supabase/PostgREST, native secure storage,
and physical device acceptance still require deployment and platform validation.
