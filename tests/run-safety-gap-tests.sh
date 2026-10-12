#!/usr/bin/env bash
# Aggregate observer. All execution/fixture writes require the private guest guard.
set -euo pipefail
ROOT=$(realpath "$(dirname "${BASH_SOURCE[0]}")/..")
exec python3 - "$ROOT" "$@" << 'PY'
import argparse
import hashlib
import json
import os
import pathlib
import signal
import socket
import stat
import subprocess
import sys
import time
import uuid
from datetime import datetime, timezone

harness = pathlib.Path(sys.argv[1]).resolve()
parser = argparse.ArgumentParser()
parser.add_argument('--source-root', required=True)
parser.add_argument('--source-manifest', required=True)
parser.add_argument('--source-manifest-sha256', required=True)
parser.add_argument('--source-role', required=True, choices=['baseline', 'starting', 'candidate'])
parser.add_argument('--case-set', choices=['original', 'corrections', 'review', 'all', 'hardening'], default='original')
parser.add_argument('--original-evidence-index')
parser.add_argument('--original-evidence-index-sha256')
parser.add_argument('--only', help='exact bounded subset, comma-separated declared case IDs')
parser.add_argument('--capability-probe', action='store_true')
parser.add_argument('--session', required=True)
parser.add_argument('--guest-id', required=True)
parser.add_argument('--baseline-tools', required=True)
parser.add_argument('--results', required=True)
parser.add_argument('--suite', choices=['romm-repair', 'codeberg-deployment', 'uv-selection', 'codeberg-pins', 'live-cleanup', 'release-transaction', 'review-gaps'])
args = parser.parse_args(sys.argv[2:])
if args.only is not None and (args.suite or args.capability_probe):
    parser.error('--only cannot be combined with --suite or --capability-probe')
source = pathlib.Path(args.source_root).resolve()
manifest_path = pathlib.Path(args.source_manifest)
session = pathlib.Path(args.session)
receipt_path = pathlib.Path(args.guest_id)
legacy = pathlib.Path(args.baseline_tools)
results_path = pathlib.Path(args.results)

def git_blob(path):
    data = path.read_bytes()
    return hashlib.sha1(f'blob {len(data)}\0'.encode() + data).hexdigest()

def verify_inventory(root, inventory):
    expected = {entry['path']: entry for entry in inventory}
    actual = set()
    for directory, dirs, names in os.walk(root, followlinks=False):
        for name in list(dirs):
            path = pathlib.Path(directory) / name
            if path.is_symlink():
                names.append(name)
                dirs.remove(name)
        for name in names:
            path = pathlib.Path(directory) / name
            relative = str(path.relative_to(root))
            actual.add(relative)
            entry = expected[relative]
            data = os.fsencode(os.readlink(path)) if path.is_symlink() else path.read_bytes()
            mode = '120000' if path.is_symlink() else ('100755' if path.stat().st_mode & 0o111 else '100644')
            assert mode == entry['mode'], (relative, mode)
            assert hashlib.sha256(data).hexdigest() == entry['sha256'], relative
            assert hashlib.sha1(f'blob {len(data)}\0'.encode() + data).hexdigest() == entry['git_blob'], relative
    assert actual == set(expected), (actual - set(expected), set(expected) - actual)

try:
    assert os.geteuid() == 0
    assert subprocess.run(['systemd-detect-virt', '--vm', '-q']).returncode == 0
    assert session.is_dir() and session.parent == pathlib.Path('/var/tmp') and session.name.startswith('su-hardening-')
    assert session.resolve() == session and session.stat().st_uid == 0
    assert receipt_path.resolve().is_relative_to(session) and legacy.resolve().is_relative_to(session)
    assert results_path.parent.resolve().is_relative_to(session) and not results_path.exists()
    receipt = json.loads(receipt_path.read_text())
    assert receipt['session'] == str(session)
    assert receipt['domain_uuid'] == '842ad04b-e0af-4a06-b1e1-fd4acd54a592'
    assert receipt['hostname'] == socket.gethostname()
    assert receipt['dmi_uuid'].lower() == pathlib.Path('/sys/class/dmi/id/product_uuid').read_text().strip().lower()
    assert receipt['boot_id'] == pathlib.Path('/proc/sys/kernel/random/boot_id').read_text().strip()
    assert receipt['supervisor_mntns'] == os.readlink('/proc/self/ns/mnt')
    assert source.is_relative_to(session) and harness.is_relative_to(session) and source != harness
    assert manifest_path.resolve().is_relative_to(session)
    assert hashlib.sha256(manifest_path.read_bytes()).hexdigest() == args.source_manifest_sha256
    manifest = json.loads(manifest_path.read_text())
    assert manifest['source_role'] == args.source_role
    assert len(manifest['source']['tree']) == 40 and all(char in '0123456789abcdef' for char in manifest['source']['tree'])
    support = session / 'support'
    for item in manifest['support']:
        assert hashlib.sha256((support / item['path']).read_bytes()).hexdigest() == item['sha256']
    assert manifest['baseline_tree'] == '52879b35babd196e828c8c8404e9e015e1eb344e'
    if args.source_role == 'baseline':
        assert manifest['source']['tree'] == manifest['baseline_tree']
    if args.source_role == 'starting':
        assert manifest['source']['tree'] == manifest['starting_tree'] == '9ef2c5c8401bf158dcdc0866ab11f54ea9a97811'
    verify_inventory(source, manifest['source']['inventory'])
    verify_inventory(harness, manifest['harness']['inventory'])
    legacy_entry = manifest['historical']['inventory'][0]
    assert git_blob(legacy) == '823880c24ea300fcd78299d7839b96bb05da7e06'
    assert hashlib.sha256(legacy.read_bytes()).hexdigest() == legacy_entry['sha256']
except (AssertionError, OSError, ValueError, KeyError) as error:
    print(f'ERROR safety/identity/source guard: {error}', file=sys.stderr)
    raise SystemExit(2)

sys.path.insert(0, str(support))
from capacity import check as capacity_check
from review_oracle import strict_existing, review_cases
schedule = [
    ('romm-repair', 'romm-repair-preservation.test.sh', [f'R{i}' for i in range(1, 6)]),
    ('codeberg-deployment', 'codeberg-deployment-safety.test.sh', [f'C{i}' for i in range(1, 8)]),
    ('uv-selection', 'uv-selection-edge-cases.test.sh', [f'U{i}' for i in range(1, 9)]),
    ('codeberg-pins', 'codeberg-pin-compatibility.test.sh', [f'P{i}' for i in range(1, 5)]),
    ('live-cleanup', 'codeberg-test-cleanup.test.sh', ['L1', 'L2']),
]
comparisons = {'C3', 'C5', 'C6', 'P2', 'P3'}
if args.case_set in ('corrections', 'all'):
    schedule = [(suite, filename, [f'U{i}' for i in range(1, 13)] if suite == 'uv-selection' else identifiers)
                for suite, filename, identifiers in schedule]
    schedule = [(suite, filename, [f'P{i}' for i in range(1, 8)] if suite == 'codeberg-pins' else identifiers)
                for suite, filename, identifiers in schedule]
    schedule.append(('release-transaction', 'release-transaction-safety.test.sh', [f'J{i}' for i in range(1, 23)]))
