"""Actual core, cold update and whole batch; PVE/network effects are modeled."""
import json
import os
from pathlib import Path
import pty
import re
import select
import shlex
import subprocess
import sys
import tempfile
import time

S = Path(sys.argv[1])
W = Path(tempfile.mkdtemp(prefix='resource-consent.', dir=os.environ['TMPDIR']))
print('Resource consent evidence: ' + str(W), flush=True)
checks = []
q = lambda p: shlex.quote(str(p))


def check(name, expected, actual):
    ok = expected == actual
    checks.append(dict(name=name, expected=expected, actual=actual, passed=ok))
    print(('PASS ' if ok else 'FAIL ') + name, flush=True)


def run(c, code, answer=b'', extra=None, dialog=None):
    env = dict(os.environ, HOME=str(c), TMPDIR=str(c), CASE_ROOT=str(c),
               SUBJECT_SOURCE=str(S), PATH=str(W / 'bin') + ':/usr/bin:/bin', TERM='dumb')
    env.update(extra or {})
    if dialog is None:
        r = subprocess.run(['/bin/bash', '-c', code], input=answer, env=env,
                           capture_output=True, timeout=25, cwd=c)
    else:
        master, slave = pty.openpty()
        child = subprocess.Popen(['/bin/bash', '-c', code], env=env, cwd=c,
                                 stdin=slave, stdout=slave, stderr=slave)
        os.close(slave)
        output = b''
        initial = json.loads((c / 'state').read_text())
        try:
            for prompt, response in dialog:
                deadline = time.monotonic() + 15
                while prompt not in output:
                    assert time.monotonic() < deadline, 'PTY prompt deadline: ' + repr(output)
                    if select.select([master], [], [], .1)[0]:
                        output += os.read(master, 65536)
                check(c.name + ' no software before answer ' + response.decode().strip(), False, (c / 'software').exists())
                check(c.name + ' no setter before answer', False, '"set"' in (c / 'calls').read_text())
                current = json.loads((c / 'state').read_text())
                check(c.name + ' exact config before answer', [initial[k]['config'] for k in ('500', '501')], [current[k]['config'] for k in ('500', '501')])
                os.write(master, response)
                output = output.replace(prompt, b'OBSERVED', 1)
            child.wait(timeout=20)
            while select.select([master], [], [], .1)[0]:
                try:
                    data = os.read(master, 65536)
                except OSError:
                    break
                if not data:
                    break
                output += data
            r = subprocess.CompletedProcess(child.args, child.returncode, output, b'')
        finally:
            os.close(master)
            if child.poll() is None:
                child.terminate()
                child.wait(timeout=5)
    (c / 'result.json').write_text(json.dumps(dict(status=r.returncode,
        stdout=r.stdout.decode(errors='replace'), stderr=r.stderr.decode(errors='replace'), code=code)))
    return r


def case(name):
    c = W / name
    c.mkdir()
    return c


