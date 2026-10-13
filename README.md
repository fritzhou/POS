# NexaPOS

**Smart Retail & Cafe POS** — Flutter for Windows desktop and Android phone/tablet.

The complete design was documented before implementation in [ARCHITECTURE.md](docs/ARCHITECTURE.md). This repository implements **Phases 1–6D: foundations, online/offline operations, security hardening and daily operations**. It is not a finished commercial POS.

## Included in Phase 1

- Shared Material 3 branding; navy desktop sidebar, adaptive tablet navigation, phone bottom navigation, dashboard, POS/cart layouts, and settings.
- A clearly labeled, read-only **DESIGN PREVIEW · Not Yet Connected**, with empty business data and no fabricated user, organization, transactions, or role.
- Supabase authentication adapter, employee sign-in UI, separate first-owner setup, email verification boundary, verified server owner bootstrap, organization selection, neutral recovery, and recovery-only password reset.
- OS-backed session/PKCE storage with explicit remembered-device consent. Actual Windows/Android vault and callback behavior still need platform integration tests.
- PostgreSQL migrations and tenant/branch RLS, backend-controlled memberships, disabled-member enforcement, server-derived audit, and idempotent first-owner setup.
- Scoped Drift/SQLite cache tables, atomic local financial snapshots plus immutable outbox, payload digests, leases, retries, and restart recovery. Phase 4 adds a separate signed authorization and ingestion path; legacy events never gain invented provenance.
- Replaceable email and payment interfaces. Provider APIs remain unconnected; online checkout uses cash or operator-confirmed manual payment evidence.
- Five clearly marked HTML email-template placeholders, plus documented future integration boundaries.

## Included in Phase 2

- Products and categories: server search/filter/paging, exact prices and reorder quantities, SKU/barcode uniqueness, revision-checked editing/deactivation, and server-masked cashier costs.
- Branch-scoped suppliers and customers, with responsive tables/cards and revision-checked forms.
- Owner/Admin employee roster, audited role/status/branch changes and server-authorized invitation submission. New and existing Auth identities use Supabase's built-in Invite/Magic Link email paths.
- Verified-email invitation inbox and acceptance, password setup where required, and a fresh server membership reload. Invitations never let an employee choose their own role.
- Business identity, currency/tax/receipt defaults and a read-only, paginated audit viewer. Updates wait for server confirmation and stale edits require a reload.
- Incremental production migrations, isolated PostgreSQL policy tests, real HTTP-adapter tests and deterministic Edge Function tests.

## Included in Phase 3

- Online POS with branch selection, product search/categories, exact barcode lookup, stock-aware whole-unit cart, optional customer, and authorized discounts with a reason.
- Exact integer prices, proportional discounts and line tax shared with PostgreSQL. Checkout supports PHP, USD, EUR, GBP, AUD, CAD and SGD; product and shift currencies must match. Currency changes do not convert existing prices.
- Cash drawer opening/closing, server-derived expected cash and counted discrepancies. Cash plus split Card/GCash/Maya/Other tenders require explicit manual evidence; they do not contact a provider.
- Atomic checkout creates immutable receipt/items/payments and stock movements under current backend authorization. A failed transaction rolls back together; repeating the same authorized request ID returns the existing result.
- Branch stock receiving, authorized reasoned adjustments, balances and append-only movement history. Checkout cannot create negative stock.
- Receipt history, partial refunds and full untouched-sale voids as separate compensating records. Original payment amounts cap refunds; physical stock is restored only when explicitly confirmed returned.
- A separate durable SQLite operation journal preserves uncertain online requests and their original IDs across restart. A later denial does not establish whether an earlier attempt committed. This journal does not grant offline checkout authority or synchronize the Phase 1 outbox.

## Included in Phase 4

- Separate authorized offline workspace with explicit device consent, Ed25519 enrollment proofs, independently configured public trust keys, and bounded signed grants for an already-open online shift.
- Cost-free frozen catalog/settings, search/barcode/cart, exact cash/manual tender, immutable provisional receipts and signed events. No automatic offline fallback, new offline password/PIN sign-in, discounts, refunds or shift administration.
- Additive Drift v2 migration preserves every legacy receipt/event, attempt and lease. Local stock effects remain until an authoritative revision absorbs them; accepted server links never rewrite provisional receipts.
- Durable payment/preparation intents, retained request IDs, leased bounded synchronization, strict acceptance validation, retry/export/review, revisioned catalog/stock pulls and tombstones.
- Service-only ingestion rechecks current authority and original-snapshot financial math. Source-backed offline overselling records a stock deficit for reconciliation; ordinary online checkout still refuses insufficient stock. A signed final release is required before closing the shift.
- Cold resume uses only the same remembered verified identity and independently verified grant/cache/device/time. Recovery, logout, known permission denial, clock rollback and incomplete cache block new offline capture.

