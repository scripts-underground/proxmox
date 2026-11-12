#!/usr/bin/env bash
# Actual cold bundles, checked replacement, Node parsing and files; compilation,
# PostgreSQL, systemd properties/control and package provisioning are modeled.
set -euo pipefail
ROOT=$(realpath "$(dirname "${BASH_SOURCE[0]}")/../..")
if [[ "${1:-}" == --closure-contract ]]; then
  mount --bind "$CASE_ROOT/opt" /opt
  mount --bind "$CASE_ROOT/srv" /srv
  mount --bind "$CASE_ROOT/mnt" /mnt
  exec "$RUNTIME_NODE" "$ROOT/tests/lib/bookorbit-path-contract.cjs" "$ROOT/scripts/lxc/bookorbit.sh"
fi
if [[ "${1:-}" == --child ]]; then
  c="$CASE_ROOT"
  mount --bind "$c/opt" /opt
  mount --bind "$c/srv" /srv
  mount --bind "$c/mnt" /mnt
  if [[ "$VARIANT" == *-bind || "$VARIANT" == root-bind ]]; then mount --bind /srv/bookorbit/dependent /mnt/books; fi
  if [[ "$VARIANT" == late-mount ]]; then mount --bind /srv/bookorbit/dependent /mnt/books; fi
  mount --bind "$c/units" /etc/systemd/system
  mount --bind "$c/local" /usr/local
  mount --bind "$c/cache" /var/cache
  mount --bind /var/lib/scripts-underground "$c/state/scripts-underground"
  mount --rbind "$c/state" /var/lib
  mount --bind "$c/pending" /var/lib/scripts-underground/update-pending
  mount --bind "$c/locks" /var/lib/scripts-underground/maintenance-locks
  mount --bind "$c/bin/systemctl" /usr/bin/systemctl
  if [[ -f "$c/request-root-link" ]]; then ln -sfn -- "$(cat "$c/request-root-link")" /opt/bookorbit; fi
  source "$ROOT/misc/bundle.func"
  source "$c/hooks.sh"
  : "${var_cpu:?source-selected CPU required}" "${var_ram:?source-selected RAM required}"
  export REPO_BASE=https://fixture.invalid
  export var_lxc_tmpdir="$TMPDIR"
  requirement_prefix=''
  if [[ "$ROLE" == install ]]; then
    printf -v requirement_prefix 'declare -- LXC_REQUIRED_CPU=%q\ndeclare -- LXC_REQUIRED_RAM=%q\n' "$var_cpu" "$var_ram"
  fi
  _write_bundle "$ROLE" "${ROLE}_script" "$ROOT/misc" --script-id bookorbit -- --requirements "$var_cpu" "$var_ram" -- \
    "${requirement_prefix}source \"\$CASE_ROOT/models.sh\"" "$(if [[ "$ROLE" == install ]]; then printf install_script; else printf run_update_script; fi)" > "$c/bundle"
  [[ $(grep -xc "declare -- LXC_REQUIRED_CPU=$var_cpu" "$c/bundle") == 1 ]]
  [[ $(grep -xc "declare -- LXC_REQUIRED_RAM=$var_ram" "$c/bundle") == 1 ]]
  printf '%s:%s\n' "$var_cpu" "$var_ram" > "$c/bundle-requirements"
  if [[ -f "$c/dependency-reader.cjs" ]]; then "$RUNTIME_NODE" "$c/dependency-reader.cjs" before; fi
  if [[ -f "$c/compat-reader.cjs" ]]; then "$RUNTIME_NODE" "$c/compat-reader.cjs" before; fi
  if [[ -f "$c/optional-reader.cjs" ]]; then "$RUNTIME_NODE" "$c/optional-reader.cjs" before; fi
  if [[ -f "$c/request-reader.cjs" ]]; then "$RUNTIME_NODE" "$c/request-reader.cjs" before; fi
  status=0
  bash "$c/bundle" || status=$?
  if [[ -f "$c/dependency-reader.cjs" ]]; then "$RUNTIME_NODE" "$c/dependency-reader.cjs" after "$status"; fi
  if [[ -f "$c/compat-reader.cjs" ]]; then "$RUNTIME_NODE" "$c/compat-reader.cjs" after "$status"; fi
  if [[ -f "$c/optional-reader.cjs" ]]; then "$RUNTIME_NODE" "$c/optional-reader.cjs" after "$status"; fi
  if [[ -f "$c/request-reader.cjs" ]]; then "$RUNTIME_NODE" "$c/request-reader.cjs" after "$status"; fi
  if [[ -f "$c/request-root-link" ]]; then ln -sfn ../srv/bookorbit "$c/opt/bookorbit"; fi
  exit "$status"
fi
: "${TMPDIR:?disk-backed scratch required}" "${RUNTIME_NODE:?}" "${RUNTIME_EXTRA_REFERENCES:?}"
systemd-detect-virt --vm --quiet || exit 1
case "$(findmnt -rn -T "$TMPDIR" -o FSTYPE)" in '' | tmpfs | ramfs) exit 1 ;; esac
work=$(mktemp -d "$TMPDIR/bookorbit-fixture.XXXXXX")
trap 'rm -rf -- "$work"' EXIT
# Compare actual V8 configuration with this exact Node binary's explicit flag,
# not an assumed heap-size-limit overhead or a string-only budget assertion.
NODE_OPTIONS='' "$RUNTIME_NODE" --max-old-space-size=2048 -p 'require("node:v8").getHeapStatistics().heap_size_limit' > "$work/build-heap-limit"
mkdir -p "$work/contract/"{opt,srv,mnt}
CASE_ROOT="$work/contract" timeout 45s unshare -m --propagation private -- bash "$0" --closure-contract
failures=0
cat > "$work/config-child.py" << 'PY'
import json,os,pathlib,signal,subprocess,sys,time
p=pathlib.Path(sys.argv[1]);child=subprocess.Popen(sys.argv[2:],start_new_session=True)
proc=pathlib.Path('/proc')/str(child.pid);birth=(proc/'stat').read_text().split(') ',1)[1].split()[19]
owner=dict(pid=child.pid,birth=birth,pgrp=os.getpgid(child.pid),argv=sys.argv[2:]);(p/'child-owner.json').write_text(json.dumps(owner));status=124
try:
 status=child.wait(timeout=15)
except subprocess.TimeoutExpired:
 assert (proc/'stat').read_text().split(') ',1)[1].split()[19]==birth and os.getpgid(child.pid)==child.pid
 os.killpg(child.pid,signal.SIGTERM);child.wait(timeout=5)
finally:
 if child.poll() is None:
  assert (proc/'stat').read_text().split(') ',1)[1].split()[19]==birth;os.killpg(child.pid,signal.SIGTERM);child.wait(timeout=5)
 assert not proc.exists() or (proc/'stat').read_text().split(') ',1)[1].split()[19]!=birth
 (p/'child-terminal.json').write_text(json.dumps(dict(owner=owner,status=status,reaped_absent=True)))
sys.exit(status if status>=0 else 128-status)
PY
check() {
  if [[ "$1" == "$2" ]]; then printf 'PASS BookOrbit %s\n' "$3"; else
    printf 'FAIL BookOrbit %s expected <%s>, got <%s>\n' "$3" "$2" "$1" >&2
    failures=$((failures + 1))
  fi
}
dependency_variants=(root-bind root-chain late-link late-mount late-config late-db-same)
config_variants=(cfg-absent cfg-regular cfg-alias cfg-hardlink cfg-dangling cfg-dangling-chain cfg-dangling-external cfg-dangling-code cfg-dangling-remap cfg-appearance cfg-disappearance cfg-remap cfg-late-appearance cfg-late-disappearance cfg-late-remap)
request_variants=()
for root_mode in plain absolute relative chain dot dotdot trailing; do
  for object in regular symlink hardlink multicomponent chained; do request_variants+=("request-$root_mode-primary-$object"); done
done
for root_mode in plain absolute; do
  for object in absent regular alias hardlink; do request_variants+=("request-$root_mode-optional-$object"); done
done
compat_variants=(compat-fs-btrfs compat-fs-zfs compat-fs-nfs4 compat-fs-cifs compat-fs-network-ambiguous compat-db-missing compat-missing-within compat-missing-late compat-tool-absolute compat-tool-default compat-tool-service-path compat-tool-manager-default compat-tool-path-invalid compat-tool-manager-ambiguous compat-tool-missing compat-tool-code)
compat_variants+=(compat-optional-path compat-optional-bogus-path compat-inline-path compat-primary-inline-path)
for kind in primary optional; do
  for object in fifo directory device socket alias-fifo overflow; do config_variants+=("cfg-$kind-$object"); done
  for object in fifo symlink; do config_variants+=("cfg-race-$kind-$object"); done
done
for seed in app dock import caller library file folder scanner dockfile dockunit cover member mapping download upload; do
  for topology in bind chain; do dependency_variants+=("dep-$seed-$topology"); done
