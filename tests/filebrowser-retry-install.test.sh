#!/usr/bin/env bash
# A failed filebrowser binary install removes the version marker so the next run retries.
set -euo pipefail

ROOT=$(realpath "$(dirname "${BASH_SOURCE[0]}")/..")
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT
export HOME="$work/home" APP="File Browser" TAB='' STD='' OS_FAMILY=debian OS_TYPE=Debian INIT_SYSTEM=systemd
export var_addon_bin_path="$work/bin/filebrowser" var_addon_db_dir="$work/db"
export var_addon_db_path="$work/db/filebrowser.db" var_addon_dist_path="$work/dist" var_addon_default_port=8080
mkdir -p "$HOME" "$work/bin" "$work/etc/systemd/system" "$work/etc/init.d"

# Keep the install hook's /etc writes inside the scratch directory.
sed -n '/^function install_script() {/,/^function post_install_script/{/^function post_install_script/!p;}' "$ROOT/scripts/addon/filebrowser.sh" |
  sed "s#/etc/#$work/etc/#g" > "$work/install.sh"
sed -n '/^function update_script() {/,/^}/p' "$ROOT/scripts/addon/filebrowser.sh" > "$work/update.sh"
source "$work/install.sh"
source "$work/update.sh"

msg_info() { :; }
msg_ok() { :; }
msg_error() { :; }
apt() { :; }
filebrowser() { :; }
systemctl() { :; }
get_system_arch() { echo amd64; }
check_for_gh_release() { return 0; }
# The framework writes the version marker before the binary is installed.
fetch_and_deploy_gh_release() {
  mkdir -p "$var_addon_dist_path"
  printf 'bin' > "$var_addon_dist_path/filebrowser"
  printf '1.0' > "$HOME/.filebrowser"
}
install() { return 1; }

rc=0
(install_script < /dev/null) || rc=$?
[[ "$rc" != 0 ]]
[[ ! -e "$HOME/.filebrowser" ]]
printf 'PASS failed install removes the marker and exits non-zero\n'

rc=0
(update_script) || rc=$?
[[ "$rc" != 0 ]]
[[ ! -e "$HOME/.filebrowser" ]]
printf 'PASS failed update removes the marker and exits non-zero\n'
