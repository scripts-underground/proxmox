#!/usr/bin/env bash
# Actual six app hooks, release/Go helpers and update owner. Downloaded builds,
# package/runtime provisioning and services are models; files/parser/HTTP are real.
set -euo pipefail
systemd-detect-virt --vm --quiet || exit 1
: "${TMPDIR:?disk-backed TMPDIR required}"
case "$(realpath -e "$TMPDIR")" in /tmp | /tmp/*) exit 1 ;; esac
ROOT=$(realpath "$(dirname "${BASH_SOURCE[0]}")/..")
if [[ "${1:-}" == --child ]]; then
  c="$CASE_ROOT"
  mount --bind "$c/opt" /opt
  mount --bind "$c/local" /usr/local
  mount --bind "$c/cache" /var/cache
  mount --bind "$c/state" /var/lib/scripts-underground/update-pending
  source "$ROOT/misc/core.func"
  source "$ROOT/misc/error_handler.func"
  source "$ROOT/misc/tools.func"
  load_functions
  source "$c/hooks.sh"
  if [[ "$APP_CASE:$ROLE" == pelican-panel:update ]]; then
    # Consumed by the actual dynamically loaded hook/shared replacement owner.
    # shellcheck disable=SC2034
    CLEAN_INSTALL_KEEP=caller-legacy
    # shellcheck disable=SC2034
    CLEAN_INSTALL_KEEP_PATHS=('caller array with space')
  fi
  header_info() { :; }
  check_container_storage() { :; }
  check_container_resources() { :; }
  cleanup_lxc() { :; }
  ensure_dependencies() { :; }
  getent() { return 0; }
  apt() { :; }
  setup_java() { :; }
  setup_uv() { :; }
  setup_nodejs() { printf '%s\n' "$NODE_VERSION" >> "$c/node-versions"; }
  setup_postgresql() { :; }
  setup_postgresql_db() {
    export PG_DB_NAME PG_DB_USER
    export PG_DB_PASS=secret
  }
  setup_php() { :; }
  setup_composer() { :; }
  setup_mariadb() { :; }
  setup_mariadb_db() { :; }
  cleanup_legacy_install() { :; }
  cleanup_old_repo_files() { :; }
  cp() {
    if [[ "$FAULT" == copy && "${!#}" == /opt/pelican-panel/ ]]; then
      printf 'partial code\n' > /opt/pelican-panel/code
      return 41
    fi
    command cp "$@"
  }
  crontab() { command cat > "$c/crontab"; }
  a2ensite() { :; }
  a2enmod() { :; }
  a2dissite() { :; }
  update-alternatives() { :; }
  uv() {
    mkdir -p /opt/apprise/.venv/bin
    touch /opt/apprise/.venv/bin/{supervisord,gunicorn}
  }
  npm() {
    printf '%s|%s\n' "$PWD" "$*" >> "$c/npm-calls"
    [[ "$FAULT" != build ]] || return 51
    [[ "$PWD" == /opt/wikijs ]] || return 63
  }
  composer() {
    [[ "$FAULT" != build ]] || return 51
    mkdir -p /opt/pelican-panel/vendor
    printf '<?php require "/usr/share/php/Dotenv/autoload.php";\n' > /opt/pelican-panel/vendor/autoload.php
    [[ -e /opt/pelican-panel/.env ]] || cp /opt/pelican-panel/.env.example /opt/pelican-panel/.env
  }
  php() {
    if [[ "$1" == -v ]]; then
      printf 'PHP 8.4.26\n'
      return
    fi
    if [[ "$1" == -r ]]; then
      command /usr/bin/php "$@"
      return
    fi
    printf '%s\n' "$*" >> "$c/artisan-calls"
    if [[ "$2" == p:environment:setup ]]; then
      local arg url='' noninteractive=no
      for arg in "$@"; do case "$arg" in --url=*) url=${arg#--url=} ;; --no-interaction) noninteractive=yes ;; esac done
      if [[ -z "$url" || "$noninteractive" != yes ]]; then
        read -r arg || return 59
        return 59
      fi
      [[ "$FAULT" != setup ]] || return 52
      printf '%s' "$url" > "$c/url-consumer"
    fi
  }
  go() {
    printf '%s\n' "$*" >> "$c/go-calls"
    [[ "$FAULT" != build ]] || return 51
    local previous='' arg
    for arg in "$@"; do
      [[ "$previous" != -o ]] || {
        printf '#!/usr/bin/env bash\nprintf "new gluetun\\n"\n' > "$arg"
        chmod 0755 "$arg"
      }
      previous="$arg"
    done
  }
  systemctl() {
    printf '%s\n' "$*" >> "$c/services"
    if [[ "$APP_CASE" == gluetun && ("$1" == start || " $* " == *' --now '*) ]]; then
      /usr/local/bin/go version > "$c/go-consumer"
    fi
    if [[ "$APP_CASE" == onedev && ("$1" == start || "$1" == stop) ]]; then
      [[ -f "$c/etc/systemd/system/$2.service" ]] || return 54
    fi
    if [[ "$1" == start || "$1" == reload ]]; then
      find "/opt/$APP_DIR" -maxdepth 2 -type f -name origin -exec cat {} \; > "$c/service-consumer"
    fi
  }
  make_archive() {
    local out="$1" url="$2" d
    d=$(mktemp -d "$TMPDIR/download.XXXXXX")
    mkdir "$d/package"
    cp -a "$c/payload/." "$d/package/"
    printf '%s\n' "$url" > "$d/package/origin"
    if [[ "$APP_CASE" == sonarr ]]; then
      local tag=4.9.0 selected_arch=unknown
      [[ "$url" != *v5.* ]] || tag=5.0.0
      [[ "$url" != *v4.8.0* ]] || tag=4.8.0
      case "$url" in *linux-x64.tar.gz) selected_arch=amd64 ;; *linux-arm64.tar.gz) selected_arch=arm64 ;; esac
      printf '#!/usr/bin/env bash\nprintf "Sonarr %s %s\\n"\n' "$tag" "$selected_arch" > "$d/package/Sonarr"
      chmod 0755 "$d/package/Sonarr"
    fi
    if [[ "$APP_CASE" == onedev ]]; then
      artifact_version=2.0.0
      [[ "$VARIANT" != drift && "$VARIANT" != fresh-drift ]] || artifact_version=2.1.0
      if [[ "$VARIANT" == drift-retry && "${ATTEMPT:-first}" == first ]]; then
        artifact_version=2.1.0
        mkdir -p "$d/package/lib"
        printf 'FAILED ARCHIVE ONLY\n' > "$d/package/lib/first-only.jar"
      fi
      printf 'version=%s\n' "$artifact_version" > "$d/package/release.properties"
      [[ "$VARIANT" != bad-version ]] || printf 'version=invalid\n' > "$d/package/release.properties"
      [[ "$VARIANT" != missing-version ]] || rm "$d/package/release.properties"
      mv "$d/package" "$d/onedev-latest"
      tar -czf "$out" -C "$d" onedev-latest
    else tar -czf "$out" -C "$d" package; fi
    rm -rf "$d"
  }
  curl_download() {
    [[ "$FAULT" != download ]] || return 22
    make_archive "$1" "$2"
  }
  curl_with_retry() {
    local url="$1" out="$2" version d
    if [[ "$url" == *'?mode=json'* ]]; then
      printf '[{"version":"go1.26.8","stable":true,"files":[{"os":"linux","arch":"amd64","kind":"archive"}]}]' > "$out"
      return 0
    fi
    if [[ "$out" == - ]]; then
      printf 'go9.99.0\n'
      return 0
    fi
    version=${url##*/go}
    version=${version%%.linux-*}
    printf '%s\n' "$version" >> "$c/go-downloads"
    d=$(mktemp -d "$TMPDIR/go-build.XXXXXX")
    mkdir -p "$d/go/bin"
    printf '#!/usr/bin/env bash\nprintf "go version go%s linux/amd64\\n"\n' "$version" > "$d/go/bin/go"
    cp "$d/go/bin/go" "$d/go/bin/gofmt"
    chmod 0755 "$d/go/bin/"*
    tar -czf "$out" -C "$d" go
    rm -rf "$d"
  }
  curl() {
    local out='' url='' format='' body tag=v2.0.0 asset=app.tar.gz
    while (($#)); do
      case "$1" in -o)
        out="$2"
        shift
        ;;
      -w)
        format="$2"
        shift
        ;;
      https:*) url="$1" ;; esac
      shift
    done
    printf '%s\n' "$url" >> "$c/network"
    if [[ "$url" == *code.onedev.io* ]]; then
      [[ "$url" == *'/~sites/public/'* && "$FAULT" != download ]] || return 22
      make_archive "$out" "$url"
      return
    fi
    if [[ "$APP_CASE" == sonarr ]]; then
      body='{"tag_name":"v5.0.0","assets":[{"browser_download_url":"https://fixture.invalid/v5.0.0/Sonarr.main.5.linux-x64.tar.gz"},{"browser_download_url":"https://fixture.invalid/v5.0.0/Sonarr.main.5.linux-arm64.tar.gz"}]}'
      if [[ "$url" == *'/tags/v4.8.0' ]]; then body='{"tag_name":"v4.8.0","assets":[{"browser_download_url":"https://fixture.invalid/v4.8.0/Sonarr.main.4.8.linux-x64.tar.gz"}]}'; fi
      if [[ "$url" == *'releases?per_page='* ]]; then
        body="[$body,{\"tag_name\":\"v4.9.0\",\"assets\":[{\"browser_download_url\":\"https://fixture.invalid/v4.9.0/Sonarr.main.4.linux-x64.tar.gz\"},{\"browser_download_url\":\"https://fixture.invalid/v4.9.0/Sonarr.main.4.linux-arm64.tar.gz\"}]}]"
      fi
    else
      if [[ "$APP_CASE" == wikijs && "$url" != *wiki-v2* ]]; then tag=v3.0.0; fi
      [[ "$url" != *'/tags/v3.0.0' ]] || tag=v3.0.0
      [[ "$APP_CASE" != wikijs ]] || asset=wiki-js.tar.gz
      [[ "$APP_CASE" != pelican-panel ]] || asset=panel.tar.gz
      [[ "$APP_CASE:${ASSET_REV:-first}" != apprise-api:second ]] || tag=v2.1.0
      body="{\"tag_name\":\"$tag\",\"assets\":[{\"browser_download_url\":\"https://fixture.invalid/$asset\"}]}"
    fi
    printf '%s' "$body" > "$out"
    [[ -z "$format" ]] || printf 200
  }
  dpkg() { if [[ "$1" == --print-architecture ]]; then printf '%s\n' "$ARCH"; else return 97; fi; }
  catch_errors
  if [[ "$ROLE" == install ]]; then install_script; else run_update_script; fi
  exit
