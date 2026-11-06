"""Actual updater producers, data-only detector and recorded batch preparation."""
import json
import os
from pathlib import Path
import re
import shlex
import subprocess
import sys
import tempfile

S = Path(sys.argv[1])
W = Path(tempfile.mkdtemp(prefix='batch-metadata.', dir=os.environ['TMPDIR']))
print('Batch metadata evidence: ' + str(W), flush=True)
checks = []
q = lambda value: shlex.quote(str(value))


def check(name, expected, actual):
    ok = expected == actual
    checks.append(dict(name=name, expected=expected, actual=actual, passed=ok))
    print(('PASS ' if ok else 'FAIL ') + name, flush=True)


def run(name, code, cwd=None):
    r = subprocess.run(['/bin/bash', '-c', code], cwd=cwd or W,
                       env=dict(PATH='/usr/bin:/bin', HOME=str(W), TMPDIR=str(W)),
                       capture_output=True, timeout=25)
    (W / (name + '.json')).write_text(json.dumps(dict(code=code, status=r.returncode,
        stdout_hex=r.stdout.hex(), stderr_hex=r.stderr.hex()), sort_keys=True))
    return r


stage = W / 'framework'
stage.mkdir()
for name in ('core', 'error_handler'):
    (stage / (name + '.func')).write_bytes((S / ('misc/' + name + '.func')).read_bytes())
for name, body in [('install', 'setup_lxc() { :; }'), ('tools', 'setup_uv() { :; }'),
                   ('github', 'clone_and_deploy_gh_commit() { :; }')]:
    (stage / (name + '.func')).write_text(body + '\n')
app = (S / 'scripts/lxc/changedetection.sh').read_text()
declarations = app[:app.index('function install_script() {')]
bundle = W / 'current-update'
sentinel = W / 'must-not-execute'
code = f'''set -euo pipefail
source {q(S / 'misc/bundle.func')}
{declarations}
NSAPP=${{APP,,}}; NSAPP=${{NSAPP// /}}
var_lxc_tmpdir={q(W)}
update_script() {{ printf executed > {q(sentinel)}; }}
_write_bundle update update_script {q(stage)} 'run_update_script "$@"' > {q(bundle)}
'''
r = run('producer', code)
check('actual current producer succeeds', 0, r.returncode)
historical = subprocess.run(['git', '-C', str(S), 'show', 'd32ca36:misc/install.func'],
                            capture_output=True, check=True, text=True, timeout=20).stdout
producer, = [line for line in historical.splitlines() if line.startswith('  echo "bash -c') and '>/usr/bin/update' in line]
legacy = W / 'legacy-update'
r = run('legacy-producer', 'update_script_name=changedetection\n' + producer.replace('>/usr/bin/update', '> ' + q(legacy)))
check('actual historical thin-wrapper producer succeeds', 0, r.returncode)
text = (S / 'scripts/pve/update-apps.sh').read_text()
detector = re.search(r'(?ms)^function detect_service\(\) \{\n.*?^\}', text).group()
resource = re.search(r'(?ms)^function prepare_batch_resources\(\) \{\n.*?^\}', text)
resource = resource.group() if resource else ''
original = bundle.read_text()
baked = 'declare -- NSAPP=changedetection\n'
assert original.count(baked) == 1
cases = [('current', bundle, 0, 'changedetection', ''), ('legacy', legacy, 0, 'changedetection', ''),
         ('pull-failed', legacy, 47, '', 'pull_status=47'), ('read-failed', legacy, 43, '', 'cat() { return 43; }')]
for name, content, status, identity in [
    ('invalid', original.replace(baked, 'declare -- NSAPP=../bad\n'), 65, ''),
    ('quoted', original.replace(baked, 'declare -- NSAPP="changedetection"\n'), 65, ''),
    ('duplicate', original.replace(baked, baked + baked), 65, ''),
    ('empty', original.replace(baked, 'declare -- NSAPP=\n'), 65, ''),
    ('malicious-id', original.replace(baked, 'declare -- NSAPP=$(touch ' + str(sentinel) + ')\n'), 65, ''),
    ('inert-body', original + '\ntouch ' + str(sentinel) + '\n', 0, 'changedetection'),
    ('unknown-body', 'touch ' + str(sentinel) + '\n' + legacy.read_text(), 65, ''),
    ('duplicate-legacy', legacy.read_text() * 2, 65, '')]:
    p = W / (name + '.data');p.write_text(content)
    cases.append((name, p, status, identity, ''))
