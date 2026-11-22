#!/usr/bin/env bash
# shellcheck disable=SC2034,SC2154
set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/../lib/runtime-hooks/addon-release.sh"
app=bichon
script_type=lxc
release_app=bichon release_mode=prebuild release_asset=bichon-server-2.0.0-x86_64-unknown-linux-gnu.tar.gz
variants=(fresh selected no-update clean pending checker download runtime missing missing-config)
hook_paths=()
runtime_hooks_variant() {
  case "$variant" in checker | download | runtime) fault=$variant ;; esac
}
runtime_hooks_expected() {
  case "$variant" in checker) expected=17 ;; missing | missing-config) expected=1 ;; esac
}
runtime_hooks_model() {
  addon_release_model
  uname() { printf 'x86_64\n'; }
  chown() { command chown "$@"; }
  cat() {
    local pid=$BASHPID output
    output=$(readlink "/proc/$pid/fd/1")
    if [[ "$output" == /opt/bichon/* ]]; then
      command printf '%s %s\n' "$output" "$(stat -Lc '%a %u %g' "/proc/$pid/fd/1")" >> "$c/creation-observations"
    fi
    command cat "$@"
  }
  printf() {
    local pid=$BASHPID output
    output=$(readlink "/proc/$pid/fd/1")
    if [[ "$output" == /opt/bichon/* ]]; then
      command printf '%s %s\n' "$output" "$(stat -Lc '%a %u %g' "/proc/$pid/fd/1")" >> "$c/creation-observations"
    fi
    command printf "$@"
  }
  mv() {
    if [[ "${!#}" == /opt/bichon/bichon.env ]]; then
      local arg source=''
      for arg in "$@"; do
        [[ "$arg" == -* || "$arg" == /opt/bichon/bichon.env ]] || source=$arg
      done
      printf '%s\n' "$(stat -c '%a %u %g' "$source")" >> "$c/publication-observations"
    fi
    command mv "$@"
  }
  if [[ -f "$c/clean" ]]; then CLEAN_INSTALL=1 UPDATE_FORCE=1 FORCE_DEPLOY=1; fi
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
  : > "$c/creation-observations"
  : > "$c/publication-observations"
  mkdir -p "$c/opt/bichon" "$c/opt/bichon-data"
  printf 'persistent mailbox data\n' > "$c/opt/bichon-data/mail"
  printf 'BICHON_ROOT_DIR=/opt/bichon-data\nBICHON_ENCRYPT_PASSWORD=saved-secret\nBICHON_PUBLIC_URL=https://saved.invalid\nBICHON_HTTP_PORT=4567\n' > "$c/opt/bichon/bichon.env"
  cp "$c/opt/bichon/bichon.env" "$c/expected-env"
  stat -c '%i' "$c/opt/bichon/bichon.env" > "$c/env-inode"
  chmod 0644 "$c/opt/bichon/bichon.env"
  chown 65534:65534 "$c/opt/bichon/bichon.env"
  printf 'incoming env default\n' > "$c/payload/bichon.env"
  printf '#!/bin/sh\nprintf "new-bichon\\n"\n' > "$c/payload/bichon-server"
  printf '#!/bin/sh\nprintf "old-bichon\\n"\n' > "$c/opt/bichon/bichon-server"
  chmod 0755 "$c/payload/bichon-server" "$c/opt/bichon/bichon-server"
  case "$variant" in no-update | clean | pending) printf '2.0.0\n' > "$c/home/.bichon" ;; *) printf '1.0.0\n' > "$c/home/.bichon" ;; esac
  if [[ "$variant" == clean ]]; then : > "$c/clean"; fi
  if [[ "$variant" == pending ]]; then
    printf 'interrupted\n' > "$c/state/bichon"
    rm "$c/opt/bichon/bichon-server"
  fi
  if [[ "$variant" == fresh ]]; then rm -f "$c/opt/bichon/bichon.env"; fi
  if [[ "$variant" == missing ]]; then mv "$c/opt/bichon" "$c/absent-bichon"; fi
  if [[ "$variant" == missing-config ]]; then rm "$c/opt/bichon/bichon.env"; fi
}
runtime_hooks_assert() {
  check "$(cat "$c/opt/bichon-data/mail")" 'persistent mailbox data' "$app/$variant mailbox retained"
  case "$variant" in missing | missing-config) return 0 ;; esac
  if [[ "$role" == install ]]; then
    check "$(grep -c '^BICHON_ENCRYPT_PASSWORD=.' "$c/opt/bichon/bichon.env" 2> /dev/null || true)" 1 "$app fresh encryption configuration exists"
    check "$(grep -c '^BICHON_PUBLIC_URL=http://10.20.30.40:15630$' "$c/opt/bichon/bichon.env" 2> /dev/null || true)" 1 "$app EOF retains documented URL fallback"
    check "$(cat "$c/publication-observations")" '600 0 0' "$app fresh publishes only an already-private root-owned file"
    check "$(grep -c '^/opt/bichon/\.bichon\.env\.[^ ]* 600 0 0$' "$c/creation-observations" || true)" 1 "$app fresh writes secrets only into private sibling staging"
    check "$(grep -c '^/opt/bichon/bichon.env ' "$c/creation-observations" || true)" 0 "$app fresh never streams secrets into the public pathname"
  else
    check "$(cmp -s "$c/expected-env" "$c/opt/bichon/bichon.env" && printf same || printf different)" same "$app/$variant exact environment retained"
    check "$(stat -c '%i' "$c/opt/bichon/bichon.env" 2> /dev/null || true)" "$(cat "$c/env-inode")" "$app/$variant environment stays in place"
  fi
  check "$(stat -c '%a %u %g' "$c/opt/bichon/bichon.env")" '600 0 0' "$app/$variant root-only configuration"
  if [[ "$variant" == checker || "$variant" == no-update ]]; then
    check "$(stat -c %s "$c/downloads")" 0 "$app/$variant no deployment"
    check "$(stat -c %s "$c/services")" 0 "$app/$variant no service effects"
  elif [[ "$rc" == 0 ]]; then
    check "$("$c/opt/bichon/bichon-server" 2> /dev/null || true)" new-bichon "$app/$variant executable consumer"
    if [[ "$role" == update && "$variant" != clean && "$variant" != pending ]]; then
      check "$(grep -c '/releases/latest$' "$c/requests" || true)" 1 "$app one release selection"
      check "$(grep -c '/releases/tags/v2.0.0$' "$c/requests" || true)" 1 "$app selected raw tag deployed"
    fi
  fi
}
runtime_hooks_retry_needed() { [[ "$role" == update && "$expected" != 0 && "$variant" != missing && "$variant" != missing-config ]]; }
runtime_hooks_retry_assert() {
  check "$("$c/opt/bichon/bichon-server")" new-bichon "$app retry restores executable"
  check "$(cmp -s "$c/expected-env" "$c/opt/bichon/bichon.env" && printf same || printf different)" same "$app retry retains full configuration"
  check "$(stat -c '%a %u %g' "$c/opt/bichon/bichon.env")" '600 0 0' "$app retry retains private root-owned configuration"
}
runtime_hooks_main "$@"