if args.case_set == 'review':
    schedule = []
if args.case_set in ('review', 'all'):
    schedule.append(('review-gaps', 'review-gap-regressions.test.sh', [f'K{i}' for i in range(1, 16)]))
if args.case_set == 'hardening':
    schedule = [('hardening', 'shared-infrastructure-hardening.test.sh', [f'H{i}' for i in range(1, 18)])]
declared_ids = {identifier for _, _, identifiers in schedule for identifier in identifiers}
if args.only is not None:
    selected = args.only.split(',')
    if any(not identifier for identifier in selected) or len(selected) != len(set(selected)):
        parser.error('--only requires nonempty unique case IDs')
    if set(selected) - declared_ids:
        parser.error('--only contains undeclared IDs: ' + ','.join(sorted(set(selected) - declared_ids)))
    schedule = [(suite, filename, [identifier for identifier in identifiers if identifier in selected])
                for suite, filename, identifiers in schedule]
expected_schedule = [identifier for suite, _, identifiers in schedule
                     if not args.suite or args.suite == suite for identifier in identifiers]
if not args.capability_probe:
    assert manifest['invocation']['case_set'] == args.case_set
    assert manifest['invocation']['expected_ids'] == expected_schedule
    timing = manifest['invocation']['review_timing']
    assert timing['variant_work_seconds'] == timing['ordinary_worker_seconds'] == 120
    assert timing['finalization_grace_seconds'] == timing['group_overhead_seconds'] == 60 and timing['overall_seconds'] == 2700
    if args.case_set != 'hardening':
        assert manifest['invocation']['group_budgets_seconds'] == {
            identifier: 120 * len(timing['variants'][identifier]) + 60 for identifier in expected_schedule if identifier.startswith('K')}
    else:
        policy = manifest['invocation']['hardening_timing']
        assert policy['overall_seconds'] == 18000 and policy['outer_variant_count'] == 84
        if 'H17' in expected_schedule:
            assert args.original_evidence_index and args.original_evidence_index_sha256
            assert hashlib.sha256(pathlib.Path(args.original_evidence_index).read_bytes()).hexdigest() == args.original_evidence_index_sha256
capacity_check(session, 'before-run')
case_parent = session / 'cases'
case_parent.mkdir(exist_ok=True)
started = datetime.now(timezone.utc).isoformat()
cases = []
controls = []
overall_signal = None
def note_overall_signal(number, frame):
    global overall_signal
    if overall_signal is None:
        overall_signal = number
signal.signal(signal.SIGTERM, note_overall_signal)
signal.signal(signal.SIGINT, note_overall_signal)

def digest(data):
    return hashlib.sha256(data).hexdigest()

def observe(path):
    path = pathlib.Path(path)
    if not path.exists() and not path.is_symlink():
        return {'exists': False}
    info = path.lstat()
    value = {'exists': True, 'mode': stat.S_IMODE(info.st_mode), 'uid': info.st_uid, 'gid': info.st_gid}
    if path.is_symlink():
        value.update(kind='symlink', target=os.readlink(path))
        try:
            value['resolved'] = str(path.resolve())
        except (OSError, RuntimeError) as error:
            value['resolution_error'] = type(error).__name__
        if path.is_file():
            value['sha256'] = digest(path.read_bytes())
    elif path.is_file():
        value.update(kind='file', sha256=digest(path.read_bytes()), text=path.read_text(errors='replace'))
    elif path.is_dir():
        value.update(kind='directory', entries={str(child.relative_to(path)): observe(child) for child in sorted(path.rglob('*'))})
    return value

def load(path, default=None):
    return json.loads(path.read_text()) if path.exists() else default

def text(path, default=''):
    return path.read_text() if path.exists() else default

def running_group(pgid):
    members = []
    for entry in pathlib.Path('/proc').iterdir():
        if not entry.name.isdigit():
            continue
        try:
            fields = (entry / 'stat').read_text().rsplit(')', 1)[1].split()
            if int(fields[2]) == pgid and fields[0] != 'Z':
                members.append({'pid': int(entry.name), 'cmdline': (entry / 'cmdline').read_bytes().replace(b'\0', b' ').decode()})
        except (OSError, IndexError, ValueError):
            continue
    return members

