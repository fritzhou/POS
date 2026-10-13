# NexaPOS architecture and delivery plan

This document defines the design before application implementation. NexaPOS is a Flutter application for Windows desktop and Android phones/tablets, backed by Supabase Auth and PostgreSQL, with Drift/SQLite for durable local data. The initial product name is **NexaPOS** and its tagline is **Smart Retail & Cafe POS**.

The long-term design supports a commercial retail and cafe POS. Phase 1 establishes the application, identity and local-durability foundation. Phase 2 implements online catalog, supplier/customer, employee-access, invitation, business-settings and audit workflows. Phase 3 adds online checkout, shifts, immutable receipts and sales, inventory and compensating reversals. Phase 4 adds bounded signed offline grants, cost-free caches, provisional checkout, ingestion, stock-conflict records and explicit synchronization/release. Phase 5 adds encrypted business/journal files, durable partial tenders, idle locking, provider TOTP/AAL2 policy, audited PIN lifecycle and scoped device/lost-key administration. Phase 6A adds immutable purchase orders/partial receiving, external or own-drawer expenses/full compensation, and server-posted operational reports. Phase 6B adds branch maintenance, stock transfers and supplier returns. Phase 6C adds receipt PDF/system-print adapters and opt-in keyboard HID scanner capture. Phase 6D adds scoped invitation history/detail, original-creator delivery retries and durable audited revocation. A real Supabase deployment, Auth email delivery and physical platform callbacks have not been connected or validated. Source implementation and local harness checks do not establish a live commercial system. A disconnected installation shows **Not Yet Connected**; unimplemented features show **Coming Soon** or **Placeholder**. Recorded card/e-wallet payments show **Manual Payment Verification** until a real provider has been connected and tested.

Current delivery boundaries:

| Area | Implemented source | Outstanding live or later work |
| --- | --- | --- |
| Auth and owner setup | Supabase adapter, verified owner bootstrap, secure session persistence and recovery gate | Real-project configuration, email/callback/OS-vault verification |
| Catalog and directories | Paginated search/edit/active status, typed repositories, revision-checked audited RPCs, role/tenant/branch policies | Deploy/test through live PostgREST; image/logo upload service |
| Employees | Scoped roster/access changes, invite-send form, recipient inbox/acceptance, Owner/Admin invitation history/detail/search/status, exact original-creator retries and durable audited revocation | Deploy Edge Function and Auth redirects; actual new/existing-account email tests; operational reconciliation of permanently ambiguous sends |
| Business and audit | Audited business/currency/tax/receipt updates and authorized paginated audit viewer | Live-project verification and production operational policy |
| Online POS, shifts and sales | Identity-bound checkout, exact calculations, cash/manual tender, immutable receipts, own-cashier history, compensating refund/void RPCs, receipt PDF/system printing and keyboard HID scanning | Deploy/test live PostgREST; physical printer/scanner and Windows validation, camera scanning, cashier-to-manager PIN approval and provider APIs |
| Branch inventory | Branch maintenance, whole-unit receiving/adjustment, purchase-linked receipts, stock dispatch/partial receipt/transit return, append-only ledger and trusted offline deficit visibility | Fractional units, specialized disposal and deficit-resolution administration, physical multi-device validation and live deployment |
| Purchases and expenses | Immutable orders/partial receipts/remainder cancellation, receipt-linked supplier stock returns, external and own-open-drawer expense originals/full compensation | Supplier payments, provider payouts, accounting integration and live deployment |
| Operational reports | Server-posted sales/current inventory/expenses, role/branch/own-shift scopes, UTC windows, historical currency groups and CSV | Profit/COGS, inventory valuation, accounting and live deployment |
| Local durability and sync | Additive Drift v2, SQLCipher business/journal files, durable partial tenders, immutable events/acceptance links and revisioned pulls | Live integration, physical vault/key recovery and operational deficit/partial-payment reconciliation |
| Offline security and device actions | Ed25519 grants/checkpoints, known-denial locking, device review/revocation, TOTP/AAL2 policy and audited PIN lifecycle | Live deployment/vault/time tests, financial PIN delegation, general Auth device binding and hardware attestation |

The table catalog, ERD and later phases below remain the complete target architecture. They include future tables/modules that are not yet present in deployed software; production migrations and actual feature capabilities are the implementation inventory.

## 1. System architecture

```text
Windows Flutter app                         Android Flutter app
  Adaptive desktop views                     Adaptive mobile/tablet views
                    Shared Dart application
             Material 3 design system + centralized branding
             Riverpod state, dependency injection and use cases
             Domain entities, policies and service interfaces
                        Repository interfaces
              /                                \
    Drift/SQLite local database          Supabase adapters
    Cache, local transactions,           Auth, PostgreSQL, Storage
    append-only outbox                   and server functions
              \                                /
                Connection-aware synchronization
                             |
         Authenticated server boundary: Edge Functions / RPC
         Validate identities, memberships and permissions
         Device proofs and signed grants bound offline sale authorization
         Invitations, privileged operations, financial acceptance
                             |
         PostgreSQL: organization + branch isolation through RLS
         Immutable financial records and authoritative audit ledger
                             |
       Supabase Auth email delivery now; replaceable email adapter later
```

Flutter never contains a Supabase service-role key, SMTP password, payment credential, or private email API key. The Supabase project URL and publishable/anon client key are public configuration; row-level security (RLS), explicit grants, validated server functions and authenticated membership checks protect data. Development secrets belong in environment settings or ignored local files, and server secrets belong in Supabase function secrets.

Application layers:

| Layer | Responsibility | Must not do |
| --- | --- | --- |
| Presentation | Responsive views, forms, navigation, connection/feature status | Decide authoritative permissions or write SQL directly |
| Application | Use cases, orchestration, transaction boundaries | Trust a role supplied by a form |
| Domain | Entities, money rules, permissions, immutable event contracts | Depend on Flutter widgets or Supabase responses |
| Data | Supabase and Drift repositories, DTO mapping, migrations | Silently fabricate backend success |
| Platform | Secure storage, scanners, device information, connectivity | Treat a device name as proof of device identity |
| Backend | Identity-bound actions, business invariants, invitations, audit | Expose administrative Auth APIs to the client |

Use integer minor currency units or exact decimal values with an explicit currency/scale; never binary floating-point arithmetic for stored financial amounts. Current Phase 3 quantities are whole units and money uses a fixed two-decimal scale, bounded to exact JSON integers. Online financial transactions accept **PHP, USD, EUR, GBP, AUD, CAD and SGD** only. Catalog/settings accept a three-letter code for legacy compatibility; such a label does not grant transactional support, and the financial boundary rejects unsupported codes. Settings explain the supported operational list. Changing currency does not convert existing prices, open shifts or historical amounts. Currencies needing zero, three or another number of decimal places require a later precision migration and shared rounding rules. Receipt calculations are validated by PostgreSQL, independently of the client calculation. Server timestamps establish authoritative ordering; client timestamps are retained as observations.

## 2. Folder structure

The following target structure is modular. Directories for later features may be introduced when their phase begins; an empty directory is not a completed module.

