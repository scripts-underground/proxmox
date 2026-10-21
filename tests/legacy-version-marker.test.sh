#!/usr/bin/env bash
# Release checks adopt only their own legacy /opt/<app>_version.txt marker.
set -euo pipefail

# tools.func hardcodes /opt, so run in a private mount namespace (root in the guest).
if [[ -z "${MARKER_NS:-}" ]]; then
  exec env MARKER_NS=1 unshare -m bash "$0"
fi
ROOT=$(realpath "$(dirname "${BASH_SOURCE[0]}")/..")
source "$ROOT/misc/tools.func"

work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT
mkdir "$work/opt" "$work/home"
mount --bind "$work/opt" /opt
export HOME="$work/home"

msg_info() { :; }
msg_ok() { :; }
msg_error() { :; }
getent() { return 0; }
ensure_dependencies() { return 0; }
_codeberg_release_json() { printf '{"tag_name":"v2.0.0"}'; }
curl() {
  local body
  body=$(printf '{"tag_name":"%s","draft":false,"prerelease":false}' "${GH_TAG:-v2.0.0}")
  while [[ "$1" != -o ]]; do shift; done
  [[ "$*" == *gitlab* ]] && body='[{"tag_name":"v2.0.0"}]'
  printf '%s' "$body" > "$2"
  printf 200
}
reset() {
  rm -rf /opt/* "$HOME"
  mkdir "$HOME"
}

reset
printf 1.0.0 > /opt/other_version.txt
rc=0
check_for_gh_release MyApp o/r || rc=$?
[[ "$rc" == 0 ]]
[[ "$(< /opt/other_version.txt)" == 1.0.0 ]]
[[ ! -e "$HOME/.myapp" ]]
printf 'PASS GitHub check ignores another app marker\n'

reset
printf 'v2.0.0' > /opt/myapp_version.txt
CHECK_UPDATE_RELEASE=stale
rc=0
check_for_gh_release MyApp o/r || rc=$?
[[ "$rc" == 1 ]]
[[ -z "$CHECK_UPDATE_RELEASE" ]]
[[ -f /opt/myapp_version.txt ]]
[[ "$(< "$HOME/.myapp")" == 2.0.0 ]]
printf 'PASS GitHub check reads own marker, keeps it, clears stale result\n'

reset
printf 1.0.0 > /opt/myapp_version.txt
check_for_gh_release MyApp o/r latest
[[ "$CHECK_UPDATE_RELEASE" == v2.0.0 ]]
printf 'PASS GitHub latest pin is treated as no pin\n'

reset
printf 'version/4.2' > /opt/myapp_version.txt
first=0 second=0
GH_TAG=version/4.2 check_for_gh_release MyApp o/r || first=$?
adopted=$(< "$HOME/.myapp")
GH_TAG=version/4.2 check_for_gh_release MyApp o/r || second=$?
if [[ "$adopted" != version/4.2 || "$first" != 1 || "$second" != 1 ]]; then
  printf 'FAIL raw word marker adoption: marker=%s first=%s second=%s\n' "$adopted" "$first" "$second" >&2
  exit 1
fi
printf 'PASS GitHub own legacy word tag stays unchanged across repeated checks\n'

reset
printf 'v2.0.0' > /opt/myapp_version.txt
rc=0
check_for_codeberg_release MyApp o/r || rc=$?
[[ "$rc" == 1 ]]
[[ -f /opt/myapp_version.txt ]]
[[ "$(< "$HOME/.myapp")" == 2.0.0 ]]
printf 'PASS Codeberg check reads own marker and keeps it\n'

reset
printf 'v2.0.0' > /opt/myapp_version.txt
printf 1.0.0 > /opt/other_version.txt
rc=0
check_for_gl_release MyApp o/r || rc=$?
[[ "$rc" == 1 ]]
[[ -f /opt/myapp_version.txt && -f /opt/other_version.txt ]]
reset
printf 1.0.0 > /opt/myapp_version.txt
check_for_gl_release MyApp o/r latest
[[ "$CHECK_UPDATE_RELEASE" == v2.0.0 ]]
printf 'PASS GitLab check reads own marker only; latest pin is no pin\n'
