#!/usr/bin/env bash
# U1 consumer contracts. HTTP, dependency installation and source transfers are
# modeled; parsing, selection, publication and the persisted markers are real.
set -euo pipefail
systemd-detect-virt --vm --quiet || exit 65
: "${TMPDIR:?disk TMPDIR required}"
ROOT=$(realpath "$(dirname "${BASH_SOURCE[0]}")/../..")
work=$(mktemp -d "$TMPDIR/core-release.XXXXXX")
trap 'rm -rf -- "$work"' EXIT
mkdir -p "$work/home" "$work/archive/source"
# Old GitLab release code uses a shared legacy response file. Keep even RED
# comparisons inside this test's admitted disk scratch rather than that path.
sed "s|/tmp/gl_rel.json|$work/gl_rel.json|g" "$ROOT/misc/tools.func" > "$work/subject.func"
source "$work/subject.func"
export HOME="$work/home" STD=''
msg_info() { :; }
msg_ok() { :; }
msg_warn() { printf '%s\n' "$*" >> "$work/diagnostics"; }
msg_error() { printf '%s\n' "$*" >> "$work/diagnostics"; }
getent() { return 0; }
sleep() { :; }
prompt_for_github_token() { return 1; }
ensure_dependencies() {
  printf 'installing %s\n' "$*"
  printf '%s\n' "$*" >> "$work/dependencies"
}
git() { return 1; }
scenario=normal
curl() {
  local out='' url='' auth=no private=no body='{}' code=200
  while (($#)); do
    case "$1" in
      -o)
        out="$2"
        shift
        ;;
      -H)
        [[ "$2" != Authorization:* ]] || auth=yes
        [[ "$2" != PRIVATE-TOKEN:* ]] || private=yes
        shift
        ;;
      https:*) url="$1" ;;
    esac
    shift
  done
  printf '%s %s\n' "$auth" "$url" >> "$work/requests"
  if [[ "$url" == *gitlab.com/api/v4/projects/*/repository/archive.tar.gz\?* ]]; then
    printf '%s %s\n' "$private" "$url" >> "$work/gitlab-archives"
    if [[ -n "${GITLAB_TOKEN:-}" && "$private" != yes || "$scenario" == gl-denied ]]; then
      printf 403
      return 22
    fi
    printf '%s\n' "$url" > "$work/archive/source/origin"
    tar -czf "$out" -C "$work/archive" source
    printf 200
    [[ "$scenario" != gl-partial ]] || return 18
    return 0
  fi
  case "$scenario" in
    token-first) [[ "$auth" == yes ]] || code=401 ;;
    rejected) [[ "$auth" == no ]] || code=401 ;;
    saml) if [[ "$auth" == yes ]]; then
      code=403
      body='{"message":"Resource protected by organization SAML enforcement"}'
    fi ;;
    ip) if [[ "$auth" == yes ]]; then
      code=403
      body='{"message":"IP allow list blocks access"}'
    fi ;;
    forbidden)
      code=403
      body='{"message":"Resource not accessible by personal access token"}'
      ;;
    partial)
      body='[{"name":"v1.0.0"}]'
      printf '%s' "$body" > "$out"
      printf 200
      return 18
      ;;
    transient)
      if [[ "$(wc -l < "$work/requests")" == 1 ]]; then
        printf '{"tag_name":"v1.2.3"}' > "$out"
        printf 200
        return 18
      fi
      ;;
  esac
  if [[ "$code" == 200 ]]; then
    case "$url" in
      *git/matching-refs*) body='[{"ref":"refs/tags/v2.0.0-rc1"},{"ref":"refs/tags/v1.9.0"},{"ref":"refs/tags/v2.0.0-beta2"},{"ref":"refs/tags/v3.0.0-rc+build.1"}]' ;;
      */tags\?*)
        if [[ "$scenario" == malformed ]]; then
          body='[{"name":null}]'
        elif [[ "$url" == *page=2* ]]; then
          body='[{"name":"v1.9.0"}]'
        elif [[ "$url" == *per_page=100* ]]; then
          body=$(command jq -cn '[range(0;100)|{name:("v2.0.0-rc"+tostring)}]')
        else body='[{"name":"v2.0.0-rc1"}]'; fi
        ;;
      */releases/latest) body='{"tag_name":"v1.2.3","draft":false,"prerelease":false,"assets":[],"body":"designated"}' ;;
      *gitlab.com*/releases*) body='[{"tag_name":"v1.2.3"}]' ;;
      */releases\?*) body='[{"tag_name":"v1.2.99","assets":[]}]' ;;
      */releases/tags/v1.2.3)
        if [[ "$scenario" == reverse ]]; then
          code=404
          body='{"message":"Not Found"}'
        else body='{"tag_name":"v1.2.3","assets":[]}'; fi
        ;;
      */releases/tags/1.2.3) body='{"tag_name":"1.2.3","assets":[],"body":"unprefixed asset release"}' ;;
      */releases/tags/*) body=$(command jq -cn --arg tag "${url##*/}" '{tag_name:$tag,assets:[]}') ;;
      *codeberg.org*/releases*) body='[{"tag_name":"v1.2.3","draft":false,"prerelease":false,"assets":[]}]' ;;
    esac
  fi
  if [[ "$code" == 200 && "$url" == */repos/owner/dependency/* ]]; then
    if [[ "$url" == */latest ]]; then
      body='{"tag_name":"v8.0.0","assets":[]}'
    elif [[ "$url" == *releases\?* || "$url" == *codeberg.org*/releases ]]; then body='[{"tag_name":"v8.0.0","draft":false,"prerelease":false,"assets":[]}]'; fi
  fi
  printf '%s' "$body" > "$out"
  printf '%s' "$code"
}
curl_download() {
  printf '%s\n' "$2" > "$work/archive/source/origin"
  tar -czf "$1" -C "$work/archive" source
}
download_file() { curl_download "$2" "$1"; }
failures=0
check() {
  if [[ "$1" == "$2" ]]; then printf 'PASS %s\n' "$3"; else
    printf 'FAIL %s: expected <%s>, got <%s>\n' "$3" "$2" "$1" >&2
    failures=$((failures + 1))
  fi
}
rc=0
value=$(get_latest_gh_tag owner/app v) || rc=$?
check "$rc" 0 'F5/F10 prefixed parser succeeds'
check "$value" v1.9.0 'F5/F10 dependency stdout stays separate and prerelease tags are excluded'
check "$(cat "$work/dependencies" 2> /dev/null || true)" jq 'F5 tag entry establishes jq'
: > "$work/dependencies"
value=$(get_latest_gitlab_release owner/app)
check "$value" 1.2.3 'F5 GitLab dependency stdout stays separate'
check "$(cat "$work/dependencies")" jq 'F5 GitLab public parser establishes jq'
ensure_dependencies() { :; }
: > "$work/requests"
value=$(get_latest_gh_tag owner/app) || true
check "$value" v1.9.0 'F10 stable tag beyond one hundred prereleases is selected'
check "$(wc -l < "$work/requests")" 2 'F10 complete checked tag pagination'
scenario=malformed
rc=0
value=$(get_latest_gh_tag owner/app) || rc=$?
check "$rc" 22 'F10 malformed tag producer is not absence'
check "$value" '' 'F10 malformed producer emits no tag'
scenario=partial
rc=0
value=$(get_latest_gh_tag owner/app) || rc=$?
check "$rc" 18 'F10 completed transfer status wins over plausible JSON'
check "$value" '' 'F10 partial producer emits no tag'
for request in generic release; do
  scenario=transient
  : > "$work/requests"
  unset GITHUB_TOKEN var_github_token
  rc=0
  if [[ "$request" == generic ]]; then
    github_api_call https://api.github.com/repos/owner/app/releases/latest "$work/response" || rc=$?
  else
    _github_release_request https://api.github.com/repos/owner/app/releases/latest "$work/response" status || rc=$?
  fi
  check "$rc" 0 "F6 $request retains existing bounded transfer retry"
  check "$(wc -l < "$work/requests")" 2 "F6 $request consumes a completed retry, never partial JSON"
  for scenario in token-first rejected saml ip forbidden; do
    : > "$work/requests"
    unset GITHUB_TOKEN
    export var_github_token=fixture-token-do-not-log
    rc=0
    if [[ "$request" == generic ]]; then
      github_api_call https://api.github.com/repos/owner/app/releases/latest "$work/response" || rc=$?
    else
      _github_release_request https://api.github.com/repos/owner/app/releases/latest "$work/response" status || rc=$?
    fi
    expected=0
    [[ "$scenario" != forbidden ]] || expected=22
    check "$rc" "$expected" "F6 $request $scenario status"
    check "$(head -n1 "$work/requests" | cut -d' ' -f1)" yes "F6 $request $scenario authenticates first request"
    if [[ "$scenario" == rejected || "$scenario" == saml || "$scenario" == ip ]]; then
      check "$(tail -n1 "$work/requests" | cut -d' ' -f1)" no "F6 $request $scenario retries unauthenticated"
      scenario=token-first
      if [[ "$request" == generic ]]; then github_api_call https://api.github.com/repos/other/app/releases/latest "$work/response" || true; else _github_release_request https://api.github.com/repos/other/app/releases/latest "$work/response" status || true; fi
      check "$(tail -n1 "$work/requests" | cut -d' ' -f1)" yes "F6 $request fallback never changes another repository's authentication"
    fi
  done