fi
: "${APPRISE_ASSET_FIXTURE:?provide actual source CSS}" "${APPRISE_ASSET_PATH:?provide its relative path}" "${APPRISE_SUPERVISOR_FIXTURE:?provide upstream supervisor config}"
work=$(mktemp -d "$TMPDIR/app-compat.XXXXXX")
server_pid=''
cleanup_test() {
  if [[ -n "$server_pid" ]]; then
    kill "$server_pid" 2> /dev/null || true
    wait "$server_pid" 2> /dev/null || true
  fi
  rm -rf "$work"
}
trap cleanup_test EXIT
failures=0
check() {
  if [[ "$1" == "$2" ]]; then printf 'PASS %s\n' "$3"; else
    printf 'FAIL %s expected <%s>, got <%s>\n' "$3" "$2" "$1" >&2
    failures=$((failures + 1))
  fi
}
for app in onedev apprise-api pelican-panel sonarr wikijs gluetun; do
  case "$app" in
    onedev) variants='fresh fresh-drift old new transition download upgrade drift missing-version bad-version upgrade-version drift-retry' ;;
    apprise-api) variants='fresh existing download' ;;
    pelican-panel) variants='fresh double single plain empty invalid database-space database-space-copy build setup download' ;;
    sonarr) variants='fresh-amd64 fresh-arm64 update-amd64 update-arm64 pin download' ;;
    wikijs) variants='fresh postgres sqlite sqlite-v3-pin rebuild download' ;;
    gluetun) variants='fresh selected pin malformed build download' ;;
  esac
  for mode in no yes; do
    for variant in $variants; do
      c="$work/$app-$mode-$variant"
      role=update fault=none arch=amd64 pin='' version_pin=''
      [[ "$app:$variant" != sonarr:pin ]] || version_pin=v4.8.0
      [[ "$variant" != sqlite-v3-pin ]] || version_pin=v3.0.0
      case "$variant" in fresh*) role=install ;; download | build | setup | upgrade) fault="$variant" ;; rebuild) fault=build ;; esac
      [[ "$variant" != database-space-copy ]] || fault=copy
      [[ "$variant" != *arm64 ]] || arch=arm64
      case "$app" in apprise-api) dir=apprise ;; sonarr) dir=Sonarr ;; *) dir="$app" ;; esac
      mkdir -p "$c/"{opt,local/bin,cache,state,home,tmp,etc/systemd/system,etc/nginx,etc/apache2/sites-available,config/store,attach,plugin,apprise-tmp,html,payload/bin,payload/server,sonarr-data}
      app_root="$c/opt/$dir"
      if [[ "$app" == onedev ]]; then
        mkdir -p "$c/opt/onedev-latest" "$c/payload/lib"
        printf 'UNKNOWN ORIGINAL DIRECTORY\n' > "$c/opt/onedev-latest/unknown.jar"
        printf 'CURRENT ARCHIVE\n' > "$c/payload/lib/current.jar"
      fi
      if [[ "$role" != install || "$app" != onedev ]]; then mkdir -p "$app_root"; fi
      mkdir -p "$c/payload/"{data,storage/app/public,bootstrap/cache,database,apprise_api/static/css,apprise_api/etc}
      printf 'new code\n' > "$c/payload/code"
      printf 'sample\n' > "$c/payload/config.sample.yml"
      printf 'APP_URL=http://panel.test\nAPP_KEY=base64:DEFAULT\n' > "$c/payload/.env.example"
      printf 'module fixture\ngo 1.26\n' > "$c/payload/go.mod"
      printf 'requirements\n' > "$c/payload/requirements.txt"
      cp "$APPRISE_ASSET_FIXTURE" "$c/payload/apprise_api/static/$APPRISE_ASSET_PATH"
      if [[ "$app:$variant" == apprise-api:existing ]]; then
        mkdir -p "$c/html/s/$(dirname "$APPRISE_ASSET_PATH")"
        printf 'stale browser asset\n' > "$c/html/s/$APPRISE_ASSET_PATH"
      fi
      cp "$APPRISE_SUPERVISOR_FIXTURE" "$c/payload/apprise_api/etc/supervisord.conf"
      printf '#!/usr/bin/env bash\nexit 0\n' > "$c/payload/apprise_api/supervisord-startup"
      cat > "$c/payload/bin/server.sh" << 'SERVER'
