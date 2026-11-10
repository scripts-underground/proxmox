#!/usr/bin/env bash
# Exact documented procedure, real private files/FDs/ACLs; service controls modeled.
set -euo pipefail
ROOT=$(realpath "$(dirname "${BASH_SOURCE[0]}")/../..")
: "${TMPDIR:?disk-backed fixture TMPDIR required}"
if [[ "${1:-}" != --child ]]; then
  systemd-detect-virt --vm --quiet || exit 1
  case "$(findmnt -rn -T "$TMPDIR" -o FSTYPE)" in '' | tmpfs | ramfs) exit 1 ;; esac
  work=$(mktemp -d "$TMPDIR/ll-privacy-focused.XXXXXXXX")
  cleanup_privacy_fixture() {
    local status=$?
    if [[ "$status" == 0 ]]; then
      rm -rf -- "$work"
    else
      printf "LL_PRIVACY_FAILED_FIXTURE %s\n" "$work"
    fi
    exit "$status"
  }
  trap cleanup_privacy_fixture EXIT
  mkdir -p "$work/opt" "$work/units" "$work/bin"
  chmod 0755 "$work/opt" "$work/units"
  export LL_PRIVACY_CASE="$work" ROOT
  timeout 180s unshare --mount --pid --fork --mount-proc --propagation private \
    bash -c 'umask 077; exec bash "$1" --child' -- "$0"
  exit
fi
mount --bind "$LL_PRIVACY_CASE/opt" /opt
mount --bind "$LL_PRIVACY_CASE/units" /etc/systemd/system
export PATH="$LL_PRIVACY_CASE/bin:$PATH"
/usr/bin/python3 -B - "$ROOT" << 'PY'
import errno,json,os,pathlib,shutil,stat,struct,subprocess,sys
root=pathlib.Path(sys.argv[1]);c=pathlib.Path(os.environ['LL_PRIVACY_CASE'])
sys.path.insert(0,str(root/'tests/lib'))
from lazylibrarian_privacy_doc import procedure
body=procedure(root);runner=c/'procedure.sh';runner.write_text(body)
assertions=failures=0
def check(ok,label):
 global assertions,failures
 assertions+=1
 print(('PASS ' if ok else 'FAIL ')+label,flush=True)
 if not ok:failures+=1
def write(p,data,mode=0o664):
 p.parent.mkdir(parents=True,exist_ok=True);p.write_bytes(data);p.chmod(mode)
