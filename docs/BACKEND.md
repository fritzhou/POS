# Supabase backend

The first three migrations implement Phase 1 tenant/identity access, catalog/audit and verified owner bootstrap. Migration `202610090004_phase2_management.sql` adds revision-checked catalog, contacts, settings, employee access and scoped audit. Migration `202610090005_phase2_invitation_lifecycle.sql` adds the invitation lifecycle and service-only email dispatch boundary. Migration `202610090006_online_pos_and_stock_ledger.sql` adds online checkout, immutable receipts, shifts, stock ledgers and compensating reversals. Migration `202610100007_offline_authorization_and_sync.sql` adds minimal device enrollment, signed grant retention, immutable offline ingestion/review, stock revisions/feed and signed shift-release barriers. Migrations 008/009 add security policies, device/grant administration, source-backed notices and server-only PIN lifecycle. Migrations 010–012 add purchase orders/partial receiving, expenses/full reversals and authoritative operational reports. Migrations 013/014 add branch maintenance and stock logistics; migration 015 adds invitation administration. Apply all fifteen in order. They have been executed on PostgreSQL 17.11 with disposable Auth interfaces; live Supabase Auth/PostgREST/email and native callbacks remain **Not Yet Connected** until a real project is configured and tested.

## Deploy and connect

Apply only `supabase/migrations/*.sql` in filename order with the Supabase migration owner, through a securely authenticated CLI or the project's SQL editor. Review the destination first: migrations change schema and grants. Never deploy `test/sql/` mocks or assertions to a real project.

The Flutter client needs public `SUPABASE_URL`, `SUPABASE_PUBLISHABLE_KEY` (legacy `SUPABASE_ANON_KEY` fallback) and a supported `AUTH_REDIRECT_URL`, as shown in `config/supabase.example.json`. Configure exact Auth redirects, email confirmation, password policy and rate limits. Test signup, verification, recovery, invitation callbacks, refresh, secure storage and sign-out on target platforms.

Deploy/configure `employee-invitations` using [INVITATIONS.md](INVITATIONS.md), including its server-only service credential, redirect and browser origins. Service-role credentials, database passwords, SMTP and provider keys belong only in secured backend settings. No administrative Auth API or secret belongs in Flutter. Migrations and static templates do not configure live email delivery.

## Identity and tenant contracts

Profiles contain names/phone, no role or password. Users can edit only their own allowed profile fields. Membership roles are `owner`, `admin`, `manager`, `cashier`, `inventory_staff`; statuses are `active`, `disabled`, `pending`. Own membership rows remain readable after disabling to explain denied access; this grants no business permission. Other membership/profile reads enforce roster branch scope.

Organizations and active branches require current membership authority. Owners have all-branch access. Admins gain it only through the explicit server-controlled `all_branches` field; otherwise assignments apply. Other roles require an active assigned branch. Composite foreign keys prevent mixing records from different businesses.

After verified owner registration, `bootstrap_organization(p_business_name, p_full_name)` derives `auth.uid()` and checks Auth's confirmed email. One transaction creates profile/business/Main Branch/Owner membership/assignment/audit. It serializes the identity, returns original IDs on retry and cannot restore a disabled owner. Existing employees can create their own separate business; metadata cannot grant ownership in another. Owner transfer and multiple ownership remain separate future operations.

## Phase 2 RPCs

| Workflow | Authenticated client operations |
| --- | --- |
| Catalog | `list_products`, `save_product`, `save_category` |
| Contacts | `save_supplier`, `save_customer`; bounded RLS reads |
| Employees | `employee_roster`, `change_employee_access` |
| Business/audit | `get_business_settings`, `save_business_settings`, `list_audit_logs` |
| Invitations | `prepare_employee_invitation`, `list_pending_invitations`, `accept_employee_invitation`, `revoke_employee_invitation` |

