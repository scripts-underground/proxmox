#!/usr/bin/env bash
set -euo pipefail
systemd-detect-virt --vm -q || exit 77
exec python3 - "$(dirname "${BASH_SOURCE[0]}")/.." << 'PY'
import json,os,pathlib,re,shlex,shutil,subprocess,time
assert os.geteuid()==0
assert pathlib.Path('/sys/class/dmi/id/product_uuid').read_text().strip().lower()=='4be13420-4459-4200-a1c2-7ac7232ac650'
source=pathlib.Path(os.sys.argv[1]).resolve()
root=pathlib.Path('/srv/scripts-underground-tests/evidence')/('backup-recovery-'+str(time.time_ns()));root.mkdir(mode=0o700)
rows=[]
cases=['capture-copy-error','capture-retry-directory','restore-copy-error','restore-retry','manifest-reader-error','missing-saved-path',
       'current-endurain','current-wanderer','current-romm-custom-store']
for scenario in cases:
 case=root/scenario;case.mkdir(mode=0o700)
 for name in ['opt','lib','tmp','home','etc']:(case/name).mkdir(mode=0o700)
 (case/'lib/dpkg').mkdir();shutil.copy2('/var/lib/dpkg/status',case/'lib/dpkg/status')
 shutil.copytree('/etc/alternatives',case/'etc/alternatives',symlinks=True)
 (case/'etc/os-release').write_bytes(pathlib.Path('/etc/os-release').read_bytes())
 (case/'actions').write_text('')
 path='/opt/fixture/data'
 if scenario=='current-endurain':path='/opt/endurain/.env'
 elif scenario=='current-wanderer':path='/opt/wanderer/source/search'
 elif scenario=='current-romm-custom-store':path='/opt/romm/frontend/dist/assets/emulatorjs'
 target=case/'opt'/path.removeprefix('/opt/');target.parent.mkdir(parents=True,exist_ok=True)
 directory=scenario in {'capture-retry-directory','current-wanderer','current-romm-custom-store'}
 if directory:target.mkdir();(target/'sentinel').write_text('original protected directory\n');(target/'sentinel').chmod(0o600)
 else:target.write_text('original protected bytes\n');target.chmod(0o600)
 store=case/'opt'/('romm-players.backup' if scenario=='current-romm-custom-store' else 'fixture.backup')
 stored=store/'files'/path.removeprefix('/')
 if scenario!='capture-copy-error':
  stored.parent.mkdir(parents=True,exist_ok=True)
  shutil.copytree(target,stored) if directory else shutil.copy2(target,stored)
  (store/'.manifest').write_text(path+'\n')
  if scenario=='capture-retry-directory':
   (store/'.manifest').write_text('');(stored/'sentinel').write_text('partial interrupted capture\n')
  elif scenario=='missing-saved-path':stored.unlink()
  elif directory:(target/'sentinel').write_text('incoming release directory\n')
  else:target.write_text('incoming release bytes\n')
 if scenario=='current-romm-custom-store':
  (case/'opt/romm/backend').mkdir(parents=True,exist_ok=True)
  assets=target.parent;(assets/'ruffle').mkdir();(assets/'ruffle/ruffle.js').write_text('valid ruffle\n')
  (target/'data/cores').mkdir(parents=True);(target/'data/loader.js').write_text('valid loader\n')
  (stored/'data/cores').mkdir(parents=True);(stored/'data/loader.js').write_text('valid loader\n')
 if scenario=='current-wanderer':
  (case/'opt/wanderer/start.sh').write_text('installed\n')
  for plugin in ['hammerhead','komoot','strava']:
   p=case/'opt/wanderer/data/plugins'/plugin;p.mkdir(parents=True)
   (p/'plugin.json').write_text(json.dumps({'id':plugin}));(p/'plugin.wasm').write_text('installed plugin\n')
 header='source '+shlex.quote(str(source/'misc/tools.func'))+'\n'+r'''
STD=''
NSAPP=fixture
APP='Fixture'
header_info() { :; }
check_container_storage() { :; }
check_container_resources() { :; }
check_available_storage_bytes() { return 0; }
setup_nodejs() { :; }
msg_info() { :; }
msg_ok() { printf 'OK %s\n' "$*"; }
msg_debug() { :; }
msg_warn() { printf 'WARN %s\n' "$*" >&2; }
msg_error() { printf 'ERROR %s\n' "$*" >&2; }
check_for_gh_release() { printf 'release-check\n' >> "$CASE/actions"; return 1; }
check_for_codeberg_release() { check_for_gh_release; }
systemctl() { printf 'service %s\n' "$*" >> "$CASE/actions"; }
cp() {
 if [[ ! -f "$CASE/fault-delivered" && ("$SCENARIO" == capture-copy-error || "$SCENARIO" == restore-copy-error || "$SCENARIO" == restore-retry) ]]; then
  printf 'delivered\n' > "$CASE/fault-delivered"
  printf 'native-prefix\n' > "${*: -1}"
  return 37
 fi
 command cp "$@"
}
cat() {
 if [[ "$SCENARIO" == manifest-reader-error && "${*: -1}" == */.manifest ]]; then
  command cat "$@"; printf 'delivered\n' > "$CASE/fault-delivered"; return 37
 fi
 command cat "$@"
}
set -euo pipefail
'''
 expression='if restore_backup; then exit 0; else exit $?; fi'
 if scenario.startswith('capture-'):expression='if create_backup "$PROTECTED_PATH"; then exit 0; else exit $?; fi'
 if scenario.startswith('current-'):
  app={'current-endurain':'endurain','current-wanderer':'wanderer','current-romm-custom-store':'romm'}[scenario]
  text=(source/('scripts/lxc/'+app+'.sh')).read_text()
  hook=re.search(r'^function update_script\(\) \{\n.*?^\}',text,re.M|re.S);assert hook
  header+=hook.group(0)+'\n'
  if app=='romm':header+='var_lxc_romm_minimum_free_bytes=0\n'
  expression='if update_script; then exit 0; else exit $?; fi'
 code='import subprocess\n'
 for name,dest in [('opt','/opt'),('lib','/var/lib'),('tmp','/tmp'),('etc','/etc')]:code+='subprocess.run(["mount","--bind",'+repr(str(case/name))+','+repr(dest)+'],check=True)\n'
 env=dict(os.environ,CASE=str(case),SCENARIO=scenario,HOME=str(case/'home'),TMPDIR=str(case/'tmp'),PROTECTED_PATH=path)
 code+='raise SystemExit(subprocess.run(["bash","-c",'+repr(header+expression)+'],env='+repr(env)+').returncode)\n'
 def invoke():return subprocess.run(['unshare','--mount','--propagation','private','python3','-c',code],capture_output=True,text=True,timeout=90)
 run=invoke();checks=[]
 def check(label,expected,actual):checks.append({'name':label,'expected':expected,'actual':actual,'passed':expected==actual})
 expected=37 if scenario in {'capture-copy-error','restore-copy-error','restore-retry','manifest-reader-error'} else 252 if scenario=='missing-saved-path' else 0
 check('checked original process status',expected,run.returncode)
 if scenario in {'capture-copy-error','restore-copy-error','restore-retry','manifest-reader-error'}:check('actual producer fault delivered',True,(case/'fault-delivered').exists())
 if scenario in {'restore-copy-error','restore-retry','manifest-reader-error','missing-saved-path'}:
  check('original backup remains recoverable',True,(store/'.manifest').exists())
  check('failed restoration never removes current live path','original protected bytes\n' if scenario=='missing-saved-path' else 'incoming release bytes\n',target.read_text() if target.exists() else None)
 if scenario=='restore-retry':
  retry=invoke();check('retry after actual restore fault',0,retry.returncode)
  check('actual protected bytes restored','original protected bytes\n',target.read_text() if target.exists() else None)
 if scenario=='capture-retry-directory':
  check('partial directory cannot cause nested retry copies','original protected directory\n',(stored/'sentinel').read_text() if (stored/'sentinel').exists() else None)
  check('no accidental nested source directory',False,(stored/'data').exists())
 if scenario.startswith('current-'):
  final=target/'sentinel' if directory else target
  check('current-marker hook recovers original consumer bytes','original protected directory\n' if directory else 'original protected bytes\n',final.read_text() if final.exists() else None)
 row={'case':scenario,'status':'PASS' if all(c['passed'] for c in checks) else 'FAIL','checks':checks,'stdout':run.stdout,'stderr':run.stderr,'process_status':run.returncode}
 (case/'result.json').write_text(json.dumps(row,indent=2)+'\n');rows.append(row);print(row['status']+' '+scenario,flush=True)
document={'status':'PASS' if all(r['status']=='PASS' for r in rows) else 'FAIL','cases':rows,'scope':'actual helpers/hooks and native private files; modeled release/service callbacks, no application runtime claim'}
(root/'results.json').write_text(json.dumps(document,indent=2)+'\n');print('EVIDENCE',root/'results.json')
raise SystemExit(0 if document['status']=='PASS' else 2)
PY
