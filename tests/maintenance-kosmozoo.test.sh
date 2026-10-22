#!/usr/bin/env bash
# Native files/processes/bundles; apt, GitHub and systemd lifecycle are explicitly
# MODELED in isolated root/mount/PID fixtures. Standalone ELF is separately real.
set -euo pipefail

if [[ "${1:-}" == --fixture-child ]]; then
  [[ -f /fixture/owned ]] || exit 65
  cd /fixture
  source /fixture/scenario.sh
  exit
fi

[[ ("${1:-}" == --native || "${1:-}" == --lxc) && "${2:-}" == --guard-manifest && $# -ge 3 ]] || {
  printf 'Usage: %s --native --guard-manifest <external-json> [--hooks-only] | --lxc --guard-manifest <external-json> --ctid <id> [--stage <checkpoint-stage>]\n' "$0" >&2
  exit 65
}
mode=$1 hooks_only=0 ctid='' stage_name=''
if [[ "$mode" == --native ]]; then
  [[ $# == 3 || ($# == 4 && "$4" == --hooks-only) ]] || exit 65
  [[ $# == 3 ]] || hooks_only=1
else
  [[ ($# == 5 || $# == 7) && "$4" == --ctid && "$5" =~ ^[1-9][0-9]{3,5}$ ]] || exit 65
  ctid=$5 stage_name=all
  if [[ $# == 7 ]]; then
    [[ "$6" == --stage ]] || exit 65
    case "$7" in bootstrap | browser-smoke | browser-first | browser-resume | lifecycle | configuration | failures | final-consumer) ;; *) exit 65 ;; esac
    stage_name=$7
  fi
fi
systemd-detect-virt --vm --quiet || exit 65
[[ "$EUID" == 0 ]] || exit 65
: "${TMPDIR:?disk-backed TMPDIR required}"
case "$(realpath -e "$TMPDIR")" in /tmp | /tmp/*) exit 65 ;; esac
case "$(findmnt -rn -T "$TMPDIR" -o FSTYPE)" in '' | tmpfs | ramfs) exit 65 ;; esac
ROOT=$(realpath "$(dirname "${BASH_SOURCE[0]}")/..")
guard=$(realpath -e "$3")
jq -e 'type == "object" and .version == 1 and (.source.base | test("^[0-9a-f]{40}$")) and
  (.guest.uuid | type == "string") and (.guest.serial | type == "string") and
  (.guest.mac | type == "string") and (.guest.machine_id | type == "string") and
  (.workspace.path | type == "string") and (.workspace.filesystem_uuid | type == "string") and
  (.source.files | type == "array" and length >= 5) and
  .release.sha256 == "2a1470029a9b50a492a9c59885f0746ca8c95e3c386fe9c72414793aa139a804"' "$guard" > /dev/null || exit 65
[[ "$(tr A-Z a-z < /sys/class/dmi/id/product_uuid)" == "$(jq -r .guest.uuid "$guard")" ]] || exit 65
[[ "$(lsblk -dn -o SERIAL /dev/vda | xargs)" == "$(jq -r .guest.serial "$guard")" ]] || exit 65
[[ "$(cat /sys/class/net/enp1s0/address)" == "$(jq -r .guest.mac "$guard")" ]] || exit 65
[[ "$(cat /etc/machine-id)" == "$(jq -r .guest.machine_id "$guard")" ]] || exit 65
W=$(jq -er .workspace.path "$guard")
[[ "$(realpath -e "$W")" == "$W" && "$ROOT" == "$W/repo" && "$TMPDIR" == "$W/tmp" ]] || exit 65
[[ "$(findmnt -rn -T "$W" -o UUID)" == "$(jq -r .workspace.filesystem_uuid "$guard")" ]] || exit 65
[[ "$(git -C "$ROOT" rev-parse HEAD)" == "$(jq -r '.source.head // .source.base' "$guard")" ]] || exit 65
git -C "$ROOT" merge-base --is-ancestor "$(jq -r .source.base "$guard")" HEAD || exit 65
[[ "$(git -C "$ROOT" write-tree)" == "$(jq -r .source.tree "$guard")" ]] || exit 65
git -C "$ROOT" diff --quiet || exit 65
[[ -z "$(git -C "$ROOT" ls-files --others --exclude-standard)" ]] || exit 65
jq -e '(.source.files | map(.path) | length == (unique | length)) and
  ([.source.files[].path] | contains(["scripts/lxc/kosmozoo.sh", "_lxc/kosmozoo.md", "tests/maintenance-kosmozoo.test.sh", "tests/maintenance-kosmozoo.browser.mjs", "tests/README.md"]))' "$guard" > /dev/null || exit 65
while IFS= read -r relative; do
  [[ "$relative" != /* && "$relative" != *..* && "$relative" != *$'\n'* && -f "$ROOT/$relative" && ! -L "$ROOT/$relative" ]] || exit 65
  expected=$(jq -er --arg path "$relative" '.source.files | map(select(.path == $path)) | select(length == 1) | .[0].sha256' "$guard") || exit 65
  [[ "$(sha256sum "$ROOT/$relative" | cut -d ' ' -f1)" == "$expected" ]] || exit 65
  [[ "$(git -C "$ROOT" ls-files -s "$relative" | cut -d ' ' -f1)" == "$(jq -er --arg path "$relative" '.source.files[] | select(.path == $path) | .mode' "$guard")" ]] || exit 65
done < <(jq -r '.source.files[].path' "$guard")
elf=$(jq -er .release.path "$guard")
[[ "$elf" == "$W/tools/kosmozoo-v0.2.2" && -f "$elf" && ! -L "$elf" ]] || exit 65
printf '%s  %s\n' "$(jq -r .release.sha256 "$guard")" "$elf" | sha256sum --check --strict
[[ "$(df -B1 --output=avail "$W" | tr -dc '0-9')" -ge 4294967296 ]] || exit 65

# Every literal Python heredoc in these new shell bodies is compiled, including
# this guard itself. New unsupported invocation/delimiter forms fail closed.
python3 - "$ROOT/scripts/lxc/kosmozoo.sh" "$0" << 'PY'
import pathlib,re,sys
count=0
for path in sys.argv[1:]:
    lines=pathlib.Path(path).read_text().splitlines(keepends=True)
    i=0
    while i<len(lines):
        line=lines[i]
        if re.search(r'\bpython(?:3)?\s',line) and not line.lstrip().startswith('#'):
            match=re.fullmatch(r"[ \t]*python3 - .* << '([A-Z][A-Z0-9_]*)'\n",line)
            if not match: raise SystemExit(f'Unknown Python heredoc form: {path}:{i+1}')
            start=i+1; i=start
            while i<len(lines) and lines[i].rstrip('\n')!=match[1]: i+=1
            if i==len(lines): raise SystemExit('Unterminated Python heredoc')
            compile(''.join(lines[start:i]),f'{path}:{start+1}','exec');count+=1
        i+=1
print(f'Python literal syntax guard: {count} compiled bodies; unknown forms rejected')
PY

# Kosmozoo-specific checkpoint data. This never executes a manifest command or
# discovers an unknown live state: prior inputs must be independently hash-bound;
# new records are made only from stages this invocation just ran successfully.
all_metadata() {
  python3 - "$ROOT" "$W" "$guard" "$ctid" "$@" << 'ALLDATA'
import pathlib,json,hashlib,sys,subprocess,sqlite3,tarfile,re
root,w,gpath,cid,action,*args=sys.argv[1:];root=pathlib.Path(root);w=pathlib.Path(w);g=json.loads(pathlib.Path(gpath).read_text());cid=int(cid)
def need(ok,why):
 if not ok: raise ValueError(why)
def sha(data):return hashlib.sha256(data).hexdigest()
def owned(path):
 p=pathlib.Path(path);need(p.is_file() and not p.is_symlink() and str(p.resolve())==str(p),'unsafe evidence path')
 need(p.is_relative_to(w/'artifacts') and p.stat().st_uid==0 and not p.stat().st_mode&0o022,'unowned evidence')
 return p
def bound(item):
 need(isinstance(item,dict) and re.fullmatch('[0-9a-f]{64}',item.get('sha256','')),'missing hash-bound input')
 p=owned(item['path']);data=p.read_bytes();need(sha(data)==item['sha256'],'input digest mismatch: '+str(p));return data
def cpfile(cp,name):
 need(name in cp.get('files',{}) and not name.startswith('/') and '..' not in pathlib.PurePosixPath(name).parts,'partial/unbound '+name)
 return bound({'path':str(pathlib.Path(cp['evidence'])/name),'sha256':cp['files'][name]})
def js(cp,name):return json.loads(cpfile(cp,name))
def runtime(r,version,port=80):need(r.get('protocol')=='kosmozoo-runtime' and r.get('version')==1 and r.get('mode')=='serve' and r.get('status')=='ready' and r.get('binding',{}).get('port')==port and r.get('app',{}).get('version')==version,'runtime semantic mismatch')
critical=['scripts/lxc/kosmozoo.sh','misc/bootstrap/lxc','misc/build.func','misc/core.func','misc/error_handler.func','misc/tools.func','misc/install.func','misc/github.func','misc/bundle.func']
index={line.split('\t',1)[1]:line.split('\t',1)[0].split()[:2] for line in subprocess.check_output(['git','-C',str(root),'ls-files','-s'],text=True).splitlines()}
need(len({c['id'] for c in g['native']['containers']})==len(g['native']['containers']) and len({c['ip'] for c in g['native']['containers']})==len(g['native']['containers']),'duplicate CT identity')
ct=next((c for c in g['native']['containers'] if c['id']==cid),None);need(ct is not None and cid in (2120,2121,2122),'undeclared CT')
a=ct.get('acceptance',{});phase=a.get('phase');failure=ct.get('role')=='failure'
image_hash=next(x['sha256'] for x in g['native']['fixtures']['files'] if x['path']=='tests/fixtures/flux-basic.png')
def provenance(cp,kind,owner=None):
 owner=owner or ct;ownerid=owner['id']
 need(cp.get('kind')==kind and re.fullmatch('[0-9a-f]{40}',cp.get('source_tree','')),'unclassified checkpoint')
 ev=pathlib.Path(cp['evidence']);need(ev.is_relative_to(w/'artifacts') and str(ev.resolve())==str(ev) and ev.name.startswith(f'lxc-{ownerid}-'),'wrong evidence owner')
 for name in cp['files']:cpfile(cp,name)
 old=js(cp,'issued-guard.json');need(old['source']['tree']==cp['source_tree'] and old['guest']==g['guest'] and old['workspace']==g['workspace'],'checkpoint source/VM mismatch')
 oldindex={line.split('\t',1)[1]:line.split('\t',1)[0].split()[:2] for line in cpfile(cp,'source-index.txt').decode().splitlines()}
 need(all(oldindex.get(p)==index.get(p) for p in critical),'installer/framework changed since native proof')
 prior=next((c for c in old['native']['containers'] if c['id']==ownerid),None);need(prior is not None,'checkpoint missing CT owner')
 need(all(prior[k]==owner[k] for k in ('id','ip','mac','hostname','state','cache','hosts')),'checkpoint CT/config mismatch')
def bootstrap(cp):
 provenance(cp,'bootstrap');need(cpfile(cp,'terminal.txt').decode().startswith('status=0;'),'bootstrap not completed')
 lv=js(cp,'actual-lv.json')['report'][0]['lv'][0];need(lv['lv_uuid']==ct['ownership']['lv_uuid'] and int(lv['lv_size'])==4294967296,'bootstrap volume mismatch')
 config=cpfile(cp,'actual-config.txt').decode().lower();need(all(x in config for x in ('cores: 2\n','memory: 1024\n','unprivileged: 1\n',f'hostname: {ct["hostname"]}\n',f'hwaddr={ct["mac"]}',f'ip={ct["ip"]}/24','bridge=vmbrkz24','size=4g')),'bootstrap actual defaults/identity mismatch')
 runtime(js(cp,'runtime.json'),cp['version']);text=cpfile(cp,'native-inspection.txt').decode()
 need(cp['binary_sha256']+'  /opt/kosmozoo/kosmozoo' in text and 'kosmozoo v'+cp['version']+' ' in text,'initial published ELF proof absent')
def baseline():
 b=json.loads(bound(a['baseline']));need(set(b['rows'])=={'local','remote'} and b['settings'].get('downvoteHides') is False,'partial consumer baseline')
 for source,row in b['rows'].items():
  j=row['judgment'];need(row['hash']==image_hash and j.get('vote')=='up' and j.get('bookmark') is True and not j.get('favorite') and j.get('notes',{}).get('pos')==f'native-{cid}-{source}-browser-blur','unknown consumer expectations')
 need(b['sources']['remote']['address']=='10.248.26.1:8188' and b['sources']['remote']['pinned'] is True and b['sources']['remote']['autoRefresh'] is True and b['sources']['local']['address']=='folder:/sources/images','source baseline incomplete');return b
def browser(cp,name,phase,version):
 r=js(cp,'browser/'+name);need(r.get('ctid')==cid and r.get('phase')==phase and r.get('status')=='passed' and r.get('origin')=='http://kosmozoo.home' and r['source']['tree']==cp['source_tree'] and not r['exceptions'] and not r['failedRequests'],'browser evidence mismatch')
 runtime(r['runtime'],version)
 need(all(n['status']<400 or (n['status']==404 and n['url']=='http://kosmozoo.home/api/collections/remote/entries/missing-404.png/bytes') for n in r['network']),'unexpected browser HTTP error')
 return r
def observed_resources(cp,last):
 rows=[r.split() for r in cpfile(cp,'resource-timeline.txt').decode().splitlines()[1:]]
 need(len(rows)>1 and all(len(r)==7 and all(x.isdigit() for x in r) for r in rows),'partial resource timeline')
 nums=[list(map(int,r)) for r in rows];need(max(r[2] for r in nums)<1073741824 and max(r[4] for r in nums)==0,'representative memory/swap outcome changed')
 need(cpfile(cp,'effective-ct-cgroup.txt').decode().strip()==f'/sys/fs/cgroup/lxc/{cid}' and 'memory.max=1073741824' in cpfile(cp,last).decode(),'missing actual finite CT ancestor')
def lifecycle(cp):
 provenance(cp,'lifecycle');r=js(cp,'lifecycle-accepted.json');need(r['status']=='lifecycle-passed' and r['source_tree']==cp['source_tree'] and r['version']==a['version'] and r['binary_sha256']==a['binary_sha256'] and r['baseline']==a['baseline'] and r['profile']==ct['browser_profile'],'lifecycle receipt semantics')
 b=baseline();initial=js(cp,'runtime.json')['app']['version'];runtime(js(cp,'runtime.json'),initial);runtime(js(cp,'restarted-runtime.json'),initial);runtime(js(cp,'updated-runtime.json'),a['version'])
 release=js(cp,'current-release.json');asset=next(x for x in release['assets'] if x['name']=='kosmozoo-linux-x86_64');need(release['draft'] is False and release['prerelease'] is False and release['tag_name'].lstrip('v')==a['version'] and asset['digest']=='sha256:'+a['binary_sha256'],'actual published target mismatch')
 prior=next(c for c in js(cp,'issued-guard.json')['native']['containers'] if c['id']==cid)
 first='first-run' if prior['acceptance']['phase']=='installed' else 'verify'
 for name,v in ((first,initial),('after-restart',initial),('after-update',a['version'])):
  obs=browser(cp,f'{cid}-{name}.json','first-run' if name=='first-run' else 'verify',v);need(len(obs.get('media',[]))==2,'missing real image consumers')
  for m in obs['media']:need(m['digest']==b['rows'][m['source']]['hash'] and m['width']==1024 and m['height']==1024 and (name=='first-run' or m['entry']['judgment']==b['rows'][m['source']]['judgment']),'wrong rendered baseline')
 for name,v in (('running-before',initial),('running-after-restart',initial),('running-after-update',a['version'])):
  need(browser(cp,f'{cid}-{name}.json','activity',v)['activity']['state']=='running','remote job not observed')
 queue=js(cp,'upstream-queue-before.json');need(len(queue['queue_running'])==1 and len(queue['queue_pending'])==1,'no independent upstream job')
 owner=cpfile(cp,'provider-owner.txt').decode().strip();continuity=cpfile(cp,'provider-continuity.txt').decode().splitlines();need(len(continuity)>=5 and all(line.split(' pid=',1)[1]==' '.join(owner.split()[0:]) .removeprefix('pid=') for line in continuity),'provider process restarted')
 out=browser(cp,f'{cid}-final-output.json','output',a['version'])['media'][-1];job=js(cp,'job-finish-input.json')['finish'][0]
 need(out['name']==job['output'] and out['width']==640 and out['height']==360 and out['digest']==r['output_sha256']==sha(cpfile(cp,'provider-output.png')) and out['entry']['hash']==out['digest'] and any(n['type']=='SaveImage' and n['inputs'].get('filename_prefix')==job['graphPrefix'] for n in out['entry']['meta']['nodes']),'remote completion chain incomplete')
 need(sha(cpfile(cp,'offline-known-cache.png'))==b['rows']['remote']['hash'] and cpfile(cp,'media-before.txt')==cpfile(cp,'media-after.txt'),'cache/media preservation absent')
 if initial==a['version']:need(cpfile(cp,'update-before-identities.txt')==cpfile(cp,'update-after-identities.txt') and cpfile(cp,'restarted-runtime.json')==cpfile(cp,'updated-runtime.json'),'not a real no-op')
 else:need(initial=='0.2.1' and cpfile(cp,'operator-before.txt')==cpfile(cp,'operator-after.txt') and 'PATH=/nonexistent\n' in cpfile(cp,'cold-native-process.txt').decode(),'native upgrade/config roundtrip missing')
 observed_resources(cp,'after-output-parent-cgroups.txt')
def configuration(cp):
 provenance(cp,'configuration');r=js(cp,'configuration-accepted.json');need(r['status']=='configuration-passed' and r['version']==a['version'] and r['profile']==ct['browser_profile'] and r['baseline']==a['baseline']['path'],'configuration receipt semantics')
 baseline()
 for name in ('verify','configuration-cold'):browser(cp,f'{cid}-{name}.json','verify',a['version'])
 text=cpfile(cp,'configuration-cold-process.txt').decode();need('PATH=/nonexistent\n' in text and 'TMPDIR=/data/native-cold-configuration\n' in text and 'KOZMOZOO_HOSTS='+ct['hosts']+'\n' in text and '/deno-native-addons/' in text and ' ro,' in text,'cold runtime/HOSTS proof missing')
 if cid==2121:
  need(r['tested_port']=='18081','operator port not tested');runtime(js(cp,'nonstandard-port-runtime.json'),a['version'],18081);need(js(cp,'nonstandard-port-runtime.json')['configuredBind']==ct['ip'] and ':18081' in cpfile(cp,'nonstandard-port-ownership.txt').decode(),'nonstandard listener absent');browser(cp,f'{cid}-after-operator-port.json','verify',a['version'])
 observed_resources(cp,'after-configuration-parent-cgroups.txt')
def failures(cp):
 provenance(cp,'failures');r=js(cp,'failures-accepted.json');need(r['status']=='failures-passed' and r['version']==a['version'] and r['binary_sha256']==a['binary_sha256'] and r['actual_reboot'] is True and r['actual_updater_crash'] is True and r['app_sigkill'] is False and r['database_rollback'] is False and 'OS curl seam' in r['checksum_injection'],'failure receipt semantics')
 init=cpfile(cp,'real-ct-reboot.txt').decode().split();need(init[0].split('=')[1]!=init[1].split('=')[1],'no actual reboot')
 text=cpfile(cp,'native-after-reboot.log').decode(errors='replace')
 for s in ('reboot did not autostart','corrupt fact','actual updater crash','safe same/newer','actual linger','original-disabled retry stayed disabled'):need(s in text,'missing native control '+s)
 need(js(cp,'native-failed-state.json')['notes']['pos']=='native-candidate-write' and js(cp,'native-final-entry.json')['judgment']['notes']['pos']==a['recovery']['note'],'lost authorized candidate writes')
 runtime(js(cp,'newer-elf-old-marker-runtime.json'),a['version'])
 # Original jq -n writes a stream of pretty JSON objects, despite the .jsonl
 # evidence name. Decode that actual producer format without rewriting records.
 stream=cpfile(cp,'corruption-boundary.jsonl').decode();corrupt=[];decoder=json.JSONDecoder()
 while stream.strip():
  stream=stream.lstrip();value,end=decoder.raw_decode(stream);corrupt.append(value);stream=stream[end:]
 need(len(corrupt)>=2 and all(x['original_sha256']==a['binary_sha256'] and x['path'].startswith('/opt/kosmozoo/.stage.') and 'controlled file corruption' in x['injection'] for x in corrupt),'unclassified checksum seam')
 with tarfile.open(fileobj=__import__('io').BytesIO(cpfile(cp,'native-controls.tar'))) as archive:
  def member(name):
   m=archive.getmember('native-controls/'+name);need(m.isfile() and m.size<2000000,'unsafe control archive');return archive.extractfile(m).read()
  fact=json.loads(member('failed-attempt.json'));need(fact['release']==a['version'] and fact['digest']==a['binary_sha256'] and fact['enabled'] is True,'native attempted floor missing')
  need('0.2.1' in member('old-pin.log').decode(errors='replace') and b'Refusing downgrade' in member('old-pin.log'),'old pin not refused')
  for name in ('active-download.log','stopped-download.log'):need(b'Download failed' in member(name),'actual transport failure missing')
  need(b'Writers remain' in member('linger-update.log') and b'native-disabled-original-write' in member('final-entry.json'),'linger/disabled recovery absent')
 rows=[x.split() for x in cpfile(cp,'failure-resource-timeline-after-reboot.txt').decode().splitlines()[1:]];payload=[list(map(float,x)) for x in rows if x[1]=='1'];need(payload and max(x[3] for x in payload)<1073741824 and max(x[5] for x in payload)==0,'failure resource evidence incomplete');need('memory.max=1073741824;' in cpfile(cp,'install-parent-last.txt').decode(),'failure parent limit missing')
def install_resources(cp):
 owner=next(c for c in g['native']['containers'] if c['id']==cp['owner_ctid']);provenance(cp,'bootstrap',owner)
 lv=js(cp,'actual-lv.json')['report'][0]['lv'][0];need(lv['lv_uuid']==owner['ownership']['lv_uuid'] and int(lv['lv_size'])==4294967296,'install resource ownership mismatch')
 rows=[x.split() for x in cpfile(cp,'install-resource-timeline.txt').decode().splitlines()[1:]];need(len(rows)>10 and all(len(x)==12 for x in rows),'partial install samples')
 payload=[list(map(float,x)) for x in rows if x[1]=='1'];need(len(payload)>10 and 0<max(x[3] for x in payload)<1073741824 and max(x[5] for x in payload)==0,'install memory/swap outcome')
 last=cpfile(cp,'install-parent-last.txt').decode();need('memory.max=1073741824;' in last and 'oom_kill 0;' in last,'missing actual install ancestor/events')
def validate():
 n=g['native'];need(n['network']=={'bridge':'vmbrkz24','gateway':'10.248.26.1','subnet':'10.248.26.0/24','dns':'192.168.122.1'},'unknown private network contract')
 need(type(n['root_reserve_bytes']) is int and n['root_reserve_bytes']>=4294967296 and type(n['thin_reserve_bytes']) is int and n['thin_reserve_bytes']>=2147483648,'missing resource reserves')
 need(n['browser']['user']=='kz-browser' and type(n['browser']['uid']) is int and n['browser']['uid']>0 and type(n['browser']['gid']) is int and n['browser']['gid']>0,'missing nonroot browser identity')
 need(n['tooling']['deno_version']=='2.9.6' and n['tooling']['deno_sha256']=='bceb5b6a6239b0b010418406d8c77a508f67cf4337d94288f1c19fe71304aab0','unapproved observer/fixture tool')
 expected_paths={'tests/fake-comfy.mjs','tests/helpers/png.mjs','src/entry-path.mjs','tests/fixtures/flux-basic.png'}
 need(n['fixtures']['commit']=='2172670f267a4e6030d295ef46a6ed0ce5de3a24' and len(n['fixtures']['files'])==4 and {f['path'] for f in n['fixtures']['files']}==expected_paths and all(re.fullmatch('[0-9a-f]{64}',f['sha256']) for f in n['fixtures']['files']),'partial frozen fixture graph')
 need(re.fullmatch('[0-9a-f]{64}',n['expected_unit_sha256']),'missing managed-unit expectation')
 need(phase in ('new','installed','consumers','lifecycle','configuration','activation-failed','failures'),'unknown checkpoint phase')
 need(ct['ip']==f'10.248.26.{cid-2100}' and ct['mac']==f'02:52:26:00:21:{cid-2100:02d}','wrong declared private identity')
 need(ct['media_source']==str(w/'fixtures'/f'media-{cid}'),'unsafe media fixture')
 if failure:need(cid==2122 and ct['hostname']=='kz-failure-2122' and a.get('recovery')=={'hash':image_hash,'note':'native-disabled-original-write'},'unknown recovery expectations')
 else:need(a.get('configuration_port')==(18081 if cid==2121 else 80),'missing configuration contract')
 if phase=='new':need(a.get('allow_create') is True,'creation not authorized');return
 bootstrap(a['bootstrap'])
 if failure:
  need(a.get('recovery')=={'hash':image_hash,'note':'native-disabled-original-write'},'unknown recovery expectations')
  if phase=='failures':failures(a['failures'])
  elif phase=='activation-failed':need(re.fullmatch('[0-9a-f]{64}',a.get('failed_fact_sha256','')),'unbound failed activation')
  else:need(phase=='installed','wrong failure continuation')
 else:
  if phase!='installed':baseline()
  if phase in ('lifecycle','configuration'):lifecycle(a['lifecycle'])
  if phase=='configuration':configuration(a['configuration'])
 need(g['native'].get('install_resources') is not None,'unbound install resource evidence');install_resources(g['native']['install_resources'])
keys={
 'bootstrap':['terminal.txt','runtime.json','native-inspection.txt','actual-lv.json','actual-config.txt','issued-guard.json','source-index.txt'],
 'lifecycle':['lifecycle-accepted.json','runtime.json','restarted-runtime.json','updated-runtime.json','current-release.json','provider-owner.txt','provider-continuity.txt','upstream-queue-before.json','job-finish-input.json','provider-output.png','offline-known-cache.png','media-before.txt','media-after.txt','update-before-identities.txt','update-after-identities.txt','resource-timeline.txt','effective-ct-cgroup.txt','after-output-parent-cgroups.txt','issued-guard.json','source-index.txt'],
 'configuration':['configuration-accepted.json','configuration-cold-process.txt','resource-timeline.txt','effective-ct-cgroup.txt','after-configuration-parent-cgroups.txt','issued-guard.json','source-index.txt'],
 'failures':['failures-accepted.json','real-ct-reboot.txt','native-after-reboot.log','native-failed-state.json','native-final-entry.json','newer-elf-old-marker-runtime.json','corruption-boundary.jsonl','native-controls.tar','failure-resource-timeline-after-reboot.txt','install-parent-last.txt','issued-guard.json','source-index.txt']}
def checkpoint(kind,ev):
 ev=pathlib.Path(ev);names=list(keys[kind]);old=json.loads((ev/'issued-guard.json').read_text())
 if kind in ('lifecycle','configuration'):
  names += ['browser/'+p.name for p in sorted((ev/'browser').glob('*.json')) if '-accepted' not in p.name and '-failed-' not in p.name]
 if kind=='lifecycle' and (ev/'operator-before.txt').exists():names+=['operator-before.txt','operator-after.txt','cold-native-process.txt']
 if kind=='configuration' and cid==2121:names+=['nonstandard-port-runtime.json','nonstandard-port-ownership.txt']
 if kind=='bootstrap' and (ev/'install-resource-timeline.txt').exists():names+=['install-resource-timeline.txt','install-parent-last.txt']
 cp={'kind':kind,'evidence':str(ev),'source_tree':old['source']['tree'],'files':{name:sha(owned(ev/name).read_bytes()) for name in names}}
 if kind=='bootstrap':
  cp['version']=json.loads((ev/'runtime.json').read_text())['app']['version'];cp['binary_sha256']=next(line.split()[0] for line in (ev/'native-inspection.txt').read_text().splitlines() if re.fullmatch('[0-9a-f]{64}  /opt/kosmozoo/kosmozoo',line))
 return cp
def expected_files():
 def q(v):return '"'+v.replace('\\','\\\\').replace('"','\\"').replace('$','\\$').replace('`','\\`')+'"'
 base=''.join(k+'='+q(v)+'\n' for k,v in [('HOME','/data'),('TMPDIR','/data/tmp'),('KOZMOZOO_STATE',ct['state']),('KOZMOZOO_CACHE',ct['cache']),('KOZMOZOO_PLUGINS','/data/plugins'),('KOZMOZOO_HOSTS',ct['hosts']),('KOZMOZOO_BIND','0.0.0.0'),('KOZMOZOO_PORT','80')])
 out={'etc/kosmozoo/env':base.encode()}
 values=''.join(k+'='+q(ct[field])+'\n' for k,field in [('KOZMOZOO_STATE','state'),('KOZMOZOO_CACHE','cache'),('KOZMOZOO_HOSTS','hosts')])
 literal='KZ_ACCEPTANCE_LITERAL="operator \\$ \\` % \\" \\\\ roundtrip"\n'
 if not failure:
  out['etc/systemd/system/kosmozoo.service.d/native-configuration.conf']=b'[Service]\nEnvironmentFile=/etc/kosmozoo/native configuration.env\n'
  config=values+'TMPDIR="/data/native-cold-configuration"\nPATH="/nonexistent"\n'+literal+f'KOZMOZOO_BIND="{ct["ip"]}"\nKOZMOZOO_PORT="80"\n'
  if cid==2121:config+='KOZMOZOO_PORT="18081"\nKOZMOZOO_PORT="80"\n'
  out['etc/kosmozoo/native configuration.env']=config.encode()
  if cid==2121:
   out['etc/systemd/system/kosmozoo.service.d/native-acceptance.conf']=b'[Service]\nEnvironmentFile=/etc/kosmozoo/native literal.env\n'
   out['etc/kosmozoo/native literal.env']=(values+'TMPDIR="/data/native-cold"\nPATH="/nonexistent"\n'+literal+f'KOZMOZOO_BIND="{ct["ip"]}"\nKOZMOZOO_PORT="080"\n').encode()
 return out
try:
 if action=='validate':validate();print(phase)
 elif action=='record':
  kind,stage_result,destination=args;s=json.loads(owned(stage_result).read_text());need(s['ctid']==cid and s['source_tree']==g['source']['tree'] and s['stage']==kind and s['status']=='stage-passed','unexpected child stage result');cp=checkpoint(kind,s['evidence']);a[kind]=cp
  if kind=='bootstrap':
   ct['ownership']=s['ownership'];a.update(phase='installed',version=cp['version'],binary_sha256=cp['binary_sha256']);cp['owner_ctid']=cid
   if g['native'].get('install_resources') is None:g['native']['install_resources']=cp
  elif kind=='lifecycle':
   r=js(cp,'lifecycle-accepted.json');a.update(phase='lifecycle',version=r['version'],binary_sha256=r['binary_sha256'],baseline=r['baseline']);ct['browser_profile']=r['profile']
  elif kind=='configuration':a['phase']='configuration'
  else:a['phase']='failures';a.update(version=js(cp,'failures-accepted.json')['version'],binary_sha256=js(cp,'failures-accepted.json')['binary_sha256'])
  with pathlib.Path(destination).open('x') as f:json.dump(g,f,indent=2)
 elif action in ('admit-disk','disk'):
  r=pathlib.Path(args[0]);need(str(r)==f'/var/lib/lxc/{cid}/rootfs','wrong disk read root')
  need(sha((r/'opt/kosmozoo/kosmozoo').read_bytes())==a['binary_sha256'] and (r/'root/.kosmozoo').read_text().strip()==a['version'],'live code/marker differs from accepted state')
  if phase in ('configuration','failures'):
   need(not (r/'opt/kosmozoo/activation-attempt.json').exists() and not (r/'var/lib/scripts-underground/update-pending/kosmozoo').exists(),'unfinished operation')
   for path,data in expected_files().items():need((r/path).read_bytes()==data,'operator input differs: '+path)
   need(sha((r/'etc/systemd/system/kosmozoo.service').read_bytes())==g['native']['expected_unit_sha256'],'unknown base service unit')
   drop=r/'etc/systemd/system/kosmozoo.service.d';expected={path.split('/')[-1] for path in expected_files() if '/kosmozoo.service.d/' in path};need((set(p.name for p in drop.iterdir()) if drop.exists() else set())==expected,'unknown service drop-in')
   need((r/'etc/systemd/system/multi-user.target.wants/kosmozoo.service').is_symlink(),'expected enabled state changed')
  if action=='disk':
   state=r/ct['state'].lstrip('/');cache=r/ct['cache'].lstrip('/');c=sqlite3.connect((state/'metadata.db').as_uri()+'?mode=ro',uri=True)
   wants={'recovery':{'hash':a['recovery']['hash'],'judgment':{'bookmark':True,'notes':{'pos':a['recovery']['note']}}}} if failure else baseline()['rows']
   for source,want in wants.items():
    row=c.execute('select hash,vote,favorite,bookmark,notes from entry where collection=? and name=?',(source,'flux-basic.png')).fetchone();need(row is not None,'missing accepted row');j=want['judgment'];need(row[0]==want['hash'] and row[1]==j.get('vote') and row[2] is None and row[3]==1 and json.loads(row[4])==j['notes'],'disk judgment mismatch');need(sha((cache/row[0][:2]/row[0]).read_bytes())==row[0],'disk cache mismatch')
   if not failure:need(json.loads((state/'settings.json').read_text())['data']['core.judgment']['downvoteHides'] is False and c.execute('select pinned,auto_refresh from collection where id=?',('remote',)).fetchone()==(1,1),'disk settings/source flags mismatch')
   c.close()
  print('PASS exact current disk '+action)
 else:raise ValueError('unknown all-mode metadata action')
except (ValueError,KeyError,StopIteration,AssertionError,OSError,TypeError,IndexError,UnicodeError,sqlite3.Error,tarfile.TarError) as e:
 print('Kosmozoo checkpoint refusal: '+str(e),file=sys.stderr);raise SystemExit(65)
ALLDATA
}

if [[ "$mode" == --lxc && "$stage_name" == all ]]; then
  phase=$(all_metadata validate) || exit 65
  ct=$(jq -ce --argjson id "$ctid" '.native.containers[] | select(.id == $id)' "$guard")
  if [[ "$phase" == new ]]; then
    [[ ! -e "/etc/pve/lxc/$ctid.conf" && ! -e "/etc/pve/qemu-server/$ctid.conf" && -z "$(lvs --noheadings -o lv_name | grep -E "^[[:space:]]*vm-${ctid}-" || true)" ]] || exit 65
  else
    [[ "$(pct status "$ctid")" == 'status: stopped' && "$(lvs --noheadings -o lv_uuid "/dev/pve/vm-$ctid-disk-0" | xargs)" == "$(jq -r .ownership.lv_uuid <<< "$ct")" && "$(blkid -s UUID -o value "/dev/pve/vm-$ctid-disk-0")" == "$(jq -r .ownership.filesystem_uuid <<< "$ct")" ]] || exit 65
    config=$(pct config "$ctid") || exit 65
    for required in 'cores: 2' 'memory: 1024' 'unprivileged: 1' "hostname: $(jq -r .hostname <<< "$ct")"; do grep -qxF "$required" <<< "$config" || exit 65; done
    grep -qiF "hwaddr=$(jq -r .mac <<< "$ct")" <<< "$config" || exit 65
    grep -qF "ip=$(jq -r .ip <<< "$ct")/24" <<< "$config" || exit 65
    grep -qF 'bridge=vmbrkz24' <<< "$config" || exit 65
    grep -qE "^rootfs: local-lvm:vm-$ctid-disk-0,size=4G$" <<< "$config" || exit 65
    timeout 30 pct mount "$ctid"
    status=0
    all_metadata admit-disk "/var/lib/lxc/$ctid/rootfs" || status=$?
    timeout 30 pct unmount "$ctid"
    [[ "$status" == 0 ]] || exit "$status"
  fi
  # Only metadata/log/profile/cache reads remain for completed checkpoints.
  thin_free=$(lvs --reportformat json --units b --nosuffix -o lv_size,data_percent /dev/pve/data | jq -er '.report[0].lv[0] | ((.lv_size|tonumber)*(1-(.data_percent|tonumber)/100))|floor')
  ((thin_free >= 2147483648 + 67108864)) || exit 65
  [[ "$(df -B1 --output=avail "$W" | tr -dc '0-9')" -ge 4429185024 ]] || exit 65
  pipeline=$(mktemp -d "$W/artifacts/kosmozoo-all.XXXXXXXX")
  cp "$guard" "$pipeline/independent-input.json"
  sequence=0
  while :; do
    phase=$(all_metadata validate) || exit 65
    case "$phase" in
      new) next_stage=bootstrap ;;
      installed | consumers) if [[ "$(jq -r .role <<< "$ct")" == failure ]]; then next_stage=failures; else next_stage=lifecycle; fi ;;
      activation-failed) next_stage=failures ;;
      lifecycle) next_stage=configuration ;;
      configuration | failures) next_stage=final-consumer ;;
      *) exit 65 ;;
    esac
    if [[ "$next_stage" == lifecycle || "$next_stage" == failures ]]; then
      media=$(jq -er .media_source <<< "$ct")
      if [[ ! -e "$media" ]]; then
        [[ "$media" == "$W/fixtures/media-$ctid" && "$phase" == installed ]] || exit 65
        fixture_hash=$(jq -er '.native.fixtures.files[] | select(.path == "tests/fixtures/flux-basic.png") | .sha256' "$guard")
        [[ "$(sha256sum "$W/fixtures/kosmozoo-v0.2.2/tests/fixtures/flux-basic.png" | cut -d ' ' -f1)" == "$fixture_hash" ]] || exit 65
        install -d -m 0755 -o 101000 -g 101000 "$media"
        install -m 0644 -o 101000 -g 101000 "$W/fixtures/kosmozoo-v0.2.2/tests/fixtures/flux-basic.png" "$media/flux-basic.png"
      fi
    fi
    sequence=$((sequence + 1))
    log="$pipeline/$sequence-$next_stage.log"
    timeout --signal=TERM --kill-after=90 2300 bash "$0" --lxc --guard-manifest "$guard" --ctid "$ctid" --stage "$next_stage" | tee "$log"
    [[ "$(grep -ac '^KZ_STAGE_RESULT=' "$log")" == 1 ]] || exit 65
    result="$pipeline/$sequence-result.json"
    grep -a '^KZ_STAGE_RESULT=' "$log" | cut -d = -f2- > "$result"
    if [[ "$next_stage" == final-consumer ]]; then
      timeout 30 pct mount "$ctid"
      status=0
      all_metadata disk "/var/lib/lxc/$ctid/rootfs" || status=$?
      timeout 30 pct unmount "$ctid"
      [[ "$status" == 0 ]] || exit "$status"
      cp "$guard" "$pipeline/final-bound-input.json"
      jq -n --argjson ctid "$ctid" --arg tree "$(git -C "$ROOT" write-tree)" --arg evidence "$pipeline" --slurpfile current "$result" '{status:"all-acceptance-passed",ctid:$ctid,source_tree:$tree,evidence:$evidence,current_consumer:$current[0],prior_outcomes:"independently bound semantic evidence, no completed mutations replayed"}' > "$pipeline/acceptance.json"
      printf '0 failure(s); Kosmozoo complete acceptance CT%s; evidence=%s\n' "$ctid" "$pipeline"
      exit 0
    fi
    next_guard="$pipeline/$sequence-known-next-input.json"
    all_metadata record "$next_stage" "$result" "$next_guard"
    guard=$next_guard
    ct=$(jq -ce --argjson id "$ctid" '.native.containers[] | select(.id == $id)' "$guard")
  done
fi

if [[ "$mode" == --lxc ]]; then
  if [[ "$stage_name" == final-consumer ]]; then
    phase=$(all_metadata validate) || exit 65
    [[ "$phase" == configuration || "$phase" == failures ]] || exit 65
  fi
  # This stage ends at a native bootstrap checkpoint. Later consumer stages must
  # never be inferred from its status or replay this first install.
  jq -e --arg id "$ctid" '
    .native.network.bridge == "vmbrkz24" and .native.network.gateway == "10.248.26.1" and
    .native.network.subnet == "10.248.26.0/24" and .native.network.dns == "192.168.122.1" and
    ([.native.containers[] | select((.id | tostring) == $id)] | length == 1) and
    (.native.root_reserve_bytes >= 4294967296) and (.native.thin_reserve_bytes >= 2147483648)
  ' "$guard" > /dev/null || exit 65
  ct=$(jq -ce --arg id "$ctid" '.native.containers[] | select((.id | tostring) == $id)' "$guard")
  ip=$(jq -er .ip <<< "$ct") mac=$(jq -er .mac <<< "$ct") hostname=$(jq -er .hostname <<< "$ct")
  initial=$(jq -er .initial_release <<< "$ct") state=$(jq -er .state <<< "$ct") cache=$(jq -er .cache <<< "$ct") hosts=$(jq -r .hosts <<< "$ct")
  [[ "$ip" =~ ^10\.248\.26\.(20|21|22)$ && "$mac" =~ ^[0-9a-f]{2}(:[0-9a-f]{2}){5}$ && "$hostname" =~ ^[a-z0-9-]+$ ]] || exit 65
  [[ "$ctid" == 2120 || "$ctid" == 2121 || "$ctid" == 2122 ]] || exit 65
  if [[ "$ctid" == 2122 ]]; then
    [[ "$ip" == 10.248.26.22 && "$mac" == 02:52:26:00:21:22 && "$hostname" == kz-failure-2122 && "$(jq -er .role <<< "$ct")" == failure ]] || exit 65
  fi
  [[ "$stage_name" != failures || "$ctid" == 2122 ]] || exit 65
  [[ "$initial" == latest || "$initial" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] || exit 65
  [[ "$state" == /data/* && "$cache" == /data/* && "$state" != "$cache" ]] || exit 65
  if [[ "$stage_name" == bootstrap ]]; then
    [[ ! -e "/etc/pve/lxc/$ctid.conf" && ! -e "/etc/pve/qemu-server/$ctid.conf" ]] || exit 65
    [[ -z "$(lvs --noheadings -o lv_name | grep -E "^[[:space:]]*vm-${ctid}-" || true)" ]] || exit 65
  else
    lv_uuid=$(jq -er .ownership.lv_uuid <<< "$ct")
    [[ "$(lvs --noheadings -o lv_uuid "/dev/pve/vm-$ctid-disk-0" | xargs)" == "$lv_uuid" ]] || exit 65
    pct config "$ctid" | grep -qiF "hwaddr=$mac" || exit 65
    pct config "$ctid" | grep -qxF "hostname: $hostname" || exit 65
    [[ "$(blkid -s UUID -o value "/dev/pve/vm-$ctid-disk-0")" == "$(jq -er .ownership.filesystem_uuid <<< "$ct")" ]] || exit 65
    [[ "$(pct status "$ctid")" == 'status: stopped' ]] || exit 65
    if [[ "$stage_name" == failures ]]; then
      failure_phase=$(jq -er .acceptance.phase <<< "$ct")
      [[ "$failure_phase" == installed || "$failure_phase" == activation-failed ]] || exit 65
      media_source=$(jq -er .media_source <<< "$ct")
      [[ "$media_source" == "$W/fixtures/media-$ctid" && -d "$media_source" && ! -L "$media_source" ]] || exit 65
      fixture_hash=$(jq -er '.native.fixtures.files[] | select(.path == "tests/fixtures/flux-basic.png") | .sha256' "$guard")
      [[ "$(sha256sum "$media_source/flux-basic.png" | cut -d ' ' -f1)" == "$fixture_hash" ]] || exit 65
      if [[ "$failure_phase" == installed ]]; then
        [[ -z "$(pct config "$ctid" | grep '^mp0:' || true)" ]] || exit 65
      else
        [[ "$(pct config "$ctid" | grep '^mp0:')" == "mp0: $media_source,mp=/sources/images,ro=1" ]] || exit 65
        [[ "$(jq -er .acceptance.failed_fact_sha256 <<< "$ct")" =~ ^[0-9a-f]{64}$ ]] || exit 65
      fi
    fi
    [[ "$(sha256sum /etc/hosts | cut -d ' ' -f1)" == "$(jq -r .native.protected_history.hosts_sha256 "$guard")" ]] || exit 65
    [[ -z "$(ss -H -lnt 'sport = :9335')" ]] || exit 65
    browser_user=$(jq -er .native.browser.user "$guard")
    [[ "$browser_user" =~ ^kz-browser$ && "$(id -u "$browser_user")" == "$(jq -r .native.browser.uid "$guard")" ]] || exit 65
    [[ "$(sha256sum "$W/tools/deno" | cut -d ' ' -f1)" == "$(jq -r .native.tooling.deno_sha256 "$guard")" ]] || exit 65
    if [[ "$stage_name" == lifecycle || "$stage_name" == configuration || "$stage_name" == final-consumer ]]; then
      acceptance=$(jq -er .acceptance.phase <<< "$ct")
      if [[ "$stage_name" == lifecycle ]]; then
        case "$acceptance" in installed | consumers) ;; *) exit 65 ;; esac
      elif [[ "$stage_name" == configuration ]]; then
        [[ "$acceptance" == lifecycle ]] || exit 65
        lifecycle_receipt=$(jq -er '.acceptance.lifecycle | .path // (.evidence + "/lifecycle-accepted.json")' <<< "$ct")
        [[ "$lifecycle_receipt" == "$W/artifacts/"* && "$lifecycle_receipt" != *..* && -f "$lifecycle_receipt" && ! -L "$lifecycle_receipt" ]] || exit 65
        [[ "$(sha256sum "$lifecycle_receipt" | cut -d ' ' -f1)" == "$(jq -er '.acceptance.lifecycle | .sha256 // .files["lifecycle-accepted.json"]' <<< "$ct")" ]] || exit 65
        jq -e '.status == "lifecycle-passed"' "$lifecycle_receipt" > /dev/null || exit 65
        configuration_port=$(jq -er .acceptance.configuration_port <<< "$ct")
        [[ "$configuration_port" == 80 || "$configuration_port" == 18081 ]] || exit 65
      fi
      expected_version=$(jq -er .acceptance.version <<< "$ct")
      expected_binary=$(jq -er .acceptance.binary_sha256 <<< "$ct")
      [[ "$expected_version" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ && "$expected_binary" =~ ^[0-9a-f]{64}$ ]] || exit 65
      if [[ "$acceptance" == consumers || "$acceptance" == lifecycle || "$acceptance" == configuration ]]; then
        baseline_input=$(jq -er .acceptance.baseline.path <<< "$ct")
        [[ "$baseline_input" == "$W/artifacts/"* && "$baseline_input" != *..* && -f "$baseline_input" && ! -L "$baseline_input" ]] || exit 65
        [[ "$(sha256sum "$baseline_input" | cut -d ' ' -f1)" == "$(jq -er .acceptance.baseline.sha256 <<< "$ct")" ]] || exit 65
      fi
    fi
    profile=$(jq -r '.browser_profile // empty' <<< "$ct")
    if [[ -n "$profile" ]]; then
      [[ "$profile" == "$W/browser/profile-$ctid."* && -d "$profile" && ! -L "$profile" && "$(stat -c %u "$profile")" == "$(id -u "$browser_user")" ]] || exit 65
    fi
    if [[ "$stage_name" == browser-first || "$stage_name" == browser-resume || "$stage_name" == lifecycle || "$stage_name" == configuration || "$stage_name" == final-consumer ]]; then
      media_source=$(jq -er .media_source <<< "$ct")
      [[ "$media_source" == "$W/fixtures/media-$ctid" && -d "$media_source" && ! -L "$media_source" ]] || exit 65
      [[ "$(sha256sum "$media_source/flux-basic.png" | cut -d ' ' -f1)" == "$(jq -er '.native.fixtures.files[] | select(.path == "tests/fixtures/flux-basic.png") | .sha256' "$guard")" ]] || exit 65
      if [[ "$stage_name" == browser-first || ("$stage_name" == lifecycle && "$acceptance" == installed) ]]; then
        [[ -z "$(pct config "$ctid" | grep '^mp0:' || true)" ]] || exit 65
      else
        [[ "$stage_name" != browser-resume || "$(jq -er .resume.phase <<< "$ct")" == local-judged ]] || exit 65
        [[ "$(pct config "$ctid" | grep '^mp0:')" == "mp0: $media_source,mp=/sources/images,ro=1" ]] || exit 65
      fi
      while IFS= read -r fixture_file; do
        [[ "$fixture_file" != /* && "$fixture_file" != *..* ]] || exit 65
        fixture_digest=$(jq -er --arg path "$fixture_file" '.native.fixtures.files[] | select(.path == $path) | .sha256' "$guard")
        [[ "$(sha256sum "$W/fixtures/kosmozoo-v0.2.2/$fixture_file" | cut -d ' ' -f1)" == "$fixture_digest" ]] || exit 65
      done < <(jq -r '.native.fixtures.files[].path' "$guard")
    fi
  fi
  # Admit expected growth separately on root and thin data. Nominal 4GiB CT
  # allowance is not charged to root or counted as current physical consumption.
  root_free=$(df -B1 --output=avail "$W" | tr -dc '0-9')
  thin_free=$(lvs --reportformat json --units b --nosuffix -o lv_size,data_percent /dev/pve/data | jq -er '[.report[0].lv[0] | (.lv_size | tonumber) * (1 - (.data_percent | tonumber) / 100)] | .[0] | floor')
  ((root_free >= $(jq -r .native.root_reserve_bytes "$guard") + 536870912)) || exit 65
  thin_growth=1610612736
  if [[ "$ctid" == 2122 && "$stage_name" == bootstrap ]]; then thin_growth=2147483648; fi
  [[ "$stage_name" != failures ]] || thin_growth=805306368
  # Completed preactivation/state-opening controls have already paid their
  # physical growth. The explicit continuation reserves the remaining maximum
  # six-ELF window (696MB total minus current116MB) plus metadata/control headroom.
  if [[ "$stage_name" == failures && "$failure_phase" == activation-failed ]]; then thin_growth=738197504; fi
  [[ "$stage_name" != final-consumer ]] || thin_growth=67108864
  ((thin_free >= $(jq -r .native.thin_reserve_bytes "$guard") + thin_growth)) || exit 65
  [[ "$(df --output=iavail "$W" | tr -dc '0-9')" -gt 100000 ]] || exit 65
  [[ "$(awk '/MemAvailable:/ {print $2}' /proc/meminfo)" -gt 1572864 ]] || exit 65
  [[ ! -e /sys/class/net/vmbrkz24 ]] || exit 65
  ! ip -j route show table all | jq -e '.[] | select(.dst == "10.248.26.0/24")' > /dev/null || exit 65
  ! nft list table inet kz_native > /dev/null 2>&1 || exit 65
  [[ -z "$(ss -H -lnt 'sport = :8089')" ]] || exit 65
  [[ "$(sysctl -n net.ipv4.ip_forward)" =~ ^[01]$ ]] || exit 65
  prior_forward=$(sysctl -n net.ipv4.ip_forward)
  work=$(mktemp -d "$W/artifacts/lxc-$ctid-$stage_name.XXXXXXXX")
  cp "$guard" "$work/issued-guard.json"
  git -C "$ROOT" ls-files -s > "$work/source-index.txt"
  printf '%s\n' "$ct" > "$work/intended-ct.json"
  printf 'phase=%s source=%s root_free=%s thin_free=%s evidence=%s\n' "$stage_name" "$(git -C "$ROOT" write-tree)" "$root_free" "$thin_free" "$work" | tee "$work/admission.txt"
  server='' provider='' sampler='' browser_unit='' hosts_after='' bridge_owned=0 firewall_owned=0 created=0 ct_mounted=0
  native_cleanup() {
    local status=$?
    trap - EXIT
    if [[ -n "$sampler" ]]; then
      touch "$work/stop-sampler"
      wait "$sampler" || status=1
    fi
    if [[ -n "$browser_unit" ]]; then timeout 30 systemctl stop "$browser_unit" || status=1; fi
    [[ -z "$provider" ]] || {
      kill "$provider" 2> /dev/null || true
      wait "$provider" 2> /dev/null || true
    }
    if [[ -n "$hosts_after" ]]; then
      if [[ "$(sha256sum /etc/hosts | cut -d ' ' -f1)" == "$hosts_after" ]]; then
        cat "$work/hosts-before" > /etc/hosts || status=1
      else
        printf 'Hosts changed concurrently; retained owned restoration bytes at %s\n' "$work/hosts-before" >&2
        status=1
      fi
    fi
    [[ -z "$server" ]] || {
      kill "$server" 2> /dev/null || true
      wait "$server" 2> /dev/null || true
    }
    if [[ "$created" == 1 && -f "/etc/pve/lxc/$ctid.conf" ]]; then
      if pct config "$ctid" | grep -qiF "hwaddr=$mac" && pct config "$ctid" | grep -qxF "hostname: $hostname"; then
        timeout 90 pct shutdown "$ctid" --timeout 60 || status=1
      else
        printf 'Refusing cleanup of changed CT identity %s\n' "$ctid" >&2
        status=1
      fi
    fi
    [[ "$ct_mounted" == 0 ]] || timeout 30 pct unmount "$ctid" || status=1
    [[ "$firewall_owned" == 0 ]] || nft delete table inet kz_native || status=1
    [[ "$bridge_owned" == 0 ]] || ip link set vmbrkz24 down || status=1
    [[ "$bridge_owned" == 0 ]] || ip link delete vmbrkz24 type bridge || status=1
    sysctl -q -w "net.ipv4.ip_forward=$prior_forward" || status=1
    printf 'status=%s; stage=%s; data retained\n' "$status" "$stage_name" > "$work/terminal.txt"
    if [[ "$status" == 0 ]]; then
      lv=$(lvs --noheadings -o lv_uuid "/dev/pve/vm-$ctid-disk-0" | xargs) || status=$?
      fs=${fs_uuid:-$(jq -r '.ownership.filesystem_uuid // empty' <<< "$ct")}
      if [[ "$status" == 0 && -n "$lv" && -n "$fs" ]]; then
        jq -n --argjson ctid "$ctid" --arg stage "$stage_name" --arg tree "$(git -C "$ROOT" write-tree)" --arg evidence "$work" --arg lv "$lv" --arg fs "$fs" --arg profile "${profile:-}" '{status:"stage-passed",ctid:$ctid,stage:$stage,source_tree:$tree,evidence:$evidence,ownership:{lv_uuid:$lv,filesystem_uuid:$fs},profile:$profile}' > "$work/stage-result.json" || status=$?
        [[ "$status" != 0 ]] || printf 'KZ_STAGE_RESULT=%s\n' "$(jq -c . "$work/stage-result.json")"
      else
        status=65
      fi
    fi
    exit "$status"
  }
  trap native_cleanup EXIT
  native_install_watch() {
    # Before payload boot, pool/root accounting observes extraction/formatting.
    # Once the owned init exists, record its ACTUAL finite ancestor cgroup and
    # namespace-root code/temp bytes throughout the ordinary install pipeline.
    local init='' cg='' path='' group='' code_bytes=0 data_bytes=0 tmp_bytes=0 bootstrap_bytes=0 fs_uuid='' value
    printf 'epoch_ms payload memory_current memory_peak swap_current swap_peak code_bytes data_bytes tmp_bytes bootstrap_bytes thin_data_percent root_available\n'
    while [[ ! -e "$work/stop-sampler" ]]; do
      group='' code_bytes=0 data_bytes=0 tmp_bytes=0 bootstrap_bytes=0
      if [[ -f "/etc/pve/lxc/$ctid.conf" ]] && pct config "$ctid" 2> /dev/null | grep -qiF "hwaddr=$mac"; then
        init=$(timeout 3 lxc-info -n "$ctid" -pH 2> /dev/null) || init=''
        if [[ "$init" =~ ^[1-9][0-9]*$ && -r "/proc/$init/cgroup" ]]; then
          cg=$(cut -d : -f3 "/proc/$init/cgroup")
          [[ "$cg" == "/lxc/$ctid/"* || "$cg" == "/lxc/$ctid" ]] || return 65
          path="/sys/fs/cgroup$cg"
          while [[ "$path" == /sys/fs/cgroup/* ]]; do
            value=$(cat "$path/memory.max") || return $?
            if [[ "$value" == 1073741824 ]]; then
              group=$path
              break
            fi
            path=${path%/*}
          done
          [[ -n "$group" ]] || return 65
          printf '%s\n' "$group" > "$work/install-effective-cgroup.txt"
          if [[ -d "/proc/$init/root/opt/kosmozoo" ]]; then code_bytes=$(du -s -B1 "/proc/$init/root/opt/kosmozoo" | cut -f1) || return $?; fi
          if [[ -d "/proc/$init/root/data" ]]; then data_bytes=$(du -s -B1 "/proc/$init/root/data" | cut -f1) || return $?; fi
          if [[ -d "/proc/$init/root/data/tmp" ]]; then tmp_bytes=$(du -s -B1 "/proc/$init/root/data/tmp" | cut -f1) || return $?; fi
          if [[ -d "/proc/$init/root/data/bootstrap-tmp" ]]; then bootstrap_bytes=$(du -s -B1 "/proc/$init/root/data/bootstrap-tmp" | cut -f1) || return $?; fi
          for value in memory.max memory.events memory.swap.max memory.swap.events cpu.stat; do
            printf '%s=' "$value"
            tr '\n' ';' < "$group/$value"
            printf '\n'
          done > "$work/install-parent-last.txt"
        fi
        if [[ ! -e "$work/creation-lv.json" && -b "/dev/pve/vm-$ctid-disk-0" ]]; then
          fs_uuid=$(blkid -s UUID -o value "/dev/pve/vm-$ctid-disk-0") || fs_uuid=''
          if [[ -n "$fs_uuid" ]]; then
            lvs --reportformat json --units b --nosuffix -o lv_name,lv_uuid,lv_size "/dev/pve/vm-$ctid-disk-0" > "$work/creation-lv.json"
            printf '%s\n' "$fs_uuid" > "$work/creation-fs-uuid.txt"
            pct config "$ctid" > "$work/creation-config.txt"
          fi
        fi
      fi
      if [[ -n "$group" ]]; then
        printf '%s 1 %s %s %s %s %s %s %s %s ' "$(date +%s%3N)" "$(cat "$group/memory.current")" "$(cat "$group/memory.peak")" "$(cat "$group/memory.swap.current")" "$(cat "$group/memory.swap.peak")" "$code_bytes" "$data_bytes" "$tmp_bytes" "$bootstrap_bytes"
      else
        printf '%s 0 0 0 0 0 0 0 0 0 ' "$(date +%s%3N)"
      fi
      printf '%s %s\n' "$(lvs --noheadings -o data_percent /dev/pve/data | xargs)" "$(df -B1 --output=avail "$W" | tr -dc '0-9')"
      sleep 0.5
    done
  }
  ip link add vmbrkz24 type bridge
  bridge_owned=1
  ip address add 10.248.26.1/24 dev vmbrkz24
  ip link set vmbrkz24 up
  nft -f - << 'NFT'
table inet kz_native {
  chain inbound { type filter hook input priority -10; policy accept;
    tcp dport { 8089, 8188 } iifname != "vmbrkz24" iifname != "lo" reject
  }
  chain outbound_nat { type nat hook postrouting priority srcnat; policy accept;
    ip saddr 10.248.26.0/24 oifname "vmbr0" masquerade
  }
}
NFT
  firewall_owned=1
  sysctl -q -w net.ipv4.ip_forward=1
  # Ordinary test transport serves the actual candidate, without a bootstrap shim.
  busybox httpd -f -p 10.248.26.1:8089 -h "$ROOT" > "$work/repo-server.log" 2>&1 &
  server=$!
  for _ in {1..30}; do
    curl -fsS --max-time 2 http://10.248.26.1:8089/misc/bootstrap/lxc > "$work/served-bootstrap" && break
    sleep 1
  done
  cmp "$work/served-bootstrap" "$ROOT/misc/bootstrap/lxc"
  nft list table inet kz_native > "$work/firewall.txt"
  if [[ "$stage_name" == failures ]]; then
    media_source=$(jq -er .media_source <<< "$ct")
    [[ "$media_source" == "$W/fixtures/media-$ctid" && -d "$media_source" && ! -L "$media_source" ]]
    fixture_hash=$(jq -er '.native.fixtures.files[] | select(.path == "tests/fixtures/flux-basic.png") | .sha256' "$guard")
    [[ "$(sha256sum "$media_source/flux-basic.png" | cut -d ' ' -f1)" == "$fixture_hash" ]]
    stat -c '%d:%i %u:%g %a %n' "$media_source" "$media_source/flux-basic.png" > "$work/media-before.txt"
    sha256sum "$media_source/flux-basic.png" >> "$work/media-before.txt"
    curl -fsSL --connect-timeout 15 --max-time 60 https://api.github.com/repos/alexindigo/kosmozoo/releases/latest > "$work/current-release.json"
    jq -e '.draft == false and .prerelease == false and ([.assets[] | select(.name == "kosmozoo-linux-x86_64")] | length == 1)' "$work/current-release.json" > /dev/null
    target=$(jq -er '.tag_name | ltrimstr("v")' "$work/current-release.json")
    target_digest=$(jq -er '.assets[] | select(.name == "kosmozoo-linux-x86_64") | .digest | ltrimstr("sha256:")' "$work/current-release.json")
    [[ "$target" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ && "$target_digest" =~ ^[0-9a-f]{64}$ && "$target" != 0.2.1 ]]
    if [[ "$failure_phase" == installed ]]; then
      pct set "$ctid" --mp0 "$media_source,mp=/sources/images,ro=1"
    else
      [[ "$target" == "$(jq -er .acceptance.attempted_release <<< "$ct")" ]]
      timeout 30 pct mount "$ctid"
      rootfs="/var/lib/lxc/$ctid/rootfs"
      safe=1
      [[ ! -e "$rootfs/etc/systemd/system/multi-user.target.wants/kosmozoo.service" ]] || safe=0
      [[ "$(cat "$rootfs/root/.kosmozoo")" == 0.2.1 ]] || safe=0
      [[ "$(sha256sum "$rootfs/opt/kosmozoo/kosmozoo" | cut -d ' ' -f1)" == 87b5f399598c61988f66c016327e189997432c3c4ad6a5102e227d32ca2b55d2 ]] || safe=0
      [[ "$(sha256sum "$rootfs/opt/kosmozoo/activation-attempt.json" | cut -d ' ' -f1)" == "$(jq -r .acceptance.failed_fact_sha256 <<< "$ct")" ]] || safe=0
      timeout 30 pct unmount "$ctid"
      [[ "$safe" == 1 ]] || exit 65
    fi
    created=1
    timeout 90 pct start "$ctid"
    native_install_watch > "$work/failure-resource-timeline-before-reboot.txt" &
    sampler=$!
    if [[ "$failure_phase" == installed ]]; then
      timeout 900 pct exec "$ctid" -- env HOME=/root TMPDIR=/data/bootstrap-tmp TARGET_VERSION="$target" TARGET_SHA="$target_digest" FIXTURE_SHA="$fixture_hash" bash -se > "$work/native-before-reboot.log" 2>&1 << 'NATIVEPRE'
set -euo pipefail
for n in {1..90}; do curl -fsS --max-time 2 http://127.0.0.1/api/runtime > /data/native-initial-runtime.json && break; sleep 1; done
jq -e '.app.version == "0.2.1" and .status == "ready"' /data/native-initial-runtime.json
printf '%s  %s\n' 87b5f399598c61988f66c016327e189997432c3c4ad6a5102e227d32ca2b55d2 /opt/kosmozoo/kosmozoo | sha256sum --check --strict
test "$(cat /root/.kosmozoo)" = 0.2.1
test "$(systemctl is-enabled kosmozoo)" = enabled
test ! -e /data/native-controls
install -d -m 0700 /data/native-controls
export CONTROL=/data/native-controls
jq -n --arg version "$TARGET_VERSION" --arg digest "$TARGET_SHA" '{version:$version,digest:$digest}' > "$CONTROL/expected.json"
curl -fsS --max-time 10 http://127.0.0.1/api/collections | jq -e 'length == 0'
curl -fsS --max-time 10 -H 'Content-Type: application/json' -d '{"name":"recovery","address":"folder:/sources/images"}' http://127.0.0.1/api/collections > "$CONTROL/source.json"
curl -fsS --max-time 10 http://127.0.0.1/api/collections/recovery/entries/flux-basic.png/bytes > "$CONTROL/original.png"
printf '%s  %s\n' "$FIXTURE_SHA" "$CONTROL/original.png" | sha256sum --check --strict
curl -fsS --max-time 10 -X PATCH -H 'Content-Type: application/json' -d '{"bookmark":true,"notes":{"pos":"native-before-activation"}}' http://127.0.0.1/api/collections/recovery/entries/flux-basic.png/judgment > "$CONTROL/before-judgment.json"
stat -c %i /data/state/engine.lock > "$CONTROL/lock-inode"
systemctl show kosmozoo -p MainPID --value > "$CONTROL/old-pid"
sha256sum /opt/kosmozoo/kosmozoo /root/.kosmozoo > "$CONTROL/old-code.sha256"
# Actual asset-network refusal; metadata remains actual public HTTPS via NO_PROXY.
status=0
timeout 180 env HTTPS_PROXY=http://127.0.0.1:9 https_proxy=http://127.0.0.1:9 NO_PROXY=api.github.com no_proxy=api.github.com /usr/local/sbin/update > "$CONTROL/active-download.log" 2>&1 || status=$?
test "$status" != 0
test "$status" != 124
grep -F 'Download failed' "$CONTROL/active-download.log"
test "$(systemctl show kosmozoo -p MainPID --value)" = "$(cat "$CONTROL/old-pid")"
systemctl is-active --quiet kosmozoo
sha256sum --check --strict "$CONTROL/old-code.sha256"
printf 'PASS native actual asset-network failure keeps old PID/code/marker active\n'
curl() {
  local status=0 output='' url='' previous='' argument actual
  /usr/bin/curl "$@" || status=$?
  [[ "$status" == 0 ]] || return "$status"
  for argument in "$@"; do
    [[ "$previous" != -o ]] || output=$argument
    [[ "$argument" != https://github.com/alexindigo/kosmozoo/releases/download/*/kosmozoo-linux-x86_64 ]] || url=$argument
    previous=$argument
  done
  if [[ -n "$url" ]]; then
    [[ "$output" == /opt/kosmozoo/.stage.*/kosmozoo && -f "$output" && ! -L "$output" ]] || return 65
    actual=$(sha256sum "$output" | cut -d ' ' -f1)
    [[ "$actual" == "$(jq -r .digest /data/native-controls/expected.json)" ]] || return 65
    jq -n --arg hash "$actual" --arg path "$output" --arg url "$url" '{injection:"OS curl seam: verified actual public bytes, then controlled file corruption",original_sha256:$hash,path:$path,url:$url}' >> /data/native-controls/corruption.jsonl
    printf '\nCONTROLLED-NATIVE-DIGEST-FAULT\n' >> "$output"
  fi
  return 0
}
export -f curl
declare -f curl > "$CONTROL/asset-corruption-function.sh"
sha256sum "$CONTROL/asset-corruption-function.sh" > "$CONTROL/asset-corruption-function.sha256"
status=0
timeout 180 /usr/local/sbin/update > "$CONTROL/active-digest.log" 2>&1 || status=$?
test "$status" = 65
test -s "$CONTROL/corruption.jsonl"
test "$(systemctl show kosmozoo -p MainPID --value)" = "$(cat "$CONTROL/old-pid")"
systemctl is-active --quiet kosmozoo
sha256sum --check --strict "$CONTROL/old-code.sha256"
unset -f curl
printf 'PASS native checksum refusal on actual downloaded bytes with explicitly modeled corruption seam; old service active\n'
cat > "$CONTROL/activation-post.sh" << 'ACTOR'
#!/usr/bin/env bash
set -euo pipefail
export TMPDIR=/data/tmp
c=/data/native-controls
target=$(jq -r .version "$c/expected.json") digest=$(jq -r .digest "$c/expected.json")
for n in {1..60}; do
 if curl -fsS --max-time 1 http://127.0.0.1/api/runtime > "$c/candidate-runtime.json" && jq -e --arg v "$target" '.app.version == $v and .status == "ready"' "$c/candidate-runtime.json" > /dev/null; then break; fi
 sleep 0.2
done
jq -e --arg v "$target" '.app.version == $v and .protocol == "kosmozoo-runtime" and .version == 1' "$c/candidate-runtime.json"
printf '%s  %s\n' "$digest" /opt/kosmozoo/kosmozoo | sha256sum --check --strict
systemctl show kosmozoo -p MainPID -p ControlGroup > "$c/candidate-unit.txt"
cat /root/.kosmozoo > "$c/candidate-old-marker.txt"
mode=$(cat "$c/actor-mode")
note=native-candidate-write
[[ "$mode" != hold ]] || note=native-newer-elf-old-marker-write
[[ "$mode" != disabled ]] || note=native-disabled-original-write
jq -n --arg note "$note" '{notes:{pos:$note}}' > "$c/candidate-write-input.json"
curl -fsS --max-time 10 -X PATCH -H 'Content-Type: application/json' --data-binary "@$c/candidate-write-input.json" http://127.0.0.1/api/collections/recovery/entries/flux-basic.png/judgment > "$c/candidate-write-result.json"
touch "$c/actor-ready"
if [[ "$mode" == hold ]]; then
 for n in {1..300}; do [[ ! -e "$c/release-hold" ]] || exit 0; sleep 0.2; done
 exit 24
fi
exit 23
ACTOR
chmod 0755 "$CONTROL/activation-post.sh"
install -d -m 0755 /etc/systemd/system/kosmozoo.service.d
printf '%s\n' '[Service]' 'Restart=no' 'ExecStartPost=/bin/bash /data/native-controls/activation-post.sh' > /etc/systemd/system/kosmozoo.service.d/native-failure.conf
sha256sum /etc/systemd/system/kosmozoo.service.d/native-failure.conf "$CONTROL/activation-post.sh" > "$CONTROL/fault-inputs.sha256"
printf 'fail\n' > "$CONTROL/actor-mode"
systemctl daemon-reload
status=0
timeout 240 /usr/local/sbin/update > "$CONTROL/state-opening-failure.log" 2>&1 || status=$?
test "$status" != 0
test "$status" != 124
test -e "$CONTROL/actor-ready"
test "$(systemctl show kosmozoo -p MainPID --value)" = 0
test "$(systemctl is-enabled kosmozoo 2>/dev/null || true)" = disabled
sha256sum --check --strict "$CONTROL/old-code.sha256"
jq -e --arg v "$TARGET_VERSION" --arg digest "$TARGET_SHA" '.release == $v and .digest == $digest and .enabled == true' /opt/kosmozoo/activation-attempt.json
cp /opt/kosmozoo/activation-attempt.json "$CONTROL/failed-attempt.json"
cp "$CONTROL/candidate-runtime.json" "$CONTROL/failed-candidate-runtime.json"
cp "$CONTROL/candidate-write-result.json" "$CONTROL/failed-candidate-write.json"
test "$(stat -c %i /data/state/engine.lock)" = "$(cat "$CONTROL/lock-inode")"
printf 'PASS actual newer candidate opened state and API-wrote; real ExecStartPost23 failed; old ELF/marker restored only after stopped+disabled\n'
NATIVEPRE
    else
      timeout 20 pct exec "$ctid" -- env HOME=/root TMPDIR=/data/bootstrap-tmp bash -se > "$work/native-continuation-admission.txt" << 'CONTINUATION'
set -euo pipefail
test "$(systemctl show kosmozoo -p MainPID --value)" = 0
test "$(systemctl is-enabled kosmozoo 2>/dev/null || true)" = disabled
sha256sum --check --strict /data/native-controls/old-code.sha256
cmp /opt/kosmozoo/activation-attempt.json /data/native-controls/failed-attempt.json
sha256sum --check --strict /data/native-controls/fault-inputs.sha256
printf 'PASS explicit prior native state-opening failure, no seed/judgment/fault replay\n'
CONTINUATION
    fi
    # Use the already proven ordinary OFFLINE PVE SQLite read route. The live
    # proc-root SQLite path and a private bind attempt both failed on this host.
    touch "$work/stop-sampler"
    wait "$sampler"
    sampler=''
    cp "$work/install-parent-last.txt" "$work/failure-parent-before-reboot.txt"
    timeout 90 pct shutdown "$ctid" --timeout 60
    timeout 30 pct mount "$ctid"
    ct_mounted=1
    python3 - "/var/lib/lxc/$ctid/rootfs/data/state/metadata.db" "$work/native-failed-state.json" << 'FAILUREDB'
import sqlite3,pathlib,json,sys
c=sqlite3.connect(pathlib.Path(sys.argv[1]).as_uri()+'?mode=ro',uri=True)
r=c.execute('select hash,bookmark,notes from entry where collection=? and name=?',('recovery','flux-basic.png')).fetchone()
assert r and r[1]==1 and json.loads(r[2])['pos']=='native-candidate-write'
pathlib.Path(sys.argv[2]).write_text(json.dumps({'hash':r[0],'bookmark':r[1],'notes':json.loads(r[2])}))
print('PASS actual stopped-engine SQLite retains candidate API write, no database rollback')
c.close()
FAILUREDB
    timeout 30 pct unmount "$ctid"
    ct_mounted=0
    timeout 90 pct start "$ctid"
    before_init=$(lxc-info -n "$ctid" -pH)
    timeout 120 pct reboot "$ctid" --timeout 90
    for _ in {1..90}; do
      native_init=$(lxc-info -n "$ctid" -pH 2> /dev/null) || native_init=''
      if [[ "$native_init" =~ ^[1-9][0-9]*$ && "$native_init" != "$before_init" ]]; then
        timeout 5 pct exec "$ctid" -- systemctl is-system-running --wait > "$work/reboot-system-state.txt" 2>&1 || true
        grep -qxE 'running|degraded' "$work/reboot-system-state.txt" && break
      fi
      sleep 1
    done
    [[ "$native_init" =~ ^[1-9][0-9]*$ && "$native_init" != "$before_init" ]]
    printf 'before_init=%s after_init=%s\n' "$before_init" "$native_init" > "$work/real-ct-reboot.txt"
    rm "$work/stop-sampler"
    native_install_watch > "$work/failure-resource-timeline-after-reboot.txt" &
    sampler=$!
    timeout 1200 pct exec "$ctid" -- env HOME=/root TMPDIR=/data/bootstrap-tmp TARGET_VERSION="$target" TARGET_SHA="$target_digest" bash -se > "$work/native-after-reboot.log" 2>&1 << 'NATIVEPOST'
set -euo pipefail
export CONTROL=/data/native-controls
test "$(systemctl show kosmozoo -p MainPID --value)" = 0
test "$(systemctl is-enabled kosmozoo 2>/dev/null || true)" = disabled
test -z "$(ss -H -lnt 'sport = :80')"
sha256sum --check --strict "$CONTROL/old-code.sha256"
printf 'PASS real CT reboot did not autostart restored older ELF\n'
cp /opt/kosmozoo/activation-attempt.json "$CONTROL/prior-valid-fact.json"
printf '{corrupt\n' > /opt/kosmozoo/activation-attempt.json
status=0; timeout 60 /usr/local/sbin/update > "$CONTROL/corrupt-fact.log" 2>&1 || status=$?
test "$status" = 65
test "$(systemctl show kosmozoo -p MainPID --value)" = 0
sha256sum --check --strict "$CONTROL/old-code.sha256"
install -m 0600 "$CONTROL/prior-valid-fact.json" /opt/kosmozoo/activation-attempt.json
status=0; timeout 90 env var_appversion=0.2.1 /usr/local/sbin/update > "$CONTROL/old-pin.log" 2>&1 || status=$?
test "$status" = 65
test "$(systemctl show kosmozoo -p MainPID --value)" = 0
grep -F 'Refusing downgrade below possibly state-opening version' "$CONTROL/old-pin.log"
cmp /opt/kosmozoo/activation-attempt.json "$CONTROL/prior-valid-fact.json"
status=0; timeout 180 env HTTPS_PROXY=http://127.0.0.1:9 https_proxy=http://127.0.0.1:9 NO_PROXY=api.github.com no_proxy=api.github.com /usr/local/sbin/update > "$CONTROL/stopped-download.log" 2>&1 || status=$?
test "$status" != 0
test "$status" != 124
grep -F 'Download failed' "$CONTROL/stopped-download.log"
test "$(systemctl show kosmozoo -p MainPID --value)" = 0
test "$(systemctl is-enabled kosmozoo 2>/dev/null || true)" = disabled
cmp /opt/kosmozoo/activation-attempt.json "$CONTROL/prior-valid-fact.json"
sha256sum --check --strict "$CONTROL/old-code.sha256"
sha256sum --check --strict "$CONTROL/asset-corruption-function.sha256"
source "$CONTROL/asset-corruption-function.sh"
export -f curl
status=0; timeout 180 /usr/local/sbin/update > "$CONTROL/stopped-digest.log" 2>&1 || status=$?
unset -f curl
test "$status" = 65
test "$(systemctl show kosmozoo -p MainPID --value)" = 0
test "$(systemctl is-enabled kosmozoo 2>/dev/null || true)" = disabled
cmp /opt/kosmozoo/activation-attempt.json "$CONTROL/prior-valid-fact.json"
sha256sum --check --strict "$CONTROL/old-code.sha256"
printf 'PASS actual corrupt fact, old-pin floor and stopped failed download/checksum never start old code; checksum seam labeled\n'
# A crash of ONLY the owned updater unit leaves a naturally published newer ELF
# and older marker. The candidate's own unit/cgroup is NOT force-killed.
rm "$CONTROL/actor-ready"
printf 'hold\n' > "$CONTROL/actor-mode"
test "$(systemctl show native-kz-updater-crash -p LoadState --value)" = not-found
systemd-run --unit=native-kz-updater-crash --property=Type=exec --property=RuntimeMaxSec=180 --property=Restart=no --setenv=HOME=/root --setenv=TMPDIR=/data/bootstrap-tmp --property=StandardOutput=file:/data/native-controls/crash-update.log --property=StandardError=inherit /usr/local/sbin/update
for n in {1..150}; do test ! -e "$CONTROL/actor-ready" || break; sleep 0.2; done
test -e "$CONTROL/actor-ready"
sha256sum --check --strict "$CONTROL/fault-inputs.sha256"
systemctl show native-kz-updater-crash -p MainPID -p ControlGroup -p ExecStart > "$CONTROL/crash-updater-owner.txt"
updater_pid=$(systemctl show native-kz-updater-crash -p MainPID --value)
test "$updater_pid" -gt 0
tr '\0' ' ' < "/proc/$updater_pid/cmdline" | grep -F /usr/local/sbin/update
printf '%s  %s\n' "$TARGET_SHA" /opt/kosmozoo/kosmozoo | sha256sum --check --strict
test "$(cat /root/.kosmozoo)" = 0.2.1
systemctl kill --signal=KILL native-kz-updater-crash
for n in {1..30}; do test "$(systemctl show native-kz-updater-crash -p MainPID --value)" != 0 || break; sleep 0.2; done
test "$(systemctl show native-kz-updater-crash -p MainPID --value)" = 0
touch "$CONTROL/release-hold"
for n in {1..60}; do systemctl is-active --quiet kosmozoo && break; sleep 0.2; done
systemctl is-active --quiet kosmozoo
curl -fsS --max-time 10 http://127.0.0.1/api/runtime > "$CONTROL/newer-elf-old-marker-runtime.json"
jq -e --arg v "$TARGET_VERSION" '.app.version == $v and .status == "ready"' "$CONTROL/newer-elf-old-marker-runtime.json"
test "$(cat /root/.kosmozoo)" = 0.2.1
cp /opt/kosmozoo/activation-attempt.json "$CONTROL/newer-elf-old-marker-fact.json"
printf 'PASS actual updater crash leaves genuine newer ELF, older marker and retained attempt fact; app unit not force-killed\n'
timeout 90 systemctl stop kosmozoo
systemctl disable kosmozoo
test "$(systemctl show kosmozoo -p MainPID --value)" = 0
sha256sum --check --strict "$CONTROL/fault-inputs.sha256"
rm /etc/systemd/system/kosmozoo.service.d/native-failure.conf
systemctl daemon-reload
timeout 240 /usr/local/sbin/update > "$CONTROL/safe-forward-retry.log" 2>&1
systemctl is-active --quiet kosmozoo
test "$(systemctl is-enabled kosmozoo)" = enabled
test "$(cat /root/.kosmozoo)" = "$TARGET_VERSION"
test ! -e /opt/kosmozoo/activation-attempt.json
printf '%s  %s\n' "$TARGET_SHA" /opt/kosmozoo/kosmozoo | sha256sum --check --strict
curl -fsS --max-time 10 http://127.0.0.1/api/collections/recovery/entries/flux-basic.png | jq -e '.judgment.notes.pos == "native-newer-elf-old-marker-write" and .judgment.bookmark == true'
test "$(stat -c %i /data/state/engine.lock)" = "$(cat "$CONTROL/lock-inode")"
printf 'PASS actual safe same/newer forward repair preserves candidate writes and original enabled state\n'
# Native lingering writer: ordinary graceful policy, no application SIGKILL.
cat > "$CONTROL/linger-stop.sh" << 'LINGER'
#!/usr/bin/env bash
trap '' TERM
printf '%s\n' "$BASHPID" > /data/native-controls/linger-pid
sleep 60 &
child=$!
wait "$child"
printf 'ended\n' > /data/native-controls/linger-ended
LINGER
chmod 0755 "$CONTROL/linger-stop.sh"
printf '%s\n' '[Service]' 'TimeoutStopSec=30s' 'SendSIGKILL=no' 'ExecStop=/bin/bash /data/native-controls/linger-stop.sh' > /etc/systemd/system/kosmozoo.service.d/native-linger.conf
sha256sum /etc/systemd/system/kosmozoo.service.d/native-linger.conf "$CONTROL/linger-stop.sh" > "$CONTROL/linger-inputs.sha256"
systemctl daemon-reload
sha256sum /opt/kosmozoo/kosmozoo /root/.kosmozoo > "$CONTROL/before-linger.sha256"
status=0; timeout 180 /usr/local/sbin/update --clean > "$CONTROL/linger-update.log" 2>&1 || status=$?
test "$status" != 0
test "$status" != 124
grep -F 'Writers remain; candidate/code restoration is forbidden' "$CONTROL/linger-update.log"
sha256sum --check --strict "$CONTROL/before-linger.sha256"
test ! -e /opt/kosmozoo/activation-attempt.json
systemctl show kosmozoo -p ActiveState -p SubState -p MainPID -p ControlPID -p ControlGroup > "$CONTROL/lingering-unit.txt"
linger_pid=$(cat "$CONTROL/linger-pid")
test -r "/proc/$linger_pid/cmdline"
tr '\0' ' ' < "/proc/$linger_pid/cmdline" | grep -F /data/native-controls/linger-stop.sh
for n in {1..40}; do
 state=$(systemctl show kosmozoo -p ActiveState --value)
 if test "$(systemctl show kosmozoo -p MainPID --value)" = 0 && [[ "$state" == inactive || "$state" == failed ]]; then break; fi
 sleep 1
done
test "$(systemctl show kosmozoo -p MainPID --value)" = 0
test "$(systemctl show kosmozoo -p ControlPID --value)" = 0
sleep 2
test "$(systemctl show kosmozoo -p MainPID --value)" = 0
sha256sum --check --strict "$CONTROL/linger-inputs.sha256"
rm /etc/systemd/system/kosmozoo.service.d/native-linger.conf
systemctl daemon-reload
systemctl reset-failed kosmozoo
timeout 90 systemctl start kosmozoo
printf 'PASS actual linger blocked candidate publication, retained code/marker and never scheduled later old-code restart\n'
# Check original-disabled enablement using the same real application/write fault.
systemctl disable kosmozoo
rm "$CONTROL/actor-ready"
printf 'disabled\n' > "$CONTROL/actor-mode"
printf '%s\n' '[Service]' 'Restart=no' 'ExecStartPost=/bin/bash /data/native-controls/activation-post.sh' > /etc/systemd/system/kosmozoo.service.d/native-failure.conf
systemctl daemon-reload
status=0; timeout 240 /usr/local/sbin/update --clean > "$CONTROL/original-disabled-failure.log" 2>&1 || status=$?
test "$status" != 0
test "$status" != 124
jq -e '.enabled == false' /opt/kosmozoo/activation-attempt.json
test "$(systemctl show kosmozoo -p MainPID --value)" = 0
sha256sum --check --strict "$CONTROL/fault-inputs.sha256"
rm /etc/systemd/system/kosmozoo.service.d/native-failure.conf
systemctl daemon-reload
timeout 240 /usr/local/sbin/update > "$CONTROL/original-disabled-retry.log" 2>&1
systemctl is-active --quiet kosmozoo
test "$(systemctl is-enabled kosmozoo 2>/dev/null || true)" = disabled
test ! -e /opt/kosmozoo/activation-attempt.json
curl -fsS --max-time 10 http://127.0.0.1/api/collections/recovery/entries/flux-basic.png | tee "$CONTROL/final-entry.json" | jq -e '.judgment.notes.pos == "native-disabled-original-write" and .judgment.bookmark == true'
# Restore only the test's explicit enablement input, after proving disabled stayed disabled.
systemctl enable kosmozoo
test "$(systemctl is-enabled kosmozoo)" = enabled
test "$(stat -c %i /data/state/engine.lock)" = "$(cat "$CONTROL/lock-inode")"
printf 'PASS actual original-disabled retry stayed disabled; only fixture enablement then restored\n'
NATIVEPOST
    timeout 30 pct exec "$ctid" -- cat /data/native-controls/final-entry.json > "$work/native-final-entry.json"
    timeout 30 pct exec "$ctid" -- cat /data/native-controls/corruption.jsonl > "$work/corruption-boundary.jsonl"
    timeout 30 pct exec "$ctid" -- cat /data/native-controls/newer-elf-old-marker-runtime.json > "$work/newer-elf-old-marker-runtime.json"
    timeout 30 pct exec "$ctid" -- env TMPDIR=/data/bootstrap-tmp tar -cf - -C /data native-controls > "$work/native-controls.tar"
    stat -c '%d:%i %u:%g %a %n' "$media_source" "$media_source/flux-basic.png" > "$work/media-after.txt"
    sha256sum "$media_source/flux-basic.png" >> "$work/media-after.txt"
    cmp "$work/media-before.txt" "$work/media-after.txt"
    jq -n --arg source "$(git -C "$ROOT" write-tree)" --arg target "$target" --arg digest "$target_digest" '{status:"failures-passed",source_tree:$source,version:$target,binary_sha256:$digest,checksum_injection:"explicit OS curl seam corrupts bytes only after actual public digest verified",database_rollback:false,actual_reboot:true,actual_updater_crash:true,app_sigkill:false}' > "$work/failures-accepted.json"
    printf 'PASS native scratch failure/boot/retry/linger controls; corruption seam explicitly labeled\n'
    exit 0
  fi
  if [[ "$stage_name" != bootstrap ]]; then
    if [[ "$stage_name" == browser-first || "$stage_name" == browser-resume || "$stage_name" == lifecycle || "$stage_name" == configuration || "$stage_name" == final-consumer ]]; then
      stat -c '%d:%i %u:%g %a %n' "$media_source" "$media_source/flux-basic.png" > "$work/media-before.txt"
      sha256sum "$media_source/flux-basic.png" >> "$work/media-before.txt"
      if [[ "$stage_name" == browser-first || ("$stage_name" == lifecycle && "$acceptance" == installed) ]]; then
        pct set "$ctid" --mp0 "$media_source,mp=/sources/images,ro=1"
      fi
      TMPDIR="$W/tmp" DENO_DIR="$W/cache/deno-fixture" "$W/tools/deno" run --no-config --no-lock --allow-all "$W/fixtures/kosmozoo-v0.2.2/tests/fake-comfy.mjs" --fixtures "$W/fixtures/kosmozoo-v0.2.2/tests/fixtures" --port 8188 > "$work/provider.log" 2>&1 &
      provider=$!
      for _ in {1..30}; do
        curl -fsS --max-time 2 http://10.248.26.1:8188/api/system_stats > "$work/provider-ready.json" && break
        sleep 1
      done
      jq -e '.system.os == "fake"' "$work/provider-ready.json"
      provider_start=$(awk '{print $22}' "/proc/$provider/stat")
      printf 'pid=%s start_ticks=%s\n' "$provider" "$provider_start" > "$work/provider-owner.txt"
    fi
    created=1
    timeout 90 pct start "$ctid"
    for _ in {1..90}; do
      curl -fsS --max-time 2 "http://$ip/api/runtime" > "$work/runtime.json" && break
      sleep 1
    done
    jq -e '.protocol == "kosmozoo-runtime" and .version == 1 and .status == "ready" and .binding.port == 80' "$work/runtime.json"
    cp /etc/hosts "$work/hosts-before"
    printf '\n%s kosmozoo.home # kz-native-%s\n' "$ip" "$ctid" >> /etc/hosts
    hosts_after=$(sha256sum /etc/hosts | cut -d ' ' -f1)
    getent ahostsv4 kosmozoo.home | tee "$work/resolution.txt"
    [[ "$(getent ahostsv4 kosmozoo.home | cut -d ' ' -f1 | sort -u)" == "$ip" ]]
    profile=$(jq -r '.browser_profile // empty' <<< "$ct")
    if [[ -n "$profile" ]]; then
      [[ "$profile" == "$W/browser/profile-$ctid."* && -d "$profile" && ! -L "$profile" && "$(stat -c %u "$profile")" == "$(id -u "$browser_user")" ]] || exit 65
    else
      profile=$(mktemp -d "$W/browser/profile-$ctid.XXXXXXXX")
      chown "$browser_user:$browser_user" "$profile"
    fi
    browser_unit="kz-browser-$ctid-$(date +%s)"
    systemd-run --unit="$browser_unit" --property=Type=exec --property="User=$browser_user" --property=RuntimeMaxSec=3000 --property=TimeoutStopSec=20 --property=MemoryMax=768M --property=MemorySwapMax=0 --property=TasksMax=128 --property="StandardOutput=file:$work/chromium.log" --property=StandardError=inherit --setenv="HOME=$W/browser" --setenv="TMPDIR=$W/btmp" --setenv="XDG_RUNTIME_DIR=$W/brun" /usr/bin/chromium --headless=new --no-first-run --disable-background-networking --disable-component-update --no-proxy-server --window-size=1280,900 --remote-debugging-address=127.0.0.1 --remote-debugging-port=9335 --user-data-dir="$profile" about:blank
    for _ in {1..60}; do
      curl -fsS --max-time 2 http://127.0.0.1:9335/json/version > "$work/cdp.json" && break
      sleep 1
    done
    jq -e '.Browser | startswith("Chrome/")' "$work/cdp.json"
    pid=$(systemctl show "$browser_unit" -p MainPID --value)
    [[ "$pid" =~ ^[1-9][0-9]*$ && "$(stat -c %u "/proc/$pid")" == "$(id -u "$browser_user")" ]]
    tr '\0' '\n' < "/proc/$pid/cmdline" > "$work/browser-argv.txt"
    ! grep -E -- '--no-sandbox|--disable-setuid-sandbox|--unsafely-treat-insecure-origin-as-secure|--host-resolver-rules' "$work/browser-argv.txt" || exit 65
    ss -lntp 'sport = :9335' | tee "$work/cdp-listener.txt"
    ! ss -H -lnt 'sport = :9335' | grep -vF 127.0.0.1:9335 || exit 65
    printf 'pid=%s user=%s profile=%s endpoint=http://127.0.0.1:9335\n' "$pid" "$browser_user" "$profile" > "$work/browser-owner.txt"
    phase=smoke
    [[ "$stage_name" != browser-first ]] || phase=first-run
    [[ "$stage_name" != browser-resume ]] || phase=finish-first-run
    if [[ "$stage_name" == lifecycle || "$stage_name" == configuration || "$stage_name" == final-consumer ]]; then
      [[ "$(jq -r .app.version "$work/runtime.json")" == "$expected_version" ]] || exit 65
      actual_binary=$(timeout 15 pct exec "$ctid" -- sha256sum /opt/kosmozoo/kosmozoo | cut -d ' ' -f1)
      [[ "$actual_binary" == "$expected_binary" ]] || exit 65
      phase=first-run
      [[ "$acceptance" != consumers && "$acceptance" != lifecycle ]] || phase=verify
      if [[ "$stage_name" == final-consumer ]]; then
        phase=verify
        [[ "$(jq -r .role <<< "$ct")" != failure ]] || phase=verify-recovery
      fi
    fi
    native_browser() {
      local p=$1 label=$2 v=$3
      shift 3
      local -a extra=()
      if [[ -n "${baseline_input:-}" ]]; then extra=(--baseline "$baseline_input" --baseline-sha256 "$(sha256sum "$baseline_input" | cut -d ' ' -f1)"); fi
      DENO_DIR="$W/cache/deno-browser" timeout 600 "$W/tools/deno" run --no-config --no-lock --allow-net --allow-read --allow-write --allow-env "$ROOT/tests/maintenance-kosmozoo.browser.mjs" --guard-manifest "$guard" --ctid "$ctid" --origin http://kosmozoo.home --cdp-endpoint http://127.0.0.1:9335 --phase "$p" --label "$label" --evidence "$work/browser" --expected-version "$v" "${extra[@]}" "$@"
    }
    native_provider_check() {
      kill -0 "$provider"
      [[ "$(awk '{print $22}' "/proc/$provider/stat")" == "$provider_start" ]]
      printf '%s pid=%s start_ticks=%s\n' "$(date -u --iso-8601=ns)" "$provider" "$provider_start" >> "$work/provider-continuity.txt"
    }
    native_ready() {
      local name=$1 version=$2 port=${3:-80}
      for _ in {1..90}; do
        if curl -fsS --max-time 2 "http://$ip:$port/api/runtime" > "$work/$name-runtime.json" &&
          jq -e --arg v "$version" --argjson port "$port" '.protocol == "kosmozoo-runtime" and .version == 1 and .status == "ready" and .mode == "serve" and .binding.port == $port and .app.version == $v' "$work/$name-runtime.json" > /dev/null; then return 0; fi
        sleep 1
      done
      return 1
    }
    native_snapshot() {
      local name=$1 init cg path limit found=0 item
      init=$(lxc-info -n "$ctid" -pH)
      [[ "$init" =~ ^[1-9][0-9]*$ ]]
      ct_init_pid=$init
      cg=$(cut -d : -f3 "/proc/$init/cgroup")
      [[ "$cg" == "/lxc/$ctid/"* || "$cg" == "/lxc/$ctid" ]] || {
        printf 'Unexpected owned CT cgroup: %s\n' "$cg" >&2
        return 65
      }
      path="/sys/fs/cgroup$cg"
      while [[ "$path" == /sys/fs/cgroup/* ]]; do
        printf '\n%s\n' "$path"
        for item in memory.current memory.peak memory.max memory.events memory.swap.current memory.swap.peak memory.swap.max memory.swap.events cpu.stat; do
          if [[ -r "$path/$item" ]]; then
            printf '%s=' "$item"
            tr '\n' ';' < "$path/$item"
            printf '\n'
          fi
        done
        limit=$(cat "$path/memory.max")
        if [[ "$limit" == 1073741824 ]]; then
          found=1
          printf '%s\n' "$path" > "$work/effective-ct-cgroup.txt"
        fi
        path=${path%/*}
      done > "$work/$name-parent-cgroups.txt"
      [[ "$found" == 1 ]] || {
        printf 'Actual configured 1GiB CT ancestor not observed\n' >&2
        return 65
      }
      timeout 20 pct exec "$ctid" -- env TMPDIR=/data/bootstrap-tmp EXPECTED_STATE="$state" bash -se > "$work/$name-service.txt" << 'SNAPSHOT'
set -euo pipefail
systemctl show kosmozoo -p MainPID -p ActiveState -p SubState -p ControlGroup
pid=$(systemctl show kosmozoo -p MainPID --value)
cat "/proc/$pid/status"
stat -c '%i' "$EXPECTED_STATE/engine.lock"
sha256sum /opt/kosmozoo/kosmozoo /root/.kosmozoo /etc/kosmozoo/env
df -B1 /
du -s -B1 /opt/kosmozoo /data
SNAPSHOT
    }
    native_process_proof() {
      local cold=$1
      timeout 30 pct exec "$ctid" -- env TMPDIR=/data/bootstrap-tmp EXPECTED_STATE="$state" EXPECTED_CACHE="$cache" EXPECTED_HOSTS="$hosts" EXPECTED_COLD="$cold" bash -se << 'PROCESS'
set -euo pipefail
pid=$(systemctl show kosmozoo -p MainPID --value)
declare -A actual=()
while IFS= read -r -d '' value; do actual[${value%%=*}]=${value#*=}; done < "/proc/$pid/environ"
test "${actual[PATH]}" = /nonexistent
test "${actual[TMPDIR]}" = "$EXPECTED_COLD"
test "${actual[KOZMOZOO_STATE]}" = "$EXPECTED_STATE"
test "${actual[KOZMOZOO_CACHE]}" = "$EXPECTED_CACHE"
test "${actual[KOZMOZOO_HOSTS]+present}" = present
test "${actual[KOZMOZOO_HOSTS]}" = "$EXPECTED_HOSTS"
test "${actual[KZ_ACCEPTANCE_LITERAL]}" = 'operator $ ` % " \ roundtrip'
for key in PATH TMPDIR KOZMOZOO_STATE KOZMOZOO_CACHE KOZMOZOO_HOSTS KOZMOZOO_BIND KOZMOZOO_PORT KZ_ACCEPTANCE_LITERAL; do printf '%s=%s\n' "$key" "${actual[$key]}"; done
findmnt -nr -T /sources/images -o TARGET,FSTYPE,OPTIONS
case ",$(findmnt -nr -T /sources/images -o OPTIONS)," in *,ro,*) ;; *) exit 1 ;; esac
grep -F "$EXPECTED_COLD/deno-native-addons/" "/proc/$pid/maps"
mapfile -t libraries < <(find "$EXPECTED_COLD" -type f -name '*.so')
test "${#libraries[@]}" -gt 0
for library in "${libraries[@]}"; do printf '%s  %s\n' 2e6eef9a727f081f0d453b4e5e6cbd8b9ef8b6f86cbf7681cbad444d3b0b55c8 "$library" | sha256sum --check --strict; done
PROCESS
    }
    if [[ "$stage_name" == lifecycle || "$stage_name" == configuration ]]; then
      native_snapshot before-consumers
      effective_group=$(cat "$work/effective-ct-cgroup.txt")
      (
        printf 'epoch_ms memory_current memory_peak swap_current swap_peak code_bytes data_bytes\n'
        while [[ ! -e "$work/stop-sampler" ]]; do
          [[ -r "$effective_group/memory.current" ]] || break
          # A running CT root is in its mount namespace, not pct mount's offline
          # rootfs directory. Resolve through the positively identified init PID.
          code_bytes=$(du -s -B1 "/proc/$ct_init_pid/root/opt/kosmozoo" | cut -f1) || exit $?
          data_bytes=$(du -s -B1 "/proc/$ct_init_pid/root/data" | cut -f1) || exit $?
          printf '%s %s %s %s %s %s %s\n' "$(date +%s%3N)" "$(cat "$effective_group/memory.current")" "$(cat "$effective_group/memory.peak")" "$(cat "$effective_group/memory.swap.current")" "$(cat "$effective_group/memory.swap.peak")" "$code_bytes" "$data_bytes"
          sleep 0.25
        done
      ) > "$work/resource-timeline.txt" &
      sampler=$!
    fi
    native_browser "$phase" "$ctid-$phase" "$(jq -r .app.version "$work/runtime.json")"
    if [[ "$stage_name" == final-consumer ]]; then
      timeout 30 pct exec "$ctid" -- env TMPDIR=/data/bootstrap-tmp EXPECTED_STATE="$state" bash -se > "$work/current-unit-ownership.txt" << 'CURRENTUNIT'
set -euo pipefail
pid=$(systemctl show kosmozoo -p MainPID --value)
test "$(readlink -f "/proc/$pid/exe")" = /opt/kosmozoo/kosmozoo
test "$(tr '\0' '\n' < "/proc/$pid/cmdline" | paste -sd ' ')" = '/opt/kosmozoo/kosmozoo serve'
ss -H -lntp 'sport = :80' | grep -F "pid=$pid,"
jq -e --argjson pid "$pid" '.ownerPid == $pid' "$EXPECTED_STATE/engine-instance.json"
systemctl is-active kosmozoo
systemctl is-enabled kosmozoo
sha256sum /opt/kosmozoo/kosmozoo
cat /root/.kosmozoo
CURRENTUNIT
      timeout 15 pct exec "$ctid" -- cat "$state/engine-instance.json" > "$work/current-private-instance.json"
      jq -e --slurpfile public "$work/runtime.json" '.instance == $public[0].instance and .binding == $public[0].binding and .sourceVersion == $public[0].sourceVersion' "$work/current-private-instance.json"
      if [[ "$(jq -r .role <<< "$ct")" != failure ]]; then
        output_hash=$(jq -er '.output_sha256' "$(jq -r .acceptance.lifecycle.evidence <<< "$ct")/lifecycle-accepted.json")
        curl -fsS --max-time 10 "http://$ip/api/content/$output_hash/bytes" > "$work/current-prior-output-cache.png"
        [[ "$(sha256sum "$work/current-prior-output-cache.png" | cut -d ' ' -f1)" == "$output_hash" ]]
        native_process_proof /data/native-cold-configuration > "$work/current-native-process.txt"
      fi
      printf 'PASS fresh current native UI/API/export/cache/unit ownership CT%s; prior completed mutations not replayed\n' "$ctid"
    fi
    if [[ "$stage_name" == lifecycle ]]; then
      [[ "$acceptance" != installed ]] || baseline_input="$work/browser/$ctid-accepted.json"
      printf 'Consumer checkpoint: baseline=%s profile=%s\n' "$baseline_input" "$profile" | tee "$work/consumer-checkpoint.txt"
      # Keep one independent provider and one browser profile across every engine
      # operation. Test controls act only on the frozen external provider.
      native_provider_check
      job="native-running-$ctid-$(date +%s)" output_name="native-finished-$ctid.png" output_prefix="native-output-$ctid"
      jq -n --arg job "$job" '{running:[$job],pending:[($job+"-pending")]}' > "$work/job-running-input.json"
      curl -fsS --max-time 10 -H 'Content-Type: application/json' --data-binary "@$work/job-running-input.json" http://10.248.26.1:8188/__test/activity > "$work/provider-running.json"
      curl -fsS --max-time 10 http://10.248.26.1:8188/api/queue | tee "$work/upstream-queue-before.json" | jq -e '.queue_running | length == 1'
      native_browser activity "$ctid-running-before" "$expected_version"
      lock_before=$(timeout 15 pct exec "$ctid" -- stat -c %i "$state/engine.lock")
      restart_begin=$(date +%s%N)
      timeout 120 pct exec "$ctid" -- systemctl restart kosmozoo
      restart_end=$(date +%s%N)
      printf 'restart_elapsed_ns=%s\n' "$((restart_end - restart_begin))" > "$work/drain-times.txt"
      native_ready restarted "$expected_version"
      [[ "$(timeout 15 pct exec "$ctid" -- stat -c %i "$state/engine.lock")" == "$lock_before" ]]
      native_provider_check
      native_browser verify "$ctid-after-restart" "$expected_version"
      native_browser activity "$ctid-running-after-restart" "$expected_version"
      curl -fsSL --connect-timeout 15 --max-time 60 https://api.github.com/repos/alexindigo/kosmozoo/releases/latest > "$work/current-release.json"
      jq -e '.draft == false and .prerelease == false and (.tag_name | test("^v?[0-9]+\\.[0-9]+\\.[0-9]+$")) and ([.assets[] | select(.name == "kosmozoo-linux-x86_64" and (.digest | test("^sha256:[0-9a-f]{64}$")))] | length == 1)' "$work/current-release.json" > /dev/null
      target=$(jq -r '.tag_name | ltrimstr("v")' "$work/current-release.json")
      target_digest=$(jq -r '.assets[] | select(.name == "kosmozoo-linux-x86_64") | .digest | ltrimstr("sha256:")' "$work/current-release.json")
      if [[ "$target" != "$expected_version" ]]; then
        # Operator fixture: retain the original env, add a second real parsed
        # EnvironmentFile and cold disk TMPDIR/PATH. The FIRST actual update is
        # still the normal installed update command, with no release pin/--clean.
        operator_env_digest=$(jq -r '.acceptance.operator_fixture.env_sha256 // empty' <<< "$ct")
        operator_unit_digest=$(jq -r '.acceptance.operator_fixture.dropin_sha256 // empty' <<< "$ct")
        timeout 30 pct exec "$ctid" -- env TMPDIR=/data/bootstrap-tmp CT_IP="$ip" PRIOR_ENV_SHA="$operator_env_digest" PRIOR_UNIT_SHA="$operator_unit_digest" bash -se << 'OPERATOR'
set -euo pipefail
if test -n "$PRIOR_ENV_SHA"; then
  printf '%s  %s\n' "$PRIOR_ENV_SHA" '/etc/kosmozoo/native literal.env' "$PRIOR_UNIT_SHA" /etc/systemd/system/kosmozoo.service.d/native-acceptance.conf | sha256sum --check --strict
  test -d /data/native-cold
  test -z "$(find /data/native-cold -mindepth 1 -print -quit)"
else
  test ! -e '/etc/kosmozoo/native literal.env'
  test ! -e /etc/systemd/system/kosmozoo.service.d/native-acceptance.conf
  test ! -e /data/native-cold
  install -d -m 0700 /data/native-cold
  install -d -m 0755 /etc/systemd/system/kosmozoo.service.d
  grep -E '^KOZMOZOO_(STATE|CACHE|HOSTS)=' /etc/kosmozoo/env > '/etc/kosmozoo/native literal.env'
  printf '%s\n' 'TMPDIR="/data/native-cold"' 'PATH="/nonexistent"' 'KZ_ACCEPTANCE_LITERAL="operator \$ \` % \" \\ roundtrip"' >> '/etc/kosmozoo/native literal.env'
  printf 'KOZMOZOO_BIND="%s"\nKOZMOZOO_PORT="080"\n' "$CT_IP" >> '/etc/kosmozoo/native literal.env'
  chmod 0600 '/etc/kosmozoo/native literal.env'
fi
# systemd257 config_parse_unit_env_file consumes the whole raw absolute path;
# quotes here become path bytes and are rejected. The property transport itself
# accepts the same literal-space filename as one argv item (native probe proven).
printf '%s\n' '[Service]' 'EnvironmentFile=/etc/kosmozoo/native literal.env' > /etc/systemd/system/kosmozoo.service.d/native-acceptance.conf
systemctl daemon-reload
busctl --system --json=short get-property org.freedesktop.systemd1 /org/freedesktop/systemd1/unit/kosmozoo_2eservice org.freedesktop.systemd1.Service EnvironmentFiles | jq -e '.data | any(.[0] == "/etc/kosmozoo/native literal.env")'
OPERATOR
      fi
      timeout 30 pct exec "$ctid" -- env TMPDIR=/data/bootstrap-tmp bash -se > "$work/first-update-os-properties.txt" << 'PROPERTIES'
set -euo pipefail
systemctl is-active dbus.socket dbus.service
dpkg-query -W dbus
for property in TimeoutStopUSec SendSIGKILL EnvironmentFiles; do
  value=$(busctl --system --json=short get-property org.freedesktop.systemd1 /org/freedesktop/systemd1/unit/kosmozoo_2eservice org.freedesktop.systemd1.Service "$property")
  printf '%s=%s\n' "$property" "$value"
  case "$property" in
    TimeoutStopUSec) jq -e '.type == "t" and .data == 45000000' <<< "$value" ;;
    SendSIGKILL) jq -e '.type == "b" and .data == false' <<< "$value" ;;
    EnvironmentFiles) jq -e '.type == "a(sb)" and (.data | any(.[0] == "/etc/kosmozoo/env" and .[1] == false))' <<< "$value" ;;
  esac
done
systemctl cat kosmozoo
sha256sum /etc/kosmozoo/env /etc/systemd/system/kosmozoo.service
if test -f '/etc/kosmozoo/native literal.env'; then sha256sum '/etc/kosmozoo/native literal.env' /etc/systemd/system/kosmozoo.service.d/native-acceptance.conf; fi
PROPERTIES
      timeout 30 pct exec "$ctid" -- env TMPDIR=/data/bootstrap-tmp bash -se > "$work/update-before-identities.txt" << 'IDENTITIES'
set -euo pipefail
systemctl show kosmozoo -p MainPID --value
stat -c '%d:%i %u:%g %a %n' /opt/kosmozoo/kosmozoo /root/.kosmozoo /etc/kosmozoo/env /etc/systemd/system/kosmozoo.service
sha256sum /opt/kosmozoo/kosmozoo /root/.kosmozoo /etc/kosmozoo/env /etc/systemd/system/kosmozoo.service
if test -f '/etc/kosmozoo/native literal.env'; then stat -c '%d:%i %u:%g %a %n' '/etc/kosmozoo/native literal.env' /etc/systemd/system/kosmozoo.service.d/native-acceptance.conf; sha256sum '/etc/kosmozoo/native literal.env' /etc/systemd/system/kosmozoo.service.d/native-acceptance.conf; fi
IDENTITIES
      update_begin=$(date +%s%N)
      timeout --signal=TERM --kill-after=60 1800 pct exec "$ctid" -- env HOME=/root TMPDIR=/data/bootstrap-tmp PHS_SILENT=1 UNATTENDED=1 TERM=xterm /usr/local/sbin/update > "$work/plain-update.log" 2>&1
      update_end=$(date +%s%N)
      printf 'plain_update_elapsed_ns=%s\n' "$((update_end - update_begin))" >> "$work/drain-times.txt"
      native_ready updated "$target"
      actual_binary=$(timeout 15 pct exec "$ctid" -- sha256sum /opt/kosmozoo/kosmozoo | cut -d ' ' -f1)
      [[ "$actual_binary" == "$target_digest" ]]
      [[ "$(timeout 15 pct exec "$ctid" -- cat /root/.kosmozoo)" == "$target" ]]
      [[ "$(timeout 15 pct exec "$ctid" -- stat -c %i "$state/engine.lock")" == "$lock_before" ]]
      native_provider_check
      native_snapshot after-plain-update
      timeout 30 pct exec "$ctid" -- env TMPDIR=/data/bootstrap-tmp bash -se > "$work/update-after-identities.txt" << 'IDENTITIES'
set -euo pipefail
systemctl show kosmozoo -p MainPID --value
stat -c '%d:%i %u:%g %a %n' /opt/kosmozoo/kosmozoo /root/.kosmozoo /etc/kosmozoo/env /etc/systemd/system/kosmozoo.service
sha256sum /opt/kosmozoo/kosmozoo /root/.kosmozoo /etc/kosmozoo/env /etc/systemd/system/kosmozoo.service
if test -f '/etc/kosmozoo/native literal.env'; then stat -c '%d:%i %u:%g %a %n' '/etc/kosmozoo/native literal.env' /etc/systemd/system/kosmozoo.service.d/native-acceptance.conf; sha256sum '/etc/kosmozoo/native literal.env' /etc/systemd/system/kosmozoo.service.d/native-acceptance.conf; fi
IDENTITIES
      if [[ "$target" == "$expected_version" ]]; then
        cmp "$work/update-before-identities.txt" "$work/update-after-identities.txt"
        cmp "$work/restarted-runtime.json" "$work/updated-runtime.json"
        printf 'PASS actual normal no-op: PID, ELF/marker bytes+inodes and unit/env unchanged\n'
      else
        grep -E '/etc/(kosmozoo/|systemd/system/)' "$work/update-before-identities.txt" > "$work/operator-before.txt"
        grep -E '/etc/(kosmozoo/|systemd/system/)' "$work/update-after-identities.txt" > "$work/operator-after.txt"
        cmp "$work/operator-before.txt" "$work/operator-after.txt"
        native_process_proof /data/native-cold > "$work/cold-native-process.txt"
      fi
      native_browser verify "$ctid-after-update" "$target"
      native_browser activity "$ctid-running-after-update" "$target"
      jq -n --arg job "$job" --arg name "$output_name" --arg prefix "$output_prefix" '{running:[],pending:[],finish:[{id:$job,output:$name,width:640,height:360,graphPrefix:$prefix}]}' > "$work/job-finish-input.json"
      curl -fsS --max-time 10 -H 'Content-Type: application/json' --data-binary "@$work/job-finish-input.json" http://10.248.26.1:8188/__test/activity > "$work/provider-finished.json"
      curl -fsS --max-time 10 "http://10.248.26.1:8188/api/view?filename=$output_name" > "$work/provider-output.png"
      output_digest=$(sha256sum "$work/provider-output.png" | cut -d ' ' -f1)
      native_browser output "$ctid-final-output" "$target" --keep-page yes --output "$output_name" --output-sha256 "$output_digest" --output-prefix "$output_prefix"
      native_provider_check
      known_hash=$(jq -er '.rows.remote.hash' "$baseline_input")
      nft insert rule inet kz_native inbound ip saddr "$ip" tcp dport 8188 reject comment 'kz-known-cache-offline'
      handle=$(nft -j -a list chain inet kz_native inbound | jq -er '.nftables[].rule? | select(.comment == "kz-known-cache-offline") | .handle')
      offline_status=0
      timeout 15 pct exec "$ctid" -- curl --fail --silent --max-time 5 http://10.248.26.1:8188/api/system_stats > "$work/offline-source.txt" 2>&1 || offline_status=$?
      [[ "$offline_status" == 7 || "$offline_status" == 28 ]]
      curl -fsS --max-time 10 "http://$ip/api/content/$known_hash/bytes" > "$work/offline-known-cache.png"
      [[ "$(sha256sum "$work/offline-known-cache.png" | cut -d ' ' -f1)" == "$known_hash" ]]
      nft delete rule inet kz_native inbound handle "$handle"
      printf 'PASS known cached content bytes while source actually unreachable; no offline inventory claim\n'
      native_snapshot after-output
      native_provider_check
      jq -n --arg baseline "$baseline_input" --arg baseline_sha "$(sha256sum "$baseline_input" | cut -d ' ' -f1)" --arg profile "$profile" --arg version "$target" --arg digest "$target_digest" --arg output "$output_digest" --arg source "$(git -C "$ROOT" write-tree)" '{status:"lifecycle-passed",source_tree:$source,baseline:{path:$baseline,sha256:$baseline_sha},profile:$profile,version:$version,binary_sha256:$digest,output_sha256:$output}' > "$work/lifecycle-accepted.json"
      printf 'PASS native lifecycle CT%s: plain update/no-op, same-profile persistence, independent remote output, known offline cache\n' "$ctid"
    fi
    if [[ "$stage_name" == configuration ]]; then
      lock_before=$(timeout 15 pct exec "$ctid" -- stat -c %i "$state/engine.lock")
      timeout 30 pct exec "$ctid" -- env TMPDIR=/data/bootstrap-tmp CT_IP="$ip" bash -se << 'CONFIGURATION'
set -euo pipefail
test ! -e '/etc/kosmozoo/native configuration.env'
test ! -e /etc/systemd/system/kosmozoo.service.d/native-configuration.conf
test ! -e /data/native-cold-configuration
install -d -m 0700 /data/native-cold-configuration
install -d -m 0755 /etc/systemd/system/kosmozoo.service.d
grep -E '^KOZMOZOO_(STATE|CACHE|HOSTS)=' /etc/kosmozoo/env > '/etc/kosmozoo/native configuration.env'
printf '%s\n' 'TMPDIR="/data/native-cold-configuration"' 'PATH="/nonexistent"' 'KZ_ACCEPTANCE_LITERAL="operator \$ \` % \" \\ roundtrip"' >> '/etc/kosmozoo/native configuration.env'
printf 'KOZMOZOO_BIND="%s"\nKOZMOZOO_PORT="80"\n' "$CT_IP" >> '/etc/kosmozoo/native configuration.env'
chmod 0600 '/etc/kosmozoo/native configuration.env'
printf '%s\n' '[Service]' 'EnvironmentFile=/etc/kosmozoo/native configuration.env' > /etc/systemd/system/kosmozoo.service.d/native-configuration.conf
systemctl daemon-reload
systemctl restart kosmozoo
CONFIGURATION
      native_ready configuration-cold "$expected_version"
      native_process_proof /data/native-cold-configuration > "$work/configuration-cold-process.txt"
      native_browser verify "$ctid-configuration-cold" "$expected_version"
      if [[ "$configuration_port" != 80 ]]; then
        timeout 20 pct exec "$ctid" -- env TMPDIR=/data/bootstrap-tmp TEST_PORT="$configuration_port" bash -se << 'PORT'
set -euo pipefail
printf 'KOZMOZOO_PORT="%s"\n' "$TEST_PORT" >> '/etc/kosmozoo/native configuration.env'
systemctl daemon-reload
for property in TimeoutStopUSec SendSIGKILL EnvironmentFiles; do
  busctl --system --json=short get-property org.freedesktop.systemd1 /org/freedesktop/systemd1/unit/kosmozoo_2eservice org.freedesktop.systemd1.Service "$property"
done
test ! -e /data/configuration-inputs.sha256
sha256sum /etc/kosmozoo/env /etc/systemd/system/kosmozoo.service '/etc/kosmozoo/native literal.env' /etc/systemd/system/kosmozoo.service.d/native-acceptance.conf '/etc/kosmozoo/native configuration.env' /etc/systemd/system/kosmozoo.service.d/native-configuration.conf > /data/configuration-inputs.sha256
PORT
        timeout --signal=TERM --kill-after=60 1800 pct exec "$ctid" -- env HOME=/root TMPDIR=/data/bootstrap-tmp PHS_SILENT=1 UNATTENDED=1 TERM=xterm /usr/local/sbin/update --clean > "$work/operator-port-update.log" 2>&1
        native_ready nonstandard-port "$expected_version" "$configuration_port"
        jq -e --arg bind "$ip" --argjson port "$configuration_port" '.configuredBind == $bind and .binding.hostname == $bind and .binding.port == $port' "$work/nonstandard-port-runtime.json"
        timeout 20 pct exec "$ctid" -- env TMPDIR=/data/bootstrap-tmp TEST_PORT="$configuration_port" bash -se > "$work/nonstandard-port-ownership.txt" << 'PORTOWNERSHIP'
set -euo pipefail
sha256sum --check --strict /data/configuration-inputs.sha256
pid=$(systemctl show kosmozoo -p MainPID --value)
test "$(readlink -f "/proc/$pid/exe")" = /opt/kosmozoo/kosmozoo
ss -H -lntp "sport = :$TEST_PORT" | grep -F "pid=$pid,"
test -z "$(ss -H -lnt 'sport = :80')"
printf '%s\n' 'KOZMOZOO_PORT="80"' >> '/etc/kosmozoo/native configuration.env'
systemctl daemon-reload
systemctl restart kosmozoo
PORTOWNERSHIP
        native_ready restored-http80 "$expected_version"
        native_browser verify "$ctid-after-operator-port" "$expected_version"
      fi
      [[ "$(timeout 15 pct exec "$ctid" -- stat -c %i "$state/engine.lock")" == "$lock_before" ]]
      native_snapshot after-configuration
      native_provider_check
      jq -n --arg version "$expected_version" --arg port "$configuration_port" --arg baseline "$baseline_input" --arg profile "$profile" '{status:"configuration-passed",version:$version,tested_port:$port,baseline:$baseline,profile:$profile}' > "$work/configuration-accepted.json"
      printf 'PASS native cold runtime/explicit HOSTS process and operator port configuration CT%s\n' "$ctid"
    fi
    if [[ "$stage_name" == browser-first || "$stage_name" == browser-resume || "$stage_name" == lifecycle || "$stage_name" == configuration || "$stage_name" == final-consumer ]]; then
      stat -c '%d:%i %u:%g %a %n' "$media_source" "$media_source/flux-basic.png" > "$work/media-after.txt"
      sha256sum "$media_source/flux-basic.png" >> "$work/media-after.txt"
      cmp "$work/media-before.txt" "$work/media-after.txt"
    fi
    timeout 30 pct exec "$ctid" -- env TMPDIR=/data/bootstrap-tmp EXPECTED_STATE="$state" bash -se > "$work/resource-consumer.txt" << 'RESOURCES'
set -euo pipefail
for path in /sys/fs/cgroup /sys/fs/cgroup/system.slice/kosmozoo.service; do
  for item in memory.current memory.peak memory.max memory.events memory.swap.current memory.swap.peak memory.swap.max memory.swap.events cpu.stat; do
    printf '\n%s/%s\n' "$path" "$item"
    if test -r "$path/$item"; then cat "$path/$item"; else printf 'unavailable\n'; fi
  done
done
pid=$(systemctl show kosmozoo -p MainPID --value)
cat "/proc/$pid/status"
du -s -B1 /opt/kosmozoo /data /data/tmp
df -B1 /
stat -c '%d:%i %u:%g %a %n' "$EXPECTED_STATE/engine.lock"
RESOURCES
    printf 'PASS %s CT%s; complete native failure/resource acceptance remains separate\n' "$stage_name" "$ctid"
    exit 0
  fi
  # Resource inputs remain unset: these are actual 2CPU/1024MiB/4GiB defaults.
  export mode=default PHS_SILENT=1 UNATTENDED=1 TERM=xterm
  export var_ctid="$ctid" var_hostname="$hostname" var_mac="$mac" var_brg=vmbrkz24
  export var_net="$ip/24" var_gateway=10.248.26.1 var_ns='-nameserver 192.168.122.1' var_ipv6_method=none
  export var_container_storage=local-lvm var_template_storage=local var_ssh=no
  export var_gpu=no INSTALL_NVIDIA_DRIVERS=no var_timezone=UTC var_verbose=yes
  export var_lxc_tmpdir=/data/bootstrap-tmp REPO_BASE=http://10.248.26.1:8089
  export KOZMOZOO_STATE="$state" KOZMOZOO_CACHE="$cache" KOZMOZOO_HOSTS="$hosts"
  export var_lxc_kosmozoo_initial_release="$initial"
  created=1
  native_install_watch > "$work/install-resource-timeline.txt" &
  sampler=$!
  timeout --signal=TERM --kill-after=60 1800 bash "$ROOT/scripts/lxc/kosmozoo.sh" < /dev/null > "$work/install.log" 2>&1
  pct config "$ctid" | tee "$work/actual-config.txt"
  grep -qiF "hwaddr=$mac" "$work/actual-config.txt"
  grep -qxF "hostname: $hostname" "$work/actual-config.txt"
  grep -qxF 'cores: 2' "$work/actual-config.txt"
  grep -qxF 'memory: 1024' "$work/actual-config.txt"
  grep -qE '^rootfs: local-lvm:vm-[0-9]+-disk-0,size=4G$' "$work/actual-config.txt"
  lvs --reportformat json --units b --nosuffix -o lv_name,lv_uuid,lv_size "/dev/pve/vm-$ctid-disk-0" > "$work/actual-lv.json"
  fs_uuid=$(blkid -s UUID -o value "/dev/pve/vm-$ctid-disk-0")
  [[ "$fs_uuid" == "$(cat "$work/creation-fs-uuid.txt")" ]]
  [[ "$(jq -r .report[0].lv[0].lv_uuid "$work/actual-lv.json")" == "$(jq -r .report[0].lv[0].lv_uuid "$work/creation-lv.json")" ]]
  timeout 90 pct exec "$ctid" -- env TMPDIR=/data/bootstrap-tmp bash -se > "$work/native-inspection.txt" << 'CT'
set -euo pipefail
id
test "$(id -u)" = 0
test "$(systemctl show kosmozoo -p User --value)" = root
systemctl is-enabled kosmozoo
systemctl is-active kosmozoo dbus.socket dbus.service
dpkg-query -W dbus dbus-daemon dbus-system-bus-common
for property in TimeoutStopUSec SendSIGKILL EnvironmentFiles; do
  busctl --system --json=short get-property org.freedesktop.systemd1 /org/freedesktop/systemd1/unit/kosmozoo_2eservice org.freedesktop.systemd1.Service "$property"
done
systemctl cat kosmozoo
systemctl show kosmozoo -p MainPID -p ControlGroup -p ExecStart -p EnvironmentFiles
pid=$(systemctl show kosmozoo -p MainPID --value)
test "$(readlink -f "/proc/$pid/exe")" = /opt/kosmozoo/kosmozoo
test "$(tr '\0' '\n' < "/proc/$pid/cmdline" | paste -sd ' ')" = '/opt/kosmozoo/kosmozoo serve'
ss -lntp 'sport = :80'
sha256sum /opt/kosmozoo/kosmozoo
/opt/kosmozoo/kosmozoo --version
cat /root/.kosmozoo
cat /etc/kosmozoo/env
cat "/proc/$pid/status"
grep deno-native-addons "/proc/$pid/maps"
df -B1 / /data
findmnt -rn -T /data -o TARGET,SOURCE,FSTYPE,UUID,OPTIONS
# Python is already in the Debian template for OS tooling. Inventory it honestly;
# the app-only no-runtime-on-PATH cold proof is a separate process-environment gate.
command -v 'python3' || true
for command in deno node docker chromium; do
  if command -v "$command"; then printf 'Unexpected app runtime: %s\n' "$command" >&2; exit 1; fi
done
CT
  curl -fsS --max-time 10 "http://$ip/api/runtime" | tee "$work/runtime.json" | jq -e '.protocol == "kosmozoo-runtime" and .version == 1 and .mode == "serve" and .status == "ready" and .binding.port == 80'
  curl -fsS --max-time 10 "http://$ip/" > "$work/index.html"
  curl -fsS --max-time 10 "http://$ip/api/collections" | tee "$work/collections.json"
  df -B1 "$W" > "$work/root-after.txt"
  lvs --units b --nosuffix -o lv_name,lv_uuid,lv_size,data_percent,metadata_percent,lv_active > "$work/storage-after.txt"
  jq -n --argjson ctid "$ctid" --arg lv "$(jq -r .report[0].lv[0].lv_uuid "$work/actual-lv.json")" --arg fs "$fs_uuid" --arg source "$(git -C "$ROOT" write-tree)" --arg version "$(jq -r .app.version "$work/runtime.json")" --arg evidence "$work" '{status:"bootstrap-passed",ctid:$ctid,ownership:{lv_uuid:$lv,filesystem_uuid:$fs},source_tree:$source,version:$version,evidence:$evidence}' > "$work/bootstrap-accepted.json"
  printf 'PASS native full bootstrap CT%s; HTTP and typed OS bus consumer; NOT browser/update/failure acceptance\n' "$ctid"
  exit 0
fi

work=$(mktemp -d "$W/artifacts/kosmozoo-native.XXXXXXXX")
printf 'Evidence: %s\n' "$work"
failures=0
check() {
  if [[ "$1" == "$2" ]]; then printf 'PASS %s\n' "$3"; else
    printf 'FAIL %s: expected <%s>, got <%s>\n' "$3" "$2" "$1" >&2
    failures=$((failures + 1))
  fi
}

# Source definitions without fetching/executing the bootstrap. Only _write_bundle
# exports each hook; no script-global helper accompanies it into the cold shell.
curl() { :; }
source "$ROOT/scripts/lxc/kosmozoo.sh"
unset -f curl
source "$ROOT/misc/bundle.func"
export APP=Kosmozoo NSAPP=kosmozoo REPO_BASE=https://fixture.invalid
export var_lxc_tmpdir=/data/testtmp
initial_bridge=$(env -i PATH="$PATH" var_appversion=0.2.1 bash -c 'curl() { :; }; source "$1"; printf "%s" "$var_lxc_kosmozoo_initial_release"' _ "$ROOT/scripts/lxc/kosmozoo.sh")
check "$initial_bridge" 0.2.1 'actual host var_appversion becomes the install-only bundle bridge'

for scenario in install initial-pin marker install-literal install-future-folder install-hosts-omitted install-hosts-mutated install-hosts-process-unset install-dbus-package install-dbus-socket install-dbus-query install-publish install-record install-stage-permission install-invalid-path install-invalid-seed install-invalid-hosts-relative install-invalid-hosts-empty install-invalid-hosts-control install-invalid-hosts-duplicate install-plugin-collision install-temp-collision install-env-publish install-unit-write install-daemon-reload update dbus-missing dbus-envfiles no-op checker-error download digest missing-digest metadata version version-dev version-target stage-create stage-permission old-copy old-marker-copy conditional-old-copy environment-probe record-write conditional-record-write record-mode publish record start readiness marker-update enable boot-verify disable stop-linger stop-error stop-override stop-short poststart-linger cleanup stage-cleanup floor corrupt newer-elf newer-elf-old-pin marker-ahead normalized-floor retry-stopped disabled-retry old-layout disabled-entry custom-env default-env empty-state-env overlap-env repeat-download repeat-digest repeat-version repeat-prestart prior-floor-prestart prestart-recovery-fail prestart-fact-restore-fail prestart-retire-fail; do
  c="$work/$scenario"
  mkdir -p "$c/root/"{usr,etc/systemd/system,opt,root,var/log,var/lib,data/testtmp,data/state,data/cache,data/plugins,data/tmp,proc,dev,sys,fixture}
  ln -s usr/bin "$c/root/bin"
  ln -s usr/sbin "$c/root/sbin"
  ln -s usr/lib "$c/root/lib"
  ln -s usr/lib64 "$c/root/lib64"
  mknod "$c/root/dev/null" c 1 3
  mknod "$c/root/dev/urandom" c 1 9
  ln -s /proc/self/fd "$c/root/dev/fd"
  chmod 0666 "$c/root/dev/"{null,urandom}
  printf 'owned isolated fixture\n' > "$c/root/fixture/owned"
  cp "$0" "$c/root/fixture/test.sh"
  cp /usr/bin/sleep "$c/root/fixture/new"
  printf '\nNEW\n' >> "$c/root/fixture/new"
  cp /usr/bin/sleep "$c/root/fixture/old"
  printf '\nOLD\n' >> "$c/root/fixture/old"
  sha256sum "$c/root/fixture/new" | cut -d ' ' -f1 > "$c/root/fixture/digest"
  var_lxc_kosmozoo_state=/data/state var_lxc_kosmozoo_cache=/data/cache var_lxc_kosmozoo_hosts=''
  var_lxc_kosmozoo_initial_release=latest
  [[ "$scenario" != initial-pin ]] || var_lxc_kosmozoo_initial_release=0.2.1
  [[ "$scenario" != install-invalid-path ]] || var_lxc_kosmozoo_state=/data/cache
  [[ "$scenario" != install-invalid-seed ]] || var_lxc_kosmozoo_hosts=typo
  [[ "$scenario" != install-plugin-collision ]] || var_lxc_kosmozoo_state=/data/plugins
  [[ "$scenario" != install-temp-collision ]] || var_lxc_kosmozoo_cache=/data/tmp
  [[ "$scenario" != install-future-folder ]] || var_lxc_kosmozoo_hosts='local=folder:/sources/images'
  case "$scenario" in
    install-invalid-hosts-relative) var_lxc_kosmozoo_hosts='local=folder:relative' ;;
    install-invalid-hosts-empty) var_lxc_kosmozoo_hosts='local=folder:/sources/images,' ;;
    install-invalid-hosts-control) var_lxc_kosmozoo_hosts=$'local=folder:/sources/images\n' ;;
    install-invalid-hosts-duplicate) var_lxc_kosmozoo_hosts='local=folder:/sources/images,local=host:8188' ;;
  esac
  if [[ "$scenario" == install-literal ]]; then
    var_lxc_kosmozoo_state='/data/state literal $ ` % " \ end'
    var_lxc_kosmozoo_cache='/data/cache "quoted"'
    var_lxc_kosmozoo_hosts='images=folder:/source literal $ ` % " \ end'
    mkdir -p "$c/root/source literal \$ \` % \" \\ end"
  fi
  _write_bundle install install_script "$ROOT/misc" 'source /fixture/models.sh' 'install_script' > "$c/root/fixture/install.sh"
  _write_bundle update update_script "$ROOT/misc" 'source /fixture/models.sh' 'run_update_script' > "$c/root/fixture/update.sh"
  cat > "$c/root/fixture/models.sh" << 'SH'
STD='' VERBOSE=no
msg_info() { :; }
msg_ok() { printf 'OK %s\n' "$*"; }
msg_error() { printf 'ERROR %s\n' "$*" >&2; }
render_header() { :; }
header_info() { :; }
check_container_storage() { :; }
check_container_resources() { :; }
cleanup_lxc() { :; }
if [[ "${CONDITIONAL:-0}" == 1 ]]; then
  execute_optional_hook() { if "$@"; then return 0; else return $?; fi; }
fi
get_system_arch() { printf amd64; }
apt() {
  printf 'MODELED apt %s\n' "$*" >> /fixture/events
  [[ "$FAULT" != dbus-package ]] || return 80
  case " $* " in *' dbus '*) printf installed > /fixture/os-dbus ;; esac
}
sleep() { SECONDS=$((SECONDS + 100)); }
_gh_release_json() {
  printf 'select %s\n' "$2" >> /fixture/events
  [[ "$FAULT" != checker-error ]] || return 98
  local v=${2#v} digest id=200 n=0
  [[ "$v" != latest ]] || v=0.2.2
  [[ ! -f /fixture/selections ]] || n=$(cat /fixture/selections)
  n=$((n + 1)); printf '%s' "$n" > /fixture/selections
  [[ "$FAULT" != metadata || "$n" -lt 3 ]] || id=201
  digest=$(cat /fixture/digest)
  [[ "$v" != 0.2.1 ]] || digest=$(sha256sum /fixture/old | cut -d ' ' -f1)
  [[ "$FAULT" != missing-digest ]] || digest=''
  jq -n --arg tag "v$v" --arg digest "$digest" --argjson id "$id" '{id:100,tag_name:$tag,draft:false,prerelease:false,published_at:"2026-10-20T08:49:44Z",
    assets:[{id:$id,name:"kosmozoo-linux-x86_64",size:100,digest:("sha256:"+$digest),browser_download_url:("https://github.com/alexindigo/kosmozoo/releases/download/"+$tag+"/kosmozoo-linux-x86_64")}]}' > "$4"
}
curl_download() {
  printf 'download %s\n' "$(cat /fixture/active)" >> /fixture/events
  [[ "$FAULT" != download ]] || return 41
  if [[ "$2" == */v0.2.1/* ]]; then command cp /fixture/old "$1"; else command cp /fixture/new "$1"; fi
  [[ "$FAULT" != digest && "$FAULT" != prestart-retire-fail ]] || printf 'BAD' >> "$1"
}
ensure_dependencies() { :; }
getent() { return 0; }
busctl() {
  printf 'MODELED getter %s\n' "$*" >> /fixture/events
  # Accept only the real documented standard-bus invocation, with its optional
  # explicit --system selector. Never treat arbitrary last-argument flags as a getter.
  [[ "${1:-}" != --system ]] || shift
  [[ $# == 6 && "$1" == --json=short && "$2" == get-property && "$3" == org.freedesktop.systemd1 ]] || return 97
  if [[ "$4" == /org/freedesktop/systemd1 && "$5" == org.freedesktop.systemd1.Manager && "$6" == Version ]]; then
    [[ "$(cat /fixture/os-dbus)" == active && "$FAULT" != dbus-query ]] || return 82
    printf '{"type":"s","data":"257.13-model"}'; return 0
  fi
  [[ "$4" == /org/freedesktop/systemd1/unit/kosmozoo_2eservice && "$5" == org.freedesktop.systemd1.Service ]] || return 97
  [[ "$FAULT" != dbus-missing ]] || { printf 'transport unavailable\n' >&2; return 83; }
  [[ "$FAULT" != dbus-envfiles || "$6" != EnvironmentFiles ]] || { printf 'transport unavailable\n' >&2; return 84; }
  case "${!#}" in
    TimeoutStopUSec) if [[ "$FAULT" == stop-short ]]; then printf '{"type":"t","data":1000000}'; else printf '{"type":"t","data":45000000}'; fi ;;
    SendSIGKILL) if [[ "$FAULT" == stop-override ]]; then printf '{"type":"b","data":true}'; else printf '{"type":"b","data":false}'; fi ;;
    EnvironmentFiles) printf '{"type":"a(sb)","data":[["/etc/kosmozoo/env",false]]}' ;;
    *) return 65 ;;
  esac
}
systemd-run() { [[ "$FAULT" != environment-probe ]] || return 72; cat /fixture/environment; }
mktemp() { [[ "$FAULT" != stage-create || "${!#}" != /opt/kosmozoo/.stage.* ]] || return 66; command mktemp "$@"; }
chmod() {
  [[ "$FAULT" != stage-permission || "$1" != 0700 || "${!#}" != /opt/kosmozoo/.stage.* ]] || return 67
  [[ "$FAULT" != record-mode || "${!#}" != */attempt.json ]] || return 71
  command chmod "$@"
}
cp() {
  [[ "$FAULT" != old-copy || "${!#}" != */previous ]] || return 68
  [[ "$FAULT" != old-marker-copy || "${!#}" != */marker ]] || return 69
  command cp "$@"
}
install() {
  [[ "$FAULT" != env-publish ]] || return 73
  command install "$@" || return $?
  if [[ "${!#}" == /etc/kosmozoo/env ]]; then
    if [[ "$FAULT" == hosts-omitted ]]; then
      sed -i '/^KOZMOZOO_HOSTS=/d' /etc/kosmozoo/env
    elif [[ "$FAULT" == hosts-mutated ]]; then
      sed -i 's/^KOZMOZOO_HOSTS=.*/KOZMOZOO_HOSTS="unexpected=elsewhere:8188"/' /etc/kosmozoo/env
    fi
    if ! grep -q '^KOZMOZOO_HOSTS=' /etc/kosmozoo/env; then
      local entry
      while IFS= read -r -d '' entry; do
        [[ "$entry" == KOZMOZOO_HOSTS=* ]] || printf '%s\0' "$entry"
      done < /fixture/environment > /fixture/no-hosts
      command mv /fixture/no-hosts /fixture/environment
    fi
  fi
}
cat() {
  local caller=$BASHPID target
  target=$(readlink "/proc/$caller/fd/1")
  [[ "$FAULT" != unit-write || "$target" != /etc/systemd/system/kosmozoo.service ]] || return 74
  command cat "$@"
}
jq() {
  local caller=$BASHPID target
  target=$(readlink "/proc/$caller/fd/1")
  [[ "$FAULT" != record-write || "$target" != */attempt.json ]] || return 70
  command jq "$@"
}
timeout() {
  if [[ "${!#}" == --version ]]; then
    local -a a=("$@")
    local binary=${a[${#a[@]}-2]} v=${PIN:-0.2.2} identity=' (2172670)' target=x86_64-unknown-linux-gnu
    [[ "$binary" != /opt/kosmozoo/kosmozoo ]] || v=0.2.2
    cmp -s "$binary" /fixture/old && v=${CURRENT_VERSION:-0.2.1}
    [[ "$FAULT" != version || "$binary" == /opt/kosmozoo/kosmozoo ]] || v=0.2.21
    [[ "$FAULT" != version-dev ]] || identity=-dev
    [[ "$FAULT" != version-target || "$binary" == /opt/kosmozoo/kosmozoo ]] || target=aarch64-unknown-linux-gnu
    printf 'kosmozoo v%s%s (input 1d4ab9b2ea1db4884a627cc0970a87447ceb4424cc0166a838c57984cd2291ea; Deno 2.9.6; %s)\n' "$v" "$identity" "$target"
    return 0
  fi
  while (($#)); do
    case "$1" in systemctl) shift; systemctl "$@"; return $? ;; systemd-run) shift; systemd-run "$@"; return $? ;; busctl) shift; busctl "$@"; return $? ;; esac
    shift
  done
  return 65
}
systemctl() {
  printf 'systemctl %s\n' "$*" >> /fixture/events
  if [[ "${!#}" == dbus.socket ]]; then
    case "$1" in
      is-active) [[ "$(cat /fixture/os-dbus)" == active ]] ;;
      start) [[ "$FAULT" != dbus-socket ]] || return 81; [[ "$(cat /fixture/os-dbus)" == installed ]] || return 85; printf active > /fixture/os-dbus ;;
      *) return 97 ;;
    esac
    return $?
  fi
  local p=0 property=${4:-} active
  [[ ! -f /fixture/pid ]] || p=$(cat /fixture/pid)
  active=$(cat /fixture/active)
  case "$1" in
    show)
      case "$property" in
        ExecStart) printf '{ path=/opt/kosmozoo/kosmozoo ; argv[]=/opt/kosmozoo/kosmozoo serve ; ignore_errors=no ; }' ;;
        User) printf root ;;
        MainPID) printf '%s' "$p" ;;
        ActiveState) printf '%s' "$active" ;;
        ControlGroup) : ;;
        Environment | PassEnvironment | UnsetEnvironment) : ;;
        *) : ;;
      esac ;;
    is-enabled)
      [[ "$FAULT" != boot-verify || ! -e /fixture/activated ]] || { printf disabled; return 1; }
      cat /fixture/enabled; [[ "$(cat /fixture/enabled)" == enabled ]] ;;
    is-active) [[ "$active" == active ]] ;;
    daemon-reload) [[ "$FAULT" != daemon-reload ]] || return 76 ;;
    enable) [[ "$FAULT" != enable ]] || return 51; printf enabled > /fixture/enabled ;;
    disable) [[ "$FAULT" != disable ]] || return 52; printf disabled > /fixture/enabled ;;
    stop)
      if [[ "$FAULT" == stop-linger ]] || { [[ "$FAULT" == poststart-linger ]] && cmp -s /fixture/new /opt/kosmozoo/kosmozoo; }; then printf deactivating > /fixture/active; return 53; fi
      if [[ "$p" != 0 ]]; then kill -TERM "$p" 2>/dev/null || true; fi
      printf 0 > /fixture/pid
      printf inactive > /fixture/active
      [[ "$FAULT" != stop-error ]] || return 54 ;;
    start)
      if [[ "$FAULT" == prestart-recovery-fail && -e /fixture/publication-failed ]]; then printf failed > /fixture/active; printf 0 > /fixture/pid; return 86; fi
      if [[ "$FAULT" == start ]]; then printf failed > /fixture/active; printf 0 > /fixture/pid; printf 'candidate touched state\n' >> /data/state/user; return 55; fi
      local -a runtime_env=()
      local setting runtime_state runtime_home=/data runtime_xdg='' runtime_bind=0.0.0.0 runtime_port=2084
      while IFS= read -r -d '' setting; do
        [[ "$FAULT" != hosts-process-unset || "$setting" != KOZMOZOO_HOSTS=* ]] || continue
        runtime_env+=("$setting")
        case "$setting" in
          HOME=*) runtime_home=${setting#*=} ;; XDG_STATE_HOME=*) runtime_xdg=${setting#*=} ;;
          KOZMOZOO_STATE=*) runtime_state=${setting#*=} ;; KOZMOZOO_BIND=*) runtime_bind=${setting#*=} ;; KOZMOZOO_PORT=*) runtime_port=${setting#*=} ;;
        esac
      done < /fixture/environment
      runtime_state=${runtime_state:-${runtime_xdg:-$runtime_home/.local/state}/kosmozoo}
      mkdir -p "$runtime_state"
      env -i PATH=/usr/bin:/bin "${runtime_env[@]}" /opt/kosmozoo/kosmozoo 900 &
      p=$!
      if cmp -s /fixture/new /opt/kosmozoo/kosmozoo; then : > /fixture/activated; fi
      printf '%s' "$p" > /fixture/pid
      command sleep 0.03
      printf active > /fixture/active
      while [[ ${#runtime_port} -gt 1 && "$runtime_port" == 0* ]]; do runtime_port=${runtime_port#0}; done
      jq -n --argjson pid "$p" --arg bind "$runtime_bind" --argjson port "$runtime_port" --arg version "${PIN:-0.2.2}" '{protocol:"kosmozoo-runtime",version:1,instance:"00000000-0000-4000-8000-000000000001",sourceVersion:"fixture",mode:"serve",status:"ready",binding:{hostname:$bind,port:$port},configuredBind:$bind,app:{version:$version,revision:"2172670"},ownerPid:$pid}' > "$runtime_state/engine-instance.json"
      cp "$runtime_state/engine-instance.json" /fixture/runtime.json
      chmod 0600 "$runtime_state/engine-instance.json" ;;
    *) return 65 ;;
  esac
}
curl() {
  [[ "$FAULT" != readiness && "$FAULT" != disable && "$FAULT" != poststart-linger ]] || return 56
  local port
  port=$(jq -er .binding.port /fixture/runtime.json)
  [[ "${!#}" == "http://127.0.0.1:$port/api/runtime" ]] || return 57
  jq 'del(.ownerPid)' /fixture/runtime.json
}
ss() { printf 'LISTEN 0 128 0.0.0.0:%s *:* users:(("kosmozoo",pid=%s,fd=3))\n' "$(jq -er .binding.port /fixture/runtime.json)" "$(cat /fixture/pid)"; }
mv() {
  local dest=${!#}
  case "$FAULT:$dest" in
    publish:/opt/kosmozoo/kosmozoo | prestart-recovery-fail:/opt/kosmozoo/kosmozoo | prestart-fact-restore-fail:/opt/kosmozoo/kosmozoo) : > /fixture/publication-failed; return 61 ;;
    record:/opt/kosmozoo/activation-attempt.json) return 62 ;;
    marker:/root/.kosmozoo | marker-update:/root/.kosmozoo) return 63 ;;
  esac
  [[ "$FAULT" != prestart-fact-restore-fail || "$*" != *restore-attempt* ]] || return 87
  command mv "$@"
}
rm() {
  [[ "$FAULT" != cleanup || "${!#}" != /opt/kosmozoo/activation-attempt.json ]] || return 64
  [[ "$FAULT" != stage-cleanup || "${!#}" != /opt/kosmozoo/.stage.* ]] || return 75
  [[ "$FAULT" != prestart-retire-fail || "${!#}" != /opt/kosmozoo/.stage.* ]] || return 77
  command rm "$@"
}
SH
  cat > "$c/root/fixture/scenario.sh" << 'SH'
