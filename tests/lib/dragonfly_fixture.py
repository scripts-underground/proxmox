"""Actual cold bundles/release helpers with explicit package/systemd models."""
import hashlib
import json
import os
from pathlib import Path
import re
import shlex
import subprocess
import sys
import tempfile

ROOT = Path(sys.argv[1])
WORK = Path(tempfile.mkdtemp(prefix='dragonfly-fixture.', dir=os.environ['TMPDIR']))
print('DRAGONFLY_FIXTURE_EVIDENCE ' + str(WORK), flush=True)
checks = []


def check(name, expected, actual):
    ok = expected == actual
    checks.append(dict(name=name, expected=expected, actual=actual, passed=ok))
    print(('PASS ' if ok else 'FAIL ') + name + ('' if ok else repr((expected, actual))), flush=True)


def write(path, text, mode=0o644):
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(text)
    path.chmod(mode)


MODELS = r'''
header_info() { :; }
check_container_storage() { :; }
check_container_resources() { :; }
cleanup_lxc() { :; }
stop_spinner() { :; }
msg_info() { :; }
msg_ok() { :; }
msg_warn() { :; }
msg_error() { printf '%s\n' "$*" >&2; }
ensure_dependencies() { :; }
getent() { return 0; }
dpkg() { [[ "$1" == --print-architecture ]] && printf '%s\n' "$TEST_ARCH"; }
chown() { printf '%s\n' "$*" >> "$CASE_ROOT/chown-calls"; }
install() {
  printf '%s\n' "$*" >> "$CASE_ROOT/install-calls"
  local args=()
  while (($#)); do case "$1" in -o|-g) shift 2 ;; *) args+=("$1"); shift ;; esac; done
  command install "${args[@]}"
}
mv() {
  if [[ "$FAULT" == publish && "${!#}" == */scripts-underground-runtime.env ]]; then return 43; fi
  command mv "$@"
}
systemctl() {
  if [[ "$1" == --version ]]; then printf 'systemd %s (fixture)\n' "$SYSTEMD_VERSION"; return; fi
  printf '%s\n' "$*" >> "$CASE_ROOT/services"
  if [[ "$1" == start || " $* " == *' --now '* ]]; then
    # Systemd is modeled; parse the actual emitted gate, not an auxiliary sentinel.
    local dropin="$CASE_ROOT/etc/systemd/system/dragonfly.service.d/scripts-underground.conf"
    local runtime="$CASE_ROOT/etc/dragonfly/scripts-underground-runtime.env"
    if grep -Fxq "ConditionPathExists=$runtime" "$dropin" && [[ ! -f "$runtime" ]]; then
      printf skipped-unprepared >> "$CASE_ROOT/start-observations"
      return
    fi
    grep -Fxq "EnvironmentFile=$runtime" "$dropin" && test -f "$runtime" || return 68
    grep -qE '^--requirepass=.+$' "$CASE_ROOT/etc/dragonfly/dragonfly.conf" || return 69
    test -d "$CASE_ROOT/var/lib/dragonfly/tmp" || return 70
    printf authenticated-ready >> "$CASE_ROOT/start-observations"
  fi
}
curl() { python3 -B "$CASE_ROOT/http.py" "$@"; }
curl_download() { printf '%s\n' "$2" >> "$CASE_ROOT/downloads"; printf package-model > "$1"; }
apt() {
  printf '%s\n' "$*" >> "$CASE_ROOT/packages"
  local arg
  for arg in "$@"; do
    [[ "$arg" == *.deb ]] || continue
    if [[ "$FAULT" == package ]]; then return 42; fi
    if [[ ! -f "$CASE_ROOT/etc/dragonfly/dragonfly.conf" || " $* " != *' Dpkg::Options::=--force-confold '* ]]; then
      printf '%s\n' '--dir=/var/lib/dragonfly' '--log_dir=/var/log/dragonfly' > "$CASE_ROOT/etc/dragonfly/dragonfly.conf"
      chmod 0640 "$CASE_ROOT/etc/dragonfly/dragonfly.conf"
    fi
    command cp "$CASE_ROOT/dragonfly-cli.py" "$CASE_ROOT/usr/bin/dragonfly"
    chmod 0755 "$CASE_ROOT/usr/bin/dragonfly"
    systemctl start dragonfly
  done
}
export PATH="$CASE_ROOT/bin:$PATH"
'''
HTTP = r'''
import json,pathlib,sys
a=sys.argv[1:];out=a[a.index('-o')+1];url=next(v for v in a if v.startswith('https://'))
assets=[dict(browser_download_url='https://fixture.invalid/dragonfly_'+arch+'.deb') for arch in ('arm64','amd64')]
pathlib.Path(out).write_text(json.dumps(dict(tag_name='v2.1',draft=False,prerelease=False,assets=assets)))
if '-w' in a:print('200',end='')
'''
OPENSSL = r'''#!/usr/bin/env bash
set -euo pipefail
printf '%s\n' "$*" >> "$CASE_ROOT/password-calls"
case "$FAULT" in
  password-failure) printf 'controlled OpenSSL failure\n' >&2; exit 47 ;;
  password-partial-failure) printf abcd; printf 'controlled partial failure\n' >&2; exit 48 ;;
  password-empty) exit 0 ;;
  password-short) printf 'abcd\n'; exit 0 ;;
  password-diagnostic) printf 'diagnostic output\n%064d\n' 0; exit 0 ;;
  password-uppercase) printf '%064s\n' '' | tr ' ' A; exit 0 ;;
  password-long) printf '%065d\n' 0; exit 0 ;;
esac
exec /usr/bin/openssl "$@"
'''
CLI = r'''#!/usr/bin/python3
import json,os,pathlib,sys
c=pathlib.Path(os.environ['CASE_ROOT']);fault=os.environ['FAULT']
with (c/'cli-calls').open('a') as out:out.write(json.dumps(sys.argv[1:])+'\n')
if sys.argv[1:]!=['--helpfull']:print('Unmodeled CLI mode',file=sys.stderr);raise SystemExit(49)
data=json.loads((c/'capabilities.json').read_text());flags=data['flags']
if fault=='help-failure':print('Controlled static help failure',file=sys.stderr);raise SystemExit(49)
if fault=='help-empty':raise SystemExit(1)
if fault=='help-error':print('ERROR: unknown help mode');raise SystemExit(1)
if fault=='help-missing':flags=[name for name in flags if name!='requirepass']
if fault=='help-partial':flags=['pidfile']
if fault=='help-no-flags':flags=[]
if fault=='help-duplicate':flags=flags+['port']
print('dragonfly: a modern in-memory store.\n\nUsage: dragonfly [FLAGS]\n\n  Flags from captured v2.1 inventory:')
for name in flags:print('    --'+name+' (captured published capability);')
raise SystemExit(0 if fault=='help-zero' else data['help_status'])
'''

