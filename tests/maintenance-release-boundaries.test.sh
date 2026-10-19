#!/usr/bin/env bash
# Actual release checker, source/asset deployment and spinner. HTTP/Git producers
# are modeled; the consumers, filesystem, logs and processes are native.
set -euo pipefail
systemd-detect-virt --vm --quiet || exit 1
: "${TMPDIR:?disk-backed TMPDIR required}"
case "$(realpath -e "$TMPDIR")" in /tmp | /tmp/*) exit 1 ;; esac
case "$(findmnt -rn -T "$TMPDIR" -o FSTYPE)" in '' | tmpfs | ramfs) exit 1 ;; esac
ROOT=$(realpath "$(dirname "${BASH_SOURCE[0]}")/..")
if [[ "${1:-}" == --spinner ]]; then
  source "$ROOT/misc/core.func"
  source "$ROOT/misc/tools.func"
  load_functions
  if [[ "$SPINNER_CASE" == marker-write ]]; then
    mkdir "$CASE_ROOT/opt" "$HOME/.forbidden"
    printf '4.0.0\n' > "$CASE_ROOT/opt/forbidden_version.txt"
    mount --bind "$CASE_ROOT/opt" /opt
  fi
  ensure_dependencies() { :; }
  getent() {
    printf '%s\n' "${SPINNER_PID:-}" > "$CASE_ROOT/spinner-pid"
    [[ "$SPINNER_CASE" != dns ]]
  }
  prompt_for_github_token() { return 1; }
  git() { return 1; }
  sleep() { case "$1" in 2 | 4) return 0 ;; *) command sleep "$@" ;; esac }
  curl() {
    local out=''
    while (($#)); do
      if [[ "$1" == -o ]]; then
        out="$2"
        shift
      fi
      shift
    done
    printf '%s\n' "${SPINNER_PID:-}" > "$CASE_ROOT/spinner-pid"
    if [[ "$SPINNER_CASE" == marker-write ]]; then
      printf '{"tag_name":"v4.7.0"}' > "$out"
      printf 200
    else
      printf '{"message":"forbidden"}' > "$out"
      printf 403
    fi
  }
  rc=0
  check_for_gh_release forbidden owner/app || rc=$?
  printf '%s\n' "$rc" > "$CASE_ROOT/status"
  alive=no
  pid=$(< "$CASE_ROOT/spinner-pid")
  if [[ -n "$pid" ]] && kill -0 "$pid" 2> /dev/null; then alive=yes; fi
  printf '%s\n' "$alive" > "$CASE_ROOT/alive"
  # RED cleanup is confined to the positively recorded fixture spinner.
  stop_spinner
  exit 0
fi
work=$(mktemp -d "$TMPDIR/maintenance-boundaries.XXXXXX")
trap 'rm -rf -- "$work"' EXIT
mkdir -p "$work/home" "$work/tmp" "$work/archive/source"
source "$ROOT/misc/tools.func"
export HOME="$work/home" TMPDIR="$work/tmp" STD=''
msg_info() { :; }
msg_ok() { :; }
msg_warn() { :; }
msg_error() { printf '%s\n' "$*" >> "$work/errors"; }
ensure_dependencies() { :; }
getent() { return 0; }
sleep() { :; }
prompt_for_github_token() { return 1; }
git() { printf 'abc refs/tags/v4.7.0\n'; }
curl() {
  local out='' url='' body='[]' code=200 fault=0
  while (($#)); do
    case "$1" in -o)
      out="$2"
      shift
      ;;
    https:*) url="$1" ;; esac
    shift
  done
  printf '%s\n' "$url" >> "$work/urls"
  case "$url" in
    */latest | */tags/*)
      code=404
      body='{"message":"Not Found"}'
      ;;
    *releases\?*)
      case "$scenario" in
        prerelease) body='[{"tag_name":"v9.0.0","prerelease":true}]' ;;
        unavailable) code=403 ;;
        truncated)
          body='[{"tag_name":"v9.0.0"}]'
          fault=18
          ;;
        malformed) body='not JSON' ;;
        prefix-pages)
          if [[ "$url" == *page=2* ]]; then
            body='[{"tag_name":"v4.10.0"}]'
          else body=$(jq -cn '[range(0;100) | {tag_name:("v4.9."+tostring)}]'); fi
          ;;
        older*)
          if [[ "$url" == *per_page=15* ]]; then
            body=$(jq -c '.[0:15]' "$work/history")
          elif [[ "$url" == *page=2* ]]; then
            body='[]'
          else body=$(< "$work/history"); fi
          [[ "$scenario" != older-truncated ]] || fault=18
          [[ "$scenario" != older-malformed ]] || body='[{"tag_name":"v1","assets":"bad"}]'
          ;;
      esac
      ;;
  esac
  printf '%s' "$body" > "$out"
  printf '%s' "$code"
  return "$fault"
}
curl_download() {
  printf '%s\n' "$2" > "$work/archive/source/origin"
  tar -czf "$1" -C "$work/archive" source
}
failures=0
check() {
  if [[ "$1" == "$2" ]]; then printf 'PASS %s\n' "$3"; else
    printf 'FAIL %s: expected <%s>, got <%s>\n' "$3" "$2" "$1" >&2
    failures=$((failures + 1))
  fi
}
for scenario in empty prerelease unavailable truncated malformed; do
  expected=0
  case "$scenario" in truncated) expected=18 ;; malformed) expected=22 ;; esac
  rc=0
  check_for_gh_release "check-$scenario" owner/app || rc=$?
  check "$rc" "$expected" "$scenario unfiltered checker status"
  if [[ "$expected" == 0 ]]; then check "$CHECK_UPDATE_RELEASE" v4.7.0 "$scenario checker retains semver tag fallback"; fi
  rc=0
  fetch_and_deploy_gh_release "deploy-$scenario" owner/app tarball latest "$work/$scenario" || rc=$?
  check "$rc" "$expected" "$scenario unfiltered source deployer status"
  if [[ "$expected" == 0 ]]; then
    check "$(cat "$work/$scenario/origin" 2> /dev/null || true)" https://github.com/owner/app/archive/refs/tags/v4.7.0.tar.gz "$scenario tag reaches source consumer"
  fi
  rc=0
  check_for_gh_release "prefix-$scenario" owner/app '' '' v4. || rc=$?
  prefix_expected=250
  case "$scenario" in unavailable | malformed) prefix_expected=22 ;; truncated) prefix_expected=18 ;; esac
  check "$rc" "$prefix_expected" "$scenario prefix never fabricates a published release from Git tags"
done
scenario='prefix-pages'
: > "$work/urls"
check_for_gh_release paged-prefix owner/app '' '' v4.
check "$CHECK_UPDATE_RELEASE" v4.10.0 'prefix checker enumerates beyond the first hundred releases'
fetch_and_deploy_gh_release paged-prefix owner/app tarball latest "$work/paged-prefix" '' v4.
check "$(cat "$work/paged-prefix/origin")" https://github.com/owner/app/archive/refs/tags/v4.10.0.tar.gz 'page-two prefix selection reaches actual source consumer'
check "$(wc -l < "$work/urls")" 4 'both prefix consumers complete pagination, independently of bounded asset scan'
scenario=empty
rc=0
check_for_gh_release missing-pin owner/app v8.0.0 || rc=$?
check "$rc" 22 'missing requested checker pin never substitutes available tag'
rc=0
fetch_and_deploy_gh_release missing-pin owner/app tarball v8.0.0 "$work/missing-pin" || rc=$?
check "$rc" 22 'missing requested deployment pin never substitutes available tag'
check "$(test -e "$HOME/.missing-pin" && printf present || printf absent)" absent 'missing pin never commits a marker'
for scenario in older-first older-ancient older-truncated older-malformed; do
  match=3
  [[ "$scenario" != older-ancient ]] || match=20
  jq -cn --argjson match "$match" '[range(0;100) | . as $i | {tag_name:("v1.0."+($i|tostring)),draft:false,prerelease:false,assets:(if $i==$match or ($match==3 and $i==4) then [{name:"app.bin",browser_download_url:("https://fixture.invalid/"+($i|tostring)+"/app.bin")}] else [] end)}]' > "$work/history"
  : > "$work/urls"
  rc=0
  selected=$(_gh_scan_older_releases owner/app singlefile app.bin v2.0.0 < /dev/null) || rc=$?
  expected=0
  case "$scenario" in older-ancient) expected=250 ;; older-truncated) expected=18 ;; older-malformed) expected=22 ;; esac
  check "$rc" "$expected" "$scenario older asset selection status"
  if [[ "$expected" == 0 ]]; then
    check "$(jq -r .tag_name <<< "$selected")" v1.0.3 'first older match retains API order'
  else check "$selected" '' "$scenario exposes no partial or ancient selected metadata"; fi
  count=$(wc -l < "$work/urls")
  if [[ "$scenario" == older-first || "$scenario" == older-ancient ]]; then
    check "$count" 1 "$scenario uses exactly one bounded list request"
    check "$(< "$work/urls")" 'https://api.github.com/repos/owner/app/releases?per_page=15' "$scenario retains original fifteen-release horizon"
  fi
done
for spinner_case in forbidden dns marker-write; do
  c="$work/spinner-$spinner_case"
  mkdir -p "$c/home" "$c/tmp"
  env -i PATH="$PATH" TMPDIR="$c/tmp" HOME="$c/home" CASE_ROOT="$c" SPINNER_CASE="$spinner_case" \
    BUILD_LOG="$c/active.log" GITHUB_TOKEN=do-not-print-fixture-secret VERBOSE=no TERM=xterm \
    python3 - "$0" > "$c/output" 2>&1 << 'PY'
import errno,os,pty,select,subprocess,sys,time
m,s=pty.openpty();p=subprocess.Popen(['unshare','-m','--propagation','private','--','bash',sys.argv[1],'--spinner'],stdin=subprocess.DEVNULL,stdout=s,stderr=s);os.close(s)
deadline=time.monotonic()+20
while p.poll() is None and time.monotonic()<deadline:
 if select.select([m],[],[],0.05)[0]:
  try:os.write(1,os.read(m,65536))
  except OSError as e:
   if e.errno!=errno.EIO:raise
if p.poll() is None:p.kill();p.wait();raise SystemExit(124)
os.set_blocking(m,False)
while True:
 try:os.write(1,os.read(m,65536))
 except OSError:break
os.close(m);raise SystemExit(p.returncode)
PY
  expected=22
  [[ "$spinner_case" != dns ]] || expected=6
  [[ "$spinner_case" != marker-write ]] || expected=252
  check "$(cat "$c/status")" "$expected" "$spinner_case actual failed checker retains error status"
  check "$(test -s "$c/spinner-pid" && printf recorded || printf absent)" recorded "$spinner_case actual checker started owned spinner"
  check "$(cat "$c/alive")" no "$spinner_case actual failed checker stops its owned spinner before returning"
  # A diagnostic must identify both HTTP status and a safe actionable token hint.
  if [[ "$spinner_case" == forbidden ]]; then
    if grep -q 'HTTP=403\|HTTP 403' "$c/active.log" && grep -q GITHUB_TOKEN "$c/active.log"; then hint=yes; else hint=no; fi
    check "$hint" yes 'actual checker log contains actionable 403/token hint'
  fi
  check "$(grep -c do-not-print-fixture-secret "$c/output" "$c/active.log" | cut -d: -f2 | paste -sd, -)" 0,0 "$spinner_case diagnostics never print token value"
done
printf '%s failure(s); actual release consumers and spinner, modeled HTTP/Git\n' "$failures"
[[ "$failures" == 0 ]]
