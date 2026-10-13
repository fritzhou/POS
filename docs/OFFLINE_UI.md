# Explicit offline workspace

The offline page is a separate workspace. A network failure in the normal POS
does not turn an online checkout into a local sale. The page requires configured
trusted signing keys, verified device authorization, and a complete branch
snapshot before it offers local checkout. Preview mode supplies no products or
financial success records.

## Prepare and enter

While online, choose an authorized branch and open your own shift in the normal
POS. On the offline page, explicitly consent to keeping device enrollment keys
in secure storage, then select **Prepare offline access online**. This consent
does not enable the account's separate Remember me setting. A warm authenticated
session may enter its prepared workspace; restarting additionally requires the
same remembered verified account and independently verified retained grant.

Preparation does not enter offline mode. Select **Enter offline workspace**
explicitly. A resumed workspace receives the branch chosen from verified resume
descriptors; it does not silently enter a different branch or grant. A prepared
page reads its catalog, shift and receipts locally instead of asking the online
people repository for branch options. A pending online checkout, recovery
session, incomplete cache, missing device key, clock rollback, released grant,
or expired authorization blocks new local capture.

The page shows branch, grant expiry, snapshot observation, last successful sync,
queue counts and grant usage. Expiry display follows the coordinator's estimated
server time plus elapsed monotonic time; the coordinator rechecks its durable
clock anchor and current identity before a capture. Cached quantities remain
explicitly uncertain even when they permit a cart addition. The monetary and
event allowances are checked before opening the tender dialog.

## Local checkout and uncertainty

Search, category selection and exact barcode lookup use the prepared catalog.
The cart uses original signed prices and the grant's frozen currency and tax.
Discounts, customer changes, refunds, voids and shift changes remain online.
Cash needs counted-cash confirmation; digital payments need the operator's
confirmation and an actual provider or terminal reference. The page never
claims a provider API approved a payment.

Before opening tender entry, the page freezes one checkout UUID and original
cart. Each confirmed cash/manual tender is saved individually in immutable
journal fragments before the dialog displays it as saved. A separate,
distinct-domain device proof binds the exact evidence to its original grant.
Saved tenders cannot be removed. An uncertain write locks the original entry
and offers **Retry saving original payment**, preserving its amount/reference
and payment index. Cancel, back navigation, authentication interruption and
process restart preserve any evidence that reached durable storage; storage
failure remains explicitly uncertain.

Partial allocations restore the original order and show its saved amount.
**Continue remaining payment** permits only the unpaid remainder under valid
original authorization. Expired or locked authority permits review/export;
it cannot authorize another payment or replacement sale. A completed
allocation offers **Retry original local save** without collecting its saved
payments again. An interrupted proof can be recovered under valid original
authority. The complete-intent journal and atomic financial/outbox transaction
still enforce the original exact sale math and event-signature contract.

A receipt response must match the original event and branch before the page
clears the order. A lost response after successful local commit recovers the
same receipt, including after grant expiry. One immutable finalization seal,
verified against that committed event digest, closes the entire fragment set;
there is no crash-prone sequence of deleting or confirming individual payments.
Unresolved records block a different checkout and normal grant release, remain
available for authorized review/export, and preserve explicit locking.
[Partial tender recovery](PARTIAL_TENDER_RECOVERY.md) documents storage,
proof, retry and finalization boundaries.

The returned receipt is labelled **Provisional offline receipt**. Its immutable
local items, taxes and payment allocations remain visible separately from any
server receipt link. The page displays PENDING, SYNCING, SYNCED and FAILED
truthfully; server-linked stock deficits remain labelled as requiring
reconciliation.

## Synchronize, review and leave

Synchronization retries original signed events and downloads bounded changes
through the coordinator. Failed or unvalidated replies preserve the original
paid records. The page sanitizes unexpected exceptions and does not display raw
backend details. Already captured records may synchronize while a different
payment intent remains unresolved, but that unresolved intent blocks grant
release and new tender collection.

The Sync tab exposes failed or stock-conflicted records, authorized review and
copying of the original signed record. A bounded explicit retry never changes
the original financial event. Release is offered only after there are no
pending, failed or unresolved payment records; the server independently checks
the signed final sequence. Releasing the grant allows the cashier to return
online and close the shift. Leaving the page does not erase stored records.
Locking suspends device authorization and preserves receipts and payment
evidence.

## Validation

`flutter test test/offline_widgets` contains 25 widget tests covering disabled
configuration, explicit branch/device consent and entry, uncertain online
checkout, blocked authority, cache and shift labels, exact barcode/search,
provisional cash, manual digital verification, same-request local retries,
lost committed responses after expiry, restored payment intent, grant limits,
server-anchored display time, stale prepare responses after workspace changes,
malformed synchronization, reconciliation and original-record export. Cash,
manual payment and reconciliation/export paths are exercised at 320 logical
pixels without overflow. These are isolated fixture tests, not evidence of a
live Supabase deployment or physical Android/Windows hardware validation.

Phase 6C receipt output and keyboard input are described in [PHASE6C_CONTRACT.md](PHASE6C_CONTRACT.md). Verify bundled fonts with `python3 tool/verify_receipt_fonts.py`; setup performs this before frozen dependency resolution. PDF rendering has no runtime font download. Print/PDF actions preserve original records and recheck source, auth and lock generations before native handoff; output is an explicit plaintext customer copy managed by the OS, separate from encrypted business databases and reviewer proof. No physical completion or provider delivery is implied. Keyboard scanner capture starts disabled and pauses for forms, dialogs, locks and unavailable capture authority.
