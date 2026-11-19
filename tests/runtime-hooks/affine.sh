#!/usr/bin/env bash
# shellcheck disable=SC2034,SC2154
# Callback inputs/outputs are supplied and consumed by the sourced harness.
set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/../lib/runtime-hooks/harness.sh"
app=affine
script_type=lxc
variants=(fresh update current current-inactive no-worker custom-worker worker-dropin worker-query worker-stop worker-disable worker-reload checker web-start download build copy)
hook_paths=()
runtime_hooks_model() {
  apt() { printf '%s\n' "$*" >> "$c/packages"; }
  setup_postgresql_db() { export PG_DB_NAME PG_DB_USER PG_DB_PASS=fixture-db-secret; }
  setup_nodejs() { :; }
  setup_rust() { :; }
  corepack() { :; }
  git() {
    if [[ "$1" == commit && "$APP_ROLE" == update ]]; then
      # Source replacement can retain Husky's Git setup while dependencies are
      # absent, and a pending retry can have an identical source commit.
      [[ "${HUSKY:-}" == 0 ]] || return 53
      [[ " $* " == *' --allow-empty '* ]] || return 54
    fi
  }
  npm() { :; }
  ensure_dependencies() { printf '%s\n' "$*" >> "$c/prerequisites"; }
  nginx() {
    printf '%s\n' "$*" >> "$c/nginx"
    : > "$c/nginx-validated"
  }
  systemctl() {
    printf '%s\n' "$*" >> "$c/services"
    case "$*" in
      'show --property=DropInPaths --value affine-worker.service')
        [[ "$APP_FAULT" != worker-query ]] || return 59
        [[ ! -f "$c/worker-dropins" ]] || cat "$c/worker-dropins"
        ;;
      'stop affine-worker') [[ "$APP_FAULT" != worker-stop ]] || return 51 ;;
      'disable affine-worker') [[ "$APP_FAULT" != worker-disable ]] || return 51 ;;
      'daemon-reload')
        [[ "$APP_FAULT" != worker-reload || -f "$c/etc/systemd/system/affine-worker.service" ]] || return 51
        if [[ -f "$c/etc/systemd/system/affine-worker.service" ]]; then
          printf 'present\n' > "$c/manager-worker"
        else
          printf 'absent\n' > "$c/manager-worker"
        fi
        ;;
      'stop affine-web') printf 'inactive\n' > "$c/web-state" ;;
      'start affine-web')
        [[ "$APP_FAULT" != web-start ]] || return 51
        printf 'active\n' > "$c/web-state"
        ;;
      'enable -q --now redis-server affine-web') printf 'active\n' > "$c/web-state" ;;
      'reload-or-restart nginx')
        [[ -f "$c/nginx-validated" ]] || return 51
        : > "$c/nginx-activated"
        ;;
    esac
  }
  yarn() {
    printf '%s\n' "$*" >> "$c/builds"
    [[ "$APP_FAULT" != build ]] || return 52
  }
  node() {
    [[ -f /opt/affine/.env ]] || return 58
    printf '%s\n' "${DATABASE_URL:-unset}" > "$c/migration-database"
  }
  curl() {
    [[ "$APP_FAULT" != checker ]] || return 28
    local out='' url='' format='' body tag=v2.0.0
    while (($#)); do
      case "$1" in
        -o)
          out="$2"
          shift
          ;;
        -w)
          format="$2"
          shift
          ;;
        http:*) url="$1" ;;
        https:*) url="$1" ;;
      esac
      shift
    done
    [[ "$url" != *'/tags/'* ]] || tag=${url##*/}
    if [[ "$url" == *create-admin-user ]]; then body='{"id":"fixture-admin"}'; else body="{\"tag_name\":\"$tag\",\"assets\":[]}"; fi
    if [[ -n "$out" ]]; then printf '%s' "$body" > "$out"; else printf '%s' "$body"; fi
    [[ -z "$format" ]] || printf 200
  }
}
runtime_hooks_variant() {
  case "$variant" in
    custom-worker | worker-dropin | worker-query | worker-stop | worker-disable | worker-reload | checker | web-start) fault="$variant" ;;
  esac
}
runtime_hooks_expected() {
  case "$fault" in
    custom-worker | worker-dropin) expected=65 ;;
    worker-query) expected=59 ;;
    worker-stop | worker-disable | worker-reload | web-start) expected=51 ;;
    checker) expected=28 ;;
  esac
}
runtime_hooks_setup() {
  mkdir -p "$c/root/.affine/"{storage,config} "$c/etc/nginx/"{sites-available,sites-enabled}
  : > "$c/root/.profile"
  printf 'old\n' > "$c/home/.affine_app"
  for log in builds packages prerequisites nginx; do : > "$c/$log"; done
  printf 'active\n' > "$c/web-state"
  [[ "$role" != install ]] || printf 'inactive\n' > "$c/web-state"
  printf 'present\n' > "$c/manager-worker"
  mkdir -p "$c/payload/packages/backend/"{native,server/scripts} \
    "$c/payload/packages/frontend/apps/web/dist" "$c/payload/packages/frontend/admin/dist"
  printf 'web asset\n' > "$c/payload/packages/frontend/apps/web/dist/index.html"
  printf 'admin asset\n' > "$c/payload/packages/frontend/admin/dist/index.html"
  # Archive defaults must never replace an existing operator environment.
  printf 'DATABASE_URL=archive-default\n' > "$c/payload/.env"
  if [[ "$role" == update ]]; then
    printf "DATABASE_URL='postgresql://custom:secret@db.example.test/custom'\nSECRET_KEY='USER original secret'\nAFFINE_SERVER_EXTERNAL_URL=https://notes.example.test\n" > "$c/opt/affine/.env"
    printf 'USER blob\n' > "$c/root/.affine/storage/canary"
    printf 'USER configuration\n' > "$c/root/.affine/config/canary"
    cat << 'UNIT' > "$c/etc/systemd/system/affine-worker.service"
[Unit]
Description=AFFiNE Background Worker
After=network.target postgresql.service redis-server.service
Requires=postgresql.service redis-server.service

[Service]
Type=simple
WorkingDirectory=/opt/affine/packages/backend/server
EnvironmentFile=/opt/affine/.env
Environment=LD_PRELOAD=libjemalloc.so.2
Environment=NODE_OPTIONS=--max-old-space-size=1024
ExecStart=/usr/bin/node ./dist/main.js --worker
Restart=always
RestartSec=10

[Install]
WantedBy=multi-user.target
UNIT
    case "$variant" in
      no-worker) rm "$c/etc/systemd/system/affine-worker.service" ;;
      custom-worker) printf '# USER customization\n' >> "$c/etc/systemd/system/affine-worker.service" ;;
      worker-dropin) printf '%s\n' "$c/etc/systemd/system/affine-worker.service.d/override.conf" > "$c/worker-dropins" ;;
      current | current-inactive) printf '2.0.0\n' > "$c/home/.affine_app" ;;
    esac
    [[ "$variant" != current-inactive ]] || printf 'inactive\n' > "$c/web-state"
    if [[ -f "$c/etc/systemd/system/affine-worker.service" ]]; then
      sha256sum "$c/etc/systemd/system/affine-worker.service" | cut -d' ' -f1 > "$c/worker-before"
    fi
  fi
}
runtime_hooks_assert() {
  runtime_hooks_configuration_assert
  if [[ "$role" == update ]]; then
    check "$(cat "$c/root/.affine/storage/canary")" 'USER blob' "$app/$variant live storage preserved"
    check "$(cat "$c/root/.affine/config/canary")" 'USER configuration' "$app/$variant live config preserved"
  fi
  case "$fault" in
    custom-worker | worker-dropin | worker-query | worker-stop | worker-disable | checker)
      check "$(sha256sum "$c/etc/systemd/system/affine-worker.service" | cut -d' ' -f1)" "$(cat "$c/worker-before")" "$app/$variant refused retirement retains worker unit"
      check "$(stat -c %s "$c/builds")" 0 "$app/$variant refusal precedes app replacement/build"
      check "$(cat "$c/opt/affine/code")" 'old code' "$app/$variant refusal preserves installed source"
      ;;
  esac
  case "$fault" in
    custom-worker | worker-dropin | worker-query | checker)
      check "$(grep -Ec '^(stop|disable) affine-worker$' "$c/services" || true)" 0 "$app/$variant admission refusal preserves the existing worker listener"
      ;;
  esac
  if [[ "$rc" == 0 ]]; then
    if [[ "$role" == install ]]; then
      check "$(grep -cE '(^| )cmake( |$)' "$c/packages" || true)" 1 "$app/$variant fresh compiler dependency installed"
    elif [[ "$variant" != current && "$variant" != current-inactive ]]; then
      check "$(cat "$c/migration-database")" 'postgresql://custom:secret@db.example.test/custom' "$app/$variant migration consumes saved database configuration"
      check "$(grep -c '^cmake$' "$c/prerequisites" || true)" 1 "$app/$variant installed compiler dependency ensured"
    fi
    if [[ "$variant" != current && "$variant" != current-inactive ]]; then
      check "$(cat "$c/opt/affine/packages/backend/server/static/index.html")" 'web asset' "$app/$variant web output reaches served root"
      check "$(cat "$c/opt/affine/packages/backend/server/static/admin/index.html")" 'admin asset' "$app/$variant admin output reaches served root"
    fi
    runtime_hooks_services_assert
  fi
}
runtime_hooks_services_assert() {
  check "$(cat "$c/web-state")" active "$app/$variant supported HTTP service active at completion"
  check "$(test -e "$c/etc/systemd/system/affine-worker.service" && printf present || printf absent)" absent "$app/$variant obsolete worker unit absent"
  check "$(grep -Ec '(start|--now).*affine-worker' "$c/services" || true)" 0 "$app/$variant never starts duplicate HTTP worker"
  check "$(test -e "$c/nginx-activated" && printf yes || printf no)" yes "$app/$variant validated nginx configuration activated"
  if [[ "$role" == update && "$variant" != no-worker ]]; then
    check "$(grep -q '^stop affine-worker$' "$c/services" && printf yes || printf no)" yes "$app/$variant legacy worker stopped"
    check "$(grep -q '^disable affine-worker$' "$c/services" && printf yes || printf no)" yes "$app/$variant legacy worker disabled"
    check "$(cat "$c/manager-worker")" absent "$app/$variant retired unit removed from manager"
  fi
  if [[ "$role" == update && "$variant" != current && "$variant" != current-inactive ]]; then
    local stop_line start_line
    stop_line=$(grep -n '^stop affine-web$' "$c/services" | tail -1 | cut -d: -f1)
    start_line=$(grep -n '^start affine-web$' "$c/services" | tail -1 | cut -d: -f1)
    check "$([[ -n "$stop_line" && -n "$start_line" ]] && ((start_line > stop_line)) && printf yes || printf no)" yes "$app/$variant supported service starts after the final stop"
  fi
}
runtime_hooks_retry_assert() {
  runtime_hooks_configuration_assert
  check "$(cat "$c/migration-database")" 'postgresql://custom:secret@db.example.test/custom' "$app/$variant pending retry consumes saved configuration"
  runtime_hooks_services_assert
}
runtime_hooks_failure_services_assert() {
  local expected_starts=0
  [[ "$fault" != web-start ]] || expected_starts=1
  check "$(grep -Ec '^(start|reload|restart)|--now' "$c/services" || true)" "$expected_starts" "$app/$variant failure admits only its explicit failed-start attempt"
  if [[ "$fault" == web-start ]]; then
    check "$(cat "$c/web-state")" inactive "$app/$variant failed start leaves the backend inactive for pending retry"
  fi
}
runtime_hooks_retry_needed() {
  [[ "$role" == update && "$expected" != 0 && "$fault" != custom-worker && "$fault" != worker-dropin ]]
}
runtime_hooks_main "$@"
