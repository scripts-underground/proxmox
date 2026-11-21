#!/usr/bin/env bash
# Cold generated hooks, real packaged shell config and listener readback.
# Package and OpenRC effects are modeled; native acceptance is separate.
# shellcheck disable=SC2034,SC2154
set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/../lib/runtime-hooks/harness.sh"
script_type=lxc app=alpine-grafana
variants=(fresh existing-loopback existing-address existing-wildcard)
hook_paths=()
runtime_hooks_setup() {
  mkdir -p "$c/etc/conf.d"
  cat > "$c/etc/conf.d/grafana" << 'CONFIG'
GRAFANA_HOME=/var/lib/grafana
GRAFANA_OPTS="-config /etc/grafana.ini -homepath /usr/share/grafana
cfg:paths.data=$GRAFANA_HOME/data
cfg:paths.plugins=$GRAFANA_HOME/plugins
cfg:paths.provisioning=$GRAFANA_HOME/provisioning
cfg:server.http_addr=127.0.0.1
cfg:log.mode=syslog"
rc_need=logger
CONFIG
  case "$variant" in
    existing-address) sed -i 's/127\.0\.0\.1/192.0.2.43/' "$c/etc/conf.d/grafana" ;;
    existing-wildcard) sed -i 's/127\.0\.0\.1/0.0.0.0/' "$c/etc/conf.d/grafana" ;;
  esac
  printf '[security]\n;admin_user = admin\n;admin_password = admin\n[auth.anonymous]\n;enabled = false\n' > "$c/etc/grafana.ini"
  cp "$c/etc/conf.d/grafana" "$c/before"
  cp "$c/etc/grafana.ini" "$c/auth-before"
  stat -c '%d:%i' "$c/etc/conf.d/grafana" > "$c/inode-before"
  cp "$c/before" "$c/expected"
  [[ "$role" != install ]] || sed -i 's/127\.0\.0\.1/0.0.0.0/' "$c/expected"
  : > "$c/events"
}
runtime_hooks_model() {
  apk() { printf 'apk:%s\n' "$*" >> "$c/events"; }
  rc-service() {
    printf 'service:%s\n' "$*" >> "$c/events"
    cmp "$c/etc/conf.d/grafana" "$c/expected"
    # Consume the package's shell configuration, not the hook's success message.
    (
      source "$c/etc/conf.d/grafana"
      printf '%s\n' "$GRAFANA_OPTS" > "$c/listener-consumer"
    )
  }
  rc-update() { printf 'enable:%s\n' "$*" >> "$c/events"; }
}
runtime_hooks_assert() {
  check "$(cmp -s "$c/etc/conf.d/grafana" "$c/expected" && printf match || printf changed)" match "$app/$variant exact listener config"
  check "$(cmp -s "$c/etc/grafana.ini" "$c/auth-before" && printf retained || printf changed)" retained "$app/$variant authentication unchanged"
  check "$(grep '^cfg:server.http_addr=' "$c/listener-consumer" 2> /dev/null || true)" "$(grep '^cfg:server.http_addr=' "$c/expected")" "$app/$variant service consumes selected address"
  if [[ "$role" == install ]]; then
    check "$(cat "$c/events")" "$(printf 'apk:add grafana\nservice:grafana start\nenable:add grafana default')" "$app fresh configuration before start"
  else
    check "$(stat -c '%d:%i' "$c/etc/conf.d/grafana")" "$(cat "$c/inode-before")" "$app/$variant update retains config inode"
    check "$(cat "$c/events")" "$(printf 'apk:-U upgrade\nservice:grafana restart')" "$app/$variant native package update only"
  fi
}
runtime_hooks_main "$@"
