#!/usr/bin/env bash
# Actual init helper with source-characterized service command boundaries.
# Native installed-manager state observations are retained separately.
set -euo pipefail
systemd-detect-virt --vm --quiet || exit 1
: "${TMPDIR:?disk-backed TMPDIR required}"
case "$(realpath -e "$TMPDIR")" in /tmp | /tmp/*) exit 1 ;; esac
ROOT=$(realpath "$(dirname "${BASH_SOURCE[0]}")/..")
work=$(mktemp -d "$TMPDIR/service-edges.XXXXXX")
trap 'rm -rf -- "$work"' EXIT
sed -n '/^svc_enable() {/,/^# SECTION 4:/p' "$ROOT/misc/install.func" > "$work/init.func"
source "$ROOT/misc/core.func"
source "$work/init.func"
load_functions
export BUILD_LOG="$work/helper.log"
failures=0
check() {
  if [[ "$1" == "$2" ]]; then printf 'PASS %s\n' "$3"; else
    printf 'FAIL %s expected <%s>, got <%s>\n' "$3" "$2" "$1" >&2
    failures=$((failures + 1))
  fi
}
systemctl() {
  printf '%s\n' "$*" >> "$calls"
  case "$1" in
    show)
      [[ "$fault" != query ]] || return 37
      if [[ "$*" == *FragmentPath* ]]; then
        [[ "$fault" != fragment-query ]] || return 38
        printf '%s\n' "$work/existing.service"
        return 0
      fi
      printf 'LoadState=%s\nActiveState=%s\n' "$load_state" "$active_state"
      [[ "$fault" == missing-property ]] || printf 'UnitFileState=%s\n' "$unit_state"
      [[ "$fault" != duplicate-property ]] || printf 'LoadState=not-found\n'
      ;;
    stop) [[ "$fault" != stop ]] || return 47 ;;
    disable) [[ "$fault" != disable ]] || return 49 ;;
  esac
}
touch "$work/existing.service"
for mode in no yes; do
  export VERBOSE="$mode" INIT_SYSTEM=systemd
  set_std_mode
  for case_name in absent-failed absent-active bad-setting error empty empty-failed bad bad-disable fragment-query malformed missing-property duplicate-property query stop disable output-state; do
    calls="$work/$mode-$case_name.calls"
    : > "$calls"
    load_state=loaded active_state=active unit_state=enabled fault=none expected=0
    case "$case_name" in
      absent-failed)
        load_state=not-found
        active_state=failed
        unit_state=''
        ;;
      absent-active)
        load_state=not-found
        unit_state=''
        ;;
      bad-setting | error)
        load_state="$case_name"
        active_state=inactive
        unit_state=disabled
        ;;
      empty) unit_state='' ;;
      empty-failed) unit_state='' active_state=failed fault=disable ;;
      bad) unit_state=bad ;;
      bad-disable) unit_state=bad fault=disable expected=49 ;;
      fragment-query) unit_state=bad fault=fragment-query expected=38 ;;
      malformed)
        unit_state=unrecognized
        expected=22
        ;;
      missing-property)
        fault=missing-property
        expected=22
        ;;
      duplicate-property)
        fault=duplicate-property
        expected=22
        ;;
      query)
        fault=query
        expected=37
        ;;
      stop)
        fault=stop
        expected=47
        ;;
      disable)
        fault=disable
        expected=49
        ;;
    esac
    state=stale
    rc=0
    svc_prepare_uninstall fixture disable state > "$work/output" 2>&1 || rc=$?
    check "$rc" "$expected" "$mode/$case_name status"
    if [[ "$case_name" == absent-active || "$case_name" == output-state ]]; then
      check "$(grep -c '^stop ' "$calls" || true)" 1 "$mode/$case_name stops known running unit"
      check "$state" yes "$mode/$case_name caller output named state is updated"
    fi
    if [[ "$case_name" == absent-failed || "$case_name" == bad-setting || "$case_name" == error || "$case_name" == empty-failed ]]; then
      check "$(grep -Ec '^(stop|disable) ' "$calls" || true)" 0 "$mode/$case_name safely quiesced state skips control"
    fi
  done
done
export INIT_SYSTEM=systemd
rc=0
svc_prepare_uninstall fixture stop _svc_reserved > "$work/output" 2>&1 || rc=$?
check "$rc" 65 'reserved internal output namespace fails clearly'
rc-service() {
  if [[ "$1" == --list ]]; then printf 'fixture\nother\n'; else return 3; fi
}
rc-status() { printf 'default\n'; }
rc-update() {
  case "$1" in
    show)
      [[ "$fault" != query ]] || return 41
      printf ' fixture | boot default custom\n'
      printf ' fixture | default\n'
      ;;
    del)
      [[ "$fault:$3" != disable:custom ]] || return 43
      printf '%s\n' "$3" >> "$calls"
      ;;
  esac
}
for mode in no yes; do
  export VERBOSE="$mode" INIT_SYSTEM=openrc
  set_std_mode
  for fault in none query disable; do
    calls="$work/openrc-$mode-$fault"
    : > "$calls"
    rc=0
    svc_prepare_uninstall fixture > "$work/output" 2>&1 || rc=$?
    expected=0
    case "$fault" in query) expected=41 ;; disable) expected=43 ;; esac
    check "$rc" "$expected" "OpenRC/$mode/$fault exact query/control status"
    if [[ "$fault" == none ]]; then check "$(paste -sd, "$calls")" boot,default,custom "OpenRC/$mode removes every verified registration"; fi
  done
done
export INIT_SYSTEM=unsupported
rc=0
svc_prepare_uninstall fixture > "$work/unsupported.out" 2>&1 || rc=$?
check "$rc" 1 'unsupported init intentionally fails closed'
check "$(grep -c 'Unsupported uninstall init system' "$work/unsupported.out" || true)" 1 'unsupported init capability diagnostic retained'
printf '%s failure(s); actual helper, modeled systemd/OpenRC boundaries\n' "$failures"
[[ "$failures" == 0 ]]
