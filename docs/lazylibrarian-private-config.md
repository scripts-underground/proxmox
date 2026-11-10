# Private LazyLibrarian configuration

New installations use `UMask=0077` for the root-run service. This protects file
creation during both ordinary config saves and startup's pre-load rewrite.
Application updates do **not** migrate existing service policy or file modes.

## Existing installations

Run this procedure explicitly as container root during a maintenance window,
with no other updater, unit editor or config writer running. Review your service
locally first. This procedure supports the stock root-run service and filesystem,
not a different account, dynamic user, remapped root or custom permission policy.
It preserves the base unit, operator drop-ins, config bytes, owners and inodes.

Set `CONFIG_FILE` to the **actual absolute filename**, not an assumed default.
The stock filename is `/opt/LazyLibrarian/config.ini`. An application `--config`
argument takes precedence; otherwise `--datadir` selects its `config.ini`.
Resolve relative arguments against the service's working directory yourself.
Do not paste config, credentials or environment contents into support logs.

For example, after confirming the stock path:

```bash
export CONFIG_FILE=/opt/LazyLibrarian/config.ini
```

The block below stops the service, validates the exact config family, installs
one exclusive known drop-in, tightens existing files to0600 and starts only after
effective0077 is established. Missing optional backups stay absent. Symlinks,
special files, hardlinks, unexpected owners, unsafe ancestry and default ACLs on
the creation directory are refused, not repaired. Resolve unsupported policy
deliberately; do not remove safeguards to make the procedure continue.