# Executable boundaries record full argv and persisted config/software state.
bin_dir = W / 'bin'
bin_dir.mkdir()
model = '''#!/usr/bin/python3
import json,os,pathlib,subprocess,sys,time
c=pathlib.Path(os.environ['CASE_ROOT']); a=sys.argv[1:]; tool=pathlib.Path(sys.argv[0]).name
with (c/'calls').open('a') as f: f.write(json.dumps([tool,*a])+'\\n')
s=json.loads((c/'state').read_text()) if (c/'state').exists() else {}
def save(): (c/'state').write_text(json.dumps(s,sort_keys=True))
marker_script='if [ -e /var/run/reboot-required ]; then printf present; else printf absent; fi'
if tool=='curl':
 if a[-1].endswith('/misc/core.func'): print((pathlib.Path(os.environ['SUBJECT_SOURCE'])/'misc/core.func').read_text())
 elif a[-1].endswith('/misc/bootstrap/pve'): print('load_functions; color; msg_info() { :; }; msg_ok() { printf "OK %s\\\\n" "$*"; }; msg_error() { printf "ERROR %s\\\\n" "$*"; }')
 elif s.get('metadata_fail'): sys.exit(47)
 else: print((c/'metadata').read_text())
elif tool=='pct':
 op=a[0]; cid=a[1] if len(a)>1 else ''; ct=s.get(cid,{})
 if op=='list': print('VMID Status Lock Name\\n500 stopped fixture\\n501 running other')
 elif op=='config':
  if ct.get('recovery') and ct.get('restore_config_fail'): sys.exit(53)
  print('ostype: debian\\ntags: community-script\\n'+('' if ct.get('recovery') and ct.get('restore_storage_missing') else 'rootfs: local:fixture\\n')+ct.get('config','cores: 1\\nmemory: 1024\\n'))
 elif op=='status':
  if ct.get('status_fail'): sys.exit(49)
  if ct.get('update_done') and ct.get('recovery_state_fail'): sys.exit(56)
  if ct.get('update_done') and ct.get('recovery_state_unknown'): print('status: unknown');sys.exit(0)
  if ct.get('update_done') and not ct.get('queued'):
   if ct.get('eligibility_fail'):sys.exit(58)
   if ct.get('eligibility_unknown'):print('status: unknown');sys.exit(0)
  if ct.get('queued'):
   if ct.get('final_query_fail'):sys.exit(59)
   if ct.get('final_query_unknown'):print('status: unknown');sys.exit(0)
  print('status: '+ct['status'])
 elif op=='start':
  if ct.get('restoring') and ct.get('restore_start_fail'): sys.exit(51)
  if ct.get('start_fail'): sys.exit(48)
  ct['status']='running'; save()
 elif op=='shutdown':
  if ct.get('shutdown_fail'): sys.exit(50)
  (c/'shutdown-inflight').write_text(cid)
  if ct.get('delayed_shutdown'): time.sleep(.15)
  s=json.loads((c/'state').read_text());ct=s[cid]
  if not ct.get('shutdown_no_effect'): ct['status']='stopped'
  save();(c/'shutdown-inflight').unlink()
 elif op=='pull': pathlib.Path(a[-1]).write_bytes((c/'bundle').read_bytes())
 elif op=='set': ct['config']='MUTATED '+repr(a); save()
 elif op=='exec':
  cmd=a[2:]; cmd=cmd[1:] if cmd and cmd[0]=='--' else cmd
  if cmd==['nproc']:
   if ct.get('cpu_fail'): sys.exit(ct.get('cpu_status',46))
   print(ct['cpu'])
  elif cmd==['free','-m']:
   if ct.get('ram_fail'): sys.exit(45)
   print('              total used free\\nMem: '+str(ct['ram'])+' 0 0')
  elif cmd==['sh','-c',marker_script] or cmd==['[','-e','/var/run/reboot-required',']']:
   if ct.get('marker_fail'):sys.exit(64)
   if ct.get('marker_status'):
    payload=ct.get('marker_payload','');(c/'marker-response').write_text(payload);sys.stdout.write(payload);sys.exit(ct['marker_status'])
   if 'marker_payload' in ct:
    (c/'marker-response').write_text(ct['marker_payload']);sys.stdout.write(ct['marker_payload']);sys.exit(0)
   if cmd[0]=='[':sys.exit(0 if ct.get('reboot_required') else 1)
   marker=c/('guest-reboot-required-'+cid)
   if ct.get('reboot_required'):marker.touch()
   elif marker.exists():marker.unlink()
   result=subprocess.run(['/bin/sh','-c',marker_script.replace('/var/run/reboot-required',str(marker))],capture_output=True,timeout=5)
   (c/'marker-response').write_bytes(result.stdout);sys.stdout.buffer.write(result.stdout);sys.stderr.buffer.write(result.stderr);sys.exit(result.returncode)
  elif '-c' in cmd and cmd[0] in ('bash','ash'):
   with (c/'software').open('a') as f: f.write(cid+'\\n')
   ct['update_done']=True
   if ct.get('update_stops'):ct['status']='stopped'
   save()
   sys.exit(ct.get('result',0))
  elif cmd==['hostname']:
   if ct.get('hostname_fail'):sys.exit(63)
   ct['queued']=True
   if ct.get('stop_after_queue'):ct['status']='stopped'
   save();print('fixture')
  else: sys.exit(98)
 elif op=='stop':
  ct['recovery']=True; save()
  if ct.get('restore_stop_fail'):sys.exit(52)
  if ct['status']=='stopped':sys.exit(57)
  if not ct.get('stop_no_effect'):ct['status']='stopped'
  save()
 elif op=='restore':
  if ct.get('restore_fail'):sys.exit(54)
  if (c/'shutdown-inflight').exists():(c/'restore-raced-shutdown').write_text(cid)
  rows=json.loads((c/'backups').read_text()) if (c/'backups').exists() else []
  row=next((r for r in rows if r['volid']==a[2]),None)
  path=c/('created-'+cid if row else 'old-local-data')
  if path.exists():(c/'restored-data').write_bytes(path.read_bytes())
  ct['restoring']=True; save()
 elif op=='reboot':
  if ct['status']!='running':sys.exit(60)
  if ct.get('reboot_fail'):sys.exit(61)
  ct['reboots']=ct.get('reboots',0)+1;save()
  with (c/'rebooted').open('a') as f:f.write(cid+'\\n')
 else: sys.exit(98)
elif tool=='vzdump':
 cid=a[0];ct=s[cid]
 if ct.get('backup_fail'): sys.exit(44)
 (c/'backup').write_text('retained')
 store=a[a.index('--storage')+1];notes=a[a.index('--notes-template')+1] if '--notes-template' in a else 'legacy backup'
 rows=json.loads((c/'backups').read_text()) if (c/'backups').exists() else []
 old=dict(volid=store+':backup/vzdump-lxc-'+cid+'-2026_01_01-00_00_00.tar.zst',vmid=int(cid),format='tar.zst',content='backup',subtype='lxc',notes='old')
 if not any(r['volid']==old['volid'] for r in rows):rows.append(old)
 row=dict(old,volid=store+(':backup/ct/'+cid+'/2026-11-07T18:00:00Z' if store=='pbs' else ':backup/vzdump-lxc-'+cid+'-2026_11_07-18_00_00.tar.zst'),notes=notes,format='pbs-ct' if store=='pbs' else 'tar.zst')
 fault=ct.get('backup_fault')
 if fault=='reuse':row['volid']=old['volid'];rows=[r for r in rows if r['volid']!=old['volid']]
 if fault in ('no-note','foreign-note'):row['notes']='' if fault=='no-note' else 'other producer'
 if fault=='wrong-store':row['volid']='foreign:'+row['volid'].split(':',1)[1]
 if fault=='wrong-ct':row['vmid']=int(cid)+1
 if fault=='wrong-type':row['subtype']='qemu';row['format']='vma.zst'
 if fault=='prune':rows=[]
 if fault not in ('zero','pruned-new'):rows.append(row)
 if fault=='multiple':rows.append(dict(row,volid=row['volid']+'-other'))
 if fault=='duplicate':rows.append(dict(row))
 (c/'backups').write_text(json.dumps(rows));(c/('created-'+cid)).write_text('NEW SELECTED BACKUP '+cid);(c/'old-local-data').write_text('OLD WRONG LOCAL BACKUP')
elif tool=='pvesh':
 cid=a[a.index('--vmid')+1];ct=s[cid];store=a[1].split('/storage/',1)[1].split('/')[0]
 count=ct['inventory_calls']=ct.get('inventory_calls',0)+1;save()
 if ct.get('inventory_fail')==count:sys.exit(55)
 if ct.get('inventory_bad')==count:print('{');sys.exit(0)
 rows=json.loads((c/'backups').read_text()) if (c/'backups').exists() else []
 if count==1:
  old=dict(volid=store+':backup/vzdump-lxc-'+cid+'-2026_01_01-00_00_00.tar.zst',vmid=int(cid),format='tar.zst',content='backup',subtype='lxc',notes='old')
  if not any(r['volid']==old['volid'] for r in rows):rows.append(old)
  (c/'backups').write_text(json.dumps(rows))
 rows=[r for r in rows if r['vmid']==int(cid) or ct.get('backup_fault')=='wrong-ct']
 if ct.get('update_done') and ct.get('receipt_removed'):rows=[]
 if ct.get('update_done') and ct.get('receipt_changed'):rows=[dict(r,notes='changed') for r in rows]
 print(json.dumps(rows))
elif tool=='awk':
 if '/etc/pve/storage.cfg' in a: print('local\\nremote\\npbs')
 else: os.execv('/usr/bin/awk',['/usr/bin/awk',*a])
elif tool in ['sleep','clear']: pass
elif tool=='nproc':
 if os.environ.get('PROBE_FAIL')=='cpu': sys.exit(46)
 print(os.environ.get('ACTUAL_CPU','1'))
elif tool=='free':
 if os.environ.get('PROBE_FAIL')=='ram': sys.exit(45)
 print('              total used free\\nMem: '+os.environ.get('ACTUAL_RAM','1024')+' 0 0')
else: sys.exit(98)
'''
for name in ('curl', 'pct', 'vzdump', 'pvesh', 'sleep', 'clear', 'nproc', 'free', 'awk'):
    p = bin_dir / name
    p.write_text(model)
    p.chmod(0o755)

