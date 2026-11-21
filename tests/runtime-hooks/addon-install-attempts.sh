#!/usr/bin/env bash
# runtime-hooks-contract: fixture case-asserted
# Bounded fresh-install custody, not ownership of arbitrary root contents.
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
  APP_SLUG=install-fixture
  app_maintenance_begin "$APP_SLUG"
  case "$phase" in
    begin) addon_install_begin "$c/root" project-fixture ;;
    publish) addon_install_publish_file "$c/candidate" "$c/external file" "$c/root" project-fixture ;;
    directory) addon_install_create_directory "$c/root/state" "$c/root" project-fixture ;;
    publish-state) addon_install_publish_file "$c/state-candidate" "$c/root/state/settings" "$c/root" project-fixture ;;
    wrong-directory) addon_install_create_directory "$c/foreign-directory" "$c/root" project-fixture ;;
    expose) addon_install_expose "$c/root" project-fixture original-native-project ;;
    consumer)
      consumer=''
      addon_install_consumer_identity consumer "$c/root" project-fixture
      printf '%s\n' "$consumer" > "$c/consumer"
      ;;
    complete) addon_install_complete "$c/root" project-fixture ;;
    down) addon_install_teardown_complete "$c/root" project-fixture ;;
    clean) addon_install_cleanup "$c/root" project-fixture ;;
    remove-failure)
      rm() {
        [[ "${!#}" != "$c/external file" ]] || return 47
        command rm "$@"
      }
      addon_install_cleanup "$c/root" project-fixture
      ;;
    directory-remove-failure)
      rmdir() {
        [[ "${!#}" != "$c/root/state" ]] || return 46
        command rmdir "$@"
      }
      addon_install_cleanup "$c/root" project-fixture
      ;;
    retire) addon_install_retire ;;
    retire-check) addon_install_retire --check ;;
    guard) addon_install_guard ;;
    wrong) addon_install_cleanup "$c/root" other-project ;;
    query)
      addon_install_status state "$c/root" project-fixture
      printf '%s\n' "$state" > "$c/observed"
      ;;
    installed)
      ADDON_MARKER_DIR="$c/addons"
      _addon_command_path() { printf '%s/commands/%s\n' "$c" "$1"; }
      _addon_installed_state state
      printf '%s\n' "$state" > "$c/observed"
      ;;
  esac
  exit
fi
source "$ROOT/misc/addon_lxc.func"
failures=0
if ! declare -F addon_install_begin > /dev/null || ! declare -F addon_install_cleanup > /dev/null || ! declare -F addon_install_create_directory > /dev/null; then
  check missing present 'shared bounded install-attempt custody API is required'
