#!/usr/bin/env bash
# Native GNU/Alpine filesystem outcomes; command wrappers count operations and
# inject explicit copy/link failures, without replacing the filesystem behavior.
set -euo pipefail
systemd-detect-virt --vm --quiet || exit 1
: "${TMPDIR:?disk-backed TMPDIR required}"
case "$(findmnt -rn -T "$TMPDIR" -o FSTYPE)" in '' | tmpfs | ramfs) exit 1 ;; esac
if [[ "${REVIEW_NS:-}" != 1 ]]; then
  REVIEW_NS=1 unshare -m --propagation private -- bash "$0"
  exit $?
fi
ROOT=$(realpath "$(dirname "${BASH_SOURCE[0]}")/..")
# Immutable baseline override for RED; actual shared helper is sourced.
# shellcheck disable=SC1090
source "${REPLACEMENT_TOOLS:-$ROOT/misc/tools.func}"
work=$(mktemp -d "$TMPDIR/replacement-review.XXXXXX")
cleanup() {
  if mountpoint -q "$work/cross-device"; then umount "$work/cross-device"; fi
  command rm -rf -- "$work"
}
trap cleanup EXIT
mkdir "$work/cross-device"
truncate -s 24M "$work/cross-device.ext4"
mkfs.ext4 -q -F "$work/cross-device.ext4"
mount -o loop "$work/cross-device.ext4" "$work/cross-device"
msg_error() { printf '%s\n' "$*" >&2; }
failures=0
check() {
  if [[ "$1" == "$2" ]]; then printf 'PASS %s\n' "$3"; else
    printf 'FAIL %s: expected <%s>, got <%s>\n' "$3" "$2" "$1" >&2
    failures=$((failures + 1))
  fi
}
for tool in gnu alpine; do
  if [[ "$tool" == alpine ]]; then : "${ALPINE_BUSYBOX:?native Alpine BusyBox required}"; fi
  native() {
    local name="$1"
    shift
    if [[ "$tool" == alpine ]]; then "$ALPINE_BUSYBOX" "$name" "$@"; else command "$name" "$@"; fi
  }
  for pair in dir-file file-dir linkdir-dir linkfile-file linkdir-file; do
    c="$work/$tool-$pair"
    mkdir -p "$c/"{source,target,outside}
    printf USER > "$c/outside/user"
    case "$pair" in
      dir-file)
        mkdir "$c/target/item"
        printf USER > "$c/target/item/user"
        printf NEW > "$c/source/item"
        ;;
      file-dir)
        printf USER > "$c/target/item"
        mkdir "$c/source/item"
        printf NEW > "$c/source/item/new"
        ;;
      linkdir-dir)
        ln -s "$c/outside" "$c/target/item"
        mkdir "$c/source/item"
        printf NEW > "$c/source/item/new"
        ;;
      linkfile-file)
        ln -s "$c/outside/user" "$c/target/item"
        printf NEW > "$c/source/item"
        ;;
      linkdir-file)
        ln -s "$c/outside" "$c/target/item"
        printf NEW > "$c/source/item"
        ;;
    esac
    cp() { native cp "$@"; }
    rc=0
    _deploy_replace_contents "$c/source" "$c/target" 0 || rc=$?
    unset -f cp
    check "$rc" 252 "$tool/$pair merge conflict fails without false success"
    check "$(cat "$c/outside/user")" USER "$tool/$pair external bytes unchanged"
    case "$pair" in
      dir-file) check "$(cat "$c/target/item/user" 2> /dev/null || true)" USER "$tool/$pair user directory retained" ;;
      file-dir) check "$(cat "$c/target/item" 2> /dev/null || true)" USER "$tool/$pair user file retained" ;;
      *) check "$(readlink "$c/target/item" || true)" "$([[ "$pair" == linkfile-file ]] && printf '%s/user' "$c/outside" || printf '%s' "$c/outside")" "$tool/$pair user link retained" ;;
    esac
  done
  for clean in 0 1; do
    c="$work/$tool-writer-$clean"
    mkdir -p "$c/"{source,target}
    printf OLD > "$c/target/code"
    printf NEW > "$c/source/code"
    printf NEW > "$c/source/new-code"
    cp() {
      if [[ "${!#}" == "$c/target/" ]]; then
        printf PARTIAL > "$c/target/new-code"
        # A separate process owns this unplanned sibling, not the copy helper.
        bash -c 'printf CONCURRENT > "$1/unrelated-user-file"' bash "$c/target"
        return 41
      fi
      native cp "$@"
    }
    rc=0
    _deploy_replace_contents "$c/source" "$c/target" "$clean" || rc=$?
    unset -f cp
    check "$rc" 252 "$tool/writer/$clean failed copy status"
    check "$(cat "$c/target/code" 2> /dev/null || true)" OLD "$tool/writer/$clean old code restored"
    check "$(test -e "$c/target/new-code" && printf present || printf absent)" absent "$tool/writer/$clean planned partial removed"
    check "$(cat "$c/target/unrelated-user-file" 2> /dev/null || true)" CONCURRENT "$tool/writer/$clean unrelated writer retained"
    _deploy_replace_contents "$c/source" "$c/target" 0
    check "$(cat "$c/target/code")" NEW "$tool/writer/$clean retry publishes actual code"
  done
  c="$work/$tool-nested-writer"
  mkdir -p "$c/"{source/app,target/app}
  printf OLD > "$c/target/app/code"
  printf NEW > "$c/source/app/code"
  cp() {
    if [[ "${!#}" == "$c/target/"* ]]; then
      native cp "$@" || return $?
      bash -c 'printf CONCURRENT > "$1/app/unrelated-user-file"' bash "$c/target"
      return 41
    fi
    native cp "$@"
  }
  rc=0
  _deploy_replace_contents "$c/source" "$c/target" 0 || rc=$?
  unset -f cp
  check "$rc" 252 "$tool nested writer failed-copy status"
  check "$(cat "$c/target/app/code")" OLD "$tool nested writer restores old code around unrelated data"
  check "$(cat "$c/target/app/unrelated-user-file" 2> /dev/null || true)" CONCURRENT "$tool nested writer retained inside planned branch"
  c="$work/$tool-populated-rollback"
  mkdir -p "$c/"{source/app,target/app}
  python3 - "$c" << 'PY'
