#!/usr/bin/env bash
# shellcheck disable=SC2034,SC2154
set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/../lib/runtime-hooks/harness.sh"
app=dockge script_type=addon
variants=(fresh openrc missing update uninstall)
hook_paths=()
runtime_hooks_variant() {
  case "$variant" in
    openrc) role=install fault=openrc ;;
    missing) fault=missing ;;
    uninstall) role=uninstall ;;
  esac
}
runtime_hooks_setup() {
  printf 'var_addon_install_path=/opt/dockge\nvar_addon_stacks_path=%q\nvar_addon_default_port=18501\n' '/opt/stacks custom' > "$c/context.sh"
  mkdir -p "$c/opt/dockge" "$c/opt/stacks custom" "$c/etc/init.d"
  printf 'foreign stack data\n' > "$c/opt/stacks custom/foreign"
  [[ "$variant" == missing ]] || printf '{"services":{"dockge":{}}}\n' > "$c/opt/dockge/compose.yaml"
  : > "$c/docker"
}
runtime_hooks_model() {
  [[ "$APP_FAULT" != openrc ]] || INIT_SYSTEM=openrc
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
    if [[ "$*" == *'--format json'* ]]; then
      printf '%s\n' '{"services":{"dockge":{"image":"louislam/dockge:1","ports":[{"target":5001,"published":"5001","protocol":"tcp"}],"volumes":[{"type":"bind","source":"/opt/stacks","target":"/opt/stacks"},{"type":"bind","source":"/opt/dockge/data","target":"/app/data"}],"environment":{"DOCKGE_STACKS_DIR":"/opt/stacks"}}}}'
    fi
  }
}
runtime_hooks_expected() { [[ "$variant" != missing ]] || expected=1; }
runtime_hooks_assert() {
  if [[ "$role" == install ]]; then
    check "$(jq -r '.services.dockge.ports[0].published' "$c/opt/dockge/compose.yaml" 2> /dev/null || true)" 18501 "$app applies displayed host port"
    check "$(jq -r '.services.dockge.environment.DOCKGE_STACKS_DIR' "$c/opt/dockge/compose.yaml" 2> /dev/null || true)" '/opt/stacks custom' "$app consumer receives configured stacks path"
    check "$(jq -r '.services.dockge.volumes[] | select(.target=="/opt/stacks custom") | .source' "$c/opt/dockge/compose.yaml" 2> /dev/null || true)" '/opt/stacks custom' "$app stacks bind source equals container target"
    check "$(jq -r '.services.dockge.volumes[] | select(.target=="/app/data") | .source' "$c/opt/dockge/compose.yaml" 2> /dev/null || true)" '/opt/dockge/data' "$app preserves independent data mount"
  fi
  check "$(cat "$c/opt/stacks custom/foreign")" 'foreign stack data' "$app preserves independent stack data"
}
runtime_hooks_retry_needed() { return 1; }
runtime_hooks_main "$@"
