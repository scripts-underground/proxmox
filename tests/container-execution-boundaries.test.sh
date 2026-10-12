#!/usr/bin/env bash
# Native guest-boundary contracts; never run on the physical host.
set -euo pipefail
systemd-detect-virt --vm -q || exit 77
exec python3 - "$(dirname "${BASH_SOURCE[0]}")/.." << 'PY'
import functools
import hashlib
import http.server
import json
import os
import pathlib
import re
import shlex
import shutil
import subprocess
import threading
import time
import textwrap

assert os.geteuid() == 0
assert pathlib.Path('/sys/class/dmi/id/product_uuid').read_text().strip().lower() == '4be13420-4459-4200-a1c2-7ac7232ac650'
source = pathlib.Path(os.sys.argv[1]).resolve()
root = pathlib.Path('/srv/scripts-underground-tests/evidence')/('container-boundaries-'+str(time.time_ns()))
root.mkdir(mode=0o700)
rows = []

def function(text, name):
    matches = list(re.finditer(r'^'+re.escape(name)+r'\(\) \{\n.*?^\}', text, re.M | re.S))
    assert len(matches) == 1, name
    return matches[0].group(0)+'\n'

server = http.server.ThreadingHTTPServer(('127.0.0.1', 0), functools.partial(http.server.SimpleHTTPRequestHandler, directory=str(source)))
thread = threading.Thread(target=server.serve_forever, daemon=True)
thread.start()
try:
    for scenario in ['cold-default-tmp', 'cold-configured-tmp', 'network-failure-status', 'kept-failure-status',
                     'retry-selection-status', 'group-query-status']:
        case = root/scenario
        case.mkdir(mode=0o700)
        for leaf in ['tmp', 'home', 'guest-root', 'configured-tmp']:
            (case/leaf).mkdir(mode=0o700)
        (case/'guest-root/install.log').write_text('retained install evidence\n')
        actions = case/'actions'
        actions.write_text('')
        env = dict(os.environ, CASE=str(case), HOME=str(case/'home'), TMPDIR='/absent-creator-only-path',
                   APP='Boundary Fixture', NSAPP='boundary-fixture', CTID='2000', SESSION_ID='boundary-'+str(time.time_ns()),
                   REPO_BASE='http://127.0.0.1:'+str(server.server_port), TERM='dumb',
                   INSTALL_LOG='/root/install.log', DEV_MODE_KEEP='true')
        code = r'''
msg_info() { :; }
msg_ok() { :; }
msg_debug() { :; }
msg_dev() { :; }
msg_error() { printf 'ERROR %s\n' "$*" >&2; }
msg_warn() { printf 'WARN %s\n' "$*" >&2; }
pct() {
  printf '%s\n' "$*" >> "$CASE/actions"
  case "$1" in
    push) cp -- "$3" "$4" ;;
    exec) shift 3; command "$@" ;;
    status) printf 'status: running\n' ;;
    *) return 88 ;;
  esac
}
'''
        if scenario.startswith('cold-'):
            code += 'source '+shlex.quote(str(source/'misc/bundle.func'))+'\n'
            if scenario == 'cold-configured-tmp':
                code += 'var_lxc_tmpdir='+shlex.quote(str(case/'configured-tmp'))+'\n'
            code += r'''
probe() {
  printf '%s\n' "$TMPDIR" > "$CASE/observed-tmp"
  mktemp > "$CASE/temp-file"
}
build_bundle update probe "$CASE/cold-bundle.sh" 0700 probe
# No inherited shell definitions or creator filesystem path may satisfy the probe.
env -i PATH="$PATH" CASE="$CASE" HOME="$HOME" TMPDIR=/absent-creator-only-path TERM=dumb bash "$CASE/cold-bundle.sh"
'''
        else:
            code += 'source '+shlex.quote(str(source/'misc/error_handler.func'))+'\n'
            if scenario == 'network-failure-status':
                code += function((source/'misc/install.func').read_text(), 'network_check')
                code += r'''
ping() { return 0; }
ping6() { return 1; }
getent() { printf '127.0.0.1 fixture\n'; }
sleep() { :; }
catch_errors
network_check
bash -c 'exit 37'
printf 'incorrect success\n' > "$CASE/success"
'''
            elif scenario == 'kept-failure-status':
                env.pop('INSTALL_LOG')
                build = (source/'misc/build.func').read_text()
                match = re.search(r'    if \[\[ "\$\{DEV_MODE_KEEP:-false\}" == "true" \]\]; then\n(.*?)    elif \[\[ "\$\{DEV_MODE_BREAKPOINT', build, re.S)
                assert match
                code += 'build_failure() {\nlocal install_exit_code=37\n'+match[1]+'}\n'
                code += 'catch_errors\nbuild_failure\nprintf "incorrect success\\n" > "$CASE/success"\n'
            elif scenario == 'retry-selection-status':
                build = (source/'misc/build.func').read_text()
                fragments = re.findall(r'^\s*(?:export )?CTID=\$\(get_valid_container_id "\$CTID"\)[^\n]*\n(?:\s*export CTID\n)?', build, re.M)
                assert len(fragments) == 3 and len({'\n'.join(line.strip() for line in fragment.splitlines()).strip() for fragment in fragments}) == 1
                code += 'get_valid_container_id() { printf "2009\\n"; return 37; }\n'
                code += 'retry_build() {\n'+fragments[0]+'printf "invalid retry dispatched\\n" > "$CASE/success"\n}\n'
                code += 'catch_errors\nretry_build\n'
            else:
                build = (source/'misc/build.func').read_text()
                fragment = re.search(r'^  get_container_gid\(\) \{\n.*?^  \}', build, re.M | re.S)
                assert fragment
                code += textwrap.dedent(fragment.group(0))+'\n'
                code += 'pct() { printf "video:x:44:\\n"; return 37; }\n'
                code += 'catch_errors\nget_container_gid video\nprintf "invalid group consumed\\n" > "$CASE/success"\n'
        # Private roots protect actual CTs/guest root while exercising the real trap.
        launcher = 'import subprocess\nsubprocess.run(["mount","--bind",'+repr(str(case/'guest-root'))+',"/root"],check=True)\n'
        launcher += 'subprocess.run(["mount","--bind",'+repr(str(case/'tmp'))+',"/tmp"],check=True)\n'
        launcher += 'raise SystemExit(subprocess.run(["bash","-c",'+repr(code)+'],env='+repr(env)+').returncode)\n'
        run = subprocess.run(['unshare','--mount','--propagation','private','python3','-c',launcher], capture_output=True, text=True, timeout=45)
        checks = []
        def check(label, expected, actual):
            checks.append({'name':label,'expected':expected,'actual':actual,'passed':expected == actual})
        check('native process status', 0 if scenario.startswith('cold-') else 37, run.returncode)
        check('failure cannot reach success continuation', False, (case/'success').exists())
        if scenario.startswith('cold-'):
            expected = '/var/tmp' if scenario == 'cold-default-tmp' else str(case/'configured-tmp')
            check('cold bundle uses guest-owned temporary context', expected, (case/'observed-tmp').read_text().strip() if (case/'observed-tmp').exists() else None)
            check('native temporary file created in guest context', True, (case/'temp-file').exists())
        else:
            check('keep policy never enters cleanup menu or calls CT destroy', False,
                  'destroy' in actions.read_text() or 'Remove broken container' in run.stdout)
            if scenario in {'network-failure-status', 'retry-selection-status', 'group-query-status'}:
                marker = case/'guest-root'/('.install-'+env['SESSION_ID']+'.failed')
                check('failure marker retains command status, not source line', '37\n', marker.read_text() if marker.exists() else None)
        row = {'scenario':scenario,'status':'PASS' if all(c['passed'] for c in checks) else 'FAIL','checks':checks,
               'native_status':run.returncode,'stdout':run.stdout,'stderr':run.stderr}
        (case/'result.json').write_text(json.dumps(row,indent=2)+'\n')
        rows.append(row)
        print(row['status']+' '+scenario,flush=True)
finally:
    server.shutdown()
    thread.join()
document = {'status':'PASS' if all(row['status']=='PASS' for row in rows) else 'FAIL','results':rows,
            'source_hashes':{name:hashlib.sha256((source/name).read_bytes()).hexdigest() for name in ['misc/build.func','misc/bundle.func','misc/install.func','misc/error_handler.func']}}
(root/'results.json').write_text(json.dumps(document,indent=2)+'\n')
print('EVIDENCE',root/'results.json')
raise SystemExit(0 if document['status']=='PASS' else 2)
PY