import pathlib,sys
p=pathlib.Path(sys.argv[1])
for i in range(2048):
 (p/'source/app'/str(i)).write_text('NEW:'+str(i))
 (p/'target/app'/str(i)).write_text('OLD:'+str(i))
PY
  : > "$c/restores"
  cp() {
    native cp "$@" || return $?
    if [[ "${!#}" == "$c/target/"* ]]; then
      bash -c 'printf CONCURRENT > "$1/app/unrelated-user-file"' bash "$c/target"
      return 41
    fi
  }
  mv() {
    printf 'mv\n' >> "$c/restores"
    native mv "$@"
  }
  rc=0
  _deploy_replace_contents "$c/source" "$c/target" 0 || rc=$?
  unset -f cp mv
  check "$rc" 252 "$tool populated rollback checked failure"
  valid=0
  python3 - "$c" << 'PY' || valid=$?
import pathlib,sys
p=pathlib.Path(sys.argv[1])
for i in range(2048): assert (p/'target/app'/str(i)).read_text()=='OLD:'+str(i)
assert (p/'target/app/unrelated-user-file').read_text()=='CONCURRENT'
PY
  check "$valid" 0 "$tool populated rollback restores every old byte and unrelated writer"
  count=$(wc -l < "$c/restores")
  printf 'ROLLBACK_SCALING tool=%s files=2048 move_operations=%s\n' "$tool" "$count"
  check "$((count < 32))" 1 "$tool populated rollback batched moves"
  command rm -rf -- "$c"
  for fallback in partial-link failed-copy cross-device; do
    c="$work/$tool-$fallback"
    mkdir -p "$c/"{source/app,target/app}
    if [[ "$fallback" == cross-device ]]; then
      mkdir -p "$work/cross-device/$tool/app"
      source_dir="$work/cross-device/$tool"
    else source_dir="$c/source"; fi
    printf NEW > "$source_dir/app/code"
    chmod 0600 "$source_dir/app/code"
    printf OLD > "$c/target/app/code"
    printf USER > "$c/target/app/old-only"
    source_before=$(stat -c '%a:%u:%g:%Y:%s' "$source_dir/app/code")
    : > "$c/fallbacks"
    cp() {
      local status=0
      native cp "$@" || status=$?
      if [[ "$*" == *'-al'* ]]; then
        if [[ "$fallback" == cross-device ]]; then
          [[ "$status" == 0 ]] || printf 'native-exdev\n' >> "$c/fallbacks"
        else return 44; fi
      elif [[ "$fallback" == failed-copy && "${!#}" == *'/deploy-source.'* ]]; then return 45; fi
      return "$status"
    }
    rc=0
    _deploy_replace_contents "$source_dir" "$c/target" 0 || rc=$?
    unset -f cp
    expected=0
    [[ "$fallback" != failed-copy ]] || expected=252
    check "$rc" "$expected" "$tool/$fallback checked projection/fallback status"
    check "$(stat -c '%a:%u:%g:%Y:%s' "$source_dir/app/code")" "$source_before" "$tool/$fallback source inode metadata unchanged"
    check "$(cat "$source_dir/app/code")" NEW "$tool/$fallback shared source bytes unchanged"
    check "$(cat "$c/target/app/old-only")" USER "$tool/$fallback old-only user bytes retained"
    expected=NEW
    [[ "$fallback" != failed-copy ]] || expected=OLD
    check "$(cat "$c/target/app/code")" "$expected" "$tool/$fallback actual code consumer"
    if [[ "$fallback" == cross-device ]]; then
      check "$(grep -c native-exdev "$c/fallbacks" || true)" 1 "$tool real cross-device hardlink refusal observed"
      check "$(test "$source_dir/app/code" -ef "$c/target/app/code" && printf linked || printf independent)" independent "$tool cross-device output is independent"
    fi
  done
  c="$work/$tool-array"
  mkdir -p "$c/"{source/database,target/database}
  printf USER > "$c/target/database/custom name.sqlite"
  printf WAL > "$c/target/database/custom name.sqlite-wal"
  printf DEFAULT > "$c/source/database/custom name.sqlite"
  printf NEW > "$c/source/code"
  (
    CLEAN_INSTALL_KEEP_PATHS=('database/custom name.sqlite' 'database/custom name.sqlite-wal')
    export CLEAN_INSTALL_KEEP=legacy
    cp() { native cp "$@"; }
    rc=0
    _deploy_replace_contents "$c/source" "$c/target" 1 || rc=$?
    check "$rc" 0 "$tool array keep status"
    check "$(cat "$c/target/database/custom name.sqlite" 2> /dev/null || true)" USER "$tool array whitespace database bytes"
    check "$(cat "$c/target/database/custom name.sqlite-wal" 2> /dev/null || true)" WAL "$tool array whitespace WAL bytes"
    exit "$failures"
  ) || failures=$((failures + 1))
  for bad in '' /absolute a/../b a//b; do
    (
      # Read by the shared helper, not by the fixture itself.
      # shellcheck disable=SC2034
      CLEAN_INSTALL_KEEP_PATHS=("$bad")
      rc=0
      _deploy_replace_contents "$c/source" "$c/invalid-target" 1 || rc=$?
      check "$rc" 65 "$tool invalid array path fails before effects"
      check "$(test -e "$c/invalid-target" && printf present || printf absent)" absent "$tool invalid array target absent"
      exit "$failures"
    ) || failures=$((failures + 1))
  done
  for size in 128 "${REPLACEMENT_LARGE_SIZE:-1024}"; do
    if ((size >= 10000)); then
      : "${REPLACEMENT_TASK_WORKSPACE:?large fixture requires explicit task admission root}" \
        "${REPLACEMENT_TASK_BUDGET_BYTES:?large fixture requires an explicit workspace budget}"
      [[ "$REPLACEMENT_TASK_BUDGET_BYTES" =~ ^[1-9][0-9]*$ ]]
      python3 - "$REPLACEMENT_TASK_WORKSPACE" "$size" << 'PY'