prefix = f'set -euo pipefail; source {q(S / "misc/core.func")}; '
for label, required, actual, answer, status, warning in [
    ('enough', ('2', '2048'), ('4', '4096'), b'', 0, False),
    ('equal', ('2', '2048'), ('2', '2048'), b'', 0, False),
    ('cpu-no', ('4', '1024'), ('2', '2048'), b'no\n', 1, True),
    ('ram-yes', ('1', '4096'), ('2', '2048'), b'YeS\n', 0, True),
    ('both-y', ('4', '4096'), ('1', '1024'), b'y\n', 0, True),
    ('empty', ('4', '4096'), ('1', '1024'), b'\n', 1, True),
    ('eof', ('4', '4096'), ('1', '1024'), b'', 1, True),
    ('partial-eof', ('4', '4096'), ('1', '1024'), b'yes', 1, True),
    ('unknown-no', ('', ''), ('1', '1024'), b'no\n', 1, True),
    ('unknown-yes', ('', ''), ('1', '1024'), b'yes\n', 0, True),
    ('overflow-unknown', ('18446744073709551616', '4096'), ('1', '1024'), b'yes\n', 0, True),
    ('literal-injection', ('$(touch BAD)', '4096'), ('1', '1024'), b'no\n', 1, True),
    ('actual-invalid', ('1', '1024'), ('bad', '1024'), b'yes\n', 65, False),
    ('actual-overflow', ('1', '1024'), ('9223372036854775808', '1024'), b'yes\n', 65, False),
    ('max', ('9223372036854775807', '0'), ('9223372036854775807', '1024'), b'', 0, False),
    ('leading-zero', ('0002', '002048'), ('02', '02048'), b'', 0, False),
]:
    c = case('core-' + label)
    code = prefix + 'var_unattended=yes var_skip_confirm=yes; if confirm_container_resources ' + ' '.join(q(v) for v in (*required, *actual, 'Probe')) + '; then rc=0; else rc=$?; fi; exit "$rc"'
    r = run(c, code, answer)
    check(label + ' exact core status', status, r.returncode)
    check(label + ' prompt only when required', warning, b'Continue update' in r.stdout + r.stderr)
    check(label + ' literal data never executes', False, (c / 'BAD').exists())

# Adapter is fatal even inside a conditional that disables errexit for its body.
for label, answer, fault, status in [('yes', b'yes\n', '', 0), ('no', b'no\n', '', 1),
                                      ('eof', b'', '', 1), ('cpu-fail', b'yes\n', 'cpu', 46),
                                      ('ram-fail', b'yes\n', 'ram', 45)]:
    c = case('direct-' + label)
    code = prefix + 'APP=Probe var_cpu=4 var_ram=4096; if check_container_resources; then printf effect > software; fi'
    r = run(c, code, answer, dict(PROBE_FAIL=fault))
    check(label + ' direct adapter explicit terminal status', status, r.returncode)
    check(label + ' direct downstream effect', status == 0, (c / 'software').exists())

# Independent direct calls cannot borrow imported/global or prior-call consent.
c = case('outside-owner-repeat')
r = run(c, prefix + '''LXC_REQUIRED_CPU=4 LXC_REQUIRED_RAM=4096
declare -a _lxc_resource_admission=(4 4096 1 1024)
check_container_resources; printf first > first
check_container_resources; printf second > second
''', b'yes\nno\n')
check('outside owner repeats actual consent despite matching forged tuple', 2, (r.stdout + r.stderr).count(b'Continue update'))
check('outside owner second refusal is terminal', 1, r.returncode)
check('outside owner first admitted effect observed', True, (c / 'first').exists())
check('outside owner no second software effect', False, (c / 'second').exists())

