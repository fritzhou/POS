# Purchase orders and receiving

The connected purchase workspace records immutable unpaid orders, physically counted deliveries, and cancellation of outstanding quantities. Owner, Admin, Manager and Inventory Staff can use their assigned active branches; Cashier access is denied. Preview and unconfigured workspaces show an explanatory empty state without fabricated suppliers, orders, stock or costs.

Order submission records the supplier and product snapshots, currency, recorded procurement costs, reason and optional reference. The confirmation explicitly says it does not pay or email the supplier. Work before submission stays in memory. There are no editable persisted drafts, supplier payments, purchase returns, tax or freight allocation, or provider transmission.

Each order has at most 100 unique products. Quantities are whole units from 1 to 1,000,000. Costs can be zero and use the supported two-decimal currencies. Dart `BigInt` and PostgreSQL `numeric` validate multiplication and aggregated costs before converting them to exact integers, with an upper bound of 9,007,199,254,740,991.

## Physical receiving and cancellation

Receiving requires a positive entered quantity within the remaining amount, review of the current active catalog product and its revision, and explicit confirmation that the goods were counted. The original order name, SKU, unit cost and currency remain immutable. A later catalog rename or currency change is shown for review and does not replace that original cost evidence.

The server appends one receipt, inventory operation, stock movement per received item, private cost evidence, audit event and request result in one transaction. It updates the existing stock and order projections. It can reduce an existing trusted stock deficit and emits the existing authoritative stock revision/change feed. It never changes catalog cost or asserts a supplier payment.

Partial receiving leaves the outstanding quantities open. Cancelling after a partial receipt closes only those quantities and displays **Remaining quantities cancelled**; the received stock and delivery history remain. Fully received or cancelled orders cannot receive or cancel again. Order detail preserves ordered, received, cancelled and remaining quantities, and pages delivery history separately in groups of 20.

## Requests and recovery

`SupabasePurchaseRepository` requires the actor/organization-scoped operation journal supplied by production services. Create, receive and cancel use the shared `OperationExecutor`, which saves the original UUID and frozen payload before dispatch. The adapter proves scope, actor, action kind, request ID, accepted revision, item quantities and immutable original costs before confirming the journal entry. It reads the current order for immutable provenance before receiving/cancelling; current remaining state does not block recovery of an earlier successful action.

A lost or malformed success remains unconfirmed. The workspace freezes creation and stock actions, displays the saved request, and retries that same UUID and payload. Operators must not repeat the physical delivery. A later server or local authorization denial cannot erase an earlier uncertain attempt. A definitive first-attempt rollback permits correction and a newly confirmed request. Recovery sessions and signed-out, foreign-account, unauthorized-role or foreign-branch requests cannot dispatch.

Replay returns the original immutable action document, including the original order creation revision or delivery revision. A separate current-order read refreshes status and remaining quantities. Account/repository changes clear displayed order state, and dialog submissions verify the repository, generation and branch captured before the dialog opened. Cancellation controllers belong to the dialog and remain valid through its closing animation.

## Validation

```bash
cd /workspace/POS
source tool/dev_env.sh
flutter analyze lib/features/purchases test/purchases
flutter test test/purchases
```

The tests cover domain bounds, exact cost arithmetic, authorization, durable intent before dispatch, malformed and foreign evidence, immutable receipt cost after catalog changes, partial cancellation, lost-response retry, later denial, and journal reopening. They decode the PostgreSQL RPC output in `test/fixtures/purchases_sql_contract.json`, including initial creation, partial and later receipts, cancellation and final order detail. Widget checks exercise actual repository data, empty/disabled preview behavior, 320-pixel and desktop layouts, confirmations, pagination, frozen uncertain requests and stale dialog/read results.

The database contract and server validation are described in [PHASE6_CONTRACT.md](PHASE6_CONTRACT.md). Overall executed checks and platform limits are recorded in [VALIDATION.md](VALIDATION.md). These local tests do not establish live Supabase connectivity, physical device behavior, provider payment, printing or email delivery.
