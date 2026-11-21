#!/usr/bin/env bash
# shellcheck disable=SC2034,SC2154
set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/../lib/runtime-hooks/addon-release.sh"
app=actual-budget-prometheus-exporter
runtime_hooks_observed_commands=(npm systemctl)
runtime_hooks_observe_recovery=1
release_app=$app release_mode=tarball release_asset=unused.tar.gz
variants+=(fresh download stopped-download stopped-selected runtime ci build copy copy-unrestored stop in-tree-config external-mode-download unit-query-download)
runtime_hooks_variant() {
  case "$variant" in checker | runtime | ci | copy | copy-unrestored | stop | external-mode-download | unit-query-download) fault=$variant ;; stopped-download) fault=download ;; esac
}
runtime_hooks_expected() {
  case "$fault" in checker) expected=17 ;; ci) expected=53 ;; copy | copy-unrestored) expected=252 ;; stop) expected=47 ;; external-mode-download | unit-query-download) expected=250 ;; esac
}
addon_release_setup() {
  mkdir -p "$c/opt/actual-budget-custom"
  printf 'old code\n' > "$c/opt/actual-budget-custom/code"
  printf 'var_addon_install_path=/opt/actual-budget-custom\nvar_addon_config_path=%q\n' "$c/external/actual.env" > "$c/context.sh"
  if [[ "$role" == update ]]; then
    mkdir -p "$c/opt/actual-budget-custom/node_modules/native"
    printf 'old native dependency\n' > "$c/opt/actual-budget-custom/node_modules/native/runtime.node"
    printf 'operator credential\n' > "$c/external/actual.env"
    chmod 0600 "$c/external/actual.env"
    local initial=active
    [[ "$variant" != stopped-* ]] || initial=inactive
    runtime_hooks_recovery_setup "$app" "$initial" "$c/opt/actual-budget-custom" "$c/external/actual.env"
    [[ "$variant" != unit-query-download ]] || : > "$c/recovery-unverified"
    if [[ "$variant" == external-mode-download ]]; then
      ln -s "$c/external/actual.env" "$c/selected-env"
      printf 'var_addon_config_path=%q\n' "$c/selected-env" >> "$c/context.sh"
    fi
    if [[ "$variant" == in-tree-config ]]; then
      printf 'var_addon_config_path=/opt/actual-budget-custom/operator\ env\n' >> "$c/context.sh"
      printf 'operator credential\n' > "$c/opt/actual-budget-custom/operator env"
      chmod 0600 "$c/opt/actual-budget-custom/operator env"
      printf 'source default credential\n' > "$c/payload/operator env"
    fi
  fi
}
addon_release_consumer_assert() { check "$(cat "$c/opt/actual-budget-custom/code")" 'new code' "$app selected source uses saved install path"; }
runtime_hooks_model() {
  addon_release_model
  if [[ "$APP_FAULT" == unit-query-download ]]; then busctl() { return 47; }; fi
  apt() { :; }
  setup_nodejs() { [[ "$APP_FAULT" != runtime ]] || return 51; }
  npm() {
    if [[ "$APP_FAULT" == ci && "$1" == ci ]]; then
      mkdir -p node_modules/native
      printf 'partial native dependency\n' > node_modules/native/runtime.node
      return 53
    fi
    [[ "$APP_FAULT/$*" != 'build/run build' ]] || return 52
  }
  systemctl() {
    [[ "$APP_FAULT/$1" != stop/stop ]] || return 47
    if [[ -f "$c/recovery-service" ]]; then
      runtime_hooks_recovery_service "$@"
    else printf '%s\n' "$*" >> "$c/services"; fi
  }
  curl_download() {
    if [[ "$APP_FAULT" == external-mode-download ]]; then
      chmod 0640 "$c/external/actual.env"
      return 22
    fi
    [[ "$APP_FAULT" != download && "$APP_FAULT" != unit-query-download ]] || return 22
    addon_release_download "$@"
  }
  cp() {
    if [[ "$APP_FAULT" == copy || "$APP_FAULT" == copy-unrestored ]] && [[ "$*" == *'/deploy-source.'* && "${!#}" == /opt/* ]]; then
      command cp "$@"
      [[ "$APP_FAULT" != copy-unrestored ]] || printf 'partial runtime\n' > /opt/actual-budget-custom/partial-runtime
      return 41
    fi
    command cp "$@"
  }
}
eval "$(declare -f runtime_hooks_assert | sed '1s/runtime_hooks_assert/release_assert/')"
runtime_hooks_assert() {
  if [[ "$variant" == fresh ]]; then
    addon_release_consumer_assert
    check "$(stat -c %a "$c/external/actual.env")" 600 "$app credentials private at creation"
    check "$(grep -c '^PORT="3001"$' "$c/external/actual.env")" 1 "$app consumer config retained"
  elif [[ "$variant" == checker || "$variant" == no-update || "$variant" == selected ]]; then
    release_assert
  fi
  if [[ "$role" == update ]]; then
    if [[ "$variant" == in-tree-config ]]; then
      check "$(cat "$c/opt/actual-budget-custom/operator env" 2> /dev/null || true)" 'operator credential' "$app clean replacement preserves in-tree credential against source defaults"
      check "$(stat -c %a "$c/opt/actual-budget-custom/operator env" 2> /dev/null || true)" 600 "$app in-tree credential retains private mode"
    fi
    check "$(cat "$c/external/actual.env")" 'operator credential' "$app/$variant credential retained"
    local expected_mode=600
    [[ "$variant" != external-mode-download ]] || expected_mode=640
    check "$(stat -c %a "$c/external/actual.env")" "$expected_mode" "$app/$variant selected credential metadata is not rewritten"
    if [[ "$variant" == stopped-selected ]]; then
      check "$(cat "$c/recovery-state")" inactive "$app successful update leaves initially stopped service stopped"
      check "$(wc -l < "$c/recovery-starts")" 0 "$app successful update never starts initially stopped service"
    fi
  fi
}
runtime_hooks_retry_assert() {
  addon_release_consumer_assert
  if [[ "$variant" == stopped-download ]]; then
    check "$(cat "$c/recovery-state")" inactive "$app retry leaves initially stopped service stopped"
    check "$(wc -l < "$c/recovery-starts")" 0 "$app retry never starts initially stopped service"
  fi
}
runtime_hooks_deployment_assert() {
  [[ "$variant" != no-update ]] || return 0
  addon_release_consumer_assert
  runtime_hooks_completed_assert npm /opt/actual-budget-custom ci
  runtime_hooks_completed_assert npm /opt/actual-budget-custom run build
}
runtime_hooks_main "$@"
