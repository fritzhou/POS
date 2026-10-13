#!/usr/bin/env bash
set -euo pipefail
repo_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$repo_dir"
source tool/dev_env.sh
for argument in "$@"; do
  if [ "$argument" = --no-pub ]; then
    echo 'Flutter 3.44 requires release plugin regeneration; --no-pub would retain debug/test registrations.' >&2
    exit 1
  fi
done
if [ -x "${JAVA_HOME:-/missing}/bin/keytool" ] &&
   [ -n "${CODEX_PROXY_CERT:-}" ] &&
   [ -n "${HTTPS_PROXY:-${https_proxy:-${HTTP_PROXY:-}}}" ]; then
  python3 tool/cloud/configure_java_network.py
  source "$NEXAPOS_TOOLCHAIN_ROOT/java-trust/network-env.sh"
fi
if [ -z "${NEXAPOS_ANDROID_SIGNING_PROPERTIES:-}" ] && [ ! -f android/key.properties ]; then
  signing_file=/workspace/.nexapos-release-signing/key.properties
  if [ ! -f "$signing_file" ]; then
    echo 'Release signing is not configured. Read docs/RELEASE.md; no debug signing fallback is permitted.' >&2
    exit 1
  fi
  export NEXAPOS_ANDROID_SIGNING_PROPERTIES="$signing_file"
fi
flutter pub get --enforce-lockfile
lock_before="$(sha256sum pubspec.lock)"
flutter build apk --release --target-platform android-arm,android-arm64,android-x64 "$@"
lock_after="$(sha256sum pubspec.lock)"
if [ "$lock_before" != "$lock_after" ]; then
  echo 'Dependency lockfile changed during the build. Review it before distributing this release.' >&2
  exit 1
fi
