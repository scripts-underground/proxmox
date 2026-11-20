#!/usr/bin/env bash
# shellcheck disable=SC2034,SC2154
set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/../lib/runtime-hooks/harness.sh"
app=komodo script_type=addon
runtime_hooks_observed_commands=(docker)
variants=(fresh ferret-install old-compose download validation env-publish-failure publish-failure update legacy-single legacy-credentials native-legacy native-current native-empty ambiguous stale-selection pull-failure uninstall down-failure)
hook_paths=()
runtime_hooks_variant() {
  case "$variant" in
    ferret-install) role=install ;;
    download) role=install fault=download ;;
    old-compose | validation | env-publish-failure | publish-failure) role=install fault=$variant ;;
    legacy-credentials) fault=legacy-credentials ;;
    native-legacy | native-current | native-empty) fault=$variant ;;
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
    if [[ "$variant" == legacy-credentials ]]; then
      sed -i 's/KOMODO_DATABASE_/KOMODO_DB_/g' "$c/external/private env"
      printf '{"services":{"core":{"image":"test:2","environment":{"USER":"${KOMODO_DB_USERNAME:?required}","PASSWORD":"${KOMODO_DB_PASSWORD:?required}"}}}}\n' > "$c/opt/komodo/ferretdb.compose.yaml"
    fi
    case "$variant" in
      native-legacy | native-current | native-empty)
        printf "export KOMODO_DB_USERNAME = 'legacy-user'\nexport KOMODO_DB_PASSWORD = 'literal\$password'\n" > "$c/external/private env"
        if [[ "$variant" != native-legacy ]]; then
          printf 'KOMODO_DB_USERNAME=legacy-user\nKOMODO_DB_PASSWORD=legacy-secret\n' > "$c/external/private env"
        fi
        if [[ "$variant" == native-current ]]; then
          printf "export KOMODO_DATABASE_USERNAME = 'chosen'\nexport KOMODO_DATABASE_PASSWORD = 'chosen-secret'\n" >> "$c/external/private env"
        elif [[ "$variant" == native-empty ]]; then
          printf "export KOMODO_DATABASE_USERNAME = ''\nexport KOMODO_DATABASE_PASSWORD = ''\n" >> "$c/external/private env"
        fi
        printf 'PERIPHERY_CORE_PUBLIC_KEYS=file:/operator/key.pub\nCOMPOSE_KOMODO_BACKUPS_PATH=/operator/backups\n' >> "$c/external/private env"
        cp "$c/external/private env" "$c/original-env"
        ;;
    esac
  fi
  [[ "$variant" != ferret-install ]] || printf '2\n' > "$c/stdin"
  : > "$c/docker"
  : > "$c/downloads"
}
runtime_hooks_model() {
  mv() {
    [[ "$APP_FAULT" != publish-failure || "${!#}" != "$var_addon_install_path/$DB_COMPOSE_FILE" ]] || return 41
    command mv "$@"
  }
  ln() {
    [[ "$APP_FAULT" != env-publish-failure || "${!#}" != "$var_addon_compose_env" ]] || return 42
    [[ "$APP_FAULT" != publish-failure || "${!#}" != "$var_addon_install_path/$DB_COMPOSE_FILE" ]] || return 41
    command ln "$@"
  }
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
      [[ ! -f "$c/template-migration" ]] || printf 'KOMODO_PASSKEY=old\n' >> "$out"
    else
      printf '{"services":{"core":{"image":"ghcr.io/moghtech/komodo-core:${COMPOSE_KOMODO_IMAGE_TAG:-2}","ports":[{"target":9120,"published":"9120"}],"env_file":[{"path":"/opt/komodo/compose.env","required":true}],"volumes":[{"source":"${COMPOSE_KOMODO_BACKUPS_PATH}","target":"/backups","type":"volume","volume":{}}]},"periphery":{"volumes":[{"source":"${PERIPHERY_ROOT_DIRECTORY:-/etc/komodo}","target":"${PERIPHERY_ROOT_DIRECTORY:-/etc/komodo}","type":"volume","volume":{}}]}}}\n' > "$out"
    fi
    [[ "$APP_FAULT" != download ]] || return 22
  }
  docker() {
    printf '%s\n' "$*" >> "$c/docker"
    local selected_env='' previous='' argument
    for argument in "$@"; do
      [[ "$previous" != --env-file ]] || selected_env=$argument
      previous=$argument
    done
    if [[ " $* " == *' pull '* || " $* " == *' up '* || " $* " == *' down '* ]]; then
      [[ "$selected_env" == "$var_addon_compose_env" && -f "$selected_env" ]] || return 65
      sha256sum "$selected_env" >> "$c/env-consumers"
    fi
    if [[ "$*" == 'compose config --help' ]]; then
      [[ "$APP_FAULT" == old-compose ]] || printf '      --no-env-resolution  Retain env_file\n      --no-interpolate  Retain expressions\n      --no-path-resolution  Retain relative paths\n'
      return 0
    fi
    [[ "$APP_FAULT" != old-compose || " $* " != *' --no-env-resolution '* ]] || return 16
    [[ "$APP_FAULT" != validation || "$*" != *'config -q'* ]] || return 49
    if [[ "$APP_FAULT" == legacy-credentials && " $* " == *' pull '* ]]; then
      grep '^KOMODO_DB_' "$selected_env" > "$c/consumed-credentials"
      [[ "$(wc -l < "$c/consumed-credentials")" == 2 ]] || return 49
    fi
    [[ "$APP_FAULT" != pull || " $* " != *' pull '* ]] || return 47
    [[ "$APP_FAULT" != down || " $* " != *' down '* ]] || return 48
    if [[ "$*" == *'config --format json'* && "$*" == *'/probe.json '* ]]; then
      # Effective-key parser effects are modeled here; native grammar, aliases
      # and literal values are independently checked against Compose itself.
      if [[ "$APP_FAULT" == legacy-credentials || "$APP_FAULT" == native-legacy ]]; then
        printf '%s\n' '{"services":{"probe":{"environment":{"KOMODO_DB_USERNAME":"present","KOMODO_DB_PASSWORD":"present","KOMODO_DATABASE_USERNAME":"","KOMODO_DATABASE_PASSWORD":""}}}}'
      else
        printf '%s\n' '{"services":{"probe":{"environment":{"KOMODO_DB_USERNAME":"","KOMODO_DB_PASSWORD":"","KOMODO_DATABASE_USERNAME":"present","KOMODO_DATABASE_PASSWORD":"present"}}}}'
      fi
    elif [[ "$*" == *'config --no-interpolate --no-env-resolution --no-path-resolution --format json'* ]]; then
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
    old-compose) expected=69 ;;
    validation) expected=49 ;;
    publish-failure) expected=41 ;;
    env-publish-failure) expected=42 ;;
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
  elif [[ "$role" == install ]]; then
    check "$(test -e "$c/external/private env" && printf present || printf absent)" absent "$app incomplete environment is not live"
    check "$(test -e "$c/opt/komodo/mongo.compose.yaml" && printf present || printf absent)" absent "$app incomplete compose is not live"
    check "$(test -e "$c/opt/komodo/.komodo-compose" && printf present || printf absent)" absent "$app incomplete selection is not live"
  elif [[ "$variant" == native-current || "$variant" == native-empty ]]; then
    check "$(cmp -s "$c/original-env" "$c/external/private env" && printf preserved || printf changed)" preserved "$app/$variant effective explicit current assignments remain byte-identical"
  elif [[ "$variant" == native-legacy ]]; then
    check "$(grep '^KOMODO_DATABASE_' "$c/external/private env" || true)" $'KOMODO_DATABASE_USERNAME=${KOMODO_DB_USERNAME}\nKOMODO_DATABASE_PASSWORD=${KOMODO_DB_PASSWORD}' "$app native effective legacy keys acquire literal aliases"
    check "$(head -c "$(stat -c %s "$c/original-env")" "$c/external/private env" | cmp -s "$c/original-env" - && printf preserved || printf changed)" preserved "$app preserves original export/space assignments"
  elif [[ "$variant" == legacy-credentials ]]; then
    check "$(cat "$c/consumed-credentials" 2> /dev/null || true)" $'KOMODO_DB_USERNAME=operator\nKOMODO_DB_PASSWORD=literal-secret' "$app retained compose consumes exact legacy credentials"
    check "$(grep '^KOMODO_DATABASE_' "$c/external/private env" || true)" $'KOMODO_DATABASE_USERNAME=${KOMODO_DB_USERNAME}\nKOMODO_DATABASE_PASSWORD=${KOMODO_DB_PASSWORD}' "$app native aliases retain legacy credential semantics"
  elif [[ "$variant" != uninstall ]]; then
    check "$(cat "$c/opt/komodo/mongo.compose.yaml" 2> /dev/null || true)" 'operator mongo' "$app/$variant retains unselected compose"
    [[ "$variant" == legacy-single ]] || check "$(cat "$c/opt/komodo/ferretdb.compose.yaml" 2> /dev/null || true)" 'operator ferret' "$app/$variant retains selected operator compose"
    check "$(stat -c %s "$c/downloads")" 0 "$app/$variant does not redownload operator compose"
  fi
  if [[ "$role" != install && "$variant" != ambiguous && "$variant" != stale-selection ]]; then
    runtime_hooks_compose_assert "/opt/komodo/$selected" "$c/external/private env" "$([[ "$variant" == update || "$variant" == legacy-single || "$variant" == legacy-credentials || "$variant" == native-* ]] && printf 2 || printf 1)"
    check "$(grep -Fc -- "-f /opt/komodo/$selected" "$c/docker" || true)" "$([[ "$variant" == update || "$variant" == legacy-single || "$variant" == legacy-credentials || "$variant" == native-* ]] && printf 2 || printf 1)" "$app/$variant every app operation uses selected compose"
  fi
  if [[ "$role" != install && "$variant" != legacy-credentials && "$variant" != native-* ]]; then
    check "$(cat "$c/external/private env")" $'COMPOSE_KOMODO_IMAGE_TAG=2\nCOMPOSE_KOMODO_BACKUPS_PATH=/operator/backups\nKOMODO_DATABASE_USERNAME=operator\nKOMODO_DATABASE_PASSWORD=literal-secret\nPERIPHERY_CORE_PUBLIC_KEYS=file:/operator/key.pub' "$app/$variant retains complete existing credential environment"
  fi
}
runtime_hooks_retry_needed() { return 1; }
runtime_hooks_more_cases() {
  local kind status first_env first_command
  for kind in owned updated edited replaced failed-down; do
    mode=no variant=fresh role=install fault=none
    c="$work/env-custody-$kind"
    mkdir -p "$c/"{opt,local/bin,cache,state,home,etc/systemd/system,payload,external,root}
    : > "$c/services"
    runtime_hooks_setup
    [[ "$kind" != updated ]] || : > "$c/template-migration"
    runtime_hooks_prepare
    status=0
    runtime_hooks_invoke install none "$c/install-output" "$c/install.log" "$c/install-errors.log" || status=$?
    check "$status" 0 "$app/$kind owned-env source-generated install succeeds"
    first_env=$(sha256sum "$c/external/private env")
    first_command=$(sha256sum "$c/local/sbin/uninstall")
    case "$kind" in
      updated)
        status=0
        runtime_hooks_invoke update none "$c/update-output" "$c/update.log" "$c/update-errors.log" || status=$?
        check "$status" 0 "$app own migration completes on generated external env"
        check "$(grep -c '^KOMODO_PASSKEY=' "$c/external/private env" || true)" 0 "$app own migration removes deprecated key"
        ;;
      edited) printf '# operator edit\n' >> "$c/external/private env" ;;
      replaced)
        rm "$c/external/private env"
        printf 'operator replacement\n' > "$c/external/private env"
        ;;
    esac
    if [[ "$kind" == failed-down ]]; then
      status=0
      runtime_hooks_invoke uninstall down "$c/failed-output" "$c/failed.log" "$c/failed-errors.log" || status=$?
      check "$status" 48 "$app failed down preserves exact status"
      check "$(sha256sum "$c/external/private env")" "$first_env" "$app failed down retains selected external env"
      check "$(sha256sum "$c/local/sbin/uninstall")" "$first_command" "$app failed down retains frozen uninstall"
      check "$(test -f "$c/addon-owned-files/komodo" && printf retained || printf absent)" retained "$app failed down retains external file custody"
    fi
    first_env=$(sha256sum "$c/external/private env")
    status=0
    runtime_hooks_invoke uninstall none "$c/uninstall-output" "$c/uninstall.log" "$c/uninstall-errors.log" || status=$?
    check "$status" 0 "$app/$kind cold uninstall succeeds"
    case "$kind" in
      edited | replaced)
        check "$(sha256sum "$c/external/private env" 2> /dev/null || true)" "$first_env" "$app/$kind preserves changed external env"
        ;;
      *) check "$(test -e "$c/external/private env" && printf present || printf absent)" absent "$app/$kind removes exact generated external env" ;;
    esac
    check "$(test -e "$c/addon-owned-files/komodo" && printf present || printf absent)" absent "$app/$kind retires handled external file receipt"
    role=uninstall rc=$status
    runtime_hooks_uninstall_assert
    if [[ "$kind" == owned ]]; then
      # A new source invocation, not a refreshed old command, must install at
      # the same selected external filename after successful owned teardown.
      rm "$c/generated"
      status=0
      runtime_hooks_invoke install none "$c/reinstall-output" "$c/reinstall.log" "$c/reinstall-errors.log" || status=$?
      check "$status" 0 "$app owned external env does not strand the next installation"
    fi
  done
}
runtime_hooks_main "$@"