import json,os,subprocess,sys
w=sys.argv[1];used=int(subprocess.check_output(['du','-sx','-B1',w],text=True).split()[0]);s=os.statvfs(w);free=s.f_bavail*s.f_frsize;budget=int(os.environ['REPLACEMENT_TASK_BUDGET_BYTES']);remaining=budget-used;n=int(sys.argv[2])
# Large old leaves are empty; populated128/2048 rollback probes cover old bytes.
# Two allocated data sets plus bounded manifests/listings and8MiB allowance.
path_bound=len(os.fsencode(os.environ['TMPDIR']))+len('/deploy-source.XXXXXX/overlay/app/50000')+1
need=n*(2*s.f_frsize+3*path_bound+160)+8*1024**2
print('LARGE_ADMISSION '+json.dumps({'workspace_budget':budget,'used':used,'headroom':remaining,'fixture_upper_bound':need,'root_available':free}))
assert remaining>need and free>=8*1024**3+remaining
PY
    fi
    c="$work/$tool-scale-$size"
    mkdir -p "$c/"{source/app,target/app}
    python3 - "$c" "$size" << 'PY'
import pathlib,sys
p=pathlib.Path(sys.argv[1]);n=int(sys.argv[2])
for i in range(n):
 (p/'source/app'/str(i)).write_text('NEW:'+str(i))
 (p/'target/app'/str(i)).write_text('OLD:'+str(i) if n<10000 else '')
