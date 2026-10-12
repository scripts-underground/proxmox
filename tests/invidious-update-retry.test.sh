#!/usr/bin/env bash
set -euo pipefail
systemd-detect-virt --vm -q || exit 77
exec python3 - "$(dirname "${BASH_SOURCE[0]}")/.." << 'PY'
import json,os,pathlib,re,shlex,shutil,subprocess,tarfile,time
assert os.geteuid()==0
assert pathlib.Path('/sys/class/dmi/id/product_uuid').read_text().strip().lower()=='4be13420-4459-4200-a1c2-7ac7232ac650'
source=pathlib.Path(os.sys.argv[1]).resolve();root=pathlib.Path('/srv/scripts-underground-tests/evidence')/('invidious-retry-'+str(time.time_ns()));root.mkdir(mode=0o700);rows=[]
text=(source/'scripts/lxc/invidious.sh').read_text();hook=re.search(r'^function update_script\(\) \{\n.*?^\}',text,re.M|re.S);assert hook
for scenario in ['both-download-error-retry','ordinary-companion-only','main-selected-error','companion-metadata-error']:
 case=root/scenario;case.mkdir(mode=0o700)
 for leaf in ['opt','lib','etc','tmp','home','incoming','companion']:(case/leaf).mkdir(mode=0o700)
 (case/'lib/dpkg').mkdir();shutil.copy2('/var/lib/dpkg/status',case/'lib/dpkg/status');shutil.copytree('/etc/alternatives',case/'etc/alternatives',symlinks=True)
 (case/'opt/invidious/config').mkdir(parents=True);(case/'opt/invidious/config/config.yml').write_text('administrator secret config\n');(case/'opt/invidious/config/config.yml').chmod(0o600)
 (case/'opt/invidious-companion').mkdir();(case/'opt/invidious-companion/invidious_companion').write_text('old companion\n')
 (case/'incoming/src').mkdir();(case/'incoming/src/invidious.cr').write_text('CURRENT_VERSION = "1"\n');(case/'incoming/config').mkdir();(case/'incoming/config/config.yml').write_text('upstream template\n')
 (case/'companion/invidious_companion').write_text('new companion\n');(case/'companion/invidious_companion').chmod(0o755)
 for name,folder in [('main.tar.gz','incoming'),('companion.tar.gz','companion')]:
  with tarfile.open(case/name,'w:gz') as archive:archive.add(case/folder,arcname='release')
 (case/'home/.invidious').write_text('2.0.0\n' if scenario=='ordinary-companion-only' else '1.0.0\n');(case/'home/.invidiouscompanion').write_text('1.0.0\n')
 (case/'states.json').write_text(json.dumps({'invidious':True,'invidious-companion':True}));(case/'actions').write_text('')
 body='source '+shlex.quote(str(source/'misc/tools.func'))+'\n'+hook.group(0)+'\n'+r'''
STD=''
NSAPP=invidious
header_info() { :; }
check_container_storage() { :; }
check_container_resources() { :; }
msg_info() { :; }
msg_ok() { :; }
msg_debug() { :; }
msg_warn() { printf 'WARN %s\n' "$*" >&2; }
msg_error() { printf 'ERROR %s\n' "$*" >&2; }
check_for_gh_release() {
 local fixture_app=${1,,};fixture_app=${fixture_app// /}
 if [[ "$SCENARIO" == companion-metadata-error && "$fixture_app" == invidiouscompanion ]]; then return 22; fi
 [[ "$(cat "$HOME/.$fixture_app")" != 2.0.0 ]] || return 1
 CHECK_UPDATE_RELEASE=v2.0.0
}
_gh_read_release_metadata() {
 local fixture_body
 printf 'metadata %s %s %s\n' "$2" "$3" "$4" >> "$CASE/actions"
 [[ "$3" == v2.0.0 && "$4" == selected ]] || return 97
 [[ "$SCENARIO" != main-selected-error || "$2" != iv-org/invidious ]] || return 22
 fixture_body=$(python3 - "$2" << 'RELEASE'
import json,sys
repo=sys.argv[1];assets=[]
if repo.endswith('invidious-companion'):assets=[{'name':'invidious_companion-x86_64-unknown-linux-gnu.tar.gz','browser_download_url':'https://github.com/'+repo+'/releases/download/v2.0.0/invidious_companion-x86_64-unknown-linux-gnu.tar.gz'}]
print(json.dumps({'tag_name':'v2.0.0','draft':False,'prerelease':False,'assets':assets}))
RELEASE
)
 printf -v "$1" '%s' "$fixture_body"
}
curl_download() {
 printf 'download %s\n' "$2" >> "$CASE/actions"
 if [[ "$2" == */archive/refs/tags/* ]]; then cp "$CASE/main.tar.gz" "$1"; else
  cp "$CASE/companion.tar.gz" "$1" || return $?
  if [[ "$SCENARIO" == both-download-error-retry && ! -f "$CASE/fault-delivered" ]]; then printf 'delivered\n' > "$CASE/fault-delivered"; return 37; fi
 fi
}
make() { printf 'build\n' >> "$CASE/actions"; }
systemctl() {
 printf 'service %s\n' "$*" >> "$CASE/actions"
 python3 - "$@" << 'STATE'
import json,os,pathlib,sys
p=pathlib.Path(os.environ['CASE'])/'states.json';states=json.loads(p.read_text());a=sys.argv[1:]
if a[0]=='is-active':raise SystemExit(0 if states[a[-1]] else 3)
for unit in a[1:]:states[unit]=a[0]=='start'
p.write_text(json.dumps(states))
STATE
}
set -euo pipefail
if update_script; then exit 0; else exit $?; fi
'''
 launcher='import json,pathlib,subprocess\n'
 for leaf,dest in [('opt','/opt'),('lib','/var/lib'),('etc','/etc'),('tmp','/tmp')]:launcher+='subprocess.run(["mount","--bind",'+repr(str(case/leaf))+','+repr(dest)+'],check=True)\n'
 env=dict(os.environ,CASE=str(case),SCENARIO=scenario,HOME=str(case/'home'),TMPDIR=str(case/'tmp'))
 launcher+='run=subprocess.run(["bash","-c",'+repr(body)+'],env='+repr(env)+');pathlib.Path('+repr(str(case/'first-status'))+').write_text(str(run.returncode))\n'
 if scenario=='both-download-error-retry':launcher+='run=subprocess.run(["bash","-c",'+repr(body)+'],env='+repr(env)+')\n'
 launcher+='raise SystemExit(run.returncode)\n'
 r=subprocess.run(['unshare','--mount','--propagation','private','python3','-c',launcher],capture_output=True,text=True,timeout=120)
 expected=22 if scenario in {'main-selected-error','companion-metadata-error'} else 0;checks=[]
 def check(label,want,actual):checks.append({'name':label,'expected':want,'actual':actual,'passed':want==actual})
 check('actual caller status',expected,r.returncode)
 check('administrator configuration preserved',['administrator secret config\n',0o600],[(case/'opt/invidious/config/config.yml').read_text(),(case/'opt/invidious/config/config.yml').stat().st_mode&0o777])
 if expected==0:
  check('both actual modeled services available',{'invidious':True,'invidious-companion':True},json.loads((case/'states.json').read_text()))
  check('actual companion bytes/real marker',['new companion\n','2.0.0\n'],[(case/'opt/invidious-companion/invidious_companion').read_text(),(case/'home/.invidiouscompanion').read_text()])
 if scenario=='both-download-error-retry':check('original actual download failure preserved','250',(case/'first-status').read_text())
 if scenario=='ordinary-companion-only':check('ordinary companion-only never stops main',False,'service stop invidious-companion invidious' in (case/'actions').read_text())
 row={'case':scenario,'status':'PASS' if all(c['passed'] for c in checks) else 'FAIL','checks':checks,'stdout':r.stdout,'stderr':r.stderr,'actions':(case/'actions').read_text()};rows.append(row);print(row['status']+' '+scenario,flush=True)
document={'status':'PASS' if all(r['status']=='PASS' for r in rows) else 'FAIL','cases':rows,'scope':'actual update hook and source/backup/companion owners; modeled transport/build/service, no live Invidious claim'}
(root/'results.json').write_text(json.dumps(document,indent=2)+'\n');print('EVIDENCE',root/'results.json');raise SystemExit(0 if document['status']=='PASS' else 2)
PY
