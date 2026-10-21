#!/usr/bin/env bash
# Native Caddy validation + HTTP; PHP/database/build/service commands are models.
set -euo pipefail
systemd-detect-virt --vm --quiet || exit 1
: "${TMPDIR:?}" "${MAINTENANCE_NEXT_REFERENCES:?}" "${MAINTENANCE_CADDY:?}"
ROOT=$(realpath "$(dirname "${BASH_SOURCE[0]}")/..")
if [[ "${1:-}" == --hook ]]; then
  c="$CASE_DIR"
  source "$ROOT/misc/core.func"
  source "$ROOT/misc/error_handler.func"
  source "$ROOT/misc/tools.func"
  load_functions
  source "$c/hook"
  header_info() { :; }
  check_container_storage() { :; }
  check_container_resources() { :; }
  cleanup_lxc() { :; }
  setup_php() { :; }
  setup_mariadb() { :; }
  setup_mariadb_db() { export MARIADB_DB_PASS=fixture-password; }
  ensure_dependencies() { :; }
  getent() { return 0; }
  apt() { :; }
  usermod() { :; }
  chown() { :; }
  su() { :; }
  sleep() { :; }
  php() { printf 8.3; }
  openssl() { printf 'fixture-password-abcdefghijklmn'; }
  mariadb() { printf 'wt_user\n'; }
  systemctl() { printf '%s\n' "$*" >> "$c/services"; }
  caddy() {
    printf '%s\n' "$*" >> "$c/validation"
    [[ ! -f "$c/original" ]] || cmp -s "$c/original" "$c/etc/caddy/Caddyfile" || {
      printf violated > "$c/validation-order"
      return 61
    }
    if [[ "$FAULT" == validate ]]; then
      local arg previous=''
      for arg in "$@"; do
        [[ "$previous" != --config ]] || printf '\ninvalid_caddy_directive\n' >> "$arg"
        previous="$arg"
      done
    fi
    "$MAINTENANCE_CADDY" "$@"
  }
  check_for_gh_release() {
    [[ "$FAULT" != metadata ]] || return 37
    case "$CASE" in repair | simple-root | trailing-root | quoted-root | unrelated-root | ambiguous-root | validate) return 1 ;; esac
    return 0
  }
  curl() {
    [[ "$*" != *'http://127.0.0.1/'* ]] || return 0
    local out='' format=''
    while (($#)); do
      case "$1" in -o)
        out="$2"
        shift
        ;;
      -w)
        format="$2"
        shift
        ;;
      esac
      shift
    done
    if [[ -n "$out" ]]; then printf '{"tag_name":"2.2.6","assets":[{"browser_download_url":"https://fixture.invalid/webtrees-2.2.6.zip"}]}' > "$out"; else printf '{"tag_name":"2.2.6","assets":[]}'; fi
    [[ -z "$format" ]] || printf 200
  }
  curl_download() {
    [[ "$FAULT" != download ]] || return 22
    (
      cd "$c/payload"
      zip -qr "$1" .
    )
  }
  cp() {
    if [[ "$FAULT" == copy && "${!#}" == /opt/webtrees* && "$*" == *'/deploy-source.'* ]]; then
      command cp -a -- "$3" "${!#}"
      return 41
    fi
    command cp "$@"
  }
  catch_errors
  if [[ "$CASE" == fresh* ]]; then install_script; else run_update_script; fi
  exit
