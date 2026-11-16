#!/usr/bin/env bash
# shellcheck disable=SC2034,SC2154
# Callback inputs/outputs are supplied and consumed by the sourced harness.
set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/../lib/runtime-hooks/harness.sh"
app=thingsboard
script_type=lxc
variants=(fresh update download copy runtime)
hook_paths=(/usr/share/thingsboard thingsboard)
runtime_hooks_model() {
  curl_download() {
    [[ "$APP_FAULT" != download ]] || return 22
    command cp "$c/package.deb" "$1"
  }
  apt() {
    local arg
    for arg in "$@"; do
      if [[ "$arg" == *.deb ]]; then
        if [[ "$APP_ROLE" == update && "${DPKG_FORCE_CONFOLD:-}" != 1 ]]; then
          printf 'PACKAGE default settings\n' > "$c/etc/thingsboard/conf/thingsboard.conf"
        fi
        dpkg -i "$arg"
        return $?
      fi
    done
  }
  setup_postgresql_db() { export PG_DB_NAME PG_DB_USER PG_DB_PASS=fixture-db-secret; }
  setup_java() {
    [[ "$APP_FAULT" != runtime ]] || return 51
    printf '%s\n' "$JAVA_VERSION" > "$c/java-version"
  }
  dpkg() {
    if [[ "$1" == --print-architecture ]]; then printf 'amd64\n'; else
      mkdir -p "$c/thingsboard/bin/install" "$c/etc/thingsboard/conf"
      printf '#!/usr/bin/env bash\nprintf "upgrade-consumer\\n" > "%s/db-upgrade"\n' "$c" > "$c/thingsboard/bin/install/upgrade.sh"
      printf '#!/usr/bin/env bash\nexit 0\n' > "$c/thingsboard/bin/install/install.sh"
      chmod 0755 "$c/thingsboard/bin/install/"*.sh
    fi
  }
  systemctl() {
    printf '%s\n' "$*" >> "$c/services"
    if [[ "$1" == start || " $* " == *' --now '* ]]; then
      [[ "$(cat "$c/java-version")" == 25 ]] || return 57
    fi
  }
  curl() {
    local out='' url='' format='' body tag=v2.0.0
    while (($#)); do
      case "$1" in -o)
        out="$2"
        shift
        ;;
      -w)
        format="$2"
        shift
        ;;
      https:*) url="$1" ;; esac
      shift
    done
    [[ "$url" != *'/tags/'* ]] || tag=${url##*/}
    body="{\"tag_name\":\"$tag\",\"assets\":[{\"browser_download_url\":\"https://fixture.invalid/thingsboard-2.deb\"}]}"
    if [[ -n "$out" ]]; then printf '%s' "$body" > "$out"; else printf '%s' "$body"; fi
    [[ -z "$format" ]] || printf 200
  }
}
runtime_hooks_expected() { [[ "$variant" != copy ]] || expected=0; }
runtime_hooks_setup() {
  mkdir -p "$c/package/DEBIAN"
  printf 'Package: su-thingsboard-probe\nVersion: 2.0\nArchitecture: amd64\nMaintainer: Fixture <fixture@example.invalid>\nDescription: package fixture without system units\n' > "$c/package/DEBIAN/control"
  dpkg-deb --build "$c/package" "$c/package.deb" > /dev/null
  printf '17\n' > "$c/java-version"
  if [[ "$role" == update ]]; then
    mkdir -p "$c/thingsboard" "$c/etc/thingsboard/conf"
    printf 'USER database/port\n' > "$c/etc/thingsboard/conf/thingsboard.conf"
  fi
}
runtime_hooks_assert() {
  if [[ "$rc" == 0 ]]; then check "$(cat "$c/java-version")" 25 "$app/$variant supported Java reaches package/upgrade consumer"; fi
  if [[ "$role" == update ]]; then check "$(cat "$c/etc/thingsboard/conf/thingsboard.conf")" 'USER database/port' "$app/$variant packaged config/DB secret/port retained"; fi
}
runtime_hooks_main "$@"