def run_worker(case_id, filename, variant):
    worker_budget = manifest['invocation'].get('group_budgets_seconds', {}).get(case_id, 120)
    capacity_check(session, 'before-case-' + case_id + '-' + variant)
    root = case_parent / f'{case_id}-{variant}-{uuid.uuid4().hex[:12]}'
    root.mkdir(mode=0o700)
    stdout, stderr = root / 'stdout.log', root / 'stderr.log'
    command = ['unshare', '--mount', '--propagation', 'private', '--fork', 'bash',
               str(harness / 'tests' / filename), case_id, variant, str(session),
               str(receipt_path), str(legacy), str(root), str(source)]
    env = {'PATH': '/usr/local/bin:/usr/bin:/bin', 'HOME': str(root), 'LC_ALL': 'C'}
    env.update(SG_MANIFEST=str(manifest_path), SG_MANIFEST_SHA256=args.source_manifest_sha256,
                SG_HARNESS=str(harness), SG_SOURCE_ROLE=args.source_role, SG_REVIEW_SUPPORT=str(support))
    env.update({name:value for name,value in os.environ.items() if name.startswith('SU_')})
    begin = time.time()
    event = None
    error = None
    with stdout.open('w') as output, stderr.open('w') as errors:
        process = subprocess.Popen(command, env=env, stdout=output, stderr=errors, start_new_session=True)
        pgid = process.pid
        try:
            if case_id in ('CAP-INT', 'CAP-TERM'):
                deadline = time.monotonic() + 15
                while process.poll() is None and time.monotonic() < deadline:
                    if (root / 'barrier.json').exists():
                        event = load(root / 'barrier.json')
                        break
                    time.sleep(0.025)
                assert event is not None, 'capability foreground mutation barrier absent'
                assert event['pgid'] == pgid and os.getpgid(event['worker_pid']) == pgid
                assert str(root) in pathlib.Path(f"/proc/{event['worker_pid']}/cmdline").read_bytes().replace(b'\0', b' ').decode()
                assert (root / 'fs/target/value').read_text() == 'incoming\n'
                delivered = signal.SIGINT if case_id == 'CAP-INT' else signal.SIGTERM
                os.killpg(pgid, delivered)
                event['signal'] = delivered.name
                event['supervisor_confirmed_post_rename'] = True
                deadline = time.monotonic() + 15
                while running_group(pgid) and time.monotonic() < deadline:
                    if (root / 'rollback-started').exists():
                        # One repeated group delivery after the finalizer entered its ignore region.
                        os.killpg(pgid, delivered)
                        event['repeated_signal_during_rollback'] = delivered.name
                        break
                    time.sleep(0.025)
                process.wait(timeout=60)
            elif case_id in ('J13', 'J14', 'J15', 'J16'):
                deadline = time.monotonic() + 15
                while process.poll() is None and time.monotonic() < deadline:
                    if (root / 'barrier.json').exists():
                        event = load(root / 'barrier.json')
                        break
                    time.sleep(0.025)
                assert event is not None, 'transaction signal barrier absent'
                assert event['pgid'] == pgid and os.getpgid(event['worker_pid']) == pgid
                assert pathlib.Path(event['transaction']).is_relative_to(root / 'var-lib')
                assert pathlib.Path(event['target']).is_dir()
                event['observed_identity'] = pathlib.Path(f"/proc/{event['worker_pid']}/cmdline").read_bytes().replace(b'\0', b' ').decode()
                assert str(root) in event['observed_identity'] and filename in event['observed_identity']
                event['state_at_barrier'] = load(pathlib.Path(event['transaction']) / 'state.json')['state']
                event['payload_at_barrier'] = text(pathlib.Path(event['target']) / 'payload')
                event['marker_at_barrier'] = text(pathlib.Path(event['marker']))
                delivered = signal.SIGINT if case_id == 'J14' else signal.SIGTERM
                os.killpg(pgid, delivered)
                event['signal'] = delivered.name
                event['supervisor_confirmed_phase'] = True
                process.wait(timeout=60)
            elif case_id == 'C7':
                deadline = time.monotonic() + 10
                while process.poll() is None and time.monotonic() < deadline:
                    if (root / 'barrier.json').exists():
                        event = load(root / 'barrier.json')
                        break
                    time.sleep(0.025)
                if event is None:
                    error = 'signal barrier was not observed'
                else:
                    assert event['pgid'] == pgid and os.getpgid(event['worker_pid']) == pgid
                    if args.source_role == 'baseline':
                        previous = pathlib.Path(event['previous'])
                        assert previous.is_relative_to(root) and (previous / 'payload').is_file()
                        assert not pathlib.Path(event['target']).exists()
                    else:
                        transaction = pathlib.Path(event['transaction'])
                        assert transaction.is_relative_to(root / 'var-lib')
                        assert pathlib.Path(event['target']).is_dir()
                        assert pathlib.Path(event['old_payload_backup']).read_text() == 'old payload\n'
                        assert pathlib.Path(event['old_marker_backup']).read_text() == '1.0.0\n'
                        assert load(transaction / 'state.json')['state'] == 'APPLYING'
                    identity = pathlib.Path(f"/proc/{event['worker_pid']}/cmdline").read_bytes().replace(b'\0', b' ').decode()
                    assert str(root) in identity and filename in identity
                    event['observed_identity'] = identity
                    event['supervisor_confirmed_post_rename'] = True
                    os.killpg(pgid, signal.SIGTERM)
                    event['signal'] = 'SIGTERM'
                process.wait(timeout=60)
            else:
                deadline = time.monotonic() + worker_budget
                while process.poll() is None and time.monotonic() < deadline and overall_signal is None:
                    time.sleep(0.025)
                if process.poll() is None:
                    raise subprocess.TimeoutExpired(command, worker_budget)
        except subprocess.TimeoutExpired:
            error = 'worker timed out before completed observation'
        except (AssertionError, OSError, ValueError) as failure:
            error = f'supervision/identity failure: {failure}'
        if process.poll() is None:
            # Only the process group created above; never a named/global process kill.
            if os.getpgid(process.pid) != pgid:
                raise RuntimeError('refusing to signal a changed process group')
            os.killpg(pgid, signal.SIGTERM)
            try:
                process.wait(timeout=10)
            except subprocess.TimeoutExpired:
                error = 'owned worker did not exit after bounded SIGTERM'
        deadline = time.monotonic() + 60
        while running_group(pgid) and time.monotonic() < deadline:
            time.sleep(0.025)
        leftovers = running_group(pgid)
        if leftovers:
            error = f'leftover running owned workers: {leftovers}'
            os.killpg(pgid, signal.SIGTERM)
    context = load(root / 'worker-context.json', {})
    dispatch_errors = [json.loads(line) for line in text(root / 'dispatch-errors.jsonl').splitlines()]
    if dispatch_errors:
        error = 'fixture dispatcher observed unexpected routes'
    if 'command not found' in text(stderr):
        error = 'fixture environment did not supply a required command'
    if not context and process.returncode != 77:
        error = error or 'worker guard/context did not complete'
    actual_helper = legacy if variant == 'legacy' else source / 'misc/tools.func'
    result = {'case_root': str(root), 'variant': variant, 'command': command,
              'worker_pid': process.pid, 'pgid': pgid, 'process_status': process.returncode,
               'started_epoch': begin, 'ended_epoch': time.time(), 'context': context,
               'work_budget_seconds': worker_budget,
              'source_under_test': {'path': str(actual_helper), 'git_blob': git_blob(actual_helper),
                                    'sha256': digest(actual_helper.read_bytes())},
              'stdout_path': str(stdout), 'stderr_path': str(stderr),
              'before_path': str(root / 'before.json'), 'after_path': str(root / 'after.json'),
              'requests_path': str(root / 'requests.jsonl'), 'dispatch_errors': dispatch_errors,
              'barrier': event, 'leftover_workers': leftovers, 'observer_error': error,
              'before': load(root / 'before.json', {}), 'after': load(root / 'after.json', {})}
    (root / 'supervisor-observation.json').write_text(json.dumps(result, indent=2) + '\n')
    return result