```text
POS/
  README.md
  docs/
    ARCHITECTURE.md
    SETUP.md
    SECURITY.md
  lib/
    main.dart
    app/
      app.dart
      config/                 # brand, public runtime configuration, feature status
      routing/                # authenticated routes and permission-aware navigation
      theme/                  # colors, typography, spacing, Material 3 theme
      shell/                  # Windows/sidebar and Android/bottom navigation
    core/
      auth/                   # auth session model, Supabase adapter, error mapping
      security/               # secure persistence, permission checks, device policy
      database/               # Drift schema, connection, migrations
      network/                # reachability and typed transport failures
      sync/                   # outbox, event contracts, retry policy
      services/               # EmailService, PaymentService, feature capability contracts
      widgets/                # shared fields, status banners, empty/error/loading states
      utils/                  # money, dates, validation
    features/
      authentication/
        presentation/
        application/
        domain/
        data/
      dashboard/
      pos/
      sales/
      products/
      inventory/
      purchases/
      suppliers/
      customers/
      employees/
      shifts/
      expenses/
      reports/
      audit/
      notifications/
      settings/
  supabase/
    migrations/               # versioned schema, constraints, grants, RLS and RPC
    functions/
      employee-invitations/    # implemented privileged invite orchestration; deployment pending
      financial-events/       # later validated append-only ingestion
      security-events/        # later authenticated security action boundary
    templates/                # clearly marked email-design placeholders
  test/
    auth/
    permissions/
    sync/
    widgets/
  integration_test/
  android/
  windows/
  tool/                       # repeatable development helpers; no secret literals
  pubspec.yaml
  pubspec.lock
```

Riverpod providers inject interfaces, allowing local, cloud and test implementations without rewriting views. Feature business logic does not depend directly on the Supabase singleton. Route visibility comes from verified server memberships; a user cannot switch roles with a UI selector.

## 3. Database tables

All organization data carries `organization_id`. Branch data also carries `branch_id`, and constraints ensure that a branch and its parent organization match. Primary identifiers use UUIDs to support offline creation. Foreign keys, unique constraints and checks enforce the model independently of UI validation. Application tables reference the identity in `auth.users`; they never contain account passwords.

### Identity, organization and security

| Table | Principal fields / constraints | Purpose |
| --- | --- | --- |
| `organizations` | id, business_name, owner_user_id, logo_path, address, contact, currency, created_at | Business tenant; owner is established by verified bootstrap |
| `branches` | id, organization_id, name, code, address, active; unique organization/code | Main Branch and future branches |
| `profiles` | user_id -> auth.users, full_name, phone, created_at | Personal identity metadata; excludes roles/passwords |
| `organization_memberships` | id, organization_id, user_id, role, status, employee_id, created_at; unique organization/user | Backend-controlled role and enable/disable status |
| `membership_branches` | membership_id, branch_id; unique pair | Authorized branches for branch-scoped employees |
| `employee_invitations` | id, organization_id, normalized_email, full_name, requested_role, invited_by, request_id, request_payload, employee_id, phone, all_branches, revision, delivery_state, delivery_claim_id, delivery_claimed_at, delivery_finished_at, expires_at, accepted_at, accepted_by, revoked_at | Server-owned, expiring business invitation; safe administration RPCs omit claim credentials/raw payload; Auth owns email action credentials |
| `invitation_branches` | invitation_id, organization_id, branch_id; unique invitation/branch and same-organization foreign keys | Authoritative multi-branch scope copied during acceptance |
| `devices` | id, organization_id, branch_id, enrolled_by, device_name, platform, public_key, status, last_login_at, last_sync_at | Registered device and future proof-of-possession key |
| `device_sessions` | id, device_id, user_id, auth_session_id, created_at, last_seen_at, revoked_at | Session/device inventory; session identity verified on server |
| `pin_credentials` | membership_id, pin_hash, hash_algorithm, version, updated_at, reset_required | Server-only PIN verifier; never selectable by app roles |
| `pin_reset_requests` | id, membership_id, requested_by, token_digest, expires_at, used_at, reason | Authorized, short-lived PIN reset grant |
| `security_policy` | organization_id, session_idle_minutes, mfa_policy, approved_devices_required, offline_grant_hours | Versioned organization security policy |
| `audit_logs` | id, organization_id, user_id, role, action, entity, entity_id, branch_id, device_id, occurred_at, reason, metadata | Server-written append-only audit; no employee edit/delete |
| `notifications` | id, organization_id, recipient_user_id, kind, title, read_at, created_at | In-app notifications; external delivery can remain a placeholder |

`role` is one of `owner`, `admin`, `manager`, `cashier`, `inventory_staff`. A role is not a JWT field controlled by a client or mutable profile property. Membership status is `active`, `disabled`, or `pending`. Branch assignments are required for branch-scoped roles. Owners have all-branch access; Admin all-branch access is an explicit organization permission, not inferred from a missing branch filter.

### Catalog, people and procurement

| Table | Principal fields / constraints | Purpose |
| --- | --- | --- |
| `categories` | id, organization_id, name, active, revision | Product grouping |
| `products` | id, organization_id, sku, barcode, name, category_id, image_path, cost_minor, price_minor, currency, reorder_level, unit, supplier_id, active, revision | Catalog with unique organization/SKU and barcode policy |
| `product_prices` | id, organization_id, product_id, branch_id, price_minor, effective_at, revision | Optional branch/time-dependent pricing |
| `suppliers` | id, organization_id, name, contact, address, active, revision | Supplier directory |
| `customers` | id, organization_id, name, contact, consent_flags, active, revision | Minimize local personal data; access scope enforced |
| `purchase_orders` | id, organization_id, branch_id, supplier_id, status, created_by, created_at | Purchase workflow |
| `purchase_order_items` | id, purchase_order_id, product_id, quantity, unit_cost_minor | Purchase line items |
| `stock_receipts` | id, organization_id, branch_id, purchase_order_id, received_by, received_at | Confirmed receiving document |
| `stock_receipt_items` | id, receipt_id, product_id, quantity, unit_cost_minor | Receiving lines that generate ledger entries |

Products do not use a mutable global `stock` field as the stock source of truth. Phase 3 branch inventory balances are projections of append-only movement entries. Catalog data remains shared within an organization; catalog existence alone does not establish branch stock. Owner/Admin/Inventory Staff can manage the shared catalog; Managers/Cashiers have read access, with product cost masked for Cashiers. Supplier/customer directories can be organization-shared or branch-scoped; branch staff write only authorized branch records. Shared-directory writes require an Owner/Admin with all-branch access. Catalog and directory updates use expected revisions and conflict detection.

### Sales, shifts, inventory and financial history

| Table | Principal fields / constraints | Purpose |
| --- | --- | --- |
| `shifts` | id, organization_id, branch_id, device_id, opened_by, opened_at, opening_cash_minor | Shift identity and opening event |
| `shift_events` | id, shift_id, event_type, actor_id, amount_minor, occurred_at, reason | Close/cash-in/cash-out events; append-only |
| `sales` | id, organization_id, branch_id, device_id, shift_id, cashier_id, customer_id, receipt_number, currency, subtotal_minor, discount_minor, tax_minor, total_minor, created_at | Immutable accepted sale header |
| `sale_items` | id, sale_id, product_id, sku_snapshot, name_snapshot, quantity, unit_price_minor, discount_minor, tax_minor, line_total_minor | Immutable item and pricing snapshots |
| `payments` | id, sale_id, method, amount_minor, currency, verification_mode, reference, recorded_by, recorded_at | Cash or explicitly manual digital payment evidence |
| `refunds` | id, organization_id, branch_id, sale_id, approved_by, reason, total_minor, created_at | New compensating financial document |
| `refund_items` | id, refund_id, sale_item_id, quantity, amount_minor | Refund quantities and amounts |
| `sale_events` | id, sale_id, event_type, actor_id, approved_by, reason, occurred_at | Void/status/approval history without rewriting the sale |
| `inventory_movements` | id, organization_id, branch_id, product_id, type, quantity_delta, source_type, source_id, actor_id, reason, occurred_at | Append-only stock movement ledger |
| `inventory_balances` | organization_id, branch_id, product_id, quantity, version, updated_at | Rebuildable server projection of the movement ledger |
| `expenses` | id, organization_id, branch_id, shift_id, category, amount_minor, currency, actor_id, reason, occurred_at | Financial expense document; corrections use reversing entries |
| `business_settings` | organization_id, branch_id optional, section, values, revision | Receipt, currency, tax and business configuration |

