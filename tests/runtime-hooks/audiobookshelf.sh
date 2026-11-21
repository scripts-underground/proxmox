#!/usr/bin/env bash
# shellcheck disable=SC2034,SC2154
# Cold generated updater; package/service effects modeled, file consumers real.
set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/../lib/runtime-hooks/harness.sh"
app=audiobookshelf
script_type=lxc
variants=(update current pending refresh-failure package-failure)
hook_paths=(/usr/share/audiobookshelf opt/audiobookshelf)

runtime_hooks_variant() {
  case "$variant" in
    refresh-failure) fault=refresh ;;
    package-failure) fault=package ;;
  esac
}
runtime_hooks_model() {
  apt() {
    printf '%s\n' "$*" >> "$c/packages"
    if [[ "$1" == update ]]; then
      [[ "$APP_FAULT" != refresh ]] || return 52
      return 0
    fi
    [[ "$APP_FAULT" != package ]] || return 53
    # Native APT does not unpack installed current-version payload without reinstall.
    if [[ "$(cat "$c/version")" != 2.38.0 || " $* " == *' --reinstall '* ]]; then
      printf '2.38.0\n' > "$c/version"
      printf '#!/bin/sh\nprintf audiobookshelf-consumer-2.38.0\n' > /opt/audiobookshelf/audiobookshelf
      chmod 0755 /opt/audiobookshelf/audiobookshelf
    fi
  }
}
runtime_hooks_setup() {
  : > "$c/packages"
  mkdir -p "$c/etc/default"
  printf 'PORT=14567\nCONFIG_PATH=/saved/config\nMETADATA_PATH=/saved/metadata\n' > "$c/etc/default/audiobookshelf"
  sha256sum "$c/etc/default/audiobookshelf" > "$c/config-before"
  printf '2.37.2\n' > "$c/version"
  printf '#!/bin/sh\nprintf old-audiobookshelf\n' > "$c/opt/audiobookshelf/audiobookshelf"
  chmod 0755 "$c/opt/audiobookshelf/audiobookshelf"
  if [[ "$variant" == current || "$variant" == pending ]]; then
    printf '2.38.0\n' > "$c/version"
    printf '#!/bin/sh\nprintf audiobookshelf-consumer-2.38.0\n' > "$c/opt/audiobookshelf/audiobookshelf"
  fi
  if [[ "$variant" == pending ]]; then
    printf 'interrupted update\n' > "$c/state/$app"
    rm "$c/opt/audiobookshelf/audiobookshelf"
  fi
}
runtime_hooks_expected() {
  case "$fault" in refresh) expected=52 ;; package) expected=53 ;; esac
}
runtime_hooks_assert() {
  runtime_hooks_configuration_assert
  check "$(sha256sum "$c/etc/default/audiobookshelf")" "$(cat "$c/config-before")" "$app/$variant complete operator defaults retained"
  if [[ "$rc" == 0 ]]; then
    check "$("$c/opt/audiobookshelf/audiobookshelf" 2> /dev/null || true)" audiobookshelf-consumer-2.38.0 "$app/$variant package payload reaches consumer"
  fi
  if [[ "$variant" == current ]]; then
    check "$(grep -c -- --reinstall "$c/packages" || true)" 0 "$app/current ordinary update does not reinstall"
  fi
  if [[ "$fault" == refresh ]]; then
    check "$(wc -l < "$c/packages")" 1 "$app/refresh failure has no package effects"
  fi
}
runtime_hooks_retry_assert() {
  check "$("$c/opt/audiobookshelf/audiobookshelf")" audiobookshelf-consumer-2.38.0 "$app/$variant pending retry repairs consumer"
}
runtime_hooks_main "$@"