def assess(case_id, observation):
    root = pathlib.Path(observation['case_root'])
    checks = []
    notes = {}
    def check(name, expected, actual):
        checks.append({'assertion': name, 'expected': expected, 'actual': actual, 'passed': expected == actual})
    if observation['process_status'] == 77:
        return 'BLOCKED', [{'assertion': 'required guest capability', 'expected': 'available', 'actual': 'exit 77', 'passed': False}], notes
    if observation['observer_error']:
        return 'ERROR', [{'assertion': 'completed valid fixture observation', 'expected': None,
                          'actual': observation['observer_error'], 'passed': False}], notes
    operation = int(text(root / 'operation-status.txt', str(observation['process_status'])).strip())
    before, after = observation['before'], observation['after']
    if case_id.startswith('H'):
        records = load(root / 'review-records.json')
        declared = manifest['invocation']['hardening_timing']['variants'][case_id]
        if not records or [r['variant'] for r in records] != declared:
            return 'ERROR', [], {'error': 'missing/duplicate hardening variants'}
        for record in records:
            fixture = pathlib.Path(record['root'])
            if record['child_status'] == 77:
                return 'BLOCKED', [], {'blocked': load(fixture / 'blocked.json')}
            evidence = load(fixture / 'evidence.json')
            if record['child_status'] != 0 or not evidence or evidence.get('observation_error'):
                return 'ERROR', [], {'error': evidence or record}
            if evidence['fault_required'] and not evidence['fault_events']:
                return 'ERROR', [], {'error': 'required fault was not delivered'}
            for contract in evidence['contracts']:
                check(record['variant'] + ': ' + contract['name'], contract['expected'], contract['actual'])
        return 'PASS' if checks and all(c['passed'] for c in checks) else 'FAIL', checks, {'case_kind': 'hardening', 'variants': records}
    elif case_id.startswith('K'):
        return review_cases(case_id, observation)
    elif case_id.startswith('J'):
        scenarios = load(root / 'scenarios.json', [])
        expected_count = {'J4': 2, 'J5': 2, 'J6': 4, 'J7': 2, 'J8': 2, 'J20': 5}.get(case_id, 1)
        if len(scenarios) != expected_count:
            return 'ERROR', [{'assertion': 'all independently seeded scenarios completed', 'expected': expected_count,
                              'actual': len(scenarios), 'passed': False}], notes
        events = [json.loads(line) for line in text(root / 'events.jsonl').splitlines()]
        journals = []
        for scenario in scenarios:
            fixture = pathlib.Path(scenario['root'])
            assert fixture.is_relative_to(root / 'fs')
            before = load(fixture / 'before.json')
            after = load(fixture / 'after.json')
            operation = scenario['operation_status']
            prefix = scenario['variant'] + ': '
            check(prefix + 'canonical root identity retained', text(fixture / 'root-before.txt'), text(fixture / 'root-after.txt'))
            old_mounts = load(fixture / 'mounts-before.json')['filesystems']
            new_mounts = load(fixture / 'mounts-after.json')['filesystems']
            target = str(fixture / 'target')
            select_mounts = lambda table: [item for item in table if item['target'] == target or item['target'].startswith(target + '/')]
            check(prefix + 'root/descendant mount identities retained', select_mounts(old_mounts), select_mounts(new_mounts))
            check(prefix + 'external witness retained', before['outside'], after['outside'])
            entries = after['target'].get('entries', {})
            rejecting = case_id in {'J4', 'J5', 'J6', 'J7', 'J8', 'J20', 'J21'}
            rolling_back = case_id in {'J9', 'J10', 'J11', 'J13', 'J14', 'J15'}
            if rejecting or rolling_back:
                check(prefix + 'operation failed', True, operation != 0)
                check(prefix + 'original complete target retained/restored', before['target'], after['target'])
                check(prefix + 'original marker retained/restored', before['marker'], after['marker'])
            elif case_id == 'J22':
                check(prefix + 'conflicted operation failed', True, operation != 0)
                check(prefix + 'external live edit preserved', 'external live edit\n', entries.get('payload', {}).get('text'))
                check(prefix + 'old marker retained', before['marker'], after['marker'])
            else:
                check(prefix + 'deployment completed', 0 if case_id != 'J16' else 143, operation)
                check(prefix + 'new authentic payload consumed', 'incoming payload\n', entries.get('payload', {}).get('text'))
                if case_id not in {'J17', 'J18'}:
                    check(prefix + 'marker agrees with payload', '2.0.0\n', after['marker'].get('text'))
            if case_id == 'J1':
                check(prefix + 'root dotfile retained', before['target']['entries']['.root-dot'], entries.get('.root-dot'))
                check(prefix + 'root dot-directory retained', before['target']['entries']['.root-dot-dir'], entries.get('.root-dot-dir'))
                check(prefix + 'eligible nested pruning completed', False, any(name.startswith('obsolete') for name in entries))
                check(prefix + 'CLEAN retains receiving alias link text', 'chain', entries.get('alias', {}).get('target'))
                check(prefix + 'CLEAN retains intermediate alias dependency', before['target']['entries']['chain']['target'], entries.get('chain', {}).get('target'))
                check(prefix + 'CLEAN alias consumes published referent', digest(b'incoming alias referent\n'), entries.get('alias', {}).get('sha256'))
                for metadata in ('mode', 'uid', 'gid'):
                    check(prefix + 'existing leaf metadata retained: ' + metadata, before['target']['entries']['payload'][metadata], entries.get('payload', {}).get(metadata))
            if case_id in {'J2', 'J3', 'J4'}:
                check(prefix + 'mounted backing sentinel retained', before['backing']['entries']['witness'], after['backing']['entries'].get('witness'))
                if case_id == 'J2':
                    check(prefix + 'mount ancestor skeleton kept', True, entries.get('ancestor', {}).get('exists', False))
                    check(prefix + 'non-mounted sibling pruned', False, 'ancestor/obsolete' in entries)
                if case_id == 'J3':
                    check(prefix + 'addressed backing leaf updated', 'new addressed leaf\n', after['backing']['entries'].get('addressed', {}).get('text'))
            if case_id == 'J19':
                check(prefix + 'relative link installed as link', 'symlink', entries.get('relative-link', {}).get('kind'))
                check(prefix + 'relative link text retained', 'payload', entries.get('relative-link', {}).get('target'))
                check(prefix + 'relative link resolves planned payload', digest(b'incoming payload\n'), entries.get('relative-link', {}).get('sha256'))
                check(prefix + 'existing link receives incoming text', 'payload', entries.get('existing-link', {}).get('target'))
                check(prefix + 'existing link resolves incoming bytes', digest(b'incoming payload\n'), entries.get('existing-link', {}).get('sha256'))
                check(prefix + 'existing link owner retained', 65534, entries.get('existing-link', {}).get('uid'))
                check(prefix + 'trailing-newline filename published losslessly', 'newline payload\n', entries.get('line\nleaf\n', {}).get('text'))
                check(prefix + 'similarly spelled installed leaf untouched', before['target']['entries']['line\nleaf'], entries.get('line\nleaf'))
            if case_id == 'J12':
                first_states = load(fixture / 'first-journal-states.json')
                check(prefix + 'first failed operation observed', True, scenario['first_status'] != 0)
                check(prefix + 'first recovery required retained', True, 'RECOVERY_REQUIRED' in first_states.values())
                check(prefix + 'same-version retry completed after recovery', 0, scenario['retry_status'])
            if case_id == 'J18':
                check(prefix + 'failure path observed', True, scenario['retry_status'] != 0)
                check(prefix + 'caller trap definitions retained', text(fixture / 'traps-before.txt'), text(fixture / 'traps-after.txt'))
            if case_id == 'J21':
                store = fixture / 'capacity-store-evidence'
                previous = fixture / 'prior-store'
                for path in previous.rglob('*'):
                    if path.is_file():
                        copy = store / path.relative_to(previous)
                        check(prefix + 'previous record retained: ' + str(path.relative_to(previous)), observe(path), observe(copy))
                check(prefix + 'controlled capacity failure observed', True, 'No space left on device' in text(root / 'stderr.log') or 'insufficient' in text(root / 'stderr.log').lower())
            else:
                store = root / 'var-lib/scripts-underground/release-deploy'
            for transaction in sorted(store.glob('txn-*')):
                if transaction in journals:
                    continue
                journals.append(transaction)
                state = load(transaction / 'state.json')['state']
                # Exact per-invocation decision checks are added by strict_existing.
                plan = load(transaction / 'plan.json', [])
                mutated = False
                for entry in plan:
                    op = load(transaction / f'operations/{entry["id"]}.json', {})
                    if op.get('state') not in {None, 'PREPARED'}:
                        mutated = True
                    original = transaction / f'entries/{entry["id"]}/original'
                    if original.is_file() and entry['before']['kind'] == 'file' and op:
                        check('retained original matches planned hash ' + transaction.name + '/' + str(entry['id']), entry['before']['sha256'], digest(original.read_bytes()))
                    elif entry['before']['kind'] == 'file' and op.get('state') not in {None, 'PREPARED'}:
                        check('required applied original retained ' + transaction.name + '/' + str(entry['id']), True, False)
                if case_id == 'J22':
                    check('conflicted journal recovery required', 'RECOVERY_REQUIRED', state)
                if case_id == 'J11':
                    check('failed commit never marked committed', False, state == 'COMMITTED')
                if case_id == 'J12':
                    check('retry resolved prior recovery record', False, state == 'RECOVERY_REQUIRED')
                check('disposable extraction removed ' + transaction.name, False, (transaction / 'staging').exists())
            leftovers = list((fixture / 'target').rglob('.release-*'))
            if case_id != 'J22':
                check(prefix + 'no live publication/restore temporaries leaked', [], [str(path) for path in leftovers])
            if case_id in {'J8', 'J9', 'J10', 'J11', 'J12', 'J22'}:
                faults = [event for event in events if event['scenario'] == scenario['variant'] and event['fault']]
                if not faults:
                    return 'ERROR', [{'assertion': 'real fault/operation event observed', 'expected': True, 'actual': False, 'passed': False}], notes
        if case_id in {'J13', 'J14', 'J15', 'J16'}:
            barrier = observation['barrier']
            check('owned signal phase/delivery/completion observed', True, bool(barrier and barrier.get('supervisor_confirmed_phase') and not observation['leftover_workers']))
            phase = {'J13': 'before-publication', 'J14': 'after-payload', 'J15': 'after-marker', 'J16': 'after-committed'}[case_id]
            check('intended genuine transaction signal phase', phase, barrier['phase'])
            if case_id == 'J16':
                check('authoritative committed state observed before signal', 'COMMITTED', barrier['state_at_barrier'])
        if case_id == 'J17':
            starts = [event for event in events if event['phase'] == 'mutation-start']
            ends = [event for event in events if event['phase'] == 'mutation-end']
            # State writers are separate untrapped pipeline children; the immutable
            # transaction state path, not their transient PID, binds each interval.
            call_statuses=[int(text(pathlib.Path(scenarios[0]['root'])/(name+'-status.txt'))) for name in ('one','two','three')]
            if (len(starts) != len(ends) or
                    len({event['destination'] for event in starts}) != len(starts) or
                    {event['destination'] for event in starts} != {event['destination'] for event in ends}):
                return 'ERROR', [{'assertion': 'all genuine serialized mutation boundaries observed',
                                  'expected': 'three unique matched transaction state paths',
                                  'actual': {'starts': starts, 'ends': ends}, 'passed': False}], notes
            intervals = sorted((event['time_ns'], next(item['time_ns'] for item in ends if item['destination'] == event['destination'])) for event in starts)
            check('three authentic concurrent call statuses',[0,0,0],call_statuses)
            check('three cooperating physical aliases completed', 3, len(intervals))
            check('cooperating mutation intervals serialized', True, bool(intervals) and all(intervals[i][1] <= intervals[i + 1][0] for i in range(len(intervals)-1)))
            for suffix in ('one', 'two', 'three'):
                check('cooperating consumer marker ' + suffix, '2.0.0\n', text(root / 'home' / ('.' + scenarios[0]['app'] + '-' + suffix)))
            notes['serialized_intervals'] = intervals
            notes['concurrent_call_statuses'] = call_statuses
        notes.update(journals=[str(path) for path in journals], operation_events=events,
                     applicability='guarded synthetic transaction fixtures; not full application installation')
    elif case_id.startswith('R'):
        if case_id == 'R5':
            requests = [json.loads(line) for line in text(root / 'requests.jsonl').splitlines()]
            archive_received = any(item['url'].endswith('/4.2.3.7z') and item['http_status'] == 200 for item in requests)
            extraction_observed = 'Failed to extract 7z archive' in text(root / 'stderr.log')
            if not archive_received or not extraction_observed:
                return 'ERROR', [{'assertion': 'corrupt-archive extraction trigger observed', 'expected': True,
                                  'actual': {'archive_received': archive_received, 'extraction_observed': extraction_observed},
                                  'passed': False}], notes
        physical = root / 'opt/romm'
        after = {'env': observe(physical / '.env'),
                 'emulator_custom': observe(physical / 'frontend/dist/assets/emulatorjs/custom/save.dat'),
                 'ruffle_custom': observe(physical / 'frontend/dist/assets/ruffle/custom/settings.json'),
                 'loader': observe(physical / 'frontend/dist/assets/emulatorjs/data/loader.js'),
                 'cores': observe(physical / 'frontend/dist/assets/emulatorjs/data/cores'),
                 'ruffle': observe(physical / 'frontend/dist/assets/ruffle/ruffle.js')}
        for name in ('romm', 'emulator', 'ruffle'):
            after[name + '_marker'] = observe(root / 'home' / ('.emulatorjs' if name == 'emulator' else '.' + name))
        check('repair process status', True, operation != 0 if case_id == 'R5' else operation == 0)
        for name in ('env', 'emulator_custom', 'ruffle_custom', 'romm_marker', 'emulator_marker', 'ruffle_marker'):
            check(f'{name} bytes/hash preserved', before.get(name), after.get(name))
        if case_id != 'R5':
            for name in ('loader', 'cores', 'ruffle'):
                check(f'{name} payload present', True, after[name].get('exists', False))
        if case_id == 'R1':
            check('healthy payload bytes unchanged', {key: before[key] for key in ('loader', 'cores', 'ruffle')},
                  {key: after[key] for key in ('loader', 'cores', 'ruffle')})
            check('healthy same-version player assets not fetched', [], text(root / 'requests.jsonl').splitlines())
        notes['applicability'] = 'actual same-version repair hook with synthetic non-hidden custom files; not gameplay/full upgrade'
    elif case_id.startswith('C'):
        target = root / 'fs/target'
        backing = root / 'fs/backing'
        if case_id == 'C7':
            after = {'target': observe(target)}
            marker_path = root / 'home' / f'.safety-{case_id.lower()}-{observation["variant"]}'
            after['marker'] = observe(marker_path)
            recoveries = {str(path): observe(path) for path in sorted((root / 'fs').glob('.codeberg-deploy.*/previous'))}
            entries = after['target'].get('entries', {})
            payload = entries.get('payload', {}).get('text')
            marker = after['marker'].get('text')
            coherent = (payload, marker) in [('old payload\n', '1.0.0\n'), ('incoming payload\n', '2.0.0\n')]
            check('signal barrier and child exit observed', True, bool(observation['barrier'] and observation['process_status'] is not None))
            check('canonical complete old/new payload with agreeing marker', True, coherent)
            if args.source_role == 'candidate':
                transaction = pathlib.Path(observation['barrier']['transaction'])
                check('caught interruption completed rollback', 'ROLLED_BACK', load(transaction / 'state.json')['state'])
                check('canonical root present at real publication barrier', True, observation['barrier']['canonical_root_present'])
                recoveries = {str(transaction): observe(transaction / 'entries')}
            notes.update(recovery_paths=recoveries, availability_failure=not coherent,
                         data_loss=not coherent and not any(value.get('entries', {}).get('payload', {}).get('text') == 'old payload\n' for value in recoveries.values()),
                         applicability='standalone helper SIGTERM at observed post-rename barrier; not SIGKILL/power loss/full caller')
        else:
            if not after or not (root / 'operation-status.txt').exists():
                return 'ERROR', [{'assertion': 'producer completion', 'expected': 'after snapshot and status', 'actual': operation, 'passed': False}], notes
            entries = after['target'].get('entries', {})
            marker = after['marker'].get('text')
            if case_id in ('C2', 'C4'):
                if not (root / 'fault-observed.txt').exists():
                    return 'ERROR', [{'assertion': 'scoped real fault exercised', 'expected': True, 'actual': False, 'passed': False}], notes
                check('fault returned failure', True, operation != 0)
                check('original target unchanged', before['target'], after['target'])
                check('original marker unchanged', before['marker'], after['marker'])
            else:
                check('deployment completed', 0, operation)
                check('new authentic marker', '2.0.0\n', marker)
                if case_id == 'C3':
                    check('absolute self-target symlink resolves incoming bytes', digest(b'incoming payload\n'), entries.get('alias', {}).get('sha256'))
                else:
                    check('new payload consumed', 'incoming payload\n', entries.get('payload', {}).get('text'))
                check('unrelated custom file retained', before['target']['entries']['custom'], entries.get('custom'))
                if case_id in ('C5', 'C6'):
                    old_witness = before['backing'].get('entries', {}).get('witness')
                    new_witness = after['backing'].get('entries', {}).get('witness')
                    check('actual mounted backing witness preserved', old_witness, new_witness)
                    notes.update(data_loss=old_witness != new_witness, safe_rejection=operation != 0 and old_witness == new_witness,
                                 applicability='custom synthetic bind-mounted target' if case_id == 'C5' else 'custom writable mounted descendant')
            notes['operation_status'] = operation
    elif case_id.startswith('U'):
        oracle = load(root / 'oracle.json')
        selected = text(root / 'consumer-version.txt').strip().removeprefix('uv ')
        cached = text(root / 'consumer-cache.txt').strip()
        requests = [json.loads(line) for line in text(root / 'requests.jsonl').splitlines()]
        downloads = [item['url'] for item in requests if '/releases/download/' in item['url']]
        expected_url = f'https://github.com/astral-sh/uv/releases/download/{oracle["expected"]}/uv-x86_64-unknown-linux-gnu.tar.gz'
        if case_id == 'U12':
            check('unsupported targeted parse maps to metadata error', 250, operation)
            check('distinct parser status', '2', text(root / 'parser-status.txt').strip())
            check('actionable required-version diagnostic', True, 'required-version' in text(root / 'stderr.log') and 'single-line' in text(root / 'stderr.log'))
            check('installed binary/cache retained', observation['before'], observation['after'])
            check('retained binary observed by consumer', '0.12.13', selected)
            check('retained cache observed by consumer', '0.12.13', cached)
            check('no latest/download substitute', [], requests)
        else:
            check('setup completes', 0, operation)
            check('installed fixture binary selects oracle version', oracle['expected'], selected)
            check('real cached version matches consumer', oracle['expected'], cached)
            check('numeric release download URL', True, bool(downloads) and all(url == expected_url for url in downloads))
        notes.update(oracle=oracle, download_urls=downloads, parser_value=text(root / 'parsed-project-pin.txt'),
                     applicability='conditional requirement-style override compatibility; current Endurain uses bare numeric spelling' if case_id == 'U8' else 'valid TOML configuration/override selection; fixture executable is not an actual resolver')
    elif case_id.startswith('P'):
        selected = text(root / 'selected-release.txt')
        desired = {'P1': (0, 'v1.0.0'), 'P2': (0, '1.0.0'), 'P3': (1, ''), 'P4': (0, 'version/2'),
                   'P5': (0, '1.0.0'), 'P6': (22, ''), 'P7': (250, '')}[case_id]
        check('checker status', desired[0], operation)
        check('raw selection / stale clearing', desired[1], selected)
        if case_id in {'P3', 'P6', 'P7'}:
            check('installed marker retained', '1.0.0\n', after.get('marker', {}).get('text'))
        requests = [json.loads(line) for line in text(root / 'requests.jsonl').splitlines()]
        if case_id == 'P4':
            check('raw slash tag URL encoded', True, any('/tags/version%2F2' in item['url'] for item in requests))
        if case_id == 'P5':
            check('pin outside list page resolved by tag endpoint', True, bool(requests) and all('/tags/' in item['url'] for item in requests))
        if case_id == 'P6':
            lookups = load(root / 'lookup-results.json')
            check('auth/network operations retain original error and clear selection',
                  [{'failure': 'auth', 'operation_status': 22, 'selection': ''}, {'failure': 'network', 'operation_status': 22, 'selection': ''}], lookups)
            check('no alternate-tag retry on auth/network error', True, all(item['url'].endswith('/tags/1.0.0') for item in requests))
            check('recognized auth and incomplete-transfer events observed', ['auth', 'network'], sorted({item['recognized_error'] for item in requests}))
        if case_id == 'P7':
            check('pin mismatch has actionable metadata diagnostic', True, 'does not match requested pin' in text(root / 'stderr.log'))
        notes.update(operation_status=operation, selected_release=selected, applicability='numeric-v spelling compatibility' if case_id in ('P2', 'P3') else 'exact/raw tag selection')
    else:
        output = text(root / 'stdout.log')
        outcomes = [app for app in ('autocaliweb', 'endurain', 'forgejo', 'readeck') if f'PASS live install/update {app} (2.0.0)' in output]
        allocations = [json.loads(line) for line in text(root / 'live-allocations.jsonl').splitlines()]
        if not allocations or not allocations[0]['path'].startswith('/tmp/'):
            return 'ERROR', [{'assertion': 'external allocation observer', 'expected': 'identified child work path', 'actual': allocations, 'passed': False}], notes
        work_path = root / 'tmp' / allocations[0]['path'].removeprefix('/tmp/')
        check('allocation belongs to the observed existing-test child group', observation['pgid'], allocations[0]['caller_pgid'])
        check('existing live-test command identity observed', True, 'codeberg-release.test.sh --live' in allocations[0]['caller_cmdline'])
        check('expected existing-test child status', True, observation['process_status'] == 0 if case_id == 'L1' else observation['process_status'] != 0)
        check('actual live end-consumer assertions ran', ['autocaliweb', 'endurain', 'forgejo', 'readeck'] if case_id == 'L1' else ['autocaliweb'], outcomes)
        if case_id == 'L2':
            requests = [json.loads(line) for line in text(root / 'requests.jsonl').splitlines()]
            check('recognized metadata failure was observed', True, any(item.get('recognized_error') == 'recognized-metadata-failure-after-autocaliweb' for item in requests))
        check('child-owned work tree removed', False, work_path.exists())
        check('unrelated temporary sibling preserved', 'protected unrelated temporary sibling\n', text(root / 'tmp/protected-sibling'))
        notes.update(child_work_tree=str(work_path), retained_work_tree=observe(work_path), allocator_events=allocations,
                     trap_before=text(root / 'diagnostic-trap-before.txt'), trap_after=text(root / 'diagnostic-trap-after.txt'),
                     applicability='cleanup of unchanged existing live test; not proof this caused a prior disk-capacity incident')
    observation['observed_after'] = after
    if case_id.startswith(('R', 'U', 'P', 'L')) and observation['variant'] != 'legacy':
        from raw_outcomes import evaluate_raw
        raw_status, raw_checks, raw_notes = evaluate_raw(case_id, observation)
        checks.extend(raw_checks)
        notes['independent_raw'] = raw_notes
        if raw_status == 'ERROR':
            return 'ERROR', checks + [{'assertion': 'complete independent raw observation',
                                      'expected': None, 'actual': raw_notes.get('error'), 'passed': False}], notes
    if observation['variant'] != 'legacy' and case_id.startswith(('C', 'J')):
        stricter, evidence = strict_existing(case_id, root)
        checks.extend(stricter)
        notes['strict_evidence'] = evidence
    observation['after_path'] = str(root / 'observer-after.json')
    (root / 'observer-after.json').write_text(json.dumps({'after': after, 'notes': notes}, indent=2) + '\n')
    return ('PASS' if all(item['passed'] for item in checks) else 'FAIL'), checks, notes