else
  work=$(mktemp -d "$TMPDIR/addon-install-attempts.XXXXXXXX")
  trap 'rm -rf -- "$work"' EXIT
  invoke() {
    local status=0
    env -i PATH="$PATH" HOME="$c/home" TMPDIR="$TMPDIR" bash "$0" --child "$c" "$1" > "$c/output-$1" 2>&1 || status=$?
    check "$status" "$2" "$variant/$1 exact status"
    [[ "$status" == "$2" ]] || cat "$c/output-$1"
  }
  for variant in directory directory-data directory-replaced directory-occupied directory-file directory-symlink directory-remove-failure prepared empty-root existing-empty exposed ready edited replaced-root occupied hardlink existing-root remove-failure unsafe malformed; do
    c="$work/$variant"
    mkdir -p "$c/home" "$c/actions"
    chmod 0700 "$c/actions"
    sed "s|/var/lib/scripts-underground/maintenance-locks|$c/locks|g" "$ROOT/misc/core.func" > "$c/core.func"
    sed "s|/var/lib/scripts-underground/addon-install-attempts|$c/actions|g" "$ROOT/misc/addon_lxc.func" > "$c/addon_lxc.func"
    printf 'generated secret\n' > "$c/candidate"
    chmod 0600 "$c/candidate"
    printf 'operator bytes\n' > "$c/foreign"
    record="$c/actions/install-fixture"
    case "$variant" in
      unsafe)
        ln -s "$c/foreign" "$record"
        invoke begin 69
        continue
        ;;
      malformed)
        printf 'invalid\0' > "$record"
        chmod 0600 "$record"
        invoke begin 65
        continue
        ;;
      existing-root | existing-empty) mkdir "$c/root" ;;
    esac
    invoke query 0
    check "$(cat "$c/observed")" absent "$variant absence is not custody"
    invoke begin 0
    invoke begin 65
    invoke guard 65
    invoke retire 65
    check "$(stat -c '%u:%a:%h' "$record")" 0:600:1 "$variant private checked record"
    case "$variant" in
      directory*)
        invoke wrong-directory 65
        check "$(test -e "$c/foreign-directory" && printf present || printf absent)" absent "$variant directory custody cannot escape admitted root"
        if [[ "$variant" == directory-occupied ]]; then mkdir "$c/root/state"; fi
        invoke directory "$([[ "$variant" == directory-occupied ]] && printf 65 || printf 0)"
        if [[ "$variant" == directory-file || "$variant" == directory-symlink ]]; then
          printf 'private state\n' > "$c/state-candidate"
          chmod 0600 "$c/state-candidate"
          invoke publish-state 0
          rm "$c/state-candidate"
        fi
        case "$variant" in
          directory-data) printf 'operator state\n' > "$c/root/state/unknown" ;;
          directory-replaced)
            mv "$c/root/state" "$c/original-state"
            mkdir "$c/root/state"
            ;;
          directory-symlink)
            mv "$c/root/state" "$c/original-state"
            ln -s "$c/original-state" "$c/root/state"
            ;;
        esac
        ;;
    esac
    if [[ "$variant" == occupied ]]; then
      cp "$c/foreign" "$c/external file"
      invoke publish 65
    else
      invoke publish 0
      rm "$c/candidate"
    fi
    invoke wrong 65
    case "$variant" in
      exposed | ready)
        invoke expose 0
        invoke consumer 0
        check "$(cat "$c/consumer")" original-native-project "$variant cold reader retains exact native resource identity"
        invoke clean 65
        if [[ "$variant" == ready ]]; then
          invoke complete 0
          invoke guard 0
        fi
        invoke down 0
        ;;
      edited) printf 'operator edit\n' > "$c/external file" ;;
      hardlink) ln "$c/external file" "$c/extra link" ;;
      replaced-root)
        mv "$c/root" "$c/original-root"
        mkdir "$c/root"
        invoke clean 65
        check "$(cat "$c/external file")" 'generated secret' "$variant mismatched root refuses removal"
        continue
        ;;
    esac
    case "$variant" in empty-root | existing-empty) ;; *) printf 'unknown root data\n' > "$c/root/operator file" ;; esac
    if [[ "$variant" == remove-failure ]]; then
      invoke remove-failure 47
      invoke retire-check 65
      check "$(cat "$c/external file")" 'generated secret' "$variant exact failed removal retains owned file"
    fi
    if [[ "$variant" == directory-remove-failure ]]; then
      invoke directory-remove-failure 46
      invoke retire-check 65
      check "$(test -d "$c/root/state" && printf present || printf absent)" present "$variant failed directory cleanup retains exact child"
    fi
    invoke clean 0
    invoke clean 0
    case "$variant" in
      directory | directory-file | directory-remove-failure) check "$(test -e "$c/root/state" && printf present || printf absent)" absent "$variant exact newly created empty child removed" ;;
      directory-data) check "$(cat "$c/root/state/unknown")" 'operator state' "$variant nonempty owned directory retained" ;;
      directory-replaced | directory-occupied) check "$(test -d "$c/root/state" && printf present || printf absent)" present "$variant unowned directory retained" ;;
      directory-symlink)
        check "$(test -L "$c/root/state" && printf link || printf replaced)" link "$variant replacement directory link retained"
        check "$(cat "$c/original-state/settings")" 'private state' "$variant never removes files through replaced parent"
        ;;
    esac
    case "$variant" in
      empty-root) check "$(test -e "$c/root" && printf present || printf absent)" absent "$variant fresh empty root removed" ;;
      existing-empty) check "$(test -d "$c/root" && printf present || printf absent)" present "$variant existing empty root not adopted" ;;
      *) check "$(cat "$c/root/operator file")" 'unknown root data' "$variant unlisted root contents preserved" ;;
    esac
    case "$variant" in
      occupied) check "$(cat "$c/external file")" 'operator bytes' "$variant collision is not adopted" ;;
      edited) check "$(cat "$c/external file")" 'operator edit' "$variant edited generated file retained" ;;
      hardlink) check "$(cat "$c/extra link")" 'generated secret' "$variant additional link retained" ;;
      *) check "$(test -e "$c/external file" && printf present || printf absent)" absent "$variant matching generated file removed" ;;
    esac
    invoke installed 0
    check "$(cat "$c/observed")" unmarked "$variant receipt alone prevents reinstall"
    invoke retire 0
    check "$(test -e "$record" && printf present || printf absent)" absent "$variant footer retires completed cleanup custody"
    check "$(cat "$c/foreign")" 'operator bytes' "$variant operator bytes unchanged"
  done
fi
printf 'RUNTIME_HOOKS_RESULT failures=%s\n' "$failures"
[[ "$failures" == 0 ]]
