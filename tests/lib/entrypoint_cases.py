"""Tests-first direct entrypoint boundary, including bounded old-source controls."""
import copy
import json
import os
from pathlib import Path
import subprocess
import sys
import unittest
import contextlib
import io
import runpy
import uuid
from types import SimpleNamespace
from unittest.mock import patch

from test_context import AdmissionError, Context, Run, sha
from test_registry import REGISTRY, policy


DIRECT = {
    'maintenance-package-force': [[]],
    'maintenance-cron-update': [[]],
    'maintenance-current-hardening': [[]],
    'maintenance-kosmozoo-current': [[]],
    'maintenance-kosmozoo-native': [[]],
    'maintenance-lazylibrarian-native': [[]],
    'maintenance-bookorbit-native': [[]],
    'migration-dragonfly': [[]],
    'migration-dragonfly-native': [[]],
    'codeberg-release': [[], ['--live'], ['--bundle']],
    'romm-player-serving': [[], ['--setup']],
    'romm-live-verification': [[]],
    'uv-project-version': [[]],
    'github-force-deploy': [[]],
    'maintenance-service-systemd': [[]],
    'maintenance-service-edge-native': [[]],
    'maintenance-globnotes-lxc': [['--stage', 'guard']],
    'calibre-web-automated': [[]],
    'odysseus': [[]],
}