done
for verbose in no yes; do
  for variant in fresh fresh-caller update update-caller build download copy invalid missing db missing-table overlap alias override stopped whitespace inherited quoted relative external trailing env-symlink env-hardlink env-directory late-db changed-set root-logical root-physical root-alias root-code-alias root-caller-code root-remap url-encoded url-ipv6 url-duplicate url-unknown url-override url-escape url-readwrite url-tls url-missing url-reserved "${dependency_variants[@]}" "${config_variants[@]}" "${compat_variants[@]}" "${request_variants[@]}"; do
    c="$work/$verbose-$variant"
    mkdir -p "$c/"{opt,srv,mnt/books,mnt/data,units,local,cache,state/scripts-underground,pending,locks,home,bin,external,payload/server/src/db/migrations/meta,payload/server/bin/kepubify,payload/server/requirements,payload/client/dist}
    chmod 0700 "$c/locks" "$c/pending"
    mkdir -p "$c/local/bin"
    for n in effects services pnpm packages db build-node caller-node; do : > "$c/$n"; done
    cp "$work/build-heap-limit" "$c/build-heap-limit"
    caller_env=()
    case "$variant" in *-caller) caller_env=('NODE_OPTIONS=--max-old-space-size=384 --stack-trace-limit=17') ;; esac
    cp "$RUNTIME_EXTRA_REFERENCES/bookorbit/package.json" "$c/payload/package.json"
    cp "$RUNTIME_EXTRA_REFERENCES/bookorbit/pnpm-workspace.yaml" "$c/payload/pnpm-workspace.yaml"
    cp "$RUNTIME_EXTRA_REFERENCES/bookorbit/server/requirements/kobo-cloudscraper.txt" "$c/payload/server/requirements/kobo-cloudscraper.txt"
    printf 'locked\n' > "$c/payload/pnpm-lock.yaml"
    printf 'new client bytes\n' > "$c/payload/client/dist/index.html"
    printf 'migration\n' > "$c/payload/server/src/db/migrations/0000.sql"
    printf '{}\n' > "$c/payload/server/src/db/migrations/meta/_journal.json"
    printf 'binary fixture\n' > "$c/payload/server/bin/kepubify/linux-x64"
    printf 'incoming source default\n' > "$c/payload/.env"
    role=update
    case "$variant" in fresh*) role=install ;; esac
    mkdir -p "$c/opt/bookorbit/custom data" "$c/opt/bookorbit/custom library" "$c/opt/bookorbit/caller keep" "$c/opt/bookorbit/legacy" "$c/opt/bookorbit/server/public"
    printf 'USER code\n' > "$c/opt/bookorbit/code"
    printf 'USER persistent bytes\n' > "$c/opt/bookorbit/custom data/row"
    printf 'USER book bytes\n' > "$c/opt/bookorbit/custom library/book.epub"
    chmod 0640 "$c/opt/bookorbit/custom library/book.epub" "$c/opt/bookorbit/custom data/row"
    printf 'USER caller\n' > "$c/opt/bookorbit/caller keep/row"
    printf 'USER legacy\n' > "$c/opt/bookorbit/legacy/row"
    printf 'USER outside\n' > "$c/external/row"
    printf 'old client\n' > "$c/opt/bookorbit/server/public/index.html"
    cp "$c/payload/package.json" "$c/opt/bookorbit/package.json"
    printf '{}\n' > "$c/opt/bookorbit/server/package.json"
    cat > "$c/opt/bookorbit/.env" << 'ENV'
NODE_ENV=production
PORT=4555
APP_URL=http://example.test:4555
CLIENT_URL=http://example.test:4555
DATABASE_URL=postgres://fixture:fixture@localhost/bookorbit
JWT_SECRET=retained-jwt
SETUP_BOOTSTRAP_TOKEN=retained-setup
EMAIL_ENCRYPTION_KEY=retained-email
MIGRATION_ENCRYPTION_KEY=retained-migration
BOOK_REQUEST_ENCRYPTION_KEY=retained-request
NODE_OPTIONS=--max-old-space-size=896
APP_DATA_PATH=/opt/bookorbit/custom data
BOOK_DOCK_PATH=/opt/bookorbit/custom data/dock
MIGRATION_IMPORT_ROOT=/opt/bookorbit/custom data/import
APP_VERSION=vold
ENV
    chmod 0600 "$c/opt/bookorbit/.env"
    printf '%s\n' "$variant" > "$c/variant"
    cat > "$c/local/bin/psql" << SH
#!/usr/bin/env bash
[[ "\$PGDATABASE" == bookorbit && "\$PGUSER" == fixture && "\$PGPASSWORD" == fixture && "\$PGHOST" == localhost && "\$PGPORT" == 5432 ]] || {
  case "\$(cat '$c/variant')" in
    url-encoded) [[ "\$PGDATABASE" == 'book orbit' && "\$PGUSER" == 'fixture user' && "\$PGPASSWORD" == 'fixture:p%@' && "\$PGHOST" == localhost && "\$PGPORT" == 5544 && "\$PGAPPNAME" == 'fixture proof' && "\$PGOPTIONS" == *'statement_timeout=9000'* ]] || exit 67 ;;
    url-ipv6) [[ "\$PGDATABASE" == bookorbit && "\$PGUSER" == fixture && "\$PGPASSWORD" == fixture && "\$PGHOST" == ::1 && "\$PGPORT" == 5432 ]] || exit 67 ;;
    *) exit 67 ;;
  esac
}
[[ "\$PGOPTIONS" == *default_transaction_read_only=on* ]] || exit 68
[[ "\$PGSSLMODE" == disable && "\$PGCONNECT_TIMEOUT" == 5 && "\$PGPASSFILE" == /dev/null ]] || exit 68
[[ "\$(cat '$c/variant')" != db && "\$(cat '$c/variant')" != missing-table ]] || exit 1
if [[ "\$(cat '$c/variant')" == late-db && -s '$c/db' ]]; then exit 1; fi
    printf 'query\n' >> '$c/db'
if [[ "\$*" == *' -f -'* ]]; then exec "$RUNTIME_NODE" "$c/sql-model.cjs" "$c" "$variant" "$ROOT"; fi
case "\$(cat '$c/variant')" in
  changed-set)
    if [[ \$(wc -l < '$c/db') == 2 ]]; then printf '["/opt/bookorbit/other library"]\n'; else printf '["/opt/bookorbit/custom library"]\n'; fi ;;
  root-physical) printf '["/srv/bookorbit/custom library","/srv/bookorbit/escape"]\n' ;;
  root-alias) printf '["/srv/bookorbit/library alias","/srv/bookorbit/escape"]\n' ;;
  root-code-alias) printf '["/srv/bookorbit/code alias/future"]\n' ;;
  *) printf '["/opt/bookorbit/custom library"]\n' ;;
esac
SH
    chmod 0755 "$c/local/bin/psql"
    case "$variant" in
      invalid) printf 'APP_DATA_PATH="unterminated\n' >> "$c/opt/bookorbit/.env" ;;
      missing) rm "$c/opt/bookorbit/.env" ;;
      env-symlink)
        mv "$c/opt/bookorbit/.env" "$c/external/environment"
        ln -s "$c/external/environment" "$c/opt/bookorbit/.env"
        ;;
      env-hardlink) ln "$c/opt/bookorbit/.env" "$c/external/environment" ;;
      env-directory)
        mv "$c/opt/bookorbit/.env" "$c/external/environment"
        mkdir "$c/opt/bookorbit/.env"
        ;;
      overlap) printf 'APP_DATA_PATH=/opt/bookorbit/server/public/user\n' >> "$c/opt/bookorbit/.env" ;;
      alias)
        ln -s server/public "$c/opt/bookorbit/alias"
        printf 'APP_DATA_PATH=/opt/bookorbit/alias/future\n' >> "$c/opt/bookorbit/.env"
        ;;
      quoted) sed -i 's|^APP_DATA_PATH=.*|APP_DATA_PATH="/opt/bookorbit/custom data"|' "$c/opt/bookorbit/.env" ;;
      relative) sed -i 's|^APP_DATA_PATH=.*|APP_DATA_PATH=../custom data|' "$c/opt/bookorbit/.env" ;;
      external) printf 'BOOK_DOCK_PATH=%s\n' "$c/external" >> "$c/opt/bookorbit/.env" ;;
      trailing)
        mkdir "$c/opt/bookorbit/custom import "
        printf 'USER imports\n' > "$c/opt/bookorbit/custom import /row"
        printf 'MIGRATION_IMPORT_ROOT="../custom import "\n' >> "$c/opt/bookorbit/.env"
        ;;
      url-encoded) sed -i 's|^DATABASE_URL=.*|DATABASE_URL=postgresql://fixture%20user:fixture%3Ap%25%40@localhost:5544/book%20orbit?application_name=fixture%20proof\&statement_timeout=9000\&client_encoding=UTF8\&sslmode=disable|' "$c/opt/bookorbit/.env" ;;
      url-ipv6) sed -i 's|^DATABASE_URL=.*|DATABASE_URL=postgres://fixture:fixture@[::1]/bookorbit|' "$c/opt/bookorbit/.env" ;;
      url-duplicate) sed -i 's|^DATABASE_URL=.*|DATABASE_URL=postgres://fixture:fixture@localhost/bookorbit?application_name=first\&application_name=second|' "$c/opt/bookorbit/.env" ;;
      url-unknown) sed -i 's|^DATABASE_URL=.*|DATABASE_URL=postgres://fixture:fixture@localhost/bookorbit?unknown=value|' "$c/opt/bookorbit/.env" ;;
      url-override) sed -i 's|^DATABASE_URL=.*|DATABASE_URL=postgres://fixture:fixture@localhost/bookorbit?user=root|' "$c/opt/bookorbit/.env" ;;
      url-escape) sed -i 's|^DATABASE_URL=.*|DATABASE_URL=postgres://fixture:bad%Q0@localhost/bookorbit|' "$c/opt/bookorbit/.env" ;;
      url-readwrite) sed -i 's|^DATABASE_URL=.*|DATABASE_URL=postgres://fixture:fixture@localhost/bookorbit?options=-c%20default_transaction_read_only%3Doff|' "$c/opt/bookorbit/.env" ;;
      url-tls) sed -i 's|^DATABASE_URL=.*|DATABASE_URL=postgres://fixture:fixture@localhost/bookorbit?sslmode=require|' "$c/opt/bookorbit/.env" ;;
      url-missing) sed -i 's|^DATABASE_URL=.*|DATABASE_URL=postgres://localhost/bookorbit|' "$c/opt/bookorbit/.env" ;;
      url-reserved) sed -i 's|^DATABASE_URL=.*|DATABASE_URL=postgres://fixture:fixture@localhost/book%2Forbit|' "$c/opt/bookorbit/.env" ;;
    esac
    case "$variant" in
      root-* | dep-* | late-link | late-mount | late-config | late-db-same)
        mv "$c/opt/bookorbit" "$c/srv/bookorbit"
        ln -s ../srv/bookorbit "$c/opt/bookorbit"
        ln -s 'custom library' "$c/opt/bookorbit/library alias"
        ln -s server/public "$c/opt/bookorbit/code alias"
        ln -s "$c/external" "$c/opt/bookorbit/escape"
        ;;
    esac
    if [[ "$variant" == changed-set ]]; then mkdir -p "$c/opt/bookorbit/other library"; fi
    cat > "$c/sql-model.cjs" << 'JS'
