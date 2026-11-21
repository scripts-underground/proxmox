#!/usr/bin/env bash
# runtime-hooks-contract: addon intent-preserving
# shellcheck disable=SC2034,SC2154
set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/../lib/runtime-hooks/addon-release.sh"
app=jellystat
runtime_hooks_observed_commands=(npm systemctl)
runtime_hooks_observe_recovery=1
release_app=$app release_mode=tarball release_asset=unused.tar.gz
variants+=(download stopped-download stopped-selected backup ci-intact ci-partial build stop linked-selected normalized-selected external-mode-download)
runtime_hooks_variant() {
  case "$variant" in checker | backup | ci-* | stop | external-mode-download) fault=$variant ;; stopped-download) fault=download ;; esac
}
runtime_hooks_expected() {
  case "$fault" in checker) expected=17 ;; backup) expected=54 ;; ci-*) expected=53 ;; stop) expected=47 ;; external-mode-download) expected=250 ;; esac
}
addon_release_setup() {
  printf 'var_addon_config_path=/opt/jellystat/.env\nvar_addon_service_path=%q\n' "$c/etc/systemd/system/custom-jellystat.service" > "$c/context.sh"
  printf 'operator unit\n' > "$c/etc/systemd/system/custom-jellystat.service"
  chmod 0600 "$c/opt/$app/.env"
  if [[ "$variant" == linked-selected ]]; then
    mkdir -p "$c/opt/$app/private" "$c/payload/private"
    mv "$c/opt/$app/.env" "$c/opt/$app/private/operator env"
    ln -s 'private/operator env' "$c/opt/$app/.env"
    printf 'release secret must not replace operator bytes\n' > "$c/payload/private/operator env"
  elif [[ "$variant" == normalized-selected ]]; then
    printf 'var_addon_config_path=/opt/jellystat/./.env\nvar_addon_service_path=%q\n' "$c/etc/systemd/system/custom-jellystat.service" > "$c/context.sh"
  elif [[ "$variant" == external-mode-download ]]; then
    mv "$c/opt/$app/.env" "$c/external/jelly.env"
    ln -s "$c/external/jelly.env" "$c/opt/$app/.env"
  fi
  stat -c '%i:%a' "$c/opt/$app/.env" > "$c/config-metadata"
  mkdir -p "$c/opt/$app/node_modules/native"
  printf 'old native dependency\n' > "$c/opt/$app/node_modules/native/runtime.node"
  printf 'archive configuration must not replace operator settings\n' > "$c/payload/.env"
  local initial=active
  [[ "$variant" != stopped-* ]] || initial=inactive
  if [[ "$fault" == ci-* ]]; then
    cp -a "$c/opt/$app/." "$c/payload/"
    rm -f "$c/payload/consumer"
  fi
  local -a footprint=("$c/opt/$app" "$c/etc/systemd/system/custom-jellystat.service")
  [[ "$variant" != external-mode-download ]] || footprint+=("$c/external/jelly.env")
  runtime_hooks_recovery_setup custom-jellystat "$initial" "${footprint[@]}"
}
runtime_hooks_model() {
  addon_release_model
  npm() {
    [[ "$APP_FAULT" != ci-intact ]] || return 53
    if [[ "$APP_FAULT" == ci-partial ]]; then
      mkdir -p node_modules/native
      printf 'partial native dependency\n' > node_modules/native/runtime.node
      return 53
    fi
    [[ "$APP_FAULT/$*" != 'build/run build' ]] || return 52
  }
  curl_download() {
    if [[ "$APP_FAULT" == external-mode-download ]]; then
      chmod 0640 "$c/external/jelly.env"
      return 22
    fi
    [[ "$APP_FAULT" != download ]] || return 22
    addon_release_download "$@"
  }
  if ! declare -F jellystat_real_backup > /dev/null; then
    eval "$(declare -f create_backup | sed '1s/create_backup/jellystat_real_backup/')"
  fi
  create_backup() {
    [[ "$APP_FAULT" != backup ]] || exit 54
    jellystat_real_backup "$@"
  }
  systemctl() {
    [[ "$APP_FAULT/$1" != stop/stop ]] || return 47
    runtime_hooks_recovery_service "$@"
  }
}
eval "$(declare -f runtime_hooks_assert | sed '1s/runtime_hooks_assert/release_assert/')"
runtime_hooks_assert() {
  case "$variant" in checker | no-update | selected) release_assert ;; esac
  check "$(cat "$c/opt/$app/.env")" 'USER settings' "$app/$variant configuration retained"
  check "$(stat -c '%i:%a' "$c/opt/$app/.env")" "$(cat "$c/config-metadata")" "$app/$variant configuration inode and mode retained"
  check "$(cat "$c/etc/systemd/system/custom-jellystat.service")" 'operator unit' "$app/$variant operator unit retained"
  if [[ "$variant" == stopped-selected ]]; then
    check "$(cat "$c/recovery-state")" inactive "$app successful update leaves initially stopped service stopped"
    check "$(wc -l < "$c/recovery-starts")" 0 "$app successful update never starts initially stopped service"
  fi
}
runtime_hooks_retry_assert() {
  runtime_hooks_backup_assert "$c/opt/jellystat_backup" /opt/jellystat/.env 'USER settings'
  addon_release_consumer_assert
  check "$(cat "$c/opt/$app/.env")" 'USER settings' "$app/$variant retry configuration retained"
  check "$(stat -c '%i:%a' "$c/opt/$app/.env")" "$(cat "$c/config-metadata")" "$app/$variant retry configuration inode and mode retained"
  if [[ "$variant" == stopped-download ]]; then
    check "$(cat "$c/recovery-state")" inactive "$app/$variant retry preserves stopped entry state"
  fi
}
addon_release_consumer_assert() {
  runtime_hooks_backup_assert "$c/opt/jellystat_backup" /opt/jellystat/.env 'USER settings'
  check "$(test -e "$c/opt/jellystat_backup/.manifest" && printf stale || printf scoped)" scoped "$app success never leaves reusable unscoped backup manifest"
  local expected_code='new code'
  [[ "$variant" != ci-* ]] || expected_code='old code'
  check "$(cat "$c/opt/$app/code")" "$expected_code" "$app selected source consumer"
}
runtime_hooks_deployment_assert() {
  [[ "$variant" != no-update ]] || return 0
  addon_release_consumer_assert
  runtime_hooks_completed_assert npm /opt/jellystat install
  runtime_hooks_completed_assert npm /opt/jellystat run build
}
runtime_hooks_main "$@"