The complete target includes sale, refund, purchase, adjustment, damaged, expired, transfer and return movements. The Phase 3 checkpoint supplied sale/receiving/adjustment/compensation; Phase 6A implements purchase orders and partial receipts, and Phase 6B implements stock transfers and supplier stock returns through the same ledger. Specialized disposal workflows remain later work. Whole-unit quantities are required by the current financial ledger; fractional measured products need an explicit exact-scale schema migration. Financial records have no normal client `UPDATE` or `DELETE` privilege. Refunds, voids and corrections are separate events/documents with permission checks and reasons.

Current Phase 3 implementation uses these narrower tables rather than every target table above:

| Implemented table | Current responsibility |
| --- | --- |
| `shifts`, `shift_closures` | Immutable opening identity and separate immutable counted-cash closure; cash-in/out events are deferred |
| `sales`, `sale_items`, `sale_payments` | Accepted receipt/settings/product snapshots and counted/manual payment evidence |
| `sale_reversals`, `sale_reversal_items`, `sale_reversal_payments` | Compensating refund/void quantities and amounts tied to original lines/payments; explicit stock-return choice |
| `inventory_operations`, `stock_movements` | Receiving/adjustment documents and source-linked branch ledger entries |
| `private.stock_balances` | Rebuildable nonnegative branch projection; not directly client-writable |
| `private.receipt_sequences`, `private.operation_requests` | Server receipt allocation and organization/actor/request idempotency |
| `private.sale_cost_snapshots`, `private.inventory_cost_evidence` | Server-private cost evidence excluded from Cashier receipts |

The corresponding online RPCs do not require a registered device or implement the future offline event schema. Device identity and offline grants remain separate security boundaries.

### Synchronization and local-only state

| Table | Location | Purpose |
| --- | --- | --- |
| `sync_event_receipts` | PostgreSQL | Unique organization/device/event ID, canonical payload digest, outcome and accepted_at; server idempotency registry |
| `sync_change_log` | PostgreSQL | Server-controlled monotonically ordered changes/tombstones for incremental cache refresh |
| `local_products`, `local_categories`, `local_prices` | Drift | Tenant/branch-scoped catalog cache with remote revision |
| `local_inventory_snapshots` | Drift | Branch balance projection, last successful sync and uncertainty indicator |
| `local_customers` | Drift | Minimal authorized customer cache |
| `local_sales`, `local_sale_items`, `local_payments` | Drift | Transactionally committed local financial snapshots |
| `local_shifts`, `local_shift_events` | Drift | Durable shift state and events |
| `sync_outbox` | Drift | event_id, scope, event_type, payload/version, payload_digest, status, attempts, lease_until, next_attempt_at, last_error, created_at |
| `sync_cursors` | Drift | Tenant/branch/feed cursor committed with applied cache changes |
| `local_session_metadata` | Drift | Non-secret device/user/scope hints only; tokens remain in secure storage |

Use separate local database files per organization and approved branch/device scope where practical. Every local row still includes scope to prevent cross-tenant access through cache mistakes. Schema migrations are versioned and must preserve pending outbox records; migration failure cannot be handled by deleting the database.

## 4. Text ERD

```text
auth.users 1 --- 1 profiles
auth.users 1 --- * organization_memberships * --- 1 organizations
organizations 1 --- * branches
organization_memberships 1 --- * membership_branches * --- 1 branches
organizations 1 --- * employee_invitations
employee_invitations 1 --- * invitation_branches * --- 1 branches
organization_memberships 1 --- 0..1 pin_credentials
organization_memberships 1 --- * pin_reset_requests
organizations 1 --- * devices * --- 1 branches
devices 1 --- * device_sessions * --- 1 auth.users
organizations 1 --- 1 security_policy
organizations 1 --- * audit_logs

organizations 1 --- * categories 1 --- * products
organizations 1 --- * suppliers 1 --- * products
products 1 --- * product_prices * --- 0..1 branches
organizations 1 --- * customers
suppliers 1 --- * purchase_orders 1 --- * purchase_order_items * --- 1 products
purchase_orders 1 --- * stock_receipts 1 --- * stock_receipt_items * --- 1 products

branches 1 --- * shifts 1 --- * shift_events
shifts 1 --- * sales * --- 0..1 customers
sales 1 --- * sale_items * --- 1 products
sales 1 --- * payments
sales 1 --- * refunds 1 --- * refund_items * --- 1 sale_items
sales 1 --- * sale_events
branches 1 --- * inventory_movements * --- 1 products
branches 1 --- * inventory_balances * --- 1 products
branches 1 --- * expenses
organizations 1 --- * business_settings
devices 1 --- * sync_event_receipts
organizations 1 --- * sync_change_log

Drift local financial transaction:
local_sale 1 --- * local_sale_items
local_sale 1 --- * local_payments
local_sale 1 --- 1 sync_outbox(event: sale.created)
```

Composite references or server constraints enforce same-organization relationships. A foreign key to a globally valid product UUID alone must never permit another organization's product to appear in a sale.

## 5. Role and permission matrix

`All` means organization-wide. `Branch` means assigned branches. `Own` means the employee's own shift/sales. A dash means denied. Permissions apply to backend actions and queries as well as navigation.

| Capability | Owner | Admin | Manager | Cashier | Inventory Staff |
| --- | --- | --- | --- | --- | --- |
| Organization and ownership settings | All | Limited business settings | — | — | — |
| Branch management | All | All | — | — | — |
| POS and ordinary sales | All | All | Branch | Branch | — |
| Sales history | All | All | Branch | Own | — |
| Customer lookup | All | All | Branch | Branch | — |
| Product/category management | All | All | Read | Read | Branch |
| Stock receiving, suppliers, purchases | All | All | Branch | — | Branch |
| Inventory adjustment | All | All | Branch, reason required | — | Branch, reason required |
| Approve discount/refund/void | All | All | Branch, policy limits | — | — |
| Manage shifts and inspect cash | All | All | Branch | Own | — |
| Financial reports | All | All | Branch | Own shift | Stock reports only |
| Invite employee | All | Limited roles | — | — | — |
| Assign Admin or change Owner | Owner only | — | — | — | — |
| Employee disable/role/branch changes | All | Non-owner/non-admin within policy | — | — | — |
| Reset employee PIN | All | Eligible subordinates | Branch cashiers | — | — |
| Security policy/device revocation | All | Delegated security scope | — | — | — |
| Audit log access | All | Security scope | Branch operational entries | — | Stock entries when authorized |
| Edit/delete audit or financial history | — | — | — | — | — |

This matrix describes the complete product target. Phase 3 implements online POS, own/authorized-branch sales and shifts, receiving/adjustment, and privileged discount/refund/void actions made by the current verified Owner/Admin/Manager actor. A Cashier cannot gain approval by entering a PIN; delegated manager approval and policy amount limits remain deferred. Fractional units, specialized disposal workflows and general Auth session-to-device binding remain **Coming Soon**. Phase 4 permits bounded signed offline sales in a separate workspace; discounts/refunds/admin remain online. Phase 5 adds enrolled-device administration and privileged MFA. The Phase 6A operations contract defines purchase, expense and report scopes. Shared catalog scope is organization-wide; mutable directory records enforce their explicit shared/branch scope. Owner/all-branch Admin can inspect organization audit, including historical inactive branches. Scoped Admin must cover the complete immutable prior/new branch snapshot for employee security events and every invitation branch for invitation events; null/first-branch shortcuts and incomplete legacy security snapshots do not grant access. Shared catalog/business audit remains explicitly organization-scoped. Operational audit access follows each implemented event's authorized branch and role policy.

