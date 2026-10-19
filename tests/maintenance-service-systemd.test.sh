#!/usr/bin/env bash
# Native installed systemd in the dedicated project VM. Only uniquely named,
# positively owned unit fixtures are installed/removed. No application is installed.
set -euo pipefail
systemd-detect-virt --vm --quiet || exit 1
: "${TMPDIR:?disk-backed TMPDIR required}" "${L2_NATIVE_FIXTURES:?explicit native systemd fixture authorization required}"
[[ "$L2_NATIVE_FIXTURES" == owned-maintenance-vm ]] || exit 65
case "$(realpath -e "$TMPDIR")" in /tmp | /tmp/*) exit 1 ;; esac
case "$(findmnt -rn -T "$TMPDIR" -o FSTYPE)" in '' | tmpfs | ramfs) exit 1 ;; esac
ROOT=$(realpath "$(dirname "${BASH_SOURCE[0]}")/..")
work=$(mktemp -d "$TMPDIR/service-systemd.XXXXXX")
prefix="su-l2-${work##*.}-$$"
owned=()
# Both routes execute the installed binary. The user route is only the deliberate
# unavailable-manager negative query; no systemctl response is modeled here.
systemctl() {
  if [[ "${NATIVE_USER_QUERY:-no}" == yes ]]; then
    command systemctl --user "$@"
  else command systemctl "$@"; fi
}
cleanup() {
  local unit rc=0 failed=0
  for unit in "${owned[@]}"; do
    # The exact file must still be the fixture installed by this invocation.
    cmp "$work/$unit.service" "/etc/systemd/system/$unit.service" || return 1
    sed -i '/^RefuseManualStop=/d' "/etc/systemd/system/$unit.service"
  done
  systemctl daemon-reload || return $?
  for unit in "${owned[@]}"; do
    systemctl stop "$unit.service" || {
      rc=$?
      failed="$rc"
    }
    systemctl disable "$unit.service" || {
      rc=$?
      failed="$rc"
    }
    [[ "$failed" == 0 ]] || return "$failed"
    rm -f -- "/etc/systemd/system/$unit.service"
  done
  systemctl daemon-reload || return $?
  for unit in "${owned[@]}"; do
    test ! -e "/etc/systemd/system/$unit.service" || return 1
    test "$(systemctl show -p LoadState --value "$unit.service")" = not-found || return 1
    test "$(systemctl show -p ActiveState --value "$unit.service")" = inactive || return 1
  done
  printf 'NATIVE_SYSTEMD_FIXTURES_REMOVED=0\n'
}
on_fixture_exit() {
  local original="$?" cleanup_status=0
  cleanup || cleanup_status=$?
  if [[ "$original" == 0 ]]; then original="$cleanup_status"; fi
  exit "$original"
}
trap on_fixture_exit EXIT
source "$ROOT/misc/core.func"
load_functions
sed -n '/^svc_enable() {/,/^# SECTION 4:/p' "$ROOT/misc/install.func" > "$work/init.func"
source "$work/init.func"
export INIT_SYSTEM=systemd BUILD_LOG="$work/helper.log"
failures=0
check() {
  if [[ "$1" == "$2" ]]; then printf 'PASS %s\n' "$3"; else
    printf 'FAIL %s: expected <%s>, got <%s>\n' "$3" "$2" "$1" >&2
    failures=$((failures + 1))
  fi
}
for variant in normal refused; do
  unit="$prefix-$variant"
  test ! -e "/etc/systemd/system/$unit.service"
  test "$(systemctl show -p LoadState --value "$unit.service")" = not-found
  cat > "$work/$unit.service" << UNIT
[Unit]
Description=Owned maintenance lifecycle fixture $unit
[Service]
Type=oneshot
RemainAfterExit=yes
ExecStart=/usr/bin/true
[Install]
WantedBy=multi-user.target
UNIT
  [[ "$variant" != refused ]] || sed -i '/^\[Unit\]/a RefuseManualStop=yes' "$work/$unit.service"
  install -m 0644 "$work/$unit.service" "/etc/systemd/system/$unit.service"
  owned+=("$unit")
done
systemctl daemon-reload
for mode in no yes; do
  export VERBOSE="$mode"
  set_std_mode
  rc=0
  svc_prepare_uninstall "$prefix-absent" || rc=$?
  check "$rc" 0 "native/$mode absent unit query permits idempotence"
  unit="$prefix-normal"
  systemctl enable --now "$unit.service"
  before=$(sha256sum "/etc/systemd/system/$unit.service")
  before=${before%% *}
  was_running=stale
  svc_prepare_uninstall "$unit" stop was_running
  check "$was_running" yes "native/$mode caller receives verified running state"
  check "$(systemctl show -p ActiveState --value "$unit.service")" inactive "native/$mode actual stop outcome"
  check "$(systemctl show -p UnitFileState --value "$unit.service")" enabled "native/$mode shared stop preserves enablement"
  svc_prepare_uninstall "$unit"
  check "$(systemctl show -p UnitFileState --value "$unit.service")" disabled "native/$mode stopped service becomes disabled"
  svc_prepare_uninstall "$unit"
  after=$(sha256sum "/etc/systemd/system/$unit.service")
  after=${after%% *}
  check "$after" "$before" "native/$mode already disabled rerun preserves custom unit bytes"

  # The actual hook, actual helper and installed manager reject RefuseManualStop.
  unit="$prefix-refused"
  systemctl enable --now "$unit.service"
  c="$work/blocked-$mode"
  mkdir -p "$c/app" "$c/home" "$c/tmp"
  native_stop_status=0
  command systemctl stop "$unit.service" > "$c/native-stop-reference.log" 2>&1 || native_stop_status=$?
  [[ "$native_stop_status" != 0 ]] || {
    printf 'Expected native refusal\n' >&2
    exit 1
  }
  printf 'NATIVE_REFUSED_STOP_STATUS mode=%s status=%s\n' "$mode" "$native_stop_status"
  printf 'native retained data\n' > "$c/app/data"
  printf 'native installed marker\n' > "$c/home/.adguardhome-sync"
  sed -n '/^function uninstall_script() {/,/^}/p' "$ROOT/scripts/addon/adguardhome-sync.sh" > "$c/hook.sh"
  cat > "$c/run.sh" << 'CHILD'
set -euo pipefail
source "$SOURCE_ROOT/misc/core.func"
load_functions
source "$HELPER_FILE"
source "$CASE_ROOT/hook.sh"
uninstall_script
CHILD
  rc=0
  env SOURCE_ROOT="$ROOT" HELPER_FILE="$work/init.func" CASE_ROOT="$c" APP=Fixture INIT_SYSTEM=systemd \
    var_addon_service="$unit" var_addon_install_path="$c/app" HOME="$c/home" TMPDIR="$c/tmp" \
    BUILD_LOG="$c/active.log" bash "$c/run.sh" > "$c/output" 2>&1 || rc=$?
  check "$rc" "$native_stop_status" "native/$mode true refused stop retains measured native status"
  check "$(cat "$c/app/data")" 'native retained data' "native/$mode actual hook retains app bytes on refusal"
  check "$(cat "$c/home/.adguardhome-sync")" 'native installed marker' "native/$mode actual hook retains marker on refusal"
  check "$(systemctl show -p ActiveState --value "$unit.service")" active "native/$mode refused unit remains active"
  check "$(systemctl show -p UnitFileState --value "$unit.service")" enabled "native/$mode stop failure never disables unit"
done

# A real unavailable user manager produces a query error, not evidence of absence.
rc=0
NATIVE_USER_QUERY=yes svc_prepare_uninstall "$prefix-absent" > "$work/query-error.log" 2>&1 || rc=$?
check "$rc" 1 'native unavailable-manager query failure is never absence'

# A nonroot native disable operation must propagate authorization failure. Only
# this fixture gets a private namespace alias; agent workspace remains0700.
unit="$prefix-normal"
systemctl enable "$unit.service"
mkdir -m 0755 "$work/nonroot"
{
  printf 'set -euo pipefail\nSTD=""; INIT_SYSTEM=systemd\n'
  declare -f svc_prepare_uninstall
  printf 'msg_error() { printf "%%s\\n" "$*" >&2; }\nsystemctl() { command systemctl --no-ask-password "$@"; }\nsvc_prepare_uninstall "$1"\n'
} > "$work/nonroot/run.sh"
chmod 0644 "$work/nonroot/run.sh"
rc=0
env NATIVE_NONROOT="$work/nonroot" NATIVE_UNIT="$unit" unshare -m --propagation private -- sh -c \
  'mount --bind "$NATIVE_NONROOT" /mnt; setpriv --reuid=65534 --regid=65534 --clear-groups env SYSTEMD_PAGER=cat bash /mnt/run.sh "$NATIVE_UNIT"' \
  > "$work/disable-error.log" 2>&1 || rc=$?
check "$rc" 1 'native denied disable propagates exact authorization status'
check "$(systemctl show -p UnitFileState --value "$unit.service")" enabled 'native denied disable preserves registration'
printf 'NATIVE_SYSTEMD_EVIDENCE=%s\n' "$work"
cleanup
trap - EXIT
printf '%s failure(s); native systemd query/control/state outcomes, actual hook; no app install\n' "$failures"
[[ "$failures" == 0 ]]
