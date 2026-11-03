"""Test-owned offline system-manager policy on an exact owned mounted CT root."""
from contextlib import contextmanager
from dataclasses import asdict
import json
import os
from pathlib import Path
import stat
import subprocess

from test_context import exclusive_json,read_custody,require,sha
from mounted_root import identity,same_node

POLICY='etc/systemd/system.conf.d/90-su-test-tmpdir.conf'
TMPDIR='/var/lib/scripts-underground-test/tmp'
CONTENT=('[Manager]\nDefaultEnvironment=TMPDIR='+TMPDIR+'\n').encode()


def node(s):
    return dict(device=s.st_dev,inode=s.st_ino,uid=s.st_uid,gid=s.st_gid,mode=stat.S_IMODE(s.st_mode),links=s.st_nlink)


@contextmanager
def directory(root,parts,uid,gid,create=False,record=None):
    """Walk only checked nonsymlink directory FDs; never chown an existing path."""
    fd=os.dup(root)
    try:
        for i,name in enumerate(parts):
            require(name not in ('','.','..') and '/' not in name,'receiver directory component')
            try:child=os.open(name,os.O_RDONLY|os.O_DIRECTORY|os.O_NOFOLLOW,dir_fd=fd)
            except FileNotFoundError:
                require(create,'receiver directory missing')
                mode=0o1777 if '/'.join(parts[:i+1])==TMPDIR.lstrip('/') else 0o755
                record('receiver-object-intent',dict(kind='directory',path='/'.join(parts[:i+1]),uid=uid,gid=gid,mode=mode))
                os.mkdir(name,mode,dir_fd=fd)
                child=os.open(name,os.O_RDONLY|os.O_DIRECTORY|os.O_NOFOLLOW,dir_fd=fd)
                os.fchown(child,uid,gid);os.fchmod(child,mode);os.fsync(child)
                record('receiver-object-created',dict(path='/'.join(parts[:i+1]),identity=node(os.fstat(child))))
            s=os.fstat(child);leaf='/'.join(parts[:i+1])==TMPDIR.lstrip('/')
            require(s.st_uid==uid and s.st_gid==gid and (stat.S_IMODE(s.st_mode)==0o1777 if leaf else not s.st_mode&0o022),'unsafe receiver directory metadata')
            os.close(fd);fd=child
        yield fd
    finally:os.close(fd)


def file_fact(parent,name):
    fd=os.open(name,os.O_RDONLY|os.O_NOFOLLOW,dir_fd=parent)
    try:
        s=os.fstat(fd);require(stat.S_ISREG(s.st_mode) and s.st_nlink==1,'receiver policy kind/links')
        with os.fdopen(os.dup(fd),'rb') as stream:raw=stream.read(65537)
        require(len(raw)<=65536,'receiver policy too large')
        return dict(identity=node(s),bytes=len(raw),sha256=sha(raw))
    finally:os.close(fd)


def write_file(parent,name,raw,uid,gid,record,label):
    record('receiver-object-intent',dict(kind='file',path=label,uid=uid,gid=gid,mode=0o644,bytes=len(raw),sha256=sha(raw)))
    fd=os.open(name,os.O_WRONLY|os.O_CREAT|os.O_EXCL|os.O_NOFOLLOW,0o600,dir_fd=parent)
    try:
        with os.fdopen(os.dup(fd),'wb') as stream:stream.write(raw);stream.flush();os.fsync(stream.fileno())
        os.fchown(fd,uid,gid);os.fchmod(fd,0o644);os.fsync(fd)
    finally:os.close(fd)
    os.fsync(parent)
    return file_fact(parent,name)


