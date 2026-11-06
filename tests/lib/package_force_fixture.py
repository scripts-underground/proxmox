"""Actual release adapters and native APT/dpkg, never the outer package root.

Only HTTP/DNS and UI are models. Recording package executables normally exec the
installed tools; explicit fault controls refuse before a native transaction.
All roots and the legacy GitLab metadata directory are on the fixture disk.
"""
import hashlib
import json
import os
from pathlib import Path
import stat
import subprocess
import tempfile

SOURCE = Path(__file__).resolve().parents[2]
WORK = Path(tempfile.mkdtemp(prefix='package-force.', dir=os.environ['TMPDIR']))
CHECKS = []
print('Package-force evidence: ' + str(WORK), flush=True)


def check(name, expected, actual):
    ok = expected == actual
    CHECKS.append(dict(name=name, expected=expected, actual=actual, passed=ok))
    print(('PASS ' if ok else 'FAIL ') + name + ('' if ok else ' ' + repr((expected, actual))), flush=True)


def write(path, text, mode=0o644):
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(text)
    path.chmod(mode)


def read(path):
    return path.read_text() if path.is_file() else '<absent>'


def outer_state():
    result = {}
    for name in ('/var/lib/dpkg', '/var/lib/apt', '/var/log/apt', '/var/log/dpkg.log',
                 '/etc/apt', '/etc/systemd/system', '/etc/pve/lxc', '/opt/su-package-probe'):
        root = Path(name)
        paths = [root, *sorted(root.rglob('*'))] if root.is_dir() else [root]
        for path in paths:
            if not path.exists() and not path.is_symlink():
                result[str(path)] = None
                continue
            s = path.lstat()
            value = dict(device=s.st_dev, inode=s.st_ino, uid=s.st_uid, gid=s.st_gid,
                         mode=s.st_mode, links=s.st_nlink, size=s.st_size,
                         mtime_ns=s.st_mtime_ns, ctime_ns=s.st_ctime_ns)
            if stat.S_ISREG(s.st_mode):
                value['sha256'] = hashlib.sha256(path.read_bytes()).hexdigest()
            elif path.is_symlink():
                value['link'] = os.readlink(path)
            result[str(path)] = value
    return result


MODEL = r'''#!/usr/bin/python3
import json,os,pathlib,sys
data=pathlib.Path('/data');name=pathlib.Path(sys.argv[0]).name;a=sys.argv[1:]
with (data/'calls').open('a') as f:f.write(json.dumps(dict(tool=name,argv=a,frontend=os.environ.get('DEBIAN_FRONTEND'),offline=os.environ.get('SYSTEMD_OFFLINE')))+'\n')
fault=(data/'fault').read_text()
if name in ('apt','dpkg'):
 if name=='apt' and fault in ('apt','both'):sys.exit(42)
 if name=='dpkg' and '-i' in a and fault=='both':sys.exit(47)
 os.execv('/usr/bin/'+name,[name,*a])
if name=='getent':print('127.0.0.1 fixture.invalid');sys.exit(0)
if name!='curl':sys.exit(86)
url=next(v for v in reversed(a) if v.startswith('https://'))
out=a[a.index('-o')+1] if '-o' in a else None
api='/api/' in url or 'api.github.com' in url
if fault=='download' and not api:sys.exit(23)
if api:
 body=(data/'release.json').read_bytes()
 if fault=='producer':sys.exit(18)
else:
 body=(data/'package.deb').read_bytes()
if out:pathlib.Path(out).write_bytes(body)
else:sys.stdout.buffer.write(body)
if '-w' in a:print('200',end='')
'''

LAUNCH = r'''
set -euo pipefail
mount --bind /usr "$1/root/usr"
mount -o remount,bind,ro "$1/root/usr"
mount --bind "$1/bin" "$1/root/usr/local/bin"
mount -o remount,bind,ro "$1/root/usr/local/bin"
mount --bind /dev/null "$1/root/dev/null"
mount --bind /dev/urandom "$1/root/dev/urandom"
mount -t proc proc "$1/root/proc"
mount --bind "$2" "$1/root/source"
mount -o remount,bind,ro "$1/root/source"
mount --bind "$1" "$1/root/data"
shift 2
exec chroot "$CASE/root" /usr/bin/env -i PATH=/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin HOME=/root TMPDIR=/data/scratch LC_ALL=C PYTHONDONTWRITEBYTECODE=1 APT_CONFIG=/etc/apt/apt.conf "$@"
'''

