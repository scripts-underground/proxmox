#!/usr/bin/env bash
set -euo pipefail
systemd-detect-virt --vm --quiet || exit 1
: "${TMPDIR:?provide disk-backed TMPDIR}" "${ALPINE_BUSYBOX:?provide extracted Alpine BusyBox}"
case "$(realpath -e "$TMPDIR")" in /tmp | /tmp/*) exit 1 ;; esac
case "$(findmnt -rn -T "$TMPDIR" -o FSTYPE)" in '' | tmpfs | ramfs) exit 1 ;; esac
ROOT=$(realpath "$(dirname "${BASH_SOURCE[0]}")/..")
if [[ "${1:-}" == --child ]]; then
  mount --bind "$CHILD_FIXTURE" /mnt
  source "$ROOT/misc/bundle.func"
  _prepare_lxc_tmpdir /mnt/new-parent/receiver
  stat -c %a /mnt/new-parent/receiver > "$CHILD_FIXTURE/mode"
  stat -c '%a:%u:%g' /mnt/new-parent > "$CHILD_FIXTURE/parent-metadata"
  rc=0
  setpriv --reuid=65534 --regid=65534 --clear-groups env TMPDIR=/mnt/new-parent/receiver \
    sh -c 'f=$(mktemp "$TMPDIR/child.XXXXXX") || exit $?; printf "child bytes\n" > "$f"' > "$CHILD_FIXTURE/child-output" 2>&1 || rc=$?
  printf '%s\n' "$rc" > "$CHILD_FIXTURE/child-status"
  find /mnt/new-parent/receiver -name 'child.*' -type f | wc -l > "$CHILD_FIXTURE/child-count"
  rm -rf /mnt/new-parent/receiver
  rc=0
  setpriv --reuid=65534 --regid=65534 --clear-groups mkdir /mnt/new-parent/receiver > "$CHILD_FIXTURE/recreate-output" 2>&1 || rc=$?
  printf '%s\n' "$rc" > "$CHILD_FIXTURE/recreate-status"
  # Preserve the evidence even when the old writable parent allowed squatting.
  rm -rf /mnt/new-parent/receiver
  _prepare_lxc_tmpdir /mnt/new-parent/receiver
  stat -c %a /mnt/new-parent/receiver > "$CHILD_FIXTURE/recreated-mode"
  mkdir -m 0750 /mnt/existing-parent
  chown 0:65534 /mnt/existing-parent
  _prepare_lxc_tmpdir /mnt/existing-parent/receiver
  stat -c '%a:%u:%g' /mnt/existing-parent > "$CHILD_FIXTURE/existing-metadata"
  exit 0
fi
work=$(mktemp -d "$TMPDIR/maintenance-portable.XXXXXX")
trap 'rm -rf -- "$work"' EXIT
failures=0
check() {
  if [[ "$1" == "$2" ]]; then printf 'PASS %s\n' "$3"; else
    printf 'FAIL %s: expected <%s>, got <%s>\n' "$3" "$2" "$1" >&2
    failures=$((failures + 1))
  fi
}
source "$ROOT/misc/bundle.func"
realpath() { "$ALPINE_BUSYBOX" realpath "$@"; }
mkdir() { "$ALPINE_BUSYBOX" mkdir "$@"; }
rc=0
_prepare_lxc_tmpdir "$work/alpine/missing" > "$work/alpine-output" 2>&1 || rc=$?
check "$rc" 0 'actual Alpine BusyBox environment prepares missing normalized path'
check "$(test -d "$work/alpine/missing" && printf present || printf absent)" present 'portable consumer observes created directory'
command mkdir -p "$work/real"
ln -s "$work/real" "$work/alias"
rc=0
_prepare_lxc_tmpdir "$work/alias/not-created" > "$work/alias-output" 2>&1 || rc=$?
check "$rc" 65 'portable validation rejects symlink parent'
check "$(test -e "$work/real/not-created" && printf reached || printf absent)" absent 'symlink rejection precedes unintended creation'
ln -s "$work/absent-target" "$work/dangling"
rc=0
_prepare_lxc_tmpdir "$work/dangling/not-created" > "$work/dangling-output" 2>&1 || rc=$?
check "$rc" 65 'portable validation also rejects dangling symlink parent'
check "$(test -e "$work/absent-target" && printf reached || printf absent)" absent 'dangling symlink rejection precedes target creation'
command mkdir -p "$work/child-fixture"
chmod 0755 "$work/child-fixture"
CHILD_FIXTURE="$work/child-fixture" unshare -m --propagation private -- bash "$0" --child
check "$(cat "$work/child-fixture/mode")" 1777 'new receiving root has shared sticky semantics'
check "$(cat "$work/child-fixture/parent-metadata")" 755:0:0 'new intermediate parent is root-owned and not writable by app users'
check "$(cat "$work/child-fixture/child-status")" 0 'actual nonroot child can create temporary file'
check "$(cat "$work/child-fixture/child-count")" 1 'actual nonroot child bytes reach the receiving filesystem'
check "$(cat "$work/child-fixture/recreate-status")" 1 'nonroot child cannot squat a removed receiving leaf'
check "$(cat "$work/child-fixture/recreated-mode")" 1777 'owner recreates removed leaf with shared sticky semantics'
check "$(cat "$work/child-fixture/existing-metadata")" 750:0:65534 'existing intermediate metadata remains unchanged'
# The emitted canonical closure itself, run by real shells with no Bash available to the Alpine leg.
unset -f mkdir realpath
closure=$(_receiving_context_contents)
check "$([[ -n "$closure" ]] && printf emitted || printf empty)" emitted 'checked single-source emitter produces the canonical closure'
ashbin="$work/ashbin"
command mkdir -p "$ashbin"
for t in sh mkdir cat; do ln -s "$ALPINE_BUSYBOX" "$ashbin/$t"; done
shells=("ash:$ALPINE_BUSYBOX sh" "dash:/bin/sh" "bash:/bin/bash")
for entry in "${shells[@]}"; do
  tag=${entry%%:*}
  IFS=' ' read -r -a shell <<< "${entry#*:}"
  prepare() {
    local root=$1
    if [[ "$tag" == ash ]]; then
      env -i PATH="$ashbin" "${shell[@]}" -c "$closure"$'\n''_prepare_lxc_tmpdir "$1" && printf "%s" "${TMPDIR-unset}"' _ "$root"
    else
      env -i PATH="$PATH" "${shell[@]}" -c "$closure"$'\n''_prepare_lxc_tmpdir "$1" && printf "%s" "${TMPDIR-unset}"' _ "$root"
    fi
  }
  base="$work/emit-$tag"
  command mkdir -p "$base"
  root="$base/new parent;\$x/leaf name"
  rc=0
  out=$(prepare "$root" 2> "$base/err") || rc=$?
  check "$rc" 0 "$tag parses and runs the emitted preparer"
  check "$out" "$root" "$tag exports the prepared root only after success"
  check "$(stat -c %a "$root")" 1777 "$tag new leaf is shared and sticky"
  check "$(stat -c %a "$base/new parent;\$x")" 755 "$tag new intermediate parent is 0755"
  command mkdir -m 0750 "$base/existing"
  rc=0
  prepare "$base/existing/leaf" > /dev/null 2>&1 || rc=$?
  check "$rc:$(stat -c %a "$base/existing")" 0:750 "$tag existing parent metadata is unchanged"
  for bad in relative / // "$base/x/" "$base//x" "$base/./x" "$base/x/../x" $'/bad\npath' $'/bad\rpath' $'/bad\tpath'; do
    rc=0
    prepare "$bad" > /dev/null 2>&1 || rc=$?
    check "$rc" 65 "$tag rejects invalid receiving path $(printf %q "$bad")"
  done
  command mkdir -p "$base/real"
  ln -s "$base/real" "$base/alias"
  rc=0
  prepare "$base/alias/leaf" > /dev/null 2>&1 || rc=$?
  check "$rc:$(test -e "$base/real/leaf" && printf created || printf absent)" 65:absent "$tag rejects a symlink prefix before creation"
  ln -s "$base/absent-target" "$base/dangling"
  rc=0
  prepare "$base/dangling/leaf" > /dev/null 2>&1 || rc=$?
  check "$rc:$(test -e "$base/absent-target" && printf created || printf absent)" 65:absent "$tag rejects a dangling symlink prefix"
  : > "$base/blocker"
  rc=0
  prepare "$base/blocker/leaf" > /dev/null 2>&1 || rc=$?
  check "$([[ "$rc" != 0 && "$rc" != 65 ]] && printf native || printf '%s' "$rc")" native "$tag keeps the native creation failure status"
  rc=0
  out=$(env -i PATH="$PATH" "${shell[@]}" -c "$closure"$'\n''_prepare_lxc_tmpdir "$1" && printf "%s" "${TMPDIR-unset}"' _ "" 2> /dev/null) || rc=$?
  check "$rc:$out" "0:unset" "$tag empty override creates nothing and exports nothing"
done
printf '%s failure(s); actual Alpine tools and nonroot child; private disk bind fixture\n' "$failures"
[[ "$failures" == 0 ]]
