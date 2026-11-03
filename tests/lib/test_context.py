"""Guest-only data admission and receipt-bound operations (Python stdlib).

Context is independently supplied root-custody data. It contains no commands.
Native effects are constructor-injected boundaries; JSON cannot select one.
This protects against accidental/mis-scoped effects, not a malicious root.
"""
from dataclasses import dataclass, asdict
import fcntl
import hashlib
import json
import os
from pathlib import Path, PurePosixPath
import re
import signal
import stat
import subprocess
import time
import uuid

from test_registry import policy


class AdmissionError(ValueError):
    pass


class PreservationPending(AdmissionError):
    """Missing external acknowledgement after fresh stopped/current proof."""


def require(ok, why):
    if not ok:
        raise AdmissionError(why)


def sha(data):
    return hashlib.sha256(data).hexdigest()


def load_json(text):
    def pairs(items):
        result = {}
        for key, value in items:
            require(key not in result, 'duplicate JSON key')
            result[key] = value
        return result
    try:
        return json.loads(text, object_pairs_hook=pairs, parse_constant=lambda _: require(False, 'JSON nonfinite value'))
    except (json.JSONDecodeError, UnicodeError) as error:
        raise AdmissionError('malformed JSON') from error


def fields(value, names):
    require(type(value) is dict and set(value) == set(names.split()), 'schema fields')


def text(value):
    require(type(value) is str and value and '\x00' not in value, 'schema text')
    return value


def absolute(value):
    value = text(value)
    p = Path(value)
    require(p.is_absolute() and str(p) == value and '..' not in p.parts, 'unsafe path')
    return p


def safe_parents(path, root=False, file=False):
    p = absolute(str(path))
    for item in [p, *p.parents]:
        s = item.lstat()
        leaf = item == p and file
        require(not stat.S_ISLNK(s.st_mode), 'custody symlink')
        require(stat.S_ISREG(s.st_mode) if leaf else stat.S_ISDIR(s.st_mode), 'custody kind')
        require(not s.st_mode & 0o022, 'custody writable ancestor')
        if root:
            require(s.st_uid == 0, 'custody not root-owned')
        if leaf:
            require(s.st_nlink == 1, 'custody context links')


def read_custody(path):
    try:
        safe_parents(path, root=True, file=True)
        require(path.stat().st_size <= 8 * 1024 * 1024, 'context too large')
        return load_json(path.read_text())
    except OSError as error:
        raise AdmissionError('context custody unavailable') from error


def query(argv):
    try:
        return subprocess.run(argv, capture_output=True, text=True, check=True, timeout=20).stdout.strip()
    except (OSError, subprocess.SubprocessError) as error:
        raise AdmissionError('read-only prerequisite query failed') from error


def filesystem(path):
    rows = load_json(query(['/usr/bin/findmnt', '-J', '-T', str(path), '-o', 'TARGET,SOURCE,FSTYPE,UUID']))['filesystems']
    require(len(rows) == 1, 'filesystem ambiguous')
    return rows[0]


def source_files(root):
    """Exact public projection, including extra files; never follow symlink dirs."""
    rows = []
    for directory, dirs, files in os.walk(root, followlinks=False):
        if Path(directory) == root:
            dirs[:] = [d for d in dirs if d != '.git']
        for name in sorted(dirs + files):
            p = Path(directory) / name
            s = p.lstat()
            if stat.S_ISDIR(s.st_mode):
                continue
            relative = p.relative_to(root).as_posix()
            kind = 'symlink' if p.is_symlink() else 'file'
            require(kind == 'symlink' or stat.S_ISREG(s.st_mode), 'source kind')
            if kind == 'symlink':
                require(p.resolve().is_relative_to(root), 'source symlink path escape')
            data = os.readlink(p).encode() if kind == 'symlink' else p.read_bytes()
            rows.append(dict(path=relative, kind=kind, mode=stat.S_IMODE(s.st_mode), sha256=sha(data)))
    return sorted(rows, key=lambda row: row['path'])


