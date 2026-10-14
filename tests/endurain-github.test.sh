#!/usr/bin/env bash
# Endurain moved to GitHub: the update check and both deploys must use endurain-project/endurain.
set -euo pipefail

ROOT=$(realpath "$(dirname "${BASH_SOURCE[0]}")/..")
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT
export work STD='' HOME="$work" PG_DB_NAME=enduraindb PG_DB_USER=endurain PG_DB_PASS=pw LOCAL_IP=10.0.0.2
mkdir -p "$work/opt/endurain/backend" "$work/opt/endurain/frontend/dist" "$work/systemd"
script="$ROOT/scripts/lxc/endurain.sh"
{
  sed -n '/^function install_script() {/,/^function post_install_script() {/p' "$script" | sed '$d'
  sed -n '/^function update_script() {/,/^# shellcheck disable=SC1090/p' "$script"
} | sed "s#/opt/endurain#$work/opt/endurain#g; s#/etc/systemd/system#$work/systemd#g" > "$work/hooks.sh"

log_call() { printf '%s\n' "$*" >> "$work/calls.log"; }
msg_info() { :; }
msg_ok() { :; }
msg_error() { :; }
header_info() { :; }
check_container_storage() { :; }
check_container_resources() { :; }
apt() { :; }
setup_uv() { :; }
setup_nodejs() { :; }
setup_postgresql() { :; }
setup_postgresql_db() { :; }
npm() { :; }
uv() { :; }
openssl() { printf 'abc\n'; }
systemctl() { :; }
create_backup() { :; }
restore_backup() { :; }
check_for_gh_release() {
  log_call check "$@"
  [[ "${DUE:-0}" == 1 ]]
}
fetch_and_deploy_gh_release() { log_call fetch "$@"; }
export -f log_call msg_info msg_ok msg_error header_info check_container_storage \
  check_container_resources apt setup_uv setup_nodejs setup_postgresql setup_postgresql_db \
  npm uv openssl systemctl create_backup restore_backup check_for_gh_release fetch_and_deploy_gh_release

run_hook() {
  rm -f "$work/calls.log"
  rc=0
  bash -c 'set -u; source "$1"; "$2"' _ "$work/hooks.sh" "$1" > /dev/null || rc=$?
}

DUE=1 run_hook update_script
calls=$(< "$work/calls.log")
[[ "$rc" == 0 ]]
[[ "$calls" == "check endurain endurain-project/endurain"* ]]
[[ "$calls" == *"fetch endurain endurain-project/endurain tarball latest $work/opt/endurain"* ]]
printf 'PASS a due update checks and deploys the GitHub repo\n'

DUE=0 run_hook update_script
[[ "$rc" == 0 && "$(< "$work/calls.log")" == "check endurain endurain-project/endurain" ]]
printf 'PASS a current update checks the GitHub repo and deploys nothing\n'

run_hook install_script
[[ "$rc" == 0 && "$(< "$work/calls.log")" == *"fetch endurain endurain-project/endurain tarball latest $work/opt/endurain"* ]]
printf 'PASS the install deploys the GitHub repo\n'
