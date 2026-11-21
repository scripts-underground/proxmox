#!/usr/bin/env bash
# runtime-hooks-contract: addon intent-preserving
# shellcheck disable=SC2034,SC2154
set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/../lib/runtime-hooks/harness.sh"
app=portainer script_type=addon
runtime_hooks_observed_commands=(docker)
variants=(fresh occupied download invalid-port update pull-failure missing uninstall down-failure interrupted-down interrupted-manifest interrupted-footer foreign-root changed-after-down)
hook_paths=()
runtime_hooks_variant() {
  case "$variant" in
    occupied | invalid-port) role=install fault=$variant ;;
    download) role=install fault=download ;;
    pull-failure) fault=pull ;;
    uninstall) role=uninstall ;;
    down-failure) role=uninstall fault=down ;;
    interrupted-* | changed-after-down) role=uninstall fault=$variant ;;
    foreign-root) role=uninstall ;;
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
  : > "$c/down-events"
  [[ "$variant" != foreign-root ]] || printf 'unknown root data\n' > "$c/opt/portainer/operator-data"
}
runtime_hooks_model() {
  rm() {
    command rm "$@" || return $?
    if [[ "$APP_FAULT" == interrupted-manifest && " $* " == *" $c/external/selected files/stack.json "* ]]; then return 77; fi
  }
  svc_prepare_uninstall() {
    printf 'prepare %s\n' "$1" >> "$c/services"
    if [[ "$APP_FAULT" == interrupted-down || "$APP_FAULT" == changed-after-down ]]; then
      [[ "$APP_FAULT" != changed-after-down ]] || printf 'operator changed model\n' > "$c/external/selected files/stack.json"
      return 77
    fi
  }
  msg_ok() {
    if [[ "$APP_FAULT" == interrupted-footer && "$*" == *'has been uninstalled'* ]]; then return 77; fi
  }
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
    if [[ "$*" == 'compose config --help' ]]; then
      printf '      --no-env-resolution  Retain env_file\n      --no-interpolate  Retain expressions\n      --no-path-resolution  Retain relative paths\n'
      return 0
    fi
    [[ "$1 ${2:-}" != 'container inspect' ]] || return 1
    [[ "$APP_FAULT" != pull || " $* " != *' pull '* ]] || return 47
    [[ "$APP_FAULT" != down || " $* " != *' down '* ]] || return 48
    if [[ " $* " == *' down '* ]]; then
      [[ ! -s "$c/down-events" ]] || return 98
      printf 'completed\n' >> "$c/down-events"
    fi
    if [[ "$*" == *'--format json'* ]]; then
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
    interrupted-* | changed-after-down) expected=77 ;;
  esac
}
runtime_hooks_assert() {
  local file="$c/external/selected files/stack.json"
  if [[ "$variant" == fresh ]]; then
    for flag in --no-interpolate --no-env-resolution --no-path-resolution; do
      check "$(grep -Fc -- "$flag" "$c/docker" || true)" 1 "$app publication retains native source semantics: $flag"
    done
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
      runtime_hooks_compose_assert "$file" '' "$([[ "$variant" == update ]] && printf 2 || printf 1)"
      check "$(grep -Fc -- "-f $file" "$c/docker" || true)" "$([[ "$variant" == update ]] && printf 2 || printf 1)" "$app/$variant all app compose calls use selected file"
      ;;
  esac
  if [[ "$expected" != 0 && "$variant" != interrupted-manifest && "$variant" != interrupted-footer ]]; then
    check "$(cat "$c/etc/systemd/system/portainer.service" 2> /dev/null || true)" "$([[ "$variant" != download ]] && printf 'operator unit' || true)" "$app/$variant preserves unit until required operation succeeds"
  fi
  check "$(cat "$c/external/selected files/foreign.yaml")" 'foreign compose' "$app/$variant leaves unrelated external files intact"
  if [[ "$variant" == uninstall ]]; then
    check "$(test -e "$file" && printf present || printf absent)" absent "$app retires only selected external compose after teardown"
  fi
  if [[ "$variant" == foreign-root ]]; then check "$(cat "$c/opt/portainer/operator-data" 2> /dev/null || true)" 'unknown root data' "$app teardown preserves unknown root contents"; fi
  check "$(find "$c/external/selected files" -maxdepth 1 -name '.portainer-compose.*' | wc -l)" 0 "$app/$variant retires exact compose stage"
}
runtime_hooks_uninstall_assert() {
  local outcome=present path
  [[ "$rc" != 0 ]] || outcome=absent
  for path in local/sbin/update local/sbin/uninstall aliases/update aliases/uninstall "addons/$pending_key"; do
    check "$({ test -e "$c/$path" || test -L "$c/$path"; } && printf present || printf absent)" "$outcome" "$app/$variant first outcome owns $path retirement"
  done
  case "$variant" in
    interrupted-* | changed-after-down)
      local retry=0 wanted=0
      [[ "$variant" != changed-after-down ]] || wanted=65
      runtime_hooks_invoke uninstall none "$c/retry-output" "$c/retry.log" "$c/retry-errors.log" || retry=$?
      check "$retry" "$wanted" "$app/$variant cold uninstall retry exact outcome"
      check "$(wc -l < "$c/down-events")" 1 "$app/$variant completed down is not replayed"
      if [[ "$wanted" == 0 ]]; then
        for path in local/sbin/update local/sbin/uninstall aliases/update aliases/uninstall "addons/$pending_key" addon-teardowns/portainer; do
          check "$({ test -e "$c/$path" || test -L "$c/$path"; } && printf present || printf absent)" absent "$app/$variant cold completion retires $path"
        done
      else
        check "$(cat "$c/external/selected files/stack.json")" 'operator changed model' "$app/$variant changed manifest preserved"
        check "$(test -e "$c/local/sbin/uninstall" && printf retained || printf lost)" retained "$app/$variant conflict retains recovery command"
      fi
      ;;
  esac
}
runtime_hooks_retry_needed() { return 1; }
runtime_hooks_main "$@"
