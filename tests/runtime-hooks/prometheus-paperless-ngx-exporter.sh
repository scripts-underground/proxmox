#!/usr/bin/env bash
# shellcheck disable=SC2034,SC2154
set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/../lib/runtime-hooks/addon-release.sh"
app=prometheus-paperless-ngx-exporter
release_app=prom-paperless-exp release_mode=binary release_asset=prometheus-paperless-exporter_2_amd64.deb
variants+=(uninstall download stopped-download package-intact package-partial stop stopped-selected stopped-no-update)
eval "$(declare -f runtime_hooks_variant | sed '1s/runtime_hooks_variant/release_variant/')"
runtime_hooks_variant() {
  release_variant
  [[ "$variant" != uninstall ]] || role=uninstall
  case "$variant" in stopped-download) fault=download ;; package-* | stop) fault=$variant ;; esac
}
runtime_hooks_expected() {
  case "$fault" in checker) expected=17 ;; package-*) expected=43 ;; stop) expected=47 ;; esac
}
addon_release_setup() {
  : > "$c/local/bin/prometheus-paperless-exporter"
  printf 'var_addon_bin_path=/usr/local/bin/prometheus-paperless-exporter\n' > "$c/context.sh"
  mkdir -p "$c/etc/prometheus-paperless-ngx-exporter" "$c/etc/systemd/system"
  printf 'operator unit and drop-in contract\n' > "$c/etc/systemd/system/$app.service"
  printf 'foreign marker\n' > "$c/home/.foreign"
  if [[ "$role" == update ]]; then
    printf 'operator URL\n' > "$c/etc/prometheus-paperless-ngx-exporter/config.env"
    printf 'operator token\n' > "$c/etc/prometheus-paperless-ngx-exporter/paperless_auth_token_file"
    chmod 0600 "$c/etc/prometheus-paperless-ngx-exporter/paperless_auth_token_file"
    local initial=active
    [[ "$variant" != stopped-* ]] || initial=inactive
    [[ "$variant" != stopped-no-update ]] || printf '2.0.0\n' > "$c/home/.prom-paperless-exp"
    runtime_hooks_recovery_setup "$app" "$initial" "$c/local/bin/prometheus-paperless-exporter" "$c/etc/prometheus-paperless-ngx-exporter" "$c/etc/systemd/system/$app.service"
  fi
}
runtime_hooks_model() {
  addon_release_model
  _deploy_release_deb() {
    [[ "$APP_FAULT" != package-intact ]] || return 43
    cat "$1" > "$c/package-consumer"
    printf 'selected executable\n' > "$c/local/bin/prometheus-paperless-exporter"
    [[ "$APP_FAULT" != package-partial ]] || return 43
  }
  curl_download() {
    [[ "$APP_FAULT" != download ]] || return 22
    addon_release_download "$@"
  }
  systemctl() {
    [[ "$APP_FAULT/$1" != stop/stop ]] || return 47
    if [[ -f "$c/recovery-service" ]]; then
      runtime_hooks_recovery_service "$@"
    else
      printf '%s\n' "$*" >> "$c/services"
      if [[ "$1" == show ]]; then printf 'LoadState=loaded\nActiveState=active\nUnitFileState=enabled\n'; fi
    fi
  }
  dpkg() { :; }
}
eval "$(declare -f runtime_hooks_assert | sed '1s/runtime_hooks_assert/release_assert/')"
runtime_hooks_assert() {
  if [[ "$role" == uninstall ]]; then
    check "$(test -e "$c/home/.prom-paperless-exp" && printf present || printf absent)" absent "$app removes actual release marker"
    check "$(cat "$c/home/.foreign")" 'foreign marker' "$app retains unrelated release marker"
  else
    case "$variant" in checker | no-update | selected) release_assert ;; esac
    check "$(cat "$c/etc/systemd/system/$app.service")" 'operator unit and drop-in contract' "$app update preserves operator service"
    check "$(cat "$c/etc/prometheus-paperless-ngx-exporter/config.env")" 'operator URL' "$app/$variant operator URL retained"
    check "$(cat "$c/etc/prometheus-paperless-ngx-exporter/paperless_auth_token_file")" 'operator token' "$app/$variant token retained"
    if [[ "$variant" == stopped-selected || "$variant" == stopped-no-update ]]; then
      check "$(cat "$c/recovery-state")" inactive "$app/$variant successful update leaves initially stopped service stopped"
      check "$(wc -l < "$c/recovery-starts")" 0 "$app/$variant successful update never starts initially stopped service"
    fi
  fi
}
addon_release_consumer_assert() { check "$(cat "$c/package-consumer")" 'selected v2.0.0' "$app selected package consumer"; }
runtime_hooks_retry_assert() {
  addon_release_consumer_assert
  if [[ "$variant" == stopped-download ]]; then
    check "$(cat "$c/recovery-state")" inactive "$app retry leaves initially stopped service stopped"
    check "$(wc -l < "$c/recovery-starts")" 0 "$app retry never starts initially stopped service"
  fi
}
runtime_hooks_main "$@"
