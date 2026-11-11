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
const root='/opt/bookorbit',cwd=root+'/server';
let stage='configuration';
const fail=()=>{throw Error('unsupported or unavailable installed configuration');};
const run=(...args)=>execFileSync('systemctl',args,{encoding:'utf8',timeout:10000,stdio:['ignore','pipe','pipe']});
function pairs(text){
  const result={};
  for(const line of text.trimEnd().split('\n')){
    const i=line.indexOf('=');if(i<1||Object.hasOwn(result,line.slice(0,i)))fail();
    result[line.slice(0,i)]=line.slice(i+1);
  }
  return result;
}
function dotenv(file){
  const text=fs.readFileSync(file,'utf8');
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
  const anchors=[...new Set([root,identity.physical])];
  stage='configuration';
  const config=root+'/.env';
  const metadata=fs.lstatSync(config);
  if(!metadata.isFile()||metadata.nlink!==1){
    process.stderr.write('BookOrbit: '+config+' must be a single-link regular file, not a symlink, hardlink alias or special file.\n');
    fail();
  }
  const p=pairs(run('show','bookorbit.service','--property=LoadState,WorkingDirectory,RootDirectory,RootImage,EnvironmentFiles,Environment,PassEnvironment,UnsetEnvironment,ExecStart'));
  if(p.LoadState!=='loaded'||p.WorkingDirectory!==cwd||p.RootDirectory!==''||p.RootImage!==''||p.PassEnvironment!==''||p.UnsetEnvironment!==''||p.EnvironmentFiles!==root+'/.env (ignore_errors=no)')fail();
  if(!/^\{ path=\/usr\/bin\/node ; argv\[\]=\/usr\/bin\/node \/opt\/bookorbit\/server\/dist\/main\.js ;/.test(p.ExecStart))fail();
  const inline={};
  for(const item of p.Environment.split(' ').filter(Boolean)){
    if(!/^[A-Za-z_][A-Za-z0-9_]*=[A-Za-z0-9_./:@%+,;=?&-]*$/.test(item))fail();
    const i=item.indexOf('=');inline[item.slice(0,i)]=item.slice(i+1);
  }
  const fallback=fs.existsSync(cwd+'/.env')?dotenv(cwd+'/.env'):{};
  const global=manager(run('show-environment'));
  // show-environment does not identify DefaultEnvironment versus manager-only
  // values. Do not mistake manager-only data overrides for service inputs.
  for(const key of Object.keys(global))if(['APP_DATA_PATH','BOOK_DOCK_PATH','MIGRATION_IMPORT_ROOT','DATABASE_URL','NODE_OPTIONS','NODE_TLS_REJECT_UNAUTHORIZED'].includes(key)||/^PG[A-Z_]+$/.test(key))fail();
  const e={...fallback,...inline,...dotenv(root+'/.env')};
  if(!e.DATABASE_URL||!e.JWT_SECRET||!e.SETUP_BOOTSTRAP_TOKEN)fail();
  if(e.NODE_OPTIONS&&!/^--max-old-space-size=[0-9]+$/.test(e.NODE_OPTIONS))fail();
  const app=path.resolve(cwd,e.APP_DATA_PATH??'/data');
  const roots=[root+'/.env',app,path.resolve(cwd,e.BOOK_DOCK_PATH?.trim()||path.join(app,'book-dock'))];
  if(fs.existsSync(cwd+'/.env'))roots.push(cwd+'/.env');
  if(e.MIGRATION_IMPORT_ROOT?.trim())roots.push(path.resolve(cwd,e.MIGRATION_IMPORT_ROOT));
  // The system client survives a failed clean source/dependency rebuild. Keep
  // connection secrets out of argv and use one read-only consistent statement.
  // library_folders exists in the oldest published v2.0.1 baseline and v3.7.0;
  // missing table/query failure is not a certified empty library.
  stage='database-uri';
  const databaseEnv=databaseEnvironment(e);
  stage='database-query';
  const rows=JSON.parse(execFileSync('psql',['-X','--no-password','-qAt','-v','ON_ERROR_STOP=1','-c',"SELECT COALESCE(json_agg(path ORDER BY path),'[]'::json) FROM public.library_folders"],{
    encoding:'utf8',timeout:15000,stdio:['ignore','pipe','pipe'],
    env:databaseEnv,
  }));
  stage='library-paths';
  if(!Array.isArray(rows))fail();
  for(const value of rows){if(typeof value!=='string'||!path.isAbsolute(value))fail();roots.push(value);}
  const keep=new Set(['.env']);if(fs.existsSync(cwd+'/.env'))keep.add('server/.env');
  const reserved=['client','packages','patches','node_modules','package.json','pnpm-lock.yaml','pnpm-workspace.yaml','tsconfig.base.json','server/src','server/dist','server/public','server/migrations','server/node_modules','server/bin','server/requirements','server/package.json','server/tsconfig.json','server/tsconfig.build.json','server/nest-cli.json'];
  function admit(relative){
    if(!relative||relative.split('/').some(v=>!v||v==='.'||v==='..')||/[\x00-\x1f\x7f*?\[]/.test(relative)||path.isAbsolute(relative)||reserved.some(r=>r===relative||r.startsWith(relative+'/')||relative.startsWith(r+'/')))fail();
    keep.add(relative);
  }
  for(const value of process.argv.slice(2)){admit(value);roots.push(path.join(root,value));}
  for(const value of roots){
    if(/[\x00-\x1f\x7f]/.test(value))fail();
    const normalized=path.resolve(value);
    // Follow existing links when deciding whether a data root aliases code.
    let ancestor=normalized;const suffix=[];
    for(;;){
      try{fs.lstatSync(ancestor);break;}catch(error){if(error.code!=='ENOENT')throw error;}
      suffix.unshift(path.basename(ancestor));const parent=path.dirname(ancestor);if(parent===ancestor)fail();ancestor=parent;
    }
    const resolved=path.join(fs.realpathSync(ancestor),...suffix);
    for(const candidate of new Set([normalized,resolved])){
      for(const anchor of anchors){
        if(candidate==='/'||candidate===anchor||anchor.startsWith(candidate+'/'))fail();
        if(candidate.startsWith(anchor+'/'))admit(path.relative(anchor,candidate));
      }
    }
  }
  if(JSON.stringify(rootIdentity())!==identityJSON)fail();
  // The identity record is plan metadata, never a relative replacement keep.
  process.stdout.write(identityJSON+'\0'+[...keep].sort().join('\0')+'\0');
})().catch(()=>{process.stderr.write('BookOrbit: installed configuration/library discovery refused at '+stage+'. Check service environment and database.\n');process.exitCode=65;});
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
      msg_error "BookOrbit application root changed during update; configuration/data retained, retry with the service stopped"
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
