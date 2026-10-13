# Development setup

The prepared cloud uses the existing isolated checkout at `/workspace/POS`. Do not create a Git worktree unless requested. Application source is separate from the retained toolchains under `/workspace/.toolchains`.

## Retained tools and initialization

Flutter 3.44.0 / Dart 3.12.0 was extracted from the Cirrus Labs publisher image pinned to Linux amd64 digest `sha256:0a9de3b70b5b7b921a346eb2793e363dc22280849a4fd690d9dde99ce1c2b1b8`. Registry TLS and OCI layer checksums remained enabled. The publisher Dockerfile uses the official Flutter tag. This is a third-party development image; no independent image signature verification is claimed. The image/export container was removed after extraction; the SDK itself is retained.

Android tooling uses Temurin JDK 21.0.12.1+1, Android command tools 23.0, platforms 34/35/36, build-tools 36.0.0, platform-tools 37.0.1, NDK 28.2.13676358, and CMake 3.22.1. JDK SHA-256: `ce79869e1307ed8ee1e2baa86a412b1eb5b75d10a01006d788a6f968bcfaee94`. Official Android command-tools metadata supplied SHA-1 `e025545c62a8e64c7559119566a569fb1dec5f60`; the archive size/checksum was verified. SDK manager retained its normal verification.

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

`tool/setup.sh` refreshes dependencies using the checked-in lockfile and regenerates Drift without deleting local databases. Preserve both the Phase 1 financial outbox and the separate Phase 3 actor/organization-scoped online operation journal: pending checkout, stock and shift requests must keep their original IDs. Do not reset either database to make startup pass. The journal supports online reconciliation and does not grant offline business authority. Phase 4 also preserves authorized events, signed grants, acceptance links, cache revisions and unresolved offline payment/preparation intents. Schema v2 migrates existing databases; never delete a database to enable the feature. See [CHECKOUT.md](CHECKOUT.md) and [OFFLINE.md](OFFLINE.md).

Setup installs the pinned Deno runner if missing. `tool/dev_env.sh` activates retained tools and writable caches without overriding `HOME`. Startup scripts must be sourced again in a new shell/task. Live processes do not survive environment publication.

Deno 2.9.7 is retained under `/workspace/.toolchains/deno`. The official Linux x86_64 GitHub release archive matched SHA-256 `c6527f24f4b16031d3ae4fa9f658d5f11534c8d84ce7dc8502420280919c3490`; `tool/cloud/install_deno.py` retains that verification for reinstalling. Function tests use native TypeScript/fetch and require no package downloads, network permissions or secrets.

Java does not use proxy environment variables automatically. `tool/cloud/configure_java_network.py` reads the injected proxy and platform public certificate, preserves standard Java roots, and writes supported JVM/Gradle settings outside the checkout. It refuses to serialize proxy credentials. Re-run it through the build helper in a new task because proxy routing can change. Gradle 9.1.0's downloaded archive matches the official checksum committed as `distributionSha256Sum`.

If Android tooling is missing, the checksum-preserving installation helpers are `tool/cloud/install_android_toolchain.py` and `tool/cloud/install_android_packages.py`; they are cloud/Linux helpers, not Windows installers. The existing Flutter SDK is part of the prepared filesystem snapshot. Installing it from scratch requires the official download domain or a trusted, pinned SDK source. A first container extraction consumed the 32 GiB workspace disk; temporary extraction followed by removal of the image/container recovered it. Do not repeat that large image bootstrap alongside existing toolchains.

Network destinations used: `pub.dev`, `github.com`/GitHub artifact hosts, `ghcr.io`, official Docker registry, `dl.google.com`, Gradle hosts and Maven repositories. `storage.googleapis.com` was added to the environment draft for official Flutter/Dart downloads; current preparation used the reachable pinned registry route. For a real Supabase project, also allow its actual project hostname in environment settings. Do not replace unrelated existing allowed domains.

## Database validation

The PostgreSQL test harness uses an isolated container, not the real application backend. It recreates only its named test database. It must never target a user/production database.

```bash
docker run -d --name nexapos-postgres-test --network none \
  -e POSTGRES_HOST_AUTH_METHOD=trust \
  postgres@sha256:2d2b8998d31037bf721cfdf764d76ba74171b4fab3431b7f72c27c56ddbdf9e3
bash test/sql/run.sh nexapos-postgres-test
docker stop nexapos-postgres-test
```