# Real producer, frozen core/error, real cold update runner and resource adapter.
for label, setup, answer, status in [
    ('absent-no', '', b'no\n', 1), ('absent-eof', '', b'', 1),
    ('absent-yes', '', b'yes\n', 0),
    ('explicit-zero', 'LXC_REQUIRED_CPU=0 LXC_REQUIRED_RAM=0 var_cpu=99 var_ram=99999', b'', 0),
    ('explicit-empty', "LXC_REQUIRED_CPU='' LXC_REQUIRED_RAM='' var_cpu=0 var_ram=0", b'no\n', 1),
    ('explicit-minimum', 'LXC_REQUIRED_CPU=4 LXC_REQUIRED_RAM=4096 var_cpu=0 var_ram=0', b'no\n', 1),
]:
    c = case('direct-presence-' + label)
    r = run(c, prefix + 'unset var_cpu var_ram LXC_REQUIRED_CPU LXC_REQUIRED_RAM; ' +
            (setup + '; ' if setup else '') + 'if check_container_resources; then printf effect > software; fi', answer)
    check(label + ' direct presence exact status', status, r.returncode)
    check(label + ' direct presence productive frontier', status == 0, (c / 'software').exists())

cache = W / 'framework'
cache.mkdir()
core = (S / 'misc/core.func').read_text()
for old, new in [('/var/lib/scripts-underground/update-pending', str(W / 'pending')),
                 ('/var/lib/scripts-underground/maintenance-locks', str(W / 'locks'))]:
    core = core.replace(old, new)
(cache / 'core.func').write_text(core)
(cache / 'error_handler.func').write_bytes((S / 'misc/error_handler.func').read_bytes())
for name, body in [('install', 'setup_lxc() { :; }'), ('tools', 'setup_uv() { :; }'),
                   ('github', 'clone_and_deploy_gh_commit() { :; }')]:
    (cache / (name + '.func')).write_text(body + '\n')
c = case('producer')
bundle = W / 'update'
r = run(c, f'''set -euo pipefail
source {q(S / 'misc/bundle.func')}
APP=Probe NSAPP=consent-probe REPO_BASE=offline var_lxc_tmpdir={q(W)}
update_script() {{ var_cpu=4 var_ram=4096; check_container_resources; printf effect > "$CASE_ROOT/software"; }}
_write_bundle update update_script {q(cache)} 'cleanup_lxc() {{ :; }}' 'run_update_script "$@"' > {q(bundle)}
''')
check('actual cold producer', 0, r.returncode)
for label, answer, status in [('yes', b'yes\n', 0), ('no', b'no\n', 1), ('eof', b'', 1)]:
    c = case('cold-' + label)
    # Bundles deliberately set a minimal PATH; executable models are injected as
    # exported functions only at the measured nproc/free boundaries.
    r = run(c, f'''nproc() {{ {q(bin_dir / 'nproc')}; }}; free() {{ {q(bin_dir / 'free')} "$@"; }}; export -f nproc free
exec /bin/bash {q(bundle)}''', answer)
    check(label + ' actual cold status', status, r.returncode)
    check(label + ' actual cold software effect', status == 0, (c / 'software').exists())

metadata = (S / 'scripts/lxc/changedetection.sh').read_text()
declarations = metadata[:metadata.index('function install_script() {')]
c = case('identity-producer')
identity_bundle = W / 'identity-update'
r = run(c, f'''set -euo pipefail
source {q(S / 'misc/bundle.func')}
{declarations}
NSAPP=${{APP,,}}; NSAPP=${{NSAPP// /}}; var_lxc_tmpdir={q(W)}
update_script() {{ :; }}
_write_bundle update update_script {q(cache)} --script-id changedetection -- 'run_update_script "$@"' > {q(identity_bundle)}
''')
check('actual identity producer', 0, r.returncode)


def batch(label, answer, expected, cpu=1, ram=1024, running=False, second=False,
          metadata_fail=False, malformed=False, legacy=False, dialog=None, second_result=0, metadata_text=None, **faults):
    c = case('batch-' + label)
    ct = dict(cpu=cpu, ram=ram, status='running' if running else 'stopped',
              config=f'cores: {cpu}\nmemory: {ram}\n', **faults)
    state = {'500': ct, '501': dict(cpu=8, ram=8192, status='running', config='custom: preserved\n', result=second_result),
             'metadata_fail': metadata_fail}
    original = json.loads(json.dumps(state))
    (c / 'state').write_text(json.dumps(state, sort_keys=True))
    (c / 'metadata').write_text(metadata_text if metadata_text is not None else 'var_cpu="${var_cpu:-$(touch BAD)}"\nvar_ram="${var_ram:-4096}"\n' if malformed else metadata)
    (c / 'bundle').write_bytes(b'bash -c "$(curl -fsSL https://fixture.invalid/ct/changedetection.sh)"\n' if legacy else identity_bundle.read_bytes())
    r = run(c, f'exec /bin/bash {q(S / "scripts/pve/update-apps.sh")}', answer,
            dict(var_backup='no', var_container='500,501' if second else '500',
                 var_unattended='yes', var_skip_confirm='yes', var_auto_reboot='no',
                 REPO_BASE='https://fixture.invalid/batch'), dialog=dialog)
    final = json.loads((c / 'state').read_text())
    calls = [json.loads(v) for v in (c / 'calls').read_text().splitlines()]
    effects = (c / 'software').read_text().splitlines() if (c / 'software').exists() else []
    out = r.stdout + r.stderr
    status, wanted_effects, wanted_state = expected
    check(label + ' exact batch status', status, r.returncode)
    check(label + ' exact software consumer', wanted_effects, effects)
    check(label + ' exact configuration preserved', [original[k]['config'] for k in ('500', '501')], [final[k]['config'] for k in ('500', '501')])
    check(label + ' zero resource setters', [], [v for v in calls if v[:2] == ['pct', 'set']])
    check(label + ' final owned lifecycle readback', wanted_state, final['500']['status'])
    check(label + ' preexisting other state preserved', 'running', final['501']['status'])
    check(label + ' never execute metadata', False, (c / 'BAD').exists())
    if '500' in wanted_effects:
        check(label + ' actual selected-CT CPU probe', True, ['pct', 'exec', '500', '--', 'nproc'] in calls)
        check(label + ' actual selected-CT RAM probe', True, ['pct', 'exec', '500', '--', 'free', '-m'] in calls)
    if status:
        check(label + ' honest partial summary', True, b'partially complete' in out and b'containers have been successfully updated' not in out)
    if not second:
        check(label + ' no nonexistent remaining-target prompt', False, b'Continue with the remaining' in out)
    if not wanted_effects:
        check(label + ' admission never stop/restore/reboot', [], [v for v in calls if v[:2] in (['pct', 'stop'], ['pct', 'restore'], ['pct', 'reboot'])])
        check(label + ' preserves preexisting running state without shutdown', not running and not faults.get('start_fail'), any(v[:2] == ['pct', 'shutdown'] for v in calls))
        if not running and not faults.get('start_fail'):
            check(label + ' bounded normal graceful shutdown', True, ['pct', 'shutdown', '500', '--timeout', '60'] in calls)
    if metadata_fail or malformed or metadata_text is not None:
        check(label + ' explicit unknown warning', True, b'unknown or invalid' in out)
    if faults.get('shutdown_fail'):
        check(label + ' failed cleanup honestly reported', True, b'unable to restore batch-owned start (status 50)' in out)
    if second and not wanted_effects:
        check(label + ' unattempted second reported', True, b'not attempted: 501' in out)
    if faults.get('result') == 75:
        check(label + ' raw75 no rollback/shutdown/reboot', [], [v for v in calls if v[:2] in (['pct', 'shutdown'], ['pct', 'stop'], ['pct', 'restore'], ['pct', 'reboot'])])
    return c, r, calls


