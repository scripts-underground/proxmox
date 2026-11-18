#!/usr/bin/env bash
# Real cold bundles, release selection, ZIP deployment and backup/restore.
# Package, PHP/database provisioning, HTTP transport and service effects are models.
# shellcheck disable=SC2034,SC2154
set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/../lib/runtime-hooks/harness.sh"
app=ampache
script_type=lxc
variants=(fresh fresh-missing-asset fresh-pin8 update current pending pin8 missing-asset checker-error download runtime)
hook_paths=(/var/www www)
runtime_hooks_model() {
  [[ "$APP_FAULT" != pin8 ]] || var_appversion=8.4.0
  apt() { :; }
  setup_php() {
    printf '%s\n' "$PHP_VERSION" >> "$c/php-calls"
    mkdir -p "$c/etc/php/8.4/apache2"
    printf 'memory_limit = 128M\n' > "$c/etc/php/8.4/apache2/php.ini"
  }
  setup_mariadb() { :; }
  setup_mariadb_db() { MARIADB_DB_PASS=fixture; }
  mariadb() { cat > "$c/schema-import"; }
  a2enmod() { :; }
  curl() {
    local out='' url='' format='' tag=''
    while (($#)); do
      case "$1" in
        -o)
          out="$2"
          shift
          ;;
        -w)
          format="$2"
          shift
          ;;
        https:*) url="$1" ;;
      esac
      shift
    done
    printf '%s\n' "$url" >> "$c/api"
    [[ "$APP_FAULT" != checker-error ]] || return 22
    case "$url" in
      */releases/latest) tag=8.4.0 ;;
      */releases/tags/*) tag="${url##*/}" ;;
      */releases\?*) ;;
      *) return 64 ;;
    esac
    python3 - "$out" "$tag" "$APP_FAULT" << 'PY'
import json,pathlib,sys
out,tag,fault=sys.argv[1:]
def release(version):
    php='8.5' if version.startswith('8.') or (fault=='missing-asset' and version=='7.10.5') else '8.4'
    name=f'ampache-{version}_all_php{php}.zip'
    return dict(tag_name=version,draft=False,prerelease=False,assets=[dict(name=name,browser_download_url=f'https://fixture.invalid/{version}/{name}')])
