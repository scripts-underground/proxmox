#!/usr/bin/env bash
# shellcheck disable=SC2034,SC2154
set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/../lib/runtime-hooks/addon-release.sh"
app=nextcloud-exporter
release_app=$app release_mode=binary release_asset=nextcloud-exporter_2_amd64.deb
variants+=(fresh uninstall download stopped-download package-intact package-partial relocate-intact relocate-partial stop stopped-selected)
hook_paths=('/usr/bin/nextcloud-exporter' 'package-bin/nextcloud-exporter')
eval "$(declare -f runtime_hooks_variant | sed '1s/runtime_hooks_variant/release_variant/')"
runtime_hooks_variant() {
  release_variant
  [[ "$variant" != uninstall ]] || role=uninstall
  case "$variant" in stopped-download) fault=download ;; package-* | relocate-* | stop) fault=$variant ;; esac
}
runtime_hooks_expected() {
  case "$fault" in checker) expected=17 ;; package-*) expected=43 ;; relocate-*) expected=44 ;; stop) expected=47 ;; esac
}
addon_release_setup() {
  mkdir -p "$c/package-bin"
  printf '#!/usr/bin/env bash\nprintf "old binary\\n"\n' > "$c/local/bin/custom-nextcloud"
  chmod 0755 "$c/local/bin/custom-nextcloud"
  printf 'var_addon_bin_path=/usr/local/bin/custom-nextcloud\nvar_addon_default_port=19205\nvar_addon_config_path=%q\n' "$c/external/nextcloud.env" > "$c/context.sh"
  printf '\nfixture-token\n\n\n\n' > "$c/stdin"
  if [[ "$role" == update ]]; then
    printf 'operator credential\n' > "$c/external/nextcloud.env"
    chmod 0600 "$c/external/nextcloud.env"
    printf 'operator unit\n' > "$c/etc/systemd/system/custom-nextcloud.service"
    printf 'var_addon_service=custom-nextcloud\n' >> "$c/context.sh"
    local initial=active
    [[ "$variant" != stopped-* ]] || initial=inactive
    runtime_hooks_recovery_setup custom-nextcloud "$initial" "$c/local/bin/custom-nextcloud" "$c/external/nextcloud.env" "$c/etc/systemd/system/custom-nextcloud.service"
  fi
}
runtime_hooks_model() {
  addon_release_model
  _deploy_release_deb() {
    [[ "$APP_FAULT" != package-intact ]] || return 43
    cat "$1" > "$c/package-consumer"
    printf '#!/usr/bin/env bash\nprintf "selected v2.0.0\\n"\n' > "$c/package-bin/nextcloud-exporter"
    chmod 0755 "$c/package-bin/nextcloud-exporter"
    if [[ "$APP_FAULT" == package-partial ]]; then
      printf 'partial unit\n' > "$c/etc/systemd/system/custom-nextcloud.service"
      return 43
    fi
  }
  install() {
    [[ "$APP_FAULT" != relocate-intact ]] || return 44
    if [[ "$APP_FAULT" == relocate-partial ]]; then
      printf 'partial executable\n' > "${!#}"
      return 44
    fi
    command install "$@"
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
  curl_download() {
    [[ "$APP_FAULT" != download ]] || return 22
    addon_release_download "$@"
  }
  dpkg() { :; }
}
addon_release_consumer_assert() { check "$("$c/local/bin/custom-nextcloud")" 'selected v2.0.0' "$app selected package reaches configured binary"; }
eval "$(declare -f runtime_hooks_assert | sed '1s/runtime_hooks_assert/release_assert/')"
runtime_hooks_assert() {
  if [[ "$role" == install ]]; then
    addon_release_consumer_assert
    check "$(stat -c %a "$c/external/nextcloud.env")" 600 "$app private credential file"
    check "$(grep -c '^NEXTCLOUD_LISTEN_ADDRESS=":19205"$' "$c/external/nextcloud.env")" 1 "$app custom listener reaches config"
  elif [[ "$role" == uninstall ]]; then
    check "$(test -e "$c/local/bin/custom-nextcloud" && printf present || printf absent)" absent "$app removes addon-owned binary override"
  else
    case "$variant" in checker | no-update | selected) release_assert ;; esac
    check "$(cat "$c/external/nextcloud.env")" 'operator credential' "$app/$variant credentials retained"
    if [[ "$variant" == stopped-selected ]]; then
      check "$(cat "$c/recovery-state")" inactive "$app successful update leaves initially stopped service stopped"
      check "$(wc -l < "$c/recovery-starts")" 0 "$app successful update never starts initially stopped service"
    fi
  fi
}
runtime_hooks_retry_assert() {
  addon_release_consumer_assert
  if [[ "$variant" == stopped-download ]]; then
    check "$(cat "$c/recovery-state")" inactive "$app retry leaves initially stopped service stopped"
    check "$(wc -l < "$c/recovery-starts")" 0 "$app retry never starts initially stopped service"
  fi
}
runtime_hooks_main "$@"