model='''#!/usr/bin/python3
import json,os,pathlib,sys
c=pathlib.Path(os.environ['LL_PRIVACY_CASE']);state=json.loads((c/'state').read_text());args=sys.argv[1:]
with (c/'calls').open('a') as f:f.write(' '.join(args)+'\\n')
action=args[0];fault=os.environ.get('LL_PRIVACY_FAULT','')
if action in ('stop','start','daemon-reload') and fault==action:sys.exit(41)
if action=='stop':state['active']=False
elif action in ('start','enable'):state['active']=True
elif action=='show':
 name=next(x.split('=',1)[1] for x in args if x.startswith('--property='))
 props=dict(LoadState='loaded',NeedDaemonReload='no',User='',DynamicUser='no',RootDirectory='',RootImage='',FragmentPath='/etc/systemd/system/lazylibrarian.service',ActiveState='active' if state['active'] else 'inactive',MainPID='1' if state['active'] else '0')
 mask='0002'
 for p in [pathlib.Path('/etc/systemd/system/lazylibrarian.service'),*sorted(pathlib.Path('/etc/systemd/system/lazylibrarian.service.d').glob('*.conf'))]:
  for line in p.read_text().splitlines():
   if line.startswith('UMask='):mask=line.split('=',1)[1]
 props['UMask']=mask;props.update(state.get('props',{}));print(props[name])
(c/'state').write_text(json.dumps(state))
'''
write(c/'bin/systemctl',model.encode(),0o755)
wrapper='''#!/bin/sh
exec /usr/bin/python3 -c '
import errno,os,pathlib,sys
code=sys.stdin.read();sys.argv=sys.argv[1:];fault=os.environ.get("LL_PRIVACY_FAULT","");original=os.fchmod;count=0
def chmod(fd,mode):
 global count
 path=os.readlink("/proc/self/fd/"+str(fd))
 if path.startswith("/opt/config/"):
  count+=1
  if fault=="chmod-second" and count==2:raise OSError(errno.EIO,"fixture failure")
  if fault=="race" and count==1:
   p=pathlib.Path(path);p.rename(str(p)+".held");p.symlink_to("/opt/outside")
 return original(fd,mode)
os.fchmod=chmod
oldwrite=os.write
def write(fd,data):
 if fault=="write" and ".private-config-" in os.readlink("/proc/self/fd/"+str(fd)):raise OSError(errno.EIO,"fixture write failure")
 return oldwrite(fd,data)
os.write=write
oldlink=os.link
def link(*a,**kw):
 if fault=="publish":raise OSError(errno.EIO,"fixture publish failure")
 return oldlink(*a,**kw)
os.link=link
oldread=os.read
def read(fd,n):
 if os.readlink("/proc/self/fd/"+str(fd)).startswith("/opt/config/"):raise AssertionError("procedure read config bytes")
 return oldread(fd,n)
os.read=read
exec(compile(code,"canonical-operator-guide","exec"),{"__name__":"__main__"})
' "$@"
'''
write(c/'bin/python3',wrapper.encode(),0o755)
base=b'[Unit]\nDescription=operator literal\n[Service]\nUMask=0002\nEnvironment=OPERATOR_LITERAL=preserve\nExecStart=/opt/LazyLibrarian/venv/bin/python3 /opt/LazyLibrarian/LazyLibrarian.py --config=/opt/config/selected.ini\nRestartSec=13\n'
unit=pathlib.Path('/etc/systemd/system/lazylibrarian.service');drop=unit.with_name(unit.name+'.d')
config=pathlib.Path('/opt/config/selected.ini');names=[pathlib.Path(str(config)+s) for s in ('','.new','.bak','.bak2')]
def reset():
 if pathlib.Path('/opt/config').exists():shutil.rmtree('/opt/config')
 if drop.exists():shutil.rmtree(drop)
 pathlib.Path('/opt/config').mkdir(mode=0o755)
 for i,p in enumerate(names):write(p,('owned fixture generation '+str(i)+'\n').encode())
 write(unit,base,0o644);write(pathlib.Path('/opt/outside'),b'unrelated operator data',0o640)
 (c/'state').write_text(json.dumps(dict(active=True)));(c/'calls').write_text('')
def facts():
 return {str(p):(p.read_bytes(),p.stat().st_ino,p.stat().st_uid,p.stat().st_gid,p.stat().st_mode&0o777) for p in names if p.exists() and p.is_file()}
def run(label,fault='',filename=None):
 env=dict(os.environ,CONFIG_FILE=str(filename or config),LL_PRIVACY_FAULT=fault)
 result=subprocess.run(['/bin/bash',str(runner)],env=env,capture_output=True,timeout=20)
 (c/(label+'.stdout')).write_bytes(result.stdout);(c/(label+'.stderr')).write_bytes(result.stderr)
 if result.returncode:print('PROCEDURE_RESULT '+label+' '+result.stderr.decode().strip(),flush=True)
 return result.returncode
def active():return json.loads((c/'state').read_text())['active']
# Genuine old template control, independent of the procedure implementation.
source=(root/'scripts/lxc/lazylibrarian.sh').read_text()
fresh=source.split('cat << EOF > /etc/systemd/system/lazylibrarian.service\n',1)[1].split('\nEOF',1)[0]
check('\nUMask=0077\n' in '\n'+fresh+'\n','fresh canonical service creates files privately')
mask=next(line.split('=',1)[1] for line in fresh.splitlines() if line.startswith('UMask='))
created=c/'template-config.new'
subprocess.run(['/usr/bin/python3','-B','-c','import os,pathlib,sys;os.umask(int(sys.argv[1],8));pathlib.Path(sys.argv[2]).write_text("owned template fixture")',mask,str(created)],check=True,timeout=10)
check(stat.S_IMODE(created.stat().st_mode)==0o600,'actual template-selected creation mode is600 (old0002 creates664)')
for label,mutate in [('missing marker',lambda s:s.replace('<!-- lazylibrarian-private-config:begin -->','')),
                     ('duplicate marker',lambda s:s+'\n<!-- lazylibrarian-private-config:begin -->'),
                     ('wrong fence',lambda s:s.replace('```bash\npython3','```python\npython3'))]:
 fake=c/('doc-'+label.replace(' ','-'));(fake/'docs').mkdir(parents=True)
 (fake/'docs/lazylibrarian-private-config.md').write_text(mutate((root/'docs/lazylibrarian-private-config.md').read_text()))
 try:procedure(fake);refused=False
 except ValueError:refused=True
 check(refused,'extractor refuses '+label)
