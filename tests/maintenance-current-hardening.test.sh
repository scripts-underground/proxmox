#!/usr/bin/env bash
# Cold generated commands and real provider/archive/backup consumers. Release
# transport, package/build tools and service control are explicitly modeled.
set -euo pipefail
python3 -B "$(dirname -- "${BASH_SOURCE[0]}")/lib/entrypoint.py" maintenance-current-hardening "$@" || exit $?
[[ "${SU_TEST_GUARD_ONLY:-0}" != 1 ]] || exit 0
systemd-detect-virt --vm --quiet || exit 65
: "${TMPDIR:?disk TMPDIR required}"
case "$(findmnt -rn -T "$TMPDIR" -o FSTYPE)" in '' | tmpfs | ramfs) exit 65 ;; esac
ROOT=$(realpath "$(dirname "${BASH_SOURCE[0]}")/..")
exec python3 -B - "$ROOT" << 'PY'
import hashlib,json,os,pathlib,shlex,subprocess,sys,tarfile,tempfile
R=pathlib.Path(sys.argv[1]);W=pathlib.Path(tempfile.mkdtemp(prefix='current-hardening.',dir=os.environ['TMPDIR']))
print('Hardening evidence: '+str(W),flush=True)
checks=[]
def check(name,wanted,actual):
 ok=wanted==actual;checks.append(dict(name=name,expected=wanted,actual=actual,passed=ok));print(('PASS ' if ok else 'FAIL ')+name+(str((wanted,actual)) if not ok else ''),flush=True)
def write(p,s,mode=0o644):
 p.parent.mkdir(parents=True,exist_ok=True);p.write_text(s);p.chmod(mode)
def read(p):return p.read_text() if p.is_file() else '<absent>'
def pack(source,dest):
 with tarfile.open(dest,'w:gz') as t:t.add(source,arcname='release')
