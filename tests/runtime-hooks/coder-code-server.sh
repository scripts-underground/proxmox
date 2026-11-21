#!/usr/bin/env bash
# runtime-hooks-contract: addon intent-preserving
# shellcheck disable=SC2034,SC2154
set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/../lib/runtime-hooks/addon-release.sh"
app=coder-code-server
runtime_hooks_observed_commands=(systemctl _deploy_release_deb)
runtime_hooks_selected_service=code-server@fixture-editor
release_app=coder-code-server release_mode=binary release_asset=code-server_2_amd64.deb
addon_release_setup() { :; }
addon_release_consumer_assert() { check "$(cat "$c/package-consumer")" 'selected v2.0.0' "$app selected package consumer"; }
eval "$(declare -f runtime_hooks_assert | sed '1s/runtime_hooks_assert/code_server_release_assert/')"
variants+=(fresh fresh-existing missing-user)
runtime_hooks_variant() {
  case "$variant" in checker) fault=checker ;; fresh | fresh-existing) role=install ;; missing-user) role=install fault=missing-user ;; esac
}
runtime_hooks_model() {
  addon_release_model
  apt() { printf '%s\n' "$*" >> "$c/packages"; }
  get_system_arch() { printf amd64; }
  getent() {
    [[ "$1" != hosts ]] || return 0
    [[ "$APP_FAULT" != missing-user ]] || return 2
    [[ "$*" == 'passwd fixture-editor' ]] || return 2
    printf 'fixture-editor:x:1234:2345:Editor:%s:/bin/bash\n' "$c/editor home"
  }
  chown() { printf '%s\n' "$*" >> "$c/ownership"; }
  runuser() {
    printf '%s\n' "$1 $2 $3" >> "$c/account-writes"
    [[ "$1 $2 $3" == '-u fixture-editor --' ]] || return 65
    shift 3
    "$@"
  }
  systemctl() {
    printf '%s\n' "$*" >> "$c/services"
    if [[ "$1" == restart && "$APP_ROLE" == install ]]; then
      cat "$c/editor home/.config/code-server/config.yaml" > "$c/running-config"
    fi
  }
}
runtime_hooks_setup() {
  : > "$c/requests"
  : > "$c/downloads"
  : > "$c/ownership"
  printf 'old package\n' > "$c/package-consumer"
  printf '%s\n' "$([[ "$variant" == no-update ]] && printf 2.0.0 || printf 1.0.0)" > "$c/home/.coder-code-server"
  printf 'var_addon_svc_user=fixture-editor\nvar_addon_default_port=18680\n' > "$c/context.sh"
  mkdir -p "$c/home/.config/code-server" "$c/editor home"
  printf 'operator root config\n' > "$c/home/.config/code-server/config.yaml"
  if [[ "$variant" == fresh-existing ]]; then
    mkdir -p "$c/editor home/.config/code-server"
    printf 'operator editor config\n' > "$c/editor home/.config/code-server/config.yaml"
    chmod 0640 "$c/editor home/.config/code-server/config.yaml"
  fi
}
runtime_hooks_expected() { case "$fault" in checker) expected=17 ;; missing-user) expected=2 ;; esac }
runtime_hooks_assert() {
  if [[ "$role" != install ]]; then
    code_server_release_assert
    return
  fi
  check "$(cat "$c/home/.config/code-server/config.yaml")" 'operator root config' "$app/$variant caller HOME config is untouched"
  if [[ "$fault" == missing-user ]]; then
    check "$(test -e "$c/packages" && printf effects || printf absent)" absent "$app missing target user refuses before packages"
    check "$(stat -c %s "$c/services")" 0 "$app missing target user has no service effects"
  elif [[ "$variant" == fresh-existing ]]; then
    check "$(cat "$c/running-config" 2> /dev/null || true)" 'operator editor config' "$app existing target-user config reaches service"
    check "$(stat -c %a "$c/editor home/.config/code-server/config.yaml")" 640 "$app existing target config mode retained"
  else
    check "$(grep -c '^bind-addr: 0.0.0.0:18680$' "$c/running-config" || true)" 1 "$app configured port reaches target-user service"
    check "$(test -s "$c/account-writes" && printf account || printf root)" account "$app fresh config writes run as target account"
    check "$(stat -c %s "$c/ownership")" 0 "$app never chowns account-controlled paths as root"
  fi
}
runtime_hooks_main "$@"
