#!/usr/bin/env bash
set -euo pipefail
repo_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$repo_dir"
source tool/dev_env.sh
if ! command -v deno >/dev/null; then
  python3 tool/cloud/install_deno.py
  source tool/dev_env.sh
fi
command -v flutter >/dev/null || { echo 'Flutter 3.44.0 is required; see docs/SETUP.md.' >&2; exit 1; }
python3 tool/verify_receipt_fonts.py
flutter pub get --enforce-lockfile
dart --suppress-analytics run build_runner build

# Rebuild runtime-only JVM routing/trust from the current injected environment.
# Never persist credentials, remove standard roots, or disable TLS verification.
if [ -x "${JAVA_HOME:-/missing}/bin/keytool" ] &&
   [ -n "${CODEX_PROXY_CERT:-}" ] &&
   [ -n "${HTTPS_PROXY:-${https_proxy:-${HTTP_PROXY:-}}}" ]; then
  python3 tool/cloud/configure_java_network.py
fi
