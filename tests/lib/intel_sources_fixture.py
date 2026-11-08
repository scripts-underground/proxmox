"""Actual Intel provider and native APT source/target/resolver consumers, no installs."""
import email.utils
import hashlib
import json
import os
from pathlib import Path
import shlex
import shutil
import subprocess


PACKAGES = ('va-driver-all', 'vainfo', 'intel-gpu-tools', 'ocl-icd-libopencl1',
            'intel-opencl-icd', 'intel-media-va-driver-non-free')


def repository(root, suite, origin='Debian', omit_opencl=False):
    components = ('main', 'non-free', 'contrib', 'non-free-firmware') if origin.startswith('Debian') else ('main', 'restricted', 'universe', 'multiverse')
    hashes = []
    for component in components:
        rows = []
        for package in PACKAGES:
            if package == 'intel-opencl-icd' and omit_opencl:
                continue
            wanted = ('non-free' if package == 'intel-media-va-driver-non-free' else 'main') if origin.startswith('Debian') else (
                'multiverse' if package == 'intel-media-va-driver-non-free' else 'universe')
            if component == wanted:
                rows.append(f'Package: {package}\nVersion: 99:1\nArchitecture: amd64\n'
                            f'Filename: pool/fixture/{package}.deb\nSize: 1\n'
                            f'SHA256: {hashlib.sha256(b"x").hexdigest()}\nDescription: source consumer fixture\n\n')
        for tail, raw in [('binary-amd64/Packages', ''.join(rows).encode()), ('source/Sources', b'')]:
            path = root / 'dists' / suite / component / tail
            path.parent.mkdir(parents=True, exist_ok=True)
            path.write_bytes(raw)
            hashes.append(f' {hashlib.sha256(raw).hexdigest()} {len(raw)} {component}/{tail}\n')
    release = (f'Origin: {origin}\nLabel: {origin}\nSuite: {suite}\nCodename: {suite}\n'
               f'Date: {email.utils.formatdate(usegmt=True)}\nArchitectures: amd64\n'
               'Components: ' + ' '.join(components) + '\nSHA256:\n' + ''.join(hashes))
    (root / 'dists' / suite / 'Release').write_text(release)
    return root.as_uri()


def apt_config(root):
    for name in ('lists/partial', 'cache/archives/partial', 'conf'):
        (root / name).mkdir(parents=True, exist_ok=True)
    (root / 'status').write_text('')
    path = root / 'apt.conf'
    path.write_text('Dir::State::lists "' + str(root / 'lists') + '";\n'
                    'Dir::State::status "' + str(root / 'status') + '";\n'
                    'Dir::Cache "' + str(root / 'cache') + '";\n'
                    'Dir::Cache::pkgcache "";\nDir::Cache::srcpkgcache "";\n'
                    'Dir::Etc::parts "' + str(root / 'conf') + '";\n'
                    'Dir::Etc::main "' + str(root / 'empty.conf') + '";\n'
                    'APT::Sandbox::User "root";\nAcquire::Languages "none";\n')
    return path


def prepare_intel_apt(work, apt):
    """A native local archive is the lower-level CT source/cache model."""
    root = work / 'baseline-native-apt'
    root.mkdir()
    uri = repository(root / 'repository', 'trixie')
    (apt / 'sources.list').write_text(f'deb [trusted=yes] {uri} trixie main non-free\n')
    config = apt_config(root)
    os.environ['APT_CONFIG'] = str(config)
    subprocess.run(['/usr/bin/apt-get', 'update', '-qq', '-o', 'APT::Update::Error-Mode=any'],
                   capture_output=True, check=True, timeout=30,
                   env=dict(os.environ, TMPDIR=os.environ['TMPDIR']))


