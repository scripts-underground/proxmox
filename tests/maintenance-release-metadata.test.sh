#!/usr/bin/env bash
# Actual GitHub deployment/older selection and IGC consumer. Only legacy /tmp
# literal is disk-mapped for RED; network/package commands are models.
set -euo pipefail
systemd-detect-virt --vm --quiet || exit 1
: "${TMPDIR:?disk-backed TMPDIR required}"
case "$(realpath -e "$TMPDIR")" in /tmp | /tmp/*) exit 1 ;; esac
case "$(findmnt -rn -T "$TMPDIR" -o FSTYPE)" in '' | tmpfs | ramfs) exit 1 ;; esac
ROOT=$(realpath "$(dirname "${BASH_SOURCE[0]}")/..")
if [[ "${1:-}" == --jellyfin ]]; then
  source "$ROOT/misc/tools.func"
  source "$CASE_ROOT/update.sh"
  header_info() { :; }
  check_container_storage() { :; }
  check_container_resources() { :; }
  msg_info() { :; }
  msg_ok() { :; }
  msg_error() { printf '%s\n' "$*" >&2; }
  fetch_and_deploy_gh_release() {
    if [[ "$1" == intel-libgdgmm12 ]]; then
      cp "$CASE_ROOT/metadata.json" "$8"
      printf '%s\n' "$8" > "$CASE_ROOT/metadata-path"
    else
      printf '%s|%s\n' "$1" "$4" >> "$CASE_ROOT/igc-consumers"
      [[ "$1" != intel-igc-opencl-2 ]] || return 73
    fi
  }
  # Stop at the modeled provider boundary, before app package/service mutations.
  update_script
  exit 97
fi
work=$(mktemp -d "$TMPDIR/maintenance-metadata.XXXXXX")
trap 'rm -rf -- "$work"' EXIT
mkdir -p "$work/home" "$work/tmp" "$work/archive"
sed "s|/tmp/gh_rel.json|$work/legacy.json|g" "$ROOT/misc/tools.func" > "$work/subject.func"
source "$work/subject.func"
export HOME="$work/home" TMPDIR="$work/tmp" STD=''
msg_info() { :; }
msg_ok() { :; }
msg_warn() { :; }
msg_error() { printf '%s\n' "$*" >> "$work/errors"; }
auth_case=no
ensure_dependencies() { :; }
getent() { return 0; }
sleep() { :; }
prompt_for_github_token() {
  [[ "$auth_case" == yes ]] || return 1
  GITHUB_TOKEN=fixture-token
  return 0
}
git() { return 1; }
curl() {
  local out='' url='' format=''
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
  local body="$api_body" response_code="$api_code" response_fault="$api_fault"
  [[ "$auth_case" != yes || "${GITHUB_TOKEN:-}" == fixture-token ]] || response_code=401
  if [[ "$url" == *'releases?per_page='* ]]; then
    body="$older_body"
    response_fault="${older_fault:-$api_fault}"
  fi
  if [[ -n "$out" ]]; then
    printf '%s\n' "$out" >> "$work/api-paths"
    printf '%s' "$body" > "$out"
    [[ -z "$format" ]] || printf '%s' "$response_code"
  else printf '%s' "$body"; fi
  return "$response_fault"
}
curl_download() {
  [[ "$auth_case" != yes || "${GITHUB_TOKEN:-}" == fixture-token ]] || return 7
  printf '%s\n' "$2" >> "$work/downloads"
  mkdir -p "$work/archive/source"
  printf '%s\n' "$2" > "$work/archive/source/served-origin"
  tar -czf "$1" -C "$work/archive" source
}
failures=0
check() { if [[ "$1" == "$2" ]]; then printf 'PASS %s\n' "$3"; else
  printf 'FAIL %s: expected <%s>, got <%s>\n' "$3" "$2" "$1" >&2
  failures=$((failures + 1))
fi; }
api_code=200 api_fault=0
api_body='{"tag_name":"v3.0.0","draft":false,"prerelease":false,"body":"https://github.com/intel/intel-graphics-compiler/releases/tag/igc-3","assets":[]}'
older_body='[{"tag_name":"v2.0.0","draft":false,"prerelease":false,"body":"https://github.com/intel/intel-graphics-compiler/releases/tag/igc-2","assets":[{"name":"app.tar.gz","browser_download_url":"https://fixture.invalid/v2.0.0/app.tar.gz"}]}]'
printf '{"tag_name":"stale","body":"old"}\n' > "$work/compute.json"
rc=0
# Exercise the real optional-command subshell: only explicit file output can cross it.
get_active_logfile() { printf '%s\n' "$work/optional.log"; }
_hwaccel_optional_command fetch_and_deploy_gh_release metadata-compute owner/compute prebuild latest "$work/compute" 'app.tar.gz' '' "$work/compute.json" || rc=$?
check "$rc" 0 'older compatible asset deploys through actual optional boundary'
check "$(cat "$work/compute/served-origin")" 'https://fixture.invalid/v2.0.0/app.tar.gz' 'served bytes come from actual older release selection'
check "$(jq -r .tag_name "$work/compute.json")" v2.0.0 'selected JSON follows older asset fallback'
igc=''
_resolve_igc_tag igc "$work/compute.json"
check "$igc" igc-2 'actual Intel consumer sees matching older compiler pin'
api_body='{"tag_name":"v9.0.0","draft":false,"prerelease":false,"body":"https://github.com/intel/intel-graphics-compiler/releases/tag/igc-9","assets":[{"name":"app.tar.gz","browser_download_url":"https://fixture.invalid/v9.0.0/app.tar.gz"}]}'
fetch_and_deploy_gh_release metadata-other owner/other prebuild latest "$work/other" 'app.tar.gz' '' "$work/other.json"
_resolve_igc_tag igc "$work/compute.json"
check "$igc" igc-2 'second repository cannot replace first call metadata'
check "$(jq -r .tag_name "$work/other.json" 2> /dev/null || true)" v9.0.0 'second call has independent selected JSON'
check "$(grep -c "$work/legacy.json" "$work/api-paths" || true)" 0 'actual API writes never use shared legacy sink'
for fault in truncated malformed wrong-schema; do
  api_fault=0 api_body='not JSON'
  [[ "$fault" != truncated ]] || {
    api_fault=18
    api_body='{"tag_name":"v9.0.0","assets":[]}'
  }
  [[ "$fault" != wrong-schema ]] || api_body='{"tag_name":"v9.0.0","draft":false,"prerelease":false,"assets":"not an asset array"}'
  getter_rc=0
  getter_value=$(get_latest_github_release owner/app) || getter_rc=$?
  getter_expected=22
  [[ "$fault" != truncated ]] || getter_expected=18
  check "$getter_rc" "$getter_expected" "$fault public latest getter checks the same completed producer"
  check "$getter_value" '' "$fault latest getter exposes no plausible failed result"
  printf '{"tag_name":"stale"}\n' > "$work/failure.json"
  rc=0
  fetch_and_deploy_gh_release "metadata-$fault" owner/app tarball latest "$work/$fault" '' '' "$work/failure.json" || rc=$?
  expected=22
  [[ "$fault" != truncated ]] || expected=18
  check "$rc" "$expected" "$fault completed producer/JSON error status"
  check "$(test -e "$HOME/.metadata-$fault" && printf present || printf absent)" absent "$fault never commits version marker"
  check "$(test -s "$work/failure.json" && printf stale || printf empty)" empty "$fault clears stale caller metadata"
done
api_fault=0 api_body='{"tag_name":"v3.0.0","draft":false,"prerelease":false,"assets":[]}'
rc=0
fetch_and_deploy_gh_release metadata-pinned owner/compute prebuild v3.0.0 "$work/pinned" app.tar.gz '' "$work/pinned.json" || rc=$?
check "$rc" 252 'explicit requested release never substitutes older asset'
check "$(test -e "$HOME/.metadata-pinned" && printf present || printf absent)" absent 'unavailable requested asset leaves marker untouched'
older_fault=18
rc=0
fetch_and_deploy_gh_release metadata-older-failure owner/compute prebuild latest "$work/older-failure" app.tar.gz '' "$work/older-failure.json" || rc=$?
check "$rc" 18 'failed older-list producer retains exact status'
check "$(test -s "$work/older-failure.json" && printf stale || printf empty)" empty 'failed older producer never exports plausible selected JSON'
unset older_fault
auth_case=yes
unset GITHUB_TOKEN
api_body='{"tag_name":"v3.0.0","draft":false,"prerelease":false,"assets":[]}'
rc=0
fetch_and_deploy_gh_release metadata-auth owner/private tarball latest "$work/auth" '' '' "$work/auth.json" || rc=$?
check "$rc" 0 'token recovery reaches actual archive-download consumer'
check "$(test -e "$work/auth/served-origin" && printf reached || printf absent)" reached 'authenticated selection and asset share recovered token context'
for pin_case in valid missing; do
  c="$work/jellyfin-$pin_case"
  mkdir -p "$c/home" "$c/tmp" "$c/installed"
  sed -n '/^function update_script() {/,/^}/p' "$ROOT/scripts/lxc/jellyfin.sh" |
    sed "s|/usr/lib/jellyfin|$c/installed|g" > "$c/update.sh"
  if [[ "$pin_case" == valid ]]; then
    printf '{"body":"https://github.com/intel/intel-graphics-compiler/releases/tag/igc-2"}\n' > "$c/metadata.json"
  else printf '{"body":"no compiler pin"}\n' > "$c/metadata.json"; fi
  rc=0
  env -i PATH="$PATH" TMPDIR="$c/tmp" HOME="$c/home" CASE_ROOT="$c" APP=Jellyfin \
    bash "$0" --jellyfin > "$c/output" 2>&1 || rc=$?
  if [[ "$pin_case" == valid ]]; then
    check "$rc" 73 'actual Jellyfin reader reaches modeled IGC consumer with selected metadata'
    check "$(cat "$c/igc-consumers")" $'intel-igc-core-2|igc-2\nintel-igc-opencl-2|igc-2' 'both Jellyfin compiler consumers receive selected pin'
  else
    check "$rc" 250 'missing Jellyfin compiler pin is a checked metadata failure'
    check "$(test -e "$c/igc-consumers" && printf reached || printf absent)" absent 'missing pin never becomes implicit latest at compiler consumers'
  fi
  check "$(test -e "$(cat "$c/metadata-path")" && printf present || printf absent)" absent "$pin_case Jellyfin reader removes its owned metadata file"
done
printf '%s failure(s); actual deploy/IGC/file outcomes, external responses modeled\n' "$failures"
[[ "$failures" == 0 ]]