#!/usr/bin/env bash
printf 'new server\n' > "$(dirname "${BASH_SOURCE[0]}")/../version"
touch "$CASE_ROOT/etc/systemd/system/onedev.server.service"
SERVER
      cat > "$c/payload/bin/upgrade.sh" << 'UPGRADE'
#!/usr/bin/env bash
[[ "$FAULT" != upgrade ]] || exit 53
printf 'new server\n' > "$1/version"
cp "$(dirname "${BASH_SOURCE[0]}")/../release.properties" "$1/release.properties"
mkdir -p "$1/lib"
cp -a "$(dirname "${BASH_SOURCE[0]}")/../lib/." "$1/lib/"
if [[ "$VARIANT" == upgrade-version ]]; then printf 'version=8.0.0\n' > "$1/release.properties"; fi
if [[ "$VARIANT" == transition ]]; then rm "$CASE_ROOT/etc/systemd/system/onedev.service"; touch "$CASE_ROOT/etc/systemd/system/onedev.server.service"; fi
UPGRADE
      chmod 0755 "$c/payload/bin/"* "$c/payload/apprise_api/supervisord-startup"
      printf 'USER settings\n' > "$c/config/store/config.yml"
      printf 'USER attachment\n' > "$c/attach/file"
      printf 'USER nginx override\n' > "$c/etc/nginx/server-override.conf"
      printf 'USER Sonarr settings\n' > "$c/sonarr-data/config.xml"
      mkdir -p "$c/opt/gluetun-data"
      printf 'USER VPN credentials/port\n' > "$c/opt/gluetun-data/.env"
      printf 'USER VPN library\n' > "$c/opt/gluetun-data/servers.json"
      if [[ "$role" == update ]]; then printf 'custom unit/port\n' > "$c/etc/systemd/system/$app.service"; fi
      printf 'old\n' > "$c/home/.${app/apprise-api/apprise}"
      printf 'existing profile\n' > "$c/home/.profile"
      if [[ "$role" == update ]]; then
        mkdir -p "$app_root/data" "$app_root/storage/app/public" "$app_root/database"
        printf 'old code\n' > "$app_root/code"
        printf 'USER wiki config\n' > "$app_root/config.yml"
        printf 'USER wiki data\n' > "$app_root/data/row"
        printf 'USER upload\n' > "$app_root/storage/app/public/file"
        printf 'USER SQLite bytes\n' > "$app_root/database/panel.sqlite"
        printf 'USER SQLite WAL\n' > "$app_root/database/panel.sqlite-wal"
        printf 'old server\n' > "$app_root/version"
        if [[ "$app" == wikijs && ("$variant" == sqlite || "$variant" == rebuild || "$variant" == sqlite-v3-pin) ]]; then printf 'USER SQLite\n' > "$app_root/db.sqlite"; fi
        if [[ -f "$app_root/db.sqlite" ]]; then printf 'USER wiki WAL\n' > "$app_root/db.sqlite-wal"; fi
        if [[ "$app" == onedev ]]; then
          rm -f "$c/etc/systemd/system/onedev.service"
          if [[ "$variant" == new ]]; then touch "$c/etc/systemd/system/onedev.server.service"; else touch "$c/etc/systemd/system/onedev.service"; fi
        fi
      fi
      url="https://panel.example.test:9443/custom?owner=O'Reilly"
      if [[ "$app" == pelican-panel && "$role" == update ]]; then
        printf 'USER legacy keep\n' > "$app_root/caller-legacy"
        printf 'USER array keep\n' > "$app_root/caller array with space"
        printf 'DEFAULT legacy\n' > "$c/payload/caller-legacy"
        printf 'DEFAULT array\n' > "$c/payload/caller array with space"
        if [[ "$variant" == database-space* ]]; then
          mv "$app_root/database/panel.sqlite" "$app_root/database/custom name.sqlite"
          mv "$app_root/database/panel.sqlite-wal" "$app_root/database/custom name.sqlite-wal"
          printf 'USER SQLite SHM\n' > "$app_root/database/custom name.sqlite-shm"
          printf 'USER SQLite journal\n' > "$app_root/database/custom name.sqlite-journal"
          printf 'DEFAULT SQLite\n' > "$c/payload/database/custom name.sqlite"
        fi
        case "$variant" in single) url=https://single.example/path ;; plain) url=http://panel.test ;; empty) url='' ;; invalid) url=not-a-url ;; esac
        case "$variant" in single) printf "APP_URL='%s'\n" "$url" > "$app_root/.env" ;; plain | empty | invalid) printf 'APP_URL=%s\n' "$url" > "$app_root/.env" ;; *) printf 'APP_URL="%s"\n' "$url" > "$app_root/.env" ;; esac
        printf 'APP_KEY=base64:USER\nDB_PASSWORD="USER secret"\n' >> "$app_root/.env"
        if [[ "$variant" == database-space* ]]; then printf 'DB_CONNECTION=sqlite\nDB_DATABASE="/opt/pelican-panel/database/custom name.sqlite"\n' >> "$app_root/.env"; fi
        env_before=$(sha256sum "$app_root/.env")
        env_before=${env_before%% *}
      fi
      if [[ "$app" == gluetun ]]; then
        printf '#!/usr/bin/env bash\nprintf "go version go1.22.0 linux/amd64\\n"\n' > "$c/local/bin/go"
        printf '#!/usr/bin/env bash\nprintf "old gluetun\\n"\n' > "$c/local/bin/gluetun"
        chmod 0755 "$c/local/bin/"*
        [[ "$variant" != pin ]] || pin=1.28.1
        [[ "$variant" != selected ]] || printf 'module fixture\ngo 1.26.3\n' > "$c/payload/go.mod"
        [[ "$variant" != malformed ]] || printf 'module fixture\ngo nonsense\n' > "$c/payload/go.mod"
      fi
      : > "$c/services"
      : > "$c/npm-calls"
      : > "$c/network"
      : > "$c/go-calls"
      : > "$c/artisan-calls"
      python3 - "$ROOT/scripts/lxc/$app.sh" "$c" << 'PY'
