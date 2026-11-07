"""Real footer/bootstrap/preparation/writer/reader, with PVE effects modeled."""
import json
import os
from pathlib import Path
import re
import shlex
import subprocess
import sys
import tempfile

S = Path(sys.argv[1])
W = Path(tempfile.mkdtemp(prefix='source-script-identity.', dir=os.environ['TMPDIR']))
print('Source identity evidence: ' + str(W), flush=True)
checks = []
q = lambda p: shlex.quote(str(p))


def check(name, expected, actual):
    ok = expected == actual
    checks.append(dict(name=name, expected=expected, actual=actual, passed=ok))
    print(('PASS ' if ok else 'FAIL ') + name, flush=True)


def function(text, name):
    found = re.search(r'(?ms)^(?:function )?' + re.escape(name) + r'\(\) \{\n.*?^\}', text)
    return found.group() if found else ''


def run(c, name, code, answer=b''):
    r = subprocess.run(['/bin/bash', '-c', code], cwd=c, input=answer,
                       env=dict(PATH='/usr/bin:/bin', HOME=str(c), TMPDIR=str(c),
                                LXC_SCRIPT_ID='ambient-poison', var_lxc_script_id='default-poison'),
                       capture_output=True, timeout=30)
    (c / (name + '.json')).write_text(json.dumps(dict(status=r.returncode,
        code=code, stdout=r.stdout.decode(errors='replace'), stderr=r.stderr.decode(errors='replace'))))
    return r


def case(name):
    c = W / name
    c.mkdir()
    return c


build = (S / 'misc/build.func').read_text()
bundle = (S / 'misc/bundle.func').read_text()
batch = (S / 'scripts/pve/update-apps.sh').read_text()
preparation = function(build, '_prepare_container_bundles')
bootstrap = function(build, '_lxc_bootstrap')
normalization = next(line for line in function(build, 'variables').splitlines() if line.strip().startswith('NSAPP='))
# Preserve the actual local capture and both production call sites. Hardware and
# storage work between these sections is outside this non-native proof boundary.
start = build.index('build_container() {')
prefix = build[start:build.index('  NET_STRING=', start)]
start = build.index('  local install_tmpdir=', start)
initial = build[start:build.index('\n\n  msg_ok ', start)]
start = build.index('            if _prepare_container_bundles ', start)
repair = build[start:build.index('            set +Eeuo pipefail', start)]
build_sections = prefix + initial + '\n' + repair + '\n}\n'
reader = '\n'.join(function(batch, name) for name in ('detect_service', 'read_batch_requirements', 'admit_batch_update'))


def module(c):
    cache = c / 'cache'
    cache.mkdir()
    core = (S / 'misc/core.func').read_text()
    for old, new in [('/var/lib/scripts-underground/update-pending', str(c / 'pending')),
                     ('/var/lib/scripts-underground/maintenance-locks', str(c / 'locks'))]:
        core = core.replace(old, new)
    (cache / 'core.func').write_text(core)
    (cache / 'error_handler.func').write_bytes((S / 'misc/error_handler.func').read_bytes())
    for name, declaration in [('install', 'setup_lxc() { :; }'), ('tools', 'setup_uv() { :; }'),
                              ('github', 'clone_and_deploy_gh_commit() { :; }')]:
        (cache / (name + '.func')).write_text(declaration + '\n')
    renamed = c / 'bundle.func'
    renamed.write_text(bundle.replace('build_bundle() {', 'fixture_real_build_bundle() {', 1))
    (c / 'received').mkdir()
    text = f'''source {q(renamed)}
{bootstrap}
{preparation}
{build_sections}
variables() {{
{normalization}
  var_lxc_tmpdir={q(c / 'received')}
  LXC_SCRIPT_ID=mutated-default var_lxc_script_id=mutated-default
}}
color() {{ :; }}; render_header() {{ :; }}; catch_errors() {{ :; }}
lxc_setup() {{ printf '%s\\n' "$@" > {q(c / 'arguments')}; }}
complete_install() {{ printf complete > {q(c / 'complete')}; }}
execute_optional_hook() {{ printf '%s\\n' "$*" >> {q(c / 'prebuild')}; }}
msg_info() {{ :; }}; msg_ok() {{ :; }}; msg_error() {{ :; }}; msg_debug() {{ :; }}
_framework_cache_ensure() {{ :; }}
_framework_cache_dir() {{ printf '%s' {q(cache)}; }}
build_bundle() {{
  local role=$1 hook=$2 ignored_destination=$3 mode=$4
  shift 4
  printf '%s\\n' "$role" >> {q(c / 'prepared')}
  fixture_real_build_bundle "$role" "$hook" {q(c / 'received')}/"$role" "$mode" "$@"
}}
pct() {{
  printf '%s\\n' "$*" >> {q(c / 'pct')}
  case "$1" in
    push) /bin/cp -- "$3" "$4" ;;
    exec)
      shift 3
      case "$1" in bash | ln) return 0 ;; *) command "$@" ;; esac ;;
    *) return 98 ;;
  esac
}}
install_script() {{ :; }}; update_script() {{ :; }}; uninstall_script() {{ :; }}
CTID=500 CT_TYPE=1 SESSION_ID=identity CONTAINER_INSTALLING=true
'''
    p = c / 'build-module'
    p.write_text(text)
    return p, cache


