#!/usr/bin/env bash
# shellcheck disable=SC2034,SC2154
set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/../lib/runtime-hooks/addon-release.sh"
app=adguardhome-sync
release_app=$app release_mode=prebuild release_asset=adguardhome-sync_2_linux_amd64.tar.gz
addon_release_setup() {
  mkdir -p "$c/config"
  printf 'operator config\n' > "$c/config/config.yaml"
  printf 'var_addon_config_path=%q\nvar_addon_backup_dir=%q\n' "$c/config/config.yaml" "$c/backup" > "$c/context.sh"
  : > "$c/opt/$app/adguardhome-sync"
}
addon_release_consumer_assert() { check "$(cat "$c/opt/$app/code")" 'new code' "$app selected source consumer"; }
runtime_hooks_main "$@"
