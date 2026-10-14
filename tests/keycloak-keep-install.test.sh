#!/usr/bin/env bash
# A failed Keycloak download leaves the install; a successful one keeps the release's new files and the user's conf.
set -euo pipefail

ROOT=$(realpath "$(dirname "${BASH_SOURCE[0]}")/..")
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT
export work STD=''
mkdir -p "$work/opt/keycloak/conf" "$work/opt/keycloak/providers/x" "$work/opt/keycloak/themes/t" "$work/opt/keycloak/bin"
printf 'old-conf' > "$work/opt/keycloak/conf/keycloak.conf"
printf 'old-provider' > "$work/opt/keycloak/providers/x/p.jar"
printf 'old-theme' > "$work/opt/keycloak/themes/t/theme.properties"
sed -n '/^function update_script() {/,/^}/p' "$ROOT/scripts/lxc/keycloak.sh" |
  sed "s#/opt#$work/opt#g" > "$work/update.sh"

msg_info() { :; }
msg_ok() { :; }
msg_warn() { :; }
msg_error() { :; }
header_info() { :; }
check_container_storage() { :; }
check_container_resources() { :; }
check_for_gh_release() { return 0; }
apt-get() { :; }
systemctl() { :; }

# Stubbed download: record what the fetch saw, then fail, or replace the tree as CLEAN_INSTALL would.
fetch_and_deploy_gh_release() {
  printf 'clean=%s conf=%s\n' "${CLEAN_INSTALL:-}" "$(< "$work/opt/keycloak/conf/keycloak.conf")" > "$work/fetch.log"
  [[ "$FETCH_MODE" == fail ]] && return 250
  rm -rf "$work/opt/keycloak/conf" "$work/opt/keycloak/providers" "$work/opt/keycloak/themes"
  mkdir -p "$work/opt/keycloak/conf" "$work/opt/keycloak/providers/y" "$work/opt/keycloak/themes/u"
  printf 'new-conf' > "$work/opt/keycloak/conf/keycloak.conf"
  printf 'new-default' > "$work/opt/keycloak/conf/new-default.properties"
  printf 'new-provider' > "$work/opt/keycloak/providers/y/new.jar"
}
export -f msg_info msg_ok msg_warn msg_error header_info check_container_storage \
  check_container_resources check_for_gh_release apt-get systemctl fetch_and_deploy_gh_release

# The hook runs in a child shell with errexit active, as run_update_script does.
run_update() {
  FETCH_MODE="$1" bash -c 'set -Eeuo pipefail; source "$1"; update_script' _ "$work/update.sh"
}

rc=0
run_update fail || rc=$?
[[ "$(< "$work/fetch.log")" == "clean=1 conf=old-conf" ]]
[[ "$rc" == 250 ]]
[[ "$(< "$work/opt/keycloak/conf/keycloak.conf")" == old-conf ]]
[[ "$(< "$work/opt/keycloak/providers/x/p.jar")" == old-provider ]]
[[ "$(< "$work/opt/keycloak/themes/t/theme.properties")" == old-theme ]]
printf 'PASS fetch runs with CLEAN_INSTALL=1 and a failed download keeps the install\n'

run_update ok
[[ "$(< "$work/opt/keycloak/conf/keycloak.conf")" == old-conf ]]
[[ "$(< "$work/opt/keycloak/conf/new-default.properties")" == new-default ]]
[[ "$(< "$work/opt/keycloak/providers/x/p.jar")" == old-provider ]]
[[ "$(< "$work/opt/keycloak/providers/y/new.jar")" == new-provider ]]
[[ "$(< "$work/opt/keycloak/themes/t/theme.properties")" == old-theme ]]
[[ ! -e "$work/opt/keycloak.old" ]]
printf "PASS successful update keeps the release's new files and the user's conf\n"

# A leftover keycloak.old from an earlier run holds the user's files and is reused, not overwritten.
mkdir -p "$work/opt/keycloak.old/conf"
printf 'user-conf' > "$work/opt/keycloak.old/conf/keycloak.conf"
printf 'release-default' > "$work/opt/keycloak/conf/keycloak.conf"
run_update ok
[[ "$(< "$work/opt/keycloak/conf/keycloak.conf")" == user-conf ]]
[[ ! -e "$work/opt/keycloak.old" ]]
printf 'PASS leftover keycloak.old is reused and the user conf wins\n'

# A stale keycloak.old.partial from an interrupted copy is discarded, never merged.
mkdir -p "$work/opt/keycloak.old.partial/conf"
printf 'stale' > "$work/opt/keycloak.old.partial/conf/stale.properties"
run_update ok
[[ ! -e "$work/opt/keycloak/conf/stale.properties" ]]
[[ ! -e "$work/opt/keycloak.old.partial" ]]
printf 'PASS stale keycloak.old.partial is discarded\n'
