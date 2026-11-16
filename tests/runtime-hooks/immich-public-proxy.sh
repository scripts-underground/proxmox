#!/usr/bin/env bash
# shellcheck disable=SC2034,SC2154
set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/../lib/runtime-hooks/addon-release.sh"
app=immich-public-proxy
release_app='Immich Public Proxy' release_mode=tarball release_asset=unused.tar.gz
addon_release_setup() {
  mkdir -p "$c/opt/$app/app" "$c/payload/app"
  printf 'operator config\n' > "$c/opt/$app/app/config.json"
  printf 'operator env\n' > "$c/opt/$app/app/.env"
  printf 'var_addon_install_path=/opt/immich-public-proxy\nvar_addon_config_path=/opt/immich-public-proxy/app\n' > "$c/context.sh"
}
addon_release_consumer_assert() { check "$(cat "$c/opt/$app/code")" 'new code' "$app selected source consumer"; }
runtime_hooks_main "$@"
