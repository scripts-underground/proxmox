#!/usr/bin/env bash
# External HTTP/package/service models; real release/backup/pending owners.
# shellcheck disable=SC2034,SC2154
set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/../lib/runtime-hooks/harness.sh"
app=cronmaster
script_type=addon
variants=(fresh update checker download stop uninstall stopped-download stopped-update copy copy-unrestored backup)
hook_paths=()
runtime_hooks_variant() {
  case "$variant" in
    checker | stop | copy | copy-unrestored | backup) fault=$variant ;;
    stopped-download) fault=download ;;
    uninstall) role=uninstall ;;
  esac
}
runtime_hooks_model() {
  systemctl() {
    [[ "$1/$APP_FAULT" != stop/stop ]] || return 47
    if [[ "$1" == show ]]; then
      printf 'LoadState=loaded\nActiveState=active\nUnitFileState=enabled\n'
    elif [[ -f "$c/recovery-service" ]]; then
      runtime_hooks_recovery_service "$@"
    else printf '%s\n' "$*" >> "$c/services"; fi
  }
  cp() {
    [[ "$APP_FAULT" != backup || "$*" != *'/backup/'* ]] || return 43
    if [[ "$APP_FAULT" == copy || "$APP_FAULT" == copy-unrestored ]] && [[ "$*" == *'/deploy-source.'* && "${!#}" == /opt/* ]]; then
      command cp "$@"
      [[ "$APP_FAULT" != copy-unrestored ]] || printf 'unverified runtime\n' > /opt/cronmaster/partial-runtime
      return 41
    fi
    command cp "$@"
  }
  node() { printf 'v22.0.0\n'; }
  curl() {
    [[ "$APP_FAULT" != checker ]] || return 17
    local out='' format='' url='' tag=v2.0.0 body
    while (($#)); do
      case "$1" in -o)
        out=$2
        shift
        ;;
      -w)
        format=$2
        shift
        ;;
      https:*) url=$1 ;; esac
      shift
    done
    [[ "$url" != *'/tags/'* ]] || tag=${url##*/}
    printf '%s\n' "$url" >> "$c/requests"
    body="{\"tag_name\":\"$tag\",\"assets\":[{\"name\":\"cronmaster_2_prebuild.tar.gz\",\"browser_download_url\":\"https://fixture.invalid/cronmaster_2_prebuild.tar.gz\"}]}"
    if [[ -n "$out" ]]; then printf '%s' "$body" > "$out"; else printf '%s' "$body"; fi
    [[ -z "$format" ]] || printf 200
  }
  curl_download() {
    [[ "$APP_FAULT" != download ]] || return 22
    tar -czf "$1" -C "$c/payload" .
  }
}
runtime_hooks_setup() {
  mkdir -p "$c/config"
  printf 'var_addon_install_path=/opt/cronmaster\nvar_addon_config_path=%q\nvar_addon_service_path=%q\nvar_addon_service=custom-cron\nvar_addon_repo=fixture/cronmaster\nvar_addon_backup_dir=%q\nvar_addon_creds_path=%q\nvar_addon_default_port=8182\n' "$c/config/operator.env" "$c/etc/systemd/system/custom-cron.service" "$c/backup" "$c/config/creds" > "$c/context.sh"
  printf 'new cron consumer\n' > "$c/payload/server.js"
  mkdir -p "$c/payload/settings"
  printf 'release cron configuration\n' > "$c/payload/settings/operator.env"
  : > "$c/requests"
  if [[ "$role" != install ]]; then
    mkdir -p "$c/opt/cronmaster/settings"
    printf 'var_addon_config_path=/opt/cronmaster/settings/operator.env\n' >> "$c/context.sh"
    ln -s "$c/opt/cronmaster/settings/operator.env" "$c/config/operator.env"
    printf 'operator cron configuration\n' > "$c/config/operator.env"
    chmod 0600 "$c/config/operator.env"
    stat -Lc '%d:%i' "$c/config/operator.env" > "$c/config-inode"
    printf 'operator saved credential\n' > "$c/config/creds"
    : > "$c/etc/systemd/system/custom-cron.service"
    printf '1.0.0\n' > "$c/home/.cronmaster"
    if [[ "$role" == update ]]; then
      printf 'old cron consumer\n' > "$c/opt/cronmaster/server.js"
      local initial=active
      [[ "$variant" != stopped-* ]] || initial=inactive
      runtime_hooks_recovery_setup custom-cron "$initial" "$c/opt/cronmaster" "$c/etc/systemd/system/custom-cron.service"
    fi
  fi
}
runtime_hooks_expected() { case "$fault" in checker) expected=17 ;; stop) expected=47 ;; copy | copy-unrestored) expected=252 ;; backup) expected=43 ;; esac }
runtime_hooks_assert() {
  if [[ "$role" == uninstall ]]; then
    check "$(test -d "$c/opt/cronmaster" && printf present || printf absent)" absent "$app scoped uninstall removes app"
    check "$(test -e "$c/config/creds" && printf present || printf absent)" absent "$app scoped uninstall removes own credential"
  elif [[ "$role" == update ]]; then
    check "$(cat "$c/config/operator.env")" 'operator cron configuration' "$app/$variant configured bytes retained"
    check "$(stat -Lc %a "$c/config/operator.env")" 600 "$app/$variant configured mode retained"
    check "$(stat -Lc '%d:%i' "$c/config/operator.env")" "$(cat "$c/config-inode")" "$app/$variant config inode stays live"
    if [[ "$rc" == 0 ]]; then
      check "$(cat "$c/opt/cronmaster/server.js")" 'new cron consumer' "$app selected source reaches consumer"
      check "$(grep -c 'fixture/cronmaster/releases/tags/v2.0.0$' "$c/requests" || true)" 1 "$app selected release and baked repository reach deployment"
      if [[ "$variant" == stopped-update ]]; then
        check "$(cat "$c/recovery-state")" inactive "$app successful update leaves initially stopped service stopped"
        check "$(wc -l < "$c/recovery-starts")" 0 "$app successful update does not start initially stopped service"
      fi
    fi
  else
    check "$(grep -c '^PORT=8182$' "$c/config/operator.env")" 1 "$app install applies nondefault port"
    check "$(stat -c %a "$c/config/creds")" 600 "$app install writes private credential"
  fi
}
runtime_hooks_retry_assert() {
  check "$(cat "$c/opt/cronmaster/server.js")" 'new cron consumer' "$app pending retry reaches consumer"
  check "$(cat "$c/config/operator.env")" 'operator cron configuration' "$app pending retry retains configuration"
  if [[ "$variant" == stopped-download ]]; then
    check "$(cat "$c/recovery-state")" inactive "$app retry leaves initially stopped service stopped"
    check "$(wc -l < "$c/recovery-starts")" 0 "$app retry never starts initially stopped service"
  fi
}
runtime_hooks_main "$@"
