#!/usr/bin/env bash
# shellcheck disable=SC2034,SC2154
set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/../lib/runtime-hooks/harness.sh"
app=arcane script_type=addon
variants=(fresh unsupported occupied invalid-port download env-download invalid-compose update pull-failure uninstall down-failure missing)
hook_paths=()
runtime_hooks_variant() {
  case "$variant" in
    unsupported | occupied | invalid-port | download | env-download | invalid-compose) role=install fault=$variant ;;
    pull-failure) fault=pull ;;
    uninstall) role=uninstall ;;
    down-failure) role=uninstall fault=down ;;
  esac
}
runtime_hooks_setup() {
  mkdir -p "$c/opt/arcane" "$c/external/selected files" "$c/etc/arcane/projects" "$c/etc/arcane/builds"
  printf 'var_addon_compose_file=%q\nvar_addon_env_file=%q\nvar_addon_default_port=%q\n' "$c/external/selected files/stack.json" "$c/external/selected files/private.env" "$([[ "$variant" == invalid-port ]] && printf invalid || printf 13552)" > "$c/context.sh"
  if [[ "$role" != install || "$variant" == occupied ]]; then
    printf '{"services":{"arcane":{"image":"operator-arcane"}}}\n' > "$c/external/selected files/stack.json"
    printf 'operator secret\n' > "$c/external/selected files/private.env"
  fi
  [[ "$variant" != missing ]] || rm "$c/external/selected files/stack.json"
  printf 'foreign compose\n' > "$c/external/selected files/foreign.yaml"
  printf 'operator project\n' > "$c/etc/arcane/projects/data"
  printf 'operator build\n' > "$c/etc/arcane/builds/data"
  : > "$c/docker"
  : > "$c/ownership"
  : > "$c/dependencies"
}
runtime_hooks_model() {
  [[ "$APP_FAULT" != unsupported ]] || OS_FAMILY=arch
  ensure_dependencies() { printf '%s\n' "$*" >> "$c/dependencies"; }
  chown() { printf '%s\n' "$*" >> "$c/ownership"; }
  curl() {
    local out='' url=''
    while (($#)); do
      case "$1" in
        -o)
          out=$2
          shift
          ;;
        https:*) url=$1 ;;
      esac
      shift
    done
    if [[ "$url" == *env.example ]]; then
      printf 'ARCANE_APP_URL=https://your-domain.com\nARCANE_ENCRYPTION_KEY=placeholder\nARCANE_PORT=3552\n' > "$out"
      [[ "$APP_FAULT" != env-download ]] || return 23
    else
      printf '{"services":{"arcane":{"image":"getarcaneapp/manager:latest","ports":[{"target":3552,"published":"3552"}],"environment":{"ARCANE_ENCRYPTION_KEY":"placeholder","ARCANE_PROJECTS_DIRECTORY":"/host/path/to/projects"},"volumes":[{"type":"bind","source":"/host/path/to/projects","target":"/host/path/to/projects"},{"type":"bind","source":"/host/path/to/builds","target":"/builds"}]}}}\n' > "$out"
      [[ "$APP_FAULT" != download ]] || return 22
    fi
  }
  docker() {
    printf '%s\n' "$*" >> "$c/docker"
    [[ "$1 ${2:-}" != 'container inspect' ]] || return 1
    [[ "$APP_FAULT" != pull || " $* " != *' pull '* ]] || return 47
    [[ "$APP_FAULT" != down || " $* " != *' down '* ]] || return 48
    [[ "$APP_FAULT" != invalid-compose || " $* " != *' config '* ]] || return 49
    if [[ "$*" == *'config --format json'* ]]; then
      local file=''
      while (($#)); do
        [[ "$1" != -f ]] || {
          file=$2
          shift
        }
        shift
      done
      cat "$file"
    fi
  }
}
runtime_hooks_expected() {
  case "$variant" in
    unsupported) expected=1 ;;
    occupied | invalid-port) expected=65 ;;
    download) expected=22 ;;
    env-download) expected=23 ;;
    missing) expected=1 ;;
    pull-failure) expected=47 ;;
    down-failure) expected=48 ;;
    invalid-compose) expected=49 ;;
  esac
}
runtime_hooks_assert() {
  local file="$c/external/selected files/stack.json" env="$c/external/selected files/private.env"
  if [[ "$variant" == fresh ]]; then
    check "$(jq -r '.services.arcane.ports[0].published' "$file" 2> /dev/null || true)" 13552 "$app fresh configured listener reaches compose consumer"
    check "$(sed -n 's/^ARCANE_ENCRYPTION_KEY=//p' "$env" | tr -d '\n' | wc -c)" 32 "$app fresh upstream encryption setting receives generated secret"
    check "$(jq -r '.services.arcane.environment.ARCANE_ENCRYPTION_KEY' "$file" 2> /dev/null || true)" '${ARCANE_ENCRYPTION_KEY}' "$app compose retains operator environment interpolation"
    check "$(stat -c %a "$file")" 600 "$app secret-bearing compose is private"
    check "$(stat -c %a "$env")" 600 "$app selected runtime environment is private"
    check "$(jq -r '.services.arcane.volumes[] | select(.target=="/builds") | .source' "$file" 2> /dev/null || true)" "$c/etc/arcane/builds" "$app selected build bind reaches compose consumer"
    check "$(jq -r '.services.arcane.environment.ARCANE_PROJECTS_DIRECTORY' "$file" 2> /dev/null || true)" "$c/etc/arcane/projects" "$app selected projects directory reaches runtime"
    check "$(jq -r '.services.arcane.env_file[0].path' "$file" 2> /dev/null || true)" "$env" "$app explicit environment reaches runtime, not only interpolation"
  fi
  case "$variant" in
    unsupported | occupied | invalid-port) check "$(stat -c %s "$c/docker")" 0 "$app/$variant refuses before Docker effects" ;;
    download | env-download | invalid-compose)
      check "$(test -e "$file" && printf present || printf absent)" absent "$app/$variant incomplete preparation never publishes compose"
      check "$(test -e "$env" && printf present || printf absent)" absent "$app/$variant incomplete preparation never publishes environment"
      ;;
    update | pull-failure | uninstall | down-failure)
      check "$(grep -Fc -- "-f $file" "$c/docker" || true)" "$([[ "$variant" == update ]] && printf 2 || printf 1)" "$app/$variant all compose operations select configured file"
      check "$(grep -Fc -- "--env-file $env" "$c/docker" || true)" "$([[ "$variant" == update ]] && printf 2 || printf 1)" "$app/$variant all compose operations select configured env"
      ;;
  esac
  if [[ "$role" != install && "$variant" != uninstall ]]; then
    check "$(stat -c %s "$c/ownership")" 0 "$app/$variant maintenance never recursively takes operator data ownership"
    check "$(cat "$env" 2> /dev/null || true)" 'operator secret' "$app/$variant retains operator environment"
  fi
  check "$(cat "$c/etc/arcane/projects/data")" 'operator project' "$app/$variant retains external project data"
  check "$(cat "$c/etc/arcane/builds/data")" 'operator build' "$app/$variant retains external build data"
  check "$(cat "$c/external/selected files/foreign.yaml")" 'foreign compose' "$app/$variant retains unrelated external file"
  if [[ "$variant" == uninstall ]]; then
    check "$(test -e "$file" && printf present || printf absent)" absent "$app successful teardown retires only selected compose"
    check "$(test -e "$env" && printf present || printf absent)" absent "$app successful teardown retires only selected environment"
  fi
  check "$(find "$c/external/selected files" -maxdepth 1 -name '.arcane-*' | wc -l)" 0 "$app/$variant retires exact preparation stages"
}
runtime_hooks_retry_needed() { return 1; }
runtime_hooks_main "$@"