for label, cpu, ram in [('cpu-short', 1, 8192), ('ram-short', 8, 1024), ('both-short', 1, 1024)]:
    for answer, tag in [(b'yes\n', 'yes'), (b'y\n', 'y'), (b'no\n', 'no'), (b'\n', 'empty'), (b'', 'eof')]:
        admitted = tag in ('yes', 'y')
        batch(label + '-' + tag, answer, (0 if admitted else 1, ['500'] if admitted else [], 'stopped'), cpu, ram)
for label, cpu, ram in [('enough', 8, 8192), ('equal', 4, 4096)]:
    batch(label, b'', (0, ['500'], 'stopped'), cpu, ram)
batch('legacy', b'yes\n', (0, ['500'], 'stopped'), legacy=True)
for label, kwargs in [('metadata-fail', dict(metadata_fail=True)), ('malformed', dict(malformed=True))]:
    batch(label + '-yes', b'yes\n', (0, ['500'], 'stopped'), **kwargs)
    batch(label + '-no', b'no\n', (1, [], 'stopped'), **kwargs)
for label, kwargs, status in [('cpu-fail', dict(cpu_fail=True), 46), ('ram-fail', dict(ram_fail=True), 45),
                               ('bad-actual', dict(cpu='unknown'), 65), ('start-fail', dict(start_fail=True), 48)]:
    batch(label, b'yes\n', (status, [], 'stopped'), **kwargs)
batch('running-decline', b'no\n', (1, [], 'running'), running=True)
batch('running-query-fail', b'yes\n', (46, [], 'running'), running=True, cpu_fail=True)
batch('query-status1', b'yes\n', (1, [], 'stopped'), cpu_fail=True, cpu_status=1)
batch('mismatched-quote', b'no\n', (1, [], 'stopped'), metadata_text='var_cpu="4\nvar_ram="4096"\n')
batch('duplicate-requirement', b'no\n', (1, [], 'stopped'), metadata_text='var_cpu="4"\nvar_cpu="1"\nvar_ram="4096"\n')
batch('cleanup-fail', b'no\n', (1, [], 'running'), shutdown_fail=True)
batch('decline-continue', b'no\nyes\n', (1, ['501'], 'stopped'), second=True)
batch('decline-stop', b'no\nno\n', (1, [], 'stopped'), second=True)
batch('decline-eof', b'no\n', (1, [], 'stopped'), second=True)
batch('query-continue', b'yes\n', (46, ['501'], 'stopped'), second=True, cpu_fail=True)
batch('decline-then75', b'no\nyes\n', (75, ['501'], 'stopped'), second=True, second_result=75)
batch('raw75', b'yes\n', (75, ['500'], 'running'), result=75)
batch('ordinary-failure', b'yes\n', (1, ['500'], 'stopped'), result=41)
batch('pty-consent', b'', (0, ['500'], 'stopped'), dialog=[(b'Continue update', b'yes\n')])
batch('pty-decline-continue', b'', (1, ['501'], 'stopped'), second=True,
      dialog=[(b'Continue update', b'no\n'), (b'Continue with the remaining', b'yes\n')])


def priority_case(label, overrides, expected_status, expected_updates, answer=b'', backup='yes', storage='local', targets='500,501,502,503'):
    c = case('priority-' + label)
    state = {str(cid): dict(cpu=8, ram=8192, status='running',
                           config=f'operator-config: {cid}\n') for cid in (500, 501, 502, 503)}
    for cid, values in overrides.items():
        state[cid].update(values)
    original = json.loads(json.dumps(state))
    (c / 'state').write_text(json.dumps(state, sort_keys=True))
    (c / 'metadata').write_text(metadata)
    (c / 'bundle').write_bytes(identity_bundle.read_bytes())
    r = run(c, f'exec /bin/bash {q(S / "scripts/pve/update-apps.sh")}', answer,
            dict(var_backup=backup, var_backup_storage=storage, var_container=targets,
                 var_unattended='yes', var_skip_confirm='yes', var_auto_reboot='yes',
                 REPO_BASE='https://fixture.invalid/batch'))
    calls = [json.loads(v) for v in (c / 'calls').read_text().splitlines()]
    final = json.loads((c / 'state').read_text())
    effects = (c / 'software').read_text().splitlines() if (c / 'software').exists() else []
    protected = [cid for cid in effects if original[cid].get('result') == 75]
    check(label + ' actual whole-batch terminal priority', expected_status, r.returncode)
    check(label + ' fatal abort preserves exact updater frontier', expected_updates, effects)
    check(label + ' no later selected target update', False, '503' in effects)
    check(label + ' exact all-container configuration readback',
          {cid: ct['config'] for cid, ct in original.items()},
          {cid: ct['config'] for cid, ct in final.items()})
    check(label + ' zero resource setters', [], [v for v in calls if v[:2] == ['pct', 'set']])
    check(label + ' fatal abort performs no new reboot', [], [v for v in calls if v[:2] == ['pct', 'reboot']])
    for cid in protected:
        check(label + ' protected updater75 has no rollback/cleanup ' + cid, [],
              [v for v in calls if len(v) > 2 and v[0] == 'pct' and v[2] == cid and
               v[1] in ('shutdown', 'stop', 'restore', 'reboot')])
        check(label + ' protected updater75 remains running ' + cid, 'running', final[cid]['status'])
    check(label + ' fatal result never claims all updated', False,
          b'containers have been successfully updated' in r.stdout + r.stderr)
    (c / 'outcome.json').write_text(json.dumps(dict(status=r.returncode,
        expected_status=expected_status, expected_updates=expected_updates,
        actual_updates=effects, protected75=protected, state=final), sort_keys=True, indent=2))
    return c, r, calls


