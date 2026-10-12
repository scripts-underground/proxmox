#!/usr/bin/env bash
# update_script must run under set -u without install-time variables, and set up uv only when an update is applied.
set -euo pipefail

ROOT=$(realpath "$(dirname "${BASH_SOURCE[0]}")/..")
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT
export work STD='' HOME="$work"
mkdir -p "$work/opt/autocaliweb/koreader/plugins/acwsync.koplugin" "$work/opt/autocaliweb/cps/static" "$work/systemd"
printf 'x' > "$work/opt/autocaliweb/koreader/plugins/acwsync.koplugin/main.lua"
printf '1.0' > "$work/.autocaliweb"
printf 'AmbientCapabilities=x\nCALIBRE_PORT=80\n' > "$work/systemd/autocaliweb.service"
sed -n '/^function update_script() {/,/^}/p' "$ROOT/scripts/lxc/autocaliweb.sh" |
  sed "s#/opt/autocaliweb#$work/opt/autocaliweb#g; s#/etc/systemd/system#$work/systemd#g" > "$work/update.sh"

log_call() { printf '%s\n' "$*" >> "$work/calls.log"; }
msg_info() { :; }
msg_ok() { :; }
msg_error() { :; }
header_info() { :; }
check_container_storage() { :; }
check_container_resources() { :; }
systemctl() { log_call systemctl "$@"; }
setup_uv() { log_call setup_uv; }
get_latest_codeberg_release() { log_call get_latest "$@"; }
check_for_codeberg_release() {
  log_call check "$@"
  [[ "${DUE:-0}" == 1 ]]
}
fetch_and_deploy_codeberg_release() { log_call fetch "$1"; }
uv() { log_call uv "$@"; }
sqlite3() { log_call sqlite3 "$@"; }
tar() {
  log_call tar "$1"
  [[ "$1" == -cf ]] && : > "$HOME/autocaliweb_bkp.tar"
  return 0
}
cp() { log_call cp "$@"; }
chown() { :; }
zip() { :; }
curl() { log_call curl; }
export -f log_call msg_info msg_ok msg_error header_info check_container_storage \
  check_container_resources systemctl setup_uv get_latest_codeberg_release \
  check_for_codeberg_release fetch_and_deploy_codeberg_release uv sqlite3 tar cp chown zip curl

run_update() {
  rm -f "$work/calls.log"
  rc=0
  bash -c 'set -u; source "$1"; update_script' _ "$work/update.sh" > /dev/null || rc=$?
}

DUE=0 run_update
[[ "$rc" == 0 && "$(< "$work/calls.log")" == "check autocaliweb gelbphoenix/autocaliweb" ]]
printf 'PASS an update with no new release sets up nothing\n'

DUE=1 run_update
calls=$(< "$work/calls.log")
[[ "$rc" == 0 ]]
[[ "$calls" == *$'\nsetup_uv\n'* ]]
[[ "$calls" == *"sqlite3 /etc/autocaliweb/app.db UPDATE settings SET config_port='80'"* ]]
[[ "$calls" != *get_latest* ]]
printf 'PASS a due update runs under set -u, sets up uv and uses the fixed app.db path\n'