import pathlib,re,sys
p=pathlib.Path(sys.argv[1]);c=pathlib.Path(sys.argv[2]);s=p.read_text()
hooks='\n'.join(m[0] for m in re.finditer(r'^function (?:install_script|update_script)\(\) \{\n.*?^\}',s,re.M|re.S))
mapping={'/etc':str(c/'etc'),'/config':str(c/'config'),'/attach':str(c/'attach'),'/plugin':str(c/'plugin'),'/tmp/apprise':str(c/'apprise-tmp'),'/usr/share/nginx/html':str(c/'html'),'/usr/sbin':str(c/'sbin'),'/var/lib/sonarr':str(c/'sonarr-data'),'/gluetun':str(c/'gluetun-link')}
pattern=r'(?<![A-Za-z0-9_./-])('+ '|'.join(re.escape(k) for k in sorted(mapping,key=len,reverse=True))+r')(?=/|[\s\"\x27]|$)'
hooks=re.sub(pattern,lambda m:mapping[m[0]],hooks);(c/'hooks.sh').write_text(hooks)
PY
      mkdir -p "$c/sbin"
      rc=0
      env -i PATH="$PATH" TMPDIR="$c/tmp" HOME="$c/home" CASE_ROOT="$c" APP_CASE="$app" APP_DIR="$dir" APP="$app" NSAPP="$app" ROLE="$role" VARIANT="$variant" FAULT="$fault" ARCH="$arch" GO_VERSION="$pin" var_appversion="$version_pin" LOCAL_IP=10.55.66.77 VERBOSE="$mode" \
        BUILD_LOG="$c/helper.log" DEBUG_LOGFILE="$c/error.log" APPRISE_ASSET_PATH="$APPRISE_ASSET_PATH" unshare -m --propagation private -- bash "$0" --child < /dev/null > "$c/output" 2>&1 || rc=$?
      expected=0
      case "$fault" in download) expected=22 ;; build) expected=51 ;; setup) expected=52 ;; upgrade) expected=53 ;; copy) expected=252 ;; esac
      [[ "$fault" != download || "$app" == onedev ]] || expected=250
      if [[ "$app" == onedev ]]; then
        case "$variant" in drift | fresh-drift | upgrade-version | drift-retry) expected=250 ;; missing-version | bad-version) expected=65 ;; esac
      fi
      if [[ "$app:$variant" == pelican-panel:empty || "$app:$variant" == pelican-panel:invalid || "$app:$variant" == gluetun:malformed ]]; then expected=65; fi
      check "$rc" "$expected" "$app/$mode/$variant actual hook status"
      if [[ "$rc" != "$expected" ]]; then
        python3 - "$c/output" "$app/$mode/$variant" << 'PY'
