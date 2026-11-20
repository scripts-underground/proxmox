#!/usr/bin/env bash
# shellcheck disable=SC2034,SC2154
# Cold install/update bundles with real release, pending and prompt owners.
# APT, repository setup, Go and xcaddy builds are modeled external effects.
set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/../lib/runtime-hooks/addon-release.sh"
app=caddy
script_type=lxc
release_app=xcaddy release_mode=binary release_asset=xcaddy_2.0.0_linux_amd64.deb
variants=(fresh fresh-xcaddy update pending package checker no-update selected missing)
hook_paths=()
runtime_hooks_variant() {
  case "$variant" in
    fresh | fresh-xcaddy) role=install ;;
    package) fault=package ;;
    checker) fault=checker ;;
  esac
}
runtime_hooks_model() {
  addon_release_model
  setup_deb822_repo() { printf 'repo %s\n' "$*" >> "$c/packages"; }
  apt() {
    printf '%s\n' "$*" >> "$c/packages"
    [[ "$1" != upgrade || "$APP_FAULT" != package ]] || return 53
    # APT leaves an installed package alone unless asked to install or reinstall it.
    if [[ " $* " == *' caddy '* ]]; then
      printf 'caddy package\n' > "$c/caddy-consumer"
    fi
  }
  _deploy_release_deb() {
    cat "$1" > "$c/package-consumer"
    printf '#!/usr/bin/env bash\nprintf "%%s\\n" "$*" >> "%s/xcaddy-builds"\n' "$c" > "$c/local/bin/xcaddy"
    chmod 0755 "$c/local/bin/xcaddy"
  }
}
addon_release_setup() {
  : > "$c/packages"
  : > "$c/xcaddy-builds"
  [[ "$variant" != fresh-xcaddy ]] || printf 'y\n' > "$c/stdin"
  if [[ "$role" == update ]]; then
    [[ "$variant" != missing ]] || return 0
    mkdir -p "$c/etc/caddy"
    printf ':80 {\n  respond "saved site"\n}\n' > "$c/etc/caddy/Caddyfile"
    printf 'caddy package\n' > "$c/caddy-consumer"
    case "$variant" in
      checker | no-update | selected)
        printf '#!/usr/bin/env bash\nprintf "%%s\\n" "$*" >> "%s/xcaddy-builds"\n' "$c" > "$c/local/bin/xcaddy"
        chmod 0755 "$c/local/bin/xcaddy"
        ;;
      *) rm -f "$c/home/.xcaddy" ;;
    esac
    if [[ "$variant" == pending ]]; then
      printf 'interrupted update\n' > "$c/state/caddy"
      rm "$c/caddy-consumer"
    fi
  fi
}
runtime_hooks_expected() {
  [[ "$variant" != missing ]] || expected=1
  case "$fault" in checker) expected=17 ;; package) expected=53 ;; esac
}
runtime_hooks_assert() {
  local reinstalls
  reinstalls=$(grep -c -- '--reinstall caddy' "$c/packages" || true)
  if [[ "$role" == install ]]; then
    check "$(grep -c '^install -y caddy$' "$c/packages" || true)" 1 "$app/$mode/$variant installs the Caddy package"
    check "$(cat "$c/caddy-consumer" 2> /dev/null || true)" 'caddy package' "$app/$mode/$variant package consumer present"
    if [[ "$variant" == fresh ]]; then
      check "$(stat -c %s "$c/downloads")" 0 "$app/$mode/fresh EOF keeps the default No answer"
      check "$(stat -c %s "$c/xcaddy-builds")" 0 "$app/$mode/fresh EOF builds nothing"
    else
      check "$(cat "$c/package-consumer")" 'selected v2.0.0' "$app/$mode/$variant xcaddy package deployed"
      check "$(cat "$c/xcaddy-builds")" build "$app/$mode/$variant xcaddy build runs once"
    fi
    return
  fi
  runtime_hooks_configuration_assert
  if [[ "$variant" == missing ]]; then
    check "$(stat -c %s "$c/packages")" 0 "$app/$mode/missing refuses before package effects"
    check "$(stat -c %s "$c/requests")" 0 "$app/$mode/missing refuses before release effects"
    mkdir -p "$c/etc/caddy"
    printf ':80 {\n  respond "saved site"\n}\n' > "$c/etc/caddy/Caddyfile"
    return
  fi
  check "$(cat "$c/etc/caddy/Caddyfile")" "$(printf ':80 {\n  respond "saved site"\n}')" "$app/$mode/$variant Caddyfile retained"
  case "$variant" in
    update | no-update | selected | checker)
      check "$reinstalls" 0 "$app/$mode/$variant ordinary update does not reinstall Caddy"
      ;;
    pending)
      check "$reinstalls" 1 "$app/$mode/pending forced update reinstalls Caddy"
      check "$(cat "$c/caddy-consumer" 2> /dev/null || true)" 'caddy package' "$app/$mode/pending package consumer repaired"
      ;;
  esac
  case "$variant" in
    update | pending | package)
      check "$(stat -c %s "$c/requests")" 0 "$app/$mode/$variant no xcaddy lookup without xcaddy"
      ;;
    no-update | checker)
      check "$(stat -c %s "$c/downloads")" 0 "$app/$mode/$variant no xcaddy deployment"
      check "$(stat -c %s "$c/xcaddy-builds")" 0 "$app/$mode/$variant no xcaddy build"
      ;;
    selected)
      check "$(cat "$c/package-consumer")" 'selected v2.0.0' "$app/$mode/selected xcaddy consumer"
      check "$(grep -c '/releases/tags/v2.0.0$' "$c/requests" || true)" 1 "$app/$mode/selected binds the selected raw tag"
      check "$(grep -c '/releases/latest$' "$c/requests" || true)" 1 "$app/$mode/selected resolves latest once"
      check "$(grep -c 'v9.0.0' "$c/downloads" || true)" 0 "$app/$mode/selected never deploys moved latest"
      check "$(cat "$c/xcaddy-builds")" build "$app/$mode/selected xcaddy build runs once"
      ;;
  esac
  if [[ "$variant" == package ]]; then
    check "$(grep -c '^upgrade -y$' "$c/packages" || true)" 1 "$app/$mode/package failure stops after the failed upgrade"
    check "$reinstalls" 0 "$app/$mode/package failure has no later package effects"
  fi
}
runtime_hooks_retry_assert() {
  check "$(grep -c -- '--reinstall caddy' "$c/packages" || true)" 1 "$app/$mode/$variant pending retry reinstalls Caddy"
  check "$(cat "$c/caddy-consumer")" 'caddy package' "$app/$mode/$variant retry package consumer"
  check "$(cat "$c/etc/caddy/Caddyfile")" "$(printf ':80 {\n  respond "saved site"\n}')" "$app/$mode/$variant retry retains Caddyfile"
  if [[ "$variant" == checker ]]; then
    check "$(cat "$c/package-consumer")" 'selected v2.0.0' "$app/$mode/checker retry redeploys the selected xcaddy"
    check "$(cat "$c/xcaddy-builds")" build "$app/$mode/checker retry builds once"
  fi
}
runtime_hooks_main "$@"
