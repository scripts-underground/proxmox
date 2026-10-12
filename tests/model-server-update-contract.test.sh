#!/usr/bin/env bash
# Native transaction and hook contracts with explicitly modeled service transport.
set -euo pipefail
systemd-detect-virt --vm -q || exit 77
exec python3 - "$(dirname "${BASH_SOURCE[0]}")/.." "${1:?application}" << 'PY'
import hashlib
import json
import os
import pathlib
import re
import shutil
import subprocess
import tarfile
import time

assert os.geteuid()==0
assert pathlib.Path('/sys/class/dmi/id/product_uuid').read_text().strip().lower()=='4be13420-4459-4200-a1c2-7ac7232ac650'
source=pathlib.Path(os.sys.argv[1]).resolve(); app=os.sys.argv[2]
assert app in ('ollama','llama-cpp')
root=pathlib.Path('/srv/scripts-underground-tests/evidence')/(app+'-update-'+str(time.time_ns()))
root.mkdir(mode=0o700)
script=(source/('scripts/lxc/'+app+'.sh')).read_text()
hook=re.search(r'^function update_script\(\) \{\n.*?^\}',script,re.M|re.S)
assert hook
rows=[]
cases=['current-running','selected-success','prepare-error','publication-error','restart-error-retry','metadata-error']
if app=='ollama': cases+=['legacy-nested-success','vendor-prefix-success','custom-layout-refusal']
for scenario in cases:
    case=root/scenario; case.mkdir(mode=0o700)
    for leaf in ['opt','etc','lib','home','tmp','data','incoming','local']:
        (case/leaf).mkdir(mode=0o700)
    (case/'lib/dpkg').mkdir(); shutil.copy2('/var/lib/dpkg/status',case/'lib/dpkg/status')
    prefix='/opt/'+app
    if scenario=='legacy-nested-success': prefix='/usr/local/lib/ollama'
    elif scenario=='vendor-prefix-success': prefix='/usr/local'
    elif scenario=='custom-layout-refusal': prefix='/opt/custom-ollama'
    target=case/'local'/prefix.removeprefix('/usr/local/') if prefix.startswith('/usr/local/') else case/'local' if prefix=='/usr/local' else case/'opt'/prefix.removeprefix('/opt/')
    target.mkdir(parents=True,exist_ok=True)
    binary='bin/ollama' if app=='ollama' else 'llama-server'
    (target/binary).parent.mkdir(parents=True,exist_ok=True)
    old=b'\x7fELFretained installed binary\n'; new=b'\x7fELFcomplete selected binary\n'
    (target/binary).write_bytes(old); (target/binary).chmod(0o755)
    (target/'administrator-file').write_text('unrelated administrator bytes\n')
    (target/'administrator-file').chmod(0o600)
    (case/'incoming'/binary).parent.mkdir(parents=True,exist_ok=True)
    (case/'incoming'/binary).write_bytes(new); (case/'incoming'/binary).chmod(0o755)
    marker=case/'home'/('.ollama-com' if app=='ollama' else '.llama-cpp')
    marker.write_text('2.0.0\n' if scenario=='current-running' else '1.0.0\n')
    (case/'data/llama-cpp').mkdir(); (case/'data/llama-cpp/.backend').write_text('cpu\n')
    for name in ['model-mount-sentinel','service-account-key','administrator-preset']:
        (case/'data'/name).write_text(name+' preserved bytes\n'); (case/'data'/name).chmod(0o600)
    (case/'etc'/('service-config')).write_text('User=custom-admin\nHOME=/data\nOLLAMA_HOST=127.0.0.1:11434\n')
    (case/'local/launcher').write_text('administrator launcher\n')
    (case/'service-active').write_text('active\n'); (case/'actions').write_text('')
    asset_name='ollama-linux-amd64.tar.zst' if app=='ollama' else 'llama-b42-bin-ubuntu-x64.tar.gz'
    # tar supports content-based detection; the Ollama fixture uses an actual zstd archive.
    with tarfile.open(case/'uncompressed.tar','w') as archive:
        if app=='ollama':
            archive.add(case/'incoming/bin',arcname='bin')
        else:
            archive.add(case/'incoming',arcname='bundle')
    subprocess.run(['zstd','-q',str(case/'uncompressed.tar'),'-o',str(case/asset_name)],check=True) if app=='ollama' else subprocess.run(['gzip','-c',str(case/'uncompressed.tar')],stdout=(case/asset_name).open('wb'),check=True)
    repo='ollama/ollama' if app=='ollama' else 'ggml-org/llama.cpp'
    release_tag='v2.0.0' if app=='ollama' else 'b42'
    digest=hashlib.sha256((case/asset_name).read_bytes()).hexdigest()
    release={'tag_name':release_tag,'draft':False,'prerelease':app=='llama-cpp','assets':[{'name':asset_name,'browser_download_url':'https://github.com/'+repo+'/releases/download/'+release_tag+'/'+asset_name,'digest':'sha256:'+digest}]}
    stable={'tag_name':'v2.0.0','draft':False,'prerelease':False,'assets':[{'name':'nightly-tag.txt','browser_download_url':'https://github.com/ggml-org/llama.cpp/releases/download/v2.0.0/nightly-tag.txt'}]}
    (case/'release.json').write_text(json.dumps(release)); (case/'stable.json').write_text(json.dumps(stable)); (case/'nightly-tag.txt').write_text('b42\n')
    code='source '+__import__('shlex').quote(str(source/'misc/tools.func'))+'\n'+hook.group(0)+r'''
STD=''
APP='Update Fixture'
var_lxc_release=v2.0.0
header_info() { :; }
check_container_storage() { :; }
check_container_resources() { :; }
msg_info() { :; }
msg_ok() { :; }
msg_debug() { :; }
msg_warn() { printf 'WARN %s\n' "$*" >&2; }
msg_error() { printf 'ERROR %s\n' "$*" >&2; }
get_system_arch() { printf amd64; }
check_for_gh_release() {
  printf 'check\n' >> "$CASE/actions"
  [[ "$SCENARIO" != metadata-error ]] || return 22
  if [[ "$(cat -- "$HOME/.$1")" == 2.0.0 ]]; then return 1; fi
  CHECK_UPDATE_RELEASE=v2.0.0
}
_gh_read_release_metadata() {
  local fixture_json
  fixture_json=$(cat -- "$CASE/release.json") || return $?
  [[ "$3" != v2.0.0 || "$2" != ggml-org/llama.cpp ]] || fixture_json=$(cat -- "$CASE/stable.json")
  printf -v "$1" '%s' "$fixture_json"
}
curl_download() {
  printf 'download %s\n' "$2" >> "$CASE/actions"
  [[ "$SCENARIO" != prepare-error ]] || return 22
  cp -- "$CASE/${2##*/}" "$1"
}
mv() {
  if [[ "$SCENARIO" == publication-error && "${*: -1}" == "$BINARY_PATH" && "${*: -2:1}" == */publish ]]; then
    printf 'publication-fault\n' >> "$CASE/actions"; return 17
  fi
  command mv "$@"
}
systemctl() {
  printf 'service %s\n' "$*" >> "$CASE/actions"
  case "$1" in
    show) printf '{ path=%s ; argv[]=%s serve ; }\n' "$BINARY_PATH" "$BINARY_PATH" ;;
    stop) rm -f -- "$CASE/service-active" ;;
    start)
      if [[ "$SCENARIO" == restart-error-retry && ! -f "$CASE/start-fault-delivered" ]]; then
        printf 'delivered\n' > "$CASE/start-fault-delivered"; return 17
      fi
      printf 'active\n' > "$CASE/service-active" ;;
    is-active) [[ -f "$CASE/service-active" ]] ;;
    *) return 88 ;;
  esac
}
set -euo pipefail
update_script
'''
    env=dict(os.environ,CASE=str(case),SCENARIO=scenario,HOME=str(case/'home'),TMPDIR=str(case/'tmp'),BINARY_PATH=prefix+'/'+binary)
    launcher='import subprocess\n'
    for name,dest in [('opt','/opt'),('etc','/etc'),('lib','/var/lib'),('local','/usr/local'),('data','/var/lib/llama-cpp')]:
        if name=='data': continue
        launcher+='subprocess.run(["mount","--bind",'+repr(str(case/name))+','+repr(dest)+'],check=True)\n'
    # Retain the native dpkg database for actual ensure_dependencies, and redirect
    # only the persistent llama metadata path in this private mount namespace.
    (case/'lib/llama-cpp').mkdir(); shutil.copy2(case/'data/llama-cpp/.backend',case/'lib/llama-cpp/.backend')
    # /etc needs real alternatives for Debian's /bin tools.
    shutil.copytree('/etc/alternatives',case/'etc/alternatives',symlinks=True)
    launcher+='raise SystemExit(subprocess.run(["bash","-c",'+repr(code)+'],env='+repr(env)+').returncode)\n'
    run=subprocess.run(['unshare','--mount','--propagation','private','python3','-c',launcher],capture_output=True,text=True,timeout=120)
    checks=[]
    def check(label,expected,actual): checks.append({'name':label,'expected':expected,'actual':actual,'passed':expected==actual})
    expected={'prepare-error':250,'publication-error':252,'restart-error-retry':17,'metadata-error':22,'custom-layout-refusal':250}.get(scenario,0)
    check('original checked producer status',expected,run.returncode)
    if scenario=='restart-error-retry':
        retry=subprocess.run(['unshare','--mount','--propagation','private','python3','-c',launcher],capture_output=True,text=True,timeout=120)
        check('current-marker retry status',0,retry.returncode)
    check('service available after failure/current retry',True,(case/'service-active').exists())
    published=scenario in {'selected-success','restart-error-retry','legacy-nested-success','vendor-prefix-success'}
    check('real marker follows publication','2.0.0\n' if published or scenario=='current-running' else '1.0.0\n',marker.read_text())
    check('actual executable bytes',new.hex() if published else old.hex(),(target/binary).read_bytes().hex())
    if scenario in {'legacy-nested-success','vendor-prefix-success','custom-layout-refusal'}:
        check('shared legacy prefix never cleaned',["unrelated administrator bytes\n",0o600],[(target/'administrator-file').read_text(),(target/'administrator-file').stat().st_mode&0o777])
    if scenario=='custom-layout-refusal':
        check('ambiguous layout refuses before stop/download',False,'service stop' in (case/'actions').read_text() or 'download ' in (case/'actions').read_text())
    for name in ['model-mount-sentinel','service-account-key','administrator-preset']:
        check('preserved '+name,[name+' preserved bytes\n',0o600],[(case/'data'/name).read_text(),(case/'data'/name).stat().st_mode&0o777])
    check('administrator service config preserved','User=custom-admin\nHOME=/data\nOLLAMA_HOST=127.0.0.1:11434\n',(case/'etc/service-config').read_text())
    check('administrator launcher preserved','administrator launcher\n',(case/'local/launcher').read_text())
    if scenario=='publication-error': check('native publication fault delivered',True,'publication-fault' in (case/'actions').read_text())
    row={'case':scenario,'status':'PASS' if all(c['passed'] for c in checks) else 'FAIL','checks':checks,'stdout':run.stdout,'stderr':run.stderr,'actions':(case/'actions').read_text()}
    (case/'result.json').write_text(json.dumps(row,indent=2)+'\n'); rows.append(row)
    print(row['status']+' '+scenario,flush=True)
document={'status':'PASS' if all(row['status']=='PASS' for row in rows) else 'FAIL','application':app,'cases':rows,
          'scope':'actual update hooks and coherent archive transaction with synthetic ordinary binaries; modeled metadata/service transport, no inference claim'}
(root/'results.json').write_text(json.dumps(document,indent=2)+'\n'); print('EVIDENCE',root/'results.json')
raise SystemExit(0 if document['status']=='PASS' else 2)
PY
