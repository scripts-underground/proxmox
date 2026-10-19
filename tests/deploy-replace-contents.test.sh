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
  if [[ "${!#}" == "$CASE/target/" ]]; then
    printf 'partial copy' > "$CASE/target/content"
    return 1
  fi
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

# Extraction roots are private; only their entries belong in the app directory.
mkdir -m 700 "$work/private"
mkdir "$work/private/bin"
printf 'binary' > "$work/private/bin/server"
chmod 755 "$work/private/bin/server"
printf 'hidden payload' > "$work/private/.release"
printf 'spaced payload' > "$work/private/file with spaces"
ln -s bin/server "$work/private/server"
for clean in 0 1; do
  for mask in 022 027; do
    for state in existing new; do
      CASE="$work/metadata-$clean-$mask-$state"
      mkdir "$CASE"
      (
        umask "$mask"
        mkdir "$CASE/default"
        if [[ "$state" == existing ]]; then
          mkdir -m 755 "$CASE/target"
          # Different ownership detects accidental root-directory chown as well.
          if [[ "$EUID" == 0 ]]; then chown 12345:12346 "$CASE/target"; fi
          printf 'old payload' > "$CASE/target/old"
          expected=$(stat -c '%a:%u:%g' "$CASE/target")
        else
          expected=$(stat -c '%a:%u:%g' "$CASE/default")
        fi
        _deploy_replace_contents "$work/private" "$CASE/target" "$clean"
        actual=$(stat -c '%a:%u:%g' "$CASE/target")
        [[ "$actual" == "$expected" ]] || {
          printf 'FAIL %s clean=%s umask=%s metadata=%s expected=%s\n' "$state" "$clean" "$mask" "$actual" "$expected"
          exit 1
        }
        [[ "$(< "$CASE/target/.release")" == 'hidden payload' ]]
        [[ "$(< "$CASE/target/file with spaces")" == 'spaced payload' ]]
        [[ "$(stat -c %a "$CASE/target/bin/server")" == 755 && -L "$CASE/target/server" ]]
        if [[ "$state" == existing ]]; then
          if [[ "$clean" == 1 ]]; then [[ ! -e "$CASE/target/old" ]]; else [[ -f "$CASE/target/old" ]]; fi
        fi
      )
      printf 'PASS %s target keeps mode/owner with private source, clean=%s umask=%s; dotfiles and entry metadata copied\n' "$state" "$clean" "$mask"
    done
  done
done

fresh restore-metadata
chmod 755 "$CASE/target"
if [[ "$EUID" == 0 ]]; then chown 12345:12346 "$CASE/target"; fi
before=$(stat -c '%a:%u:%g' "$CASE/target")
cp() {
  if [[ "${!#}" == "$CASE/target/" ]]; then
    # Model a partial entry in this payload, not an arbitrary writer's sibling.
    command cp "$work/private/bin/server" "$CASE/target/file with spaces"
    return 1
  fi
  command cp "$@"
}
rc=0
_deploy_replace_contents "$work/private" "$CASE/target" 1 || rc=$?
unset -f cp
[[ "$rc" == 252 && "$(stat -c '%a:%u:%g' "$CASE/target")" == "$before" ]]
[[ "$(< "$CASE/target/content")" == 'old payload' && ! -e "$CASE/target/file with spaces" ]]
[[ -z "$(find "$CASE/target" -name '.deploy-aside*')" ]]
printf 'PASS partial-copy failure restores entries without changing target mode/owner\n'
