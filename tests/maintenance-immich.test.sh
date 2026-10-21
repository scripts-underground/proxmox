#!/usr/bin/env bash
# Cold real hooks/release deployment/files; compilers/ML/DB/service controls modeled.
set -euo pipefail
systemd-detect-virt --vm --quiet || exit 1
: "${TMPDIR:?}" "${MAINTENANCE_NEXT_REFERENCES:?}" "${RUNTIME_NODE:?}"
ROOT=$(realpath "$(dirname "${BASH_SOURCE[0]}")/..")
if [[ "${1:-}" != --child && "${1:-}" != --consumer ]]; then
  for path in /usr/bin/ffmpeg /usr/bin/ffprobe /usr/bin/immich /usr/bin/immich-admin /var/log/immich; do
    [[ ! -e "$path" && ! -L "$path" ]] || {
      printf 'Fixture requires its verified-clean global boundary: %s\n' "$path" >&2
      exit 1
    }
  done
fi
if [[ "${1:-}" == --consumer ]]; then
  mount --bind "$CASE_DIR/opt" /opt
  "$RUNTIME_NODE" --input-type=module - "$MAINTENANCE_NEXT_REFERENCES" << 'JS'
import fs from 'node:fs';
import readLine from 'node:readline';
import {execFileSync} from 'node:child_process';
const {getResourcePaths}=await import('file:///opt/immich/app/dist/repositories/config.repository.js');
const text=fs.readFileSync(process.argv[2]+'/immich/server/src/repositories/map.repository.ts','utf8');
let method=text.slice(text.indexOf('  private async readCountryNames()'),text.indexOf('  private async importNaturalEarthCountries()'));
if(!method.includes('countryInfo')||!method.includes('fields[4]?.trim()'))throw Error('Wrong immutable source method');
// Erase only the selected method's TypeScript visibility/return/generic types.
method=method.replace('private async readCountryNames(): Promise<CountryNames>','async readCountryNames()').replaceAll('new Map<string, string>()','new Map()');
const existsSync=fs.existsSync,createReadStream=fs.createReadStream;
const ActualMapRepository=eval('(class {'+method+'})');
const consumer=new ActualMapRepository();consumer.configRepository={getEnv:()=>({resourcePaths:getResourcePaths()})};consumer.logger={log:()=>{}};
const path=getResourcePaths().geodata.countryInfo;
if(path!=='/opt/immich/app/geodata/countryInfo.txt')throw Error('Wrong deployed resource path: '+path);
const result=await consumer.readCountryNames();
if(result.byAlpha2.get('US')!=='United States'||result.byAlpha3.get('USA')!=='United States')throw Error('Native country-name consumer did not see fixture data');
for(const [name,target] of [['immich','/opt/immich/app/cli/bin/immich'],['immich-admin','/opt/immich/app/bin/immich-admin']]) {
 const link=process.env.CASE_DIR+'/local/bin/'+name;
 if(fs.readlinkSync(link)!==target||!fs.existsSync(link))throw Error('Published CLI link references a removed build stage: '+name);
}
if(execFileSync(process.env.CASE_DIR+'/local/bin/immich',{encoding:'utf8'}).trim()!=='MODELED CLI artifact')throw Error('Published CLI artifact not executable');
if(!fs.readFileSync('/opt/immich/app/bin/immich-admin','utf8').includes('/opt/immich/app/bin/start'))throw Error('Admin artifact embeds a build-stage path');
console.log('NATIVE_IMMICH_GEODATA_CONSUMER='+JSON.stringify({path,alpha2:result.byAlpha2.get('US'),alpha3:result.byAlpha3.get('USA')}));
console.log('NATIVE_IMMICH_CLI_PUBLICATION=live targets and executable modeled artifact observed after stage cleanup');
JS
  exit
