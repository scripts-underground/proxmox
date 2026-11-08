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
                                LXC_SCRIPT_ID='ambient-poison', var_lxc_script_id='default-poison',
                                LXC_REQUIRED_CPU='0', LXC_REQUIRED_RAM='0'),
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
  var_cpu=99 var_ram=99999
}}
color() {{ :; }}; render_header() {{ :; }}; catch_errors() {{ :; }}
_lxc_setup() {{ shift 2; printf '%s\\n' "$@" > {q(c / 'arguments')}; var_cpu=1 var_ram=1; }}
complete_install() {{ printf complete > {q(c / 'complete')}; }}
execute_optional_hook() {{ printf '%s\\n' "$*" >> {q(c / 'prebuild')}; }}
msg_info() {{ :; }}; msg_ok() {{ :; }}; msg_error() {{ :; }}; msg_debug() {{ :; }}
_framework_cache_ensure() {{ :; }}
_framework_cache_dir() {{ printf '%s' {q(cache)}; }}
build_bundle() {{
  local role=$1 hook=$2 ignored_destination=$3 mode=$4
  shift 4
  printf '%s\\n' "$role" >> {q(c / 'prepared')}
  fixture_real_build_bundle "$role" "$hook" {q(c / 'received')}/"$role" "$mode" "$@" || return $?
  if [[ "$role" == update ]]; then
    /bin/cp {q(c / 'received')}/update {q(c / 'received')}/"update.$(wc -l < {q(c / 'prepared')})"
  fi
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

# Actual maintained app hook, through its footer and both real preparation paths.
# Service/package/release executables are modeled; consent, bundles and files are real.
budget_cases = [
    ('equal', '', ('2', '2048'), b'', 0, ('2', '2048'), False),
    ('enough', '', ('4', '4096'), b'', 0, ('2', '2048'), False),
    ('cpu-no', '', ('1', '4096'), b'no\n', 1, ('2', '2048'), True),
    ('ram-no', '', ('4', '1024'), b'no\n', 1, ('2', '2048'), True),
    ('short-empty', '', ('1', '1024'), b'\n', 1, ('2', '2048'), True),
    ('short-eof', '', ('1', '1024'), b'', 1, ('2', '2048'), True),
    ('short-yes', '', ('1', '1024'), b'YeS\n', 0, ('2', '2048'), True),
    ('override', 'var_cpu=3 var_ram=3072', ('3', '3072'), b'', 0, ('3', '3072'), False),
    ('missing-no', 'unset var_cpu var_ram', ('8', '8192'), b'no\n', 1, ('', ''), True),
    ('missing-eof', 'unset var_cpu var_ram', ('8', '8192'), b'', 1, ('', ''), True),
    ('missing-yes', 'unset var_cpu var_ram', ('8', '8192'), b'yes\n', 0, ('', ''), True),
    ('invalid', "var_cpu='$(touch BAD)' var_ram=2048", ('8', '8192'), b'no\n', 1, ('$(touch BAD)', '2048'), True),
    ('zero', 'var_cpu=0 var_ram=0', ('1', '1024'), b'', 0, ('0', '0'), False),
    ('prior-no', '', ('1', '1024'), b'no\n', 1, ('2', '2048'), True),
]
grafana_cases = [
    ('short-no', '', ('1', '1024'), b'no\n', 1, ('2', '1024'), True),
    ('short-eof', '', ('1', '1024'), b'', 1, ('2', '1024'), True),
    ('short-yes', '', ('1', '1024'), b'yes\n', 0, ('2', '1024'), True),
    ('unknown-no', 'unset var_cpu var_ram', ('8', '8192'), b'no\n', 1, ('', ''), True),
    ('unknown-eof', 'unset var_cpu var_ram', ('8', '8192'), b'', 1, ('', ''), True),
    ('unknown-yes', 'unset var_cpu var_ram', ('8', '8192'), b'yes\n', 0, ('', ''), True),
    ('enough', '', ('8', '8192'), b'', 0, ('2', '1024'), False),
    ('prior-no', '', ('1', '1024'), b'no\n', 1, ('2', '1024'), True),
]
for slug, scenario in [('actualbudget', row) for row in budget_cases] + [('alpine-grafana', row) for row in grafana_cases]:
    label, supplied, actual, answer, status, required, prompt = scenario
    app = (S / ('scripts/lxc/' + slug + '.sh')).read_text()
    app_declarations = app[:app.index('function install_script() {')]
    app_hook = function(app, 'update_script')
    app_footer, = [line for line in app.splitlines() if line.startswith('source ') and '/misc/bootstrap/lxc' in line]
    label = slug + '-' + label
    c = case('direct-requirements-' + label)
    m, _ = module(c)
    mapped_hook = app_hook.replace('/opt/actualbudget-data', str(c / 'app-data'))
    m.write_text(m.read_text().replace('update_script() { :; }', mapped_hook, 1))
    code = f'''set -euo pipefail
{app_declarations}
{supplied}
curl() {{ case "${{!#}}" in */misc/bootstrap/lxc) /bin/cat {q(S / 'misc/bootstrap/lxc')};; */misc/build.func) /bin/cat {q(m)};; *) return 89;; esac; }}
{app_footer}
'''
    r = run(c, 'producer', code)
    check(label + ' maintained footer capture producer status', 0, r.returncode)
    for suffix in ('2', '5'):
        p = c / 'received' / ('update.' + suffix)
        text = p.read_text() if p.exists() else ''
        # Read field values through the actual cold shell below, never eval them here.
        check(label + '/' + suffix + ' both explicit requirement declarations', 2,
              len(re.findall(r'(?m)^declare -- LXC_REQUIRED_(?:CPU|RAM)=', text)))
    (c / '.actualbudget').write_text('fixture release')
    (c / 'app-data').mkdir()
    (c / 'app-data/config.json').write_text('operator-config: retained\n')
    runtime = c / 'received/update'
    (c / 'models').write_text('''header_info() { :; }; check_container_storage() { :; }; cleanup_lxc() { :; }
msg_info() { :; }; msg_ok() { :; }; msg_warn() { :; }
setup_nodejs() { printf package >> "$HOME/software"; }
get_latest_github_release() { printf release >> "$HOME/software"; printf fixture; }
check_for_gh_release() { return 0; }
systemctl() { printf service >> "$HOME/software"; }; npm() { printf npm >> "$HOME/software"; }
apk() { printf apk >> "$HOME/software"; }; rc-service() { printf service >> "$HOME/software"; }
printf '%s\\n%s' "${LXC_REQUIRED_CPU-absent}" "${LXC_REQUIRED_RAM-absent}" > "$HOME/captured"
''')
    # The bundle pipeline remains real run_update_script, with modeled APIs supplied
    # immediately before that call rather than by a seeded replacement update hook.
    # A second consumer file is constructed only from the generated bundle bytes.
    text = runtime.read_text()
    text = text.replace('run_update_script "$@"', f'source {q(c / "models")}\nrun_update_script "$@"', 1)
    consumer = c / 'cold-consumer';consumer.write_text(text)
    pending = c / 'pending' / slug
    if label.endswith('prior-no'):
        pending.parent.mkdir(exist_ok=True)
        pending.write_text('original pending bytes\n')
    check(label + ' initial and repair requirement fields identical',
          re.findall(r'(?m)^declare -- LXC_REQUIRED_(?:CPU|RAM)=.*$', (c / 'received/update.2').read_text()),
          re.findall(r'(?m)^declare -- LXC_REQUIRED_(?:CPU|RAM)=.*$', text))
    r = run(c, 'cold-consumer', f'''nproc() {{ printf '%s\\n' {q(actual[0])}; }}; free() {{ printf 'total used free\\nMem: %s 0 0\\n' {q(actual[1])}; }}; export -f nproc free
exec /bin/bash {q(consumer)}''', answer)
    check(label + ' actual maintained cold terminal status', status, r.returncode)
    check(label + ' actual package/service boundary requires consent', status == 0, (c / 'software').exists())
    check(label + ' warning/consent at the real adapter', prompt, b'Continue update' in r.stdout + r.stderr)
    check(label + ' exactly one unchanged-input consent prompt', int(prompt), (r.stdout + r.stderr).count(b'Continue update'))
    check(label + ' refusal preserves original pending without new flag',
          'original pending bytes\n' if label.endswith('prior-no') else None,
          pending.read_text() if pending.exists() else None)
    check(label + ' captured pair survives defaults/menus/ambient poison', '\n'.join(required),
          (c / 'captured').read_text() if (c / 'captured').exists() else '')
    check(label + ' actual app configuration unchanged', 'operator-config: retained\n', (c / 'app-data/config.json').read_text())
    check(label + ' requirement expression never executes', False, (c / 'BAD').exists())

# Actual maintained source/footer/bootstrap/setup/runner, including profile input
# mutation. Only context detection, profile and package/service APIs are modeled.
for mode in ('silent', 'menu'):
    for label, supplied, answer, expected, prompt in [
        ('no', '', b'no\n', 1, True), ('eof', '', b'', 1, True),
        ('yes', '', b'yes\n', 0, True), ('unknown-no', 'unset var_cpu var_ram', b'no\n', 1, True),
        ('unknown-eof', 'unset var_cpu var_ram', b'', 1, True),
        ('unknown-yes', 'unset var_cpu var_ram', b'yes\n', 0, True),
        ('zero', 'var_cpu=0 var_ram=0', b'', 0, False), ('busy', '', b'yes\n', 75, False)]:
        c = case('source-entry-' + mode + '-' + label)
        core = (S / 'misc/core.func').read_text().replace('/var/lib/scripts-underground/update-pending', str(c / 'pending')).replace('/var/lib/scripts-underground/maintenance-locks', str(c / 'locks'))
        (c / 'core.func').write_text(core)
        setup = '\n'.join(function(build, n) for n in ('_lxc_bootstrap', 'lxc_setup', '_lxc_setup'))
        (c / 'module').write_text(f'''source {q(c / 'core.func')}
source {q(S / 'misc/error_handler.func')}
source {q(S / 'misc/bundle.func')}
load_functions
{setup}
variables() {{ NSAPP=alpine-grafana; var_cpu=99 var_ram=99999; }}
color() {{ :; }}; render_header() {{ :; }}; header_info() {{ :; }}; cleanup_lxc() {{ :; }}
msg_info() {{ :; }}; msg_ok() {{ :; }}; msg_warn() {{ :; }}
ensure_profile_loaded() {{ var_cpu=0 var_ram=0 LXC_REQUIRED_CPU=0 LXC_REQUIRED_RAM=0; printf loaded > "$HOME/profile"; }}
whiptail() {{ printf 1 >&3; }}
nproc() {{ printf cpu >> "$HOME/probes"; printf '1\\n'; }}
free() {{ printf ram >> "$HOME/probes"; printf 'total used free\\nMem: 8192 0 0\\n'; }}
apk() {{ printf package >> "$HOME/software"; }}; rc-service() {{ printf service >> "$HOME/software"; }}
''')
        # Keep native shell/tool semantics. Model container context by omitting
        # pveversion from a private PATH, as the native lock fixture does.
        (c / 'bin').mkdir()
        for name in ('bash', 'stat', 'flock', 'mkdir', 'rm', 'date', 'awk', 'grep',
                     'sed', 'tr', 'dirname', 'basename', 'mktemp', 'tee', 'stty',
                     'tput', 'hostname', 'ip', 'find', 'du', 'tail', 'cat', 'ps',
                     'readlink', 'df'):
            p = Path('/usr/bin') / name
            if p.is_file():
                (c / 'bin' / name).symlink_to(p)
        declarations = (S / 'scripts/lxc/alpine-grafana.sh').read_text()
        declarations = declarations[:declarations.index('function install_script() {')]
        hook = function((S / 'scripts/lxc/alpine-grafana.sh').read_text(), 'update_script')
        busy = f'''umask 077; mkdir -p {q(c / 'locks')}; exec {{held}}> {q(c / 'locks/alpine-grafana.lock')}; builtin command flock -n "$held";''' if label == 'busy' else ''
        footer, = [line for line in (S / 'scripts/lxc/alpine-grafana.sh').read_text().splitlines() if line.startswith('source ') and '/misc/bootstrap/lxc' in line]
        code = f'''set -euo pipefail
{declarations}
{supplied}
{hook}
curl() {{ case "${{!#}}" in */misc/bootstrap/lxc) /bin/cat {q(S / 'misc/bootstrap/lxc')};; */misc/build.func) /bin/cat {q(c / 'module')};; *) :;; esac; }}
{('PHS_SILENT=1' if mode == 'silent' else 'unset PHS_SILENT')}
export PATH={q(c / 'bin')}
{busy}
{footer}
'''
        # The same curl transport used by the actual footer loads our source-only
        # module; the bootstrap file itself is literal repository content.
        r = run(c, 'source-flow', code, answer)
        check(mode + '/' + label + ' actual source entry status', expected, r.returncode)
        check(mode + '/' + label + ' no package/service before source consent', expected == 0, (c / 'software').exists())
        check(mode + '/' + label + ' source consent prompt', int(prompt), (r.stdout + r.stderr).count(b'Continue update'))
        check(mode + '/' + label + ' profile path reached', True, (c / 'profile').exists())
        if label == 'busy':
            check(mode + '/busy fresh owner precedes any resource probe', False, (c / 'probes').exists())

(W / 'checks.json').write_text(json.dumps(checks, sort_keys=True, indent=2))
failures = sum(not d['passed'] for d in checks)
print(f'{len(checks)} source identity checks; {failures} failure(s)', flush=True)
raise SystemExit(bool(failures))
