#!/usr/bin/env bash
# Real cold bundles, release selection, ZIP deployment and backup/restore.
# Package, PHP/database provisioning, HTTP transport and service effects are models.
# shellcheck disable=SC2034,SC2154
set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/../lib/runtime-hooks/harness.sh"
app=ampache
script_type=lxc
variants=(fresh fresh-media fresh-kept-data fresh-missing-asset fresh-pin8 update ipv6 current pending pin8 missing-asset checker-error download extract backup copy partial restore permissions ownership query stop stopped-missing-asset stopped-download stopped-backup stopped-copy media-files media-missing-asset kept-data mounted-restore-missing mounted-restore-partial local-restore-missing local-restore-partial runtime)
hook_paths=(/var/www www)
runtime_hooks_model() {
  [[ "$APP_FAULT" != pin8 ]] || var_appversion=8.4.0
  if [[ "$c" == *-media-* || "$c" == *-fresh-media ]]; then
    mount --bind "$c/external/media" '/opt/ampache/external media [live]*?'
  fi
  if [[ "$c" == *-mounted-restore-* ]]; then
    mount --bind "$c/opt/ampache/config" /opt/ampache/config
  fi
  if [[ "$c" == *-kept-data ]]; then
    CLEAN_INSTALL_KEEP=legacy-media
    CLEAN_INSTALL_KEEP_PATHS=('user library' alias/library)
  fi
  sha256sum() {
    local input
    input=$(readlink /proc/self/fd/0) || return $?
    case "$input" in
      */ampache/music/* | *'/external media [live]*?/'* | *'/ampache/user library/'* | */ampache/legacy-media/*) printf '%s\n' "$input" >> "$c/media-reads" ;;
    esac
    command sha256sum "$@"
  }
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
  get_lxc_ip() {
    LOCAL_IP=10.20.30.40
    [[ "$APP_FAULT" != ipv6 ]] || LOCAL_IP=2001:db8::40
  }
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
    [[ "$APP_FAULT" != extract ]] || printf 'invalid ZIP\n' > "$1"
  }
  cp() {
    if [[ "$APP_FAULT" == *-restore-* && "$1" == -a && "$3" == /opt/ampache.backup/files/opt/ampache/config/ampache.cfg.php ]]; then
      [[ "$APP_FAULT" != *-restore-partial ]] || printf 'partial config\n' > /opt/ampache/config/ampache.cfg.php
      printf 'restore copy failed after removal\n' > "$c/restore-consumer"
      return 43
    fi
    if [[ "$APP_FAULT" == backup && "${!#}" == /opt/ampache.backup/files/* ]]; then return 42; fi
    if [[ "$APP_FAULT" == copy || "$APP_FAULT" == partial ]] && [[ "${!#}" == /opt/ampache/* && "$*" == *'/deploy-source.'* ]]; then
      command cp "$@"
      [[ "$APP_FAULT" != partial ]] || printf 'unverified mutation\n' > /opt/ampache/.env
      return 41
    fi
    command cp "$@"
  }
  chmod() {
    [[ "$APP_FAULT" != permissions || "$*" != *'/opt/ampache/public/rest/.htaccess'* ]] || return 44
    command chmod "$@"
  }
  chown() {
    command chown "$@" || return $?
    [[ "$APP_FAULT" != ownership || "$*" != *'/opt/ampache'* ]] || return 45
  }
  rm() {
    [[ "$APP_FAULT" != restore || "${!#}" != /opt/ampache/config/ampache.cfg.php ]] || return 43
    command rm "$@"
  }
  systemctl() {
    if [[ "$1" == stop && "$c" == *-media-* ]]; then
      printf '%s\n' "${before:-unobserved}" > "$c/runtime-fingerprint"
    fi
    if [[ "$1" == show ]]; then
      [[ "$APP_FAULT" != query ]] || return 53
      cat "$c/recovery-state"
      return
    fi
    if [[ "$1" == stop && "$APP_FAULT" == stop ]]; then return 55; fi
    if [[ "$1" == start && "$APP_FAULT" == runtime ]]; then
      printf 'failed-start apache2\n' >> "$c/services"
      return 51
    fi
    if [[ -f "$c/recovery-service" ]]; then runtime_hooks_recovery_service "$@"; else printf '%s\n' "$*" >> "$c/services"; fi
  }
}
runtime_hooks_variant() {
  [[ "$variant" != fresh-media && "$variant" != fresh-kept-data ]] || role=install
  case "$variant" in missing-asset | checker-error | pin8 | ipv6 | extract | backup | partial | restore | permissions | ownership | query | stop) fault="$variant" ;; esac
  [[ "$variant" != stopped-* ]] || fault="${variant#stopped-}"
  [[ "$variant" != media-missing-asset ]] || fault=missing-asset
  [[ "$variant" != *-restore-* ]] || fault="$variant"
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
  case "$fault" in
    missing-asset | copy | partial) expected=252 ;;
    checker-error) expected=22 ;;
    pin8) expected=65 ;;
    extract) expected=251 ;;
    backup) expected=42 ;;
    restore | *-restore-*) expected=43 ;;
    permissions) expected=44 ;;
    ownership) expected=45 ;;
    query) expected=53 ;;
    stop) expected=55 ;;
  esac
}
runtime_hooks_setup() {
  mkdir -p "$c/www/html"
  : > "$c/downloads"
  : > "$c/php-calls"
  : > "$c/media-reads"
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
  if [[ "$variant" == *kept-data ]]; then
    mkdir -p "$c/opt/ampache/user library" "$c/opt/ampache/legacy-media" "$c/external/library"
    printf 'operator data\n' > "$c/opt/ampache/user library/canary"
    printf 'operator data\n' > "$c/opt/ampache/legacy-media/canary"
    printf 'operator data\n' > "$c/external/library/canary"
    ln -s "$c/external" "$c/opt/ampache/alias"
    python3 - "$c/release.zip" << 'PY'
import sys,zipfile
with zipfile.ZipFile(sys.argv[1],'a') as archive:
    for path in ('user library/canary','legacy-media/canary','alias/library/canary'):
        archive.writestr(path,'archive defaults\n')
PY
  fi
  if [[ "$variant" == fresh-media ]]; then
    mkdir -p "$c/opt/ampache/music" "$c/external/media" "$c/opt/ampache/external media [live]*?"
    printf 'saved music\n' > "$c/opt/ampache/music/canary"
    printf 'mounted media bytes\n' > "$c/external/media/track"
    ln -s "$c/external/credential" "$c/opt/ampache/external-credential"
    python3 - "$c/release.zip" << 'PY'
import sys,zipfile
with zipfile.ZipFile(sys.argv[1],'a') as archive: archive.writestr('music/canary','archive media defaults\n')
PY
  fi
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
    if [[ "$variant" == *-restore-* ]]; then
      # Same-version forced repair: deploy code and marker are byte-identical,
      # so only the mounted configuration consumer exposes the failed restore.
      printf '7.10.5\n' > "$c/home/.ampache"
      printf 'interrupted update\n' > "$c/state/ampache"
      unzip -qo "$c/release.zip" -d "$c/opt/ampache"
    fi
    [[ "$variant" != pending ]] || printf 'interrupted update\n' > "$c/state/ampache"
    if [[ "$variant" == media-* ]]; then
      mkdir -p "$c/external/media" "$c/opt/ampache/external media [live]*?"
      printf 'mounted media bytes\n' > "$c/external/media/track"
      ln -s "$c/external/credential" "$c/opt/ampache/external-credential"
      python3 - "$c/release.zip" << 'PY'
import sys,zipfile
with zipfile.ZipFile(sys.argv[1],'a') as archive: archive.writestr('music/canary','archive media defaults\n')
PY
    fi
    local initial=active
    [[ "$variant" != stopped-* ]] || initial=inactive
    runtime_hooks_recovery_setup apache2 "$initial" "$c/opt/ampache" "$c/home/.ampache"
  fi
}
runtime_hooks_assert() {
  if [[ "$variant" == *kept-data ]]; then
    local path
    check "$(stat -c %s "$c/media-reads")" 0 "$app/$variant declared persistent data never reaches hashing"
    for path in "$c/opt/ampache/user library/canary" "$c/opt/ampache/legacy-media/canary" "$c/external/library/canary"; do
      check "$(cat "$path")" 'operator data' "$app/$variant declared persistent bytes retained"
      check "$(stat -c %u:%g "$path")" 0:0 "$app/$variant declared persistent ownership retained"
    done
    check "$(stat -c %u:%g "$c/opt/ampache/alias")" 0:0 "$app/$variant kept symlink ancestor ownership retained"
  fi
  if [[ "$variant" == media-* ]]; then
    check "$(stat -c %s "$c/media-reads")" 0 "$app/$variant runtime verification never reads media or same-device mount contents"
    local fingerprint_status=0
    python3 - "$c/runtime-fingerprint" << 'PY' || fingerprint_status=$?
import pathlib,re,sys
assert re.fullmatch(rb'[0-9a-f]{64}  -\n',pathlib.Path(sys.argv[1]).read_bytes())
PY
    check "$fingerprint_status" 0 "$app/$variant fingerprint exposes one text checksum, not binary metadata"
  fi
  if [[ "$variant" == media-* || "$variant" == fresh-media ]]; then
    check "$(cat "$c/opt/ampache/music/canary")" 'saved music' "$app/$variant archive defaults cannot replace library data"
    check "$(stat -c %u:%g "$c/opt/ampache/music/canary")" 0:0 "$app/$variant library ownership remains operator-owned"
    check "$(stat -c %u:%g "$c/external/media/track")" 0:0 "$app/$variant mounted data ownership remains operator-owned"
    check "$(stat -c %u:%g "$c/external/credential")" 0:0 "$app/$variant ownership never follows an external symlink"
  fi
  if [[ "$role" == update ]]; then
    if [[ "$variant" == *-restore-* ]]; then
      check "$(cat "$c/restore-consumer")" 'restore copy failed after removal' "$app/$variant destructive restore reached copy failure"
      local config=missing
      [[ ! -f "$c/opt/ampache/config/ampache.cfg.php" ]] || config=$(cat "$c/opt/ampache/config/ampache.cfg.php")
      [[ "$variant" != *-restore-partial ]] || check "$config" 'partial config' "$app/$variant partial bytes observed at config consumer"
      [[ "$variant" != *-restore-missing ]] || check "$config" missing "$app/$variant missing file observed at config consumer"
      check "$(cat "$c/recovery-state")" inactive "$app/$variant incomplete config cannot start Apache"
    else
      check "$(cat "$c/opt/ampache/config/ampache.cfg.php")" 'saved database configuration' "$app/$variant saved configuration retained"
    fi
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
        local host=10.20.30.40
        [[ "$variant" != ipv6 ]] || host='[2001:db8::40]'
        check "$(grep -Fc "http://${host}/update.php" "$c/output" || true)" 1 "$app/$variant container-owned update URL"
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
  if [[ "$role" == update && "$rc" != 0 ]]; then
    check "$(grep -c 'Updated successfully!' "$c/output" || true)" 0 "$app/$variant failure cannot publish success"
    if [[ "$fault" == query ]]; then
      check "$(stat -c %s "$c/services")" 0 "$app/query failed state query precedes all service control"
    fi
  elif [[ "$role" == update && "$variant" != current ]]; then
    check "$(cat "$c/recovery-state")" active "$app/$variant successful deployment activates service"
  fi
}
runtime_hooks_retry_assert() {
  check "$(cat "$c/home/.ampache")" 7.10.5 "$app/$variant retry selects same supported line"
  check "$(cat "$c/opt/ampache/config/ampache.cfg.php")" 'saved database configuration' "$app/$variant retry retains configuration"
  check "$(cat "$c/opt/ampache/music/canary")" 'saved music' "$app/$variant retry retains media"
}
runtime_hooks_main "$@"
