#!/usr/bin/env bash
# Native framework contracts; run only inside the dedicated Strata test VM.
set -euo pipefail
systemd-detect-virt --vm -q || exit 77
guest_uuid=$(< /sys/class/dmi/id/product_uuid)
[[ "${guest_uuid,,}" == 4be13420-4459-4200-a1c2-7ac7232ac650 ]] || exit 77
exec python3 - "$(dirname "${BASH_SOURCE[0]}")/.." "$@" << 'PY'
import functools
import hashlib
import http.server
import json
import os
import pathlib
import re
import shlex
import shutil
import stat
import subprocess
import sys
import threading
import time

source = pathlib.Path(sys.argv[1]).resolve()
assert os.geteuid() == 0
parent = pathlib.Path('/srv/scripts-underground-tests/evidence')
assert parent.is_dir() and not parent.is_symlink()
worker = len(sys.argv) == 4
cases = ['effective-disable', 'mixed-detection', 'regular-node-rejection', 'shared-only-rejection',
         'mixed-unattended', 'nvidia-one', 'repeated-selection', 'existing-mappings',
         'mapping-gids', 'gid-read-error', 'restart-error', 'restart-not-running',
         'permission-ownership', 'membership-error', 'cold-selected', 'cold-disabled',
         'gid-missing-group', 'gid-create-error', 'gid-valid-output-error', 'gid-malformed-record']

def function(text, name, indent=''):
    pattern = re.compile(r'^'+re.escape(indent+name)+r'\(\) \{\n.*?^'+re.escape(indent)+r'\}', re.M | re.S)
    matches = list(pattern.finditer(text))
    assert len(matches) == 1, name
    return matches[0].group(0)+'\n'

if not worker:
    root = parent/('gpu-mapping-'+str(time.time_ns()))
    root.mkdir(mode=0o700)
    rows = []
    for name in cases:
        case = root/name
        case.mkdir(mode=0o700)
        # A native PTY exercises the actual interactive read paths, not a read stub.
        argv = ['unshare', '--mount', '--propagation', 'private', 'bash',
                str(source/'tests/gpu-mapping-context.test.sh'), name, str(case)]
        if name == 'repeated-selection':
            argv = ['script', '--quiet', '--return', '--command', shlex.join(argv), '/dev/null']
        completed = subprocess.run(argv, input='1,1,3,3\n2,2\n' if name == 'repeated-selection' else '',
                                   capture_output=True, text=True, timeout=30)
        (case/'stdout.log').write_text(completed.stdout)
        (case/'stderr.log').write_text(completed.stderr)
        result = json.loads((case/'result.json').read_bytes()) if (case/'result.json').exists() else {'error': completed.stderr}
        rows.append({'case': name, 'process_status': completed.returncode, 'result': result})
        print(('PASS' if completed.returncode == 0 else 'FAIL')+' '+name, flush=True)
    document = {'source': str(source), 'source_hashes': {name: hashlib.sha256((source/name).read_bytes()).hexdigest()
                for name in ['misc/build.func', 'misc/bundle.func', 'misc/tools.func']}, 'cases': rows,
                'status': 'PASS' if all(row['process_status'] == 0 for row in rows) else 'FAIL',
                'scope': 'native private fixtures, actual framework functions/bundle; modeled PVE/account callbacks, no real GPU claim'}
    (root/'results.json').write_text(json.dumps(document, indent=2)+'\n')
    print('EVIDENCE '+str(root/'results.json'), flush=True)
    raise SystemExit(0 if document['status'] == 'PASS' else 2)

name, case = sys.argv[2], pathlib.Path(sys.argv[3])
assert name in cases and case.parent.parent == parent and case.name == name
for child in ['dev', 'sys', 'tmp', 'home', 'etc']:
    (case/child).mkdir(mode=0o700)
for leaf, major, minor in [('null', 1, 3), ('zero', 1, 5), ('tty', 5, 0)]:
    os.mknod(case/'dev'/leaf, stat.S_IFCHR | 0o666, os.makedev(major, minor))
for leaf, target in [('fd', '/proc/self/fd'), ('stdin', 'fd/0'), ('stdout', 'fd/1'), ('stderr', 'fd/2')]:
    os.symlink(target, case/'dev'/leaf)
(case/'dev/dri').mkdir()
(case/'dev/nvidia-caps').mkdir()
(case/'sys/class/drm').mkdir(parents=True)
nodes = {'/dev/dri/card0': '0x8086', '/dev/dri/renderD128': '0x8086',
         '/dev/dri/card1': '0x1002', '/dev/dri/renderD129': '0x1002',
         '/dev/nvidia0': None, '/dev/nvidia1': None, '/dev/nvidiactl': None,
         '/dev/nvidia-uvm': None, '/dev/nvidia-caps/nvidia-cap1': None, '/dev/kfd': None}
