#!/usr/bin/env bash
# Run inside the dedicated Alpine CT. Utilities are the real BusyBox applets.
set -euo pipefail
: "${TMPDIR:?disk-backed test workspace required}"
[[ "$TMPDIR" != /tmp && "$TMPDIR" != /tmp/* && -d "$TMPDIR" ]]
ROOT=${1:?source root required}
BUSYBOX=${BUSYBOX:-/bin/busybox}
"$BUSYBOX" | grep -q BusyBox
work=$(mktemp -d "$TMPDIR/addon-busybox.XXXXXXXX")
trap 'rm -rf -- "$work"' EXIT
mkdir "$work/bin"
for applet in realpath readlink find stat sed grep date cp mktemp mv ln install sort tail head base64 sha256sum chown chmod cut tr dirname basename xargs touch od du df awk tar timeout id cat mkdir rm rmdir cmp; do
  ln -s "$BUSYBOX" "$work/bin/$applet"
done
export PATH="$work/bin:$PATH"
source "$ROOT/misc/addon_lxc.func"
failures=0
check() {
  if [[ "$2" == "$3" ]]; then printf 'PASS %s\n' "$1"; else
    printf 'FAIL %s: expected <%s>, got <%s>\n' "$1" "$3" "$2" >&2
    failures=$((failures + 1))
  fi
}
status() {
  local rc=0
  "$@" || rc=$?
  printf '%s' "$rc"
}
msg_warn() { printf '%s\n' "$*" >&2; }
msg_ok() { :; }
mkdir -p "$work/tree/physical/inside" "$work/tree/files"
ln -s physical/inside "$work/tree/alias"
ln -s ../missing/deep "$work/tree/physical/dangling"
ln -s cycle-b "$work/tree/cycle-a"
ln -s cycle-a "$work/tree/cycle-b"
printf 'config\n' > "$work/tree/files/config"
ln -s files/config "$work/tree/config-link"

# Existing shared path is the failing-first consumer, not only a missing new API.
resolved=''
rc=0
_addon_backup_root resolved "$work/tree/alias/../new/deep/.." || rc=$?
check 'backup root canonicalization status' "$rc" 0
check 'backup root follows link before dot-dot and permits missing parents' "$resolved" "$work/tree/physical/new"
printf 'private\n' | addon_write_private_file "$work/tree/files/private"
check 'private native publication mode' "$(stat -c %a -- "$work/tree/files/private")" 600
check 'private native publication bytes' "$(cat "$work/tree/files/private")" private

if declare -F addon_resolve_path > /dev/null; then
  check 'missing suffix' "$(addon_resolve_path "$work/tree/absent/a/../b")" "$work/tree/absent/b"
  check 'symlink before dot-dot' "$(addon_resolve_path "$work/tree/alias/../file")" "$work/tree/physical/file"
  check 'dangling link with multiple missing components' "$(addon_resolve_path "$work/tree/physical/dangling/../file")" "$work/tree/missing/file"
  check 'root and repeated separators' "$(addon_resolve_path ////./../)" /
  ln -s . "$work/tree/self"
  check 'repeated noncyclic link' "$(addon_resolve_path "$work/tree/self/self/files/config")" "$work/tree/files/config"
  rc=0
  addon_resolve_path "$work/tree/cycle-a/file" > "$work/cycle-output" || rc=$?
  check 'cycle refuses' "$rc" 1
  check 'cycle emits no candidate' "$(cat "$work/cycle-output")" ''
  check 'relative physical working directory' "$(cd "$work/tree/alias" && addon_resolve_path ../file)" "$work/tree/physical/file"
  unusual=$'line\nend'
  ln -s "$unusual" "$work/tree/newline-link"
  check 'link target newline remains data' "$(addon_resolve_path "$work/tree/newline-link/file")" "$work/tree/$unusual/file"
else
  check 'shared missing-component resolver API exists' absent present
fi

# Relocate only test custody; serialization and backup payloads are explicitly modeled.
_addon_backup_path() { printf -v "$1" '%s' "$work/backup-record"; }
create_backup() { printf '%s\0' "$@" > "$work/backup-inputs"; }
# shellcheck disable=SC2034 # consumed by the sourced addon owner
APP_SLUG=busybox-test
rc=0
addon_backup_create "$work/backups" "$work/tree/config-link" || rc=$?
check 'backup input preparation status' "$rc" 0
inputs=()
[[ ! -f "$work/backup-inputs" ]] || mapfile -d '' -t inputs < "$work/backup-inputs"
check 'backup retains lexical link' "${inputs[0]:-}" "$work/tree/config-link"
check 'backup includes actual resolved consumer' "${inputs[1]:-}" "$work/tree/files/config"

# Actual applet option/consumer contracts used by this PR's changed code.
check 'dirname option boundary' "$(dirname -- "$work/tree/files/config")" "$work/tree/files"
check 'native link resolution' "$(readlink -f -- "$work/tree/config-link")" "$work/tree/files/config"
check 'stat metadata and follow' "$(stat -Lc '%u:%a:%h' -- "$work/tree/config-link")" "0:$(stat -c '%a:%h' -- "$work/tree/files/config")"
check 'find depth and quit' "$(find "$work/tree/files" -mindepth 1 -maxdepth 1 -name config -print -quit)" "$work/tree/files/config"
check 'NUL sort and base64' "$(printf 'b\0a\0' | sort -z | base64 -w0)" YQBiAA==
check 'tail byte' "$(printf 'value\0' | tail -c1 -- | base64 -w0)" AA==
check 'grep ERE whitespace' "$(printf 'host\tuser\n' | grep -Ec '^host\s+user')" 1
check 'ISO date option' "$(date -Is | grep -Ec '^[0-9]{4}-[0-9]{2}-[0-9]{2}T')" 1
stage=$(mktemp -- "$work/tree/files/stage.XXXXXXXX")
install -m 0755 -- "$work/tree/files/config" "$stage"
mv -T -- "$stage" "$work/tree/files/executable"
ln -T -- "$work/tree/files/executable" "$work/tree/files/linked"
check 'native install/move/link identity' "$(stat -c '%i:%h:%a' -- "$work/tree/files/linked")" "$(stat -c '%i:%h:%a' -- "$work/tree/files/executable")"
check 'hard-link publication refuses occupied directory' "$(status ln -T -- "$work/tree/files/executable" "$work/tree/files" 2> /dev/null)" 1
printf 'old\n' > "$work/occupied"
printf 'new\n' > "$work/candidate"
mv -nT -- "$work/candidate" "$work/occupied"
check 'no-clobber move preserves occupied consumer' "$(cat "$work/occupied")" old
check 'no-clobber move retains candidate' "$(cat "$work/candidate")" new
cp -p -- "$work/tree/files/config" "$work/copied"
check 'preserving copy mode' "$(stat -c %a -- "$work/copied")" "$(stat -c %a -- "$work/tree/files/config")"
sed -i -e 's/^config$/changed/' "$work/copied"
check 'in-place sed' "$(cat "$work/copied")" changed
printf 'BUSYBOX_ADDON_RESULT failures=%s\n' "$failures"
[[ "$failures" == 0 ]]