set -euo pipefail
scenario=$SCENARIO
export FAULT=none PIN='' CURRENT_VERSION=0.2.1
: > /fixture/events
printf inactive > /fixture/active
printf enabled > /fixture/enabled
printf 0 > /fixture/pid
printf active > /fixture/os-dbus
case "$scenario" in install* | marker | initial-pin) printf missing > /fixture/os-dbus ;; esac
printf 'user state\n' > /data/state/user
printf 'user cache\n' > /data/cache/user
chown 1234:1234 /data/cache/user
protected_before=$(stat -c '%d:%i:%a:%u:%g' /data/state /data/cache /data/cache/user)
mount_before=$(grep ' /data/cache ' /proc/self/mountinfo)
printf '%s\0' HOME=/data TMPDIR=/data/tmp KOZMOZOO_STATE=/data/state KOZMOZOO_CACHE=/data/cache KOZMOZOO_BIND=0.0.0.0 KOZMOZOO_PORT=80 KOZMOZOO_HOSTS= KOZMOZOO_PLUGINS=/data/plugins > /fixture/environment
if [[ "$scenario" == custom-env ]]; then printf '%s\0' HOME=/data TMPDIR=/data/tmp XDG_STATE_HOME=/data/alternate KOZMOZOO_BIND=127.0.0.1 KOZMOZOO_PORT=00018081 > /fixture/environment; fi
if [[ "$scenario" == default-env ]]; then printf '%s\0' HOME=/data TMPDIR=/data/tmp > /fixture/environment; fi
if [[ "$scenario" == empty-state-env ]]; then printf '%s\0' HOME=/data TMPDIR=/data/tmp KOZMOZOO_STATE= XDG_STATE_HOME=/data/alternate > /fixture/environment; fi
if [[ "$scenario" == overlap-env ]]; then printf '%s\0' HOME=/data TMPDIR=/data/tmp KOZMOZOO_STATE=/data/state KOZMOZOO_CACHE=/data/state > /fixture/environment; fi
source /fixture/models.sh
if [[ "$scenario" != install* && "$scenario" != marker && "$scenario" != initial-pin ]]; then
  mkdir -p /opt/kosmozoo /etc/kosmozoo
  if [[ "$scenario" == no-op || "$scenario" == newer-elf* ]]; then cp /fixture/new /opt/kosmozoo/kosmozoo; else cp /fixture/old /opt/kosmozoo/kosmozoo; fi
  printf '0.2.1\n' > /root/.kosmozoo
  printf 'OPERATOR ENV MUST SURVIVE\n' > /etc/kosmozoo/env
  printf 'OPERATOR UNIT MUST SURVIVE\n' > /etc/systemd/system/kosmozoo.service
  operator_metadata=$(stat -c '%d:%i:%a:%u:%g:%y' /etc/kosmozoo/env /etc/systemd/system/kosmozoo.service)
  systemctl start kosmozoo
