#!/usr/bin/env bash
# Native inode/byte/writer/mount outcomes; only explicit failure injection modeled.
set -euo pipefail
systemd-detect-virt --vm --quiet || exit 1
: "${TMPDIR:?disk-backed TMPDIR required}"
case "$(findmnt -rn -T "$TMPDIR" -o FSTYPE)" in '' | tmpfs | ramfs) exit 1 ;; esac
if [[ "${MERGE_NS:-}" != 1 ]]; then
  MERGE_NS=1 unshare -m --propagation private -- bash "$0"
  exit $?
fi
ROOT=$(realpath "$(dirname "${BASH_SOURCE[0]}")/..")
source "$ROOT/misc/tools.func"
work=$(mktemp -d "$TMPDIR/merge-inplace.XXXXXX")
mounts=()
cleanup() {
  local path
  for path in "${mounts[@]}"; do umount "$path"; done
  command rm -rf -- "$work"
}
trap cleanup EXIT
msg_error() { printf '%s\n' "$*" >&2; }
failures=0
check() {
  if [[ "$1" == "$2" ]]; then printf 'PASS %s\n' "$3"; else
    printf 'FAIL %s expected <%s>, got <%s>\n' "$3" "$2" "$1" >&2
    failures=$((failures + 1))
  fi
}
for clean in 0 1; do
  c="$work/in-place-$clean"
  source_dir="$c/source"
  target="$c/target"
  branch=app
  [[ "$clean" != 1 ]] || branch=.app
  mkdir -p "$source_dir/$branch" "$target/$branch/old-only" "$c/outside"
  python3 - "$target/$branch/old-only" << 'PY'
import pathlib,sys
p=pathlib.Path(sys.argv[1])
for i in range(3000): (p/str(i)).write_text('USER:'+str(i))
with (p/'large').open('wb') as f:f.write(b'U'*4*1024**2)
PY
  ln "$target/$branch/old-only/large" "$c/outside/shared"
  printf OLD > "$target/$branch/code"
  printf NEW > "$source_dir/$branch/code"
  chmod 0700 "$target/$branch"
  chmod 0751 "$source_dir/$branch"
  before=$(stat -c '%d:%i:%a:%u:%g' "$target/$branch")
  data_before=$(stat -c '%d:%i:%a:%u:%g:%Y' "$target/$branch/old-only/large")
  : > "$c/copies"
  : > "$c/old-live-reads"
  cp() {
    local arg
    # Only inputs are reads; publication's final destination is live by design.
    for arg in "${@:1:$#-1}"; do [[ "$arg" != "$target/$branch"* ]] || printf '%s\n' "$arg" >> "$c/old-live-reads"; done
    if [[ "$*" != *'-al'* ]]; then
      python3 - "$@" << 'PY' >> "$c/copies"
import os,pathlib,sys
sources=[pathlib.Path(a) for a in sys.argv[1:-1] if not a.startswith('-')];size=0
for p in sources:
 for f in ([p] if not p.is_dir() or p.is_symlink() else p.rglob('*')):
  if f.is_file() and not f.is_symlink():size+=f.stat().st_size
print(size)
PY
    fi
    command cp "$@"
  }
  mv() {
    if [[ "$*" == *'.deploy-aside.'* && ! -e "$c/writer" ]]; then
      bash -c 'printf CONCURRENT > "$1/$2/concurrent"' bash "$target" "$branch"
      : > "$c/writer"
    fi
    command mv "$@"
  }
  rc=0
  _deploy_replace_contents "$source_dir" "$target" "$clean" || rc=$?
  unset -f cp mv
  check "$rc" 0 "merge/$clean success"
  check "$(stat -c '%d:%i:%a:%u:%g' "$target/$branch")" "$before" "merge/$clean existing directory inode/mode retained"
  check "$(stat -c '%d:%i:%a:%u:%g:%Y' "$target/$branch/old-only/large")" "$data_before" "merge/$clean populated old-only file inode/metadata retained"
  check "$(test "$target/$branch/old-only/large" -ef "$c/outside/shared" && printf linked || printf broken)" linked "merge/$clean old-only hardlink identity retained"
  check "$(cat "$target/$branch/concurrent" 2> /dev/null || true)" CONCURRENT "merge/$clean independent success writer retained"
  check "$(wc -l < "$c/old-live-reads")" 0 "merge/$clean never projects/copies old live tree"
  bytes=$(
    python3 - "$c/copies" << 'PY'
import pathlib,sys
print(sum(map(int,pathlib.Path(sys.argv[1]).read_text().splitlines())))
PY
  )
  printf 'ACTUAL_COPY_BYTES clean=%s input=3 copied=%s\n' "$clean" "$bytes"
  check "$bytes" 3 "merge/$clean only incoming bytes copied"
  check "$(cat "$target/$branch/code")" NEW "merge/$clean incoming consumer bytes"
