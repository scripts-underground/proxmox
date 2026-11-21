#!/usr/bin/env bash
# runtime-hooks-contract: addon intent-preserving
# shellcheck disable=SC2034,SC2154
set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/../lib/runtime-hooks/addon-release.sh"
app=filebrowser-quantum
runtime_hooks_observed_commands=(systemctl rc-service)
runtime_hooks_observe_recovery=1
release_app=$app release_mode=singlefile release_asset=linux-amd64-filebrowser
variants+=(download stopped-download stopped-selected stop rename-intact rename-partial cleanup openrc-download openrc-stopped-download openrc-selected)
runtime_hooks_variant() {
  case "$variant" in checker | stop | rename-* | cleanup) fault=$variant ;; *download) fault=download ;; esac
}
runtime_hooks_expected() {
  case "$fault" in checker) expected=17 ;; stop) expected=47 ;; rename-*) expected=44 ;; cleanup) expected=55 ;; esac
}
addon_release_setup() {
  mkdir -p "$c/opt/quantum-config" "$c/etc/init.d"
  printf 'operator config\n' > "$c/opt/quantum-config/fq-config.yaml"
  chmod 0600 "$c/opt/quantum-config/fq-config.yaml"
  printf 'var_addon_conf_dir=/opt/quantum-config\nvar_addon_conf_path=/opt/quantum-config/fq-config.yaml\n' > "$c/context.sh"
  printf '#!/usr/bin/env bash\nprintf "old executable\\n"\n' > "$c/local/bin/filebrowser"
  chmod 0755 "$c/local/bin/filebrowser"
  printf 'operator unit\n' > "$c/etc/systemd/system/filebrowser.service"
  printf 'operator OpenRC unit\n' > "$c/etc/init.d/filebrowser"
  local initial=active unit="$c/etc/systemd/system/filebrowser.service"
  [[ "$variant" != *stopped-* ]] || initial=inactive
  [[ "$variant" != openrc-* ]] || unit="$c/etc/init.d/filebrowser"
  runtime_hooks_recovery_setup filebrowser "$initial" "$c/local/bin/filebrowser" "$c/opt/quantum-config/fq-config.yaml" "$unit"
}
runtime_hooks_model() {
  addon_release_model
  if [[ "${c##*/}" == *openrc-* ]]; then INIT_SYSTEM=openrc; fi
  curl_download() {
    [[ "$APP_FAULT" != download ]] || return 22
    addon_release_download "$@"
  }
  mv() {
    if [[ "${!#}" == /usr/local/bin/filebrowser ]]; then
      [[ "$APP_FAULT" != rename-intact ]] || return 44
      if [[ "$APP_FAULT" == rename-partial ]]; then
        printf 'partial executable\n' > /usr/local/bin/filebrowser
        return 44
      fi
    fi
    command mv "$@"
  }
  systemctl() {
    [[ "$INIT_SYSTEM" == systemd ]] || return 4
    [[ "$APP_FAULT/$1" != stop/stop ]] || return 47
    runtime_hooks_recovery_service "$@" || return $?
    [[ "$1" != start ]] || "$var_addon_bin_path" > "$c/running-executable"
  }
  rc-service() {
    [[ "$INIT_SYSTEM" == openrc ]] || return 4
    [[ "$APP_FAULT/$2" != stop/stop ]] || return 47
    runtime_hooks_recovery_service "$2" "$1" || return $?
    [[ "$2" != start ]] || "$var_addon_bin_path" > "$c/running-executable"
  }
  rmdir() {
    [[ "$APP_FAULT" != cleanup || "${!#}" != *'/.filebrowser-quantum.'* ]] || return 55
    command rmdir "$@"
  }
}
eval "$(declare -f runtime_hooks_assert | sed '1s/runtime_hooks_assert/release_assert/')"
runtime_hooks_assert() {
  case "$variant" in checker | no-update | selected) release_assert ;; esac
  check "$(cat "$c/opt/quantum-config/fq-config.yaml")" 'operator config' "$app/$variant configuration retained"
  local stages=0
  [[ "$variant" != cleanup ]] || stages=1
  check "$(find "$c/local/bin" -maxdepth 1 -name '.filebrowser-quantum.*' | wc -l)" "$stages" "$app/$variant publication cleanup outcome is truthful"
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
addon_release_consumer_assert() { check "$("$c/local/bin/filebrowser")" 'selected v2.0.0' "$app selected executable consumer"; }
eval "$(declare -f runtime_hooks_failure_services_assert | sed '1s/runtime_hooks_failure_services_assert/quantum_failure_services_assert/')"
runtime_hooks_failure_services_assert() {
  if [[ "$variant" == cleanup ]]; then
    check "$(cat "$c/recovery-state")" active "$app cleanup failure does not suppress successful deployment activation"
    check "$(cat "$c/running-executable" 2> /dev/null || true)" 'selected v2.0.0' "$app cleanup failure still reaches updated native consumer"
  else quantum_failure_services_assert; fi
}
runtime_hooks_deployment_assert() {
  [[ "$variant" != no-update ]] || return 0
  addon_release_consumer_assert
  if [[ "$(cat "$c/recovery-initial")" == active ]]; then
    check "$(cat "$c/running-executable" 2> /dev/null || true)" 'selected v2.0.0' "$app/$variant activated service consumes selected executable"
  fi
}
runtime_hooks_main "$@"
