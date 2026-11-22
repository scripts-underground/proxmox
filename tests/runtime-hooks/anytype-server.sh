#!/usr/bin/env bash
# shellcheck disable=SC2034,SC2154
# Real cold bundles/replacement/filesystem; database/package/service effects modeled.
set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/../lib/runtime-hooks/harness.sh"
app=anytype-server
script_type=lxc
variants=(fresh update download copy)
hook_paths=()

runtime_hooks_model() {
  apt() { :; }
  setup_mongodb() {
    cat > "$c/etc/mongod.conf" << 'EOF'
storage:
  dbPath: /var/lib/mongodb
systemLog:
  destination: file
  path: /var/log/mongodb/mongod.log
net:
  bindIp: 127.0.0.1
#replication:
EOF
  }
  setup_deb822_repo() { :; }
  sleep() { :; }
  mongosh() {
    # Native mongod otherwise selects its absent /data/db and cannot answer.
    grep -q 'dbPath: /var/lib/mongodb' "$c/etc/mongod.conf" || return 58
    grep -q 'bindIp: 127.0.0.1' "$c/etc/mongod.conf" || return 58
  }
  systemctl() {
    printf '%s\n' "$*" >> "$c/services"
    case "$*" in
      'start anytype' | 'enable -q --now anytype')
        test -f /opt/anytype/.env || return 59
        if [[ "$APP_ROLE" == update && ! -f /opt/anytype/network.yml ]]; then
          printf 'new generated network identity\n' > /opt/anytype/network.yml
        fi
        ;;
    esac
  }
  curl() {
    local out='' format=''
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
      esac
      shift
    done
    local body='{"tag_name":"v1.7.0-2026-10-12","assets":[{"browser_download_url":"https://runtime-hooks.invalid/any-sync-bundle_new_linux_amd64.tar.gz"}]}'
    if [[ -n "$out" ]]; then printf '%s' "$body" > "$out"; else printf '%s' "$body"; fi
    [[ -z "$format" ]] || printf 200
  }
}
runtime_hooks_setup() {
  printf '#!/bin/sh\nexit 0\n' > "$c/payload/any-sync-bundle"
  chmod 0755 "$c/payload/any-sync-bundle"
  printf 'old\n' > "$c/home/.anytype"
  if [[ "$role" == update ]]; then
    mkdir -p "$c/opt/anytype/data/storage"
    printf '#!/bin/sh\nexit 0\n' > "$c/opt/anytype/any-sync-bundle"
    chmod 0755 "$c/opt/anytype/any-sync-bundle"
    printf 'ANY_SYNC_BUNDLE_CONFIG=/opt/anytype/network.yml\nANY_SYNC_BUNDLE_LOG_LEVEL=debug\n' > "$c/opt/anytype/.env"
    printf 'private fixture configuration\n' > "$c/opt/anytype/data/bundle-config.yml"
    printf 'saved configured network identity\n' > "$c/opt/anytype/network.yml"
    printf 'stored block bytes\n' > "$c/opt/anytype/data/storage/block"
  fi
}
runtime_hooks_assert() {
  if [[ "$role" == install ]]; then
    check "$(grep -c 'dbPath: /var/lib/mongodb' "$c/etc/mongod.conf")" 1 "$app/$variant native MongoDB storage retained"
    check "$(grep -c 'bindIp: 127.0.0.1' "$c/etc/mongod.conf")" 1 "$app/$variant native MongoDB loopback binding retained"
    check "$(grep -c 'replSetName:.*rs0' "$c/etc/mongod.conf")" 1 "$app/$variant replica set configured"
  else
    check "$(cat "$c/opt/anytype/.env" 2> /dev/null || true)" $'ANY_SYNC_BUNDLE_CONFIG=/opt/anytype/network.yml\nANY_SYNC_BUNDLE_LOG_LEVEL=debug' "$app/$variant operator environment retained"
    check "$(cat "$c/opt/anytype/data/bundle-config.yml" 2> /dev/null || true)" 'private fixture configuration' "$app/$variant network identity retained"
    check "$(cat "$c/opt/anytype/network.yml" 2> /dev/null || true)" 'saved configured network identity' "$app/$variant configured network identity retained"
    check "$(cat "$c/opt/anytype/data/storage/block" 2> /dev/null || true)" 'stored block bytes' "$app/$variant block storage retained"
  fi
}
runtime_hooks_retry_assert() {
  check "$(cat "$c/opt/anytype/.env")" $'ANY_SYNC_BUNDLE_CONFIG=/opt/anytype/network.yml\nANY_SYNC_BUNDLE_LOG_LEVEL=debug' "$app/$variant retry retains environment"
  check "$(cat "$c/opt/anytype/network.yml")" 'saved configured network identity' "$app/$variant retry retains configured network identity"
}
runtime_hooks_more_cases() {
  local message
  message=$(bash -c '
    curl() { :; }
    source "$1"
    msg_ok() { :; }
    CREATING= GN= CL= INFO= YW= TAB= GATEWAY= BGN= IP=192.0.2.10
    post_install_script
  ' _ "$ROOT/scripts/lxc/anytype-server.sh")
  check "$(grep -c /opt/anytype/data/client-config.yml <<< "$message" || true)" 1 "$app/client configuration path is discoverable"
  check "$(grep -c '33010/TCP' <<< "$message" || true)" 1 "$app/DRPC TCP endpoint is identified"
  check "$(grep -c '33020/UDP' <<< "$message" || true)" 1 "$app/QUIC UDP endpoint is identified"
  check "$(grep -c 'http://' <<< "$message" || true)" 0 "$app/no nonexistent HTTP UI advertised"
}

runtime_hooks_main "$@"