elif [[ "${1:-}" == --child ]]; then
  c="$CASE_DIR"
  mount --bind "$c/opt" /opt
  mount --bind "$c/cache" /var/cache
  mount --bind "$c/state" /var/lib/scripts-underground/update-pending
  ip link set lo up
  original_server=''
  if [[ "$FAULT" == validate ]]; then
    "$MAINTENANCE_CADDY" run --config "$c/etc/caddy/Caddyfile" --adapter caddyfile > "$c/original-server.log" 2>&1 &
    original_server=$!
    trap 'kill "$original_server" 2>/dev/null || true; wait "$original_server" 2>/dev/null || true' EXIT
    ready=no
    for attempt in {1..80}; do
      if command curl -fsS http://127.0.0.1:18080/healthz > "$c/original-health" 2> /dev/null; then
        ready=yes
        break
      fi
      sleep .05
    done
    [[ "$ready" == yes ]] || {
      printf 'Original Caddy readiness failed after %s attempts\n' "$attempt" >&2
      exit 1
    }
  fi
  rc=0
  bash "$0" --hook > "$c/output" 2>&1 || rc=$?
  printf '%s' "$rc" > "$c/status"
  if [[ -n "$original_server" ]]; then
    kill -0 "$original_server"
    command curl -fsS http://127.0.0.1:18080/healthz > "$c/after-health"
    cmp -s "$c/original-health" "$c/after-health"
    printf preserved > "$c/original-state"
  fi
  [[ "$rc" == 0 ]] || exit 0
  if [[ "$CASE" == repair ]]; then
    before=$(stat -c '%i:%s:%a:%u:%g:%Y' "$c/etc/caddy/Caddyfile")
    cp -p -- "$c/etc/caddy/Caddyfile" "$c/original"
    repeated=0
    bash "$0" --hook > "$c/repeated-output" 2>&1 || repeated=$?
    printf '%s' "$repeated" > "$c/repeated-status"
    after=$(stat -c '%i:%s:%a:%u:%g:%Y' "$c/etc/caddy/Caddyfile")
    [[ "$before" != "$after" ]] || printf unchanged > "$c/repeated-metadata"
  fi
  python3 - "$c" "$MAINTENANCE_CADDY" << 'PY'
import hashlib,json,os,pathlib,subprocess,sys,time,urllib.error,urllib.request
c=pathlib.Path(sys.argv[1]);config=c/'etc/caddy/Caddyfile';log=(c/'caddy.log').open('wb');p=subprocess.Popen([sys.argv[2],'run','--config',str(config),'--adapter','caddyfile'],stdout=log,stderr=log,env=dict(os.environ,HOME=str(c/'home'),XDG_CONFIG_HOME=str(c/'home/config'),XDG_DATA_HOME=str(c/'home/data')))
try:
 for _ in range(60):
  try:
   with urllib.request.urlopen('http://127.0.0.1:18080/public/css/webtrees.min.css',timeout=1):break
  except (OSError,urllib.error.URLError):time.sleep(.05)
 else:raise RuntimeError('native Caddy HTTP readiness failed')
 results={}
 for name in ('data/private.bin','app/private.bin','modules_v4/private.bin','resources/private.bin','vendor/private.bin','.env','data/.htaccess','public/css/webtrees.min.css','public/js/webtrees.min.js'):
  try:
   with urllib.request.urlopen('http://127.0.0.1:18080/'+name,timeout=3) as response:status=response.status;body=response.read()
  except urllib.error.HTTPError as response:status=response.code;body=response.read()
  results[name]={'status':status,'sha256':hashlib.sha256(body).hexdigest()}
 (c/'http.json').write_text(json.dumps(results))
finally:
 p.terminate()
 try:p.wait(timeout=5)
 except subprocess.TimeoutExpired:p.kill();p.wait()
 log.close()
PY
  exit
