"""Shared before-effects admission and fixed consumer dispatch, including direct use."""
import os
from pathlib import Path
import subprocess
import sys
import json
import shlex
import time

sys.dont_write_bytecode = True
from test_context import AdmissionError, Context, require
from test_registry import REGISTRY, execution_policy


def invocation(suite, args):
    row = REGISTRY[suite]
    if suite == 'codeberg-release':
        require(args in ([], ['--live'], ['--bundle']), 'Codeberg takes no ambient CT/URL')
        return {'--live': 'live', '--bundle': 'bundle'}.get(args[0] if args else '', 'fixture')
    if suite == 'romm-player-serving':
        require(args in ([], ['--setup']), 'unknown player option')
        return 'setup' if args else 'live-runtime'
    if suite == 'maintenance-globnotes-lxc':
        # The stronger original parser/manifest owns its other explicit options.
        require(all(a != '--context' for a in args), 'context uses SU_TEST_CONTEXT')
        return 'guard' if '--stage' in args and args[args.index('--stage') + 1:][:1] == ['guard'] else 'native-app'
    require(not args, 'unknown direct option')
    return row.modes[0]


def admit_direct(suite, args):
    mode = invocation(suite, args)
    rule = execution_policy(suite,mode)
    path = os.environ.get('SU_TEST_CONTEXT')
    require(path, 'explicit SU_TEST_CONTEXT required')
    # Nested runtime/installed invocations require independently sealed delegation,
    # never an ambient inside-CT flag or comparison to the outer root filesystem.
    if rule.direct_phase == 'delegated':
        from test_pve import admit_delegated
        context = admit_delegated(path, suite, mode)
    else:
        context = Context.admit(path, suite, mode)
    require(Path(__file__).resolve().parents[2] == Path(context.document['source']['path']), 'entrypoint source path mismatch')
    if rule.direct_phase == 'unit':
        require(os.environ.get('L2_NATIVE_FIXTURES') == 'owned-maintenance-vm', 'native systemd fixture token required')
    if suite == 'maintenance-globnotes-lxc':
        from test_pve import strong_input
        strong_path, strong = strong_input(context)
        require('--guard-manifest' in args and args[args.index('--guard-manifest')+1] == str(strong_path), 'strong manifest selection mismatch')
        require('--ctid' in args and args[args.index('--ctid')+1] == str(context.operation['nested'][0]['ctid']), 'strong manifest CT selection mismatch')
        n = context.operation.get('native')
        require(n is not None and all(strong['topology'][k] == n[v] for k,v in
                [('bridge','bridge'),('storage','storage'),('template_storage','template_storage'),('vg','vg'),('pool','pool')]), 'strong/shared topology mismatch')
    if rule.direct_phase not in ('local','unit'):
        from test_pve import admit_scope
        admit_scope(context, rule.direct_phase)
    return context


def command_for(context):
    op = context.operation
    row = REGISTRY[op['suite']]
    root = Path(context.document['source']['path'])
    if op['suite'] in ('maintenance-globnotes-lxc','globnotes-browser'):
        from test_pve import globnotes_guard_argv
        argv = globnotes_guard_argv(context)
        if op['suite'] == 'globnotes-browser':
            argv[-1] = 'verify'
        elif op['mode'] == 'native-app':
            argv[-1] = 'all'
        return argv
    if row.path.endswith('.test.sh'):
        argv = ['/bin/bash', str(root / row.path)]
        # Ownership suite's established positional context remains unchanged.
        if op['suite'] in ('workflow-ownership', 'workflow-entrypoints'):
            return argv + [str(context.path)]
        selected = next((list(a[1:]) for a in row.args if a[0] == op['mode']), [])
        from test_inputs import bindings
        extra,_=bindings(context)
        return argv + selected + extra
    commands = {
        'go-unit': ['/usr/local/go/bin/go', 'test', '-C', str(root / 'tools/ast'), './...'],
        'go-ast': ['/usr/local/go/bin/go', 'run', '-C', str(root / 'tools/ast'), '.'],
        'catalogue': ['/usr/bin/ruby', str(root / 'tools/regen-scripts-json.rb')],
        'logos': ['/usr/bin/ruby', str(root / 'tools/validate-logos.rb')],
        'contribution': ['/usr/bin/python3','-B',str(root/'tests/lib/contribution.py')],
    }
    require(op['suite'] in commands, 'consumer requires its owning dispatch')
    return commands[op['suite']]


def dispatch(document, path, suite, mode, execute):
    context = Context.validate(document, path, suite, mode)
    preflight(context)
    argv = command_for(context)
    env = {'PATH': '/usr/local/go/bin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin',
           'TMPDIR': context.operation['tmpdir'], 'SU_TEST_CONTEXT': str(path),
           'PYTHONDONTWRITEBYTECODE': '1', 'GOTOOLCHAIN': 'local'}
    from test_inputs import bindings
    _,inputs=bindings(context)
    env.update(inputs)
    return execute(argv, env, context)