def exercise_intel_sources(source, work, run, check, base, sections):
    quote = lambda value: shlex.quote(str(value))
    root = work / 'intel-source-cases'
    root.mkdir()
    original_config = os.environ['APT_CONFIG']
    cases = [
        ('deb822-only', 'trixie', 'Debian', 'deb822', 0),
        ('bookworm-legacy', 'bookworm', 'Debian', 'legacy', 0),
        ('trixie-legacy-comment', 'trixie', 'Debian', 'legacy-comment', 0),
        ('trixie-firmware-not-nonfree', 'trixie', 'Debian', 'firmware', 0),
        ('ubuntu-deb822', 'noble', 'Ubuntu', 'deb822', 0),
        ('ubuntu-legacy-options', 'jammy', 'Ubuntu', 'legacy-options', 0),
        ('deb822-disabled-folded', 'trixie', 'Debian', 'folded', 0),
        ('already-configured', 'trixie', 'Debian', 'complete', 0),
        ('installed-only-is-not-source-support', 'trixie', 'Debian', 'installed-only', 0),
        ('operator-owned-fragment', 'trixie', 'Debian', 'custom', 0),
        ('unreadable-source', 'trixie', 'Debian', 'unreadable', None),
        ('malformed-source', 'trixie', 'Debian', 'malformed', 100),
        ('source-concurrent-edit', 'trixie', 'Debian', 'concurrent', None),
        ('native-trixie-opencl-unavailable', 'trixie', 'Debian', 'unavailable', 100),
    ]
    for name, suite, origin, kind, status in cases:
        case = root / name
        apt = case / 'apt'
        (apt / 'sources.list.d').mkdir(parents=True)
        uri = repository(case / 'repository', suite, origin, omit_opencl=kind == 'unavailable')
        config = apt_config(case)
        if kind == 'installed-only':
            (case / 'status').write_text('Package: intel-media-va-driver-non-free\nStatus: install ok installed\n'
                                       'Version: 99:1\nArchitecture: amd64\nDescription: installed-only control\n\n')
        component = 'main non-free' if kind == 'complete' else 'main non-free-firmware' if kind == 'firmware' else 'main'
        path = apt / 'sources.list.d/operator.sources'
        disabled = ''
        if kind.startswith('legacy') or kind == 'firmware':
            path = apt / 'sources.list'
            option = 'trusted=yes arch=amd64'
            if kind == 'legacy-options':
                key = case / 'archive#fixture.gpg'
                shutil.copyfile('/usr/share/keyrings/debian-archive-keyring.gpg', key)
                option += ' signed-by=' + str(key)
            text = f'# operator {name}\ndeb [{option}] {uri} {suite} {component}'
            text += ' # non-free comment is not a component\n' if kind == 'legacy-comment' else ' # retain options\n'
        else:
            text = (f'# operator {name}\nTypes: deb deb-src\nURIs: {uri}\nSuites: {suite}\n'
                    f'Components: {component}\nTrusted: yes\nArchitectures: amd64\n'
                    'Signed-By: /usr/share/keyrings/debian-archive-keyring.gpg\nX-User-Note: retain non-free text\n')
            if kind == 'folded':
                disabled = f'Types: deb\nURIs: {uri}\nSuites: disabled\nComponents: main\nEnabled: no\n\n# comment-only paragraph\n\n'
                text = disabled + text.replace('Components: main\n', 'Components:\n main\n \n')
            if kind == 'malformed':
                text = text.replace(f'Suites: {suite}\n', '')
        path.write_text(text)
        path.chmod(0o640)
        os.setxattr(path, 'user.fixture', b'operator ownership')
        if kind == 'custom':
            os.chown(path, 1234, 1234)
            other = repository(case / 'operator-repository', suite, 'Operator Archive')
            (apt / 'sources.list.d/non-free.list').write_text(f'# operator owns this filename\ndeb [trusted=yes] {other} {suite} main\n')
        originals = {str(p.relative_to(apt)): p.read_bytes() for p in apt.rglob('*') if p.is_file()}
        subprocess.run(['mount', '--bind', str(apt), '/etc/apt'], check=True, timeout=10)
        try:
            env = dict(os.environ, APT_CONFIG=str(config), TMPDIR=os.environ['TMPDIR'], LC_ALL='C')
            native = subprocess.run(['/usr/bin/apt-get', '--print-uris', 'update'], capture_output=True, text=True, env=env, timeout=20)
            check(name + ' native input admission', 100 if kind == 'malformed' else 0, native.returncode)
            if native.returncode == 0:
                subprocess.run(['/usr/bin/apt-get', 'update', '-qq', '-o', 'APT::Update::Error-Mode=any'],
                               capture_output=True, check=True, env=env, timeout=30)
            if kind == 'unreadable':
                path.chmod(0)
            settings = f'APT_CONFIG={quote(config)} GPU_TEST_ROOT={quote(work / "provider-models")} GPU_TEST_INSTALL_SIMULATE=1 GPU_TEST_REFRESH_INDEX=1'
            if kind == 'concurrent':
                settings += ' GPU_TEST_SOURCE_EDIT=' + quote('/etc/apt/' + str(path.relative_to(apt)))
            code = (f'export {settings} PATH={quote(work / "provider-models/bin")}:"$PATH"\n'
                    f'source {quote(source / "tools/pve/gpu-intel.func")}\n'
                    f'source {quote(work / "provider-models/transport.func")}\n')
            if kind == 'unreadable':
                # Execute the real provider without DAC override, not a failing stub.
                body = code + '\nif install_intel_tools_in_ct 987654; then exit 0; else exit $?; fi'
                code = '/usr/bin/setpriv --bounding-set=-dac_override,-dac_read_search /bin/bash -c ' + quote(body)
            else:
                code += 'install_intel_tools_in_ct 987654'
            facts = run('intel-source-' + name, code)
            check(name + ' actual provider status', True if status is None else status,
                  facts['status'] != 0 if status is None else facts['status'])
            if facts['status']:
                check(name + ' no false Installed claim', False, 'Installed Intel' in facts['stdout'])
            if kind in ('unreadable', 'malformed'):
                check(name + ' refused source bytes retained', text.encode().hex(), path.read_bytes().hex())
                if kind == 'unreadable':
                    check(name + ' genuine source path diagnosed', True, 'operator.sources' in facts['stderr'])
            elif kind == 'concurrent':
                check(name + ' concurrent operator edit retained', text + '# concurrent operator edit\n', path.read_text())
            else:
                consumer = subprocess.run(['/usr/bin/apt-get', '--print-uris', 'update'], capture_output=True, text=True, env=env, timeout=20)
                check(name + ' native output admission', 0, consumer.returncode)
                wanted = ('non-free',) if origin == 'Debian' else ('universe', 'multiverse')
                for part in wanted:
                    check(name + ' native consumer requests ' + part, True, f'/{suite}/{part}/' in consumer.stdout)
                check(name + ' no fabricated foreign suite', False, 'bookworm' in consumer.stdout if suite != 'bookworm' else False)
                check(name + ' no foreign source file injection', sorted(originals),
                       sorted(str(p.relative_to(apt)) for p in apt.rglob('*') if p.is_file()
                              and not any(part.startswith('.gpu-intel-recovery.') for part in p.relative_to(apt).parts)))
                check(name + ' source mode retained', 0o640, path.stat().st_mode & 0o777)
                check(name + ' source xattr retained', b'operator ownership'.hex(), os.getxattr(path, 'user.fixture').hex())
                if disabled:
                    check(name + ' disabled/comment stanza retained', True, path.read_text().startswith(disabled))
                if kind == 'complete':
                    check(name + ' sufficient sources stay byte-identical', text, path.read_text())
                if kind == 'custom':
                    check(name + ' operator uid/gid retained', (1234, 1234), (path.stat().st_uid, path.stat().st_gid))
                    check(name + ' operator fragment stays byte-identical', originals['sources.list.d/non-free.list'].hex(),
                          (apt / 'sources.list.d/non-free.list').read_bytes().hex())
                subprocess.run(['/usr/bin/apt-get', 'update', '-qq', '-o', 'APT::Update::Error-Mode=any'],
                               capture_output=True, check=True, env=env, timeout=30)
                policy = subprocess.run(['/usr/bin/apt-cache', 'policy', 'intel-media-va-driver-non-free'],
                                        capture_output=True, text=True, check=True, env=env, timeout=10)
                check(name + ' native candidate consumer sees media package', True, 'Candidate: 99:1' in policy.stdout)
            (case / 'facts.json').write_text(json.dumps(facts, indent=2))
        finally:
            path.chmod(0o640)
            subprocess.run(['mount', '--bind', str(work / 'apt'), '/etc/apt'], check=True, timeout=10)
            os.environ['APT_CONFIG'] = original_config
    from intel_publication_fixture import exercise_intel_publication
    exercise_intel_publication(source, work, run, check)