const fs=require('node:fs'),assert=require('node:assert/strict'),crypto=require('node:crypto');
const [c,v,root]=process.argv.slice(2);
const schema=JSON.parse(fs.readFileSync(root+'/tests/assets/bookorbit-path-schema.json'));
const source=fs.readFileSync(root+'/scripts/lxc/bookorbit.sh','utf8');
const packed=Buffer.from(/const migrationBytes=Buffer.from\(`([\s\S]*?)`/.exec(source)[1].replace(/\s/g,''),'base64');
assert.equal(crypto.createHash('sha256').update(packed).digest('hex'),schema.ledger_hash_bytes_sha256);
const request=fs.readFileSync(0,'utf8');assert(request.includes('BEGIN ISOLATION LEVEL REPEATABLE READ READ ONLY;')&&request.includes('\\gexec'));
const fields=schema.fields.filter(f=>f[3]<=140&&(f[4]===null||140<f[4]));
const columns=fields.map(([table,column,type])=>({table,column,type,kind:'r'}));
const rows=[{kind:'catalog',readonly:'on',snapshot:'fixture',columns},{kind:'ledger',rows:Array.from({length:141},(_,i)=>[packed.subarray(i*32,i*32+32).toString('hex'),String(i+1)])}];
let library='/opt/bookorbit/custom library';
if(v==='root-physical')library='/srv/bookorbit/custom library';
if(v==='root-alias')library='/srv/bookorbit/library alias';
if(v==='root-code-alias')library='/srv/bookorbit/code alias/future';
if(v==='changed-set'&&fs.readFileSync(c+'/db','utf8').trim().split('\n').length===2)library='/opt/bookorbit/other library';
if(v==='late-db-same'&&fs.readFileSync(c+'/db','utf8').trim().split('\n').length===2)library='/srv/bookorbit/custom library';
if(v==='late-link')library='/mnt/entry';
if(v==='late-mount')library='/mnt/books';
if(['cfg-appearance','cfg-disappearance','cfg-remap'].includes(v)){
 const p='/opt/bookorbit/server/.env';
 if(v==='cfg-appearance')fs.writeFileSync(p,'# appeared during SQL\n');
 if(v==='cfg-disappearance')fs.unlinkSync(p);
 if(v==='cfg-remap'){const b=fs.readFileSync(p);fs.renameSync(p,p+'.old');fs.writeFileSync(p,b);}
}
if(v==='cfg-dangling-remap'){fs.unlinkSync('/opt/bookorbit/optional-middle');fs.symlinkSync('/mnt/other-absent','/opt/bookorbit/optional-middle');}
const selected={app:null,dock:null,import:null,caller:null,library:'library_folders.path',file:'book_files.absolute_path',folder:'books.folder_path',scanner:'library_dir_scan_state.dir_path',dockfile:'book_dock_files.absolute_path',dockunit:'book_dock_files.unit_directory',cover:'book_dock_files.cover_path',member:'book_dock_unit_files.absolute_path',mapping:'download_client_path_mappings.local_path',download:'book_request_downloads.local_path',upload:'upload_sessions.staging_path'};
let origin=null,value=null;
if(v==='root-bind'||v==='root-chain'){origin='library_folders.path';value=v==='root-bind'?'/mnt/books':'/mnt/entry';}
if(v.startsWith('dep-')){const [,kind,topology]=v.split('-');origin=selected[kind];value=topology==='bind'?'/mnt/books':'/mnt/entry';if(['file','dockfile','member','cover'].includes(kind))value+='/'+(kind==='cover'?'cover.jpg':'row');}
if(['compat-db-missing','compat-missing-within','compat-missing-late'].includes(v)){origin='book_files.absolute_path';value='/mnt/missing-entry/missing.epub';}
for(const [table,column] of fields){const key=table+'.'+column;rows.push({kind:'paths',origin:key,snapshot:'fixture',paths:key===origin?[value]:key==='library_folders.path'?([library,...(['root-physical','root-alias'].includes(v)?['/srv/bookorbit/escape']:[])]):[]});}
for(const row of rows)console.log(JSON.stringify(row));
JS
    case "$variant" in
      root-bind | root-chain | dep-*)
        mkdir -p "$c/srv/bookorbit/dependent"
        for name in row cover.jpg cover_thumb.jpg; do
          printf 'OWNED dependency bytes\n' > "$c/srv/bookorbit/dependent/$name"
          printf 'OWNED dependency bytes\n' > "$c/mnt/data/$name"
        done
        if [[ "$variant" == *-chain || "$variant" == root-chain ]]; then
          ln -s /srv/bookorbit/dependency-link "$c/mnt/entry"
          ln -s /mnt/data "$c/srv/bookorbit/dependency-link"
        fi
        case "$variant" in
          dep-app-*) printf 'APP_DATA_PATH=/mnt/%s\n' "$(if [[ "$variant" == *-bind ]]; then printf books; else printf entry; fi)" >> "$c/opt/bookorbit/.env" ;;
          dep-dock-*) printf 'BOOK_DOCK_PATH=/mnt/%s\n' "$(if [[ "$variant" == *-bind ]]; then printf books; else printf entry; fi)" >> "$c/opt/bookorbit/.env" ;;
          dep-import-*) printf 'MIGRATION_IMPORT_ROOT=/mnt/%s\n' "$(if [[ "$variant" == *-bind ]]; then printf books; else printf entry; fi)" >> "$c/opt/bookorbit/.env" ;;
          dep-caller-*) ln -s "/mnt/$(if [[ "$variant" == *-bind ]]; then printf books; else printf entry; fi)" "$c/srv/bookorbit/caller-dependency" ;;
        esac
        cat > "$c/dependency-reader.cjs" << 'JS'