import pathlib,sys
for line in pathlib.Path(sys.argv[1]).read_text().splitlines()[-10:]:print('DIAG '+sys.argv[2]+' '+line)
PY
      fi
      if [[ "$expected" != 0 ]]; then check "$(grep -Ec '^(start|reload)' "$c/services" || true)" 0 "$app/$variant failure never restarts service"; fi
      if [[ "$expected" != 0 && "$app" == pelican-panel ]]; then check "$(grep -c '^artisan up$' "$c/artisan-calls" || true)" 0 "$app/$variant failed update never exits maintenance mode"; fi
      case "$app" in
        onedev)
          check "$(cat "$c/opt/onedev-latest/unknown.jar" 2> /dev/null || true)" 'UNKNOWN ORIGINAL DIRECTORY' "$app/$variant unknown legacy extraction path retained"
          stage_count=$(
            python3 - "$c/opt" << 'PY'
import pathlib,sys
print(len(list(pathlib.Path(sys.argv[1]).glob('.onedev-release.*'))))
PY
          )
          check "$stage_count" 0 "$app/$variant owned extraction stages cleaned on every outcome"
          if [[ "$expected" != 0 ]]; then check "$(cat "$c/home/.onedev")" old "$app/$variant failure retains previous own marker"; fi
          if [[ "$expected" == 0 ]]; then
            check "$(cat "$app_root/version" 2> /dev/null || true)" 'new server' "$app/$variant upgraded consumer bytes"
            check "$(cat "$c/home/.onedev")" v2.0.0 "$app/$variant own release marker"
            service=onedev
            [[ "$variant" != fresh && "$variant" != new && "$variant" != transition ]] || service=onedev.server
            check "$(grep -c "^start $service$" "$c/services" || true)" 1 "$app/$variant starts installed old/new unit"
          fi
          if [[ "$variant" == drift-retry ]]; then
            retry_rc=0
            env -i PATH="$PATH" TMPDIR="$c/tmp" HOME="$c/home" CASE_ROOT="$c" APP_CASE="$app" APP_DIR="$dir" APP="$app" NSAPP="$app" ROLE=update VARIANT="$variant" ATTEMPT=second FAULT=none ARCH="$arch" VERBOSE="$mode" BUILD_LOG="$c/retry.log" DEBUG_LOGFILE="$c/retry-error.log" \
              unshare -m --propagation private -- bash "$0" --child < /dev/null > "$c/retry-output" 2>&1 || retry_rc=$?
            check "$retry_rc" 0 "$app/$mode drift then clean archive retry succeeds"
            check "$(test -e "$app_root/lib/first-only.jar" && printf mixed || printf absent)" absent "$app/$mode retry never mixes a failed archive's old-only jar"
            check "$(cat "$app_root/lib/current.jar" 2> /dev/null || true)" 'CURRENT ARCHIVE' "$app/$mode retry publishes current archive jar"
            check "$(cat "$app_root/config.yml" 2> /dev/null || true)" 'USER wiki config' "$app/$mode retry preserves installed custom config"
          fi
          ;;
        pelican-panel)
          if [[ "$role" == update ]]; then
            after=$(sha256sum "$app_root/.env" 2> /dev/null) || after=missing
            after=${after%% *}
            check "$after" "$env_before" "$app/$variant complete custom env retained"
            check "$(cat "$app_root/caller-legacy" 2> /dev/null || true)" 'USER legacy keep' "$app/$variant legacy caller keep retained"
            check "$(cat "$app_root/caller array with space" 2> /dev/null || true)" 'USER array keep' "$app/$variant inherited lossless caller keep retained"
            check "$(cat "$app_root/storage/app/public/file" 2> /dev/null || true)" 'USER upload' "$app/$variant upload retained"
            database_path="$app_root/database/panel.sqlite"
            [[ "$variant" != database-space* ]] || database_path="$app_root/database/custom name.sqlite"
            check "$(cat "$database_path" 2> /dev/null || true)" 'USER SQLite bytes' "$app/$variant database retained"
            check "$(cat "$database_path-wal" 2> /dev/null || true)" 'USER SQLite WAL' "$app/$variant SQLite sidecar retained"
            if [[ "$variant" == database-space* ]]; then
              check "$(cat "$database_path-shm" 2> /dev/null || true)" 'USER SQLite SHM' "$app/$variant whitespace SHM retained"
              check "$(cat "$database_path-journal" 2> /dev/null || true)" 'USER SQLite journal' "$app/$variant whitespace journal retained"
            fi
          else url=http://10.55.66.77; fi
          if [[ "$expected" == 0 ]]; then check "$(cat "$c/url-consumer" 2> /dev/null || true)" "$url" "$app/$variant decoded URL reaches noninteractive command consumer"; fi
          ;;
        sonarr)
          check "$(cat "$c/sonarr-data/config.xml")" 'USER Sonarr settings' "$app/$variant external settings retained"
          wanted_tag=4.9.0
          [[ "$variant" != pin ]] || wanted_tag=4.8.0
          if [[ "$expected" == 0 ]]; then check "$("$app_root/Sonarr" 2> /dev/null || true)" "Sonarr $wanted_tag $arch" "$app/$variant actual selected architecture/stable payload consumer"; fi
          ;;
        wikijs)
          if [[ "$role" == update ]]; then
            check "$(cat "$app_root/config.yml" 2> /dev/null || true)" 'USER wiki config' "$app/$variant existing configuration retained"
            check "$(cat "$app_root/data/row" 2> /dev/null || true)" 'USER wiki data' "$app/$variant data retained"
          fi
          if [[ "$expected" == 0 ]]; then check "$(grep -c 'requarks/wiki-v2' "$c/network" || true)" "$([[ "$role" == install || "$variant" == sqlite-v3-pin ]] && printf 1 || printf 2)" "$app/$variant checker/deployer use canonical v2 source"; fi
          if [[ "$variant" == sqlite-v3-pin ]]; then
            check "$(grep -c 'SQLite is not supported' "$c/output" || true)" 1 "$app explicit v3 pin reaches retained SQLite guard"
            check "$(cat "$app_root/code")" 'old code' "$app rejected v3 pin never replaces SQLite app code"
            check "$(cat "$app_root/db.sqlite")" 'USER SQLite' "$app rejected v3 pin retains SQLite bytes"
          fi
          if [[ "$variant" == sqlite || "$variant" == rebuild ]]; then
            check "$(cat "$app_root/db.sqlite")" 'USER SQLite' "$app/$variant SQLite bytes retained"
            check "$(cat "$app_root/db.sqlite-wal" 2> /dev/null || true)" 'USER wiki WAL' "$app/$variant SQLite sidecar retained"
            check "$(wc -l < "$c/npm-calls")" 1 "$app/$variant SQLite rebuild remains conditional"
          else check "$(wc -l < "$c/npm-calls")" 0 "$app/$variant no unconditional SQLite rebuild"; fi
          ;;
        gluetun)
          if [[ "$role" == update ]]; then
            check "$(cat "$c/opt/gluetun-data/.env")" 'USER VPN credentials/port' "$app/$variant external VPN settings retained"
            check "$(cat "$c/opt/gluetun-data/servers.json")" 'USER VPN library' "$app/$variant server library retained"
          fi
          if [[ "$expected" == 0 ]]; then
            wanted=1.26.8
            [[ "$variant" != pin ]] || wanted=1.28.1
            [[ "$variant" != selected ]] || wanted=1.26.8
            check "$(cat "$c/go-consumer" 2> /dev/null || true)" "go version go$wanted linux/amd64" "$app/$variant actual selected Go runtime artifact consumer"
            check "$(grep -c 'passteque/gluetun' "$c/network" || true)" "$([[ "$role" == update ]] && printf 2 || printf 1)" "$app/$variant canonical selected source"
          fi
          ;;
        apprise-api)
          check "$(cat "$c/config/store/config.yml")" 'USER settings' "$app/$variant config retained"
          check "$(cat "$c/attach/file")" 'USER attachment' "$app/$variant attachment retained"
          if [[ "$expected" == 0 ]]; then
            # A real HTTP consumer reads the exact path documented by upstream
            # nginx's /s root. This is a fixture server, not a full app install.
            python3 - "$c/html" "$c/port" << 'PY' > "$c/http.log" 2>&1 &
