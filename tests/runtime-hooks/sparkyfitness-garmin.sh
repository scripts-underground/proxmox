#!/usr/bin/env bash
# shellcheck disable=SC2034,SC2154
set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/../lib/runtime-hooks/addon-release.sh"
app=sparkyfitness-garmin
runtime_hooks_observed_commands=(uv systemctl)
runtime_hooks_observe_recovery=1
release_app=$app release_mode=tarball release_asset=unused.tar.gz
variants+=(stop download build fresh uninstall stopped-download stopped-selected copy copy-unrestored pip-intact pip-partial inherited-venv)
runtime_hooks_variant() { case "$variant" in checker | stop | copy | copy-unrestored | pip-*) fault=$variant ;; stopped-download) fault=download ;; uninstall) role=uninstall ;; esac }
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
  if [[ "$role" == update ]]; then
    printf 'old dependency\n' > "$app_root/SparkyFitnessGarmin/.venv/dependency.py"
    if [[ "$variant" == pip-* ]]; then
      rm -rf "$c/payload"
      mkdir "$c/payload"
      command cp -a "$app_root/." "$c/payload/"
    fi
    local initial=active
    [[ "$variant" != stopped-* ]] || initial=inactive
    runtime_hooks_recovery_setup operator-garmin.service "$initial" "$app_root" "$c/etc/systemd/system/operator-garmin.service"
  fi
}
addon_release_consumer_assert() {
  local expected_code='new code'
  [[ "$variant" != pip-* ]] || expected_code='old code'
  check "$(cat "$c/opt/$app/code")" "$expected_code" "$app selected source consumer"
}
eval "$(declare -f runtime_hooks_assert | sed '1s/runtime_hooks_assert/garmin_release_assert/')"
runtime_hooks_model() {
  addon_release_model
  VIRTUAL_ENV="$c/unrelated-environment"
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
    if [[ "$1" == pip ]]; then
      local selected="$VIRTUAL_ENV/bin/python3" previous='' arg
      for arg in "$@"; do
        [[ "$previous" != --python ]] || selected=$arg
        previous=$arg
      done
      printf '%s\n' "$selected" > "$c/pip-interpreter"
      [[ "$APP_FAULT" != pip-intact ]] || return 52
      if [[ "$APP_FAULT" == pip-partial ]]; then
        printf 'partial dependency\n' > .venv/dependency.py
        return 52
      fi
    fi
    [[ "$APP_FAULT" != build || "$1" != pip ]] || return 52
  }
  cp() {
    if [[ "$APP_FAULT" == copy || "$APP_FAULT" == copy-unrestored ]] && [[ "$*" == *'/deploy-source.'* && "${!#}" == /opt/* ]]; then
      command cp "$@"
      [[ "$APP_FAULT" != copy-unrestored ]] || printf 'partial source\n' > /opt/sparkyfitness-garmin/partial-runtime
      return 41
    fi
    command cp "$@"
  }
  systemctl() {
    [[ "$APP_FAULT" != stop || "$1" != stop ]] || return 31
    if [[ -f "$c/recovery-service" ]]; then
      runtime_hooks_recovery_service "$@" || return $?
    else
      printf '%s\n' "$*" >> "$c/services"
      if [[ "$1" == show ]]; then printf 'LoadState=loaded\nActiveState=active\nUnitFileState=enabled\n'; fi
    fi
    if [[ "$1" == start ]]; then
      python3 - "$var_addon_install_path/SparkyFitnessGarmin/mock_data/range capture.json" "$c/running-capture" << 'PY'
import json,sys
from pathlib import Path
Path(sys.argv[2]).write_text(json.loads(Path(sys.argv[1]).read_text())['capture'])
PY
    fi
  }
}
runtime_hooks_expected() { case "$fault" in checker) expected=17 ;; stop) expected=31 ;; copy | copy-unrestored) expected=252 ;; pip-*) expected=52 ;; esac }
runtime_hooks_assert() {
  if [[ "$role" == install ]]; then
    check "$(grep -c '^enable -q --now operator-garmin.service$' "$c/services" || true)" 1 "$app fresh install enables the configured unit"
    check "$(grep -c '^EnvironmentFile=.*operator config/.env$' "$c/etc/systemd/system/operator-garmin.service" || true)" 1 "$app fresh installed unit uses native environment path grammar"
    check "$(cat "$c/pip-interpreter" 2> /dev/null || true)" "/opt/$app/SparkyFitnessGarmin/.venv/bin/python3" "$app fresh requirements target service interpreter"
    return
  elif [[ "$role" == uninstall ]]; then
    check "$(grep -c '^stop -- operator-garmin.service$' "$c/services" || true)" 1 "$app uninstall stops configured unit"
    check "$(test -e "$c/etc/systemd/system/operator-garmin.service" && printf present || printf absent)" absent "$app uninstall retires configured unit file"
    check "$(test -e "$c/opt/$app" && printf present || printf absent)" absent "$app uninstall retires owned source and data"
    return
  fi
  if [[ "$variant" == checker || "$variant" == no-update || "$variant" == selected ]]; then garmin_release_assert; fi
  if [[ "$rc" == 0 && "$variant" != no-update ]]; then
    check "$(cat "$c/pip-interpreter" 2> /dev/null || true)" "/opt/$app/SparkyFitnessGarmin/.venv/bin/python3" "$app requirements ignore inherited VIRTUAL_ENV"
  fi
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
  elif [[ "$variant" == stopped-selected ]]; then
    check "$(cat "$c/recovery-state")" inactive "$app successful update leaves initially stopped service stopped"
    check "$(wc -l < "$c/recovery-starts")" 0 "$app successful update never starts initially stopped service"
  elif [[ "$expected" == 0 && "$variant" != no-update ]]; then
    check "$(cat "$c/running-capture" 2> /dev/null || true)" 'operator saved range' "$app service consumer reads saved capture after update"
    check "$(grep -c '^start operator-garmin.service$' "$c/services" || true)" 1 "$app service control follows configured unit path"
  fi
}
runtime_hooks_retry_assert() {
  addon_release_consumer_assert
  if [[ "$variant" == stopped-download ]]; then
    check "$(cat "$c/recovery-state")" inactive "$app retry leaves initially stopped service stopped"
    check "$(wc -l < "$c/recovery-starts")" 0 "$app retry never starts initially stopped service"
  else
    check "$(cat "$c/recovery-state")" active "$app retry restores original active service"
    check "$(cat "$c/running-capture" 2> /dev/null || true)" 'operator saved range' "$app pending retry retains capture at running consumer"
  fi
  check "$({ "$c/opt/$app/SparkyFitnessGarmin/.venv/bin/python3" || true; } 2> /dev/null)" 'existing runtime' "$app pending retry retains existing interpreter"
}
runtime_hooks_deployment_assert() {
  [[ "$role" != uninstall && "$variant" != no-update ]] || return 0
  [[ "$role" == install ]] || addon_release_consumer_assert
  runtime_hooks_completed_assert uv /opt/sparkyfitness-garmin/SparkyFitnessGarmin pip install --python /opt/sparkyfitness-garmin/SparkyFitnessGarmin/.venv/bin/python3 -r requirements.txt
}
runtime_hooks_main "$@"
