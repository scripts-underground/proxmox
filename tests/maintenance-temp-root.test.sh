#!/usr/bin/env bash
# Guest-only path outcomes. Default mode maps literal legacy paths in subject
# copies; --native executes unmodified functions with modeled network/transport.
set -euo pipefail
systemd-detect-virt --vm --quiet || {
  printf 'Run this test inside an isolated Linux VM.\n' >&2
  exit 1
}
: "${TMPDIR:?provide an existing disk-backed fixture directory}"
case "$TMPDIR" in
  /tmp | /tmp/*)
    printf 'TMPDIR must not use the guest temporary root.\n' >&2
    exit 1
    ;;
esac
export TMPDIR
TMPDIR=$(realpath -e -- "$TMPDIR")
[[ -d "$TMPDIR" && -w "$TMPDIR" ]]
case "$TMPDIR" in
  /tmp | /tmp/*)
    printf 'TMPDIR must not resolve into the guest temporary root.\n' >&2
    exit 1
    ;;
esac
tmp_fstype=$(findmnt --noheadings --raw --output FSTYPE --target "$TMPDIR")
case "$tmp_fstype" in
  '' | *$'\n'* | tmpfs | ramfs)
    printf 'TMPDIR requires a disk-backed filesystem, observed <%s>.\n' "$tmp_fstype" >&2
    exit 1
    ;;
esac
ROOT=$(realpath "$(dirname "${BASH_SOURCE[0]}")/..")
work=$(mktemp -d "$TMPDIR/maintenance-temp-root.XXXXXX")
trap 'rm -rf -- "$work"' EXIT
export LEGACY_TMP="$work/legacy-sink"
mkdir -p "$LEGACY_TMP" "$work/root-a" "$work/root-b" "$work/subjects"
printf 'retain unrelated sibling\n' > "$LEGACY_TMP/preserved"

# Instrument only filesystem literals, not TMPDIR selection or helper outcomes.
# No install.func/bootstrap is sourced and no generated bundle is executed.
subjects="$ROOT/misc"
native=1
if [[ "${1:-}" != --native ]]; then
  native=0
  subjects="$work/subjects"
  for file in bundle addon_lxc tools core; do
    sed 's|/tmp|${LEGACY_TMP}|g' "$ROOT/misc/$file.func" > "$subjects/$file.func"
  done
fi
source "$subjects/bundle.func"
source "$subjects/addon_lxc.func"
source "$subjects/tools.func"
source "$subjects/core.func"
failures=0
check() {
  if [[ "$1" == "$2" ]]; then
    printf 'PASS %s\n' "$3"
  else
    printf 'FAIL %s: expected <%s>, got <%s>\n' "$3" "$2" "$1" >&2
    failures=$((failures + 1))
  fi
}
in_selected_root() {
  if [[ "$1" == "$TMPDIR/"* ]]; then printf yes; else printf no; fi
}
msg_debug() { :; }
debug_log() { :; }
msg_error() { printf '%s\n' "$*" >> "$work/diagnostics"; }
sleep() { :; }
date() {
  if [[ "${1:-}" == +%Y%m%d_%H%M%S ]]; then
    printf '20261018_000000\n'
  else
    command date "$@"
  fi
}
update_script() { printf 'unused hook\n'; }
export APP=TempRoot NSAPP=temp-root APP_SLUG=temp-root CTID=2110
export REPO_BASE=https://fixture.invalid SESSION_ID=temp-root-probe
seed=a
fail_fetch=''
: > "$work/fetches"
: > "$work/pct-calls"

# Model transport only. Each framework response has a valid size/sentinel and
# distinguishable bytes; the real cache and bundle functions choose/store/read it.
curl() {
  local output='' url='' format='' name
  while (($#)); do
    case "$1" in
      -o)
        output="$2"
        shift
        ;;
      -w)
        format="$2"
        shift
        ;;
      --connect-timeout | --max-time) shift ;;
      https://fixture.invalid/*) url="$1" ;;
    esac
    shift
  done
  [[ "$output" == "$work/"* ]] || return 99
  printf '%s\n' "$output" >> "$work/fetches"
  name="${url##*/}"
  [[ "$name" != "$fail_fetch" ]] || return 37
  if [[ "$name" == body ]]; then
    printf 'body-%s\n' "$seed" > "$output"
    printf '%s' "${format//\%\{http_code\}/200}"
    return 0
  fi
  {
    printf '# fixture-%s-%s\n# %0120d\n' "$seed" "$name" 0
    case "$name" in
      core.func) printf 'load_functions() { :; }\n' ;;
      error_handler.func) printf 'catch_errors() { :; }\n' ;;
      install.func) printf 'setup_lxc() { :; }\n' ;;
      tools.func) printf 'setup_uv() { :; }\n' ;;
      github.func) printf 'clone_and_deploy_gh_commit() { :; }\n' ;;
      addon.func) printf 'addon_baseline() { :; }\n' ;;
      *) return 98 ;;
    esac
  } > "$output"
}
pct() {
  printf '%s\n' "$1" >> "$work/pct-calls"
  case "$1" in
    push)
      [[ "$3" == "$work/"* && "$4" == "$work/"* ]] || return 99
      printf '%s\n' "$3" > "$work/pushed-from"
      cp -- "$3" "$4"
      ;;
    exec)
      shift 3
      case "$1" in mktemp | chmod | mv | rm) command "$@" ;; *) return 99 ;; esac
      ;;
    *) return 99 ;;
  esac
}
# Addon destination writing is outside the staging contract tested here.
_addon_bundle_write() {
  printf '%s\n' "$3" > "$work/addon-stage"
  cp -- "$3/core.func" "$work/addon-bytes"
}