reset();before=facts();unit_before=unit.read_bytes();outside=pathlib.Path('/opt/outside').stat()
check(run('legacy')==0,'exact guide repairs legacy service family')
after=facts();check(all(after[k][:-1]==v[:-1] and after[k][-1]==0o600 for k,v in before.items()),'all config bytes/inodes/owners retained, modes600')
check(unit.read_bytes()==unit_before and pathlib.Path('/opt/outside').stat()==outside,'base and unrelated data metadata preserved')
policy=drop/'10-scripts-underground-private-config.conf';old=policy.stat().st_ino
check(run('repeat')==0 and policy.stat().st_ino==old,'normal repeat reuses exact policy inode')
reset();custom=pathlib.Path('/opt/config/chosen name.ini')
for p in names:p.rename(pathlib.Path(str(custom)+str(p)[len(str(config)):]))
check(run('spaces',filename=custom)==0,'explicit custom filename with spaces')
reset()
for p in names[1:]:p.unlink()
check(run('absent')==0 and all(not p.exists() for p in names[1:]),'absent siblings remain absent')
for kind in ('symlink','fifo','device','directory','hardlink','owner'):
 reset();target=names[-1];target.unlink()
 if kind=='symlink':target.symlink_to('/opt/outside')
 elif kind=='fifo':os.mkfifo(target,0o600)
 elif kind=='device':os.mknod(target,stat.S_IFCHR|0o600,os.makedev(1,3))
 elif kind=='directory':target.mkdir()
 elif kind=='hardlink':os.link(names[0],target)
 else:write(target,b'foreign owner');os.chown(target,1234,1234)
 original=names[0].stat();check(run(kind)!=0 and active(),'unsafe last member '+kind+' refuses before stop')
 check(names[0].stat()==original,'unsafe '+kind+' cannot partially chmod preceding members')
for kind in ('symlink-ancestor','writable-ancestor','acl','collision','nonroot','dynamic','root-remap'):
 reset()
 if kind=='symlink-ancestor':pathlib.Path('/opt/config').rename('/opt/other-config');pathlib.Path('/opt/config').symlink_to('/opt/other-config')
 elif kind=='writable-ancestor':pathlib.Path('/opt/config').chmod(0o777)
 elif kind=='acl':os.setxattr('/opt/config','system.posix_acl_default',struct.pack('<I',2)+b''.join(struct.pack('<HHI',tag,perm,0xffffffff) for tag,perm in [(1,7),(4,5),(32,0)]))
 elif kind=='collision':write(policy,b'[Service]\nUMask=0027\n',0o644)
 else:
  props={'nonroot':{'User':'nobody'},'dynamic':{'DynamicUser':'yes'},'root-remap':{'RootDirectory':'/elsewhere'}}[kind]
  (c/'state').write_text(json.dumps(dict(active=True,props=props)))
 check(run(kind)!=0 and active(),kind+' refuses before service effects')
 if kind=='symlink-ancestor':pathlib.Path('/opt/config').unlink();pathlib.Path('/opt/other-config').rename('/opt/config')
reset();write(drop/'99-operator.conf',b'[Service]\nUMask=0002\n',0o644)
operator=(drop/'99-operator.conf').read_bytes()
check(run('conflict')!=0 and not active(),'later incompatible override prevents start')
check((drop/'99-operator.conf').read_bytes()==operator,'operator override bytes are not changed')
for fault in ('chmod-second','write','publish','daemon-reload','start'):
 reset();before=facts()
 check(run('fault-'+fault,fault)!=0 and not active(),fault+' leaves service stopped')
 check(all(facts()[k][:-1]==v[:-1] for k,v in before.items()),fault+' retains config bytes/inodes/owners')
 check(run('retry-'+fault)==0 and all(p.stat().st_mode&0o777==0o600 for p in names),fault+' normal retry succeeds')
reset();outside=pathlib.Path('/opt/outside').stat()
check(run('race','race')!=0 and not active(),'path substitution is detected through pinned identity')
check(pathlib.Path('/opt/outside').stat()==outside,'pinned fchmod never reaches substituted target')
print(f'LL_PRIVACY_FOCUSED assertions={assertions} failures={failures}; real extracted guide/files/FDs/ACLs, modeled systemctl',flush=True)
raise SystemExit(bool(failures))
PY
