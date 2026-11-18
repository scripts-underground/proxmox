#!/usr/bin/env bash
# shellcheck disable=SC2034,SC2154
set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/../lib/runtime-hooks/addon-release.sh"
app=immich-public-proxy
release_app='Immich Public Proxy' release_mode=tarball release_asset=unused.tar.gz
variants+=(download stopped-download stopped-selected backup ci-intact ci-partial build stop)
runtime_hooks_variant() {
  case "$variant" in checker | backup | ci-* | stop) fault=$variant ;; stopped-download) fault=download ;; esac
}
runtime_hooks_expected() {
  case "$fault" in checker) expected=17 ;; backup) expected=54 ;; ci-*) expected=53 ;; stop) expected=47 ;; esac
}
addon_release_setup() {
  mkdir -p "$c/opt/$app/app" "$c/payload/app"
  printf 'operator config\n' > "$c/opt/$app/app/config.json"
  printf 'operator env\n' > "$c/opt/$app/app/.env"
  chmod 0600 "$c/opt/$app/app/.env" "$c/opt/$app/app/config.json"
  stat -c '%i:%a' "$c/opt/$app/app/.env" "$c/opt/$app/app/config.json" > "$c/config-metadata"
  printf 'archive config\n' > "$c/payload/app/config.json"
  printf 'archive env\n' > "$c/payload/app/.env"
  printf 'var_addon_install_path=/opt/immich-public-proxy\nvar_addon_config_path=/opt/immich-public-proxy/app\nvar_addon_service_path=%q\n' "$c/etc/systemd/system/custom-proxy.service" > "$c/context.sh"
  printf 'operator unit\n' > "$c/etc/systemd/system/custom-proxy.service"
  mkdir -p "$c/opt/$app/app/node_modules/native"
  printf 'old native dependency\n' > "$c/opt/$app/app/node_modules/native/runtime.node"
  local initial=active
  [[ "$variant" != stopped-* ]] || initial=inactive
  if [[ "$fault" == ci-* ]]; then
    cp -a "$c/opt/$app/." "$c/payload/"
    rm -f "$c/payload/consumer"
  fi
  runtime_hooks_recovery_setup custom-proxy "$initial" "$c/opt/$app" "$c/etc/systemd/system/custom-proxy.service"
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
    [[ "$APP_FAULT" != download ]] || return 22
    addon_release_download "$@"
  }
  if ! declare -F proxy_real_backup > /dev/null; then
    eval "$(declare -f create_backup | sed '1s/create_backup/proxy_real_backup/')"
  fi
  create_backup() {
    [[ "$APP_FAULT" != backup ]] || exit 54
    proxy_real_backup "$@"
  }
  systemctl() {
    [[ "$APP_FAULT/$1" != stop/stop ]] || return 47
    runtime_hooks_recovery_service "$@"
  }
}
eval "$(declare -f runtime_hooks_assert | sed '1s/runtime_hooks_assert/release_assert/')"
runtime_hooks_assert() {
  case "$variant" in checker | no-update | selected) release_assert ;; esac
  check "$(cat "$c/opt/$app/app/.env")" 'operator env' "$app/$variant environment retained"
  check "$(cat "$c/opt/$app/app/config.json")" 'operator config' "$app/$variant configuration retained"
  check "$(stat -c '%i:%a' "$c/opt/$app/app/.env" "$c/opt/$app/app/config.json")" "$(cat "$c/config-metadata")" "$app/$variant configuration inodes and modes retained"
  check "$(cat "$c/etc/systemd/system/custom-proxy.service")" 'operator unit' "$app/$variant operator unit retained"
  if [[ "$variant" == stopped-selected ]]; then
    check "$(cat "$c/recovery-state")" inactive "$app successful update leaves initially stopped service stopped"
    check "$(wc -l < "$c/recovery-starts")" 0 "$app successful update never starts initially stopped service"
  fi
}
runtime_hooks_retry_assert() {
  if [[ "$fault" != ci-* ]]; then addon_release_consumer_assert; fi
  check "$(cat "$c/opt/$app/app/.env")" 'operator env' "$app/$variant retry environment retained"
  check "$(cat "$c/opt/$app/app/config.json")" 'operator config' "$app/$variant retry configuration retained"
  check "$(stat -c '%i:%a' "$c/opt/$app/app/.env" "$c/opt/$app/app/config.json")" "$(cat "$c/config-metadata")" "$app/$variant retry configuration inodes and modes retained"
  if [[ "$variant" == stopped-download || "$fault" == ci-partial || "$fault" == build ]]; then
    check "$(cat "$c/recovery-state")" inactive "$app/$variant retry preserves stopped entry state"
  fi
}
addon_release_consumer_assert() { check "$(cat "$c/opt/$app/code")" 'new code' "$app selected source consumer"; }
runtime_hooks_main "$@"