Role hierarchy alone is insufficient: current actions check target role, branch and required reason. Configurable approval amount limits belong to the later policy/approval implementation and must not be implied by a Manager role check. Admin cannot promote themselves or grant Owner. Owner transfer is a separate, later high-assurance workflow. A normal invitation cannot assign Owner. Phase 2 employee-access RPCs prevent self-access changes and changes to Owner; Admin cannot change another Admin or grant all-branch access. A stale expected revision fails instead of overwriting a concurrent access change. No client can set `role`, `organization_id`, invitation acceptance, or audit author to gain authority.

RLS must be enabled on every exposed business table, including later tables. Membership lookups use narrowly scoped server helpers with fixed `search_path` and fully qualified objects where `SECURITY DEFINER` is needed. Ordinary membership, invitation and owner-role writes are denied; audited server actions perform them. Functions revoke default public execute grants and explicitly grant only intended roles. Views must honor RLS; never use an unrestricted definer view as a reporting shortcut.

Disabling a membership blocks subsequent cloud requests even if its access token has not expired. Device/session revocation adds a server check for device-sensitive actions; merely recording a device row is not enforcement. Offline revocation cannot be immediate on an unreachable device and is bounded by an expiring offline grant.

## 6. Authentication and first-owner flow

1. The initial configuration screen accepts Supabase project URL/client key through runtime configuration. If absent, explain **Not Yet Connected** and offer a read-only **DESIGN PREVIEW** of the adaptive shell. The preview has no fictional user, role, organization, session or usable business data. Live catalog data requires real authentication and authorized branch context.
2. A separate **Set up a new business** route offers first-owner onboarding. Ordinary employee login does not show Create Account. It displays **Need access? Contact your administrator.**
3. Collect business name, owner full name, email, password and confirmation; phone/address/logo are optional. Password and confirmation are validated in memory and never written to Drift, logs or analytics.
4. Supabase Auth signs up the owner candidate and sends verification email. The app does not create privileged membership before email verification. If an existing email is used, show a safe sign-in/recovery path without claiming ownership.
5. After verified sign-in, the client calls `bootstrap_organization`. In one server transaction, derive the owner from `auth.uid()`, verify confirmed email, validate business fields, create organization, Main Branch and Owner membership, and record the bootstrap audit entry. Never accept an owner user ID or arbitrary role from the request.
6. Bootstrap is idempotent for the verified setup attempt and serialized to prevent duplicate organizations from concurrent retries. Initial self-service organization creation needs rate/abuse limits. Joining an existing organization is invite-only; public owner onboarding never grants access to an existing tenant.
7. Load active memberships and authorized branches. Route into the authenticated shell only after identity and scope are known. Cache absence or network errors do not imply Owner access.

Supabase supplies password verification, verified email, access token expiry and token refresh. Secure-storage persistence is used instead of saving tokens in SQLite or ordinary preferences. **Remember this device** controls whether a refresh session is persisted; an unchecked session remains memory-only. Logout clears session secrets and sensitive presentation state. Cached sales/outbox remain protected and scoped; never discard unsynced business records as a side effect of logout.

The login field is labeled **Email or Employee ID** to match the product direction. Phase 1 supports email. Employee ID login remains **Coming Soon** until an authenticated-business-context, rate-limited server resolver exists; the app must not query an employee-email directory anonymously. Failed-login protection relies on Supabase Auth's configured rate limits, supported CAPTCHA where applicable, and backend controls; a local cooldown is usability feedback, not security. Do not claim configurable lockout until enforced and tested.

Phase 2 implements employee membership disable/enable through the audited access-change RPC; current membership checks reject subsequent business requests from a disabled employee. This does not disable the person's global Auth identity or access to another organization. Phase 5 adds enrolled offline-device tracking, whole-Navigator idle locking, provider global refresh-session revocation and privileged MFA enforcement. General Auth session-to-device binding and hardware-attested offline login remain unavailable. Already issued access tokens may remain valid until expiry unless application authorization checks reject the affected session; the app does not claim immediate revocation of those tokens.

## 7. Employee invitation flow

1. Owner/Admin opens Employees → Add Employee and enters full name, email, an allowed role, authorized branch assignments, optional employee ID/phone and an audit reason. Only Owner can invite Admin; employees never choose their own role.
2. Flutter calls the `employee-invitations` Edge Function with its user bearer token and a stable request UUID. The function validates that token with Supabase Auth `/user`; decoding JWT claims alone is not verification. Request fields/body size are bounded and browser origins are allowlisted.
3. The function calls `prepare_employee_invitation` using the same actor JWT, not the service-role credential. PostgreSQL rechecks verified identity, current active membership, target role and every branch, stores the role/scope in a seven-day pending invitation, and records audit. Organization/inviter/request uniqueness and the canonical stored request payload make retries idempotent; changing payload under the same request ID is a conflict.
4. The service-only `claim_invitation_delivery` RPC locks the record, rechecks the persisted inviter's current authority and marks it `sending`. Only the server then calls Auth Admin invitation email for a new identity. Only an authoritative Auth `email_exists` response permits an existing-user `/otp` email-link request with `create_user: false`. There is no duplicate public employee signup or client-held service key.
5. **Supabase Auth owns the expiring, single-use email action token and validates it before issuing a signed authenticated session.** NexaPOS stores no separate clear organization token or invitation-token digest. The invitation UUID is a resource identifier, never an acceptance credential. The action URL uses server-configured, allowlisted callback destinations and is never returned/logged by the function.
6. Service-only `finish_invitation_delivery` records Auth request acceptance/rejection using the matching delivery claim. `sent` means Auth accepted the email request, not that an inbox received it. Unknown outcomes/timeouts remain `sending`; a repeated request does not dispatch another uncertain email. Explicit rejection becomes `failed` and can be retried with the same request. Phase 6D supplies administrator history, exact original-creator retries and audited durable revocation. Operational reconciliation of permanently ambiguous sends remains follow-up work.
7. After Auth validates the email action and supplies a verified session, the app's invitation inbox calls `list_pending_invitations`. The server derives the current recipient email from `auth.users`, checks current inviter authority, and returns only that identity's unexpired, unrevoked, `sent`, unused invitations. A verified recipient may also discover their invitations after normal sign-in; possession of the UUID alone grants nothing.
8. New invited identities with no Auth password create/confirm one through Auth; existing accounts retain their password. The app blocks this operation during a recovery-only session and rechecks identity after asynchronous password update. The server independently requires a verified recipient and an established Auth password.
9. Flutter calls `accept_employee_invitation` with only the invitation ID. In one transaction, PostgreSQL rechecks the matching verified email, delivery/expiry/unused state, current inviter authority and stored branch assignments, creates membership using the stored role, marks accepted and appends audit. Clients cannot supply recipient identity, role or branch overrides. Replayed acceptance fails safely.

This Phase 2 flow is implemented in source with adapter/handler/SQL test boundaries. Actual Supabase deployment, Auth delivery for new and existing identities, configured callback handling and end-to-end acceptance remain **Not Yet Connected** until a real project is configured and tested. PostgreSQL serializes new invitations per organization and limits them to 20 per rolling ten minutes and 200 per rolling 24 hours; known request status retries remain available. Rejected dispatch retries have a ten-second cooldown and the function reports throttling as HTTP 429. Supabase Auth's project/email limits remain independently required.