if args.capability_probe:
    capabilities = []
    for identifier in ('CAP-PRIMITIVES', 'CAP-EXIT', 'CAP-INT', 'CAP-TERM'):
        observation = run_worker(identifier, 'release-transaction-safety.test.sh', 'current')
        root = pathlib.Path(observation['case_root'])
        evidence = load(root / 'capability-results.json', [])
        expected_names = {'CAP-PRIMITIVES': {'exact-leaf-rename', 'copy-metadata', 'copy-no-dereference',
                          'mountinfo-bind-origins', 'findmnt-explicit-fields', 'flock-serialization'},
                          'CAP-EXIT': {'exit-finalizer'}, 'CAP-INT': {'caught-int-finalizer'},
                          'CAP-TERM': {'caught-term-finalizer'}}[identifier]
        expected_owner_status = 130 if identifier == 'CAP-INT' else 143 if identifier == 'CAP-TERM' else 252
        valid = (not observation['observer_error'] and not observation['leftover_workers']
                 and observation['process_status'] is not None
                 and {entry['id'] for entry in evidence} == expected_names
                 and all(entry['status'] == 'PASS' for entry in evidence))
        if identifier == 'CAP-PRIMITIVES':
            valid = valid and observation['process_status'] == 0
        else:
            valid = valid and text(root / 'owner-status.txt').strip() == str(expected_owner_status)
        if identifier in ('CAP-INT', 'CAP-TERM'):
            valid = valid and bool(observation['barrier'] and observation['barrier'].get('repeated_signal_during_rollback'))
            valid = valid and (root / 'fs/target/value').read_text() == 'old\n'
        capabilities.append({'id': identifier, 'status': 'PASS' if valid else 'FAIL',
                             'controls': evidence, 'observation': observation})
        print(('PASS' if valid else 'FAIL') + ' ' + identifier, flush=True)
    result = {'schema_version': 2, 'kind': 'capabilities', 'source_tree': manifest['source']['tree'],
              'harness_tree': manifest['harness']['tree'], 'source_role': args.source_role,
              'manifest_sha256': args.source_manifest_sha256, 'session': str(session), 'guest': receipt,
              'capabilities': capabilities}
    results_path.write_text(json.dumps(result, indent=2) + '\n')
    raise SystemExit(0 if all(entry['status'] == 'PASS' for entry in capabilities) else 2)

