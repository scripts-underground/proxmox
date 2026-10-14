#!/usr/bin/env bash
# Each wanderer plugin deploys to its own directory, the plugin loop runs when the app is
# current, and a missing plugin.wasm forces that plugin's redeploy.
set -euo pipefail

ROOT=$(realpath "$(dirname "${BASH_SOURCE[0]}")/..")
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT
export APP=Wanderer STD='' LOCAL_IP=10.0.0.2 IP=10.0.0.2
calls="$work/calls"
plugins="$work/opt/wanderer/data/plugins"
mkdir -p "$work/bin" "$work/etc/systemd/system" "$work/opt/wanderer/source/"{db,web,search}
touch "$work/opt/wanderer/start.sh"

# Keep every /opt, /etc and /usr/local/bin write inside the scratch directory.
sed -n '/^function install_script() {/,/^function post_install_script/{/^function post_install_script/!p;}' "$ROOT/scripts/lxc/wanderer.sh" |
  sed "s#/opt/wanderer#$work/opt/wanderer#g; s#/etc/systemd#$work/etc/systemd#g; s#/usr/local/bin#$work/bin#g" > "$work/install.sh"
sed -n '/^function update_script() {/,/^}/p' "$ROOT/scripts/lxc/wanderer.sh" |
  sed "s#/opt/wanderer#$work/opt/wanderer#g" > "$work/update.sh"
source "$work/install.sh"
source "$work/update.sh"

msg_info() { :; }
msg_ok() { :; }
msg_warn() { :; }
msg_error() { :; }
header_info() { :; }
check_container_storage() { :; }
check_container_resources() { :; }
setup_go() { :; }
setup_nodejs() { :; }
get_system_arch() { echo amd64; }
apt() { :; }
go() { :; }
npm() { :; }
systemctl() { :; }
sleep() { :; }
create_backup() { :; }
restore_backup() { :; }
check_for_gh_release() {
  [[ "$1" == wanderer ]] && return "${APP_UPDATE:-1}"
  return 1
}
fetch_and_deploy_gh_release() { echo "$1 force=${FORCE_DEPLOY:-unset} dir=$5" >> "$calls"; }
expect() {
  grep -qxF "$1" "$calls" || {
    echo "FAIL $2: missing '$1'"
    cat "$calls"
    exit 1
  }
  echo "PASS $2"
}

: > "$calls"
(install_script)
for p in hammerhead komoot strava; do
  expect "wanderer-plugin-$p force=unset dir=$plugins/$p" "install deploys $p to its own directory"
done

mkdir -p "$plugins"/{hammerhead,komoot,strava}
touch "$plugins"/{hammerhead,komoot,strava}/plugin.wasm
: > "$calls"
(update_script)
for p in hammerhead komoot strava; do
  expect "wanderer-plugin-$p force=0 dir=$plugins/$p" "app current: $p loop runs"
done

rm "$plugins/komoot/plugin.wasm"
: > "$calls"
(update_script)
expect "wanderer-plugin-komoot force=1 dir=$plugins/komoot" "missing plugin.wasm forces komoot"
expect "wanderer-plugin-hammerhead force=0 dir=$plugins/hammerhead" "present plugin.wasm is not forced"

: > "$calls"
(APP_UPDATE=0 update_script)
expect "wanderer-plugin-strava force=0 dir=$plugins/strava" "app updated: plugin loop still runs"