const fs=require('node:fs'),assert=require('node:assert/strict'),crypto=require('node:crypto');
const c=process.env.CASE_ROOT,v=process.env.VARIANT,[phase,status]=process.argv.slice(2),bind=v.endsWith('-bind');
const requested=(bind?'/mnt/books':'/mnt/entry')+'/'+(v.startsWith('dep-cover-')?'cover.jpg':'row');
const raw=fs.readFileSync(requested),s=fs.statSync(requested),outside=fs.readFileSync('/mnt/data/row');
const fact={requested,sha256:crypto.createHash('sha256').update(raw).digest('hex'),dev:s.dev,inode:s.ino,mode:s.mode,uid:s.uid,gid:s.gid,outside:crypto.createHash('sha256').update(outside).digest('hex')};
if(phase==='before')fs.writeFileSync(c+'/dependency-before.json',JSON.stringify(fact));
else{assert.equal(status,'0');assert.deepEqual(fact,JSON.parse(fs.readFileSync(c+'/dependency-before.json')));if(!bind)assert.equal(fs.readlinkSync('/srv/bookorbit/dependency-link'),'/mnt/data');console.log('DEPENDENCY_GREEN '+v+' original requested Node bytes/inode/metadata and external witness retained');}
JS
        ;;
    esac
    case "$variant" in
      late-link | late-mount)
        mkdir -p "$c/srv/bookorbit/dependent" "$c/mnt/other"
        printf 'original link target\n' > "$c/mnt/data/row"
        printf 'replacement link target\n' > "$c/mnt/other/row"
        ln -s /srv/bookorbit/dependency-link "$c/mnt/entry"
        ln -s /mnt/data "$c/srv/bookorbit/dependency-link"
        ;;
    esac
    case "$variant" in
      cfg-*)
        optional="$c/opt/bookorbit/server/.env"
        case "$variant" in
          cfg-regular | cfg-alias | cfg-hardlink)
            printf 'SETUP_BOOTSTRAP_TOKEN=fallback-owned\nPORT=9999\n' > "$c/opt/bookorbit/optional-owned"
            sed -i '/^SETUP_BOOTSTRAP_TOKEN=/d' "$c/opt/bookorbit/.env"
            case "$variant" in
              cfg-regular) cp "$c/opt/bookorbit/optional-owned" "$optional" ;;
              cfg-alias) ln -s ../optional-owned "$optional" ;;
              cfg-hardlink)
                mv "$c/opt/bookorbit/optional-owned" "$c/external/optional-owned"
                ln "$c/external/optional-owned" "$optional"
                ;;
            esac
            ;;
          cfg-dangling) ln -s ../absent-optional "$optional" ;;
          cfg-dangling-chain | cfg-dangling-external | cfg-dangling-remap)
            ln -s ../optional-middle "$optional"
            if [[ "$variant" == cfg-dangling-chain ]]; then
              ln -s absent-optional "$c/opt/bookorbit/optional-middle"
            else
              ln -s /mnt/absent-optional "$c/opt/bookorbit/optional-middle"
            fi
            ;;
          cfg-dangling-code) ln -s ../server/src/absent-optional "$optional" ;;
          cfg-disappearance | cfg-remap | cfg-late-disappearance | cfg-late-remap | cfg-race-optional-*) printf '# optional unchanged bytes\n' > "$optional" ;;
        esac
        case "$variant" in
          cfg-primary-* | cfg-optional-*)
            config_target="$optional"
            [[ "$variant" != cfg-primary-* ]] || config_target="$c/opt/bookorbit/.env"
            rm -f -- "$config_target"
            case "$variant" in
              *-alias-fifo)
                mkfifo "$c/opt/bookorbit/special-owned"
                ln -s /opt/bookorbit/special-owned "$config_target"
                ;;
              *-fifo) mkfifo "$config_target" ;;
              *-directory) mkdir "$config_target" ;;
              *-device) mknod "$config_target" c 1 3 ;;
              *-socket) python3 -c 'import os,socket,sys;os.chdir(os.path.dirname(sys.argv[1]));s=socket.socket(socket.AF_UNIX);s.bind(os.path.basename(sys.argv[1]));s.close()' "$config_target" ;;
              *-overflow) head -c 1048577 /dev/zero | tr '\0' '#' > "$config_target" ;;
            esac
            ;;
        esac
        ;;
    esac
    case "$variant" in
      cfg-regular | cfg-alias | cfg-hardlink | cfg-dangling | cfg-dangling-chain | cfg-dangling-external | compat-optional-path | compat-optional-bogus-path | compat-inline-path | compat-primary-inline-path)
        if [[ "$variant" == compat-* ]]; then
          printf 'PATH=%s\n' "$(if [[ "$variant" == compat-optional-bogus-path ]]; then printf relative:bogus; else printf /usr/bin:/bin; fi)" > "$c/opt/bookorbit/server/.env"
          printf '#!/bin/sh\nprintf "INHERITED service command\\n"\n' > "$c/mnt/service-tool"
          chmod 0755 "$c/mnt/service-tool"
          ln -s /mnt/service-tool "$c/opt/bookorbit/service-tool-link"
          ln -s /opt/bookorbit/service-tool-link "$c/local/bin/ffmpeg"
          [[ "$variant" != compat-primary-inline-path ]] || printf 'PATH=/usr/local/bin:/usr/bin:/bin\n' >> "$c/opt/bookorbit/.env"
        fi
        cat > "$c/optional-reader.cjs" << 'JS'
const fs=require('node:fs'),cp=require('node:child_process'),assert=require('node:assert/strict'),util=require('node:util');
const c=process.env.CASE_ROOT,v=process.env.VARIANT,[phase,status]=process.argv.slice(2),p='/opt/bookorbit/server/.env';
if(phase==='after'){console.log('OPTIONAL_HOOK_STATUS '+v+' '+status);assert.equal(status,'0');}
const metadata=p=>{const s=fs.lstatSync(p);return {dev:s.dev,ino:s.ino,mode:s.mode,uid:s.uid,gid:s.gid,nlink:s.nlink,link:s.isSymbolicLink()?fs.readlinkSync(p):null};};
const fact={config:metadata(p)};
if(v.startsWith('cfg-dangling')){fact.absent=!fs.existsSync(p);assert(fact.absent);if(v!=='cfg-dangling')fact.middle=metadata('/opt/bookorbit/optional-middle');assert(!fs.existsSync('/opt/bookorbit/absent-optional'));}
else{fact.raw=fs.readFileSync(p,'utf8');const primary=util.parseEnv(fs.readFileSync('/opt/bookorbit/.env','utf8')),optional=util.parseEnv(fact.raw);if(v.startsWith('cfg-')){const e={...optional,...primary};assert.equal(e.SETUP_BOOTSTRAP_TOKEN,'fallback-owned');assert.equal(e.PORT,'4555');}else{const PATH=v==='compat-inline-path'||v==='compat-primary-inline-path'?'/usr/local/bin:/usr/bin:/bin':cp.execFileSync('/usr/bin/systemd-path',['search-binaries-default'],{encoding:'utf8'}).trim();const e={...optional,PATH,...primary};assert.equal(e.PATH,PATH);fact.tool=cp.execFileSync('ffmpeg',[],{encoding:'utf8',env:e});assert.equal(fact.tool,'INHERITED service command\n');fact.link=metadata('/opt/bookorbit/service-tool-link');}}
if(phase==='before'){fs.writeFileSync(c+'/optional-before.json',JSON.stringify(fact));console.log('OPTIONAL_BEFORE '+v+' '+JSON.stringify(fact));}
else{assert.deepEqual(fact,JSON.parse(fs.readFileSync(c+'/optional-before.json')));assert.equal(fs.readFileSync('/opt/bookorbit/server/public/index.html','utf8'),'new client bytes\n');console.log('OPTIONAL_OUTCOME_GREEN '+v+' '+JSON.stringify(fact));}
JS
        ;;
    esac
    case "$variant" in
      compat-*)
        mkdir -p "$c/mnt/missing" "$c/mnt/tools" "$c/mnt/plugin-source"
        ln -s /opt/bookorbit/missing-link "$c/mnt/missing-entry"
        ln -s /mnt/missing "$c/opt/bookorbit/missing-link"
        printf '#!/bin/sh\nprintf "OWNED tool consumer\\n"\n' > "$c/mnt/tools/owned-tool"
        chmod 0755 "$c/mnt/tools/owned-tool"
        printf 'owned plugin resource\n' > "$c/mnt/plugin-source/main.lua"
        ln -s /opt/bookorbit/tool-link "$c/mnt/tool-entry"
        ln -s /mnt/tools/owned-tool "$c/opt/bookorbit/tool-link"
        ln -s /opt/bookorbit/tool-link "$c/mnt/tool entry"
        mkdir -p "$c/mnt/tools space"
        cp "$c/mnt/tools/owned-tool" "$c/mnt/tools space/owned-tool"
        ln -s /opt/bookorbit/plugin-link "$c/mnt/plugin-entry"
        ln -s /mnt/plugin-source "$c/opt/bookorbit/plugin-link"
        case "$variant" in
          compat-tool-absolute)
            printf 'FFMPEG_PATH=/mnt/tool entry\nFFPROBE_PATH=/mnt/tools/owned-tool\nKOBO_CLOUDSCRAPER_PYTHON=/mnt/tools/owned-tool\nKOREADER_PLUGIN_PATH=/mnt/plugin-entry\n' >> "$c/opt/bookorbit/.env"
            ;;
          compat-tool-default | compat-tool-manager-default)
            cp "$c/mnt/tools/owned-tool" "$c/local/bin/ffmpeg"
            cp "$c/mnt/tools/owned-tool" "$c/local/bin/ffprobe"
            printf 'FFMPEG_PATH=ffmpeg\nFFPROBE_PATH=ffprobe\nKOBO_CLOUDSCRAPER_PYTHON=ffmpeg\nKOREADER_PLUGIN_PATH=/mnt/plugin-entry\n' >> "$c/opt/bookorbit/.env"
            ;;
          compat-tool-service-path) printf 'PATH=/mnt/tools space:/usr/bin:/bin\nFFMPEG_PATH=owned-tool\n' >> "$c/opt/bookorbit/.env" ;;
          compat-tool-path-invalid) printf 'PATH=relative:/usr/bin\n' >> "$c/opt/bookorbit/.env" ;;
          compat-tool-missing) printf 'FFMPEG_PATH=/mnt/absent-tool\nFFPROBE_PATH=absent-optional-probe\nKOBO_CLOUDSCRAPER_PYTHON=/mnt/absent-python\nKOREADER_PLUGIN_PATH=/mnt/absent-plugin\n' >> "$c/opt/bookorbit/.env" ;;
          compat-tool-code) printf 'FFMPEG_PATH=/opt/bookorbit/server/public/index.html\n' >> "$c/opt/bookorbit/.env" ;;
        esac
        if [[ "$variant" == compat-db-missing || "$variant" == compat-tool-absolute || "$variant" == compat-tool-default || "$variant" == compat-tool-manager-default || "$variant" == compat-tool-service-path || "$variant" == compat-tool-missing || "$variant" == compat-fs-* ]]; then
          cat > "$c/compat-reader.cjs" << 'JS'