done
check "$(grep -c fixture-token-do-not-log "$work/diagnostics" || true)" 0 'F6 diagnostics never expose token'
unset GITHUB_TOKEN var_github_token
scenario=normal
: > "$work/requests"
_gh_release_json owner/app latest v1.2. "$work/selected" || true
check "$(command jq -r .tag_name "$work/selected")" v1.2.3 'F7 matching designated release wins over higher listed version'
check "$(command jq -r .body "$work/selected")" designated 'F7 selected metadata retains designated object'
check "$(wc -l < "$work/requests")" 1 'F7 matching designation needs no list'
_gh_release_json owner/app latest v1.2.9 "$work/selected" || true
check "$(command jq -r .tag_name "$work/selected")" v1.2.99 'F7 nonmatching designation retains literal prefix list selection'
scenario=reverse
rc=0
_gh_release_json owner/app v1.2.3 '' "$work/selected" || rc=$?
check "$rc" 0 'F11 reverse numeric-v lookup succeeds without Git-tag substitution'
check "$(command jq -r '.body // empty' "$work/selected")" 'unprefixed asset release' 'F11 reverse spelling retains asset-associated release object'
scenario=normal
export APP='Main App' NSAPP=mainapp var_appversion=v6.0.0
check_for_gh_tag mainapp owner/app || true
check "$CHECK_UPDATE_RELEASE" v6.0.0 'F8 tag checker and deployer share main-app pin selection'
check_for_gh_release mainapp owner/app || true
check "$CHECK_UPDATE_RELEASE" v6.0.0 'F8 release checker and deployer share main-app pin selection'
var_appversion=v1.2.3
fetch_and_deploy_gh_tag mainapp owner/app latest "$work/main-tag" || true
check "$(cat "$work/main-tag/origin" 2> /dev/null || true)" https://github.com/owner/app/archive/refs/tags/v1.2.3.tar.gz 'F8 main-app tag consumes app pin'
fetch_and_deploy_gh_tag dependency owner/app v7.0.0 "$work/dependency-tag"
check "$(cat "$work/dependency-tag/origin")" https://github.com/owner/app/archive/refs/tags/v7.0.0.tar.gz 'F8 prerequisite tag retains independent explicit identity'
export GITLAB_TOKEN=fixture-gitlab-token-do-not-log
fetch_and_deploy_gl_release mainapp owner/app tag latest "$work/gitlab-tag" || true
check "$(cat "$work/gitlab-tag/origin" 2> /dev/null || true)" 'https://gitlab.com/api/v4/projects/owner%2Fapp/repository/archive.tar.gz?sha=v1.2.3&ref_type=tags' 'F8 GitLab tag-only source consumes main-app pin'
check "$(head -n1 "$work/gitlab-archives" 2> /dev/null | cut -d' ' -f1 || true)" yes 'GitLab tag archive receives existing private authentication'
fetch_and_deploy_gl_release dependency owner/app tag v7.0.0 "$work/gitlab-dependency" || true
check "$(cat "$work/gitlab-dependency/origin" 2> /dev/null || true)" 'https://gitlab.com/api/v4/projects/owner%2Fapp/repository/archive.tar.gz?sha=v7.0.0&ref_type=tags' 'F8 GitLab prerequisite tag retains explicit identity'
fetch_and_deploy_gl_release encoded owner/app tag 'v3.0%23#x?y/part' "$work/gitlab-encoded" || true
check "$(cat "$work/gitlab-encoded/origin" 2> /dev/null || true)" 'https://gitlab.com/api/v4/projects/owner%2Fapp/repository/archive.tar.gz?sha=v3.0%2523%23x%3Fy%2Fpart&ref_type=tags' 'GitLab archive ref percent-encodes URL delimiters as query data'
for scenario in gl-denied gl-partial; do
  rc=0
  FORCE_DEPLOY=1 CLEAN_INSTALL=1 fetch_and_deploy_gl_release dependency owner/app tag v8.0.0 "$work/gitlab-dependency" || rc=$?
  expected=22
  [[ "$scenario" != gl-partial ]] || expected=18
  check "$rc" "$expected" "$scenario keeps exact archive producer failure"
  check "$(cat "$HOME/.dependency")" 7.0.0 "$scenario never advances marker"
  check "$(cat "$work/gitlab-dependency/origin")" 'https://gitlab.com/api/v4/projects/owner%2Fapp/repository/archive.tar.gz?sha=v7.0.0&ref_type=tags' "$scenario preserves existing source"
