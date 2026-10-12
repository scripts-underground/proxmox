#!/usr/bin/env bash
# A release-check error stops the Forgejo and Readeck updates instead of reporting "No update required".
set -euo pipefail

ROOT=$(realpath "$(dirname "${BASH_SOURCE[0]}")/..")
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT

msg_info() { :; }
msg_ok() { printf '%s\n' "$*" >> "$work/msgs"; }
msg_error() { :; }
header_info() { :; }
check_container_storage() { :; }
check_container_resources() { :; }
systemctl() { :; }
fetch_and_deploy_codeberg_release() { printf 'deploy\n' >> "$work/calls"; }
check_for_codeberg_release() { return "$CHECK_RC"; }

for app in forgejo readeck; do
  # shellcheck disable=SC2034 # read by the sourced update_script
  APP=$app
  mkdir -p "$work/opt/$app"
  sed -n '/^function update_script() {/,/^}/p' "$ROOT/scripts/lxc/$app.sh" |
    sed "s#/opt/#$work/opt/#g" > "$work/$app.sh"
  for CHECK_RC in 22 1; do
    : > "$work/msgs"
    rc=0
    # shellcheck disable=SC1090 # generated per app above
    (source "$work/$app.sh" && update_script) || rc=$?
    [[ ! -e "$work/calls" ]]
    if [[ "$CHECK_RC" == 22 ]]; then
      [[ "$rc" == 22 ]]
      [[ "$(< "$work/msgs")" != *"No update required"* ]]
      printf 'PASS %s: checker error 22 exits 22 without "No update required"\n' "$app"
    else
      [[ "$rc" == 0 ]]
      [[ "$(< "$work/msgs")" == *"No update required"* ]]
      printf 'PASS %s: checker status 1 still reports no update and exits 0\n' "$app"
    fi
  done
done