priority_case('75-then-backup-fail', {'500': dict(result=75), '501': dict(backup_fail=True)},
              75, ['500'])
priority_case('65-continue-backup-fail', {'500': dict(cpu='unknown'), '501': dict(backup_fail=True)},
              65, [], b'yes\n')
priority_case('75-then-restore-fail', {'500': dict(result=75), '501': dict(result=41, restore_start_fail=True)},
              75, ['500', '501'])
priority_case('65-continue-restore-fail', {'500': dict(cpu='unknown'), '501': dict(result=41, restore_start_fail=True)},
              65, ['501'], b'yes\n')
priority_case('backup-fail-no-prior', {'500': dict(backup_fail=True)}, 1, [])
priority_case('restore-fail-no-prior', {'500': dict(result=41, restore_start_fail=True)}, 1, ['500'])
priority_case('unrecoverable-no-prior', {'500': dict(result=41)}, 1, ['500'], backup='no')
priority_case('successful-then-unrecoverable', {'500': dict(reboot_required=True), '501': dict(result=41)},
              1, ['500', '501'], backup='no')
priority_case('75-then-unrecoverable', {'500': dict(result=75), '501': dict(result=41)},
              75, ['500', '501'], backup='no')
priority_case('65-then75-backup-fail', {'500': dict(cpu='unknown'), '501': dict(result=75), '502': dict(backup_fail=True)},
              75, ['501'], b'yes\n')
priority_case('75-then65-backup-fail', {'500': dict(result=75), '501': dict(cpu='unknown'), '502': dict(backup_fail=True)},
              75, ['500'], b'yes\n')

for step, fault, native in [('stop', 'restore_stop_fail', 52), ('config', 'restore_config_fail', 53),
                            ('storage', 'restore_storage_missing', 65), ('restore', 'restore_fail', 54),
                            ('start', 'restore_start_fail', 51)]:
    for prior in ('none', '75', '65'):
        target = '500' if prior == 'none' else '501'
        overrides = {target: dict(result=41, **{fault: True})}
        if prior == '75': overrides['500'] = dict(result=75)
        if prior == '65': overrides['500'] = dict(cpu='unknown')
        expected = 1 if prior == 'none' else int(prior)
        updates = ['500'] if prior == 'none' else ['500', '501'] if prior == '75' else ['501']
        c, r, calls = priority_case('restore-' + step + '-prior-' + prior, overrides,
                                     expected, updates, b'yes\n' if prior == '65' else b'')
        out = r.stdout + r.stderr
        check(step + '/' + prior + ' recovery identifies exact failed step/status', True,
              ('backup recovery failed at ' + step + ' (status ' + str(native) + ')').encode() in out)
        check(step + '/' + prior + ' no false restoration success', False, b'OK Restored LXC from backup' in out)
        selected = [v for v in calls if v[:2] in (['pct', 'stop'], ['pct', 'restore'], ['pct', 'start']) and v[2] == target]
        expected_ops = ['stop'] + (['restore'] if step in ('restore', 'start') else []) + (['start'] if step == 'start' else [])
        check(step + '/' + prior + ' exact recovery effects frontier', expected_ops, [v[1] for v in selected])

# Exact producer association and an actual filesystem data consumer behind the
# modeled PVE restore boundary. No native PVE archive/restore claim is made.
for store, faults in [('remote', {}), ('pbs', {}), ('remote', {'backup_fault': 'prune'}),
                      ('remote', {'status': 'stopped', 'delayed_shutdown': True}),
                      ('remote', {'update_stops': True})]:
    label = 'owned-' + store + '-' + ('-'.join(faults) or 'normal')
    c, r, calls = priority_case(label, {'500': dict(result=41, **faults)}, 1, ['500'], storage=store, targets='500')
    check(label + ' restore consumer reads newly created selected backup data', 'NEW SELECTED BACKUP 500',
          (c / 'restored-data').read_text() if (c / 'restored-data').exists() else None)
    restores = [v for v in calls if v[:2] == ['pct', 'restore']]
    wanted = store + (':backup/ct/500/2026-11-07T18:00:00Z' if store == 'pbs' else ':backup/vzdump-lxc-500-2026_11_07-18_00_00.tar.zst')
    check(label + ' literal exact typed backup argument', [wanted], [v[3] for v in restores])
    check(label + ' no in-flight shutdown crosses restore', False, (c / 'restore-raced-shutdown').exists())
    check(label + ' final initially owned state', 'stopped' if faults.get('status') == 'stopped' else 'running',
          json.loads((c / 'state').read_text())['500']['status'])
    if faults.get('update_stops'):
        check(label + ' verified stopped skips native stop', [], [v for v in calls if v[:2] == ['pct', 'stop']])
    check(label + ' backup hook and pruning options not overridden', [],
          [a for v in calls if v[0] == 'vzdump' for a in v if a in ('--script', '--remove', '--prune-backups')])