if name == 'nvidia-one':
    nodes = {path: vendor for path, vendor in nodes.items() if path.startswith('/dev/nvidia') and path != '/dev/nvidia0'}
if name == 'shared-only-rejection':
    nodes = {'/dev/nvidiactl': None, '/dev/nvidia-uvm': None}
for index, (path, vendor) in enumerate(nodes.items()):
    target = case/'dev'/path.removeprefix('/dev/')
    if name == 'regular-node-rejection':
        target.write_text('not a device\n')
    else:
        os.mknod(target, stat.S_IFCHR | 0o640, os.makedev(240, index))
    if vendor:
        record = case/'sys/class/drm'/path.rsplit('/', 1)[-1]/'device'
        record.mkdir(parents=True)
        (record/'vendor').write_text(vendor+'\n')

def native_nodes():
    return {str(path.relative_to(case/'dev')): {'mode': stat.S_IMODE(path.lstat().st_mode),
            'uid': path.lstat().st_uid, 'gid': path.lstat().st_gid, 'inode': path.lstat().st_ino}
            for path in (case/'dev').rglob('*')}

before = native_nodes()
for leaf in ['group', 'passwd', 'nsswitch.conf', 'os-release']:
    (case/'etc'/leaf).write_bytes((pathlib.Path('/etc')/leaf).read_bytes())
shutil.copytree('/etc/alternatives', case/'etc/alternatives', symlinks=True)
group_before = (case/'etc/group').read_bytes()
for origin, destination in [(case/'dev', '/dev'), (case/'sys', '/sys'), (case/'tmp', '/tmp'), (case/'etc', '/etc')]:
    subprocess.run(['mount', '--bind', str(origin), destination], check=True)
build = (source/'misc/build.func').read_text()
definitions = '\n'.join(function(build, method, '  ') for method in ['is_gpu_app', 'detect_gpu_devices', 'configure_gpu_passthrough'])
definitions += function(build, 'fix_gpu_gids')
definitions += function((source/'misc/tools.func').read_text(), '_setup_gpu_permissions')
config = case/'ct.conf'
config.write_text('hostname: fixture\n')
if name == 'existing-mappings':
    config.write_text('hostname: fixture\ndev4: /dev/unrelated,gid=77,mode=0640\n')
env = dict(os.environ, HOME=str(case/'home'), TMPDIR=str(case/'tmp'), TEST_CASE=str(case), TEST_SCENARIO=name,
           LXC_CONFIG=str(config), CTID='2000', CT_TYPE='1', ENABLE_GPU='yes', var_gpu='yes')
if name in {'effective-disable', 'cold-disabled'}:
    env['ENABLE_GPU'] = 'no'
