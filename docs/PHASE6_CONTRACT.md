# Phase 6A contract — purchases, expenses and operational reports

Status: **Implemented and locally validated.** Phase 6A implements the daily-operations slice selected by the user. The preceding Phase 5 checkpoint passed 544 Flutter tests, 80 Deno tests and 749 PostgreSQL assertions. Final Phase 6 checks passed 748 Flutter tests, 80 Deno tests and 1,097 PostgreSQL assertions, plus 200 concurrent report snapshot checks. [VALIDATION.md](VALIDATION.md) records evidence and outstanding live/platform acceptance.

## Scope and existing foundations

Implement connected, server-authoritative purchase orders, partial receiving, cancellation of unreceived quantities, recorded business expenses with full compensating reversal, and sales/inventory/expense reports. Normal connected workflows use the currently verified actor and assigned branch. They do not enter offline mode automatically.

Existing foundations to preserve:

- `receive_stock` already writes immutable `inventory_operations`, `stock_movements` and private `inventory_cost_evidence`. The stock projection increments `stock_revision` and appends a transaction-held organization change-feed revision. Purchase receiving must use these same tables/triggers, not another stock source.
- `private.phase3_request` / `phase3_save_request` serialize an organization/actor/request UUID and reject changed kinds/payloads. Flutter `OperationExecutor` writes a durable immutable request before dispatch, marks every attempt, and preserves transport/malformed-response uncertainty. Later replay denial cannot erase an earlier uncertain financial success.
- `private.require_active_member` checks verified current membership and configured Owner/Admin MFA. `phase3_require` additionally validates active branch/current assignments and role. New functions must use this chain, including before an idempotent replay returns its old document.
- Existing accepted sale/reversal history, shift closures, trusted offline deficit provenance, device revocation, signed grants, release/administrative-review barriers and local paid-fragment recovery remain authoritative. Reports exclude unposted provisional records and never invent synchronization or provider success.

Phase 6A does not add supplier payments/accounts payable, purchase tax/freight, purchase returns, draft editing, approval delegation, fractional stock, transfers, inventory valuation/COGS/profit, physical printing, email delivery, or provider payment APIs.

**Approved expense sources:** externally funded/manual payments by default, plus explicit cash payouts from the current actor’s own open same-branch/currency POS shift. Drawer effects are derived from immutable expense/reversal entries; an existing closed shift and its count can never be rewritten. Cashier expense authoring remains denied.

## Common wire and transaction rules

RPC inputs use `p_organization_id` plus an explicit `p_branch_id`. Mutation inputs include `p_request_id`; actor, membership, role, timestamps and audit author always come from the verified server context. Unsupported JSON keys are rejected. UUIDs are normalized; money and whole quantities are JSON integers, never strings/floats.

Amounts use existing supported two-decimal currencies (`PHP`, `USD`, `EUR`, `GBP`, `AUD`, `CAD`, `SGD`). Individual and aggregated money/quantity outputs must remain within exact integer bounds, absolute value at most `9,007,199,254,740,991`. Calculate multiplication/sums in PostgreSQL `numeric` and Dart `BigInt`, validate before casting. An over-limit report fails with a useful narrower-range error instead of rounding or emitting unsafe numbers. A purchase may have a zero recorded cost; an expense must be positive. Quantities are whole units `1..1,000,000`; mutation lines are unique and limited to 100.

All history and idempotency mappings are append-only. New public tables enable RLS and reject UPDATE/DELETE/TRUNCATE. Ordinary clients receive no direct mutation grants. Private projections may change only inside validated server transactions and must be rebuildable from immutable documents. Private cost/request/projection tables receive no authenticated/service direct access. RPCs are fixed-empty-search-path definers with explicit authenticated execution grants; no anonymous execute or arbitrary actor parameter.

