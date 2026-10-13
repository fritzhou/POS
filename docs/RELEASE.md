# Installable release builds

Build the existing NexaPOS application; do not recreate the project or reset its
databases. Flutter 3.44.0/Dart 3.12.0 and the committed dependency lockfile are the
validated toolchain. See [VALIDATION.md](VALIDATION.md) for application checks.

The user selected a disconnected design preview for this release. Missing public
Supabase configuration opens **Not Yet Connected**, with an explicit read-only
preview. It grants no business authority. A connected release additionally needs
the real schema, public URL/key, registered callback, Edge functions, privileged
MFA policy and email configuration documented in [SETUP.md](SETUP.md).

## Android

```bash
source tool/dev_env.sh
bash tool/release/build_android_release.sh
python3 tool/release/verify_android_release.py
```

The helper makes a release APK for ARM32, ARM64 and x64. It checks frozen
dependencies and retains the original lockfile. Leave pub enabled in the release
build: Flutter 3.44 regenerates the release plugin registrant at that step. Using
`--no-pub` after debug/test tooling can leave a dev-only plugin registration that
cannot compile in release. Do not edit generated Java to hide that mismatch.

Existing ignored `android/key.properties` or an explicit
`NEXAPOS_ANDROID_SIGNING_PROPERTIES` path takes precedence. All four fields are
required: `storeFile`, `storePassword`, `keyAlias`, `keyPassword`. Relative store
paths resolve against `android/`. Release signing never falls back to the debug
key. For a first local signing identity only:

```bash
python3 tool/release/prepare_android_signing.py --create-local-key
```

This creates a dedicated RSA-3072 PKCS12 key and private configuration in
`/workspace/.nexapos-release-signing`, outside the checkout. Existing or partially
created signing files are preserved; no key is silently regenerated. Securely
retain and back up both files for future updates. Never commit them, include them
in the installer/APK, or attach credentials to the public build report. Environment
publication and restoration do not substitute for a verified signing backup.

Future APK updates need the same certificate and an increased versionCode.
This release key differs from the prior Android Debug certificate, so it cannot
update an existing debug installation. Preserve business databases and keys;
removing an installed app to resolve a signature mismatch can erase local data.

The verifier checks actual v2 signatures against the retained key, release
manifest flags, native/AOT libraries for all three ABIs, licensed font assets,
printing classes through R8 mapping, and compiled backup resources. R8 shortens
resource paths, so verification resolves the compiled resource table. Static
checks do not replace installation and startup tests. The exact native callback
is `com.nexapos.app://auth/callback`; it uses the existing Supabase/app_links
handler, and live Auth callbacks still need project/device acceptance.

## Windows x64

Run on Windows with Visual Studio's Desktop development with C++ workload and
Python 3. Inno Setup 6 is optional for the installer:

```powershell
pwsh -File tool/release/windows.ps1 -OutputDirectory C:\NexaPOS-release
```

The script builds `NexaPOS.exe` and packages the complete Release directory,
including Flutter, plugin and SQLCipher DLLs, app-local MSVC redistributables and
`data/`. The original `nexapos` secure-storage namespace is retained when
branding the executable; Windows does not acquire an optional JVM dependency. It verifies x64 PE headers, pinned SQLCipher/font bytes, and every ZIP
entry after extraction. It produces `NexaPOS-Windows-Portable.zip`; when Inno
Setup is installed it also produces `NexaPOS-Windows-Setup.exe` with Start Menu
and optional desktop shortcuts and an uninstaller. Uninstall removes application
files, not external application databases or vault keys. Windows Authenticode
signing is not configured; the EXE/installer remain unsigned.

The GitHub workflow `.github/workflows/release-windows.yml` uses `windows-latest`
and Flutter 3.44.0. It runs on approved pushes to `release/builds` or manual
dispatch. It validates the app, packages the full runtime, runs native launch
smoke on the extracted ZIP, and tests install/launch/uninstall when an installer
exists. Smoke tests are restricted to the disposable runner profile. The workflow
uploads verified packages, file manifests, checksums and the Windows build report.
An absent installer compiler does not prevent producing the required portable ZIP.

No connected configuration is embedded by default. An optional repository variable
`NEXAPOS_PUBLIC_CLIENT_CONFIG_JSON` may supply only public Flutter configuration;
never place service-role, SMTP, database or signing secrets there. An available
workflow file alone is not evidence that a Windows build succeeded. Inspect the
actual completed run and artifacts before offering them as downloads.

## Downloads and report

Copy only successful verified artifacts to `/mnt/data/` with the exact names
`NexaPOS-Android.apk`, `NexaPOS-Windows-Portable.zip` and, when generated,
`NexaPOS-Windows-Setup.exe`. Preserve hashes when copying. Include
`NexaPOS-Build-Report.txt` with build/signing/configuration and test evidence.
Do not rename source archives as Windows builds or offer nonexistent download
links. Physical peripherals, live email/providers and commercial acceptance
remain separate from the disconnected release.