produced = {}
for slug, namespace, cpu in [('llama-cpp', 'llama.cpp', '4'), ('netvisor', 'scanopy', '2'), ('scanopy', 'scanopy', '4')]:
    c = case(slug)
    m, cache = module(c)
    source = (S / ('scripts/lxc/' + slug + '.sh')).read_text()
    declarations = source[:source.index('function install_script() {')]
    footer, = [line for line in source.splitlines() if line.startswith('source ') and '/misc/bootstrap/lxc' in line]
    code = f'''set -euo pipefail
export REPO_BASE=https://fixture.invalid/owned
{declarations}
curl() {{ case "${{!#}}" in
 */misc/bootstrap/lxc) /bin/cat {q(S / 'misc/bootstrap/lxc')} ;;
 */misc/build.func) /bin/cat {q(m)} ;;
 *) return 89 ;; esac; }}
set -- --clean
{footer}
'''
    r = run(c, 'footer-chain', code)
    check(slug + ' actual footer/bootstrap/initial/repair status', 0, r.returncode)
    check(slug + ' remaining --clean argument', '--clean\n', (c / 'arguments').read_text() if (c / 'arguments').exists() else '')
    check(slug + ' both actual preparation call sites', ['install', 'update', 'uninstall'] * 2,
          (c / 'prepared').read_text().splitlines() if (c / 'prepared').exists() else [])
    for role in ('install', 'update', 'uninstall'):
        p = c / 'received' / role
        raw = p.read_text() if p.exists() else ''
        fields = re.findall(r'(?m)^declare -- LXC_SCRIPT_ID=(.*)$', raw)
        check(slug + '/' + role + ' exact identity ownership', [slug] if role == 'update' else [], fields)
        check(slug + '/' + role + ' original namespace retained', True, 'declare -- NSAPP=' + namespace + '\n' in raw)
    if (c / 'received/update').exists():
        produced[slug] = (c / 'received/update', cache, namespace, cpu)

for label, args, expected in [
    ('legacy', '--clean', 0), ('empty', '--script-id "" --', 65),
    ('missing', '--script-id', 65), ('separator', '--script-id netvisor --clean', 65),
    ('path', '--script-id ../netvisor --', 65), ('expression', "--script-id '$(touch BAD)' --", 65),
    ('duplicate', '--script-id netvisor -- --script-id scanopy --', 65),
]:
    c = case('bootstrap-' + label)
    m, _ = module(c)
    code = f'''set -euo pipefail; APP=Compatibility; REPO_BASE=https://fixture.invalid
curl() {{ /bin/cat {q(m)}; }}
source {q(S / 'misc/bootstrap/lxc')} {args}
'''
    r = run(c, 'result', code)
    check(label + ' exact bootstrap validation status', expected, r.returncode)
    check(label + ' effects only after admission', expected == 0, (c / 'prebuild').exists())
    check(label + ' no expression execution', False, (c / 'BAD').exists())
    if label == 'legacy':
        p = c / 'received/update'
        check('legacy no ambient/default identity inheritance', False,
              p.exists() and 'declare -- LXC_SCRIPT_ID=' in p.read_text())


