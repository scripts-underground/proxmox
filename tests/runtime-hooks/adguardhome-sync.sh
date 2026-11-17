#!/usr/bin/env bash
# shellcheck disable=SC2034,SC2154
set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/../lib/runtime-hooks/addon-release.sh"
app=adguardhome-sync
release_app=$app release_mode=prebuild release_asset=adguardhome-sync_2_linux_amd64.tar.gz
variants=(checker no-update selected download stopped-download copy copy-unrestored openrc-download)
runtime_hooks_variant() {
  case "$variant" in
    checker) fault=checker ;;
    download | stopped-download) fault=download ;;
    openrc-download) fault=openrc-download ;;
    copy | copy-unrestored) fault=$variant ;;
  esac
}
runtime_hooks_expected() {
  case "$fault" in checker) expected=17 ;; download | openrc-download) expected=250 ;; copy | copy-unrestored) expected=252 ;; esac
}
runtime_hooks_model() {
  addon_release_model
  [[ "$APP_FAULT" != openrc-download ]] || INIT_SYSTEM=openrc
  systemctl() { runtime_hooks_recovery_service "$@"; }
  rc-service() { runtime_hooks_recovery_service "$2" "$1"; }
  curl_download() {
    [[ "$APP_FAULT" != download && "$APP_FAULT" != openrc-download ]] || return 22
    addon_release_download "$@"
  }
  cp() {
    if [[ "$APP_FAULT" == copy || "$APP_FAULT" == copy-unrestored ]] && [[ "$*" == *'/deploy-source.'* && "${!#}" == /opt/* ]]; then
      command cp "$@"
      [[ "$APP_FAULT" != copy-unrestored ]] || printf 'unverified extra bytes\n' > /opt/adguardhome-sync/unowned-partial
      return 41
    fi
    command cp "$@"
  }
}
addon_release_setup() {
  mkdir -p "$c/config"
  printf 'operator config\n' > "$c/config/config.yaml"
  printf 'var_addon_config_path=%q\nvar_addon_backup_dir=%q\n' "$c/config/config.yaml" "$c/backup" > "$c/context.sh"
  : > "$c/opt/$app/adguardhome-sync"
  local initial=active
  [[ "$variant" != stopped-download ]] || initial=inactive
  runtime_hooks_recovery_setup adguardhome-sync "$initial" "$c/opt/$app" "$c/config/config.yaml"
}
eval "$(declare -f runtime_hooks_assert | sed '1s/runtime_hooks_assert/release_assert/')"
runtime_hooks_assert() {
  case "$variant" in checker | no-update | selected) release_assert ;; esac
  check "$(cat "$c/config/config.yaml")" 'operator config' "$app/$variant configuration retained"
}
addon_release_consumer_assert() { check "$(cat "$c/opt/$app/code")" 'new code' "$app selected source consumer"; }
runtime_hooks_retry_assert() {
  addon_release_consumer_assert
  if [[ "$variant" == stopped-download ]]; then
    check "$(cat "$c/recovery-state")" inactive "$app retry preserves initially stopped service"
    check "$(wc -l < "$c/recovery-starts")" 0 "$app retry never starts initially stopped service"
  fi
}
runtime_hooks_main "$@"