# Sensitivity controls use actual synthetic files and the same witness comparator.
control_root = session / ('detector-controls-' + uuid.uuid4().hex[:12])
control_root.mkdir(mode=0o700)
for name, data in [('original', b'sentinel\n'), ('preserved', b'sentinel\n'), ('damaged', b'deliberately damaged\n')]:
    (control_root / name).write_bytes(data)
original, preserved, damaged = (observe(control_root / name) for name in ['original', 'preserved', 'damaged'])
controls.append({'id': 'HC-preserved-witness', 'status': 'PASS' if original == preserved else 'FAIL',
                 'evidence_root': str(control_root), 'expected': original, 'observed': preserved})
controls.append({'id': 'HC-damaged-witness-rejected', 'status': 'PASS' if original != damaged else 'FAIL',
                 'evidence_root': str(control_root), 'expected': original, 'observed': damaged})
for suite, filename, identifiers in schedule:
    if args.suite and args.suite != suite:
        continue
    for case_id in identifiers:
        if overall_signal is not None:
            break
        observation = run_worker(case_id, filename, 'current')
        try:
            status, checks, notes = assess(case_id, observation)
        except (OSError, KeyError, ValueError, TypeError) as error:
            status, checks, notes = 'ERROR', [{'assertion': 'observer completed', 'expected': 'valid complete witness', 'actual': str(error), 'passed': False}], {}
        result = {'id': case_id, 'suite': suite, 'status': status, 'assertions': checks, 'observation': observation, 'notes': notes}
        if case_id in comparisons:
            comparison = run_worker(case_id, filename, 'legacy')
            try:
                legacy_status, legacy_checks, legacy_notes = assess(case_id, comparison)
            except (OSError, KeyError, ValueError, TypeError) as error:
                legacy_status, legacy_checks, legacy_notes = 'ERROR', [], {'observer_error': str(error)}
            result['legacy'] = {'status': legacy_status, 'assertions': legacy_checks, 'observation': comparison, 'notes': legacy_notes}
            if legacy_status in ('ERROR', 'BLOCKED') and status not in ('ERROR', 'BLOCKED'):
                result['status'] = status = legacy_status
                result['assertions'].append({'assertion': 'required legacy compatibility control completed', 'expected': 'observed', 'actual': legacy_status, 'passed': False})
        cases.append(result)
        print(f'{status} {case_id} ({suite})', flush=True)
        (pathlib.Path(observation['case_root']) / 'result.json').write_text(json.dumps(result, indent=2) + '\n')
        partial = {'schema_version': 2, 'started': started, 'source_tree': manifest['source']['tree'],
                   'harness_tree': manifest['harness']['tree'], 'source_role': args.source_role,
                    'manifest_sha256': args.source_manifest_sha256, 'case_set': args.case_set,
                    'only': args.only, 'scheduled_ids': expected_schedule,
                   'baseline_commit': '008d5f5ff58e54a00bf1e97085dc86c68190ee2e', 'session': str(session), 'guest': receipt,
                   'cases': cases, 'controls': controls}
        results_path.write_text(json.dumps(partial, indent=2) + '\n')
    if overall_signal is not None:
        break

