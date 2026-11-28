#!/usr/bin/env bash
# Container failures retain their status across the network, bundle and host boundaries.
set -euo pipefail

ROOT=$(realpath "$(dirname "${BASH_SOURCE[0]}")/..")
: "${TMPDIR:?provide a disk-backed fixture directory}"
case "$(realpath -e "$TMPDIR")" in /tmp | /tmp/*) exit 1 ;; esac
case "$(findmnt -rn -T "$TMPDIR" -o FSTYPE)" in '' | tmpfs | ramfs) exit 1 ;; esac
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT
export ROOT work

# Source definitions without running install.func's bootstrap.
sed -n '/^network_check() {/,/^}/p' "$ROOT/misc/install.func" > "$work/network.sh"
rc=0
bash -c '
  source "$ROOT/misc/error_handler.func"
  source "$work/network.sh"
  msg_ok() { :; }; msg_warn() { :; }; msg_error() { printf "%s\n" "$*"; }
  ping() { return 0; }; ping6() { return 0; }; sleep() { :; }
  getent() { printf "127.0.0.1 localhost\n"; }
  set -Eeuo pipefail
  network_check
  bash -c "exit 37"
' > "$work/network.log" 2>&1 || rc=$?
[[ $rc == 37 ]]
grep -q 'exit code 37' "$work/network.log"
printf 'PASS network_check restores a status-preserving ERR trap\n'

# Exercise the actual build result path, including flag precedence and the host ERR trap.
sed -n '/^  # Check for error flag file in container/,/^  # Clean up host-side capture log/p' \
  "$ROOT/misc/build.func" > "$work/result.sh"
for result in '37 0 37' '1 37 37' '0 0 0'; do
  read -r attach_rc flag_rc expected <<< "$result"
  rc=0
  attach_rc=$attach_rc flag_rc=$flag_rc bash -c '
    source "$ROOT/misc/error_handler.func"
    msg_error() { printf "%s\n" "$*"; }; msg_dev() { printf "%s\n" "$*"; }
    pct() {
      printf "%s\n" "$*" >> "$work/pct.log"
      case "$*" in
        "exec 9876 -- test -f "*) [[ $flag_rc != 0 ]];;
        "exec 9876 -- cat "*) printf "%s\n" "$flag_rc";;
        "pull "*) return 1;;
      esac
    }
    export DEV_MODE_KEEP=true CTID=9876 SESSION_ID=probe APP=Probe
    export GN= CL= BL= TAB= YW= RD= YWB=
    BUILD_LOG=$work/missing combined_log=$work/combined.log lxc_exit=$attach_rc
    build_result() { eval "$(cat "$work/result.sh")"; }
    set -Eeuo pipefail
    trap error_handler ERR
    build_result
    printf "SUCCESS_REACHED\n"
  ' > "$work/result.log" 2>&1 || rc=$?
  [[ $rc == "$expected" ]]
  if [[ $expected != 0 ]]; then
    grep -q "Installation failed in container 9876 (exit code: $expected)" "$work/result.log"
    if grep -qE 'SUCCESS_REACHED|Remove broken container|Select option' "$work/result.log"; then
      printf 'FAIL kept failure reached success or a removal prompt\n' >&2
      exit 1
    fi
  else
    grep -q SUCCESS_REACHED "$work/result.log"
  fi
  if grep -qE '^stop |^destroy ' "$work/pct.log"; then
    printf 'FAIL kept container was stopped or destroyed\n' >&2
    exit 1
  fi
done
printf 'PASS kept failures preserve flag/attach status, skip success and never remove the CT\n'

# A diagnostic IP lookup after choosing to keep a failed CT cannot replace its status.
rc=0
bash -c '
  source "$ROOT/misc/error_handler.func"
  msg_error() { printf "%s\n" "$*"; }
  pct() {
    printf "%s\n" "$*" >> "$work/motd-pct.log"
    case "$*" in
      "exec 9876 -- test -f "* | "pull "*) return 1;;
      "exec 9876 ip a s dev eth0") return 43;;
    esac
  }
  export DEV_MODE_KEEP=false DEV_MODE_MOTD=true CTID=9876 SESSION_ID=probe APP=Probe
  export GN= CL= BL= TAB= YW= RD= YWB= HOLD= DGN= BFR= CM= REPO_BASE=offline
  BUILD_LOG=$work/missing combined_log=$work/combined.log lxc_exit=37 var_os=debian
  build_result() { eval "$(cat "$work/result.sh")"; }
  set -Eeuo pipefail
  trap error_handler ERR
  build_result
  printf "SUCCESS_REACHED\n"
' > "$work/motd.log" 2>&1 <<< 2 || rc=$?
[[ $rc == 37 ]]
grep -q 'exec 9876 ip a s dev eth0' "$work/motd-pct.log"
if grep -qE '^stop |^destroy ' "$work/motd-pct.log"; then
  printf 'FAIL diagnostic lookup stopped or destroyed the kept container\n' >&2
  exit 1
fi
if grep -q SUCCESS_REACHED "$work/motd.log"; then
  printf 'FAIL failed diagnostic lookup reached success\n' >&2
  exit 1
fi
printf 'PASS failed diagnostic IP lookup preserves the install exit code after keep selection\n'

# Errors before the installer also obey keep mode.
rc=0
bash -c '
  source "$ROOT/misc/error_handler.func"
  export DEV_MODE_KEEP=true CTID=9876 RD= CL= YWB= YW=
  pct() { printf "%s\n" "$*" >> "$work/early-pct.log"; }
  set -Eeuo pipefail
  trap error_handler ERR
  bash -c "exit 42"
' > "$work/early.log" 2>&1 || rc=$?
[[ $rc == 42 ]]
if grep -q 'Remove broken container' "$work/early.log"; then
  printf 'FAIL early error prompted to remove the kept container\n' >&2
  exit 1
fi
[[ ! -e $work/early-pct.log ]]
printf 'PASS early host errors preserve keep mode and the original status\n'

# Exercise the plain bootstrap and its real ERR trap with an installed CT
# represented only by fake pct. No real PVE command is reachable here.
sed -n '/^_lxc_bootstrap() {/,/^}/p; /^_apply_lxc_ssh_access() {/,/^}/p; /^_finish_container_build() {/,/^}/p' \
  "$ROOT/misc/build.func" > "$work/finish.sh"
for finish_case in access broken hook; do
  for caller in ordinary conditional; do
    rc=0
    : > "$work/finish-pct.log"
    finish_case=$finish_case caller=$caller bash -c '
      source "$ROOT/misc/error_handler.func"
      source "$ROOT/misc/core.func"
      source "$ROOT/misc/ssh-access.func"
      source "$work/finish.sh"
      export CTID=9876 SESSION_ID=probe RD= CL= YWB= YW= BL= GN= TAB= DEV_MODE_KEEP=false
      variables() { :; }; color() { :; }; render_header() { :; }
      catch_errors() { set -Eeuo pipefail; trap error_handler ERR; }
      msg_error() { printf "%s\n" "$*"; }; msg_info() { :; }; msg_ok() { :; }
      pveversion() { :; }
      pct() { printf "%s\n" "$*" >> "$work/finish-pct.log"; }
      _lxc_setup() { :; }; _load_ssh_access() { :; }
      _lxc_script_identity_args() { :; }
      _collect_lxc_ssh_access() { _lbs_access_mode=key; }
      _receiving_exec() { cat >/dev/null; [[ $finish_case != access ]] || return 69; }
      post_build_script() { [[ $finish_case != hook ]] || bash -c "exit 48"; echo HOOK_CONTINUED; }
      complete_install() { echo COMPLETED; }
      build_container() {
        if [[ $finish_case == broken ]]; then return 42; fi
        _finish_container_build
      }
      var_ssh_access_account=rea
      if [[ $caller == conditional ]]; then _lxc_bootstrap || exit "$?"; else _lxc_bootstrap; fi
    ' < /dev/null > "$work/finish.log" 2>&1 || rc=$?
    case "$finish_case:$caller" in
      access:*)
        [[ $rc == 69 ]] && grep -Fq 'pct enter 9876' "$work/finish.log" &&
          ! grep -qE '^(stop|destroy) ' "$work/finish-pct.log" &&
          ! grep -qE 'COMPLETED|HOOK_CONTINUED' "$work/finish.log" || {
          printf 'FAIL installed CT access failure (%s, status %s)\n' "$caller" "$rc" >&2
          cat "$work/finish.log" "$work/finish-pct.log" >&2
          exit 1
        }
        ;;
      broken:ordinary)
        if [[ $rc != 42 ]] || ! grep -Fxq 'destroy 9876' "$work/finish-pct.log"; then
          printf 'FAIL broken install did not preserve status 42 and remove CT (status %s)\n' "$rc" >&2
          cat "$work/finish.log" "$work/finish-pct.log" >&2
          exit 1
        fi
        ;;
      broken:conditional) [[ $rc == 42 ]] ;;
      hook:ordinary)
        if [[ $rc != 48 ]] || grep -Eq 'HOOK_CONTINUED|COMPLETED' "$work/finish.log"; then
          printf 'FAIL post-build hook did not stop bootstrap with status 48 (status %s)\n' "$rc" >&2
          cat "$work/finish.log" >&2
          exit 1
        fi
        ;;
    esac
  done
done
printf 'PASS post-install access failure preserves the CT and status; broken installs retain cleanup and hooks retain errexit\n'

# Generate and run real bundles using tiny offline framework stubs.
test_tmp=$TMPDIR
export FALLBACK_TMP="$work/fallback"
mkdir -p "$FALLBACK_TMP"
# Only the unset-creator case instruments its legacy default allocation: it must
# still prove TMPDIR is unset in the receiver without writing to the VM's /tmp.
sed 's|/tmp|${FALLBACK_TMP}|g' "$ROOT/misc/bundle.func" > "$work/fallback-bundle.func"
SESSION_ID="failure-test-$$"
msg_debug() { :; }
pct() {
  case "$1" in
    push) cp "$3" "$4" ;;
    exec)
      shift 3
      command "$@"
      ;;
  esac
}
export APP=Probe NSAPP=probe REPO_BASE=offline CTID=9876
update_script() { printf '%s\n' "${TMPDIR-unset}"; }
for host_tmp in "$work/host-only" ''; do
  if [[ -n $host_tmp ]]; then
    mkdir -p "$host_tmp"
    export TMPDIR=$host_tmp
    source "$ROOT/misc/bundle.func"
  else
    unset TMPDIR
    source "$work/fallback-bundle.func"
  fi
  cache=$(_framework_cache_dir)
  mkdir -p "$cache"
  printf 'load_functions() { :; }; color() { :; }\n' > "$cache/core.func"
  printf 'catch_errors() { :; }\n' > "$cache/error_handler.func"
  printf 'setup_lxc() { :; }\n' > "$cache/install.func"
  printf 'setup_uv() { :; }\n' > "$cache/tools.func"
  printf 'clone_and_deploy_gh_commit() { :; }\n' > "$cache/github.func"
  cp "$ROOT/misc/ssh-access.func" "$cache/"
  _framework_cache_ensure() { :; }
  build_bundle update update_script "$work/bundle.sh" 0700 update_script
  [[ $(bash "$work/bundle.sh") == unset ]]
done
export TMPDIR=$test_tmp
printf 'PASS bundles use the container temp default with and without a host TMPDIR\n'

source "$ROOT/misc/bundle.func"
export TMPDIR="$work/explicit-creator"
mkdir -p "$TMPDIR"
export var_lxc_tmpdir="$work/receiving-context"
mkdir -p "$var_lxc_tmpdir"
cache=$(_framework_cache_dir)
mkdir -p "$cache"
cp "$FALLBACK_TMP/framework-$SESSION_ID/"*.func "$cache/"
_framework_cache_ensure() { :; }
build_bundle update update_script "$work/receiver-bundle.sh" 0700 update_script
[[ $(bash "$work/receiver-bundle.sh") == "$var_lxc_tmpdir" ]]
unset var_lxc_tmpdir
export TMPDIR=$test_tmp
printf 'PASS explicit receiving temporary root is baked independently of creator TMPDIR\n'

# Lookup failures must not be hidden by local/export declaration builtins.
sed -n '/^  get_container_gid() {/,/^  }/p' "$ROOT/misc/build.func" > "$work/gid.sh"
source "$work/gid.sh"
pct() { return 43; }
rc=0
get_container_gid video > "$work/gid.log" || rc=$?
[[ $rc == 43 && ! -s $work/gid.log ]]
pct() { printf 'video:x:104:\n'; }
[[ $(get_container_gid video) == 104 ]]
pct() { :; }
[[ $(get_container_gid video) == 44 ]]
printf 'PASS GID lookup preserves failures, values and the empty-result fallback\n'

sed -n '/^[[:space:]]*\(export \)\?CTID=$(get_valid_container_id /p' \
  "$ROOT/misc/build.func" > "$work/ctid.sh"
[[ $(wc -l < "$work/ctid.sh") == 3 ]]
while IFS= read -r assignment; do
  rc=0
  assignment=$assignment bash -c '
    CTID=9876
    get_valid_container_id() { return 109; }
    lookup() { eval "$assignment"; printf "MASKED\n"; }
    lookup
  ' > "$work/ctid.log" || rc=$?
  [[ $rc == 109 && ! -s $work/ctid.log ]]
done < "$work/ctid.sh"
printf 'PASS all three rebuild paths propagate container-ID allocation failures\n'
