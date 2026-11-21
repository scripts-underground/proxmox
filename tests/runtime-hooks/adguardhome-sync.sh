#!/usr/bin/env bash
# runtime-hooks-contract: addon intent-preserving
# shellcheck disable=SC2034,SC2154
set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/../lib/runtime-hooks/addon-release.sh"
app=adguardhome-sync
release_app=$app release_mode=prebuild release_asset=adguardhome-sync_2_linux_amd64.tar.gz
variants=(checker no-update selected stop download stopped-download copy copy-unrestored openrc-download external-download external-selected backup-store backup-copy stopped-backup)
runtime_hooks_variant() {
  case "$variant" in
    checker | stop) fault=$variant ;;
    download | stopped-download | external-download) fault=download ;;
    openrc-download) fault=openrc-download ;;
    copy | copy-unrestored) fault=$variant ;;
    backup-store | stopped-backup) fault=backup-store ;;
    backup-copy) fault=backup-copy ;;
  esac
}
runtime_hooks_expected() {
  case "$fault" in checker) expected=17 ;; stop) expected=47 ;; download | openrc-download) expected=250 ;; copy | copy-unrestored) expected=252 ;; backup-store) expected=73 ;; backup-copy) expected=74 ;; esac
}
runtime_hooks_model() {
  addon_release_model
  [[ "$APP_FAULT" != openrc-download ]] || INIT_SYSTEM=openrc
  systemctl() {
    [[ "$1/$APP_FAULT" != stop/stop ]] || return 47
    runtime_hooks_recovery_service "$@"
  }
  rc-service() { runtime_hooks_recovery_service "$2" "$1"; }
  curl_download() {
    [[ "$APP_FAULT" != download && "$APP_FAULT" != openrc-download ]] || return 22
    addon_release_download "$@"
  }
  mkdir() {
    [[ "$APP_FAULT" != backup-store || "${!#}" != "$var_addon_backup_dir" ]] || return 73
    command mkdir "$@"
  }
  cp() {
    [[ "$APP_FAULT" != backup-copy || "${!#}" != "$var_addon_backup_dir/"*/files* ]] || return 74
    if [[ "$APP_FAULT" == copy || "$APP_FAULT" == copy-unrestored ]] && [[ "$*" == *'/deploy-source.'* && "${!#}" == /opt/* ]]; then
      command cp "$@"
      [[ "$APP_FAULT" != copy-unrestored ]] || printf 'unverified extra bytes\n' > /opt/adguardhome-sync/unowned-partial
      return 41
    fi
    command cp "$@"
  }
}
addon_release_setup() {
  mkdir -p "$c/opt/$app/settings" "$c/payload/settings"
  printf 'operator config\n' > "$c/opt/$app/settings/operator config.yaml"
  chmod 0600 "$c/opt/$app/settings/operator config.yaml"
  stat -c '%d:%i' "$c/opt/$app/settings/operator config.yaml" > "$c/config-inode"
  printf 'release config\n' > "$c/payload/settings/operator config.yaml"
  : > "$c/payload/adguardhome-sync"
  printf 'var_addon_config_path=%q\nvar_addon_backup_dir=%q\nvar_addon_service=custom-sync\n' "/opt/$app/settings/operator config.yaml" "$c/backup" > "$c/context.sh"
  config_file="$c/opt/$app/settings/operator config.yaml"
  if [[ "$variant" == external-* ]]; then
    mkdir -p "$c/config"
    config_file="$c/config/config.yaml"
    printf 'operator config\n' > "$config_file"
    chmod 0600 "$config_file"
    stat -c '%d:%i' "$config_file" > "$c/config-inode"
    printf 'var_addon_config_path=%q\nvar_addon_backup_dir=%q\nvar_addon_service=custom-sync\n' "$config_file" "$c/backup" > "$c/context.sh"
  fi
  : > "$c/opt/$app/adguardhome-sync"
  local initial=active
  case "$variant" in stopped-download | stopped-backup) initial=inactive ;; esac
  local -a footprint=("$c/opt/$app")
  [[ "$variant" != external-* ]] || footprint+=("$c/config")
  runtime_hooks_recovery_setup custom-sync "$initial" "${footprint[@]}"
}
eval "$(declare -f runtime_hooks_assert | sed '1s/runtime_hooks_assert/release_assert/')"
runtime_hooks_assert() {
  case "$variant" in checker | no-update | selected) release_assert ;; esac
  [[ "$variant" != external-selected ]] || addon_release_consumer_assert
  check "$(cat "$config_file" 2> /dev/null || true)" 'operator config' "$app/$variant config remains live"
  check "$(stat -c '%d:%i' "$config_file" 2> /dev/null || true)" "$(cat "$c/config-inode")" "$app/$variant config inode retained"
  check "$(stat -c %a "$config_file" 2> /dev/null || true)" 600 "$app/$variant config mode retained"
  if [[ "$fault" == stop ]]; then check "$(stat -c %s "$c/downloads")" 0 "$app refused stop prevents replacement"; fi
}
addon_release_consumer_assert() {
  local backup_input="/opt/$app/settings/operator config.yaml"
  [[ "$variant" != external-* ]] || backup_input="$c/config/config.yaml"
  runtime_hooks_backup_assert "$c/backup" "$backup_input" 'operator config'
  check "$(test -e "$c/backup/.manifest" && printf stale || printf scoped)" scoped "$app success never leaves reusable unscoped backup manifest"
  check "$(cat "$c/opt/$app/code")" 'new code' "$app selected source consumer"
  check "$(cat "$config_file")" 'operator config' "$app consumer retains config"
  check "$(stat -c '%d:%i' "$config_file")" "$(cat "$c/config-inode")" "$app consumer retains config inode"
}
runtime_hooks_retry_assert() {
  addon_release_consumer_assert
  if [[ "$variant" == stopped-download || "$variant" == stopped-backup ]]; then
    check "$(cat "$c/recovery-state")" inactive "$app retry preserves initially stopped service"
    check "$(wc -l < "$c/recovery-starts")" 0 "$app retry never starts initially stopped service"
  fi
}
runtime_hooks_main "$@"