@dataclass(frozen=True)
class Context:
    document: dict
    path: Path
    operation: dict

    @classmethod
    def admit(cls, path, suite, mode):
        return cls.validate(read_custody(Path(path)), Path(path), suite, mode)

    @classmethod
    def validate(cls, d, path, suite, mode):
        try:
            row, role, effects = policy(suite, mode)
        except ValueError as error:
            raise AdmissionError(str(error)) from error
        fields(d, 'schema target source operations protection')
        require(type(d['schema']) is int and d['schema'] == 1, 'schema version')
        t = d['target']
        fields(t, 'name uuid mac receipt receipt_sha256 root_fs workspace_fs workspace disks')
        for key in ('name', 'uuid', 'mac', 'receipt_sha256'):
            text(t[key])
        receipt_path = absolute(t['receipt'])
        receipt = read_custody(receipt_path)
        require(sha(receipt_path.read_bytes()) == t['receipt_sha256'], 'target receipt bytes')
        fields(receipt, 'name uuid mac owner_receipt_sha256 readiness_sha256')
        require(all(t[key] == receipt[key] for key in ('name', 'uuid', 'mac')), 'target expected receipt mismatch')
        actual_uuid = Path('/sys/class/dmi/id/product_uuid').read_text().strip().lower()
        require(actual_uuid == t['uuid'], 'target DMI UUID mismatch')
        macs = {p.read_text().strip() for p in Path('/sys/class/net').glob('*/address')}
        require(t['mac'] in macs, 'target MAC mismatch')
        for key in ('root_fs', 'workspace_fs'):
            fields(t[key], 'target source fstype uuid')
            require(all(type(v) is str and v for v in t[key].values()), 'schema filesystem')
            require(t[key]['fstype'] in ('ext4', 'xfs', 'btrfs'), 'disk-backed filesystem required')
        workspace = absolute(t['workspace'])
        safe_parents(workspace)
        require(filesystem('/') == t['root_fs'] and filesystem(workspace) == t['workspace_fs'], 'target filesystem mismatch')
        fields(t['disks'], 'vda vdb')
        for device, serial in t['disks'].items():
            require(query(['/usr/bin/lsblk', '-dn', '-o', 'SERIAL', '/dev/' + device]) == text(serial), 'target disk serial mismatch')
        s = d['source']
        fields(s, 'path base_commit history history_sha256 files tree_sha256 index_sha256 new_files')
        source = absolute(s['path'])
        require(source.is_relative_to(workspace) and source != workspace, 'source path scope')
        safe_parents(source)
        require(type(s['files']) is list and s['files'], 'schema source files')
        names = []
        for item in s['files']:
            fields(item, 'path kind mode sha256')
            p = PurePosixPath(text(item['path']))
            require(not p.is_absolute() and '..' not in p.parts and str(p) == item['path'] and '.git' not in p.parts, 'source path')
            require(item['kind'] in ('file', 'symlink') and type(item['mode']) is int and 0 <= item['mode'] <= 0o7777, 'schema source mode')
            require(re.fullmatch('[0-9a-f]{64}', text(item['sha256'])), 'schema source hash')
            names.append(item['path'])
        require(names == sorted(set(names)), 'duplicate/unordered source path')
        require(type(s['new_files']) is list and set(s['new_files']) <= set(names) and len(set(s['new_files'])) == len(s['new_files']), 'schema new files')
        require(sha(json.dumps(s['files'], sort_keys=True, separators=(',', ':')).encode()) == s['tree_sha256'], 'source tree manifest')
        require(source_files(source) == s['files'], 'source bytes/modes mismatch')
        history = absolute(s['history'])
        require(history.is_relative_to(workspace) and not history.is_relative_to(source), 'history path scope')
        require(sha(history.read_bytes()) == s['history_sha256'], 'source history hash')
        git = ['/usr/bin/git', '--no-optional-locks', '-c', 'core.fsmonitor=false', '-c', 'diff.autoRefreshIndex=false', '-C', str(source)]
        require(query(git + ['rev-parse', 'HEAD']) == text(s['base_commit']), 'source history HEAD')
        listed = query(git + ['bundle', 'list-heads', str(history)]).splitlines()
        require(listed == [s['base_commit'] + ' refs/heads/main'], 'source standalone main history scope')
        index = query(git + ['ls-files', '--stage'])
        require(sha((index + '\n').encode()) == s['index_sha256'], 'source index mismatch')
        # Relocated indexes report stat-cache candidates through diff --name-only
        # with autoRefreshIndex=false. Porcelain validates content without writing
        # the index. The independent full manifest and index digest above also
        # bind every byte/mode/blob; do not refresh an index during admission.
        status = query(git + ['status', '--porcelain=v1', '-z', '--untracked-files=all'])
        require(all(len(item) >= 3 and item[1] == ' ' for item in status.split('\0') if item), 'source index working mismatch')
        fields(d['protection'], 'files')
        require(type(d['protection']['files']) is list, 'schema protection')
        for item in d['protection']['files']:
            fields(item, 'path sha256')
            p = absolute(item['path'])
            require(not p.is_symlink() and sha(p.read_bytes()) == text(item['sha256']), 'protected input mismatch')
        require(type(d['operations']) is list and d['operations'], 'schema operations')
        selected, keys = None, set()
        for op in d['operations']:
            fields(op, 'run_id suite mode role effects tmpdir runs deadline inputs nested' + (' native' if 'native' in op else '') + (' parameters' if 'parameters' in op else ''))
            require(re.fullmatch('[a-z0-9][a-z0-9-]{0,63}', text(op['run_id'])), 'schema run ID')
            key = (text(op['suite']), text(op['mode']))
            require(key not in keys, 'duplicate operation')
            keys.add(key)
            try:
                _, expected_role, expected_effects = policy(*key)
            except ValueError as error:
                raise AdmissionError(str(error)) from error
            require(op['role'] == expected_role and op['effects'] == expected_effects, 'operation scope mismatch')
            require(type(op['deadline']) is int and 0 < op['deadline'] <= 3600, 'schema deadline')
            tmp = absolute(op['tmpdir'])
            runs = absolute(op['runs'])
            require(tmp != Path('/tmp') and Path('/tmp') not in tmp.parents, 'unsafe TMPDIR')
            require(runs.is_relative_to(Path('/var/lib/scripts-underground/test-workflow-runs')) and tmp.is_relative_to(runs), 'TMPDIR/run path scope')
            require(not runs.is_relative_to(source) and not source.is_relative_to(runs), 'run/source path overlap')
            safe_parents(tmp, root=True)
            safe_parents(runs, root=True)
            require(filesystem(tmp) == t['workspace_fs'] and filesystem(runs) == t['workspace_fs'], 'TMPDIR disk mismatch')
            require(type(op['inputs']) is list and type(op['nested']) is list, 'schema operation inputs')
            for item in op['inputs']:
                fields(item, 'path sha256')
                p = absolute(item['path'])
                require(not p.is_symlink() and sha(p.read_bytes()) == text(item['sha256']), 'operation input mismatch')
            for resource in op['nested']:
                fields(resource, 'ctid tag mac hostname storage volume volume_uuid')
                Resource(**resource).validate()
            if 'native' in op:
                from test_pve import validate_native
                validate_native(op['native'], op)
            from test_inputs import bindings
            bindings(cls(d,path,op),required=key==(suite,mode))
            if key == (suite, mode):
                selected = op
        require(selected is not None, 'selected operation scope absent')
        require(os.environ.get('TMPDIR') == selected['tmpdir'], 'TMPDIR environment mismatch')
        return cls(d, path, selected)

    def recheck(self):
        return Context.admit(self.path, self.operation['suite'], self.operation['mode'])


