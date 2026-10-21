#!/usr/bin/env bash
# Native manager tombstones/broken settings; unique owned unit fixtures only.
set -euo pipefail
systemd-detect-virt --vm --quiet || exit 1
: "${TMPDIR:?disk-backed TMPDIR required}" "${L2_NATIVE_FIXTURES:?explicit native fixture scope required}"
[[ "$L2_NATIVE_FIXTURES" == owned-maintenance-vm ]] || exit 65
case "$(realpath -e "$TMPDIR")" in /tmp | /tmp/*) exit 1 ;; esac
ROOT=$(realpath "$(dirname "${BASH_SOURCE[0]}")/..")
work=$(mktemp -d "$TMPDIR/service-edge-native.XXXXXX")
prefix="su-l2-edges-${work##*.}-$$"
owned=()
cleanup() {
  local u rc=0
  for u in "${owned[@]}"; do
    if [[ -f "/etc/systemd/system/$u.service" ]]; then
      cmp "$work/$u.service" "/etc/systemd/system/$u.service" || return 1
      rm -- "/etc/systemd/system/$u.service"
    fi
  done
  systemctl daemon-reload || return $?
  for u in "${owned[@]}"; do
    systemctl stop "$u.service" 2> /dev/null || rc=$?
    [[ "$rc" == 0 || "$rc" == 5 ]] || return "$rc"
    systemctl reset-failed "$u.service" 2> /dev/null || true
    [[ "$(systemctl show -p ActiveState --value "$u.service")" == inactive ]] || return 1
    [[ "$(systemctl show -p LoadState --value "$u.service")" == not-found ]] || return 1
  done
  printf 'NATIVE_REVIEW_FIXTURES_REMOVED=0\n'
}
on_exit_fixture() {
  local original="$?" clean_rc=0
  cleanup || clean_rc=$?
  [[ "$original" != 0 ]] || original="$clean_rc"
  exit "$original"
}
trap on_exit_fixture EXIT
source "$ROOT/misc/core.func"
load_functions
sed -n '/^svc_enable() {/,/^# SECTION 4:/p' "$ROOT/misc/install.func" > "$work/init.func"
source "$work/init.func"
export INIT_SYSTEM=systemd BUILD_LOG="$work/helper.log"
failures=0
check() {
  if [[ "$1" == "$2" ]]; then printf 'PASS %s\n' "$3"; else
    printf 'FAIL %s expected <%s>, got <%s>\n' "$3" "$2" "$1" >&2
    failures=$((failures + 1))
  fi
}
for mode in no yes; do
  export VERBOSE="$mode"
  set_std_mode
  for kind in active failed failed-no-reload broken; do
    u="$prefix-$mode-$kind"
    [[ "$(systemctl show -p LoadState --value "$u.service")" == not-found ]]
    test ! -e "/etc/systemd/system/$u.service"
    printf '[Service]\nType=oneshot\nRemainAfterExit=yes\nExecStart=/usr/bin/true\n[Install]\nWantedBy=multi-user.target\n' > "$work/$u.service"
    case "$kind" in failed | failed-no-reload) sed -i s,/usr/bin/true,/usr/bin/false, "$work/$u.service" ;; broken) sed -i '/^ExecStart=/d' "$work/$u.service" ;; esac
    install -m 0644 "$work/$u.service" "/etc/systemd/system/$u.service"
    owned+=("$u")
    systemctl daemon-reload
    rc=0
    systemctl start "$u.service" > "$work/$u-start.log" 2>&1 || rc=$?
    if [[ "$kind" != broken ]]; then
      rm -- "/etc/systemd/system/$u.service"
      [[ "$kind" == failed-no-reload ]] || systemctl daemon-reload
    fi
    systemctl show -p LoadState -p ActiveState -p UnitFileState "$u.service" > "$work/$u-before"
    state=stale
    rc=0
    svc_prepare_uninstall "$u" disable state > "$work/$u-helper.log" 2>&1 || rc=$?
    check "$rc" 0 "native/$mode/$kind exact helper outcome"
    if [[ "$kind" == active ]]; then
      check "$state" yes "native/$mode running state reaches caller named state"
      check "$(systemctl show -p ActiveState --value "$u.service")" inactive "native/$mode removed-file running unit is actually stopped"
    fi
  done
done
cleanup
trap - EXIT
printf '%s failure(s); native removed-file/broken-manager states and output consumer\n' "$failures"
[[ "$failures" == 0 ]]