These workflows require a configured Supabase project and deployed migrations/function. **Live Supabase and email delivery are Not Yet Connected in this environment.** Preview data stays empty and its actions stay disabled. Confirmed email submission does not establish inbox arrival; ambiguous outcomes require manual review.

Phase 5 adds genuine SQLCipher business/journal encryption and encrypted legacy recovery, whole-Navigator idle/background locking, same-account online unlock, provider refresh-session revocation, real TOTP enrollment and server Owner/Admin AAL2 policy, audited employee PIN reset/change, scoped offline-device management and explicit lost-key administrative resolution. In-app notices derive from backend events. Each confirmed offline partial tender is durable before display, with original checkout recovery. See [PHASE5_CONTRACT.md](docs/PHASE5_CONTRACT.md), [LOCAL_SECURITY.md](docs/LOCAL_SECURITY.md), [MFA.md](docs/MFA.md), [PIN_SECURITY.md](docs/PIN_SECURITY.md) and [SECURITY_UI.md](docs/SECURITY_UI.md).

Cashier-to-manager PIN approval, image upload, camera scanning and general Auth session-to-device binding remain **Coming Soon**. Device inventory covers enrolled offline signing keys. Global sign-out revokes refresh sessions; issued access tokens may survive until expiry. Live enrollment, MFA, PIN and synchronization remain **Not Yet Connected** here. Card/GCash/Maya/Other remain **Manual Payment Verification**; discount/refund/void authority requires the privileged operator's own verified session.

## Included in Phase 6A

- Immutable supplier purchase orders, partial physical receipts and cancellation of remaining quantities. Receipts update the existing branch stock ledger and preserve original order costs and delivery history.
- Recorded expenses from external funds or the operator's own open cash drawer, with full compensating reversals. Drawer payouts and confirmed returns feed the existing shift cash projection; closed shifts retain their original counts.
- Server-posted sales, inventory and expense reports with assigned-branch permissions, explicitly selected own-shift cashier reports, UTC activity windows and separate historical currency groups. CSV copies contain the authorized returned snapshot.
- Encrypted saved requests preserve original UUIDs through lost responses and restart. Retry records the original action; it does not repeat a physical payment, return or stock receipt.

These operations require the deployed backend. They do not pay or email suppliers, initiate provider payouts, value inventory, calculate profit or turn provisional offline records into posted reports. See [PHASE6_CONTRACT.md](docs/PHASE6_CONTRACT.md), [PURCHASES.md](docs/PURCHASES.md), [EXPENSES.md](docs/EXPENSES.md) and [REPORTS.md](docs/REPORTS.md).

## Included in Phase 6B

- Owner/Admin branch creation and revision-checked maintenance, immutable branch codes, safe deactivation barriers and fresh membership reload after scope changes.
- Physical stock dispatch, partial destination receipts and returns from transit. Each endpoint accounts only for confirmed goods; quantities remaining in transit stay visible.
- Supplier stock returns against original purchase receipts, preserving original cost/currency and bounded cumulative quantities. These record physical goods rather than supplier payments.
- Scoped immutable history and encrypted restart/retry using the original request UUID. See [PHASE6B_CONTRACT.md](docs/PHASE6B_CONTRACT.md).

Open **Settings → Manage branches** or **Inventory → Transfers and supplier returns**. Existing operational views need reactivation to access an inactive branch.

## Included in Phase 6C

- Explicit receipt PDF copies and native system printing from accepted sales and preserved offline receipts. Select A4, 80 mm or 58 mm; original amounts and recorded reversals remain separate.
- Offline copies remain provisional after synchronization. Customer PDFs omit signed reviewer proof and unrecorded cash tender/change; unknown characters fail clearly.
- Bundled licensed Unicode fonts work without a network connection. Auth, source and lock guards prevent a delayed export from handing off after access changes.
- Opt-in keyboard HID scanner capture for USB/Bluetooth devices, with framing/timing controls, exact barcode lookup and stale-response protection. Camera scanning remains pending.

Use the receipt view's **Print copy** or **Open / share PDF** actions. The operating system handles the print/PDF request; physical output still needs device testing. See [PHASE6C_CONTRACT.md](docs/PHASE6C_CONTRACT.md).

## Included in Phase 6D

- Owner/Admin invitation history and details, with paginated literal search and pending/accepted/revoked/expired filters. Historical scope includes every original branch assignment, including inactive branches.
- Separate recorded email request and employee acceptance states. `sent` means the authentication service accepted the request; inbox delivery remains unconfirmed. An ambiguous `sending` state cannot trigger automatic resend or a replacement invitation.
- Explicit retries for an authorized original creator using the exact retained invitation UUID, request UUID and original payload. Current role, full branch scope and required MFA are checked again by the server.
- Revision-checked, audited revocation with an encrypted durable request journal and original-UUID replay after uncertainty or restart. Revocation blocks acceptance but cannot recall an email already requested.

