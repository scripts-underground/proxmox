#!/usr/bin/env bash
# runtime-hooks-contract: addon intent-preserving
# External HTTP/package/service models; actual release and binary publishers.
# shellcheck disable=SC2034,SC2154
set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/../lib/runtime-hooks/harness.sh"
app=filebrowser
runtime_hooks_observed_commands=(systemctl rc-service)
runtime_hooks_selected_service=filebrowser
script_type=addon
variants=(fresh update openrc stopped openrc-stopped restart-failure checker download uninstall uninstall-failure)
hook_paths=()
runtime_hooks_variant() {
  case "$variant" in checker | restart-failure) fault=$variant ;; openrc | openrc-stopped) fault=openrc ;; uninstall) role=uninstall ;; uninstall-failure) role=uninstall fault=uninstall-failure ;; esac
}
runtime_hooks_model() {
  [[ "$APP_FAULT" != openrc ]] || INIT_SYSTEM=openrc
  systemctl() {
    printf '%s\n' "$*" >> "$c/services"
    [[ "$APP_FAULT" != uninstall-failure || "$1" != stop ]] || return 49
    if [[ "$1" == show ]]; then printf 'LoadState=loaded\nActiveState=%s\nUnitFileState=enabled\n' "$(cat "$c/service-state")"; fi
    if [[ "$1" == is-active ]]; then
      [[ "$(cat "$c/service-state")" == active ]]
      return
    fi
    if [[ "$1" == start || "$1" == restart || ("$1" == try-restart && "$(cat "$c/service-state")" == active) ]]; then
      printf failed > "$c/service-state"
      [[ "$APP_FAULT" != restart-failure ]] || return 47
      "$c/local/bin/filebrowser" > "$c/running-consumer"
      printf active > "$c/service-state"
    fi
  }
  rc-service() {
    printf '%s\n' "$*" >> "$c/services"
    if [[ "$1" == --ifstarted ]]; then
      [[ "$(cat "$c/service-state")" == active ]] || return 0
      shift
    fi
    if [[ "$2" == status ]]; then [[ "$(cat "$c/service-state")" == active ]] || return 3; fi
    if [[ "$2" == start || "$2" == restart ]]; then
      "$c/local/bin/filebrowser" > "$c/running-consumer"
      printf active > "$c/service-state"
    fi
  }
  apt() { :; }
  filebrowser() { printf '%s\n' "$*" >> "$c/binary-calls"; }
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
    body="{\"tag_name\":\"$tag\",\"assets\":[{\"name\":\"linux-amd64-filebrowser.tar.gz\",\"browser_download_url\":\"https://fixture.invalid/linux-amd64-filebrowser.tar.gz\"}]}"
    if [[ -n "$out" ]]; then printf '%s' "$body" > "$out"; else printf '%s' "$body"; fi
    [[ -z "$format" ]] || printf 200
  }
  curl_download() {
    [[ "$APP_FAULT" != download ]] || return 22
    tar -czf "$1" -C "$c/payload" filebrowser
  }
}
runtime_hooks_setup() {
  mkdir -p "$c/db" "$c/local/bin"
  printf 'var_addon_bin_path=/usr/local/bin/filebrowser\nvar_addon_db_dir=%q\nvar_addon_db_path=%q\nvar_addon_default_port=8181\n' "$c/db" "$c/db/custom.db" > "$c/context.sh"
  printf '#!/usr/bin/env bash\nprintf "new binary consumer\\n"\n' > "$c/payload/filebrowser"
  chmod 0755 "$c/payload/filebrowser"
  : > "$c/requests"
  printf active > "$c/service-state"
  case "$variant" in stopped | openrc-stopped) printf inactive > "$c/service-state" ;; esac
  if [[ "$role" != install ]]; then
    printf 'operator database\n' > "$c/db/custom.db"
    printf '#!/usr/bin/env bash\nprintf "old binary consumer\\n"\n' > "$c/local/bin/filebrowser"
    chmod 0755 "$c/local/bin/filebrowser"
    printf '1.0.0\n' > "$c/home/.filebrowser"
    : > "$c/etc/systemd/system/filebrowser.service"
    printf 'old binary consumer\n' > "$c/running-consumer"
  fi
  if [[ "$role" == uninstall ]]; then
    mkdir -m 0700 "$c/addon-service-actions"
    printf 'v1\nsystemd\nfilebrowser\n' > "$c/addon-service-actions/file-browser"
    chmod 0600 "$c/addon-service-actions/file-browser"
  fi
}
runtime_hooks_expected() { case "$fault" in checker) expected=17 ;; restart-failure) expected=47 ;; uninstall-failure) expected=49 ;; esac }
runtime_hooks_assert() {
  if [[ "$role" == uninstall ]]; then
    local outcome=absent
    [[ "$rc" == 0 ]] || outcome=present
    check "$(test -e "$c/db/custom.db" && printf present || printf absent)" "$outcome" "$app scoped uninstall owns configured DB"
    check "$(test -e "$c/local/bin/filebrowser" && printf present || printf absent)" "$outcome" "$app scoped uninstall owns configured binary"
    check "$(test -e "$c/addon-service-actions/file-browser" && printf present || printf absent)" "$outcome" "$app uninstall retires activation receipt only after success"
  elif [[ "$role" == update ]]; then
    check "$(cat "$c/db/custom.db")" 'operator database' "$app/$variant configured DB retained"
    if [[ "$rc" == 0 ]]; then
      check "$("$c/local/bin/filebrowser")" 'new binary consumer' "$app selected binary reaches executable consumer"
      check "$(grep -c '/tags/v2.0.0$' "$c/requests" || true)" 1 "$app update deploys the selected release"
      if [[ "$variant" == stopped || "$variant" == openrc-stopped ]]; then
        check "$(cat "$c/service-state")" inactive "$app/$variant operator-stopped service stays stopped"
        check "$(cat "$c/running-consumer")" 'old binary consumer' "$app/$variant never activates new executable"
      else
        check "$(cat "$c/running-consumer")" 'new binary consumer' "$app/$variant service activates replaced executable"
      fi
    elif [[ "$fault" == checker ]]; then
      check "$("$c/local/bin/filebrowser")" 'old binary consumer' "$app release error retains executable"
    fi
  else
    check "$(grep -c -- '-p 8181' "$c/binary-calls")" 2 "$app nondefault setting reaches config consumer"
    check "$(stat -c %a "$c/db/custom.db")" 644 "$app install creates configured database"
  fi
}
runtime_hooks_retry_assert() {
  check "$("$c/local/bin/filebrowser")" 'new binary consumer' "$app ordinary retry publishes executable"
  check "$(cat "$c/db/custom.db")" 'operator database' "$app retry retains configured DB"
  check "$(cat "$c/running-consumer")" 'new binary consumer' "$app retry activates replaced executable"
  check "$(cat "$c/service-state")" active "$app retry recovers a failed unit instead of treating it as operator-stopped"
}
eval "$(declare -f runtime_hooks_failure_services_assert | sed '1s/runtime_hooks_failure_services_assert/filebrowser_failure_services_assert/')"
runtime_hooks_failure_services_assert() {
  if [[ "$variant" == restart-failure ]]; then
    check "$(cat "$c/running-consumer")" 'old binary consumer' "$app failed activation does not claim a new consumer"
  else filebrowser_failure_services_assert; fi
}
runtime_hooks_main "$@"