contexts_valid = all(case['observation']['context'].get('mntns') != receipt['supervisor_mntns'] and case['observation']['context'].get('pgid') == case['observation']['pgid'] for case in cases if case['status'] != 'BLOCKED')
controls.append({'id': 'HC-worker-identity-and-private-namespace', 'status': 'PASS' if contexts_valid else 'FAIL'})
review_groups = [case for case in cases if case['id'].startswith('K')]
if review_groups:
    complete = True
    for case in review_groups:
        root = pathlib.Path(case['observation']['case_root'])
        launches = load(root / 'variant-launches.json', [])
        expected_variants = manifest['invocation']['review_timing']['variants'][case['id']]
        complete = complete and [item['variant'] for item in launches] == expected_variants
        complete = complete and all(item['work_seconds'] == 120 and item['grace_seconds'] == 60
                                   and item['group_quiescent'] and not item['observer_error'] and not item['timed_out']
                                   for item in launches)
    controls.append({'id': 'HC-review-variant-budgets-and-owned-groups', 'status': 'PASS' if complete else 'FAIL'})
signal_cases = [case for case in cases if case['id'] == 'C7']
if signal_cases:
    event = signal_cases[0]['observation']['barrier']
    controls.append({'id': 'HC-observed-signal-barrier-and-exit', 'status': 'PASS' if event and event.get('supervisor_confirmed_post_rename') and signal_cases[0]['observation']['process_status'] is not None else 'FAIL'})