fi
invoke() {
  local kind=$1 status=0
  env -i PATH=/usr/sbin:/usr/bin:/bin HOME=/root TMPDIR=/data/testtmp LOCAL_IP=127.0.0.1 FAULT="$FAULT" PIN="$PIN" UPDATE_FORCE="${FORCE:-0}" \
    var_appversion="$PIN" CURRENT_VERSION="$CURRENT_VERSION" CONDITIONAL="${CONDITIONAL:-0}" \
    bash "/fixture/$kind.sh" > "/fixture/$kind-$FAULT-output" 2>&1 || status=$?
  printf '%s\n' "$status" > /fixture/status
}
case "$scenario" in
  install-literal) FAULT=start ;;
  install-env-publish) FAULT=env-publish ;;
  install-unit-write) FAULT=unit-write ;;
  install-daemon-reload) FAULT=daemon-reload ;;
  install-hosts-omitted) FAULT=hosts-omitted ;;
  install-hosts-mutated) FAULT=hosts-mutated ;;
  install-hosts-process-unset) FAULT=hosts-process-unset ;;
  install-dbus-package) FAULT=dbus-package ;;
  install-dbus-socket) FAULT=dbus-socket ;;
  install-dbus-query) FAULT=dbus-query ;;
  install-publish) FAULT=publish ;;
  install-record) FAULT=record ;;
  install-stage-permission) FAULT=stage-permission ;;
  install-future-folder) FAULT=start ;;
  install-invalid-path | install-invalid-seed | install-plugin-collision | install-temp-collision) : ;;
  initial-pin) PIN=0.2.1 ;;
  no-op) printf '0.2.2\n' > /root/.kosmozoo ;;
  corrupt) printf 'bad json\n' > /opt/kosmozoo/activation-attempt.json; chmod 0600 /opt/kosmozoo/activation-attempt.json ;;
  old-layout) rm /opt/kosmozoo/kosmozoo; printf 'branch:main\n' > /root/.kosmozoo ;;
  newer-elf) : ;;
  newer-elf-old-pin) PIN=0.2.1 ;;
  marker-ahead) printf '0.3.0\n' > /root/.kosmozoo ;;
  normalized-floor) CURRENT_VERSION=0.2 PIN=0.2.0; printf '0.2\n' > /root/.kosmozoo ;;
  disabled-entry) printf disabled > /fixture/enabled ;;
  floor | retry-stopped) FAULT=start ;;
  disabled-retry) printf disabled > /fixture/enabled; FAULT=start ;;
  conditional-old-copy) FAULT=old-copy; CONDITIONAL=1 ;;
  conditional-record-write) FAULT=record-write; CONDITIONAL=1 ;;
  repeat-download) FAULT=download ;;
  repeat-digest) FAULT=digest ;;
  repeat-version) FAULT=version ;;
  repeat-prestart) FAULT=publish ;;
  prior-floor-prestart | prestart-fact-restore-fail) FAULT=start ;;
  update | install | custom-env | default-env | empty-state-env | overlap-env) : ;;
  *) FAULT=$scenario ;;
