"""Finite native BookOrbit consumer; secrets and app logs stay in the owned CT."""
import hashlib
import json
import math
import os
from pathlib import Path
import subprocess
import tempfile
import time

from entrypoint import admit_direct


REMOTE = r'''
from pathlib import Path
import hashlib,io,json,os,secrets,shutil,stat,subprocess,sys,threading,time,urllib.error,urllib.parse,urllib.request,zipfile
P=Path('/var/lib/bookorbit-native-proof')
APP=Path('/opt/bookorbit')
def cmd(*args,seconds=30):
 r=subprocess.run(args,capture_output=True,timeout=seconds)
 assert r.returncode==0,'native command failed: '+args[0]
 return r.stdout.decode().strip()
def private(name,data):
 p=P/name
 fd=os.open(p,os.O_WRONLY|os.O_CREAT|os.O_TRUNC,0o600)
 with os.fdopen(fd,'w') as f:json.dump(data,f,sort_keys=True)
 p.chmod(0o600)
def state():return json.loads((P/'private-state.json').read_text())
def emit(label,**facts):print(json.dumps(dict(label=label,**facts),sort_keys=True),flush=True)
def provenance(label):
 # Pinned upstream commit 6f8f5f4818eb737dc4d78fc5b5294fc3adb26860,
 # three selected-release contract files, not an all-commit manifest.
 expected={
  'package.json':'bbbece86aa9e104cbf17a855d8207f5debd9a1d475e8f0266ed0d88f2bd8362e',
  'pnpm-lock.yaml':'9f61e754620ccdd6d9fcdf500c882ebb3e7e89dde07215b628b15b3a2fa084d4',
  'Dockerfile':'5ec48241a736df30a6dab726a64db0263d7eeeaa7d22ab8f954c9e5444d251f9',
 }
 assert all(hashlib.sha256((APP/name).read_bytes()).hexdigest()==digest for name,digest in expected.items()),'selected-release contract bytes differ'
 version=Path('/root/.bookorbit').read_text().strip();assert version.lstrip('v')=='3.7.0'
 emit(label,selected_release='v3.7.0',selected_contract_files=3,contract_hashes_match=True,all_commit_manifest=False)
def env():
 return json.loads(cmd('/usr/bin/node','-e','console.log(JSON.stringify(require("node:util").parseEnv(require("fs").readFileSync("/opt/bookorbit/.env","utf8"))))'))
def db(sql,args=()):
 code=''' + 'r"""' + r'''
const {Client}=require('/opt/bookorbit/server/node_modules/pg');
const fs=require('fs'),util=require('util');
const e=util.parseEnv(fs.readFileSync('/opt/bookorbit/.env','utf8'));
(async()=>{const c=new Client({connectionString:e.DATABASE_URL});await c.connect();try{await c.query('BEGIN READ ONLY');const r=await c.query(process.argv[1],JSON.parse(process.argv[2]));await c.query('COMMIT');console.log(JSON.stringify(r.rows));}finally{await c.end();}})().catch(()=>process.exit(1));
''' + '"""' + r'''
 return json.loads(cmd('/usr/bin/node','-e',code,sql,json.dumps(args)))
def api(method,path,data=None,raw=None,headers=None,auth=True):
 s=state();h={} if headers is None else dict(headers)
 if auth:h['Authorization']='Bearer '+s['token']
 if data is not None:raw=json.dumps(data).encode();h['Content-Type']='application/json'
 request=urllib.request.Request('http://127.0.0.1:'+str(s['port'])+'/api/v1/'+path,raw,h,method=method)
 try:
  with urllib.request.urlopen(request,timeout=25) as response:
   body=response.read();return json.loads(body) if body and 'json' in response.headers.get('Content-Type','') else body
 except urllib.error.HTTPError as error:raise AssertionError('native API failed: '+method+' '+path+' status '+str(error.code)) from None
def ready():
 end=time.monotonic()+120
 while True:
  try:
   s=state()
   with urllib.request.urlopen('http://127.0.0.1:'+str(s['port'])+'/api/v1/health',timeout=4) as response:
    if response.status==200:break
  except (OSError,urllib.error.HTTPError):pass
  assert time.monotonic()<end,'native app health deadline'
  time.sleep(1)
 pid=int(cmd('systemctl','show','bookorbit','-p','MainPID','--value'));assert pid>0
 birth=Path('/proc/'+str(pid)+'/stat').read_text().split(') ',1)[1].split()[19]
 values=dict(v.split(b'=',1) for v in Path('/proc/'+str(pid)+'/environ').read_bytes().split(b'\0') if b'=' in v)
 assert values[b'TMPDIR']==b'/var/lib/scripts-underground-test/tmp'
 assert int(cmd('systemctl','show','bookorbit','-p','MainPID','--value'))==pid and Path('/proc/'+str(pid)+'/stat').read_text().split(') ',1)[1].split()[19]==birth
 return pid
def login():
 s=state();r=api('POST','auth/login',dict(username=s['username'],password=s['password']),auth=False);s['token']=r['accessToken'];private('private-state.json',s)
def epub():
 buf=io.BytesIO()
 with zipfile.ZipFile(buf,'w') as z:
  z.writestr('mimetype','application/epub+zip',compress_type=zipfile.ZIP_STORED)
  z.writestr('META-INF/container.xml','<?xml version="1.0"?><container version="1.0" xmlns="urn:oasis:names:tc:opendocument:xmlns:container"><rootfiles><rootfile full-path="OPS/package.opf" media-type="application/oebps-package+xml"/></rootfiles></container>')
  z.writestr('OPS/package.opf','<?xml version="1.0"?><package xmlns="http://www.idpf.org/2007/opf" version="3.0" unique-identifier="id"><metadata xmlns:dc="http://purl.org/dc/elements/1.1/"><dc:identifier id="id">urn:su:bookorbit:owned</dc:identifier><dc:title>BookOrbit native proof</dc:title><dc:creator>ScriptsUnderground</dc:creator><dc:language>en</dc:language></metadata><manifest><item id="chapter" href="chapter.xhtml" media-type="application/xhtml+xml"/></manifest><spine><itemref idref="chapter"/></spine></package>')
  z.writestr('OPS/chapter.xhtml','<html xmlns="http://www.w3.org/1999/xhtml"><head><title>Owned proof</title></head><body><p>BookOrbit native consumer owns these words.</p></body></html>')
 # ZipInfo defaults to a fixed DOS epoch; normalize generated member metadata.
 stable=io.BytesIO()
 with zipfile.ZipFile(buf) as source,zipfile.ZipFile(stable,'w') as output:
  for name in source.namelist():output.writestr(zipfile.ZipInfo(name),source.read(name))
 return stable.getvalue()
def upload(library,name,raw):
 boundary='su-'+secrets.token_hex(12)
 body=('--'+boundary+'\r\nContent-Disposition: form-data; name="file"; filename="'+name+'"\r\nContent-Type: application/octet-stream\r\n\r\n').encode()+raw+('\r\n--'+boundary+'--\r\n').encode()
 return api('POST','libraries/'+str(library)+'/upload',raw=body,headers={'Content-Type':'multipart/form-data; boundary='+boundary})
def filefacts(path):
 p=Path(path);s=p.stat();return dict(bytes=s.st_size,sha256=hashlib.sha256(p.read_bytes()).hexdigest(),inode=s.st_ino,uid=s.st_uid,gid=s.st_gid,mode=stat.S_IMODE(s.st_mode))
def rootfacts():
 link=APP.lstat();physical=APP.resolve(strict=True);target=physical.stat()
 assert stat.S_ISLNK(link.st_mode) and physical==Path('/srv/bookorbit') and stat.S_ISDIR(target.st_mode)
 return dict(alias=str(APP),link=os.readlink(APP),alias_dev=link.st_dev,alias_inode=link.st_ino,alias_mode=stat.S_IMODE(link.st_mode),alias_uid=link.st_uid,alias_gid=link.st_gid,
  physical=str(physical),root_dev=target.st_dev,root_inode=target.st_ino,root_mode=stat.S_IMODE(target.st_mode),root_uid=target.st_uid,root_gid=target.st_gid)
def observed(label):
 ready();login();s=state()
 assert rootfacts()==s['root_facts']
 assert api('GET','auth/me')['username']==s['username']
 cards=api('POST','libraries/'+str(s['library'])+'/books',{})
 assert any(int(row['id'])==s['book'] for row in cards['items'])
 info=api('GET','epub/'+str(s['book'])+'/info')
 text=api('GET','epub/'+str(s['book'])+'/file/'+urllib.parse.quote(info['spine'][0]['href'],safe='/'))
 assert b'BookOrbit native consumer owns these words.' in text
 assert api('GET','user-preferences/theme')['settings']==s['theme']
 progress=api('GET','reading-progress?fileId='+str(s['file']))['items'];assert len(progress)==1 and float(progress[0]['percentage'])==37 and progress[0]['text']['cfi']==s['cfi']
 rows=db('SELECT id, absolute_path FROM public.book_files WHERE book_id=$1 ORDER BY id',[s['book']]);assert len(rows)==1
 libraries=db('SELECT path FROM public.library_folders ORDER BY path')
 assert s['library_path'] in [row['path'] for row in libraries] and Path(s['library_path']).is_relative_to(APP.resolve())
 assert Path(rows[0]['absolute_path']).is_relative_to(Path(s['library_path']))
 assert filefacts(rows[0]['absolute_path'])==s['book_fact']
 ledger=db('SELECT hash,created_at FROM drizzle.__drizzle_migrations ORDER BY id');assert ledger==s['ledger'] and ledger
 if 'protected' in s:
  assert {name:filefacts(name) for name in s['protected']}==s['protected']
  current=env();assert all(current[k]==v for k,v in s['keys'].items())
  assert {k:v for k,v in current.items() if k!='APP_VERSION'}==s['config_values']
  config=(APP/'.env').stat();assert dict(mode=stat.S_IMODE(config.st_mode),uid=config.st_uid,gid=config.st_gid)==s['config_access']
  assert current['PORT']=='4555' and current['APP_URL']=='http://127.0.0.1:4555'
  assert (Path('/etc/systemd/system/bookorbit.service').read_bytes()==(P/'unit.before').read_bytes())
 emit(label,account=True,library=True,reader_owned_text=True,book_bytes_inode_metadata=True,preference=True,progress=37,migrations=len(ledger),keys_equal=True)
 emit(label+'-root',root=s['root_facts'],physical_library=s['library_path'],physical_book=rows[0]['absolute_path'],book=s['book_fact'],config_inode_equality_claimed=False)
def build(role):
 start=time.monotonic();free=[];done=threading.Event()
 def sample():
  while not done.is_set():free.append(os.statvfs('/').f_bavail*os.statvfs('/').f_frsize);done.wait(1)
 thread=threading.Thread(target=sample);thread.start()
 try:
  with (P/(role+'.private.log')).open('xb') as log:
   os.chmod(P/(role+'.private.log'),0o600)
   r=subprocess.run(['timeout','2400s','bash',str(P/(role+'.sh'))],stdout=log,stderr=log,timeout=2420)
  assert r.returncode==0,'native cold '+role+' failed; private log retained'
 finally:
  done.set();thread.join(timeout=3)
  peak=Path('/sys/fs/cgroup/memory.peak')
  facts=dict(seconds=round(time.monotonic()-start,2),min_root_free_bytes=min(free),cgroup_memory_peak=int(peak.read_text()) if peak.exists() else None,root_total_bytes=os.statvfs('/').f_blocks*os.statvfs('/').f_frsize)
  private(role+'-measurements.json',facts);emit(role+'-peak',**facts)
action=sys.argv[1]
if action=='bootstrap':
 assert os.geteuid()==0 and os.environ['TMPDIR']=='/var/lib/scripts-underground-test/tmp';P.mkdir(mode=0o700)
elif action in ('install','update'):build(action)
elif action=='provenance':provenance(sys.argv[2])
elif action=='relocate':
 private('private-state.json',dict(port=80))
 ready();target=Path('/srv/bookorbit');entry=APP.lstat()
 assert stat.S_ISDIR(entry.st_mode) and not APP.is_symlink() and not target.exists() and not target.is_symlink()
 assert APP.stat().st_dev==target.parent.stat().st_dev
 unit=Path('/etc/systemd/system/bookorbit.service').read_bytes();(P/'relocate-unit.before').write_bytes(unit)
 cmd('systemctl','stop','bookorbit');assert cmd('systemctl','show','bookorbit','-p','MainPID','--value')=='0'
 APP.rename(target);APP.symlink_to(target,target_is_directory=True)
 assert target.stat().st_dev==entry.st_dev and target.stat().st_ino==entry.st_ino
 s=state();s['root_facts']=rootfacts();private('private-state.json',s)
 cmd('systemctl','start','bookorbit');ready()
 assert Path('/etc/systemd/system/bookorbit.service').read_bytes()==unit
 emit('canonical-root-fixture',root=s['root_facts'],normal_unit_unchanged=True,same_filesystem_rename=True,source_copy=False)
elif action=='setup':
 s=state();s.update(port=80,username='su-bookorbit',password='OwnedNative9-'+secrets.token_hex(16));private('private-state.json',s)
 ready();e=env();assert e['PORT']=='80'
 assert stat.S_IMODE((APP/'.env').stat().st_mode)==0o600 and stat.S_IMODE(Path('/root/bookorbit.creds').stat().st_mode)==0o600
 keys={k:e[k] for k in ('JWT_SECRET','SETUP_BOOTSTRAP_TOKEN','EMAIL_ENCRYPTION_KEY','MIGRATION_ENCRYPTION_KEY','BOOK_REQUEST_ENCRYPTION_KEY')};assert len(set(keys.values()))==5
 s=state();r=api('POST','auth/setup',dict(username=s['username'],password=s['password'],name='Owned native proof',email='native@example.invalid'),headers={'x-setup-token':e['SETUP_BOOTSTRAP_TOKEN']},auth=False);s['token']=r['accessToken'];private('private-state.json',s)
 library=APP.resolve()/'custom library';library.mkdir();lib=api('POST','libraries',dict(name='Native proof',icon='book',folders=[str(library)],watch=False));s['library']=lib['id'];s['library_path']=str(library);private('private-state.json',s)
 uploaded=upload(s['library'],'owned.epub',epub());s['book']=uploaded['bookId']
 rows=db('SELECT id, absolute_path FROM public.book_files WHERE book_id=$1 ORDER BY id',[s['book']]);assert len(rows)==1;s['file']=rows[0]['id'];s['book_fact']=filefacts(rows[0]['absolute_path']);s['ledger']=db('SELECT hash,created_at FROM drizzle.__drizzle_migrations ORDER BY id')
 s['theme']=dict(theme='dark',accent='blue',radius='rounded',background='none',brightness=37);s['cfi']='epubcfi(/6/2!/4/2/1:7)';private('private-state.json',s)
 api('PUT','user-preferences/theme',dict(settings=s['theme']));api('PUT','reading-progress',dict(writes=[dict(fileId=s['file'],kind='text',percentage=37,text=dict(cfi=s['cfi']))]))
 observed('fresh-outcome')
elif action=='custom':
 cmd('systemctl','stop','bookorbit');assert cmd('systemctl','show','bookorbit','-p','MainPID','--value')=='0'
 old=Path('/opt/bookorbit-data');new=APP/'custom data';old.rename(new)
 imports=APP/'custom imports';imports.mkdir();(imports/'owned').write_text('preserve imports')
 e=env();e.update(PORT='4555',APP_URL='http://127.0.0.1:4555',CLIENT_URL='http://127.0.0.1:4555',APP_DATA_PATH=str(new),BOOK_DOCK_PATH=str(new/'book-bucket'),MIGRATION_IMPORT_ROOT=str(imports))
 (APP/'.env').write_text(''.join(k+'='+v+'\n' for k,v in e.items()))
 s=state();s['port']=4555;s['keys']={k:e[k] for k in ('JWT_SECRET','SETUP_BOOTSTRAP_TOKEN','EMAIL_ENCRYPTION_KEY','MIGRATION_ENCRYPTION_KEY','BOOK_REQUEST_ENCRYPTION_KEY')}
 s['config_values']={k:v for k,v in e.items() if k!='APP_VERSION'};config=(APP/'.env').stat();s['config_access']=dict(mode=stat.S_IMODE(config.st_mode),uid=config.st_uid,gid=config.st_gid)
 (new/'owned').write_text('preserve data');s['protected']={str(p):filefacts(p) for p in (new/'owned',imports/'owned')};private('private-state.json',s)
 (P/'unit.before').write_bytes(Path('/etc/systemd/system/bookorbit.service').read_bytes())
 cmd('systemctl','start','bookorbit');observed('custom-before-update')
elif action=='observe':observed(sys.argv[2])
elif action=='djvu':
 pgm=P/'owned.pgm';pgm.write_bytes(b'P5\n16 16\n255\n'+bytes(range(256)))
 target=P/'owned.djvu';cmd('c44',str(pgm),str(target));assert cmd('djvused',str(target),'-e','n')=='1'
 output=P/'owned.ppm';cmd('ddjvu','-format=ppm',str(target),str(output));assert output.read_bytes().startswith(b'P6') and output.stat().st_size>256
 emit('djvu-consumer',pages=1,decoded_pixels=True,input_sha256=hashlib.sha256(target.read_bytes()).hexdigest(),output_bytes=output.stat().st_size)
else:raise AssertionError('unknown native probe action')
'''


