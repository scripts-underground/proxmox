#!/usr/bin/env bash
# Actual normal/retry preparation fragments and bundle assembly; pct/OS pipeline
# are modeled. --baseline instruments old literal temporary paths for safe RED.
set -euo pipefail
systemd-detect-virt --vm --quiet || exit 1
: "${TMPDIR:?provide a disk-backed temporary directory}"
case "$(realpath -e "$TMPDIR")" in /tmp | /tmp/*) exit 1 ;; esac
case "$(findmnt -rn -T "$TMPDIR" -o FSTYPE)" in '' | tmpfs | ramfs) exit 1 ;; esac
ROOT=$(realpath "$(dirname "${BASH_SOURCE[0]}")/..")

if [[ "${1:-}" == --child ]]; then
  source "$ROOT/misc/core.func"
  source "$ROOT/misc/error_handler.func"
  source "$CASE_ROOT/bundle.func"
  source "$CASE_ROOT/preparation.sh"
  load_functions
  stop_spinner() { :; }
  msg_info() { :; }
  msg_ok() { :; }
  msg_debug() { :; }
  curl() {
    local path='' url=''
    while (($#)); do
      case "$1" in -o)
        path="$2"
        shift
        ;;
      https://fixture.invalid/*) url="$1" ;; esac
      shift
    done
    [[ "$path" == "$CASE_ROOT/"* ]] || return 97
    [[ "$FETCH_FAILURE" != 1 ]] || return 37
    {
      printf '# %0140d\n' 0
      case "${url##*/}" in
        core.func) printf 'load_functions() { :; }; color() { :; }\n' ;;
        error_handler.func) printf 'catch_errors() { :; }\n' ;;
        install.func)
          printf 'setup_lxc() { :; }; setting_up_container() { :; }; network_check() { :; }; update_os() { :; }; motd_ssh() { :; }; cleanup_lxc() { :; }\n'
          ;;
        tools.func) printf 'setup_uv() { :; }\n' ;;
        github.func) printf 'clone_and_deploy_gh_commit() { :; }\n' ;;
      esac
    } > "$path"
  }
  pct() {
    printf 'pct %s\n' "$*" >> "$CASE_ROOT/calls"
    case "$1" in
      push)
        [[ "$3" == "$CASE_ROOT/"* && "$4" == "$CASE_ROOT/"* ]] || return 97
        printf '%s\n' "$3" > "$CASE_ROOT/pushed-source"
        [[ "$FETCH_FAILURE" != 2 ]] || return 53
        cp -- "$3" "$4"
        ;;
      exec)
        shift 3
        case "$1" in
          mkdir | bash | mktemp | mv | rm) command "$@" ;;
          chmod)
            [[ "$FETCH_FAILURE" != 3 ]] || return 54
            command "$@"
            ;;
          *) return 97 ;;
        esac
        ;;
      *) return 97 ;;
    esac
  }
  lxc-attach() {
    printf 'lxc %s\n' "$*" >> "$CASE_ROOT/calls"
    [[ "$1 $2 $3 $4" == '-n 2110 -- bash' ]] || return 97
    printf '%s\n' "$5" > "$CASE_ROOT/executed-path"
    if [[ -f "$5" ]]; then
      stat -c %a "$5" > "$CASE_ROOT/destination-mode"
      shift 3
      "$@"
    fi
  }
  export APP=PathProbe NSAPP=path-probe REPO_BASE=https://fixture.invalid CTID=2110
  export SESSION_ID="path-${BASHPID}" DEV_MODE_KEEP=true VERBOSE=no
  export var_lxc_tmpdir="$CASE_ROOT/receiver" var_lxc_probe_out="$CASE_ROOT/receiver-effect"
  export install_bundle="$var_lxc_tmpdir/install-bundle.sh"
  install_script() { printf '%s\n' "${TMPDIR-unset}" > "$var_lxc_probe_out"; }
  catch_errors
  preparation() { source "$CASE_ROOT/fragment.sh"; }
  preparation
  exit 0
fi

