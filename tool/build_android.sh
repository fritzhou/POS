#!/usr/bin/env bash
set -euo pipefail
repo_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$repo_dir"
source tool/dev_env.sh
if [ -x "${JAVA_HOME:-/missing}/bin/keytool" ] &&
   [ -n "${CODEX_PROXY_CERT:-}" ] &&
   [ -n "${HTTPS_PROXY:-${https_proxy:-${HTTP_PROXY:-}}}" ]; then
  python3 tool/cloud/configure_java_network.py
  source "$NEXAPOS_TOOLCHAIN_ROOT/java-trust/network-env.sh"
fi
flutter build apk --debug --target-platform android-arm64 "$@"