Phase 6D adds **Employees → Invitations**. Safe server documents expose scoped invitation history/detail, literal search, status and recorded delivery metadata, with current action capabilities. Owner/Admin reads and revocation cover the complete original branch assignment set, including inactive branches; an Admin cannot revoke an Admin target. Only the original creator with current creation authority receives the exact retained retry payload, and only prepared/failed requests can be retried explicitly. No `sending` claim is reclaimed or automatically resent. Revocation preserves its original request UUID, revision and reason in the encrypted operation journal before dispatch, and repeats current authorization/MFA checks before replay. A later denial after uncertainty does not prove that the earlier revocation failed. Accepted/revoked/expired status takes precedence over recorded email request state; revocation blocks acceptance but cannot recall an already requested email. Legacy history with missing branch scope remains read only for an authorized Owner/all-branch Admin. See [INVITATIONS.md](INVITATIONS.md).

## 8. Forgot-password and password-reset flows

**Request:** Forgot Password? → email → `resetPasswordForEmail` with an allowlisted recovery destination → neutral confirmation:

> If an account exists for this email, recovery instructions have been sent.

Responses must not disclose account existence. Auth availability errors can say that the service is temporarily unavailable without changing wording based on identity. Do not return raw Auth exceptions or include tokens in logs. Password reset is online-only.

**Reset:** secure Supabase email link → configured HTTPS recovery landing/app link → Auth verifies recovery session → dedicated new-password/confirm-password form → update authenticated password → return to sign-in or explicitly authorized session → server audit event.

The reset form requires a verified recovery-session state; possession of an arbitrary route name or query parameter is insufficient. Link expiry and reused links produce safe errors. Android App Links and Windows URI/HTTPS recovery handling require registered platform destinations, Supabase redirect allowlists and an actual callback test. A fallback HTTPS recovery page is a later deployment component; it must not be presented as working merely because a URL is configured.

Phase 5 implements ordinary Owner/Admin policy-driven MFA enforcement, explicit global refresh-session revocation and notices derived from recorded backend security actions. Recovery-specific step-up and password-changed/suspicious-login email delivery remain separate integrations. A password-update response alone cannot truthfully assert that every old session was revoked or that a security email was sent. Authoritative audit comes from a server-confirmed action/Auth event pipeline rather than trusting a client-written success record. Supabase Auth audit evidence can be retained immediately; application audit ingestion is a separate integration.

Never use security questions, personal-history questions, locally stored passwords, or passwords disclosed by administrators.

## 9. Employee PIN and PIN-reset flow

PINs are separate from main passwords and do not establish organization membership. The preferred minimum is a configurable 6–8 numeric digits; a short PIN has limited entropy and requires strict server/device attempt limits and temporary lockout. Use an audited Argon2id/scrypt-class verifier with per-record salt in a server-only table, plus a server-held pepper if adopted; never plaintext, reversible PIN storage, unsalted SHA hashes, or PIN values in analytics.

Manager approval validates the approving manager's identity, active role, authorized branch and requested action/amount. Entering any syntactically valid PIN must never approve an action. Cashier PINs cannot confer manager authority.

Forgotten-PIN sequence:

1. Manager/Admin opens the employee profile and requests Reset PIN with a reason.
2. Server checks actor/target scope, records the reset request and audit, and invalidates the old verifier/authorization as policy requires.
3. Employee receives or opens a single-use, short-lived reset grant and authenticates according to policy.
4. Employee supplies the new PIN; server stores only the new verifier, consumes the reset grant and records completion audit.
5. The old PIN is never displayed or emailed. Offline verifier grants, if supported later, are replaced only after a trusted refresh.

PIN unlock and approval remain **Coming Soon** through Phase 3. Current privileged online actions use the acting user's authenticated membership, with no Cashier-side PIN substitute. Offline PIN support requires OS-keystore-backed local protection, tamper/rate-limit assumptions and expiring authorization grants; a database hash by itself is insufficient. No dummy fixed PIN or local role toggle is allowed.

## 10. Email architecture and template design

Define an `EmailService` boundary for invitation, email verification, recovery and future security notification requests. The initial `SupabaseEmailService` delegates verification/recovery to Supabase Auth. Privileged invite dispatch lives in a server counterpart because the Auth Admin API requires server credentials. Password-changed and suspicious-login notifications remain **Placeholder** until an authoritative backend/Auth event pipeline sends them.

```text
Flutter auth/use-case request
  → EmailService / Supabase auth adapter
  → Supabase Auth built-in email
  → employee inbox

Privileged employee invitation
  → authenticated server function
  → authorization + invitation record
  → Supabase Admin Auth invitation email (new identity)
       or Supabase Auth email sign-in link, create_user: false (existing identity)
  → Auth validates its own email action token
  → verified JWT + server-owned pending invitation RPC
  → transactional membership acceptance

Later provider replacement
  → server EmailService
  → Resend / Postmark / SendGrid / Amazon SES
```

Do not integrate a future provider during the current phases. Auth action tokens still originate from Auth; switching provider does not mean the app manufactures verification links or gives an invitation UUID credential status. The Phase 2 server adapter uses Supabase Auth's built-in sender for invitation and existing-identity email-link delivery, and records submission separately from recipient acceptance. Supabase default sender delivery/rate limits must be acknowledged during deployment testing; project-specific production email readiness is not established by a successful local UI test.

Placeholder templates use the same blue/navy branding, a readable title, a single call to action, expiry/security text and plain-text fallback. The following designs may be stored as previews; they are not deployed custom email infrastructure:

| Template | Subject / content direction | Status |
| --- | --- | --- |
| Employee invitation | “You are invited to [business]”; inviter/business, branch, invitation expiry, Accept Invitation | Built-in Auth delivery; branding preview |
| Email verification | “Verify your NexaPOS email”; Verify Email, ignore-if-unrequested text | Built-in Auth delivery; branding preview |
| Password reset | “Reset your NexaPOS password”; Reset Password, expiry, do-not-share guidance | Built-in Auth delivery; branding preview |
| Password changed | “Your NexaPOS password changed”; timestamp, contact-admin guidance | Placeholder |
| Suspicious login | “Review a recent NexaPOS sign-in”; device/time, review sessions | Placeholder |

`security@nexapos.com` is an example future sender, never a claim that the domain or mailbox is configured. No secrets or real customer data belong in previews.

## 11. Offline architecture

Drift uses SQLite on both platforms. The target offline transaction for a completed sale writes the header, items, payment, stock effects and outbox event together. The legacy foundation writes local sale/item/payment snapshots and events. Phase 4 adds authorized atomic capture with signed evidence, local stock effects and separate append-only server acceptance. Ordinary local history without genuine authorization cannot be uploaded through that path. Phase 3 online checkout uses a separate PostgreSQL transaction and its own authenticated request-idempotency record. It must not mark a Drift outbox event synced or imply that local and online protocols are interchangeable. If either transaction fails, none of that transaction's changes should remain. Confirmed online sale acceptance and receipt identity survive a lost response through replay of the same request; local durable events survive restart independently.

Cache supported: products, categories, prices, inventory snapshots, minimal customers, sales/items/payments, shifts and pending sync. Show the last successful sync and pending record count. Never label cached quantities as live cloud stock while offline.

Offline operation requires prior verified online enrollment and a server-issued, signed, device-bound, short-lived grant specifying user, organization, branch, allowed actions, policy version and expiration. Phase 5 selects actual SQLCipher for native SQLite files and separately stores random file keys in the OS vault. Target-device vault, backup, screenshot and lost-device behavior still require platform acceptance tests; secure token storage alone does not establish those protections.

