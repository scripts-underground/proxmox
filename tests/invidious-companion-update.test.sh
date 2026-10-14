#!/usr/bin/env bash
# The companion is checked after Invidious, and is redeployed when its binary is missing.
set -euo pipefail

ROOT=$(realpath "$(dirname "${BASH_SOURCE[0]}")/..")
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT
export work STD=''
mkdir -p "$work/opt/invidious/src" "$work/opt/invidious-companion"
printf 'x' > "$work/opt/invidious/src/invidious.cr"
printf 'x' > "$work/opt/invidious-companion/invidious_companion"
chmod +x "$work/opt/invidious-companion/invidious_companion"
sed -n '/^function update_script() {/,/^}/p' "$ROOT/scripts/lxc/invidious.sh" |
  sed "s#/opt#$work/opt#g" > "$work/update.sh"

msg_info() { :; }
msg_ok() { :; }
msg_warn() { :; }
msg_error() { :; }
header_info() { :; }
check_container_storage() { :; }
check_container_resources() { :; }
uname() { echo x86_64; }
systemctl() { :; }
create_backup() { :; }
restore_backup() { :; }
make() { :; }
# Invidious is current unless MAIN_DUE=1; the companion is due only when forced.
check_for_gh_release() {
  printf '%s:%s\n' "$1" "${UPDATE_FORCE:-}" >> "$work/checks.log"
  [[ "$1" == Invidious && "${MAIN_DUE:-0}" == 1 ]] && return 0
  [[ "$1" == "Invidious Companion" && "${UPDATE_FORCE:-}" == 1 ]] && return 0
  return 1
}
fetch_and_deploy_gh_release() {
  printf '%s clean=%s force=%s\n' "$1" "${CLEAN_INSTALL:-}" "${FORCE_DEPLOY:-}" >> "$work/fetch.log"
}
export -f msg_info msg_ok msg_warn msg_error header_info check_container_storage \
  check_container_resources uname systemctl create_backup restore_backup make \
  check_for_gh_release fetch_and_deploy_gh_release

run_update() {
  bash -c 'set -Eeuo pipefail; source "$1"; update_script' _ "$work/update.sh" > /dev/null
}

run_update
[[ "$(< "$work/checks.log")" == $'Invidious:\nInvidious Companion:0' ]]
[[ ! -e "$work/fetch.log" ]]
printf 'PASS companion is checked and left alone when Invidious and the companion are current\n'

rm -f "$work/checks.log"
rm -f "$work/opt/invidious-companion/invidious_companion"
run_update
[[ "$(< "$work/checks.log")" == $'Invidious:\nInvidious Companion:1' ]]
[[ "$(< "$work/fetch.log")" == "Invidious Companion clean=1 force=1" ]]
printf 'PASS missing companion binary forces its redeploy\n'

rm -f "$work/checks.log" "$work/fetch.log"
printf 'x' > "$work/opt/invidious-companion/invidious_companion"
chmod +x "$work/opt/invidious-companion/invidious_companion"
MAIN_DUE=1 run_update
[[ "$(< "$work/checks.log")" == $'Invidious:\nInvidious Companion:0' ]]
[[ "$(< "$work/fetch.log")" == "Invidious clean=1 force=" ]]
printf 'PASS companion check runs after a main update\n'