That command creates a disposable local test service without host ports. If the named container already exists, inspect/reuse that test container rather than recreating it blindly. The harness refuses another container name and checks the pinned image, running state, disabled networking, absent host ports and anonymous PostgreSQL volume before resetting its test database. Test Auth fixtures stay under `test/sql/`; deploy only `supabase/migrations/` to a real project.

## Platform and connection limits

Windows compilation requires Windows plus Visual Studio C++ tooling and remains unrun on this Linux host. Android APK compilation does not validate scanners, secure storage, callback registration, peripherals or device sessions. No physical Android device/emulator is attached. The installed ADB attempts to create the host's read-only `.android` directory; device deployment requires a suitable runner.

Supabase URL/client key/redirect configuration is absent by default. Auth, email delivery, token refresh, native callbacks and live RLS through PostgREST need a real non-production project test. Local tests validate adapters, gates and SQL behavior independently. Backend deployment and production release signing are separate actions.

For offline development, follow [OFFLINE_BACKEND.md](OFFLINE_BACKEND.md). Public trust pins are an independent Flutter configuration requirement; keys are not accepted from the grant response. Missing public configuration disables offline checkout. Edge signing/service credentials are separate from cloud setup and belong only in the deployment secret store. No live project or deployment key was created here.

## Phase 5 file and platform protection

The existing sqlite3 package selects checksum-verified SQLCipher native assets through pubspec hooks. Native business/journal factories fail closed without SQLCipher and retain independent OS-vault file keys across logout. Legacy migration preserves exact encrypted recovery archives and never resets pending financial data. Read [LOCAL_SECURITY.md](LOCAL_SECURITY.md) before changing filenames, backup or vault key lifecycle. Run `python3 tool/verify_android_security.py` for source policy checks; actual screenshot/recents/backup/vault behavior still needs devices. Auth and offline signing keys remain separate. Apply all fifteen migrations in filename order and deploy employee-pin plus the updated offline function with [SECURITY_BACKEND.md](SECURITY_BACKEND.md).

Phase 6A adds online purchase, expense and report RPCs without additional Dart packages or a new local cache schema. Their mutations share the encrypted actor/organization journal; preserve pending stock receipts, expense payouts and returned-cash intents exactly. Report snapshots contain posted server activity, historical currency groups and explicit UTC windows. Read [PHASE6_CONTRACT.md](PHASE6_CONTRACT.md) before changing financial rules or report aggregation.

Phase 6B adds branch maintenance and physical stock logistics through migrations 013/014. Read [PHASE6B_CONTRACT.md](PHASE6B_CONTRACT.md). Current authorization and privileged MFA precede every replay; dispatch requires both endpoints, receipt requires its destination and transit return its source. Supplier returns reference original purchase receipt quantities and costs and do not pay suppliers. Branch deactivation blocks retained grants, unresolved stock/transit, open shifts and outstanding orders. Codes remain immutable, referenced product units cannot change, and scope changes reload server membership. Preserve encrypted logistics intents, original evidence and UUIDs through uncertain responses. Direct service branch/catalog writes are revoked; use validated RPCs.

Phase 6C receipt output and keyboard input are described in [PHASE6C_CONTRACT.md](PHASE6C_CONTRACT.md). Verify bundled fonts with `python3 tool/verify_receipt_fonts.py`; setup performs this before frozen dependency resolution. PDF rendering has no runtime font download. Print/PDF actions preserve original records and recheck source, auth and lock generations before native handoff; output is an explicit plaintext customer copy managed by the OS, separate from encrypted business databases and reviewer proof. No physical completion or provider delivery is implied. Keyboard scanner capture starts disabled and pauses for forms, dialogs, locks and unavailable capture authority.

Phase 6D adds migration 015 and the Owner/Admin **Employees → Invitations** workflow. Read [PHASE6D_CONTRACT.md](PHASE6D_CONTRACT.md) before changing history scope, email-request retry or revocation. Preserve original creator/request fields and encrypted revocation intents through restart, lock and uncertain responses. Never reclaim an unknown `sending` dispatch or generate a replacement UUID automatically. Invitation administration requires current online authority; an empty design preview has no records or mutation permission.