esac
if [[ "$scenario" == no-op ]]; then
  entry_pid=$(cat /fixture/pid)
  entry_code_marker=$(stat -c '%d:%i:%a:%u:%g:%y' /opt/kosmozoo/kosmozoo /root/.kosmozoo)
fi
case "$scenario" in install* | marker | initial-pin) invoke install ;; *) invoke update ;; esac
case "$scenario" in
  repeat-download | repeat-digest | repeat-version | repeat-prestart)
    case "$scenario" in repeat-download) primary=250 ;; repeat-prestart) primary=61 ;; *) primary=65 ;; esac
    for repeat in 1 2 3; do
      test "$(cat /fixture/status)" = "$primary"
      test "$(find /opt/kosmozoo -mindepth 1 -maxdepth 1 -name '.stage.*' | wc -l)" = 0
      test ! -e /opt/kosmozoo/activation-attempt.json
      test "$(cat /fixture/active)" = active
      invoke update
    done ;;
  prior-floor-prestart | prestart-fact-restore-fail)
    test "$(cat /fixture/status)" != 0
    cp /opt/kosmozoo/activation-attempt.json /fixture/prior-fact
    prior_root=$(jq -er .recovery /fixture/prior-fact)
    prior_metadata=$(stat -c '%d:%i:%a:%u:%g' "$prior_root")
    prior_files=$(find "$prior_root" -type f -exec sha256sum {} + | sort)
    if [[ "$scenario" == prior-floor-prestart ]]; then
      for repeat in 1 2; do
        FAULT=record invoke update
        test "$(cat /fixture/status)" = 62
        cmp /fixture/prior-fact /opt/kosmozoo/activation-attempt.json
        test "$(find /opt/kosmozoo -mindepth 1 -maxdepth 1 -name '.stage.*' | wc -l)" = 1
      done
    fi
    if [[ "$scenario" == prior-floor-prestart ]]; then FAULT=publish; else FAULT=prestart-fact-restore-fail; fi
    invoke update
    test "$(cat /fixture/status)" = 61
    test "$prior_files" = "$(find "$prior_root" -type f -exec sha256sum {} + | sort)"
    test "$prior_metadata" = "$(stat -c '%d:%i:%a:%u:%g' "$prior_root")"
    if [[ "$scenario" == prior-floor-prestart ]]; then
      cmp /fixture/prior-fact /opt/kosmozoo/activation-attempt.json
      test "$(find /opt/kosmozoo -mindepth 1 -maxdepth 1 -name '.stage.*' | wc -l)" = 1
      FAULT=none PIN=0.2.1 invoke update
      test "$(cat /fixture/status)" = 65
      cmp /fixture/prior-fact /opt/kosmozoo/activation-attempt.json
      test "$(stat -c '%u:%a' /opt/kosmozoo/activation-attempt.json)" = 0:600
      FAULT=none PIN='' invoke update
      test "$(cat /fixture/status)" = 0
      test "$prior_files" = "$(find "$prior_root" -type f -exec sha256sum {} + | sort)"
      test "$(find /opt/kosmozoo -mindepth 1 -maxdepth 1 -name '.stage.*' | wc -l)" = 1
    else
      test "$(find /opt/kosmozoo -mindepth 1 -maxdepth 1 -name '.stage.*' | wc -l)" = 2
      test "$(jq -er .release /opt/kosmozoo/activation-attempt.json)" = 0.2.2
    fi ;;
