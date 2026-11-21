#!/usr/bin/env bash
# runtime-hooks-contract: fixture case-asserted
# Shared addon backup operation custody; real checked records and backup files.
# shellcheck disable=SC2034
set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/../lib/runtime-hooks/harness.sh"
systemd-detect-virt --vm --quiet || exit 1
: "${TMPDIR:?disk-backed TMPDIR required}"
case "$(findmnt -rn -T "$TMPDIR" -o FSTYPE)" in '' | tmpfs | ramfs) exit 1 ;; esac
if [[ "${1:-}" == --child ]]; then
  c=$2 phase=$3
  source "$c/core.func"
  source "$ROOT/misc/tools.func"
  source "$c/addon_lxc.func"
  msg_info() { :; }
  msg_ok() { :; }
  msg_warn() { printf '%s\n' "$*"; }
  msg_error() { printf '%s\n' "$*" >&2; }
  APP_SLUG=backup-fixture
  app_maintenance_begin "$APP_SLUG"
  case "$phase" in
    create) addon_backup_create "$c/store" "$c/config" "$c/optional" ;;
    complete) addon_backup_complete "$c/store" ;;
    wrong-root) addon_backup_create "$c/foreign" "$c/config" "$c/optional" ;;
    copy-failure)
      cp() { return 43; }
      addon_backup_create "$c/store" "$c/config" "$c/optional"
      ;;
  esac
  exit
fi
source "$ROOT/misc/addon_lxc.func"
failures=0
if ! declare -F addon_backup_create > /dev/null || ! declare -F addon_backup_complete > /dev/null; then
  check missing present 'shared operation-scoped backup API is required'
else
  work=$(mktemp -d "$TMPDIR/addon-backups.XXXXXXXX")
  trap 'rm -rf -- "$work"' EXIT
  invoke() {
    local status=0
    env -i PATH="$PATH" HOME="$c/home" TMPDIR="$TMPDIR" bash "$0" --child "$c" "$1" > "$c/output-$1" 2>&1 || status=$?
    check "$status" "$2" "$variant/$1 exact status"
    [[ "$status" == "$2" ]] || cat "$c/output-$1"
  }
  for variant in rotation copy-failure unsafe-record changed-root changed-link; do
    c="$work/$variant"
    mkdir -p "$c/home" "$c/actions" "$c/store"
    chmod 0700 "$c/actions"
    sed "s|/var/lib/scripts-underground/maintenance-locks|$c/locks|g" "$ROOT/misc/core.func" > "$c/core.func"
    sed "s|/var/lib/scripts-underground/addon-backup-actions|$c/actions|g" "$ROOT/misc/addon_lxc.func" > "$c/addon_lxc.func"
    printf 'operator unknown store\n' > "$c/store/.manifest"
    printf 'operator unknown data\n' > "$c/store/unknown"
    printf 'first secret\n' > "$c/target"
    chmod 0600 "$c/target"
    ln -s target "$c/config"
    record="$c/actions/backup-fixture"
    if [[ "$variant" == unsafe-record ]]; then
      ln -s "$c/store/unknown" "$record"
      invoke create 69
    else
      if [[ "$variant" == copy-failure ]]; then invoke copy-failure 43; fi
      invoke create 0
      mapfile -d '' -t rows < "$record"
      saved=${rows[2]}
      check "$(stat -c '%u:%a:%h' "$record")" 0:600:1 "$variant private operation provenance"
      check "$(stat -c '%u:%a' "$saved")" 0:700 "$variant private snapshot store"
      check "$(cat "$saved/files$c/target")" 'first secret' "$variant backs up consumed symlink target"
      case "$variant" in
        changed-root) invoke wrong-root 65 ;;
        changed-link)
          printf 'new target\n' > "$c/other"
          ln -sfn other "$c/config"
          invoke create 65
          ;;
        *)
          printf 'second secret\n' > "$c/target"
          invoke create 0
          check "$(cat "$saved/files$c/target")" 'first secret' "$variant cold retry preserves first snapshot"
          printf 'operator addition\n' > "$saved/unknown"
          invoke complete 0
          check "$(test -e "$record" && printf present || printf absent)" absent "$variant success retires active provenance"
          check "$(cat "$saved/unknown")" 'operator addition' "$variant retirement preserves unknown snapshot contents"
          invoke create 0
          mapfile -d '' -t rows < "$record"
          next=${rows[2]}
          check "$([[ "$saved" != "$next" ]] && printf fresh || printf stale)" fresh "$variant next operation gets fresh store"
          check "$(cat "$next/files$c/target")" 'second secret' "$variant next operation backs up current consumed bytes"
          invoke complete 0
          ;;
      esac
    fi
    check "$(cat "$c/store/.manifest")" 'operator unknown store' "$variant never adopts old configured manifest"
    check "$(cat "$c/store/unknown")" 'operator unknown data' "$variant preserves unknown configured store contents"
  done
fi
printf 'RUNTIME_HOOKS_RESULT failures=%s\n' "$failures"
[[ "$failures" == 0 ]]