const fs=require('node:fs'),cp=require('node:child_process'),assert=require('node:assert/strict');
const c=process.env.CASE_ROOT,v=process.env.VARIANT,[phase,status]=process.argv.slice(2);
if(phase==='after'&&status!=='0'){console.log('COMPAT_REFUSAL '+v+' hook_status='+status);process.exit(0);}
const s=fs.statSync('/opt/bookorbit/custom library/book.epub'),fact={present:fs.readFileSync('/opt/bookorbit/custom library/book.epub','utf8'),inode:s.ino,dev:s.dev};
if(v==='compat-db-missing'){assert(!fs.existsSync('/mnt/missing-entry/missing.epub'));fact.missing=true;fact.link=fs.readlinkSync('/opt/bookorbit/missing-link');}
if(['compat-tool-absolute','compat-tool-default','compat-tool-manager-default','compat-tool-service-path'].includes(v)){
 const requested=v==='compat-tool-absolute'?'/mnt/tool entry':v==='compat-tool-service-path'?'owned-tool':'ffmpeg',PATH=v==='compat-tool-service-path'?'/mnt/tools space:/usr/bin:/bin':cp.execFileSync('/usr/bin/systemd-path',['search-binaries-default'],{encoding:'utf8'}).trim();
 fact.tool=cp.execFileSync(requested,[],{encoding:'utf8',env:{PATH}});if(v!=='compat-tool-service-path')fact.plugin=fs.readFileSync('/mnt/plugin-entry/main.lua','utf8');assert.equal(fact.tool,'OWNED tool consumer\n');
}
if(v==='compat-tool-missing'){assert(!fs.existsSync('/mnt/absent-tool'));fact.absentOptional=true;}
if(phase==='before'){fs.writeFileSync(c+'/compat-before.json',JSON.stringify(fact));console.log('COMPAT_BEFORE '+v+' actual present/missing/tool consumer');}
else{assert.deepEqual(fact,JSON.parse(fs.readFileSync(c+'/compat-before.json')));console.log('COMPAT_GREEN '+v+' actual requested consumer retained; source changed separately');}
JS
        fi
        ;;
    esac
    if [[ "$variant" == request-* ]]; then
      IFS=- read -r _ request_root request_role request_object <<< "$variant"
      if [[ "$request_role" == primary ]]; then
        case "$request_object" in
          hardlink) ln "$c/opt/bookorbit/.env" "$c/external/environment" ;;
          symlink | multicomponent | chained)
            mv "$c/opt/bookorbit/.env" "$c/external/environment"
            mkdir "$c/external/sub"
            target="$c/external/environment"
            if [[ "$request_object" == multicomponent ]]; then target="$c/external/sub/../environment"; fi
            if [[ "$request_object" == chained ]]; then
              ln -s "$target" "$c/external/leaf-link"
              target="$c/external/leaf-link"
            fi
            ln -s "$target" "$c/opt/bookorbit/.env"
            ;;
        esac
      elif [[ "$request_object" != absent ]]; then
        printf 'SETUP_BOOTSTRAP_TOKEN=fallback-owned\nPORT=9999\n' > "$c/opt/bookorbit/optional-owned"
        sed -i '/^SETUP_BOOTSTRAP_TOKEN=/d' "$c/opt/bookorbit/.env"
        case "$request_object" in
          regular) cp "$c/opt/bookorbit/optional-owned" "$c/opt/bookorbit/server/.env" ;;
          alias) ln -s ../optional-owned "$c/opt/bookorbit/server/.env" ;;
          hardlink)
            mv "$c/opt/bookorbit/optional-owned" "$c/external/optional-owned"
            ln "$c/external/optional-owned" "$c/opt/bookorbit/server/.env"
            ;;
        esac
      fi
      if [[ "$request_root" != plain ]]; then
        mv "$c/opt/bookorbit" "$c/srv/bookorbit"
        ln -s ../srv/bookorbit "$c/opt/bookorbit"
        case "$request_root" in
          absolute) printf /srv/bookorbit > "$c/request-root-link" ;;
          relative)
            mkdir "$c/srv/level"
            printf ../srv/level/../bookorbit > "$c/request-root-link"
            ;;
          chain)
            ln -s /srv/bookorbit "$c/mnt/root-entry"
            printf /mnt/root-entry > "$c/request-root-link"
            ;;
          dot) printf /srv/./bookorbit > "$c/request-root-link" ;;
          dotdot)
            mkdir "$c/srv/level"
            printf /srv/level/../bookorbit > "$c/request-root-link"
            ;;
          trailing) printf /srv/bookorbit/ > "$c/request-root-link" ;;
        esac
      fi
      cat > "$c/request-reader.cjs" << 'JS'
const fs=require('node:fs'),assert=require('node:assert/strict'),util=require('node:util');
const c=process.env.CASE_ROOT,v=process.env.VARIANT,[phase,status]=process.argv.slice(2),[,root,role,object]=v.split('-'),invalid=role==='primary'&&object!=='regular';
const fact=p=>{const s=fs.lstatSync(p);return {dev:s.dev,ino:s.ino,mode:s.mode,uid:s.uid,gid:s.gid,nlink:s.nlink,link:s.isSymbolicLink()?fs.readlinkSync(p):null};};
const primary='/opt/bookorbit/.env',optional='/opt/bookorbit/server/.env',target=c+'/external/environment';
const current={leaf:fact(primary),raw:fs.readFileSync(primary,'utf8').replace(/^APP_VERSION=.*\n/gm,''),rootLink:root==='plain'?null:fs.readlinkSync('/opt/bookorbit')};
if(fs.existsSync(target)){current.target=fact(target);current.targetRaw=fs.readFileSync(target,'utf8');}
if(role==='optional'&&object!=='absent'){current.optional=fact(optional);current.optionalRaw=fs.readFileSync(optional,'utf8');}
if(phase==='before'){fs.writeFileSync(c+'/request-before.json',JSON.stringify(current));}
else{
 const before=JSON.parse(fs.readFileSync(c+'/request-before.json'));
 console.log('REQUEST_COLD_STATUS '+v+' '+status);
 if(invalid){
  console.log('REQUEST_RELATIONSHIP '+v+' '+JSON.stringify({status,leafBefore:before.leaf,leafAfter:current.leaf,targetUnchanged:JSON.stringify(before.target)===JSON.stringify(current.target),rawUnchanged:before.raw===current.raw}));
  assert.equal(status,'65');assert.deepEqual(current,before);
  const reads=fs.readFileSync(c+'/config-observations','utf8').trim().split('\n').map(JSON.parse);assert(reads.length&&reads.every(r=>r.contentOpens===0&&r.reads===0&&r.FDs_closed));
  for(const file of ['effects','services','packages','pnpm'])assert.equal(fs.statSync(c+'/'+file).size,0);assert.equal(fs.readFileSync('/opt/bookorbit/code','utf8'),'USER code\n');
 }else{
  assert.equal(status,'0');assert.equal(current.raw,before.raw);assert.equal(current.rootLink,before.rootLink);for(const k of ['mode','uid','gid'])assert.equal(current.leaf[k],before.leaf[k]);
  if(role==='optional'&&object!=='absent'){assert.deepEqual(current.optional,before.optional);assert.equal(current.optionalRaw,before.optionalRaw);const e={...util.parseEnv(current.optionalRaw),...util.parseEnv(fs.readFileSync(primary,'utf8'))};assert.equal(e.SETUP_BOOTSTRAP_TOKEN,'fallback-owned');assert.equal(e.PORT,'4555');}
  assert.equal(fs.readFileSync('/opt/bookorbit/server/public/index.html','utf8'),'new client bytes\n');
 }
 console.log('REQUEST_POLICY_GREEN '+v+' status='+status+'; original leaf policy, content admission and final relationships verified');
}
JS
    fi
    printf '[Service]\nEnvironmentFile=/opt/bookorbit/.env\n' > "$c/units/bookorbit.service"
    env_before=missing
    [[ ! -f "$c/opt/bookorbit/.env" ]] || env_before=$(sed '/^APP_VERSION=/d' "$c/opt/bookorbit/.env" | sha256sum | cut -d' ' -f1)
    env_metadata=$(stat -c '%i:%a:%u:%g:%h:%F' "$c/opt/bookorbit/.env" 2> /dev/null || true)
    env_access=$(stat -c '%a:%u:%g' "$c/opt/bookorbit/.env" 2> /dev/null || true)
    target_metadata=$(stat -c '%i:%a:%u:%g:%h:%F' "$c/external/environment" 2> /dev/null || true)
    target_bytes=$(sha256sum "$c/external/environment" 2> /dev/null | cut -d' ' -f1 || true)
    env_link=$(readlink "$c/opt/bookorbit/.env" || true)
    data_before=$(stat -c '%d:%i:%a:%u:%g' "$c/opt/bookorbit/custom data/row")
    library_before=$(stat -c '%d:%i:%a:%u:%g' "$c/opt/bookorbit/custom library/book.epub")
    unit_before=$(sha256sum "$c/units/bookorbit.service" | cut -d' ' -f1)
    cat > "$c/bin/systemctl" << 'SH'