cleanup_cases = [case for case in cases if case['id'].startswith('L')]
if cleanup_cases:
    complete = all(case['observation']['process_status'] is not None and case['notes'].get('allocator_events') for case in cleanup_cases)
    controls.append({'id': 'HC-cleanup-child-completion-and-allocation', 'status': 'PASS' if complete else 'FAIL'})
journal_cases = [case for case in cases if case['id'].startswith('J')]
if journal_cases:
    journal_assertions = ('journal terminal/recovery state ', 'retained original matches planned hash ', 'required applied original retained ')
    complete = all(case['notes'].get('journals') and case['notes'].get('strict_evidence') for case in journal_cases)
    controls.append({'id': 'HC-journal-state-and-backup-consistency', 'status': 'PASS' if complete else 'FAIL'})
    serial = next((case for case in journal_cases if case['id'] == 'J17'), None)
    if 'J17' in expected_schedule:
        controls.append({'id': 'HC-serialized-mutation-boundaries',
                         'status': 'PASS' if serial and serial['notes'].get('serialized_intervals') and len(serial['notes'].get('concurrent_call_statuses',[]))==3 else 'FAIL'})
    signalled = [case for case in journal_cases if case['id'] in {'J13', 'J14', 'J15', 'J16'}]
    selected_signals = set(expected_schedule) & {'J13', 'J14', 'J15', 'J16'}
    if selected_signals:
        observed = {case['id'] for case in signalled} == selected_signals and all(case['observation']['barrier'] and case['observation']['barrier'].get('supervisor_confirmed_phase') and not case['observation']['leftover_workers'] for case in signalled)
        controls.append({'id': 'HC-observed-owned-transaction-signals', 'status': 'PASS' if observed else 'FAIL'})
expected_ids = [identifier for suite, _, identifiers in schedule if not args.suite or args.suite == suite for identifier in identifiers]
review_controls = [case for case in cases if case['id'] in {'K13', 'K14'}]
if review_controls:
    controls.append({'id':'HC-independent-decision-premutation-hardlink-controls',
                      'status':'PASS' if {case['id'] for case in review_controls} == set(expected_schedule) & {'K13','K14'} and all(case['status']=='PASS' for case in review_controls) else 'FAIL'})
assert len(cases) == len(expected_ids) and {case['id'] for case in cases} == set(expected_ids)
counts = {state: sum(case['status'] == state for case in cases) for state in ('PASS', 'FAIL', 'ERROR', 'BLOCKED')}
partial.update(ended=datetime.now(timezone.utc).isoformat(), controls=controls, summary=counts, scheduled_ids=expected_ids)
results_path.write_text(json.dumps(partial, indent=2) + '\n')
capacity_check(session, 'after-run')
for control in controls:
    print(f"{control['status']} {control['id']}")
print('SUMMARY ' + ' '.join(f'{key}={value}' for key, value in counts.items()))
if counts['ERROR'] or counts['BLOCKED'] or any(control['status'] != 'PASS' for control in controls):
    raise SystemExit(2)
raise SystemExit(1 if counts['FAIL'] else 0)
PY