for fault in ('zero', 'pruned-new', 'reuse', 'no-note', 'foreign-note', 'wrong-store', 'wrong-ct', 'wrong-type', 'multiple', 'duplicate'):
    c, r, calls = priority_case('receipt-' + fault, {'500': dict(backup_fault=fault)}, 1, [], storage='remote')
    check(fault + ' invalid producer receipt precedes every CT mutation', [],
          [v for v in calls if v[:2] in (['pct', 'start'], ['pct', 'stop'], ['pct', 'restore'], ['pct', 'shutdown'])])
for field, count in [('inventory_fail', 1), ('inventory_fail', 2), ('inventory_bad', 1), ('inventory_bad', 2)]:
    c, r, calls = priority_case(field + '-' + str(count), {'500': {field: count}}, 1, [], storage='remote')
    check(field + str(count) + ' query/JSON failure prevents software', False, (c / 'software').exists())
for field in ('receipt_removed', 'receipt_changed', 'recovery_state_fail', 'recovery_state_unknown'):
    c, r, calls = priority_case(field, {'500': dict(result=41, **{field: True})}, 1, ['500'], storage='remote')
    check(field + ' revalidation/query refusal before destructive effects', [],
          [v for v in calls if v[:2] in (['pct', 'stop'], ['pct', 'restore'], ['pct', 'start'])])
c, r, calls = priority_case('stop-not-stopped', {'500': dict(result=41, stop_no_effect=True)}, 1, ['500'], storage='remote')
check('successful stop without stopped readback never restores', [], [v for v in calls if v[:2] == ['pct', 'restore']])
c, r, calls = priority_case('shutdown-not-stopped', {'500': dict(status='stopped', shutdown_no_effect=True)}, 1, ['500'], storage='remote')
check('successful shutdown without stopped readback aborts later targets', ['500'],
      (c / 'software').read_text().splitlines() if (c / 'software').exists() else [])
c, r, calls = priority_case('backup-stale-next', {'500': dict(result=41), '501': dict(backup_fault='zero')}, 1, ['500'], storage='remote')
check('next CT cannot inherit previous successful receipt', ['500'], [v[2] for v in calls if v[:2] == ['pct', 'restore']])

# Exercise the actual recovery/revalidation boundary with healthy backend rows
# but a malformed expected identity. Identity bytes must never choose parser mode.
batch_source = (S / 'scripts/pve/update-apps.sh').read_text()
recovery_helpers = '\n'.join(re.search(r'(?ms)^function ' + name + r'\(\) \{\n.*?^\}$', batch_source).group()
                             for name in ('backup_inventory_volid', 'read_backup_inventory', 'revalidate_backup_receipt', 'read_batch_state', 'restore_container_backup'))
for identity in ('inventory-only', 'inventory', 'select-new', 'verify-exact'):
    c = case('expected-identity-' + identity)
    (c / 'state').write_text(json.dumps({'500': dict(cpu=8, ram=8192, status='running')}))
    volid = 'remote:backup/vzdump-lxc-500-2026_11_07-18_00_00.tar.zst'
    row = dict(volid=volid, vmid=500, format='tar.zst', content='backup', subtype='lxc', notes='fixture owned token')
    (c / 'backups').write_text(json.dumps([row]))
    code = prefix + recovery_helpers + f'''
NODE=fixture STORAGE_CHOICE=remote
batch_backup_ct=500 batch_backup_store=remote batch_backup_notes='fixture owned token'
batch_backup_volid={q(identity)}
if restore_container_backup 500; then rc=0; else rc=$?; fi
exit "$rc"
'''
    r = run(c, code)
    calls = [json.loads(v) for v in (c / 'calls').read_text().splitlines()]
    check(identity + ' malformed expected identity returns65 through actual recovery', 65, r.returncode)
    check(identity + ' malformed expected identity has no destructive frontier', [],
          [v for v in calls if v[:2] in (['pct', 'stop'], ['pct', 'restore'], ['pct', 'start'])])
    check(identity + ' malformed identity retains initial running state', 'running', json.loads((c / 'state').read_text())['500']['status'])

c = case('parser-mode-contract')
volid = 'remote:backup/vzdump-lxc-500-2026_11_07-18_00_00.tar.zst'
(c / 'before').write_text('[]')
(c / 'current').write_text(json.dumps([dict(volid=volid, vmid=500, format='tar.zst', content='backup', subtype='lxc', notes='token')]))
for mode, args, output in [
    ('inventory', [c / 'current', 'remote', '500'], ''),
    ('select-new', [c / 'before', c / 'current', 'remote', '500', 'token'], volid),
    ('verify-exact', [c / 'current', 'remote', '500', 'token', volid], volid),
]:
    command = 'backup_inventory_volid ' + ' '.join(q(v) for v in [mode, *args])
    r = run(case('parser-mode-' + mode), prefix + recovery_helpers + '\n' + command)
    check(mode + ' explicit parser mode native status', 0, r.returncode)
    check(mode + ' explicit parser mode data output', output, r.stdout.decode())
for index, args in enumerate([[], ['inventory-only', c / 'current', 'remote', '500'],
             ['inventory', c / 'current', 'remote'], ['inventory', c / 'current', 'remote', '500', 'extra'],
             ['select-new', c / 'before', c / 'current', 'remote', '500'],
             ['verify-exact', c / 'current', 'remote', '500', 'token'],
             ['verify-exact', c / 'current', 'remote', '500', 'token', volid, 'extra']]):
    r = run(case('parser-invalid-' + str(index)), prefix + recovery_helpers + '\nbackup_inventory_volid ' + ' '.join(q(v) for v in args))
    check('closed parser mode/arity refusal ' + repr(args), 65, r.returncode)