Creates derive identifiers and revisions server-side. Every edit/deactivation requires the displayed revision; stale edits raise `40001` without committing. Successful mutations return canonical records and append actor-derived audit atomically. Employee access changes return the complete roster-shaped result in the same transaction. Owner transfer, self-edits and Admin escalation are denied. See [PHASE2_DATA.md](PHASE2_DATA.md) for typed adapter contracts.

## Phase 3 RPCs

| Workflow | Authenticated client operations |
| --- | --- |
| POS lookup | `get_pos_context`, `list_pos_products`, `lookup_pos_product_by_barcode` |
| Cash shifts | `open_shift`, `get_current_shift`, `list_shifts`, `close_shift` |
| Checkout/receipts | `checkout_sale`, `get_sale_by_request`, `get_sale`, `list_sales` |
| Stock | `receive_stock`, `adjust_stock`, `list_inventory`, `list_stock_movements` |
| Compensation | `reverse_sale` |

Mutation requests bind a UUID to the organization, authenticated actor, operation kind and canonical payload. Current identity/membership/branch authority is checked before an existing result can be replayed. A changed payload cannot reuse the UUID. These request records are separate from offline event ingestion.

Checkout locks the current shift, settings and products, checks displayed revisions and available branch stock, and computes exact discounts/tax/payments on the server. The transaction seals the sale/items/payments, appends depletion movements, allocates a receipt number and records audit atomically. Cashiers cannot discount or reverse sales. Owner/Admin/Manager actors require their own verified session and branch authority for those actions. Cashier receipt history is limited to their own sales; Inventory Staff cannot read sales.

Stock balances are private projections of immutable movements. Receiving permits Owner/Admin/Manager/Inventory Staff; signed adjustments permit Owner/Admin/Manager. Ordinary online operations cannot introduce or deepen a negative stock balance. Source-backed offline ingestion may post an already-paid sale as a deficit, and positive physical receipts/returns can reduce it without rewriting the original sale. Private receiving-cost evidence records the product currency/revision and does not alter catalog valuation.

Refunds lock the original sale and limit cumulative returned units and payouts to original item/payment sources. Exact cumulative proportions preserve final rounding cents. Untouched-sale voids are full compensations. Stock is restored only with an explicit physical-return choice. An open payout shift is required, and its expected cash can be negative after a historical cash refund. Original financial documents remain unchanged. See [CHECKOUT.md](CHECKOUT.md) and [INVENTORY.md](INVENTORY.md).

## Access and integrity

Phase 6A RPCs include `get_purchase_context`, purchase order/receipt reads, `create_purchase_order`, `receive_purchase_order`, `cancel_purchase_order_remaining`, expense context/history reads, `record_expense`, `reverse_expense`, and `get_sales_report`, `get_inventory_report`, `get_expense_report`. [PHASE6_CONTRACT.md](PHASE6_CONTRACT.md) defines their wire, permission and recovery contracts.

Submitted orders and costs remain immutable. Receiving uses the original cost/currency while checking the current product revision and posting through the existing stock ledger/feed. Each action returns its original immutable result on an authorized replay; current order state is read separately. Suppliers receive no payment or email from these RPCs.

Expenses record explicitly confirmed external payments or cash payouts from the current actor's own open same-branch/currency shift. Full reversal appends compensation; a new drawer reversal requires the original drawer still open and the cash physically returned. Expense, reversal and shift close serialize on the same shift row. Expected cash is opening cash plus cash sales, minus cash sale reversals and drawer expenses, plus drawer expense reversals. External expenses do not change it. Successful old requests remain recoverable after closure or settings changes; current authorization is still required.

Reports read server-posted documents in one SQL statement snapshot. Sales and compensations use their own activity timestamps, historical currencies remain separate, and split payment/item joins do not inflate totals. Cashier sales reports require an explicitly selected own shift; Inventory Staff receives current inventory only. UTC windows span at most 366 days; unsafe aggregates return `NX003` with a narrower-range error. Pending or review-only offline events do not become sales metrics. No inventory valuation, COGS, profit, net-tax allocation or provider settlement is invented.

