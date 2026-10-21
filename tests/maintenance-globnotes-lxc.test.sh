#!/usr/bin/env bash
# Native acceptance runs only in the explicitly owned PVE guest. No generic CT harness.
set -euo pipefail

ctid='' origin='' cdp='' evidence='' guard_manifest='' fixture_role='' stage=all native=0
run_id="$(date -u +%Y%m%dT%H%M%S)-$$"
while (($#)); do
  case "$1" in
    --native)
      native=1
      shift
      ;;
    --guard-manifest)
      guard_manifest=${2:?--guard-manifest requires an absolute JSON file}
      shift 2
      ;;
    --ctid)
      ctid=$2
      shift 2
      ;;
    --origin)
      origin=$2
      shift 2
      ;;
    --cdp)
      cdp=$2
      shift 2
      ;;
    --evidence)
      evidence=$2
      shift 2
      ;;
    --stage)
      stage=$2
      shift 2
      ;;
    --role)
      fixture_role=$2
      shift 2
      ;;
    *)
      printf 'Unknown argument: %s\n' "$1" >&2
      exit 64
      ;;
  esac
done
if [[ "$guard_manifest" != /* || ! -f "$guard_manifest" ]]; then
  printf 'Required --guard-manifest <absolute JSON file> missing or unreadable; no effects performed.\n' >&2
  exit 64
fi
[[ "$native" == 1 && "$EUID" == 0 && "$origin" == http://globnotes.home && "$cdp" == http://127.0.0.1:9335 ]]
repo=$(realpath -- "$(dirname -- "${BASH_SOURCE[0]}")/..")
# Data only: no shell evaluation, commands or implicit delivery files in the guard.
# This preflight is read-only, including dependency/source/protection checks.
verify_guard() {
  python3 - "$guard_manifest" "$repo" "$ctid" "$evidence" << 'PY'
import hashlib,json,os,pathlib,re,shutil,sqlite3,stat,subprocess,sys
gpath,repo,ctid,evidence=sys.argv[1:];r=pathlib.Path(repo)
def require(ok,message):
    if not ok: raise SystemExit('Native guard: '+message)
def absolute(value):
    require(isinstance(value,str) and value.startswith('/') and '\n' not in value,'absolute path required')
    require(str(pathlib.Path(value).resolve())==value,'canonical path required: '+value)
    return pathlib.Path(value)
def checked_file(item):
    require(set(item)=={'path','sha256'},'file reference schema')
    p=absolute(item['path']);require(p.is_file(),'missing declared file: '+str(p))
    require(hashlib.sha256(p.read_bytes()).hexdigest()==item['sha256'],'declared file hash mismatch: '+str(p))
    return p
def command(*args):return subprocess.check_output(args,text=True,close_fds=True).strip()
try:
 require(pathlib.Path(gpath).stat().st_uid==0 and pathlib.Path(gpath).stat().st_mode&0o022==0,'guard must be root-owned and not group/world writable')
 g=json.loads(pathlib.Path(gpath).read_text())
 require(set(g)=={'version','workspace','source','vm','protected','fixtures'},'top-level schema')
 require(g['version']==1,'unsupported schema version')
 for tool in ['git','jq','pct','lvs','dmsetup','findmnt','flock','curl','systemctl','systemd-run','chromium','runuser','ss','getent','timeout','lxc-info','lxc-ls','sha256sum','df','free','du','stat','cmp','realpath','blkid','cp','mkdir','cat','tr','sed','grep','cut','ps','install','chown']:
    require(shutil.which(tool) is not None,'missing dependency: '+tool)
 w=absolute(g['workspace']);require(w.is_dir() and w.stat().st_uid==0,'workspace ownership')
 require(os.environ.get('TMPDIR')==str(w/'tmp') and (w/'tmp').is_dir(),'disk-backed TMPDIR')
 require(r==w/'source' and r.stat().st_uid==g['source']['uid'],'source path/ownership')
 e=absolute(evidence);require(e.is_relative_to(w/'artifacts') and e!=w/'artifacts','evidence containment')
 vm=g['vm'];require(set(vm)=={'uuid','root_uuid','serial','disk_bytes'},'VM schema')
 require(pathlib.Path('/sys/class/dmi/id/product_uuid').read_text().strip()==vm['uuid'],'VM UUID mismatch')
 require(command('findmnt','-nro','UUID','/')==vm['root_uuid'],'root filesystem UUID mismatch')
 require(pathlib.Path('/sys/class/block/vda/serial').read_text().strip()==vm['serial'],'disk serial mismatch')
 require(int(pathlib.Path('/sys/class/block/vda/size').read_text())*512==vm['disk_bytes'],'disk size mismatch')
 require(command('findmnt','-nro','FSTYPE','-T',str(w)) not in ['tmpfs','ramfs'],'workspace must be disk-backed')
 require(set(g['source'])=={'tree','uid'},'source schema')
 git=['git','-c','safe.directory='+repo,'-C',repo]
 # Compute the index tree without write-tree (which may create objects before admission).
 rows=subprocess.check_output(git+['ls-files','--stage','-z']).split(b'\0');tree={}
 oids=[row.split(b' ',2)[1] for row in rows if row]
 objects=subprocess.check_output(git+['cat-file','--batch-check'],input=b'\n'.join(oids)+b'\n').splitlines()
 require(len(objects)==len(oids) and all(len(line.split())==3 and line.split()[1]==b'blob' for line in objects),'missing Git index blob dependency')
 for row in rows:
    if not row:continue
    meta,path=row.split(b'\t',1);mode,oid,stage=meta.split();require(stage==b'0','unmerged index')
    p=r/os.fsdecode(path);require(p.exists() or p.is_symlink(),'missing indexed file: '+str(p))
    kind=p.lstat().st_mode
    require((mode==b'120000' and stat.S_ISLNK(kind)) or (mode in [b'100644',b'100755'] and stat.S_ISREG(kind)),'source/index file type mismatch: '+str(p))
    data=os.fsencode(os.readlink(p)) if mode==b'120000' else p.read_bytes()
    blob=hashlib.sha1(b'blob '+str(len(data)).encode()+b'\0'+data).hexdigest().encode()
    require(blob==oid,'source/index bytes mismatch: '+str(p))
    require(mode==b'120000' or (mode==b'100755')==bool(p.stat().st_mode&0o111),'source/index mode mismatch: '+str(p))
    node=tree;parts=path.split(b'/')
    for part in parts[:-1]:node=node.setdefault(part,{})
    node[parts[-1]]=(mode,oid)
 def digest(node):
    entries=[]
    for name,value in node.items():
      mode,oid=(b'40000',digest(value)) if isinstance(value,dict) else value
      entries.append((name+(b'/' if mode==b'40000' else b''),mode+b' '+name+b'\0'+bytes.fromhex(oid.decode())))
    data=b''.join(value for _,value in sorted(entries))
    return hashlib.sha1(b'tree '+str(len(data)).encode()+b'\0'+data).hexdigest().encode()
 require(digest(tree).decode()==g['source']['tree'],'expected index tree mismatch')
 require(ctid in g['fixtures'],'CT not authorized')
 f=g['fixtures'][ctid]
 require(set(f)=={'role','ip','mac','name','state','lv_uuid','fs_uuid','baseline','receipts','completed'},'fixture schema')
 require(f['role'] in ['default','custom'] and isinstance(f['completed'],bool),'fixture role/completed')
 require(re.fullmatch(r'[0-9]+',ctid) and re.fullmatch(r'[A-Za-z0-9-]+',f['name']) and re.fullmatch(r'(?:[a-fA-F0-9]{2}:){5}[a-fA-F0-9]{2}',f['mac']),'fixture identifiers')
 __import__('ipaddress').IPv4Address(f['ip'])
 absolute(f['state']);base=absolute(f['baseline']);require(base.is_relative_to(w/'artifacts'),'baseline containment')
 for item in f['receipts'].values():checked_file(item)
 if f['completed']:
    required=['identity.json','install.status','installer.sha256','browser/fixture.json','target','completion']
    if f['role']=='custom':required+=['operator-env-expected','http-fixture.json','http-provider-unit.txt','update.status']
    for key in required:
      require(key in f['receipts'],'missing declared fixture receipt: '+key)
      if key not in ['target','completion']:require(f['receipts'][key]['path']==str(base/key),'receipt outside baseline: '+key)
    completion=json.loads(checked_file(f['receipts']['completion']).read_text())
    require(completion.get('completed') is True and completion.get('ctid')==ctid,'retained fixture not complete')
    flags=json.loads(checked_file(f['receipts']['browser/fixture.json']).read_text())
    require(flags.get('firstRunComplete') is True,'completed fixture missing original setup/note/settings outcome')
    if f['role']=='custom':require(flags.get('httpBeforeComplete') is True and flags.get('httpAfterComplete') is True,'completed fixture missing original offline outcomes')
    target=json.loads(checked_file(f['receipts']['target']).read_text());release=target['release']
    require(type(release.get('id')) is int and release.get('published_at') and release.get('draft') is False and release.get('prerelease') is False,'retained published release metadata')
    require(release['url']=='https://api.github.com/repos/alexindigo/globnotes/releases/'+str(release['id']) and release['tag_name']==target['tag'] and target['tag'].removeprefix('v')==target['version'],'retained release identity')
    objects=target['gitObjects'];require(objects[0]['ref']=='refs/tags/'+target['tag'],'retained exact tag ref')
    obj=objects[0]['object'];seen=set()
    for peeled in objects[1:]:
      require(obj['type']=='tag' and obj['sha']==peeled['sha'] and obj['sha'] not in seen,'retained tag peel identity')
      seen.add(obj['sha']);obj=peeled['object']
    require(obj['type']=='commit' and obj['sha']==target['commit'] and re.fullmatch('[a-f0-9]{40}',target['commit']),'retained peeled commit identity')
 if pathlib.Path('/etc/pve/lxc/'+ctid+'.conf').exists():
    config=command('pct','config',ctid)
    require('hostname: '+f['name']+'\n' in config+'\n' and 'hwaddr='+f['mac'].lower() in config.lower(),'CT name/MAC mismatch')
    require('bridge=vmbrgn24' in config and 'rootfs: local-lvm:vm-'+ctid+'-disk-0,size=8G' in config,'CT network/root ownership')
    expected_lv,expected_fs=f['lv_uuid'],f['fs_uuid']
    if expected_lv is None and not f['completed']:
      intent=json.loads((e/'create-intent.json').read_text());created=json.loads((e/'identity.json').read_text())
      require(intent['freeBeforeCreate'] is True and intent['ctid']==ctid and intent['mac']==f['mac'],'missing guarded creation intent')
      expected_lv,expected_fs=created['lv_uuid'],created['fs_uuid']
    require(command('lvs','--noheadings','-o','lv_uuid','pve/vm-'+ctid+'-disk-0')==expected_lv,'CT LV mismatch')
    require(command('blkid','-s','UUID','-o','value','/dev/pve/vm-'+ctid+'-disk-0')==expected_fs,'CT filesystem mismatch')
 else:require(not f['completed'] and f['lv_uuid'] is None and f['fs_uuid'] is None,'recorded CT missing')
 protected=g['protected'];require(set(protected)=={'checkout','pve_tree','lvs','retained_cts'},'protection schema')
 historical=json.loads(checked_file(protected['checkout']).read_text())
 for name,row in historical.items():
    p=pathlib.Path('/')/name;s=p.lstat()
    require((s.st_mode,s.st_uid,s.st_gid)==(row['mode'],row['uid'],row['gid']),'historical metadata: '+name)
    if 'link' in row:require(os.readlink(p)==row['link'],'historical link: '+name)
    if 'sha256' in row:require(hashlib.sha256(p.read_bytes()).hexdigest()==row['sha256'],'historical bytes: '+name)
 orig=json.loads(checked_file(protected['pve_tree']).read_text())
 selected={row[0] for row in orig if row[6]=='pve' and row[1]!=0};require(len(selected)==1,'protected old-node root')
 while True:
    before=len(selected);selected.update(row[0] for row in orig if row[1] in selected)
    if len(selected)==before:break
 db=sqlite3.connect('file:/var/lib/pve-cluster/config.db?mode=ro',uri=True)
 current={row[0]:[x.hex() if isinstance(x,bytes) else x for x in row] for row in db.execute('select inode,parent,version,writer,mtime,type,name,data from tree order by inode')}
 for row in orig:
    if row[0] in selected:require(current[row[0]]==row,'historical node row mismatch')
 lvs=json.loads(command('lvs','-a','--units','b','--nosuffix','--reportformat','json','-o','lv_name,lv_uuid,lv_size,lv_attr'))['report'][0]['lv']
 for name,expected in protected['lvs'].items():
    actual=next(row for row in lvs if row['lv_name']==name)
    require(actual['lv_uuid']==expected['uuid'] and int(actual['lv_size'])==expected['bytes'],'protected LV mismatch: '+name)
    if expected.get('inactive'):require(actual['lv_attr']=='Vwi---tz--','protected CT activated: '+name)
 for old,item in protected['retained_cts'].items():
    require(command('pct','status',old)=='status: stopped','retained CT running')
    require(hashlib.sha256(pathlib.Path('/etc/pve/lxc/'+old+'.conf').read_bytes()).hexdigest()==item['config_sha256'],'retained CT config changed')
    require(command('blkid','-s','UUID','-o','value',item['root_path'])==item['fs_uuid'],'retained CT filesystem changed')
 fs=os.statvfs(w);pool=command('dmsetup','status','pve-data-tpool').split();used,total=map(int,pool[5].split('/'));mu,mt=map(int,pool[4].split('/'))
 require(fs.f_bavail*fs.f_frsize>4*1024**3+512*1024**2 and fs.f_favail>50000,'root free floor/headroom')
 require((total-used)*65536>2*1024**3 and mu/mt<.8,'thin free floor/metadata')
 require((w/'tools/deno').is_file() and os.access(w/'tools/deno',os.X_OK),'missing browser Deno prerequisite')
 print(json.dumps({'guardVersion':1,'sourceTree':g['source']['tree'],'indexedFiles':len([x for x in rows if x]),'historicalEntries':len(historical),'oldNodeRows':len(selected),'rootFreeBytes':fs.f_bavail*fs.f_frsize,'thinFreeBytes':(total-used)*65536}))
except (KeyError,ValueError,TypeError,StopIteration,OSError,subprocess.CalledProcessError) as error:
 raise SystemExit('Native guard invalid or mismatched: '+str(error))
PY
}
verify_guard
if [[ "$stage" == guard ]]; then exit 0; fi
W=$(jq -r .workspace "$guard_manifest")
manifest_role=$(jq -r --arg id "$ctid" '.fixtures[$id].role' "$guard_manifest")
fixture_role=${fixture_role:-$manifest_role}
[[ "$fixture_role" == "$manifest_role" ]]
ip=$(jq -r --arg id "$ctid" '.fixtures[$id].ip' "$guard_manifest")
mac=$(jq -r --arg id "$ctid" '.fixtures[$id].mac' "$guard_manifest")
name=$(jq -r --arg id "$ctid" '.fixtures[$id].name' "$guard_manifest")
state=$(jq -r --arg id "$ctid" '.fixtures[$id].state' "$guard_manifest")
baseline=$(jq -r --arg id "$ctid" '.fixtures[$id].baseline' "$guard_manifest")
completed=$(jq -r --arg id "$ctid" '.fixtures[$id].completed' "$guard_manifest")
exec 9> "$W/native-owner.lock"
flock -n 9
umask 077
mkdir -p -- "$evidence"
cp -- /etc/hosts "$evidence/hosts-before-$run_id"
cleanup_native() {
  local status=$?
  trap - EXIT
  if [[ -n "${browser_unit:-}" ]]; then browser_stop || status=1; fi
  if [[ -e "$evidence/identity.json" ]] && owned; then
    if [[ $(pct status "$ctid") == 'status: running' ]]; then pct shutdown "$ctid" --timeout 60 || status=1; fi
  fi
  if [[ -f "$evidence/hosts-before-$run_id" ]]; then
    cat "$evidence/hosts-before-$run_id" > /etc/hosts
    cmp "$evidence/hosts-before-$run_id" /etc/hosts || status=1
  fi
  exit "$status"
}
trap cleanup_native EXIT
# Explicit retained input, copied only once; original evidence is never rewritten.
if [[ "$baseline" != "$evidence" && ! -e "$evidence/identity.json" ]]; then
  mkdir -p "$evidence/browser"
  for receipt in identity.json install.status installer.sha256 operator-env-expected http-fixture.json http-provider-unit.txt update.status; do
    if [[ -f "$baseline/$receipt" ]]; then cp -- "$baseline/$receipt" "$evidence/$receipt"; fi
  done
  cp -- "$baseline/browser/fixture.json" "$evidence/browser/fixture.json"
fi

admission() {
  df -B1 / > "$evidence/capacity-$1.txt"
  df -i / >> "$evidence/capacity-$1.txt"
  free -b >> "$evidence/capacity-$1.txt"
  lvs -a --units b --nosuffix -o lv_name,lv_uuid,lv_size,lv_attr,data_percent,metadata_percent >> "$evidence/capacity-$1.txt" 9>&-
  dmsetup status pve-data-tpool >> "$evidence/capacity-$1.txt"
  python3 - "$1" "${2:-2200}" "${3:-3}" "${4:-0}" << 'PY'
import os, subprocess,sys
s=os.statvfs('/')
assert s.f_bavail*s.f_frsize > 4*1024**3+512*1024**2, 'PVE root stage admission'
assert s.f_favail > 50000, 'PVE root inode admission'
status=subprocess.check_output(['dmsetup','status','pve-data-tpool'],text=True).split()
used,total=map(int,status[5].split('/'))
assert (total-used)*65536 > 2*1024**3+int(sys.argv[3])*1024**3, 'thin mapped-growth admission plus 2GiB floor'
meta_used,meta_total=map(int,status[4].split('/'))
assert meta_used/meta_total < .8, 'thin metadata admission'
mem=dict(line.split(':',1) for line in open('/proc/meminfo'))
assert int(mem['MemAvailable'].split()[0])*1024+int(sys.argv[4]) > int(sys.argv[2])*1024**2, 'concrete serial phase memory admission'
PY
}

owned() {
  [[ -s "$evidence/identity.json" ]]
  local config lv
  config=$(pct config "$ctid")
  [[ "$config" == *"hostname: $name"* && "${config,,}" == *"hwaddr=${mac,,}"* && "$config" == *'bridge=vmbrgn24'* ]]
  lv=$(lvs --noheadings -o lv_uuid "pve/vm-$ctid-disk-0" 9>&- | tr -d ' ')
  [[ "$lv" == "$(jq -r .lv_uuid "$evidence/identity.json")" ]]
  local expected_lv expected_fs
  expected_lv=$(jq -r --arg id "$ctid" '.fixtures[$id].lv_uuid' "$guard_manifest")
  expected_fs=$(jq -r --arg id "$ctid" '.fixtures[$id].fs_uuid' "$guard_manifest")
  if [[ "$expected_lv" != null ]]; then [[ "$lv" == "$expected_lv" ]]; fi
  if [[ "$expected_fs" != null ]]; then [[ $(blkid -s UUID -o value "/dev/pve/vm-$ctid-disk-0") == "$expected_fs" ]]; fi
}

snapshot() {
  local cache=/var/cache/globnotes
  if [[ -f "$evidence/operator-env-expected" ]]; then cache='/var/cache/globnotes custom cache'; fi
  pct config "$ctid" > "$evidence/config-$1.txt"
  pct status "$ctid" > "$evidence/status-$1.txt"
  lvs --units b --nosuffix -o lv_name,lv_uuid,lv_size,lv_attr,data_percent "pve/vm-$ctid-disk-0" > "$evidence/lv-$1.txt" 9>&-
  pct exec "$ctid" -- env TMPDIR=/var/lib/globnotes/tmp bash -c '
    systemctl show globnotes -p MainPID -p ActiveState -p ControlGroup -p MemoryCurrent -p MemoryPeak -p CPUUsageNSec -p User -p Group -p ExecStart -p AmbientCapabilities -p CapabilityBoundingSet
    ss -lntp
    df -B1 /
    df -i /
    du -sx /opt/globnotes "$1" /var/lib/globnotes /opt/globnotes-builds
    stat -c "%U:%G %a %n" /opt/globnotes /opt/globnotes/runtime/deno /opt/globnotes/node_modules /opt/globnotes/client/dist/index.html "$1" /etc/globnotes/env
    pid=$(systemctl show globnotes -p MainPID --value)
    ps -p "$pid" -o pid,user,rss,vsz,args
    grep -E "^(VmRSS|VmHWM|VmSwap):" "/proc/$pid/status"
    /opt/globnotes/runtime/deno --version
  ' -- "$cache" > "$evidence/native-$1.txt" 2>&1 || true
  pct exec "$ctid" -- journalctl -u globnotes --no-pager > "$evidence/journal-$1.txt" 2>&1 || true
}

install_native() {
  [[ ! -e "/etc/pve/lxc/$ctid.conf" && ! -e "$evidence/install-attempted" ]]
  if lvs "pve/vm-$ctid-disk-0" > /dev/null 2>&1 9>&-; then return 65; fi
  [[ -d /sys/class/net/vmbrgn24 ]]
  admission before-install
  verify_guard > "$evidence/source-index.txt"
  jq -r .source.tree "$guard_manifest" > "$evidence/source-tree.txt"
  sha256sum "$repo/scripts/lxc/globnotes.sh" > "$evidence/installer.sha256"
  select_release latest "install-latest-$run_id"
  cp "$selected_target" "$evidence/install-target.json"
  local -a extra=()
  if [[ "$fixture_role" == custom ]]; then
    extra+=("GLOBNOTES_INDEX_PATH=$state" var_appversion=v2.3.3)
    select_release tags/v2.3.3 "install-initial-$run_id"
    cp "$selected_target" "$evidence/install-target.json"
  fi
  jq -n --arg ctid "$ctid" --arg mac "$mac" --arg name "$name" --arg state "$state" \
    '{ctid:$ctid,mac:$mac,name:$name,state:$state,freeBeforeCreate:true}' > "$evidence/create-intent.json"
  : > "$evidence/install-attempted"
  python3 - "$ctid" "$evidence" << 'PY' &
import json, pathlib, subprocess, sys, time
ctid, directory=sys.argv[1:]
root=pathlib.Path(directory)
with (root/'install-resources.jsonl').open('x') as f:
    for _ in range(385):
        row={'time':time.time(),'rootAvailable':__import__('os').statvfs('/').f_bavail*4096}
        p=subprocess.run(['lxc-info','-n',ctid,'-pH'],capture_output=True,text=True,timeout=5)
        if p.returncode==0 and p.stdout.strip().isdigit():
            try:
                row['initPid']=int(p.stdout)
                group=pathlib.Path('/proc/'+p.stdout.strip()+'/cgroup').read_text().strip().split('::',1)[1]
                assert group.startswith('/lxc/'+ctid+'/'), 'Unexpected CT cgroup identity'
                cg=pathlib.Path('/sys/fs/cgroup/lxc/'+ctid)
                for key in ['memory.current','memory.peak','memory.max','memory.events','memory.swap.max','memory.swap.peak','memory.swap.current','cpu.stat']:
                    row[key]=(cg/key).read_text() if (cg/key).exists() else None
                row['initCgroup']=group
                row['measuredCgroup']=str(cg)
            except FileNotFoundError: pass
        f.write(json.dumps(row)+'\n'); f.flush()
        if (root/'install.status').exists(): break
        time.sleep(5)
PY
  local monitor=$!
  # Full framework: real host bootstrap, OS setup and generated install/update bundles.
  local status=0
  timeout --signal=TERM --kill-after=60 1800 env -i PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin HOME=/root TERM=xterm-256color TMPDIR="$TMPDIR" \
    REPO_BASE=http://10.248.24.1:8240 mode=default PHS_SILENT=1 UNATTENDED=1 dev_mode=keep,logs \
    var_ctid="$ctid" var_hostname="$name" var_mac="$mac" var_brg=vmbrgn24 var_net="$ip/24" var_gateway=10.248.24.1 var_ns=-nameserver=192.168.122.1 \
    var_container_storage=local-lvm var_template_storage=local var_ipv6_method=none var_verbose=yes \
    var_lxc_tmpdir=/var/lib/globnotes-bootstrap-tmp INSTALL_NVIDIA_DRIVERS=no "${extra[@]}" \
    bash -c 'umask 022; exec bash "$1"' -- "$repo/scripts/lxc/globnotes.sh" < /dev/null > "$evidence/install.log" 2>&1 9>&- || status=$?
  printf '%s\n' "$status" > "$evidence/install.status"
  wait "$monitor"
  if [[ -e "/etc/pve/lxc/$ctid.conf" ]]; then
    pct config "$ctid" > "$evidence/created-config.txt"
    local lv
    lv=$(lvs --noheadings -o lv_uuid "pve/vm-$ctid-disk-0" 9>&- | tr -d ' ')
    jq -n --arg ctid "$ctid" --arg mac "$mac" --arg name "$name" --arg lv "$lv" --arg state "$state" --arg fs "$(blkid -s UUID -o value "/dev/pve/vm-$ctid-disk-0")" \
      '{ctid:$ctid,mac:$mac,name:$name,lv_uuid:$lv,fs_uuid:$fs,state:$state}' > "$evidence/identity.json"
    owned
    pct set "$ctid" --onboot 0
    snapshot after-install
  fi
  [[ "$status" == 0 ]] || return "$status"
  checkpoint_native
  check_target "$evidence/install-target.json" "$evidence/early-http.json"
}

select_release() {
  local selector=$1 label=$2
  selected_target="$evidence/selected-$label.json"
  python3 - "$selector" "$selected_target" << 'PY'
import json,pathlib,re,subprocess,sys,urllib.parse
selector,path=sys.argv[1:];api='https://api.github.com/repos/alexindigo/globnotes/'
def get(url):
    return json.loads(subprocess.check_output(['curl','-fsS','--max-time','30',url],timeout=40))
release=get(api+'releases/'+selector)
assert type(release.get('id')) is int and release['id']>0 and release.get('published_at')
assert release.get('url')==api+'releases/'+str(release['id'])
assert release.get('draft') is False and release.get('prerelease') is False
tag=release['tag_name'];assert isinstance(tag,str) and re.fullmatch(r'^v?\d+\.\d+(\.\d+)?$',tag)
ref=get(api+'git/ref/tags/'+urllib.parse.quote(tag,safe=''));assert ref['ref']=='refs/tags/'+tag
obj=ref['object'];seen=set();objects=[ref]
for _ in range(16):
    sha=obj['sha'];assert re.fullmatch('[a-f0-9]{40}',sha) and sha not in seen;seen.add(sha)
    if obj['type']=='commit':break
    assert obj['type']=='tag';peeled=get(api+'git/tags/'+sha);assert peeled['sha']==sha
    objects.append(peeled);obj=peeled['object']
else:raise ValueError('tag peel depth')
pathlib.Path(path).write_text(json.dumps({'tag':tag,'version':tag.removeprefix('v'),'commit':sha,'release':release,'gitObjects':objects},indent=2))
PY
}

check_target() {
  if ! jq -e --slurpfile target "$1" '.version==$target[0].version and .revision==$target[0].commit' "$2" > /dev/null; then
    printf 'Selected published input and observed deployment differ; possible external input race. Preserve receipts and inspect before any replay.\n' >&2
    return 75
  fi
}

selection_unchanged() {
  if ! jq -e --slurpfile before "$1" '.tag==$before[0].tag and .commit==$before[0].commit and .release.id==$before[0].release.id' "$2" > /dev/null; then
    printf 'Published release input changed during the native operation; retain both selections and actual command outcome. This is an external-input race, not a product failure; do not replay or relabel it.\n' >&2
    return 75
  fi
}

checkpoint_native() {
  owned
  [[ $(< "$evidence/install.status") == 0 ]]
  pct set "$ctid" --onboot 0
  snapshot checkpoint
  curl -fsS --max-time 15 "http://$ip/_/api/config" > "$evidence/early-http.json"
  jq -e '.version != null and (.revision|length)==40' "$evidence/early-http.json"
  pct exec "$ctid" -- env TMPDIR=/var/lib/globnotes-bootstrap-tmp bash -c 'grep -E "^declare -- var_lxc_globnotes_(index_path|initial_release)=" /usr/local/sbin/update' > "$evidence/baked-context.txt"
  printf 'Native install HTTP checkpoint CT%s: %s\n' "$ctid" "$(jq -c '{version,revision}' "$evidence/early-http.json")"
}

browser_native() {
  owned
  [[ $(getent ahostsv4 globnotes.home) == "$ip"* ]]
  [[ -x "$W/tools/deno" ]]
  local phase=$1 label=${2:-$1}
  local version revision cache=/var/cache/globnotes
  local -a extra=()
  if [[ "$fixture_role" == custom && -f "$evidence/operator-env-expected" ]]; then
    cache='/var/cache/globnotes custom cache'
    extra+=(--expected-brand 'Native acceptance')
  fi
  if [[ "$fixture_role" == custom && -f "$evidence/http-fixture.json" ]]; then extra+=(--expected-http yes); fi
  version=$(pct exec "$ctid" -- cat /root/.globnotes)
  revision=$(pct exec "$ctid" -- sed -n 's/^GLOBNOTES_REVISION="\([a-f0-9]*\)"$/\1/p' /opt/globnotes/runtime/release.env)
  [[ "$revision" =~ ^[a-f0-9]{40}$ ]]
  sha256sum "$repo/tests/maintenance-globnotes-browser.mjs" > "$evidence/browser-driver-$label.sha256"
  DENO_DIR="$W/cache/browser-driver" timeout --signal=TERM --kill-after=60 600 "$W/tools/deno" run \
    --no-config --no-lock --cached-only --allow-net --allow-read --allow-write --allow-env \
    "$repo/tests/maintenance-globnotes-browser.mjs" --origin "$origin" --cdp "$cdp" --phase "$phase" --label "$label" \
    --evidence "$evidence/browser" --expected-version "$version" --expected-revision "$revision" "${extra[@]}" > "$evidence/browser-$label.log" 2>&1
  jq -e '.completed==true and (.notes|length)==2 and all(.notes[]; (.path|type)=="string" and (.content|type)=="string")' "$evidence/browser/$label-consumers.json" > /dev/null
  jq -r '.notes[].path' "$evidence/browser/$label-consumers.json" > "$evidence/note-paths-$label.txt"
  local path expected observed title
  while IFS= read -r title; do
    path=$(jq -r --arg title "$title" '.notes[]|select(.path==$title)|.path' "$evidence/browser/$label-consumers.json")
    expected="$evidence/expected-${title##*/}.md"
    observed="$evidence/disk-${title##*/}.md"
    jq -j --arg title "$title" '.notes[]|select(.path==$title)|.content' "$evidence/browser/$label-consumers.json" > "$expected"
    pct exec "$ctid" -- cat "/var/lib/globnotes/notes/$path.md" > "$observed"
    cmp -- "$expected" "$observed"
  done < "$evidence/note-paths-$label.txt"
  pct exec "$ctid" -- env TMPDIR=/var/lib/globnotes/tmp bash -c '
    set -euo pipefail
    test -f "$1/config.json"
    test -f "$1/plugin-data/globnotes-backup/settings.json"
    runuser -u globnotes -- test -w "$2"
    runuser -u globnotes -- test -w /opt/globnotes/node_modules
    runuser -u globnotes -- test -w /opt/globnotes/client/dist/index.html
    runuser -u globnotes -- test -w /opt/globnotes/runtime/dependency-lock
    runuser -u globnotes -- test -w /opt/globnotes/runtime/dependency-lock/deno.lock
    if runuser -u globnotes -- test -w /opt/globnotes/runtime; then exit 1; fi
    if runuser -u globnotes -- test -w /opt/globnotes/runtime/deno; then exit 1; fi
    if runuser -u globnotes -- test -w /opt/globnotes/runtime/release.env; then exit 1; fi
    if runuser -u globnotes -- test -w /opt/globnotes/deno.lock; then exit 1; fi
    if runuser -u globnotes -- test -w /opt/globnotes; then exit 1; fi
    if runuser -u globnotes -- test -w /opt/globnotes/server/main.ts; then exit 1; fi
    if command -v docker; then exit 1; fi
    pid=$(systemctl show globnotes -p MainPID --value)
    grep -zFx "DENO_DIR=$2" "/proc/$pid/environ" > /dev/null
    systemctl show globnotes -p ExecStart --value | grep -F -- --lock=/opt/globnotes/runtime/dependency-lock/deno.lock > /dev/null
    cd /opt/globnotes
    sha256sum -c runtime/released-lock.sha256
    stat -c "%U:%G %a %n" "$1" "$1/config.json" "$1/plugin-data/globnotes-backup/settings.json"
    sha256sum "$1/config.json" "$1/plugin-data/globnotes-backup/settings.json" /etc/globnotes/env /root/.globnotes
  ' -- "$state" "$cache" > "$evidence/persistence-$label.txt"
  if [[ "$phase" == http-before || "$phase" == http-after || "$phase" == http-force ]]; then
    pct exec "$ctid" -- cat "$state/plugin-data/native-http-cache/data.json" > "$evidence/http-private-$label.json"
    jq -e --slurpfile consumer "$evidence/browser/$label-consumers.json" '.values==$consumer[0].httpDependency.result' "$evidence/http-private-$label.json" > /dev/null
    pct exec "$ctid" -- jq -e --arg url http://10.248.24.1:8242/dependency-v2.mjs \
      --arg sha "$(jq -r .moduleSha256 "$evidence/http-fixture.json")" '.remote[$url]==$sha' \
      /opt/globnotes/runtime/dependency-lock/deno.lock > "$evidence/runtime-integrity-$label.txt"
  fi
  if [[ "$phase" == all-after && "$fixture_role" == custom ]]; then
    pct exec "$ctid" -- cat "$state/plugin-data/native-http-cache/data.json" > "$evidence/http-private-$label.json"
    jq -e --slurpfile consumer "$evidence/browser/$label-consumers.json" '.values==$consumer[0].httpDependencyReadback.result' "$evidence/http-private-$label.json" > /dev/null
  fi
  printf '%s\n' "$label" > "$evidence/last-browser-label.txt"
  printf 'Native browser/API/disk %s observed for CT%s\n' "$phase" "$ctid"
}

