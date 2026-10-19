#!/usr/bin/env bash
# Actual generated bundle prelude across install/update/uninstall invocations.
set -euo pipefail
systemd-detect-virt --vm --quiet || exit 1
: "${TMPDIR:?provide a disk-backed temporary directory}"
case "$(realpath -e "$TMPDIR")" in /tmp | /tmp/*) exit 1 ;; esac
case "$(findmnt -rn -T "$TMPDIR" -o FSTYPE)" in '' | tmpfs | ramfs) exit 1 ;; esac
ROOT=$(realpath "$(dirname "${BASH_SOURCE[0]}")/..")
work=$(mktemp -d "$TMPDIR/maintenance-receiver.XXXXXX")
trap 'rm -rf -- "$work"' EXIT
failures=0
check() {
  if [[ "$1" == "$2" ]]; then printf 'PASS %s\n' "$3"; else
    printf 'FAIL %s: expected <%s>, got <%s>\n' "$3" "$2" "$1" >&2
    failures=$((failures + 1))
  fi
}
source "$ROOT/misc/bundle.func"
sed -n '/^build_container() {/,/^  NET_STRING=/p' "$ROOT/misc/build.func" | sed '$d' > "$work/build-prefix.sh"
printf '}\n' >> "$work/build-prefix.sh"
source "$work/build-prefix.sh"
execute_optional_hook() { printf 'PREBUILD_REACHED\n' >> "$work/prebuild"; }
export TMPDIR="$work/creator"
mkdir -p "$TMPDIR/framework-context"
export APP=Context NSAPP=context REPO_BASE=offline SESSION_ID=context CTID=2110
msg_debug() { :; }
msg_error() { printf '%s\n' "$*" >&2; }
_framework_cache_ensure() { :; }
pct() {
  printf '%s\n' "$*" >> "$work/transport"
  case "$1" in push) cp -- "$3" "$4" ;; exec)
    shift 3
    command "$@"
    ;;
  esac
}
cat > "$TMPDIR/framework-context/core.func" << 'LIB'
load_functions() { :; }
color() { :; }
LIB
printf 'catch_errors() { :; }\n' > "$TMPDIR/framework-context/error_handler.func"
cat > "$TMPDIR/framework-context/install.func" << 'LIB'
# This source-time boundary precedes any hook and models the first log redirect.
printf '%s\n' "${TMPDIR-unset}" >> "$OBSERVED"
if [[ "$CHECK_WRITABLE" == yes ]]; then printf 'first log\n' > "$TMPDIR/first.log"; fi
setup_lxc() { :; }
LIB
printf 'setup_uv() { :; }\n' > "$TMPDIR/framework-context/tools.func"
printf 'clone_and_deploy_gh_commit() { :; }\n' > "$TMPDIR/framework-context/github.func"
install_script() { :; }
update_script() { :; }
uninstall_script() { return 37; }
for role in install update uninstall; do
  receiver="$work/$role/receiving space"
  mkdir -p "$work/$role"
  export var_lxc_tmpdir="$receiver"
  build_bundle "$role" "${role}_script" "$work/$role/bundle" 0700 "${role}_script"
  for invocation in 1 2; do
    rm -rf -- "$receiver"
    rc=0
    OBSERVED="$work/$role/observed-$invocation" CHECK_WRITABLE=yes bash "$work/$role/bundle" > "$work/$role/output-$invocation" 2>&1 || rc=$?
    expected=0
    [[ "$role" != uninstall ]] || expected=37
    check "$rc" "$expected" "$role invocation-$invocation recreates receiving directory before first library"
    check "$(test -f "$receiver/first.log" && printf present || printf absent)" present "$role invocation-$invocation first consumer sees writable directory"
    check "$(stat -c %a "$receiver")" 1777 "$role invocation-$invocation newly created directory is shared and sticky"
    # The install bundle self-destructs normally; generate the next invocation.
    if [[ "$role" == install && "$invocation" == 1 ]]; then
      build_bundle "$role" "${role}_script" "$work/$role/bundle" 0700 "${role}_script"
    fi
  done
  # Independent existing-directory case must still run after a target RED above.
  mkdir -p -- "$receiver"
  chmod 0750 "$receiver"
  before=$(stat -c '%a:%u:%g' "$receiver")
  [[ "$role" != install ]] || build_bundle "$role" "${role}_script" "$work/$role/bundle" 0700 "${role}_script"
  rc=0
  OBSERVED="$work/$role/existing" CHECK_WRITABLE=yes bash "$work/$role/bundle" > "$work/$role/existing-output" 2>&1 || rc=$?
  check "$(stat -c '%a:%u:%g' "$receiver")" "$before" "$role retains existing directory metadata"
done

unset var_lxc_tmpdir
build_bundle update update_script "$work/default-bundle" 0700 update_script
OBSERVED="$work/default-observed" CHECK_WRITABLE=no bash "$work/default-bundle"
check "$(cat "$work/default-observed")" unset 'default never inherits creator TMPDIR'

mkdir -p "$work/valid"
ln -s "$work/valid" "$work/alias"
bad_values=(relative / // "$work/valid/" "$work//valid" "$work/./valid" "$work/valid/../valid" "$work/alias" $'/invalid\npath')
for i in "${!bad_values[@]}"; do
  var_lxc_tmpdir="${bad_values[$i]}"
  before=$(wc -l < "$work/transport")
  rc=0
  build_bundle update update_script "$work/invalid-$i" 0700 update_script > "$work/invalid-$i-output" 2>&1 || rc=$?
  if [[ "$var_lxc_tmpdir" != "$work/alias" ]]; then
    check "$rc" 65 "invalid-$i rejected by sender"
    check "$(wc -l < "$work/transport")" "$before" "invalid-$i rejected before publication"
    rc=0
    build_container > "$work/prebuild-$i-output" 2>&1 || rc=$?
    check "$rc" 65 "invalid-$i initial creation rejects lexical input"
    check "$(test -e "$work/prebuild" && printf reached || printf absent)" absent "invalid-$i rejected before pre-build hook"
  else
    # Symlink resolution belongs to the receiver, not the creator's filesystem.
    check "$rc" 0 'sender does not impose creator filesystem topology on receiver'
  fi
  # Also exercise the runtime prelude independently (an existing/corrupted bundle).
  python3 - "$work/default-bundle" "$work/runtime-$i" "$var_lxc_tmpdir" << 'PY'
import pathlib,shlex,sys
src=pathlib.Path(sys.argv[1]).read_text();marker='# ═══ runtime context (baked at bundle build time) ═══'
assert src.count(marker)==1
pathlib.Path(sys.argv[2]).write_text(src.replace(marker,marker+'\ndeclare -- var_lxc_tmpdir='+shlex.quote(sys.argv[3]),1))
PY
  rc=0
  (
    cd "$work"
    OBSERVED="$work/invalid-observed-$i" CHECK_WRITABLE=no bash "$work/runtime-$i"
  ) > "$work/runtime-$i-output" 2>&1 || rc=$?
  check "$rc" 65 "invalid-$i rejected at invocation"
  check "$(test -e "$work/invalid-observed-$i" && printf reached || printf absent)" absent "invalid-$i rejected before first library effect"
done
var_lxc_tmpdir="$work/blocker"
: > "$var_lxc_tmpdir"
build_bundle update update_script "$work/blocked-bundle" 0700 update_script
rc=0
OBSERVED="$work/blocked-observed" CHECK_WRITABLE=no bash "$work/blocked-bundle" > "$work/blocked-output" 2>&1 || rc=$?
check "$rc" 1 'receiving mkdir failure preserves native status'
check "$(test -e "$work/blocked-observed" && printf reached || printf absent)" absent 'mkdir failure precedes framework effects'
printf '%s failure(s); actual generated bundles, source-time consumer; tiny framework/pct models\n' "$failures"
[[ "$failures" == 0 ]]