(p/'target/app/old-only').write_text('USER')
PY
    chmod 0751 "$c/source/app"
    chmod 0600 "$c/source/app/0"
    before=$(stat -c '%a:%u:%g:%Y:%s' "$c/source/app/0")
    dir_before=$(stat -c '%a:%u:%g:%Y' "$c/source/app")
    : > "$c/ops"
    cp() {
      printf 'cp\n' >> "$c/ops"
      if [[ "${!#}" == *'/deploy-source.'*'/payload/' && "$*" == *"$c/source/"* ]]; then
        native cp "$@" || return $?
        if [[ "$*" == *'-al'* ]]; then
          test "$c/source/app/0" -ef "${!#}/app/0" || return 47
          ! test "$c/source/app" -ef "${!#}/app" || return 48
          printf 'shared-source\n' >> "$c/ops"
        fi
        return 0
      fi
      native cp "$@"
    }
    mv() {
      printf 'mv\n' >> "$c/ops"
      native mv "$@"
    }
    mkdir() {
      printf 'mkdir\n' >> "$c/ops"
      native mkdir "$@"
    }
    find() {
      printf 'find\n' >> "$c/ops"
      native find "$@"
    }
    rm() {
      printf 'rm\n' >> "$c/ops"
      native rm "$@"
    }
    rc=0
    _deploy_replace_contents "$c/source" "$c/target" 0 || rc=$?
    unset -f cp mv mkdir find rm
    check "$rc" 0 "$tool/$size populated merge status"
    check "$(stat -c '%a:%u:%g:%Y:%s' "$c/source/app/0")" "$before" "$tool/$size shared source metadata unchanged"
    check "$(stat -c '%a:%u:%g:%Y' "$c/source/app")" "$dir_before" "$tool/$size independent source directory metadata unchanged"
    check "$(grep -c shared-source "$c/ops" || true)" 1 "$tool/$size source projection shares file inodes"
    valid=0
    python3 - "$c" "$size" << 'PY' || valid=$?
import pathlib,sys
p=pathlib.Path(sys.argv[1]);n=int(sys.argv[2])
assert (p/'target/app/old-only').read_text()=='USER'
for i in range(n): assert (p/'target/app'/str(i)).read_text()=='NEW:'+str(i)
PY
    check "$valid" 0 "$tool/$size every populated payload file and old sibling observed"
    count=$(wc -l < "$c/ops")
    printf 'SCALING tool=%s files=%s external_operations=%s\n' "$tool" "$size" "$count"
    check "$((count < 100 + size / 16))" 1 "$tool/$size coarse bounded operations"
    command rm -rf -- "$c"
  done
done
printf '%s failure(s); native files/metadata/Alpine operations, modeled named failure boundaries\n' "$failures"
[[ "$failures" == 0 ]]
