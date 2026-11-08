"""Delegated CT only. Native package/service/RESP outcomes, no lifecycle authority."""
import base64
import hashlib
import json
import os
from pathlib import Path
import pwd
import secrets
import socket
import subprocess
import sys
import time
from dragonfly_observer import capture_process, identity, same_identity, stable

WORK = Path(sys.argv[1])
CONFIG = Path('/etc/dragonfly/dragonfly.conf')
RUNTIME = Path('/etc/dragonfly/scripts-underground-runtime.env')
command_count = 0
protocol_count = 0
capture_count = 0


def command(*argv, seconds=60):
    global command_count
    command_count += 1
    try:
        result = subprocess.run(argv, capture_output=True, text=True, timeout=seconds)
    except subprocess.TimeoutExpired as error:
        record('command-' + str(command_count), dict(argv=argv, status=124, stdout=error.stdout, stderr=error.stderr))
        raise
    record('command-' + str(command_count), dict(argv=argv, status=result.returncode, stdout=result.stdout, stderr=result.stderr))
    result.check_returncode()
    return result.stdout.strip()


def record(name, data):
    def encode(value):
        if isinstance(value, bytes):
            return dict(bytes_base64=base64.b64encode(value).decode())
        raise TypeError(type(value).__name__)

    with (WORK / (name + '.json')).open('x') as out:
        json.dump(data, out, sort_keys=True, indent=2, default=encode)
        out.flush()
        os.fsync(out.fileno())


def digest(path):
    s = path.stat()
    return dict(sha256=hashlib.sha256(path.read_bytes()).hexdigest(), mode=s.st_mode & 0o7777, uid=s.st_uid, gid=s.st_gid)


KEY = b'su-dragonfly-' + secrets.token_hex(16).encode()
VALUE = secrets.token_bytes(96) + b'\x00\r\nprivate RESP roundtrip'
record('request-identity', dict(key_base64=base64.b64encode(KEY).decode(), value_base64=base64.b64encode(VALUE).decode()))
ACCOUNT = pwd.getpwnam('dfly')
passwords = [v.split('=', 1)[1].encode() for v in CONFIG.read_text().splitlines() if v.startswith('--requirepass=')]
record('initial-config-metadata', dict(config=digest(CONFIG), runtime=digest(RUNTIME), password_count=len(passwords), account_uid=ACCOUNT.pw_uid, account_gid=ACCOUNT.pw_gid))
assert len(passwords) == 1 and passwords[0]
PASSWORD = passwords[0]


def resp(*args, authenticated=True):
    global protocol_count
    protocol_count += 1
    call = protocol_count
    step = 0

    def event(kind, data):
        nonlocal step
        step += 1
        record('protocol-' + str(call) + '-' + str(step), dict(kind=kind, data=data))

    def send(connection, values):
        values = [v if isinstance(v, bytes) else str(v).encode() for v in values]
        # AUTH response/framing is raw evidence; credential bytes stay private.
        event('send', dict(command='AUTH', secret_redacted=True) if values[0] == b'AUTH' else dict(arguments_base64=[base64.b64encode(v).decode() for v in values]))
        connection.sendall(b'*' + str(len(values)).encode() + b'\r\n' + b''.join(b'$' + str(len(v)).encode() + b'\r\n' + v + b'\r\n' for v in values))

    def read(stream):
        prefix = stream.read(1)
        line = stream.readline()
        event('response-header', dict(prefix=prefix, line=line))
        assert line.endswith(b'\r\n'), (prefix, line)
        body = line[:-2]
        if prefix == b'$':
            length = int(body)
            if length == -1:
                return None
            value = stream.read(length)
            terminator = stream.read(2)
            event('response-bulk', dict(value=value, terminator=terminator))
            assert len(value) == length and terminator == b'\r\n'
            return value
        if prefix == b':':
            return int(body)
        assert prefix in (b'+', b'-'), (prefix, body)
        return (prefix.decode(), body.decode())

    try:
        with socket.create_connection(('127.0.0.1', 6379), timeout=5) as connection:
            stream = connection.makefile('rb')
            if authenticated:
                send(connection, ['AUTH', PASSWORD])
                auth = read(stream)
                event('auth-result', auth)
                assert auth == ('+', 'OK')
            send(connection, args)
            result = read(stream)
            event('result', result)
            return result
    except BaseException as error:
        event('exception', dict(type=type(error).__name__, message=str(error)))
        raise


def properties():
    names = ('MainPID', 'User', 'Group', 'PrivateTmp', 'PrivateTmpEx', 'ReadOnlyPaths', 'PrivateDevices', 'ProtectHome', 'ProtectSystem', 'NoNewPrivileges', 'MemoryDenyWriteExecute', 'ProtectKernelModules', 'ProtectKernelTunables', 'ProtectControlGroups', 'RestrictNamespaces', 'RestrictRealtime', 'RestrictAddressFamilies', 'CapabilityBoundingSet', 'UMask', 'LimitNOFILE', 'RuntimeDirectoryMode')
    raw = command('systemctl', 'show', 'dragonfly', *[value for name in names for value in ('-p', name)])
    return dict(line.split('=', 1) for line in raw.splitlines())