DRIVER = r'''
set -euo pipefail
source /source/misc/core.func
source /source/misc/tools.func
load_functions
# These are only UI doubles, and must belong to the actual candidate API.
for name in msg_info msg_ok msg_warn msg_error; do declare -F "$name" >/dev/null || exit 86; done
msg_info() { :; }
msg_ok() { :; }
msg_warn() { :; }
msg_error() { printf '%s\n' "$*" >&2; }
export INSTALL_LOG=/data/helper.log
STD=''
[[ "$2" != quiet ]] || STD=silent
export FORCE_DEPLOY="$3" DPKG_FORCE_CONFOLD="$4" DPKG_FORCE_CONFNEW="$5"
case "$1" in
github) fetch_and_deploy_gh_release probe owner/probe binary "$6" /opt/unused 'probe_*.deb' '' /data/selected.json ;;
codeberg) fetch_and_deploy_codeberg_release probe owner/probe binary "$6" /opt/unused 'probe_*.deb' ;;
gitlab) fetch_and_deploy_gl_release probe owner/probe binary "$6" /opt/unused 'probe_*.deb' ;;
url) fetch_and_deploy_from_url "https://fixture.invalid/$6/probe_amd64.deb" '' ;;
esac
'''


def invoke(case, argv):
    number = len(list(case.glob('result-*.json')))
    result = subprocess.run(['unshare', '--mount', '--pid', '--fork', '--net', '--propagation', 'private',
                             '/bin/bash', '-c', LAUNCH, '_', str(case), str(SOURCE), *argv],
                            env=dict(os.environ, CASE=str(case)), capture_output=True, text=True, timeout=60)
    write(case / f'result-{number}.json', json.dumps(dict(argv=argv, status=result.returncode,
          stdout=result.stdout, stderr=result.stderr), indent=2))
    return result


def deploy(case, provider, force='0', std='verbose', old='1', new='0', version='v1.0'):
    return invoke(case, ['/bin/bash', '/data/driver', provider, std, force, old, new, version])


def calls(case, tool):
    return [json.loads(line) for line in read(case / 'calls').splitlines()
            if json.loads(line)['tool'] == tool]


def package(case, version='1.0'):
    stage = case / ('package-' + version)
    write(stage / 'DEBIAN/control', 'Package: su-package-probe\nVersion: ' + version +
          '\nArchitecture: amd64\nMaintainer: Fixture <fixture@example.invalid>\nDescription: private repair probe\n')
    write(stage / 'DEBIAN/conffiles', '/etc/su-package-probe.conf\n')
    write(stage / 'DEBIAN/postinst', '#!/bin/sh\nset -eu\n[ ! -e /data/postinst-fail ] || exit 31\n'
          'n=0\n[ ! -f /var/lib/su-package-probe/count ] || read -r n < /var/lib/su-package-probe/count\n'
          'mkdir -p /var/lib/su-package-probe\nprintf "%s\\n" "$((n + 1))" > /var/lib/su-package-probe/count\n', 0o755)
    write(stage / 'opt/su-package-probe/bin/probe', '#!/bin/sh\nprintf "native-' + version + '\\n"\n', 0o755)
    config_version = '1.0' if (case / 'provider').read_text() == 'url' else version
    write(stage / 'etc/su-package-probe.conf', 'vendor=' + config_version + '\n')
    result = subprocess.run(['/usr/bin/dpkg-deb', '--build', '--root-owner-group', str(stage), str(case / 'package.deb')],
                            capture_output=True, text=True, timeout=30)
    write(case / ('build-' + version + '.json'), json.dumps(dict(status=result.returncode, stdout=result.stdout, stderr=result.stderr)))
    if result.returncode:
        raise RuntimeError(result.stderr)
    url = 'https://fixture.invalid/v' + version + '/probe_amd64.deb'
    release = dict(tag_name='v' + version, draft=False, prerelease=False,
                   assets=[dict(name='probe_amd64.deb', browser_download_url=url)])
    if (case / 'provider').read_text() == 'gitlab':
        release['assets'] = dict(links=[dict(name='probe_amd64.deb', direct_asset_url=url)])
    write(case / 'release.json', json.dumps(release))
    return (stage / 'opt/su-package-probe/bin/probe').read_text()


