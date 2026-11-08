"""Plain read-only kernel observations. No consumer imports or workflow at import."""
import hashlib
import os
from pathlib import Path


def capture(path, table):
    """Return an open read-only FD and its native VFS/mount binding."""
    fd = os.open(path, os.O_RDONLY | os.O_DIRECTORY | os.O_CLOEXEC)
    try:
        info = Path('/proc/self/fdinfo/' + str(fd)).read_text()
        metadata = os.fstat(fd)
        filesystem = os.fstatvfs(fd)
        fields = dict(line.split(':', 1) for line in info.splitlines() if ':' in line)
        mount_id = int(fields['mnt_id'].strip())
        return fd, dict(opened_path=str(path), open_flags=os.O_RDONLY | os.O_DIRECTORY | os.O_CLOEXEC,
                        fdinfo=info, mount_id=mount_id,
                        matching_mount_rows=[line for line in table.splitlines() if int(line.split()[0]) == mount_id],
                        device=metadata.st_dev, inode=metadata.st_ino, mode=metadata.st_mode,
                        uid=metadata.st_uid, gid=metadata.st_gid, statvfs=list(filesystem),
                        f_flag=filesystem.f_flag, st_rdonly_mask=os.ST_RDONLY,
                        readonly=bool(filesystem.f_flag & os.ST_RDONLY), directory_entries=os.listdir(fd))
    except BaseException:
        os.close(fd)
        raise


def identity(pid):
    process = Path('/proc') / str(pid)
    raw = (process / 'stat').read_text()
    metadata = (process / 'exe').stat()
    return dict(pid=pid, birth=raw.rsplit(') ', 1)[1].split()[19], exe=os.readlink(process / 'exe'),
                executable_device=metadata.st_dev, executable_inode=metadata.st_ino, raw_stat=raw)


def same_identity(first, second):
    keys = ('pid', 'birth', 'exe', 'executable_device', 'executable_inode')
    return all(key in first and key in second and first[key] == second[key] for key in keys)


def capture_process(pid, sink):
    """Persist raw facts as collected; report read failures as data before checks."""
    data = dict(pid=pid, errors=[], paths={})
    process = Path('/proc') / str(pid)

    def collect(name, getter):
        try:
            value = getter()
            data[name] = value
            sink(name, value)
            return value
        except (OSError, ValueError, KeyError) as error:
            item = dict(field=name, error=repr(error))
            data['errors'].append(item)
            sink(name + '-error', item)
            return None

    if not isinstance(pid, int) or pid <= 0:
        data['errors'].append(dict(field='pid', error='invalid service PID'))
        sink('process', data)
        return data
    collect('identity_before', lambda: identity(pid))
    table = collect('mountinfo', lambda: (process / 'mountinfo').read_text())
    collect('status', lambda: (process / 'status').read_text())
    collect('cmdline_hex', lambda: (process / 'cmdline').read_bytes().hex())
    collect('namespaces', lambda: {name: os.readlink(process / 'ns' / name) for name in ('mnt', 'pid', 'user')})

    def environment():
        raw = (process / 'environ').read_bytes()
        fields = dict(item.split(b'=', 1) for item in raw.split(bytes([0])) if item)
        # Preserve required runtime evidence without exporting environment secrets.
        return dict(sha256=hashlib.sha256(raw).hexdigest(), bytes=len(raw),
                    keys=sorted(key.decode(errors='replace') for key in fields),
                    tmpdir=fields.get(b'TMPDIR', b'').decode(errors='replace'))

    collect('environment', environment)
    if table is not None:
        descriptors = []
        try:
            for path in ('/tmp', '/var/tmp'):
                try:
                    fd, facts = capture(process / 'root' / path.lstrip('/'), table)
                    descriptors.append(fd)
                    data['paths'][path] = facts
                    sink('path-' + path.strip('/').replace('/', '-'), facts)
                except (OSError, ValueError, KeyError) as error:
                    item = dict(field=path, error=repr(error))
                    data['errors'].append(item)
                    sink('path-error-' + path.strip('/').replace('/', '-'), item)
            collect('identity_after', lambda: identity(pid))
        finally:
            for fd in descriptors:
                os.close(fd)
    sink('process', data)
    return data


def stable(snapshot, expected_executable=None):
    before = snapshot.get('identity_before', {})
    after = snapshot.get('identity_after', {})
    return (not snapshot['errors'] and same_identity(before, after)
            and (expected_executable is None or before['exe'] == expected_executable))