baseline=0
[[ "${1:-}" != --baseline ]] || baseline=1
work=$(mktemp -d "$TMPDIR/maintenance-build-temp.XXXXXX")
trap 'rm -rf -- "$work"' EXIT
for name in build bundle; do
  if [[ "$baseline" == 1 ]]; then
    git -C "$ROOT" show "59149630ec9f1805295f1d01f43ba5cbafe4b77a:misc/$name.func" | sed 's|/tmp|${LEGACY_TMP}|g' > "$work/$name.func"
  else
    cp "$ROOT/misc/$name.func" "$work/$name.func"
  fi
done
failures=0
check() {
  if [[ "$1" == "$2" ]]; then printf 'PASS %s\n' "$3"; else
    printf 'FAIL %s: expected <%s>, got <%s>\n' "$3" "$2" "$1" >&2
    failures=$((failures + 1))
  fi
}
for route in normal retry; do
  for fault in 0 1 2 3; do
    c="$work/$route-$fault"
    mkdir -p "$c/host" "$c/legacy" "$c/home"
    [[ "$route" != retry ]] || mkdir -m 750 "$c/receiver"
    : > "$c/calls"
    cp "$work/bundle.func" "$c/bundle.func"
    sed -n '/^_prepare_container_bundles() {/,/^}/p' "$work/build.func" > "$c/preparation.sh"
    python3 - "$work/build.func" "$c/fragment.sh" "$route" << 'PY'
import pathlib,sys
lines=pathlib.Path(sys.argv[1]).read_text().splitlines();route=sys.argv[3]
start=next(i for i,l in enumerate(lines) if ('msg_info "Preparing container installer"' in l if route=='normal' else 'local _LXC_CAPTURE_LOG=' in l))
while start>0 and (not lines[start-1].strip() or lines[start-1].strip().startswith(('#','set ','trap '))):start-=1
needle='local lxc_exit=' if route=='normal' else 'local apt_retry_exit='
end=next(i for i in range(start,len(lines)) if needle in lines[i])
pathlib.Path(sys.argv[2]).write_text('\n'.join(lines[start:end+1])+'\n')
PY
    rc=0
    timeout --signal=TERM --kill-after=5s 25s env -i PATH="$PATH" TMPDIR="$c/host" HOME="$c/home" \
      CASE_ROOT="$c" LEGACY_TMP="$c/legacy" FETCH_FAILURE="$fault" BUILD_LOG="$c/active.log" DEBUG_LOGFILE="$c/error.log" \
      bash "$0" --child > "$c/output" 2>&1 || rc=$?
    if [[ "$fault" != 0 ]]; then
      expected=1
      [[ "$fault" != 2 ]] || expected=53
      [[ "$fault" != 3 ]] || expected=54
      check "$rc" "$expected" "$route fault-$fault exact preparation failure propagates"
      check "$(test -e "$c/executed-path" && printf reached || printf absent)" absent "$route failed preparation never invokes container execution"
      if [[ "$fault" != 1 ]]; then
        check "$(test -e "$(cat "$c/pushed-source")" && printf present || printf absent)" absent "$route failed publication removes only its owned sender stage"
      fi
    else
      check "$rc" 0 "$route actual preparation succeeds"
      check "$(cat "$c/executed-path")" "$c/receiver/install-bundle.sh" "$route sender and execution use the same receiver path"
      check "$(cat "$c/receiver-effect")" "$c/receiver" "$route executed bundle sees only its explicit receiving TMPDIR"
      check "$(cat "$c/destination-mode")" 700 "$route transported bundle mode retained"
      expected_dir_mode=1777
      [[ "$route" != retry ]] || expected_dir_mode=750
      check "$(stat -c %a "$c/receiver")" "$expected_dir_mode" "$route receiver root uses shared sticky creation or retains its existing mode"
      check "$(test -e "$(cat "$c/pushed-source")" && printf present || printf absent)" absent "$route removes its owned sender stage"
    fi
  done
done
printf '%s failure(s); baseline=%s; pct and OS hooks modeled\n' "$failures" "$baseline"
[[ "$failures" == 0 ]]
