#!/usr/bin/env bash
# Cold shared-context and operation contracts. Runs only through the public suite.
set -euo pipefail
: "${TMPDIR:?disk TMPDIR required}"
ROOT=$(realpath "$(dirname "${BASH_SOURCE[0]}")/../..")
work=$(mktemp -d "$TMPDIR/addon-operations.XXXXXX")
trap 'rm -rf -- "$work"' EXIT
failures=0
check() {
  local label=$1
  shift
  local status=0
  (
    set -e
    "$@"
  ) || status=$?
  if [[ "$status" == 0 ]]; then printf 'PASS %s\n' "$label"; else
    printf 'FAIL %s (status %s)\n' "$label" "$status" >&2
    failures=$((failures + 1))
  fi
}
identity() (
  source "$ROOT/misc/addon_lxc.func"
  render_header() { :; }
  APP="Renamed display" NSAPP=foreign APP_SLUG=foreign
  addon_init filebrowser
  [[ "$APP_SLUG" == file-browser && "$NSAPP" == file-browser && "$ADDON_SCRIPT_ID" == filebrowser ]]
)
bad_identity() (
  source "$ROOT/misc/addon_lxc.func"
  render_header() { :; }
  APP=Probe
  rc=0
  addon_init ../foreign || rc=$?
  [[ "$rc" == 65 ]]
)
admission() (
  source "$ROOT/misc/addon_lxc.func"
  grep() { return 1; }
  rc=0
  (addon_guard) || rc=$?
  [[ "$rc" != 0 ]] && declare -F _addon_bootstrap > /dev/null
)
temporary_context() (
  source "$ROOT/misc/bundle.func"
  TMPDIR="$work/selected root"
  var_addon_tmpdir=""
  _prepare_addon_context
  [[ -d "$TMPDIR" && "$TMPDIR" == "$work/selected root" ]] || return 1
  rmdir "$TMPDIR"
  _prepare_addon_context
  [[ -d "$TMPDIR" ]]
)
scalar_data() (
  source "$ROOT/misc/bundle.func"
  decoded=''
  v=$'line one\nline two \' $(touch NEVER) \\ end'
  printf -v encoded %q "$v"
  _bundle_scalar_decode decoded "$encoded" || return $?
  [[ "$decoded" == "$v" && ! -e NEVER ]] || return 1
  rc=0
  _bundle_scalar_decode decoded '\$(touch NEVER)' || rc=$?
  [[ "$rc" == 65 && ! -e NEVER ]]
)
scalar_bytes() (
  source "$ROOT/misc/bundle.func"
  decoded=''
  for ((byte = 1; byte < 256; byte++)); do
    printf -v octal '%03o' "$byte"
    printf -v value '%b' "\\$octal"
    printf -v encoded '%q' "$value"
    _bundle_scalar_decode decoded "$encoded" || return $?
    [[ "$decoded" == "$value" ]] || return 1
  done
)
occupied() (
  source "$ROOT/misc/addon_lxc.func"
  APP_SLUG=probe ADDON_MARKER_DIR="$work/markers" var_addon_install_path="$work/app"
  mkdir -p "$var_addon_install_path"
  _addon_installed_state state || return $?
  [[ "$state" == unmarked ]]
)
configured_files() (
  source "$ROOT/misc/addon_lxc.func"
  APP_SLUG=phase-c-file-probe ADDON_MARKER_DIR="$work/absent-markers"
  for field in bin_path config_path conf_path service_path creds_path db_path compose_file compose_env env_file profile_d auth_token_file; do
    printf -v "var_addon_$field" '%s' "$work/existing-$field"
    : > "$work/existing-$field"
    _addon_installed_state state || return $?
    [[ "$state" == unmarked ]] || {
      printf 'Configured file missed: %s\n' "$field" >&2
      return 1
    }
    unset "var_addon_$field"
  done
  var_addon_data_path="$work/shared-content"
  mkdir -p "$var_addon_data_path"
  _addon_installed_state state || return $?
  [[ "$state" == absent ]]
)
unknown_action() (
  source "$ROOT/misc/addon_lxc.func"
  APP=Probe APP_SLUG=probe ADDON_ACTION=updaet ADDON_MARKER_DIR="$work/markers"
  mkdir -p "$ADDON_MARKER_DIR"
  : > "$ADDON_MARKER_DIR/probe"
  rc=0
  (addon_guard_installed --clean) || rc=$?
  [[ "$rc" == 65 ]]
)
root_environment() (
  source "$ROOT/misc/bundle.func"
  _bundle_runtime_header addon > "$work/header" || return $?
  printf 'printf "%%s|%%s|%%s\\n" "$HOME" "$USER" "$LOGNAME"\n' >> "$work/header"
  [[ "$(env -i /bin/bash "$work/header")" == '/root|root|root' ]]
)
installation_lock() (
  sed "s|/var/lib/scripts-underground/maintenance-locks|$work/locks|g" "$ROOT/misc/core.func" > "$work/core.func"
  mkfifo "$work/lock-release"
  exec 4<> "$work/lock-release"
  bash -c 'source "$1"; app_maintenance_acquire operation-probe || exit; : > "$2"; read -r -t 20 _ <&4' _ "$work/core.func" "$work/lock-ready" &
  holder=$!
  trap 'kill "$holder" 2>/dev/null || true; wait "$holder" 2>/dev/null || true' EXIT
  for ((i = 0; i < 100; i++)); do
    [[ ! -e "$work/lock-ready" ]] || break
    sleep 0.02
  done
  [[ -e "$work/lock-ready" ]] || return 1
  source "$work/core.func"
  source "$ROOT/misc/addon_lxc.func"
  APP=Probe APP_SLUG=operation-probe NSAPP=operation-probe REPO_BASE=offline ADDON_MARKER_DIR="$work/operation-markers"
  addon_baseline() { :; }
  addon_assemble_bundles() { :; }
  install_script() { : > "$work/installation-effect"; }
  post_install_script() { :; }
  msg_ok() { :; }
  status=0
  (addon_run_install) || status=$?
  printf 'release\n' >&4
  wait "$holder"
  exec 4>&-
  trap - EXIT
  [[ "$status" == 75 && ! -e "$work/installation-effect" ]]
)
marker_publication() (
  source "$ROOT/misc/addon_lxc.func"
  APP=Probe APP_SLUG=probe REPO_BASE=offline ADDON_MARKER_DIR="$work/atomic-markers"
  mkdir -p "$ADDON_MARKER_DIR"
  printf 'prior marker bytes\n' > "$ADDON_MARKER_DIR/probe"
  chmod() { return 47; }
  status=0
  addon_marker_write || status=$?
  [[ "$status" == 47 && "$(cat "$ADDON_MARKER_DIR/probe")" == 'prior marker bytes' ]]
)
check 'G5 literal identity ignores display label and ambient NSAPP' identity
check 'G5 invalid literal identity refuses' bad_identity
check 'G2 early context admission entry' admission
check 'G6 shared preparer recreates selected same-CT TMPDIR' temporary_context
check 'G7 saved scalars are decoded as data only' scalar_data
check 'G7 all non-NUL scalar bytes roundtrip' scalar_bytes
check 'G3/G14 occupied configured path is not fresh' occupied
check 'G3 configured app files prevent reinstall; shared content alone does not' configured_files
check 'G8 unknown action refuses' unknown_action
check 'G15 shared generated root environment' root_environment
check 'G4 installation refuses the same native maintenance owner before effects' installation_lock
check 'G14 failed marker publication preserves prior bytes' marker_publication
printf '%s failure(s); phase C shared operation contracts\n' "$failures"
[[ "$failures" == 0 ]]