import http.server,pathlib,sys
from functools import partial
s=http.server.HTTPServer(('127.0.0.1',0),partial(http.server.SimpleHTTPRequestHandler,directory=sys.argv[1]));pathlib.Path(sys.argv[2]).write_text(str(s.server_port));s.serve_forever()
PY
            server_pid=$!
            for ((i = 0; i < 100; i++)); do
              [[ ! -s "$c/port" ]] || break
              sleep 0.02
            done
            status=0
            python3 - "http://127.0.0.1:$(cat "$c/port")/s/$APPRISE_ASSET_PATH" "$c/http-asset" << 'PY' || status=$?
import pathlib,sys,urllib.request
with urllib.request.urlopen(sys.argv[1],timeout=5) as r:pathlib.Path(sys.argv[2]).write_bytes(r.read())
PY
            check "$status" 0 "$app/$variant native HTTP /s consumer status"
            check "$(cmp -s "$APPRISE_ASSET_FIXTURE" "$c/http-asset" && printf same || printf different)" same "$app/$variant actual upstream asset bytes served"
            printf '\n/* repeated fixture revision */\n' >> "$c/payload/apprise_api/static/$APPRISE_ASSET_PATH"
            repeat_rc=0
            env -i PATH="$PATH" TMPDIR="$c/tmp" HOME="$c/home" CASE_ROOT="$c" APP_CASE="$app" APP_DIR="$dir" APP="$app" NSAPP="$app" ROLE=update VARIANT="$variant" FAULT=none ARCH="$arch" GO_VERSION='' LOCAL_IP=10.55.66.77 VERBOSE="$mode" ASSET_REV=second \
              BUILD_LOG="$c/repeat.log" DEBUG_LOGFILE="$c/repeat-error.log" APPRISE_ASSET_PATH="$APPRISE_ASSET_PATH" unshare -m --propagation private -- bash "$0" --child < /dev/null > "$c/repeat-output" 2>&1 || repeat_rc=$?
            check "$repeat_rc" 0 "$app/$variant repeated actual update status"
            status=0
            python3 - "http://127.0.0.1:$(cat "$c/port")/s/$APPRISE_ASSET_PATH" "$c/http-second-asset" << 'PY' || status=$?
