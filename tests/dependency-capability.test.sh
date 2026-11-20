#!/usr/bin/env bash
# Guest-only native dependency admission: Alpine installs, full tools are reused.
set -euo pipefail
: "${TMPDIR:?disk-backed workspace required}"
[[ "$TMPDIR" != /tmp && "$TMPDIR" != /tmp/* && -d "$TMPDIR" ]]
ROOT=${1:?source root required}
work=$(mktemp -d "$TMPDIR/dependency-capability.XXXXXXXX")
trap 'rm -rf -- "$work"' EXIT
_INSTALL_DEFER_BOOTSTRAP=1 source "$ROOT/misc/install.func"
source "$ROOT/misc/tools.func"
msg_error() { printf '%s\n' "$*" >&2; }
if ! declare -f ensure_dependencies | grep -q -- --capability; then
  printf 'FAIL dependency owner lacks explicit capability admission\nDEPENDENCY_CAPABILITY_RESULT failures=1\n' >&2
  exit 1
fi
# shellcheck disable=SC2034 # consumed by the sourced package owner
STD=''
PKG_MANAGER=apt
[[ ! -f /etc/alpine-release ]] || PKG_MANAGER=apk
# Observe the native package-manager boundary under the real framework owner.
# Fault controls select an exit status there; no framework API is replaced.
mkdir "$work/bin"
for tool in apk apt apt-get; do
  real=$(command -v "$tool") || continue
  cat > "$work/bin/$tool" << EOF
#!/bin/sh
printf '%s\\n' "\$*" >> '$work/packages'
[ ! -f '$work/package-status' ] || exit "\$(cat '$work/package-status')"
exec '$real' "\$@"
EOF
  chmod 0755 "$work/bin/$tool"
done
native_path=$PATH
PATH="$work/bin:$PATH"
hash -r
failures=0
check() {
  if [[ "$2" == "$3" ]]; then printf 'PASS %s\n' "$1"; else
    printf 'FAIL %s: expected <%s>, got <%s>\n' "$1" "$3" "$2" >&2
    failures=$((failures + 1))
  fi
}
uid=$(id -u) gid=$(id -g)
package=util-linux
expected=0
if [[ "$PKG_MANAGER" == apk ]]; then
  package=setpriv
  if ! setpriv --reuid="$uid" --regid="$gid" --clear-groups sh -c : > /dev/null 2>&1; then
    expected=1
    check 'initial reduced applet' "$(readlink -f "$(command -v setpriv)")" /bin/busybox
  fi
fi
: > "$work/packages"
ensure_dependencies --capability "$package" -- setpriv --reuid="$uid" --regid="$gid" --clear-groups sh -c :
ensure_dependencies --capability "$package" -- setpriv --reuid="$uid" --regid="$gid" --groups="$gid" sh -c :
check 'only a deficient tool installs its native package' "$(wc -l < "$work/packages")" "$expected"
if [[ "$expected" == 1 ]]; then
  check 'exact Alpine package selected' "$(cat "$work/packages")" 'add --no-cache setpriv'
  check 'full Alpine package installed' "$(PATH=$native_path apk info -e setpriv)" setpriv
fi
ensure_dependencies --capability "$package" -- setpriv --reuid="$uid" --regid="$gid" --clear-groups sh -c :
check 'existing full tool installs nothing on repeat' "$(wc -l < "$work/packages")" "$expected"
ensure_dependencies bash
check 'legacy satisfied dependency path unchanged' "$(wc -l < "$work/packages")" "$expected"
printf 'full\n' > "$work/full"
probe() { [[ -e "$work/full" ]]; }
ensure_dependencies --capability not-a-real-package -- probe
check 'capability wins over absent package/name metadata' "$(wc -l < "$work/packages")" "$expected"
rm "$work/full"
printf '42\n' > "$work/package-status"
rc=0
ensure_dependencies --capability test-package -- probe || rc=$?
check 'native package failure status retained' "$rc" 42
printf '0\n' > "$work/package-status"
rc=0
ensure_dependencies --capability test-package -- probe || rc=$?
check 'unsatisfied post-install capability refuses' "$rc" 69
printf 'DEPENDENCY_CAPABILITY_RESULT failures=%s manager=%s\n' "$failures" "$PKG_MANAGER"
[[ "$failures" == 0 ]]
