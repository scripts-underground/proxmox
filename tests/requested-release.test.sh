#!/usr/bin/env bash
# A requested release is never replaced by another GitHub or Codeberg tag.
set -euo pipefail

ROOT=$(realpath "$(dirname "${BASH_SOURCE[0]}")/..")
source "$ROOT/misc/tools.func"

work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT
export HOME="$work/home" STD='' NSAPP=pin-probe
mkdir "$HOME"
calls="$work/calls" errs="$work/errs"
api_code=200 api_body='' cb_code=200 cb_v_code=200 cb_tag=v1.0.0

msg_info() { :; }
msg_ok() { :; }
msg_warn() { :; }
msg_error() { printf '%s\n' "$*" >> "$errs"; }
ensure_dependencies() { :; }
getent() { return 0; }
sleep() { :; }
git() { printf '%s\n' refs/tags/v3.0.0 refs/tags/v0.9.0; }

# GitHub API stub: answers from $api_code/$api_body and records every URL.
# Assets and the older-release scan fail, so the test stops after the tag check.
curl() {
  local out='' prev='' arg url="${*: -1}"
  for arg in "$@"; do
    [[ "$prev" == -o ]] && out="$arg"
    prev="$arg"
  done
  printf '%s\n' "$url" >> "$calls"
  [[ -n "$out" && "$url" == *api.github.com* ]] || return 22
  printf '%s' "$api_body" > "$out"
  printf '%s' "$api_code"
}

# Codeberg API stub: the v-prefixed tag URL gets $cb_v_code, others $cb_code.
codeberg_api_call() {
  local code="$cb_code"
  printf '%s\n' "$1" >> "$calls"
  if [[ "$1" == */tags/v* ]]; then code="$cb_v_code"; fi
  if [[ -n "${3:-}" ]]; then printf '%s' "$code" > "$3"; fi
  [[ "$code" == 200 ]] || return 22
  printf '{"tag_name":"%s"}' "$cb_tag"
}

# GitHub: a mismatched metadata tag is refused before any download.
api_body='{"tag_name":"v2.0.0"}'
: > "$calls"
rc=0
fetch_and_deploy_gh_release pin-probe owner/app binary 1.0.0 "$work/target" || rc=$?
[[ "$rc" == 250 && "$(wc -l < "$calls")" == 1 ]]
printf 'PASS mismatched GitHub release is refused before download\n'

# GitHub: a v-prefixed request matches the unprefixed tag.
api_body='{"tag_name":"1.0.0","assets":[]}'
: > "$errs"
fetch_and_deploy_gh_release pin-probe owner/app binary v1.0.0 "$work/target" || true
if grep -q Requested "$errs"; then
  printf 'FAIL matching v-prefixed release was rejected\n' >&2
  exit 1
fi
printf 'PASS v-prefixed request matches the same release\n'

# GitHub metadata failure: the git fallback accepts only the requested tag.
api_code=500 api_body=''
rc=0
fetch_and_deploy_gh_release pin-probe owner/app binary 1.0.0 "$work/target" || rc=$?
[[ "$rc" == 22 ]]
printf 'PASS requested tag missing from git fallback returns 22\n'

# Codeberg: a non-404 failure never tries the v-prefixed spelling.
cb_code=500
: > "$calls"
rc=0
_codeberg_release_json owner/app 1.0.0 > /dev/null || rc=$?
[[ "$rc" == 22 && "$(wc -l < "$calls")" == 1 ]]
printf 'PASS Codeberg non-404 error does not try the v spelling\n'

# Codeberg: a 404 tries v1.0.0 and accepts it only when the tag matches.
cb_code=404 cb_v_code=200
: > "$calls"
out=$(_codeberg_release_json owner/app 1.0.0)
[[ "$(jq -r .tag_name <<< "$out")" == v1.0.0 && "$(wc -l < "$calls")" == 2 ]]
printf 'PASS Codeberg 404 falls back to the v spelling\n'

cb_tag=v2.0.0
rc=0
_codeberg_release_json owner/app 1.0.0 > /dev/null || rc=$?
[[ "$rc" == 250 ]]
printf 'PASS Codeberg v-spelling returning another tag is refused\n'
