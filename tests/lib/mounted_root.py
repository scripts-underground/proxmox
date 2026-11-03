"""Typed owned PVE root mount and explicit cross-namespace address projection.

Native pct executes in the broker namespace. Its raw output is retained. A
verified /proc/<broker>/root address lets the private framework consumer reach
that SAME mount; an underlying empty consumer directory is never substituted.
"""
import os
from pathlib import Path
import re
import stat
import subprocess

from test_context import AdmissionError, require, sha


def birth(pid):
    return Path('/proc',str(pid),'stat').read_text().split(') ',1)[1].split()[19]


def identity(path):
    s=Path(path).stat()
    return dict(device=s.st_dev,inode=s.st_ino,uid=s.st_uid,gid=s.st_gid,mode=stat.S_IMODE(s.st_mode))


def same_node(a,b):
    return (a['device'],a['inode'])==(b['device'],b['inode'])


def project_output(raw,ctid,projection):
    """Only a verified address substitution; never add a consumer grammar."""
    canonical='/var/lib/lxc/'+str(ctid)+'/rootfs'
    formats={'current-quoted':"mounted CT "+str(ctid)+" in '"+canonical+"'",'legacy':'mounted at '+canonical}
    matches=[name for name,line in formats.items() if raw in (line,line+'\n')]
    require(len(matches)==1 and raw.count(canonical)==1,'unexpected/ambiguous native mount output')
    require(type(projection) is str and re.fullmatch(r'/proc/[1-9][0-9]*/root/[^\s\x00\'\"]+',projection),'native projection address syntax')
    return raw.replace(canonical,projection,1),matches[0]