esac
case "$scenario" in
  install-invalid-seed | install-invalid-hosts-*) grep -q '^ERROR Invalid KOZMOZOO_HOSTS:' /fixture/install-"$FAULT"-output ;;
  install-future-folder) test ! -e /sources/images ;;
esac
case "$scenario" in
  floor)
    test -f /opt/kosmozoo/activation-attempt.json
    test "$(cat /fixture/active)" = inactive
    test "$(cat /fixture/enabled)" = disabled
    count=$(grep -c '^download ' /fixture/events)
    PIN=0.2.1 FAULT=none invoke update
    test "$(cat /fixture/status)" != 0
    test "$(cat /fixture/active)" = inactive
    test "$(grep -c '^download ' /fixture/events)" = "$count"
    PIN='' FAULT=none invoke update ;;
  retry-stopped)
    FAULT=download invoke update
    test "$(cat /fixture/active)" = inactive
    test "$(cat /fixture/enabled)" = disabled
    FAULT=digest invoke update
    test "$(cat /fixture/active)" = inactive
    FAULT=none invoke update ;;
  initial-pin)
    test "$(cat /fixture/status)" = 0
    test "$(cat /root/.kosmozoo)" = 0.2.1
    cmp /fixture/old /opt/kosmozoo/kosmozoo
    PIN=''; invoke update ;;
  disabled-retry) FAULT=none invoke update ;;