fi
work=$(mktemp -d "$TMPDIR/webtrees-http.XXXXXX")
trap 'rm -rf -- "$work"' EXIT
failures=0
check() { if [[ "$1" == "$2" ]]; then printf 'PASS %s\n' "$3"; else
  printf 'FAIL %s expected <%s>, got <%s>\n' "$3" "$2" "$1" >&2
  failures=$((failures + 1))
fi; }
for mode in no yes; do
  for variant in fresh repair update simple-root trailing-root quoted-root unrelated-root ambiguous-root validate fresh-validate download copy metadata; do
    c="$work/$mode-$variant"
    fault=none
    case "$variant" in *validate) fault=validate ;; download | copy | metadata) fault="$variant" ;; esac
    mkdir -p "$c/"{opt/webtrees/data,etc/caddy,home,cache,state,payload/public/css,payload/public/js,payload/data}
    for directory in app data modules_v4 resources vendor; do
      mkdir -p "$c/opt/webtrees/$directory"
      printf 'USER PRIVATE BYTES\n' > "$c/opt/webtrees/$directory/private.bin"
      mkdir -p "$c/payload/$directory"
      printf 'SOURCE PRIVATE BYTES\n' > "$c/payload/$directory/private.bin"
    done
    printf 'USER SECRET\n' > "$c/opt/webtrees/.env"
    printf 'SOURCE SECRET\n' > "$c/payload/.env"
    cp "$MAINTENANCE_NEXT_REFERENCES/webtrees/data/.htaccess" "$c/payload/data/.htaccess"
    cp "$MAINTENANCE_NEXT_REFERENCES/webtrees/public/css/webtrees.min.css" "$c/payload/public/css/"
    cp "$MAINTENANCE_NEXT_REFERENCES/webtrees/public/js/webtrees.min.js" "$c/payload/public/js/"
    cp -a "$c/payload/public" "$c/opt/webtrees/"
    cp "$c/payload/data/.htaccess" "$c/opt/webtrees/data/"
    printf '2.2.6\n' > "$c/home/.webtrees"
    cat > "$c/etc/caddy/Caddyfile" << 'CF'
http://127.0.0.1:18080 {
    # USER CUSTOM CONFIGURATION
    root * /opt/webtrees
    header X-User-Custom retained
    respond /healthz "USER HEALTH"
    php_fastcgi unix//run/php/php8.3-fpm.sock
    file_server
    encode gzip
}
CF
    python3 - "$c/etc/caddy/Caddyfile" "$variant" << 'PY'
import pathlib,sys
p=pathlib.Path(sys.argv[1]);s=p.read_text();variant=sys.argv[2]
forms={'simple-root':'root /opt/webtrees','trailing-root':'root * /opt/webtrees/','quoted-root':'root "/opt/webtrees/"','unrelated-root':'root /srv/unrelated','ambiguous-root':'root * /opt/webtrees\n    root /opt/webtrees/'}
if variant in forms:p.write_text(s.replace('root * /opt/webtrees',forms[variant]))
PY
    cp -p "$c/etc/caddy/Caddyfile" "$c/original"
    original_metadata=$(stat -c '%i:%s:%a:%u:%g:%Y:%Z' "$c/etc/caddy/Caddyfile")
    : > "$c/services"
    : > "$c/validation"
    python3 - "$ROOT/scripts/lxc/webtrees.sh" "$c" << 'PY'
import pathlib,subprocess,sys
p,c=map(pathlib.Path,sys.argv[1:]);text=subprocess.check_output(['bash','-c','curl() { :; }; source "$1"; declare -f install_script update_script','cold',str(p)],text=True);text=text.replace('/etc/caddy/',str(c/'etc/caddy')+'/').replace(':80 {','http://127.0.0.1:18080 {');(c/'hook').write_text(text)
PY
    rc=0
    env CASE_DIR="$c" CASE="$variant" FAULT="$fault" MAINTENANCE_CADDY="$MAINTENANCE_CADDY" TMPDIR="$TMPDIR" HOME="$c/home" APP=Webtrees NSAPP=webtrees LOCAL_IP=127.0.0.1 VERBOSE="$mode" FORCE_DEPLOY=1 UPDATE_FORCE=1 BUILD_LOG="$c/build.log" DEBUG_LOGFILE="$c/error.log" \
      unshare -mn --propagation private -- bash "$0" --child > "$c/driver-output" 2>&1 || rc=$?
    check "$rc" 0 "webtrees/$mode/$variant native fixture driver status"
    expected=0
    case "$fault" in validate) expected=1 ;; download) expected=250 ;; copy) expected=252 ;; metadata) expected=37 ;; esac
    case "$variant" in unrelated-root | ambiguous-root) expected=65 ;; esac
    check "$(cat "$c/status" 2> /dev/null || true)" "$expected" "webtrees/$mode/$variant actual cold-hook status"
    if [[ "$(cat "$c/status" 2> /dev/null || true)" != "$expected" ]]; then
      python3 - "$c/output" << 'PY'
