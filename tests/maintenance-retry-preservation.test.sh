#!/usr/bin/env bash
# Real recovery menu and retry preparation with normal keep=false; pct is a
# recording model, so an erroneous destroy is observed without touching a CT.
set -euo pipefail
systemd-detect-virt --vm --quiet || exit 1
: "${TMPDIR:?provide a disk-backed temporary directory}"
case "$(realpath -e "$TMPDIR")" in /tmp | /tmp/*) exit 1 ;; esac
case "$(findmnt -rn -T "$TMPDIR" -o FSTYPE)" in '' | tmpfs | ramfs) exit 1 ;; esac
ROOT=$(realpath "$(dirname "${BASH_SOURCE[0]}")/..")
work=$(mktemp -d "$TMPDIR/maintenance-retry.XXXXXX")
trap 'rm -rf -- "$work"' EXIT
sed -n '/^  # Check for error flag file in container/,/^  # Clean up host-side capture log/p' "$ROOT/misc/build.func" > "$work/result.sh"
sed -n '/^_prepare_container_bundles() {/,/^}/p' "$ROOT/misc/build.func" > "$work/preparation.sh"
failures=0
check() {
  if [[ "$1" == "$2" ]]; then printf 'PASS %s\n' "$3"; else
    printf 'FAIL %s: expected <%s>, got <%s>\n' "$3" "$2" "$1" >&2
    failures=$((failures + 1))
  fi
}
for fault in receiver install update update-link uninstall uninstall-link; do
  c="$work/$fault"
  mkdir -p "$c/tmp"
  rc=0
  env -i PATH="$PATH" TMPDIR="$c/tmp" ROOT="$ROOT" work="$work" CASE_ROOT="$c" FAULT="$fault" bash -c '
    source "$ROOT/misc/error_handler.func"
    source "$ROOT/misc/bundle.func"
    source "$work/preparation.sh"
    export DEV_MODE_KEEP=false DEV_MODE_MOTD=false CTID=2110 SESSION_ID=retry APP=Probe
    export GN= CL= BL= TAB= YW= RD= YWB= HOLD= DGN= BFR= CM= REPO_BASE=offline
    BUILD_LOG=$CASE_ROOT/missing combined_log=$CASE_ROOT/combined.log lxc_exit=100 var_os=debian
    RAM_SIZE=1024 CORE_COUNT=2 DISK_SIZE=8 install_bundle=$CASE_ROOT/install.sh
    msg_info() { printf "%s\n" "$*"; }; msg_error() { printf "%s\n" "$*"; }; msg_ok() { printf "%s\n" "$*"; }
    export CONTAINER_INSTALLING=true
    [[ "$FAULT" != receiver ]] || var_lxc_tmpdir=$CASE_ROOT/receiver
    install_script() { :; }; update_script() { :; }; uninstall_script() { :; }
    build_bundle() {
      printf "bundle %s\n" "$1" >> "$CASE_ROOT/calls"
      case "$1:$FAULT" in install:install) return 47 ;; update:update) return 48 ;; uninstall:uninstall) return 50 ;; esac
    }
    pct() {
      printf "pct %s\n" "$*" >> "$CASE_ROOT/calls"
      case "$*" in
        "exec 2110 -- test -f "* | "pull "*) return 1 ;;
        "exec 2110 -- bash -c "*) [[ "$FAULT" != receiver ]] || return 46 ;;
        "exec 2110 -- ln -sf /usr/local/sbin/update /usr/bin/update") [[ "$FAULT" != update-link ]] || return 49 ;;
        "exec 2110 -- ln -sf /usr/local/sbin/uninstall /usr/bin/uninstall") [[ "$FAULT" != uninstall-link ]] || return 51 ;;
      esac
      return 0
    }
    lxc-attach() { printf "EXECUTED_STALE\n" >> "$CASE_ROOT/calls"; }
    build_result() { source "$work/result.sh"; }
    set -Eeuo pipefail
    catch_errors
    build_result
    printf "FALSE_SUCCESS\n"
  ' > "$c/output" 2>&1 <<< 4 || rc=$?
  case "$fault" in receiver) expected=46 ;; install) expected=47 ;; update) expected=48 ;; update-link) expected=49 ;; uninstall) expected=50 ;; uninstall-link) expected=51 ;; esac
  check "$rc" "$expected" "$fault repair preparation retains exact failure status"
  check "$(grep -c 'Select option' "$c/output" || true)" 1 "$fault actual recovery prompt reached"
  check "$(grep -c 'Repair APT/DPKG' "$c/output" || true)" 1 "$fault actual repair choice offered"
  check "$(grep -Ec '^pct (stop|destroy) ' "$c/calls" || true)" 0 "$fault chosen existing container is never stopped/destroyed"
  check "$(grep -c 'Remove broken container' "$c/output" || true)" 0 "$fault never re-enters destructive host prompt"
  check "$(grep -c EXECUTED_STALE "$c/calls" || true)" 0 "$fault no stale execution"
  check "$(grep -c FALSE_SUCCESS "$c/output" || true)" 0 "$fault no false success"
  check "$(grep -c "preparation failed.*$expected" "$c/output" || true)" 1 "$fault preparation diagnostic carries original status"
done
printf '%s failure(s); actual recovery prompt/branch, recording pct and bundle models\n' "$failures"
[[ "$failures" == 0 ]]
