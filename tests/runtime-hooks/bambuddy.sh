#!/usr/bin/env bash
# shellcheck disable=SC2034,SC2154
# Real bundle/release/replacement/pending owners; package and build effects modeled.
set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/../lib/runtime-hooks/addon-release.sh"
app=bambuddy
script_type=lxc
release_app=$app release_mode=tarball release_asset=source.tar.gz
variants=(selected checker no-update build-failure pending missing)
hook_paths=()
runtime_hooks_variant() {
  case "$variant" in checker) fault=checker ;; build-failure) fault=build ;; esac
}
runtime_hooks_expected() {
  case "$fault" in checker) expected=17 ;; build) expected=37 ;; esac
  [[ "$variant" != missing ]] || expected=1
}
addon_release_setup() {
  printf '#!/usr/bin/env bash\nexit 0\n' > "$c/local/bin/systemctl"
  chmod 0755 "$c/local/bin/systemctl"
  mkdir -p "$c/opt/bambuddy/"{frontend,backend/app/core,.venv/bin} "$c/payload/"{frontend,backend/app/core}
  # Native Python executes the production path reader. Only the installed
  # application's Settings object is a fixture, not the reader or replacement.
  cat > "$c/opt/bambuddy/backend/app/core/config.py" << 'PY'
from pathlib import Path
from types import SimpleNamespace
import sys
sys.modules['sqlalchemy.engine'] = SimpleNamespace(make_url=lambda value: SimpleNamespace(database='/opt/bambuddy/custom data/state.db', get_backend_name=lambda: 'sqlite'))
settings = SimpleNamespace(base_dir=Path('/opt/bambuddy'), archive_dir=Path('/opt/bambuddy/archive'), plate_calibration_dir=Path('/opt/bambuddy/data/plate_calibration'), log_dir=Path('/opt/bambuddy/logs'), database_url='sqlite+aiosqlite:////opt/bambuddy/custom data/state.db')
PY
  cp "$c/opt/bambuddy/backend/app/core/config.py" "$c/payload/backend/app/core/config.py"
  ln -s /usr/bin/python3 "$c/opt/bambuddy/.venv/bin/python"
  printf 'original env\n' > "$c/opt/bambuddy/.env"
  paths=(data bambuddy.db bambuddy.db-wal bambuddy.db-shm bambuddy.db-journal archive virtual_printer firmware icons projects overlay-branding photos notification_photos spoolbuddy/ssh timelapse_frames backups logs 'custom data')
  local path
  for path in "${paths[@]}"; do
    if [[ "$path" == bambuddy.db* ]]; then printf 'saved database\n' > "$c/opt/bambuddy/$path"; else
      mkdir -p "$c/opt/bambuddy/$path"
      printf 'saved %s\n' "$path" > "$c/opt/bambuddy/$path/state.db"
    fi
  done
  for path in -wal -shm -journal; do printf 'saved sidecar\n' > "$c/opt/bambuddy/custom data/state.db$path"; done
  printf 'source default\n' > "$c/payload/.env"
  mkdir -p "$c/payload/overlay-branding"
  printf 'source must not reset data\n' > "$c/payload/overlay-branding/state.db"
  printf 'old source\n' > "$c/opt/bambuddy/revision"
  printf 'selected source\n' > "$c/payload/revision"
  mkdir -p "$c/opt/bambuddy/spoolbuddy/daemon" "$c/payload/spoolbuddy/daemon"
  printf 'old daemon\n' > "$c/opt/bambuddy/spoolbuddy/daemon/revision"
  printf 'selected daemon\n' > "$c/payload/spoolbuddy/daemon/revision"
  if [[ "$variant" == pending ]]; then
    printf '2.0.0\n' > "$c/home/.bambuddy"
    printf 'interrupted\n' > "$c/state/bambuddy"
  fi
  : > "$c/inodes"
  for path in .env "${paths[@]}"; do stat -c '%i %n' "$c/opt/bambuddy/$path" >> "$c/inodes"; done
  [[ "$variant" != missing ]] || rm -rf -- "$c/opt/bambuddy"
}
runtime_hooks_model() {
  addon_release_model
  uv() {
    if [[ "$APP_FAULT" == build && "$*" == 'pip install -r requirements.txt' ]]; then return 37; fi
  }
  systemctl() {
    if [[ "$1" == show ]]; then printf '0\n'; else printf '%s\n' "$*" >> "$c/services"; fi
  }
}
bambuddy_preservation_assert() {
  check "$(cat "$c/opt/bambuddy/.env")" 'original env' "$app/$variant environment retained"
  check "$(cat "$c/opt/bambuddy/bambuddy.db")" 'saved database' "$app/$variant database retained"
  local path
  for path in "${paths[@]}"; do
    if [[ "$path" == bambuddy.db* ]]; then
      check "$(cat "$c/opt/bambuddy/$path" 2> /dev/null || true)" 'saved database' "$app/$variant $path consumer"
    else
      check "$(cat "$c/opt/bambuddy/$path/state.db" 2> /dev/null || true)" "saved $path" "$app/$variant $path consumer"
    fi
  done
  for path in -wal -shm -journal; do check "$(cat "$c/opt/bambuddy/custom data/state.db$path" 2> /dev/null || true)" 'saved sidecar' "$app/$variant configured database $path consumer"; done
  : > "$c/inodes-after"
  for path in .env "${paths[@]}"; do stat -c '%i %n' "$c/opt/bambuddy/$path" >> "$c/inodes-after" 2> /dev/null || true; done
  check "$(cat "$c/inodes-after")" "$(cat "$c/inodes")" "$app/$variant persistent roots stay in place"
}
runtime_hooks_assert() {
  if [[ "$variant" == missing ]]; then
    check "$(stat -c %s "$c/services")" 0 "$app missing installation has no service effects"
    check "$(stat -c %s "$c/downloads")" 0 "$app missing installation has no deployment"
    return
  fi
  bambuddy_preservation_assert
  if [[ "$variant" == checker || "$variant" == no-update ]]; then
    check "$(stat -c %s "$c/services")" 0 "$app/$variant no service effects"
    check "$(stat -c %s "$c/downloads")" 0 "$app/$variant no deployment"
    check "$(cat "$c/opt/bambuddy/revision")" 'old source' "$app/$variant old source retained"
  else
    check "$(cat "$c/opt/bambuddy/revision")" 'selected source' "$app/$variant selected source consumer"
    check "$(cat "$c/opt/bambuddy/spoolbuddy/daemon/revision")" 'selected daemon' "$app/$variant source beside persistent SSH keys updates"
    check "$(grep -c 'v9.0.0' "$c/downloads" || true)" 0 "$app/$variant selected release retained"
  fi
}
runtime_hooks_retry_assert() { bambuddy_preservation_assert; }
runtime_hooks_retry_needed() { [[ "$variant" != missing && "$role" == update && "$expected" != 0 ]]; }
runtime_hooks_main "$@"
