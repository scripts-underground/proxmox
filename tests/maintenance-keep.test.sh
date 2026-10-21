#!/usr/bin/env bash
# Native replacement/protection outcomes. Network producers and named failure
# boundaries are models; archives, mounts, links, metadata and rollback are real.
set -euo pipefail
systemd-detect-virt --vm --quiet || exit 1
: "${TMPDIR:?disk-backed TMPDIR required}"
case "$(realpath -e "$TMPDIR")" in /tmp | /tmp/*) exit 1 ;; esac
case "$(findmnt -rn -T "$TMPDIR" -o FSTYPE)" in '' | tmpfs | ramfs) exit 1 ;; esac
if [[ "${KEEP_NS:-}" != 1 ]]; then
  work=$(mktemp -d "$TMPDIR/maintenance-keep.XXXXXX")
  trap 'rm -rf -- "$work"' EXIT
  KEEP_NS=1 WORK_ROOT="$work" unshare -m --propagation private -- bash "$0"
  exit $?
fi
ROOT=$(realpath "$(dirname "${BASH_SOURCE[0]}")/..")
work="$WORK_ROOT"
# Only the pre-existing GitLab metadata literal is disk-mapped for its fixture.
sed "s|/tmp/gl_rel.json|$work/gl.json|g" "$ROOT/misc/tools.func" > "$work/tools.func"
source "$work/tools.func"
export STD='' HOME="$work/home"
mkdir -p "$HOME"
msg_info() { :; }
msg_ok() { :; }
msg_warn() { :; }
msg_error() { printf '%s\n' "$*" >&2; }
ensure_dependencies() { :; }
getent() { return 0; }
sleep() { :; }
failures=0
check() {
  if [[ "$1" == "$2" ]]; then printf 'PASS %s\n' "$3"; else
    printf 'FAIL %s: expected <%s>, got <%s>\n' "$3" "$2" "$1" >&2
    failures=$((failures + 1))
  fi
}
signature() { stat -c '%d:%i:%a:%u:%g:%Y' "$1"; }
snapshot() {
  python3 - "$1" << 'PY'
import hashlib,json,os,pathlib,stat,sys
p=pathlib.Path(sys.argv[1]);rows=[]
for f in [p]+sorted(p.rglob('*')):
 s=f.lstat();r=[str(f.relative_to(p)),stat.S_IMODE(s.st_mode),s.st_uid,s.st_gid,s.st_mtime_ns]
 if f.is_symlink():r+=['link',os.readlink(f)]
 elif f.is_file():r+=['file',hashlib.sha256(f.read_bytes()).hexdigest()]
 rows.append(r)
print(json.dumps(rows))
PY
}
fresh() {
  c="$work/$1"
  source_dir="$c/source"
  target="$c/target"
  mkdir -p "$source_dir/state/settings" "$source_dir/data" "$target/state/settings" "$target/data"
  printf 'new code\n' > "$source_dir/code"
  printf 'source config default\n' > "$source_dir/config.yaml"
  printf 'source nested default\n' > "$source_dir/state/settings/user.conf"
  printf 'new sibling\n' > "$source_dir/state/settings/new-code"
  printf 'source data default\n' > "$source_dir/data/row"
  printf 'old code\n' > "$target/code"
  printf 'user config\n' > "$target/config.yaml"
  printf 'user nested config\n' > "$target/state/settings/user.conf"
  printf 'user data\n' > "$target/data/row"
  printf 'obsolete\n' > "$target/obsolete"
  chmod 0751 "$target"
  chown 12345:12346 "$target"
  chmod 0700 "$target/data"
}
for clean in 0 1; do
  for fault in none copy move; do
    fresh "direct-$clean-$fault"
    before=$(signature "$target/data")
    root_mode=$(stat -c '%a:%u:%g' "$target")
    input=$(snapshot "$source_dir")
    cp() {
      if [[ "$fault" == copy && "${!#}" == "$target/"* ]]; then
        # Copy one entry from the current batch, not a future batch's filename.
        command cp -a -- "$3" "${!#}"
        return 41
      fi
      command cp "$@"
    }
    mv() {
      if [[ "$fault" == move && "$*" == *'.deploy-aside.'* && ! -e "$c/move-injected" ]]; then
        : > "$c/move-injected"
        return 42
      fi
      command mv "$@"
    }
    rc=0
    CLEAN_INSTALL_KEEP='config.yaml data state/settings/user.conf' _deploy_replace_contents "$source_dir" "$target" "$clean" || rc=$?
    expected=0
    [[ "$fault" == none ]] || expected=252
    check "$rc" "$expected" "direct/$clean/$fault status"
    check "$(cat "$target/config.yaml" 2> /dev/null || true)" 'user config' "direct/$clean/$fault config bytes"
    check "$(cat "$target/state/settings/user.conf" 2> /dev/null || true)" 'user nested config' "direct/$clean/$fault nested keep bytes"
    check "$(cat "$target/data/row" 2> /dev/null || true)" 'user data' "direct/$clean/$fault data bytes"
    check "$(signature "$target/data")" "$before" "direct/$clean/$fault persistent directory identity/metadata"
    check "$(stat -c '%a:%u:%g' "$target")" "$root_mode" "direct/$clean/$fault root metadata"
    check "$(snapshot "$source_dir")" "$input" "direct/$clean/$fault source bytes/metadata unchanged"
    if [[ "$fault" == none ]]; then
      check "$(cat "$target/state/settings/new-code" 2> /dev/null || true)" 'new sibling' "direct/$clean projected sibling is deployed"
    else check "$(cat "$target/code" 2> /dev/null || true)" 'old code' "direct/$clean/$fault rollback restores old code"; fi
    unset -f cp mv
    CLEAN_INSTALL_KEEP='config.yaml data state/settings/user.conf' _deploy_replace_contents "$source_dir" "$target" "$clean"
    check "$(cat "$target/code")" 'new code' "direct/$clean/$fault retry reaches new code"
    check "$(cat "$target/data/row")" 'user data' "direct/$clean/$fault retry retains user data"
  done
done
for bad in / /absolute . .. a/../b a/./b a//b a/ '*' $'data\n../escape'; do
  c="$work/bad-$failures-$RANDOM"
  mkdir "$c"
  rc=0
  CLEAN_INSTALL_KEEP="$bad" _deploy_replace_contents "$source_dir" "$c/not-created" 1 || rc=$?
  check "$rc" 65 "invalid keep '$bad' status"
  check "$(test -e "$c/not-created" && printf created || printf absent)" absent 'invalid keep fails before target creation'
done
fresh missing
rm -rf "$target/data"
CLEAN_INSTALL_KEEP=data _deploy_replace_contents "$source_dir" "$target" 1
check "$(cat "$target/data/row")" 'source data default' 'missing keep receives source default'
for clean in 0 1; do
  fresh "links-$clean"
  mkdir -p "$c/external/live"
  printf 'outside user bytes\n' > "$c/external/live/row"
  ln -s "$c/external" "$target/alias"
  ln -s "$c/absent" "$target/dangling"
  mkdir -p "$source_dir/alias/live"
  printf 'bad default\n' > "$source_dir/alias/live/row"
  printf 'default\n' > "$source_dir/dangling"
  rc=0
  CLEAN_INSTALL_KEEP='alias/live dangling' _deploy_replace_contents "$source_dir" "$target" "$clean" || rc=$?
  check "$rc" 0 "persistent links/$clean deployment status"
  check "$(readlink "$target/alias" 2> /dev/null || true)" "$c/external" 'symlink ancestor retained in place'
  check "$(readlink "$target/dangling" 2> /dev/null || true)" "$c/absent" 'dangling keep link retained'
  check "$(cat "$c/external/live/row")" 'outside user bytes' 'copy never traverses persistent link'
  fresh "mount-$clean"
  mkdir -p "$c/mounted" "$target/state/mount" "$source_dir/state/mount"
  printf 'mounted bytes\n' > "$c/mounted/row"
  printf 'archive collision\n' > "$source_dir/state/mount/row"
  mount --bind "$c/mounted" "$target/state/mount"
  mount_before=$(signature "$target/state/mount")
  rc=0
  _deploy_replace_contents "$source_dir" "$target" "$clean" || rc=$?
  check "$rc" 0 "nested bind/$clean deployment status"
  check "$(cat "$c/mounted/row")" 'mounted bytes' "nested bind/$clean underlying data survives source collision"
  check "$(signature "$target/state/mount")" "$mount_before" "nested bind/$clean identity/metadata unchanged"
done
for clean in 0 1; do
  fresh "mount-failure-$clean"
  mkdir -p "$c/mounted" "$target/state/mount with space" "$source_dir/state/mount with space"
  printf 'mounted user bytes\n' > "$c/mounted/row"
  printf 'bad mounted default\n' > "$source_dir/state/mount with space/row"
  mount --bind "$c/mounted" "$target/state/mount with space"
  before=$(signature "$target/state/mount with space")
  cp() {
    if [[ "${!#}" == "$target/"* ]]; then
      command cp -a -- "$3" "${!#}"
      return 41
    fi
    command cp "$@"
  }
  rc=0
  _deploy_replace_contents "$source_dir" "$target" "$clean" || rc=$?
  unset -f cp
  check "$rc" 252 "mounted path with spaces/$clean failed-copy status"
  check "$(cat "$target/code")" 'old code' "mounted path/$clean rollback restores ordinary code"
  check "$(cat "$c/mounted/row")" 'mounted user bytes' "mounted path/$clean failed copy cannot overwrite mount data"
  check "$(signature "$target/state/mount with space")" "$before" "mounted path/$clean failed copy preserves mount identity"
done
fresh archive-input
tar -czf "$c/good.tar.gz" -C "$c" source
(
  cd "$c"
  zip -qr "$c/good.zip" source
)
ASSET="$c/good.tar.gz" ZIP_ASSET="$c/good.zip"
curl_download() { command cp "$ASSET" "$1"; }
download_file() { command cp "$ASSET" "$2"; }
curl() {
  local out='' format='' url=''
  while (($#)); do
    case "$1" in -o)
      out="$2"
      shift
      ;;
    -w)
      format="$2"
      shift
      ;;
    https:*) url="$1" ;; esac
    shift
  done
  if [[ "$url" == *'/archive/'* || "$url" == https://fixture.invalid/* ]]; then
    if [[ "$url" == *.zip ]]; then command cp "$ZIP_ASSET" "$out"; else command cp "$ASSET" "$out"; fi
  else
    body='{"tag_name":"v2.0.0","draft":false,"prerelease":false,"assets":[{"name":"app.tar.gz","browser_download_url":"https://fixture.invalid/app.tar.gz"}]}'
    [[ "$url" != *gitlab.com/api* ]] || body='{"tag_name":"v2.0.0","assets":{"links":[{"url":"https://fixture.invalid/app.tar.gz"}]}}'
    if [[ -n "$out" ]]; then printf '%s' "$body" > "$out"; else printf '%s' "$body"; fi
  fi
  [[ -z "$format" ]] || printf 200
}
for provider in gh-source gh-archive gh-tag cb-source cb-archive cb-tag gl-source gl-archive url-tar url-zip; do
  for fault in none copy; do
    fresh "$provider-$fault"
    mkdir -p "$source_dir/database" "$target/database"
    printf 'user custom database\n' > "$target/database/custom name.sqlite"
    # Consumed by the sourced replacement helper through every provider.
    # shellcheck disable=SC2034
    CLEAN_INSTALL_KEEP_PATHS=('database/custom name.sqlite')
    printf 'old\n' > "$HOME/.probe"
    cp() {
      if [[ "$fault" == copy && "${!#}" == "$target/"* ]]; then
        printf partial > "$target/code"
        return 41
      fi
      command cp "$@"
    }
    rc=0
    export CLEAN_INSTALL=1 CLEAN_INSTALL_KEEP='config.yaml data'
    case "$provider" in
      gh-source) fetch_and_deploy_gh_release probe owner/app tarball v2.0.0 "$target" || rc=$? ;;
      gh-archive) fetch_and_deploy_gh_release probe owner/app prebuild v2.0.0 "$target" app.tar.gz || rc=$? ;;
      gh-tag) fetch_and_deploy_gh_tag probe owner/app v2.0.0 "$target" || rc=$? ;;
      cb-source) fetch_and_deploy_codeberg_release probe owner/app tarball v2.0.0 "$target" || rc=$? ;;
      cb-archive) fetch_and_deploy_codeberg_release probe owner/app prebuild v2.0.0 "$target" app.tar.gz || rc=$? ;;
      cb-tag) fetch_and_deploy_codeberg_release probe owner/app tag v2.0.0 "$target" || rc=$? ;;
      gl-source) fetch_and_deploy_gl_release probe owner/app tarball v2.0.0 "$target" || rc=$? ;;
      gl-archive) fetch_and_deploy_gl_release probe owner/app prebuild v2.0.0 "$target" app.tar.gz || rc=$? ;;
      url-tar) fetch_and_deploy_from_url https://fixture.invalid/app.tar.gz "$target" || rc=$? ;;
      url-zip) fetch_and_deploy_from_url https://fixture.invalid/app.zip "$target" || rc=$? ;;
    esac
    unset -f cp
    expected=0
    [[ "$fault" == none ]] || expected=252
    [[ "$provider" != gl-* || "$fault" == none ]] || expected=1
    check "$rc" "$expected" "$provider/$fault actual provider status"
    check "$(cat "$target/config.yaml" 2> /dev/null || true)" 'user config' "$provider/$fault actual config consumer"
    check "$(cat "$target/data/row" 2> /dev/null || true)" 'user data' "$provider/$fault actual data consumer"
    check "$(cat "$target/database/custom name.sqlite" 2> /dev/null || true)" 'user custom database' "$provider/$fault lossless array path reaches shared owner"
    if [[ "$fault" != none ]]; then check "$(cat "$HOME/.probe")" old "$provider failed copy leaves version marker"; fi
  done
done
unset CLEAN_INSTALL_KEEP_PATHS
for collision in file link; do
  fresh "parent-collision-$collision"
  rm -rf "$source_dir/state"
  if [[ "$collision" == file ]]; then
    printf default > "$source_dir/state"
  else ln -s "$c/outside" "$source_dir/state"; fi
  mkdir -p "$c/outside/settings"
  printf 'outside witness\n' > "$c/outside/settings/user.conf"
  input=$(snapshot "$source_dir")
  CLEAN_INSTALL_KEEP='state/settings/user.conf' _deploy_replace_contents "$source_dir" "$target" 1
  check "$(cat "$target/state/settings/user.conf")" 'user nested config' "$collision source ancestor cannot replace protected spine"
  check "$(cat "$c/outside/settings/user.conf")" 'outside witness' "$collision source ancestor never follows external link"
  check "$(snapshot "$source_dir")" "$input" "$collision projection leaves input unchanged"
done
fresh dotfile
printf 'private env\n' > "$target/.env"
printf 'default env\n' > "$source_dir/.env"
before=$(signature "$target/.env")
CLEAN_INSTALL_KEEP=.env _deploy_replace_contents "$source_dir" "$target" 1
check "$(cat "$target/.env")" 'private env' 'explicit hidden keep defeats source default collision'
check "$(signature "$target/.env")" "$before" 'explicit hidden keep inode/metadata unchanged'
fresh prepare-failure
cp() { return 44; }
rc=0
CLEAN_INSTALL_KEEP=data _deploy_replace_contents "$source_dir" "$target" 1 || rc=$?
unset -f cp
check "$rc" 252 'projection-copy failure status'
check "$(cat "$target/code")" 'old code' 'projection failure precedes live replacement'
fresh restore-failure
cp() {
  if [[ "${!#}" == "$target/"* ]]; then
    printf partial > "$target/code"
    return 41
  fi
  command cp "$@"
}
mv() {
  local from=''
  for from in "$@"; do [[ "$from" == -* ]] || break; done
  [[ "$from" != *'.deploy-aside.'* ]] || return 46
  command mv "$@"
}
rc=0
CLEAN_INSTALL_KEEP=data _deploy_replace_contents "$source_dir" "$target" 1 > "$c/output" 2>&1 || rc=$?
unset -f cp mv
check "$rc" 252 'failed restore remains a failed deployment'
check "$(cat "$target/data/row")" 'user data' 'failed restore never touches protected live data'
old_backup=$(find "$target" -path '*/.deploy-aside.*/code' -type f)
check "$(cat "$old_backup" 2> /dev/null || true)" 'old code' 'failed restore retains recoverable old entry instead of deleting backup'
check "$(grep -c 'rollback incomplete' "$c/output" || true)" 1 'failed restore exposes retained recovery location'
for clean in 0 1; do
  fresh "planned-partial-$clean"
  printf 'new planned payload\n' > "$source_dir/planned-partial"
  cp() {
    if [[ "${!#}" == "$target/"* ]]; then
      printf partial > "$target/planned-partial"
      return 41
    fi
    command cp "$@"
  }
  rc=0
  CLEAN_INSTALL_KEEP=data _deploy_replace_contents "$source_dir" "$target" "$clean" || rc=$?
  unset -f cp
  check "$rc" 252 "planned partial/$clean failed-copy status"
  check "$(test -e "$target/planned-partial" && printf present || printf absent)" absent "planned partial/$clean rollback removes partial payload entry"
  check "$(cat "$target/code")" 'old code' "planned partial/$clean old code restored"
  check "$(cat "$target/data/row")" 'user data' "planned partial/$clean live persistent data retained"
done
fresh bad-archive
python3 -c 'import sys; sys.stdout.buffer.write(b"invalid tar header"*256)' | gzip > "$c/bad.tar.gz"
ASSET="$c/bad.tar.gz"
before=$(snapshot "$target")
rc=0
CLEAN_INSTALL=1 CLEAN_INSTALL_KEEP=data fetch_and_deploy_from_url https://fixture.invalid/bad.tar.gz "$target" > "$c/output" 2>&1 || rc=$?
check "$rc" 251 'URL extraction failure retains native public status'
check "$(snapshot "$target")" "$before" 'URL extraction failure precedes any target effect'
unset CLEAN_INSTALL CLEAN_INSTALL_KEEP
printf '%s failure(s); actual filesystem/helper/providers; network/fault boundaries modeled\n' "$failures"
[[ "$failures" == 0 ]]