restart_native() {
  owned
  pct exec "$ctid" -- sha256sum "$state/config.json" /etc/globnotes/env > "$evidence/restart-before.sha256"
  pct exec "$ctid" -- systemctl restart globnotes
  local i
  for ((i = 0; i < 30; i++)); do
    if curl -fsS --max-time 5 "http://$ip/_/api/config" > "$evidence/restart-http.json"; then break; fi
    sleep 1
  done
  jq -e '.version != null and (.revision|length)==40' "$evidence/restart-http.json"
  pct exec "$ctid" -- sha256sum "$state/config.json" /etc/globnotes/env > "$evidence/restart-after.sha256"
  cmp "$evidence/restart-before.sha256" "$evidence/restart-after.sha256"
  browser_native restart
  snapshot restarted
}

noop_native() {
  owned
  [[ "$fixture_role" == default && ! -e "$evidence/noop.status" ]]
  local before after status=0
  select_release latest "noop-before-$run_id"
  local target=$selected_target
  curl -fsS --max-time 10 "http://$ip/_/api/config" > "$evidence/noop-before-http.json"
  check_target "$target" "$evidence/noop-before-http.json"
  before=$(pct exec "$ctid" -- systemctl show globnotes -p MainPID --value)
  pct exec "$ctid" -- env TMPDIR=/var/lib/globnotes/tmp bash -e -o pipefail -c '
    find /opt/globnotes -xdev -type f -print0 | sort -z | xargs -0 sha256sum
    sha256sum /etc/globnotes/env /root/.globnotes
  ' > "$evidence/noop-before.sha256"
  pct exec "$ctid" -- env TMPDIR=/var/lib/globnotes/tmp bash -e -o pipefail -c '
    find /opt/globnotes -xdev -printf "%P|%y|%m|%U|%G|%i|%s|%T@|%C@|%l\n" | LC_ALL=C sort
    stat -c "%n|%f|%u|%g|%i|%s|%Y|%Z" /etc/globnotes/env /root/.globnotes
  ' > "$evidence/noop-before-metadata.txt"
  timeout --signal=TERM --kill-after=60 600 pct exec "$ctid" -- env -i \
    PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin HOME=/root TERM=xterm-256color \
    TMPDIR=/var/lib/globnotes-bootstrap-tmp bash /usr/local/sbin/update > "$evidence/noop.log" 2>&1 || status=$?
  printf '%s\n' "$status" > "$evidence/noop.status"
  [[ "$status" == 0 ]]
  select_release latest "noop-after-$run_id"
  selection_unchanged "$target" "$selected_target"
  after=$(pct exec "$ctid" -- systemctl show globnotes -p MainPID --value)
  [[ "$before" == "$after" && "$before" != 0 ]]
  pct exec "$ctid" -- env TMPDIR=/var/lib/globnotes/tmp bash -e -o pipefail -c '
    find /opt/globnotes -xdev -type f -print0 | sort -z | xargs -0 sha256sum
    sha256sum /etc/globnotes/env /root/.globnotes
  ' > "$evidence/noop-after.sha256"
  cmp "$evidence/noop-before.sha256" "$evidence/noop-after.sha256"
  pct exec "$ctid" -- env TMPDIR=/var/lib/globnotes/tmp bash -e -o pipefail -c '
    find /opt/globnotes -xdev -printf "%P|%y|%m|%U|%G|%i|%s|%T@|%C@|%l\n" | LC_ALL=C sort
    stat -c "%n|%f|%u|%g|%i|%s|%Y|%Z" /etc/globnotes/env /root/.globnotes
  ' > "$evidence/noop-after-metadata.txt"
  cmp "$evidence/noop-before-metadata.txt" "$evidence/noop-after-metadata.txt"
  jq -n --arg before "$before" --arg after "$after" '{status:0,mainPidBefore:$before,mainPidAfter:$after,codeEnvironmentMarkerUnchanged:true,codeEnvironmentMarkerMetadataUnchanged:true}' > "$evidence/noop-consumers.json"
}