header = definitions+r'''
STD=''
INFO='' TAB3=''
msg_info() { :; }
msg_ok() { :; }
msg_debug() { :; }
msg_custom() { :; }
msg_warn() { printf 'WARN %s\n' "$*" >&2; }
msg_error() { printf 'ERROR %s\n' "$*" >&2; }
lspci() { printf '%s\n' '0000:00:02.0 VGA controller: Intel [8086:0001]' '0000:01:00.0 VGA controller: AMD [1002:0001]' '0000:02:00.0 3D controller: NVIDIA [10de:0001]'; }
prompt_select() { printf 'INTEL\n'; }
getent() {
  case "$1 $2" in
    'group video') printf 'video:x:44:\n' ;;
    'group render') printf 'render:x:104:\n' ;;
    *) command getent "$@" ;;
  esac
}
usermod() {
  printf '%s\n' "usermod $*" >> "$TEST_CASE/actions.log"
  if [[ "$TEST_SCENARIO" == membership-error ]]; then return 17; fi
}
adduser() { printf '%s\n' "adduser $*" >> "$TEST_CASE/actions.log"; }
vainfo() { return 0; }
nvidia-smi() { return 0; }
pct() {
  printf '%s\n' "pct $*" >> "$TEST_CASE/actions.log"
  case "$1" in
    stop) return 0 ;;
    start) [[ "$TEST_SCENARIO" != restart-error ]] || return 17 ;;
    status) [[ "$TEST_SCENARIO" != restart-not-running ]] && printf 'status: running\n' || printf 'status: stopped\n' ;;
    push) cp -- "$3" "$4" ;;
    set)
      python3 - "$LXC_CONFIG" "${3#--}" "$4" << 'CONFIG'
import pathlib,sys
path,key,value=pathlib.Path(sys.argv[1]),sys.argv[2],sys.argv[3]
lines=path.read_text().splitlines()
assert sum(line.startswith(key+': ') for line in lines)==1
path.write_text('\n'.join(key+': '+value if line.startswith(key+': ') else line for line in lines)+'\n')
CONFIG
      ;;
    exec)
      shift 3
      if [[ "$1" == groupadd ]]; then
        [[ "$TEST_SCENARIO" != gid-create-error ]] || return 17
        printf 'created\n' > "$TEST_CASE/group-created"
      elif [[ "$*" == *getent* ]]; then
        [[ "$TEST_SCENARIO" != gid-read-error ]] || return 17
        if [[ "$*" == *render* && ("$TEST_SCENARIO" == gid-missing-group || "$TEST_SCENARIO" == gid-create-error) && ! -e "$TEST_CASE/group-created" ]]; then return 2; fi
        if [[ "$TEST_SCENARIO" == gid-valid-output-error ]]; then
          getent "${@:2}"; return 17
        fi
        if [[ "$TEST_SCENARIO" == gid-malformed-record ]]; then
          printf 'video:x:invalid:\n'; return 0
        fi
        if [[ "$1" == getent ]]; then
          getent "${@:2}"
        else
          [[ "$*" == *video* ]] && printf '44\n' || printf '104\n'
        fi
      elif [[ "$1" == chmod ]]; then command "$@"; fi
      ;;
  esac
}
'''
expression = 'configure_gpu_passthrough; printf "%s\\n" "${GPU_TYPE:-}" > "$TEST_CASE/types.txt"'
if name in {'mixed-detection', 'regular-node-rejection', 'shared-only-rejection'}:
    expression = 'detect_gpu_devices; declare -p INTEL_DEVICES AMD_DEVICES NVIDIA_DEVICES > "$TEST_CASE/devices.txt"'
elif name in {'mapping-gids', 'gid-read-error', 'restart-error', 'restart-not-running',
              'gid-missing-group', 'gid-create-error', 'gid-valid-output-error', 'gid-malformed-record'}:
    config.write_text('hostname: fixture\ndev0: /dev/dri/card0,gid=9\ndev1: /dev/dri/renderD128,gid=9\ndev2: /dev/kfd,gid=9\ndev3: /dev/nvidia1,gid=9\ndev4: /dev/unrelated,gid=77,mode=0640\n')
    env['GPU_TYPE'] = 'INTEL AMD NVIDIA'
    env['CT_TYPE'] = '0'
    expression = 'if fix_gpu_gids; then exit 0; else exit $?; fi' if name == 'gid-valid-output-error' else 'fix_gpu_gids'
elif name in {'permission-ownership', 'membership-error'}:
    expression = '_setup_gpu_permissions 0 root'
elif name.startswith('cold-'):
    handler = functools.partial(http.server.SimpleHTTPRequestHandler, directory=str(source))
    server = http.server.ThreadingHTTPServer(('127.0.0.1', 0), handler)
    thread = threading.Thread(target=server.serve_forever, daemon=True)
    thread.start()
    env.update(REPO_BASE='http://127.0.0.1:'+str(server.server_port), APP='GPU Fixture', NSAPP='gpu-fixture',
               SESSION_ID='gpu-fixture-'+str(os.getpid()), GPU_TYPE='AMD NVIDIA', INSTALL_NVIDIA_DRIVERS='no',
               var_lxc_test_output=str(case/'context.txt'))
    header += 'source '+shlex.quote(str(source/'misc/bundle.func'))+'\n'+r'''
context_probe() {
  printf '%s\n' "${ENABLE_GPU-unset}" "${GPU_TYPE-unset}" "${INSTALL_NVIDIA_DRIVERS-unset}" "${CTTYPE-unset}" > "$var_lxc_test_output"
}
'''
    expression = 'build_bundle update context_probe "$TEST_CASE/cold-bundle.sh" 0700 context_probe; env -i PATH="$PATH" HOME="$HOME" TERM=dumb bash "$TEST_CASE/cold-bundle.sh"'
input_stream = open('/dev/tty') if name == 'repeated-selection' else None
try:
    completed = subprocess.run(['bash', '-c', header+'\nset -e\n'+expression], stdin=input_stream,
                               env=env, capture_output=True, text=True, timeout=20)
finally:
    if input_stream is not None:
        input_stream.close()
if name.startswith('cold-'):
    server.shutdown()
    thread.join()
