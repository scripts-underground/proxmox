#!/usr/bin/env bash
# runtime-hooks-contract: fixture case-asserted
# Exact-resource teardown custody, including cold interruption recovery.
# shellcheck disable=SC2034
set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/../lib/runtime-hooks/harness.sh"
systemd-detect-virt --vm --quiet || exit 1
: "${TMPDIR:?disk-backed TMPDIR required}"
case "$(findmnt -rn -T "$TMPDIR" -o FSTYPE)" in '' | tmpfs | ramfs) exit 1 ;; esac
if [[ "${1:-}" == --child ]]; then
  c=$2 phase=$3
  source "$c/core.func"
  source "$c/addon_lxc.func"
  msg_warn() { printf '%s\n' "$*" >&2; }
  APP_SLUG=teardown-fixture
  app_maintenance_begin "$APP_SLUG"
  files=("$c/root/compose file" "$c/external env" "$c/optional unit")
  case "$phase" in
    begin) addon_teardown_begin "$c/root" project-fixture "${files[@]}" ;;
    done) addon_teardown_complete "$c/root" project-fixture "${files[@]}" ;;
    remove) addon_teardown_remove "$c/root" project-fixture "${files[@]}" ;;
    retire) addon_teardown_retire ;;
    guard) addon_teardown_guard ;;
    installed)
      ADDON_MARKER_DIR="$c/addons"
      _addon_command_path() { printf '%s/commands/%s\n' "$c" "$1"; }
      _addon_installed_state state
      printf '%s\n' "$state" > "$c/observed"
      ;;
    wrong-project) addon_teardown_begin "$c/root" project-other "${files[@]}" ;;
    wrong-files) addon_teardown_begin "$c/root" project-fixture "$c/foreign" ;;
    query)
      addon_teardown_status state "$c/root" project-fixture "${files[@]}"
      printf '%s\n' "$state" > "$c/observed"
      ;;
  esac
  exit
fi
source "$ROOT/misc/addon_lxc.func"
failures=0
if ! declare -F addon_teardown_begin > /dev/null || ! declare -F addon_teardown_complete > /dev/null || ! declare -F addon_teardown_remove > /dev/null || ! declare -F addon_teardown_retire > /dev/null; then
  check missing present 'shared exact-resource teardown API is required'
else
  work=$(mktemp -d "$TMPDIR/addon-teardown.XXXXXXXX")
  trap 'rm -rf -- "$work"' EXIT
  invoke() {
    local status=0
    env -i PATH="$PATH" HOME="$c/home" TMPDIR="$TMPDIR" bash "$0" --child "$c" "$1" > "$c/output-$1" 2>&1 || status=$?
    check "$status" "$2" "$variant/$1 exact status"
    [[ "$status" == "$2" ]] || cat "$c/output-$1"
  }
  for variant in cold unchanged changed-file replaced-root wrong-inputs unsafe-record malformed-record optional-appeared foreign-content symlink-file; do
    c="$work/$variant"
    mkdir -p "$c/home" "$c/actions" "$c/root"
    chmod 0700 "$c/actions"
    sed "s|/var/lib/scripts-underground/maintenance-locks|$c/locks|g" "$ROOT/misc/core.func" > "$c/core.func"
    sed "s|/var/lib/scripts-underground/addon-teardowns|$c/actions|g" "$ROOT/misc/addon_lxc.func" > "$c/addon_lxc.func"
    printf 'selected model\n' > "$c/root/compose file"
    printf 'selected secret\n' > "$c/external env"
    printf 'operator file\n' > "$c/foreign"
    record="$c/actions/teardown-fixture"
    case "$variant" in
      unsafe-record)
        ln -s "$c/foreign" "$record"
        invoke begin 69
        continue
        ;;
      malformed-record)
        printf 'invalid\0' > "$record"
        chmod 0600 "$record"
        invoke begin 65
        continue
        ;;
      symlink-file)
        rm "$c/external env"
        ln -s foreign "$c/external env"
        ;;
    esac
    invoke query 0
    check "$(cat "$c/observed")" absent "$variant no receipt is not completed teardown"
    invoke guard 0
    invoke begin 0
    check "$(stat -c '%u:%a:%h' "$record")" 0:600:1 "$variant private single-link record"
    invoke query 0
    check "$(cat "$c/observed")" started "$variant begin is not successful down"
    invoke remove 65
    invoke retire 65
    invoke guard 65
    check "$(cat "$c/root/compose file")" 'selected model' "$variant no removal before positive teardown"
    if [[ "$variant" == wrong-inputs ]]; then
      invoke wrong-project 65
      invoke wrong-files 65
    fi
    invoke 'done' 0
    invoke query 0
    check "$(cat "$c/observed")" 'done' "$variant cold observer sees completed down"
    case "$variant" in
      changed-file) printf 'operator edit\n' > "$c/external env" ;;
      replaced-root)
        mv "$c/root" "$c/original"
        mkdir "$c/root"
        printf 'foreign model\n' > "$c/root/compose file"
        ;;
      optional-appeared) printf 'foreign unit\n' > "$c/optional unit" ;;
      foreign-content) printf 'unknown bytes\n' > "$c/root/unknown" ;;
      cold) rm "$c/root/compose file" ;;
    esac
    case "$variant" in
      changed-file | replaced-root | optional-appeared)
        invoke remove 65
        check "$(test -e "$record" && printf retained || printf lost)" retained "$variant conflict retains recovery custody"
        ;;
      *)
        invoke remove 0
        invoke remove 0
        check "$(test -e "$c/root/compose file" && printf present || printf absent)" absent "$variant exact selected model removed"
        check "$({ test -e "$c/external env" || test -L "$c/external env"; } && printf present || printf absent)" absent "$variant selected env name removed"
        if [[ "$variant" == foreign-content ]]; then
          check "$(cat "$c/root/unknown")" 'unknown bytes' "$variant unknown root contents preserved"
        else check "$(test -e "$c/root" && printf present || printf absent)" absent "$variant empty root retired"; fi
        invoke installed 0
        check "$(cat "$c/observed")" unmarked "$variant unfinished footer cannot admit automatic reinstall"
        invoke retire 0
        invoke guard 0
        check "$(test -e "$record" && printf present || printf absent)" absent "$variant successful footer retires receipt"
        ;;
    esac
    check "$(cat "$c/foreign")" 'operator file' "$variant external operator bytes preserved"
  done
fi
printf 'RUNTIME_HOOKS_RESULT failures=%s\n' "$failures"
[[ "$failures" == 0 ]]