protection() {
  verify_guard > "$evidence/protection-$run_id-$1.json"
}

bind_source() {
  verify_guard > "$evidence/source-$run_id.txt"
  owned
  [[ $(< "$evidence/install.status") == 0 ]]
  [[ $(sha256sum "$repo/scripts/lxc/globnotes.sh" | cut -d ' ' -f1) == "$(cut -d ' ' -f1 "$evidence/installer.sha256")" ]]
  pct pull "$ctid" /usr/local/sbin/update "$evidence/update-bundle-$run_id.sh"
  python3 - "$repo" "$evidence/update-bundle-$run_id.sh" "$evidence/source-binding-$run_id.json" "$guard_manifest" << 'PY'
import hashlib,json,pathlib,subprocess,sys
r=pathlib.Path(sys.argv[1]);script=(r/'scripts/lxc/globnotes.sh').read_text()
assert script.count('\nsource <(')==1
expected=subprocess.check_output(['bash','-c',script.rsplit('\nsource <(',1)[0]+'\ndeclare -f update_script'],text=True).strip()
bundle=pathlib.Path(sys.argv[2]).read_text()
actual=bundle.split('# ═══ hook: update_script ═══\n',1)[1].split('# ═══ update pipeline ═══',1)[0].strip()
assert actual==expected,'Installed cold update hook differs from exact source'
pathlib.Path(sys.argv[3]).write_text(json.dumps({'tree':json.loads(pathlib.Path(sys.argv[4]).read_text())['source']['tree'],'installerSha256':hashlib.sha256(script.encode()).hexdigest(),'installedUpdateHookSha256':hashlib.sha256(actual.encode()).hexdigest(),'exactHookMatch':True},indent=2))
PY
}

