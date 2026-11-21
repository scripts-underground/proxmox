#!/usr/bin/env bash
# runtime-hooks-contract: addon intent-preserving
# shellcheck disable=SC2034,SC2154
set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/../lib/runtime-hooks/harness.sh"
app=glances script_type=addon
variants=(fresh update installed-uv broken-uv alpine-fresh alpine-update unsupported)
hook_paths=()
runtime_hooks_variant() {
  if [[ "$variant" == unsupported ]]; then role=install fault=unsupported; fi
  case "$variant" in installed-uv | broken-uv) fault=$variant ;; alpine-fresh) role=install fault=alpine ;; alpine-update) fault=alpine ;; esac
}
runtime_hooks_setup() {
  mkdir -p "$c/opt/glances/.venv/bin" "$c/etc/init.d"
  printf 'deactivate() { :; }\n' > "$c/opt/glances/.venv/bin/activate"
  printf 'var_addon_app_dir=/opt/glances\n' > "$c/context.sh"
  : > "$c/runtime"
  : > "$c/packages"
}
runtime_hooks_model() {
  [[ "$APP_FAULT" != unsupported ]] || OS_FAMILY=fedora
  [[ "$APP_FAULT" != alpine ]] || { OS_FAMILY=alpine INIT_SYSTEM=openrc; }
  apt() { printf '%s\n' "$*" >> "$c/packages"; }
  apk() { printf '%s\n' "$*" >> "$c/packages"; }
  rc-update() { printf 'openrc registration %s\n' "$*" >> "$c/services"; }
  rc-service() { printf 'openrc %s\n' "$*" >> "$c/services"; }
  uv() {
    printf 'uv %s\n' "$*" >> "$c/runtime"
    if [[ "$1" == --version || "$*" == 'pip install --help' ]]; then
      [[ "$APP_FAULT" == installed-uv ]] || return 127
      return 0
    fi
    if [[ "$1" == venv ]]; then
      mkdir -p .venv/bin
      printf 'deactivate() { :; }\n' > .venv/bin/activate
    fi
    printf 'configured venv glances\n' > "$c/package-consumer"
  }
  setup_uv() {
    printf 'python=%s argc=%s\n' "${PYTHON_VERSION:-unset}" "$#" >> "$c/runtime"
    [[ "$APP_FAULT" != installed-uv ]] || return 37
  }
}
runtime_hooks_expected() { [[ "$fault" != unsupported ]] || expected=1; }
runtime_hooks_assert() {
  if [[ "$variant" == unsupported ]]; then
    check "$(stat -c %s "$c/packages")" 0 "$app refuses unsupported package family before effects"
    check "$(stat -c %s "$c/runtime")" 0 "$app unsupported family never provisions Python"
  elif [[ "$role" == install ]]; then
    check "$(grep -c '^python=3.12 argc=0$' "$c/runtime" || true)" 1 "$app Python selection uses helper environment not argv"
    check "$(grep -c '^uv venv --python 3.12 --clear$' "$c/runtime" || true)" 1 "$app venv selects intended Python"
  else
    local setups=1
    [[ "$variant" != installed-uv ]] || setups=0
    check "$(grep -c '^python=unset argc=0$' "$c/runtime" || true)" "$setups" "$app update restores unusable uv but reuses installed capable uv"
    check "$(grep -c '^uv pip install --upgrade glances\[web\]$' "$c/runtime" || true)" 1 "$app update reaches installed venv consumer"
    check "$(cat "$c/package-consumer" 2> /dev/null || true)" 'configured venv glances' "$app update completes package consumer"
  fi
  if [[ "$fault" == alpine ]]; then
    check "$(grep -c '^openrc .*glances.*\(start\|restart\)$' "$c/services" || true)" 1 "$app Alpine selects native OpenRC dispatch"
  fi
}
runtime_hooks_main "$@"