esac
case "$scenario" in
  install | initial-pin | update | no-op | newer-elf | disabled-entry | floor | retry-stopped | disabled-retry | version-dev | custom-env | default-env | empty-state-env | normalized-floor | prior-floor-prestart)
    test "$(cat /fixture/status)" = 0
    test "$(cat /root/.kosmozoo)" = "${PIN:-0.2.2}"
    test ! -e /opt/kosmozoo/activation-attempt.json
    if [[ "$scenario" == disabled-entry || "$scenario" == disabled-retry ]]; then test "$(cat /fixture/enabled)" = disabled; else test "$(cat /fixture/enabled)" = enabled; fi ;;
  marker | install-literal | install-future-folder | install-hosts-process-unset | start | readiness | marker-update | enable | boot-verify)
    test "$(cat /fixture/status)" != 0
    test "$(cat /fixture/active)" = inactive
    test "$(cat /fixture/enabled)" = disabled
    test -f /opt/kosmozoo/activation-attempt.json
    if [[ "$scenario" != marker && "$scenario" != install* ]]; then
      cmp /fixture/old /opt/kosmozoo/kosmozoo
      test "$(cat /root/.kosmozoo)" = 0.2.1
    fi ;;
  disable | poststart-linger)
    test "$(cat /fixture/status)" != 0
    cmp /fixture/new /opt/kosmozoo/kosmozoo
    test -f /opt/kosmozoo/activation-attempt.json ;;
  cleanup | stage-cleanup)
    test "$(cat /fixture/status)" != 0
    test "$(cat /fixture/active)" = active
    test "$(cat /root/.kosmozoo)" = 0.2.2
    cmp /fixture/new /opt/kosmozoo/kosmozoo ;;
  install-invalid* | install-plugin-collision | install-temp-collision) test "$(cat /fixture/status)" != 0; ! grep -q '^MODELED apt ' /fixture/events || exit 1 ;;
  install-env-publish | install-unit-write | install-daemon-reload)
    test "$(cat /fixture/status)" != 0
    test "$(cat /fixture/active)" = inactive
    test ! -e /root/.kosmozoo
    test ! -e /opt/kosmozoo/activation-attempt.json ;;
  install-hosts-omitted | install-hosts-mutated | install-dbus-package | install-dbus-socket | install-dbus-query | install-publish | install-record | install-stage-permission)
    test "$(cat /fixture/status)" != 0
    ! grep -q '^systemctl start kosmozoo' /fixture/events || exit 1
    test ! -e /root/.kosmozoo
    test ! -e /opt/kosmozoo/activation-attempt.json
    case "$scenario" in install-dbus-package) test "$(cat /fixture/status)" = 80 ;; install-dbus-socket) test "$(cat /fixture/status)" = 81 ;; install-dbus-query) test "$(cat /fixture/status)" = 82 ;; install-publish) test "$(cat /fixture/status)" = 61 ;; install-record) test "$(cat /fixture/status)" = 62 ;; install-stage-permission) test "$(cat /fixture/status)" = 67 ;; esac ;;
  prestart-recovery-fail | prestart-fact-restore-fail) test "$(cat /fixture/status)" = 61 ;;
  prestart-retire-fail) test "$(cat /fixture/status)" = 65; test "$(find /opt/kosmozoo -mindepth 1 -maxdepth 1 -name '.stage.*' | wc -l)" = 1 ;;
  dbus-missing | dbus-envfiles)
    if [[ "$scenario" == dbus-missing ]]; then test "$(cat /fixture/status)" = 83; else test "$(cat /fixture/status)" = 84; fi
    grep -Eq '^ERROR Cannot read .*dbus.socket.*dbus.service' /fixture/update-"$FAULT"-output
    ! grep -Eq '^select |^download |^MODELED apt |^systemctl (start|stop) dbus' /fixture/events || exit 1
    ! grep -q '^systemctl stop kosmozoo' /fixture/events || exit 1 ;;
  marker-ahead) test "$(cat /fixture/status)" != 0; test "$(cat /root/.kosmozoo)" = 0.3.0 ;;
  overlap-env) test "$(cat /fixture/status)" != 0; ! grep -q '^systemctl stop ' /fixture/events || exit 1; cmp /fixture/old /opt/kosmozoo/kosmozoo ;;
  *) test "$(cat /fixture/status)" != 0; test "$(cat /root/.kosmozoo)" = 0.2.1 || test "$scenario" = old-layout ;;