def fixture(name, provider):
    case = WORK / name
    case.mkdir()
    root = case / 'root'
    for directory in ('usr/local/bin', 'dev', 'proc', 'source', 'data', 'root', 'opt', 'tmp',
                      'etc/alternatives', 'etc/apt/apt.conf.d', 'etc/apt/sources.list.d',
                      'var/lib/dpkg/updates', 'var/lib/apt/lists/partial', 'var/cache/apt/archives/partial', 'var/log/apt'):
        (root / directory).mkdir(parents=True, exist_ok=True)
    for name in ('bin', 'sbin', 'lib', 'lib64'):
        (root / name).symlink_to('usr/' + name)
    (root / 'etc/alternatives/awk').symlink_to('/usr/bin/mawk')
    for name in ('null', 'urandom'):
        (root / 'dev' / name).touch()
    for name, target in (('fd', '/proc/self/fd'), ('stdin', '/proc/self/fd/0'),
                         ('stdout', '/proc/self/fd/1'), ('stderr', '/proc/self/fd/2')):
        (root / 'dev' / name).symlink_to(target)
    (root / 'var/lib/dpkg/status').touch()
    write(root / 'etc/dpkg/dpkg.cfg', 'log /var/log/dpkg.log\n')
    write(root / 'etc/passwd', 'root:x:0:0:root:/root:/bin/bash\n')
    write(root / 'etc/group', 'root:x:0:\n')
    write(root / 'etc/apt/apt.conf', 'APT::Sandbox::User "root";\nDir::Cache::pkgcache "";\nDir::Cache::srcpkgcache "";\nDpkg::Use-Pty "false";\n')
    (case / 'bin').mkdir()
    (case / 'scratch').mkdir()
    for name in ('curl', 'getent', 'apt', 'dpkg'):
        write(case / 'bin' / name, MODEL, 0o755)
    write(case / 'driver', DRIVER)
    write(case / 'calls', '')
    write(case / 'fault', '')
    write(case / 'provider', provider)
    return case, package(case)


