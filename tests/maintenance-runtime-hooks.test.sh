#!/usr/bin/env bash
# Actual cold hooks/release helper/update owner/files/native config readers.
# Package/runtime provisioning, compilers, database and services are explicit models.
set -euo pipefail
systemd-detect-virt --vm --quiet || exit 1
: "${TMPDIR:?disk-backed TMPDIR required}" "${MAINTENANCE_REFERENCES:?immutable source metadata required}"
case "$(findmnt -rn -T "$TMPDIR" -o FSTYPE)" in '' | tmpfs | ramfs) exit 1 ;; esac
ROOT=$(realpath "$(dirname "${BASH_SOURCE[0]}")/..")
if [[ "${1:-}" == --child ]]; then
  c="$APP_FIXTURE"
  mount --bind "$c/opt" /opt
  mount --bind "$c/local" /usr/local
  mount --bind "$c/cache" /var/cache
  mount --bind "$c/state" /var/lib/scripts-underground/update-pending
  source "$ROOT/misc/core.func"
  source "$ROOT/misc/error_handler.func"
  source "$ROOT/misc/tools.func"
  load_functions
  source "$c/hooks.sh"
  header_info() { :; }
  check_container_storage() { :; }
  check_container_resources() { :; }
  cleanup_lxc() { :; }
  ensure_dependencies() { :; }
  getent() { return 0; }
  apt() {
    local arg
    for arg in "$@"; do
      if [[ "$arg" == *.deb ]]; then
        if [[ "$APP_CASE:$APP_ROLE" == thingsboard:update && "${DPKG_FORCE_CONFOLD:-}" != 1 ]]; then
          printf 'PACKAGE default settings\n' > "$c/etc/thingsboard/conf/thingsboard.conf"
        fi
        dpkg -i "$arg"
        return $?
      fi
    done
  }
  setup_rust() { :; }
  rustup() { :; }
  setup_ruby() { :; }
  setup_deb822_repo() { :; }
  setup_postgresql() { printf '%s\n' "${PG_VERSION:-unset}" >> "$c/db-major-calls"; }
  setup_postgresql_db() { export PG_DB_NAME PG_DB_USER PG_DB_PASS=fixture-db-secret; }
  setup_nodejs() {
    [[ "$APP_FAULT" != runtime ]] || return 51
    printf '%s\n' "$NODE_VERSION" > "$c/node-version"
  }
  setup_java() {
    [[ "$APP_FAULT" != runtime ]] || return 51
    printf '%s\n' "$JAVA_VERSION" > "$c/java-version"
  }
  setup_uv() {
    [[ "$APP_FAULT" != runtime ]] || return 51
    printf '%s\n' "$PYTHON_VERSION" > "$c/python-version"
  }
  htpasswd() { printf 'admin:fixture-hash\n' > /opt/radicale/users; }
  chown() { :; }
  rbenv() { printf ':\n'; }
  uv() {
    printf '%s\n' "$*" >> "$c/uv-calls"
    if [[ "$*" == *'python -'* ]]; then
      while [[ "$1" != python ]]; do shift; done
      shift
      /usr/bin/python3 "$@"
    fi
  }
  corepack() { printf '%s\n' "$*" >> "$c/corepack-calls"; }
  bundle() {
    printf '%s|%s|%s\n' "$PWD" "${RAILS_ENV:-unset}" "$*" >> "$c/bundle-calls"
    [[ "$APP_FAULT" != build ]] || return 52
    [[ "$PATH" == *"$HOME/.rbenv/shims"* && "${RAILS_ENV:-}" == production ]] || return 54
    [[ "${DISCOURSE_DB_PASSWORD:-}" == 'user db secret' ]] || [[ "$APP_ROLE" == install ]]
  }
  yarn() {
    printf '%s\n' "$*" >> "$c/yarn-calls"
    return 55
  }
  pnpm() {
    printf '%s|%s\n' "$PWD" "$*" >> "$c/pnpm-calls"
    [[ "$APP_FAULT" != build ]] || return 52
  }
  npm() {
    printf '%s|%s\n' "$PWD" "$*" >> "$c/npm-calls"
    [[ "$APP_FAULT" != build ]] || return 52
    if [[ "$PWD" == /opt/aliasvault/apps/web && "$*" == 'run build' ]]; then
      mkdir -p dist
      printf '<html>React source-layout consumer</html>\n' > dist/index.html
      printf '{"ApiUrl":"http://localhost:5100","SupportEmail":""}\n' > dist/appsettings.json
    fi
  }
  dotnet() {
    printf '%s\n' "$*" >> "$c/dotnet-calls"
    [[ "$APP_FAULT" != build ]] || return 52
    [[ "$*" != *AliasVault.Client* ]] || return 56
    case "$*" in *hash-password*) printf 'fixture-hash\n' ;; esac
  }
  git() {
    [[ "$APP_FAULT" != download ]] || return 22
    if [[ "$1" == clone ]]; then
      mkdir -p /opt/discourse
      command cp -a "$c/payload/." /opt/discourse/
    elif [[ "$1" == pull ]]; then printf 'new code\n' > /opt/discourse/code; fi
  }
  runuser() { printf '%s\n' "$*" >> "$c/runuser-calls"; }
  nginx() {
    printf '%s\n' "$*" >> "$c/nginx-calls"
    [[ "$APP_FAULT" != nginx ]] || return 61
  }
  a2ensite() { :; }
  dpkg() {
    if [[ "$1" == --print-architecture ]]; then printf 'amd64\n'; else
      mkdir -p "$c/thingsboard/bin/install" "$c/etc/thingsboard/conf"
      printf '#!/usr/bin/env bash\nprintf "upgrade-consumer\\n" > "%s/db-upgrade"\n' "$c" > "$c/thingsboard/bin/install/upgrade.sh"
      printf '#!/usr/bin/env bash\nexit 0\n' > "$c/thingsboard/bin/install/install.sh"
      chmod 0755 "$c/thingsboard/bin/install/"*.sh
    fi
  }
  systemctl() {
    printf '%s\n' "$*" >> "$c/services"
    if [[ "$1" == start || " $* " == *' --now '* ]]; then
      [[ "$APP_CASE" != thingsboard || "$(cat "$c/java-version")" == 25 ]] || return 57
    fi
  }
  curl_download() {
    [[ "$APP_FAULT" != download ]] || return 22
    if [[ "$1" == *.deb ]]; then printf package > "$1"; else tar -czf "$1" -C "$c" payload; fi
  }
  curl() {
    local out='' url='' format='' body tag=v2.0.0
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
    [[ "$url" != *'/tags/'* ]] || tag=${url##*/}
    body="{\"tag_name\":\"$tag\",\"assets\":[{\"browser_download_url\":\"https://fixture.invalid/thingsboard-2.deb\"},{\"browser_download_url\":\"https://fixture.invalid/wasm-pack-v1-x86_64-unknown-linux-musl.tar.gz\"}]}"
    if [[ -n "$out" ]]; then printf '%s' "$body" > "$out"; else printf '%s' "$body"; fi
    [[ -z "$format" ]] || printf 200
  }
  cp() {
    if [[ "$APP_FAULT" == copy && "${!#}" == /opt/* ]]; then
      case "$*" in *'/deploy-source.'*)
        command cp -a -- "$3" "${!#}"
        return 41
        ;;
      esac
    fi
    command cp "$@"
  }
  catch_errors
  if [[ "$APP_ROLE" == install ]]; then install_script; else run_update_script; fi
  exit
fi
work=$(mktemp -d "$TMPDIR/runtime-hooks.XXXXXX")
trap 'rm -rf -- "$work"' EXIT
failures=0
check() {
  if [[ "$1" == "$2" ]]; then printf 'PASS %s\n' "$3"; else
    printf 'FAIL %s expected <%s>, got <%s>\n' "$3" "$2" "$1" >&2
    failures=$((failures + 1))
  fi
}
for app in radicale discourse thingsboard aliasvault; do
  for mode in no yes; do
    for variant in fresh update download build copy runtime; do
      [[ ("$app" != thingsboard && "$app" != radicale) || "$variant" != build ]] || continue
      [[ "$app" != discourse || "$variant" != copy ]] || continue
      [[ "$app" != discourse || "$variant" != runtime ]] || continue
      c="$work/$app-$mode-$variant"
      role=update fault=none
      [[ "$variant" != fresh ]] || role=install
      case "$variant" in download | build | copy | runtime) fault="$variant" ;; esac
      mkdir -p "$c/"{opt,local/bin,cache,state,home/.cargo,home/.rbenv/shims,etc/systemd/system,etc/nginx/sites-available,etc/nginx/sites-enabled,etc/radicale,etc/postgresql/16/main,payload,external,root}
      : > "$c/home/.cargo/env"
      printf 'old\n' > "$c/home/.$app"
      for log in services db-major-calls uv-calls corepack-calls bundle-calls yarn-calls pnpm-calls npm-calls dotnet-calls nginx-calls runuser-calls; do : > "$c/$log"; done
      printf '17\n' > "$c/java-version"
      printf 'old PostgreSQL data\n' > "$c/external/database"
      printf 'old credential\n' > "$c/external/credential"
      printf 'new code\n' > "$c/payload/code"
      mkdir -p "$c/payload/"{core,apps/server,apps/web,certificates}
      cat > "$c/payload/core/build-and-distribute.sh" << 'SH'
#!/usr/bin/env bash
[[ "$1" == --web ]] || { printf 'Unknown core build target: %s\n' "$1" >&2; exit 64; }
[[ "$APP_FAULT" != build ]] || exit 52
SH
      chmod 0755 "$c/payload/core/build-and-distribute.sh"
      cp "$MAINTENANCE_REFERENCES/radicale/pyproject.toml" "$c/payload/pyproject.toml"
      if [[ "$role" == update ]]; then
        mkdir -p "$c/opt/$app"
        printf 'old code\n' > "$c/opt/$app/code"
        printf 'USER settings\n' > "$c/opt/$app/.env"
      fi
      if [[ "$app" == radicale ]]; then
        mkdir -p "$c/radicale-data"
        printf 'USER calendar\n' > "$c/radicale-data/calendar"
        printf '[server]\nhosts=127.0.0.1:5522\n[auth]\nhtpasswd_filename=/opt/radicale/custom users\n[storage]\nfilesystem_folder=/opt/radicale/custom calendars\n' > "$c/etc/radicale/config"
        if [[ "$role" == update ]]; then
          mkdir -p "$c/opt/radicale/custom calendars"
          printf 'USER auth hashes\n' > "$c/opt/radicale/custom users"
          printf 'USER calendar\n' > "$c/opt/radicale/custom calendars/calendar"
          printf 'USER default auth\n' > "$c/opt/radicale/users"
          printf '[Unit]\nDescription=Custom Radicale\n[Service]\nWorkingDirectory=/opt/radicale\nExecStart=/usr/local/bin/uv run -m radicale --config %s/etc/radicale/config\nRestart=always\nEnvironment=USER_PORT=5522\n' "$c" > "$c/etc/systemd/system/radicale.service"
        fi
      elif [[ "$app" == discourse ]]; then
        printf 'local all all peer\n' > "$c/etc/postgresql/16/main/pg_hba.conf"
        if [[ "$role" == update ]]; then
          printf "RAILS_ENV=production\nDISCOURSE_DB_NAME=custom-discourse\nDISCOURSE_DB_PASSWORD='user db secret'\nSECRET_KEY_BASE='USER secret'\nDISCOURSE_HOSTNAME=forum.example.test:9443\n" > "$c/opt/discourse/.env"
          printf 'server {\n listen 9443;\n proxy_set_header X-Accel-Mapping /opt/discourse/public/=/downloads/;\n # USER custom rule\n}\n' > "$c/etc/nginx/sites-available/discourse"
          mkdir -p "$c/opt/discourse/public/uploads"
          printf 'USER forum upload\n' > "$c/opt/discourse/public/uploads/file"
        fi
      elif [[ "$app" == aliasvault && "$role" == update ]]; then
        mkdir -p "$c/opt/aliasvault/certificates/ssl" "$c/opt/aliasvault/data"
        printf 'USER private key\n' > "$c/opt/aliasvault/certificates/ssl/key.pem"
        printf 'USER database/upload\n' > "$c/opt/aliasvault/data/persisted"
      elif [[ "$app" == thingsboard && "$role" == update ]]; then
        mkdir -p "$c/thingsboard" "$c/etc/thingsboard/conf"
        printf 'USER database/port\n' > "$c/etc/thingsboard/conf/thingsboard.conf"
      fi
      python3 - "$ROOT/scripts/lxc/$app.sh" "$c" << 'PY'
import pathlib,re,subprocess,sys
p=pathlib.Path(sys.argv[1]);c=pathlib.Path(sys.argv[2])
# Use the same native declare-f boundary as real bundles; heredoc braces are data.
hooks=subprocess.check_output(['bash','-c','curl() { :; }; source "$1"; declare -f install_script update_script','hook-source',str(p)],text=True)
mapping={'/etc':str(c/'etc'),'/root':str(c/'root'),'/usr/share/thingsboard':str(c/'thingsboard'),'/var/lib/radicale':str(c/'radicale-data')}
pattern=r'(?<![A-Za-z0-9_./-])('+ '|'.join(re.escape(k) for k in sorted(mapping,key=len,reverse=True))+r')(?=/|[\s"\x27]|$)';hooks=re.sub(pattern,lambda m:mapping[m[0]],hooks);(c/'hooks.sh').write_text(hooks)
PY
      env_before=''
      if [[ -f "$c/opt/$app/.env" ]]; then
        env_before=$(sha256sum "$c/opt/$app/.env")
        env_before=${env_before%% *}
      fi
      rc=0
      env -i PATH="$PATH" HOME="$c/home" TMPDIR="$TMPDIR" APP_FIXTURE="$c" APP_CASE="$app" APP_ROLE="$role" APP_FAULT="$fault" APP="$app" NSAPP="$app" LOCAL_IP=10.20.30.40 VERBOSE="$mode" BUILD_LOG="$c/build.log" DEBUG_LOGFILE="$c/errors.log" MAINTENANCE_REFERENCES="$MAINTENANCE_REFERENCES" \
        unshare -m --propagation private -- bash "$0" --child < /dev/null > "$c/output" 2>&1 || rc=$?
      expected=0
      case "$fault" in download)
        expected=250
        [[ "$app" != discourse ]] || expected=22
        ;;
      build) expected=52 ;; copy) expected=252 ;; runtime) expected=51 ;; esac
      [[ "$app:$variant" != thingsboard:copy ]] || expected=0
      check "$rc" "$expected" "$app/$mode/$variant cold hook status"
      if [[ "$rc" != "$expected" ]]; then
        python3 - "$c/output" "$app/$variant" << 'PY'
import pathlib,sys
lines=pathlib.Path(sys.argv[1]).read_text().splitlines()
for line in lines:
 if any(word in line for word in ('unbound variable','No such file','exit code','Unknown core','unsupported')): print('DIAG '+sys.argv[2]+' '+line)
for line in lines[-4:]:print('DIAG '+sys.argv[2]+' '+line)
PY
      fi
      check "$(cat "$c/external/database")" 'old PostgreSQL data' "$app/$variant installed DB bytes retained"
      check "$(cat "$c/external/credential")" 'old credential' "$app/$variant external credential retained"
      if [[ "$role" == update && "$app" != thingsboard ]]; then
        after=$(sha256sum "$c/opt/$app/.env" 2> /dev/null) || after=missing
        check "${after%% *}" "$env_before" "$app/$variant complete existing configuration retained"
      fi
      if [[ "$role" == update ]]; then
        check "$(stat -c %s "$c/db-major-calls")" 0 "$app/$variant no installed DB major provisioning"
        check "$(test -f "$c/state/$app" && printf present || printf absent)" "$([[ "$expected" == 0 ]] && printf absent || printf present)" "$app/$variant pending flag reflects actual outcome"
      fi
      if [[ "$rc" != 0 ]]; then check "$(grep -Ec '^(start|reload|restart)|--now' "$c/services" || true)" 0 "$app/$variant failure never starts dependent services"; fi
      case "$app" in
        radicale)
          if [[ "$rc" == 0 ]]; then check "$(grep -c -- '--extra bcrypt --extra argon2' "$c/etc/systemd/system/radicale.service" || true)" 1 "$app/$variant supported metadata extras reach service"; fi
          if [[ "$role" == update ]]; then
            check "$(cat "$c/opt/radicale/custom users" 2> /dev/null || true)" 'USER auth hashes' "$app/$variant configured custom users retained"
            check "$(cat "$c/opt/radicale/custom calendars/calendar" 2> /dev/null || true)" 'USER calendar' "$app/$variant configured custom calendar retained"
            check "$(grep -c USER_PORT=5522 "$c/etc/systemd/system/radicale.service")" 1 "$app/$variant existing unit port setting retained"
          fi
          ;;
        discourse)
          if [[ "$role" == update ]]; then check "$(cat "$c/opt/discourse/public/uploads/file")" 'USER forum upload' "$app/$variant forum uploads retained"; fi
          if [[ "$rc" == 0 ]]; then
            check "$(grep -c 'discourse discourse-sidekiq' "$c/services" || true)" "$([[ "$role" == update ]] && printf 2 || printf 1)" "$app/$variant both service lifecycle participants"
            check "$(stat -c %s "$c/yarn-calls")" 0 "$app/$variant obsolete package manager never invoked"
            check "$(grep -c X-Accel-Mapping "$c/etc/nginx/sites-available/discourse" || true)" 0 "$app/$variant invalid stylesheet mapping removed"
          fi
          ;;
        thingsboard)
          if [[ "$rc" == 0 ]]; then check "$(cat "$c/java-version")" 25 "$app/$variant supported Java reaches package/upgrade consumer"; fi
          if [[ "$role" == update ]]; then check "$(cat "$c/etc/thingsboard/conf/thingsboard.conf")" 'USER database/port' "$app/$variant packaged config/DB secret/port retained"; fi
          ;;
        aliasvault)
          if [[ "$rc" == 0 ]]; then
            check "$(cat "$c/node-version" 2> /dev/null || true)" 24 "$app/$variant selected Node24"
            check "$(cat "$c/opt/aliasvault/client/wwwroot/index.html" 2> /dev/null || true)" '<html>React source-layout consumer</html>' "$app/$variant React build output reaches served root"
          fi
          if [[ "$role" == update ]]; then
            check "$(cat "$c/opt/aliasvault/certificates/ssl/key.pem" 2> /dev/null || true)" 'USER private key' "$app/$variant original certificate key retained"
            check "$(cat "$c/opt/aliasvault/data/persisted" 2> /dev/null || true)" 'USER database/upload' "$app/$variant internal persistent data retained"
          fi
          ;;
      esac
      if [[ "$role" == update && "$expected" != 0 ]]; then
        retry=0
        env -i PATH="$PATH" HOME="$c/home" TMPDIR="$TMPDIR" APP_FIXTURE="$c" APP_CASE="$app" APP_ROLE=update APP_FAULT=none APP="$app" NSAPP="$app" LOCAL_IP=10.20.30.40 VERBOSE="$mode" BUILD_LOG="$c/retry.log" DEBUG_LOGFILE="$c/retry-errors.log" MAINTENANCE_REFERENCES="$MAINTENANCE_REFERENCES" \
          unshare -m --propagation private -- bash "$0" --child < /dev/null > "$c/retry-output" 2>&1 || retry=$?
        check "$retry" 0 "$app/$variant cold pending retry succeeds"
        check "$(test -f "$c/state/$app" && printf present || printf absent)" absent "$app/$variant successful retry clears pending flag"
        check "$(cat "$c/external/database")" 'old PostgreSQL data' "$app/$variant retry preserves installed DB bytes"
        if [[ "$app" == aliasvault ]]; then
          check "$(cat "$c/opt/aliasvault/certificates/ssl/key.pem" 2> /dev/null || true)" 'USER private key' "$app/$variant retry retains original private key"
          check "$(cat "$c/opt/aliasvault/data/persisted" 2> /dev/null || true)" 'USER database/upload' "$app/$variant retry retains persisted app data"
        fi
      fi
    done
  done
done
printf '%s failure(s); actual cold hooks/helpers/files/config readers; external build/runtime/DB/service models\n' "$failures"
[[ "$failures" == 0 ]]
