#!/usr/bin/env bash
set -euo pipefail
systemd-detect-virt --vm -q || exit 77
exec python3 - "$(dirname "${BASH_SOURCE[0]}")/.." << 'PY'
import json,os,pathlib,shlex,subprocess,tarfile,time
assert os.geteuid()==0
assert pathlib.Path('/sys/class/dmi/id/product_uuid').read_text().strip().lower()=='4be13420-4459-4200-a1c2-7ac7232ac650'
source=pathlib.Path(os.sys.argv[1]).resolve();root=pathlib.Path('/srv/scripts-underground-tests/evidence')/('selected-source-'+str(time.time_ns()));root.mkdir(mode=0o700);rows=[]
for scenario in ['complete','metadata-error','metadata-prefix-error','mismatched-tag','extract-error','copy-error','literal-latest']:
 case=root/scenario;case.mkdir(mode=0o700)
 for leaf in ['opt','home','tmp','incoming']:(case/leaf).mkdir(mode=0o700)
 target=case/'opt/selected';target.mkdir();(target/'payload').write_text('old source\n');(target/'user-config').write_text('administrator data\n');(target/'user-config').chmod(0o600)
 marker=case/'home/.selected';marker.write_text('1.0.0\n');(case/'incoming/payload').write_text('new selected source\n')
 tag='latest' if scenario=='literal-latest' else 'v2.0.0'
 (case/'release.json').write_text(json.dumps({'tag_name':'v3.0.0' if scenario=='mismatched-tag' else tag,'draft':False,'prerelease':False,'assets':[]}))
 with tarfile.open(case/'source.tar.gz','w:gz') as archive:archive.add(case/'incoming',arcname='source')
 if scenario=='extract-error':(case/'source.tar.gz').write_text('bad archive\n')
 (case/'actions').write_text('')
 body='source '+shlex.quote(str(source/'misc/tools.func'))+'\n'+r'''
STD=''
msg_warn() { printf 'WARN %s\n' "$*" >&2; }
msg_error() { printf 'ERROR %s\n' "$*" >&2; }
ensure_dependencies() { :; }
curl() {
 local output='' last='' previous=''
 for last in "$@"; do [[ "$previous" != -o ]] || output=$last; previous=$last; done
 printf 'metadata %s\n' "$last" >> "$CASE/actions"
 [[ "$last" == "https://api.github.com/repos/fixture/source/releases/tags/$TAG" ]] || return 97
 cp "$CASE/release.json" "$output"
 if [[ "$SCENARIO" == metadata-error ]]; then printf 503; return 22; fi
 printf 200
 [[ "$SCENARIO" != metadata-prefix-error ]] || return 37
}
curl_download() {
 printf 'archive %s\n' "$2" >> "$CASE/actions"
 [[ "$2" == "https://github.com/fixture/source/archive/refs/tags/$TAG.tar.gz" ]] || return 97
 cp "$CASE/source.tar.gz" "$1"
}
cp() {
 if [[ "$SCENARIO" == copy-error && "${*: -1}" == /opt/selected/ ]]; then
  printf 'copy-fault\n' >> "$CASE/actions"; return 37
 fi
 command cp "$@"
}
if CLEAN_INSTALL=0 _gh_deploy_selected_source selected fixture/source "$TAG" /opt/selected; then exit 0; else exit $?; fi
'''
 env=dict(os.environ,CASE=str(case),SCENARIO=scenario,TAG=tag,HOME=str(case/'home'),TMPDIR=str(case/'tmp'))
 launcher='import subprocess\n'
 for leaf,dest in [('opt','/opt'),('tmp','/tmp')]:launcher+='subprocess.run(["mount","--bind",'+repr(str(case/leaf))+','+repr(dest)+'],check=True)\n'
 launcher+='raise SystemExit(subprocess.run(["bash","-c",'+repr(body)+'],env='+repr(env)+').returncode)\n'
 r=subprocess.run(['unshare','--mount','--propagation','private','python3','-c',launcher],capture_output=True,text=True,timeout=60)
 expected={'complete':0,'literal-latest':0,'metadata-error':22,'metadata-prefix-error':22,'mismatched-tag':250,'extract-error':251,'copy-error':251}[scenario];checks=[]
 def check(label,want,actual):checks.append({'name':label,'expected':want,'actual':actual,'passed':want==actual})
 check('actual selected-only status',expected,r.returncode)
 check('real marker follows checked source publication',('latest\n' if scenario=='literal-latest' else '2.0.0\n') if expected==0 else '1.0.0\n',marker.read_text())
 check('actual payload outcome','new selected source\n' if expected==0 else 'old source\n',(target/'payload').read_text())
 check('unrelated administrator configuration preserved',['administrator data\n',0o600],[(target/'user-config').read_text(),(target/'user-config').stat().st_mode&0o777])
 if scenario=='copy-error':check('actual publisher fault delivered',True,'copy-fault' in (case/'actions').read_text())
 row={'case':scenario,'status':'PASS' if all(c['passed'] for c in checks) else 'FAIL','checks':checks,'stdout':r.stdout,'stderr':r.stderr,'actions':(case/'actions').read_text()};rows.append(row);print(row['status']+' '+scenario,flush=True)
document={'status':'PASS' if all(r['status']=='PASS' for r in rows) else 'FAIL','cases':rows,'scope':'actual selected metadata/ordinary source publication, native tar/copy and final consumer readback; modeled transport'}
(root/'results.json').write_text(json.dumps(document,indent=2)+'\n');print('EVIDENCE',root/'results.json');raise SystemExit(0 if document['status']=='PASS' else 2)
PY
