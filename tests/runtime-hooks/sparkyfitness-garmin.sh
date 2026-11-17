#!/usr/bin/env bash
# shellcheck disable=SC2034,SC2154
set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/../lib/runtime-hooks/addon-release.sh"
app=sparkyfitness-garmin
release_app=$app release_mode=tarball release_asset=unused.tar.gz
variants+=(stop download build fresh uninstall)
runtime_hooks_variant() { case "$variant" in checker) fault=checker ;; stop) fault=stop ;; uninstall) role=uninstall ;; esac }
addon_release_setup() {
  local app_root="$c/opt/$app"
  if [[ "$role" == install ]]; then
    mkdir -p "$c/opt/sparkyfitness" "$c/payload/SparkyFitnessGarmin" "$c/payload/docker"
    printf 'GARMIN_MICROSERVICE_URL=default\n' > "$c/payload/docker/.env.example"
    printf 'var_addon_config_path=%q\nvar_addon_service_path=%q\n' "/opt/$app/operator config/.env" "$c/etc/systemd/system/operator-garmin.service" > "$c/context.sh"
    return
  fi
  mkdir -p "$c/payload/SparkyFitnessGarmin/"{mock_data,.venv/bin} "$app_root/SparkyFitnessGarmin/"{mock_data,.venv/bin} "$app_root/operator config" "$app_root/operator extra"
  printf '{"capture":"operator saved range"}\n' > "$app_root/SparkyFitnessGarmin/mock_data/range capture.json"
  printf 'archive default\n' > "$c/payload/SparkyFitnessGarmin/mock_data/range capture.json"
  printf '#!/usr/bin/env bash\nprintf "existing runtime\\n"\n' > "$app_root/SparkyFitnessGarmin/.venv/bin/python3"
  chmod +x "$app_root/SparkyFitnessGarmin/.venv/bin/python3"
  printf 'operator environment\n' > "$app_root/operator config/.env"
  printf 'operator inherited keep\n' > "$app_root/operator extra/data"
  chmod 0600 "$app_root/operator config/.env" "$app_root/SparkyFitnessGarmin/mock_data/range capture.json"
  stat -c %i "$app_root/SparkyFitnessGarmin/mock_data" > "$c/capture-inode"
  stat -c %i "$app_root/SparkyFitnessGarmin/.venv" > "$c/venv-inode"
  printf 'operator unit\n' > "$c/etc/systemd/system/operator-garmin.service"
  printf 'var_addon_config_path=%q\nvar_addon_service_path=%q\n' "/opt/$app/operator config/.env" "$c/etc/systemd/system/operator-garmin.service" > "$c/context.sh"
}
addon_release_consumer_assert() { check "$(cat "$c/opt/$app/code")" 'new code' "$app selected source consumer"; }
eval "$(declare -f runtime_hooks_assert | sed '1s/runtime_hooks_assert/garmin_release_assert/')"
runtime_hooks_model() {
  addon_release_model
  CLEAN_INSTALL_KEEP_PATHS=('operator extra')
  curl_download() {
    [[ "$APP_FAULT" != download ]] || return 22
    addon_release_download "$@"
  }
  uv() {
    printf '%s\n' "$*" >> "$c/uv-calls"
    if [[ "$1" == venv ]]; then
      if [[ " $* " == *' --clear '* ]]; then rm -rf .venv; fi
      mkdir -p .venv/bin
      printf '#!/usr/bin/env bash\nprintf "new runtime\\n"\n' > .venv/bin/python3
      chmod +x .venv/bin/python3
    fi
    [[ "$APP_FAULT" != build || "$1" != pip ]] || return 52
  }
  systemctl() {
    printf '%s\n' "$*" >> "$c/services"
    if [[ "$1" == show ]]; then printf 'LoadState=loaded\nActiveState=active\nUnitFileState=enabled\n'; fi
    [[ "$APP_FAULT" != stop || "$1" != stop ]] || return 31
    if [[ "$1" == start ]]; then
      python3 - "$var_addon_install_path/SparkyFitnessGarmin/mock_data/range capture.json" "$c/running-capture" << 'PY'
import json,sys
from pathlib import Path
Path(sys.argv[2]).write_text(json.loads(Path(sys.argv[1]).read_text())['capture'])
PY
    fi
  }
}
runtime_hooks_expected() { case "$fault" in checker) expected=17 ;; stop) expected=31 ;; esac }
runtime_hooks_assert() {
  if [[ "$role" == install ]]; then
    check "$(grep -c '^enable -q --now operator-garmin.service$' "$c/services" || true)" 1 "$app fresh install enables the configured unit"
    check "$(grep -c '^EnvironmentFile=".*operator config/.env"$' "$c/etc/systemd/system/operator-garmin.service" || true)" 1 "$app fresh installed unit uses configured environment"
    return
  elif [[ "$role" == uninstall ]]; then
    check "$(grep -c '^stop -- operator-garmin.service$' "$c/services" || true)" 1 "$app uninstall stops configured unit"
    check "$(test -e "$c/etc/systemd/system/operator-garmin.service" && printf present || printf absent)" absent "$app uninstall retires configured unit file"
    check "$(test -e "$c/opt/$app" && printf present || printf absent)" absent "$app uninstall retires owned source and data"
    return
  fi
  if [[ "$variant" == checker || "$variant" == no-update || "$variant" == selected ]]; then garmin_release_assert; fi
  local app_root="$c/opt/$app"
  check "$(cat "$app_root/operator config/.env" 2> /dev/null || true)" 'operator environment' "$app/$variant in-tree configuration stays live"
  check "$(cat "$app_root/operator extra/data" 2> /dev/null || true)" 'operator inherited keep' "$app/$variant inherited literal keep retained"
  check "$(cat "$app_root/SparkyFitnessGarmin/mock_data/range capture.json" 2> /dev/null || true)" '{"capture":"operator saved range"}' "$app/$variant saved provider capture retained instead of archive defaults"
  check "$(stat -c %i "$app_root/SparkyFitnessGarmin/mock_data" 2> /dev/null || true)" "$(cat "$c/capture-inode")" "$app/$variant capture directory inode retained"
  check "$(stat -c %i "$app_root/SparkyFitnessGarmin/.venv" 2> /dev/null || true)" "$(cat "$c/venv-inode")" "$app/$variant runtime directory inode retained"
  check "$({ "$app_root/SparkyFitnessGarmin/.venv/bin/python3" || true; } 2> /dev/null)" 'existing runtime' "$app/$variant existing interpreter consumer retained"
  check "$(cat "$c/etc/systemd/system/operator-garmin.service")" 'operator unit' "$app/$variant existing unit retained"
  if [[ "$fault" == stop ]]; then
    check "$(stat -c %s "$c/downloads")" 0 "$app failed stop prevents source replacement"
  elif [[ "$expected" == 0 && "$variant" != no-update ]]; then
    check "$(cat "$c/running-capture" 2> /dev/null || true)" 'operator saved range' "$app service consumer reads saved capture after update"
    check "$(grep -c '^start operator-garmin.service$' "$c/services" || true)" 1 "$app service control follows configured unit path"
  fi
}
runtime_hooks_retry_assert() {
  addon_release_consumer_assert
  check "$(cat "$c/running-capture" 2> /dev/null || true)" 'operator saved range' "$app pending retry retains capture at running consumer"
  check "$({ "$c/opt/$app/SparkyFitnessGarmin/.venv/bin/python3" || true; } 2> /dev/null)" 'existing runtime' "$app pending retry retains existing interpreter"
}
runtime_hooks_main "$@"