elif [[ "${1:-}" == --child ]]; then
  c="$CASE_DIR"
  # Both roots are disk-backed, but the global scratch filesystem is distinct.
  mount -o loop "$c/global-scratch.ext4" "$c/tmp"
  mount --bind "$c/opt" /opt
  mount --bind "$c/local" /usr/local
  mount --bind "$c/cache" /var/cache
  mount --bind "$c/state" /var/lib/scripts-underground/update-pending
  [[ "$(stat -c %d /opt/immich)" != "$(stat -c %d "$TMPDIR")" ]]
  source "$ROOT/misc/core.func"
  source "$ROOT/misc/error_handler.func"
  source "$ROOT/misc/tools.func"
  load_functions
  source "$c/hook"
  definition=$(declare -f _deploy_replace_contents)
  eval "${definition/_deploy_replace_contents/native_replace_contents}"
  _deploy_replace_contents() {
    local _immich_probe_app=0 _immich_probe_rc=0 _immich_probe_source_rc=0
    if [[ "$1" == /opt/immich/.app-build.* ]]; then
      _immich_probe_app=1
      python3 - "$1" "$c/app-source-before.json" << 'PY' || _immich_probe_source_rc=$?
import hashlib,json,os,pathlib,stat,sys
root=pathlib.Path(sys.argv[1]);rows=[]
for p in [root,*sorted(root.rglob('*'))]:
 s=p.lstat();r={'path':str(p.relative_to(root)),'mode':s.st_mode,'uid':s.st_uid,'gid':s.st_gid}
 if stat.S_ISLNK(s.st_mode):r['link']=os.readlink(p)
 elif stat.S_ISREG(s.st_mode):r['sha256']=hashlib.sha256(p.read_bytes()).hexdigest()
 rows.append(r)
pathlib.Path(sys.argv[2]).write_text(json.dumps(rows))
PY
      printf '%s|%s\n' "$1" "$TMPDIR" >> "$c/app-publication-calls"
    fi
    native_replace_contents "$@" || _immich_probe_rc=$?
    if [[ "$_immich_probe_app" == 1 ]]; then
      python3 - "$1" "$c/app-source-before.json" << 'PY' || _immich_probe_source_rc=$?
import hashlib,json,os,pathlib,stat,sys
root=pathlib.Path(sys.argv[1]);rows=[]
for p in [root,*sorted(root.rglob('*'))]:
 s=p.lstat();r={'path':str(p.relative_to(root)),'mode':s.st_mode,'uid':s.st_uid,'gid':s.st_gid}
 if stat.S_ISLNK(s.st_mode):r['link']=os.readlink(p)
 elif stat.S_ISREG(s.st_mode):r['sha256']=hashlib.sha256(p.read_bytes()).hexdigest()
 rows.append(r)
assert rows==json.loads(pathlib.Path(sys.argv[2]).read_text()),'Publication mutated its input tree'
PY
      if [[ "$_immich_probe_source_rc" == 0 ]]; then printf protected > "$c/app-source-protected"; else printf changed > "$c/app-source-protected"; fi
    fi
    return "$_immich_probe_rc"
  }
  mktemp() {
    local _immich_probe_path _immich_probe_rc=0
    _immich_probe_path=$(command mktemp "$@") || _immich_probe_rc=$?
    [[ "$_immich_probe_rc" == 0 ]] || return "$_immich_probe_rc"
    if [[ "$_immich_probe_path" == /opt/immich/.app-build.* ]]; then printf '%s\n' "$_immich_probe_path" >> "$c/owned-app-stages"; fi
    if [[ "${_immich_probe_app:-0}" == 1 && "$_immich_probe_path" == */deploy-source.* ]]; then
      printf '%s|%s|%s\n' "$_immich_probe_path" "$(stat -c %d "$_immich_probe_path")" "$(stat -c %d /opt/immich)" >> "$c/app-projection-stages"
    fi
    printf '%s\n' "$_immich_probe_path"
  }
  definition=$(declare -f _deploy_remove_owned_trees)
  eval "${definition/_deploy_remove_owned_trees/native_remove_owned_trees}"
  _deploy_remove_owned_trees() {
    local _immich_cleanup_rc=0
    native_remove_owned_trees "$@" || _immich_cleanup_rc=$?
    if [[ "$1" == /opt/immich/.app-build.* ]]; then
      printf '%s\n' "$1" >> "$c/app-cleanup-calls"
      [[ "$FAULT" != cleanup && "$FAULT" != build-cleanup ]] || return 67
    fi
    return "$_immich_cleanup_rc"
  }
  header_info() { :; }
  check_container_storage() { :; }
  check_container_resources() { :; }
  cleanup_lxc() { :; }
  apt() { :; }
  apt-mark() { :; }
  ensure_dependencies() { :; }
  setup_deb822_repo() { :; }
  ldconfig() { :; }
  make() { :; }
  cmake() { :; }
  meson() { :; }
  ninja() { :; }
  autoreconf() { :; }
  chown() { :; }
  chgrp() { :; }
  usermod() { :; }
  useradd() { :; }
  adduser() { :; }
  lscpu() { printf 'Vendor ID: AuthenticAMD\n'; }
  sleep() { :; }
  setup_postgresql() { printf '%s\n' "$PG_VERSION" >> "$c/database-majors"; }
  setup_postgresql_db() { export PG_DB_USER=immich PG_DB_NAME=immich PG_DB_PASS=fixture-secret; }
  get_os_info() { printf trixie; }
  get_system_arch() { printf amd64; }
  setup_uv() { :; }
  setup_nodejs() {
    printf '%s\n' "$NODE_VERSION" > "$c/node-version"
    [[ "$FAULT" != node ]] || return 43
  }
  corepack() {
    printf '%s\n' "$*" >> "$c/corepack"
    [[ "$FAULT" != corepack ]] || return 44
  }
  node() { "$RUNTIME_NODE" "$@"; }
  check_for_gh_release() {
    printf '%s\n' "$*" >> "$c/selected"
    [[ "$FAULT" != metadata ]] || return 37
    if [[ "$1" == VectorChord ]]; then
      [[ -z "${var_appversion:-}" ]] || return 58
      return 1
    fi
    [[ "$CASE" != same-version ]] || return 1
    return 0
  }
  definition=$(declare -f fetch_and_deploy_gh_release)
  eval "${definition/fetch_and_deploy_gh_release/native_fetch}"
  fetch_and_deploy_gh_release() { if [[ "$1" == VectorChord ]]; then
    [[ -z "${var_appversion:-}" ]] || return 58
    printf '%s\n' "$*" >> "$c/vectorchord"
  else native_fetch "$@"; fi; }
  systemctl() { printf '%s\n' "$*" >> "$c/services"; }
  dpkg() { printf 'ii  libmimalloc3 3.1\nii libde265-dev 1.0.16\n'; }
  git() {
    printf '%s\n' "$*" >> "$c/git"
    if [[ "$1" == clone ]]; then
      local dest="${!#}"
      mkdir -p "$dest"
      if [[ "$*" == *base-images* ]]; then
        [[ "$*" == *'--branch 202610021601'* ]] || return 57
        cp -a "$MAINTENANCE_NEXT_REFERENCES/immich-base-images/." "$dest/"
        mkdir -p "$dest/.git"
      else
        printf '#!/usr/bin/env bash\nexit 0\n' > "$dest/configure"
        chmod +x "$dest/configure"
      fi
    fi
  }
  bash() {
    if [[ "$1" == *'/server/sources/'*.sh ]]; then
      [[ -f "$1" ]] || return 66
      printf '%s\n' "${1##*/}" >> "$c/libraries"
      local library="${1##*/}" revision_variable
      library="${library%.sh}"
      revision_variable="${library^^}_REVISION"
      printf '%s: %s\n' "$library" "$(command bash -c 'printf "%s" "${!1:-missing}"' effective-pin "$revision_variable")" >> "$c/effective-library-pins"
      [[ "$FAULT" != library ]] || return 51
    else command bash "$@"; fi
  }
  pnpm() {
    printf '%s|%s\n' "$PWD" "$*" >> "$c/pnpm"
    local pnpm_number=0
    [[ ! -f "$c/pnpm-count" ]] || pnpm_number=$(< "$c/pnpm-count")
    pnpm_number=$((pnpm_number + 1))
    printf '%s' "$pnpm_number" > "$c/pnpm-count"
    [[ "$FAULT" != "pnpm-$pnpm_number" ]] || return 52
    [[ "$FAULT" != build && "$FAULT" != build-cleanup ]] || return 52
    if [[ "$*" == *deploy* ]]; then
      local dest="${!#}"
      mkdir -p "$dest"/{bin,dist/repositories,node_modules/sharp}
      cp "$MAINTENANCE_NEXT_REFERENCES/immich/server/package.json" "$dest/package.json"
      printf 'start immich\n' > "$dest/bin/immich-admin"
      chmod +x "$dest/bin/immich-admin"
      printf '#!/usr/bin/env bash\nprintf "MODELED CLI artifact\\n"\n' > "$dest/bin/immich"
      chmod +x "$dest/bin/immich"
      printf 'export const build="/build";\n' > "$dest/dist/main.js"
      python3 - "$dest" "$MAINTENANCE_NEXT_REFERENCES" << 'PY'
import pathlib,re,sys
dest,refs=map(pathlib.Path,sys.argv[1:]);source=(refs/'immich/server/src/repositories/config.repository.ts').read_text();constants=(refs/'immich/server/src/constants.ts').read_text()
folders=source[source.index('  const buildFolder ='):source.index('  let redisConfig =')]
start=source.index('    resourcePaths: {',source.index('  return {'));properties=source[start:source.index('    setup:',start)]
cities=re.search(r"export const citiesFile = '[^']+';",constants)[0]
code="import {join} from 'node:path';\n"+cities+"\nexport function getResourcePaths(dto={}) {\n"+folders+'return {\n'+properties+'}.resourcePaths;\n}\n'
(dest/'dist/repositories/config.repository.js').write_text(code)
PY
    fi
    mkdir -p /opt/immich/source/web/build
    printf 'MODELED selected-source web build\n' > /opt/immich/source/web/build/index.html
  }
  mise() {
    printf '%s\n' "$*" >> "$c/mise"
    if [[ "$1" == install ]]; then
      local n=0
      [[ ! -f "$c/mise-count" ]] || n=$(< "$c/mise-count")
      n=$((n + 1))
      printf '%s' "$n" > "$c/mise-count"
      [[ "$FAULT" != mise ]] || return 49
      [[ "$CASE" != retry || "$n" == 3 ]] || return 49
    elif [[ "$1" == bin-paths ]]; then
      [[ "$FAULT" != mise-paths ]] || return 48
      printf '%s\n' "$c/local/bin"
    else
      [[ "$FAULT" != plugin-install || "$*" != *' install '* ]] || return 55
      [[ "$FAULT" != plugin-build || "$*" != *' build' ]] || return 56
      mkdir -p /opt/immich/source/packages/plugin-core/dist
      printf '{}' > /opt/immich/source/packages/plugin-core/manifest.json
    fi
  }
  sudo() {
    while (($#)) && [[ "$1" != uv ]]; do shift; done
    [[ $# -gt 0 ]] || return 0
    shift
    uv "$@"
  }
  uv() {
    printf '%s\n' "$*" >> "$c/uv"
    local counter=sync n=0
    [[ "$1" != python ]] || counter=python
    [[ ! -f "$c/$counter-count" ]] || n=$(< "$c/$counter-count")
    n=$((n + 1))
    printf '%s' "$n" > "$c/$counter-count"
    [[ "$FAULT" != "$counter" ]] || return 47
    [[ "$CASE" != retry || "$n" == 3 ]] || return 47
    if [[ "$1" == sync ]]; then
      mkdir -p "$VIRTUAL_ENV/bin"
      printf ':\n' > "$VIRTUAL_ENV/bin/activate"
    fi
  }
  curl() {
    local out='' format='' url=''
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
    if [[ "$url" == *mise.jdx.dev* ]]; then
      printf 'MODELED signing key\n'
      return 0
    fi
    local body='{"tag_name":"v3.3.1","assets":[]}'
    if [[ -n "$out" ]]; then printf '%s' "$body" > "$out"; else printf '%s' "$body"; fi
    [[ -z "$format" ]] || printf 200
  }
  curl_download() {
    [[ "$FAULT" != download ]] || return 22
    command tar -czf "$1" -C "$c" payload
  }
  curl_with_retry() {
    if [[ "$1" == *countryInfo.txt ]]; then
      printf 'US\tUSA\t840\tUS\tUnited States\n' > "$2"
    elif [[ "$1" == *cities500.zip ]]; then
      python3 - "$2" << 'PY'
import sys,zipfile
with zipfile.ZipFile(sys.argv[1],'w') as z:z.writestr('cities500.txt','MODELED cities fixture\n')
PY
    else printf 'MODELED downloaded data\n' > "$2"; fi
  }
  cp() {
    if [[ "${_immich_probe_app:-0}" == 1 && "${!#}" == */deploy-source.*/payload/ ]]; then
      printf '%s\n' "$*" >> "$c/app-projection-copy"
      [[ "$FAULT" != projection ]] || return 62
    fi
    if [[ "$FAULT" == copy && "${!#}" == /opt/immich/app* && "$*" == *'/deploy-source.'* ]]; then
      command cp -a -- "$3" "${!#}"
      return 41
    fi
    command cp "$@"
  }
  catch_errors
  if [[ "$CASE" == fresh ]]; then install_script; else run_update_script; fi
  exit
fi
work=$(mktemp -d "$TMPDIR/immich-hooks.XXXXXX")
trap 'rm -rf -- "$work"' EXIT
failures=0
check() { if [[ "$1" == "$2" ]]; then printf 'PASS %s\n' "$3"; else
  printf 'FAIL %s expected <%s>, got <%s>\n' "$3" "$2" "$1" >&2
  failures=$((failures + 1))
fi; }
for mode in no yes; do
  for variant in fresh update same-version retry missing-revisions source-upload explicit-pin library-pin cross-device bad-base python sync mise mise-paths node corepack plugin-install plugin-build pnpm-{1..8} library download projection copy build cleanup build-cleanup metadata; do
    for path in /usr/bin/ffmpeg /usr/bin/ffprobe /usr/bin/immich /usr/bin/immich-admin /var/log/immich; do
      [[ ! -e "$path" && ! -L "$path" ]] || {
        printf 'Global fixture boundary changed before case: %s\n' "$path" >&2
        exit 1
      }
    done
    c="$work/$mode-$variant"
    fault=none
    case "$variant" in python | sync | mise | mise-paths | node | corepack | plugin-install | plugin-build | pnpm-* | library | download | projection | copy | build | cleanup | build-cleanup | metadata) fault="$variant" ;; esac
    mkdir -p "$c/"{tmp,opt/immich/app/bin,opt/immich/app/machine-learning/ml-venv,home,cache,local/bin,state,etc/apt/sources.list.d,etc/apt/preferences.d,etc/apt/keyrings,etc/postgresql/16/main,etc/systemd/system,logs,database,payload/server,payload/machine-learning/immich_ml,payload/machine-learning/ann,payload/packages/plugin-core/dist}
    mkdir -p "$c/opt/immich/custom uploads" "$c/opt/immich/geodata" "$c/opt/staging/base-images/.git"
    truncate -s 32M "$c/global-scratch.ext4"
    mkfs.ext4 -q -F "$c/global-scratch.ext4"
    mkdir -p "$c/opt/immich/.app-build.UNKNOWN-PRIOR" "$c/opt/immich/app/dist"
    printf 'UNKNOWN PRIOR STAGE\n' > "$c/opt/immich/.app-build.UNKNOWN-PRIOR/user"
    printf 'OLD LIVE APPLICATION\n' > "$c/opt/immich/app/dist/main.js"
    cp -a "$MAINTENANCE_NEXT_REFERENCES/immich-base-images/." "$c/opt/staging/base-images/"
    cp -a "$MAINTENANCE_NEXT_REFERENCES/immich/." "$c/payload/"
    mkdir -p "$c/opt/immich/source"
    cp -a "$MAINTENANCE_NEXT_REFERENCES/immich/." "$c/opt/immich/source/"
    printf '#shared_preload_libraries =\n' > "$c/etc/postgresql/16/main/postgresql.conf"
    printf 'LICENSE\n' > "$c/payload/LICENSE"
    printf 'CACHE_FOLDER="/cache"\n' > "$c/payload/machine-learning/immich_ml/config.py"
    printf 'USER external database bytes\n' > "$c/database/state"
    printf 'USER upload bytes\n' > "$c/opt/immich/custom uploads/photo"
    printf '{"user":"configuration"}\n' > "$c/opt/immich/app/custom config.json"
    printf 'USER venv marker\n' > "$c/opt/immich/app/machine-learning/ml-venv/user"
    ln -s '/opt/immich/custom uploads' "$c/opt/immich/app/upload"
    printf '#!/usr/bin/env bash\n# USER custom startup options\nset -a\nsource /opt/immich/.env\nset +a\n/usr/bin/node --no-warnings /opt/immich/app/dist/main.js\n' > "$c/opt/immich/app/bin/start.sh"
    printf '#!/usr/bin/env bash\nexit 0\n' > "$c/opt/immich/app/bin/immich-admin"
    chmod +x "$c/opt/immich/app/bin/immich-admin"
    printf '# USER saved secret/port/database\nDB_HOSTNAME=127.0.0.1\nDB_USERNAME=user\nDB_PASSWORD="USER secret"\nDB_DATABASE_NAME=userdb\nIMMICH_MEDIA_LOCATION="/opt/immich/custom uploads"\nIMMICH_CONFIG_FILE="/opt/immich/app/custom config.json"\nIMMICH_PORT=4555\n' > "$c/opt/immich/.env"
    photo_path="$c/opt/immich/custom uploads/photo"
    if [[ "$variant" == source-upload ]]; then
      mkdir -p "$c/opt/immich/source/custom uploads"
      printf 'USER upload bytes\n' > "$c/opt/immich/source/custom uploads/photo"
      printf 'IMMICH_MEDIA_LOCATION="/opt/immich/source/custom uploads"\n' >> "$c/opt/immich/.env"
      photo_path="$c/opt/immich/source/custom uploads/photo"
    elif [[ "$variant" == bad-base ]]; then printf 'FROM unsupported-base\n' > "$c/payload/server/Dockerfile"; fi
    printf '[Service]\nExecStart=/opt/immich/app/bin/start.sh\nEnvironment=USER_PORT=4555\n' > "$c/etc/systemd/system/immich-web.service"
    printf '[Service]\nExecStart=/opt/immich/app/machine-learning/ml_start.sh\n' > "$c/etc/systemd/system/immich-ml.service"
    printf 'Suites: trixie trixie-updates testing\n' > "$c/etc/apt/sources.list.d/debian.sources"
    printf 'deb mise\n' > "$c/etc/apt/sources.list.d/mise.list"
    printf 'UTC\n' > "$c/etc/timezone"
    for tool in extism-js wasm-merge; do
      printf '#!/usr/bin/env bash\nexit 0\n' > "$c/local/bin/$tool"
      chmod +x "$c/local/bin/$tool"
    done
    # find -exec invokes an executable, not the shell's modeled chown function.
    printf '#!/usr/bin/env bash\nexit 0\n' > "$c/local/bin/chown"
    chmod +x "$c/local/bin/chown"
    for f in database-majors libraries pnpm mise uv git services selected corepack owned-app-stages app-publication-calls app-projection-stages app-projection-copy app-cleanup-calls; do : > "$c/$f"; done
    printf '3.0.3\n' > "$c/home/.immich"
    if [[ "$variant" != missing-revisions ]]; then printf '%s: old\n' imagemagick jpegli libheif libjxl libraw libvips > "$c/home/.immich_library_revisions"; fi
    cp "$c/opt/immich/.env" "$c/env-before"
    python3 - "$c/payload" "$c/payload-inputs.json" << 'PY'
import hashlib,json,os,pathlib,stat,sys
root=pathlib.Path(sys.argv[1]);out={}
for p in root.rglob('*'):
 s=p.lstat();r={'mode':s.st_mode,'uid':s.st_uid,'gid':s.st_gid}
 if stat.S_ISLNK(s.st_mode):r['link']=os.readlink(p)
 elif stat.S_ISREG(s.st_mode):r['sha256']=hashlib.sha256(p.read_bytes()).hexdigest()
 out[str(p.relative_to(root))]=r
pathlib.Path(sys.argv[2]).write_text(json.dumps(out))
PY
    python3 - "$ROOT/scripts/lxc/immich.sh" "$c" << 'PY'
import pathlib,re,subprocess,sys
p,c=map(pathlib.Path,sys.argv[1:]);s=subprocess.check_output(['bash','-c','curl() { :; }; source "$1"; declare -f install_script update_script','cold',str(p)],text=True)
mapping={'/etc':str(c/'etc'),'/tmp':str(c/'legacy-scratch'),'/root':str(c/'home'),'/var/log/immich':str(c/'logs'),'/usr/bin/ffmpeg':str(c/'local/bin/ffmpeg'),'/usr/bin/ffprobe':str(c/'local/bin/ffprobe'),'/usr/bin/immich':str(c/'local/bin/immich'),'/usr/bin/immich-admin':str(c/'local/bin/immich-admin')};pattern=r'(?<![A-Za-z0-9_./-])('+ '|'.join(re.escape(k) for k in sorted(mapping,key=len,reverse=True))+r')(?=/|[\s"\x27;|&(){}]|$)';s=re.sub(pattern,lambda m:mapping[m[0]],s)
for original in mapping:assert not re.search(r'(?<![A-Za-z0-9_./-])'+re.escape(original)+r'(?=/|[\s"\x27;|&(){}]|$)',s),('unmapped mutable hook path',original)
for token in re.findall(r'(?<![A-Za-z0-9_./-])(/(?:etc|tmp|root|var|usr)(?:/[^\s"\x27;|&(){}]*)?)',s):
 assert token.startswith(str(c)+'/') or token.startswith(('/usr/local','/usr/lib','/var/cache')) or token in ('/usr/src','/usr/bin/node','/usr/bin/env','/usr/sbin/nologin','/usr/share/keyrings/debian-archive-keyring.gpg'),('unmapped mutable root',token)
(c/'legacy-scratch').mkdir();(c/'hook').write_text(s)
PY
    rc=0
    pin=''
    [[ "$variant" != explicit-pin && "$variant" != fresh ]] || pin=v3.3.1
    library_pin=''
    [[ "$variant" != library-pin ]] || library_pin=caller-validated-tag
    env CASE_DIR="$c" CASE="$variant" FAULT="$fault" RUNTIME_NODE="$RUNTIME_NODE" MAINTENANCE_NEXT_REFERENCES="$MAINTENANCE_NEXT_REFERENCES" PATH="$c/local/bin:$PATH" TMPDIR="$c/tmp" HOME="$c/home" APP=Immich APPLICATION=immich NSAPP=immich var_lxc_git_repo=immich-app/immich var_lxc_release=v3.3.1 var_appversion="$pin" IMAGEMAGICK_REVISION="$library_pin" CTTYPE=1 VERBOSE="$mode" FORCE_DEPLOY=1 UPDATE_FORCE=1 BUILD_LOG="$c/build.log" DEBUG_LOGFILE="$c/error.log" \
      unshare -m --propagation private -- bash "$0" --child > "$c/output" 2>&1 || rc=$?
    expected=0
    case "$fault" in python | sync) expected=47 ;; mise) expected=49 ;; mise-paths) expected=48 ;; node) expected=43 ;; corepack) expected=44 ;; plugin-install) expected=55 ;; plugin-build) expected=56 ;; library) expected=51 ;; build | build-cleanup | pnpm-*) expected=52 ;; cleanup) expected=67 ;; download) expected=250 ;; copy | projection) expected=252 ;; metadata) expected=37 ;; esac
    [[ "$variant" != bad-base ]] || expected=65
    check "$rc" "$expected" "immich/$mode/$variant actual cold-hook status"
    check "$(cat "$c/opt/immich/.app-build.UNKNOWN-PRIOR/user" 2> /dev/null || true)" 'UNKNOWN PRIOR STAGE' "immich/$mode/$variant unknown prior app stage retained"
    while IFS= read -r owned_stage; do
      check "$(test ! -e "$c$owned_stage" && printf gone || printf leaked)" gone "immich/$mode/$variant current owned app stage removed before fixture teardown"
    done < "$c/owned-app-stages"
    if [[ -s "$c/owned-app-stages" ]]; then
      check "$(wc -l < "$c/app-cleanup-calls")" 1 "immich/$mode/$variant current app-stage lifecycle has exactly one checked cleanup owner"
    fi
    if [[ -s "$c/app-publication-calls" ]]; then
      check "$(cat "$c/app-source-protected" 2> /dev/null || true)" protected "immich/$mode/$variant real publication source bytes/mode/owner protected"
      projection_device=0
      python3 - "$c/app-projection-stages" << 'PY' || projection_device=$?