import pathlib,sys,urllib.request
with urllib.request.urlopen(sys.argv[1],timeout=5) as r:pathlib.Path(sys.argv[2]).write_bytes(r.read())
PY
            check "$status" 0 "$app/$variant repeated native HTTP status"
            check "$(cmp -s "$c/payload/apprise_api/static/$APPRISE_ASSET_PATH" "$c/http-second-asset" && printf same || printf stale)" same "$app/$variant repeated /s asset consumer sees changed bytes"
            kill "$server_pid"
            wait "$server_pid" 2> /dev/null || true
            server_pid=''
          fi
          ;;
      esac
      if [[ "$variant" == database-space-copy ]]; then
        check "$(cat "$app_root/code")" 'old code' 'Pelican whitespace failed copy restores old code'
        check "$(cat "$c/home/.pelican-panel")" old 'Pelican whitespace failed copy retains own marker'
        check "$(test -f "$c/state/pelican-panel" && printf present || printf absent)" present 'Pelican whitespace failure retains pending flag'
        retry_rc=0
        env -i PATH="$PATH" TMPDIR="$c/tmp" HOME="$c/home" CASE_ROOT="$c" APP_CASE="$app" APP_DIR="$dir" APP="$app" NSAPP="$app" ROLE=update VARIANT="$variant" FAULT=none ARCH="$arch" GO_VERSION='' LOCAL_IP=10.55.66.77 VERBOSE="$mode" \
          BUILD_LOG="$c/retry.log" DEBUG_LOGFILE="$c/retry-error.log" APPRISE_ASSET_PATH="$APPRISE_ASSET_PATH" unshare -m --propagation private -- bash "$0" --child < /dev/null > "$c/retry-output" 2>&1 || retry_rc=$?
        check "$retry_rc" 0 'Pelican whitespace pending retry status'
        check "$(cat "$c/url-consumer" 2> /dev/null || true)" "$url" 'Pelican whitespace retry real Dotenv URL reaches consumer'
        check "$(cat "$app_root/code")" 'new code' 'Pelican whitespace retry publishes new code'
        check "$(cat "$database_path")" 'USER SQLite bytes' 'Pelican whitespace retry database bytes'
        check "$(cat "$database_path-wal")" 'USER SQLite WAL' 'Pelican whitespace retry WAL bytes'
        check "$(cat "$database_path-shm")" 'USER SQLite SHM' 'Pelican whitespace retry SHM bytes'
        check "$(cat "$database_path-journal")" 'USER SQLite journal' 'Pelican whitespace retry journal bytes'
        check "$(test -f "$c/state/pelican-panel" && printf present || printf absent)" absent 'Pelican whitespace successful retry clears pending flag'
      fi
    done
  done
done
printf '%s failure(s); actual hooks/helpers/files/PHP parser/HTTP, external builds/services modeled\n' "$failures"
[[ "$failures" == 0 ]]