def mapped_root(native):
    program='my $c=PVE::LXC::Config->load_config($ARGV[0]); my ($m,$u,$g)=PVE::LXC::parse_id_maps($c); print JSON::PP->new->encode({maps=>$m,uid=>$u,gid=>$g});'
    result=subprocess.run(['/usr/bin/perl','-MPVE::LXC','-MPVE::LXC::Config','-MJSON::PP','-e',program,str(native.owner.spec.ctid)],capture_output=True,text=True,timeout=20)
    require(result.returncode==0,'canonical PVE mapping query failed')
    value=json.loads(result.stdout)
    require(type(value['uid']) is int and type(value['gid']) is int and value['uid']>0 and value['gid']>0,'unprivileged mapped root required')
    for kind,key in [('u','uid'),('g','gid')]:
        require(len([r for r in value['maps'] if r[0]==kind and int(r[1])==0 and int(r[2])==value[key] and int(r[3])>0])==1,'canonical root map ambiguous')
    native.run.record('receiver-root-map',dict(**value,module_sha256=sha(Path('/usr/share/perl5/PVE/LXC.pm').read_bytes()),broker_uid_map=Path('/proc/self/uid_map').read_text(),broker_gid_map=Path('/proc/self/gid_map').read_text()))
    return value['uid'],value['gid']


def prepare(native):
    """Called by every typed start BEFORE PID1 and static services exist."""
    require(native.n['receiver_tmpdir']==TMPDIR,'receiver fixed policy scope')
    native.owner.checked();native.mount.stopped()
    receipt=Path(native.run.context.operation['runs'])/('receiver-policy-'+str(native.owner.spec.ctid)+'-'+native.owner.spec.tag+'.json')
    prior=read_custody(receipt) if receipt.exists() else None
    uid,gid=mapped_root(native)
    native.mount.open_owned()
    try:
        a=native.mount.active;root=os.open(a['path'],os.O_RDONLY|os.O_DIRECTORY|os.O_NOFOLLOW)
        try:
            require(same_node(identity(a['path']),a['identity']) and node(os.fstat(root))['uid']==uid and node(os.fstat(root))['gid']==gid,'mapped mounted root identity mismatch')
            with directory(root,TMPDIR.strip('/').split('/'),uid,gid,True,native.run.record):pass
            with directory(root,POLICY.split('/')[:-1],uid,gid,True,native.run.record) as parent:
                name=POLICY.rsplit('/',1)[1]
                if prior is not None:
                    require(prior['schema']==1 and prior['resource']==asdict(native.owner.current) and prior['root']==a['identity'] and prior['uid']==uid and prior['gid']==gid,'receiver policy ownership provenance changed')
                    require(file_fact(parent,name)==prior['file'],'recorded receiver policy bytes/metadata changed')
                else:
                    require(not os.path.lexists('/proc/self/fd/'+str(parent)+'/'+name),'unknown existing receiver policy')
                    fact=write_file(parent,name,CONTENT,uid,gid,native.run.record,POLICY)
                    exclusive_json(receipt,dict(schema=1,source=native.run.context.document['source']['tree_sha256'],run=str(native.run.directory),creation=native.owner.creation,resource=asdict(native.owner.current),root=a['identity'],uid=uid,gid=gid,file=fact))
                fact=file_fact(parent,name)
                require(fact['sha256']==sha(CONTENT) and fact['identity']['uid']==uid and fact['identity']['gid']==gid and fact['identity']['mode']==0o644,'receiver policy content/owner mismatch')
            native.mount.check_active()
            native.run.record('receiver-policy-ready',dict(receipt=str(receipt),sha256=sha(receipt.read_bytes()),policy=POLICY,file=fact,resource=asdict(native.owner.current)))
        finally:os.close(root)
    finally:
        if native.mount.active is not None:native.mount.close()


