#!/usr/bin/env bash
# shellcheck disable=SC2034,SC2154
# Real bundle/release/pending owners; only package and service effects are modeled.
set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/../lib/runtime-hooks/addon-release.sh"
app=bazarr
script_type=lxc
release_app=$app release_mode=prebuild release_asset=bazarr.zip
variants=(fresh checker no-update selected pending build missing)
hook_paths=(/var/lib/bazarr var-lib-bazarr)
runtime_hooks_model() {
  addon_release_model
  curl_download() {
    printf '%s\n' "$2" >> "$c/downloads"
    python3 - "$c/payload" "$1" << 'PY'
import pathlib,sys,zipfile
root=pathlib.Path(sys.argv[1])
with zipfile.ZipFile(sys.argv[2],'w') as archive:
 for path in root.rglob('*'):
  if path.is_file():archive.write(path,path.relative_to(root))
PY
  }
  uv() {
    [[ "$APP_FAULT" != build || "$1 $2" != 'pip install' ]] || return 52
  }
}
addon_release_setup() {
  mkdir -p "$c/var-lib-bazarr" "$c/opt/bazarr/data/"{config,db,backup}
  printf 'saved API identity\n' > "$c/opt/bazarr/data/config/config.yaml"
  printf 'saved profiles\n' > "$c/opt/bazarr/data/db/bazarr.db"
  printf 'saved backup\n' > "$c/opt/bazarr/data/backup/proof"
  stat -c '%i' "$c/opt/bazarr/data/db/bazarr.db" > "$c/data-inode"
  printf 'new requirements\n' > "$c/payload/requirements.txt"
  printf 'new application\n' > "$c/payload/bazarr.py"
  printf 'old application\n' > "$c/opt/bazarr/bazarr.py"
  if [[ "$variant" == pending ]]; then
    printf '2.0.0\n' > "$c/home/.bazarr"
    printf 'interrupted update\n' > "$c/state/bazarr"
  fi
  [[ "$variant" != missing ]] || rmdir "$c/var-lib-bazarr"
}
runtime_hooks_expected() {
  case "$fault:$variant" in checker:*) expected=17 ;; build:*) expected=52 ;; *:missing) expected=1 ;; esac
}
runtime_hooks_assert() {
  check "$(cat "$c/opt/bazarr/data/config/config.yaml")" 'saved API identity' "$app/$variant API identity retained"
  check "$(cat "$c/opt/bazarr/data/db/bazarr.db")" 'saved profiles' "$app/$variant profile data retained"
  check "$(cat "$c/opt/bazarr/data/backup/proof")" 'saved backup' "$app/$variant backups retained"
  check "$(stat -c '%i' "$c/opt/bazarr/data/db/bazarr.db")" "$(cat "$c/data-inode")" "$app/$variant live database inode retained"
  case "$variant" in
    checker | no-update | missing)
      check "$(stat -c %s "$c/downloads")" 0 "$app/$variant no deployment"
      check "$(stat -c %s "$c/services")" 0 "$app/$variant no service effects"
      ;;
    *)
      check "$(cat "$c/opt/bazarr/bazarr.py")" 'new application' "$app/$variant source deployed"
      check "$(grep -c 'v9.0.0' "$c/downloads" || true)" 0 "$app/$variant never deploys moved latest"
      ;;
  esac
  if [[ "$variant" == selected ]]; then
    check "$(grep -c '/releases/tags/v2.0.0$' "$c/requests" || true)" 1 "$app binds selected raw tag"
    check "$(grep -c '/releases/latest$' "$c/requests" || true)" 1 "$app resolves latest once"
  fi
}
runtime_hooks_retry_needed() { [[ "$expected" != 0 && "$variant" != missing ]]; }
runtime_hooks_retry_assert() {
  check "$(cat "$c/opt/bazarr/bazarr.py")" 'new application' "$app retry source consumer"
  check "$(cat "$c/opt/bazarr/data/db/bazarr.db")" 'saved profiles' "$app retry preserves profiles"
}
runtime_hooks_main "$@"
