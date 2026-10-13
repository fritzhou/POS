# Online checkout, shifts and stock

Phase 3 supplies online repository contracts and Supabase RPC adapters for actual product lookup, checkout, receipts, shifts, stock receiving and adjustments, and compensating sale reversals. A verified Supabase session and an authorized business/branch are required. These paths do not grant offline permission and do not write an accepted sale into the Phase 1 local outbox.

The app has no deployed Supabase project credentials in this workspace. SQL and Dart validation exercise isolated test data; they do not establish live email delivery, payment authorization or a production checkout.

## Monetary and quantity contract

Prices exclude tax. Amounts use integer minor units, with two decimal places for PHP, USD, EUR, GBP, AUD, CAD and SGD. Checkout rejects other currencies rather than interpreting an unsupported precision. Quantities are whole units from 1 to 1,000,000 per line; fractional units remain follow-up work. Each request supports at most 100 unique products and five payment records. Amounts and stock balances cannot exceed 9,007,199,254,740,991.

`CartTotals.calculate` uses `BigInt` intermediates. It orders product UUIDs after case normalization, computes each price × quantity subtotal, and allocates a cart discount using cumulative exact proportions:

```
line_discount = floor(discount × cumulative_subtotal / subtotal)
              - floor(discount × preceding_subtotal / subtotal)
line_tax      = floor(((line_subtotal - line_discount) × tax_bps + 5000) / 10000)
line_total    = line_subtotal - line_discount + line_tax
```

This preserves every discount cent and prevents a tiny final line from receiving an excessive rounding remainder. Tax rounds half-up independently for each discounted line. The backend uses exact integer numeric division for allocation and refund proportions; ordinary PostgreSQL numeric division can round before `floor` near the maximum amount. Zero-total checkout is explicitly unsupported in this phase. Zero-value returns of a fully discounted individual line are allowed without payment reversal records.

The server loads current product prices and checks every expected product revision, the expected business settings revision, currency, current actor/branch permissions, current open shift and stock. It computes the accepted totals itself. A client estimate never creates a financial receipt.

## Payments and shifts

Cash requires the counted amount received to cover the amount applied. Change is counted tender minus the applied cash amount. Card, GCash, Maya and Other require an operator confirmation and a reference of 3–120 characters. These are manual payment records; no field or response claims authorization by a payment provider.

Opening a shift supplies the expected currency from the branch POS context, preventing changed settings from reinterpreting counted cash. Closing records actual counted cash and a reason. Expected cash comes from opening cash plus applied cash sales, minus cash reversals recorded in that shift. Returned receipts and shift closures are server-confirmed records. Expected cash can be negative when historical cash sales are refunded in a later shift; the client preserves the signed value.

## Durable uncertain requests

Construct each `CheckoutRequest`, `OpenShiftRequest`, `CloseShiftRequest`, `ReceiveStockRequest`, `AdjustStockRequest` or `ReversalRequest` once when the operator confirms it. Its UUID and immutable input lists remain stable across retries. The shared `OperationJournal` stores canonical RPC parameters before sending them, scoped by business, actor and branch. It stores no session tokens. An outstanding intent is neither a receipt nor evidence that the server rolled back.

The journal increments an attempt counter durably before every RPC. Only a definitive SQL rollback on attempt one can terminally reject an intent. A later replay may be denied after the original operation committed and its response was lost, so later errors keep the original request pending. A malformed 200 response, a wrong request ID, changed identity, connection loss or timeout also leaves it pending. The app must preserve the request and reconcile it; it must not silently issue a fresh UUID.

`pendingCheckout` restores an unresolved cart request without manufacturing product names or cloud confirmation. `findSaleByRequest` queries the original request identity, and confirms the journal only after receiving an actual matching receipt. `pendingOperations` and `retryPending` support the same recovery for shifts, stock and reversals. Retrying a confirmed request still asks the backend to check current authority, while leaving its immutable journal history intact even if the returned receipt now includes newer reversal summaries.

A revoked actor may be unable to reconcile an earlier request. That uncertainty remains visible and requires an authorized manager's server-side review; deleting the local journal or marking a denial as proof of original rollback is unsafe.

## Stock and reversals

Inventory derives from append-only movements. Receiving records positive whole units and optional private unit-cost evidence; it does not overwrite catalog prices or costs. Signed adjustments are nonzero and bounded to 1,000,000 units in either direction. The server rejects stock changes that would produce negative balances. Inactive products remain visible in inventory so existing stock does not disappear from administrative views; POS lookup uses saleable products only.

Owner, Admin and Manager accounts can record refunds or voids within their branch scope, with a meaningful reason and their own current open payout shift. A void requires an untouched complete original sale. Refunds are bounded by each original item's remaining quantity and original payment's remaining amount. Cumulative integer proportions release the final rounding cent on the last returned unit. Original sales, payment records and stock movements remain immutable; reversals append compensating documents.

Partial selection uses the immutable original tax-inclusive line amount `T`, original quantity `Q`, prior returned quantity `U` and newly selected quantity `N`: `div(T × (U + N), Q) − div(T × U, Q)`. It does not re-price the product or apply today's tax. The interface allocates that exact payout to original payment sources in stable UUID order without exceeding their remaining amounts. A selection change clears both payout and physical-return confirmations.

Every actual payout needs manual confirmation against an original payment source. Restocking is a separate explicit `returnStock` choice, defaulting to false in presentation; choose it only when goods physically return to inventory. The server cannot establish that a bank/provider reversed funds or that physical goods arrived. Cashier PIN approval, terminal/provider integrations, receipt printing remain follow-up work. Phase 4 adds separate bounded signed offline sales; offline discounts/refunds/shift administration remain unavailable. See [OFFLINE.md](OFFLINE.md).

## Checks

Run `flutter test test/checkout_domain test/checkout_repositories test/checkout_review` after sourcing `tool/dev_env.sh`. These tests cover integer rounding and boundaries, canonical UUID handling, stable payloads, actual SDK request serialization, sanitized failures, receipt identity, durable uncertainty, first rollback versus replay denial, session changes, barcode equality, stock operations and signed shift summaries. The SQL harness separately checks transaction rollback, concurrent idempotency and current backend authorization against an isolated test PostgreSQL database.

Phase 6C receipt output and keyboard input are described in [PHASE6C_CONTRACT.md](PHASE6C_CONTRACT.md). Verify bundled fonts with `python3 tool/verify_receipt_fonts.py`; setup performs this before frozen dependency resolution. PDF rendering has no runtime font download. Print/PDF actions preserve original records and recheck source, auth and lock generations before native handoff; output is an explicit plaintext customer copy managed by the OS, separate from encrypted business databases and reviewer proof. No physical completion or provider delivery is implied. Keyboard scanner capture starts disabled and pauses for forms, dialogs, locks and unavailable capture authority.
