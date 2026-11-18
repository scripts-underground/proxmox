#!/usr/bin/env bash
# shellcheck disable=SC2034,SC2154
set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/../lib/runtime-hooks/addon-release.sh"
app=nextcloud-exporter
release_app=$app release_mode=binary release_asset=nextcloud-exporter_2_amd64.deb
addon_release_setup() {
  : > "$c/local/bin/nextcloud-exporter"
  printf 'var_addon_bin_path=/usr/local/bin/nextcloud-exporter\n' > "$c/context.sh"
}
addon_release_consumer_assert() { check "$(cat "$c/package-consumer")" 'selected v2.0.0' "$app selected package consumer"; }
runtime_hooks_main "$@"