Phases 1–3 established durability and online operations. Phase 4 adds bounded grant-backed offline sales; new offline account/PIN sign-in remains **Coming Soon**. Current checkout, shift and inventory writes require an authenticated online response; a failed request does not fall back to local financial acceptance. The app never treats a network error as a fresh membership. Phase 4 resumes a separate stored grant workspace for the same verified remembered identity; new offline checkout permits only actions in an unexpired grant; invitation, role changes, owner setup, password resets and security-policy changes remain online-only. Refund/void/discount approvals need a validated manager grant or return an explicit online-required result.

Logout or switching business closes the scoped database and clears secrets/UI state without deleting unsynced sales. Administrative device revocation blocks new online operations immediately through backend checks; offline behavior expires with its grant. Product/customer changes may wait for online validation, depending on policy. Multi-device offline sales can temporarily oversell stock, so stock policy and reconciliation must make that limitation explicit.

## 12. Append-only, idempotent synchronization

Outbox states: **PENDING → SYNCING → SYNCED**; retries transition back to **PENDING** with a delay, while permanent rejection becomes **FAILED** and requires review. `SYNCING` is a leased state; an expired lease after a crash is safely recoverable.

Each event has a UUID idempotency key created once, schema version, organization/branch/device/user scope, event type, payload and canonical payload digest. Generate financial document UUIDs and identifiers before committing the local transaction. Retry the same event and document identifiers; never generate a fresh sale ID on a transport retry.

Phase 4 offline-event server ingestion sequence (see PHASE4_CONTRACT.md for the actual bounded wire contract):

1. Verify session, active membership, branch permission, device status, event schema and business invariants. Do not trust the actor ID or role in the payload.
2. Lock/check the unique organization/device/event ID in `sync_event_receipts`.
3. If already accepted with the same digest, return the original result without another sale, payment, stock movement or audit entry. If the same key carries a different payload, reject as a conflict.
4. In one PostgreSQL transaction, validate amounts/quantities, insert immutable sale/items/payments, append inventory and audit entries, update the inventory projection and persist event receipt.
5. Mark the local event synced only after confirmed server acceptance. If the response is lost, a retry gets the original result.

Concurrent ingestion is protected by unique constraints and transactional handling; “check, then insert” without a unique constraint is insufficient. Failed authorization, unsupported schema and invalid financial totals are not silently retried forever. Display a sanitized reason and preserve the record for repair. Backoff uses jitter; sync batches are bounded and preserve dependencies such as opening shift before sale. Pull applies revisions/tombstones and advances its cursor in one Drift transaction.

Financial documents are never merged through last-write-wins. A refund/void/correction is a new event referencing the original accepted document. Mutable catalog/settings data uses expected revision and explicit conflict resolution. Current online receipt identity is allocated by the server. Phase 4 provisional receipt/event identity is retained across ingestion and linked to an independently allocated server receipt without editing the local financial document; online receipt allocation alone does not solve that offline requirement.

Network-interface availability is only a hint. A “Wi-Fi connected” signal does not prove Supabase is reachable; actual authenticated requests decide reachability. Sync errors never delete unsent data. Manual retry reuses the existing event key.

## 13. Windows UI architecture

Brand tokens: white/light canvas, dark navy sidebar, bright blue primary action, restrained teal accents, rounded cards, subtle shadows, clear typography, generous spacing and large readable totals. Use a centralized `BrandConfig` for `app_name`, `tagline`, `logo`, `primary_color`, `secondary_color`, and configurable `business_name`. Business name is tenant data after sign-in, not a hardcoded demo retailer.

Desktop shell has a stable left navigation rail/sidebar and a large content area. Navigation: Dashboard, POS, Sales, Products, Inventory, Purchases, Suppliers, Customers, Employees, Shifts, Expenses, Reports, Audit Logs, Notifications, Settings. Routes are filtered using verified permissions and enforced again in use cases/backend.

POS layout: sidebar → center search/barcode/categories/product grid → right cart panel with subtotal, discount, tax, total and payment. Cash is a real locally recorded tender; Card/GCash/Maya/Other must be labeled **Manual Payment Verification** and require an operator-confirmed reference when appropriate. Payment-service capabilities expose whether an integration is connected. No animation or simulated success response may imply provider authorization.

Inventory/products use readable sortable tables, clear stock status, consistent empty states and explicit loading/error/retry states. Dashboard shows real data or a purposeful empty/not-connected state. Financial KPIs cannot be invented to decorate the page.

Keyboard support: predictable tab order, focused search, enter/escape handling and discoverable action shortcuts. Phase 6C implements opt-in USB/Bluetooth keyboard HID scanner capture with framing/timing/focus guards; actual hardware validation remains a platform test. A manual barcode field remains usable. Desktop resize must not obscure cart totals or block keyboard interaction.

## 14. Android UI architecture

Bottom navigation: Home, POS, Sales, Inventory, More, filtered where the employee lacks access. More exposes Products, Customers, Suppliers, Employees, Reports and Settings according to permission. Tablet widths can adapt to navigation rail and a split POS/cart layout; phone widths use compact product cards and a dedicated cart screen/sheet.

Touch targets, typography and spacing remain readable. Avoid shrinking the desktop table to phone width; use cards and detail screens. Keep the active branch, user, connection state and pending-sync state accessible. Phone camera barcode scanning requires explicit camera permission and a supported scanner adapter; it is **Coming Soon** until implemented/tested. Manual barcode entry remains available.

Authenticated flows, design tokens, permission checks, repository interfaces and domain rules are shared with Windows. Platform differences live in adaptive shell/widgets and scanner/device services, not duplicated business rules.

## 15. Recommended packages and purposes

Explain these choices before installation and pin compatible resolved versions in the lockfile. Add only packages needed by the current phase; a future package entry is not permission to imply its integration is complete. The onboarding toolchain is pinned to **Flutter 3.44.0 / Dart 3.12**, obtained through a digest-pinned official-source-compatible build image; application SDK constraints must match Dart 3.12. A reachable compatible release is preferable to claiming an unavailable toolchain is installed.

| Package/tool | Purpose | Phase |
| --- | --- | --- |
| Flutter SDK / Dart SDK | Windows and Android build/runtime toolchain, bundled Material 3 | 1 |
| `flutter_riverpod` | Predictable application state and dependency injection | 1 |
| `supabase_flutter` | Auth session, authenticated data and Supabase adapters | 1 |
| `flutter_secure_storage` | OS-backed persistence for refresh session/installation secrets | 1; platform configuration verified |
| `drift` | Typed SQLite schema, queries, transactions and migrations | 1 |
| `drift_dev` + `build_runner` | Development-only generation of Drift database code | 1 |
| `sqlite3` 3.x native assets | Cross-platform SQLite runtime for current Drift; do not add deprecated `sqlite3_flutter_libs` | 1 |
| `path_provider` | Writable application-data location on Windows/Android | 1 |
| `path` | Platform-safe local paths | 1 |
| `connectivity_plus` | Network-interface changes as a reachability hint | 1 or use typed request failures initially |
| `uuid` | Stable local event/document identifiers | 1 |
| `crypto` | Canonical payload digests for sync; never password/PIN hashing | 1 |
| `intl` | Locale-aware dates/currency display | 1 or first financial UI phase |
| `go_router` | Declarative authenticated routes and deep-link routing | Adopt if routing scope warrants it |
| `mobile_scanner` | Android camera barcode capture | Later hardware phase |
| `device_info_plus` | Platform/device display information, never identity proof | Later device-management phase |
| `flutter_test` / `integration_test` / `flutter_lints` | Core policy/widget tests, end-to-end checks and static analysis | 1 |
| `pdf` / `printing` | Receipt PDF rendering and native system printing/PDF handoff | 6C; physical platform acceptance remains outstanding |

