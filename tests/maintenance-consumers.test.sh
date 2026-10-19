#!/usr/bin/env bash
# Actual Aria2 update and MQTTX uninstall consumers; filesystem paths and external
# executables are modeled, while pending/status/success and file outcomes are real.
set -euo pipefail
systemd-detect-virt --vm --quiet || exit 1
: "${TMPDIR:?provide a disk-backed temporary directory}"
case "$(realpath -e "$TMPDIR")" in /tmp | /tmp/*) exit 1 ;; esac
case "$(findmnt -rn -T "$TMPDIR" -o FSTYPE)" in '' | tmpfs | ramfs) exit 1 ;; esac
ROOT=$(realpath "$(dirname "${BASH_SOURCE[0]}")/..")

if [[ "${1:-}" == --aria ]]; then
  source "$CASE_ROOT/core.func"
  source "$ROOT/misc/error_handler.func"
  source "$CASE_ROOT/hook.sh"
  load_functions
  header_info() { :; }
  check_container_storage() { :; }
  check_container_resources() { :; }
  stop_spinner() { :; }
  msg_info() { :; }
  msg_ok() { printf '%s\n' "$*" >> "$CASE_ROOT/success"; }
  cleanup_lxc() { printf 'cleanup\n' >> "$CASE_ROOT/cleanup"; }
  apt() {
    printf '%s\n' "$*" >> "$CASE_ROOT/apt"
    [[ "$1" != "$FAULT" ]] || return 43
  }
  catch_errors
  run_update_script
fi

work=$(mktemp -d "$TMPDIR/maintenance-consumers.XXXXXX")
trap 'rm -rf -- "$work"' EXIT
failures=0
check() {
  if [[ "$1" == "$2" ]]; then printf 'PASS %s\n' "$3"; else
    printf 'FAIL %s: expected <%s>, got <%s>\n' "$3" "$2" "$1" >&2
    failures=$((failures + 1))
  fi
}
for mode in no yes; do
  for fault in update upgrade none; do
    c="$work/aria-$mode-$fault"
    mkdir -p "$c/state" "$c/tmp"
    : > "$c/aria2c"
    sed "s|/var/lib/scripts-underground/update-pending|$c/state|g" "$ROOT/misc/core.func" > "$c/core.func"
    sed -n '/^function update_script() {/,/^}/p' "$ROOT/scripts/lxc/aria2.sh" | sed "s|/usr/bin/aria2c|$c/aria2c|g" > "$c/hook.sh"
    rc=0
    env -i PATH="$PATH" TMPDIR="$c/tmp" HOME="$c" CASE_ROOT="$c" FAULT="$fault" VERBOSE="$mode" \
      APP=Aria2 NSAPP=aria-probe BUILD_LOG="$c/active.log" DEBUG_LOGFILE="$c/error.log" \
      bash "$0" --aria > "$c/output" 2>&1 || rc=$?
    expected=43
    [[ "$fault" != none ]] || expected=0
    check "$rc" "$expected" "aria/$mode/$fault actual consumer status"
    if [[ "$fault" != none ]]; then
      check "$(test -e "$c/state/aria-probe" && printf present || printf absent)" present "aria/$mode/$fault pending remains"
      check "$(test -e "$c/success" && printf reached || printf absent)" absent "aria/$mode/$fault no false success"
      check "$(test -e "$c/cleanup" && printf reached || printf absent)" absent "aria/$mode/$fault no success cleanup"
    else
      check "$(test -e "$c/state/aria-probe" && printf present || printf absent)" absent "aria/$mode/success pending cleared"
      check "$(grep -c '^cleanup$' "$c/cleanup" || true)" 1 "aria/$mode/success cleanup once"
    fi
    if [[ "$fault" == update ]]; then
      check "$(grep -c '^upgrade' "$c/apt" || true)" 0 "aria/$mode failed update never upgrades"
    fi
  done

  for fault in nginx reload none; do
    c="$work/mqtt-$mode-$fault"
    mkdir -p "$c/stage" "$c/sbin" "$c/bin" "$c/markers" "$c/nginx/sites-enabled" "$c/nginx/sites-available" "$c/systemd" "$c/app"
    printf 'retained app\n' > "$c/app/data"
    printf 'installed\n' > "$c/markers/mqttx"
    cp "$ROOT/misc/core.func" "$c/stage/core.func"
    cp "$ROOT/misc/error_handler.func" "$c/stage/error_handler.func"
    printf 'pkg_install() { :; }\n' > "$c/stage/install.func"
    sed -n '/^svc_prepare_uninstall() {/,/^}/p' "$ROOT/misc/install.func" >> "$c/stage/install.func"
    printf 'fetch_and_deploy_gh_release() { :; }\n' > "$c/stage/tools.func"
    printf 'clone_and_deploy_gh_commit() { :; }\n' > "$c/stage/github.func"
    cat > "$c/stage/addon.func" << 'STUBS'
addon_baseline() { :; }
stop_spinner() { :; }
msg_info() { :; }
msg_ok() { printf '%s\n' "$*" >> "$CASE_ROOT/success"; }
systemctl() {
  printf '%s\n' "$*" >> "$CASE_ROOT/services"
  if [[ "$1" == show ]]; then
    printf 'LoadState=loaded\nActiveState=inactive\nUnitFileState=disabled\n'
    return 0
  fi
  [[ "$1" != reload || "$FAULT" != reload ]] || return 44
}
nginx() { [[ "$FAULT" != nginx ]] || return 43; }
STUBS
    sed -n '/^function uninstall_script() {/,/^}/p' "$ROOT/scripts/addon/mqttx.sh" |
      sed -e "s|/etc/nginx|$c/nginx|g" -e "s|/etc/systemd/system|$c/systemd|g" > "$c/hook.sh"
    sed -e "s|/usr/local/sbin|$c/sbin|g" -e "s|/usr/bin|$c/bin|g" \
      "$ROOT/misc/addon_lxc.func" > "$c/addon.func"
    (
      source "$c/addon.func"
      source "$c/hook.sh"
      export APP=MQTTX APP_SLUG=mqttx REPO_BASE=offline ADDON_MARKER_DIR="$c/markers"
      export var_addon_app_dir="$c/app" var_addon_service=mqttx
      _addon_bundle_write uninstall uninstall_script "$c/stage"
    ) > "$c/generate-output" 2>&1
    rc=0
    env -i PATH="$PATH" TMPDIR="$c" CASE_ROOT="$c" FAULT="$fault" VERBOSE="$mode" INIT_SYSTEM=systemd \
      BUILD_LOG="$c/active.log" DEBUG_LOGFILE="$c/error.log" bash "$c/sbin/uninstall_mqttx" > "$c/output" 2>&1 || rc=$?
    expected=0
    [[ "$fault" != nginx ]] || expected=43
    [[ "$fault" != reload ]] || expected=44
    check "$rc" "$expected" "mqtt/$mode/$fault actual uninstall bundle status"
    if [[ "$fault" != none ]]; then
      for witness in app/data markers/mqttx sbin/uninstall_mqttx; do
        check "$(test -e "$c/$witness" && printf present || printf absent)" present "mqtt/$mode/$fault retains $witness"
      done
      check "$(test -e "$c/success" && printf reached || printf absent)" absent "mqtt/$mode/$fault no false success"
    else
      check "$(test -e "$c/app/data" && printf present || printf absent)" absent "mqtt/$mode/success removes owned app"
      check "$(test -e "$c/markers/mqttx" && printf present || printf absent)" absent "mqtt/$mode/success removes marker"
    fi
    if [[ "$fault" == nginx ]]; then
      check "$(grep -c '^reload' "$c/services" || true)" 0 "mqtt/$mode failed validation never reloads"
    fi
  done
done
printf '%s failure(s); actual consumer hooks/bundle; external commands and filesystem literals modeled\n' "$failures"
[[ "$failures" == 0 ]]
