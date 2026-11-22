#!/usr/bin/env bash
# shellcheck disable=SC2034,SC2154
# Real cold bundle/release/persistence owners; npm and systemd effects are modeled.
set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/../lib/runtime-hooks/harness.sh"
app=bytestash
script_type=lxc
variants=(fresh update current legacy-admin missing checker pending build download copy runtime)
hook_paths=()
runtime_hooks_model() {
  setup_nodejs() { :; }
  mv() {
    if [[ "${!#}" == "$c/etc/systemd/system/bytestash-backend.service" ]]; then
      stat -c %a "${@: -2:1}" > "$c/unit-stage-mode"
    fi
    command mv "$@"
  }
  npm() {
    printf '%s\n' "$PWD $*" >> "$c/npm"
    [[ "$APP_FAULT" != build ]] || return 52
  }
  systemctl() {
    if [[ "$1" == start && "$APP_FAULT" == runtime ]]; then
      printf 'failed-start %s\n' "${*:2}" >> "$c/services"
      return 51
    fi
    printf '%s\n' "$*" >> "$c/services"
  }
  curl() {
    [[ "$APP_FAULT" != checker ]] || return 28
    local out='' format='' tag=v1.6.2 latest=0
    while (($#)); do
      case "$1" in
        -o)
          out=$2
          shift
          ;;
        -w)
          format=$2
          shift
          ;;
        */tags/*) tag=${1##*/} ;;
        */releases/latest) latest=1 ;;
      esac
      shift
    done
    if [[ "$latest" == 1 ]]; then
      local count=0 counter="$c/latest-$APP_ROLE-$APP_FAULT"
      [[ ! -f "$counter" ]] || count=$(cat "$counter")
      count=$((count + 1))
      printf '%s' "$count" > "$counter"
      [[ "$count" == 1 ]] || tag=v1.6.3
    fi
    local body="{\"tag_name\":\"$tag\",\"assets\":[]}"
    if [[ -n "$out" ]]; then printf '%s' "$body" > "$out"; else printf '%s' "$body"; fi
    [[ -z "$format" ]] || printf 200
  }
}
runtime_hooks_variant() { [[ "$variant" != checker ]] || fault=$variant; }
runtime_hooks_expected() {
  [[ "$fault" != checker ]] || expected=28
  [[ "$variant" != missing ]] || expected=1
}
runtime_hooks_setup() {
  : > "$c/npm"
  mkdir -p "$c/payload/"{client,server,data/snippets}
  printf 'archive default\n' > "$c/payload/data/snippets/canary"
  printf 'n\n' > "$c/stdin"
  if [[ "$role" == update ]]; then
    mkdir -p "$c/opt/bytestash/"{client,server,data/snippets} "$c/opt/data"
    printf 'saved database\n' > "$c/opt/bytestash/data/snippets/canary"
    printf 'persisted JWT\n' > "$c/opt/bytestash/data/snippets/.jwt_secret"
    chmod 0600 "$c/opt/bytestash/data/snippets/.jwt_secret"
    printf 'legacy data\n' > "$c/opt/data/canary"
    printf '[Service]\nEnvironment=JWT_SECRET=fixture-secret\n' > "$c/etc/systemd/system/bytestash-backend.service"
    if [[ "$variant" == legacy-admin ]]; then
      : > "$c/legacy-admin"
      printf 'Environment=ADMIN_USERNAMES=legacy-admin\n' >> "$c/etc/systemd/system/bytestash-backend.service"
    fi
    chmod 0644 "$c/etc/systemd/system/bytestash-backend.service"
    stat -c %i "$c/etc/systemd/system/bytestash-backend.service" > "$c/unit-inode"
    sha256sum "$c/etc/systemd/system/bytestash-backend.service" | cut -d' ' -f1 > "$c/unit-hash"
    case "$variant" in current | pending) printf '1.6.2\n' > "$c/home/.bytestash" ;; esac
    [[ "$variant" != pending ]] || printf 'interrupted\n' > "$c/state/bytestash"
    [[ "$variant" != missing ]] || mv "$c/opt/bytestash" "$c/opt/bytestash-missing-fixture"
  fi
}
runtime_hooks_assert() {
  if [[ "$variant" == missing ]]; then
    check "$(test -d "$c/opt/bytestash" && printf present || printf absent)" absent "$app/missing absent installation not recreated"
    check "$(stat -c %s "$c/npm")" 0 "$app/missing no dependency work"
    check "$(stat -c %s "$c/services")" 0 "$app/missing no service effects"
    return
  fi
  runtime_hooks_configuration_assert
  if [[ "$role" == update ]]; then
    check "$(cat "$c/opt/bytestash/data/snippets/canary")" 'saved database' "$app/$variant live data preserved"
    check "$(cat "$c/opt/bytestash/data/snippets/.jwt_secret")" 'persisted JWT' "$app/$variant JWT bytes preserved"
    check "$(cat "$c/opt/data/canary")" 'legacy data' "$app/$variant legacy path untouched"
    check "$(stat -c %i "$c/etc/systemd/system/bytestash-backend.service")" "$(cat "$c/unit-inode")" "$app/$variant unit inode retained"
    check "$(sha256sum "$c/etc/systemd/system/bytestash-backend.service" | cut -d' ' -f1)" "$(cat "$c/unit-hash")" "$app/$variant secret and operator settings unchanged"
    if [[ "$fault" == checker ]]; then
      check "$(grep -Ec '^(stop|start) ' "$c/services" || true)" 0 "$app/$variant failed preflight never stops service"
      check "$(cat "$c/opt/bytestash/code")" 'old code' "$app/$variant failed preflight retains code"
    fi
  fi
  if [[ "$rc" == 0 ]]; then
    check "$(stat -c %a "$c/etc/systemd/system/bytestash-backend.service")" 600 "$app/$variant secret-bearing unit private"
    if [[ "$role" == install ]]; then
      check "$(cat "$c/unit-stage-mode" 2> /dev/null || printf missing)" 600 "$app/fresh unit private before atomic publication"
    fi
    if [[ "$role" == update ]]; then
      check "$(grep -c 'ADMIN_USERNAMES.*ignored' "$c/output" || true)" 1 "$app/$variant obsolete setting warning"
      check "$(grep -c 'node src/scripts/admin.js grant <username>' "$c/output" || true)" 1 "$app/$variant explicit operator CLI command"
    fi
    if [[ "$variant" == current ]]; then
      check "$(stat -c %s "$c/npm")" 0 "$app/current same-version no build"
    else
      check "$(wc -l < "$c/npm")" 2 "$app/$variant both dependencies installed"
      check "$(cat "$c/opt/bytestash/code")" 'new code' "$app/$variant release deployed"
      check "$(cat "$c/home/.bytestash")" 1.6.2 "$app/$variant checker-selected release deployed without a second latest selection"
    fi
  fi
}
runtime_hooks_retry_assert() {
  runtime_hooks_configuration_assert
  check "$(cat "$c/opt/bytestash/code")" 'new code' "$app/$variant pending retry deploys source"
  check "$(cat "$c/opt/bytestash/data/snippets/canary")" 'saved database' "$app/$variant pending retry retains data"
  check "$(stat -c %a "$c/etc/systemd/system/bytestash-backend.service")" 600 "$app/$variant pending retry retains private unit"
}
runtime_hooks_retry_needed() { [[ "$role" == update && "$expected" != 0 && "$variant" != missing ]]; }
runtime_hooks_more_cases() {
  check "$(grep -Fc 'node src/scripts/admin.js grant <username>' "$ROOT/_lxc/bytestash.md" || true)" 1 "$app/catalogue explicit upstream admin command"
  check "$(grep -Fc '/etc/systemd/system/bytestash-backend.service' "$ROOT/_lxc/bytestash.md" || true)" 1 "$app/catalogue actual configured JWT location"
  check "$(grep -Fc 'The first account created is the admin account.' "$ROOT/_lxc/bytestash.md" || true)" 0 "$app/catalogue no automatic admin promise"
}
runtime_hooks_main "$@"