for seed in a b; do
  export TMPDIR="$work/root-$seed"
  unset BUILD_LOG INSTALL_LOG _HOST_LOGFILE
  logfile=$(get_active_logfile)
  log_msg "fallback-fixture-$seed"
  check "$(in_selected_root "$logfile")" yes "root-$seed fallback logging honors TMPDIR"
  if grep -Fq "fallback-fixture-$seed" "$logfile"; then
    check yes yes "root-$seed fallback consumer sees actual logged bytes"
  else
    check no yes "root-$seed fallback consumer sees actual logged bytes"
  fi
  : > "$work/fetches"
  _framework_cache_ensure
  fetch_count=$(wc -l < "$work/fetches")
  check "$fetch_count" 5 "root-$seed obtains its own five framework files"
  cache_path=$(dirname "$(head -n 1 "$work/fetches")")
  check "$(in_selected_root "$cache_path")" yes "root-$seed cache lives below selected TMPDIR"
  build_bundle update update_script "$work/delivered-$seed" 0755 run_update_script
  pushed=$(< "$work/pushed-from")
  check "$(in_selected_root "$pushed")" yes "root-$seed bundle staging honors TMPDIR"
  if grep -Fq "# fixture-$seed-core.func" "$work/delivered-$seed"; then
    check yes yes "root-$seed delivered bundle contains its own fetched bytes"
  else
    check no yes "root-$seed delivered bundle contains its own fetched bytes"
  fi
  check "$(wc -l < "$work/fetches")" "$fetch_count" "root-$seed bundle reuses that root's cache"
  addon_assemble_bundles
  stage=$(< "$work/addon-stage")
  check "$(in_selected_root "$stage")" yes "root-$seed addon stage honors TMPDIR"
  check "$(test -e "$stage" && printf present || printf absent)" absent 'addon removes only its owned stage'
  check "$(< "$LEGACY_TMP/preserved")" 'retain unrelated sibling' 'unrelated legacy-sink data survives cleanup'
done

# Actual API helper body/status output, with curl as the completed producer.
export CURL_RETRIES=1
curl_api_with_retry https://fixture.invalid/body > "$work/body-output"
check "$(< "$work/body-output")" $'body-b\n200' 'omitted API body path retains real helper output'
check "$(in_selected_root "$(tail -n 1 "$work/fetches")")" yes 'API capture honors selected TMPDIR'

# Negative transport control: a failed producer must not deliver a bundle.
SESSION_ID=failed-temp-root
fail_fetch=tools.func
before=$(wc -l < "$work/pct-calls")
rc=0
build_bundle update update_script "$work/never-delivered" 0755 run_update_script || rc=$?
check "$rc" 1 'failed framework fetch reports failure'
check "$(wc -l < "$work/pct-calls")" "$before" 'failed fetch does not invoke delivery'
check "$(test -e "$work/never-delivered" && printf present || printf absent)" absent 'failed fetch creates no delivered payload'
printf '%s failure(s); native-source=%s; network/transport modeled\n' "$failures" "$native"
[[ "$failures" == 0 ]]