Open **Employees → Invitations**. Live email/callback acceptance and operational reconciliation of permanently ambiguous sends remain outstanding. See [INVITATIONS.md](docs/INVITATIONS.md).

## Development

For installable Android release and complete Windows x64 portable/installer
packages, follow [RELEASE.md](docs/RELEASE.md). Release signing uses a retained
dedicated key; the Windows workflow builds and tests on `windows-latest`.

Use Flutter **3.44.0** / Dart **3.12.0** with the committed lockfile. The prepared cloud environment also contains JDK 21 and Android SDK 36 outside this checkout.

```bash
cd /workspace/POS
bash tool/setup.sh
source tool/dev_env.sh
flutter analyze
flutter test
deno check supabase/functions/employee-invitations/index.ts
deno check supabase/functions/offline-sync/index.ts
deno check supabase/functions/employee-pin/index.ts
deno test --allow-read=test/fixtures test/functions
python3 tool/verify_android_security.py
bash tool/build_android.sh
```

Android debug output: `build/app/outputs/flutter-apk/app-debug.apk`. This is a development build, not a signed production release.

On a Windows development machine with Visual Studio's Desktop development with C++ workload:

```powershell
flutter pub get --enforce-lockfile
dart run build_runner build
flutter run -d windows
```

On an attached Android development device: `flutter run -d <device-id>`. The cloud has no attached device/emulator; an APK build and widget tests do not establish hardware behavior. See [SETUP.md](docs/SETUP.md) for toolchain and verification details.

## Connect Supabase

The app can display the read-only design preview without a backend. For authenticated use:

1. Prepare a non-production Supabase project, review/apply the production migrations in filename order, and enable email confirmation.
2. Copy `config/supabase.example.json` to ignored `config/supabase.local.json` and enter the public project URL, publishable key, and approved auth callback. Legacy anon keys are accepted through `SUPABASE_ANON_KEY` as a fallback.
3. Configure the callback in Supabase's redirect allowlist and implement/register the relevant Android/Windows or HTTPS destination before claiming recovery or invitation links work.
4. Configure/deploy the `employee-invitations` server function using [INVITATIONS.md](docs/INVITATIONS.md), including server-only secrets and the exact invitation redirect/origin settings. No server secret belongs in the Flutter JSON file.
5. For offline operation, configure/deploy `offline-sync` and merge only its public `OFFLINE_TRUSTED_KEYS_JSON` pins using [OFFLINE_BACKEND.md](docs/OFFLINE_BACKEND.md). A signing private key belongs exclusively in the Edge secret store.
6. Deploy `employee-pin` and the updated offline function after migrations 008/009 using [SECURITY_BACKEND.md](docs/SECURITY_BACKEND.md) and [PIN_SECURITY.md](docs/PIN_SECURITY.md). Enable privileged MFA only from a genuinely verified AAL2 account.
7. Run `flutter run -d <device-id> --dart-define-from-file=config/supabase.local.json`.

Never put a service-role key, database password, SMTP credential, or private email/payment API key in Flutter. The app rejects private/service-role client configuration. Public client keys do not replace RLS.

Live Auth/email and platform callbacks have not been tested against a real project. A valid local SQL harness does not establish Supabase deployment. [AUTH.md](docs/AUTH.md), [BACKEND.md](docs/BACKEND.md), and [SECURITY.md](docs/SECURITY.md) describe those gates.

## Architecture and next phases

- [Architecture, ERD, permissions and phases](docs/ARCHITECTURE.md)
- [Local persistence and sync contracts](docs/OFFLINE.md), [offline backend](docs/OFFLINE_BACKEND.md) and [offline workspace](docs/OFFLINE_UI.md)
- [Backend deployment and tests](docs/BACKEND.md)
- [Authentication and secure storage](docs/AUTH.md)
- [Employee invitation deployment](docs/INVITATIONS.md)
- [Catalog editing](docs/CATALOG.md) and [employees/contact administration](docs/EMPLOYEES.md)
- [Phase 2 repository contracts](docs/PHASE2_DATA.md)
- [Online checkout and recovery](docs/CHECKOUT.md) and [inventory operations](docs/INVENTORY.md)
- [Setup and platform validation](docs/SETUP.md)
- [Current validation evidence](docs/VALIDATION.md)

Remaining operations and commercial integrations include cashier delegation, hardware, coordinated backup recovery, supplier payments, valuation/COGS/profit and live deployment. Real providers require their own credentials and acceptance tests.
