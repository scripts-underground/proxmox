#!/usr/bin/env bash
# Native files, TOML, HTTP and cold child processes; engine/package/init are models.
set -euo pipefail
ROOT=$(realpath "$(dirname "${BASH_SOURCE[0]}")/../..")
if [[ "${1:-}" == --child ]]; then
  c="$CASE_ROOT"
  source "$ROOT/misc/core.func"
  sed -e "s|/usr/bin|$c/bin|g" -e "s|/etc/meilisearch.toml|$c/etc/meilisearch.toml|g" "$ROOT/misc/tools.func" > "$c/tools.func"
  source "$c/tools.func"
  export STD=''
  msg_info() { printf 'INFO %s\n' "$*" >> "$c/messages"; }
  msg_ok() { printf 'OK %s\n' "$*" >> "$c/messages"; }
  msg_error() { printf 'ERROR %s\n' "$*" >> "$c/messages"; }
  msg_warn() { :; }
  ensure_dependencies() { :; }
  get_system_arch() { printf amd64; }
  # The sourced setup_meilisearch owner consumes this returning checker's output.
  # shellcheck disable=SC2034
  check_for_gh_release() {
    CHECK_UPDATE_RELEASE="$SELECTED"
    [[ "$FAULT" != checker ]] || return 77
  }
  fetch_and_deploy_gh_release() {
    printf '%s\n' "$*" >> "$c/releases"
    [[ "$FAULT" != download ]] || return 18
    local target="${5:-$c/bin}"
    mkdir -p "$target"
    cp "$c/new-meilisearch" "$target/meilisearch"
    printf '%s\n' "${4:-$SELECTED}" > "$HOME/.meilisearch"
  }
  cp() {
    if [[ "$FAULT" == publication && "$*" == *'/bin/meilisearch '*'.asset-file.'* ]]; then return 41; fi
    command cp "$@"
  }
  stop_live() {
    if [[ -s "$c/live-pid" ]]; then
      local child
      child=$(cat "$c/live-pid")
      kill "$child" 2> /dev/null || true
      wait "$child" 2> /dev/null || true
      rm "$c/live-pid"
    fi
  }
  systemctl() {
    printf '%s\n' "$*" >> "$c/services"
    case "$1" in
      show)
        case "$*" in
          *ExecStart*) printf '{ path=%s/bin/meilisearch ; argv[]=%s/bin/meilisearch --config-file-path %s/etc/meilisearch.toml ; }\n' "$c" "$c" "$c" ;;
          *Environment*) printf '\n' ;;
          *WorkingDirectory*) printf '/\n' ;;
          *ActiveState*) cat "$c/state" ;;
        esac
        ;;
      stop)
        stop_live
        printf inactive > "$c/state"
        ;;
      start)
        if [[ "$FAULT" == restart && ! -e "$c/restart-failed" ]]; then
          : > "$c/restart-failed"
          return 53
        fi
        "$c/bin/meilisearch" --config-file-path "$c/etc/meilisearch.toml" > "$c/live.log" 2>&1 &
        printf '%s' "$!" > "$c/live-pid"
        for ((i = 0; i < 100; i++)); do
          if command curl -fsS "$LIVE_URL/health" > /dev/null 2>&1; then
            printf active > "$c/state"
            return 0
          fi
          sleep 0.02
        done
        return 54
        ;;
      is-active) [[ "$(cat "$c/state")" == active ]] ;;
    esac
  }
  trap stop_live EXIT
  rc=0
  setup_meilisearch || rc=$?
  printf '%s' "$rc" > "$c/rc"
  exit 0
fi
: "${TMPDIR:?disk TMPDIR required}"
systemd-detect-virt --vm --quiet || exit 65
work=$(mktemp -d "$TMPDIR/core-meilisearch.XXXXXX")
trap 'rm -rf -- "$work"' EXIT
cat > "$work/engine.py" << 'PY'
#!/usr/bin/env python3
import argparse,http.server,json,os,pathlib,sys,tomllib
VERSION='@VERSION@'
if '--version' in sys.argv: print('meilisearch '+VERSION);sys.exit()
p=argparse.ArgumentParser();p.add_argument('--config-file-path');p.add_argument('--db-path');p.add_argument('--dump-dir');p.add_argument('--snapshot-dir');p.add_argument('--http-addr');p.add_argument('--import-dump');a=p.parse_args()
c=pathlib.Path(os.environ['CASE_ROOT']);fault=os.environ['FAULT']
with open(a.config_file_path,'rb') as f: config=tomllib.load(f)
db=pathlib.Path(a.db_path or config['db_path']);db.mkdir(parents=True,exist_ok=True)
dump=pathlib.Path(a.dump_dir or config['dump_dir']);dump.mkdir(parents=True,exist_ok=True)
if a.import_dump:
    if fault=='import':sys.exit(51)
    doc=json.loads(pathlib.Path(a.import_dump).read_text())['document']
    (db/'document').write_text(doc if fault!='counts' else '')