def verify_live(native):
    """Live PID1 policy, root maps, plus a genuine static unit end consumer."""
    from app_driver import checked
    receipt=Path(native.run.context.operation['runs'])/('receiver-policy-'+str(native.owner.spec.ctid)+'-'+native.owner.spec.tag+'.json')
    prior=read_custody(receipt);require(prior['resource']==asdict(native.owner.current),'live policy resource changed')
    kernel=json.loads(checked(native,['python3','-B','-c','import json,pathlib; p=pathlib.Path("/");s=p.stat();print(json.dumps(dict(uid=s.st_uid,gid=s.st_gid,mode=s.st_mode&4095,uid_map=pathlib.Path("/proc/1/uid_map").read_text(),gid_map=pathlib.Path("/proc/1/gid_map").read_text())))']))
    require(kernel['uid']==kernel['gid']==0 and kernel['mode']==0o755,'receiving root permissions changed')
    for key,expected in [('uid_map',prior['uid']),('gid_map',prior['gid'])]:
        rows=[list(map(int,line.split())) for line in kernel[key].splitlines()]
        require(len([r for r in rows if r[0]==0 and r[1]==expected and r[2]>0])==1,'PID1 root map differs from canonical PVE mapping')
    native.run.record('receiving-kernel-root',kernel)
    # No per-unit environment/PassEnvironment/inline env. The shell records the
    # actual process environment AND creates a tempfile via inherited TMPDIR.
    token=native.run.directory.name
    unit='su-receiver-'+token+'.service';output=TMPDIR+'/static-'+token+'/result'
    raw=('[Unit]\nDescription=Owned receiver static environment proof\n[Service]\nType=oneshot\nRemainAfterExit=yes\nExecStart=:/bin/sh -ec \'test "$TMPDIR" = '+TMPDIR+'; f=$(mktemp); test -f "$f"; case "$f" in '+TMPDIR+'/*) ;; *) exit 71;; esac; printf "TMPDIR=%%s\\nFILE=%%s\\n" "$TMPDIR" "$f" > '+output+'; rm -- "$f"\'\n').encode()
    script='''import hashlib,json,os,pathlib,sys
p=pathlib.Path('/etc/systemd/system')/sys.argv[1];raw=bytes.fromhex(sys.argv[2]);out=pathlib.Path(sys.argv[3])
assert not p.exists() and not p.is_symlink() and not out.exists() and not out.is_symlink()
assert not out.parent.exists() and not out.parent.is_symlink();out.parent.mkdir(mode=0o700)
fd=os.open(p,os.O_WRONLY|os.O_CREAT|os.O_EXCL|os.O_NOFOLLOW,0o644)
with os.fdopen(fd,'wb') as f:f.write(raw);f.flush();os.fsync(f.fileno())
os.chmod(p,0o644);print(hashlib.sha256(p.read_bytes()).hexdigest())'''
    native.run.record('static-unit-intent',dict(unit=unit,path='/etc/systemd/system/'+unit,bytes=len(raw),sha256=sha(raw),output=output,environment_workarounds=False))
    require(checked(native,['python3','-B','-c',script,unit,raw.hex(),output])==sha(raw),'static fixture creation bytes mismatch')
    checked(native,['systemctl','daemon-reload']);checked(native,['systemctl','start',unit])
    state=checked(native,['systemctl','show',unit,'-p','Type','-p','MainPID','-p','ExecMainCode','-p','ExecMainStatus','-p','ExecMainStartTimestampMonotonic','-p','ExecMainExitTimestampMonotonic'])
    require('ExecMainStatus=0' in state and 'ExecMainCode=1' in state,'static service did not execute successfully')
    value=checked(native,['cat',output]);require(value.startswith('TMPDIR='+TMPDIR+'\nFILE='+TMPDIR+'/'),'static service disk tempfile consumer failed')
    maps=checked(native,['/bin/sh','-ec','cat /proc/1/uid_map /proc/1/gid_map; stat -c "%u:%g:%a" /'])
    native.run.record('static-service-consumer',dict(unit=unit,unit_sha256=sha(raw),state=state,output=value,maps=maps,policy_sha256=prior['file']['sha256'],cold_start_policy=True,mainpid_environment_claim=False))
    checked(native,['systemctl','stop',unit])
    remove='''import hashlib,pathlib,sys
p=pathlib.Path('/etc/systemd/system')/sys.argv[1];o=pathlib.Path(sys.argv[3]);assert not p.is_symlink() and p.stat().st_uid==0 and hashlib.sha256(p.read_bytes()).hexdigest()==sys.argv[2];assert o.is_file() and not o.is_symlink() and o.stat().st_uid==0;p.unlink();o.unlink();o.parent.rmdir();assert not p.exists() and not o.exists() and not o.parent.exists()'''
    checked(native,['python3','-B','-c',remove,unit,sha(raw),output]);checked(native,['systemctl','daemon-reload'])
    native.run.record('static-unit-removed',dict(unit=unit,file_absent=True,output_absent=True,status=0))
    return prior
