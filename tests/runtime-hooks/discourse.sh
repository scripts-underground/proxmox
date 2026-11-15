#!/usr/bin/env bash
# shellcheck disable=SC2034,SC2154
# Callback inputs/outputs are supplied and consumed by the sourced harness.
set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/../lib/runtime-hooks/harness.sh"
app=discourse
variants=(fresh update download build)
hook_paths=()
runtime_hooks_model() {
  apt() { :; }
  setup_ruby() { :; }
  setup_deb822_repo() { :; }
  setup_postgresql_db() { export PG_DB_NAME PG_DB_USER PG_DB_PASS=fixture-db-secret; }
  setup_nodejs() {
    [[ "$APP_FAULT" != runtime ]] || return 51
    printf '%s\n' "$NODE_VERSION" > "$c/node-version"
  }
  rbenv() { printf ':\n'; }
  corepack() { printf '%s\n' "$*" >> "$c/corepack-calls"; }
  bundle() {
    printf '%s|%s|%s\n' "$PWD" "${RAILS_ENV:-unset}" "$*" >> "$c/bundle-calls"
    [[ "$APP_FAULT" != build ]] || return 52
    [[ "$PATH" == *"$HOME/.rbenv/shims"* && "${RAILS_ENV:-}" == production ]] || return 54
    [[ "${DISCOURSE_DB_PASSWORD:-}" == 'user db secret' ]] || [[ "$APP_ROLE" == install ]]
  }
  yarn() {
    printf '%s\n' "$*" >> "$c/yarn-calls"
    return 55
  }
  pnpm() {
    printf '%s|%s\n' "$PWD" "$*" >> "$c/pnpm-calls"
    [[ "$APP_FAULT" != build ]] || return 52
  }
  git() {
    [[ "$APP_FAULT" != download ]] || return 22
    if [[ "$1" == clone ]]; then
      mkdir -p /opt/discourse
      command cp -a "$c/payload/." /opt/discourse/
    elif [[ "$1" == pull ]]; then printf 'new code\n' > /opt/discourse/code; fi
  }
  runuser() { printf '%s\n' "$*" >> "$c/runuser-calls"; }
  nginx() {
    printf '%s\n' "$*" >> "$c/nginx-calls"
    [[ "$APP_FAULT" != nginx ]] || return 61
  }
  a2ensite() { :; }
}
runtime_hooks_expected() { [[ "$fault" != download ]] || expected=22; }
runtime_hooks_setup() {
  mkdir -p "$c/home/.rbenv/shims" "$c/etc/nginx/"{sites-available,sites-enabled} "$c/etc/postgresql/16/main"
  for log in corepack-calls bundle-calls yarn-calls pnpm-calls nginx-calls runuser-calls; do : > "$c/$log"; done
  printf 'local all all peer\n' > "$c/etc/postgresql/16/main/pg_hba.conf"
  if [[ "$role" == update ]]; then
    printf "RAILS_ENV=production\nDISCOURSE_DB_NAME=custom-discourse\nDISCOURSE_DB_PASSWORD='user db secret'\nSECRET_KEY_BASE='USER secret'\nDISCOURSE_HOSTNAME=forum.example.test:9443\n" > "$c/opt/discourse/.env"
    printf 'server {\n listen 9443;\n proxy_set_header X-Accel-Mapping /opt/discourse/public/=/downloads/;\n # USER custom rule\n}\n' > "$c/etc/nginx/sites-available/discourse"
    mkdir -p "$c/opt/discourse/public/uploads"
    printf 'USER forum upload\n' > "$c/opt/discourse/public/uploads/file"
  fi
}
runtime_hooks_assert() {
  runtime_hooks_configuration_assert
  if [[ "$role" == update ]]; then check "$(cat "$c/opt/discourse/public/uploads/file")" 'USER forum upload' "$app/$variant forum uploads retained"; fi
  if [[ "$rc" == 0 ]]; then
    check "$(grep -c 'discourse discourse-sidekiq' "$c/services" || true)" "$([[ "$role" == update ]] && printf 2 || printf 1)" "$app/$variant both service lifecycle participants"
    check "$(stat -c %s "$c/yarn-calls")" 0 "$app/$variant obsolete package manager never invoked"
    check "$(grep -c X-Accel-Mapping "$c/etc/nginx/sites-available/discourse" || true)" 0 "$app/$variant invalid stylesheet mapping removed"
  fi
}
runtime_hooks_main "$@"