class MountedRoot:
    def __init__(self,native):
        self.native=native;self.active=None;self.consumer=None;self.unverified=False
        self.pid=os.getpid();self.birth=birth(self.pid);self.namespace=os.readlink('/proc/self/ns/mnt')
        self.path='/var/lib/lxc/'+str(native.owner.spec.ctid)+'/rootfs'
        self.close_attempted=False

    def backing(self):
        return (Path('/dev')/self.native.n['vg']/self.native.owner.spec.volume).stat()

    def bind_consumer(self,pid):
        require(self.consumer is None,'consumer already bound')
        self.consumer=dict(pid=pid,birth=birth(pid))
        self.native.run.record('native-consumer-bound',self.consumer)

    def peer(self,pid):
        require(self.consumer is not None and type(pid) is int,'verified mount consumer required')
        c=self.consumer
        require(birth(c['pid'])==c['birth'] and birth(self.pid)==self.birth,'mount consumer/broker process birth changed')
        namespace=os.readlink('/proc/'+str(c['pid'])+'/ns/mnt')
        require(namespace!=self.namespace and os.readlink('/proc/'+str(pid)+'/ns/mnt')==namespace,'mount consumer namespace mismatch')
        current=pid
        for _ in range(128):
            if current==c['pid']:break
            require(current>1,'mount caller outside bound consumer lineage')
            current=int(Path('/proc',str(current),'stat').read_text().split(') ',1)[1].split()[1])
        else:raise AdmissionError('mount consumer ancestry bound exceeded')
        return dict(**c,namespace=namespace,peer=pid,peer_birth=birth(pid))

    def mounted(self):
        path=self.path
        rows=[]
        for line in Path('/proc/self/mountinfo').read_text().splitlines():
            parts=line.split();separator=parts.index('-')
            if parts[4]==path:
                rows.append(dict(id=parts[0],device=parts[2],root=parts[3],path=parts[4],fstype=parts[separator+1],source=parts[separator+2]))
        require(len(rows)<=1,'ambiguous owned mount')
        return rows[0] if rows else None

    def stopped(self):
        n=self.native;n.owner.checked()
        result=n.call('pct',['status',str(n.owner.spec.ctid)])
        require(result.returncode==0 and result.stdout.strip()=='status: stopped','mount requires proven stopped CT')

    def config(self):
        return Path('/etc/pve/lxc/'+str(self.native.owner.spec.ctid)+'.conf').read_text()

    def check_active(self):
        require(self.active is not None,'unowned mount cannot be unmounted')
        self.stopped();a=self.active;m=self.mounted()
        require(m==a['mount'] and same_node(identity(a['path']),a['identity']),'owned root mount identity changed')
        config=self.config()
        require(config.replace('lock: mounted\n','')==a['config'] and config.count('lock: mounted\n')==1,'mounted config changed')

    def open(self,peer):
        return self._open(self.peer(peer))

    def open_owned(self):
        """Offline preparation by the same checked native owner, no RPC caller."""
        return self._open(None)

    def _open(self,consumer):
        n=self.native;self.stopped()
        require(self.active is None and self.mounted() is None,'pre-existing/foreign mount cannot be adopted')
        config=self.config()
        require(not re.search(r'^(lock:|mp[0-9]+:|lxc\.mount\.)',config,re.M),'root-only unlocked mount scope required')
        ct=str(n.owner.spec.ctid);path=self.path;self.close_attempted=False
        n.run.record('root-mount-intent',dict(resource=n.owner.current.__dict__,config_sha256=sha(config.encode()),consumer=consumer))
        result=n.call('pct',['mount',ct])
        require(result.returncode==0,'native root mount failed')
        self.unverified=True
        # Keep provisional ownership if any postcondition refuses; it is NOT
        # permission to unmount an unknown backing or proceed to start/destroy.
        mount=self.mounted();require(mount is not None,'native mount not visible in broker namespace')
        s=self.backing();require(stat.S_ISBLK(s.st_mode),'owned root device not a block device')
        require(mount['device']==str(os.major(s.st_rdev))+':'+str(os.minor(s.st_rdev)) and mount['root']=='/' and mount['fstype'] in ('ext4','ext3','ext2'),'native mounted foreign backing/filesystem')
        node=identity(path)
        require(node['device']==s.st_rdev,'native mount stat/device mismatch')
        self.active=dict(path=path,mount=mount,identity=node,config=config,consumer=consumer)
        self.check_active()
        if consumer is None:
            n.run.record('root-owner-visible',dict(mount=mount,identity=node,broker=dict(pid=self.pid,birth=self.birth,namespace=self.namespace)))
            return result
        projection='/proc/'+str(self.pid)+'/root'+path
        projected,grammar=project_output(result.stdout,ct,projection)
        visible=identity('/proc/'+str(consumer['pid'])+'/root'+projection)
        require(same_node(node,visible),'consumer sees a different projected root')
        underlying=identity('/proc/'+str(consumer['pid'])+'/root'+path)
        n.run.record('root-mount-visible',dict(native_stdout=result.stdout,projected_stdout=projected,native_stderr=result.stderr,projection=projection,
                     transformation=dict(kind='exact-native-path-substitution',grammar=grammar,native_path='/var/lib/lxc/'+ct+'/rootfs',projected_path=projection),
                     broker=dict(pid=self.pid,birth=self.birth,namespace=self.namespace),consumer=consumer,mount=mount,
                     broker_root=node,projected_consumer_root=visible,unprojected_consumer_root=underlying))
        # A real legacy message would make this product stage reach a mapped-
        # root chown. Pure grammar controls cover that format without authorizing
        # such a mutation on the retained unprivileged fixture.
        require(grammar=='current-quoted','native format reaches unresolved product ownership branch')
        return subprocess.CompletedProcess(result.args,0,projected,result.stderr)

    def close(self,peer=None):
        require(self.active is not None,'unowned mount cannot be unmounted')
        if peer is not None:
            c=self.peer(peer)
            require(c['pid']==self.active['consumer']['pid'] and c['namespace']==self.active['consumer']['namespace'],'unmount consumer changed')
        self.check_active();n=self.native;a=self.active
        before=identity(a['path']);self.close_attempted=True;result=n.call('pct',['unmount',str(n.owner.spec.ctid)])
        require(result.returncode==0,'native unmount failed')
        require(self.mounted() is None and self.config()==a['config'],'owned unmount/config restoration not proven')
        n.owner.checked();n.run.record('root-unmount-result',dict(status=0,mount=a['mount'],original_root=a['identity'],before_unmount=before,config_sha256=sha(a['config'].encode())))
        self.active=None
        self.unverified=False
        return result