done
scenario=normal
unset GITLAB_TOKEN
mkdir -p "$work/empty-home"
rc=0
HOME="$work/empty-home" var_appversion=v6.0.0 fetch_and_deploy_gh_release '' owner/mainapp tarball latest "$work/derived" || rc=$?
check "$rc" 0 'derived main-app deployment succeeds'
check "$(cat "$work/derived/origin" 2> /dev/null || true)" https://github.com/owner/mainapp/archive/refs/tags/v6.0.0.tar.gz 'derived main app consumes its exact pin before resolving latest'
for provider in gh codeberg; do
  mkdir -p "$work/home-$provider"
  export HOME="$work/home-$provider"
  rc=0
  fetch_and_deploy_${provider}_release mainapp owner/app tarball v7.0.0 "$work/$provider-explicit" || rc=$?
  check "$rc" 0 "F8 $provider explicit deployment succeeds independently"
  check "$(cat "$HOME/.mainapp")" 7.0.0 "F8 $provider explicit requested release outranks ambient app pin"
  rc=0
  fetch_and_deploy_${provider}_release mainapp-helper owner/dependency tarball latest "$work/$provider-dependency" || rc=$?
  check "$rc" 0 "F8 $provider prerequisite deployment succeeds independently"
  check "$(cat "$HOME/.mainapp-helper" 2> /dev/null || true)" 8.0.0 "F8 $provider prerequisite uses its own latest"
  check "$(test -s "$work/$provider-dependency/origin" && printf present || printf absent)" present "F8 $provider publishes its own prerequisite payload"
done
printf '%s failure(s); U1 actual release selection/publication with modeled HTTP\n' "$failures"
[[ "$failures" == 0 ]]
