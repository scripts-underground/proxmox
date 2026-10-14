#!/usr/bin/env bash
# Clean deployments extract first, keep mounts and restore the old tree on failed copy.
set -euo pipefail

ROOT=$(realpath "$(dirname "${BASH_SOURCE[0]}")/..")
source "$ROOT/misc/tools.func"

work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT
export HOME="$work/home" TMPDIR="$work/tmp" STD=''
mkdir "$HOME" "$TMPDIR"

msg_info() { :; }
msg_ok() { :; }
msg_error() { :; }
ensure_dependencies() { :; }
getent() { return 0; }
MOUNTED=''
mountpoint() { [[ "$2" == "$MOUNTED" ]]; }
curl() {
  local prev='' arg
  for arg in "$@"; do
    [[ "$prev" == -o ]] && printf '{"tag_name":"v2.0.0"}' > "$arg"
    prev="$arg"
  done
  printf 200
}
curl_download() { cp "$ASSET" "$1"; }

mkdir -p "$work/src/app"
printf 'new payload' > "$work/src/app/content"
tar -czf "$work/good.tar.gz" -C "$work/src" app
fresh() {
  CASE="$work/$1"
  mkdir -p "$CASE/target"
  printf 'old payload' > "$CASE/target/content"
  printf 'old version' > "$HOME/.app"
  ASSET="$work/good.tar.gz"
  MOUNTED=''
}
deploy() { CLEAN_INSTALL=1 fetch_and_deploy_gh_release app owner/app tarball latest "$CASE/target"; }

fresh extract
printf 'not an archive' > "$work/bad.tar.gz"
ASSET="$work/bad.tar.gz"
rc=0
deploy || rc=$?
[[ "$rc" == 251 ]]
[[ "$(< "$CASE/target/content")" == 'old payload' ]]
[[ "$(< "$HOME/.app")" == 'old version' ]]
printf 'PASS failed extraction leaves target and marker unchanged\n'

fresh mounts
mkdir "$CASE/target/data"
printf 'mounted data' > "$CASE/target/data/row"
printf 'configuration' > "$CASE/target/.env"
MOUNTED="$CASE/target/data"
deploy
[[ "$(< "$CASE/target/data/row")" == 'mounted data' ]]
[[ "$(< "$CASE/target/.env")" == 'configuration' ]]
[[ "$(< "$CASE/target/content")" == 'new payload' ]]
[[ "$(< "$HOME/.app")" == '2.0.0' ]]
[[ -z "$(find "$CASE/target" -name '.deploy-aside*')" ]]
printf 'PASS clean deployment leaves mount points and root dotfiles untouched\n'

fresh copy
mkdir "$CASE/target/data"
printf 'mounted data' > "$CASE/target/data/row"
MOUNTED="$CASE/target/data"
cp() {
  case "$*" in *'/app/.'*) return 1 ;; esac
  command cp "$@"
}
rc=0
deploy || rc=$?
unset -f cp
[[ "$rc" == 252 ]]
[[ "$(< "$CASE/target/content")" == 'old payload' ]]
[[ "$(< "$CASE/target/data/row")" == 'mounted data' ]]
[[ "$(< "$HOME/.app")" == 'old version' ]]
[[ -z "$(find "$CASE/target" -name '.deploy-aside*')" ]]
printf 'PASS failed copy restores the old files and keeps the old marker\n'