Every exposed business table has RLS. Security-definer helpers use fully qualified objects and an empty search path, derive identity from the JWT and read current memberships. Migrations revoke broad PostgreSQL/Supabase default grants before applying intended privileges. The test harness deliberately starts with broad defaults to exercise this boundary.

The catalog is organization shared. Direct client writes are revoked; Owner/Admin/Inventory Staff use revision-checked RPCs. Manager/Cashier views are read-only. Direct client column grants exclude costs; catalog and POS lookup mask Cashier costs. Money is bounded to exact platform integers, and decimal reorder quantities are serialized as strings. Phase 3 stock is branch-scoped and uses whole units. Branch-specific pricing and fractional stock operations remain deferred.

Supplier/customer RLS checks organization, role and branch. Branch staff cannot write global contacts; authorized all-branch administrators can. Membership and profile reads prevent scoped Admins from inspecting employees outside their permitted branches.

Audit is server written and immutable to normal clients, including insert/update/delete/truncate denial. Owner/all-branch Admin can inspect organization audit. Scoped Admin security-event reads must cover every branch in the immutable prior/new employee or invitation snapshot; later reassignment cannot reveal old out-of-scope events. Shared catalog/settings audit remains organization wide. Managers read authorized branch supplier/customer, sale, shift, inventory-operation and reversal events; Inventory Staff read branch supplier and inventory-operation events. Cashiers are denied audit access. The trusted database superuser and backend service remain administrative boundaries.

Invitation preparation stores permitted role/branches and a canonical request UUID/payload under the actor JWT. `claim_invitation_delivery` and `finish_invitation_delivery` are service-only. Supabase Auth owns email action credentials; business invitation IDs are lookup identifiers. Acceptance derives verified recipient email, checks password presence, expiry, delivery state and inviter authority, then creates membership/assignments/audit transactionally. Clients cannot supply their own role during acceptance.

New invitations are limited to 20 per organization per rolling ten minutes and 200 per rolling 24 hours under an organization advisory lock. Known status retries work at the cap. Rejected dispatch retries have a ten-second cooldown. Dedicated SQLSTATE `NX001`/`NX002` becomes sanitized HTTP 429. A timeout stays `sending`, never automatically reclaimed or reported as sent. Auth provider acceptance does not prove inbox arrival.

`financial_events` remains private and immutable with no client write grants. Phase 3 online operations retain their separate transactional request registry. Phase 4 authorized events use retained device/grant proofs and service-only `ingest_offline_event`; legacy outbox rows without genuine authorization remain excluded. Edge verifies signatures/current bearer identity and SQL independently checks scope, current membership/device, replay and original math. See [OFFLINE_BACKEND.md](OFFLINE_BACKEND.md).

## Deferred operations

Phase 5 implements PIN verification/reset, privileged MFA policy and enrolled-device/lost-key administration. Employee-ID resolution, financial delegation and general Auth session/device inventory remain **Coming Soon**. Global sign-out explicitly revokes provider refresh sessions; already issued access tokens retain their provider expiry. Minimal proof-of-possession enrollment and bounded signed offline grants are implemented source, with live deployment outstanding. Phase 6D implements administrator invitation history/detail, original delivery retry and durable revocation. Unknown `sending` outcomes have no automatic reclaim or administrative outcome guess. Images/logo upload and rendering are not integrated.

Auth login/logout/failed-login/password-reset audit and password-changed/suspicious-login emails require trustworthy Auth events. They are not fabricated through client audit writes. Implemented audit covers catalog/contact/settings/membership/bootstrap/invitation actions and accepted sales, shifts, stock receipts/adjustments and reversals. Passwords, PINs, tokens and email action URLs are excluded from security metadata.

## PostgreSQL validation

