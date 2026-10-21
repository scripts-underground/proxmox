#!/usr/bin/env bash
# Actual Dockge consumer and both generated uninstall owners. Only external
# Docker commands and framework library prerequisites are modeled.
set -euo pipefail
systemd-detect-virt --vm --quiet || exit 1
: "${TMPDIR:?provide disk-backed TMPDIR}"
case "$(realpath -e "$TMPDIR")" in /tmp | /tmp/*) exit 1 ;; esac
case "$(findmnt -rn -T "$TMPDIR" -o FSTYPE)" in '' | tmpfs | ramfs) exit 1 ;; esac
ROOT=$(realpath "$(dirname "${BASH_SOURCE[0]}")/..")
work=$(mktemp -d "$TMPDIR/maintenance-uninstall.XXXXXX")
trap 'rm -rf -- "$work"' EXIT
failures=0
check() {
  if [[ "$1" == "$2" ]]; then printf 'PASS %s\n' "$3"; else
    printf 'FAIL %s: expected <%s>, got <%s>\n' "$3" "$2" "$1" >&2
    failures=$((failures + 1))
  fi
}
for owner in addon lxc; do
  for mode in no yes; do
    for fault in command returned none; do
      c="$work/$owner-$mode-$fault"
      mkdir -p "$c/stage" "$c/sbin" "$c/bin" "$c/markers" "$c/app" "$c/stacks" "$c/tmp"
      printf 'user data\n' > "$c/app/data"
      : > "$c/app/compose.yaml"
      : > "$c/markers/dockge"
      cp "$ROOT/misc/core.func" "$c/stage/core.func"
      cp "$ROOT/misc/error_handler.func" "$c/stage/error_handler.func"
      printf 'pkg_install() { :; }; setup_lxc() { :; }\n' > "$c/stage/install.func"
      printf 'setup_uv() { :; }; fetch_and_deploy_gh_release() { :; }\n' > "$c/stage/tools.func"
      printf 'clone_and_deploy_gh_commit() { :; }\n' > "$c/stage/github.func"
      cat > "$c/model.sh" << 'MODEL'
docker() {
  printf 'docker consumer output\n'
  printf '%s\n' "${SPINNER_PID:-}" > "$CASE_ROOT/spinner-pid"
  [[ "$FAULT" == none ]] || return 47
}
MODEL
      if [[ "$owner" == addon ]]; then
        printf 'addon_baseline() { :; }\n' > "$c/stage/addon.func"
        cat "$c/model.sh" >> "$c/stage/addon.func"
        sed -n '/^function uninstall_script() {/,/^}/p' "$ROOT/scripts/addon/dockge.sh" > "$c/hook.sh"
      else
        cat "$c/model.sh" >> "$c/stage/github.func"
        cat > "$c/hook.sh" << 'HOOK'
uninstall_script() {
  msg_info "Stopping fixture app"
  $STD docker compose down
  rm -rf -- "$var_lxc_app_dir"
  msg_ok "Uninstalled fixture app"
}
HOOK
      fi
      if [[ "$fault" == returned ]]; then
        cat > "$c/hook.sh" << 'HOOK'
uninstall_script() {
  msg_info "Returning uninstall failure"
  printf '%s\n' "${SPINNER_PID:-}" > "$CASE_ROOT/spinner-pid"
  return 47
}
HOOK
      fi
      (
        export APP=Dockge APP_SLUG=dockge NSAPP=dockge REPO_BASE=offline CTID=2110 SESSION_ID=uninstall
        export ADDON_MARKER_DIR="$c/markers" TMPDIR="$c/tmp"
        export var_lxc_tmpdir="$c/tmp"
        export var_addon_install_path="$c/app" var_addon_stacks_path="$c/stacks" var_lxc_app_dir="$c/app"
        source "$c/hook.sh"
        if [[ "$owner" == addon ]]; then
          sed -e "s|/usr/local/sbin|$c/sbin|g" -e "s|/usr/bin|$c/bin|g" "$ROOT/misc/addon_lxc.func" > "$c/subject.func"
          source "$c/subject.func"
          ADDON_MARKER_DIR="$c/markers"
          _addon_bundle_write uninstall uninstall_script "$c/stage"
        else
          sed -e "s|/usr/local/sbin|$c/sbin|g" -e "s|/usr/bin|$c/bin|g" "$ROOT/misc/bundle.func" > "$c/subject.func"
          source "$c/subject.func"
          _framework_cache_ensure() { :; }
          _framework_cache_dir() { printf '%s\n' "$c/stage"; }
          msg_debug() { :; }
          pct() { case "$1" in push) cp -- "$3" "$4" ;; exec)
            shift 3
            command "$@"
            ;;
          esac }
          build_bundle uninstall uninstall_script "$c/sbin/uninstall_dockge" 0755
        fi
      ) > "$c/generate-output" 2>&1
      rc=0
      env -i PATH="$PATH" TMPDIR="$c/tmp" HOME="$c" CASE_ROOT="$c" FAULT="$fault" VERBOSE="$mode" INIT_SYSTEM=openrc \
        var_addon_install_path="$c/app" var_addon_stacks_path="$c/stacks" BUILD_LOG="$c/active.log" DEBUG_LOGFILE="$c/error.log" \
        python3 - "$c/sbin/uninstall_dockge" > "$c/output" 2>&1 << 'PY' || rc=$?
import errno,os,pty,select,subprocess,sys,time
master,slave=pty.openpty()
p=subprocess.Popen(['bash',sys.argv[1]],stdin=subprocess.DEVNULL,stdout=slave,stderr=slave)
os.close(slave);deadline=time.monotonic()+15
while p.poll() is None and time.monotonic()<deadline:
 if select.select([master],[],[],0.05)[0]:
  try:os.write(1,os.read(master,65536))
  except OSError as e:
   if e.errno!=errno.EIO:raise
if p.poll() is None:p.kill();p.wait();raise SystemExit(124)
os.set_blocking(master,False)
for _ in range(20):
 try:os.write(1,os.read(master,65536))
 except OSError:break
os.close(master);raise SystemExit(p.returncode)
PY
      expected=47
      [[ "$fault" != none ]] || expected=0
      check "$rc" "$expected" "$owner/$mode/$fault native uninstall status"
      if [[ "$fault" != none ]]; then
        for witness in app/data sbin/uninstall_dockge; do
          check "$(test -e "$c/$witness" && printf present || printf absent)" present "$owner/$mode/$fault retains $witness"
        done
        [[ "$owner" != addon ]] || check "$(test -e "$c/markers/dockge" && printf present || printf absent)" present "$owner/$mode/$fault retains installed marker"
        check "$(grep -c 'exit code 47' "$c/active.log" || true)" 1 "$owner/$mode/$fault actual error diagnostic in active log"
        check "$(grep -c 'Exit Code : 47' "$c/error.log" 2> /dev/null || true)" 1 "$owner/$mode/$fault actual ERR handler recorded status"
        check "$(grep -Ec 'Stopped and removed|has been uninstalled|Uninstalled fixture' "$c/output" || true)" 0 "$owner/$mode/$fault no false success"
      else
        check "$(test -e "$c/app/data" && printf present || printf absent)" absent "$owner/$mode/success actual hook removes app"
        check "$(test -e "$c/sbin/uninstall_dockge" && printf present || printf absent)" absent "$owner/$mode/success removes command"
      fi
      if [[ "$mode" == no && "$fault" != none ]]; then
        pid=$(cat "$c/spinner-pid")
        check "${pid:+recorded}" recorded "$owner/$fault actual owned spinner started"
        alive=no
        for ((attempt = 0; attempt < 25; attempt++)); do
          if kill -0 "$pid" 2> /dev/null && [[ "$(ps -o stat= -p "$pid")" != *Z* ]]; then
            alive=yes
            sleep 0.02
          else
            alive=no
            break
          fi
        done
        check "$alive" no "$owner/$fault actual owned spinner stopped"
        check "$(test -e "$c/tmp/.spinner.pid" && printf present || printf absent)" absent "$owner/$fault spinner PID file removed"
        # Only the positively recorded fixture spinner may need RED cleanup.
        [[ "$alive" != yes ]] || kill "$pid" 2> /dev/null || true
      fi
    done
  done
done
printf '%s failure(s); actual uninstall owners/Dockge/ERR/spinner; Docker modeled\n' "$failures"
[[ "$failures" == 0 ]]