def reboot_case(label, overrides, expected_status, expected_reboots, expected_commands,
                targets='500', answer=b'', expected_updates=None, automatic='yes', diagnostic=None):
    c = case('reboot-' + label)
    state = {str(cid): dict(cpu=8, ram=8192, status='running', reboot_required=True,
                            config='operator-config: ' + str(cid) + '\n') for cid in (500, 501)}
    for cid, values in overrides.items():
        state[cid].update(values)
    (c / 'state').write_text(json.dumps(state))
    (c / 'metadata').write_text(metadata)
    (c / 'bundle').write_bytes(identity_bundle.read_bytes())
    r = run(c, f'exec /bin/bash {q(S / "scripts/pve/update-apps.sh")}', answer,
            dict(var_backup='no', var_container=targets, var_unattended='yes',
                 var_skip_confirm='yes', var_auto_reboot=automatic, REPO_BASE='https://fixture.invalid/batch'))
    calls = [json.loads(v) for v in (c / 'calls').read_text().splitlines()]
    final = json.loads((c / 'state').read_text())
    completed = (c / 'rebooted').read_text().splitlines() if (c / 'rebooted').exists() else []
    check(label + ' exact final reboot result priority', expected_status, r.returncode)
    check(label + ' actual modeled reboot consumer readback', expected_reboots, completed)
    check(label + ' exact requested reboot command frontier', expected_commands,
          [v[2] for v in calls if v[:2] == ['pct', 'reboot']])
    check(label + ' selected-container configuration retained',
          {k: v['config'] for k, v in state.items()}, {k: v['config'] for k, v in final.items()})
    if expected_updates is not None:
        check(label + ' update frontier retained', expected_updates,
              (c / 'software').read_text().splitlines() if (c / 'software').exists() else [])
    if diagnostic:
        check(label + ' native reboot diagnostic status', True,
              diagnostic.encode() in r.stdout + r.stderr)
    if label == 'initially-stopped':
        check('initially stopped marked CT stays stopped', 'stopped', final['500']['status'])
        check('initially stopped CT is not started merely for reboot', 1,
              sum(v[:3] == ['pct', 'start', '500'] for v in calls))
        check('stopped CT is not probed for reboot marker after cleanup', False,
              any(v[:3] == ['pct', 'exec', '500'] and 'reboot-required' in ' '.join(v) for v in calls))
    if label == 'stopped-since-queue':
        check('stopped-since-queue remains stopped', 'stopped', final['500']['status'])
    if '500' in targets and overrides.get('500', {}).get('result') == 75:
        check(label + ' protected75 receives no power/marker effects', [],
              [v for v in calls if len(v)>2 and v[0]=='pct' and v[2]=='500' and
               (v[1] in ('stop','shutdown','restore','reboot') or 'reboot-required' in ' '.join(v))])
    (c / 'outcome.json').write_text(json.dumps(dict(status=r.returncode, state=final,
         reboots=completed, expected_reboots=expected_reboots, expected_commands=expected_commands)))

reboot_case('initially-stopped', {'500': dict(status='stopped')}, 0, [], [])
reboot_case('running-requested', {}, 0, ['500'], ['500'])
reboot_case('request-declined', {}, 0, [], [], automatic='no')
reboot_case('no-marker', {'500': dict(reboot_required=False)}, 0, [], [])
reboot_case('stopped-since-queue', {'500': dict(stop_after_queue=True)}, 0, [], [])
for label, fields, native in [('final-query-fail', dict(final_query_fail=True), 59),
                              ('final-query-unknown', dict(final_query_unknown=True), 69),
                              ('eligibility-fail', dict(eligibility_fail=True), 58),
                              ('eligibility-unknown', dict(eligibility_unknown=True), 69),
                              ('marker-fail', dict(marker_fail=True), 64),
                              ('hostname-fail', dict(hostname_fail=True), 63)]:
    reboot_case(label, {'500': fields}, 1, [], [], diagnostic='status ' + str(native))
reboot_case('reboot-command-fail', {'500': dict(reboot_fail=True)}, 1, [], ['500'], diagnostic='status 61')
reboot_case('prior75-reboot-fail', {'500': dict(result=75), '501': dict(reboot_fail=True)},
            75, [], ['501'], targets='500,501', expected_updates=['500','501'], diagnostic='status 61')
reboot_case('prior65-reboot-fail', {'500': dict(cpu='unknown'), '501': dict(reboot_fail=True)},
            65, [], ['501'], targets='500,501', answer=b'yes\n', expected_updates=['501'], diagnostic='status 61')
reboot_case('marker-attach1', {'500': dict(marker_status=1)}, 1, [], [], diagnostic='status 1')
reboot_case('marker-attach1-partial', {'500': dict(marker_status=1, marker_payload='present')}, 1, [], [], diagnostic='status 1')
reboot_case('marker-other-error', {'500': dict(marker_status=55)}, 1, [], [], diagnostic='status 55')
reboot_case('marker-present-data', {'500': dict(marker_payload='present')}, 0, ['500'], ['500'])
reboot_case('marker-absent-data', {'500': dict(marker_payload='absent')}, 0, [], [])
for label, payload in [('empty',''),('unknown','maybe'),('multiple','present\nabsent'),
                       ('trailing-newline','present\n'),('absent-newline','absent\n'),
                       ('space',' present'),('nul','present\0'),('repeated','presentpresent')]:
    reboot_case('marker-malformed-' + label, {'500': dict(marker_payload=payload)}, 1, [], [], diagnostic='status 65')

(W / 'checks.json').write_text(json.dumps(checks, indent=2))
failures = sum(not v['passed'] for v in checks)
print(f'{len(checks)} resource consent checks; {failures} failure(s)', flush=True)
raise SystemExit(bool(failures))
