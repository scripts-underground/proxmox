#!/usr/bin/env bash
# shellcheck disable=SC2034,SC2154
# Shared external-effect models; real release, bundle and pending owners run cold.
set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/../lib/runtime-hooks/addon-release.sh"
app=backrest
script_type=lxc
release_app=$app release_mode=prebuild release_asset=backrest_Linux_x86_64.tar.gz
variants=(fresh checker no-update selected pending)
hook_paths=()
addon_release_setup() {
  mkdir -p "$c/opt/backrest/"{bin,config,data}
  printf 'saved config and auth\n' > "$c/opt/backrest/config/config.json"
  printf 'saved operation history\n' > "$c/opt/backrest/data/history"
  printf '#!/bin/sh\nprintf "selected v2.0.0\\n"\n' > "$c/payload/backrest"
  chmod 0755 "$c/payload/backrest"
  printf '#!/bin/sh\nprintf "old binary\\n"\n' > "$c/opt/backrest/bin/backrest"
  chmod 0755 "$c/opt/backrest/bin/backrest"
  if [[ "$variant" == pending ]]; then
    printf '2.0.0\n' > "$c/home/.backrest"
    printf 'interrupted update\n' > "$c/state/backrest"
    rm "$c/opt/backrest/bin/backrest"
  fi
}
runtime_hooks_assert() {
  check "$(cat "$c/opt/backrest/config/config.json")" 'saved config and auth' "$app/$variant config and auth retained"
  check "$(cat "$c/opt/backrest/data/history")" 'saved operation history' "$app/$variant operation history retained"
  runtime_hooks_configuration_assert
  case "$variant" in
    fresh | selected | pending)
      check "$("$c/opt/backrest/bin/backrest")" 'selected v2.0.0' "$app/$variant selected binary consumer"
      check "$(grep -c 'v9.0.0' "$c/downloads" || true)" 0 "$app/$variant never deploys moved latest"
      ;;
    checker | no-update)
      check "$(stat -c %s "$c/downloads")" 0 "$app/$variant no deployment"
      check "$(stat -c %s "$c/services")" 0 "$app/$variant no service effects"
      check "$("$c/opt/backrest/bin/backrest")" 'old binary' "$app/$variant old binary retained"
      ;;
  esac
  if [[ "$variant" == selected ]]; then
    check "$(grep -c '/releases/tags/v2.0.0$' "$c/requests" || true)" 1 "$app binds selected raw tag"
    check "$(grep -c '/releases/latest$' "$c/requests" || true)" 1 "$app resolves latest once"
  fi
}
runtime_hooks_retry_assert() {
  check "$("$c/opt/backrest/bin/backrest")" 'selected v2.0.0' "$app pending retry binary consumer"
  check "$(cat "$c/opt/backrest/config/config.json")" 'saved config and auth' "$app retry preserves config and auth"
  check "$(cat "$c/opt/backrest/data/history")" 'saved operation history' "$app retry preserves history"
}
runtime_hooks_main "$@"
