#!/usr/bin/env bash
# shellcheck disable=SC2034,SC2154
# Real cold bundles and file/marker consumers; package, migration and services modeled.
set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/../lib/runtime-hooks/harness.sh"
app=apache-airflow
script_type=lxc
variants=(update current pending package-failure migration-failure start-failure)
hook_paths=(/opt/airflow opt/apache-airflow)

runtime_hooks_variant() {
  case "$variant" in
    package-failure) fault=package ;;
    migration-failure) fault=migration ;;
    start-failure) fault=start ;;
  esac
}
runtime_hooks_model() {
  curl() { printf '{"info":{"version":"3.4.0"}}\n'; }
  uv() {
    printf '%s\n' "$*" >> "$c/packages"
    [[ "$APP_FAULT" != package ]] || return 53
    # uv normally leaves an already-satisfied package alone, even with missing files.
    if [[ ! -f "$c/installed" || " $* " == *' --reinstall '* ]]; then
      printf '3.4.0\n' > "$c/installed"
      cat > /opt/apache-airflow/.venv/bin/airflow << 'EOF'
#!/usr/bin/env bash
set -euo pipefail
[[ "${APP_FAULT:-none}" != migration ]] || exit 54
[[ "$*" != 'db migrate' ]] || printf 'migrated\n' >> "$APP_FIXTURE/migrations"
printf 'airflow-consumer-3.4.0\n'
EOF
      chmod 0755 /opt/apache-airflow/.venv/bin/airflow
    fi
  }
  systemctl() {
    if [[ "$1" == start && "$APP_FAULT" == start ]]; then
      printf 'failed-start\n' >> "$c/services"
      return 55
    fi
    printf '%s\n' "$*" >> "$c/services"
  }
}
runtime_hooks_setup() {
  : > "$c/packages"
  : > "$c/migrations"
  mkdir -p "$c/opt/apache-airflow/.venv/bin"
  printf 'SAVED_SETTING=preserved\n' > "$c/opt/apache-airflow/.env"
  printf '3.2.1\n' > "$c/home/.airflow"
  if [[ "$variant" == current || "$variant" == pending ]]; then
    printf '3.4.0\n' > "$c/home/.airflow"
    printf '3.4.0\n' > "$c/installed"
  fi
  printf '#!/bin/sh\nprintf old-airflow-consumer\n' > "$c/opt/apache-airflow/.venv/bin/airflow"
  chmod 0755 "$c/opt/apache-airflow/.venv/bin/airflow"
  if [[ "$variant" == pending ]]; then
    printf 'interrupted update\n' > "$c/state/$app"
    rm "$c/opt/apache-airflow/.venv/bin/airflow"
  fi
}
runtime_hooks_expected() {
  case "$fault" in package) expected=53 ;; migration) expected=54 ;; start) expected=55 ;; esac
}
runtime_hooks_assert() {
  runtime_hooks_configuration_assert
  if [[ "$rc" != 0 ]]; then
    check "$(cat "$c/home/.airflow")" 3.2.1 "$app/$variant failed update keeps prior completion marker"
  elif [[ "$variant" == current ]]; then
    check "$(wc -l < "$c/packages")" 0 "$app/current unforced latest remains a no-op"
    check "$(wc -l < "$c/services")" 0 "$app/current unforced no-op leaves services alone"
  else
    check "$("$c/opt/apache-airflow/.venv/bin/airflow" 2> /dev/null || true)" airflow-consumer-3.4.0 "$app/$variant executable consumer sees deployment"
    check "$(cat "$c/home/.airflow")" 3.4.0 "$app/$variant successful completion publishes version"
    check "$(wc -l < "$c/migrations")" 1 "$app/$variant migrates before completion"
  fi
}
runtime_hooks_retry_assert() {
  check "$("$c/opt/apache-airflow/.venv/bin/airflow")" airflow-consumer-3.4.0 "$app/$variant frozen pending retry redeploys executable"
  check "$(cat "$c/home/.airflow")" 3.4.0 "$app/$variant retry publishes successful version"
  check "$(tail -1 "$c/services")" 'start airflow-api-server airflow-scheduler airflow-dag-processor airflow-triggerer' "$app/$variant retry reaches services"
  check "$(cat "$c/opt/apache-airflow/.env")" SAVED_SETTING=preserved "$app/$variant retry retains saved settings"
}
runtime_hooks_main "$@"