before = outer_state()
write(WORK / 'outer-before.json', json.dumps(before, sort_keys=True))
try:
    for provider in ('github', 'codeberg', 'gitlab', 'url'):
        case, expected = fixture(provider, provider)
        root = case / 'root'
        binary = root / 'opt/su-package-probe/bin/probe'
        counter = root / 'var/lib/su-package-probe/count'
        conffile = root / 'etc/su-package-probe.conf'
        marker = root / 'root/.probe'
        result = deploy(case, provider, force='1')
        check(provider + ' forced fresh native install', 0, result.returncode)
        check(provider + ' fresh executable bytes', expected, read(binary))
        check(provider + ' native postinst ran once', '1\n', read(counter))
        if not binary.is_file():
            raise RuntimeError(result.stdout + result.stderr)
        write(binary, 'damaged executable\n', 0o755)
        write(conffile, 'operator configuration\n')
        write(root / 'var/lib/su-package-probe/operator-data', 'operator data\n')
        preserved = (conffile.read_bytes(), conffile.stat().st_mtime_ns,
                     (root / 'var/lib/su-package-probe/operator-data').read_bytes())
        previous = len(calls(case, 'apt'))
        result = deploy(case, provider)
        check(provider + ' unforced adapter no-op', (0, 'damaged executable\n', '1\n', previous + int(provider == 'url')),
              (result.returncode, read(binary), read(counter), len(calls(case, 'apt'))))
        if provider != 'url':
            marker.unlink()
        result = deploy(case, provider)
        check(provider + ' unforced APT same-version no-op without marker', (0, 'damaged executable\n', '1\n'),
              (result.returncode, read(binary), read(counter)))
        check(provider + ' unforced APT has no reinstall', False, '--reinstall' in calls(case, 'apt')[-1]['argv'])
        options = ['-o', 'Dpkg::Options::=--force-confold']
        if provider == 'codeberg':
            options = ['-o', 'Dpkg::Options::=--force-confdef', *options]
        elif provider == 'url':
            options = []
        check(provider + ' unforced exact primary options', ['install', '-y', *options], calls(case, 'apt')[-1]['argv'][:-1])
        result = deploy(case, provider, force='1', std='quiet')
        check(provider + ' forced same-version adapter status', 0, result.returncode)
        check(provider + ' forced native unpack repairs installed bytes', expected, read(binary))
        check(provider + ' forced native postinst increments', '2\n', read(counter))
        check(provider + ' real dpkg records upgrade/unpack', 2, read(root / 'var/log/dpkg.log').count(' upgrade su-package-probe:amd64 ')
              + read(root / 'var/log/dpkg.log').count(' install su-package-probe:amd64 '))
        check(provider + ' repaired executable consumer', 'native-1.0\n',
              invoke(case, ['/opt/su-package-probe/bin/probe']).stdout)
        check(provider + ' real dpkg installed status/version', 'install ok installed 1.0\n',
              invoke(case, ['/usr/bin/dpkg-query', '-W', '-f=${Status} ${Version}\n', 'su-package-probe']).stdout)
        check(provider + ' selected package origin at download', 'https://fixture.invalid/v1.0/probe_amd64.deb',
              calls(case, 'curl')[-1]['argv'][-1])
        check(provider + ' operator config and data retained', preserved,
              (conffile.read_bytes(), conffile.stat().st_mtime_ns, (root / 'var/lib/su-package-probe/operator-data').read_bytes()))
        check(provider + ' selected release marker' if provider != 'url' else 'URL has no new marker',
              '1.0\n' if provider != 'url' else '<absent>', read(marker))
        check(provider + ' actual STD quiet log consumer', True, 'Setting up su-package-probe' in read(case / 'helper.log'))
        primary = calls(case, 'apt')[-1]
        check(provider + ' exact primary option vector', ['install', '-y', '--reinstall', *options], primary['argv'][:-1])
        check(provider + ' primary environment', (None, None) if provider == 'url' else ('noninteractive', '1'),
              (primary['frontend'], primary['offline']))
        write(case / 'fault', 'apt')
        result = deploy(case, provider, force='1')
        check(provider + ' primary fault actual dpkg fallback', (0, '3\n'), (result.returncode, read(counter)))
        fallback = [c for c in calls(case, 'dpkg') if '-i' in c['argv']][-1]
        check(provider + ' existing fallback vector', (['--force-confdef', '--force-confold'] if provider == 'codeberg' else []) + ['-i'], fallback['argv'][:-1])
        check(provider + ' fallback environment', ('noninteractive' if provider == 'codeberg' else None, None if provider == 'url' else '1'), (fallback['frontend'], fallback['offline']))
        for fault in (('both', 'download', 'postinst') if provider == 'url' else ('both', 'download', 'producer', 'postinst')):
            if provider != 'url':
                write(marker, 'prior-marker\n')
            oldcounter = read(counter)
            write(case / 'fault', fault)
            if fault == 'postinst':
                write(case / 'postinst-fail', 'fail native maintainer script\n')
            result = deploy(case, provider, force='1')
            wanted = (1 if provider == 'gitlab' else 100) if fault in ('both', 'postinst') else (1 if provider == 'gitlab' else 250) if fault == 'download' else {'github': 18, 'codeberg': 22, 'gitlab': 1}[provider]
            check(provider + '/' + fault + ' failure status', wanted, result.returncode)
            check(provider + '/' + fault + ' marker not published', 'prior-marker\n' if provider != 'url' else '<absent>', read(marker))
            check(provider + '/' + fault + ' no successful postinst', oldcounter, read(counter))
        (case / 'postinst-fail').unlink()
        write(case / 'fault', '')
        result = deploy(case, provider, force='1')
        check(provider + ' pending native package retry', (0, '4\n'), (result.returncode, read(counter)))
        for old, new in (('0', '0'), ('1', '0'), ('0', '1'), ('1', '1')):
            result = deploy(case, provider, force='1', old=old, new=new)
            wanted_options = []
            if provider == 'codeberg':
                wanted_options = ['-o', 'Dpkg::Options::=--force-confdef', '-o', 'Dpkg::Options::=--force-confold']
            elif provider != 'url' and (old == '1' or new == '1'):
                wanted_options = ['-o', 'Dpkg::Options::=--force-confnew' if new == '1' else 'Dpkg::Options::=--force-confold']
            check(provider + '/' + old + new + ' existing option precedence and transaction',
                  (0, ['install', '-y', '--reinstall', *wanted_options]),
                  (result.returncode, calls(case, 'apt')[-1]['argv'][:-1]))
        # A changed vendor conffile exercises real dpkg conffile policy, not strings.
        package(case, '2.0')
        result = deploy(case, provider, force='1', old='0', new='1', version='v2.0')
        check(provider + ' version2 actual native upgrade', 0, result.returncode)
        check(provider + ' caller conffile policy consumed', 'operator configuration\n' if provider in ('codeberg', 'url') else 'vendor=2.0\n', read(conffile))
        check(provider + ' selected version2 marker' if provider != 'url' else 'URL version2 has no marker',
              '2.0\n' if provider != 'url' else '<absent>', read(marker))
        check(provider + ' version2 executable consumer', 'native-2.0\n', invoke(case, ['/opt/su-package-probe/bin/probe']).stdout)
finally:
    after = outer_state()
    write(WORK / 'outer-after.json', json.dumps(after, sort_keys=True))
    check('outer package/config/log/service/CT metadata and bytes unchanged', before, after)
    write(WORK / 'checks.json', json.dumps(CHECKS, sort_keys=True, indent=2,
          default=lambda value: dict(bytes_hex=value.hex()) if isinstance(value, bytes) else str(value)))

failures = sum(not c['passed'] for c in CHECKS)
print(f'{len(CHECKS)} checks; {failures} failure(s); native private APT/dpkg, modeled forge/UI', flush=True)
raise SystemExit(bool(failures))
