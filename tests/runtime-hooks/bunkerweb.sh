#!/usr/bin/env bash
# shellcheck disable=SC2034,SC2154
# Real cold bundles, release checker and pending owner; APT/HTTP/service effects modeled.
set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/../lib/runtime-hooks/harness.sh"
app=bunkerweb
script_type=lxc
variants=(selected checker no-update pending package-failure dependency metadata metadata-missing)
hook_paths=()
runtime_hooks_variant() {
  case "$variant" in checker) fault=checker ;; package-failure) fault=package ;; dependency | metadata | metadata-missing) fault=$variant ;; esac
}
runtime_hooks_expected() {
  case "$variant" in checker) expected=22 ;; package-failure) expected=42 ;; dependency) expected=0 ;; metadata) expected=43 ;; metadata-missing) expected=65 ;; esac
}
runtime_hooks_model() {
  git() { return 128; }
  apt-cache() {
    printf '%s\n' "$*" >> "$c/metadata-requests"
    [[ "$APP_FAULT" != metadata ]] || return 43
    if [[ "$APP_FAULT" == metadata-missing ]]; then
      printf 'Package: bunkerweb\nVersion: 1.6.17\nDepends: bash, python3\n'
    else
      printf 'Package: bunkerweb\nVersion: 1.6.17\nDepends: bash, nginx (= 1.30.6-1~trixie), python3\n'
    fi
  }
  apt-mark() { printf '%s\n' "$*" >> "$c/packages"; }
  apt() {
    printf '%s\n' "$*" >> "$c/packages"
    [[ "$1" == install ]] || return 0
    [[ "$APP_FAULT" != package ]] || return 42
    local arg version='' nginx_version='' reinstall=no
    for arg in "$@"; do
      case "$arg" in bunkerweb=*) version=${arg#*=} ;; nginx=*) nginx_version=${arg#*=} ;; --reinstall) reinstall=yes ;; esac
    done
    [[ -n "$version" ]] || return 65
    # Reproduce native APT's newer-candidate conflict with the selected ABI pin.
    [[ "$APP_FAULT" != dependency || "$nginx_version" == 1.30.6-1~trixie ]] || return 100
    # APT does not unpack an installed same-version package without --reinstall.
    if [[ "$version" != "$(cat "$c/installed-version")" || "$reinstall" == yes ]]; then
      printf '%s\n' "$version" > "$c/installed-version"
      printf 'package %s\n' "$version" > "$c/opt/bunkerweb/code"
    fi
  }
  curl() {
    local out='' url='' format='' tag=v1.6.17
    while (($#)); do
      case "$1" in
        -o)
          out=$2
          shift
          ;;
        -w)
          format=$2
          shift
          ;;
        https:*) url=$1 ;;
      esac
      shift
    done
    printf '%s\n' "$url" >> "$c/requests"
    [[ "$APP_FAULT" != checker ]] || return 22
    if [[ "$c" == *-selected && "$url" == */releases/latest && "$(grep -c '/releases/latest$' "$c/requests")" -gt 1 ]]; then tag=v9.0.0; fi
    [[ "$url" != */releases/tags/* ]] || tag=${url##*/}
    local body="{\"tag_name\":\"$tag\",\"draft\":false,\"prerelease\":false,\"assets\":[]}"
    if [[ -n "$out" ]]; then printf '%s' "$body" > "$out"; else printf '%s' "$body"; fi
    [[ -z "$format" ]] || printf 200
  }
}
runtime_hooks_setup() {
  mkdir -p "$c/etc/bunkerweb" "$c/etc/apt/preferences.d"
  printf 'saved user settings\n' > "$c/etc/bunkerweb/variables.env"
  printf '1.6.16\n' > "$c/home/.bunkerweb"
  printf '1.6.16\n' > "$c/installed-version"
  : > "$c/packages"
  : > "$c/requests"
  : > "$c/metadata-requests"
  case "$variant" in
    no-update | pending)
      printf '1.6.17\n' > "$c/home/.bunkerweb"
      printf '1.6.17\n' > "$c/installed-version"
      ;;
  esac
  if [[ "$variant" == pending ]]; then
    printf 'interrupted update\n' > "$c/state/bunkerweb"
    rm "$c/opt/bunkerweb/code"
  fi
}
runtime_hooks_assert() {
  check "$(cat "$c/etc/bunkerweb/variables.env")" 'saved user settings' "$app/$variant configuration retained"
  case "$variant" in
    selected | pending | dependency)
      check "$(cat "$c/opt/bunkerweb/code" 2> /dev/null || true)" 'package 1.6.17' "$app/$variant selected package reaches consumer"
      check "$(cat "$c/home/.bunkerweb")" 1.6.17 "$app/$variant marker advances only after package success"
      check "$(grep -c '^Pin: version 1.6.17$' "$c/etc/apt/preferences.d/bunkerweb")" 1 "$app/$variant preference matches selected release"
      check "$(grep -c '/releases/latest$' "$c/requests")" 1 "$app/$variant one selection, no moved latest lookup"
      check "$(cat "$c/metadata-requests")" 'show bunkerweb=1.6.17' "$app/$variant selected package owns its Nginx ABI"
      check "$(grep -c 'nginx=1.30.6-1~trixie' "$c/packages")" 1 "$app/$variant dependency bound in the same APT transaction"
      ;;
    checker | no-update)
      check "$(stat -c %s "$c/packages")" 0 "$app/$variant no package effects"
      check "$(cat "$c/opt/bunkerweb/code")" 'old code' "$app/$variant existing consumer retained"
      ;;
    package-failure)
      check "$(cat "$c/home/.bunkerweb")" 1.6.16 "$app/$variant failure never advances marker"
      ;;
    metadata | metadata-missing)
      check "$(grep -c '^install ' "$c/packages" || true)" 0 "$app/$variant no install with unproven package metadata"
      check "$(cat "$c/home/.bunkerweb")" 1.6.16 "$app/$variant metadata failure never advances marker"
      ;;
  esac
}
runtime_hooks_retry_assert() {
  check "$(cat "$c/opt/bunkerweb/code")" 'package 1.6.17' "$app retry deploys selected package"
  check "$(cat "$c/home/.bunkerweb")" 1.6.17 "$app retry publishes completed version"
  check "$(cat "$c/etc/bunkerweb/variables.env")" 'saved user settings' "$app retry retains configuration"
}
runtime_hooks_main "$@"
