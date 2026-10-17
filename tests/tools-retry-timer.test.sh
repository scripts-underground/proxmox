#!/usr/bin/env bash
# API retries preserve curl argv/status/body contracts; timers print elapsed time.
set -euo pipefail

ROOT=$(realpath "$(dirname "${BASH_SOURCE[0]}")/..")
source "$ROOT/misc/tools.func"

work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT
calls="$work/calls" sleeps="$work/sleeps"
failures=0

check() {
  if [[ "$1" == "$2" ]]; then
    printf 'PASS %s\n' "$3"
  else
    printf 'FAIL %s: expected <%s>, got <%s>\n' "$3" "$2" "$1" >&2
    failures=$((failures + 1))
  fi
}

sleep() { printf '%s\n' "$1" >> "$sleeps"; }

# Render -w like curl does, including any literal quotes in the format argument.
curl() {
  local format='' output='' max_time='' connect_timeout='' retry='' url=''
  while [[ $# -gt 0 ]]; do
    case "$1" in
      -w)
        format="$2"
        shift
        ;;
      -o)
        output="$2"
        shift
        ;;
      --max-time)
        max_time="$2"
        shift
        ;;
      --connect-timeout)
        connect_timeout="$2"
        shift
        ;;
      --retry)
        retry="$2"
        shift
        ;;
      -fsSL) ;;
      *) url="$1" ;;
    esac
    shift
  done
  local attempt code
  attempt=$(wc -l < "$calls")
  code="${codes[$attempt]:-500}"
  printf '%s|%s|%s|%s|%s\n' "$format" "$max_time" "$connect_timeout" "$retry" "$url" >> "$calls"
  printf 'body-%s\n' "$code" > "$output"
  printf '%s' "${format//\%\{http_code\}/$code}"
  [[ "$code" == 2?? ]]
}

export CURL_RETRIES=3 CURL_TIMEOUT=17 CURL_CONNECT_TO=4
url='https://example.invalid/api?query=two words'
: > "$calls"
: > "$sleeps"
codes=(200)
rc=0
out=$(curl_api_with_retry "$url" "$work/body file" '--retry 0') || rc=$?
check "$rc" 0 '200 succeeds'
check "$out" 200 'status has no literal quotes'
check "$(wc -l < "$calls")" 1 '200 stops retries immediately'
check "$(cat "$calls")" "%{http_code}|17|4|0|$url" 'format, timeouts, extra options and URL retain argument boundaries'
check "$(cat "$work/body file")" body-200 'body is written to the requested path'
check "$(cat "$sleeps")" '' 'success does not sleep'

: > "$calls"
_extra=('global value' 'another value')
before=$(declare -p _extra)
rc=0
curl_api_with_retry "$url" "$work/body file" '--retry 0' > "$work/status" || rc=$?
check "$rc:$(cat "$work/status")" 0:200 'direct call succeeds'
check "$(declare -p _extra)" "$before" 'global _extra is unchanged after a direct call'

check_caller_scope() {
  local -a _extra=('caller value' 'second value')
  local before rc=0
  before=$(declare -p _extra)
  : > "$calls"
  curl_api_with_retry "$url" "$work/body file" '--retry 0' > "$work/status" || rc=$?
  check "$rc:$(cat "$work/status")" 0:200 'caller-scoped direct call succeeds'
  check "$(declare -p _extra)" "$before" 'caller-local _extra is unchanged after a direct call'
}
check_caller_scope

: > "$calls"
rc=0
out=$(curl_api_with_retry "$url" "$work/body file" $' \t--retry\t0\n\n--connect-timeout 9\n ') || rc=$?
check "$rc:$out" 0:200 'multiline extra options succeed'
check "$(cat "$calls")" "%{http_code}|17|9|0|$url" 'options on both lines reach curl across spaces, tabs and newlines'

: > "$calls"
: > "$sleeps"
codes=(503 503 204)
rc=0
out=$(curl_api_with_retry "$url" "$work/body file") || rc=$?
check "$rc:$out" 0:204 'transient failures retry until any 2xx'
check "$(cut -d '|' -f 2 "$calls")" $'17\n34\n68' 'per-attempt timeout doubles'
check "$(cat "$sleeps")" $'1\n2' 'retry waits increase and stop on success'

: > "$calls"
: > "$sleeps"
codes=(500 500 500)
rc=0
out=$(curl_api_with_retry "$url" "$work/body file") || rc=$?
check "$rc:$out" 7:500 'exhaustion returns 7 with the last HTTP status'
check "$(wc -l < "$calls")" 3 'exhaustion honors CURL_RETRIES'

: > "$calls"
: > "$sleeps"
codes=(200)
rc=0
out=$(curl_api_with_retry "$url") || rc=$?
check "$rc:$out" $'0:body-200\n200' 'omitted body path prints body followed by status'
if [[ -e "/tmp/curl_api_body_$$" ]]; then
  printf 'FAIL temporary body file was not removed\n' >&2
  failures=$((failures + 1))
fi

now=100
date() { printf '%s\n' "$now"; }
start=$(start_timer)
check "$start" 100 'start_timer returns epoch seconds'
now=107
check "$(end_timer "$start" 'API request')" 'API request took 7s' 'timer prints custom label and elapsed seconds'
check "$(end_timer "$start")" 'Operation took 7s' 'timer supplies the upstream default label'

printf '%s failure(s)\n' "$failures"
[[ "$failures" == 0 ]]