Lock order for purchase stock writers is organization offline-feed counter, actor/request advisory lock, order state, supplier, then every product in sorted UUID order before the first movement. Existing stock/shift/counter lock order must remain intact. Requests replay only after current authorization succeeds; a replay recovers the original immutable action document. Current derived order status is fetched separately through the order read RPC.

New operational audit actions are `purchase.created`, `purchase.received`, `purchase.remaining_cancelled`, `expense.recorded`, and `expense.reversed`. Audit contains scope, immutable document IDs, amount/currency or item counts and a meaningful reason; it contains no token, PIN or provider secret. Extend operational audit visibility additively while preserving complete employee/security branch-snapshot rules.

## Purchase documents and states

A submitted purchase order is immutable immediately. The create form is unpaid, in-memory work until submission; there is no persisted editable draft or implied vendor transmission. The confirmation says that it records an order and does not pay or email the supplier.

Suggested additive tables:

| Table | Required fields and constraints |
| --- | --- |
| `public.purchase_orders` | `id`, `organization_id`, `branch_id`, `supplier_id`, `supplier_name` snapshot, `supplier_revision`, `currency`, `settings_revision`, `created_by`, `created_at`, `reference` nullable <=120, `reason` trimmed 3..1000, `ordered_total_minor`; tenant/branch composite FKs |
| `public.purchase_order_items` | `id`, organization/branch/order IDs, `product_id`, original `product_name`, `sku`, `unit`, `product_revision`, `ordered_quantity`, `unit_cost_minor`, `line_cost_minor`; unique order/product, exact line cost, tenant/order/product FKs |
| `public.purchase_receipts` | `id`, organization/branch/order IDs, accepted `order_revision`, unique `operation_id` linked to the existing scoped `inventory_operations`, `received_by`, `received_at`, order currency, `received_total_minor`, `reference`, `reason` |
| `public.purchase_receipt_items` | `id`, scoped receipt/order/item/product IDs, `quantity`, fixed original `unit_cost_minor`, `line_cost_minor`, accepted current `product_revision`, unique `movement_id` linked to the existing stock ledger; unique receipt/order item |
| `public.purchase_order_cancellations` | `id`, organization/branch/order IDs (one cancellation per order), accepted `order_revision`, `actor_user_id`, `created_at`, reason and immutable canceled-quantity/item-cost snapshots |
| `private.purchase_order_states` | order ID, monotonically increasing `revision`, derived received/closed state; no client grants |
| `private.purchase_order_item_balances` | order-item ID and received quantity, constrained between zero and ordered quantity; rebuildable from receipt items |

Derived statuses are `ordered`, `partially_received`, `received`, `cancelled`. A cancellation after a partial receipt closes only the outstanding quantities; UI labels it **Remaining quantities cancelled** and still shows all received quantities/receipts. `cancelled_quantity` is frozen in the cancellation document. For every item, `remaining_quantity = ordered_quantity - received_quantity - cancelled_quantity` and may never be negative. Fully received orders cannot be cancelled. Closed orders cannot receive additional stock. Ordered cost and quantity never change when receipts/cancellation advance the projection revision.

Create validates an active same-tenant supplier whose scope is shared or matches the selected branch, the expected supplier revision, current organization settings/currency and active current product revisions. Selected costs are explicit operator-recorded procurement costs, not provider quotes or mutable product-cost changes.

Receiving validates the current order revision and every requested quantity against the remaining order item while holding the state lock. Only original order items may be received, at the original unit cost/currency. All products and the supplier must still be valid in the tenant/branch; expected current product revisions are supplied separately from the original order snapshot. Products whose catalog currency later changed may still receive an original-currency order when the operator has reviewed the current revision: physical stock has no currency, and cost evidence uses the order's original currency. Catalog cost is never overwritten.

One receiving transaction appends its purchase receipt/items, existing `inventory_operations(kind='receive')`, stock movements/private cost evidence, order projection changes, actor/request result and audit. It must commit all or none. Positive receiving may reduce an existing trusted offline deficit; it must not grant an untrusted negative-stock bypass. The existing stock trigger emits authoritative revisioned changes for offline pull.

