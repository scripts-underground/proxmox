#!/usr/bin/env bash
# shellcheck disable=SC2034,SC2154
set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/../lib/runtime-hooks/addon-release.sh"
app=actual-budget-prometheus-exporter
release_app=$app release_mode=tarball release_asset=unused.tar.gz
variants+=(fresh)
addon_release_setup() {
  mkdir -p "$c/opt/actual-budget-custom"
  printf 'old code\n' > "$c/opt/actual-budget-custom/code"
  printf 'var_addon_install_path=/opt/actual-budget-custom\nvar_addon_config_path=%q\n' "$c/external/actual.env" > "$c/context.sh"
}
addon_release_consumer_assert() { check "$(cat "$c/opt/actual-budget-custom/code")" 'new code' "$app selected source uses saved install path"; }
runtime_hooks_model() {
  addon_release_model
  apt() { :; }
}
eval "$(declare -f runtime_hooks_assert | sed '1s/runtime_hooks_assert/release_assert/')"
runtime_hooks_assert() {
  if [[ "$variant" == fresh ]]; then
    addon_release_consumer_assert
    check "$(stat -c %a "$c/external/actual.env")" 600 "$app credentials private at creation"
    check "$(grep -c '^PORT="3001"$' "$c/external/actual.env")" 1 "$app consumer config retained"
  else
    release_assert
  fi
}
runtime_hooks_main "$@"
