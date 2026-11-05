#!/usr/bin/env bash
# One actual native consumer inside the generic runtime owner's delegated CT.
# Outer creation, publisher, shutdown and external preservation remain owner-held.
set -euo pipefail
python3 -B "$(dirname -- "${BASH_SOURCE[0]}")/lib/entrypoint.py" maintenance-kosmozoo-native "$@" || exit $?
[[ "${SU_TEST_GUARD_ONLY:-0}" != 1 ]] || exit 0
ROOT=$(realpath "$(dirname "${BASH_SOURCE[0]}")/..")
: "${TMPDIR:?disk-backed receiver TMPDIR required}"
[[ "$EUID" == 0 && "$TMPDIR" == /var/lib/scripts-underground-test/tmp ]] || exit 65
case "$(findmnt -rn -T "$TMPDIR" -o FSTYPE)" in '' | tmpfs | ramfs) exit 65 ;; esac
work=$(mktemp -d "$TMPDIR/kosmozoo-native.XXXXXXXX")
printf 'NATIVE_EVIDENCE %s\n' "$work"
native_evidence_exit() {
  local status=$? capture=0
  trap - EXIT
  if [[ -d "$work" ]]; then
    tar -czf "$work.evidence.tar.gz" -C "$work" . || capture=$?
    if [[ "$capture" == 0 ]]; then
      printf 'KOSMOZOO_NATIVE_EVIDENCE_TGZ_SHA256 '
      sha256sum "$work.evidence.tar.gz" || capture=$?
      printf 'KOSMOZOO_NATIVE_EVIDENCE_TGZ_BASE64 '
      base64 -w0 "$work.evidence.tar.gz" || capture=$?
      printf '\n'
    fi
  fi
  [[ "$status" != 0 ]] || status=$capture
  exit "$status"
}
trap native_evidence_exit EXIT
# Fresh fixture only: no operator mount or existing source is modified.
[[ ! -e /sources && ! -e /opt/kosmozoo && ! -e /etc/kosmozoo ]] || exit 65
mkdir -p /sources/images
base64 -d > /sources/images/pixel.png <<< 'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+a9e8AAAAASUVORK5CYII='
publisher=$REPO_BASE
curl() { :; }
source "$ROOT/scripts/lxc/kosmozoo.sh"
unset -f curl
source "$ROOT/misc/bundle.func"
export APP=Kosmozoo NSAPP=kosmozoo REPO_BASE="$publisher"
export var_lxc_tmpdir="$TMPDIR" var_lxc_kosmozoo_hosts='local=folder:/sources/images'
export var_lxc_kosmozoo_initial_release=v0.3.0
_write_bundle install install_script "$ROOT/misc" 'install_script' > "$work/install.sh"
_write_bundle update update_script "$ROOT/misc" 'run_update_script "$@"' > "$work/update.sh"
timeout --signal=TERM --kill-after=30 1200 bash "$work/install.sh" > "$work/install.log" 2>&1
install -m 0755 "$work/update.sh" /usr/local/sbin/update
ln -s /usr/local/sbin/update /usr/bin/update

# Prove effective operator overrides and a truly cold native process without any
# external application runtime in PATH. The updater must preserve these bytes.
mkdir -p /data/operator-tmp /etc/systemd/system/kosmozoo.service.d
chown "$(id -u kosmozoo):$(id -g kosmozoo)" /data/operator-tmp
cat > /etc/kosmozoo/operator.env << 'ENV'
TMPDIR="/data/operator-tmp"
PATH="/nonexistent"
KOZMOZOO_PORT="080"
KZ_ACCEPTANCE_LITERAL="operator \$ \` % \" \\ roundtrip"
ENV
chmod 0600 /etc/kosmozoo/operator.env
cat > /etc/systemd/system/kosmozoo.service.d/operator.conf << 'UNIT'
[Service]
EnvironmentFile=/etc/kosmozoo/operator.env
UNIT
systemctl daemon-reload
timeout 60 systemctl restart kosmozoo
python3 - "$work" << 'CONSUMER'
import base64,hashlib,json,os,pathlib,pwd,shutil,sqlite3,stat,subprocess,sys,time,urllib.request,urllib.error
w=pathlib.Path(sys.argv[1]); origin='http://127.0.0.1'
account=pwd.getpwnam('kosmozoo');uid=account.pw_uid;gid=account.pw_gid
def sha(raw):return hashlib.sha256(raw).hexdigest()
def command(*args):return subprocess.run(args,check=True,capture_output=True,text=True,timeout=90).stdout.strip()
def save_json(path,value):
    data=json.dumps(value,sort_keys=True,indent=2).encode()
    with path.open('xb') as out:out.write(data);out.flush();os.fsync(out.fileno())