capabilities = json.loads((ROOT / 'tests/assets/dragonfly-v2.1-capabilities.json').read_text())
flags = capabilities['flags']
check('package model retains captured amd64 ELF association', 'ea5b802370c8f9ba342dd2829fec9e30f59932b382facd31cd5ff49bd912574b', capabilities['elf_sha256'])
check('package model uses all 274 actual captured flags', (274, capabilities['flags_sha256']), (len(flags), hashlib.sha256(json.dumps(flags, indent=2).encode()).hexdigest()))
assert flags == sorted(set(flags)) and capabilities['help_status'] == 1
check('unlinked prototype is absent from the actual capability model', False, 'disk_backpressure_folder' in flags or 'disk_backpressure_file_max_bytes' in flags)

# Framework doubles must be actual candidate APIs. Command models are explicitly
# distinguished, so a new foreign helper cannot masquerade as local framework.
external_doubles = {'getent', 'dpkg', 'chown', 'install', 'mv', 'systemctl', 'curl', 'curl_download', 'apt'}
definition = r'(?m)^\s*(?:function\s+)?([A-Za-z_][\w-]*)\s*\(\)\s*\{'
declared = set(re.findall(definition, MODELS))
framework = '\n'.join((ROOT / 'misc' / name).read_text() for name in ('core.func', 'error_handler.func', 'install.func', 'tools.func', 'github.func'))
available = set(re.findall(definition, framework))
# curl_download is a real framework boundary, unlike the external curl command.
external_doubles.remove('curl_download')
missing = sorted(declared - external_doubles - available)
check('every fixture framework double exists in candidate framework', [], missing)
assert not missing, missing
check('foreign upstream helper is rejected by framework-double admission', ['random_password'], sorted((declared | {'random_password'}) - external_doubles - available))
(WORK / 'framework-double-surface.json').write_text(json.dumps(dict(framework_doubles=sorted(declared-external_doubles), external_command_models=sorted(declared & external_doubles), available_framework=sorted(available), openssl=dict(path='/usr/bin/openssl', sha256=hashlib.sha256(Path('/usr/bin/openssl').read_bytes()).hexdigest())), sort_keys=True, indent=2))


