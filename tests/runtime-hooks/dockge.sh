#!/usr/bin/env bash
# runtime-hooks-contract: addon intent-preserving
# shellcheck disable=SC2034,SC2154
set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/../lib/runtime-hooks/harness.sh"
app=dockge script_type=addon
runtime_hooks_observed_commands=(docker systemctl)
runtime_hooks_selected_service=dockge
variants=(fresh openrc named-stacks missing update pull-failure up-failure uninstall down-failure)
hook_paths=()
runtime_hooks_variant() {
  case "$variant" in
    openrc) role=install fault=openrc ;;
    named-stacks) role=install fault=named-stacks ;;
    missing) fault=missing ;;
    uninstall) role=uninstall ;;
    pull-failure) fault=pull ;;
    up-failure) fault=up ;;
    down-failure) role=uninstall fault=down ;;
  esac
}
runtime_hooks_setup() {
  printf 'var_addon_install_path=%q\nvar_addon_stacks_path=%q\nvar_addon_default_port=18501\n' '/opt/dockge custom' '/opt/stacks custom' > "$c/context.sh"
  mkdir -p "$c/opt/dockge custom" "$c/opt/stacks custom" "$c/etc/init.d"
  printf 'foreign stack data\n' > "$c/opt/stacks custom/foreign"
  [[ "$variant" == missing ]] || printf '{"services":{"dockge":{"ports":[{"published":"18501"}],"environment":{"DOCKGE_STACKS_DIR":"/opt/stacks custom"}}}}\n' > "$c/opt/dockge custom/compose.yaml"
  [[ "$role" == install ]] || printf 'old running stack\n' > "$c/running-stack"
  : > "$c/docker"
}
runtime_hooks_model() {
  [[ "$APP_FAULT" != openrc ]] || INIT_SYSTEM=openrc
  systemctl() {
    printf '%s\n' "$*" >> "$c/services"
    case "$1" in
      show) printf 'LoadState=loaded\nActiveState=active\nUnitFileState=enabled\n' ;;
      start)
        local unit="$c/etc/systemd/system/dockge.service" directory executable
        directory=$(sed -n 's/^WorkingDirectory=//p' "$unit")
        executable=$(sed -n 's/^ExecStart=//p' "$unit")
        [[ "$directory" == "$var_addon_install_path" && "$executable" == '/usr/bin/docker compose up -d --remove-orphans' ]] || return 65
        (cd "$directory" && docker compose up -d --remove-orphans)
        ;;
    esac
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
    printf 'services:\n  dockge:\n    image: louislam/dockge:1\n' > "$out"
  }
  docker() {
    printf '%s\n' "$*" >> "$c/docker"
    if [[ "$1 ${2:-}" == 'compose pull' || "$1 ${2:-}" == 'compose up' || "$1 ${2:-}" == 'compose down' ]]; then
      [[ "$PWD" == "$var_addon_install_path" ]] || return 65
      [[ "$APP_FAULT" != "$2" ]] || return 47
      case "$2" in
        up) jq '{port:.services.dockge.ports[0].published,stacks:.services.dockge.environment.DOCKGE_STACKS_DIR}' compose.yaml > "$c/running-stack" ;;
        pull) printf 'pulled\n' >> "$c/pull-completed" ;;
        down) rm -f "$c/running-stack" ;;
      esac
      return 0
    fi
    if [[ "$*" == 'compose config --help' ]]; then
      printf '      --no-env-resolution  Retain env_file\n      --no-interpolate  Retain expressions\n      --no-path-resolution  Retain relative paths\n'
      return 0
    fi
    if [[ "$*" == *'--format json'* ]]; then
      local model='{"services":{"dockge":{"image":"louislam/dockge:1","ports":[{"target":5001,"published":"5001","protocol":"tcp"}],"volumes":[{"type":"bind","source":"/opt/stacks","target":"/opt/stacks"},{"type":"bind","source":"/opt/dockge/data","target":"/app/data"}],"environment":{"DOCKGE_STACKS_DIR":"/opt/stacks"}}}}'
      if [[ "$*" == *' --no-interpolate '* ]]; then
        model=$(jq '.services.dockge.environment = ["DOCKGE_STACKS_DIR=/opt/stacks","OPERATOR","EXPRESSION=${OPERATOR_VALUE:-a=b}"]' <<< "$model")
      fi
      if [[ "$APP_FAULT" == named-stacks ]]; then
        jq '.services.dockge.volumes[0] |= (.type = "volume" | .source = "operator-stacks")' <<< "$model"
      else printf '%s\n' "$model"; fi
    fi
  }
}
runtime_hooks_expected() {
  [[ "$variant" != missing ]] || expected=1
  [[ "$variant" != named-stacks ]] || expected=65
  case "$fault" in pull | up | down) expected=47 ;; esac
}
runtime_hooks_assert() {
  if [[ "$role" == install && "$variant" != named-stacks ]]; then
    for flag in --no-interpolate --no-env-resolution --no-path-resolution; do
      check "$(grep -Fc -- "$flag" "$c/docker" || true)" 1 "$app publication retains native source semantics: $flag"
    done
    check "$(jq -r '.services.dockge.ports[0].published' "$c/opt/dockge custom/compose.yaml" 2> /dev/null || true)" 18501 "$app applies displayed host port"
    check "$(jq -r '.services.dockge.environment.DOCKGE_STACKS_DIR' "$c/opt/dockge custom/compose.yaml" 2> /dev/null || true)" '/opt/stacks custom' "$app consumer receives configured stacks path"
    check "$(jq -r '.services.dockge.environment | has("OPERATOR") and .OPERATOR == null' "$c/opt/dockge custom/compose.yaml" 2> /dev/null || true)" true "$app bare-key environment retains native inheritance"
    check "$(jq -r '.services.dockge.environment.EXPRESSION' "$c/opt/dockge custom/compose.yaml" 2> /dev/null || true)" '${OPERATOR_VALUE:-a=b}' "$app environment assignment keeps equals and interpolation"
    check "$(jq -r '.services.dockge.volumes[] | select(.target=="/opt/stacks custom") | .source' "$c/opt/dockge custom/compose.yaml" 2> /dev/null || true)" '/opt/stacks custom' "$app stacks bind source equals container target"
    check "$(jq -r '.services.dockge.volumes[] | select(.target=="/app/data") | .source' "$c/opt/dockge custom/compose.yaml" 2> /dev/null || true)" '/opt/dockge/data' "$app preserves independent data mount"
  fi
  if [[ "$variant" == named-stacks ]]; then
    check "$(grep -Ec '(^start | up )' "$c/services" "$c/docker" | awk -F: '{n+=$NF} END {print n+0}')" 0 "$app named-volume stacks refuses before startup"
  fi
  check "$(cat "$c/opt/stacks custom/foreign")" 'foreign stack data' "$app preserves independent stack data"
  if [[ "$rc" == 0 && "$role" != uninstall ]]; then
    check "$(jq -r '.port' "$c/running-stack" 2> /dev/null || true)" 18501 "$app/$variant live modeled stack consumes selected listener"
    check "$(jq -r '.stacks' "$c/running-stack" 2> /dev/null || true)" '/opt/stacks custom' "$app/$variant live modeled stack consumes selected directory"
    local -a expected_argv=(compose up -d)
    [[ "$variant" == openrc ]] || expected_argv+=(--remove-orphans)
    runtime_hooks_completed_assert docker '/opt/dockge custom' "${expected_argv[@]}"
  elif [[ "$role" == uninstall ]]; then
    check "$(test -f "$c/running-stack" && printf present || printf absent)" "$([[ "$rc" == 0 ]] && printf absent || printf present)" "$app/$variant teardown controls actual modeled stack"
    check "$(test -f "$c/opt/dockge custom/compose.yaml" && printf present || printf absent)" "$([[ "$rc" == 0 ]] && printf absent || printf present)" "$app/$variant required down precedes selected manifest removal"
  fi
}
runtime_hooks_retry_needed() { return 1; }
runtime_hooks_main "$@"