Do not invoke `receive_stock` using the purchase-receipt request UUID and then save that UUID again under `purchase.receive`: the existing request key would conflict. Reuse the stock ledger/posting primitives inside the new purchase RPC, or extract a private shared primitive without a second public request mapping. Existing ad hoc receiving continues to work independently.

### Purchase RPCs

Read paging follows the existing convention: RPC `p_offset` 0..1,000,000, `p_limit` 1..101; the shared Flutter `PageRequest` conservatively limits client offsets to 100,000 and page sizes to 100. Flutter requests `page.limit + 1` for `DataPage`. Ordering is stable (`created_at DESC, id` for documents; item product UUID for detail).

```text
get_purchase_context(p_organization_id, p_branch_id)
  -> {organization_id, branch_id, branch_name, currency, settings_revision}

list_purchase_orders(p_organization_id, p_branch_id,
  p_status=null, p_query='', p_offset=0, p_limit=51)
  -> [PurchaseOrderSummary]

get_purchase_order(p_organization_id, p_branch_id, p_order_id)
  -> PurchaseOrder

list_purchase_receipts(p_organization_id, p_branch_id, p_order_id,
  p_offset=0, p_limit=51)
  -> [PurchaseReceiptSummary]

get_purchase_receipt(p_organization_id, p_branch_id, p_receipt_id)
  -> PurchaseReceipt

create_purchase_order(p_organization_id, p_branch_id, p_request_id,
  p_supplier_id, p_expected_supplier_revision, p_expected_settings_revision,
  p_currency, p_items, p_reference=null, p_reason)
  p_items = [{product_id, expected_revision, quantity, unit_cost_minor}]
  -> {request_id, kind:'purchase.create', order_id, order_revision:1,
      order:PurchaseOrderCreation}

receive_purchase_order(p_organization_id, p_branch_id, p_request_id,
  p_order_id, p_expected_revision, p_items, p_reference=null, p_reason)
  p_items = [{order_item_id, quantity, expected_product_revision}]
  -> {request_id, kind:'purchase.receive', order_id, order_revision,
      receipt:PurchaseReceipt}

cancel_purchase_order_remaining(p_organization_id, p_branch_id,
  p_request_id, p_order_id, p_expected_revision, p_reason)
  -> {request_id, kind:'purchase.cancel_remaining', order_id, order_revision,
      cancellation:PurchaseOrderCancellation}
```

`PurchaseOrderSummary` carries ID/scope, original `created_by/created_at`, supplier ID/name, reference, currency, immutable ordered total, derived received total/status/revision and line count. Detail adds at most 100 immutable order items with `ordered_quantity`, `received_quantity`, `cancelled_quantity`, `remaining_quantity`, unit/line cost and product snapshots, `receipt_count`, and optional bounded cancellation. Receipt history is paginated separately, never an unbounded nested list. `PurchaseReceipt` includes its ID/scope/order/operation, original actor/time, currency/exact total/reference/reason and item/movement IDs with quantities, accepted product revisions, cost and actual `balance_after/stock_revision`.

Flutter `PurchaseRepository` owns context, list/detail, create/receive/cancel, pending mutations and exact retry. Mutation models deep-freeze line inputs. `OperationExecutor` journal types are the actual RPC names above. A malformed foreign scope, mismatched request/actor/document, duplicate item/movement, wrong receipt quantity/cost/currency or inconsistent totals cannot confirm a mutation. Preserve the original UUID/payload and show a retry/reconciliation card. Mutation responses are immutable action snapshots: `PurchaseOrderCreation` contains the original header/items and initial revision/status/zero received quantities; receipts/cancellations contain their accepted order revision and original action evidence. Replays return that original response rather than a later mutable projection. The page separately reloads `get_purchase_order` to show current remaining quantities/status. Unbounded receipt history must not be embedded in action/detail responses.