<!-- lazylibrarian-private-config:begin -->
```bash
python3 - "${CONFIG_FILE:?Set CONFIG_FILE to the actual absolute config filename}" << 'PY'
import contextlib
import errno
import os
import pathlib
import secrets
import stat
import subprocess
import sys

SERVICE = 'lazylibrarian.service'
PARENT = '/etc/systemd/system/lazylibrarian.service.d'
NAME = '10-scripts-underground-private-config.conf'
BODY = b'[Service]\nUMask=0077\n'
stopped = False
phase = 'preflight'

class Refusal(Exception):
    pass

def require(ok, reason):
    if not ok:
        raise Refusal(reason)

def control(*args):
    result = subprocess.run(['systemctl', *args], capture_output=True,
                            text=True, timeout=90)
    require(result.returncode == 0, 'systemctl ' + args[0] + ' failed')
    return result.stdout.strip()

def show(name):
    return control('show', SERVICE, '--property=' + name, '--value')

def remember(stack, fd):
    stack.callback(os.close, fd)
    return fd

def directory(path, stack, create=False):
    parts = pathlib.PurePosixPath(path).parts
    fd = remember(stack, os.open('/', os.O_RDONLY | os.O_DIRECTORY | os.O_CLOEXEC))
    for index, part in enumerate(parts[1:]):
        try:
            child = os.open(part, os.O_RDONLY | os.O_DIRECTORY | os.O_NOFOLLOW | os.O_CLOEXEC, dir_fd=fd)
        except FileNotFoundError:
            if not create or index != len(parts) - 2:
                raise
            no_default_acl(fd)
            os.mkdir(part, 0o755, dir_fd=fd)
            child = os.open(part, os.O_RDONLY | os.O_DIRECTORY | os.O_NOFOLLOW | os.O_CLOEXEC, dir_fd=fd)
        fd = remember(stack, child)
        info = os.fstat(fd)
        require(info.st_uid == 0 and not info.st_mode & 0o022, 'unsafe directory ancestry')
    return fd

def no_default_acl(fd):
    try:
        acl = os.getxattr(fd, 'system.posix_acl_default')
    except OSError as error:
        if error.errno in (errno.ENODATA, errno.ENOTSUP):
            return
        raise
    require(not acl, 'default ACL requires an operator policy decision')

def regular(info):
    require(stat.S_ISREG(info.st_mode) and info.st_uid == 0 and info.st_nlink == 1,
            'expected a root-owned, single-link regular file')

def identity(info):
    return (info.st_dev, info.st_ino, info.st_uid, info.st_gid,
            info.st_nlink, info.st_size, info.st_mtime_ns)

def pin(parent, name, stack):
    fd = remember(stack, os.open(name, os.O_PATH | os.O_NOFOLLOW | os.O_CLOEXEC, dir_fd=parent))
    info = os.fstat(fd)
    regular(info)
    # Reopen the already classified inode, not an untrusted pathname. Never read it.
    handle = remember(stack, os.open('/proc/self/fd/' + str(fd), os.O_RDONLY | os.O_CLOEXEC))
    require(identity(os.fstat(handle)) == identity(info), 'file identity changed')
    return handle, info

@contextlib.contextmanager
def family(filename):
    with contextlib.ExitStack() as stack:
        parent = directory(str(filename.parent), stack)
        no_default_acl(parent)
        present, absent = [], []
        for suffix in ('', '.new', '.bak', '.bak2'):
            name = filename.name + suffix
            try:
                handle, info = pin(parent, name, stack)
                present.append((name, handle, info))
            except FileNotFoundError:
                require(suffix != '', 'active config is missing; do not initialize a replacement')
                absent.append(name)
        def check(private=False):
            for name, handle, original in present:
                linked = os.stat(name, dir_fd=parent, follow_symlinks=False)
                current = os.fstat(handle)
                regular(linked)
                require(identity(linked) == identity(current) == identity(original), 'config family changed')
                if private:
                    require(stat.S_IMODE(current.st_mode) == 0o600, 'config mode was not made private')
            for name in absent:
                try:
                    os.stat(name, dir_fd=parent, follow_symlinks=False)
                except FileNotFoundError:
                    continue
                raise Refusal('a previously absent config member appeared')
        check()
        yield present, check

def known_policy(parent, stack):
    try:
        handle, info = pin(parent, NAME, stack)
    except FileNotFoundError:
        return False
    require(not info.st_mode & 0o022 and info.st_size == len(BODY), 'private-policy filename collision')
    require(os.read(handle, len(BODY) + 1) == BODY, 'private-policy filename collision')
    return True

def policy(create):
    with contextlib.ExitStack() as stack:
        try:
            parent = directory(PARENT, stack, create=create)
        except FileNotFoundError:
            require(not create, 'private-policy parent is unavailable')
            return
        no_default_acl(parent)
        if known_policy(parent, stack) or not create:
            return
        stage = '.private-config-' + secrets.token_hex(12)
        fd = remember(stack, os.open(stage, os.O_WRONLY | os.O_CREAT | os.O_EXCL | os.O_NOFOLLOW, 0o600, dir_fd=parent))
        made = os.fstat(fd)
        try:
            remaining = BODY
            while remaining:
                count = os.write(fd, remaining)
                require(count > 0, 'private-policy write failed')
                remaining = remaining[count:]
            os.fchmod(fd, 0o644)
            os.fsync(fd)
            try:
                os.link(stage, NAME, src_dir_fd=parent, dst_dir_fd=parent, follow_symlinks=False)
            except FileExistsError:
                require(known_policy(parent, stack), 'private-policy filename collision')
        finally:
            current = os.stat(stage, dir_fd=parent, follow_symlinks=False)
            require((current.st_dev, current.st_ino) == (made.st_dev, made.st_ino), 'private stage identity changed')
            os.unlink(stage, dir_fd=parent)
        os.fsync(parent)
        require(known_policy(parent, stack), 'private-policy publication failed')

try:
    require(os.geteuid() == 0, 'run as container root')
    raw = sys.argv[1]
    filename = pathlib.PurePosixPath(raw)
    require(raw.startswith('/') and not raw.startswith('//') and str(filename) == raw
            and filename.name and '..' not in filename.parts and filename != pathlib.PurePosixPath('/'),
            'supply the actual normalized absolute config filename')
    require(show('LoadState') == 'loaded' and show('NeedDaemonReload') == 'no', 'review and load the actual unit first')
    require(show('User') in ('', 'root', '0') and show('DynamicUser') == 'no'
            and show('RootDirectory') == '' and show('RootImage') == '', 'unsupported service account/root scope')
    require(show('FragmentPath') == '/etc/systemd/system/lazylibrarian.service', 'unsupported service fragment')
    with contextlib.ExitStack() as stack:
        parent = directory('/etc/systemd/system', stack)
        pin(parent, 'lazylibrarian.service', stack)
    with family(filename):
        policy(False)
    phase = 'stop'
    control('stop', SERVICE)
    stopped = True
    require(show('ActiveState') == 'inactive' and show('MainPID') == '0', 'service did not drain')
    require(show('UMask') in ('0002', '0077'), 'custom umask requires an operator policy decision')
    phase = 'private configuration'
    with family(filename) as (members, check):
        policy(True)
        control('daemon-reload')
        require(show('UMask') == '0077', 'incompatible operator override; service remains stopped')
        check()
        for name, handle, original in members:
            check()
            os.fchmod(handle, 0o600)
        check(private=True)
        require(show('UMask') == '0077' and show('NeedDaemonReload') == 'no', 'unit policy changed; service remains stopped')
        phase = 'start'
        control('start', SERVICE)
        pid = show('MainPID')
        require(show('ActiveState') == 'active' and pid.isdecimal() and int(pid) > 0, 'service did not start')
        status = dict(line.split(':', 1) for line in pathlib.Path('/proc/' + pid + '/status').read_text().splitlines() if ':' in line)
        require(status['Umask'].strip() == '0077' and status['Uid'].split() == ['0'] * 4
                and show('MainPID') == pid, 'actual service process is not private/root')
    print('Private config policy and existing modes verified; service started.')
except (Exception, KeyboardInterrupt) as error:
    reason = str(error) if isinstance(error, Refusal) else type(error).__name__
    print('Privacy upgrade refused during ' + phase + ': ' + reason, file=sys.stderr)
    if stopped:
        try:
            control('stop', SERVICE)
            require(show('ActiveState') == 'inactive' and show('MainPID') == '0', 'stop readback failed')
        except (Exception, KeyboardInterrupt):
            print('Service stop also failed; inspect its state before continuing.', file=sys.stderr)
    sys.exit(1)
PY
```
<!-- lazylibrarian-private-config:end -->

If a later step fails, any files already tightened stay private; they are never
rolled back to weaker modes. The service remains stopped, or a stop failure is
reported explicitly. Correct the reported condition and repeat the same block.
An existing identical safe drop-in is reused; different content at its name is
never overwritten. Do not start with a later incompatible override: reload and
require effective0077 again before starting. This procedure is not a policy monitor.

`FILE_PERM` and `DIR_PERM` are unchanged. Explicit application media chmod choices
still apply, while other newly created media/cache files may now be more private.
Shared-group media workflows need separate qualification. Config privacy does not
establish metadata-provider, downloading or full library functionality.