resume_native() {
  owned
  admission "resume-$run_id" 700 1
  local active other
  active=$(pct status "$ctid")
  other=$(lxc-ls --active)
  [[ -z "$other" || "$other" == "$ctid" ]]
  if [[ "$active" == 'status: stopped' ]]; then pct start "$ctid"; else [[ "$active" == 'status: running' ]]; fi
  local i
  for ((i = 0; i < 30; i++)); do
    if curl -fsS --max-time 5 "http://$ip/_/api/config" > "$evidence/resume-$run_id.json"; then break; fi
    sleep 1
  done
  jq -e '.version != null and (.revision|length)==40' "$evidence/resume-$run_id.json" > /dev/null
  local config
  config=$(pct config "$ctid")
  grep -Fxq 'cores: 2' <<< "$config"
  grep -Fxq 'memory: 2048' <<< "$config"
  grep -Fxq 'unprivileged: 1' <<< "$config"
  grep -Fxq "rootfs: local-lvm:vm-$ctid-disk-0,size=8G" <<< "$config"
}

browser_start() {
  if [[ -n $(ss -H -lnt 'sport = :9335') ]]; then
    [[ -s "$evidence/active-browser-unit.txt" ]]
    browser_unit=$(< "$evidence/active-browser-unit.txt")
    [[ "$browser_unit" == su-gn-native-browser-"$ctid"-* && $(systemctl show "$browser_unit" -p User --value) == su-gn-browser ]]
    [[ $(getent ahostsv4 globnotes.home) == "$ip"* ]]
    return 0
  fi
  local browser_home="$W/browser-$ctid" browser_tmp="$W/t${ctid: -2}"
  if [[ ! -d "$browser_home" ]]; then
    install -d -o su-gn-browser -g su-gn-browser -m 700 "$browser_home" "$browser_home/profile" "$browser_home/cache" "$browser_home/config" "$browser_home/runtime"
  fi
  if [[ ! -d "$browser_tmp" ]]; then install -d -o su-gn-browser -g su-gn-browser -m 700 "$browser_tmp"; fi
  runuser -u su-gn-browser -- test -w "$browser_tmp"
  python3 - "$ip" << 'PY'
import pathlib,sys
p=pathlib.Path('/etc/hosts');old=p.read_text();lines=old.splitlines(keepends=True)
owned=[i for i,line in enumerate(lines) if line.rstrip().endswith('# su-globnotes-deno-phase-d')]
assert len(owned)<=1
assert not any('globnotes.home' in line.split('#',1)[0].split()[1:] for i,line in enumerate(lines) if i not in owned)
entry=sys.argv[1]+' globnotes.home # su-globnotes-deno-phase-d\n'
if owned:lines[owned[0]]=entry
else:lines.append(entry)
p.write_text(''.join(lines))
PY
  browser_unit="su-gn-native-browser-$ctid-$run_id"
  systemd-run --quiet --unit "$browser_unit" --property User=su-gn-browser --property Group=su-gn-browser \
    --property RuntimeMaxSec=3900 --property KillMode=control-group --property "WorkingDirectory=$browser_home" \
    --property "StandardOutput=append:$evidence/browser-process-$run_id.log" --property "StandardError=append:$evidence/browser-process-$run_id.log" \
    --setenv "HOME=$browser_home" --setenv "TMPDIR=$browser_tmp" --setenv "XDG_CONFIG_HOME=$browser_home/config" \
    --setenv "XDG_CACHE_HOME=$browser_home/cache" --setenv "XDG_RUNTIME_DIR=$browser_home/runtime" \
    /usr/bin/chromium --headless=new --remote-debugging-address=127.0.0.1 --remote-debugging-port=9335 \
    "--user-data-dir=$browser_home/profile" "--disk-cache-dir=$browser_home/cache" --disable-dev-shm-usage --no-first-run --no-default-browser-check about:blank 9>&-
  printf '%s\n' "$browser_unit" > "$evidence/browser-unit-$run_id.txt"
  printf '%s\n' "$browser_unit" > "$evidence/active-browser-unit.txt"
  local i
  for ((i = 0; i < 20; i++)); do
    if curl -fsS --max-time 2 "$cdp/json/version" > "$evidence/browser-version-$run_id.json"; then return 0; fi
    sleep 1
  done
  return 75
}