models=r'''
header_info() { :; }
check_container_storage() { :; }
check_container_resources() { :; }
cleanup_lxc() { :; }
addon_baseline() { :; }
stop_spinner() { :; }
msg_info() { :; }
msg_ok() { printf 'OK %s\n' "$*"; }
msg_error() { printf 'ERROR %s\n' "$*" >&2; }
msg_warn() { printf 'WARN %s\n' "$*" >&2; }
ensure_dependencies() { :; }
getent() { return 0; }
setup_uv() { :; }
apt-get() { :; }
npm() { if [[ "$FAULT" == build && "$*" == 'run build' ]]; then return 41; fi; }
uv() { [[ "$FAULT" != build ]] || return 41; }
make() { [[ "$FAULT" != build ]] || return 41; }
zip() { printf zip-fixture > koplugin.zip; }
chown() { :; }
sqlite3() { python3 -B "$CASE_ROOT/sqlite.py" "$@"; }
systemctl() {
  local action="$1" s
  shift
  for s in "$@"; do
    case "$action" in
      stop) printf stopped > "$CASE_ROOT/service-$s" ;;
      start|restart)
        if [[ "$s" == invidious-companion ]]; then "$CASE_ROOT/opt/invidious-companion/invidious_companion" > "$CASE_ROOT/companion-consumer" || return 45; fi
        printf running > "$CASE_ROOT/service-$s"
        ;;
    esac
  done
}
curl() { python3 -B "$CASE_ROOT/http.py" "${app:-}" "$@"; }
curl_download() {
  printf '%s\n' "$2" >> "$CASE_ROOT/downloads"
  [[ "$FAULT" != download ]] || return 17
  local input="$CASE_ROOT/release.tar.gz"
  [[ "$2" != *invidious_companion-* ]] || input="$CASE_ROOT/companion.tar.gz"
  command cp "$input" "$1"
}
cp() {
  if [[ "$FAULT" == provider-backup && "$*" == *'/keycloak/providers '* ]]; then return 42; fi
  if [[ "$FAULT" == provider-restore && "$*" == *'keycloak.old/providers/.'* ]]; then return 43; fi
  command cp "$@"
}
'''
http=r'''
import json,os,pathlib,sys
c=pathlib.Path(os.environ['CASE_ROOT']);app=sys.argv[1];args=sys.argv[2:];out=None;fmt=False;url=''
for i,a in enumerate(args):
 if a=='-o':out=args[i+1]
 if a=='-w':fmt=True
 if a.startswith('https://'):url=a
with (c/'requests').open('a') as f:f.write(json.dumps(dict(app=app,url=url))+'\n')
fault=os.environ['FAULT']
if fault=='checker' or fault=='companion-checker' and app=='Invidious Companion':raise SystemExit(17)
if 'kovidgoyal/calibre' in url:
 print('{"tag_name": "v2.0"}');raise SystemExit(0)
tag='v2.0'
key='companion' if 'invidious-companion' in url else 'main'
count=c/('requests-'+key);n=int(count.read_text())+1 if count.exists() else 1;count.write_text(str(n))
if '/tags/' in url:tag=url.rsplit('/',1)[-1]
elif fault=='selected-race' and n>1:tag='v3.0'
if fault=='selected-mismatch' and '/tags/' in url:tag='v9.0'
asset={'endurain':'source.tar.gz','invidious':'source.tar.gz','keycloak':'keycloak-2.0.tar.gz','cronmaster':'cronmaster_2.0_prebuild.tar.gz','autocaliweb':'source.tar.gz'}[os.environ['TEST_APP']]
if key=='companion':asset='invidious_companion-x86_64-unknown-linux-gnu.tar.gz'
d=dict(tag_name=tag,draft=False,prerelease=False,assets=[dict(name=asset,browser_download_url='https://fixture.invalid/'+asset)])
if 'codeberg.org/api/' in url and '/tags/' not in url:d=[d]
b=json.dumps(d)
if out:pathlib.Path(out).write_text(b)
else:print(b,end='')
if fmt:print('200',end='')
'''
for app in ('endurain','invidious','keycloak','cronmaster','autocaliweb'):
 scenarios=['current','checker','download','selected-race','selected-mismatch']
 scenarios+=['build'] if app in ('endurain','invidious','autocaliweb') else []
 if app=='keycloak':scenarios+=['provider-backup','provider-restore']
 if app=='invidious':scenarios+=['companion-checker','bad-companion']
 for verbose in ('no','yes'):
  for fault in scenarios:
   c=W/(app+'-'+verbose+'-'+fault);c.mkdir();live=c/'opt'/app;incoming=c/'incoming';incoming.mkdir()
   for n in ('home','tmp','stage','sbin','config'): (c/n).mkdir()
   protected={}
   def protect(p,s,mode=0o600):write(p,s,mode);protected[str(p)]=dict(data=s,mode=mode)
   marker={'keycloak':'keycloak_app'}.get(app,app)
   write(c/'home'/('.'+marker),'2.0\n' if fault=='current' or fault=='companion-checker' else '1.0\n')
   write(live/'selected-version','1.0\n');write(incoming/'selected-version','2.0\n')
   services={'endurain':['endurain'],'invidious':['invidious','invidious-companion'],'keycloak':['keycloak'],'cronmaster':['fixture-cronmaster'],'autocaliweb':['autocaliweb','metadata-change-detector','acw-ingest-service','acw-auto-zipper']}[app]
   for s in services:write(c/('service-'+s),'running')
   if app=='endurain':
    protect(live/'.env','operator env\n');protect(live/'frontend/dist/env.js','operator frontend\n',0o640)
    write(live/'backend/pyproject.toml','[tool.uv]\nrequired-version = "0.11.18"\n')
    write(incoming/'.env','release env\n');write(incoming/'frontend/dist/env.js','release frontend\n');write(incoming/'backend/pyproject.toml','[tool.uv]\nrequired-version = "0.11.18"\n')
   elif app=='invidious':
    protect(live/'config/config.yml','operator invidious\n')
    write(incoming/'config/config.yml','release invidious\n');write(incoming/'src/invidious.cr','CURRENT_BRANCH = "old"\nCURRENT_COMMIT = "old"\nCURRENT_VERSION = "old"\nCURRENT_TAG = "old"\nASSET_COMMIT = "old"\n')
    write(live/'src/invidious.cr',(incoming/'src/invidious.cr').read_text())
    companion=c/'opt/invidious-companion';write(companion/'invidious_companion','#!/usr/bin/env bash\nprintf "old companion"\n',0o755)
    write(c/'companion-input/invidious_companion','#!/usr/bin/env bash\nprintf "new companion"\n',0o755)
    write(c/'home/.invidiouscompanion','2.0\n' if fault in ('current','companion-checker') else '1.0\n')
    if fault=='bad-companion':
     (c/'companion-input/invidious_companion').unlink();write(c/'companion-input/not-the-executable','bad payload\n')
    pack(c/'companion-input',c/'companion.tar.gz')
   elif app=='keycloak':
    for name in ('conf/keycloak.conf','providers/x/p.jar','themes/t/theme.properties'):
     protect(live/name,'operator '+name+'\n',0o640);write(incoming/name,'release '+name+'\n')
    write(incoming/'conf/new-default.properties','new-default\n')
   elif app=='cronmaster':
    protect(c/'config/operator.env','operator cron env\n')
    write(live/'server.js','old cron code\n');write(incoming/'server.js','new cron code\n')
   else:
    for name in ('dirs.json','.env','scripts/ingest_watcher.sh','scripts/auto_zipper_wrapper.sh','scripts/metadata_change_detector_wrapper.sh','metadata_change_logs/old.json'):
     protect(live/name,'operator '+name+'\n',0o640);write(incoming/name,'release '+name+'\n')
    for root in (live,incoming):
     write(root/'koreader/plugins/acwsync.koplugin/main.lua','plugin input\n');(root/'cps/static').mkdir(parents=True)
    write(c/'systemd/autocaliweb.service','Environment=CALIBRE_PORT=80\nAmbientCapabilities=CAP_NET_BIND_SERVICE\n')
    import sqlite3
    db=sqlite3.connect(c/'config/app.db');db.execute('CREATE TABLE settings(config_port TEXT,custom TEXT)');db.execute("INSERT INTO settings VALUES('80','operator setting')");db.commit();db.close()
    write(c/'sqlite.py','import sqlite3,sys\nc=sqlite3.connect(sys.argv[1]);c.execute(sys.argv[2]);c.commit();c.close()\n')
   pack(incoming,c/'release.tar.gz')
   write(c/'models.sh',models);write(c/'http.py',http)
   core=(R/'misc/core.func').read_text().replace('/var/lib/scripts-underground/update-pending',str(c/'pending')).replace('/var/lib/scripts-underground/maintenance-locks',str(c/'locks'))
   write(c/'stage/core.func',core)
   for name in ('tools.func','error_handler.func'):write(c/'stage'/name,(R/'misc'/name).read_text())
   write(c/'stage/install.func','pkg_install() { :; }\nsetup_lxc() { :; }\n')
   write(c/'stage/github.func','clone_and_deploy_gh_commit() { :; }\nsource '+shlex.quote(str(c/'models.sh'))+'\n')
   write(c/'stage/addon.func','source '+shlex.quote(str(c/'models.sh'))+'\n')
   kind='addon' if app=='cronmaster' else 'lxc';text=(R/'scripts'/kind/(app+'.sh')).read_text();start=text.index('function update_script() {');end=text.index('\n}\n',start)+3
   hook=text[start:end].replace('/opt',str(c/'opt')).replace('/etc/systemd/system',str(c/'systemd')).replace('/etc/autocaliweb/app.db',str(c/'config/app.db')).replace('/usr/bin/kepubify',str(c/'kepubify'))
   write(c/'kepubify','#!/usr/bin/env bash\nprintf v2.0\n',0o755);write(c/'hook.sh',hook)
   compose='source '+shlex.quote(str(R/'misc/bundle.func'))+'\nsource '+shlex.quote(str(R/'misc/addon_lxc.func'))+'\n'
   compose+='export APP='+shlex.quote(app)+' NSAPP='+app+' APP_SLUG='+app+' REPO_BASE=https://fixture.invalid var_lxc_tmpdir='+shlex.quote(str(c/'tmp'))+'\n'
   if app=='cronmaster':
    # Deliberately nondefault baked values; no install-time ambient variables.
    for k,v in dict(install_path=str(live),config_path=str(c/'config/operator.env'),service_path=str(c/'systemd/custom.service'),service='fixture-cronmaster',repo='fixture/cronmaster',backup_dir=str(c/'cron-backup'),creds_path=str(c/'config/creds'),default_port='80').items():compose+='export var_addon_'+k+'='+shlex.quote(v)+'\n'
   compose+='source '+shlex.quote(str(c/'hook.sh'))+'\n'
   compose+=('_addon_bundle_contents update update_script ' if kind=='addon' else '_write_bundle update update_script ')+shlex.quote(str(c/'stage'))
   if kind!='addon':compose+=' '+shlex.quote('run_update_script "$@"')
   with (c/'sbin/update').open('w') as out:subprocess.run(['bash','-ceu',compose],stdout=out,check=True,timeout=20)
   digest=hashlib.sha256((c/'sbin/update').read_bytes()).hexdigest()
   def invoke(label,active):
    env=dict(PATH=os.environ['PATH'],HOME=str(c/'home'),TMPDIR=str(c/'tmp'),CASE_ROOT=str(c),TEST_APP=app,FAULT=active,VERBOSE=verbose,BACKUP_DIR=str(c/'backup'),BUILD_LOG=str(c/(label+'.log')),DEBUG_LOGFILE=str(c/(label+'-error.log')))
    with (c/(label+'-output')).open('w') as out:r=subprocess.run(['timeout','45s','bash',str(c/'sbin/update')],env=env,stdout=out,stderr=subprocess.STDOUT,timeout=50)
    return r.returncode
   primary=invoke('primary',fault);name=app+'/'+verbose+'/'+fault
   expected=(22 if app=='autocaliweb' else 17) if fault in ('checker','companion-checker') else 250 if fault in ('download','selected-mismatch') else 41 if fault=='build' else 42 if fault=='provider-backup' else 43 if fault=='provider-restore' else 252 if fault=='bad-companion' else 0
   check(name+'/primary status',expected,primary)
   if expected:
    check(name+'/pending retained',True,(c/'pending'/app).is_file())
    if fault=='bad-companion':check(name+'/invalid payload preserves old executable','#!/usr/bin/env bash\nprintf "old companion"\n',read(c/'opt/invidious-companion/invidious_companion'))
    if app=='invidious' and fault=='bad-companion':
     write(c/'companion-retry/invidious_companion','#!/usr/bin/env bash\nprintf "new companion"\n',0o755);pack(c/'companion-retry',c/'companion.tar.gz')
    retry=invoke('retry','none');check(name+'/ordinary retry status',0,retry)
   if fault=='selected-race':check(name+'/selected marker','2.0\n',read(c/'home'/('.'+marker)))
   if app=='invidious' and fault=='selected-race':check(name+'/selected companion marker','2.0\n',read(c/'home/.invidiouscompanion'))
   for p,f in protected.items():
    q=pathlib.Path(p);check(name+'/protected bytes/'+str(q.relative_to(c)),f['data'],read(q));check(name+'/protected mode/'+str(q.relative_to(c)),f['mode'],q.stat().st_mode&0o777 if q.exists() else -1)
   for s in services:check(name+'/final service/'+s,'running',read(c/('service-'+s)))
   if app=='invidious' and fault!='current':check(name+'/companion consumer','new companion',read(c/'companion-consumer'))
   if app=='keycloak' and fault!='current':check(name+'/new release default','new-default\n',read(live/'conf/new-default.properties'))
   if app=='cronmaster' and fault!='current':check(name+'/baked source selection',True,'fixture/cronmaster' in read(c/'requests'))
   if app=='autocaliweb':
    import sqlite3
    db=sqlite3.connect(c/'config/app.db');row=db.execute('SELECT config_port,custom FROM settings').fetchone();db.close();check(name+'/fixed config consumer',['80','operator setting'],list(row))
   check(name+'/final pending retired',False,(c/'pending'/app).exists());check(name+'/frozen command unchanged',digest,hashlib.sha256((c/'sbin/update').read_bytes()).hexdigest())
check('original assertions retained',784,len(checks))
exec(compile((R/'tests/maintenance-romm-current.py').read_bytes(),'maintenance-romm-current.py','exec'))
exec(compile((R/'tests/maintenance-input-current.py').read_bytes(),'maintenance-input-current.py','exec'))
failures=sum(not x['passed'] for x in checks);(W/'result.json').write_text(json.dumps(dict(checks=checks,failures=failures,scope='cold generated commands/native files, tar, metadata and SQLite; network/build/services modeled'),sort_keys=True,indent=2))
print(str(len(checks))+' current hardening checks; '+str(failures)+' failure(s)',flush=True)
if not failures:print('CURRENT_HARDENING_PASS',flush=True)
raise SystemExit(1 if failures else 0)
PY