## Recorded business expenses and own-shift cash payouts

An expense records an operator-confirmed business payment. The default source is `external`: funds outside the POS drawer, no provider transaction or inventory movement. Cash with this source explicitly means externally funded cash and does not alter a shift. The optional `cash_drawer` source is a manually confirmed physical payout from the current actor's own open shift in the same authorized branch and currency. Recording an expense never initiates a payout.

`public.expenses`: `id`, organization/branch, `actor_user_id`, server `created_at/occurred_at`, `currency`, `settings_revision`, positive `amount_minor`, `category`, `payee` nullable <=160, `payment_method`, `manual_confirmed=true`, `reference` nullable <=120, `source` (`external` or `cash_drawer`), nullable `shift_id`, and reason trimmed 3..1000. Categories are `rent`, `utilities`, `wages`, `transport`, `maintenance`, `fees`, `other`. Payment methods reuse cash/card/GCash/Maya/other manual naming. Noncash needs an actual operator-verified reference (3..120); cash may omit it or use a trimmed 1..120-character reference. `cash_drawer` requires method cash and a shift; `external` requires null shift. Creation accepts no client actor/timestamp or signed amount. Expense/reversal timestamps and context shift `opened_at` are serialized as explicit UTC `Z` strings independently of the PostgreSQL session timezone.

`public.expense_reversals`: new immutable full-amount compensation with original expense/scope/currency FK, actor, server timestamp, reason, `manual_confirmed=true`, optional reversal reference and `amount_minor` equal to the original. Source/shift derive from that original. One full reversal per expense; no UPDATE, DELETE, partial reversal, provider payout or automatic money return. External reversal is an explicitly confirmed bookkeeping correction/reimbursement record; its text must not claim provider success. Drawer reversal requires confirmation that the original cash has actually returned to the same own open drawer. A correction may append a reversal and a new separately confirmed expense; it never replaces the old record under its UUID.

```text
get_expense_context(p_organization_id, p_branch_id)
  -> {organization_id, branch_id, branch_name, currency, settings_revision,
      own_open_shift:null|{id,actor_user_id,currency,opened_at,expected_cash_minor}}

list_expenses(p_organization_id, p_branch_id,
  p_from=null, p_to=null, p_category=null, p_offset=0, p_limit=51)
  -> [Expense]   # immutable original + optional full reversal snapshot

get_expense(p_organization_id, p_branch_id, p_expense_id)
  -> Expense

record_expense(p_organization_id, p_branch_id, p_request_id,
  p_expected_settings_revision, p_currency, p_amount_minor,
  p_category, p_source, p_shift_id, p_payment_method, p_manual_confirmed,
  p_payee=null, p_reference=null, p_reason)
  -> {request_id, kind:'expense.record', expense:Expense}

reverse_expense(p_organization_id, p_branch_id, p_request_id,
  p_expense_id, p_manual_confirmed, p_reference=null, p_reason)
  -> {request_id, kind:'expense.reverse', reversal:ExpenseReversal,
      expense_id}
```

Creation first checks current role/branch/MFA, then the immutable actor/request mapping. A successful lost-response replay returns its original immutable action before rechecking present open-state/settings, so a subsequent shift closure/currency change cannot imply that an earlier payout vanished. New creation compares current organization currency/settings revision; drawer source row-locks the supplied own shift and requires it to be open, in this branch, and in that same currency. All source, actual manual confirmation and payment-reference fields must be structurally consistent.

Reversal first checks current role/branch/MFA and its actor/request replay mapping. For a new drawer reversal, lock the original shift before the immutable expense, require the shift still open and owned by the current actor, then append its one exact compensation. For an external reversal, lock the original expense before checking its unique compensation. Concurrent different UUIDs cannot reverse twice. **A new drawer reversal after the original shift has closed is denied and requires review; it must never change that closure or silently move the cash effect to another shift.** A replay of a successfully committed earlier reversal still returns its original immutable result after closure.