import pathlib,sys
rows=[line.split('|') for line in pathlib.Path(sys.argv[1]).read_text().splitlines()]
assert rows and all(path.startswith('/opt/immich/deploy-source.') and actual==expected for path,actual,expected in rows),rows
PY
      check "$projection_device" 0 "immich/$mode/$variant publication projection stays on app disk despite cross-device global TMPDIR"
      expected_fallbacks=0
      [[ "$fault" != projection ]] || expected_fallbacks=1
      check "$(grep -c '^-a --' "$c/app-projection-copy" || true)" "$expected_fallbacks" "immich/$mode/$variant full projection fallback is limited to explicit injected link failure"
    fi
    source_status=0
    python3 - "$c/payload" "$c/payload-inputs.json" << 'PY' || source_status=$?
import hashlib,json,os,pathlib,stat,sys
root=pathlib.Path(sys.argv[1]);out={}
for p in root.rglob('*'):
 s=p.lstat();r={'mode':s.st_mode,'uid':s.st_uid,'gid':s.st_gid}
 if stat.S_ISLNK(s.st_mode):r['link']=os.readlink(p)
 elif stat.S_ISREG(s.st_mode):r['sha256']=hashlib.sha256(p.read_bytes()).hexdigest()
 out[str(p.relative_to(root))]=r