browser_stop() {
  [[ -n "${browser_unit:-}" && "$browser_unit" == su-gn-native-browser-"$ctid"-* ]]
  [[ $(systemctl show "$browser_unit" -p User --value) == su-gn-browser ]]
  systemctl stop "$browser_unit"
  [[ -z $(ss -H -lnt 'sport = :9335') ]]
}

prepare_http() {
  owned
  [[ "$fixture_role" == custom && ! -e "$evidence/http-preparation-attempted" ]]
  [[ $(pct exec "$ctid" -- cat /root/.globnotes) == 2.3.3 ]]
  [[ -z $(ss -H -lnt 'sport = :8242') ]]
  admission "http-$run_id" 256 1
  : > "$evidence/http-preparation-attempted"
  mkdir -m 700 -- "$evidence/http-provider"
  printf '%s\n' 'export const moduleIdentity = "su-native-http-module-v2";' 'export function nativeValue() { return "cache-value-" + (6 * 7); }' > "$evidence/http-provider/dependency-v2.mjs"
  local unit="su-gn-native-http-$run_id"
  printf '%s\n' "$unit" > "$evidence/http-provider-unit.txt"
  systemd-run --quiet --unit "$unit" --property RuntimeMaxSec=900 --property "WorkingDirectory=$evidence/http-provider" \
    --property "StandardOutput=append:$evidence/http-provider.log" --property "StandardError=append:$evidence/http-provider.log" \
    --setenv "TMPDIR=$W/tmp" python3 -m http.server 8242 --bind 10.248.24.1 --directory "$evidence/http-provider" 9>&-
  curl -fsS --retry 5 --retry-connrefused --max-time 5 http://10.248.24.1:8242/dependency-v2.mjs > "$evidence/http-provider/received.mjs"
  cmp "$evidence/http-provider/dependency-v2.mjs" "$evidence/http-provider/received.mjs"
  pct exec "$ctid" -- sha256sum /opt/globnotes/deno.lock > "$evidence/http-app-lock-before.sha256"
  pct exec "$ctid" -- env TMPDIR=/var/lib/globnotes-bootstrap-tmp bash -s -- "$state" > "$evidence/http-preparation.log" 2>&1 << 'SHELL'
set -euo pipefail
state=$1
test ! -e "$state/plugins/native-http-cache"
sha256sum /opt/globnotes/deno.lock
systemctl stop globnotes
test "$(systemctl show globnotes -p MainPID --value)" = 0
install -d -m 750 -o globnotes -g globnotes "$state/plugins/native-http-cache"
cat > "$state/plugins/native-http-cache/manifest.json" <<'JSON'
{"id":"native-http-cache","name":"Native HTTP cache acceptance","version":"1.0.0","runtime":{"server":"service.js"},"capabilities":{"network":false,"imports":["10.248.24.1:8242"]}}
JSON
cat > "$state/plugins/native-http-cache/service.js" <<'JS'
const url='http://10.248.24.1:8242/dependency-v2.mjs';
export function activate(ctx) {
  ctx.commands.register({id:'consume',label:'Consume offline HTTP module',target:'server'},async()=>{
    try {
      const {moduleIdentity,nativeValue}=await import(url);
      const previous=await ctx.data.load();
      const result={checks:(previous.values.checks??0)+1,moduleIdentity,value:nativeValue(),url};
      await ctx.data.save(result,previous.revision);
      return result;
    } catch(error) { console.error('NATIVE_HTTP_CACHE_IMPORT',error?.stack??String(error));throw error; }
  });
  ctx.commands.register({id:'observe',label:'Observe offline HTTP result',target:'server'},async()=>(await ctx.data.load()).values);
}
JS
chown globnotes:globnotes "$state/plugins/native-http-cache/manifest.json" "$state/plugins/native-http-cache/service.js"
runuser -u globnotes -- env -i PATH=/opt/globnotes/runtime:/usr/bin:/bin HOME=/var/lib/globnotes TMPDIR=/var/lib/globnotes/tmp DENO_DIR='/var/cache/globnotes custom cache' \
  deno cache --no-config --no-lock --allow-import=10.248.24.1:8242 http://10.248.24.1:8242/dependency-v2.mjs
sha256sum /opt/globnotes/deno.lock
systemctl start globnotes
SHELL
  pct exec "$ctid" -- sha256sum "$state/plugins/native-http-cache/manifest.json" "$state/plugins/native-http-cache/service.js" > "$evidence/http-plugin-source.sha256"
  pct exec "$ctid" -- sha256sum /opt/globnotes/deno.lock > "$evidence/http-app-lock-after.sha256"
  cmp "$evidence/http-app-lock-before.sha256" "$evidence/http-app-lock-after.sha256"
  jq -n --arg url http://10.248.24.1:8242/dependency-v2.mjs --arg sha "$(sha256sum "$evidence/http-provider/dependency-v2.mjs" | cut -d ' ' -f1)" \
    --arg unit "$unit" '{pluginId:"native-http-cache",moduleUrl:$url,moduleSha256:$sha,providerUnit:$unit,effectiveCache:"/var/cache/globnotes custom cache"}' > "$evidence/http-fixture.json"
}