def process_facts(label, pid):
    global capture_count
    capture_count += 1
    prefix = label + '-capture-' + str(capture_count) + '-'
    return capture_process(pid, lambda name, value: record(prefix + name, value))


def ready():
    end = time.monotonic() + 60
    while True:
        try:
            props = properties()
            pid = int(props['MainPID'])
            snapshot = process_facts('readiness', pid)
            pong = resp('PING')
            after = properties()
            record('readiness-result-' + str(capture_count), dict(properties_before=props, properties_after=after, snapshot=snapshot, response=pong))
            assert pong == ('+', 'PONG') and pid > 0 and after['MainPID'] == str(pid) and stable(snapshot, '/usr/bin/dragonfly')
            return pid
        except (OSError, AssertionError):
            if time.monotonic() >= end:
                raise
            time.sleep(0.5)


def observe(label):
    pid = ready()
    props = properties()
    snapshot = process_facts(label, pid)
    value = resp('GET', KEY)
    denied = resp('GET', KEY, authenticated=False)
    info = resp('INFO', 'ALL')
    props_after = properties()
    try:
        after_protocol = identity(pid)
    except OSError as error:
        after_protocol = dict(error=repr(error))
    elf = Path('/usr/bin/dragonfly').read_bytes()
    directory = Path('/var/lib/dragonfly/tmp')
    metadata = directory.stat()
    filesystem = command('findmnt', '-rn', '-T', str(directory), '-o', 'FSTYPE')
    facts = dict(label=label, pid=pid, value_base64=base64.b64encode(value).decode() if isinstance(value, bytes) else value,
                 unauthenticated=denied, properties=props, properties_after=props_after, process_snapshot=snapshot,
                 identity_after_protocol=after_protocol, info=info.decode(errors='replace') if isinstance(info, bytes) else info,
                 temporary_directory=dict(uid=metadata.st_uid, gid=metadata.st_gid, mode=metadata.st_mode & 0o777, filesystem=filesystem),
                 elf=digest(Path('/usr/bin/dragonfly')), config=digest(CONFIG), runtime=digest(RUNTIME), wall_ns=time.time_ns())
    # Everything above is persisted before any outcome, type or hardening check.
    record(label + '-raw', facts)
    assert stable(snapshot, '/usr/bin/dragonfly') and same_identity(snapshot['identity_before'], after_protocol)
    assert props['MainPID'] == props_after['MainPID'] == str(pid)
    assert value == VALUE and denied[0] == '-' and 'NOAUTH' in denied[1], denied
    status = dict(line.split(':', 1) for line in snapshot['status'].splitlines() if ':' in line)
    assert ACCOUNT.pw_uid != 0 and ACCOUNT.pw_gid != 0
    assert list(map(int, status['Uid'].split())) == [ACCOUNT.pw_uid] * 4
    assert list(map(int, status['Gid'].split())) == [ACCOUNT.pw_gid] * 4
    assert elf[:6] == b'\x7fELF\x02\x01' and int.from_bytes(elf[18:20], 'little') == 62
    assert snapshot['environment']['tmpdir'] == '/var/lib/dragonfly/tmp'
    for path in ('/tmp', '/var/tmp'):
        observed = snapshot['paths'][path]
        assert observed['readonly'] and observed['f_flag'] & os.ST_RDONLY
        assert len(observed['matching_mount_rows']) == 1
        fields = observed['matching_mount_rows'][0].split()
        assert int(fields[0]) == observed['mount_id'] and 'ro' in fields[5].split(',') and fields[fields.index('-') + 1] == 'tmpfs'
        assert not observed['directory_entries']
    assert props['User'] == props['Group'] == 'dfly' and props['PrivateTmpEx'] == 'disconnected' and props['PrivateTmp'] == 'yes'
    assert props['ProtectSystem'] == 'full' and props['ProtectHome'] == 'yes'
    for name in ('PrivateDevices', 'NoNewPrivileges', 'MemoryDenyWriteExecute', 'ProtectKernelModules', 'ProtectKernelTunables', 'ProtectControlGroups', 'RestrictRealtime'):
        assert props[name] == 'yes', (name, props[name])
    assert set(props['CapabilityBoundingSet'].split()) == {'cap_setgid', 'cap_setuid', 'cap_sys_resource'}
    assert set(props['RestrictAddressFamilies'].split()) == {'AF_INET', 'AF_INET6', 'AF_UNIX'}
    assert int(props['UMask'], 8) == 0o007 and props['LimitNOFILE'] == '262144' and int(props['RuntimeDirectoryMode'], 8) == 0o2755
    assert metadata.st_uid == ACCOUNT.pw_uid and metadata.st_gid == ACCOUNT.pw_gid and metadata.st_mode & 0o777 == 0o700
    assert filesystem not in ('tmpfs', 'ramfs', '')
    assert '--disk_backpressure_folder=' not in CONFIG.read_text()
    assert isinstance(info, bytes)
    facts.update(process_status=status, mountinfo=snapshot['mountinfo'], environment_tmpdir=snapshot['environment']['tmpdir'])
    record(label, facts)
    return facts