checks = []
def check(label, expected, actual):
    checks.append({'name': label, 'expected': expected, 'actual': actual, 'passed': expected == actual})
check('native invocation status', 17 if name in {'gid-read-error', 'restart-error', 'gid-create-error', 'gid-valid-output-error'}
      else 1 if name in {'restart-not-running', 'gid-malformed-record'} else 0, completed.returncode)
lines = config.read_text().splitlines()
mapping = {line.split(': ', 1)[0]: line.split(': ', 1)[1] for line in lines if re.match(r'^dev\d+: ', line)}
paths = [value.split(',', 1)[0] for value in mapping.values()]
if name == 'effective-disable': check('effective request disables all mapping', [], paths)
elif name == 'mixed-detection':
    text = (case/'devices.txt').read_text()
    check('AMD owns its DRM nodes and KFD', True, all(path in text.split('AMD_DEVICES=')[1].split('\n')[0]
          for path in ['/dev/dri/card1', '/dev/dri/renderD129', '/dev/kfd']))
    check('Intel never claims AMD node', False, '/dev/dri/card1' in text.split('INTEL_DEVICES=')[1].split('\n')[0])
elif name in {'regular-node-rejection', 'shared-only-rejection'}:
    text = (case/'devices.txt').read_text()
    check('non-card/non-character objects are not GPU inventories', False, any(path in text for path in nodes))
elif name in {'mixed-unattended', 'nvidia-one', 'repeated-selection', 'existing-mappings'}:
    wanted = set(nodes) if name != 'repeated-selection' else {path for path in nodes if path.startswith('/dev/nvidia') and path != '/dev/nvidia0' or nodes[path] == '0x8086'}
    if name == 'existing-mappings': wanted.add('/dev/unrelated')
    check('exact independently selected node set', sorted(wanted), sorted(paths))
    check('each selected node mapped once', len(set(paths)), len(paths))
    if name == 'existing-mappings': check('unrelated existing device preserved', '/dev/unrelated,gid=77,mode=0640', mapping.get('dev4'))
elif name in {'mapping-gids', 'gid-missing-group'}:
    for key, gid in [('dev0', 44), ('dev1', 104), ('dev2', 104), ('dev3', 44)]:
        properties = dict(property.split('=', 1) for property in mapping[key].split(',')[1:])
        check(key+' uses guest-owned GID', str(gid), properties.get('gid'))
    check('unrelated properties preserved', '/dev/unrelated,gid=77,mode=0640', mapping['dev4'])
    actions = (case/'actions.log').read_text()
    check('mapping owner never asks guest to mutate device inodes', False, 'chgrp' in actions or 'chmod 660' in actions)
    if name == 'gid-missing-group':
        check('missing group created through guest owner', True, 'groupadd --system render' in actions)
elif name == 'membership-error': check('membership failure is reported', True, 'WARN' in completed.stderr)
elif name.startswith('cold-'):
    check('actual cold hook consumes exact host GPU context', ['no' if name == 'cold-disabled' else 'yes', 'AMD NVIDIA', 'no', '1'],
          (case/'context.txt').read_text().splitlines() if (case/'context.txt').exists() else [])
if name in {'permission-ownership', 'mapping-gids', 'gid-missing-group', 'membership-error'}:
    check('shared backing node metadata never mutated', before, native_nodes())
    check('guest group file never rewritten directly', hashlib.sha256(group_before).hexdigest(), hashlib.sha256((case/'etc/group').read_bytes()).hexdigest())
if name in {'restart-error', 'restart-not-running'}:
    actions = (case/'actions.log').read_text()
    check('named start fault/state actually reached', True, 'pct start 2000' in actions)
    if name == 'restart-not-running':
        check('actual post-start state checked', True, 'pct status 2000' in actions)
if name in {'gid-create-error', 'gid-valid-output-error', 'gid-malformed-record'}:
    check('invalid/failed GID preparation does not stop the guest', False, 'pct stop' in (case/'actions.log').read_text())
    check('invalid/failed GID preparation preserves mapping', '/dev/dri/card0,gid=9', mapping['dev0'])
document = {'case': name, 'status': 'PASS' if all(row['passed'] for row in checks) else 'FAIL',
            'native_status': completed.returncode, 'checks': checks, 'config': config.read_text(),
            'stdout': completed.stdout, 'stderr': completed.stderr,
            'actions': (case/'actions.log').read_text() if (case/'actions.log').exists() else ''}
(case/'result.json').write_text(json.dumps(document, indent=2)+'\n')
raise SystemExit(0 if document['status'] == 'PASS' else 2)
PY
