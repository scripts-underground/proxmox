#!/usr/bin/env bash
# shellcheck disable=SC2034,SC2154
# Callback inputs/outputs are supplied and consumed by the sourced harness.
set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/../lib/runtime-hooks/harness.sh"
app=radicale
variants=(fresh update download copy runtime)
hook_paths=(/var/lib/radicale radicale-data)
runtime_hooks_model() {
  apt() { :; }
  setup_uv() {
    [[ "$APP_FAULT" != runtime ]] || return 51
    printf '%s\n' "$PYTHON_VERSION" > "$c/python-version"
  }
  htpasswd() { printf 'admin:fixture-hash\n' > /opt/radicale/users; }
  uv() {
    printf '%s\n' "$*" >> "$c/uv-calls"
    if [[ "$*" == *'python -'* ]]; then
      while [[ "$1" != python ]]; do shift; done
      shift
      /usr/bin/python3 "$@"
    fi
  }
  curl() {
    local out='' url='' format='' body tag=v2.0.0
    while (($#)); do
      case "$1" in -o)
        out="$2"
        shift
        ;;
      -w)
        format="$2"
        shift
        ;;
      https:*) url="$1" ;; esac
      shift
    done
    [[ "$url" != *'/tags/'* ]] || tag=${url##*/}
    body="{\"tag_name\":\"$tag\",\"assets\":[]}"
    if [[ -n "$out" ]]; then printf '%s' "$body" > "$out"; else printf '%s' "$body"; fi
    [[ -z "$format" ]] || printf 200
  }
}
runtime_hooks_setup() {
  : > "$c/uv-calls"
  cp "$MAINTENANCE_REFERENCES/radicale/pyproject.toml" "$c/payload/pyproject.toml"
  mkdir -p "$c/radicale-data" "$c/etc/radicale"
  printf 'USER calendar\n' > "$c/radicale-data/calendar"
  printf '[server]\nhosts=127.0.0.1:5522\n[auth]\nhtpasswd_filename=/opt/radicale/custom users\n[storage]\nfilesystem_folder=/opt/radicale/custom calendars\n' > "$c/etc/radicale/config"
  if [[ "$role" == update ]]; then
    mkdir -p "$c/opt/radicale/custom calendars"
    printf 'USER auth hashes\n' > "$c/opt/radicale/custom users"
    printf 'USER calendar\n' > "$c/opt/radicale/custom calendars/calendar"
    printf 'USER default auth\n' > "$c/opt/radicale/users"
    printf '[Unit]\nDescription=Custom Radicale\n[Service]\nWorkingDirectory=/opt/radicale\nExecStart=/usr/local/bin/uv run -m radicale --config %s/etc/radicale/config\nRestart=always\nEnvironment=USER_PORT=5522\n' "$c" > "$c/etc/systemd/system/radicale.service"
  fi
}
runtime_hooks_assert() {
  runtime_hooks_configuration_assert
  if [[ "$rc" == 0 ]]; then check "$(grep -c -- '--extra bcrypt --extra argon2' "$c/etc/systemd/system/radicale.service" || true)" 1 "$app/$variant supported metadata extras reach service"; fi
  if [[ "$role" == update ]]; then
    check "$(cat "$c/opt/radicale/custom users" 2> /dev/null || true)" 'USER auth hashes' "$app/$variant configured custom users retained"
    check "$(cat "$c/opt/radicale/custom calendars/calendar" 2> /dev/null || true)" 'USER calendar' "$app/$variant configured custom calendar retained"
    check "$(grep -c USER_PORT=5522 "$c/etc/systemd/system/radicale.service")" 1 "$app/$variant existing unit port setting retained"
  fi
}
runtime_hooks_main "$@"