esac
case "$scenario" in
  install-invalid* | install-plugin-collision | install-temp-collision | install-dbus-* | install-stage-permission | dbus-missing | dbus-envfiles | corrupt | old-layout | stop-override | stop-short | stage-create | stage-permission) ! grep -q '^select ' /fixture/events || exit 1 ;;
  marker-ahead | newer-elf-old-pin) grep -q '^select ' /fixture/events; ! grep -q '^download ' /fixture/events || exit 1 ;;
  no-op | checker-error) grep -q '^select ' /fixture/events ;;
  missing-digest) grep -q '^select ' /fixture/events; ! grep -q '^download ' /fixture/events || exit 1 ;;
  *) grep -q '^download ' /fixture/events ;;
esac
case "$scenario" in install | initial-pin | marker | install-literal | install-future-folder | install-hosts-*)
  grep -Eq '^MODELED apt install .* dbus( |$)' /fixture/events
  test "$(cat /fixture/os-dbus)" = active ;;
esac
case "$scenario" in
  checker-error | download | digest | missing-digest | metadata | version | version-target | stage-permission | old-copy | old-marker-copy | conditional-old-copy | environment-probe | record-write | conditional-record-write | record-mode | publish | record | stop-error | repeat-download | repeat-digest | repeat-version | repeat-prestart | install-env-publish | install-unit-write | install-daemon-reload | install-hosts-omitted | install-hosts-mutated | install-publish | install-record | install-stage-permission)
    test "$(find /opt/kosmozoo -mindepth 1 -maxdepth 1 -name '.stage.*' | wc -l)" = 0
    test ! -e /opt/kosmozoo/activation-attempt.json ;;
