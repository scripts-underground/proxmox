#!/usr/bin/env bash
# shellcheck disable=SC2034,SC2154
set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/../lib/runtime-hooks/addon-release.sh"
app=pihole-exporter
release_app=$app release_mode=tarball release_asset=unused.tar.gz
variants+=(download stopped-download build-intact build-partial runtime stop stopped-selected openrc-download openrc-stopped-download openrc-build-partial openrc-selected)
eval "$(declare -f runtime_hooks_variant | sed '1s/runtime_hooks_variant/release_variant/')"
runtime_hooks_variant() {
  release_variant
  case "$variant" in
    *download) fault=download ;;
    *build-partial) fault=build-partial ;;
    build-intact | stop) fault=$variant ;;
  esac
}
runtime_hooks_expected() {
  case "$fault" in checker) expected=17 ;; build-*) expected=52 ;; stop) expected=47 ;; esac
}
addon_release_setup() {
  printf 'old executable\n' > "$c/opt/$app/pihole-exporter"
  printf 'operator credential\n' > "$c/external/exporter.env"
  printf 'var_addon_config_path=%q\nvar_addon_service=custom-exporter\n' "$c/external/exporter.env" > "$c/context.sh"
  mkdir -p "$c/etc/init.d"
  printf 'operator unit\n' > "$c/etc/systemd/system/custom-exporter.service"
  printf 'operator OpenRC unit\n' > "$c/etc/init.d/custom-exporter"
  local initial=active unit="$c/etc/systemd/system/custom-exporter.service"
  [[ "$variant" != *stopped-* ]] || initial=inactive
  [[ "$variant" != openrc-* ]] || unit="$c/etc/init.d/custom-exporter"
  runtime_hooks_recovery_setup custom-exporter "$initial" "$c/opt/$app" "$c/external/exporter.env" "$unit"
  if [[ "$fault" == build-* ]]; then
    printf 'old code\n' > "$c/payload/code"
    rm -f "$c/payload/consumer"
  fi
  cat > "$c/local/bin/go" << 'GO'
#!/usr/bin/env bash
[[ "$APP_FAULT" != build-intact ]] || exit 52
if [[ "$APP_FAULT" == build-partial ]]; then printf 'partial executable\n' > ./pihole-exporter; exit 52; fi
printf 'selected executable\n' > ./pihole-exporter
GO
  chmod 0755 "$c/local/bin/go"
}
runtime_hooks_model() {
  addon_release_model
  if [[ "${c##*/}" == *openrc-* ]]; then INIT_SYSTEM=openrc; fi
  setup_go() { [[ "$APP_FAULT" != runtime ]] || return 51; }
  curl_download() {
    [[ "$APP_FAULT" != download ]] || return 22
    addon_release_download "$@"
  }
  systemctl() {
    [[ "$APP_FAULT/$1" != stop/stop ]] || return 47
    runtime_hooks_recovery_service "$@"
  }
  rc-service() {
    [[ "$APP_FAULT/$2" != stop/stop ]] || return 47
    runtime_hooks_recovery_service "$2" "$1"
  }
}
eval "$(declare -f runtime_hooks_assert | sed '1s/runtime_hooks_assert/release_assert/')"
runtime_hooks_assert() {
  case "$variant" in checker | no-update | selected) release_assert ;; esac
  check "$(cat "$c/external/exporter.env")" 'operator credential' "$app/$variant credentials retained"
  if [[ "$variant" == stopped-selected ]]; then
    check "$(cat "$c/recovery-state")" inactive "$app successful update leaves initially stopped service stopped"
    check "$(wc -l < "$c/recovery-starts")" 0 "$app successful update never starts initially stopped service"
  fi
}
runtime_hooks_retry_assert() {
  addon_release_consumer_assert
  if [[ "$variant" == *stopped-* || "$fault" == build-partial || "$fault" == runtime ]]; then
    check "$(cat "$c/recovery-state")" inactive "$app/$variant retry preserves stopped entry state"
  fi
}
addon_release_consumer_assert() {
  if [[ "$fault" != build-* ]]; then check "$(cat "$c/opt/$app/code")" 'new code' "$app selected source consumer"; fi
  check "$(cat "$c/opt/$app/pihole-exporter")" 'selected executable' "$app/$variant compiled executable consumer"
}
runtime_hooks_main "$@"
