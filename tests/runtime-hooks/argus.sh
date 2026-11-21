#!/usr/bin/env bash
# runtime-hooks-contract: lxc start-on-success
# shellcheck disable=SC2034,SC2154
# Real release/bundle/pending owners; HTTP and service control are modeled.
set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/../lib/runtime-hooks/harness.sh"
app=argus
script_type=lxc
variants=(fresh update current pending checker download runtime)
hook_paths=()
runtime_hooks_variant() {
  [[ "$variant" != checker ]] || fault=checker
}
runtime_hooks_model() {
  : > "$c/requests"
  get_system_arch() { printf amd64; }
  curl() {
    [[ "$APP_FAULT" != checker ]] || return 17
    local out='' format='' url='' tag=0.39.1 body
    while (($#)); do
      case "$1" in
        -o)
          out=$2
          shift
          ;;
        -w)
          format=$2
          shift
          ;;
        https:*) url=$1 ;;
      esac
      shift
    done
    # A moving latest must not replace the release already selected by the check.
    if [[ "$url" == */latest && -s "$c/requests" && "$APP_ROLE" == update ]]; then tag=0.40.0; fi
    [[ "$url" != */tags/* ]] || tag=${url##*/}
    printf '%s\n' "$url" >> "$c/requests"
    body="{\"tag_name\":\"$tag\",\"assets\":[{\"name\":\"Argus-$tag.linux-amd64\",\"browser_download_url\":\"https://fixture.invalid/Argus-$tag.linux-amd64\"}]}"
    if [[ -n "$out" ]]; then printf '%s' "$body" > "$out"; else printf '%s' "$body"; fi
    [[ -z "$format" ]] || printf 200
  }
  curl_download() {
    [[ "$APP_FAULT" != download ]] || return 22
    local tag=${2##*/Argus-}
    printf '#!/bin/sh\nprintf "consumer-%s\\n"\n' "${tag%.linux-amd64}" > "$1"
  }
  systemctl() {
    printf '%s\n' "$*" >> "$c/services"
    if [[ "$1" == start ]]; then
      [[ "$APP_FAULT" != runtime ]] || return 51
      /opt/argus/Argus > "$c/started-consumer"
    fi
  }
}
runtime_hooks_setup() {
  : > "$c/requests"
  mkdir -p "$c/opt/argus/data"
  printf 'operator data\n' > "$c/opt/argus/data/argus.db"
  if [[ "$role" == update ]]; then
    printf 'operator config\n' > "$c/opt/argus/config.yml"
    chmod 0640 "$c/opt/argus/config.yml"
    printf '#!/bin/sh\nprintf "consumer-0.39.0\\n"\n' > "$c/opt/argus/Argus"
    chmod 0755 "$c/opt/argus/Argus"
    printf '0.39.0\n' > "$c/home/.argus"
    if [[ "$variant" == current || "$variant" == pending ]]; then printf '0.39.1\n' > "$c/home/.argus"; fi
    if [[ "$variant" == pending ]]; then
      printf 'interrupted update\n' > "$c/state/argus"
      rm "$c/opt/argus/Argus"
    fi
  fi
}
runtime_hooks_expected() { [[ "$fault" != checker ]] || expected=17; }
runtime_hooks_assert() {
  check "$(cat "$c/opt/argus/data/argus.db")" 'operator data' "$app/$variant data retained"
  if [[ "$role" == update ]]; then
    check "$(cat "$c/opt/argus/config.yml")" 'operator config' "$app/$variant configuration retained"
    check "$(stat -c %a "$c/opt/argus/config.yml")" 640 "$app/$variant configuration metadata retained"
    if [[ "$fault" == checker || "$variant" == current ]]; then
      check "$(wc -l < "$c/services")" 0 "$app/$variant no service effects before positive release selection"
    elif [[ "$rc" == 0 ]]; then
      check "$("$c/opt/argus/Argus")" consumer-0.39.1 "$app/$variant selected release reaches executable consumer"
      check "$(cat "$c/started-consumer")" consumer-0.39.1 "$app/$variant started service consumes selected executable"
      check "$(cat "$c/home/.argus")" 0.39.1 "$app/$variant marker belongs to selected release"
    fi
  elif [[ "$rc" == 0 ]]; then
    check "$("$c/opt/argus/Argus")" consumer-0.39.1 "$app fresh executable consumer"
    local seeded
    seeded=$(ruby -ryaml -rjson -e '
      config = YAML.load_file(ARGV[0])
      puts JSON.generate({
        global: config.dig("defaults", "service", "options", "semantic_versioning"),
        argus_override: config.dig("service", "release-argus/argus", "options", "semantic_versioning"),
        community_override: config.dig("service", "community-scripts/ProxmoxVE", "options", "semantic_versioning"),
        community_target: config.dig("service", "community-scripts/ProxmoxVE", "latest_version", "url")
      })
    ' "$c/opt/argus/config.yml")
    check "$seeded" '{"global":true,"argus_override":null,"community_override":false,"community_target":"community-scripts/ProxmoxVE"}' "$app fresh YAML keeps the global default and opts only the date-tagged seeded monitor out"
  fi
}
runtime_hooks_retry_assert() {
  check "$("$c/opt/argus/Argus")" consumer-0.39.1 "$app/$variant frozen pending retry consumes selected release"
  check "$(cat "$c/opt/argus/config.yml")" 'operator config' "$app/$variant retry preserves configuration"
}
runtime_hooks_failure_services_assert() {
  local starts=0
  [[ "$fault" != runtime ]] || starts=1
  check "$(grep -Ec '^(start|reload|restart)|--now' "$c/services" || true)" "$starts" "$app/$variant failure admits only its explicit failed-start attempt"
}
runtime_hooks_main "$@"
