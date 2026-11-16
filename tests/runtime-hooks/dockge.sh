#!/usr/bin/env bash
# Docker pull is this app's release check; the hook uses no GitHub checker.
# shellcheck disable=SC2034,SC2154
set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/../lib/runtime-hooks/harness.sh"
app=dockge
script_type=addon
variants=(fresh update pull-error uninstall)
hook_paths=()
runtime_hooks_variant() {
  case "$variant" in pull-error) fault=checker ;; uninstall) role=uninstall ;; esac
}
runtime_hooks_model() {
  docker() {
    printf '%s|%s\n' "$PWD" "$*" >> "$c/docker-calls"
    case "$*" in
      'compose version') : ;;
      'compose pull') [[ "$APP_FAULT" != checker ]] || return 17 ;;
      'compose up -d --remove-orphans') printf 'new image consumer\n' > "$c/consumer" ;;
      'compose down --remove-orphans') rm -f "$c/own-container" ;;
      *) return 91 ;;
    esac
  }
  curl() {
    [[ "$1" == -fsSL && "$3" == -o ]] || return 92
    printf 'services: {dockge: {image: fixture/dockge:2}}\n' > "$4"
  }
}
runtime_hooks_setup() {
  mkdir -p "$c/opt/stacks" "$c/opt/dockge"
  printf 'operator stack data\n' > "$c/opt/stacks/foreign-stack"
  printf 'var_addon_install_path=/opt/dockge\nvar_addon_stacks_path=/opt/stacks\nvar_addon_compose_url=https://fixture.invalid/compose.yaml\n' > "$c/context.sh"
  : > "$c/docker-calls"
  : > "$c/own-container"
  if [[ "$role" != install ]]; then
    printf 'operator compose\n' > "$c/opt/dockge/compose.yaml"
    printf 'old image consumer\n' > "$c/consumer"
    : > "$c/etc/systemd/system/dockge.service"
  fi
}
runtime_hooks_expected() { [[ "$fault" != checker ]] || expected=17; }
runtime_hooks_assert() {
  check "$(cat "$c/opt/stacks/foreign-stack")" 'operator stack data' "$app/$variant retains independent stacks"
  if [[ "$role" == install ]]; then
    check "$(cat "$c/opt/dockge/compose.yaml")" 'services: {dockge: {image: fixture/dockge:2}}' "$app install writes configured compose"
  elif [[ "$role" == update ]]; then
    check "$(cat "$c/consumer")" "$([[ "$rc" == 0 ]] && printf 'new image consumer' || printf 'old image consumer')" "$app/$variant consumer reflects release outcome"
    check "$(cat "$c/opt/dockge/compose.yaml")" 'operator compose' "$app/$variant retains operator compose"
  else
    check "$(test -e "$c/own-container" && printf present || printf absent)" absent "$app scoped compose uninstall removes own container"
  fi
}
runtime_hooks_retry_assert() {
  check "$(cat "$c/consumer")" 'new image consumer' "$app pending retry reaches image consumer"
  check "$(cat "$c/opt/stacks/foreign-stack")" 'operator stack data' "$app pending retry preserves stacks"
}
runtime_hooks_main "$@"
