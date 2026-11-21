#!/usr/bin/env bash
# Checked no-clobber publication and exact private-file custody, in cold children.
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
  APP_SLUG=owned-file-fixture
  app_maintenance_begin "$APP_SLUG"
  case "$phase" in
    publish) addon_publish_owned_file "$c/source" "$c/external env" ;;
    remove) addon_remove_owned_file "$c/external env" ;;
    record-stage) addon_record_owned_file "$c/source" ;;
    remove-stage) addon_remove_owned_file ;;
    fail-remove-stage)
      rm() { return 44; }
      addon_remove_owned_file
      ;;
    wrong-path) addon_remove_owned_file "$c/foreign" ;;
    installed)
      ADDON_MARKER_DIR="$c/addons"
      _addon_command_path() { printf '%s/commands/%s\n' "$c" "$1"; }
      _addon_installed_state state
      printf '%s\n' "$state" > "$c/observed"
      ;;
    updated | rename-refusal | concurrent-update)
      before=''
      addon_owned_file_identity before "$c/external env"
      printf 'updated private bytes\n' > "$c/update source"
      chmod 0600 "$c/update source"
      if [[ "$phase" == rename-refusal ]]; then mv() { return 44; }; fi
      if [[ "$phase" == concurrent-update ]]; then printf 'operator bytes\n' > "$c/external env"; fi
      addon_replace_owned_file "$c/update source" "$c/external env" "$before"
      ;;
    interrupted)
      ln() {
        command ln "$@" || return $?
        return 44
      }
      addon_publish_owned_file "$c/source" "$c/external env"
      ;;
    collision)
      ln() {
        printf 'foreign bytes\n' > "${!#}"
        command ln "$@"
      }
      addon_publish_owned_file "$c/source" "$c/external env"
      ;;
  esac
  exit
fi
source "$ROOT/misc/addon_lxc.func"
failures=0
if ! declare -F addon_publish_owned_file > /dev/null || ! declare -F addon_remove_owned_file > /dev/null; then
  check missing present 'shared private-file publication custody API is required'
else
  work=$(mktemp -d "$TMPDIR/addon-owned-file.XXXXXXXX")
  trap 'rm -rf -- "$work"' EXIT
  invoke() {
    local status=0
    env -i PATH="$PATH" HOME="$c/home" TMPDIR="$TMPDIR" bash "$0" --child "$c" "$1" > "$c/output-$1" 2>&1 || status=$?
    check "$status" "$2" "$variant/$1 exact status"
    [[ "$status" == "$2" ]] || cat "$c/output-$1"
  }
  for variant in cold edited replaced symlink hardlink missing interrupted collision occupied legacy unsafe-record malformed-record unsafe-source wrong-path updated rename-refusal concurrent-update; do
    c="$work/$variant"
    mkdir -p "$c/home" "$c/actions"
    chmod 0700 "$c/actions"
    sed "s|/var/lib/scripts-underground/maintenance-locks|$c/locks|g" "$ROOT/misc/core.func" > "$c/core.func"
    sed "s|/var/lib/scripts-underground/addon-owned-files|$c/actions|g" "$ROOT/misc/addon_lxc.func" > "$c/addon_lxc.func"
    printf 'private bytes\n' > "$c/source"
    chmod 0600 "$c/source"
    printf 'operator bytes\n' > "$c/foreign"
    record="$c/actions/owned-file-fixture"
    case "$variant" in
      unsafe-record)
        ln -s "$c/foreign" "$record"
        invoke publish 69
        continue
        ;;
      malformed-record)
        printf 'invalid\0' > "$record"
        chmod 0600 "$record"
        invoke publish 65
        continue
        ;;
      unsafe-source)
        chmod 0644 "$c/source"
        invoke publish 65
        continue
        ;;
      occupied)
        cp "$c/foreign" "$c/external env"
        invoke publish 65
        check "$(cat "$c/external env")" 'operator bytes' 'occupied destination is never adopted'
        continue
        ;;
      legacy)
        cp "$c/foreign" "$c/external env"
        invoke remove 0
        check "$(cat "$c/external env")" 'operator bytes' 'legacy file survives removal without custody'
        continue
        ;;
      interrupted) invoke interrupted 44 ;;
      collision) invoke collision 1 ;;
      *) invoke publish 0 ;;
    esac
    check "$(stat -c '%u:%a:%h' "$record")" 0:600:1 "$variant private single-link data receipt"
    if [[ "$variant" != collision ]]; then
      check "$(cat "$c/external env")" 'private bytes' "$variant complete bytes reach selected consumer"
      check "$(stat -c %a "$c/external env")" 600 "$variant published file is private"
    fi
    # Staging is gone before a new process recovers or removes the file.
    rm "$c/source"
    case "$variant" in
      updated)
        invoke updated 0
        check "$(cat "$c/external env")" 'updated private bytes' 'owned rewrite reaches selected consumer'
        ;;
      rename-refusal)
        invoke rename-refusal 44
        check "$(cat "$c/external env")" 'private bytes' 'refused rename preserves old owned preimage'
        ;;
      concurrent-update) invoke concurrent-update 65 ;;
      edited) printf 'operator bytes\n' > "$c/external env" ;;
      replaced)
        rm "$c/external env"
        cp "$c/foreign" "$c/external env"
        ;;
      symlink)
        rm "$c/external env"
        ln -s foreign "$c/external env"
        ;;
      hardlink) ln "$c/external env" "$c/operator-link" ;;
      missing)
        rm "$c/external env"
        invoke installed 0
        check "$(cat "$c/observed")" unmarked 'file custody alone prevents automatic reinstall'
        ;;
      wrong-path)
        invoke wrong-path 65
        check "$(test -f "$record" && printf retained)" retained 'wrong destination retains custody'
        ;;
    esac
    invoke remove 0
    case "$variant" in
      edited | replaced | symlink | hardlink | collision | concurrent-update)
        check "$({ test -e "$c/external env" || test -L "$c/external env"; } && printf retained)" retained "$variant operator-owned or ambiguous file retained"
        ;;
      *) check "$(test -e "$c/external env" && printf present || printf absent)" absent "$variant exact owned file retired" ;;
    esac
    check "$(cat "$c/foreign")" 'operator bytes' "$variant foreign data remains unchanged"
    check "$(test -e "$record" && printf present || printf absent)" absent "$variant handled custody retired"
    if [[ "$variant" == missing ]]; then
      invoke installed 0
      check "$(cat "$c/observed")" absent 'retired file custody does not strand an empty target'
    fi
  done
