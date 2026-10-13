# Local business file protection

Phase 5 uses actual SQLCipher for the native business database and the separate
operation journal. `sqlite3` 3.5.2 already supplies SQLCipher through Dart native
asset hooks, so no new Dart package is added. `pubspec.yaml` selects
`hooks.user_defines.sqlite3.source: sqlcipher`. Its release binaries have SHA256
references in the locked package; the hook verifies each download. The package
provides Windows and Android assets as well as the Linux asset used by cloud
verification. Durable production factories reject a non-SQLCipher runtime; there
is no plaintext fallback.

The Linux asset is `libsqlcipher.x64.linux.so`, package SHA256
`45db1843eba3c91d7a229ef603bbb6a3bb9abeab430bbd95dbaa40240c713809`.
Native SQLCipher/OpenSSL licensing and the native SBOM must be included in release
notices. SQLCipher community builds may use an older SQLite version than the
package's default unencrypted SQLite build; the full existing database and
checkout tests must run against the selected hook.

## Keys and lifecycle

`EncryptedDatabaseFactory` generates an independent random 256-bit key for each
absolute business/journal filename. It stores the key only in `SecretStore`,
using a SHA256 filename locator. The default store is Flutter's OS secure-storage
adapter. A write is read back and verified before any new business file is
materialized. Auth tokens, offline signing seeds and database keys use separate
namespaces and purposes. Keys and SQL statements containing keys are never
logged by these factories; errors carry sanitized codes.

A raw SQLCipher key is applied before reading the schema. Every open verifies
that the file decrypts and passes SQLCipher page authentication and SQLite
integrity checks. Temporary SQL storage is forced into memory; SQLCipher protects
on-disk database, journal and WAL page contents. No data/password hashing or
base64 encoding is represented as encryption.

Database keys deliberately survive sign-out, idle lock, account changes and
removal of an offline signing seed. Deleting a database key while paid records
or uncertain checkout intents remain would make those records irrecoverable.
These keys grant file decryption, never a role, membership, shift or offline
transaction authorization. Application authority still comes from freshly
verified server membership or the bounded signed offline grant.

A missing or malformed key for an encrypted file or migration artifact fails
closed. The factory preserves the file; it never generates a replacement key,
resets a schema or discards a payment to make opening succeed. Corrupt pages and
invalid recovery metadata also fail closed. Backup of the OS vault and business
files must remain a coordinated platform/administrator operation. Copying only
a database to another installation does not provide its key. Automatic key
rotation, vault recovery escrow and data erasure are not implemented; they need
an explicit pending-payment retention and administrator recovery policy.

## Existing files and interrupted upgrades

Legacy plaintext v1/v2 Drift databases and v1 operation journals are protected
before Drift runs its normal additive schema migration. The upgrade uses an
exclusive source transaction, SQLCipher's `sqlcipher_export`, a separately
named encrypted target, and full comparison of schema SQL, `user_version`,
all typed table values, duplicate rows and internal sequence rows. SQLCipher
and SQLite integrity checks run on the result.

Before changing the original filenames, the upgrade seals the exact source
main database and any source WAL/rollback-journal bytes with AES-256-GCM. Its
archive key is derived from the database key with HKDF-SHA256 and a dedicated
recovery domain. Associated data binds the archive to the protected filename
scope. The original and archive are never copied into a plaintext backup file.
The encrypted recovery archive is decrypted and verified before promotion.

Files adjacent to the original database are:

- `.legacy-recovery.enc`: authenticated encrypted original main/WAL/journal
  bytes, preserved after a successful upgrade.
- `.encrypted-next`: independently encrypted, verified target while upgrading.
- `.protection-state`: non-secret scope/fingerprint and ready/promoting/complete
  recovery state, written with a flushed staging file and atomic rename.
- `.protection-lock`: inter-process migration lock; contains no business data.

The durable target and verified encrypted recovery archive precede every
original-file deletion. Source WAL/SHM/journal sidecars are removed before the
encrypted target takes the original name. A successful upgrade leaves no
plaintext source backup or plaintext SQLite sidecar. Interrupted ready,
partially removed source, and already-promoted states resume with the same key
and verified copy. New paid rows found in an interrupted plaintext source stop
stale target promotion and preserve both versions for administrator recovery.

`readLegacyRecovery(file)` exposes the authenticated original byte copies in
memory for an explicit administrator recovery/export tool. It never writes or
automatically reopens plaintext. There is currently no end-user recovery UI.

Migration requires a single active application version: stop older app
instances before upgrading. SQLite locking protects the export and the
migration lock serializes current factories, but an older executable does not
honor this new migration lock. File promotion closes SQLite handles first for
Windows compatibility. File flushes and atomic rename protect ordinary
process interruption; power-loss behavior and directory durability still need
filesystem-specific Windows/Android acceptance testing. Legacy source bytes
are bounded to 128 MiB for the in-memory recovery archive; larger files fail
closed and remain intact for a separately reviewed migration tool.

## Verified boundaries

Cloud tests use genuine SQLCipher, physical files and the real Drift/native
operation journal. They cover random per-file keys, correct-key reopening,
missing/corrupt keys, failure to persist a new key, ciphertext-only main/WAL
contents, forced memory temporary storage, authenticated page corruption,
recovery archive tampering, exact typed rows/triggers/schema version,
pre-existing pending UUID/payload/attempt counts, WAL-only committed money,
literal v1 protection before additive v2 migration, concurrent initialization,
three interrupted promotion positions and prevention of stale paid-record
promotion. Recovery archive byte comparison proves original files are
recoverable without silently rewriting their history.

The cloud cannot establish Windows/Android OS-vault behavior, physical process
termination/power failure, antivirus/indexer behavior, secure deletion on flash,
or hardware-backed anti-rollback. SQLCipher confidentiality/authentication does
not attest a trustworthy clock or prevent replay of a complete older valid
file. Backups/exports made outside this factory require their own protection.
Native assets bundled in an APK or Windows build are packaging evidence,
not physical device acceptance. Production approval still needs those platform
checks and release signing.

## Android backup and screen privacy defaults

The Android application sets `allowBackup=false`, explicit legacy backup
exclusions and Android 12+ data-extraction exclusions for both cloud backup and
device transfer. Application root/files/database/shared-preference/external
backup domains are excluded together; a vendor transfer must not restore
business files while omitting the vault keys, or restore stale device authority
independently of those files. This application currently stores no business or
vault state in device-protected/direct-boot storage. Windows backups still
require a coordinated administrator policy.

`MainActivity` applies Android `FLAG_SECURE` before Flutter creates its UI.
Screenshots, screen recording and recent-app thumbnails of Auth, payments and
customer data are blocked by that OS flag. The default applies to the entire
Android app, including preview; there is no insecure debug bypass. Android also
disables cleartext application network traffic. These native settings compile
into the app; vendor-specific backup/transfer and screen-capture behavior still
require physical Android acceptance checks. Windows screen capture prevention
is not implemented.

Phase 6C receipt output and keyboard input are described in [PHASE6C_CONTRACT.md](PHASE6C_CONTRACT.md). Verify bundled fonts with `python3 tool/verify_receipt_fonts.py`; setup performs this before frozen dependency resolution. PDF rendering has no runtime font download. Print/PDF actions preserve original records and recheck source, auth and lock generations before native handoff; output is an explicit plaintext customer copy managed by the OS, separate from encrypted business databases and reviewer proof. No physical completion or provider delivery is implied. Keyboard scanner capture starts disabled and pauses for forms, dialogs, locks and unavailable capture authority.