#!/usr/bin/env bash
if [[ "$1" == show ]]; then
  cat <<'PROPERTIES'
LoadState=loaded
WorkingDirectory=/opt/bookorbit/server
RootDirectory=
RootImage=
EnvironmentFiles=/opt/bookorbit/.env (ignore_errors=no)
PassEnvironment=
UnsetEnvironment=
MainPID=0
PrivateMounts=no
PrivateTmp=no
PrivateDevices=no
PrivateUsers=no
ProtectSystem=no
ProtectHome=no
ProtectKernelTunables=no
ProtectKernelModules=no
ProtectControlGroups=no
ProtectProc=default
ProcSubset=all
MountAPIVFS=no
RootEphemeral=no
MountImages=
ExtensionImages=
ExtensionDirectories=
BindPaths=
BindReadOnlyPaths=
TemporaryFileSystem=
ReadOnlyPaths=
ReadWritePaths=
InaccessiblePaths=
JoinsNamespaceOf=
PROPERTIES
  execution='start_time=[n/a] ; stop_time=[n/a] ; pid=0 ; code=(null) ; status=0/0'
  if grep -qx 'stop bookorbit' "$CASE_ROOT/services"; then
    execution='start_time=[Wed 2026-11-11 16:20:37 UTC] ; stop_time=[Wed 2026-11-11 16:20:38 UTC] ; pid=41 ; code=killed ; status=15/TERM'
  fi
  printf 'ExecStart={ path=/usr/bin/node ; argv[]=/usr/bin/node /opt/bookorbit/server/dist/main.js ; ignore_errors=no ; %s }\n' "$execution"
  printf '%s\n' "$execution" >> "$CASE_ROOT/service-lifecycle"
  case "$VARIANT" in
    compat-inline-path) printf 'Environment=PATH=/usr/local/bin:/usr/bin:/bin\n' ;;
    compat-primary-inline-path) printf 'Environment=PATH=/usr/bin:/bin\n' ;;
    *) printf 'Environment=\n' ;;
  esac
  [[ "$VARIANT" != override ]] || printf 'RootDirectory=/foreign\n'
elif [[ "$1" == show-environment ]]; then
  printf 'LANG=C.UTF-8\n'
  case "$VARIANT" in
    compat-tool-service-path | compat-tool-manager-ambiguous) printf 'PATH=/foreign-manager-path\n' ;;
    compat-tool-manager-default) printf 'PATH=%s\n' "$(/usr/bin/systemd-path search-binaries-default)" ;;
  esac
else
  printf '%s\n' "$*" >> "$CASE_ROOT/services"
  if [[ "$*" == 'stop bookorbit' && "$VARIANT" == root-remap ]]; then
    mv /srv/bookorbit /srv/remapped
    ln -sfn ../srv/remapped /opt/bookorbit
  fi
  if [[ "$*" == 'stop bookorbit' ]]; then
    case "$VARIANT" in
      late-link) ln -sfn /mnt/other /srv/bookorbit/dependency-link ;;
      late-mount) mount --bind /srv/bookorbit/dependent /mnt/books ;;
      late-config) printf '# stopped-view witness\n' >> /opt/bookorbit/.env ;;
      cfg-late-appearance) printf '# appeared after stop\n' > /opt/bookorbit/server/.env ;;
      cfg-late-disappearance) rm /opt/bookorbit/server/.env ;;
      cfg-late-remap) mv /opt/bookorbit/server/.env /opt/bookorbit/server/.env.old; printf '# optional unchanged bytes\n' > /opt/bookorbit/server/.env ;;
      compat-missing-late) printf 'appeared after stop\n' > /mnt/missing/missing.epub ;;
    esac
  fi
fi
SH
    chmod 0755 "$c/bin/systemctl"
    cat > "$c/build-observe.cjs" << 'JS'
// Native process/environment consumers; pnpm lifecycle and compilation producers
// remain models. Children receive no replacement env or heap CLI option.
const fs = require('node:fs');
const assert = require('node:assert/strict');
const v8 = require('node:v8');
const {spawnSync} = require('node:child_process');
const [target, phase] = process.argv.slice(2);
const heap = v8.getHeapStatistics().heap_size_limit;
assert.equal(process.versions.node.split('.')[0], '24');
assert.equal(process.env.NODE_OPTIONS, '--max-old-space-size=2048');
assert.equal(heap, Number(fs.readFileSync(process.env.CASE_ROOT + '/build-heap-limit', 'utf8')));
fs.appendFileSync(process.env.CASE_ROOT + '/build-node', JSON.stringify({
  target, phase, options: process.env.NODE_OPTIONS, heap_size_limit: heap,
}) + '\n');
if (phase === 'launcher') {
  const phases = target === 'server'
    ? ['prebuild-types', 'prebuild-plugin-api', 'prebuild-swagger', 'build']
    : ['build-only'];
  for (const childPhase of phases) {
    const child = spawnSync('/bin/bash', ['-c', 'exec "$RUNTIME_NODE" "$CASE_ROOT/build-observe.cjs" "$1" "$2"', '--', target, childPhase], {stdio: 'inherit'});
    assert.ifError(child.error);
    assert.equal(child.signal, null);
    assert.equal(child.status, 0);
  }
}
JS
    cat > "$c/models.sh" << 'MODELS'
