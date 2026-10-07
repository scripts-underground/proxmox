#!/usr/bin/env bash
# Actual Filebrowser hook outcomes. Run only through the protected VM supervisor.
set -euo pipefail
[[ $# == 2 || $# == 4 ]] || {
  printf 'Usage: %s SESSION MANIFEST_SHA [SCENARIO CASE]\n' "$0" >&2
  exit 64
}
systemd-detect-virt --vm -q || exit 77
exec python3 - "$0" "$@" << 'PY'
import hashlib
import json
import os
import pathlib
import shlex
import subprocess
import sys
import tarfile

script, session, pinned = pathlib.Path(sys.argv[1]).resolve(), pathlib.Path(sys.argv[2]), sys.argv[3]
assert os.geteuid() == 0
assert pathlib.Path('/sys/class/dmi/id/product_uuid').read_text().strip().lower() == '842ad04b-e0af-4a06-b1e1-fd4acd54a592'
assert os.environ['SU_JOB_PRIVATE_PIDNS'] == os.readlink('/proc/self/ns/pid')
raw = (session / 'manifest.json').read_bytes()
assert hashlib.sha256(raw).hexdigest() == pinned
manifest = json.loads(raw)
assert script == session / 'harness/tests/filebrowser-deployment-safety.test.sh'
assert hashlib.sha256(script.read_bytes()).hexdigest() == next(e['sha256'] for e in manifest['harness']['inventory'] if e['path'] == 'tests/filebrowser-deployment-safety.test.sh')
scenarios = ['success', 'mode-755', 'custom-path', 'binary-failure-retry', 'marker-failure-rollback', 'checker-error',
             'mode-recovery-default', 'historical-default', 'invalid-mode']
if len(sys.argv) == 4:
    parent = session / 'cases'
    parent.mkdir(mode=0o700)
    results = []
    for scenario in scenarios:
        case = parent / ('filebrowser-' + scenario)
        case.mkdir(mode=0o700)
        process = subprocess.run(['unshare', '--mount', '--propagation', 'private', 'bash', str(script), str(session), pinned, scenario, str(case)], capture_output=True, text=True)
        (case / 'stdout.log').write_text(process.stdout)
        (case / 'stderr.log').write_text(process.stderr)
        result = json.loads((case / 'result.json').read_bytes()) if (case / 'result.json').exists() else {'error': process.stderr}
        results.append({'scenario': scenario, 'process_status': process.returncode, 'result': result})
        print(('PASS' if process.returncode == 0 else 'FAIL') + ' filebrowser/' + scenario, flush=True)
    result = {'status': 'PASS' if all(r['process_status'] == 0 for r in results) else 'FAIL', 'manifest_sha256': pinned, 'results': results}
    (session / 'filebrowser-results.json').write_text(json.dumps(result, indent=2) + '\n')
    raise SystemExit(0 if result['status'] == 'PASS' else 1)

scenario, case = sys.argv[4], pathlib.Path(sys.argv[5])
assert scenario in scenarios and case.parent == session / 'cases'
work = pathlib.Path(os.environ['SU_CONTAINMENT_WORK'])
for name in ['lib', 'opt', 'local-bin', 'home', 'archive', 'data']:
    (case / name).mkdir(mode=0o700)
(case / 'lib/dpkg').mkdir()
(case / 'lib/dpkg/status').write_bytes(pathlib.Path('/var/lib/dpkg/status').read_bytes())
for name, destination, inherited_name in [('lib', '/var/lib', 'var-lib'), ('opt', '/opt', 'opt'), ('local-bin', '/usr/local/bin', 'local-bin')]:
    inherited = work / 'private' / inherited_name
    actual = pathlib.Path(destination)
    assert (inherited.stat().st_dev, inherited.stat().st_ino) == (actual.stat().st_dev, actual.stat().st_ino)
    subprocess.run(['umount', '--recursive', '--', destination], check=True)
    subprocess.run(['mount', '--no-mtab', '--bind', str(case / name), destination], check=True)
binary_name = 'custom-filebrowser' if scenario == 'custom-path' else 'filebrowser'
binary = pathlib.Path('/usr/local/bin') / binary_name
old_bytes = b'#!/usr/bin/env bash\nprintf "File Browser v1.0.0\\n"\n'
new_bytes = b'#!/usr/bin/env bash\nprintf "File Browser v2.0.0\\n"\n'
binary.write_bytes(old_bytes)
binary.chmod(0o640 if scenario in {'mode-755', 'marker-failure-rollback', 'mode-recovery-default', 'historical-default', 'invalid-mode'} else 0o755)
old_mode = binary.stat().st_mode & 0o7777
sibling = pathlib.Path('/usr/local/bin/unrelated-tool')
sibling.write_bytes(b'unrelated bytes\n')
sibling.chmod(0o751)
marker = case / 'home/.filebrowser'
marker.write_bytes(b'1.0.0\n')
db = case / 'data/filebrowser.db'
db.write_bytes(b'protected database fixture\n')
(case / 'archive/filebrowser').write_bytes(new_bytes)
(case / 'archive/filebrowser').chmod(0o644)
(case / 'archive/LICENSE').write_bytes(b'archive-only license\n')
tools = session / 'source/misc/tools.func'
common = session / 'harness/tests/lib/safety-gap-common.sh'
env = dict(os.environ, HOME=str(marker.parent), TMPDIR='/tmp', SG_CASE=str(case), SG_SOURCE=str(session / 'source'),
           SG_TOOLS=str(tools), SG_HARNESS=str(session / 'harness'), SG_REVIEW_SUPPORT=str(session / 'support'),
           SG_ID='filebrowser', SG_SCENARIO=scenario, SG_OBSERVE_ACTIVE='0', SG_APP='filebrowser',
           SG_ROUTES=str(case / 'routes.json'), SG_REQUESTS=str(case / 'requests.jsonl'), SG_DISPATCH_ERRORS=str(case / 'dispatch-errors.jsonl'),
           var_addon_bin_path=str(binary), var_addon_db_dir=str(db.parent), var_addon_db_path=str(db),
           var_addon_dist_path='/opt/filebrowser-dist', INIT_SYSTEM='systemd', OS_FAMILY='debian')
env['H_PUBLISHED_BYTES'] = str(case / 'published-before-marker-failure')
for name in ['requests.jsonl', 'dispatch-errors.jsonl', 'fault-events.jsonl']:
    (case / name).write_bytes(b'')
header = 'source ' + shlex.quote(str(tools)) + '\nsource ' + shlex.quote(str(common)) + r'''
STD=''
msg_info() { printf 'INFO %s\n' "$*"; }
msg_ok() { printf 'OK %s\n' "$*"; }
msg_warn() { printf 'WARN %s\n' "$*" >&2; }
msg_error() { printf 'ERROR %s\n' "$*" >&2; }
getent() { printf '127.0.0.1 deterministic-fixture\n'; }
curl() { sg_dispatch_curl "$@"; }
'''
arch = subprocess.run(['bash', '-c', header + '\nget_system_arch uname'], env=env, capture_output=True, text=True, check=True).stdout.strip()
assert arch in {'amd64', 'arm64', 'x86_64', 'aarch64'}
archive = case / ('linux-' + arch + '-filebrowser.tar.gz')
with tarfile.open(archive, 'w:gz') as stream:
    for p in (case / 'archive').iterdir(): stream.add(p, arcname=p.name)
url = 'https://github.com/filebrowser/filebrowser/releases/download/v2.0.0/' + archive.name
release = {'tag_name': 'v2.0.0', 'draft': False, 'prerelease': False, 'assets': [{'name': archive.name, 'browser_download_url': url}]}
(case / 'routes.json').write_text(json.dumps({'https://api.github.com/repos/filebrowser/filebrowser/releases/latest': {'json': release}, url: {'file': str(archive)}}) + '\n')
raw_script = (session / 'source/scripts/addon/filebrowser.sh').read_text()
definitions = case / 'definitions.sh'
definitions.write_text(raw_script[:raw_script.index('\n# Addons run inside arbitrary containers')] + '\n')
body = header + '\nsource ' + shlex.quote(str(definitions)) + '\n'
if scenario == 'checker-error': body += 'getent() { sg_review_fault actual-filebrowser-dns getent "$@" status=17; return 17; }\n'
if scenario == 'marker-failure-rollback':
    body += r'''
mv() {
  command mv "$@" || return "$?"
  if [[ "${*: -1}" == "$var_addon_bin_path" && "${*: -2:1}" == */publish ]]; then
    command cp "$var_addon_bin_path" "$H_PUBLISHED_BYTES" || return "$?"
    sg_review_fault actual-final-binary-published mv "$@" status=0
  fi
}
'''
body += 'set -e\nif update_script; then result=0; else result=$?; fi\nexit "$result"\n'
def update(label):
    p = subprocess.run(['bash', '-c', body], env=dict(env, SG_INVOCATION=label), capture_output=True, text=True)
    (case / (label + '-stdout.log')).write_text(p.stdout)
    (case / (label + '-stderr.log')).write_text(p.stderr)
    return p.returncode
def direct(label, expression, extra=''):
    p = subprocess.run(['bash', '-c', header + '\n' + extra + '\n' + expression], env=dict(env, SG_INVOCATION=label), capture_output=True, text=True)
    (case / (label + '-stdout.log')).write_text(p.stdout)
    (case / (label + '-stderr.log')).write_text(p.stderr)
    return p.returncode
prepared = case / 'prepared'
prepared.mkdir()
(prepared / binary_name).write_bytes(new_bytes)
(prepared / binary_name).chmod(0o644)
def request(version, mode=None):
    args = ['_release_transaction', 'prepared-tree', str(prepared), '', 'tree', '/usr/local/bin', str(marker), version, '0', '1']
    if mode is not None: args.append(mode)
    return shlex.join(args)
checks = {}
if scenario == 'mode-recovery-default':
    fault = r'''
mv() {
  command mv "$@" || return "$?"
  if [[ "${*: -1}" == "$var_addon_bin_path" && "${*: -2:1}" == */publish ]]; then
    sg_review_fault mode-publication-then-error mv "$@" status=17
    return 17
  fi
}
cp() {
  if [[ "${*: -1}" == */.release-restore.*/restore ]]; then
    sg_review_fault mode-original-copy-error cp "$@" status=17
    return 17
  fi
  command cp "$@"
}
'''
    status = direct('unfinished-mode', request('2.0.0', '755'), fault)
    records = list((case / 'lib/scripts-underground/release-deploy').glob('txn-*/state.json'))
    checks.update({'mode-bearing_failure_observed': status != 0, 'unfinished_mode_record': len(records) == 1 and json.loads(records[0].read_bytes())['state'] == 'RECOVERY_REQUIRED',
                   'published_requested_mode': binary.read_bytes() == new_bytes and binary.stat().st_mode & 0o7777 == 0o755})
    status = direct('recover-and-preserve-default', request('3.0.0'))
    checks.update({'subsequent_request_succeeded': status == 0, 'recovery_does_not_leak_mode_override': binary.stat().st_mode & 0o7777 == old_mode,
                   'subsequent_payload_and_marker': binary.read_bytes() == new_bytes and marker.read_bytes() == b'3.0.0\n'})
elif scenario == 'historical-default':
    starting = 'source ' + shlex.quote(str(session / 'starting-tools.func'))
    status = direct('historical', request('2.0.0'), starting)
    records = list((case / 'lib/scripts-underground/release-deploy').glob('txn-*/manifest.json'))
    checks.update({'genuine_historical_record': status == 0 and len(records) == 1 and 'publish_mode' not in json.loads(records[0].read_bytes())})
    status = direct('current-after-historical', request('3.0.0'))
    checks.update({'historical_default_accepted': status == 0 and marker.read_bytes() == b'3.0.0\n',
                   'historical_default_preserves_mode': binary.stat().st_mode & 0o7777 == old_mode})
elif scenario == 'invalid-mode':
    status = direct('invalid-request', request('2.0.0', 'bad-mode'))
    checks['invalid_request_refuses_without_mutation'] = status == 65 and binary.read_bytes() == old_bytes and marker.read_bytes() == b'1.0.0\n'
    status = direct('valid-mode-record', request('2.0.0', '755'))
    records = list((case / 'lib/scripts-underground/release-deploy').glob('txn-*/manifest.json'))
    checks['valid_mode_record_created'] = status == 0 and len(records) == 1
    record = records[0]
    saved = record.read_bytes()
    for invalid in ['bad-mode', '700']:
        document = json.loads(saved)
        document['publish_mode'] = invalid
        record.write_text(json.dumps(document) + '\n')
        status = direct('invalid-record-' + invalid, request('3.0.0'))
        checks['invalid_record_refuses_' + invalid] = status == 252 and binary.read_bytes() == new_bytes and marker.read_bytes() == b'2.0.0\n'
    record.write_bytes(saved)
elif scenario == 'binary-failure-retry':
    subprocess.run(['mount', '--no-mtab', '-o', 'remount,bind,ro', '/usr/local/bin'], check=True)
    status = update('failed')
    checks.update({'failed_install_returns_error': status != 0, 'failed_install_preserves_marker': marker.read_bytes() == b'1.0.0\n',
                   'failed_install_preserves_binary': binary.read_bytes() == old_bytes and binary.stat().st_mode & 0o7777 == old_mode})
    subprocess.run(['mount', '--no-mtab', '-o', 'remount,bind,rw', '/usr/local/bin'], check=True)
    retry = update('retry')
    checks['retry_installs_version'] = retry == 0 and binary.read_bytes() == new_bytes and marker.read_bytes() == b'2.0.0\n'
elif scenario == 'marker-failure-rollback':
    subprocess.run(['mount', '--no-mtab', '--bind', str(marker.parent), str(marker.parent)], check=True)
    subprocess.run(['mount', '--no-mtab', '-o', 'remount,bind,ro', str(marker.parent)], check=True)
    status = update('marker-failed')
    checks.update({'failed_marker_returns_error': status != 0, 'failed_marker_restores_binary': binary.read_bytes() == old_bytes,
                   'failed_marker_restores_original_mode': binary.stat().st_mode & 0o7777 == old_mode,
                   'failed_marker_keeps_old_version': marker.read_bytes() == b'1.0.0\n'})
    witness = pathlib.Path(env['H_PUBLISHED_BYTES'])
    checks['new_binary_was_published_before_rollback'] = witness.is_file() and witness.read_bytes() == new_bytes
elif scenario == 'checker-error':
    status = update('failed-check')
    checks.update({'checker_error_propagates': status == 6, 'checker_error_keeps_binary': binary.read_bytes() == old_bytes,
                   'checker_error_keeps_marker': marker.read_bytes() == b'1.0.0\n'})
else:
    status = update('success')
    checks.update({'update_succeeded': status == 0, 'actual_final_binary': binary.read_bytes() == new_bytes,
                   'actual_final_marker': marker.read_bytes() == b'2.0.0\n', 'executable_mode_755': binary.stat().st_mode & 0o7777 == 0o755,
                   'license_not_published_to_binary_directory': not pathlib.Path('/usr/local/bin/LICENSE').exists()})
    if binary.read_bytes() == new_bytes and os.access(binary, os.X_OK):
        version = subprocess.run([str(binary), '--version'], capture_output=True, text=True, check=True).stdout
        checks['consumer_executes_new_binary'] = version == 'File Browser v2.0.0\n'
checks['database_preserved'] = db.read_bytes() == b'protected database fixture\n'
checks['unrelated_binary_preserved'] = sibling.read_bytes() == b'unrelated bytes\n' and sibling.stat().st_mode & 0o7777 == 0o751
result = {'status': status, 'checks': checks, 'binary_mode': oct(binary.stat().st_mode & 0o7777), 'marker': marker.read_text()}
(case / 'result.json').write_text(json.dumps(result, indent=2) + '\n')
raise SystemExit(0 if all(checks.values()) else 1)
PY
