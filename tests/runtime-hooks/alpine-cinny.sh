#!/usr/bin/env bash
# shellcheck disable=SC2034,SC2154
# Real cold bundles, release/publication and pending owners; APK/OpenRC are models.
set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/../lib/runtime-hooks/addon-release.sh"
app=alpine-cinny
script_type=lxc
release_app=cinny release_mode=prebuild release_asset=cinny-v2.0.0.tar.gz
variants=(fresh update no-update selected pending checker download copy runtime missing missing-config linked-config)
hook_paths=()

runtime_hooks_variant() {
  case "$variant" in
    checker | download | copy | runtime) fault=$variant ;;
  esac
}
runtime_hooks_model() {
  addon_release_model
  apk() { :; }
  rc-update() { printf 'enable %s\n' "$*" >> "$c/services"; }
  rc-service() {
    if [[ "$APP_FAULT" == runtime && "$2" == restart ]]; then
      printf 'failed-restart %s\n' "$1" >> "$c/services"
      return 51
    fi
    printf '%s %s\n' "$2" "$1" >> "$c/services"
  }
  curl_download() {
    [[ "$APP_FAULT" != download ]] || return 22
    addon_release_download "$@"
  }
}
addon_release_setup() {
  mkdir -p "$c/etc/nginx/http.d" "$c/opt/cinny"
  printf 'new Cinny assets\n' > "$c/payload/index.html"
  printf '{"homeserverList":["archive-default.invalid"]}\n' > "$c/payload/config.json"
  printf 'old Cinny assets\n' > "$c/opt/cinny/index.html"
  # A previous backup is not this invocation's scratch and must never be touched.
  printf 'unrelated saved backup\n' > "$c/opt/cinny_config.json.bak"
  if [[ "$role" == update ]]; then
    printf '{"homeserverList":["saved.invalid"],"hashRouter":{"enabled":true}}\n' > "$c/opt/cinny/config.json"
    if [[ "$variant" == linked-config ]]; then
      mv "$c/opt/cinny/config.json" "$c/external/cinny-config.json"
      ln -s "$c/external/cinny-config.json" "$c/opt/cinny/config.json"
    fi
    stat -c '%i %a %u %g' "$c/opt/cinny/config.json" > "$c/config-before"
    sha256sum < "$c/opt/cinny/config.json" > "$c/config-sha"
    if [[ "$variant" == pending ]]; then
      printf '2.0.0\n' > "$c/home/.cinny"
      printf 'interrupted update\n' > "$c/state/$app"
      rm "$c/opt/cinny/index.html"
    fi
    [[ "$variant" != missing-config ]] || rm "$c/opt/cinny/config.json"
    [[ "$variant" != missing ]] || rm -r "$c/opt/cinny"
  fi
}
runtime_hooks_expected() {
  case "$fault:$variant" in
    checker:*) expected=17 ;;
    *:missing | *:missing-config) expected=1 ;;
  esac
}
cinny_configuration_assert() {
  case "$variant" in fresh | missing | missing-config) return ;; esac
  check "$(sha256sum < "$c/opt/cinny/config.json" 2> /dev/null || true)" "$(cat "$c/config-sha")" "$app/$variant saved configuration bytes retained"
  check "$(stat -c '%i %a %u %g' "$c/opt/cinny/config.json" 2> /dev/null || true)" "$(cat "$c/config-before")" "$app/$variant configuration identity retained in place"
  if [[ "$variant" == linked-config ]]; then
    check "$(readlink "$c/opt/cinny/config.json" || true)" "$c/external/cinny-config.json" "$app/$variant operator link retained"
  fi
}
runtime_hooks_assert() {
  cinny_configuration_assert
  check "$(cat "$c/opt/cinny_config.json.bak" 2> /dev/null || true)" 'unrelated saved backup' "$app/$variant unrelated backup retained"
  case "$variant" in
    checker | no-update | missing | missing-config)
      check "$(stat -c %s "$c/downloads")" 0 "$app/$variant no deployment"
      check "$(stat -c %s "$c/services")" 0 "$app/$variant no service effects"
      ;;
  esac
  if [[ "$rc" == 0 && "$variant" != no-update ]]; then
    check "$(cat "$c/opt/cinny/index.html" 2> /dev/null || true)" 'new Cinny assets' "$app/$variant served asset consumer"
    check "$(grep -c 'v9.0.0' "$c/downloads" || true)" 0 "$app/$variant never deploys moved latest"
  fi
  if [[ "$variant" == selected ]]; then
    check "$(grep -c '/releases/tags/v2.0.0$' "$c/requests" || true)" 1 "$app binds selected raw release"
    check "$(grep -c '/releases/latest$' "$c/requests" || true)" 1 "$app resolves latest once"
  fi
  if [[ "$role" == update && "$fault" != runtime && "$rc" != 0 && "$variant" != missing ]]; then
    check "$(cat "$c/opt/cinny/index.html" 2> /dev/null || true)" 'old Cinny assets' "$app/$variant failed preparation preserves old consumer"
  fi
}
runtime_hooks_retry_needed() {
  [[ "$role" == update && "$expected" != 0 && "$variant" != missing && "$variant" != missing-config ]]
}
runtime_hooks_retry_assert() {
  cinny_configuration_assert
  check "$(cat "$c/opt/cinny/index.html")" 'new Cinny assets' "$app/$variant frozen pending retry repairs asset consumer"
  check "$(cat "$c/opt/cinny_config.json.bak")" 'unrelated saved backup' "$app/$variant retry leaves unrelated backup alone"
  check "$(tail -1 "$c/services")" 'restart nginx' "$app/$variant retry restarts the native service"
}
runtime_hooks_main "$@"
