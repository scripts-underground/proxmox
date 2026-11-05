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
  shopt -s nullglob
  local -a files=("$work/"*.log "$work/"*.json)
  if ((${#files[@]})); then
    tar -czf "$work/evidence.tar.gz" -- "${files[@]}" || capture=$?
    if [[ "$capture" == 0 ]]; then
      printf 'KOSMOZOO_NATIVE_EVIDENCE_TGZ_SHA256 '
      sha256sum "$work/evidence.tar.gz" || capture=$?
      printf 'KOSMOZOO_NATIVE_EVIDENCE_TGZ_BASE64 '
      base64 -w0 "$work/evidence.tar.gz" || capture=$?
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
import base64,hashlib,json,os,pathlib,pwd,sqlite3,subprocess,sys,time,urllib.request,urllib.error
w=pathlib.Path(sys.argv[1]); origin='http://127.0.0.1'
account=pwd.getpwnam('kosmozoo');uid=account.pw_uid;gid=account.pw_gid
assert uid!=0 and gid!=0
assert hashlib.sha256(pathlib.Path('/opt/kosmozoo/kosmozoo').read_bytes()).hexdigest()=='ff2486bfd42f0c50c0e48eb08a52ac9ec8eee826f873629e6e4cad90d0179d34'
def sha(raw):return hashlib.sha256(raw).hexdigest()
def command(*args):return subprocess.run(args,check=True,capture_output=True,text=True,timeout=90).stdout.strip()
def api(path,method='GET',body=None,raw=False,request_origin=None):
 data=None if body is None else json.dumps(body).encode()
 headers={'Content-Type':'application/json'}
 if request_origin is not None:headers['Origin']=request_origin
 req=urllib.request.Request(origin+path,data=data,method=method,headers=headers)
 with urllib.request.urlopen(req,timeout=15) as response:
  content=response.read()
 return content if raw else json.loads(content)
def ready():
 end=time.monotonic()+90
 while True:
  try:
   r=api('/api/runtime')
   assert r['protocol']=='kosmozoo-runtime' and r['version']==1 and r['status']=='ready' and r['mode']=='serve'
   assert r['binding']=={'hostname':'0.0.0.0','port':80} and r['configuredBind']=='0.0.0.0'
   pid=int(command('systemctl','show','kosmozoo','-p','MainPID','--value'))
   assert pathlib.Path('/proc/'+str(pid)+'/exe').resolve()==pathlib.Path('/opt/kosmozoo/kosmozoo')
   private=pathlib.Path('/data/state/engine-instance.json');s=private.stat();p=json.loads(private.read_bytes())
   assert s.st_uid==uid and s.st_mode&0o777==0o600 and not private.is_symlink()
   status=dict(line.split(':',1) for line in pathlib.Path('/proc/'+str(pid)+'/status').read_text().splitlines() if ':' in line)
   assert list(map(int,status['Uid'].split()))==[uid]*4 and list(map(int,status['Gid'].split()))==[gid]*4
   assert set(map(int,status['Groups'].split()))==set(os.getgrouplist('kosmozoo',gid))
   assert all(int(status[k].strip(),16)==1<<10 for k in ('CapEff','CapPrm','CapBnd','CapAmb'))
   assert r['app']['version']=='0.3.0'
   assert p['ownerPid']==pid and all(p[k]==r[k] for k in ('instance','sourceVersion','binding'))
   env=dict(v.split(b'=',1) for v in pathlib.Path('/proc/'+str(pid)+'/environ').read_bytes().split(b'\0') if v)
   assert env[b'PATH']==b'/nonexistent' and env[b'TMPDIR']==b'/data/operator-tmp' and env[b'KOZMOZOO_PORT']==b'080'
   assert env[b'KZ_ACCEPTANCE_LITERAL']==b'operator $ ` % " \\ roundtrip'
   assert 'pid='+str(pid)+',' in command('ss','-H','-lntp','sport = :80')
   mappings=pathlib.Path('/proc/'+str(pid)+'/maps').read_text()
   assert any('/data/operator-tmp/' in line and 'sqlite' in line.lower() and 'x' in line.split()[1] for line in mappings.splitlines())
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
 with sqlite3.connect('file:/data/state/metadata.db?mode=ro',uri=True) as db:
  stored=db.execute('select hash,vote,bookmark,notes from entry where collection=? and name=?',('local','pixel.png')).fetchone()
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
dbhash=sha(pathlib.Path('/data/state/metadata.db').read_bytes())
command('systemctl','start','kosmozoo');fourth=observe('final-cold-readback')
command('systemctl','stop','kosmozoo')
assert sha(pathlib.Path('/data/state/metadata.db').read_bytes())==dbhash
assert hashes()==before
summary=dict(status='consumer-pass',proof='actual native ELF/service/local-media/API/SQLite/settings/restart/same-version-no-op',version=version,protected=before,state_db_sha256=dbhash,image_sha256=digest,outcomes=[first,second,third,fourth])
summary.update(runtime_uid=uid,runtime_gid=gid,bind_capability_only=True,matching_origin_saved=True,foreign_origin_refused=403,originless_api_saved=True,sqlite_disk_executable_mapping=True)
(w/'accepted.json').write_text(json.dumps(summary,sort_keys=True,indent=2))
print('KOSMOZOO_NATIVE_PASS '+json.dumps(summary,sort_keys=True),flush=True)
CONSUMER
# EXIT includes native logs/records in the existing runtime owner's sealed stdout
# evidence on failure too, before that owner stops at its preservation barrier.