Extend the existing `private.phase3_expected_cash` to derive `opening + cash sales - cash sale reversals - drawer expenses + drawer expense reversals`. All contributing amounts remain immutable; sums use `numeric` and enforce the existing signed exact-integer bound. Externally funded expenses/reversals never affect this function. Do not invent an extra positive-cash availability policy: operator confirmation attests physical payout/return, while server expected cash is a projection rather than proof of cash on hand. A transaction must reject exact-integer overflow before commit. Existing current-shift/closure UI then receives the correct derived cash through its existing server contract.

Expense/reversal and close contend on the same shift row; offline ingest already takes that row. Preserve the existing organization-counter-before-shift ordering for writers that use the offline feed. Expense code must not acquire a feed counter after holding a shift. Existing offline-grant release/administrative-review closure triggers remain unchanged; drawer expenses never release a grant or discard paid events. Recording drawer expenses while signed grants remain outstanding does not imply those grants are reconciled, and normal closure still waits for their existing barrier.

Original/reversal, idempotency mapping and audit are one transaction. Flutter `ExpenseRepository` uses the non-null production encrypted actor/organization journal and `OperationExecutor`. Responses match exact scope/actor/UUID/currency/amount/category/payee/source/shift/manual evidence before confirmation; reversal matches its immutable original amount/currency/source/shift. A pending uncertain record/reversal freezes its original intent and blocks a replacement expense until retry/review; UI must explicitly avoid repeating the physical transfer. A pending uncertain same-branch checkout/shift-close operation also blocks starting a new drawer expense flow. Original action responses remain stable on replay; current expense/reversal state reloads separately.

## Authoritative operational reports

Reports query committed server documents/projections. Unconfigured/design-preview pages have explanatory empty states and no fabricated zero business metrics. A successful authorized empty query can truthfully show zero activity. Loading/error/stale states preserve the requested branch/window and never display another actor's results after account/branch changes.

All report responses contain `organization_id`, explicit `branch_id`, `generated_at` UTC, their requested filters and `source='server_posted'`. Financial reports use a finite UTC half-open activity window `p_from <= timestamp < p_to`, with `p_from < p_to` and maximum span 366 days. Such a window may touch 367 UTC calendar dates when its boundaries fall within a day. UI labels UTC dates; inclusive selected end date is converted to the next UTC midnight. Output is grouped by each immutable document's currency, never silently combined across a currency change. Reports must derive each result from one consistent SQL snapshot, avoiding independent aggregate/detail queries that can observe different concurrent commits and avoiding join fan-out across items/payments/reversals. Aggregates outside the exact integer bound fail with `NX003` and a narrower-window/filter message.

### Sales activity

```text
get_sales_report(p_organization_id, p_branch_id, p_from, p_to,
  p_shift_id=null)
  -> {common scope/window/source,
      shift_id:null|UUID, currencies:[SalesReportCurrency]}
```

Each currency group carries `sale_count`, `sales_subtotal_minor`, `sales_discount_minor`, `sales_tax_minor`, `sales_total_minor`, `reversal_count`, `refund_total_minor`, `void_total_minor`, `reversal_total_minor`, `net_sales_minor`, `payments:[{method,sales_minor,reversed_minor,net_minor}]`, and bounded daily UTC groups with sale/reversal counts and the same sales/reversal/net totals.

Sales contribute at immutable `sales.created_at`; this includes accepted offline sales at their original capture timestamp once they have actually posted. Refunds/voids contribute at `sale_reversals.created_at`, even if the original sale lies before the window. `net_sales_minor = sales_total_minor - reversal_total_minor`; it may be negative for a refund-only window. Payment reversal methods derive from the original `sale_payments`; split tender must not double-count sales totals. The contract does not invent refunded-tax allocation, net tax, net discount or profit. Late accepted offline postings can change historical activity on a fresh report; pending/review-only paid events remain excluded.

