#!/usr/bin/env bash
# shellcheck disable=SC2034,SC2154
set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/../lib/runtime-hooks/harness.sh"
app=glances script_type=addon
variants=(fresh update unsupported)
hook_paths=()
runtime_hooks_variant() {
  if [[ "$variant" == unsupported ]]; then role=install fault=unsupported; fi
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
  apt() { printf '%s\n' "$*" >> "$c/packages"; }
  setup_uv() {
    printf 'python=%s argc=%s\n' "${PYTHON_VERSION:-unset}" "$#" >> "$c/runtime"
    uv() {
      printf 'uv %s\n' "$*" >> "$c/runtime"
      if [[ "$1" == venv ]]; then
        mkdir -p .venv/bin
        printf 'deactivate() { :; }\n' > .venv/bin/activate
      fi
    }
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
    check "$(grep -c '^python=unset argc=0$' "$c/runtime" || true)" 1 "$app update restores missing uv without changing Python"
    check "$(grep -c '^uv pip install --upgrade glances\[web\]$' "$c/runtime" || true)" 1 "$app update reaches installed venv consumer"
  fi
}
runtime_hooks_main "$@"