class Entrypoints(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.context = Context.admit(sys.argv_context, 'workflow-entrypoints', 'fixture')
        cls.run_owner = Run(cls.context)
        cls.run_owner.__enter__()
        cls.source = Path(cls.context.document['source']['path'])

    @classmethod
    def tearDownClass(cls):
        cls.run_owner.__exit__(None, None, None)

    def test_catalogue_exact_shell_set(self):
        actual = {p.relative_to(self.source).as_posix() for p in (self.source / 'tests').glob('*.test.sh')}
        declared = {r.path for r in REGISTRY.values() if r.path.endswith('.test.sh')}
        self.assertEqual(actual, declared)
        additions = {'tests/maintenance-kosmozoo-current.test.sh', 'tests/maintenance-kosmozoo-native.test.sh',
                     'tests/maintenance-current-hardening.test.sh', 'tests/maintenance-cron-update.test.sh',
                     'tests/maintenance-package-force.test.sh',
                      'tests/migration-dragonfly.test.sh', 'tests/migration-dragonfly-native.test.sh',
                       'tests/maintenance-lazylibrarian-native.test.sh',
                       'tests/maintenance-bookorbit-native.test.sh'}
        self.assertTrue(additions <= actual)
        self.assertEqual(len(actual - additions - {'tests/test-workflow-ownership.test.sh', 'tests/test-workflow-entrypoints.test.sh'}), 69)
        for suite, row in REGISTRY.items():
            for mode in row.modes:
                with self.subTest(suite=suite, mode=mode):
                    _, role, effects = policy(suite, mode)
                    self.assertTrue(role and effects)
                    d = copy.deepcopy(self.context.document)
                    # An ownership/fixture context must never authorize another role.
                    with self.assertRaises(AdmissionError):
                        Context.validate(d, self.context.path, suite, 'not-a-mode')
        print('CATALOGUE original=69 additions=9 shell=80 roles=actual-policy', flush=True)

    def test_every_registered_mode_has_fixed_source_argv(self):
        from entrypoint import command_for
        from test_registry import INPUT_BINDINGS
        # Private data fixture for source dispatch selection only. The original
        # strong native guard still runs at its actual consumer, not this callback.
        strong = self.run_owner.directory/'dispatch-strong.json'
        strong.write_text(json.dumps(dict(version=1,workspace=str(self.run_owner.directory),source={},vm={},protected={},fixtures={'2012':{}},topology={})))
        strong.chmod(0o400)
        fixture=self.run_owner.directory/'input-tree';fixture.mkdir(mode=0o700)
        leaf=fixture/'subject';leaf.write_bytes(b'input');leaf.chmod(0o755)
        from test_context import source_files
        manifest=self.run_owner.directory/'input-tree.json'
        manifest.write_text(json.dumps(dict(root=str(fixture),files=source_files(fixture))));manifest.chmod(0o400)
        self.assertEqual(set(INPUT_BINDINGS),{(s,m) for s,r in REGISTRY.items() for m in r.modes})
        cases = 0
        for suite,row in REGISTRY.items():
            for mode in row.modes:
                with self.subTest(suite=suite,mode=mode):
                    _,role,effects = policy(suite,mode)
                    d = copy.deepcopy(self.context.document)
                    op = copy.deepcopy(d['operations'][0])
                    op.update(suite=suite,mode=mode,role=role,effects=effects)
                    op['parameters']={name:dict(path=str(manifest if rule.kind=='tree' else leaf),sha256=sha((manifest if rule.kind=='tree' else leaf).read_bytes()))
                                      for name,rule in INPUT_BINDINGS[suite,mode].items() if rule.required and rule.kind in ('tree','file','executable')}
                    if suite=='maintenance-app-compat':op['parameters']['apprise_asset_path']='css/source.css'
                    recording_calls = None
                    if suite in ('maintenance-globnotes-lxc','globnotes-browser'):
                        native,recording_calls,_ = self.native_fixture()
                        op['native'] = copy.deepcopy(native.n)
                        op['nested'] = copy.deepcopy(native.run.context.operation['nested'])
                        self.assertEqual(set(json.loads(strong.read_bytes())['fixtures']),{str(op['nested'][0]['ctid'])})
                        op['inputs'] = [dict(path=str(strong),sha256=sha(strong.read_bytes()))]
                    d['operations'] = [op]
                    admitted=Context.validate(d,self.context.path,suite,mode)
                    argv=command_for(admitted)
                    self.assertTrue(any(str(self.source) in a for a in argv),argv)
                    self.assertFalse(any(a in ('ssh','eval') for a in argv))
                    if recording_calls is not None:self.assertEqual(recording_calls,[])
                    cases += 1
        self.assertEqual(cases,101)
        print('REGISTERED_SOURCE_ARGV cases='+str(cases)+' public_native_routes=separate_actual_main_test',flush=True)

    def direct(self, suite, args, context):
        # All potential effects stop at a recording executable. No legacy app
        # driver is run in the old-source control; its helpers include root SSH.
        root = self.run_owner.directory / ('direct-' + suite + '-' + str(len(list(self.run_owner.directory.iterdir()))))
        root.mkdir()
        binpath = root / 'bin'
        binpath.mkdir()
        effects = root / 'effects'
        for name in ('mktemp', 'apt', 'apt-get', 'curl', 'pct', 'pvesm', 'pveam', 'systemctl', 'ssh', 'wget', 'unshare'):
            p = binpath / name
            p.write_text('#!/bin/bash\nprintf "%s\\n" "${0##*/} $*" >> "$EFFECT_LOG"\nexit 86\n')
            p.chmod(0o755)
        env = dict(os.environ, PATH=str(binpath) + ':' + os.environ['PATH'], SU_TEST_CONTEXT=str(context),
                   SU_TEST_GUARD_ONLY='1', EFFECT_LOG=str(effects), L2_NATIVE_FIXTURES='owned-maintenance-vm')
        result = subprocess.run(['/bin/bash', str(self.source / REGISTRY[suite].path), *args],
                                env=env, cwd=self.source, capture_output=True, text=True, timeout=40)
        (root / 'result.json').write_text(json.dumps(dict(status=result.returncode, out=result.stdout, err=result.stderr)))
        return result, effects.read_text() if effects.exists() else ''

    def test_direct_bad_context_before_effects(self):
        cases = 0
        contexts = [self.run_owner.directory / 'absent.json']
        for defect in ('target','source'):
            data = copy.deepcopy(self.context.document)
            if defect == 'target':
                data['target']['uuid'] = '00000000-0000-0000-0000-000000000000'
            else:
                data['source']['files'][0]['sha256'] = '0'*64
            path = self.run_owner.directory/(defect+'-invalid-context.json')
            path.write_text(json.dumps(data))
            path.chmod(0o400)
            contexts.append(path)
        for suite, modes in DIRECT.items():
            for args in modes:
                for context in contexts:
                    with self.subTest(suite=suite, args=args, context=context.name):
                        result, effects = self.direct(suite, args, context)
                        self.assertEqual(effects, '', 'bad context reached effect before admission')
                        self.assertEqual(result.returncode, 65, result.stderr)
                        self.assertIn('CONTEXT_REFUSED', result.stderr)
                        cases += 1
        print('DIRECT_REFUSAL cases=' + str(cases) + ' effects=0', flush=True)

    def test_wrong_target_and_source_dispatch(self):
        from entrypoint import dispatch
        for mutate in ('uuid', 'source'):
            d = copy.deepcopy(self.context.document)
            if mutate == 'uuid':
                d['target']['uuid'] = '00000000-0000-0000-0000-000000000000'
            else:
                d['source']['files'][0]['sha256'] = '0' * 64
            calls = []
            with self.assertRaises(AdmissionError):
                dispatch(d, self.context.path, 'workflow-entrypoints', 'fixture', lambda *a: calls.append(a))
            self.assertEqual(calls, [])

    def test_current_hardening_direct_guard_only(self):
        result, effects = self.direct('maintenance-current-hardening', [], self.context.path)
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(effects, '')
        self.assertIn('ENTRYPOINT_ADMITTED maintenance-current-hardening fixture', result.stdout)
        print('CURRENT_HARDENING_DIRECT_GUARD admitted=1 consumer_body=0 effects=0', flush=True)

    def test_package_force_direct_guard_only(self):
        result, effects = self.direct('maintenance-package-force', [], self.context.path)
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(effects, '')
        self.assertIn('ENTRYPOINT_ADMITTED maintenance-package-force fixture', result.stdout)
        print('PACKAGE_FORCE_DIRECT_GUARD admitted=1 consumer_body=0 effects=0', flush=True)

    def test_valid_fixed_dispatch(self):
        from entrypoint import dispatch
        calls = []
        dispatch(self.context.document, self.context.path, 'workflow-entrypoints', 'fixture', lambda *a: calls.append(a))
        self.assertEqual(len(calls), 1)
        self.assertEqual(calls[0][0][:2], ['/bin/bash', str(self.source / 'tests/test-workflow-entrypoints.test.sh')])

    def input_context(self,suite,mode,parameters):
        document=copy.deepcopy(self.context.document)
        _,role,effects=policy(suite,mode)
        op=dict(self.context.operation,suite=suite,mode=mode,role=role,effects=effects,nested=[],parameters=parameters)
        op.pop('native',None);document['operations']=[op]
        path=self.run_owner.directory/('inputs-'+uuid.uuid4().hex+'.json')
        path.write_text(json.dumps(document));path.chmod(0o400)
        return document,path,op

    def test_named_baseline_and_prerequisite_public_dispatch(self):
        from entrypoint import dispatch
        literal=self.run_owner.directory/'baseline ; $(literal).func'
        literal.write_text('literal subject\n');literal.chmod(0o400)
        reference=dict(path=str(literal),sha256=sha(literal.read_bytes()))
        for suite,mode,name,expected in [('maintenance-template-lock','review-baseline','baseline',None),
                                       ('maintenance-gpg-key','fixture','gpg_fixture','GPG_FIXTURE')]:
            document,path,op=self.input_context(suite,mode,{name:reference});calls=[]
            # Isolate propagation from the new schema, so the old dispatcher
            # fails on the actual lost argv/environment value, not schema setup.
            with patch.object(Context,'validate',return_value=Context(document,path,op)):
                dispatch(document,path,suite,mode,lambda *args:calls.append(args))
            self.assertEqual(len(calls),1)
            argv,env,_=calls[0]
            if expected:self.assertEqual(env[expected],str(literal))
            else:self.assertEqual(argv[-2:],['--review-baseline',str(literal)])
        self.assertFalse((self.run_owner.directory/'literal').exists())

    def test_required_named_input_refuses_before_run(self):
        from entrypoint import dispatch
        for suite,mode,name in [('maintenance-template-lock','baseline','baseline'),
                               ('maintenance-gpg-key','fixture','gpg_fixture'),
                                ('maintenance-node24-vite','fixture','runtime_extra_references'),
                                ('maintenance-lazylibrarian-native','bundle','lazylibrarian_fixture')]:
            document,path,op=self.input_context(suite,mode,{})
            del op['parameters']
            path.write_text(json.dumps(document));path.chmod(0o400)
            with patch('test_context.Run.__enter__') as run:
                with self.assertRaisesRegex(AdmissionError,'required input.*'+name):
                    dispatch(document,path,suite,mode,lambda *a:self.fail('missing input dispatched'))
                run.assert_not_called()

    def test_named_input_unknown_hash_path_type_before_effects(self):
        from entrypoint import dispatch
        p=self.run_owner.directory/'key fixture';p.write_bytes(b'key');p.chmod(0o400)
        good=dict(path=str(p),sha256=sha(p.read_bytes()))
        for parameters in ({'PATH':good},{'gpg_fixture':dict(good,sha256='0'*64)},
                           {'gpg_fixture':dict(good,path=str(p.parent/'..'/p.name))},
                           {'gpg_fixture':True}):
            document,path,_=self.input_context('maintenance-gpg-key','fixture',parameters)
            calls=[]
            with self.assertRaises(AdmissionError):dispatch(document,path,'maintenance-gpg-key','fixture',lambda *a:calls.append(a))
            self.assertEqual(calls,[])

    def test_named_input_inventory_and_scalar_tree_contracts(self):
        import re
        from test_registry import INPUT_BINDINGS
        from test_inputs import bindings
        from test_context import source_files
        # Actual entrypoint declarations, not helper-local fixture variables.
        for suite,row in REGISTRY.items():
            if not row.path.endswith('.test.sh'):continue
            required=set(re.findall(r'\$\{([A-Z_]+):\?', '\n'.join(line for line in (self.source/row.path).read_text().splitlines() if line.startswith(': '))))-{'TMPDIR','L2_NATIVE_FIXTURES'}
            for mode in row.modes:
                self.assertLessEqual(required,{r.target for r in INPUT_BINDINGS[suite,mode].values()},suite+'/'+mode)
        tree=self.run_owner.directory/'references ; literal';tree.mkdir(mode=0o700)
        leaf=tree/'ref';leaf.write_bytes(b'original');leaf.chmod(0o400)
        manifest=self.run_owner.directory/'references.json';manifest.write_text(json.dumps(dict(root=str(tree),files=source_files(tree))));manifest.chmod(0o400)
        parameters={'maintenance_references':dict(path=str(manifest),sha256=sha(manifest.read_bytes()))}
        d,p,op=self.input_context('maintenance-runtime-hooks','fixture',parameters)
        self.assertEqual(bindings(Context(d,p,op))[1]['MAINTENANCE_REFERENCES'],str(tree))
        leaf.write_bytes(b'changed')
        with self.assertRaisesRegex(AdmissionError,'tree bytes'):bindings(Context(d,p,op))
        d,p,op=self.input_context('maintenance-replacement-review','fixture',{'large_size':50000})
        # Required executable omitted only to isolate dependent budget validation.
        with self.assertRaisesRegex(AdmissionError,'budget_workspace'):bindings(Context(d,p,op),required=False)
        for value in (True,0,-1,'50000',2**64):
            op['parameters']={'large_size':value}
            with self.assertRaises(AdmissionError):bindings(Context(d,p,op),required=False)
        op['parameters']={'large_size':50000,'budget_workspace':op['runs'],'budget_bytes':1024**3}
        self.assertEqual(bindings(Context(d,p,op),required=False)[1]['REPLACEMENT_LARGE_SIZE'],'50000')

    def test_public_existing_baseline_and_gpg_consumers(self):
        key=self.run_owner.directory/'public key ; literal.gpg'
        key.write_bytes(Path('/usr/share/keyrings/debian-archive-keyring.gpg').read_bytes());key.chmod(0o400)
        for suite,mode,name,subject,marker in [
            ('maintenance-template-lock','review-baseline','baseline',self.source/'misc/build.func','0 failure(s)'),
            ('maintenance-gpg-key','fixture','gpg_fixture',key,'0 failure(s)'),
        ]:
            document,path,op=self.input_context(suite,mode,{name:dict(path=str(subject),sha256=sha(subject.read_bytes()))})
            result=subprocess.run(['/usr/bin/python3','-B',str(self.source/'tests/run'),'--run','--context',str(path),'--suite',suite,'--mode',mode],
                                  env=dict(os.environ,TMPDIR=op['tmpdir']),cwd=self.source,capture_output=True,text=True,timeout=650)
            self.run_owner.record('named-input-consumer',dict(suite=suite,mode=mode,parameters=op['parameters'],status=result.returncode,stdout=result.stdout,stderr=result.stderr))
            self.assertEqual(result.returncode,0,result.stdout+'\n'+result.stderr)
            self.assertIn(marker,result.stdout)
        print('NAMED_INPUT_ACTUAL_PUBLIC_CONSUMERS template_review_baseline=0 real_GPG=0 native_pve_models=retained',flush=True)

    def test_existing_lineage_generic_identity_source_and_receipt_negatives(self):
        from test_context import Resource
        from test_pve import existing_lineage
        c,parent,observed=self.review_context('romm-live-verification','installed-probe')
        path=Path(c.operation['native']['lineage']);raw=path.read_bytes();initial=json.loads(raw)
        before=self.tree_state(parent)
        with patch('test_pve.NativePVE.observe_static',return_value=Resource(**observed)) as observe,patch('test_pve.admit_topology'),patch('test_pve.NativePVE._process') as effects:
            self.assertEqual(existing_lineage(c),initial)
            for wrong in (None,Resource(**dict(observed,volume_uuid='wrong')),Resource(**dict(observed,tag='foreign')),Resource(**dict(observed,mac='02:96:99:99:99:99'))):
                observe.return_value=wrong
                with self.assertRaises(AdmissionError):existing_lineage(c)
            observe.return_value=Resource(**observed)
            for changed in (dict(initial,source='f'*64),dict(initial,status=17),dict(initial,requested=dict(initial['requested'],ctid=9999)),dict(initial,unexpected='command')):
                path.write_text(json.dumps(changed));path.chmod(0o400)
                with self.assertRaises(AdmissionError):existing_lineage(c)
            path.write_bytes(raw);path.chmod(0o400);effects.assert_not_called()
        self.assertEqual(path.read_bytes(),raw)

    def test_native_broker_receiving_kernel_lineage_and_obsolete_action(self):
        import socket
        from mounted_root import birth
        from test_pve import Broker
        native,calls,argv=self.native_fixture();native.dispatch('pct',argv)
        count=len(calls)
        with Broker(native) as address:
            native.mount.consumer=dict(pid=os.getpid(),birth=birth(os.getpid()))
            for request in (dict(tool='framework-existing',argv=[]),dict(tool='pct',argv=['exec','2012','--','true'],environment={})):
                with socket.socket(socket.AF_UNIX) as client:
                    client.settimeout(10);client.connect('\0'+address[1:]);client.sendall(json.dumps(request).encode()+b'\n')
                    with client.makefile('rb') as stream:value=json.loads(stream.readline())
                self.assertEqual(value['status'],65);self.assertEqual(len(calls),count)
            native.mount.consumer['birth']='stale'
            with self.assertRaisesRegex(AdmissionError,'birth'):native.mount.peer(os.getpid())
        native.owner.finish(17)

    def test_obsolete_public_options_zero_effects(self):
        cli=runpy.run_path(str(self.source/'tests/run'),run_name='obsolete_options')
        for option in ('--resume','--native-preflight','--framework-existing'):
            with patch.object(sys,'argv',['tests/run','--run',option]),patch.object(Context,'admit') as admission,patch('entrypoint.execute') as effects,contextlib.redirect_stderr(io.StringIO()):
                with self.assertRaises(SystemExit) as error:cli['main']()
                self.assertEqual(error.exception.code,2);admission.assert_not_called();effects.assert_not_called()
        self.assertNotIn('model',REGISTRY['maintenance-template-lock'].modes)
        for action in ('--check','--run'):
            with patch.object(sys,'argv',['tests/run',action,'--context',str(self.context.path),'--suite','maintenance-template-lock','--mode','model']),patch('entrypoint.execute') as effects:
                with self.assertRaisesRegex(AdmissionError,'not registered'):cli['main']()
                effects.assert_not_called()

    def test_direct_valid_fixture_and_native_token(self):
        for suite in ('codeberg-release', 'maintenance-service-systemd', 'maintenance-service-edge-native'):
            result, effects = self.direct(suite, [], self.context.path)
            self.assertEqual(result.returncode, 0, result.stderr)
            self.assertEqual(effects, '')
            self.assertIn('ENTRYPOINT_ADMITTED', result.stdout)
        # App create admission's positive uses explicitly recording observations:
        # a real preserved CT must never be made to look absent for this test.
        from entrypoint import admit_direct
        with patch.dict(os.environ,SU_TEST_CONTEXT=str(self.context.path)),patch('test_pve.NativePVE.observe_static',return_value=None),patch('test_pve.admit_resources'):
            for suite in ('calibre-web-automated','odysseus'):
                self.assertEqual(admit_direct(suite,[]).operation['suite'],suite)
        print('DIRECT_GUARD_ONLY admitted=5 actual_direct=3 app_native_observation=recording consumer_body=0 native_effects=0', flush=True)

    def native_fixture(self):
        from test_context import Resource
        from test_pve import NativePVE
        from ownership_cases import RecordingNative
        root = self.run_owner.directory / ('native-' + str(len(list(self.run_owner.directory.iterdir()))))
        root.mkdir()
        recorder = RecordingNative(root)
        spec = Resource(2012, 'su-workflow-'+uuid.uuid4().hex, '52:54:00:aa:bb:cc', 'su-fixture', 'su-thin', 'vm-2012-disk-0', 'pending')
        n = dict(bridge='vmbr0', address='172.29.42.1', storage='su-thin', template_storage='su-files', vg='su_data', pool='nested',
                 cpu=2, ram=2048, disk=8, template='debian-13-standard_13.6-1_amd64.tar.zst', template_sha256='0'*64,
                 receiver_tmpdir='/var/lib/scripts-underground-test/tmp', budgets=dict(root_free=1, workspace_peak=1, thin_peak=1, memory_peak=1), lineage=None)
        op = dict(self.context.operation, native=n, nested=[spec.__dict__])
        run = SimpleNamespace(context=SimpleNamespace(operation=op, recheck=self.context.recheck,document=self.context.document,path=self.context.path), directory=root, record=self.run_owner.record)
        calls = []
        def call(tool, args):
            calls.append((tool, list(args)))
            action = args[0]
            if tool == 'pct' and action in ('create', 'stop', 'shutdown', 'destroy'):
                recorder.invoke('stop' if action=='shutdown' else action, spec)
            return subprocess.CompletedProcess(args, 0, 'status: stopped\n' if action == 'status' else '', '')
        native = NativePVE(run, call=call)
        # PVE lifecycle below is a recording model, including the offline mount
        # and static-service consumer. Real filesystem policy controls are separate.
        native.prepare_service_policy=lambda:None
        native.verify_service_policy=lambda:None
        native.observe = recorder.observe
        argv = ['create','2012','su-files:vztmpl/'+n['template'], '-hostname',spec.hostname,'-tags','community-script,'+spec.tag,
                '-cores','2','-memory','2048','-unprivileged','1','-rootfs','su-thin:8','-onboot','1',
                '-features','nesting=1,keyctl=1','-net0','name=eth0,bridge=vmbr0,ip=dhcp,hwaddr='+spec.mac]
        return native, calls, argv

    def test_native_creation_boundary_refuses_changed_scope(self):
        for field, replacement in [('2012','9999'), ('su-thin:8','local-lvm:8'), ('2048','8192'),
                                    ('nesting=1,keyctl=1','nesting=0'), ('community-script,su-workflow-testtoken','community-script,foreign')]:
            native, calls, argv = self.native_fixture()
            if field=='community-script,su-workflow-testtoken':field=argv[argv.index('-tags')+1]
            argv[argv.index(field)] = replacement
            with self.assertRaises(AdmissionError):
                native.dispatch('pct', argv)
            self.assertEqual(calls, [])
        print('NATIVE_CREATE_REFUSAL cases=5 actual_adapter=1 native_effects=0', flush=True)

    def test_storage_fallback_before_activation_download(self):
        for tool, argv in [('pvesm',['list','local','--content','vztmpl']), ('pvesm',['path','local:vztmpl/debian.tar.zst']),
                           ('pvesm',['alloc','local','2012','disk','8G']), ('pveam',['download','local','debian.tar.zst']),
                           ('pveam',['update'])]:
            native, calls, _ = self.native_fixture()
            with self.assertRaises(AdmissionError):
                native.dispatch(tool, argv)
            self.assertEqual(calls, [])
        print('NATIVE_STORAGE_REFUSAL cases=5 activation_download=0', flush=True)

    def test_unowned_secondary_volume_prevents_absent_id_adoption(self):
        from test_pve import NativePVE
        native, calls, _ = self.native_fixture()
        for vg in ('su_data','foreign_vg'):
            volumes = json.dumps({'report':[{'lv':[{'vg_name':vg,'lv_name':'vm-4042-disk-1','lv_uuid':'foreign'}]}]})
            with patch('test_pve.query',return_value=volumes):
                with self.assertRaisesRegex(AdmissionError,'unowned root volume'):
                    NativePVE.observe_static(4042,native.n)
            self.assertEqual(calls,[])

    def test_native_start_prepares_receiver_before_returning(self):
        native, calls, argv = self.native_fixture()
        self.assertEqual(native.dispatch('pct', argv).returncode, 0)
        calls.clear()
        self.assertEqual(native.dispatch('pct', ['start', '2012']).returncode, 0)
        self.assertEqual(calls[0], ('pct', ['start', '2012']))
        self.assertGreater(len(calls), 1, 'start returned without preparing the service receiver')
        receiver = calls[-1][1]
        self.assertEqual(receiver[:3], ['exec', '2012', '--'])
        self.assertIn('TMPDIR=' + native.n['receiver_tmpdir'], receiver)
        self.assertIn(native.n['receiver_tmpdir'], receiver)
        body = receiver[receiver.index('-ec') + 1]
        syntax = subprocess.run(['/bin/sh', '-n'], input=body, capture_output=True, text=True, timeout=10)
        self.assertEqual(syntax.returncode, 0, syntax.stderr)
        self.assertTrue(any('systemctl show-environment' in a and '1777' in a and 'mktemp' in a for a in receiver))
        print('NATIVE_START_RECEIVER root_parents_disk_sticky_user_write_manager_environment native=recording', flush=True)

    def test_framework_stop_is_graceful_and_failed_stop_blocks_mount(self):
        native,calls,argv=self.native_fixture()
        self.assertEqual(native.dispatch('pct',argv).returncode,0)
        self.assertEqual(native.dispatch('pct',['stop','2012']).returncode,0)
        self.assertIn(('pct',['shutdown','2012','--timeout','120','--forceStop','0']),calls)
        self.assertFalse(any(a[0]=='stop' for _,a in calls),'framework requested a force stop')
        self.assertIn(('pct',['status','2012']),calls)
        other,failed,other_argv=self.native_fixture()
        self.assertEqual(other.dispatch('pct',other_argv).returncode,0)
        def fail(tool,args):
            failed.append((tool,args))
            return subprocess.CompletedProcess(args,31 if args[0]=='shutdown' else 0,'status: running\n' if args[0]=='status' else '','')
        other.call=fail
        self.assertEqual(other.dispatch('pct',['stop','2012']).returncode,31)
        with self.assertRaises(AdmissionError):other.dispatch('pct',['mount','2012'])
        self.assertFalse(any(a[0] in ('mount','stop') for _,a in failed))
        print('FRAMEWORK_TYPED_STOP requested_stop actual_graceful_shutdown_forceStop0 stopped_identity=recording',flush=True)

    def test_owned_mount_consumer_namespace_projection_and_foreign_controls(self):
        from test_pve import Broker
        from mounted_root import same_node,identity
        import stat
        native,calls,argv=self.native_fixture();self.assertEqual(native.dispatch('pct',argv).returncode,0)
        native.run.context.document=self.context.document
        parent=native.run.directory;backing=parent/'backing';target=parent/'target';backing.mkdir();target.mkdir()
        (backing/'owned.txt').write_text('model volume consumer bytes\n')
        m=native.mount;m.path=str(target);baseline='rootfs: su-thin:vm-2012-disk-0\nonboot: 0\n';state={'config':baseline}
        m.config=lambda:state['config']
        actual_mounted=m.mounted
        def mounted():
            row=actual_mounted()
            return dict(row,root='/') if row else None  # modeled PVE volume root; real private bind below
        m.mounted=mounted
        s=backing.stat();m.backing=lambda:SimpleNamespace(st_mode=stat.S_IFBLK,st_rdev=s.st_dev)
        def call(tool,args):
            calls.append((tool,args))
            if args[0]=='mount':
                subprocess.run(['/bin/mount','--bind',str(backing),str(target)],check=True,timeout=10)
                state['config']=baseline+'lock: mounted\n'
                return subprocess.CompletedProcess(args,0,"mounted CT 2012 in '/var/lib/lxc/2012/rootfs'\n",'')
            if args[0]=='unmount':
                subprocess.run(['/bin/umount',str(target)],check=True,timeout=10);state['config']=baseline
            return subprocess.CompletedProcess(args,0,'status: stopped\n' if args[0]=='status' else '','')
        native.call=call
        returned=[];original_open=m.open
        def opened(peer):
            result=original_open(peer);returned.append(result.stdout)
            from mounted_root import project_output
            legacy,grammar=project_output('mounted at /var/lib/lxc/2012/rootfs\n',2012,'/proc/'+str(m.pid)+'/root'+m.path)
            self.assertEqual(grammar,'legacy')
            parsed=subprocess.run(['/usr/bin/grep','-oP',r'mounted at \K.*'],input=legacy,text=True,capture_output=True,timeout=10)
            self.assertEqual(parsed.returncode,0)
            self.assertTrue(same_node(identity(parsed.stdout.strip()),identity(backing)))
            return result
        m.open=opened
        with self.assertRaisesRegex(AdmissionError,'verified mount consumer'):native.dispatch('pct',['mount','2012'])
        with patch.object(m,'peer',return_value=dict(pid=os.getpid(),birth='model',namespace='model',peer=os.getpid(),peer_birth='model')),patch.object(m,'mounted',return_value={'foreign':'mount'}):
            with self.assertRaisesRegex(AdmissionError,'foreign mount'):native.dispatch('pct',['mount','2012'])
        self.assertFalse(any(a[0]=='mount' for _,a in calls),'negative controls reached native mount')
        body='''import pathlib,re,subprocess
r=subprocess.run(['/usr/sbin/pct','mount','2012'],check=True,capture_output=True,text=True,timeout=10)
m=re.fullmatch("mounted CT 2012 in '([^']+)'\\n?",r.stdout);assert m
print((pathlib.Path(m.group(1))/'owned.txt').read_text(),end='')
subprocess.run(['/usr/sbin/pct','unmount','2012'],check=True,timeout=10)
'''
        prefix=['/usr/bin/unshare','--mount','--propagation','private','/bin/bash',str(self.source/'tests/lib/native-launch.sh'),str(self.source),'/usr/bin/python3','-B','-c',body]
        try:
            with Broker(native) as sock,(parent/'consumer.log').open('x') as log:
                status=native.child(prefix,dict(os.environ,SU_TEST_NATIVE_SOCKET=str(sock)),log,seconds=20)
            self.assertEqual(status,0,(parent/'consumer.log').read_text())
            self.assertIn('model volume consumer bytes',(parent/'consumer.log').read_text())
            visible=json.loads(max(self.run_owner.directory.glob('*-root-mount-visible.json')).read_text())
            self.assertTrue(same_node(visible['broker_root'],visible['projected_consumer_root']))
            self.assertFalse(same_node(visible['broker_root'],visible['unprojected_consumer_root']))
            self.assertIsNone(actual_mounted());self.assertEqual(state['config'],baseline)
            self.assertFalse(same_node(identity(target),identity(backing)))
            def product_parser(output):
                result=subprocess.run(['/usr/bin/grep','-oP',r'mounted at \K.*'],input=output,text=True,capture_output=True,timeout=10)
                self.assertIn(result.returncode,(0,1))
                return result.stdout.strip()
            self.assertEqual(bool(product_parser(visible['native_stdout'])),bool(product_parser(returned[-1])),
                             'adapter changed actual framework parser branch')
            self.assertEqual(len(visible['native_stdout'].splitlines()),len(returned[-1].splitlines()),'adapter added native output lines')
        finally:
            if actual_mounted() is not None and same_node(identity(target),identity(backing)):
                subprocess.run(['/bin/umount',str(target)],check=True,timeout=10)
        print('OWNED_MOUNT_NAMESPACE private_namespace_bind_and_consumer=actual PVE_device_config_effects=recording unprojected_wrong_inode_refused foreign_unowned_controls=zero_mount',flush=True)

    def test_mount_output_grammar_preserves_product_parser(self):
        from mounted_root import project_output
        canonical='/var/lib/lxc/2010/rootfs';proxy='/proc/123/root'+canonical
        for raw in ("mounted CT 2010 in '"+canonical+"'",'mounted at '+canonical):
            for newline in ('','\n'):
                before=raw+newline;after,grammar=project_output(before,2010,proxy)
                self.assertEqual(after,before.replace(canonical,proxy))
                self.assertEqual(after.replace(proxy,canonical),before)
                a=subprocess.run(['/usr/bin/grep','-oP',r'mounted at \K.*'],input=before,text=True,capture_output=True,timeout=10)
                b=subprocess.run(['/usr/bin/grep','-oP',r'mounted at \K.*'],input=after,text=True,capture_output=True,timeout=10)
                self.assertEqual(a.returncode,b.returncode)
                if grammar=='legacy':self.assertEqual((a.stdout.strip(),b.stdout.strip()),(canonical,proxy))
                else:self.assertEqual((a.stdout,b.stdout),('',''))
        for bad in ('warning\nmounted at '+canonical+'\n','mounted at '+canonical+'\nmounted at '+canonical+'\n',"mounted CT 9999 in '"+canonical+"'\n"):
            with self.assertRaises(AdmissionError):project_output(bad,2010,proxy)
        print('MOUNT_OUTPUT_FIDELITY current_unrecognized legacy_recognized exact_path_only quoting_linecount_other_bytes_preserved unknown_ambiguous_refused legacy_same_node=separate_actual_namespace_model',flush=True)

    def test_native_success_create_then_literal_exec_and_preserve(self):
        native, calls, argv = self.native_fixture()
        self.assertEqual(native.dispatch('pct', argv).returncode, 0)
        native.dispatch('pct', ['exec', '2012', '--', 'printf', '%s', 'space;$(never) *'])
        self.assertEqual(calls[-1], ('pct', ['exec', '2012', '--', *native.receiving_argv(['printf','%s','space;$(never) *'])]))
        with self.assertRaises(AdmissionError):
            native.dispatch('pct', ['destroy', '2012'])
        self.assertEqual(native.owner.finish(17), 17)
        self.assertIsNotNone(native.observe(2012))
        self.assertIn(('pct',['shutdown','2012','--timeout','120','--forceStop','0']),calls)
        self.assertIn(('pct',['status','2012']),calls)
        self.assertEqual((native.run.directory/'2012.state').read_text(),'stopped')
        self.assertFalse(any(args[0] == 'destroy' for _, args in calls))

    def test_native_exec_optional_separator_preserves_literal_consumer(self):
        native,calls,argv=self.native_fixture();self.assertEqual(native.dispatch('pct',argv).returncode,0)
        original=native.call
        def call(tool,args):
            if tool=='pct' and args[0]=='exec':
                calls.append((tool,args))
                return subprocess.run(['/usr/bin/env','-i',*args[3:]],capture_output=True,text=True,timeout=10)
            return original(tool,args)
        native.call=call;literal='space ;$(not-executed) *'
        commands=[]
        for separator in (['--'],[]):
            result=native.dispatch('pct',['exec','2012',*separator,'/usr/bin/printf','%s',literal])
            self.assertEqual(result.returncode,0,result.stderr);self.assertEqual(result.stdout,literal)
            commands.append(calls[-1][1])
        self.assertEqual(commands[0],commands[1],'optional native separator changed consumer argv')
        before=list(calls)
        for args in (['exec','2012'],['exec','2012','--'],['exec','2012','--keep-env','0','/bin/true']):
            with self.assertRaises(AdmissionError):native.dispatch('pct',args)
            self.assertEqual(calls,before)
        print('NATIVE_EXEC_GRAMMAR native_optional_separator both_forms_same_root_receiver_literal_consumer=actual unsupported_options_missing_command_refused native=recording',flush=True)

    def test_request_local_receiving_session_log_and_no_environment_leak(self):
        from test_pve import Broker
        native,calls,argv=self.native_fixture();self.assertEqual(native.dispatch('pct',argv).returncode,0)
        receiver=native.run.directory/'receiver-root';receiver.mkdir(mode=0o700)
        original=native.call
        def call(tool,args):
            if tool=='pct' and args[0]=='exec':
                calls.append((tool,args))
                wrapper='mount --make-rprivate /; mount --bind "$1" /root; shift; exec "$@"'
                return subprocess.run(['/usr/bin/unshare','--mount','--propagation','private','/bin/bash','-c',wrapper,'--',str(receiver),*args[3:]],capture_output=True,text=True,timeout=20)
            return original(tool,args)
        native.call=call
        consumer='''import json,os,pathlib,sys
sid=os.environ.get('SESSION_ID');log=os.environ.get('INSTALL_LOG')
if sid and log:
 pathlib.Path(log).write_text(sys.argv[1]);pathlib.Path('/root/.install-'+sid+'.failed').write_text('17')
print(json.dumps({k:os.environ.get(k) for k in ('SESSION_ID','INSTALL_LOG','VERBOSE','MODE','CTID','tz','HOME','TMPDIR','_HOST_LOGFILE','GITHUB_TOKEN','SSH_AUTH_SOCK')}))
'''
        literal='literal ;$(not-executed) *'
        code='''import os,subprocess,sys
os.environ.update(SESSION_ID='a1b2c3d4',INSTALL_LOG='/root/.install-a1b2c3d4.log',VERBOSE='yes',MODE='default',CTID='2012',tz='host',_HOST_LOGFILE='/host-only/private.log',GITHUB_TOKEN='never-forward',SSH_AUTH_SOCK='/host-only/agent')
argv=['/usr/sbin/pct','exec','2012','--','/usr/bin/python3','-B','-c',sys.argv[1],sys.argv[2]]
for i in range(2):
 if i:
   for k in ('SESSION_ID','INSTALL_LOG','VERBOSE','MODE','CTID','tz'):os.environ.pop(k,None)
 r=subprocess.run(argv,capture_output=True,text=True,check=True,timeout=25);print(r.stdout,end='',flush=True)
'''
        prefix=['/usr/bin/unshare','--mount','--propagation','private','/bin/bash',str(self.source/'tests/lib/native-launch.sh'),str(self.source),'/usr/bin/python3','-B','-c',code,consumer,literal]
        with Broker(native) as sock,(native.run.directory/'receiving-context.log').open('x') as log:
            status=native.child(prefix,dict(os.environ,SU_TEST_NATIVE_SOCKET=str(sock)),log,seconds=60)
        self.assertEqual(status,0,(native.run.directory/'receiving-context.log').read_text())
        rows=[json.loads(v) for v in (native.run.directory/'receiving-context.log').read_text().splitlines()]
        self.assertEqual(len(rows),2)
        self.assertEqual(rows[0]['SESSION_ID'],'a1b2c3d4','broker dropped exported receiving session')
        self.assertEqual(rows[0]['INSTALL_LOG'],'/root/.install-a1b2c3d4.log')
        self.assertEqual(rows[0]['VERBOSE'],'yes');self.assertEqual(rows[0]['MODE'],'default');self.assertEqual(rows[0]['CTID'],'2012')
        self.assertEqual(rows[0]['tz'],'host')
        self.assertEqual((receiver/'.install-a1b2c3d4.log').read_text(),literal)
        self.assertEqual((receiver/'.install-a1b2c3d4.failed').read_text(),'17')
        for row in rows:
            self.assertEqual(row['HOME'],'/root');self.assertEqual(row['TMPDIR'],native.n['receiver_tmpdir'])
            for key in ('_HOST_LOGFILE','GITHUB_TOKEN','SSH_AUTH_SOCK'):self.assertIsNone(row[key])
        for key in ('SESSION_ID','INSTALL_LOG','VERBOSE','MODE','CTID','tz'):self.assertIsNone(rows[1][key],'receiving context leaked across requests')
        print('RECEIVING_REQUEST_CONTEXT session_log_flag_and_literal_consumer=actual private_receiver_root=actual_bind PVE_exec=recording forbidden_env_absent second_request_absent=1',flush=True)

    def test_receiving_timezone_native_data_and_empty_environment_consumer(self):
        from receiving_context import validate
        native,calls,argv=self.native_fixture();self.assertEqual(native.dispatch('pct',argv).returncode,0)
        original=native.call
        def call(tool,args):
            if tool=='pct' and args[0]=='exec':
                calls.append((tool,args))
                return subprocess.run(['/usr/bin/env','-i',*args[3:]],capture_output=True,text=True,timeout=10)
            return original(tool,args)
        native.call=call
        consumer='import json,os,sys;print(json.dumps(dict(tz=os.environ.get("tz"),literal=sys.argv[1],home=os.environ.get("HOME"),tmpdir=os.environ.get("TMPDIR"),forbidden=os.environ.get("BASH_ENV"))))'
        literal='literal ;$(not-executed) *'
        supported=['host','UTC','Etc/UTC','Etc/GMT+5','Europe/Berlin','GMT']
        for zone in supported:
            self.assertEqual(validate(dict(tz=zone),native.run.context,2012),dict(tz=zone))
            result=native.dispatch('pct',['exec','2012','--','python3','-B','-c',consumer,literal],environment=dict(tz=zone))
            self.assertEqual(result.returncode,0,result.stderr);value=json.loads(result.stdout)
            self.assertEqual(value,dict(tz=zone,literal=literal,home='/root',tmpdir=native.n['receiver_tmpdir'],forbidden=None))
        result=native.dispatch('pct',['exec','2012','--','python3','-B','-c',consumer,literal])
        self.assertIsNone(json.loads(result.stdout)['tz'],'previous request timezone leaked')
        before=list(calls)
        for zone in ('','/etc/passwd','../UTC','Europe/../UTC','Europe//Berlin','UTC/','UTC\n','UTC\r','UTC\t','UTC;id','zone.tab','tzdata.zi','Europe/NoSuchZone','a'*256):
            with self.assertRaises(AdmissionError):native.dispatch('pct',['exec','2012','--','true'],environment=dict(tz=zone))
            self.assertEqual(calls,before)
        with self.assertRaises(AdmissionError):native.dispatch('pct',['exec','2012','--','true'],environment=dict(tz='host',BASH_ENV='/foreign'))
        self.assertEqual(calls,before)
        print('RECEIVING_TZ sentinel_host_native_TZif_zones_aliases exact_emptyenv_consumer_literal request_local absent_noleak path_control_nonzone_forbidden_fields_refused native=recording',flush=True)

    def test_receiving_context_closed_fields_and_bindings(self):
        from receiving_context import capture,validate
        native,calls,argv=self.native_fixture();self.assertEqual(native.dispatch('pct',argv).returncode,0)
        forbidden={k:'never-forward' for k in ('HOME','PATH','TMPDIR','PASSWORD','BUILD_LOG','_HOST_LOGFILE','BASH_ENV','PYTHONPATH','LD_PRELOAD','SSH_AUTH_SOCK','GITHUB_TOKEN')}
        self.assertEqual(capture(forbidden),{})
        valid=dict(SESSION_ID='a1b2c3d4',INSTALL_LOG='/root/.install-a1b2c3d4.log',CTID='2012',VERBOSE='yes',MODE='default')
        self.assertEqual(validate(valid,native.run.context,2012),valid)
        before=list(calls)
        for bad in [dict(valid,BASH_ENV='/host-only/evil'),dict(valid,CTID='9999'),dict(valid,SESSION_ID='literal;bad'),dict(valid,INSTALL_LOG='/creator/install.log'),dict(valid,INSTALL_LOG='/root/.install-deadbeef.log'),dict(valid,VERBOSE='arbitrary'),[]]:
            with self.assertRaises(AdmissionError):native.dispatch('pct',['exec','2012','--','/bin/true'],environment=bad)
            self.assertEqual(calls,before)
        print('RECEIVING_CONTEXT_SCHEMA fixed_allowset forbidden_ambient_not_captured forged_fields_wrong_target_session_log_option_types_refused native_effects=0',flush=True)

    def test_unbound_installed_probe_refuses(self):
        result, effects = self.direct('romm-live-verification', [], self.context.path)
        self.assertEqual(result.returncode, 65)
        self.assertEqual(effects, '')

    def test_delegated_namespace_root_source_contract(self):
        from test_pve import admit_delegated, admit_scope
        native, _, _ = self.native_fixture()
        original = copy.deepcopy(self.context.document)
        op = dict(native.run.context.operation,suite='romm-live-verification',mode='installed-probe',role='installed-probe',effects=['installed-probe'])
        op['native'] = dict(op['native'],lineage=str(self.run_owner.directory/'model-lineage.json'))
        original['operations'] = [op]
        root = Path('/').stat()
        d = dict(schema=1,context_sha256=sha(self.context.path.read_bytes()),suite=op['suite'],mode=op['mode'],resource=op['nested'][0],
                 namespaces={k:os.readlink('/proc/self/ns/'+k) for k in ('mnt','pid','user')},root=[root.st_dev,root.st_ino],source=original['source']['tree_sha256'])
        lineage = dict(requested=d['resource'],observed=d['resource'],status=0,source=d['source'])
        # Parsed-data seam only: never writes or blesses an authoritative context.
        path = self.run_owner.directory/'model-delegation.json'
        def read(p):
            return {str(path):d,str(self.context.path):original,op['native']['lineage']:lineage}[str(p)]
        with patch('test_pve.read_custody',side_effect=read),patch.dict(os.environ,SU_TEST_DELEGATION=str(path),TMPDIR=op['native']['receiver_tmpdir']):
            c = admit_delegated(self.context.path,op['suite'],op['mode'])
            admit_scope(c,'delegated')
            d['root'][1] += 1
            with self.assertRaisesRegex(AdmissionError,'root'):
                admit_delegated(self.context.path,op['suite'],op['mode'])
            d['root'][1] -= 1
            d['namespaces']['pid'] = 'pid:[foreign]'
            with self.assertRaisesRegex(AdmissionError,'namespace'):
                admit_delegated(self.context.path,op['suite'],op['mode'])
        print('DELEGATION_CONTRACT namespace_root_source=actual resource_lineage=recording effects=0',flush=True)

    def test_native_absolute_path_and_timeout_child_are_intercepted(self):
        from test_pve import Broker
        native, calls, argv = self.native_fixture()
        root = self.source
        with Broker(native) as socket:
            env = dict(os.environ, SU_TEST_NATIVE_SOCKET=str(socket))
            prefix = ['/usr/bin/unshare', '--mount', '--propagation', 'private', '/bin/bash', str(root/'tests/lib/native-launch.sh'), str(root)]
            # Absolute native path, then timeout's child, both reach actual broker.
            bad = list(argv)
            bad[1] = '9999'
            p = subprocess.run(prefix + ['/usr/bin/timeout','10s','/usr/sbin/pct',*bad],env=env,capture_output=True,text=True,timeout=20)
            self.assertEqual(p.returncode,65,p.stderr)
            self.assertEqual(calls,[])
            p = subprocess.run(prefix + ['/usr/sbin/pct',*argv],env=env,capture_output=True,text=True,timeout=20)
            self.assertEqual(p.returncode,0,p.stderr)
            self.assertEqual(calls[0],('pct',argv))
            self.assertEqual(native.owner.finish(17),17)
        print('NATIVE_PATH_BOUNDARY absolute=1 timeout_child=1 native=recording mounts=actual',flush=True)

    def test_kosmozoo_delegation_requires_exact_native_scope(self):
        from test_pve import admit_delegated,admit_scope
        c,_,_=self.review_context('maintenance-kosmozoo-native','live-runtime')
        original=c.document;op=c.operation;root=Path('/').stat()
        delegated=self.run_owner.directory/'kosmozoo-delegation-model.json'
        d=dict(schema=1,context_sha256=sha(self.context.path.read_bytes()),suite=op['suite'],mode=op['mode'],resource=op['nested'][0],
               namespaces={k:os.readlink('/proc/self/ns/'+k) for k in ('mnt','pid','user')},root=[root.st_dev,root.st_ino],source=original['source']['tree_sha256'])
        lineage=json.loads(Path(op['native']['lineage']).read_bytes())
        # Parsed custody seam only; never mint a delegation for the outer guest.
        def read(path):return {str(delegated):d,str(self.context.path):original,op['native']['lineage']:lineage}[str(path)]
        with patch('test_pve.read_custody',side_effect=read),patch.dict(os.environ,SU_TEST_DELEGATION=str(delegated),TMPDIR=op['native']['receiver_tmpdir']):
            admitted=admit_delegated(self.context.path,op['suite'],op['mode']);admit_scope(admitted,'delegated')
            for key,value in [('suite','github-force-deploy'),('source','0'*64),('root',[0,0]),('namespaces',{})]:
                saved=d[key];d[key]=value
                with self.assertRaises(AdmissionError):admit_delegated(self.context.path,op['suite'],op['mode'])
                d[key]=saved
        print('KOSMOZOO_DELEGATION actual_source_namespace_root checks=5 custody=recording no_native_effects=1',flush=True)

    def review_context(self, suite, mode):
        """Parsed operation/model seam; authoritative context is never rewritten."""
        native, calls, _ = self.native_fixture()
        op = copy.deepcopy(native.run.context.operation)
        _, role, effects = policy(suite,mode)
        op.update(suite=suite,mode=mode,role=role,effects=effects)
        token = uuid.uuid4().hex
        spec = op['nested'][0]
        spec.update(tag='su-workflow-'+token,hostname='su-review-'+token[:12])
        if suite in ('calibre-web-automated','odysseus'):
            spec.update(ctid=2010 if suite=='calibre-web-automated' else 2011)
            spec['volume']='vm-'+str(spec['ctid'])+'-disk-0'
            op['native']['ram']=2048 if spec['ctid']==2010 else 4096
        parent = native.run.directory/'admission-target'
        parent.mkdir(mode=0o700)
        op['runs']=str(parent)
        tmp=parent/'tmp';tmp.mkdir(mode=0o700);op['tmpdir']=str(tmp)
        op['native']['lineage']=str(parent/'creation.json')
        op['native']['budgets']=dict(root_free=1024**3,workspace_peak=1024**3,thin_peak=op['native']['disk']*1024**3,memory_peak=(op['native']['ram']+512)*1024**2)
        observed = dict(spec,volume_uuid='owned-lv')
        lineage=dict(requested=spec,observed=observed,status=0,source=self.context.document['source']['tree_sha256'])
        Path(op['native']['lineage']).write_text(json.dumps(lineage))
        Path(op['native']['lineage']).chmod(0o400)
        document=copy.deepcopy(self.context.document)
        document['operations']=[op]
        c=SimpleNamespace(document=document,operation=op,path=self.context.path,recheck=self.context.recheck)
        return c, parent, observed

    def public_main(self, context, check=False):
        cli=runpy.run_path(str(self.source/'tests/run'),run_name='review_cli')
        args=['tests/run','--check' if check else '--run','--context',str(context.path),'--suite',context.operation['suite'],'--mode',context.operation['mode']]
        with patch.object(Context,'admit',return_value=context),patch.object(sys,'argv',args),patch.dict(os.environ,TMPDIR=context.operation['tmpdir']):
            try:return cli['main']()
            except AdmissionError:return 65

    def test_dragonfly_delegation_requires_exact_native_scope(self):
        from test_pve import admit_delegated,admit_scope
        c,_,_=self.review_context('migration-dragonfly-native','live-runtime')
        original=c.document;op=c.operation;root=Path('/').stat()
        delegated=self.run_owner.directory/'dragonfly-delegation-model.json'
        d=dict(schema=1,context_sha256=sha(self.context.path.read_bytes()),suite=op['suite'],mode=op['mode'],resource=op['nested'][0],
               namespaces={k:os.readlink('/proc/self/ns/'+k) for k in ('mnt','pid','user')},root=[root.st_dev,root.st_ino],source=original['source']['tree_sha256'])
        lineage=json.loads(Path(op['native']['lineage']).read_bytes())
        def read(path):return {str(delegated):d,str(self.context.path):original,op['native']['lineage']:lineage}[str(path)]
        with patch('test_pve.read_custody',side_effect=read),patch.dict(os.environ,SU_TEST_DELEGATION=str(delegated),TMPDIR=op['native']['receiver_tmpdir']):
            admitted=admit_delegated(self.context.path,op['suite'],op['mode']);admit_scope(admitted,'delegated')
            for key,value in [('suite','maintenance-kosmozoo-native'),('source','0'*64),('root',[0,0]),('namespaces',{})]:
                saved=d[key];d[key]=value
                with self.assertRaises(AdmissionError):admit_delegated(self.context.path,op['suite'],op['mode'])
                d[key]=saved
        print('DRAGONFLY_DELEGATION actual_source_namespace_root checks=5 custody=recording no_native_effects=1',flush=True)

    def test_review_actual_public_execution_routes(self):
        cases=[('codeberg-release','live','runtime'),('codeberg-release','bundle','runtime'),
               ('maintenance-kosmozoo-native','live-runtime','runtime'),
               ('migration-dragonfly-native','live-runtime','runtime'),
               ('github-force-deploy','live-runtime','runtime'),('uv-project-version','live-runtime','runtime'),
               ('romm-player-serving','live-runtime','runtime'),('romm-player-serving','setup','runtime'),
               ('romm-live-verification','installed-probe','installed'),
               ('calibre-web-automated','nested-install','local'),('odysseus','nested-install','local'),
               ('maintenance-service-systemd','native-unit','local'),('maintenance-service-edge-native','native-unit','local'),
               ('maintenance-globnotes-lxc','native-app','local'),('maintenance-globnotes-lxc','guard','local'),
               ('globnotes-browser','installed-probe','local')]
        real_process=subprocess.run
        for suite,mode,expected in cases:
            with self.subTest(suite=suite,mode=mode):
                c,_,_=self.review_context(suite,mode)
                events=[]
                def runtime(ctx,argv):
                    events.append('installed' if ctx.operation['mode']=='installed-probe' else 'runtime');return 0
                def installed(ctx,argv):events.append('installed');return 0
                def process(argv,**kwargs):
                    if len(argv)>1 and str(self.source/'tests') in argv[1]:
                        events.append('local');return subprocess.CompletedProcess(argv,0,'','')
                    return real_process(argv,**kwargs)
                # Only the argv producer/OS effect boundaries are recorded. The
                # actual public main and its execution-route selection run.
                with patch('entrypoint.command_for',return_value=['/bin/bash',str(self.source/REGISTRY[suite].path)]),patch('test_pve.admit_scope'),patch('test_pve.runtime_dispatch',side_effect=runtime),patch('test_pve.installed_dispatch',side_effect=installed),patch('subprocess.run',side_effect=process),patch.object(Context,'validate',return_value=c):
                    self.assertEqual(self.public_main(c),0)
                self.assertEqual(events,[expected], 'public route escaped the source-owned effect owner')
        print('PUBLIC_EXECUTION_ROUTES cases=16 codeberg_live=owned-runtime kosmozoo_native=owned-runtime dragonfly_native=owned-runtime effects=recording',flush=True)

    def test_review_preflight_precedes_run_and_public_check(self):
        from test_context import Resource
        from test_pve import runtime_dispatch,installed_dispatch
        for suite,mode,consumer in [('migration-dragonfly-native','live-runtime',runtime_dispatch),('maintenance-kosmozoo-native','live-runtime',runtime_dispatch),('github-force-deploy','live-runtime',runtime_dispatch),('codeberg-release','bundle',runtime_dispatch),('romm-live-verification','installed-probe',installed_dispatch)]:
            for action in ('consumer','public-run','public-check'):
                with self.subTest(suite=suite,action=action):
                    c,parent,observed=self.review_context(suite,mode)
                    if mode!='installed-probe':Path(c.operation['native']['lineage']).unlink()
                    with patch.dict(os.environ,TMPDIR=c.operation['tmpdir']):Context.validate(c.document,c.path,suite,mode)
                    foreign=Resource(**dict(observed,volume_uuid='foreign-lv'))
                    before=self.tree_state(parent)
                    out=io.StringIO()
                    with patch('test_pve.admit_resources'),patch('test_pve.NativePVE.observe_static',return_value=foreign),patch('test_pve.Publisher') as publisher,contextlib.redirect_stdout(out):
                        try:status=consumer(c,['/bin/true']) if action=='consumer' else self.public_main(c,check=action=='public-check')
                        except AdmissionError:status=65
                        self.assertNotEqual(status,0,'unowned native target passed admission')
                        publisher.assert_not_called()
                    after=self.tree_state(parent)
                    self.assertEqual(before,after,'refusal created run lock/directory/receipt before native ownership preflight')
                    self.assertNotIn('CONTEXT_OK',out.getvalue())
        print('NATIVE_BEFORE_EFFECTS cases=15 direct_publicrun_publiccheck locks_runs_publishers=0',flush=True)

    def test_review_bundle_bootstrap_and_publisher_phases_are_distinct(self):
        from test_context import Resource
        from test_pve import admit_scope,publisher_receipt_path
        c,parent,observed=self.review_context('codeberg-release','bundle')
        lineage_path=Path(c.operation['native']['lineage']);raw=lineage_path.read_bytes();lineage_path.unlink()
        before=self.tree_state(parent)
        with patch('test_pve.NativePVE.observe_static',return_value=None),patch('test_pve.admit_resources'):
            admit_scope(c,'create')
        self.assertEqual(self.tree_state(parent),before)
        with self.assertRaises(AdmissionError):admit_scope(c,'publisher')
        lineage_path.write_bytes(raw);lineage_path.chmod(0o400)
        url='http://'+c.operation['native']['address']+':12345'
        publisher=publisher_receipt_path(c)
        publisher.write_text(json.dumps(dict(url=url,source=c.document['source']['tree_sha256'],pid=os.getpid(),birth=Path('/proc/self/stat').read_text().split()[21])))
        publisher.chmod(0o400);before=self.tree_state(parent)
        with patch('test_pve.NativePVE.observe_static',return_value=Resource(**observed)),patch('test_pve.admit_topology'),patch.dict(os.environ,SU_TEST_REPO_BASE=url,SU_TEST_CTID=str(observed['ctid'])):
            admit_scope(c,'publisher')
            with self.assertRaises(AdmissionError):admit_scope(c,'create')
        self.assertEqual(self.tree_state(parent),before)
        print('BUNDLE_PHASES bootstrap_absence_then_existing_publisher current_identity=recording birth=actual no_run_or_listener=1',flush=True)

    @staticmethod
    def tree_state(root):
        return {str(p.relative_to(root)):(p.stat().st_ino,p.stat().st_mode,p.stat().st_uid,p.stat().st_gid,p.stat().st_mtime_ns,
                    sha(p.read_bytes()) if p.is_file() else None) for p in [root,*root.rglob('*')]}

    def test_review_public_wrong_target_source_before_all_effects(self):
        for defect in ('target','source'):
            for action in ('--run','--check'):
                with self.subTest(defect=defect,action=action):
                    c,parent,_=self.review_context('github-force-deploy','live-runtime')
                    Path(c.operation['native']['lineage']).unlink()  # own setup fixture: create phase requires absence
                    with patch.dict(os.environ,TMPDIR=c.operation['tmpdir']):
                        Context.validate(c.document,c.path,'github-force-deploy','live-runtime')
                    d=copy.deepcopy(c.document)
                    if defect=='target':d['target']['uuid']='00000000-0000-0000-0000-000000000000'
                    else:
                        d['source']['files'][0]['sha256']='0'*64
                        d['source']['tree_sha256']=sha(json.dumps(d['source']['files'],sort_keys=True,separators=(',',':')).encode())
                    cli=runpy.run_path(str(self.source/'tests/run'),run_name='review_identity_cli')
                    args=['tests/run',action,'--context',str(c.path),'--suite','github-force-deploy','--mode','live-runtime']
                    before=self.tree_state(parent);out=io.StringIO()
                    with patch.object(Context,'admit',side_effect=lambda path,suite,mode:Context.validate(d,path,suite,mode)),patch.object(sys,'argv',args),patch.dict(os.environ,TMPDIR=c.operation['tmpdir']),patch('test_pve.NativePVE.observe_static') as observe,patch('test_pve.admit_resources') as resources,patch('test_pve.runtime_dispatch') as runtime,patch('test_pve.Publisher') as publisher,contextlib.redirect_stdout(out):
                        with self.assertRaises(AdmissionError):cli['main']()
                        for boundary in (observe,resources,runtime,publisher):boundary.assert_not_called()
                    self.assertEqual(self.tree_state(parent),before)
                    self.assertNotIn('CONTEXT_OK',out.getvalue())
        print('PUBLIC_IDENTITY_REFUSAL cases=4 bytes_modes_inodes_directories_unchanged native_run_publisher=0',flush=True)

    def test_review_independently_admitted_other_topology_and_id(self):
        from test_pve import validate_native,NativePVE
        c,_,_=self.review_context('github-force-deploy','live-runtime')
        n=c.operation['native'];spec=c.operation['nested'][0]
        n.update(bridge='br-proof7',address='172.31.55.1',storage='proof-thin',template_storage='proof-files',vg='proof_data',pool='proof_pool')
        spec.update(ctid=3042,volume='vm-3042-disk-0',storage='proof-thin')
        validate_native(n,c.operation)
        token=spec['tag'];spec['tag']='su-workflow-reused-default'
        with self.assertRaisesRegex(AdmissionError,'token'):validate_native(n,c.operation)
        spec['tag']=token
        run=SimpleNamespace(context=c,directory=Path(c.operation['runs']),record=self.run_owner.record)
        calls=[]
        native=NativePVE(run,call=lambda tool,args:calls.append((tool,args)))
        argv=['create','3042','proof-files:vztmpl/'+n['template'],'-hostname',spec['hostname'],'-tags','community-script,'+spec['tag'],'-cores','2','-memory','2048','-unprivileged','1','-rootfs','proof-thin:8','-onboot','1','-features','nesting=1,keyctl=1','-net0','name=eth0,bridge=br-proof7,ip=dhcp,hwaddr='+spec['mac']]
        native.check_create(argv)
        argv[1]='3043'
        with self.assertRaises(AdmissionError):native.dispatch('pct',argv)
        self.assertEqual(calls,[])
        print('ADMITTED_FACTS alternate_id=3042 alternate_bridge=br-proof7 unauthorized_id_refused=3043 effects=0',flush=True)

    def test_review_graceful_shutdown_and_failure_preservation(self):
        native,calls,argv=self.native_fixture()
        self.assertEqual(native.dispatch('pct',argv).returncode,0)
        original=native.call
        def fail(tool,args):
            if args[0] in ('stop','shutdown'):
                calls.append((tool,list(args)));return subprocess.CompletedProcess(args,31,'','shutdown refused')
            return original(tool,args)
        native.call=fail
        self.assertEqual(native.owner.finish(17),17)
        self.assertIn(('pct',['shutdown','2012','--timeout','120','--forceStop','0']),calls)
        self.assertFalse(any(a[0] in ('stop','destroy') for _,a in calls))
        self.assertIsNotNone(native.observe(2012))
        receipt=json.loads(sorted(self.run_owner.directory.glob('*-failure-preservation.json'))[-1].read_text())
        self.assertEqual((receipt['original_status'],receipt['preservation_status'],receipt['state']),(17,31,'unknown'))

    def test_review_shutdown_timeout_preserves_original_status(self):
        for phase in ('shutdown','status'):
            native,calls,argv=self.native_fixture()
            self.assertEqual(native.dispatch('pct',argv).returncode,0)
            original=native.call
            def timeout(tool,args):
                if args[0]==phase:
                    calls.append((tool,list(args)));raise subprocess.TimeoutExpired(args,75 if phase=='shutdown' else 20)
                return original(tool,args)
            native.call=timeout
            self.assertEqual(native.owner.finish(17),17)
            self.assertFalse(any(a[0]=='destroy' for _,a in calls))
            self.assertIsNotNone(native.observe(2012))
            self.assertEqual((native.run.directory/'2012.state').read_text(),'running' if phase=='shutdown' else 'stopped')
            receipt=json.loads(sorted(self.run_owner.directory.glob('*-failure-preservation.json'))[-1].read_text())
            self.assertEqual((receipt['original_status'],receipt['preservation_status'],receipt['state']),(17,124,'unknown'))

    def test_review_actual_native_process_umask(self):
        native,_,_=self.native_fixture()
        native.PROGRAMS=dict(native.PROGRAMS,pct='/usr/bin/python3')
        old=os.umask(0o077)
        try:result=native._process('pct',['-c','import os; print(oct(os.umask(0o077)))'])
        finally:os.umask(old)
        self.assertEqual(result.returncode,0)
        self.assertEqual(result.stdout.strip(),'0o22','native subprocess inherited private evidence umask')
        self.assertEqual(self.run_owner.directory.stat().st_mode&0o777,0o700)
        self.assertTrue(all(p.stat().st_mode&0o777==0o400 for p in self.run_owner.directory.glob('*.json')))
        print('NATIVE_PROCESS_UMASK actual_child=022 private_evidence=0700/0400',flush=True)

    def test_review_actual_fact_checks_use_admitted_topology(self):
        from test_pve import admit_resources
        c,parent,_=self.review_context('github-force-deploy','live-runtime')
        n=c.operation['native'];spec=c.operation['nested'][0]
        n.update(bridge='br-proof7',address='172.31.55.1',storage='proof-thin',template_storage='proof-files',vg='proof_data',pool='proof_pool')
        spec.update(ctid=3042,volume='vm-3042-disk-0',storage='proof-thin')
        template=parent/n['template'];template.write_bytes(b'owned authenticated template model')
        n['template_sha256']=sha(template.read_bytes())
        calls=[];wrong=False;logical=[]
        def query(argv):
            calls.append(argv)
            if argv[0]=='/usr/sbin/ip':
                if 'link' in argv:return json.dumps([{'ifname':n['bridge'],'linkinfo':{'info_kind':'bridge'}}])
                return json.dumps([{'addr_info':[{'family':'inet','local':'172.31.55.2' if wrong else n['address'],'prefixlen':24}]}])
            if argv[0]=='/usr/bin/pvesh':
                name=argv[2].rsplit('/',1)[1]
                return json.dumps(dict(storage=name,type='lvmthin' if name==n['storage'] else 'dir',vgname=n['vg'],thinpool=n['pool'],content='rootdir,vztmpl'))
            if argv[0]=='/usr/sbin/pvesm':return str(template)
            if argv[0]=='/usr/sbin/lvs':return json.dumps({'report':[{'lv':[dict(vg_name=n['vg'],lv_name=n['pool'],pool_lv='',segtype='thin-pool',lv_size=str(36*1024**3),data_percent='0',metadata_percent='1'),*logical]}]})
            raise AssertionError(argv)
        before=set(parent.iterdir())
        with patch('test_pve.query',side_effect=query):
            admit_resources(c)
            logical.extend([dict(vg_name=n['vg'],lv_name='vm-9000-disk-0',pool_lv=n['pool'],segtype='thin',origin='',lv_attr='Vwi---tz--',lv_size=str(16*1024**3),data_percent='0.01'),
                            dict(vg_name=n['vg'],lv_name='snap_vm-9000-disk-0_foreign',pool_lv=n['pool'],segtype='thin',origin='vm-9000-disk-0',lv_attr='Vri---tz--',lv_size=str(12*1024**3),data_percent='0.01')])
            with self.assertRaisesRegex(AdmissionError,'virtual thin capacity'):admit_resources(c)
            logical.clear()
            logical.append(dict(vg_name='other_vg',lv_name='unrelated',pool_lv=n['pool'],segtype='thin',lv_size=str(1000*1024**3)))
            admit_resources(c)
            logical.clear()
            cpu=n['cpu'];n['cpu']=(os.cpu_count() or 1)+1
            with self.assertRaisesRegex(AdmissionError,'CPU envelope'):admit_resources(c)
            n['cpu']=cpu
            peak=n['budgets']['memory_peak'];n['budgets']['memory_peak']=n['ram']*1024**2-1
            with self.assertRaisesRegex(AdmissionError,'peak envelope'):admit_resources(c)
            n['budgets']['memory_peak']=peak
            wrong=True
            with self.assertRaisesRegex(AdmissionError,'bridge address'):admit_resources(c)
        self.assertEqual(set(parent.iterdir()),before)
        self.assertTrue(any('/storage/proof-thin' in a for a in calls))
        print('NATIVE_FACT_PREFLIGHT bridge_storage_vg_pool=admitted-model template_bytes=actual mismatched_address_refused effects=0',flush=True)
        print('VIRTUAL_CAPACITY inactive_foreign16GiB_snapshot12GiB_low_data_refused other_vg_ignored ordinary_pass effects=0',flush=True)

    def test_receiver_actual_empty_environment_literal_consumer(self):
        native,calls,argv=self.native_fixture()
        self.assertEqual(native.dispatch('pct',argv).returncode,0)
        original=native.call
        def receiving(tool,args):
            if args[0]=='exec':
                self.assertEqual(args[3],'env')
                return subprocess.run(['/usr/bin/env','-i','/usr/bin/env',*args[4:]],capture_output=True,text=True,timeout=10)
            if tool=='lxc-attach':
                self.assertEqual(args[3],'env')
                return subprocess.run(['/usr/bin/env','-i','/usr/bin/env',*args[4:]],capture_output=True,text=True,timeout=10)
            return original(tool,args)
        native.call=receiving
        body='test "$HOME" = /root; test -n "$PATH"; printf "%s\\n" "$1" "$TMPDIR"'
        literal='space;$(never) *'
        for tool,args in [('pct',['exec','2012','--','/bin/bash','-euc',body,'--',literal]),('lxc-attach',['-n','2012','--','/bin/bash','-euc',body,'--',literal])]:
            result=native.dispatch(tool,args)
            self.assertEqual(result.returncode,0,result.stderr)
            self.assertEqual(result.stdout.splitlines(),[literal,'/var/lib/scripts-underground-test/tmp'])
        self.assertEqual(native.owner.finish(17),17)
        print('RECEIVER_EMPTY_ENV actual_shell_exec_attach HOME_PATH_TMPDIR_literal=pass native=recording',flush=True)

    def test_contribution_refuses_nested_workload_before_supervision_effects(self):
        from entrypoint import supervise
        from test_context import Resource
        c=Context.admit(self.context.path,'contribution','contribution');before=self.tree_state(self.run_owner.directory)
        foreign=Resource(**next(v for v in c.document['operations'] if v['suite']=='odysseus')['nested'][0])
        with patch('test_pve.NativePVE.observe_static',return_value=foreign),patch('entrypoint.subprocess.run') as effects:
            with self.assertRaisesRegex(AdmissionError,'nested resources retired'):supervise(c,3600)
            effects.assert_not_called()
        self.assertEqual(before,self.tree_state(self.run_owner.directory))
        print('CONTRIBUTION_BUDGET refuses_nested_workload_before_unit_job_lock_log_effects native_observation=recording',flush=True)

    def test_contribution_rejects_semantically_corrupted_owned_catalogue(self):
        import contribution
        parent=self.run_owner.directory/('contribution-negative-'+uuid.uuid4().hex);parent.mkdir(mode=0o700)
        source=parent/'input-model';source.mkdir();(source/'_lxc').mkdir()
        (source/'_lxc/demo.md').write_text('---\nslug: demo\ntitle: Demo\n---\nDemo fixture\n')
        out=parent/'output';out.mkdir(mode=0o700)
        document=copy.deepcopy(self.context.document);document['source']['path']=str(source)
        c=SimpleNamespace(document=document,operation=self.context.operation,recheck=self.context.recheck)
        owner=SimpleNamespace(context=c,directory=out,record=self.run_owner.record)
        real_process=subprocess.run
        def process(argv,**kwargs):
            if argv[0] in ('/usr/bin/node','/usr/bin/nodejs') or argv[:2]==['/usr/bin/ruby','-rjson']:return real_process(argv,**kwargs)
            projection=Path(kwargs['cwd'])
            if argv[0]=='bundle':
                site=Path(argv[-1]);site.mkdir();(site/'index.html').write_text('<title>Home</title>')
                bad=dict(meta=dict(total=999),scripts=[])
                (projection/'scripts.json').write_text(json.dumps(bad));(site/'scripts.json').write_text(json.dumps(bad))
            return subprocess.CompletedProcess(argv,0,b'' if kwargs.get('capture_output') else None,b'')
        with patch.dict(os.environ,SU_TEST_CONTEXT=str(self.context.path)),patch.object(contribution.Context,'admit',return_value=c),patch.object(contribution,'preflight',return_value=None,create=True),patch.object(contribution,'Run',return_value=contextlib.nullcontext(owner)),patch.object(contribution.subprocess,'run',side_effect=process):
            with self.assertRaisesRegex(AdmissionError,'catalogue'):
                status=contribution.main()
                print('CORRUPTED_CATALOGUE_ACTUAL_MAIN_RETURN',status,flush=True)
        print('CONTRIBUTION_NEGATIVE actual_owned_corrupt_JSON_count refused_by_actual_main native_builders_admission=recording input_untouched=1',flush=True)

    def test_static_receiver_policy_precedes_native_start(self):
        native,calls,argv=self.native_fixture()
        self.assertEqual(native.dispatch('pct',argv).returncode,0)
        before=list(calls);events=[]
        def policy():
            events.append('offline-policy')
            raise AdmissionError('policy evidence refused')
        with patch.object(native,'prepare_service_policy',side_effect=policy,create=True):
            with self.assertRaisesRegex(AdmissionError,'policy evidence refused'):
                native.dispatch('pct',['start','2012'])
        self.assertEqual(events,['offline-policy'])
        self.assertEqual(calls,before,'native start occurred before offline policy')
        print('STATIC_POLICY_ORDER policy_refusal_before_start native=recording effects=0',flush=True)

    def test_offline_receiver_policy_owned_files_and_unknown_refusals(self):
        from receiver_service import prepare,POLICY,CONTENT
        from mounted_root import identity
        from test_context import Resource
        import stat
        parent=self.run_owner.directory/('policy-model-'+uuid.uuid4().hex);parent.mkdir(mode=0o700)
        root=parent/'mounted-root';root.mkdir(mode=0o755);os.chown(root,123456,123457)
        resource=Resource(2012,'su-workflow-'+uuid.uuid4().hex,'02:96:ab:cd:ef:01','su-fixture','su-thin','vm-2012-disk-0','model-lv')
        events=[];record=lambda label,value:events.append((label,value))
        mount=SimpleNamespace(active=None,stopped=lambda:None,check_active=lambda:None)
        def opened():mount.active=dict(path=str(root),identity=identity(root))
        def closed():mount.active=None
        mount.open_owned=opened;mount.close=closed
        c=SimpleNamespace(operation=dict(runs=str(parent)),document=self.context.document)
        native=SimpleNamespace(n=dict(receiver_tmpdir='/var/lib/scripts-underground-test/tmp'),owner=SimpleNamespace(spec=resource,current=resource,creation=dict(model=True),checked=lambda:None),mount=mount,run=SimpleNamespace(context=c,directory=parent,record=record))
        before=identity(root)
        with patch('receiver_service.mapped_root',return_value=(123456,123457)):
            prepare(native);policy=root/POLICY
            self.assertEqual(policy.read_bytes(),CONTENT);self.assertEqual(policy.stat().st_uid,123456);self.assertEqual(policy.stat().st_gid,123457)
            leaf=root/'var/lib/scripts-underground-test/tmp';self.assertEqual(stat.S_IMODE(leaf.stat().st_mode),0o1777)
            self.assertEqual(identity(root),before,'existing root metadata repaired')
            first=policy.stat();prepare(native);self.assertEqual(policy.stat(),first,'repeated start rewrote recorded policy')
            policy.write_bytes(CONTENT+b'# unknown change\n')
            with self.assertRaisesRegex(AdmissionError,'bytes/metadata'):prepare(native)
            policy.write_bytes(CONTENT)
            receipt=next(parent.glob('receiver-policy-*.json'));receipt.unlink()
            with self.assertRaisesRegex(AdmissionError,'unknown existing'):prepare(native)
            policy.unlink();policy.symlink_to(parent/'foreign')
            with self.assertRaisesRegex(AdmissionError,'unknown existing'):prepare(native)
            policy.unlink();leaf.rmdir();leaf.symlink_to(parent)
            with self.assertRaises(OSError):prepare(native)
        self.assertTrue(any(label=='receiver-object-intent' for label,_ in events));self.assertIsNone(mount.active)
        print('OFFLINE_POLICY actual_dirfd_nofollow_mapped_new_ownership_01777 immutable_existing_root repeat_verify changed_unknown_symlink_refused native_mount_map=recording',flush=True)


if __name__ == '__main__':
    sys.argv_context = sys.argv[1]
    result = unittest.TextTestRunner(verbosity=2).run(unittest.defaultTestLoader.loadTestsFromTestCase(Entrypoints))
    if result.wasSuccessful():
        print(f'ENTRYPOINT_CONFORMANCE_PASS cases={result.testsRun} native=recording direct=actual')
    raise SystemExit(0 if result.wasSuccessful() else 1)