Owner/Admin/Manager may report any assigned-branch sales, optionally an authorized branch shift. Cashier must supply `p_shift_id` belonging to the same actor/branch, and receives only that own-shift activity. Cashier cannot use null/arbitrary shift or access expense/purchase/cost data through report side fields. Inventory Staff is denied sales reports.

### Current server inventory

```text
get_inventory_report(p_organization_id, p_branch_id,
  p_query='', p_offset=0, p_limit=51)
  -> {common scope/source, catalog_product_count, stocked_product_count,
      deficit_product_count, low_stock_product_count,
      items:[InventoryReportItem]}
```

Items carry `product_id`, current name/SKU/unit/active/reorder level, `quantity`, `stock_revision`, `has_movement`, `is_deficit`, `is_low_stock`. Use the existing branch projection; absent balance means observed zero and `has_movement=false`, not a fictional receiving history. Deficits are visible. Low stock uses active product quantity `<= reorder_level`. Show active/inactive products with stock so historical quantities do not disappear. Do not total unlike product units into a misleading grand quantity, and do not multiply current catalog cost into a purported historical valuation. No product cost/customer/supplier-contact fields are included.

This is current posted stock, not a historical inventory snapshot or device-local availability. New offline paid events still awaiting ingest are excluded. Owner/Admin/Manager/Inventory Staff may read their assigned branch; Cashier is denied this operational inventory report. Product/item ordering is stable by name/ID.

Inventory query text is a case-insensitive literal name/SKU substring, including literal `%` and `_` characters. Counts cover all matching products before pagination. Reorder level remains exact decimal text because existing catalog thresholds may be fractional; physical quantities and stock revisions remain exact JSON integers.

### Expense activity

```text
get_expense_report(p_organization_id, p_branch_id, p_from, p_to)
  -> {common scope/window/source,
      currencies:[ExpenseReportCurrency]}
```

Each currency group carries `expense_count`, `expense_total_minor`, `reversal_count`, `reversal_total_minor`, `net_expense_minor`, category groups, source groups (`external`/`cash_drawer`) and bounded daily UTC groups. Expense originals contribute at their server `occurred_at`, reversals at their own server creation time. A reversal of an older expense reduces the current window and can produce a negative net expense; the original historical document remains unchanged. Categories derive from the original expense for compensations. Expense reports exclude purchase commitments/received inventory cost and do not claim profit or external-provider settlement. The report describes expense activity; drawer closing balance still comes from the separately derived shift contract. Only Owner/Admin/Manager with current branch access may read them.

Flutter `ReportsRepository` validates every returned scope/filter/currency, supported payment/category label, uniqueness, exact integer/time and arithmetic relationship before rendering. The UI shows the report kind available for the verified role: privileged branch sales/inventory/expenses; Cashier own-shift sales; Inventory Staff current inventory. Selection remains presentation only; SQL independently enforces all permissions. Initial export may copy/share CSV generated from the actual authorized returned snapshot, with scope/UTC dates/currency/source clearly included; spreadsheet formula injection must be neutralized for textual cells. Physical printing/provider links remain deferred.

## Role and scope matrix

| Action | Owner / Admin | Manager | Cashier | Inventory Staff |
| --- | --- | --- | --- | --- |
| Purchase context/list/detail/create/receive/cancel remaining | Assigned branches | Assigned branches | Denied | Assigned branches |
| Expense context/list/detail/record/full reverse | Assigned branches | Assigned branches | Denied | Denied |
| Sales report | Assigned branch; optional branch shift | Assigned branch; optional branch shift | Own explicitly selected branch shift only | Denied |
| Inventory report | Assigned branch | Assigned branch | Denied | Assigned branch |
| Expense report | Assigned branch | Assigned branch | Denied | Denied |
| Purchase audit | Existing audit policy | Assigned branch | Denied | Assigned branch |
| Expense audit | Existing audit policy | Assigned branch | Denied | Denied |