for arch in ('amd64', 'arm64'):
    c = WORK / arch
    for name in ('tmp', 'home', 'stage', 'bin', 'usr/bin', 'var/lib/dragonfly'):
        (c / name).mkdir(parents=True)
    text = (ROOT / 'scripts/lxc/dragonfly.sh').read_text()
    hooks = []
    for role in ('install', 'update'):
        start = text.index('function ' + role + '_script() {')
        end = text.index('\n}\n', start) + 3
        hook = text[start:end]
        for prefix in ('/etc', '/var/lib/dragonfly', '/usr/bin/dragonfly'):
            hook = hook.replace(prefix, str(c) + prefix)
        hooks.append(hook)
    write(c / 'hooks.sh', '\n'.join(hooks))
    write(c / 'models.sh', MODELS)
    write(c / 'bin/openssl', OPENSSL, 0o755)
    write(c / 'dragonfly-cli.py', CLI, 0o755)
    write(c / 'capabilities.json', json.dumps(capabilities, sort_keys=True))
    write(c / 'http.py', HTTP)
    for name in ('core.func', 'error_handler.func', 'tools.func'):
        raw = (ROOT / 'misc' / name).read_text()
        if name == 'core.func':
            raw = raw.replace('/var/lib/scripts-underground/update-pending', str(c / 'pending')).replace('/var/lib/scripts-underground/maintenance-locks', str(c / 'locks'))
        write(c / 'stage' / name, raw)
    write(c / 'stage/install.func', 'pkg_install() { :; }\nsetup_lxc() { :; }\n')
    write(c / 'stage/github.func', 'clone_and_deploy_gh_commit() { :; }\nsource ' + shlex.quote(str(c / 'models.sh')) + '\n')
    compose = 'source ' + shlex.quote(str(ROOT / 'misc/bundle.func')) + '\nsource ' + shlex.quote(str(c / 'hooks.sh')) + '\n'
    compose += 'export APP=Dragonfly NSAPP=dragonfly REPO_BASE=https://fixture.invalid var_lxc_tmpdir=' + shlex.quote(str(c / 'tmp')) + '\n'
    for role, pipeline in (('install', 'install_script'), ('update', 'run_update_script "$@"')):
        compose += '_write_bundle ' + role + ' ' + role + '_script ' + shlex.quote(str(c / 'stage')) + ' ' + shlex.quote(pipeline) + ' > ' + shlex.quote(str(c / (role + '-master.sh'))) + '\n'
    subprocess.run(['/bin/bash', '-ceu', compose], check=True, timeout=30, capture_output=True)
    env = dict(os.environ, CASE_ROOT=str(c), TEST_ARCH=arch, STD='', HOME=str(c / 'home'), FAULT='', SYSTEMD_VERSION='257')

    def run(label, role='install', args=(), **overrides):
        target = c / (label + '.sh')
        target.write_bytes((c / (role + '-master.sh')).read_bytes())
        result = subprocess.run(['/bin/bash', str(target), *args], env=dict(env, **overrides), capture_output=True, text=True, timeout=70)
        write(c / (label + '.stdout'), result.stdout)
        write(c / (label + '.stderr'), result.stderr)
        write(c / (label + '.status'), str(result.returncode))
        return result.returncode

    check(arch + ' unsupported systemd refuses before package', 65, run('old-systemd', SYSTEMD_VERSION='256'))
    check(arch + ' old systemd has no package effects', False, (c / 'packages').exists())
    config = c / 'etc/dragonfly/dragonfly.conf'
    runtime = c / 'etc/dragonfly/scripts-underground-runtime.env'
    write(config, '--dir=/var/lib/dragonfly\n--log_dir=/var/log/dragonfly\n', 0o640)
    write(c / 'var/lib/dragonfly/operator-data', 'private data bytes', 0o600)
    initial = config.read_bytes()
    negative_producers = [('password-failure', 47), ('password-partial-failure', 48), ('password-empty', 65), ('password-short', 65), ('password-diagnostic', 65), ('password-uppercase', 65), ('password-long', 65)]
    for fault, status in negative_producers:
        check(arch + ' ' + fault + ' retains exact refusal status', status, run(fault, FAULT=fault))
        check(arch + ' ' + fault + ' cannot append credentials or diagnostics', initial, config.read_bytes())
        check(arch + ' ' + fault + ' cannot publish runtime configuration', False, runtime.exists())
        check(arch + ' ' + fault + ' retains operator data', b'private data bytes', (c / 'var/lib/dragonfly/operator-data').read_bytes())
    check(arch + ' partial preparation failure retains status', 43, run('partial', FAULT='publish'))
    dropin = c / 'etc/systemd/system/dragonfly.service.d/scripts-underground.conf'
    check(arch + ' package autostart skipped before auth/config readiness', 'skipped-unprepared', (c / 'start-observations').read_text())
    check(arch + ' incomplete runtime input remains absent', False, runtime.exists())
    password = next(v for v in config.read_text().splitlines() if v.startswith('--requirepass='))
    check(arch + ' real native OpenSSL produced exactly 64 lowercase hex bytes', True, re.fullmatch(r'--requirepass=[0-9a-f]{64}', password) is not None)
    data = (c / 'var/lib/dragonfly/operator-data').read_bytes()
    prepared = config.read_bytes()
    for fault, status in [('help-failure', 49), ('help-empty', 65), ('help-error', 65), ('help-zero', 65), ('help-partial', 65), ('help-no-flags', 65), ('help-duplicate', 65), ('help-missing', 65)]:
        check(arch + ' ' + fault + ' refuses preparation', status, run(fault, FAULT=fault))
        check(arch + ' ' + fault + ' retains config and password', prepared, config.read_bytes())
        check(arch + ' ' + fault + ' cannot release runtime gate', False, runtime.exists())
        check(arch + ' ' + fault + ' retains operator data', data, (c / 'var/lib/dragonfly/operator-data').read_bytes())
    secret = 'controlled-private-value-do-not-log'
    for label, line in [('unknown-config', '--not_a_published_flag=' + secret), ('prototype-config', '--disk_backpressure_folder=' + secret), ('malformed-config', 'not a flag ' + secret)]:
        config.write_bytes(prepared + (line + '\n').encode())
        before_rejection = config.read_bytes()
        check(arch + ' ' + label + ' stops before eligibility', 65, run(label))
        check(arch + ' ' + label + ' preserves original bytes', before_rejection, config.read_bytes())
        check(arch + ' ' + label + ' keeps runtime gate closed', False, runtime.exists())
        logs = (c / (label + '.stdout')).read_text() + (c / (label + '.stderr')).read_text()
        check(arch + ' ' + label + ' does not log private values', False, secret in logs or password.split('=', 1)[1] in logs)
        config.write_bytes(prepared)
    check(arch + ' capability stages are removed after refusal', [], list((c / 'tmp').glob('dragonfly-capabilities.*')))
    config.write_bytes(prepared + b'--cache_mode=true\n')
    check(arch + ' cold retry finishes', 0, run('retry'))
    check(arch + ' retry retains exactly one password', [password], [v for v in config.read_text().splitlines() if v.startswith('--requirepass=')])
    check(arch + ' retry does not generate another password', len(negative_producers) + 1, len((c / 'password-calls').read_text().splitlines()))
    check(arch + ' password executable receives only documented native args', {'rand -hex 32'}, set((c / 'password-calls').read_text().splitlines()))
    check(arch + ' retry retains data', data, (c / 'var/lib/dragonfly/operator-data').read_bytes())
    check(arch + ' only linked package capabilities enter config', False, '--disk_backpressure_folder=' in config.read_text())
    check(arch + ' no unused prototype directory is provisioned', False, (c / 'var/lib/dragonfly/backpressure').exists())
    check(arch + ' supported operator capability stays configured', True, '--cache_mode=true\n' in config.read_text())
    check(arch + ' actual static help mode is the only capability invocation', {('--helpfull',)}, {tuple(json.loads(line)) for line in (c / 'cli-calls').read_text().splitlines()})
    check(arch + ' private TMPDIR path is disk-backed runtime configuration', 'TMPDIR=' + str(c) + '/var/lib/dragonfly/tmp\n', runtime.read_text())
    check(arch + ' runtime env mode', 0o640, runtime.stat().st_mode & 0o777)
    check(arch + ' native directory creation asks for dfly/private mode', True, '-o dfly -g dfly -m 0700' in (c / 'install-calls').read_text())
    check(arch + ' private isolation retained', True, 'PrivateTmp=disconnected\nReadOnlyPaths=/tmp /var/tmp\n' in dropin.read_text())
    check(arch + ' asset selection uses requested architecture', {'https://fixture.invalid/dragonfly_' + arch + '.deb'}, set((c / 'downloads').read_text().splitlines()))
    operator = c / 'etc/systemd/system/dragonfly.service.d/operator.conf'
    write(operator, '[Service]\nRestartSec=7\n', 0o640)
    config.write_text(config.read_text() + '# operator configuration\n')
    protected = [config, runtime, dropin, operator, c / 'var/lib/dragonfly/operator-data']

    def facts():
        return {str(p): (hashlib.sha256(p.read_bytes()).hexdigest(), p.stat().st_mode & 0o777, p.stat().st_uid, p.stat().st_gid) for p in protected}

    before = facts()
    downloads = (c / 'downloads').read_text()
    check(arch + ' cold same-version update succeeds', 0, run('noop', 'update'))
    check(arch + ' normal current version does not deploy', downloads, (c / 'downloads').read_text())
    check(arch + ' current update preserves all protected files', before, facts())
    check(arch + ' cold forced same-version reinstall succeeds', 0, run('forced', 'update', ('--clean',)))
    check(arch + ' forced reinstall actually deploys', 2, len((c / 'downloads').read_text().splitlines()))
    check(arch + ' forced reinstall preserves config/data/dropins/metadata', before, facts())
    check(arch + ' all package invocations use confold', True, all('Dpkg::Options::=--force-confold' in v for v in (c / 'packages').read_text().splitlines() if '.deb' in v))
    check(arch + ' package helper reports exhausted install failure', 100, run('package-fail', 'update', ('--clean',), FAULT='package'))
    check(arch + ' failed update retains pending', True, (c / 'pending/dragonfly').exists())
    check(arch + ' failed update retains protected files', before, facts())
    check(arch + ' pending retry succeeds', 0, run('pending-retry', 'update'))
    check(arch + ' pending retry clears pending', False, (c / 'pending/dragonfly').exists())
    check(arch + ' pending retry preserves files', before, facts())
    dropin.write_text('[Service]\nPrivateTmp=no\n')
    check(arch + ' own drop-in collision diagnosed', 65, run('collision'))
    check(arch + ' collision not overwritten', '[Service]\nPrivateTmp=no\n', dropin.read_text())

def evidence_value(value):
    if isinstance(value, bytes):
        return dict(bytes_hex=value.hex())
    if isinstance(value, set):
        return sorted(value)
    raise TypeError(type(value).__name__)


(WORK / 'checks.json').write_text(json.dumps(checks, sort_keys=True, indent=2, default=evidence_value))
failed = sum(not row['passed'] for row in checks)
print(f'{len(checks)} checks; {failed} failure(s); actual cold bundles/files/release helper; package/HTTP/systemd modeled', flush=True)
raise SystemExit(bool(failed))