host,port=(a.http_addr or config['http_addr']).rsplit(':',1)
class Handler(http.server.BaseHTTPRequestHandler):
    def log_message(self,*args):pass
    def send(self,data,status=200):
        body=json.dumps(data).encode();self.send_response(status);self.end_headers();self.wfile.write(body)
    def do_GET(self):
        if self.path=='/health':self.send({'status':'available'})
        elif self.path=='/version':self.send({'pkgVersion':VERSION})
        elif self.path=='/stats':self.send({'indexes':{'probe':{'numberOfDocuments':int((db/'document').is_file() and bool((db/'document').read_text()))}}})
        elif self.path.startswith('/tasks/'):
            self.send({'status':'failed' if fault=='dump-task' else 'succeeded','details':{'dumpUid':'fixture-dump'}})
        else:self.send({},404)
    def do_POST(self):
        if fault=='dump':self.send({},500);return
        if fault!='dump-missing':(dump/'fixture-dump.dump').write_text(json.dumps({'document':(db/'document').read_text()}))
        self.send({'taskUid':1})
http.server.HTTPServer((host,int(port)),Handler).serve_forever()
PY
failures=0
check() {
  if [[ "$1" == "$2" ]]; then printf 'PASS %s\n' "$3"; else
    printf 'FAIL %s: expected <%s>, got <%s>\n' "$3" "$2" "$1" >&2
    failures=$((failures + 1))
  fi
}
n=0
go() {
  n=$((n + 1))
  c="$work/$n"
  mkdir -p "$c/"{bin,etc,home} "$c/live data" "$c/dumps"
  printf 'retained document bytes\n' > "$c/live data/document"
  sed 's/@VERSION@/1.2.2/' "$work/engine.py" > "$c/bin/meilisearch"
  sed "s/@VERSION@/${SELECTED#v}/" "$work/engine.py" > "$c/new-meilisearch"
  chmod +x "$c/bin/meilisearch" "$c/new-meilisearch"
  local port
  port=$(python3 -c 'import socket;s=socket.socket();s.bind(("127.0.0.1",0));print(s.getsockname()[1])')
  printf 'db_path = "%s/live data"\ndump_dir = "%s/dumps"\nmaster_key = "private fixture secret"\nhttp_addr = "127.0.0.1:%s"\n' "$c" "$c" "$port" > "$c/etc/meilisearch.toml"
  [[ "$FAULT" != config ]] || printf 'db_path = [\n' > "$c/etc/meilisearch.toml"
  printf prior-marker > "$c/home/.meilisearch"
  printf active > "$c/state"
  : > "$c/messages"
  : > "$c/releases"
  : > "$c/services"
  env -i PATH="$PATH" TMPDIR="$TMPDIR" HOME="$c/home" CASE_ROOT="$c" FAULT="$FAULT" SELECTED="$SELECTED" LIVE_URL="http://127.0.0.1:$port" \
    BUILD_LOG="$c/build.log" DEBUG_LOGFILE="$c/errors.log" timeout 60 bash "$0" --child > "$c/output" 2>&1 || true
  rc=missing
  [[ ! -f "$c/rc" ]] || rc=$(cat "$c/rc")
}
for SELECTED in v1.2.3 v1.3.0; do
  for pair in 'download:18' 'dump:22' 'dump-task:150' 'dump-missing:65' 'import:150' 'counts:150' 'restart:53' 'publication:252' 'config:65' 'checker:77'; do
    FAULT="${pair%%:*}"
    go
    check "$rc" "${pair##*:}" "$SELECTED/$FAULT returning failure"
    check "$(cat "$c/live data/document" 2> /dev/null || true)" 'retained document bytes' "$SELECTED/$FAULT original data still at consumer path"
    check "$("$c/bin/meilisearch" --version)" 'meilisearch 1.2.2' "$SELECTED/$FAULT original binary restored"
    check "$(cat "$c/home/.meilisearch")" prior-marker "$SELECTED/$FAULT marker unchanged"
    check "$(grep -c 'OK Updated MeiliSearch' "$c/messages" || true)" 0 "$SELECTED/$FAULT no false update success"
  done
  FAULT=normal
  go
  check "$rc" 0 "$SELECTED actual patch/minor migration"
  check "$(cat "$c/live data/document")" 'retained document bytes' "$SELECTED imported document reaches live consumer"
  check "$(cat "$c/home/.meilisearch")" "${SELECTED#v}" "$SELECTED marker follows consumer"
  check "$(grep -c "singlefile ${SELECTED#v} " "$c/releases" || true)" 1 "$SELECTED exact selected binary, no latest race"
  old=$(find "$c" -path '*/original-data/document' -print -quit)
  check "$(cat "$old" 2> /dev/null || true)" 'retained document bytes' "$SELECTED original retained after successful migration"
done
SELECTED=v1.2.2 FAULT=dump go
check "$rc" 0 'same full version repair needs no incompatible-format dump'
check "$(cat "$c/live data/document")" 'retained document bytes' 'same-version repair retains its compatible data'
check "$(cat "$c/home/.meilisearch")" 1.2.2 'same-version marker follows the repaired consumer'
printf 'MEILISEARCH_FIXTURE failures=%s\n' "$failures"
[[ "$failures" == 0 ]]