def admission(label, updater, namespace, answer, status, expected_id, cpu, expected_url):
    c = case('admission-' + label)
    calls = c / 'urls'
    code = f'''set -euo pipefail
source {q(S / 'misc/core.func')}
{reader}
REPO_BASE=https://fixture.invalid/owned container=500
PULL_STATUS=0
pct() {{ case "$1" in
 pull) /bin/cp -- {q(updater)} "$4"; return "$PULL_STATUS" ;;
 exec) case "$*" in 'exec 500 -- nproc') printf '8\\n';; 'exec 500 -- free -m') printf 'total used free\\nMem: 8192 0 0\\n';; *) return 98;; esac ;;
 *) return 98;; esac; }}
curl() {{
 printf '%s\\n' "${{!#}}" >> {q(calls)}
 local slug=${{!#}}; slug=${{slug##*/}}
 [[ -f {q(S / 'scripts/lxc')}/"$slug" ]] || return 47
 /bin/cat {q(S / 'scripts/lxc')}/"$slug"
}}
service=stale source_script_id=stale
detect_service 500 || exit $?
printf '%s' "$service" > namespace
printf '%s' "${{source_script_id-}}" > identity
if admit_batch_update; then rc=0; printf admitted > software; else rc=$?; fi
printf '%s' "$required_cpu" > requirement
PULL_STATUS=47
if detect_service 501; then exit 99; else
 [[ -z "$service" && -z "${{source_script_id-}}" ]] || exit 98
fi
exit "$rc"
'''
    r = run(c, 'result', code, answer)
    check(label + ' exact consent/measurement status', status, r.returncode)
    check(label + ' original namespace consumer', namespace, (c / 'namespace').read_text() if (c / 'namespace').exists() else '')
    check(label + ' canonical or unknown source identity', expected_id, (c / 'identity').read_text() if (c / 'identity').exists() else '')
    check(label + ' exact required CPU consumer', cpu, (c / 'requirement').read_text() if (c / 'requirement').exists() else '')
    check(label + ' only authoritative metadata request', expected_url,
          calls.read_text().splitlines() if calls.exists() else [])
    check(label + ' software requires actual consent', status == 0, (c / 'software').exists())
    check(label + ' identity expression never executes', False, (W / 'BAD').exists())


for slug, (p, cache, namespace, cpu) in produced.items():
    admission(slug, p, namespace, b'', 0, slug, cpu,
              ['https://fixture.invalid/owned/scripts/lxc/' + slug + '.sh'])

if 'scanopy' in produced:
    p, cache, namespace, _ = produced['scanopy']
    raw = p.read_text()
    marker = 'declare -- LXC_SCRIPT_ID=scanopy\n'
    old = raw.replace(marker, '')
    malformed = W / 'malformed-updater'
    duplicate = W / 'duplicate-updater'
    legacy = W / 'old-updater'
    legacy.write_text(old)
    malformed.write_text(old + '\ndeclare -- LXC_SCRIPT_ID=$(touch ' + str(W / 'BAD') + ')\n')
    duplicate.write_text(old + '\n' + marker + marker)
    for label, data in [('old', legacy), ('malformed', malformed), ('duplicate', duplicate)]:
        for answer, suffix, status in [(b'no\n', 'no', 1), (b'\n', 'empty', 1), (b'', 'eof', 1), (b'yes\n', 'yes', 0)]:
            admission(label + '-' + suffix, data, namespace, answer, status, '', '', [])

    for label, assignment in [
        ('export', 'export LXC_SCRIPT_ID=netvisor'),
        ('readonly', 'readonly LXC_SCRIPT_ID=netvisor'),
        ('bare', 'LXC_SCRIPT_ID=netvisor'),
        ('append', 'LXC_SCRIPT_ID+=netvisor'),
        ('array', 'LXC_SCRIPT_ID[0]=netvisor'),
        ('declare-array', 'declare -a LXC_SCRIPT_ID[0]=netvisor'),
        ('quoted', 'declare -- LXC_SCRIPT_ID="scanopy"'),
        ('empty', 'declare -- LXC_SCRIPT_ID='),
        ('suffix', 'declare -- LXC_SCRIPT_ID=scanopy.sh'),
    ]:
        p = W / ('unsupported-' + label)
        p.write_text(raw + '\n' + assignment + '\n')
        admission('unsupported-' + label, p, namespace, b'no\n', 1, '', '', [])

(W / 'checks.json').write_text(json.dumps(checks, sort_keys=True, indent=2))
failures = sum(not d['passed'] for d in checks)
print(f'{len(checks)} source identity checks; {failures} failure(s)', flush=True)
raise SystemExit(bool(failures))