for name, data, expected, identity, fault in cases:
    c = W / name;c.mkdir()
    dest = c / 'destination'
    code = f'''{detector}
pull_status=0
pct() {{ [[ "$1" == pull ]] || return 98; printf '%s\\n' "$4" > {q(dest)}; /bin/cp {q(data)} "$4"; return "$pull_status"; }}
{fault}
service=stale
if detect_service 500; then rc=0; else rc=$?; fi
printf '%s' "${{service:-}}" > {q(c / 'service')}
printf '%s' "$PWD" > {q(c / 'cwd')}
exit "$rc"
'''
    r = run('detect-' + name, code, c)
    check(name + ' exact detector status', expected, r.returncode)
    check(name + ' canonical or cleared output', identity, (c / 'service').read_text())
    check(name + ' caller cwd retained', str(c), (c / 'cwd').read_text())
    pulled = Path(dest.read_text().strip())
    check(name + ' private stage removed', True, pulled.is_absolute() and pulled.parent == W and not pulled.exists())
    check(name + ' pulled data never executed', False, sentinel.exists())

# Same shell: a failed later pull cannot inherit the preceding CT's identity.
r = run('stale-after-success', detector + f'''
n=0
pct() {{ n=$((n+1)); if [[ "$n" == 1 ]]; then /bin/cp {q(bundle)} "$4"; else printf partial > "$4"; return 47; fi; }}
detect_service 500 || exit $?
if detect_service 501; then exit 91; else rc=$?; fi
[[ -z "$service" && "$rc" == 47 ]]
''')
check('failed pull after actual success clears stale identity', 0, r.returncode)

# Actual producer -> detector -> URL -> real source parser -> recorded pct set.
start = re.search(r'(?m)^  (?:if )?detect_service ', text).start()
fragment = text[start:text.index('  case "$os" in', start)]
prefix = text[:text.index('# CONFIGURATION VARIABLES')]
for name, data, base in [('current-chain', bundle, 'https://fixture.invalid/batch'),
                         ('legacy-chain', legacy, 'https://fixture.invalid/batch'),
                         ('current-default-chain', bundle, None),
                         ('legacy-default-chain', legacy, None)]:
    c = W / name;c.mkdir();calls = c / 'calls'
    expected_base = base or 'https://raw.githubusercontent.com/scripts-underground/proxmox/main'
    setup = 'unset REPO_BASE' if base is None else 'REPO_BASE=' + q(base)
    code = f'''{setup}
curl() {{ printf 'curl %s\\n' "${{!#}}" >> {q(calls)}; case "${{!#}}" in
 */misc/core.func) /bin/cat {q(S / 'misc/core.func')} ;;
 {q(expected_base + '/scripts/lxc/changedetection.sh')}) /bin/cat {q(S / 'scripts/lxc/changedetection.sh')} ;;
 *) return 89 ;; esac; }}
cpu=1 ram=8192
pct() {{ printf 'pct %s\\n' "$*" >> {q(calls)}; case "$1" in
 pull) /bin/cp {q(data)} "$4" ;;
 config) printf 'cores: %s\\nmemory: %s\\n' "$cpu" "$ram" ;;
 set) cpu=$4; ram=$6 ;; *) return 98 ;; esac; }}
{prefix}
load_functions
{detector}
{resource}
for container in 500; do
{fragment}
printf '%s:%s:%s' "$service" "$cpu" "$ram" > {q(c / 'consumer')}
done
'''
    r = run(name, code, c)
    check(name + ' productive chain status', 0, r.returncode)
    check(name + ' exact final prepared pair', 'changedetection:4:8192',
          (c / 'consumer').read_text() if (c / 'consumer').exists() else '')
    trace = calls.read_text()
    check(name + ' exact metadata service URL', True,
          'curl ' + expected_base + '/scripts/lxc/changedetection.sh\n' in trace)
    check(name + ' no lowered current dimension', True, 'pct set 500 --cores 4 --memory 8192\n' in trace)

if resource:
    for label, value, status, pair in [
        ('max', '9223372036854775807', 0, '4:9223372036854775807'),
        ('overflow', '9223372036854775808', 65, '4:4096'),
        ('long-overflow', '18446744073709551616', 65, '4:4096'),
        ('leading-zero', '0008192', 0, '4:8192')]:
        target = W / ('range-' + label)
        r = run('range-' + label, resource + f'''
container=500 current_cpu=1 current_ram={q(value)} build_cpu=4 build_ram=4096 run_cpu=1 run_ram={q(value)}
if prepare_batch_resources; then rc=0; else rc=$?; fi
printf '%s:%s' "$build_cpu" "$build_ram" > {q(target)}
exit "$rc"
''')
        check(label + ' literal range status without arithmetic overflow', status, r.returncode)
        check(label + ' literal range/floor consumer', pair, target.read_text())
(W / 'checks.json').write_text(json.dumps(checks, sort_keys=True, indent=2))
failures = sum(not v['passed'] for v in checks)
print(str(len(checks)) + ' batch metadata checks; ' + str(failures) + ' failure(s)', flush=True)
raise SystemExit(bool(failures))
