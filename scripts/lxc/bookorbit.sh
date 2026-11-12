#!/usr/bin/env bash
REPO_BASE="${REPO_BASE:-https://raw.githubusercontent.com/scripts-underground/proxmox/main}"

# Copyright (c) 2021-2026 community-scripts ORG
# Author: MickLesk (CanbiZ)
# License: MIT | https://raw.githubusercontent.com/scripts-underground/proxmox/main/LICENSE
# Source: https://bookorbit.app

APP="BookOrbit"
var_tags="${var_tags:-books;library;reading}"
var_cpu="${var_cpu:-2}"
var_ram="${var_ram:-4096}"
var_disk="${var_disk:-10}"
var_os="${var_os:-debian}"
var_version="${var_version:-13}"
var_unprivileged="${var_unprivileged:-1}"

function install_script() {
  msg_info "Installing Dependencies"
  $STD apt install -y \
    build-essential \
    djvulibre-bin \
    ffmpeg \
    poppler-utils
  msg_ok "Installed Dependencies"

  PG_VERSION="16" PG_MODULES="pgvector" setup_postgresql
  PG_DB_NAME="bookorbit" PG_DB_USER="bookorbit" PG_DB_EXTENSIONS="uuid-ossp,pg_trgm,unaccent,vector" setup_postgresql_db
  NODE_VERSION="24" NODE_MODULE="corepack" setup_nodejs
  setup_uv

  fetch_and_deploy_gh_release "bookorbit" "bookorbit/bookorbit" "tarball"

  msg_info "Building Application"
  cd /opt/bookorbit || exit
  local manager build_node_options='--max-old-space-size=2048'
  manager=$(jq -er '.packageManager | select(type=="string" and test("^pnpm@[0-9]+\\.[0-9]+\\.[0-9]+([+].*)?$"))' package.json) || exit 65
  $STD corepack prepare "$manager" --activate
  $STD pnpm install --frozen-lockfile --filter client... --filter server...
  NODE_OPTIONS="$build_node_options" $STD pnpm --config.verify-deps-before-run=false --filter client run build-only
  NODE_OPTIONS="$build_node_options" $STD pnpm --config.verify-deps-before-run=false --filter server run build
  mkdir -p /opt/bookorbit/server/public
  cp -a /opt/bookorbit/client/dist/. /opt/bookorbit/server/public/
  mkdir -p /opt/bookorbit/server/migrations
  cp -r /opt/bookorbit/server/src/db/migrations/. /opt/bookorbit/server/migrations/
  chmod +x /opt/bookorbit/server/bin/kepubify/*
  msg_ok "Built Application"

  msg_info "Setting up Python Runtime"
  $STD uv venv /opt/bookorbit-python
  $STD uv pip install --python /opt/bookorbit-python/bin/python -r /opt/bookorbit/server/requirements/kobo-cloudscraper.txt
  msg_ok "Set up Python Runtime"

  msg_info "Configuring Application"
  mkdir -p /opt/bookorbit-data/covers /opt/bookorbit-data/book-bucket /opt/bookorbit-books
  APP_VER=$(cat ~/.bookorbit)
  JWT_SECRET=$(openssl rand -hex 32)
  SETUP_BOOTSTRAP_TOKEN=$(openssl rand -hex 16)
  EMAIL_ENCRYPTION_KEY=$(openssl rand -hex 32)
  MIGRATION_ENCRYPTION_KEY=$(openssl rand -hex 32)
  BOOK_REQUEST_ENCRYPTION_KEY=$(openssl rand -hex 32)
  install -m 0600 /dev/null ~/bookorbit.creds
  cat << EOF > ~/bookorbit.creds

Setup Token: ${SETUP_BOOTSTRAP_TOKEN}
EOF
  install -m 0600 /dev/null /opt/bookorbit/.env
  cat << EOF > /opt/bookorbit/.env
NODE_ENV=production
PORT=80
DATABASE_URL=postgres://${PG_DB_USER}:${PG_DB_PASS}@127.0.0.1:5432/${PG_DB_NAME}
JWT_SECRET=${JWT_SECRET}
SETUP_BOOTSTRAP_TOKEN=${SETUP_BOOTSTRAP_TOKEN}
EMAIL_ENCRYPTION_KEY=${EMAIL_ENCRYPTION_KEY}
MIGRATION_ENCRYPTION_KEY=${MIGRATION_ENCRYPTION_KEY}
BOOK_REQUEST_ENCRYPTION_KEY=${BOOK_REQUEST_ENCRYPTION_KEY}
APP_URL=http://${LOCAL_IP}
CLIENT_URL=http://${LOCAL_IP}
NODE_OPTIONS=--max-old-space-size=2048
APP_DATA_PATH=/opt/bookorbit-data
KOBO_CLOUDSCRAPER_PYTHON=/opt/bookorbit-python/bin/python
BOOK_DOCK_PATH=/opt/bookorbit-data/book-bucket
APP_VERSION=v${APP_VER}
EOF
  msg_ok "Configured Application"

  msg_info "Creating Service"
  cat << EOF > /etc/systemd/system/bookorbit.service
[Unit]
Description=BookOrbit Service
After=network.target postgresql.service
Requires=postgresql.service

[Service]
Type=simple
User=root
WorkingDirectory=/opt/bookorbit/server
EnvironmentFile=/opt/bookorbit/.env
ExecStartPre=/usr/bin/node /opt/bookorbit/server/dist/scripts/migrate.js
ExecStart=/usr/bin/node /opt/bookorbit/server/dist/main.js
Restart=on-failure
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF
  systemctl enable -q --now bookorbit
  msg_ok "Created Service"
}

function post_install_script() {
  msg_ok "Completed Successfully!\n"
  echo -e "${CREATING}${GN}${APP} setup has been successfully initialized!${CL}"
  echo -e "${INFO}${YW} Access it using the following URL:${CL}"
  echo -e "${TAB}${GATEWAY}${BGN}http://${IP}${CL}"
  echo -e "${INFO}${YW} Setup Token is stored in ~/bookorbit.creds inside the container${CL}"
}

function update_script() {
  header_info
  check_container_storage
  check_container_resources

  if [[ ! -d /opt/bookorbit ]]; then
    msg_error "No ${APP} Installation Found!"
    exit
  fi

  # Discovery belongs to this cold hook, before runtime/service/source effects.
  # The systemd EnvironmentFile and Nest's optional cwd .env accept only the
  # characterized common grammar below; unsupported inputs fail, never guess.
  local preflight status declaration root_identity
  local -a inherited=() legacy=() discovered=() discovery_plan=()
  if declaration=$(declare -p CLEAN_INSTALL_KEEP_PATHS 2> /dev/null); then
    [[ "$declaration" == 'declare -a '* ]] || exit 65
    inherited+=("${CLEAN_INSTALL_KEEP_PATHS[@]}")
  fi
  case "${CLEAN_INSTALL_KEEP:-}" in *$'\n'* | *$'\r'* | *$'\t'*) exit 65 ;; esac
  read -r -a legacy <<< "${CLEAN_INSTALL_KEEP:-}"
  function bookorbit_discover() {
    node - "${inherited[@]}" "${legacy[@]}" << 'JS'
const fs=require('node:fs'),path=require('node:path'),util=require('node:util');
const {execFileSync}=require('node:child_process');
const {isIP}=require('node:net');
const assert=require('node:assert/strict'),crypto=require('node:crypto');
const root='/opt/bookorbit',cwd=root+'/server';
let stage='configuration';
let detail='unsupported or unavailable installed configuration';
const fail=(why=detail)=>{detail=why;throw Error(why);};
const digest=value=>crypto.createHash('sha256').update(value).digest('hex');
const started=Date.now();
const configInputs=new Map();
function filesystemCoordinate(mount,p){
  const api=/^(proc|sysfs|devpts|devtmpfs|cgroup2?|debugfs|tracefs|securityfs|configfs|pstore|bpf|nsfs|mqueue|hugetlbfs|autofs|fusectl|binfmt_misc|rpc_pipefs|efivarfs)$/;
  if(api.test(mount.type))fail('API/magic filesystem is not ordinary persistent data: '+p);
  let base=mount.root;
  // NFS show_path is always "/"; show_devname carries the actual export root.
  if(/^nfs4?$/.test(mount.type)){const i=mount.source.indexOf(':/');if(i<1)fail('unprovable NFS export coordinate: '+p);base=mount.source.slice(i+1);}
  if(!path.posix.isAbsolute(base)||path.posix.normalize(base)!==base||/[\x00-\x1f\x7f]/.test(base))fail('unprovable filesystem root coordinate: '+p);
  if(p!==mount.target&&!p.startsWith(mount.target==='/'?'/':mount.target+'/'))fail('reached mount target does not contain path: '+p);
  return path.posix.join(base,path.posix.relative(mount.target,p));
}
const run=(...args)=>execFileSync('systemctl',args,{encoding:'utf8',timeout:10000,stdio:['ignore','pipe','pipe']});
function execStartConfiguration(value){
  // systemd 257 systemctl-show.c: configuration followed by execution status.
  // Parse one complete record; never strip a greedy suffix from argv[].
  if(typeof value!=='string'||value.length>4096)fail('unsupported service command serialization');
  const timestamp='(?:n/a|(?:Mon|Tue|Wed|Thu|Fri|Sat|Sun) [0-9]{4}-[0-9]{2}-[0-9]{2} [0-9]{2}:[0-9]{2}:[0-9]{2} [A-Za-z0-9_+:/-]{1,64})';
  const record=new RegExp('^\\{ path=(/[A-Za-z0-9_./+-]+) ; argv\\[\\]=([A-Za-z0-9_./+:-]+(?: [A-Za-z0-9_./+:-]+)*) ; ignore_errors=(yes|no) ; start_time=\\['+timestamp+'\\] ; stop_time=\\['+timestamp+'\\] ; pid=([0-9]{1,10}) ; code=(\\(null\\)|exited|killed|dumped) ; status=([0-9]{1,3})(?:/(0|[A-Z][A-Z0-9+_-]{0,31}))? \\}$').exec(value);
  if(!record)fail('unsupported service command serialization');
  const [,executable,argumentsText,ignore,pid,code,status,signal]=record;
  if(Number(pid)>2147483647||Number(status)>255||
    (code==='(null)'&&(status!=='0'||signal!=='0'))||
    (code==='exited'&&signal!==undefined)||
    ((code==='killed'||code==='dumped')&&(!signal||signal==='0'||Number(status)<1||Number(status)>64)))fail('unsupported service execution status');
  return {path:executable,argv:argumentsText.split(' '),ignoreErrors:ignore==='yes'};
}
function serviceConfiguration(properties){
  const {MainPID,ExecStart,...view}=properties;
  return {...view,ExecStart:execStartConfiguration(ExecStart)};
}
function pairs(text){
  const result={};
  for(const line of text.trimEnd().split('\n')){
    const i=line.indexOf('=');if(i<1||Object.hasOwn(result,line.slice(0,i)))fail();
    result[line.slice(0,i)]=line.slice(i+1);
  }
  return result;
}
function configInput(file,required){
  const records=[],fds=new Set(),flags=0o10000000|fs.constants.O_NOFOLLOW|0o2000000;
  const identity=s=>(s.isDirectory()?[s.dev,s.ino,s.mode,s.uid,s.gid]:[s.dev,s.ino,s.mode,s.uid,s.gid,s.nlink,s.size,s.mtimeNs,s.ctimeNs]).map(String);
  let current='/',todo=file.split('/').slice(1),links=0,steps=0,finalFD,text=null,missing=false;
  try{
    while(todo.length){
      if(++steps>4096||Date.now()-started>60000)fail('config lookup budget');
      const part=todo.shift();if(!part||part==='.')continue;if(part==='..'){current=path.dirname(current);continue;}
      const next=path.posix.join(current,part);let fd;
      try{fd=fs.openSync(next,flags);fds.add(fd);}catch(error){if(error.code!=='ENOENT'||required)throw error;records.push({path:next,missing:true});missing=true;break;}
      const s=fs.fstatSync(fd,{bigint:true}),mnt=/^mnt_id:\s+(\d+)$/m.exec(fs.readFileSync('/proc/self/fdinfo/'+fd,'utf8'));
      const mount=mnt&&fs.readFileSync('/proc/self/mountinfo','utf8').split('\n').find(line=>line.startsWith(mnt[1]+' '));
      if(!mount)fail('config reached mount unavailable: '+file);
      const [head,tail]=mount.split(' - '),fields=head.split(' '),decode=v=>v.replace(/\\(040|011|012|134)/g,(_,n)=>String.fromCharCode(parseInt(n,8))),other=tail.split(' ');
      filesystemCoordinate({root:decode(fields[3]),target:decode(fields[4]),type:other[0],source:decode(other[1])},next);
      const item={path:next,identity:identity(s),mount:mnt[1],view:digest(mount),link:s.isSymbolicLink()?fs.readlinkSync(next):null};records.push(item);
      if(required&&!todo.length&&(!s.isFile()||s.nlink!==1n)){
        process.stderr.write('BookOrbit: '+file+' must be a single-link regular file, not a symlink, hardlink alias or special file.\n');fail('unsupported primary config object');
      }
      if(s.isSymbolicLink()){
        if(++links>40||Buffer.byteLength(item.link)>4096||/[\x00-\x1f\x7f]/.test(item.link))fail('unsupported config link: '+file);
        if(item.link.startsWith('/'))current='/';todo=[...item.link.split('/'),...todo];
      }else{
        if(todo.length&&!s.isDirectory())fail('non-directory config prefix: '+file);
        current=next;if(!todo.length){if(!s.isFile())fail('config target must be an ordinary regular file: '+file);finalFD=fd;}
      }
      if(fd!==finalFD){fs.closeSync(fd);fds.delete(fd);}
    }
    if(finalFD===undefined&&!missing)fail('config target must be an ordinary regular file: '+file);
    if(finalFD!==undefined){
      // Only this process's admitted regular metadata FD is reopened for I/O.
      const before=fs.fstatSync(finalFD,{bigint:true}),content=fs.openSync('/proc/self/fd/'+finalFD,fs.constants.O_RDONLY|fs.constants.O_NONBLOCK|0o2000000);fds.add(content);
      if(!fs.fstatSync(content).isFile()||JSON.stringify(identity(fs.fstatSync(content,{bigint:true})))!==JSON.stringify(identity(before)))fail('config content descriptor changed: '+file);
      const bytes=Buffer.alloc(1024**2+1);let count=0;
      while(count<bytes.length){const n=fs.readSync(content,bytes,count,bytes.length-count,count);if(!n)break;count+=n;}
      if(count>1024**2)fail('config 1MiB byte limit: '+file);
      if(JSON.stringify(identity(fs.fstatSync(content,{bigint:true})))!==JSON.stringify(identity(before)))fail('config changed during read: '+file);
      text=bytes.subarray(0,count).toString('utf8');
    }
    const record={required,present:finalFD!==undefined,records,hash:text===null?null:digest(text)};
    if(required&&!record.present)fail('required config unavailable: '+file);
    const previous=configInputs.get(file);if(previous&&JSON.stringify(previous)!==JSON.stringify(record))fail('configuration changed during discovery: '+file);
    configInputs.set(file,record);return text;
  }finally{for(const fd of fds)fs.closeSync(fd);}
}
function dotenv(file,required){
  const text=configInput(file,required);if(text===null)return {};
  // No multiline/escaped values, export prefixes or inline-comment ambiguity.
  for(const physical of text.split('\n')){
    const line=physical.replace(/\r$/,'').trim();
    if(!line||line.startsWith('#'))continue;
    const m=/^([A-Za-z_][A-Za-z0-9_]*)\s*=\s*(.*)$/.exec(line);if(!m)fail();
    const v=m[2];
    if(/[\x00-\x1f\x7f\\]/.test(v))fail();
    if(v.startsWith('"')){if(!/^"[^"\n]*"$/.test(v))fail();}
    else if(v.startsWith("'")){if(!/^'[^'\n]*'$/.test(v))fail();}
    else if(/["'#]/.test(v))fail();
  }
  return util.parseEnv(text);
}
function manager(text){
  const result={};
  for(const line of text.trimEnd().split('\n')){
    if(!line)continue;
    const m=/^([A-Za-z_][A-Za-z0-9_]*)=([A-Za-z0-9_./:@%+,;=?& -]*)$/.exec(line);
    if(!m)fail();result[m[1]]=m[2];
  }
  return result;
}
function databaseEnvironment(e){
  // pg-connection-string 2.14.1 decodes user/password with decodeURIComponent,
  // database with decodeURI, and strips IPv6 brackets. Do not import app modules:
  // discovery must also work after an interrupted dependency replacement.
  const raw=e.DATABASE_URL;
  if(typeof raw!=='string'||raw.length>8192||!/^postgres(?:ql)?:\/\//.test(raw)||/[\s\\\x00-\x1f\x7f]/.test(raw)||/%(?![0-9a-f]{2})/i.test(raw))fail();
  const url=new URL(raw);
  if(url.hash||raw.includes('#'))fail();
  const host=decodeURIComponent(url.hostname).replace(/^\[(.+)\]$/,'$1');
  const user=decodeURIComponent(url.username),password=decodeURIComponent(url.password);
  const database=decodeURI(url.pathname.slice(1));
  // Encoded reserved database characters have different Node/libpq URI meanings.
  // Missing identity, sockets, host overrides and ambiguous forms are unsupported.
  if(database!==decodeURIComponent(url.pathname.slice(1))||![host,user,password,database].every(v=>v&&!/[\x00-\x1f\x7f]/.test(v)))fail();
  if(!isIP(host)&&!(/^[A-Za-z0-9](?:[A-Za-z0-9.-]*[A-Za-z0-9])?$/.test(host)))fail();
  const port=url.port||'5432';
  if(!/^[0-9]+$/.test(port)||Number(port)<1||Number(port)>65535)fail();
  if(Object.keys(e).some(key=>/^PG[A-Z_]+$/.test(key)||key==='NODE_TLS_REJECT_UNAUTHORIZED'))fail();
  const env={PATH:process.env.PATH,LANG:'C.UTF-8',PGHOST:host,PGPORT:port,PGUSER:user,PGPASSWORD:password,PGDATABASE:database,
    PGCONNECT_TIMEOUT:'5',PGPASSFILE:'/dev/null',PGSSLMODE:'disable',PGGSSENCMODE:'disable',PGCLIENTENCODING:'UTF8'};
  const options=['-c default_transaction_read_only=on','-c statement_timeout=10000'];
  const seen=new Set();
  for(const [key,value] of url.searchParams){
    if(seen.has(key)||/[\x00-\x1f\x7f]/.test(value))fail();seen.add(key);
    if(key==='application_name'){
      if(!/^[A-Za-z0-9_. -]{1,63}$/.test(value))fail();env.PGAPPNAME=value;
    }else if(key==='statement_timeout'||key==='lock_timeout'){
      if(!/^[1-9][0-9]*$/.test(value)||Number(value)>10000)fail();options.push('-c '+key+'='+value);
    }else if(key==='client_encoding'){
      if(!/^utf-?8$/i.test(value))fail();
    }else if(key==='sslmode'){
      // The pinned Node driver defaults to no TLS. Its other sslmode aliases
      // and trust-store behavior are not libpq equivalents: refuse, never downgrade.
      if(value!=='disable')fail();
    }else fail();
  }
  env.PGOPTIONS=options.join(' ');
  return env;
}
// Source-pinned v2.0.1 7668f46 and v3.7.0 6f8f5f4: identical first 74
// migrations, 141 selected hashes. No installed app modules/migration files.
const migrationBytes=Buffer.from(`
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
3FjbShZGLUNmx3U1
`.replace(/\s/g,''),'base64');
const contract={fields:[['library_folders','path','character varying(4096)',0,null],['book_files','absolute_path','character varying(4096)',0,null],['books','folder_path','character varying(4096)',0,null],['library_dir_scan_state','dir_path','character varying(4096)',0,null],['book_dock_files','absolute_path','text',0,null],['book_dock_files','cover_path','text',0,null],['book_dock_files','unit_directory','text',83,null],['book_dock_unit_files','absolute_path','text',83,null],['download_client_path_mappings','local_path','character varying(4096)',83,null],['book_request_downloads','local_path','text',83,null],['upload_sessions','staging_path','text',91,null],['podcast_episode_media','local_path','character varying(4096)',91,132]],ledger:Array.from({length:141},(_,i)=>[migrationBytes.subarray(i*32,i*32+32).toString('hex')])};
function inventory(env){
  const quote=s=>"'"+s.replaceAll("'","''")+"'",names=[...new Set(contract.fields.map(f=>f[0]))];
  const sql=["BEGIN ISOLATION LEVEL REPEATABLE READ READ ONLY;",
    "SELECT json_build_object('kind','catalog','readonly',current_setting('transaction_read_only'),'snapshot',pg_current_snapshot()::text,'columns',COALESCE(json_agg(json_build_object('table',c.relname,'kind',c.relkind,'column',a.attname,'type',format_type(a.atttypid,a.atttypmod)) ORDER BY c.relname,a.attnum) FILTER(WHERE a.attname IS NOT NULL),'[]'::json)) FROM pg_class c JOIN pg_namespace n ON n.oid=c.relnamespace LEFT JOIN pg_attribute a ON a.attrelid=c.oid AND a.attnum>0 AND NOT a.attisdropped WHERE n.nspname='public' AND c.relname IN ("+names.map(quote).join(',')+");",
    "SELECT json_build_object('kind','ledger','rows',COALESCE(json_agg(json_build_array(hash,created_at::text) ORDER BY id),'[]'::json)) FROM drizzle.__drizzle_migrations;",
    "SELECT query FROM (VALUES "+contract.fields.map(([table,col])=>{const query="SELECT json_build_object('kind','paths','origin',"+quote(table+'.'+col)+",'snapshot',pg_current_snapshot()::text,'paths',COALESCE(json_agg(\""+col+"\" ORDER BY \""+col+"\") FILTER(WHERE \""+col+"\" IS NOT NULL),'[]'::json)) FROM public.\""+table+'\";';return '('+quote(table)+','+quote(col)+','+quote(query)+')';}).join(',')+") AS v(t,c,query) WHERE EXISTS(SELECT 1 FROM pg_class r JOIN pg_namespace n ON n.oid=r.relnamespace JOIN pg_attribute a ON a.attrelid=r.oid WHERE n.nspname='public' AND r.relname=v.t AND a.attname=v.c AND a.attnum>0 AND NOT a.attisdropped) ORDER BY t,c\n\\gexec",'COMMIT;'].join('\n');
  const text=execFileSync('psql',['-X','--no-password','-qAt','-v','ON_ERROR_STOP=1','-f','-'],{env,input:sql,encoding:'utf8',timeout:Math.max(1,60000-(Date.now()-started)),maxBuffer:64*1024**2,stdio:['pipe','pipe','pipe']});
  const rows=text.trim().split('\n').map(JSON.parse),cat=rows.shift(),ledger=rows.shift();
  assert.equal(cat.kind,'catalog');assert.equal(cat.readonly,'on');assert.equal(ledger.kind,'ledger');
  assert(ledger.rows.length>=74&&ledger.rows.length<=141,'unknown migration checkpoint');
  for(let i=0;i<ledger.rows.length;i++){assert.equal(ledger.rows[i][0],contract.ledger[i][0],'unknown migration prefix');assert(/^[0-9]+$/.test(ledger.rows[i][1]));}
  const checkpoint=ledger.rows.length-1,columns=new Map(cat.columns.map(c=>[c.table+'.'+c.column,c])),active=[];
  for(const [table,col,type,start,end] of contract.fields){const key=table+'.'+col,c=columns.get(key),present=checkpoint>=start&&(end===null||checkpoint<end);assert.equal(Boolean(c),present,'schema/checkpoint contradiction: '+key);if(present){assert.equal(c.kind,'r');assert.equal(c.type,type,'wrong field type: '+key);active.push(key);}}
  const tables=new Set(cat.columns.map(c=>c.table));for(const table of names)assert.equal(tables.has(table),contract.fields.some(f=>f[0]===table&&checkpoint>=f[3]&&(f[4]===null||checkpoint<f[4])),'unexpected feature table: '+table);
  assert.equal(rows.length,active.length,'incomplete path inventory');const seeds=[];
  for(const row of rows){assert.equal(row.kind,'paths');assert.equal(row.snapshot,cat.snapshot,'inconsistent SQL snapshot');assert(active.includes(row.origin));assert(Array.isArray(row.paths));for(const value of row.paths){assert(typeof value==='string'&&path.isAbsolute(value),'invalid persisted local path');seeds.push({origin:row.origin,value,creatable:false});if(row.origin==='book_dock_files.cover_path')seeds.push({origin:row.origin+'.thumbnail',value:value.replace(/\.\w+$/,'_thumb.jpg'),creatable:true});}}
  return {seeds,hash:digest(JSON.stringify([cat.columns,ledger.rows,seeds]))};
}
function closure(identity,seeds){
  stage='path-dependencies';
  const keeps=new Set(['.env']),deps=new Map(),relevant=new Set(),namespace=fs.readlinkSync('/proc/self/ns/mnt');
  const reserved=['client','packages','patches','node_modules','package.json','pnpm-lock.yaml','pnpm-workspace.yaml','tsconfig.base.json','server/src','server/dist','server/public','server/migrations','server/node_modules','server/bin','server/requirements','server/package.json','server/tsconfig.json','server/tsconfig.build.json','server/nest-cli.json'];
  const inside=(p,a)=>p===a||(a==='/'?p.startsWith('/'):p.startsWith(a+'/')),decode=s=>s.replace(/\\(040|011|012|134)/g,(_,n)=>String.fromCharCode(parseInt(n,8)));
  function budget(){if(Date.now()-started>60000)fail('inventory 60s limit');}
  function mounts(){return fs.readFileSync('/proc/self/mountinfo','utf8').trim().split('\n').map(line=>{const parts=line.split(' - '),f=parts[0].split(' ');if(parts.length!==2||f.length<6||!/^\d+:\d+$/.test(f[2]))fail('invalid mountinfo');return {id:f[0],parent:f[1],dev:f[2],root:decode(f[3]),target:decode(f[4]),type:parts[1].split(' ')[0],source:decode(parts[1].split(' ')[1])};});}
  const before=mounts(),byID=new Map(before.map(r=>[r.id,r]));
  function observe(p,remember=true){
    budget();if(Buffer.byteLength(p)>4096||/[\x00-\x1f\x7f]/.test(p))fail('unsupported path bytes');
    const fd=fs.openSync(p,0o10000000|fs.constants.O_NOFOLLOW|0o2000000);
    try{const s=fs.fstatSync(fd,{bigint:true}),m=/^mnt_id:\s+(\d+)$/m.exec(fs.readFileSync('/proc/self/fdinfo/'+fd,'utf8'));if(!m||!byID.has(m[1]))fail('reached mount ID unavailable');
      const mount=byID.get(m[1]);
      const item={path:p,dev:String(s.dev),ino:String(s.ino),mode:String(s.mode),mount:m[1],link:s.isSymbolicLink()?fs.readlinkSync(p):null,coordinate:filesystemCoordinate(mount,p),fsdev:mount.dev,network:/^(nfs4?|cifs|smb3)$/.test(mount.type)};
      if(remember){const old=deps.get(p);if(old&&JSON.stringify(old)!==JSON.stringify(item))fail('dependency changed within discovery: '+p);deps.set(p,item);relevant.add(m[1]);}return item;
    }finally{fs.closeSync(fd);}
  }
  const app=identity.physical,anchor=observe(app),charts=[{path:app,item:anchor}];
  for(const r of before)if(r.target.startsWith(app+'/')){const item=observe(r.target),hidden=item.mount!==r.id;relevant.add(r.id);charts.push({path:r.target,item:hidden?{fsdev:r.dev,coordinate:filesystemCoordinate(r,r.target),network:/^(nfs4?|cifs|smb3)$/.test(r.type)}:item,hidden});}
   function admit(relative,keep=true){if(!relative||path.isAbsolute(relative)||relative.split('/').some(v=>!v||v==='.'||v==='..')||/[\x00-\x1f\x7f*?\[\]]/.test(relative)||reserved.some(r=>inside(relative,r)||inside(r,relative)))fail('persistent path overlaps source or is unsupported: '+relative);if(keep)keeps.add(relative);}
  function material(p,item){
    if(p===root||p===app)fail('persistent path aliases application root: '+p);
    if(inside(app,p)||inside(root,p))fail('persistent path contains application: '+p);
    for(const a of [root,app])if(p.startsWith(a+'/'))admit(path.relative(a,p));
    for(const chart of charts){const c=chart.item;if(item.network&&c.network&&item.fsdev!==c.fsdev)fail('unprovable cross-superblock network alias: '+p);if(item.fsdev!==c.fsdev||(!chart.hidden&&item.dev!==c.dev))continue;
      if(item.coordinate!==c.coordinate&&inside(c.coordinate,item.coordinate))fail('persistent path contains application: '+p);
      if(!inside(item.coordinate,c.coordinate))continue;
      if(chart.hidden)fail('hidden application mount projection: '+p);
      const candidate=path.posix.join(chart.path,path.posix.relative(c.coordinate,item.coordinate));if(candidate===app)fail('persistent path aliases application root: '+p);
      const target=observe(candidate);if(target.fsdev!==item.fsdev||target.coordinate!==item.coordinate||target.dev!==item.dev||target.ino!==item.ino)fail('unreachable application projection: '+p);
      admit(path.posix.relative(app,candidate));
    }
  }
  function walk(seed){
    const raw=seed.value;if(typeof raw!=='string'||!path.isAbsolute(raw)||Buffer.byteLength(raw)>4096||/[\x00-\x1f\x7f]/.test(raw))fail('invalid path seed: '+seed.origin);
    if(seed.origin.startsWith('db:')&&raw.split('/').includes('..'))fail('unsupported literal DB dot-dot path: '+seed.origin);
    let current='/',todo=raw.split('/').slice(1),links=0,components=0,last=observe('/');
    while(todo.length){budget();if(++components>4096)fail('path component limit: '+seed.origin);const part=todo.shift();if(!part||part==='.')continue;if(part==='..'){current=path.dirname(current);last=observe(current);continue;}
      const next=current==='/'?'/'+part:current+'/'+part;let item;
      try{item=observe(next);}catch(error){if(error.code!=='ENOENT'||!(seed.mayBeAbsent||seed.creatable))throw error;const suffix=[part,...todo];if(suffix.some(v=>v==='.'||v==='..'))fail('unsupported missing suffix: '+seed.origin);const missing=next+(todo.length?'/'+todo.join('/'):'');deps.set('missing:'+missing,{path:next,missing:true,unresolved:missing});
         const keep=!seed.traceOnly&&seed.materialMissing!==false;
         for(const a of [root,app]){if(inside(a,missing))fail('missing path contains application: '+missing);if(missing.startsWith(a+'/'))admit(path.relative(a,missing),keep);}
        // A missing suffix still inherits the existing ancestor's filesystem chart.
         for(const c of charts)if(last.fsdev===c.item.fsdev&&(c.hidden||last.dev===c.item.dev)){const coordinate=path.posix.join(last.coordinate,...suffix);if(inside(c.item.coordinate,coordinate))fail('missing path contains application projection');if(inside(coordinate,c.item.coordinate)){if(c.hidden)fail('hidden missing-path projection');admit(path.posix.relative(app,path.posix.join(c.path,path.posix.relative(c.item.coordinate,coordinate))),keep);}}
        return;
      }
      if(item.link!==null){if(++links>40)fail('symlink expansion limit: '+seed.origin);if(next!==root&&next!==app)material(next,item);const target=item.link.split('/');if(item.link.startsWith('/')){current='/';last=observe('/');}todo=[...target,...todo];continue;}
      if(todo.length&&(BigInt(item.mode)&0o170000n)!==0o040000n)fail('non-directory path prefix: '+seed.origin);
      if(next.startsWith(app+'/')&&reserved.some(r=>inside(path.relative(app,next),r)))fail('data lookup visits generated code: '+seed.origin);
      current=next;last=item;
    }
    if(![0o040000n,0o100000n].includes(BigInt(last.mode)&0o170000n))fail('unsupported persistent object: '+seed.origin);
    if(seed.kind==='directory'&&(BigInt(last.mode)&0o170000n)!==0o040000n)fail('resource must be a directory: '+seed.origin);
    if(seed.kind==='file'&&(BigInt(last.mode)&0o170000n)!==0o100000n)fail('tool must be a regular file: '+seed.origin);
    if(seed.origin.startsWith('tool:')&&inside(current,app))fail('uncharacterized in-tree executable override: '+seed.origin);
    if(!seed.traceOnly)material(current,last);
  }
  for(const seed of seeds){detail='path dependency refused: '+seed.origin;walk(seed);}
  const after=mounts(),afterByID=new Map(after.map(r=>[r.id,r]));
  for(const id of relevant)if(JSON.stringify(byID.get(id))!==JSON.stringify(afterByID.get(id)))fail('relevant mount changed during discovery');
  if(JSON.stringify(before.filter(r=>inside(r.target,app)))!==JSON.stringify(after.filter(r=>inside(r.target,app))))fail('application mount topology changed during discovery');
  const records=[...deps.entries()].sort(([a],[b])=>a.localeCompare(b));
  for(const [key,item] of records){if(item.missing){try{fs.lstatSync(item.path);fail('missing dependency appeared: '+item.path);}catch(error){if(error.code!=='ENOENT')throw error;}}else if(JSON.stringify(observe(item.path,false))!==JSON.stringify(item))fail('dependency changed during discovery: '+item.path);}
  return {keeps:[...keeps].sort(),metadata:{namespace,dependencies:records.map(([,v])=>v),topology:[...relevant].sort().map(id=>byID.get(id))}};
}
(async()=>{
  stage='root-identity';
  function rootIdentity(){
    const physical=fs.realpathSync(root);
    if(physical==='/'||root.startsWith(physical+'/')||/[\x00-\x1f\x7f]/.test(physical))fail();
    const entry=fs.lstatSync(root,{bigint:true}),target=fs.statSync(root,{bigint:true});
    if(!target.isDirectory())fail();
    return {physical,device:String(target.dev),inode:String(target.ino),
      entryDevice:String(entry.dev),entryInode:String(entry.ino),link:entry.isSymbolicLink()?fs.readlinkSync(root):null};
  }
  const identity=rootIdentity(),identityJSON=JSON.stringify(identity);
  stage='configuration';
   const config=root+'/.env',primary=dotenv(config,true);
  const unitSnapshot=()=>pairs(run('show','bookorbit.service','--property=LoadState,WorkingDirectory,RootDirectory,RootImage,EnvironmentFiles,Environment,PassEnvironment,UnsetEnvironment,ExecStart,MainPID,PrivateMounts,PrivateTmp,PrivateDevices,PrivateUsers,ProtectSystem,ProtectHome,ProtectKernelTunables,ProtectKernelModules,ProtectControlGroups,ProtectProc,ProcSubset,MountAPIVFS,RootEphemeral,MountImages,ExtensionImages,ExtensionDirectories,BindPaths,BindReadOnlyPaths,TemporaryFileSystem,ReadOnlyPaths,ReadWritePaths,InaccessiblePaths,JoinsNamespaceOf'));
  const p=unitSnapshot();
  if(p.LoadState!=='loaded'||p.WorkingDirectory!==cwd||p.RootDirectory!==''||p.RootImage!==''||p.PassEnvironment!==''||p.UnsetEnvironment!==''||p.EnvironmentFiles!==root+'/.env (ignore_errors=no)')fail();
   const command=execStartConfiguration(p.ExecStart);
   if(command.path!=='/usr/bin/node'||JSON.stringify(command.argv)!==JSON.stringify(['/usr/bin/node','/opt/bookorbit/server/dist/main.js']))fail('unsupported service command');
  for(const key of ['PrivateMounts','PrivateTmp','PrivateDevices','PrivateUsers','ProtectSystem','ProtectHome','ProtectKernelTunables','ProtectKernelModules','ProtectControlGroups','MountAPIVFS','RootEphemeral'])if(p[key]!=='no')fail('unsupported service mount view: '+key);
  if(p.ProtectProc!=='default'||p.ProcSubset!=='all')fail('unsupported service proc mount view');
  for(const key of ['MountImages','ExtensionImages','ExtensionDirectories','BindPaths','BindReadOnlyPaths','TemporaryFileSystem','ReadOnlyPaths','ReadWritePaths','InaccessiblePaths','JoinsNamespaceOf'])if(p[key]!=='')fail('unsupported service mount view: '+key);
  if(!/^(0|[1-9][0-9]*)$/.test(p.MainPID))fail('service process identity unavailable');
  const processBirth=pid=>fs.readFileSync('/proc/'+pid+'/stat','utf8').split(') ')[1].split(' ')[19];
  let processIdentity=null;
  if(p.MainPID!=='0'){
    processIdentity=processBirth(p.MainPID);
    if(fs.readlinkSync('/proc/'+p.MainPID+'/ns/mnt')!==fs.readlinkSync('/proc/self/ns/mnt')||fs.readlinkSync('/proc/'+p.MainPID+'/root')!=='/'||fs.realpathSync('/proc/'+p.MainPID+'/cwd')!==fs.realpathSync(cwd))fail('unsupported live service filesystem view');
  }
  const inline={};
  for(const item of p.Environment.split(' ').filter(Boolean)){
    if(!/^[A-Za-z_][A-Za-z0-9_]*=[A-Za-z0-9_./:@%+,;=?&-]*$/.test(item))fail();
    const i=item.indexOf('=');inline[item.slice(0,i)]=item.slice(i+1);
  }
  const fallback=dotenv(cwd+'/.env',false);
  const global=manager(run('show-environment'));
  // show-environment does not identify DefaultEnvironment versus manager-only
  // values. Do not mistake manager-only data overrides for service inputs.
   for(const key of Object.keys(global))if(['APP_DATA_PATH','BOOK_DOCK_PATH','MIGRATION_IMPORT_ROOT','DATABASE_URL','NODE_OPTIONS','NODE_TLS_REJECT_UNAUTHORIZED','LIBRARY_BROWSE_ROOT','KOREADER_PLUGIN_PATH','KOBO_CLOUDSCRAPER_PYTHON','FFMPEG_PATH','FFPROBE_PATH'].includes(key)||/^PG[A-Z_]+$/.test(key))fail();
   const service={...inline,...primary};
   const servicePath=service.PATH??execFileSync('/usr/bin/systemd-path',['search-binaries-default'],{encoding:'utf8',timeout:5000,stdio:['ignore','pipe','pipe']}).trim();
   if(service.PATH===undefined&&global.PATH!==undefined&&global.PATH!==servicePath)fail('ambiguous manager service PATH');
   // Nest fills only unset process variables; systemd supplies PATH before Node.
   const e={...fallback,...service,PATH:servicePath};
  if(!e.DATABASE_URL||!e.JWT_SECRET||!e.SETUP_BOOTSTRAP_TOKEN)fail();
  if(e.NODE_OPTIONS&&!/^--max-old-space-size=[0-9]+$/.test(e.NODE_OPTIONS))fail();
  const physicalCwd=fs.realpathSync(cwd);if(physicalCwd!==identity.physical+'/server')fail('unsupported physical service cwd');
  const app=path.resolve(physicalCwd,e.APP_DATA_PATH??'/data');
  const seeds=[{origin:'config:.env',value:root+'/.env',creatable:false},{origin:'config:APP_DATA_PATH',value:app,creatable:true},{origin:'config:BOOK_DOCK_PATH',value:path.resolve(physicalCwd,e.BOOK_DOCK_PATH?.trim()||path.join(app,'book-dock')),creatable:true}];
   seeds.push({origin:'config:server/.env',value:cwd+'/.env',mayBeAbsent:true,materialMissing:false});
  if(e.MIGRATION_IMPORT_ROOT?.trim())seeds.push({origin:'config:MIGRATION_IMPORT_ROOT',value:path.resolve(physicalCwd,e.MIGRATION_IMPORT_ROOT),creatable:true});
  // Union service-PATH candidates, never guess the first executable or use updater PATH.
  const search=servicePath.split(':');if(!search.length||search.some(p=>!path.isAbsolute(p)||path.normalize(p)!==p||/[\x00-\x1f\x7f]/.test(p)))fail('unsupported service PATH grammar');
  function tool(key,value){
    if(!value||/[\x00-\x1f\x7f]/.test(value))fail('unsupported executable path: '+key);
    for(const p of value.includes('/')?[path.resolve(physicalCwd,value)]:search.map(dir=>path.join(dir,value)))seeds.push({origin:'tool:'+key,value:p,kind:'file',mayBeAbsent:true,materialMissing:false});
  }
  tool('FFMPEG_PATH',e.FFMPEG_PATH?.trim()||'ffmpeg');tool('FFPROBE_PATH',e.FFPROBE_PATH?.trim()||'ffprobe');
  if(e.KOBO_CLOUDSCRAPER_PYTHON?.trim())tool('KOBO_CLOUDSCRAPER_PYTHON',e.KOBO_CLOUDSCRAPER_PYTHON.trim());
  for(const value of ['/opt/bookorbit-python/bin/python','python3','python'])tool('KOBO fallback',value);
  const localPython=path.join(physicalCwd,'.venv/kobo-cloudscraper');seeds.push({origin:'resource:KOBO local runtime',value:localPython,kind:'directory',mayBeAbsent:true,materialMissing:false});
  if(e.KOREADER_PLUGIN_PATH?.trim())seeds.push({origin:'resource:KOREADER_PLUGIN_PATH',value:path.resolve(physicalCwd,e.KOREADER_PLUGIN_PATH.trim()),kind:'directory',mayBeAbsent:true,materialMissing:false});
  if(e.LIBRARY_BROWSE_ROOT?.trim()&&path.resolve(physicalCwd,e.LIBRARY_BROWSE_ROOT.trim())!=='/')seeds.push({origin:'config:LIBRARY_BROWSE_ROOT',value:path.resolve(physicalCwd,e.LIBRARY_BROWSE_ROOT.trim()),creatable:true,traceOnly:true});
  // The system client survives a failed clean source/dependency rebuild. Keep
  // connection secrets out of argv and use one read-only consistent statement.
  // library_folders exists in the oldest published v2.0.1 baseline and v3.7.0;
  // missing table/query failure is not a certified empty library.
  stage='database-uri';
  const databaseEnv=databaseEnvironment(e);
  stage='database-query';
  const database=inventory(databaseEnv);for(const seed of database.seeds)seeds.push({...seed,origin:'db:'+seed.origin,mayBeAbsent:true});
  for(const value of process.argv.slice(2)){if(!value||path.isAbsolute(value)||value.split('/').some(v=>!v||v==='.'||v==='..')||/[\x00-\x1f\x7f*?\[]/.test(value))fail('invalid inherited keep');seeds.push({origin:'caller:keep',value:root+'/'+value,creatable:true});}
  const plan=closure(identity,seeds);
  if(JSON.stringify(rootIdentity())!==identityJSON)fail();
  if(processIdentity!==null&&processBirth(p.MainPID)!==processIdentity)fail('live service changed during discovery');
  for(const [file,record] of configInputs)configInput(file,record.required);
  const {MainPID,...view}=p,{MainPID:afterPID,...afterView}=unitSnapshot();
  if(JSON.stringify(view)!==JSON.stringify(afterView)||MainPID!==afterPID)fail('service view changed during discovery');
   const configuration=serviceConfiguration(p),serviceHash=digest(JSON.stringify(configuration));
   const inputHash=digest(JSON.stringify([configuration,e,database.hash,seeds,[...configInputs].sort()]));
   const planMetadata={version:2,root:identity,inputHash,service:{command:configuration.ExecStart,hash:serviceHash},...plan.metadata};
  // Structured metadata is never a replacement keep. No credentials leave Node.
  process.stdout.write(JSON.stringify(planMetadata)+'\0'+plan.keeps.join('\0')+'\0');
})().catch(error=>{const reason=error.code==='ENOBUFS'?'SQL JSON 64MiB limit':error.code==='ETIMEDOUT'?'inventory timeout':error.code==='ERR_ASSERTION'?'SQL schema/checkpoint contract refused':detail;process.stderr.write('BookOrbit: installed configuration/library discovery refused at '+stage+': '+reason+'. Check service environment and database.\n');process.exitCode=65;});
JS
  }
  preflight=$(mktemp) || exit $?
  if bookorbit_discover > "$preflight"; then
    mapfile -d '' -t discovery_plan < "$preflight"
    rm -f -- "$preflight"
    ((${#discovery_plan[@]} >= 2)) || exit 65
    root_identity=${discovery_plan[0]}
    discovered=("${discovery_plan[@]:1}")
  else
    status=$?
    rm -f -- "$preflight"
    exit "$status"
  fi
  local -a CLEAN_INSTALL_KEEP_PATHS=("${discovered[@]}")

  NODE_VERSION="24" NODE_MODULE="corepack" setup_nodejs

  if check_for_gh_release "bookorbit" "bookorbit/bookorbit"; then
    msg_info "Stopping Service"
    systemctl stop bookorbit
    msg_ok "Stopped Service"

    # No API writer can add an unobserved in-tree library between discovery and
    # replacement. A changed selection is a retryable refusal, never data removal.
    local -a stopped=() stopped_plan=()
    preflight=$(mktemp) || exit $?
    if bookorbit_discover > "$preflight"; then
      mapfile -d '' -t stopped_plan < "$preflight"
      rm -f -- "$preflight"
      ((${#stopped_plan[@]} >= 2)) || exit 65
      stopped=("${stopped_plan[@]:1}")
    else
      status=$?
      rm -f -- "$preflight"
      msg_error "BookOrbit discovery failed after service stop; configuration/data retained and source not replaced. Service remains stopped; inspect the discovery error before retrying"
      exit "$status"
    fi
    if [[ "$root_identity" != "${stopped_plan[0]}" ]]; then
      msg_error "BookOrbit application root changed or path dependency inputs/topology changed during update; configuration/data retained, retry with the service stopped"
      exit 65
    fi
    if [[ "$(printf '%s\n' "${discovered[@]}")" != "$(printf '%s\n' "${stopped[@]}")" ]]; then
      msg_error "BookOrbit configuration/library roots changed during update; retry with the service stopped"
      exit 65
    fi
    $STD apt install -y djvulibre-bin
    CLEAN_INSTALL=1 fetch_and_deploy_gh_release "bookorbit" "bookorbit/bookorbit" "tarball"

    msg_info "Rebuilding Application"
    cd /opt/bookorbit || exit
    local manager build_node_options='--max-old-space-size=2048'
    manager=$(jq -er '.packageManager | select(type=="string" and test("^pnpm@[0-9]+\\.[0-9]+\\.[0-9]+([+].*)?$"))' package.json) || exit 65
    $STD corepack prepare "$manager" --activate
    $STD pnpm install --frozen-lockfile --filter client... --filter server...
    NODE_OPTIONS="$build_node_options" $STD pnpm --config.verify-deps-before-run=false --filter client run build-only
    NODE_OPTIONS="$build_node_options" $STD pnpm --config.verify-deps-before-run=false --filter server run build
    mkdir -p /opt/bookorbit/server/public
    cp -a /opt/bookorbit/client/dist/. /opt/bookorbit/server/public/
    mkdir -p /opt/bookorbit/server/migrations
    cp -r /opt/bookorbit/server/src/db/migrations/. /opt/bookorbit/server/migrations/
    chmod +x /opt/bookorbit/server/bin/kepubify/*
    APP_VER=$(cat ~/.bookorbit)
    sed -i "s/^APP_VERSION=.*/APP_VERSION=v$APP_VER/" /opt/bookorbit/.env
    msg_ok "Rebuilt Application"

    msg_info "Updating Kobo Python Runtime"
    $STD uv pip install --python /opt/bookorbit-python/bin/python -r /opt/bookorbit/server/requirements/kobo-cloudscraper.txt
    msg_ok "Updated Kobo Python Runtime"

    msg_info "Starting Service"
    systemctl start bookorbit
    msg_ok "Started Service"
    msg_ok "Updated successfully!"
  fi
  exit
}

# shellcheck disable=SC1090
source <(curl -fsSL "$REPO_BASE/misc/bootstrap/lxc") --script-id "bookorbit" -- "$@"
