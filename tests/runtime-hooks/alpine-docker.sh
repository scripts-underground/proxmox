#!/usr/bin/env bash
# shellcheck disable=SC2034,SC2154
# Real cold bundles and checked single-file publication; APK/Docker are models.
set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/../lib/runtime-hooks/addon-release.sh"
app=alpine-docker
script_type=lxc
release_app=docker-compose release_mode=singlefile release_asset=docker-compose-linux-x86_64
variants=(fresh update no-update selected pending checker download copy missing-plugin missing-directory invalid-plugin package-failure)
hook_paths=()

runtime_hooks_variant() {
  case "$variant" in checker | download | copy | package-failure) fault=$variant ;; esac
}
runtime_hooks_model() {
  addon_release_model
  apk() {
    printf '%s\n' "$*" >> "$c/packages"
    [[ "$APP_FAULT" != package-failure ]] || return 53
  }
  rc-update() { printf 'enable %s\n' "$*" >> "$c/services"; }
  rc-service() { printf '%s %s\n' "$2" "$1" >> "$c/services"; }
  sleep() { :; }
  uname() { printf 'x86_64\n'; }
  docker() {
    if [[ "$1" == compose && "$2" == version ]]; then
      "$HOME/.docker/cli-plugins/docker-compose"
    fi
  }
  cp() {
    if [[ "$APP_FAULT" == copy && "${!#}" == */.asset-file.* ]]; then
      command cp "$@"
      return 41
    fi
    command cp "$@"
  }
  curl_download() {
    if [[ "$APP_FAULT" == download ]]; then
      printf 'partial transfer\n' > "$1"
      return 18
    fi
    addon_release_download "$@"
  }
  curl() {
    local arg out='' url=''
    local -a args=("$@")
    while (($#)); do
      arg=$1
      case "$arg" in -o)
        out=$2
        shift
        ;;
      https:*) url=$arg ;; esac
      shift
    done
    if [[ "$url" == *'/releases/download/'* ]]; then
      curl_download "$out" "$url"
    else
      # Retain the real release request/parser and model only HTTP transport.
      addon_release_curl "${args[@]}"
    fi
  }
}
addon_release_setup() {
  : > "$c/packages"
  if [[ "$role" == update ]]; then
    mkdir -p "$c/home/.docker/cli-plugins"
    printf '#!/usr/bin/env bash\nprintf "old Compose plugin\\n"\n' > "$c/home/.docker/cli-plugins/docker-compose"
    chmod 0755 "$c/home/.docker/cli-plugins/docker-compose"
    printf 'saved Docker client settings\n' > "$c/home/.docker/config.json"
    sha256sum < "$c/home/.docker/cli-plugins/docker-compose" > "$c/plugin-before"
    stat -c '%i %a %u %g' "$c/home/.docker/cli-plugins/docker-compose" > "$c/plugin-meta-before"
    printf '%s\n' "$([[ "$variant" == no-update || "$variant" == pending || "$variant" == missing-* || "$variant" == invalid-plugin ]] && printf 2.0.0 || printf 1.0.0)" > "$c/home/.docker-compose"
    if [[ "$variant" == pending ]]; then
      printf 'interrupted update\n' > "$c/state/$app"
      printf 'damaged plugin\n' > "$c/home/.docker/cli-plugins/docker-compose"
    fi
    case "$variant" in
      missing-plugin) rm "$c/home/.docker/cli-plugins/docker-compose" ;;
      missing-directory) rm -r "$c/home/.docker/cli-plugins" ;;
      invalid-plugin) printf 'damaged plugin\n' > "$c/home/.docker/cli-plugins/docker-compose" ;;
    esac
  fi
}
runtime_hooks_expected() {
  case "$fault" in checker) expected=17 ;; package-failure) expected=53 ;; esac
}
alpine_docker_preserved_assert() {
  [[ "$role" != update ]] || check "$(cat "$c/home/.docker/config.json")" 'saved Docker client settings' "$app/$variant client configuration retained"
}
runtime_hooks_assert() {
  alpine_docker_preserved_assert
  if [[ "$rc" == 0 ]]; then
    local desired='selected v2.0.0'
    [[ "$variant" != no-update ]] || desired='old Compose plugin'
    check "$("$c/home/.docker/cli-plugins/docker-compose" 2> /dev/null || true)" "$desired" "$app/$variant plugin executable consumer"
    if [[ "$variant" == no-update ]]; then
      check "$(stat -c %s "$c/downloads")" 0 "$app/$variant no unnecessary deployment"
      check "$(stat -c '%i %a %u %g' "$c/home/.docker/cli-plugins/docker-compose")" "$(cat "$c/plugin-meta-before")" "$app/$variant current plugin remains in place"
    else
      check "$(grep -c '/releases/latest$' "$c/requests" || true)" 1 "$app/$variant one release selection"
      check "$(grep -c 'v9.0.0' "$c/downloads" || true)" 0 "$app/$variant never deploys moving latest"
    fi
  elif [[ "$role" == update ]]; then
    check "$(sha256sum < "$c/home/.docker/cli-plugins/docker-compose")" "$(cat "$c/plugin-before")" "$app/$variant failure preserves previous plugin bytes"
    check "$(stat -c '%i %a %u %g' "$c/home/.docker/cli-plugins/docker-compose")" "$(cat "$c/plugin-meta-before")" "$app/$variant failure preserves previous plugin identity"
    check "$(cat "$c/home/.docker-compose")" 1.0.0 "$app/$variant failure does not advance release marker"
  fi
}
runtime_hooks_retry_assert() {
  alpine_docker_preserved_assert
  check "$("$c/home/.docker/cli-plugins/docker-compose")" 'selected v2.0.0' "$app/$variant pending retry repairs plugin"
  check "$(cat "$c/home/.docker-compose")" 2.0.0 "$app/$variant retry publishes selected marker"
}
runtime_hooks_retry_needed() {
  [[ "$role" == update && "$expected" != 0 ]] || return 1
  # Moving latest models a race within one invocation, not between invocations.
  : > "$c/requests"
}
runtime_hooks_main "$@"