`bash test/sql/run.sh nexapos-postgres-test` verifies the exact pinned test image, running state, disabled networking, absent host ports and anonymous PostgreSQL volume before recreating only `nexapos_security_test`. It rejects arbitrary container names. Never target a user database.

The harness applies production migrations without policy exemptions. Phase 1 assertions run before Phase 2 supersedes direct catalog writes; Phase 2/invitation, Phase 3 and Phase 4 assertions validate the final schema. Checks cover tenant/branch isolation, disabled identities, escalation attempts, costs, revisions, exact quantities, immutable audit, invitation identity/password/expiry/replay/rates and atomic rollback. Financial checks include exact large discounts, split manual tenders, stock depletion, historical refunds, partial rounding, physical returns, voids, immutable receipts and audit-failure rollback.

Eight simultaneous owner-bootstrap calls create one organization/branch/membership/audit, and concurrent product updates produce one commit and one revision conflict. Two cashiers competing for the last unit produce one accepted sale and one insufficient-stock rejection. Two concurrent transports replaying one checkout UUID return one identical receipt, one depletion movement and one audit event. Phase 4 adds authenticated/denied/replayed offline outcomes, source-backed deficits, bounded changefeed/tombstones, grant expiry/release and reservation recovery assertions, plus offline duplicate-upload and late-commit feed races. See [VALIDATION.md](VALIDATION.md) for the final current counts.

Phase 6 adds purchase receipt/cancellation and UUID/revision races, expense/reversal-versus-close and offline-ingest races, and concurrent report reads during committed financial writes. The final Phase 6D isolated run passed 1,227 assertions and checked 200 changing report snapshots, including concurrent receipt/transit-return, invitation acceptance/revocation and original delivery-claim checks. Actual RPC fixtures under `test/fixtures/` are rolled-back test data used by Dart decoders; they must never appear as live business records.

`test/checkout_review/collect_server_contract.sql` creates a rollback-only test business to capture actual RPC JSON for `server_contract_test.dart`. Its test-only fixture verifies SQL response decoding, large-number parity, private-cost omission and signed drawer deficits; the application never loads it.

Passing SQL/HTTP tests does not establish live deployment, email delivery, platform callbacks, hardware or payment providers. Static email designs remain **Placeholder**.

An expired finalized grant always blocks ordinary shift close until signed final release or explicit administrator resolution. An expired unsigned zero-event reservation can be abandoned by the server because no signed grant was delivered; this exception cannot discard a paid financial event. Logout/lost device keys preserve original proofs for online upload, and Phase 5 supplies audited revoked/expired-grant resolution with explicit unknown-payment exposure. It never fabricates a device final-release proof.

Phase 6B adds branch maintenance and physical stock logistics through migrations 013/014. Read [PHASE6B_CONTRACT.md](PHASE6B_CONTRACT.md). Current authorization and privileged MFA precede every replay; dispatch requires both endpoints, receipt requires its destination and transit return its source. Supplier returns reference original purchase receipt quantities and costs and do not pay suppliers. Branch deactivation blocks retained grants, unresolved stock/transit, open shifts and outstanding orders. Codes remain immutable, referenced product units cannot change, and scope changes reload server membership. Preserve encrypted logistics intents, original evidence and UUIDs through uncertain responses. Direct service branch/catalog writes are revoked; use validated RPCs.

Phase 6D adds `list_managed_employee_invitations`, `get_managed_employee_invitation` and `revoke_employee_invitation_action` through migration 015. Read [PHASE6D_CONTRACT.md](PHASE6D_CONTRACT.md). Owner/Admin history checks current verified membership, privileged MFA and every original branch assignment, including inactive branches. Only an Owner can mutate an Admin invitation. Retry payloads are private to the original creator and preserve the existing email request UUID and all canonical fields; no unknown `sending` claim is reclaimed. Revocation checks current authority before immutable replay, locks the invitation and atomically appends its action/request receipt and audit. All invitation lifecycle updates advance a bounded revision. Recipient and service-only delivery RPCs retain their existing credential boundaries.
