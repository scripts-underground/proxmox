#!/usr/bin/env bash
set -euo pipefail
systemd-detect-virt --vm --quiet || exit 1
: "${TMPDIR:?disk-backed TMPDIR required}"
case "$(realpath -e "$TMPDIR")" in /tmp | /tmp/*) exit 1 ;; esac
case "$(findmnt -rn -T "$TMPDIR" -o FSTYPE)" in '' | tmpfs | ramfs) exit 1 ;; esac
ROOT=$(realpath "$(dirname "${BASH_SOURCE[0]}")/..")
work=$(mktemp -d "$TMPDIR/maintenance-prefix.XXXXXX")
trap 'rm -rf -- "$work"' EXIT
mkdir -p "$work/home" "$work/archive/source"
sed "s|/tmp/gh_rel.json|$work/legacy.json|g" "$ROOT/misc/tools.func" > "$work/subject.func"
source "$work/subject.func"
export HOME="$work/home" STD=''
msg_info() { :; }
msg_ok() { :; }
msg_warn() { :; }
msg_error() { printf '%s\n' "$*" >&2; }
ensure_dependencies() { :; }
getent() { return 0; }
sleep() { :; }
git() {
  [[ "${api_down:-no}" == yes ]] || return 1
  printf 'abc refs/tags/v4.7.0\n'
}
curl() {
  local out='' url='' format='' code
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
  printf '%s\n' "$url" >> "$work/urls"
  local body='{"tag_name":"v5.0.0","draft":false,"prerelease":false}'
  case "$url" in
    *'/tags/'*) body='{"tag_name":"v2.0.0","draft":false,"prerelease":false}' ;;
    *'releases?per_page='*) body='[{"tag_name":"v5.0.0","draft":false,"prerelease":false},{"tag_name":"v4.9.0","draft":false,"prerelease":false},{"tag_name":"v4.10.0","draft":false,"prerelease":false},{"tag_name":"v4.99.0","draft":false,"prerelease":true},{"tag_name":"v4.98.0","draft":true,"prerelease":false}]' ;;
  esac
  if [[ "${prefix_line:-no}" == yes ]]; then
    body='[{"tag_name":"v1.20.0"},{"tag_name":"v1.2.3"}]'
  fi
  if [[ "${word_case:-no}" == yes ]]; then body='{"tag_name":"version/4.2","draft":false,"prerelease":false}'; fi
  printf '%s' "$body" > "$out"
  code=200
  [[ "${api_down:-no}" != yes ]] || code=403
  [[ -z "$format" ]] || printf '%s' "$code"
}
curl_download() {
  printf '%s\n' "$2" > "$work/archive/source/origin"
  tar -czf "$1" -C "$work/archive" source
}
failed=0
check() { if [[ "$1" == "$2" ]]; then printf 'PASS %s\n' "$3"; else
  printf 'FAIL %s: expected <%s>, got <%s>\n' "$3" "$2" "$1" >&2
  failed=$((failed + 1))
fi; }
check_for_gh_release prefix-probe owner/app '' '' v4.
check "$CHECK_UPDATE_RELEASE" v4.10.0 'checker selects highest stable matching raw tag'
fetch_and_deploy_gh_release prefix-probe owner/app tarball latest "$work/target" '' v4.
check "$(cat "$HOME/.prefix-probe")" 4.10.0 'deployer agrees on stable prefix selection'
check "$(cat "$work/target/origin")" 'https://github.com/owner/app/archive/refs/tags/v4.10.0.tar.gz' 'selected raw tag reaches actual source consumer'
rc=0
check_for_gh_release prefix-probe owner/app '' '' v4. || rc=$?
check "$rc" 1 'same selected line reports no update'
check "${CHECK_UPDATE_RELEASE:-}" '' 'same-version checker clears stale result'
UPDATE_FORCE=1 check_for_gh_release prefix-probe owner/app '' '' v4.
check "$CHECK_UPDATE_RELEASE" v4.10.0 'force check retains selected raw tag'
check_for_gh_release pin-probe owner/app v2.0.0 reason v4.
check "$CHECK_UPDATE_RELEASE" v2.0.0 'explicit pin retains priority over optional latest prefix'
fetch_and_deploy_gh_release pin-probe owner/app tarball v2.0.0 "$work/pin" '' v4.
check "$(cat "$HOME/.pin-probe")" 2.0.0 'deployer retains explicit pin with optional prefix'
var_appversion=v2.0.0 fetch_and_deploy_gh_release override-probe owner/app tarball latest "$work/override" '' v4.
check "$(cat "$HOME/.override-probe")" 2.0.0 'environment app pin retains priority'
check_for_gh_release default-probe owner/app
check "$CHECK_UPDATE_RELEASE" v5.0.0 'unfiltered default retains designated latest behavior'
rc=0
check_for_gh_release missing-probe owner/app '' '' missing/ || rc=$?
check "$rc" 250 'absent prefix never falls through to unrelated latest'
word_case=yes
check "$(get_latest_github_release owner/app false)" version/4.2 'latest getter can retain raw nonnumeric-v tag'
check_for_gh_release raw-probe owner/app
check "$CHECK_UPDATE_RELEASE" version/4.2 'checker retains raw word/slash tag'
fetch_and_deploy_gh_release raw-probe owner/app tarball latest "$work/raw"
check "$(cat "$HOME/.raw-probe")" version/4.2 'deployer never strips v from a word tag'
rc=0
fetch_and_deploy_gh_release wrong-word-pin owner/app tarball ersion/4.2 "$work/wrong-word-pin" || rc=$?
check "$rc" 250 'numeric-v compatibility never substitutes a different word tag'
check "$(test -e "$HOME/.wrong-word-pin" && printf present || printf absent)" absent 'mismatched raw word pin cannot commit a marker'
word_case=no
api_down=yes
rc=0
check_for_gh_release unavailable-prefix owner/app '' '' v4. || rc=$?
check "$rc" 22 'unavailable stable release list never infers published state from git tags'
check "${CHECK_UPDATE_RELEASE:-}" '' 'unavailable prefix clears selected result rather than inventing release metadata'
api_down=no
prefix_line=yes
check_for_gh_release raw-prefix owner/app '' '' v1.2
check "$CHECK_UPDATE_RELEASE" v1.20.0 'prefix is raw startswith, not numeric component matching'
check_for_gh_release separated-prefix owner/app '' '' v1.2.
check "$CHECK_UPDATE_RELEASE" v1.2.3 'explicit separator limits the intended release line'
rc=0
check_for_gh_release no-v-prefix owner/app '' '' 1.2. || rc=$?
check "$rc" 250 'prefix must include the actual raw leading v'
prefix_line=no
for test_arch in amd64 arm64; do
  dpkg() { printf '%s\n' "$test_arch"; }
  uname() {
    [[ "$test_arch" != amd64 ]] || {
      printf 'x86_64\n'
      return
    }
    printf 'aarch64\n'
  }
  check "$(get_system_arch)" "$test_arch" "$test_arch default dpkg naming stays compatible"
  check "$(get_system_arch uname)" "$test_arch" "$test_arch uname normalization stays compatible"
  expected=x64
  [[ "$test_arch" != arm64 ]] || expected=aarch64
  check "$(get_system_arch both x64 aarch64)" "$expected" "$test_arch explicit release alias"
done
dpkg() { return 1; }
uname() { printf 'x86_64\n'; }
check "$(get_system_arch both)" amd64 'both retains uname fallback'
printf '%s failure(s); actual checker/deployer/architecture outcomes; responses modeled\n' "$failed"
[[ "$failed" == 0 ]]