ready()
assert resp('GET', KEY, authenticated=False)[0] == '-'
assert resp('SET', KEY, VALUE) == ('+', 'OK')
before = observe('initial-authenticated')
assert resp('SAVE') == ('+', 'OK')
snapshots = sorted(Path('/var/lib/dragonfly').glob('dump*'))
record('snapshot-raw', [dict(path=str(p),file=p.is_file(),bytes=p.stat().st_size) for p in snapshots])
assert snapshots and all(p.is_file() and p.stat().st_size > 0 for p in snapshots)
record('snapshot-files', {str(p): digest(p) for p in snapshots})
CONFIG.write_text(CONFIG.read_text() + '# operator configuration retained\n')
operator = Path('/etc/systemd/system/dragonfly.service.d/operator.conf')
operator.write_text('[Service]\nRestartSec=7\n')
operator.chmod(0o640)
data = Path('/var/lib/dragonfly/operator-data')
data.write_bytes(secrets.token_bytes(128))
data.chmod(0o600)
protected = [CONFIG, RUNTIME, operator, Path('/etc/systemd/system/dragonfly.service.d/scripts-underground.conf'), data]
saved = {str(p): digest(p) for p in protected}
command('systemctl', 'daemon-reload')
command('systemctl', 'restart', 'dragonfly')
after_restart = observe('after-snapshot-restart')
assert after_restart['pid'] != before['pid']
assert {str(p): digest(p) for p in protected} == saved
version = Path('/root/.dragonfly').read_text().strip()
updater = Path('/usr/local/sbin/update')
updater_lines = updater.read_text().splitlines()
baked = {}
for field, value in [('LXC_SCRIPT_ID', 'dragonfly'), ('LXC_REQUIRED_CPU', '2'), ('LXC_REQUIRED_RAM', '1024')]:
    lines = [line for line in updater_lines if line.startswith('declare -- ' + field + '=')]
    assert lines == ['declare -- ' + field + '=' + value], (field, lines)
    baked[field] = value
record('installed-updater-provenance', dict(file=digest(updater), fields=baked))
assert command('dpkg-query', '-W', '-f=${Version} ${Architecture}', 'dragonfly') == '2.1 amd64'
assert version == '2.1'
outcomes = [before, after_restart]
for label, arguments in [('normal-noop-update', []), ('forced-same-version-reinstall', ['--clean'])]:
    package_log = WORK / (label + '-package.log')
    with (WORK / (label + '.log')).open('x') as out:
        result = subprocess.run(['/usr/local/sbin/update', *arguments], env=dict(os.environ, var_appversion='v2.1', INSTALL_LOG=str(package_log)), stdout=out, stderr=subprocess.STDOUT, timeout=600)
    record(label + '-update-result', dict(argv=['/usr/local/sbin/update', *arguments], status=result.returncode, package_log=str(package_log), terminal_log=str(WORK / (label + '.log'))))
    assert result.returncode == 0, (label, result.returncode)
    observed = observe(label)
    assert {str(p): digest(p) for p in protected} == saved
    assert not Path('/var/lib/scripts-underground/update-pending/dragonfly').exists()
    if not arguments:
        assert observed['pid'] == after_restart['pid']
    else:
        assert observed['pid'] != after_restart['pid']
        assert 'Unpacking dragonfly' in package_log.read_text()
    outcomes.append(observed)
assert resp('SAVE') == ('+', 'OK')
command('systemctl', 'restart', 'dragonfly')
outcomes.append(observe('final-cold-readback'))
assert {str(p): digest(p) for p in protected} == saved
record('package', dict(identity=command('dpkg-query', '-W', '-f=${Package} ${Version} ${Architecture}', 'dragonfly'), audit=command('dpkg', '--audit'), unit=command('systemctl', 'cat', 'dragonfly'), systemd=command('systemctl', '--version'), cgroup=Path('/sys/fs/cgroup/memory.max').read_text(), receiver_filesystem=command('findmnt', '-rn', '-T', os.environ['TMPDIR'], '-o', 'SOURCE,FSTYPE'), data_files={str(p): digest(p) for p in Path('/var/lib/dragonfly').glob('dump*') if p.is_file()}))
summary = dict(status='consumer-pass', version=version, key_base64=base64.b64encode(KEY).decode(), value_base64=base64.b64encode(VALUE).decode(), protected=saved, outcomes=outcomes, proof='native amd64 package/ELF/dfly/authenticated RESP/snapshot/restart/no-op update/forced same-version reinstall', arm_runtime=False, static_cli_inventory_checked=True)
record('accepted', summary)
print('DRAGONFLY_NATIVE_PASS ' + json.dumps(summary, sort_keys=True), flush=True)
