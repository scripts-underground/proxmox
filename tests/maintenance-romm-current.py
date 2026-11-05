"""RomM cases run by the admitted current-hardening consumer in its namespace.

Native files, archives, provider, backup, pending and maintenance owners are real.
HTTP, Node/package/build and service control are recording models. The build model
clears dist like Vite; this is caller proof, not a complete RomM installation.
"""
import shutil
import zipfile

romm_models = models + r'''
setup_nodejs() { printf 'node=%s\n' "$NODE_VERSION" >> "$CASE_ROOT/runtime"; }
npm() {
  printf 'npm %s\n' "$*" >> "$CASE_ROOT/builds"
  [[ "$FAULT" != build ]] || return 41
  if [[ "$*" == 'run build' ]]; then
    command rm -rf "$CASE_ROOT/opt/romm/frontend/dist"
    command mkdir -p "$CASE_ROOT/opt/romm/frontend/dist/assets"
  fi
}
uv() { printf 'uv %s\n' "$*" >> "$CASE_ROOT/builds"; }
systemctl() {
  printf '%s\n' "$*" >> "$CASE_ROOT/service-calls"
  local action="$1" s; shift
  for s in "$@"; do
    case "$action" in
      stop) printf stopped > "$CASE_ROOT/service-$s" ;;
      start|restart) printf running > "$CASE_ROOT/service-$s" ;;
    esac
  done
}
curl_download() {
  printf '%s\n' "$2" >> "$CASE_ROOT/downloads"
  [[ "$FAULT" != download ]] || return 17
  local input="$CASE_ROOT/release.tar.gz"
  case "$2" in
    *ruffle*) input="$CASE_ROOT/ruffle.zip" ;;
    *4.2.3.7z*) input="$CASE_ROOT/emulator.7z" ;;
  esac
  command cp "$input" "$1"
}
cp() {
  if [[ "$FAULT" == env-restore && "${3:-}" == *'/backup/files/'* ]]; then return 43; fi
  if [[ "$FAULT" == player-restore && "${3:-}" == *'/romm-players.backup/files/'* ]]; then return 44; fi
  command cp "$@"
}
'''
romm_http = r'''
import json,os,pathlib,sys
c=pathlib.Path(os.environ['CASE_ROOT']);app=sys.argv[1];args=sys.argv[2:];out=None;fmt=False;url=''
for i,a in enumerate(args):
 if a=='-o':out=args[i+1]
 if a=='-w':fmt=True
 if a.startswith('https://'):url=a
with (c/'requests').open('a') as f:f.write(json.dumps(dict(app=app,url=url))+'\n')
fault=os.environ['FAULT'];main='rommapp/romm/' in url;ejs='EmulatorJS/EmulatorJS/' in url
if fault=='checker' and main or fault=='emulator-checker' and ejs:raise SystemExit(17)
tag='v2.0' if main else 'v4.2.3' if ejs else 'nightly-2026-11-04'
count=c/('main-requests' if main else 'player-requests');n=int(count.read_text())+1 if count.exists() else 1;count.write_text(str(n))
if '/tags/' in url:tag=url.rsplit('/',1)[-1]
elif main and fault=='selected-race' and n>1:tag='v3.0'
if main and fault=='selected-mismatch' and '/tags/' in url:tag='v9.0'
asset='4.2.3.7z' if ejs else 'ruffle-nightly-web-selfhosted.zip'
d=dict(tag_name=tag,draft=False,prerelease=False,assets=[dict(name=asset,browser_download_url='https://fixture.invalid/'+asset)])
b=json.dumps(d)
if out:pathlib.Path(out).write_text(b)
else:print(b,end='')
if fmt:print('200',end='')
'''
services = ['romm-backend', 'romm-worker', 'romm-scheduler', 'romm-watcher', 'romm-scan-worker']
for verbose in ('no', 'yes'):
 for fault in ('current', 'checker', 'emulator-checker', 'selected-race', 'selected-mismatch', 'download', 'build', 'env-restore', 'player-restore', 'ruffle-missing', 'emulator-missing', 'pinned-players'):
  c=W/('romm-'+verbose+'-'+fault);c.mkdir();live=c/'opt/romm'
  for n in ('home','tmp','stage','sbin','config','incoming/backend','incoming/frontend/assets'):(c/n).mkdir(parents=True)
  incoming=c/'incoming';write(incoming/'selected-version','2.0\n');write(incoming/'.env','release env\n');write(incoming/'frontend/assets/base.js','base asset\n')
  write(live/'selected-version','1.0\n')
  protected={}
  def protect_romm(p,s,mode):
   write(p,s,mode);protected[str(p)]=dict(data=s,mode=mode)
  protect_romm(live/'.env','ROMM_BASE_PATH='+str(c/'library')+'\nOPERATOR=secret\n',0o600)
  protect_romm(c/'library/config/config.yml','operator config\n',0o640)
  protect_romm(c/'library/library/roms/original.rom','original game\n',0o640)
  players=live/'frontend/dist/assets'
  for n in ('ruffle/ruffle.js','emulatorjs/data/loader.js','emulatorjs/data/cores/core.wasm'):
   protect_romm(players/n,'operator '+n+'\n',0o640)
  current=fault in ('current','checker','emulator-checker','ruffle-missing','emulator-missing','pinned-players')
  write(c/'home/.romm','2.0\n' if current else '1.0\n');write(c/'home/.emulatorjs','4.2.3\n');write(c/'home/.ruffle','nightly-2026-11-04\n')
  for s in services:write(c/('service-'+s),'running')
  write(c/'systemd/romm-scan-worker.service','[Service]\nExecStart=unchanged\n')
  if fault in ('ruffle-missing','pinned-players'):
   (players/'ruffle/ruffle.js').unlink();del protected[str(players/'ruffle/ruffle.js')]
  if fault in ('emulator-missing','pinned-players'):
   shutil.rmtree(players/'emulatorjs');protected={p:v for p,v in protected.items() if '/emulatorjs/' not in p}
  pack(incoming,c/'release.tar.gz')
  with zipfile.ZipFile(c/'ruffle.zip','w') as z:z.writestr('ruffle.js','new ruffle\n')
  write(c/'player-input/data/loader.js','operator emulatorjs/data/loader.js\n',0o640);write(c/'player-input/data/cores/core.wasm','operator emulatorjs/data/cores/core.wasm\n',0o640)
  write(c/'player-input/README','pinned player distribution\n')
  subprocess.run(['7z','a',str(c/'emulator.7z'),'data','README'],cwd=c/'player-input',stdout=subprocess.DEVNULL,check=True,timeout=20)
  write(c/'models.sh',romm_models);write(c/'http.py',romm_http)
  core=(R/'misc/core.func').read_text().replace('/var/lib/scripts-underground/update-pending',str(c/'pending')).replace('/var/lib/scripts-underground/maintenance-locks',str(c/'locks'))
  write(c/'stage/core.func',core)
  for n in ('tools.func','error_handler.func'):write(c/'stage'/n,(R/'misc'/n).read_text())
  write(c/'stage/install.func','pkg_install() { :; }\nsetup_lxc() { :; }\n')
  write(c/'stage/github.func','clone_and_deploy_gh_commit() { :; }\nsource '+shlex.quote(str(c/'models.sh'))+'\n')
  text=(R/'scripts/lxc/romm.sh').read_text();start=text.index('function update_script() {');end=text.index('\n}\n',start)+3
  hook=text[start:end].replace('/opt',str(c/'opt')).replace('/etc/systemd/system',str(c/'systemd')).replace('/etc/angie',str(c/'angie')).replace('/etc/nginx',str(c/'nginx'))
  write(c/'hook.sh',hook)
  compose='source '+shlex.quote(str(R/'misc/bundle.func'))+'\nexport APP=RomM NSAPP=romm REPO_BASE=https://fixture.invalid var_lxc_tmpdir='+shlex.quote(str(c/'tmp'))+'\nsource '+shlex.quote(str(c/'hook.sh'))+'\n_write_bundle update update_script '+shlex.quote(str(c/'stage'))+' '+shlex.quote('run_update_script "$@"')
  with (c/'sbin/update').open('w') as out:subprocess.run(['bash','-ceu',compose],stdout=out,check=True,timeout=20)
  digest=hashlib.sha256((c/'sbin/update').read_bytes()).hexdigest()
  def invoke_romm(label,active):
   env=dict(PATH=os.environ['PATH'],HOME=str(c/'home'),TMPDIR=str(c/'tmp'),CASE_ROOT=str(c),FAULT=active,VERBOSE=verbose,BACKUP_DIR=str(c/'backup'),BUILD_LOG=str(c/(label+'.log')),DEBUG_LOGFILE=str(c/(label+'-error.log')))
   if fault=='pinned-players':env['var_appversion']='v2.0'
   with (c/(label+'-output')).open('w') as out:r=subprocess.run(['timeout','45s','bash',str(c/'sbin/update')],env=env,stdout=out,stderr=subprocess.STDOUT,timeout=50)
   return r.returncode
  expected=17 if fault in ('checker','emulator-checker') else 250 if fault in ('download','selected-mismatch') else 41 if fault=='build' else 43 if fault=='env-restore' else 44 if fault=='player-restore' else 0
  name='romm/'+verbose+'/'+fault;primary=invoke_romm('primary',fault);check(name+'/primary status',expected,primary)
  lock_inode=(c/'locks/romm.lock').stat().st_ino
  check(name+'/primary pending',bool(expected),(c/'pending/romm').is_file())
  if fault in ('current','checker','emulator-checker'):
   check(name+'/no deployment',False,(c/'downloads').exists());check(name+'/no service control',False,(c/'service-calls').exists())
   check(name+'/no success update',False,'Updated successfully' in read(c/'primary-output'))
  if expected:
   # Snapshot before ordinary pending retry, including recovery objects and services.
   (c/'primary-state.json').write_text(json.dumps(dict(pending=(c/'pending/romm').exists(),services={s:read(c/('service-'+s)) for s in services},files={p:read(pathlib.Path(p)) for p in protected}),sort_keys=True))
   check(name+'/ordinary retry status',0,invoke_romm('retry','none'))
  for p,v in protected.items():
   q=pathlib.Path(p);check(name+'/protected bytes/'+str(q.relative_to(c)),v['data'],read(q));check(name+'/protected mode/'+str(q.relative_to(c)),v['mode'],q.stat().st_mode&0o777 if q.exists() else -1)
  for s in services:check(name+'/final service/'+s,'running',read(c/('service-'+s)))
  if fault=='selected-race':
   check(name+'/selected marker','2.0\n',read(c/'home/.romm'));check(name+'/selected source','2.0\n',read(live/'selected-version'))
   requests=[json.loads(line)['url'] for line in read(c/'requests').splitlines()]
   check(name+'/no latest reselection',1,sum(u.endswith('/rommapp/romm/releases/latest') for u in requests))
  if fault in ('ruffle-missing','pinned-players'):
   check(name+'/ruffle consumer','new ruffle\n',read(players/'ruffle/ruffle.js'))
   check(name+'/independent ruffle latest',True,'ruffle-rs/ruffle/releases/latest' in read(c/'requests'))
  if fault in ('emulator-missing','pinned-players'):
   check(name+'/independent emulator pin',False,'EmulatorJS/EmulatorJS/releases/tags/v2.0' in read(c/'requests'))
  if fault in ('emulator-missing','pinned-players'):check(name+'/loader consumer','operator emulatorjs/data/loader.js\n',read(players/'emulatorjs/data/loader.js'))
  check(name+'/runtime policy','node=24\n'*(2 if expected else 1),read(c/'runtime'))
  check(name+'/final pending retired',False,(c/'pending/romm').exists());check(name+'/maintenance mode',0o600,(c/'locks/romm.lock').stat().st_mode&0o777)
  check(name+'/stable maintenance inode',lock_inode,(c/'locks/romm.lock').stat().st_ino)
  check(name+'/frozen command unchanged',digest,hashlib.sha256((c/'sbin/update').read_bytes()).hexdigest())
