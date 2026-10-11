#!/usr/bin/env bash
# An unfinished update is redone; --clean forces it; unknown options are refused.
# Needs root (guest): the pending-flag directory is a tmpfs in a private mount namespace.
set -euo pipefail

if [[ "${UPDATE_PENDING_NS:-}" != 1 ]]; then
  exec unshare -m --propagation private env UPDATE_PENDING_NS=1 bash -c \
    'mkdir -p /var/lib/scripts-underground && mount -t tmpfs tmpfs /var/lib/scripts-underground && exec bash "$1"' _ "$0"
fi

ROOT=$(realpath "$(dirname "${BASH_SOURCE[0]}")/..")
source "$ROOT/misc/core.func"
source "$ROOT/misc/error_handler.func"
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT
export NSAPP=upd-probe APP=UpdProbe
calls="$work/calls"
flag=/var/lib/scripts-underground/update-pending/upd-probe

msg_info() { :; }
msg_ok() { :; }
msg_warn() { :; }
msg_error() { :; }
cleanup_lxc() { :; }

# The hook records the force flags it saw and returns $hook_rc.
hook_rc=0
update_script() {
  printf '%s %s\n' "${UPDATE_FORCE:-none}" "${FORCE_DEPLOY:-none}" >> "$calls"
  return "$hook_rc"
}

# run_update_script always exits, so each run is a subshell with the EXIT trap.
run() {
  (
    trap on_exit EXIT
    run_update_script "$@"
  )
}

rc=0
run || rc=$?
[[ $rc == 0 && ! -e $flag && "$(tail -n 1 "$calls")" == 'none none' ]]
printf 'PASS normal run is not forced and leaves no flag\n'

hook_rc=1
rc=0
run || rc=$?
[[ $rc == 1 && -e $flag ]]
printf 'PASS failing hook leaves the pending flag\n'

hook_rc=0
rc=0
run || rc=$?
[[ $rc == 0 && ! -e $flag && "$(tail -n 1 "$calls")" == '1 1' ]]
printf 'PASS unfinished update is redone forced and clears the flag\n'

rc=0
run --clean || rc=$?
[[ $rc == 0 && ! -e $flag && "$(tail -n 1 "$calls")" == '1 1' ]]
printf 'PASS update --clean forces the update\n'

rc=0
run --bogus || rc=$?
[[ $rc == 65 && ! -e $flag && "$(wc -l < "$calls")" == 4 ]]
printf 'PASS unknown option exits 65 without running the hook\n'
