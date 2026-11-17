#!/usr/bin/env bash
# shellcheck disable=SC2034,SC2154
set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/../lib/runtime-hooks/harness.sh"
app=portainer script_type=addon
variants=(fresh occupied download invalid-port update pull-failure missing uninstall down-failure)
hook_paths=()
runtime_hooks_variant() {
  case "$variant" in
    occupied | invalid-port) role=install fault=$variant ;;
    download) role=install fault=download ;;
    pull-failure) fault=pull ;;
    uninstall) role=uninstall ;;
    down-failure) role=uninstall fault=down ;;
  esac
}
runtime_hooks_setup() {
  mkdir -p "$c/opt/portainer" "$c/external/selected files"
  printf 'var_addon_compose_file=%q\nvar_addon_default_port=%q\n' "$c/external/selected files/stack.json" "$([[ "$variant" == invalid-port ]] && printf invalid || printf 19443)" > "$c/context.sh"
  if [[ "$role" != install || "$variant" == occupied ]]; then
    printf '{"services":{"portainer":{"image":"operator-portainer","ports":[{"target":9443,"published":"19443"},{"target":8000,"published":"18000"}]}}}\n' > "$c/external/selected files/stack.json"
  fi
  [[ "$variant" != missing ]] || rm "$c/external/selected files/stack.json"
  printf 'foreign compose\n' > "$c/external/selected files/foreign.yaml"
  if [[ "$variant" != fresh && "$variant" != download ]]; then
    printf 'operator unit\n' > "$c/etc/systemd/system/portainer.service"
  fi
  : > "$c/docker"
}
runtime_hooks_model() {
  curl() {
    local out=''
    while (($#)); do
      [[ "$1" != -o ]] || {
        out=$2
        shift
      }
      shift
    done
    printf '{"services":{"portainer":{"image":"portainer/portainer-ce:sts","ports":[{"target":9443,"published":"9443"},{"target":8000,"published":"8000"}]}}}\n' > "$out"
    [[ "$APP_FAULT" != download ]] || return 22
  }
  docker() {
    printf '%s\n' "$*" >> "$c/docker"
    [[ "$1 ${2:-}" != 'container inspect' ]] || return 1
    [[ "$APP_FAULT" != pull || " $* " != *' pull '* ]] || return 47
    [[ "$APP_FAULT" != down || " $* " != *' down '* ]] || return 48
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
    occupied | invalid-port) expected=65 ;;
    download) expected=22 ;;
    missing) expected=1 ;;
    pull-failure) expected=47 ;;
    down-failure) expected=48 ;;
  esac
}
runtime_hooks_assert() {
  local file="$c/external/selected files/stack.json"
  if [[ "$variant" == fresh ]]; then
    check "$(jq -r '.services.portainer.ports[] | select(.target==9443) | .published' "$file" 2> /dev/null || true)" 19443 "$app fresh consumer receives configured HTTPS port"
    check "$(jq -r '.services.portainer.ports[] | select(.target==8000) | .published' "$file" 2> /dev/null || true)" 8000 "$app preserves independent edge-agent port"
    check "$(grep -Fc -- "-f \"$file\"" "$c/etc/systemd/system/portainer.service" || true)" 2 "$app unit start and stop select configured compose file"
  elif [[ "$variant" == occupied || "$variant" == update || "$variant" == pull-failure || "$variant" == down-failure ]]; then
    check "$(jq -r '.services.portainer.image' "$file" 2> /dev/null || true)" operator-portainer "$app/$variant retains operator compose"
  fi
  case "$variant" in
    occupied | invalid-port) check "$(stat -c %s "$c/docker")" 0 "$app/$variant refuses before Docker effects" ;;
    download) check "$(test -e "$file" && printf present || printf absent)" absent "$app incomplete download never publishes live compose" ;;
    update | pull-failure | uninstall | down-failure)
      check "$(grep -Fc -- "-f $file" "$c/docker" || true)" "$([[ "$variant" == update ]] && printf 2 || printf 1)" "$app/$variant all app compose calls use selected file"
      ;;
  esac
  if [[ "$expected" != 0 ]]; then
    check "$(cat "$c/etc/systemd/system/portainer.service" 2> /dev/null || true)" "$([[ "$variant" != download ]] && printf 'operator unit' || true)" "$app/$variant preserves unit until required operation succeeds"
  fi
  check "$(cat "$c/external/selected files/foreign.yaml")" 'foreign compose' "$app/$variant leaves unrelated external files intact"
  if [[ "$variant" == uninstall ]]; then
    check "$(test -e "$file" && printf present || printf absent)" absent "$app retires only selected external compose after teardown"
  fi
  check "$(find "$c/external/selected files" -maxdepth 1 -name '.portainer-compose.*' | wc -l)" 0 "$app/$variant retires exact compose stage"
}
runtime_hooks_retry_needed() { return 1; }
runtime_hooks_main "$@"