def exclusive_json(path, data):
    with path.open('x') as stream:
        json.dump(data, stream, sort_keys=True)
        stream.flush()
        os.fsync(stream.fileno())
    path.chmod(0o400)


class Run:
    def __init__(self, context, existing=None):
        self.context = context
        self.directory = None
        self.lock = None
        self.existing=existing

    def __enter__(self):
        self.context.recheck()
        parent = Path(self.context.operation['runs'])
        lock_path = parent / 'owner.lock'
        descriptor = os.open(lock_path, os.O_RDWR | os.O_CREAT | os.O_NOFOLLOW, 0o600)
        self.lock = os.fdopen(descriptor, 'r+')
        current = os.fstat(descriptor)
        require(stat.S_ISREG(current.st_mode) and current.st_uid == 0 and not current.st_mode & 0o022
                and current.st_nlink == 1 and current.st_size == 0 and lock_path.stat().st_ino == current.st_ino, 'run lock custody')
        fcntl.flock(self.lock, fcntl.LOCK_EX | fcntl.LOCK_NB)
        if self.existing is None:
            self.directory = parent / (self.context.operation['run_id'] + '-' + uuid.uuid4().hex)
            self.directory.mkdir(mode=0o700)
            self.record('run', {'context_sha256': sha(self.context.path.read_bytes()), 'source': self.context.document['source']['tree_sha256']})
        else:
            self.directory=absolute(str(self.existing));safe_parents(self.directory,root=True)
            require(self.directory.parent==parent and self.directory.name.startswith(self.context.operation['run_id']+'-'),'finalize run path scope')
            self.record('finalize-open',dict(context_sha256=sha(self.context.path.read_bytes())))
        return self

    def record(self, label, data):
        path=self.directory / f'{time.time_ns()}-{label}.json'
        exclusive_json(path, data)
        return path

    def execute(self, argv, seconds):
        self.context.recheck()
        require(type(argv) in (list, tuple) and argv and all(type(a) is str and '\x00' not in a for a in argv), 'typed argv required')
        require(Path(argv[0]).is_absolute() and type(seconds) is int and 0 < seconds <= self.context.operation['deadline'], 'argv/deadline scope')
        env = {'PATH': '/usr/local/go/bin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin', 'TMPDIR': self.context.operation['tmpdir'], 'HOME': str(self.directory), 'PYTHONDONTWRITEBYTECODE': '1'}
        self.record('process-intent', {'argv': list(argv), 'seconds': seconds})
        with subprocess.Popen(argv, cwd=self.directory, env=env, stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True, start_new_session=True) as child:
            try:
                out, err = child.communicate(timeout=seconds)
                rc = child.returncode
            except subprocess.TimeoutExpired:
                os.killpg(child.pid, signal.SIGTERM)
                try:
                    out, err = child.communicate(timeout=5)
                except subprocess.TimeoutExpired:
                    os.killpg(child.pid, signal.SIGKILL)
                    out, err = child.communicate(timeout=5)
                rc = 124
        self.record('process-result', {'argv': list(argv), 'status': rc, 'stdout': out, 'stderr': err})
        return subprocess.CompletedProcess(argv, rc, out, err)

    def __exit__(self, kind, value, traceback):
        if self.directory:
            self.record('terminal', {'status': 'failure' if kind else 'complete'})
        if self.lock:
            self.lock.close()