assert out==json.loads(pathlib.Path(sys.argv[2]).read_text()),'Fixture source archive input changed'
PY
    check "$source_status" 0 "immich/$mode/$variant source archive inputs protected"
    if [[ "$expected" != 0 ]]; then
      check "$(test -f "$c/state/immich" && printf retained || printf lost)" retained "immich/$mode/$variant failed update retains pending truth"
      check "$(grep -c 'Updated successfully' "$c/output" || true)" 0 "immich/$mode/$variant failure never becomes overall update/cleanup success"
    fi
    if [[ "$rc" != "$expected" ]]; then
      python3 - "$c/output" << 'PY'
import pathlib,sys
for line in pathlib.Path(sys.argv[1]).read_text().splitlines()[-6:]:print('DIAG immich '+line)
PY
    fi
    check "$(cat "$c/database/state")" 'USER external database bytes' "immich/$mode/$variant installed database data retained"
    check "$(cat "$photo_path" 2> /dev/null || true)" 'USER upload bytes' "immich/$mode/$variant upload bytes retained"
    if [[ "$variant" != fresh ]]; then
      check "$(stat -c %s "$c/database-majors")" 0 "immich/$mode/$variant installed database major not provisioned"
      status=0
      cmp -s "$c/env-before" "$c/opt/immich/.env" || status=$?
      check "$status" 0 "immich/$mode/$variant saved environment byte-identical"
      check "$(cat "$c/opt/immich/app/custom config.json" 2> /dev/null || true)" '{"user":"configuration"}' "immich/$mode/$variant in-app configured settings retained"
      check "$(cat "$c/opt/immich/app/machine-learning/ml-venv/user" 2> /dev/null || true)" 'USER venv marker' "immich/$mode/$variant existing runtime retained"
    fi
    if [[ "$rc" == 0 ]]; then
      check "$(test -s "$c/opt/immich/geodata/countryInfo.txt" && printf present || printf absent)" present "immich/$mode/$variant countryInfo in actual geodata directory"
      if [[ "$variant" != same-version ]]; then
        build_location=0
        python3 - "$c/pnpm" << 'PY' || build_location=$?