import pathlib,sys
for line in pathlib.Path(sys.argv[1]).read_text().splitlines()[-8:]:print('DIAG webtrees '+line)
PY
    fi
    if [[ "$variant" == unrelated-root || "$variant" == ambiguous-root ]]; then
      preserved=0
      cmp -s "$c/original" "$c/etc/caddy/Caddyfile" || preserved=$?
      check "$preserved" 0 "webtrees/$mode/$variant unsupported root retains original custom bytes"
      check "$(stat -c %s "$c/services")" 0 "webtrees/$mode/$variant unsupported root fails before service effects"
    elif [[ "$fault" == validate ]]; then
      status=0
      cmp -s "$c/original" "$c/etc/caddy/Caddyfile" || status=$?
      check "$status" 0 "webtrees/$mode/$variant native validation failure preserves original bytes"
      check "$(stat -c '%i:%s:%a:%u:%g:%Y:%Z' "$c/etc/caddy/Caddyfile")" "$original_metadata" "webtrees/$mode/$variant failed validation preserves config inode and metadata"
      check "$(cat "$c/original-state" 2> /dev/null || true)" preserved "webtrees/$mode/$variant native original Caddy process and HTTP state survive rejected candidate"
      check "$(stat -c %s "$c/services")" 0 "webtrees/$mode/$variant validation precedes service effects"
    else
      if [[ "$(cat "$c/status" 2> /dev/null || true)" == 0 ]]; then
        status=0
        python3 - "$c/http.json" "$MAINTENANCE_NEXT_REFERENCES/webtrees" << 'PY' || status=$?
import hashlib,json,pathlib,sys
d=json.loads(pathlib.Path(sys.argv[1]).read_text());root=pathlib.Path(sys.argv[2])
for name,row in d.items():
 if name.startswith('public/'):assert row=={'status':200,'sha256':hashlib.sha256((root/name).read_bytes()).hexdigest()},(name,row)
 else:assert row['status']==403,(name,row)
PY
        check "$status" 0 "webtrees/$mode/$variant native403 private vs200 exact upstream public assets"
      fi
      if [[ "$variant" != fresh ]]; then
        check "$(grep -c '# USER CUSTOM CONFIGURATION' "$c/etc/caddy/Caddyfile")" 1 "webtrees/$mode/$variant custom configuration retained"
        check "$(cat "$c/opt/webtrees/data/private.bin" 2> /dev/null || true)" 'USER PRIVATE BYTES' "webtrees/$mode/$variant live user data preserved"
      fi
    fi
    check "$(test -e "$c/validation-order" && printf violated || printf unchanged)" unchanged "webtrees/$mode/$variant original config unchanged at validation boundary"
    if [[ "$variant" != unrelated-root && "$variant" != ambiguous-root ]]; then check "$(test -s "$c/validation" && printf validated || printf missing)" validated "webtrees/$mode/$variant native validation actually called"; fi
    if [[ "$variant" == repair ]]; then
      check "$(cat "$c/repeated-status" 2> /dev/null || true)" 0 "webtrees/$mode repeated same-version repair succeeds"
      check "$(cat "$c/repeated-metadata" 2> /dev/null || true)" unchanged "webtrees/$mode repeated repair preserves published config inode and metadata"
      check "$(grep -c 'reload-or-restart caddy' "$c/services" || true)" 1 "webtrees/$mode repeated repair does not reload unchanged configuration"
    fi
    rm -rf -- "$c"
  done
done
printf '%s failure(s); native Caddy validation/HTTP/files; PHP/database/build/service commands modeled\n' "$failures"
[[ "$failures" == 0 ]]
