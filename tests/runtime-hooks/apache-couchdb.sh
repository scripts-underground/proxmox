#!/usr/bin/env bash
# shellcheck disable=SC2034,SC2154
# Real cold update bundles and file consumers; APT package effects are modeled.
set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/../lib/runtime-hooks/harness.sh"
app=apache-couchdb
script_type=lxc
variants=(update current pending refresh-failure package-failure)
hook_paths=(/usr/lib/systemd/system/couchdb.service etc/systemd/system/couchdb.service)

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
    # APT leaves already-installed package files alone unless reinstall is requested.
    if [[ "$(cat "$c/version")" != 3.5.3 || " $* " == *' --reinstall '* ]]; then
      printf '3.5.3\n' > "$c/version"
      printf '#!/bin/sh\nprintf couchdb-consumer-3.5.3\n' > /opt/couchdb/bin/couchdb
      chmod 0755 /opt/couchdb/bin/couchdb
    fi
  }
}
runtime_hooks_setup() {
  : > "$c/packages"
  mkdir -p "$c/opt/couchdb/bin"
  : > "$c/etc/systemd/system/couchdb.service"
  printf '3.5.2\n' > "$c/version"
  printf '#!/bin/sh\nprintf couchdb-consumer-3.5.2\n' > "$c/opt/couchdb/bin/couchdb"
  chmod 0755 "$c/opt/couchdb/bin/couchdb"
  if [[ "$variant" == current || "$variant" == pending ]]; then
    printf '3.5.3\n' > "$c/version"
    printf '#!/bin/sh\nprintf couchdb-consumer-3.5.3\n' > "$c/opt/couchdb/bin/couchdb"
  fi
  if [[ "$variant" == pending ]]; then
    printf 'interrupted update\n' > "$c/state/$app"
    rm "$c/opt/couchdb/bin/couchdb"
  fi
}
runtime_hooks_expected() {
  case "$fault" in refresh) expected=52 ;; package) expected=53 ;; esac
}
runtime_hooks_assert() {
  runtime_hooks_configuration_assert
  if [[ "$rc" == 0 ]]; then
    check "$("$c/opt/couchdb/bin/couchdb" 2> /dev/null || true)" couchdb-consumer-3.5.3 "$app/$variant package executable reaches consumer"
  fi
  if [[ "$variant" == current ]]; then
    check "$(grep -c -- --reinstall "$c/packages" || true)" 0 "$app/current ordinary update does not force package reinstall"
  fi
  if [[ "$fault" == refresh ]]; then
    check "$(wc -l < "$c/packages")" 1 "$app/refresh-failure no package effects after failed refresh"
  fi
}
runtime_hooks_retry_assert() {
  check "$("$c/opt/couchdb/bin/couchdb")" couchdb-consumer-3.5.3 "$app/$variant frozen pending retry repairs executable"
}
runtime_hooks_main "$@"