fi
if ! declare -F addon_record_owned_file > /dev/null; then
  check missing present 'shared exact-stage custody API is required'
else
  for variant in stage-cold stage-edited stage-link stage-hardlink stage-missing stage-unsafe stage-malformed stage-double stage-public-source stage-link-source stage-hardlink-source; do
    c="$work/$variant"
    mkdir -p "$c/home" "$c/actions"
    chmod 0700 "$c/actions"
    sed "s|/var/lib/scripts-underground/maintenance-locks|$c/locks|g" "$ROOT/misc/core.func" > "$c/core.func"
    sed "s|/var/lib/scripts-underground/addon-owned-files|$c/actions|g" "$ROOT/misc/addon_lxc.func" > "$c/addon_lxc.func"
    printf 'private stage\n' > "$c/source"
    chmod 0600 "$c/source"
    printf 'foreign bytes\n' > "$c/foreign"
    record="$c/actions/owned-file-fixture"
    case "$variant" in
      stage-public-source) chmod 0644 "$c/source" ;;
      stage-link-source)
        rm "$c/source"
        ln -s foreign "$c/source"
        ;;
      stage-hardlink-source) ln "$c/source" "$c/operator-link" ;;
    esac
    if [[ "$variant" == *-source ]]; then
      invoke record-stage 65
      check "$(test -e "$record" && printf present || printf absent)" absent "$variant unsafe source gains no custody"
      continue
    fi
    invoke record-stage 0
    case "$variant" in
      stage-cold)
        invoke fail-remove-stage 44
        check "$(test -e "$record" && printf retained)" retained 'failed exact-stage removal retains custody'
        ;;
      stage-edited) printf 'operator bytes\n' > "$c/source" ;;
      stage-link)
        rm "$c/source"
        ln -s foreign "$c/source"
        ;;
      stage-hardlink) ln "$c/source" "$c/operator-link" ;;
      stage-missing) rm "$c/source" ;;
      stage-unsafe)
        chmod 0644 "$record"
        invoke remove-stage 69
        continue
        ;;
      stage-malformed)
        printf 'invalid\0' > "$record"
        invoke remove-stage 65
        continue
        ;;
      stage-double) invoke record-stage 65 ;;
    esac
    invoke remove-stage 0
    case "$variant" in
      stage-edited | stage-link | stage-hardlink)
        check "$({ test -e "$c/source" || test -L "$c/source"; } && printf retained)" retained "$variant changed stage is not deleted"
        ;;
      *) check "$(test -e "$c/source" && printf present || printf absent)" absent "$variant exact stage removed" ;;
    esac
    check "$(cat "$c/foreign")" 'foreign bytes' "$variant foreign bytes remain"
    check "$(test -e "$record" && printf present || printf absent)" absent "$variant stage custody retired"
  done
fi
printf 'RUNTIME_HOOKS_RESULT failures=%s\n' "$failures"
[[ "$failures" == 0 ]]
