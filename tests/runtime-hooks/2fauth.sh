#!/usr/bin/env bash
# shellcheck disable=SC2034,SC2154
# Cold hooks with real filesystem modes; PHP/package/service effects are modeled.
set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/../lib/runtime-hooks/harness.sh"
app=2fauth
script_type=lxc
variants=(fresh update install-repair-failure update-repair-failure)
hook_paths=()

runtime_hooks_variant() {
  [[ "$variant" != install-repair-failure ]] || role=install
  case "$variant" in *repair-failure) fault=repair ;; esac
}
runtime_hooks_model() {
  apt() { :; }
  setup_php() { :; }
  setup_composer() { :; }
  setup_mariadb() { :; }
  setup_mariadb_db() { export MARIADB_DB_NAME=2fauth_db MARIADB_DB_USER=2fauth MARIADB_DB_PASS=fixture-password; }
  composer() { :; }
  create_backup() { :; }
  restore_backup() { :; }
  dpkg() { printf 'ii php8.4\n'; }
  php() {
    case "$*" in
      'artisan passport:install -q -n')
        mkdir -p storage
        printf 'fixture-private-key\n' > storage/oauth-private.key
        printf 'fixture-public-key\n' > storage/oauth-public.key
        ;;
      'artisan 2fauth:fix-passport-key-permissions')
        [[ "$APP_FAULT" != repair ]] || return 57
        chmod 0600 storage/oauth-private.key
        chmod 0660 storage/oauth-public.key
        ;;
      'artisan 2fauth:install'*)
        # The native wizard otherwise reviews .env and clears the DB password
        # on EOF; production also needs explicit migration confirmation.
        [[ " $* " == *' --no-interaction '* && " $* " == *' --force '* ]] || return 58
        ;;
    esac
  }
  curl() {
    local out='' format=''
    while (($#)); do
      case "$1" in -o)
        out=$2
        shift
        ;;
      -w)
        format=$2
        shift
        ;;
      esac
      shift
    done
    local body='{"tag_name":"v9.0.1","assets":[]}'
    if [[ -n "$out" ]]; then printf '%s' "$body" > "$out"; else printf '%s' "$body"; fi
    [[ -z "$format" ]] || printf 200
  }
}
runtime_hooks_setup() {
  mkdir -p "$c/etc/nginx/conf.d" "$c/payload/storage"
  printf 'APP_URL=http://localhost\nDB_CONNECTION=\nDB_DATABASE=\nDB_HOST=\nDB_PORT=\nDB_USERNAME=\nDB_PASSWORD=\n' > "$c/payload/.env.example"
  if [[ "$role" == update ]]; then
    mkdir -p "$c/opt/2fauth/storage"
    printf 'fixture-private-key\n' > "$c/opt/2fauth/storage/oauth-private.key"
    printf 'fixture-public-key\n' > "$c/opt/2fauth/storage/oauth-public.key"
    printf 'php8.4\n' > "$c/etc/nginx/conf.d/2fauth.conf"
  fi
}
runtime_hooks_expected() { [[ "$fault" != repair ]] || expected=57; }
runtime_hooks_assert() {
  runtime_hooks_configuration_assert
  if [[ "$rc" == 0 ]]; then
    check "$(stat -c %a "$c/opt/2fauth/storage/oauth-private.key")" 600 "$app/$variant final private key mode accepted by Passport"
    check "$(stat -c %a "$c/opt/2fauth/storage/oauth-public.key")" 660 "$app/$variant final public key mode accepted by Passport"
  fi
  if [[ "$role" == update ]]; then
    check "$(cat "$c/opt/2fauth/storage/oauth-private.key")" fixture-private-key "$app/$variant existing private key bytes preserved"
    check "$(cat "$c/opt/2fauth/storage/oauth-public.key")" fixture-public-key "$app/$variant existing public key bytes preserved"
  fi
}
runtime_hooks_retry_assert() {
  check "$(stat -c %a "$c/opt/2fauth/storage/oauth-private.key")" 600 "$app/$variant retry repairs private key mode"
  check "$(stat -c %a "$c/opt/2fauth/storage/oauth-public.key")" 660 "$app/$variant retry repairs public key mode"
}

runtime_hooks_main "$@"