import pathlib,sys
commands=pathlib.Path(sys.argv[1]).read_text().splitlines();targets=[line.split(' deploy ',1)[1] for line in commands if ' --prod --no-optional deploy ' in line]
assert targets and all(p.startswith('/opt/immich/.app-build.') for p in targets),targets
PY
        if [[ "$variant" != fresh ]]; then check "$build_location" 0 "immich/$mode/$variant app artifacts staged on adjacent install disk, independent of TMPDIR"; fi
        status=0
        python3 - "$c/home/.immich_library_revisions" "$c/effective-library-pins" << 'PY' || status=$?
import pathlib,sys
read=lambda p:dict(line.split(': ',1) for line in pathlib.Path(p).read_text().splitlines())
record,used=map(read,sys.argv[1:]);assert set(record)=={'libjxl','jpegli','libheif','libraw','imagemagick','libvips'} and record==used and 'missing' not in used.values(),(record,used)
PY
        check "$status" 0 "immich/$mode/$variant revision record agrees with effective exported compiler pins"
        status=0
        env CASE_DIR="$c" RUNTIME_NODE="$RUNTIME_NODE" MAINTENANCE_NEXT_REFERENCES="$MAINTENANCE_NEXT_REFERENCES" TMPDIR="$c/tmp" unshare -m --propagation private -- bash "$0" --consumer > "$c/consumer-output" 2>&1 || status=$?
        check "$status" 0 "immich/$mode/$variant native selected-source geodata reader sees country names through deployed path"
        if [[ "$status" == 0 ]]; then cat "$c/consumer-output"; else
          python3 - "$c/consumer-output" << 'PY'
