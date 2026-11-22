#!/usr/bin/env bash
# shellcheck disable=SC2034,SC2154
# Real bundle/release/pending owners; package/build/service effects are modeled.
set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/../lib/runtime-hooks/addon-release.sh"
app=bentopdf
script_type=lxc
release_app=$app release_mode=tarball release_asset=source.tar.gz
variants=(fresh checker no-update selected pending build late-build missing-public missing)
hook_paths=()
runtime_hooks_variant() {
  case "$variant" in checker) fault=checker ;; late-build) fault=late-build ;; esac
}
runtime_hooks_model() {
  addon_release_model
  apt() { :; }
  openssl() {
    while (($#)); do
      case "$1" in
        -keyout | -out)
          printf 'certificate fixture\n' > "$2"
          shift
          ;;
      esac
      shift
    done
  }
  npm() {
    [[ "$APP_FAULT" != build || "$*" != 'run build:all' ]] || return 52
    if [[ "$*" == 'run build:all' ]]; then
      # Vite empties dist and copies public, independently of source replacement.
      rm -rf -- dist
      mkdir dist
      [[ "$APP_FAULT" != late-build ]] || return 53
      cp public/config.json dist/config.json
      printf 'new frontend\n' > dist/index.html
      cp .env.production "$c/consumed-environment"
    fi
  }
}
addon_release_setup() {
  mkdir -p "$c/etc/nginx/"{sites-available,sites-enabled} "$c/etc/ssl/"{private,certs} "$c/payload/public"
  printf 'application/rss+xml\n' > "$c/etc/nginx/mime.types"
  printf 'default environment\n' > "$c/payload/.env.example"
  printf '{}\n' > "$c/payload/public/config.json"
  printf 'selected source\n' > "$c/payload/package.json"
  if [[ "$role" == update ]]; then
    mkdir -p "$c/opt/bentopdf/"{dist,public}
    printf '{}\n' > "$c/opt/bentopdf/public/config.json"
    printf 'operator environment\n' > "$c/opt/bentopdf/.env.production"
    printf '{"disabledTools":["merge-pdf"]}\n' > "$c/opt/bentopdf/dist/config.json"
    printf 'operator nginx configuration\n' > "$c/etc/nginx/sites-available/bentopdf"
    printf 'operator unit options\n' > "$c/etc/systemd/system/bentopdf.service"
    printf 'operator certificate\n' > "$c/etc/ssl/certs/bentopdf-selfsigned.crt"
    printf 'operator key\n' > "$c/etc/ssl/private/bentopdf-selfsigned.key"
  fi
  if [[ "$variant" == pending ]]; then
    printf '2.0.0\n' > "$c/home/.bentopdf"
    printf 'interrupted update\n' > "$c/state/bentopdf"
  fi
  if [[ "$variant" == missing ]]; then
    mv "$c/opt/bentopdf" "$c/missing-installation"
  fi
  if [[ "$variant" == missing-public ]]; then
    rm -rf -- "$c/opt/bentopdf/public"
  fi
}
runtime_hooks_expected() {
  case "$fault:$variant" in checker:*) expected=17 ;; build:*) expected=52 ;; late-build:*) expected=53 ;; *:missing) expected=1 ;; esac
}
runtime_hooks_assert() {
  if [[ "$role" == update && "$variant" != missing ]]; then
    check "$(cat "$c/opt/bentopdf/.env.production")" 'operator environment' "$app/$variant saved environment"
    check "$(cat "$c/etc/nginx/sites-available/bentopdf")" 'operator nginx configuration' "$app/$variant installed nginx settings"
    check "$(cat "$c/etc/systemd/system/bentopdf.service")" 'operator unit options' "$app/$variant installed unit settings"
    check "$(cat "$c/etc/ssl/certs/bentopdf-selfsigned.crt")" 'operator certificate' "$app/$variant existing certificate"
    check "$(cat "$c/etc/ssl/private/bentopdf-selfsigned.key")" 'operator key' "$app/$variant existing key"
    if [[ "$expected" == 0 ]]; then
      check "$(cat "$c/opt/bentopdf/dist/config.json")" '{"disabledTools":["merge-pdf"]}' "$app/$variant served tool policy"
    fi
  fi
  case "$variant" in
    checker | no-update | missing)
      check "$(stat -c %s "$c/downloads")" 0 "$app/$variant no deployment"
      check "$(stat -c %s "$c/services")" 0 "$app/$variant no service effects"
      ;;
    *) check "$(grep -c 'v9.0.0' "$c/downloads" || true)" 0 "$app/$variant never deploys moving latest" ;;
  esac
  if [[ "$variant" == selected ]]; then
    check "$(grep -c '/releases/tags/v2.0.0$' "$c/requests" || true)" 1 "$app binds selected raw tag"
    check "$(grep -c '/releases/latest$' "$c/requests" || true)" 1 "$app resolves latest once"
  fi
}
runtime_hooks_retry_needed() { [[ "$expected" != 0 && "$variant" != missing ]]; }
runtime_hooks_retry_assert() {
  check "$(cat "$c/opt/bentopdf/dist/config.json")" '{"disabledTools":["merge-pdf"]}' "$app retry served tool policy"
  check "$(cat "$c/consumed-environment")" 'operator environment' "$app retry build consumes saved environment"
}
runtime_hooks_main "$@"
