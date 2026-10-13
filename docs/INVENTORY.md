# Stock, sales and shifts

Phase 3 provides online transaction workflows that require the PostgreSQL migrations to be deployed to a configured Supabase project. This workspace has no live deployment or business credentials. The app requires a verified business membership and reads only authorized server branches. The design preview makes no repository requests and contains no products, balances, transactions or shifts.

## Stock operations

Inventory shows branch balances and a paginated, read-only movement ledger. Product search runs on the server. Selecting **View ledger** filters by the actual product identifier; clearing the filter returns to the authorized branch ledger.

Owners, Admins, Managers and Inventory Staff can receive physical stock. The current form records one product per stock receipt, with a whole-unit quantity, optional supplier, delivery reference, reason and explicit confirmation that the merchandise entered this branch. Product and supplier searches return up to 50 records; refine the search to find another record. The request carries the selected product revision so a changed product must be reloaded before receiving.

Optional receiving cost is private document evidence in the selected product's currency. The server snapshots that currency and revision with the cost; a concurrent product currency change rejects the stale revision. Receiving does not overwrite the catalog cost or calculate an accounting valuation.

Owners, Admins and Managers can append a signed adjustment after a physical count. A negative change removes units; a positive change adds units. The form requires a reason and confirmation of the discrepancy. The server locks the current branch balance and rejects an adjustment that would make it negative. Staff cannot edit a balance or ledger row directly.

Quantities are whole units, at most 1,000,000 units per line or adjustment. Purchase orders, purchasing payments, stock transfers, fractional units and camera scanning remain **Coming Soon**.

## Sales and receipt history

Sales history loads bounded pages from the selected authorized branch. Cashiers read their own sales; Owners, Admins and Managers read the branch scope permitted by the server. Inventory Staff cannot read sales. Receipt details use the committed seller, branch, product and price snapshots rather than the current catalog. Original totals remain visible after a reversal. Noncash records show **Manual Verification** and the recorded reference; the app does not claim card or wallet authorization.

Owners, Admins and Managers can select any whole-unit quantity from each remaining receipt item, or void every unit of an untouched sale. Entering zero skips an item. This creates a compensating transaction while preserving the original receipt, items and payments. An active shift belonging to the actor in the sale's original branch is required. The operator provides a meaningful reason, confirms that the allocated payouts were made manually, and supplies a reversal reference only for each allocated noncash payment. The app does not initiate a provider reversal.

The refund uses each immutable original tax-inclusive line total. For a line total `T`, original quantity `Q`, previously returned quantity `U` and newly selected quantity `N`, its amount is `div(T × (U + N), Q) − div(T × U, Q)`. Exact integer arithmetic preserves the final remaining cents without re-pricing the item or re-applying current tax settings. The interface shows the selected total and allocates it to original payment sources in stable original payment ID order, bounded by each source's remaining amount. A fully discounted selected line can return units with no payment allocation or manual payout confirmation.

The physical return checkbox starts unchecked. An unchecked request records financial compensation without increasing stock. Checking it confirms that every selected unit physically returned to the original branch, and the server appends the corresponding source-backed stock movement. Printing, PDF export and receipt sharing remain **Coming Soon**.

## Cash shifts

Owners, Admins, Managers and Cashiers can open their own shift with a counted opening float. The request includes the expected currency, preventing a concurrent business currency change from reinterpreting the amount. Only one open shift is allowed for each actor in an organization, across all branches.

Closing requires a nonnegative counted amount, a closing note and physical-count confirmation. Cashiers close their own shifts. Owners, Admins and Managers may close another authorized branch shift. The server computes expected cash from opening cash, committed cash sales and recorded cash reversal payouts, then computes the counted difference. The interface displays these server values, including signed shortages or excesses.

Expected cash can be negative when recorded cash payouts exceed the drawer's opening float and cash sales. The interface highlights this deficit and still requires the actual nonnegative physical count. It does not invent cash availability or replace the expected value with zero.

## Unconfirmed requests

Each mutation freezes a UUID and complete payload after confirmation. The repository writes an actor- and business-scoped durable journal entry before contacting the server. A lost response keeps the entry pending. The form disables edits and offers **Retry same request**; closing the dialog retains the pending intent.

Saved pending requests are restored after restart and shown before new mutations are enabled. **Retry saved request** reuses the exact persisted payload and UUID. The server returns the original committed result if it already exists. The operator must not repeat the physical payout, stock receipt or cash count when retrying a server request.

The journal is online reconciliation, not offline transaction authority. No background worker submits it automatically. Revoked access after an earlier unknown result can leave the request unresolved; the interface keeps it pending until its original server result can be established.

## Validation

`test/operations_widgets/operations_pages_test.dart` covers preview and role denial before reads, bounded queries, 320-pixel layouts, immutable receipts, partial taxed and discounted refunds, final-cent allocation, original payment caps, zero-value selected units, explicit stock-return decisions, exact money, physical-count confirmation, server-confirmed success, frozen retry identifiers and persisted uncertain requests. Pure refund calculations also have independent tests under `test/checkout_review`. Backend transaction and security assertions live separately under `test/sql`.

Live business data, email, receipts and device behavior require a configured Supabase project with the migrations deployed. The isolated tests use fixtures and local PostgreSQL; their results do not confirm a live deployment.

Phase 6B opens transfers and supplier returns from Inventory. Dispatch depletes only the source; partial physical receipt adds only counted destination goods; transit return adds only physically returned source goods. Supplier returns deplete against original purchase receipt quantities/costs. All writers share the authoritative movement ledger, stock revisions and feed counter. Unknown responses retain encrypted original intent and UUID; retry does not repeat goods movement. Read [PHASE6B_CONTRACT.md](PHASE6B_CONTRACT.md).