prepare_operator_environment() {
  [[ "$fixture_role" == custom ]]
  if [[ -s "$evidence/operator-env-expected" ]]; then return 0; fi
  pct pull "$ctid" /etc/globnotes/env "$evidence/operator-env-before"
  pct exec "$ctid" -- env TMPDIR=/var/lib/globnotes/tmp bash -e -c '
    test ! -e "/var/cache/globnotes custom cache"
    systemctl stop globnotes
    test "$(systemctl show globnotes -p MainPID --value)" = 0
    mv -T /var/cache/globnotes "/var/cache/globnotes custom cache"
    sed -i '\''s|^DENO_DIR=.*|DENO_DIR="/var/cache/globnotes custom cache"|'\'' /etc/globnotes/env
    printf '\''\nGLOBNOTES_BRAND_NAME="Native acceptance"\n'\'' >> /etc/globnotes/env
    systemctl start globnotes
  '
  pct pull "$ctid" /etc/globnotes/env "$evidence/operator-env-expected"
}

provider_stopped() {
  [[ -s "$evidence/http-provider-unit.txt" ]]
  local unit state pid status=0
  unit=$(< "$evidence/http-provider-unit.txt")
  [[ "$unit" == su-gn-native-http-* ]]
  state=$(systemctl show "$unit" -p ActiveState --value)
  pid=$(systemctl show "$unit" -p MainPID --value)
  [[ "$state" == inactive || "$state" == failed ]] && [[ "$pid" == 0 ]]
  [[ -z $(ss -H -lnt 'sport = :8242') ]]
  curl -fsS --max-time 2 http://10.248.24.1:8242/dependency-v2.mjs > /dev/null 2>&1 || status=$?
  [[ "$status" == 7 ]]
}