# Snapshot the bundle caller before either hook changes anything. The real
# silent wrapper remains untouched in both modes, including its return status.
caller_node_declaration=$(declare -p NODE_OPTIONS 2> /dev/null || true)
fixture_caller_unchanged() {
  [[ "$(declare -p NODE_OPTIONS 2> /dev/null || true)" == "$caller_node_declaration" ]] || return 71
}
fixture_caller_node() {
  fixture_caller_unchanged || return $?
  "$RUNTIME_NODE" - "$1" "${NODE_OPTIONS+x}" "${NODE_OPTIONS-}" << 'JS'
const fs = require('node:fs');
const assert = require('node:assert/strict');
const [phase, present, value] = process.argv.slice(2);
assert.equal(Object.hasOwn(process.env, 'NODE_OPTIONS'), present === 'x');
assert.equal(process.env.NODE_OPTIONS ?? '', value);
fs.appendFileSync(process.env.CASE_ROOT + '/caller-node', JSON.stringify({
  phase, present, value, heap_size_limit: require('node:v8').getHeapStatistics().heap_size_limit,
}) + '\n');
JS
}
header_info() { :; }
check_container_storage() { :; }
check_container_resources() { :; }
cleanup_lxc() { :; }
setup_nodejs() { printf runtime >> "$CASE_ROOT/effects"; }
setup_postgresql() { printf database >> "$CASE_ROOT/effects"; }
setup_postgresql_db() { export PG_DB_NAME=bookorbit PG_DB_USER=fixture PG_DB_PASS=fixture; }
setup_uv() { :; }
node() {
  case "$VARIANT" in
    cfg-* | request-*) "$RUNTIME_NODE" --require "$BOOKORBIT_FIXTURE_SOURCE/tests/lib/bookorbit-config-observe.cjs" "$@" ;;
    compat-*) "$RUNTIME_NODE" --require "$BOOKORBIT_FIXTURE_SOURCE/tests/lib/bookorbit-compat-observe.cjs" "$@" ;;
    *) "$RUNTIME_NODE" "$@" ;;
  esac
}
apt() { printf '%s\n' "$*" >> "$CASE_ROOT/packages"; printf apt >> "$CASE_ROOT/effects"; }
corepack() { printf '%s\n' "$*" >> "$CASE_ROOT/pnpm"; }
pnpm() {
  printf '%s\n' "$*" >> "$CASE_ROOT/pnpm"
  case "$*" in
    'install --frozen-lockfile --filter client... --filter server...') fixture_caller_node dependency-install || return $? ;;
    '--config.verify-deps-before-run=false --filter client run build-only') "$RUNTIME_NODE" "$CASE_ROOT/build-observe.cjs" client launcher || return $? ;;
    '--config.verify-deps-before-run=false --filter server run build') "$RUNTIME_NODE" "$CASE_ROOT/build-observe.cjs" server launcher || return $? ;;
  esac
  [[ "$VARIANT" != build ]] || return 52
  mkdir -p /opt/bookorbit/client/dist /opt/bookorbit/server/dist
  printf 'new client bytes\n' > /opt/bookorbit/client/dist/index.html
}
uv() {
  fixture_caller_node after-build || return $?
  if [[ "$1" == venv ]]; then mkdir -p "${!#}/bin"; touch "${!#}/bin/python"; fi
}
cp() {
  fixture_caller_unchanged || return $?
  if [[ "$VARIANT" == copy && "$*" == *'/deploy-source.'* ]]; then return 41; fi
  command cp "$@"
}
curl() {
  local out='' format=''
  while (($#)); do case "$1" in -o) out="$2"; shift ;; -w) format="$2"; shift ;; esac; shift; done
  printf '{"tag_name":"v3.7.0","assets":[]}' > "$out"
  [[ -z "$format" ]] || printf 200
}
curl_download() {
  printf download >> "$CASE_ROOT/effects"
  [[ "$VARIANT" != download ]] || return 22
  tar -czf "$1" -C "$CASE_ROOT" payload
}
# shellcheck disable=SC2034
CLEAN_INSTALL_KEEP_PATHS=('caller keep')
CLEAN_INSTALL_KEEP=legacy
case "$VARIANT" in root-bind | root-chain | dep-*) CLEAN_INSTALL_KEEP_PATHS+=('custom data' 'custom library') ;; esac
case "$VARIANT" in dep-caller-*) CLEAN_INSTALL_KEEP_PATHS+=('caller-dependency') ;; esac
if [[ "$VARIANT" == root-caller-code ]]; then CLEAN_INSTALL_KEEP_PATHS+=('code alias/future'); fi
MODELS
    if [[ "$role" == install ]]; then rm -rf "$c/opt/bookorbit"; fi
    # Extract only actual cold hook definitions; framework bootstrap is not run.
    bash -c 'unset var_cpu var_ram var_disk; curl() { :; }; source "$1"; declare -p var_cpu var_ram var_disk; declare -f install_script update_script' hook-source "$ROOT/scripts/lxc/bookorbit.sh" > "$c/hooks.sh"
    rc=0
    launcher=(timeout 50s)
    case "$variant" in cfg-* | request-*) launcher=(python3 "$work/config-child.py" "$c") ;; esac
    env -i "${caller_env[@]}" PATH="$c/bin:$PATH" CASE_ROOT="$c" BOOKORBIT_FIXTURE_SOURCE="$ROOT" HOME="$c/home" TMPDIR="$TMPDIR" RUNTIME_NODE="$RUNTIME_NODE" VARIANT="$variant" ROLE="$role" VERBOSE="$verbose" APP=BookOrbit NSAPP=bookorbit LOCAL_IP=10.20.30.40 BUILD_LOG="$c/build.log" DEBUG_LOGFILE="$c/errors.log" \
      "${launcher[@]}" unshare -m --propagation private -- bash "$0" --child > "$c/output" 2>&1 || rc=$?
    expected=0
    case "$variant" in build) expected=52 ;; download) expected=250 ;; copy) expected=252 ;; invalid | missing | db | missing-table | overlap | alias | override | env-symlink | env-hardlink | env-directory | late-db | late-link | late-mount | late-config | late-db-same | changed-set | root-code-alias | root-caller-code | root-remap | url-duplicate | url-unknown | url-override | url-escape | url-readwrite | url-tls | url-missing | url-reserved) expected=65 ;; esac
    case "$variant" in cfg-absent | cfg-regular | cfg-alias | cfg-hardlink | cfg-dangling | cfg-dangling-chain | cfg-dangling-external) ;; cfg-*) expected=65 ;; esac
    case "$variant" in compat-missing-within | compat-missing-late | compat-tool-code | compat-fs-network-ambiguous | compat-tool-path-invalid | compat-tool-manager-ambiguous) expected=65 ;; esac
    case "$variant" in request-*-primary-*) [[ "$variant" == *-regular ]] || expected=65 ;; esac
    check "$rc" "$expected" "$verbose/$variant actual generated cold-hook status"
    if [[ "$variant" == request-* ]]; then
      check "$(grep -c '^REQUEST_POLICY_GREEN ' "$c/output" || true)" 1 "$verbose/$variant original request leaf and outcome"
      check "$(test -s "$c/child-owner.json" && test -s "$c/child-terminal.json" && printf owned)" owned "$verbose/$variant early owned request child reaped"
      grep -E '^REQUEST_(COLD_STATUS|RELATIONSHIP|POLICY_GREEN) ' "$c/output" || true
    fi
    if [[ -f "$c/optional-reader.cjs" ]]; then
      check "$(grep -c '^OPTIONAL_OUTCOME_GREEN ' "$c/output" || true)" 1 "$verbose/$variant actual optional topology and service command retained"
      grep -E '^OPTIONAL_(BEFORE|HOOK_STATUS|OUTCOME_GREEN) ' "$c/output" || true
    fi
    if [[ -f "$c/compat-reader.cjs" ]]; then
      check "$(grep -c '^COMPAT_GREEN ' "$c/output" || true)" "$(if [[ "$expected" == 0 ]]; then printf 1; else printf 0; fi)" "$verbose/$variant compatibility consumer witness"
      grep -E '^COMPAT_(BEFORE|GREEN|REFUSAL) ' "$c/output" || true
    fi
    if [[ "$variant" == cfg-* ]]; then
      check "$(test -s "$c/child-owner.json" && test -s "$c/child-terminal.json" && printf owned)" owned "$verbose/$variant early owned child reaped"
      check "$(grep -c '^CONFIG_FD_GREEN ' "$c/output" || true)" "$(if [[ "$variant" == cfg-late-* || "$expected" == 0 ]]; then printf 2; else printf 1; fi)" "$verbose/$variant regular-only bounded reads and no FD leak"
      grep '^CONFIG_FD_GREEN ' "$c/output" || true
    fi
    if [[ -f "$c/dependency-reader.cjs" ]]; then
      check "$(grep -c '^DEPENDENCY_GREEN ' "$c/output" || true)" 1 "$verbose/$variant requested-path reader witness"
      grep '^DEPENDENCY_GREEN ' "$c/output" || true
    fi
    check "$(cat "$c/bundle-requirements")" '2:4096' "$verbose/$variant actual source-selected cold bundle CPU/RAM"
    if [[ "$rc" != "$expected" ]]; then tail -n 5 "$c/output"; fi
    if [[ "$role" == install && "$rc" == 0 ]]; then
      check "$(grep -c '^PORT=80$' "$c/opt/bookorbit/.env" || true)" 1 'fresh HTTP80 config'
      check "$(stat -c %a "$c/opt/bookorbit/.env")" 600 'fresh environment private'
      check "$(stat -c %a "$c/home/bookorbit.creds")" 600 'fresh setup token private'
      check "$(grep -Ec '^(EMAIL|MIGRATION|BOOK_REQUEST)_ENCRYPTION_KEY=[a-f0-9]{64}$' "$c/opt/bookorbit/.env" || true)" 3 'fresh independent encryption keys'
      check "$(grep -c '^NODE_OPTIONS=--max-old-space-size=2048$' "$c/opt/bookorbit/.env" || true)" 1 'fresh runtime options unchanged by build budget'
    elif [[ "$role" == update ]]; then
      after=missing
      observed_env="$c/opt/bookorbit/.env"
      [[ "$variant" != cfg-race-primary-* ]] || observed_env+='.old'
      [[ ! -f "$observed_env" ]] || after=$(sed '/^APP_VERSION=/d; /^# stopped-view witness$/d' "$observed_env" | sha256sum | cut -d' ' -f1)
      check "$after" "$env_before" "$variant existing keys/port/config byte-preserved"
      check "$(stat -c '%a:%u:%g' "$observed_env" 2> /dev/null || true)" "$env_access" "$variant config access metadata preserved"
      check "$(stat -c '%d:%i:%a:%u:%g' "$c/opt/bookorbit/custom data/row" 2> /dev/null || true)" "$data_before" "$variant data inode/metadata survived"
      check "$(cat "$c/opt/bookorbit/custom data/row" 2> /dev/null || true)" 'USER persistent bytes' "$variant actual data bytes survived"
      check "$(stat -c '%d:%i:%a:%u:%g' "$c/opt/bookorbit/custom library/book.epub" 2> /dev/null || true)" "$library_before" "$variant database library inode survived"
      check "$(cat "$c/opt/bookorbit/custom library/book.epub" 2> /dev/null || true)" 'USER book bytes' "$variant book bytes survived"
      check "$(cat "$c/opt/bookorbit/caller keep/row" 2> /dev/null || true)" 'USER caller' "$variant literal inherited keep survives"
      check "$(cat "$c/opt/bookorbit/legacy/row" 2> /dev/null || true)" 'USER legacy' "$variant legacy inherited keep survives"
      if [[ "$variant" == trailing ]]; then check "$(cat "$c/opt/bookorbit/custom import /row" 2> /dev/null || true)" 'USER imports' 'source resolves import-root value without trimming'; fi
      check "$(sha256sum "$c/units/bookorbit.service" | cut -d' ' -f1)" "$unit_before" "$variant operator unit unchanged"
      if [[ "$rc" == 0 ]]; then
        check "$(grep -c 'status=0/0' "$c/service-lifecycle")" 2 "$verbose/$variant initial service execution sampled within pass"
        check "$(grep -c 'status=15/TERM' "$c/service-lifecycle")" 2 "$verbose/$variant stopped lifecycle changes do not alter stable plan"
        printf 'SERVICE_PLAN_LIFECYCLE_GREEN %s/%s full cold-hook preservation\n' "$verbose" "$variant"
      fi
      if [[ "$expected" == 65 && "$variant" != late-* && "$variant" != cfg-late-* && "$variant" != compat-missing-late && "$variant" != changed-set && "$variant" != root-remap ]]; then
        check "$(stat -c %s "$c/effects")" 0 "$variant refusal precedes runtime effects"
        check "$(stat -c %s "$c/services")" 0 "$variant refusal precedes service effects"
        check "$(cat "$c/opt/bookorbit/code")" 'USER code' "$variant refusal precedes replacement"
      fi
      case "$variant" in
        env-symlink | env-hardlink | env-directory)
          check "$(stat -c '%i:%a:%u:%g:%h:%F' "$c/opt/bookorbit/.env")" "$env_metadata" "$variant config alias inode/type/metadata unchanged"
          check "$(stat -c '%i:%a:%u:%g:%h:%F' "$c/external/environment")" "$target_metadata" "$variant config target inode/metadata unchanged"
          check "$(sha256sum "$c/external/environment" | cut -d' ' -f1)" "$target_bytes" "$variant target bytes unchanged"
          check "$(readlink "$c/opt/bookorbit/.env" || true)" "$env_link" "$variant link target unchanged"
          check "$(grep -c '/opt/bookorbit/.env must be a single-link regular file' "$c/output" || true)" 1 "$variant specific config path diagnostic"
          ;;
        late-db | late-link | late-mount | late-config | late-db-same | cfg-late-* | compat-missing-late | changed-set | root-remap)
          check "$(cat "$c/effects")" runtime 'late discovery failure follows runtime setup'
          check "$(cat "$c/services")" 'stop bookorbit' 'late discovery failure leaves stopped service'
          check "$(cat "$c/opt/bookorbit/code")" 'USER code' 'late discovery failure leaves source untouched'
          if [[ "$variant" == late-db ]]; then
            check "$(grep -c 'discovery failed after service stop; configuration/data retained' "$c/output" || true)" 1 'late discovery diagnostic identifies retained state and stopped service'
          else
            check "$(grep -Ec 'configuration/library roots changed|application root changed' "$c/output" || true)" 1 'changed successful discovery refuses before replacement'
            check "$(wc -l < "$c/db")" 2 'two successful SQL discovery calls'
            check "$(stat -c %s "$c/packages")" 0 'no package work after changed discovery'
            check "$(stat -c %s "$c/pnpm")" 0 'no build work after changed discovery'
          fi
          check "$(grep -c 'no app effects' "$c/output" || true)" 0 'late discovery never claims before-effects refusal'
          check "$(cat "$c/opt/bookorbit/server/public/index.html")" 'old client' 'late refusal retains original published source'
          check "$(grep -c download "$c/effects" || true)" 0 'late refusal has no source fetch'
          if [[ "$variant" == late-config ]]; then check "$(grep -c '^# stopped-view witness$' "$c/opt/bookorbit/.env")" 1 'config byte-only change was actually produced'; fi
          ;;
      esac
      case "$variant" in
        root-*)
          printf 'BOOKORBIT_ROOT_OUTCOME mode=%s variant=%s status=%s library=%s source=%s\n' "$verbose" "$variant" "$rc" \
            "$(if [[ -f "$c/opt/bookorbit/custom library/book.epub" ]]; then printf present; else printf missing; fi)" \
            "$(if grep -qx 'new client bytes' "$c/opt/bookorbit/server/public/index.html"; then printf changed; else printf old; fi)"
          check "$(readlink "$c/opt/bookorbit")" "$(if [[ "$variant" == root-remap ]]; then printf ../srv/remapped; else printf ../srv/bookorbit; fi)" 'logical root alias retained at selected physical root'
          if [[ "$rc" == 0 ]]; then
            check "$(cat "$c/opt/bookorbit/server/public/index.html")" 'new client bytes' 'physical root received changed source witness'
            if [[ "$variant" == root-alias ]]; then check "$(readlink "$c/opt/bookorbit/library alias")" 'custom library' 'in-tree alias retained with referent'; fi
            case "$variant" in root-physical | root-alias) check "$(readlink "$c/opt/bookorbit/escape")" "$c/external" 'escaping alias retained without touching external target' ;; esac
          fi
          ;;
      esac
      if [[ "$rc" != 0 ]]; then check "$(test -e "$c/pending/bookorbit" && printf present || printf absent)" present "$variant failure retains pending"; fi
      if [[ "$variant" == build || "$variant" == copy || "$variant" == download ]]; then
        printf 'update\n' > "$c/variant"
        retry=0
        env -i PATH="$c/bin:$PATH" CASE_ROOT="$c" BOOKORBIT_FIXTURE_SOURCE="$ROOT" HOME="$c/home" TMPDIR="$TMPDIR" RUNTIME_NODE="$RUNTIME_NODE" VARIANT=update ROLE=update VERBOSE="$verbose" APP=BookOrbit NSAPP=bookorbit LOCAL_IP=10.20.30.40 BUILD_LOG="$c/build.log" DEBUG_LOGFILE="$c/errors.log" \
          timeout 50s unshare -m --propagation private -- bash "$0" --child > "$c/retry-output" 2>&1 || retry=$?
        check "$retry" 0 "$variant normal pending retry succeeds without app dependencies"
        if [[ "$retry" != 0 ]]; then tail -n 5 "$c/retry-output"; fi
        check "$(test -e "$c/pending/bookorbit" && printf present || printf absent)" absent "$variant successful retry clears pending"
        check "$(stat -c '%d:%i:%a:%u:%g' "$c/opt/bookorbit/custom library/book.epub" 2> /dev/null || true)" "$library_before" "$variant retry retains original book inode"
      fi
    fi
    check "$(cat "$c/external/row")" 'USER outside' "$variant external data untouched"
    if [[ "$rc" == 0 ]]; then
      check "$(
        "$RUNTIME_NODE" - "$c/build-node" << 'JS'