import pathlib,sys
for line in pathlib.Path(sys.argv[1]).read_text().splitlines()[-5:]:print('DIAG native consumer '+line)
PY
        fi
        check "$(sort -u "$c/libraries" | tr '\n' ' ')" 'imagemagick.sh jpegli.sh libheif.sh libjxl.sh libraw.sh libvips.sh ' "immich/$mode/$variant all six self-contained selected-source library recipes"
        check "$(grep -c 'uv python\|python install' "$c/uv" || true)" "$(cat "$c/python-count" 2> /dev/null || printf 0)" "immich/$mode/$variant modeled interpreter calls accounted"
        check "$(grep -c 'python3.11' "$c/uv" || true)" 0 "immich/$mode/$variant selected CPU source never requests unsupported Python3.11"
        check "$(grep -c 'node_modules/sharp.*exec npm run build' "$c/pnpm" || true)" 1 "immich/$mode/$variant supported global-libvips sharp build reached"
      fi
    fi
    if [[ "$fault" == python || "$fault" == sync || "$fault" == mise ]]; then
      counter="$fault"
      [[ "$fault" != mise ]] || counter=mise
      check "$(cat "$c/$counter-count" 2> /dev/null || true)" 3 "immich/$mode/$variant all retries reached before exhaustion"
    fi
    for path in /usr/bin/ffmpeg /usr/bin/ffprobe /usr/bin/immich /usr/bin/immich-admin /var/log/immich; do
      check "$(test ! -e "$path" && test ! -L "$path" && printf untouched || printf changed)" untouched "immich/$mode/$variant VM-global fixture boundary preserved: $path"
      [[ ! -e "$path" && ! -L "$path" ]] || {
        printf 'Preserving fixture after global-boundary violation: %s\n' "$c" >&2
        exit 1
      }
    done
    rm -rf -- "$c"
  done
done
printf '%s failure(s); native cold hooks/deployment/files; compiler/ML/database/services modeled\n' "$failures"
[[ "$failures" == 0 ]]