def preflight(context):
    from test_inputs import bindings
    bindings(context)
    rule = execution_policy(context.operation['suite'],context.operation['mode'])
    phase=rule.public_phase
    if phase not in ('local','unit'):
        from test_pve import admit_scope
        admit_scope(context, phase)
    return context


def execute(argv, env, context):
    rule = execution_policy(context.operation['suite'],context.operation['mode'])
    if rule.owner == 'runtime':
        from test_pve import runtime_dispatch
        return runtime_dispatch(context,argv)
    if rule.owner == 'installed':
        from test_pve import installed_dispatch
        return installed_dispatch(context,argv)
    if rule.owner == 'unit':
        env['L2_NATIVE_FIXTURES']='owned-maintenance-vm'
    require(rule.owner in ('local','unit'), 'execution owner missing')
    return subprocess.run(argv,cwd=context.document['source']['path'],env=env,timeout=context.operation['deadline']).returncode


def supervise(context,deadline):
    """Finite guest job only; outer access/lifecycle remains external."""
    from test_context import safe_parents,exclusive_json,sha
    preflight(context)
    require(type(deadline) is int and context.operation['deadline']<deadline<=3900,'supervision deadline envelope')
    op=context.operation;source=Path(context.document['source']['path'])
    contribution=(op['suite'],op['mode'])==('contribution','contribution')
    if contribution:
        from contribution import preflight as contribution_preflight
        contribution_preflight(context)
    job=Path(op['runs'])/'jobs'/op['run_id'];unit='su-test-'+op['run_id']
    state=subprocess.run(['/usr/bin/systemctl','show',unit,'-p','LoadState','--value'],capture_output=True,text=True,check=True,timeout=20).stdout.strip()
    require(state=='not-found' and not job.exists(),'owned job already exists; inspect rather than duplicate')
    if not job.parent.exists():job.parent.mkdir(mode=0o700)
    safe_parents(job.parent,root=True);job.mkdir(mode=0o700)
    for name in ('stdout.log','stderr.log'):(job/name).touch(mode=0o600,exist_ok=False)
    argv=['/usr/bin/python3','-B',str(source/'tests/run'),'--run','--context',str(context.path),'--suite',op['suite'],'--mode',op['mode']]
    body='exec 9>'+shlex.quote(str(job/'job.lock'))+'; /usr/bin/flock -n 9 || exit 75; exec '+shlex.join(argv)
    exclusive_json(job/'intent.json',dict(unit=unit,argv=argv,source=context.document['source']['tree_sha256'],context_sha256=sha(context.path.read_bytes()),ctid=op['nested'][0]['ctid'] if op['nested'] else None,deadline_seconds=deadline,started_wall=time.time(),cwd=str(source)))
    args=['/usr/bin/systemd-run','--quiet','--unit',unit,'--property','Type=exec','--property','Restart=no','--property',f'RuntimeMaxSec={deadline}','--property','TimeoutStopSec=120','--property','SendSIGKILL=no','--property','KillMode=control-group','--property','MemoryMax='+('5G' if contribution else '1G'),'--property','CPUQuota='+('400%' if contribution else '200%'),'--property','TasksMax='+('512' if contribution else '256'),'--property','UMask=0077','--property','WorkingDirectory='+str(source),'--property','StandardOutput=append:'+str(job/'stdout.log'),'--property','StandardError=append:'+str(job/'stderr.log'),'--setenv','TMPDIR='+op['tmpdir'],'--setenv','PYTHONDONTWRITEBYTECODE=1','--setenv','PATH=/usr/local/go/bin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin','/bin/bash','-c',body]
    subprocess.run(args,check=True,timeout=30)
    state=subprocess.run(['/usr/bin/systemctl','show',unit,'-p','MainPID','-p','ControlGroup','-p','ActiveState','-p','SubState'],capture_output=True,text=True,check=True,timeout=20).stdout
    pid=int(next(line.split('=',1)[1] for line in state.splitlines() if line.startswith('MainPID=')))
    process={}
    if pid and Path(f'/proc/{pid}').exists():
        process=dict(pid=pid,birth=Path(f'/proc/{pid}/stat').read_text().split(') ',1)[1].split()[19],argv=Path(f'/proc/{pid}/cmdline').read_bytes().decode().split('\0'),cgroup=Path(f'/proc/{pid}/cgroup').read_text())
    exclusive_json(job/'started.json',dict(state=state,process=process,observed_wall=time.time()))
    return dict(unit=unit,job=str(job),run_id=op['run_id'],preservation='not-yet-completed')


if __name__ == '__main__':
    try:
        c = admit_direct(sys.argv[1], sys.argv[2:])
        print('ENTRYPOINT_ADMITTED', c.operation['suite'], c.operation['mode'])
    except (AdmissionError, OSError, ValueError, IndexError, subprocess.SubprocessError) as error:
        print('CONTEXT_REFUSED:', error, file=sys.stderr)
        raise SystemExit(65)
