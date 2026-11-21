#!/usr/bin/env bash
# shellcheck disable=SC2034,SC2154
# Callback inputs/outputs are supplied and consumed by the sourced harness.
set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/../lib/runtime-hooks/harness.sh"
app=asterisk
script_type=lxc
variants=(fresh start-failure update pending)
hook_paths=()
runtime_hooks_model() {
  apt() { :; }
  curl() {
    case "$*" in
      *certified-asterisk/) printf 'asterisk-certified-22.8-cert5.tar.gz\n' ;;
      *asterisk/) printf 'asterisk-23.6.0.tar.gz\nasterisk-24.0.0.tar.gz\n' ;;
      *) command cp "$c/release.tar.gz" "${!#}" ;;
    esac
  }
  make() {
    printf '%s\n' "$*" >> "$c/make-calls"
    [[ "$1" != config ]] || : > "$c/sysv-installed"
  }
  systemctl() {
    # Native Debian SysV compatibility enables but does not honor --now.
    if [[ "$1" == enable ]]; then
      test -f "$c/sysv-installed"
      printf 'enable\n' >> "$c/services"
    elif [[ "$1" == start ]]; then
      if [[ "$APP_FAULT" == runtime ]]; then
        printf 'failed-start\n' >> "$c/services"
        return 51
      fi
      printf 'start\n' >> "$c/services"
      printf 'running\n' > "$c/consumer-state"
    fi
  }
}
runtime_hooks_variant() {
  if [[ "$variant" == start-failure ]]; then role=install fault=runtime; fi
}
runtime_hooks_setup() {
  : > "$c/make-calls"
  printf '1\n' > "$c/stdin"
  mkdir -p "$c/payload/contrib/scripts" "$c/etc/radcli" "$c/etc/asterisk"
  printf '#!/bin/sh\nexit 0\n' > "$c/payload/configure"
  printf '#!/bin/sh\nexit 0\n' > "$c/payload/contrib/scripts/install_prereq"
  chmod 0755 "$c/payload/configure" "$c/payload/contrib/scripts/install_prereq"
  tar -czf "$c/release.tar.gz" -C "$c" payload
  printf 'saved radius settings\n' > "$c/etc/radcli/radiusclient.conf"
  printf 'saved dialplan\n' > "$c/etc/asterisk/extensions.conf"
  if [[ "$role" == update ]]; then
    printf 'running\n' > "$c/consumer-state"
    [[ "$variant" != pending ]] || printf 'interrupted\n' > "$c/state/asterisk"
  fi
}
runtime_hooks_assert() {
  check "$(cat "$c/etc/asterisk/extensions.conf")" 'saved dialplan' "$app/$variant preserves dialplan"
  if [[ "$role" == install && "$rc" != 0 ]]; then
    check "$(grep -c 'Installed Asterisk' "$c/output" || true)" 0 "$app/$variant failed start never publishes installation success"
  fi
  if [[ "$rc" == 0 ]]; then
    check "$(cat "$c/consumer-state" 2> /dev/null || true)" running "$app/$variant consumer is running"
    if [[ "$role" == install ]]; then
      check "$(cat "$c/services")" $'enable\nstart' "$app/$variant separately enables and starts SysV service"
    else
      check "$(stat -c %s "$c/services")" 0 "$app/$variant documented manual rebuild policy has no service effects"
      check "$(stat -c %s "$c/make-calls")" 0 "$app/$variant generated updater does not rebuild source"
    fi
  fi
}
runtime_hooks_main "$@"
