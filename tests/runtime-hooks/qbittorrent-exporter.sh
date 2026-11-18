#!/usr/bin/env bash
# shellcheck disable=SC2034,SC2154
set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/../lib/runtime-hooks/addon-release.sh"
app=qbittorrent-exporter
release_app=$app release_mode=tarball release_asset=unused.tar.gz
addon_release_setup() {
  : > "$c/opt/$app/qbittorrent-exporter"
  mkdir -p "$c/config"
  printf 'QBITTORRENT_API_KEY=fixture\n' > "$c/config/config"
  printf 'var_addon_config_path=%q\n' "$c/config/config" > "$c/context.sh"
}
addon_release_consumer_assert() { check "$(cat "$c/opt/$app/code")" 'new code' "$app selected source consumer"; }
runtime_hooks_main "$@"
