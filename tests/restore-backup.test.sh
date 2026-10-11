#!/usr/bin/env bash
# A failed restore keeps the backup store so the data can still be restored.
set -euo pipefail

ROOT=$(realpath "$(dirname "${BASH_SOURCE[0]}")/..")
source "$ROOT/misc/tools.func"

work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT
export HOME="$work/home" BACKUP_DIR="$work/store" NSAPP=restore-probe STD=''
mkdir "$HOME" "$work/data"

msg_info() { :; }
msg_ok() { :; }
msg_warn() { :; }
msg_error() { :; }

printf 'original' > "$work/data/config"
create_backup "$work/data/config"
printf 'changed by the update' > "$work/data/config"

cp() { return 1; }
rc=0
restore_backup || rc=$?
unset -f cp
[[ "$rc" != 0 ]]
[[ -f "$BACKUP_DIR/.manifest" ]]
[[ "$(< "$BACKUP_DIR/files$work/data/config")" == original ]]
printf 'PASS failed restore keeps the backup store\n'

restore_backup
[[ "$(< "$work/data/config")" == original ]]
[[ ! -e "$BACKUP_DIR" ]]
printf 'PASS successful restore returns the data and removes the store\n'