def main():
    context = admit_direct('maintenance-bookorbit-native', [])
    root = Path(context.document['source']['path'])
    # Identify this supervised operation's actual ancestor birth, including CT
    # preparation time before the app consumer started. No new ambient clock input.
    expected = ['/usr/bin/python3', '-B', str(root / 'tests/run'), '--run', '--context', str(context.path), '--suite', context.operation['suite'], '--mode', context.operation['mode']]
    pid = os.getpid()
    operation_started = None
    own_cgroup = Path('/proc/self/cgroup').read_bytes()
    while pid > 1:
        proc = Path('/proc') / str(pid)
        fields = (proc / 'stat').read_text().split(') ', 1)[1].split()
        argv = (proc / 'cmdline').read_bytes().rstrip(b'\0').decode().split('\0')
        if argv == expected:
            assert (proc / 'cgroup').read_bytes() == own_cgroup
            assert (proc / 'stat').read_text().split(') ', 1)[1].split()[19] == fields[19]
            operation_started = int(fields[19]) / os.sysconf('SC_CLK_TCK')
            break
        pid = int(fields[1])
    assert operation_started is not None and 0 < operation_started <= time.monotonic(), 'supervised operation birth unavailable'
    assert context.operation['deadline'] == 3600, 'original operation allowance required'
    ctid = str(context.operation['nested'][0]['ctid'])
    work = Path(tempfile.mkdtemp(prefix='bookorbit-native.', dir=os.environ['TMPDIR']))
    target = '/var/lib/bookorbit-native-proof'

    def pct(*args, seconds=180):
        remaining = 3600 - (time.monotonic() - operation_started)
        assert remaining > 0, 'original operation allowance exhausted'
        result = subprocess.run(['/usr/sbin/pct', *args], capture_output=True, text=True, timeout=min(seconds, remaining))
        if result.returncode:
            raise RuntimeError('native typed command failed: ' + args[0])
        return result.stdout

    def execute(*argv, seconds=180):
        return pct('exec', ctid, '--', *argv, seconds=seconds)

    def push(raw, name):
        stage = work / name
        stage.write_bytes(raw)
        pct('push', ctid, str(stage), target + '/' + name)
        assert execute('sha256sum', target + '/' + name).split()[0] == hashlib.sha256(raw).hexdigest()
        stage.unlink()

    def probe(*args, seconds=180):
        output = execute('/usr/bin/python3', '-B', target + '/probe.py', *args, seconds=seconds)
        print(output, end='', flush=True)
        return [json.loads(line) for line in output.splitlines() if line.startswith('{')]

    execute('/usr/bin/python3', '-B', '-c', REMOTE, 'bootstrap')
    push(REMOTE.encode(), 'probe.py')
    # Generic runtime transport is not the full LXC baseline; sudo is one of the
    # normal framework baseline prerequisites used by PostgreSQL's existing helper.
    execute('/bin/sh', '-ec', 'export DEBIAN_FRONTEND=noninteractive; apt install -y sudo', seconds=180)
    setup = r'''
set -euo pipefail
ROOT="$1"
P=/var/lib/bookorbit-native-proof
# Read the selected script's defaults, not creator environment overrides.
unset var_cpu var_ram var_disk
curl() { :; }
source "$ROOT/scripts/lxc/bookorbit.sh"
unset -f curl
source "$ROOT/misc/bundle.func"
export APP=BookOrbit NSAPP=bookorbit REPO_BASE="$2"
export var_lxc_tmpdir=/var/lib/scripts-underground-test/tmp
# Reproduce the normal creator's identity at both finite cold entry points.
prefix='export APPLICATION="$APP"; var_appversion=v3.7.0; '
printf -v install_requirements 'declare -- LXC_REQUIRED_CPU=%q\ndeclare -- LXC_REQUIRED_RAM=%q\n' "$var_cpu" "$var_ram"
_write_bundle install install_script "$ROOT/misc" --script-id bookorbit -- --requirements "$var_cpu" "$var_ram" -- "${install_requirements}${prefix}install_script" > "$P/install.sh"
_write_bundle update update_script "$ROOT/misc" --script-id bookorbit -- --requirements "$var_cpu" "$var_ram" -- "${prefix}run_update_script --clean" > "$P/update.sh"
chmod 0700 "$P/install.sh" "$P/update.sh"
python3 - "$P" "$var_cpu" "$var_ram" "$var_disk" "$ROOT/tests/lib/bookorbit-native.py" <<'PY'
import ast,json,pathlib,re,sys
p=pathlib.Path(sys.argv[1]);cpu,ram,disk=map(int,sys.argv[2:5])
assert min(cpu,ram,disk)>0
module=ast.parse(pathlib.Path(sys.argv[5]).read_text())
main=next(n for n in module.body if isinstance(n,ast.FunctionDef) and n.name=='main')
calls=[n.value for n in main.body if isinstance(n,(ast.Assign,ast.Expr)) and isinstance(n.value,ast.Call)]
probes=[n.args[0].value for n in calls if isinstance(n.func,ast.Name) and n.func.id=='probe']
assert probes.index('install')<probes.index('provenance')<probes.index('relocate')<probes.index('setup')
for role in ('install','update'):
 text=(p/(role+'.sh')).read_text()
 for key,value in [('CPU',cpu),('RAM',ram)]:
  assert re.findall(r'^declare -- LXC_REQUIRED_'+key+r'=([0-9]+)$',text,re.M)==[str(value)],'generated bundle requirement mismatch'
print(json.dumps(dict(cpu=cpu,ram=ram,disk=disk,bundles_checked=['install','update']),sort_keys=True))
PY
'''
    requirements = json.loads(execute('/bin/bash', '-c', setup, '--', str(root), os.environ['SU_TEST_REPO_BASE']))
    selected = {key: context.operation['native'][key] for key in ('cpu', 'ram', 'disk')}
    assert {key: requirements[key] for key in selected} == selected, 'selected native allocation must match published source defaults'
    assert int(execute('/usr/bin/nproc')) == selected['cpu'], 'actual native CPU differs from selected allocation'
    from dataclasses import asdict
    from bookorbit_memory import observe
    from test_pve import NativePVE
    lineage_path = Path(context.operation['native']['lineage'])
    lineage_bytes = lineage_path.read_bytes()
    lineage = json.loads(lineage_bytes)
    assert lineage['status'] == 0 and lineage['source'] == context.document['source']['tree_sha256']
    assert lineage['requested'] == context.operation['nested'][0], 'native creation lineage mismatch'
    receiving_root = list(map(int, execute('/usr/bin/stat', '-c', '%d %i', '/').split()))

    def memory_owner():
        # Existing read-only identity observer binds tag/name/MAC/config/LVID.
        assert lineage_path.read_bytes() == lineage_bytes, 'native lineage changed'
        current = NativePVE.observe_static(int(ctid), context.operation['native'])
        assert current is not None and asdict(current) == lineage['observed'], 'native creation changed'
        pid_text = subprocess.check_output(['/usr/bin/lxc-info', '-n', ctid, '-pH'], text=True, timeout=20).strip()
        assert pid_text.isascii() and pid_text.isdecimal(), 'owned init PID unavailable'
        return dict(pid=int(pid_text), root=receiving_root, creation=asdict(current),
                    config_sha256=hashlib.sha256(Path('/etc/pve/lxc/' + ctid + '.conf').read_bytes()).hexdigest())

    memory = observe(memory_owner, selected['ram'] * 1024**2)
    print('BOOKORBIT_NATIVE_REQUIREMENTS ' + json.dumps(dict(requirements=requirements, selected=selected, actual_memory_max=memory['effective_memory_max'], memory_observation=memory), sort_keys=True), flush=True)
    install_records = probe('install', seconds=2450)
    probe('provenance', 'after-install-source-contract')
    probe('relocate')
    probe('setup')
    probe('djvu')
    execute('systemctl', 'restart', 'bookorbit')
    probe('observe', 'after-service-restart')
    measured, = [row for row in install_records if row.get('label') == 'install-peak']
    for key in ('cgroup_memory_peak', 'root_total_bytes', 'min_root_free_bytes'):
        assert type(measured.get(key)) is int and measured[key] >= 0, 'missing/malformed install measurement: ' + key
    assert measured['cgroup_memory_peak'] > 0 and measured['root_total_bytes'] > 0
    assert measured['min_root_free_bytes'] <= measured['root_total_bytes']
    duration = measured.get('seconds')
    assert type(duration) in (int, float) and math.isfinite(duration) and duration > 0, 'missing/malformed install duration'
    elapsed = time.monotonic() - operation_started
    assert math.isfinite(elapsed) and elapsed >= duration
    remaining = 3600 - elapsed
    projected = 1.25 * duration + 180
    used = measured['root_total_bytes'] - measured['min_root_free_bytes']
    unsafe = measured['cgroup_memory_peak'] > selected['ram'] * 1024**2 or used > selected['disk'] * 1024**3
    print('BOOKORBIT_PRE_UPDATE_GATE ' + json.dumps(dict(install=measured,operation_elapsed_seconds=elapsed,remaining_seconds=remaining,projected_update_seconds=projected,formula='1.25 * install_seconds + 180',observed_peak_root_used_bytes=used,default_resource_issue=unsafe,defaults_safe_proven=False,cpu2_qualified=False),sort_keys=True),flush=True)
    assert remaining >= projected, 'insufficient original operation allowance for projected update; update not attempted'
    probe('custom')
    probe('update', seconds=2450)
    probe('provenance', 'after-update-source-contract')
    probe('observe', 'after-cold-forced-update')
    print('BOOKORBIT_OPERATION_TIMING ' + json.dumps(dict(elapsed_seconds=time.monotonic()-operation_started,allowance_seconds=3600,defaults_safe_proven=False,cpu2_qualified=False),sort_keys=True),flush=True)
    print('BOOKORBIT_NATIVE_PASS actual cold install/build/database/setup/upload/reader/settings/progress/restart/update/DjVu; secrets retained inside CT', flush=True)


if __name__ == '__main__':
    main()