def query_rows(connection,sql,parameters=()):
    cursor=connection.cursor()
    try:
        cursor.execute(sql,parameters)
        return [d[0] for d in cursor.description] if cursor.description else [],cursor.fetchall()
    finally:cursor.close()
def original_db_handles(include_private=False):
    handles={}
    for p in pathlib.Path('/proc/self/fd').iterdir():
        try:target=os.readlink(p)
        except FileNotFoundError:continue
        name=target.removesuffix(' (deleted)')
        if name in ('/data/state/metadata.db','/data/state/metadata.db-wal','/data/state/metadata.db-shm') or include_private and name.startswith(str(w)+'/') and pathlib.Path(name).name in ('metadata.db','metadata.db-wal','metadata.db-shm'):handles[p.name]=target
    return handles
def logical_snapshot(raw,view):
    view.mkdir(mode=0o700)
    for name in ('metadata.db','metadata.db-wal','metadata.db-shm'):
        if (raw/name).exists():shutil.copyfile(raw/name,view/name)
    connection=sqlite3.connect('file:'+str(view/'metadata.db')+'?mode=ro',uri=True)
    try:
        query_rows(connection,'PRAGMA query_only=ON');query_rows(connection,'BEGIN')
        _,schema=query_rows(connection,'select type,name,tbl_name,rootpage,sql from sqlite_master order by type,name');tables={}
        encode=lambda v:dict(blob=base64.b64encode(v).decode()) if isinstance(v,bytes) else v
        for kind,name,_,rootpage,sql in schema:
            if kind!='table':continue
            columns,rows=query_rows(connection,'select * from "'+name.replace('"','""')+'"')
            tables[name]=dict(columns=columns,rows=sorted([[encode(v) for v in row] for row in rows],key=lambda row:json.dumps(row,sort_keys=True)),rootpage=rootpage)
        _,version=query_rows(connection,'PRAGMA user_version')
        return dict(schema=schema,tables=tables,user_version=version[0][0])
    finally:connection.close()