body=release(tag) if tag else [release(v) for v in ('8.4.0','7.10.5','7.10.4')]
raw=json.dumps(body)
if out:pathlib.Path(out).write_text(raw)
else:print(raw,end='')
PY
    [[ -z "$format" ]] || printf 200
  }
  curl_download() {
    printf '%s\n' "$2" >> "$c/downloads"
    [[ "$APP_FAULT" != download ]] || return 22
    command cp "$c/release.zip" "$1"
  }
  systemctl() {
    if [[ "$1" == start && "$APP_FAULT" == runtime ]]; then
      printf 'failed-start apache2\n' >> "$c/services"
      return 51
    fi
    printf '%s\n' "$*" >> "$c/services"
  }
}
runtime_hooks_variant() {
  case "$variant" in missing-asset | checker-error | pin8) fault="$variant" ;; esac
  [[ "$variant" != fresh-missing-asset ]] || {
    role=install
    fault=missing-asset
  }
  [[ "$variant" != fresh-pin8 ]] || {
    role=install
    fault=pin8
  }
}
runtime_hooks_expected() {
  case "$variant" in missing-asset | fresh-missing-asset) expected=252 ;; checker-error) expected=22 ;; pin8 | fresh-pin8) expected=65 ;; esac
}
runtime_hooks_setup() {
  mkdir -p "$c/www/html"
  : > "$c/downloads"
  : > "$c/php-calls"
  python3 - "$c/release.zip" << 'PY'
import sys,zipfile
with zipfile.ZipFile(sys.argv[1],'w') as archive:
    for name,body in {
        'code':'new code\n',
        'config/ampache.cfg.php.dist':'database_hostname = "localhost"\ndatabase_name = "ampache"\ndatabase_username = "ampache"\ndatabase_password = ""\n',
        'public/rest/.htaccess.dist':'new rest defaults\n',
        'public/play/.htaccess.dist':'new play defaults\n',
        'resources/sql/ampache.sql':'schema fixture\n',
    }.items(): archive.writestr(name,body)
PY
  if [[ "$role" == update ]]; then
    mkdir -p "$c/opt/ampache/"{config,public/rest,public/play,advanced-config,music}
    printf 'saved database configuration\n' > "$c/opt/ampache/config/ampache.cfg.php"
    printf 'saved REST rules\n' > "$c/opt/ampache/public/rest/.htaccess"
    printf 'saved play rules\n' > "$c/opt/ampache/public/play/.htaccess"
    printf 'saved advanced configuration\n' > "$c/opt/ampache/advanced-config/canary"
    printf 'saved music\n' > "$c/opt/ampache/music/canary"
    printf '7.10.4\n' > "$c/home/.ampache"
    case "$variant" in
      current | pending) printf '7.10.5\n' > "$c/home/.ampache" ;;
    esac
    [[ "$variant" != pending ]] || printf 'interrupted update\n' > "$c/state/ampache"
  fi
}
runtime_hooks_assert() {
  if [[ "$role" == update ]]; then
    check "$(cat "$c/opt/ampache/config/ampache.cfg.php")" 'saved database configuration' "$app/$variant saved configuration retained"
    check "$(cat "$c/opt/ampache/public/rest/.htaccess")" 'saved REST rules' "$app/$variant REST rules retained"
    check "$(cat "$c/opt/ampache/public/play/.htaccess")" 'saved play rules' "$app/$variant play rules retained"
    check "$(cat "$c/opt/ampache/advanced-config/canary")" 'saved advanced configuration' "$app/$variant advanced configuration retained"
    check "$(cat "$c/opt/ampache/music/canary")" 'saved music' "$app/$variant media retained"
    check "$(stat -c %s "$c/php-calls")" 0 "$app/$variant updater never provisions another PHP line"
  fi
  if [[ "$rc" == 0 ]]; then
    check "$(cat "$c/home/.ampache")" 7.10.5 "$app/$variant selected newest stable 7.x"
    if [[ "$variant" != current ]]; then
      check "$(cat "$c/downloads")" 'https://fixture.invalid/7.10.5/ampache-7.10.5_all_php8.4.zip' "$app/$variant exact selected release without fallback"
      check "$(cat "$c/opt/ampache/code")" 'new code' "$app/$variant deployed code consumer"
      if [[ "$role" == update ]]; then
        check "$(grep -c 'http://10.20.30.40/update.php' "$c/output" || true)" 1 "$app/$variant container-owned update URL"
      else
        check "$(cat "$c/php-calls")" 8.4 "$app/fresh supported PHP line"
      fi
    else
      check "$(stat -c %s "$c/downloads")" 0 "$app/current no unnecessary deployment"
    fi
  elif [[ "$variant" == *missing-asset || "$variant" == checker-error || "$variant" == *pin8 ]]; then
    check "$(stat -c %s "$c/downloads")" 0 "$app/$variant no silent older-release fallback"
    local previous=7.10.4
    [[ "$role" != install ]] || previous=old
    check "$(cat "$c/home/.ampache")" "$previous" "$app/$variant failed selection leaves marker unchanged"
  fi
}
runtime_hooks_retry_assert() {
  check "$(cat "$c/home/.ampache")" 7.10.5 "$app/$variant retry selects same supported line"
  check "$(cat "$c/opt/ampache/config/ampache.cfg.php")" 'saved database configuration' "$app/$variant retry retains configuration"
  check "$(cat "$c/opt/ampache/music/canary")" 'saved music' "$app/$variant retry retains media"
}
runtime_hooks_main "$@"