esac
case "$scenario" in
  no-op)
    test "$(cat /fixture/pid)" = "$entry_pid"
    test "$(stat -c '%d:%i:%a:%u:%g:%y' /opt/kosmozoo/kosmozoo /root/.kosmozoo)" = "$entry_code_marker"
    ! grep -Eq '^download |^systemctl stop ' /fixture/events || exit 1 ;;
  checker-error | download | digest | missing-digest | metadata | version | version-target | stage-create | stage-permission | old-copy | old-marker-copy | conditional-old-copy | environment-probe | record-write | conditional-record-write | record-mode | publish | record | stop-error)
    test "$(cat /fixture/active)" = active
    cmp /fixture/old /opt/kosmozoo/kosmozoo ;;
esac
case "$scenario" in start | floor | retry-stopped | disabled-retry | prior-floor-prestart | prestart-fact-restore-fail) grep -Fxq 'candidate touched state' /data/state/user ;; esac
if [[ "$scenario" != install* && "$scenario" != marker && "$scenario" != initial-pin ]]; then
  if [[ "$(cat /fixture/status)" == 0 ]]; then
    test ! -e /var/lib/scripts-underground/update-pending/kosmozoo
  else
    test -f /var/lib/scripts-underground/update-pending/kosmozoo
  fi
fi
if [[ "$scenario" != install* && "$scenario" != marker && "$scenario" != initial-pin ]]; then
  test "$(cat /etc/kosmozoo/env)" = 'OPERATOR ENV MUST SURVIVE'
  test "$(cat /etc/systemd/system/kosmozoo.service)" = 'OPERATOR UNIT MUST SURVIVE'
  test "$(stat -c '%d:%i:%a:%u:%g:%y' /etc/kosmozoo/env /etc/systemd/system/kosmozoo.service)" = "$operator_metadata"
fi
grep -Fxq 'user state' /data/state/user
test "$(cat /data/cache/user)" = 'user cache'
test "$(stat -c '%d:%i:%a:%u:%g' /data/state /data/cache /data/cache/user)" = "$protected_before"
test "$(grep ' /data/cache ' /proc/self/mountinfo)" = "$mount_before"
printf 'PASS isolated cold bundles: %s; systemd/network/apt/CLI-version MODELED\n' "$scenario"
SH
  rc=0
  export c scenario
  unshare --mount --pid --fork --propagation private bash -c '
    set -euo pipefail
    mount --bind /usr "$c/root/usr"
    mount -o remount,bind,ro "$c/root/usr"
    mount -t proc proc "$c/root/proc"
    mount --bind "$c/root/data/cache" "$c/root/data/cache"
    cd "$c/root/fixture"
    env -i PATH=/usr/sbin:/usr/bin:/bin HOME=/root TMPDIR=/data/testtmp SCENARIO="$scenario" \
      chroot "$c/root" /bin/bash /fixture/test.sh --fixture-child
  ' > "$c/output" 2>&1 || rc=$?
  check "$rc" 0 "$scenario cold hook/files/process/recovery outcome"
  if [[ "$scenario" == install-literal ]]; then
    timeout 20 systemd-run --quiet --wait --pipe --collect --service-type=exec "--unit=kosmozoo-native-env-$$-$RANDOM" \
      "--property=EnvironmentFile=$c/root/etc/kosmozoo/env" /usr/bin/env -0 > "$c/parsed-environment"
    parsed_state='' parsed_cache='' parsed_hosts=''
    while IFS= read -r -d '' item; do
      case "$item" in KOZMOZOO_STATE=*) parsed_state=${item#*=} ;; KOZMOZOO_CACHE=*) parsed_cache=${item#*=} ;; KOZMOZOO_HOSTS=*) parsed_hosts=${item#*=} ;; esac
    done < "$c/parsed-environment"
    check "$parsed_state" "$var_lxc_kosmozoo_state" 'real systemd parser: literal STATE punctuation'
    check "$parsed_cache" "$var_lxc_kosmozoo_cache" 'real systemd parser: literal CACHE quotes'
    check "$parsed_hosts" "$var_lxc_kosmozoo_hosts" 'real systemd parser: literal HOSTS seed'
  fi
done

if [[ "$hooks_only" == 1 ]]; then
  printf '%s failure(s); Kosmozoo focused cold hooks only; standalone ELF proof retained separately\n' "$failures"
  [[ "$failures" == 0 ]]
  exit
fi

# Actual published ELF, cold disk temp, embedded SQLite/VFS/HTTP consumers. This
# is deliberately a standalone loopback process, not an LXC/systemd acceptance.
native="$work/standalone"
mkdir -p "$native/"{home,tmp-first,tmp-second,tmp-seed-empty,tmp-seed,tmp-seed-retained,state,seed-state,cache,plugins,source}
active_state="$native/state" active_hosts=''
base64 -d > "$native/source/pixel.png" <<< 'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+a9e8AAAAASUVORK5CYII='
file "$elf" > "$native/file.txt"
readelf -lW -dW -VW "$elf" > "$native/readelf.txt"
KOZMOZOO_REVISION=deadbee env -i PATH=/nonexistent HOME="$native/home" TMPDIR="$native/tmp-first" "$elf" --version > "$native/version.txt"
grep -Ex 'kosmozoo v0\.2\.2( \([0-9a-f]{7}\)|-dev) \(input ([0-9a-f]{64}|working-source); Deno 2\.9\.6; x86_64-unknown-linux-gnu\)' "$native/version.txt"
[[ -z "$(ss -H -lnt 'sport = :18080')" ]] || exit 65
pid=''
stop_native() {
  [[ -n "$pid" ]] || return 0
  local end=$((SECONDS + 45)) status=0
  kill -TERM "$pid" || return $?
  while kill -0 "$pid" 2> /dev/null; do
    ((SECONDS < end)) || {
      printf 'Standalone PID %s did not drain; retained evidence\n' "$pid" >&2
      return 1
    }
    sleep 0.1
  done
  wait "$pid" || status=$?
  pid=''
  return "$status"
}
trap 'stop_native' EXIT
start_native() {
  local temp=$1 end=$((SECONDS + 90))
  env -i PATH=/nonexistent HOME="$native/home" TMPDIR="$temp" KOZMOZOO_STATE="$active_state" KOZMOZOO_CACHE="$native/cache" \
    KOZMOZOO_HOSTS="$active_hosts" KOZMOZOO_PLUGINS="$native/plugins" KOZMOZOO_BIND=127.0.0.1 KOZMOZOO_PORT=18080 \
    "$elf" serve > "$native/engine-${temp##*/}.log" 2>&1 &
  pid=$!
  while :; do
    if curl --noproxy '*' --fail --silent --max-time 2 http://127.0.0.1:18080/api/runtime > "$native/runtime.json" &&
      jq -e '.protocol == "kosmozoo-runtime" and .version == 1 and .status == "ready" and .mode == "serve" and .app.version == "0.2.2" and .binding == {hostname:"127.0.0.1",port:18080}' "$native/runtime.json" > /dev/null; then break; fi
    kill -0 "$pid" || return 1
    ((SECONDS < end)) || return 1
    sleep 0.2
  done
  jq -e --argjson pid "$pid" --slurpfile runtime "$native/runtime.json" '.ownerPid == $pid and .instance == $runtime[0].instance' "$active_state/engine-instance.json" > /dev/null
  ss -H -lntp 'sport = :18080' | grep -Fq "pid=$pid,"
  [[ "$(readlink "/proc/$pid/exe")" == "$elf" ]]
  grep -F "$temp/deno-native-addons/" "/proc/$pid/maps" > "$native/sqlite-${temp##*/}-maps.txt"
  grep -E '^(VmRSS|VmHWM|VmSwap|Threads):' "/proc/$pid/status" > "$native/process-${temp##*/}.txt"
}
start_native "$native/tmp-first"
first_nonce=$(jq -er .instance "$native/runtime.json")
curl --noproxy '*' --fail --silent --max-time 2 http://127.0.0.1:18080/api/collections | jq -e 'length == 0'
jq -n --arg address "folder:$native/source" '{name:"native",address:$address}' > "$native/source.json"
curl --noproxy '*' --fail --silent --max-time 2 -H 'Content-Type: application/json' --data-binary "@$native/source.json" http://127.0.0.1:18080/api/collections > "$native/collection.json"
curl --noproxy '*' --fail --silent --max-time 2 http://127.0.0.1:18080/api/collections/native/entries/pixel.png/bytes > "$native/served.png"
cmp "$native/source/pixel.png" "$native/served.png"
curl --noproxy '*' --fail --silent --max-time 2 -X PATCH -H 'Content-Type: application/json' --data '{"vote":"up","favorite":true,"bookmark":true,"notes":{"pos":"native SQLite persistence"}}' http://127.0.0.1:18080/api/collections/native/entries/pixel.png/judgment > "$native/judgment.json"
curl --noproxy '*' --fail --silent --max-time 2 http://127.0.0.1:18080/ > "$native/index.html"
grep -q '<html' "$native/index.html"
test -s "$native/state/metadata.db"
image_hash=$(sha256sum "$native/source/pixel.png" | cut -d ' ' -f1)
cmp "$native/source/pixel.png" "$native/cache/${image_hash:0:2}/$image_hash"
stop_native
start_native "$native/tmp-second"
[[ "$(jq -er .instance "$native/runtime.json")" != "$first_nonce" ]]
curl --noproxy '*' --fail --silent --max-time 2 http://127.0.0.1:18080/api/collections/native/entries/pixel.png | jq -e '.judgment.vote == "up" and .judgment.favorite == true and .judgment.bookmark == true and .judgment.notes.pos == "native SQLite persistence"'
curl --noproxy '*' --fail --silent --max-time 2 "http://127.0.0.1:18080/api/content/$image_hash/bytes" > "$native/restarted.png"
cmp "$native/source/pixel.png" "$native/restarted.png"
stop_native
active_state="$native/seed-state"
start_native "$native/tmp-seed-empty"
curl --noproxy '*' --fail --silent --max-time 2 http://127.0.0.1:18080/api/collections | jq -e 'length == 0'
stop_native
active_hosts="seed=folder:$native/source"
start_native "$native/tmp-seed"
curl --noproxy '*' --fail --silent --max-time 2 http://127.0.0.1:18080/api/collections | jq -e 'keys == ["seed"]'
stop_native
active_hosts="ignored=folder:$native/source"
start_native "$native/tmp-seed-retained"
curl --noproxy '*' --fail --silent --max-time 2 http://127.0.0.1:18080/api/collections | jq -e 'keys == ["seed"]'
stop_native
trap - EXIT
printf 'PASS actual HOSTS: empty default, configured seed on later empty-table boot, nonempty persisted sources win\n'
printf 'PASS actual v0.2.2 ELF: ABI/version, embedded SQLite/VFS/HTTP, image/cache bytes and restarted judgments; no installed runtime on PATH; NOT LXC/browser proof\n'
printf '%s failure(s); Kosmozoo native focused hooks plus standalone published ELF\n' "$failures"
[[ "$failures" == 0 ]]