def drained_snapshot(label):
    folder=w/label;folder.mkdir(mode=0o700);raw=folder/'raw';raw.mkdir(mode=0o700)
    facts=dict(main_pid=command('systemctl','show','kosmozoo','-p','MainPID','--value'),active=command('systemctl','show','kosmozoo','-p','ActiveState','--value'),observer_original_db_handles=original_db_handles(),observer_all_owned_sqlite_handles=original_db_handles(True),wall_ns=time.time_ns())
    save_json(folder/'drain-facts.json',facts)
    assert facts['main_pid']=='0' and facts['active']=='inactive' and not facts['observer_original_db_handles'] and not facts['observer_all_owned_sqlite_handles']
    physical={}
    for name in ('metadata.db','metadata.db-wal','metadata.db-shm'):
        path=pathlib.Path('/data/state')/name
        if not os.path.lexists(path):physical[name]=None;continue
        fd=os.open(path,os.O_RDONLY|os.O_NOFOLLOW|os.O_NOATIME)
        try:
            before=os.fstat(fd);save_json(folder/(name+'-source-kind.json'),dict(mode=before.st_mode,device=before.st_dev,inode=before.st_ino,bytes=before.st_size));assert stat.S_ISREG(before.st_mode);expected=hashlib.sha256()
            while chunk:=os.read(fd,1048576):expected.update(chunk)
            save_json(folder/(name+'-expected.json'),dict(sha256=expected.hexdigest(),bytes=before.st_size,device=before.st_dev,inode=before.st_ino,mode=stat.S_IMODE(before.st_mode),uid=before.st_uid,gid=before.st_gid))
            os.lseek(fd,0,os.SEEK_SET)
            with (raw/name).open('xb') as out:
                while chunk:=os.read(fd,1048576):out.write(chunk)
            after=os.fstat(fd);linked=path.lstat();copied=(raw/name).read_bytes();actual=sha(copied)
            record=dict(expected_sha256=expected.hexdigest(),actual_sha256=actual,bytes=len(copied),device=after.st_dev,inode=after.st_ino,uid=after.st_uid,gid=after.st_gid,mode=stat.S_IMODE(after.st_mode),mtime_ns=after.st_mtime_ns,ctime_ns=after.st_ctime_ns,first136_hex=copied[:136].hex())
            save_json(folder/(name+'-bytes.json'),record)
            if name=='metadata.db':
                size=int.from_bytes(copied[16:18],'big');size=65536 if size==1 else size
                record.update(page_size=size,pages=[dict(number=i//size+1,sha256=sha(copied[i:i+size])) for i in range(0,len(copied),size)],header={field:int.from_bytes(copied[o:o+4],'big') for o,field in {24:'change_counter',28:'database_pages',32:'freelist_first',36:'freelist_pages',40:'schema_cookie',44:'schema_format',48:'cache_size',52:'largest_root',56:'encoding',60:'user_version',64:'incremental_vacuum',68:'application_id',92:'version_valid_for',96:'sqlite_version_number'}.items()})
            save_json(folder/(name+'-actual.json'),record);physical[name]=record
            identity=lambda s:(s.st_dev,s.st_ino,s.st_size,s.st_mtime_ns,s.st_ctime_ns)
            assert stat.S_ISREG(linked.st_mode) and identity(before)==identity(after)==identity(linked) and expected.hexdigest()==actual and len(copied)==before.st_size
        finally:os.close(fd)
    logical=logical_snapshot(raw,folder/'view');save_json(folder/'logical.json',logical)
    remaining=original_db_handles(True);save_json(folder/'observer-handles-after.json',remaining);assert not remaining
    result=dict(label=label,physical=physical,logical=logical,drain=facts)
    save_json(folder/'snapshot.json',result);return result
def api(path,method='GET',body=None,raw=False,request_origin=None):
    data=None if body is None else json.dumps(body).encode()
    headers={'Content-Type':'application/json'}
    if request_origin is not None:headers['Origin']=request_origin
    req=urllib.request.Request(origin+path,data=data,method=method,headers=headers)
    with urllib.request.urlopen(req,timeout=15) as response:
        content=response.read()
    return content if raw else json.loads(content)
def process_birth(pid):return pathlib.Path('/proc/'+str(pid)+'/stat').read_text().split(') ',1)[1].split()[19]
def sqlite_mapping(pid,env,mappings):
 # v0.3.0 packaging/linux/inputs.json authenticates these complete SQLite bytes.
 # Deno names its extracted file from the executable and hashes, not "sqlite".
 expected='2e6eef9a727f081f0d453b4e5e6cbd8b9ef8b6f86cbf7681cbad444d3b0b55c8'
 tmp=env[b'TMPDIR'].decode();candidates=[]
 for line in mappings.splitlines():
  fields=line.split(maxsplit=5)
  if len(fields)!=6 or 'x' not in fields[1] or not fields[5].startswith(tmp+'/'):continue
  row=dict(map=line,path=fields[5],map_device=fields[3],map_inode=int(fields[4]))
  try:
   path=row['path'];assert not path.endswith(' (deleted)') and os.path.normpath(path)==path
   parent=os.open('/',os.O_RDONLY|os.O_DIRECTORY)
   try:
    for part in pathlib.Path(path).parts[1:-1]:
     child=os.open(part,os.O_RDONLY|os.O_DIRECTORY|os.O_NOFOLLOW,dir_fd=parent);os.close(parent);parent=child
    fd=os.open(pathlib.Path(path).name,os.O_RDONLY|os.O_NOFOLLOW|os.O_NOATIME,dir_fd=parent)
    try:
     before=os.fstat(fd);assert stat.S_ISREG(before.st_mode) and before.st_nlink>0 and before.st_uid==uid
     assert tuple(int(v,16) for v in fields[3].split(':'))==(os.major(before.st_dev),os.minor(before.st_dev)) and before.st_ino==row['map_inode']
     header=os.read(fd,64);os.lseek(fd,0,os.SEEK_SET);h=hashlib.sha256()
     while chunk:=os.read(fd,1048576):h.update(chunk)
     after=os.fstat(fd);linked=os.stat(pathlib.Path(path).name,dir_fd=parent,follow_symlinks=False)
     identity=lambda s:(s.st_dev,s.st_ino,s.st_size,s.st_mtime_ns,s.st_ctime_ns)
     assert identity(before)==identity(after)==identity(linked) and stat.S_ISREG(linked.st_mode)
     row.update(device=before.st_dev,inode=before.st_ino,bytes=before.st_size,uid=before.st_uid,gid=before.st_gid,mode=stat.S_IMODE(before.st_mode),sha256=h.hexdigest(),elf_header=header.hex(),regular_nonsymlink=True,stable_file_identity=True)
     assert header[:6]==b'\x7fELF\x02\x01' and int.from_bytes(header[18:20],'little')==62
    finally:os.close(fd)
   finally:os.close(parent)
  except (OSError,AssertionError) as error:row['error']=str(error) or 'mapping/file identity assertion failed'
  candidates.append(row)
 (w/('mapping-candidates-'+str(pid)+'-'+str(time.time_ns())+'.json')).write_text(json.dumps(candidates,sort_keys=True,indent=2))
 assert candidates and not any('error' in v for v in candidates)
 matched=[v for v in candidates if v['sha256']==expected]
 assert len({(v['device'],v['inode']) for v in matched})==1
 return matched
def ready():
    end=time.monotonic()+90
    while True:
        try:
            r=api('/api/runtime')
            pid=int(command('systemctl','show','kosmozoo','-p','MainPID','--value'));birth=process_birth(pid)
            proc=pathlib.Path('/proc/'+str(pid));mappings=(proc/'maps').read_text();status_raw=(proc/'status').read_text();env_raw=(proc/'environ').read_bytes()
            private=pathlib.Path('/data/state/engine-instance.json');s=private.stat();p=json.loads(private.read_bytes());socket=command('ss','-H','-lntp','sport = :80')
            (w/('ready-raw-'+str(pid)+'-'+str(time.time_ns())+'.json')).write_text(json.dumps(dict(pid=pid,birth=birth,runtime=r,private=p,private_stat=dict(uid=s.st_uid,gid=s.st_gid,mode=s.st_mode&0o777,inode=s.st_ino),maps=mappings,status=status_raw,environ_base64=base64.b64encode(env_raw).decode(),exe=os.readlink(proc/'exe'),socket=socket),sort_keys=True,indent=2))
            assert uid!=0 and gid!=0
            assert hashlib.sha256(pathlib.Path('/opt/kosmozoo/kosmozoo').read_bytes()).hexdigest()=='ff2486bfd42f0c50c0e48eb08a52ac9ec8eee826f873629e6e4cad90d0179d34'
            assert r['protocol']=='kosmozoo-runtime' and r['version']==1 and r['status']=='ready' and r['mode']=='serve'
            assert r['binding']=={'hostname':'0.0.0.0','port':80} and r['configuredBind']=='0.0.0.0'
            assert pathlib.Path('/proc/'+str(pid)+'/exe').resolve()==pathlib.Path('/opt/kosmozoo/kosmozoo')
            assert s.st_uid==uid and s.st_mode&0o777==0o600 and not private.is_symlink()
            status=dict(line.split(':',1) for line in status_raw.splitlines() if ':' in line)
            assert list(map(int,status['Uid'].split()))==[uid]*4 and list(map(int,status['Gid'].split()))==[gid]*4
            assert set(map(int,status['Groups'].split()))==set(os.getgrouplist('kosmozoo',gid))
            assert all(int(status[k].strip(),16)==1<<10 for k in ('CapEff','CapPrm','CapBnd','CapAmb'))
            assert r['app']['version']=='0.3.0'
            assert p['ownerPid']==pid and all(p[k]==r[k] for k in ('instance','sourceVersion','binding'))
            env=dict(v.split(b'=',1) for v in env_raw.split(b'\0') if v)
            assert env[b'PATH']==b'/nonexistent' and env[b'TMPDIR']==b'/data/operator-tmp' and env[b'KOZMOZOO_PORT']==b'080'
            assert env[b'KZ_ACCEPTANCE_LITERAL']==b'operator $ ` % " \\ roundtrip'
            assert 'pid='+str(pid)+',' in socket
            mapped=sqlite_mapping(pid,env,mappings)
            assert int(command('systemctl','show','kosmozoo','-p','MainPID','--value'))==pid and process_birth(pid)==birth and os.readlink(proc/'exe')=='/opt/kosmozoo/kosmozoo'
            assert api('/api/runtime')==r and json.loads(private.read_bytes())==p
            (w/('mapping-proof-'+str(pid)+'-'+str(time.time_ns())+'.json')).write_text(json.dumps(dict(pid=pid,birth=birth,runtime=r,sqlite=mapped,same_process_all_layers=True,full_raw_capture_precedes_assertions=True),sort_keys=True,indent=2))
            return r,pid
        except (OSError,ValueError,AssertionError):
            if time.monotonic()>=end:raise
            time.sleep(1)
image=pathlib.Path('/sources/images/pixel.png').read_bytes();digest=sha(image)
entry_path='/api/collections/local/entries/pixel.png'
judgment={'vote':'up','bookmark':True,'notes':{'pos':'native-preserved-judgment'}}
setting={'downvoteHides':False}
def observe(label):
 r,pid=ready()
 sources=api('/api/collections');assert sources['local']['address']=='folder:/sources/images'
 assert any(v['name']=='pixel.png' for v in api('/api/collections/local/entries'))
 served=api(entry_path+'/bytes',raw=True);assert served==image and sha(served)==digest
 row=api(entry_path);assert row['hash']==digest and row['extracted'] and row['width']==row['height']==1
 assert row['judgment']==judgment
 assert api('/api/settings/core.judgment')==setting
 export=api('/api/collections/local/feedback.json');assert export['entries']['pixel.png']==dict(hash=digest,**judgment)
 db=sqlite3.connect('file:/data/state/metadata.db?mode=ro',uri=True)
 try:
  _,rows=query_rows(db,'select hash,vote,bookmark,notes from entry where collection=? and name=?',('local','pixel.png'));stored=rows[0] if rows else None
 finally:db.close()
 handles=original_db_handles();save_json(w/(label+'-observer-handles.json'),handles);assert not handles
 assert stored and stored[0]==digest and stored[1]=='up' and stored[2]==1 and json.loads(stored[3])==judgment['notes']
 assert json.loads(pathlib.Path('/data/state/settings.json').read_bytes())['data']['core.judgment']==setting
 cached=pathlib.Path('/data/cache')/digest[:2]/digest;assert cached.read_bytes()==image
 result=dict(label=label,runtime=r,pid=pid,entry=row,settings=setting,sources=sources,feedback=export,image_sha256=digest,cache_sha256=sha(cached.read_bytes()),sqlite=list(stored))
 (w/(label+'.json')).write_text(json.dumps(result,sort_keys=True,indent=2));return result
ready()
api(entry_path+'/bytes',raw=True)
api(entry_path+'/judgment','PATCH',judgment,request_origin=origin)
api('/api/settings/core.judgment','PATCH',setting)
try:
 api(entry_path+'/judgment','PATCH',{'vote':'down'},request_origin='http://foreign.invalid')
 raise AssertionError('Foreign Origin mutation was accepted')
except urllib.error.HTTPError as error:
 assert error.code==403
assert api(entry_path)['judgment']==judgment
first=observe('before-restart')
protected=[pathlib.Path(p) for p in ('/opt/kosmozoo/kosmozoo','/root/.kosmozoo','/etc/kosmozoo/env','/etc/kosmozoo/operator.env','/etc/systemd/system/kosmozoo.service','/etc/systemd/system/kosmozoo.service.d/operator.conf','/data/state/settings.json','/sources/images/pixel.png')]
def hashes():return {str(p):dict(sha256=sha(p.read_bytes()),mode=p.stat().st_mode&0o777,uid=p.stat().st_uid,gid=p.stat().st_gid) for p in protected}
before=hashes()
command('systemctl','restart','kosmozoo')
second=observe('after-restart');assert second['runtime']['instance']!=first['runtime']['instance']
assert hashes()==before
version=pathlib.Path('/root/.kosmozoo').read_text().strip();assert version==second['runtime']['app']['version']
with (w/'update.log').open('x') as log:
 result=subprocess.run(['/usr/local/sbin/update'],env=dict(os.environ,var_appversion=version),stdout=log,stderr=subprocess.STDOUT,timeout=600)
assert result.returncode==0,result.returncode
third=observe('after-same-version-update')
assert third['pid']==second['pid'] and third['runtime']==second['runtime'] and hashes()==before
assert not pathlib.Path('/opt/kosmozoo/activation-attempt.json').exists()
assert not pathlib.Path('/var/lib/scripts-underground/update-pending/kosmozoo').exists()
command('systemctl','stop','kosmozoo')
assert command('systemctl','show','kosmozoo','-p','MainPID','--value')=='0'
assert command('systemctl','show','kosmozoo','-p','ActiveState','--value')=='inactive'
# After graceful writer drain, the exact DB bytes must survive a cold restart.
drained_before=drained_snapshot('db-before-cold');dbhash=drained_before['physical']['metadata.db']['actual_sha256']
command('systemctl','start','kosmozoo');fourth=observe('final-cold-readback')
command('systemctl','stop','kosmozoo')
drained_after=drained_snapshot('db-after-cold');actual_dbhash=drained_after['physical']['metadata.db']['actual_sha256']
save_json(w/'db-exact-comparison.json',dict(expected_sha256=dbhash,actual_sha256=actual_dbhash,before=drained_before,after=drained_after,observer_original_db_handles=original_db_handles()))
assert actual_dbhash==dbhash
assert drained_after['logical']==drained_before['logical']
assert hashes()==before
summary=dict(status='consumer-pass',proof='actual native ELF/service/local-media/API/SQLite/settings/restart/same-version-no-op',version=version,protected=before,state_db_sha256=dbhash,image_sha256=digest,outcomes=[first,second,third,fourth])
summary.update(runtime_uid=uid,runtime_gid=gid,bind_capability_only=True,matching_origin_saved=True,foreign_origin_refused=403,originless_api_saved=True,sqlite_disk_executable_mapping=True)
(w/'accepted.json').write_text(json.dumps(summary,sort_keys=True,indent=2))
print('KOSMOZOO_NATIVE_PASS '+json.dumps(summary,sort_keys=True),flush=True)
CONSUMER
# EXIT includes native logs/records in the existing runtime owner's sealed stdout
# evidence on failure too, before that owner stops at its preservation barrier.
