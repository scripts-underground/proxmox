#!/usr/bin/env bash
# shellcheck disable=SC2034,SC2154
set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/../lib/runtime-hooks/harness.sh"
app=komodo script_type=addon
variants=(fresh ferret-install download update legacy-single ambiguous stale-selection pull-failure uninstall down-failure)
hook_paths=()
runtime_hooks_variant() {
  case "$variant" in
    ferret-install) role=install ;;
    download) role=install fault=download ;;
    uninstall) role=uninstall ;;
    down-failure) role=uninstall fault=down ;;
    pull-failure) fault=pull ;;
  esac
}
runtime_hooks_setup() {
  mkdir -p "$c/opt/komodo"
  printf 'var_addon_compose_env=%q\nvar_addon_default_port=19120\n' "$c/external/private env" > "$c/context.sh"
  if [[ "$role" != install ]]; then
    printf 'operator mongo\n' > "$c/opt/komodo/mongo.compose.yaml"
    printf 'COMPOSE_KOMODO_IMAGE_TAG=2\nCOMPOSE_KOMODO_BACKUPS_PATH=/operator/backups\nKOMODO_DATABASE_USERNAME=operator\nKOMODO_DATABASE_PASSWORD=literal-secret\nPERIPHERY_CORE_PUBLIC_KEYS=file:/operator/key.pub\n' > "$c/external/private env"
    if [[ "$variant" != legacy-single ]]; then
      printf 'operator ferret\n' > "$c/opt/komodo/ferretdb.compose.yaml"
    fi
    case "$variant" in
      ambiguous | legacy-single) ;;
      stale-selection) printf 'missing.compose.yaml\n' > "$c/opt/komodo/.komodo-compose" ;;
      *) printf 'ferretdb.compose.yaml\n' > "$c/opt/komodo/.komodo-compose" ;;
    esac
    chmod 600 "$c/external/private env"
  fi
  [[ "$variant" != ferret-install ]] || printf '2\n' > "$c/stdin"
  : > "$c/docker"
  : > "$c/downloads"
}
runtime_hooks_model() {
  curl() {
    local out='' url=''
    while (($#)); do
      case "$1" in -o)
        out=$2
        shift
        ;;
      https:*) url=$1 ;; esac
      shift
    done
    printf '%s\n' "$url" >> "$c/downloads"
    if [[ "$url" == */compose.env ]]; then
      printf 'COMPOSE_KOMODO_IMAGE_TAG=2\nCOMPOSE_KOMODO_BACKUPS_PATH=/etc/komodo/backups\nKOMODO_DATABASE_USERNAME=admin\nKOMODO_DATABASE_PASSWORD=admin\nKOMODO_INIT_ADMIN_PASSWORD=changeme\nKOMODO_WEBHOOK_SECRET=old\nKOMODO_JWT_SECRET=old\nPERIPHERY_CORE_PUBLIC_KEYS=file:/config/keys/core.pub\n' > "$out"
    else
      printf '{"services":{"core":{"image":"ghcr.io/moghtech/komodo-core:${COMPOSE_KOMODO_IMAGE_TAG:-2}","ports":[{"target":9120,"published":"9120"}],"env_file":[{"path":"/opt/komodo/compose.env","required":true}],"volumes":[{"source":"${COMPOSE_KOMODO_BACKUPS_PATH}","target":"/backups","type":"volume","volume":{}}]},"periphery":{"volumes":[{"source":"${PERIPHERY_ROOT_DIRECTORY:-/etc/komodo}","target":"${PERIPHERY_ROOT_DIRECTORY:-/etc/komodo}","type":"volume","volume":{}}]}}}\n' > "$out"
    fi
    [[ "$APP_FAULT" != download ]] || return 22
  }
  docker() {
    printf '%s\n' "$*" >> "$c/docker"
    [[ "$APP_FAULT" != pull || " $* " != *' pull '* ]] || return 47
    [[ "$APP_FAULT" != down || " $* " != *' down '* ]] || return 48
    if [[ "$*" == *'config --no-interpolate --no-env-resolution --format json'* ]]; then
      local file=''
      while (($#)); do
        [[ "$1" != -f ]] || {
          file=$2
          shift
        }
        shift
      done
      # The harness maps /etc defaults inside the hook's literal match as well
      # as the modeled Compose input. Keep this output on the same fixture path.
      jq --arg root "$c/etc/komodo" '
        .services.periphery.volumes[0].source = ("${PERIPHERY_ROOT_DIRECTORY:-" + $root + "}") |
        .services.periphery.volumes[0].target = ("${PERIPHERY_ROOT_DIRECTORY:-" + $root + "}")
      ' "$file"
    fi
  }
}
runtime_hooks_expected() {
  case "$variant" in
    ambiguous | stale-selection) expected=233 ;;
    download) expected=22 ;;
    pull-failure) expected=47 ;;
    down-failure) expected=48 ;;
  esac
}
runtime_hooks_assert() {
  local selected=ferretdb.compose.yaml
  [[ "$variant" != fresh && "$variant" != legacy-single ]] || selected=mongo.compose.yaml
  if [[ "$role" == install && "$rc" == 0 ]]; then
    check "$(cat "$c/opt/komodo/.komodo-compose" 2> /dev/null || true)" "$selected" "$app/$variant persists database compose choice as data"
    check "$(stat -c %a "$c/external/private env")" 600 "$app/$variant fresh environment is private"
    check "$(stat -c %a "$c/home/komodo.creds")" 600 "$app/$variant fresh saved credentials are private"
    check "$(jq -r '.services.core.ports[0].published' "$c/opt/komodo/$selected" 2> /dev/null || true)" 19120 "$app/$variant actual compose receives configured host port"
    check "$(jq -r '.services.core.env_file[0].path' "$c/opt/komodo/$selected" 2> /dev/null || true)" "$c/external/private env" "$app/$variant runtime env_file uses configured path"
    check "$(jq -r '.services.periphery.volumes[0].type' "$c/opt/komodo/$selected" 2> /dev/null || true)" bind "$app/$variant variable host directory remains a bind"
    check "$(jq -r '.services.core.volumes[0].source' "$c/opt/komodo/$selected" 2> /dev/null || true)" '${COMPOSE_KOMODO_BACKUPS_PATH}' "$app/$variant backup directory interpolation remains operator-owned"
  elif [[ "$variant" == ambiguous || "$variant" == stale-selection ]]; then
    check "$(stat -c %s "$c/docker")" 0 "$app/$variant no Docker effects without a proven selection"
    check "$(stat -c %s "$c/downloads")" 0 "$app/$variant never overwrites a candidate"
  elif [[ "$variant" == download ]]; then
    check "$(test -e "$c/external/private env" && printf present || printf absent)" absent "$app incomplete environment is not live"
  elif [[ "$variant" != uninstall ]]; then
    check "$(cat "$c/opt/komodo/mongo.compose.yaml" 2> /dev/null || true)" 'operator mongo' "$app/$variant retains unselected compose"
    [[ "$variant" == legacy-single ]] || check "$(cat "$c/opt/komodo/ferretdb.compose.yaml" 2> /dev/null || true)" 'operator ferret' "$app/$variant retains selected operator compose"
    check "$(stat -c %s "$c/downloads")" 0 "$app/$variant does not redownload operator compose"
  fi
  if [[ "$role" != install && "$variant" != ambiguous && "$variant" != stale-selection ]]; then
    check "$(grep -Fc -- "-f /opt/komodo/$selected" "$c/docker" || true)" "$([[ "$variant" == update || "$variant" == legacy-single ]] && printf 2 || printf 1)" "$app/$variant every operation uses selected compose"
  fi
  if [[ "$role" != install ]]; then
    check "$(cat "$c/external/private env")" $'COMPOSE_KOMODO_IMAGE_TAG=2\nCOMPOSE_KOMODO_BACKUPS_PATH=/operator/backups\nKOMODO_DATABASE_USERNAME=operator\nKOMODO_DATABASE_PASSWORD=literal-secret\nPERIPHERY_CORE_PUBLIC_KEYS=file:/operator/key.pub' "$app/$variant retains complete existing credential environment"
  fi
}
runtime_hooks_retry_needed() { return 1; }
runtime_hooks_main "$@"