SQLite 3.x native support and Flutter minimum versions must be checked against the selected package releases before choosing implementation. Windows secure storage requires its OS-specific setup and validation; Linux host checks do not prove Windows-keystore behavior. Phase 5 selects SQLCipher for native business/journal files, with independent retained OS-vault keys and encrypted legacy recovery. Target-device key lifecycle and Windows behavior still require platform acceptance. Argon2id verification belongs server-side; do not add a simplistic client hashing package as a substitute.

Future email/payment SDKs are intentionally absent until requested. `PaymentService`, `CashPaymentService` and `ManualDigitalPaymentService` describe counted/operator-confirmed evidence; the online checkout boundary validates and records that evidence. `GCashPaymentService`, `MayaPaymentService`, `CardTerminalService`, and provider-specific `EmailService` adapters remain capability declarations/documented placeholders until real credentials and verified integrations exist.

## 16. Development phases and acceptance gates

### Phase 1 — runnable foundation

Deliver modular Flutter Material 3/Riverpod application, centralized branding, adaptive Windows/Android shell, polished login/first-owner/forgot/reset-password views, real Supabase auth adapter when configured, secure session persistence, honest connection states, Drift durable cache/outbox schema, versioned PostgreSQL access/schema foundations and documented deployment configuration. The unconnected **DESIGN PREVIEW** is read-only and contains empty module states; it has no role selector or mock session. Real authenticated role/context controls live navigation. Placeholder modules show their status rather than fake records. Add email-template design previews and disabled settings integrations.

Required checks: format/analyze, meaningful auth/permission/widget/database durability tests, generated Drift code validation, secure configuration review, and executable host-compatible development build. Verify a local outbox survives close/reopen and that unavailable cloud configuration cannot establish a privileged session. Validate RLS/grants against a real local/deployed PostgreSQL/Supabase instance when available.

Windows desktop builds require Windows Flutter tooling; Android builds require SDK/JDK and accepted Android SDK licenses. A Linux build or Flutter web preview is development feedback and does not replace Windows/Android compilation or device tests. Report those missing checks explicitly. Real email delivery/recovery callbacks require a configured Supabase project and allowed redirect destinations; they remain **Not Yet Connected** until exercised.

Explicitly deferred from Phase 1: full checkout, financially accepted sync, employee invitation deployment, employee-ID resolver, manager/PIN authorization, secure offline session grants, OS-specific hardware verification, account/session/device enforcement UI, provider APIs and production data encryption. Phase 2 now implements employee membership status/access administration and invitation source; its live deployment remains outstanding. Architecture/schema for later paths is not a claim of functional completion.

### Phase 2 — organization and employee administration

Implemented source now includes products/categories with search/paging/revision-checked save, supplier/customer directories, scoped employee roster, role/status/branch management, Supabase-email invitation orchestration, recipient invitation inbox/password setup/acceptance, audited business/currency/tax/receipt settings and authorized audit viewer. Direct catalog/directory/member/settings mutations are denied to ordinary clients; validated RPCs derive the actor and write immutable audit. Product cost is not exposed to Cashiers.

Required checks cover cross-organization/branch access, shared-versus-branch directory rules, role escalation and self-change, optimistic conflicts, invitation replay/expiry/wrong recipient, disabled membership/inviter, delivery claim idempotency, rejection and unknown Auth outcomes, new versus existing identities, and recovery/identity-switch restrictions. Local PostgreSQL and adapter tests verify their respective boundaries. Complete the live acceptance gate by deploying migrations/function to a real non-production Supabase project, configuring server-only secrets/origins/callbacks and exercising Auth/PostgREST/email end to end. Until then the feature is implemented but **Not Yet Connected**.

Phase 3 adds the online checkout/stock workflows deferred by Phase 2. Subsequent phases implement signed offline authorization and security hardening, Phase 6B branch maintenance, and Phase 6D invitation administration. Image/logo upload, operational reconciliation of permanently ambiguous invitation sends, additional production invitation-abuse controls and general Auth session/device binding remain follow-up work. Successful local management tests do not establish live email or platform behavior.

### Phase 3 — POS, shifts and inventory ledger

Implemented source adds online catalog search/grid and barcode text lookup, cart/calculations, authenticated branch shifts, cash and manual Card/GCash/Maya/Other tender, immutable sales and receipt views, branch stock receiving/adjustments, and privileged compensating refund/void documents. These are online repository/RPC workflows. A configured, deployed Supabase project is still required to use them with business data; no preview generates completed sales or receipts.

Current financial rules:

- One verified active membership and assigned active branch bounds each operation. Cashiers inspect their own shifts/sales; eligible supervisors inspect authorized-branch records. Authorization is rechecked even for an idempotent replay. Branch switching must not apply an in-flight cart, tender or request to another branch.
- Allocate a stable request UUID before submitting a write and retain its unchanged payload through retries. Server request identity includes organization and actor. Concurrent duplicates return the original accepted document identity without another financial document, stock movement or audit entry; changed fields under that identity fail as a conflict. Current projections such as subsequent compensation totals or shift cash may differ from their first view without rewriting accepted history. Timeout is an unknown outcome, not proof of failure or permission to create a new request UUID. The native operation journal preserves pending request identity/payload through restart and scope changes; it is not an offline checkout grant or a synced Drift financial event.
- Quantities are positive whole units. Monetary values use exact integer two-decimal minor units for PHP/USD/EUR/GBP/AUD/CAD/SGD only. The server recomputes totals from current validated product/settings revisions and immutable accepted snapshots.
- Order discounts require a reason and the current verified Owner/Admin/Manager actor. Allocation follows sorted product UUIDs with cumulative proportional floor differences; tax is exclusive, rounded half up per discounted line. Cashiers cannot claim that a manager PIN approved a discount.
- Counted cash records the amount applied, amount received and change. Noncash tender requires an operator confirmation and reference and is stored as manual evidence. The system does not capture, settle, authorize or remotely refund card/e-wallet money. Operators perform actual external money movement separately.
- Checkout locks products in a stable order and appends sale, line/payment snapshots, stock movements, receipt identity, request result and audit in one transaction. Branch stock cannot become negative. A rejected transaction leaves no accepted financial or inventory partial state.
- Refunds and voids reference accepted immutable history and append compensation. The server bounds cumulative quantity/value by the original line and payment, preserves cumulative rounding, and requires a reason and a current privileged actor's open shift. A void is allowed only for an untouched full sale. The original receipt and amounts remain unchanged. A separate explicit `return_stock` choice controls inventory restoration: its default is false; true means the operator confirms the selected goods physically return to the original branch. Money compensation never silently fabricates a physical return.
- Receiving records supplier/product/cost evidence and adds branch quantity; recorded receiving cost does not overwrite mutable catalog cost. Owner/Admin/Manager/Inventory Staff can receive within their branch scope; current adjustments require Owner/Admin/Manager. Receiving/adjustment requires its own idempotent request and reason. Cost evidence remains server-private.
- One open shift per organization/actor is allowed across branches. Shift currency is immutable. Cashiers can close their own shift; the backend also permits an authorized Owner/Admin/Manager to close an assigned-branch shift. New checkout must agree with the current business settings/product currency; a currency change requires an appropriate close/reopen rather than rewriting an existing shift or accepted sale. Shift close records counted cash, server-derived expected cash and variance; expected cash is opening plus applied cash sales minus cash compensation in that shift, and manual digital tender does not become counted cash. Cash-in/out events remain deferred.