done
c="$work/restore-type"
mkdir -p "$c/source/X" "$c/target"
printf OLD > "$c/target/X"
printf NEW > "$c/source/X/new"
: > "$c/unsafe-restore"
cp() {
  command cp "$@" || return $?
  if [[ "${!#}" == "$c/target/" ]]; then
    bash -c 'printf CONCURRENT > "$1/X/user"' bash "$c/target"
    return 41
  fi
}
mv() {
  local arg
  for arg in "$@"; do
    if [[ "$arg" == *'.deploy-aside.'*'/X' && -d "$c/target/X" ]]; then printf attempt >> "$c/unsafe-restore"; fi
  done
  command mv "$@"
}
rc=0
_deploy_replace_contents "$c/source" "$c/target" 1 > "$c/output" 2>&1 || rc=$?
unset -f cp mv
check "$rc" 252 'restore conflict stays failed'
check "$(cat "$c/target/X/user")" CONCURRENT 'restore conflict preserves concurrent directory data'
check "$(test -e "$c/target/X/X" && printf nested || printf absent)" absent 'restore never nests old X at X/X'
backups=("$c/target/".deploy-aside.*/X)
check "$(cat "${backups[0]}" 2> /dev/null || true)" OLD 'restore conflict retains exact old file in aside'
check "$(grep -c 'rollback incomplete' "$c/output" || true)" 1 'restore conflict reports retained recovery location'
check "$(stat -c %s "$c/unsafe-restore")" 0 'restore conflict prevents unsafe mv invocation before batching'
for owner in aside stage; do
  c="$work/late-$owner"
  mkdir -p "$c/source" "$c/target/old-only" "$c/external"
  printf NEW > "$c/source/code"
  printf USER > "$c/external/witness"
  cp() {
    command cp "$@" || return $?
    if [[ "${!#}" == "$c/target/" && ! -e "$c/mounted" ]]; then
      local dirs path arg
      if [[ "$owner" == aside ]]; then
        dirs=("$c/target/".deploy-aside.*)
        path="${dirs[0]}/old-only/late-mount"
      else
        for arg in "$@"; do [[ "$arg" != *'/deploy-source.'*'/payload/'* ]] || path="${arg%%/payload/*}/late-mount"; done
      fi
      mkdir -p "$path"
      mount --bind "$c/external" "$path"
      mounts+=("$path")
      : > "$c/mounted"
    fi
  }
  rc=0
  _deploy_replace_contents "$c/source" "$c/target" 1 > "$c/output" 2>&1 || rc=$?
  unset -f cp
  check "$rc" 252 "$owner late mount reports cleanup failure"
  check "$(cat "$c/external/witness" 2> /dev/null || true)" USER "$owner late mount external bytes survive recursive cleanup"
  check "$(grep -c 'mounted.*retained\|retained.*mount' "$c/output" || true)" 1 "$owner late mount retained location reported"
  for path in "${mounts[@]}"; do umount "$path"; done
  if [[ "$owner" == stage ]]; then command rm -rf -- "${path%/late-mount}"; fi
  mounts=()
done
printf '%s failure(s); native live identity, hardlinks, bytes, success writers, restore conflicts and late mounts\n' "$failures"
[[ "$failures" == 0 ]]