stop_provider() {
  local unit
  unit=$(< "$evidence/http-provider-unit.txt")
  [[ "$unit" == su-gn-native-http-* ]]
  systemctl stop "$unit"
  provider_stopped
  jq -n --arg unit "$unit" '{unit:$unit,mainPid:0,tcpListenerAbsent:true,actualCurlStatus:7}' > "$evidence/http-provider-stopped-before.json"
}

preserved_files() {
  pct exec "$ctid" -- env TMPDIR=/var/lib/globnotes/tmp bash -e -o pipefail -c '
    state=$1
    sha256sum /etc/globnotes/env "$state/config.json" "$state/plugin-data/globnotes-backup/settings.json" \
      "$state/plugins/native-http-cache/manifest.json" "$state/plugins/native-http-cache/service.js" \
      "$state/plugin-network/native-http-cache.json" "$state/plugin-data/native-http-cache/data.json"
    find /var/lib/globnotes/notes -xdev -type f -print0 | sort -z | xargs -0 sha256sum
  ' -- "$state" > "$evidence/preserved-$1.sha256"
}

update_native() {
  local operation=${1:-update} force=0
  local -a update_args=()
  if [[ "$operation" == force ]]; then
    force=1
    update_args+=(--clean)
  fi
  owned
  [[ "$fixture_role" == custom && ! -e "$evidence/$operation-attempted" ]]
  if [[ "$force" == 0 ]]; then
    [[ $(pct exec "$ctid" -- cat /root/.globnotes) == 2.3.3 ]]
    [[ -s "$evidence/http-before-consumers.json" ]]
    jq -e '.completed and .httpDependency.result.checks==1 and .httpDependency.result.value=="cache-value-42"' "$evidence/http-before-consumers.json" > /dev/null
    pct exec "$ctid" -- jq -e '.values.checks==1 and .values.value=="cache-value-42"' "$state/plugin-data/native-http-cache/data.json" > /dev/null
  else
    [[ "$completed" == true ]]
    pct exec "$ctid" -- jq -e '.values.checks==2 and .values.value=="cache-value-42"' "$state/plugin-data/native-http-cache/data.json" > /dev/null
  fi
  select_release latest "$operation-$run_id"
  local target=$selected_target before_version
  before_version=$(pct exec "$ctid" -- cat /root/.globnotes)
  if [[ "$force" == 1 ]]; then [[ "$before_version" == "$(jq -r .version "$target")" ]]; fi
  provider_stopped
  [[ -z $(ss -H -lnt 'sport = :9335') ]]
  local releasable
  releasable=$(pct exec "$ctid" -- bash -c 'pid=$(systemctl show globnotes -p MainPID --value); ps -o rss= -p "$pid"')
  [[ "$releasable" =~ ^[[:space:]]*[0-9]+[[:space:]]*$ ]]
  # The existing Deno process is stopped by the real updater before its build.
  # Count only its observed RSS, not reclaimable cache already in MemAvailable.
  admission "update-$run_id" 2200 3 "$((releasable * 1024))"
  pct exec "$ctid" -- env TMPDIR=/var/lib/globnotes/tmp bash -c 'read -r available block < <(stat -f -c "%a %S" /opt); (( available * block > 3 * 1024 * 1024 * 1024 ))'
  bind_source
  preserved_files "before-$operation-$run_id"
  pct exec "$ctid" -- du -sx '/var/cache/globnotes custom cache' /opt/globnotes > "$evidence/cache-code-before-update.txt"
  pct exec "$ctid" -- env TMPDIR=/var/lib/globnotes/tmp bash -c 'find /opt/globnotes-builds -mindepth 1 -maxdepth 1 -printf "%f\n"; find /var/cache -maxdepth 1 -name "globnotes custom cache.*" -printf "%f\n"' > "$evidence/stages-before-update.txt"
  : > "$evidence/$operation-attempted"
  python3 - "$ctid" "$evidence" "$operation-$run_id" << 'PY' &
import json,os,pathlib,subprocess,sys,time
ctid,directory,label=sys.argv[1:];out=pathlib.Path(directory)
init=int(subprocess.check_output(['lxc-info','-n',ctid,'-pH'],text=True).strip())
cg=pathlib.Path('/sys/fs/cgroup/lxc/'+ctid)
assert pathlib.Path('/proc/'+str(init)+'/cgroup').read_text().strip().split('::',1)[1].startswith('/lxc/'+ctid+'/')
with (out/(label+'-resources.jsonl')).open('x') as f:
    for _ in range(7600):
        fs=os.statvfs('/proc/'+str(init)+'/root');host=os.statvfs('/')
        row={'time':time.time(),'cgroup':str(cg),'ctFreeBytes':fs.f_bavail*fs.f_frsize,'rootFreeBytes':host.f_bavail*host.f_frsize}
        for key in ['memory.current','memory.peak','memory.max','memory.events','memory.swap.max','memory.swap.peak','memory.swap.current','cpu.stat']:
            row[key]=(cg/key).read_text() if (cg/key).exists() else None
        if _%4==0:
            pool=subprocess.check_output(['dmsetup','status','pve-data-tpool'],text=True).split()
            used,total=map(int,pool[5].split('/'));row['thinFreeBytes']=(total-used)*65536
        processes={}
        for group in cg.rglob('cgroup.procs'):
            try:pids=group.read_text().split()
            except FileNotFoundError:continue
            for pid in pids:
                try:
                    fields=dict(line.split(':',1) for line in pathlib.Path('/proc/'+pid+'/status').read_text().splitlines() if ':' in line)
                    if fields.get('Name','').strip() in ['deno','node','rolldown']:
                        processes[pid]={'name':fields['Name'].strip(),'rssBytes':int(fields.get('VmRSS','0 kB').split()[0])*1024,'hwmBytes':int(fields.get('VmHWM','0 kB').split()[0])*1024}
                except FileNotFoundError:pass
        row['compilerAndRuntimeProcesses']=processes;row['summedRssBytes']=sum(p['rssBytes'] for p in processes.values())
        f.write(json.dumps(row)+'\n');f.flush()
        if (out/(label+'.status')).exists():break
        time.sleep(.25)
PY
  local monitor=$! status=0
  timeout --signal=TERM --kill-after=60 1800 pct exec "$ctid" -- env -i \
    PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin HOME=/root TERM=xterm-256color \
    TMPDIR=/var/lib/globnotes-bootstrap-tmp bash /usr/local/sbin/update "${update_args[@]}" > "$evidence/$operation-$run_id.log" 2>&1 9>&- || status=$?
  printf '%s\n' "$status" > "$evidence/$operation-$run_id.status"
  if [[ "$force" == 0 ]]; then printf '%s\n' "$status" > "$evidence/update.status"; fi
  wait "$monitor"
  [[ "$status" == 0 ]] || return "$status"
  python3 - "$evidence" "$operation-$run_id" << 'PY'
import json,pathlib,sys
p=pathlib.Path(sys.argv[1]);label=sys.argv[2];rows=[json.loads(line) for line in (p/(label+'-resources.jsonl')).read_text().splitlines()]
assert len(rows)>1
events=dict(line.split() for line in rows[-1]['memory.events'].splitlines())
first_events=dict(line.split() for line in rows[0]['memory.events'].splitlines())
delta={key:int(value)-int(first_events[key]) for key,value in events.items()}
assert delta['oom_kill']==0 and delta['oom']==0
peak=max(int(row['memory.peak']) for row in rows)
minimum=min(row['rootFreeBytes'] for row in rows);assert minimum>4*1024**3+512*1024**2
thin=min(row['thinFreeBytes'] for row in rows if 'thinFreeBytes' in row);assert thin>2*1024**3
summary={'sampleCount':len(rows),'seconds':rows[-1]['time']-rows[0]['time'],'ctCgroupPeakBytes':peak,'compilerAndRuntimeSummedRssPeakBytes':max(row['summedRssBytes'] for row in rows),'ctFilesystemPeakGrowthBytes':rows[0]['ctFreeBytes']-min(row['ctFreeBytes'] for row in rows),'ctMinimumFreeBytes':min(row['ctFreeBytes'] for row in rows),'pveRootMinimumFreeBytes':minimum,'thinMinimumFreeBytes':thin,'cpuUsec':int(dict(line.split() for line in rows[-1]['cpu.stat'].splitlines())['usage_usec'])-int(dict(line.split() for line in rows[0]['cpu.stat'].splitlines())['usage_usec']),'memoryEvents':events}
def number(value):return int(value) if value is not None else None
def maximum(key):
    values=[int(row[key]) for row in rows if row[key] is not None]
    return max(values) if values else None
summary.update({'memoryMax':rows[-1]['memory.max'],'memoryEventsDelta':delta,'swapMax':rows[-1]['memory.swap.max'],'swapCurrentFirstBytes':number(rows[0]['memory.swap.current']),'swapCurrentLastBytes':number(rows[-1]['memory.swap.current']),'swapSampledCurrentPeakBytes':maximum('memory.swap.current'),'swapCgroupPeakBytes':maximum('memory.swap.peak'),'swapPeakScope':'cgroup lifetime since CT start, not necessarily this operation; sampled current is only a lower bound when peak unsupported','adequacyLimit':'Successful finite native build plus observed pressure/events; hard cap does not independently establish adequate headroom'})
(p/(label+'-measurements.json')).write_text(json.dumps(summary,indent=2))
PY
  select_release latest "$operation-after-$run_id"
  selection_unchanged "$target" "$selected_target"
  curl -fsS --max-time 10 "http://$ip/_/api/config" > "$evidence/$operation-$run_id-http.json"
  check_target "$target" "$evidence/$operation-$run_id-http.json"
  [[ $(pct exec "$ctid" -- cat /root/.globnotes) == "$(jq -r .version "$target")" ]]
  jq -n --arg before "$before_version" --slurpfile target "$target" --arg operation "$operation" '{operation:$operation,fromVersion:$before,toVersion:$target[0].version,toCommit:$target[0].commit,currentVersionForcedRebuild:($operation=="force")}' > "$evidence/$operation-$run_id-transition.json"
  pct exec "$ctid" -- env TMPDIR=/var/lib/globnotes/tmp bash -e -c 'cd /opt/globnotes; sha256sum -c runtime/released-lock.sha256; jq -e --arg url http://10.248.24.1:8242/dependency-v2.mjs '\''(.remote // {})|has($url)|not'\'' runtime/dependency-lock/deno.lock' > "$evidence/new-generation-lock-seed.txt"
  provider_stopped
  preserved_files "after-$operation-$run_id"
  cmp "$evidence/preserved-before-$operation-$run_id.sha256" "$evidence/preserved-after-$operation-$run_id.sha256"
  pct exec "$ctid" -- du -sx '/var/cache/globnotes custom cache' /opt/globnotes > "$evidence/cache-code-after-update.txt"
  pct exec "$ctid" -- env TMPDIR=/var/lib/globnotes/tmp bash -c 'find /opt/globnotes-builds -mindepth 1 -maxdepth 1 -printf "%f\n"; find /var/cache -maxdepth 1 -name "globnotes custom cache.*" -printf "%f\n"' > "$evidence/stages-after-update.txt"
  cmp "$evidence/stages-before-update.txt" "$evidence/stages-after-update.txt"
  snapshot updated
  printf 'Actual native %s reached %s; offline provider and persistent hashes unchanged\n' "$operation" "$(jq -r .tag "$target")"
}

all_native() {
  protection before-all
  if [[ ! -e "$evidence/identity.json" ]]; then install_native; fi
  resume_native
  bind_source
  select_release latest "all-$run_id"
  if [[ "$completed" == true ]]; then
    local retained_target
    retained_target=$(jq -r --arg id "$ctid" '.fixtures[$id].receipts.target.path' "$guard_manifest")
    check_target "$retained_target" "$evidence/resume-$run_id.json"
    printf 'Completed fixture retains original %s at %s; current published input %s is observation only.\n' "$(jq -r .tag "$retained_target")" "$(jq -r .commit "$retained_target")" "$(jq -r .tag "$selected_target")"
    if [[ "$fixture_role" == custom ]]; then
      provider_stopped
      preserved_files "resume-before-$run_id"
    fi
  fi
  if [[ "$fixture_role" == custom && "$completed" != true ]]; then
    prepare_operator_environment
    if [[ ! -f "$evidence/http-fixture.json" ]]; then prepare_http; fi
  fi
  browser_start
  if [[ ! -f "$evidence/browser/fixture.json" ]] || ! jq -e '.firstRunComplete==true' "$evidence/browser/fixture.json" > /dev/null; then
    browser_native first-run "first-run-$run_id"
  fi
  browser_native all-before "all-before-$run_id"
  if [[ "$completed" == true ]]; then
    [[ $(jq -r .firstRunComplete "$evidence/browser/fixture.json") == true ]]
    if [[ "$fixture_role" == custom ]]; then
      [[ $(jq -r .httpAfterComplete "$evidence/browser/fixture.json") == true ]]
      provider_stopped
    fi
  elif [[ "$fixture_role" == default ]]; then
    check_target "$selected_target" "$evidence/resume-$run_id.json"
    # Re-observe the real no-op without replacing any earlier proof files.
    local saved_evidence=$evidence
    mkdir -m 700 "$evidence/noop-$run_id"
    cp "$evidence/identity.json" "$evidence/noop-$run_id/identity.json"
    evidence="$evidence/noop-$run_id"
    noop_native
    evidence=$saved_evidence
  else
    if ! jq -e '.httpConsentComplete==true' "$evidence/browser/fixture.json" > /dev/null; then browser_native http-consent "http-consent-$run_id"; fi
    if ! jq -e '.httpBeforeComplete==true' "$evidence/browser/fixture.json" > /dev/null; then
      # A failed command may not be silently retried: inspect its native state.
      if jq -e '.httpBeforeAttempted==true' "$evidence/browser/fixture.json" > /dev/null; then
        printf 'Offline dependency baseline has an unresolved prior attempt; inspect its native result and private state before a bounded continuation.\n' >&2
        return 75
      fi
      stop_provider
      browser_native http-before "http-before-$run_id"
      cp "$evidence/browser/$(< "$evidence/last-browser-label.txt")-consumers.json" "$evidence/http-before-consumers.json"
    fi
    provider_stopped
    browser_stop
    if [[ ! -e "$evidence/update.status" ]]; then update_native; else [[ $(< "$evidence/update.status") == 0 ]]; fi
    browser_start
    if ! jq -e '.httpAfterComplete==true' "$evidence/browser/fixture.json" > /dev/null; then browser_native http-after "http-after-$run_id"; fi
    provider_stopped
  fi
  browser_native all-after "all-after-$run_id"
  if [[ "$completed" == true && "$fixture_role" == custom ]]; then
    provider_stopped
    preserved_files "resume-after-$run_id"
    cmp "$evidence/preserved-resume-before-$run_id.sha256" "$evidence/preserved-resume-after-$run_id.sha256"
  fi
  snapshot "all-$run_id"
  protection after-all
  jq -n --arg tree "$(jq -r .source.tree "$guard_manifest")" --arg ctid "$ctid" --arg run "$run_id" --argjson retained "$completed" \
    '{completed:true,ctid:$ctid,sourceTree:$tree,run:$run,retainedCompleteResume:$retained,installedConsumers:true,setupAndNoteMutationsResumedWithoutReplay:true}' > "$evidence/all-$run_id.json"
  browser_stop
  browser_unit=''
  pct shutdown "$ctid" --timeout 60
  [[ $(pct status "$ctid") == 'status: stopped' ]]
  printf 'Complete native entrypoint CT%s observed; owned fixture stopped with data retained\n' "$ctid"
}

case "$stage" in
  all) all_native ;;
  update) update_native ;;
  force-measure)
    [[ "$completed" == true && "$fixture_role" == custom ]]
    resume_native
    bind_source
    provider_stopped
    update_native force
    browser_start
    browser_native http-force "http-force-$run_id"
    provider_stopped
    browser_native all-after "force-all-after-$run_id"
    protection after-force
    ;;
  install) install_native ;;
  checkpoint) checkpoint_native ;;
  inspect)
    owned
    snapshot inspection
    ;;
  first-run | finish-settings | verify) browser_native "$stage" ;;
  restart) restart_native ;;
  noop) noop_native ;;
  http-prepare)
    protection before-http
    resume_native
    bind_source
    prepare_http
    ;;
  http-consent)
    owned
    browser_start
    browser_native http-consent "http-consent-$run_id"
    ;;
  http-before)
    owned
    stop_provider
    browser_native http-before "http-before-$run_id"
    cp "$evidence/browser/$(< "$evidence/last-browser-label.txt")-consumers.json" "$evidence/http-before-consumers.json"
    ;;
  stop)
    owned
    pct shutdown "$ctid" --timeout 60
    [[ $(pct status "$ctid") == 'status: stopped' ]]
    ;;
  *)
    printf 'Native acceptance stage not yet implemented: %s\n' "$stage" >&2
    exit 64
    ;;
esac