Owner/all-branch Admin can select all permitted branches individually; this slice does not introduce an unscoped organization aggregate. Scoped Admin never gains access to a supplier/order/expense or report in another branch. Disabled memberships, lost branch assignment, unverified accounts and configured privileged AAL1 sessions fail on new requests and replay.

## Migration/ownership split

- `202610110010_purchase_orders.sql`: purchase tables/projections/immutable guards/RLS/constraints, stock-linked partial receiving and cancellation, purchase context/read/mutation RPCs, relevant narrow audit-policy extension and execution grants. Existing ad hoc receiving remains supported.
- `202610110011_expenses.sql`: external/own-open-drawer expense originals/full reversals and immutable/RLS/constraints, expense context/read/mutation RPCs, expense audit-policy extension and grants. It extends the existing shift expected-cash helper with exact net drawer-expense effects, preserving every closure/grant trigger and historical count.
- `202610110012_operational_reports.sql`: sales/current-inventory/expense report RPCs with role/window/currency enforcement, consistent server snapshots and exact aggregate bounds.
- Flutter procurement and expense domains/adapters use existing actor-scoped encrypted operation journal. Reports are read-only server adapters. UI composition adds actual pages/repositories in verified production services and empty read-only design preview pages; no fictional suppliers/orders/expenses/metrics.
- SQL harness changes should be coordinated by one owner: independent new assertion files, additive `test/sql/run.sh` hooks, and meaningful multiple-connection races. Never modify user/production databases or deploy mock Auth fixtures.

## Required local acceptance evidence

Purchase SQL: same-UUID replay and changed-payload conflict; current role/branch/MFA/disabled-member failures; supplier tenant/branch/status/revision checks; invalid/duplicate/unsafe lines; exact cost multiplication; partial/final receipts; concurrent receive beyond remaining quantity; receiving versus cancellation; rollback after a later invalid line; movement/cost/source linkage; revision/feed effects and positive receiving against an existing deficit; immutable direct mutation denial; cancellation preserves received history.

Expense SQL: positive exact amounts and supported currencies/categories/manual evidence; current settings conflict; atomic original/audit/request; stable lost-response replay; full same-currency compensation; one reversal under different-UUID race; direct mutation/foreign-scope/cashier/inventory denial; configured privileged MFA; external expenses leave expected cash unchanged; drawer expenses/confirmed returns change it exactly; wrong actor/branch/currency/closed shift and noncash drawer source fail; new reversal after closure is denied; earlier successful replay after closure stays recoverable; expense-versus-close and reverse-versus-close races serialize; offline grant barriers remain intact.

Report SQL: empty authorized results; source-backed exact totals/daily groups; split payments without fan-out; partial refunds and untouched voids; reversal-only windows; original versus reversal activity timestamps; two currencies never summed; own-shift Cashier restrictions; staff stock-only restrictions; negative stock/never-received products; scope/MFA/current-member checks; time bound/overflow failure; concurrent report snapshot consistency; expense source groups remain accurate without join fan-out. Explicitly verify that unposted/review-only offline evidence does not invent accepted sale totals; external expenses never change drawer math, and recorded drawer effects derive only from immutable expense/reversal documents.

Dart/repository/UI: integral arithmetic and validation; original UUID/deep-frozen payload before RPC; persisted pending/reopen/retry without duplicate receiving/expense; malformed/foreign/contradictory server success stays unresolved; later denial after uncertain success stays pending; role-filtered branches/report variants; 320px and desktop empty/data/error/recovery layouts; account/branch switch while an old request resolves; ISO UTC/currency/source labels; no fake metrics and no provider/payment-success claim.

Local checks establish implementation and isolated database behavior. They do not establish deployed Supabase/PostgREST, real provider/bank payouts, email delivery, Windows/Android hardware or production signing. Final documentation must state actual test/build outcomes and retain those acceptance gates.