const fs = require('node:fs');
const rows = fs.readFileSync(process.argv[2], 'utf8').trim().split('\n').map(JSON.parse);
console.log(rows.map(r => r.target + '/' + r.phase).join(','));
JS
      )" 'client/launcher,client/build-only,server/launcher,server/prebuild-types,server/prebuild-plugin-api,server/prebuild-swagger,server/build' "$verbose/$variant native child Node heap and modeled lifecycle inheritance"
      check "$(
        "$RUNTIME_NODE" - "$c/caller-node" "${caller_env[0]-}" << 'JS'
const fs = require('node:fs');
const assert = require('node:assert/strict');
const rows = fs.readFileSync(process.argv[2], 'utf8').trim().split('\n').map(JSON.parse);
const expected = process.argv[3].replace(/^NODE_OPTIONS=/, '');
assert(rows.some(r => r.phase === 'dependency-install'));
assert(rows.some(r => r.phase === 'after-build'));
assert(rows.every(r => r.present === (expected ? 'x' : '') && r.value === expected));
assert(rows.every(r => r.heap_size_limit === rows[0].heap_size_limit));
console.log('restored');
JS
      )" restored "$verbose/$variant caller flags and native heap unchanged outside build phase"
      check "$(grep -c djvulibre-bin "$c/packages" || true)" 1 "$variant DjVu dependency installed"
      check "$(grep -c 'install --frozen-lockfile --filter client... --filter server...' "$c/pnpm" || true)" 1 "$variant frozen core-only closure"
      check "$(grep -c -- '--config.verify-deps-before-run=false.*run build' "$c/pnpm" || true)" 2 "$variant prebuild-aware filtered commands"
      check "$(cat "$c/opt/bookorbit/server/public/index.html")" 'new client bytes' "$variant actual public contents replaced"
      check "$(test -e "$c/opt/bookorbit/server/public/dist" && printf nested || printf correct)" correct "$variant no nested dist publication"
    fi
    rm -rf -- "$c"
  done
done
printf 'BookOrbit focused failures=%s; native file/parser/replacement/Node heap consumers, package/build/lifecycle/PG/systemd producers modeled\n' "$failures"
[[ "$failures" == 0 ]]
