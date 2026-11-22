#!/usr/bin/env bash
# shellcheck disable=SC2034,SC2154
set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/../lib/runtime-hooks/addon-release.sh"
app=beszel
script_type=lxc
release_app=beszel release_mode=prebuild release_asset=beszel_linux_amd64.tar.gz
variants=(fresh selected no-update clean pending checker download runtime missing)
hook_paths=()
runtime_hooks_variant() {
  case "$variant" in checker | download | runtime) fault=$variant ;; esac
}
runtime_hooks_expected() {
  case "$fault" in checker) expected=17 ;; esac
  [[ "$variant" != missing ]] || expected=1
}
runtime_hooks_model() {
  addon_release_model
  if [[ -f "$c/clean" ]]; then CLEAN_INSTALL=1 UPDATE_FORCE=1 FORCE_DEPLOY=1; fi
  apt() { :; }
  get_system_arch() { printf 'amd64\n'; }
  curl_download() {
    [[ "$APP_FAULT" != download ]] || return 22
    addon_release_download "$@"
  }
  systemctl() {
    if [[ "$1" == start && "$APP_FAULT" == runtime ]]; then
      printf 'failed-start %s\n' "${!#}" >> "$c/services"
      return 51
    fi
    printf '%s\n' "$*" >> "$c/services"
  }
}
runtime_hooks_setup() {
  : > "$c/requests"
  : > "$c/downloads"
  mkdir -p "$c/opt/beszel/beszel_data" "$c/payload/beszel_data"
  printf 'saved database\n' > "$c/opt/beszel/beszel_data/data.db"
  printf 'saved config\n' > "$c/opt/beszel/beszel_data/config.yml"
  printf 'saved key\n' > "$c/opt/beszel/beszel_data/id_ed25519"
  printf 'incoming defaults\n' > "$c/payload/beszel_data/data.db"
  stat -c '%i' "$c/opt/beszel/beszel_data" > "$c/data-inode"
  printf '#!/bin/sh\nprintf "new-beszel\\n"\n' > "$c/payload/beszel"
  printf '#!/bin/sh\nprintf "old-beszel\\n"\n' > "$c/opt/beszel/beszel"
  chmod 0755 "$c/payload/beszel" "$c/opt/beszel/beszel"
  if [[ "$variant" == no-update || "$variant" == clean || "$variant" == pending ]]; then
    printf '2.0.0\n' > "$c/home/.beszel"
  else printf '1.0.0\n' > "$c/home/.beszel"; fi
  if [[ "$variant" == clean ]]; then
    : > "$c/clean"
    printf 'stale code\n' > "$c/opt/beszel/obsolete"
  fi
  if [[ "$variant" == pending ]]; then
    printf 'interrupted\n' > "$c/state/beszel"
    rm "$c/opt/beszel/beszel"
  fi
  [[ "$variant" != missing ]] || mv "$c/opt/beszel" "$c/absent-beszel"
}
runtime_hooks_assert() {
  [[ "$variant" != missing ]] || return 0
  check "$(cat "$c/opt/beszel/beszel_data/data.db" 2> /dev/null || true)" 'saved database' "$app/$variant database retained"
  check "$(cat "$c/opt/beszel/beszel_data/config.yml" 2> /dev/null || true)" 'saved config' "$app/$variant configuration retained"
  check "$(cat "$c/opt/beszel/beszel_data/id_ed25519" 2> /dev/null || true)" 'saved key' "$app/$variant identity retained"
  check "$(stat -c '%i' "$c/opt/beszel/beszel_data" 2> /dev/null || true)" "$(cat "$c/data-inode")" "$app/$variant data directory stays in place"
  if [[ "$variant" == checker || "$variant" == no-update ]]; then
    check "$(stat -c %s "$c/downloads")" 0 "$app/$variant no deployment"
    check "$(stat -c %s "$c/services")" 0 "$app/$variant no service effects"
  elif [[ "$rc" == 0 ]]; then
    check "$("$c/opt/beszel/beszel" 2> /dev/null || true)" new-beszel "$app/$variant executable consumer"
    if [[ "$role" == update && "$variant" != clean && "$variant" != pending ]]; then
      check "$(grep -c '/releases/latest$' "$c/requests" || true)" 1 "$app one release selection"
      check "$(grep -c '/releases/tags/v2.0.0$' "$c/requests" || true)" 1 "$app selected raw tag deployed"
    fi
  fi
  if [[ "$variant" == clean ]]; then check "$(test -e "$c/opt/beszel/obsolete" && printf present || printf absent)" absent "$app clean removes obsolete code"; fi
}
runtime_hooks_retry_needed() { [[ "$expected" != 0 && "$variant" != missing ]]; }
runtime_hooks_retry_assert() {
  check "$("$c/opt/beszel/beszel")" new-beszel "$app retry restores executable"
  check "$(cat "$c/opt/beszel/beszel_data/data.db")" 'saved database' "$app retry retains database"
  check "$(tail -1 "$c/services")" 'start beszel-hub' "$app retry starts service"
}
runtime_hooks_main "$@"
