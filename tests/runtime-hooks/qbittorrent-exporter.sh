#!/usr/bin/env bash
# runtime-hooks-contract: addon intent-preserving
# shellcheck disable=SC2034,SC2154
set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/../lib/runtime-hooks/addon-release.sh"
app=qbittorrent-exporter
runtime_hooks_observed_commands=(systemctl rc-service)
runtime_hooks_observe_recovery=1
release_app=$app release_mode=tarball release_asset=unused.tar.gz
variants+=(download stopped-download build-intact build-partial runtime stop stopped-selected openrc-download openrc-stopped-download openrc-build-partial openrc-selected legacy-selected legacy-download openrc-absent-download openrc-absent-selected)
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
  printf 'old executable\n' > "$c/opt/$app/qbittorrent-exporter"
  mkdir -p "$c/config"
  printf 'QBITTORRENT_API_KEY=fixture\n' > "$c/config/config"
  if [[ "$variant" == legacy-* ]]; then
    printf 'QBITTORRENT_USERNAME="operator"\nQBITTORRENT_PASSWORD="literal credential"\n' > "$c/config/config"
  fi
  cp "$c/config/config" "$c/config-before"
  printf 'var_addon_config_path=%q\nvar_addon_service=custom-exporter\n' "$c/config/config" > "$c/context.sh"
  mkdir -p "$c/etc/init.d"
  printf 'operator unit\n' > "$c/etc/systemd/system/custom-exporter.service"
  printf 'operator OpenRC unit\n' > "$c/etc/init.d/custom-exporter"
  local initial=active unit="$c/etc/systemd/system/custom-exporter.service"
  [[ "$variant" != *stopped-* ]] || initial=inactive
  [[ "$variant" != openrc-* ]] || unit="$c/etc/init.d/custom-exporter"
  local -a footprint=("$c/opt/$app" "$unit")
  if [[ "$variant" == openrc-absent-* ]]; then
    rm -f "$c/config/config"
  else
    footprint+=("$c/config/config")
  fi
  runtime_hooks_recovery_setup custom-exporter "$initial" "${footprint[@]}"
  if [[ "$fault" == build-* ]]; then
    printf 'old code\n' > "$c/payload/code"
    rm -f "$c/payload/consumer"
  fi
  printf '#!/usr/bin/env bash\n' > "$c/local/bin/go"
  declare -f runtime_hooks_event >> "$c/local/bin/go"
  cat >> "$c/local/bin/go" << 'GO'
c=$APP_FIXTURE
INIT_SYSTEM=$(cat "$c/fixture-init-system")
runtime_hooks_event enter /usr/local/bin/go "$PWD" "$@"
[[ "$APP_FAULT" != build-intact ]] || exit 52
if [[ "$APP_FAULT" == build-partial ]]; then printf 'partial executable\n' > ./qbittorrent-exporter; exit 52; fi
printf 'selected executable\n' > ./qbittorrent-exporter
runtime_hooks_event complete /usr/local/bin/go "$PWD" "$@"
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
  if [[ "$variant" == openrc-absent-* ]]; then
    check "$(test -e "$c/config/config" && printf present || printf absent)" absent "$app/$variant optional absent config remains absent"
  else
    check "$(cmp -s "$c/config/config" "$c/config-before" && printf equal || printf changed)" equal "$app/$variant existing authentication retained"
  fi
  if [[ "$variant" == legacy-selected ]]; then addon_release_consumer_assert; fi
  if [[ "$variant" == stopped-selected ]]; then
    check "$(cat "$c/recovery-state")" inactive "$app successful update leaves initially stopped service stopped"
    check "$(wc -l < "$c/recovery-starts")" 0 "$app successful update never starts initially stopped service"
  fi
}
runtime_hooks_retry_assert() {
  addon_release_consumer_assert
  if [[ "$variant" == *stopped-* ]]; then
    check "$(cat "$c/recovery-state")" inactive "$app/$variant retry preserves stopped entry state"
  fi
}
addon_release_consumer_assert() {
  if [[ "$fault" != build-* ]]; then check "$(cat "$c/opt/$app/code")" 'new code' "$app selected source consumer"; fi
  check "$(cat "$c/opt/$app/qbittorrent-exporter")" 'selected executable' "$app/$variant compiled executable consumer"
}
runtime_hooks_deployment_assert() {
  [[ "$variant" != no-update ]] || return 0
  addon_release_consumer_assert
  runtime_hooks_completed_assert /usr/local/bin/go /opt/qbittorrent-exporter build -o ./qbittorrent-exporter
}
runtime_hooks_main "$@"