@dataclass(frozen=True)
class Resource:
    ctid: int
    tag: str
    mac: str
    hostname: str
    storage: str
    volume: str
    volume_uuid: str

    def validate(self):
        require(type(self.ctid) is int and 100 <= self.ctid < 1000000, 'nested ID scope')
        for value in (self.tag, self.mac, self.hostname, self.storage, self.volume, self.volume_uuid):
            require(type(value) is str and re.fullmatch('[A-Za-z0-9:_.-]{1,128}', value), 'nested resource scope')


class NestedOwner:
    """One admitted ID and immutable creation/transition receipts under Run lock.

    The native adapter owns atomic no-clobber creation and independent config/LV
    observations. A recording adapter exercises this contract without PVE effects.
    """
    def __init__(self, run, spec, native):
        spec.validate()
        require(asdict(spec) in run.context.operation['nested'], 'nested resource not admitted')
        self.run, self.spec, self.native = run, spec, native
        self.creation, self.current = None, None
        self.snapshots = set()
        self.cleanup_status = None
        self.pending = None

    def acknowledgement_path(self):
        require(self.pending is not None,'preservation pending receipt required')
        return self.run.context.path.parent/'acknowledgements'/(self.run.directory.name+'-'+self.pending.name)

    def evidence_identity(self):
        require(hasattr(self.native,'evidence_identity'),'native preservation state evidence required')
        facts=self.native.evidence_identity(self.current)
        require(type(facts) is dict and facts.get('state') in ('stopped','status: stopped'),
                'preservation requires proven stopped resource')
        return facts

    @staticmethod
    def file_fact(path):
        path=absolute(str(path));s=path.lstat()
        require(stat.S_ISREG(s.st_mode) and not path.is_symlink(),'preservation evidence kind')
        raw=path.read_bytes()
        return dict(path=str(path),bytes=len(raw),sha256=sha(raw))

    def prepare_preservation(self):
        self.checked()
        status=self.native.invoke('stop',self.current)
        self.run.record('stop-result',dict(status=status,identity=asdict(self.current)))
        if status:return status
        self.checked()
        result=self.run.record('consumer-result',dict(status=0,identity=asdict(self.current),creation=self.creation))
        op=self.run.context.operation;doc=self.run.context.document
        paths=[*(p for p in self.run.directory.iterdir() if p.is_file()),self.run.context.path]
        native=op.get('native',{})
        if native.get('lineage'):paths.append(Path(native['lineage']))
        for name,value in op.get('parameters',{}).items():
            if type(value) is dict and set(value)=={'path','sha256'}:
                path=Path(value['path']);paths.append(path)
                from test_registry import INPUT_BINDINGS
                if INPUT_BINDINGS[op['suite'],op['mode']][name].kind=='tree':
                    manifest=read_custody(path)
                    paths.extend(Path(manifest['root'])/r['path'] for r in manifest['files'])
        binding=dict(run=self.run.directory.name,run_id=op['run_id'],suite=op['suite'],mode=op['mode'],
                     target=doc['target']['uuid'],source=doc['source']['tree_sha256'],context_sha256=sha(self.run.context.path.read_bytes()),
                     resource=asdict(self.current),creation=self.creation,creation_sha256=sha(json.dumps(self.creation,sort_keys=True).encode()),
                     transition_sha256=None,result=self.file_fact(result),current=self.evidence_identity())
        data=dict(schema=1,created_ns=time.time_ns(),binding=binding,evidence=[self.file_fact(p) for p in sorted(set(paths))])
        self.pending=self.run.directory/('preservation-pending-'+uuid.uuid4().hex+'.json')
        exclusive_json(self.pending,data)
        self.run.record('preservation-state',dict(consumer_status=0,preservation='awaiting-external-preservation',state='stopped',pending=str(self.pending)))
        return 0

    def verify_preservation(self,record=True):
        self.checked()
        require(self.pending is not None,'external preservation acknowledgement required')
        pending=read_custody(self.pending);fields(pending,'schema created_ns binding evidence')
        b=pending['binding'];doc=self.run.context.document
        fields(b,'run run_id suite mode target source context_sha256 resource creation creation_sha256 transition_sha256 result current')
        require(pending['schema']==1 and b['run']==self.run.directory.name and b['run_id']==self.run.context.operation['run_id']
                and b['source']==doc['source']['tree_sha256'] and b['target']==doc['target']['uuid']
                and b['context_sha256']==sha(self.run.context.path.read_bytes()) and b['resource']==asdict(self.current)
                and b['creation']==self.creation and b['creation_sha256']==sha(json.dumps(self.creation,sort_keys=True).encode())
                and (b['suite'],b['mode'])==(self.run.context.operation['suite'],self.run.context.operation['mode'])
                and b['current']==self.evidence_identity(),'pending current binding changed')
        require(all(self.file_fact(Path(v['path']))==v for v in pending['evidence']),'declared preservation evidence changed')
        ackpath=self.acknowledgement_path()
        try:
            ackpath.lstat()
        except FileNotFoundError:
            # A genuinely absent leaf/directory is pending; unsafe ancestry,
            # unreadable custody or rejected current/evidence facts are not.
            for parent in ackpath.parents:
                try:parent.lstat()
                except FileNotFoundError:continue
                safe_parents(parent,root=True)
                break
            self.checked()
            require(b['current']==self.evidence_identity(),'pending current binding changed')
            raise PreservationPending('external preservation acknowledgement missing')
        ack=read_custody(ackpath)
        require(not ackpath.stat().st_mode&0o222,'acknowledgement must be read-only')
        fields(ack,'schema pending_sha256 external_manifest_sha256 external_manifest')
        require(type(ack['schema']) is int and ack['schema']==1 and ack['pending_sha256']==sha(self.pending.read_bytes()),'stale/wrong preservation acknowledgement')
        manifest=ack['external_manifest'];fields(manifest,'schema pending files copied_at_ns destination archive_sha256 archive_bytes')
        require(manifest['schema']==1 and manifest['pending']==self.file_fact(self.pending) and manifest['files']==pending['evidence']
                and type(manifest['copied_at_ns']) is int and pending['created_ns']<=manifest['copied_at_ns']<=time.time_ns()+60*10**9
                and type(manifest['archive_bytes']) is int and manifest['archive_bytes']>0
                and re.fullmatch('[a-f0-9]{64}',manifest['archive_sha256']) and type(manifest['destination']) is str and manifest['destination'].startswith('/'), 'external preservation manifest mismatch')
        require(sha(json.dumps(manifest,sort_keys=True).encode())==ack['external_manifest_sha256'],'external manifest hash mismatch')
        if record:self.run.record('preservation-accepted',dict(pending_sha256=ack['pending_sha256'],external_manifest_sha256=ack['external_manifest_sha256'],accepted_ns=time.time_ns(),resource=asdict(self.current)))
        self.checked()
        return ack

    def observe(self):
        try:
            row = self.native.observe(self.spec.ctid)
            require(row is None or type(row) is Resource, 'unknown observation')
            return row
        except (OSError, ValueError, TypeError) as error:
            raise AdmissionError('nested observation failed') from error

    def checked(self):
        self.run.context.recheck()
        require(self.creation is not None and self.current is not None, 'unowned resource')
        require(self.observe() == self.current, 'nested identity mismatch')

    def create(self):
        self.run.context.recheck()
        require(self.creation is None and self.observe() is None, 'nested ID present')
        self.run.record('create-intent', asdict(self.spec))
        require(self.observe() is None, 'nested ID present after intent')
        status = self.native.invoke('create', self.spec)
        try:
            observed = self.observe()
        except AdmissionError as error:
            self.creation = {'requested': asdict(self.spec), 'observed': None, 'status': status, 'observation_error': str(error)}
            self.run.record('create-result', self.creation)
            raise
        self.creation = {'requested': asdict(self.spec), 'observed': asdict(observed) if observed else None, 'status': status}
        self.run.record('create-result', self.creation)
        # Creation observes the new LV UUID; it cannot be known before create.
        if observed is not None and asdict(observed) | {'volume_uuid': self.spec.volume_uuid} == asdict(self.spec):
            self.current = observed
        else:
            require(status != 0, 'creation identity mismatch')
        return status

    def exec(self, argv):
        self.checked()
        require(type(argv) in (list, tuple) and argv and all(type(a) is str and '\x00' not in a for a in argv), 'typed argv required')
        return self.native.invoke('exec', self.current, tuple(argv))

    def snapshot(self, name):
        self.checked()
        require(re.fullmatch('[a-z0-9-]{1,64}', name) and name not in self.snapshots, 'snapshot scope')
        status = self.native.invoke('snapshot', self.current, (name,))
        if status == 0:
            self.snapshots.add(name)
        self.run.record('snapshot', {'name': name, 'identity': asdict(self.current), 'status': status})
        return status

    def rollback(self, name):
        self.checked()
        require(name in self.snapshots, 'snapshot not owned')
        before = self.current
        self.run.record('rollback-intent', {'name': name, 'before': asdict(before)})
        status = self.native.invoke('rollback', before, (name,))
        observed = self.observe()
        self.run.record('rollback-result', {'name': name, 'status': status, 'observed': asdict(observed) if observed else None})
        require(status == 0 and observed is not None and asdict(observed) | {'volume_uuid': before.volume_uuid} == asdict(before), 'rollback identity mismatch')
        self.current = observed
        return status

    def cleanup(self):
        self.checked()
        self.verify_preservation()
        self.checked()
        status = self.native.invoke('destroy', self.current)
        self.run.record('destroy-result', {'status': status, 'identity': asdict(self.current)})
        if status == 0:
            require(self.observe() is None, 'destroy absence not proven')
        return status

    def finish(self, original_status):
        if original_status:
            preservation = self.preserve_failure(original_status)
            self.cleanup_status = preservation['preservation_status']
            disposition, state = preservation['disposition'], preservation['state']
        else:
            disposition,state='retirement-failed','unknown'
            try:
                if self.pending is None:
                    self.cleanup_status=self.prepare_preservation()
                else:self.cleanup_status=0
                if self.cleanup_status==0:
                    self.checked()
                    self.cleanup_status = self.cleanup()
                if self.cleanup_status==0:
                    disposition,state='retired','absent'
            except PreservationPending as error:
                self.run.record('preservation-awaiting',dict(error=str(error),pending=str(self.pending),state='stopped'))
                self.cleanup_status=75
                disposition,state='awaiting-external-preservation','stopped'
            except (AdmissionError, OSError, subprocess.SubprocessError) as error:
                self.run.record('preservation-refused',dict(error=str(error),pending=str(self.pending),state='unknown'))
                self.cleanup_status = 70
        self.run.record('cleanup-result', {'original_status': original_status, 'cleanup_status': self.cleanup_status,
                                          'disposition': disposition, 'state': state})
        return original_status or self.cleanup_status

    def preserve_failure(self, original_status):
        """Stop only proven-owned failed resources; retain config/LV and status.

        A completed successful stop boundary establishes stopped state. A failed
        stop cannot establish running or stopped, even if identity still matches.
        Unknown/unowned resources are recorded without lifecycle calls. Explicit
        cleanup remains a separate authorized retirement operation.
        """
        require(original_status != 0, 'failure preservation requires failure status')
        result = dict(original_status=original_status, preservation_status=70,
                      disposition='retained-unverified', state='unknown', stop_status=None,
                      owned_identity=asdict(self.current) if self.current else None,
                      observed_identity=None,
                      creation_status=self.creation['status'] if self.creation else None, error=None)
        try:
            self.checked()
            result['stop_status'] = self.native.invoke('stop', self.current)
            self.run.record('stop-result', {'status': result['stop_status'], 'identity': asdict(self.current)})
            observed = self.observe()
            result['observed_identity'] = asdict(observed) if observed else None
            require(observed == self.current, 'nested identity mismatch after stop')
            result['preservation_status'] = result['stop_status']
            if result['stop_status'] == 0:
                result.update(disposition='preserved', state='stopped')
            else:
                result['disposition'] = 'preservation-incomplete'
        except (AdmissionError, OSError) as error:
            result['error'] = str(error)
        self.run.record('failure-preservation', result)
        return result