Required checks cover exact tax/discount/partial-refund rounding, replay/concurrent idempotency, changed-payload conflict, own-cashier and cross-branch access, disabled memberships, direct table mutation denial, stock underflow/transaction rollback, payment evidence, immutable receipts and history, currency changes and shift-close variance. Local SQL/repository/widget tests do not establish live PostgREST behavior or platform hardware. Validate the deployed migrations and actual multi-device concurrent checkout against a real non-production project before commercial use.

The Phase 3 checkpoint deferred offline financial ingestion/grants, purchases/transfers, printer adapters, expenses and reporting; Phases 4–6C now implement those source workflows. Measured fractional products and variable currency precision, saved/held carts, provider payment APIs, camera barcode scanning, cashier-to-manager PIN approvals, policy approval ceilings and accounting/valuation remain later work. Current online checkout supports split operator-recorded tender; that does not connect a provider.

### Phase 4 — resilient offline business operation

At the Phase 4 checkpoint, implemented source included minimal Ed25519 device enrollment, independently pinned signed grants, frozen cost-free caches, explicit bounded offline sales and payment intents, additive v2 durability, strict idempotent ingestion, stock deficit/review records, revisioned pulls/tombstones and signed final release. Phase 5 subsequently adds native database encryption, individual partial-tender durability and lost-key administrative resolution. Legacy events remain unchanged and excluded from authorized upload. Offline discounts/refunds/administration/shift lifecycle remain online. New offline password/PIN sign-in, hardware attestation and real payment providers remain unavailable. Live deployment, platform behavior and commercial operating controls remain acceptance gates.

Device-bound grants first require minimal server-backed device enrollment, proof-of-possession keys and a tested signature/key/expiry lifecycle. Include these prerequisites in Phase 4 rather than treating a device UUID or name as identity proof while waiting for Phase 5 hardening. The Phase 3 operation journal and request receipts remain separate from offline authorization and event acceptance.

The bounded implementation supplies signed device grants, local transactions/authorized ingestion, idempotent acceptance, crash recovery, backoff, revisioned cursor/tombstone downloads and explicit conflict/reconciliation views. Phase 5 adds audited lost-key resolution for revoked devices with expired signed grants. Unknown paid exposure and source-backed stock deficits remain review obligations; an administrative resolution does not invent a receipt or discard paid evidence. Test dropped responses, duplicate/concurrent requests, revoked memberships, expired grants, interrupted migrations, multi-device stock conflicts and scope switching without lost pending sales.

### Phase 5 — security and platform hardening

Extend the Phase 4 minimal server-verifiable enrollment with device management and session/device revocation, audited PIN reset/approval, idle locking, tested secure storage, local data encryption/key lifecycle, MFA enforcement for privileged accounts and security notification pipeline. Test Windows keyboard/scanners, Android camera scanning/links, accessibility, responsive layouts and release signing.

Implemented Phase 5 source is described in [PHASE5_CONTRACT.md](PHASE5_CONTRACT.md). Native SQLCipher migration, durable partial tender recovery, audited device/grant review, provider TOTP/AAL2 policy, PIN lifecycle and idle locking are locally tested. Financial PIN delegation, general Auth session-device binding, physical camera/scanner/printer/vault behavior and production signing remain acceptance/integration gates. Phase 6A implements purchases, expenses and authoritative reports, as selected by the user.

### Phase 6 — commercial integrations and operations

The user selected purchases, expenses and reports as the first slice. [PHASE6_CONTRACT.md](PHASE6_CONTRACT.md) defines immutable purchase orders with stock-linked partial receipts, recorded external/own-drawer expenses and compensating reversals, and server-posted sales/inventory/expense reports. These workflows retain the existing current-actor authorization, exact integer arithmetic, historical currencies, encrypted request journal and explicit unresolved-request recovery.

Phase 6B implements branch maintenance, stock transfers and supplier stock returns. Phase 6C implements receipt PDF/native system printing and keyboard HID capture. Phase 6D implements invitation administration and durable revocation. These source capabilities have local acceptance checks; live Supabase/email, target-device printing/scanning/vault behavior, Windows builds and release signing remain separate acceptance gates.

Improve branded email, real GCash/Maya/card-terminal APIs, SMS/push, multi-branch replication, backup/restore, accounting, loyalty, attendance and analytics. AI sales insights are a later optional capability. Each feature requires explicit connection status, provider-specific failure handling, credentials outside Flutter, operational monitoring and separate acceptance tests.

## 17. Settings and capability truthfulness

| Section | Fields/capabilities | Early behavior |
| --- | --- | --- |
| Business | Business name, logo storage path, address, contact | Revision-checked Phase 2 tenant settings when connected; logo upload not integrated |
| POS | Currency, tax basis points, receipt footer | Revision-checked business settings feed online receipt snapshots; receipt copies use system printing/PDF output; physical printers need acceptance |
| Security | Session timeout, MFA, password policy, approved devices | Enforced capabilities distinguished from Coming Soon controls |
| Email | Current provider: Supabase Auth Email; future Custom SMTP / Resend / Postmark | Current delivery depends on project configuration; future providers disabled |
| Payments | Cash, manual Card/GCash/Maya, future provider connections | Manual verification explicitly labeled; APIs disabled |
| Future services | SMS, push, backup, accounting, loyalty, attendance, advanced analytics/AI | Coming Soon |

Capability state is centralized (`available`, `manual`, `not_connected`, `coming_soon`) so every page uses consistent wording. The UI must not save a decorative toggle and imply server enforcement. Business data is empty until real data exists; test fixtures belong only in tests or explicitly labeled previews.

## 18. Validation, configuration and operational boundaries

- Keep public client configuration separate from private backend secrets. Track only examples with blank values. Never commit token-bearing callbacks, password/PIN inputs or service credentials.
- Validate authentication with a real non-production Supabase project before claiming connection. Check new/existing employee invites, neutral recovery responses, real password update, callback expiration, token refresh and sign-out semantics.
- RLS tests cover every role, disabled membership, malicious role assignment, organization/branch mixing, audit mutation and direct financial update/delete attempts. SQL migrations require an actual database execution test; file presence is insufficient.
- Preserve financial/audit history and unsynced data through restarts, retries, migrations and logout. Backups require tested restoration, not a success banner.
- Auth and sync error messages are sanitized and useful. Security logs do not contain passwords, PINs, refresh tokens, private keys or invitation/recovery URLs.
- Offline approval/revocation limitations, deployment prerequisites and platform tests remain documented until their phase gate passes.

Use the existing isolated cloud checkout for development. Do not create another worktree unless the user requests it. Save reusable installation/startup instructions without embedding secrets, and report exactly which checks were run and which platform/cloud integrations remain unverified.

Phase 6B adds branch maintenance and physical stock logistics through migrations 013/014. Read [PHASE6B_CONTRACT.md](PHASE6B_CONTRACT.md). Current authorization and privileged MFA precede every replay; dispatch requires both endpoints, receipt requires its destination and transit return its source. Supplier returns reference original purchase receipt quantities and costs and do not pay suppliers. Branch deactivation blocks retained grants, unresolved stock/transit, open shifts and outstanding orders. Codes remain immutable, referenced product units cannot change, and scope changes reload server membership. Preserve encrypted logistics intents, original evidence and UUIDs through uncertain responses. Direct service branch/catalog writes are revoked; use validated RPCs.

Phase 6C adds receipt document/output and keyboard HID scanning without backend migrations. See [PHASE6C_CONTRACT.md](PHASE6C_CONTRACT.md). The PDF renderer preserves original receipt snapshots and provisional identity, uses retained licensed fonts and finite pagination, and makes no financial mutation. `pdf` and `printing` are pinned through the lockfile; system handoff requires a current source and access-lock generation. Native printing/PDF handlers and physical scanner devices require target-platform testing.
