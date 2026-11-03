"""Exercise the shared owner, not installed applications or native CT mutation."""
import copy
import json
import os
from pathlib import Path
import sys
import unittest
import time
import hashlib

from test_context import AdmissionError, Context, NestedOwner, Resource, Run, load_json, sha


class BrokenIdentityOwner(NestedOwner):
    """Deliberate test-subject negative control: number-based lifecycle identity."""

    def checked(self):
        self.run.context.recheck()
        if self.creation is None:
            raise AdmissionError('unowned resource')


class RecordingNative:
    """Real private config files, modeled lifecycle; never calls pct/lvs/systemctl."""

    def __init__(self, root):
        self.root = root
        self.calls = []
        self.fail = {}
        self.race = False
        self.reads = 0
        self.created_uuid = None

    def observe(self, ctid):
        self.reads += 1
        path = self.root / str(ctid)
        if self.race and self.reads == 2:
            path.write_text(json.dumps(Resource(ctid, 'foreign', 'other', 'other', 'other', 'other', 'foreign').__dict__))
        return Resource(**json.loads(path.read_text())) if path.exists() else None

    def evidence_identity(self,spec):
        return dict(config_sha256=sha((self.root/str(spec.ctid)).read_bytes()),state=(self.root/f'{spec.ctid}.state').read_text())

    def invoke(self, action, spec, args=()):
        self.calls.append([action, spec.ctid, list(args)])
        path = self.root / str(spec.ctid)
        if action == 'create':
            with path.open('x') as stream:
                json.dump(spec.__dict__ | {'volume_uuid': self.created_uuid or spec.volume_uuid}, stream)
            (self.root / f'{spec.ctid}.state').write_text('running')
        elif action == 'stop' and not self.fail.get(action):
            (self.root / f'{spec.ctid}.state').write_text('stopped')
        elif action == 'destroy' and not self.fail.get(action):
            path.unlink()
            (self.root / f'{spec.ctid}.state').unlink()
        elif action == 'rollback' and not self.fail.get(action):
            row = spec.__dict__ | {'volume_uuid': 'rollback-uuid'}
            path.write_text(json.dumps(row))
        return self.fail.get(action, 0)


class Ownership(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.context_path = Path(sys.argv_context)
        # This is an existing independently installed context, never minted here.
        cls.admitted = Context.admit(cls.context_path, 'workflow-ownership', 'fixture')
        cls.owner_run = Run(cls.admitted)
        cls.owner_run.__enter__()

    @classmethod
    def tearDownClass(cls):
        cls.owner_run.__exit__(None, None, None)

    def setUp(self):
        self.root = self.owner_run.directory / self.id().split('.')[-1]
        self.root.mkdir(mode=0o700)
        self.native = RecordingNative(self.root)
        self.spec = Resource(2012, 'su-test-token', '52:54:00:aa:bb:cc', 'su-fixture', 'su-thin', 'vm-2012-disk-0', 'initial-uuid')
        owner_class = BrokenIdentityOwner if sys.negative_control else NestedOwner
        self.owner = owner_class(self.owner_run, self.spec, self.native)

    def refuse(self, operation, contains):
        before = list(self.native.calls)
        with self.assertRaisesRegex(AdmissionError, contains):
            operation()
        self.assertEqual(self.native.calls, before, 'refusal reached mutating native boundary')
        print('ZERO_EFFECT', self.id(), contains, flush=True)

    def approve(self,owner=None):
        # Independently supplied model custody actor, NOT a production ack API.
        owner=owner or self.owner
        if owner.pending is None:self.assertEqual(owner.prepare_preservation(),0)
        pending=json.loads(owner.pending.read_text())
        external=self.root/'external-copy';external.mkdir(exist_ok=True,mode=0o700)
        for number,fact in enumerate(pending['evidence']):
            raw=Path(fact['path']).read_bytes();copied=external/str(number);copied.write_bytes(raw)
            self.assertEqual(len(copied.read_bytes()),fact['bytes']);self.assertEqual(sha(copied.read_bytes()),fact['sha256'])
        copied=external/'pending';copied.write_bytes(owner.pending.read_bytes());self.assertEqual(copied.read_bytes(),owner.pending.read_bytes())
        manifest=dict(schema=1,pending=owner.file_fact(owner.pending),files=pending['evidence'],copied_at_ns=time.time_ns(),destination=str(external),archive_sha256=sha(b'model externally verified archive'),archive_bytes=1)
        custody=self.root/'independent-custody';custody.mkdir(exist_ok=True,mode=0o700)
        ackpath=custody/'ack.json';owner.acknowledgement_path=lambda:ackpath
        ack=dict(schema=1,pending_sha256=sha(owner.pending.read_bytes()),external_manifest_sha256=sha(json.dumps(manifest,sort_keys=True).encode()),external_manifest=manifest)
        ackpath.write_text(json.dumps(ack,sort_keys=True));ackpath.chmod(0o400)
        return ackpath,ack

    def changed(self, mutate, error):
        document = copy.deepcopy(self.admitted.document)
        mutate(document)
        document['source']['tree_sha256'] = sha(json.dumps(document['source']['files'], sort_keys=True, separators=(',', ':')).encode())
        # Test-only constructor seam supplies parsed data; normal CLI only reads root custody.
        self.refuse(lambda: Context.validate(document, self.context_path, 'workflow-ownership', 'fixture'), error)

    def test_wrong_uuid(self):
        self.changed(lambda d: d['target'].__setitem__('uuid', '00000000-0000-0000-0000-000000000000'), 'target')

    def test_changed_source_bytes(self):
        self.changed(lambda d: d['source']['files'][0].__setitem__('sha256', '0' * 64), 'source')

    def test_changed_source_mode(self):
        self.changed(lambda d: d['source']['files'][0].__setitem__('mode', 0o777), 'source')

    def test_wrong_index(self):
        self.changed(lambda d: d['source'].__setitem__('index_sha256', '0' * 64), 'index')

    def test_missing_field(self):
        self.changed(lambda d: d.pop('target'), 'schema')

    def test_unknown_field(self):
        self.changed(lambda d: d.__setitem__('command', 'touch forbidden'), 'schema')

    def test_duplicate_json(self):
        self.refuse(lambda: load_json('{"schema":1,"schema":1}'), 'duplicate')

    def test_malformed_json(self):
        self.refuse(lambda: load_json('{bad'), 'JSON')

    def test_nonfinite_json(self):
        self.refuse(lambda: load_json('{"value":NaN}'), 'JSON')

    def test_wrong_type(self):
        self.changed(lambda d: d.__setitem__('schema', True), 'schema')

    def test_unknown_mode(self):
        self.refuse(lambda: Context.admit(self.context_path, 'workflow-ownership', 'live'), 'registry')

    def test_scope_mismatch(self):
        self.changed(lambda d: d['operations'][0].__setitem__('effects', ['native-ct']), 'scope')

    def test_duplicate_operation(self):
        self.changed(lambda d: d['operations'].append(copy.deepcopy(d['operations'][0])), 'duplicate')

    def test_unsafe_tmpdir(self):
        self.changed(lambda d: d['operations'][0].__setitem__('tmpdir', '/tmp'), 'TMPDIR')

    def test_escaping_source(self):
        self.changed(lambda d: d['source']['files'][0].__setitem__('path', '../outside'), 'path')

    def test_missing_context(self):
        self.refuse(lambda: Context.admit(self.root / 'missing', 'workflow-ownership', 'fixture'), 'context')

    def test_unsafe_ancestor(self):
        unsafe = self.root / 'unsafe'
        unsafe.mkdir(mode=0o777)
        unsafe.chmod(0o777)
        path = unsafe / 'context.json'
        path.write_text(self.context_path.read_text())
        self.refuse(lambda: Context.admit(path, 'workflow-ownership', 'fixture'), 'custody')

    def test_context_symlink(self):
        path = self.root / 'context-link'
        path.symlink_to(self.context_path)
        self.refuse(lambda: Context.admit(path, 'workflow-ownership', 'fixture'), 'custody')

    def test_writable_context(self):
        path = self.root / 'context.json'
        path.write_text(self.context_path.read_text())
        path.chmod(0o666)
        self.refuse(lambda: Context.admit(path, 'workflow-ownership', 'fixture'), 'custody')

    def test_literal_argv_and_status(self):
        words = ['a b', '; touch forbidden', '$(whoami)', '*', "quote'\""]
        result = self.owner_run.execute(['/usr/bin/python3', '-B', '-c', 'import json,sys; print(json.dumps(sys.argv[1:])); sys.exit(17)', *words], seconds=10)
        self.assertEqual(result.returncode, 17)
        self.assertEqual(json.loads(result.stdout), words)
        self.assertFalse((self.owner_run.directory / 'forbidden').exists())

    def test_timeout(self):
        result = self.owner_run.execute(['/usr/bin/python3', '-B', '-c', 'import time; time.sleep(10)'], seconds=1)
        self.assertEqual(result.returncode, 124)

    def test_nested_literal_argv(self):
        self.owner.create()
        args = ['/bin/tool', 'a b', '; touch forbidden', '$(whoami)', '*']
        self.assertEqual(self.owner.exec(args), 0)
        self.assertEqual(self.native.calls[-1], ['exec', 2012, args])

    def test_unadmitted_resource(self):
        foreign = Resource(**(self.spec.__dict__ | {'ctid': 2010}))
        self.refuse(lambda: NestedOwner(self.owner_run, foreign, self.native), 'not admitted')

    def test_creation_captures_actual_volume_uuid(self):
        self.native.created_uuid = 'new-actual-volume-uuid'
        self.assertEqual(self.owner.create(), 0)
        self.assertEqual(self.owner.current.volume_uuid, 'new-actual-volume-uuid')
        self.assertEqual(self.owner.creation['observed']['volume_uuid'], 'new-actual-volume-uuid')
        self.approve()
        self.assertEqual(self.owner.cleanup(), 0)

    def test_unowned_ct(self):
        foreign = self.spec.__dict__ | {'tag': 'foreign'}
        (self.root / '2012').write_text(json.dumps(foreign))
        self.refuse(self.owner.create, 'present')

    def test_absent_id_race(self):
        self.native.race = True
        self.refuse(self.owner.create, 'present')
        self.assertEqual(json.loads((self.root / '2012').read_text())['tag'], 'foreign')

    def test_unknown_preexisting_state(self):
        (self.root / '2012').write_text('bad config')
        self.refuse(self.owner.create, 'observation')

    def test_unowned_volume(self):
        self.assertEqual(self.owner.create(), 0)
        row = json.loads((self.root / '2012').read_text())
        row['volume_uuid'] = 'foreign-volume'
        (self.root / '2012').write_text(json.dumps(row))
        self.refuse(self.owner.cleanup, 'identity')

    def test_partial_create(self):
        self.native.fail['create'] = 29
        self.assertEqual(self.owner.create(), 29)
        self.assertEqual(self.owner.creation['status'], 29)
        self.assertEqual(self.owner.current, self.spec)
        self.assertTrue(list(self.owner_run.directory.glob('*create-result*.json')))

    def test_stop_failure_prevents_destroy(self):
        self.owner.create()
        self.native.fail['stop'] = 31
        self.assertEqual(self.owner.finish(0), 31)
        self.assertNotIn('destroy', [c[0] for c in self.native.calls])
        self.assertTrue((self.root / '2012').exists())

    def test_original_failure_survives_cleanup(self):
        self.owner.create()
        self.native.fail['stop'] = 31
        self.assertEqual(self.owner.finish(23), 23)
        self.assertEqual(self.owner.cleanup_status, 31)

    def test_cleanup_error_cannot_be_success(self):
        self.owner.create()
        self.native.fail['destroy'] = 37
        self.approve()
        self.assertEqual(self.owner.finish(0), 37)
        self.assertTrue((self.root / '2012').exists())
        receipt = self.last_receipt('cleanup-result')
        self.assertEqual(receipt['disposition'], 'retirement-failed')
        self.assertEqual(receipt['state'], 'unknown')
        self.assertEqual(receipt['cleanup_status'], 37)

    def last_receipt(self, label):
        paths = sorted(self.owner_run.directory.glob(f'*-{label}.json'))
        self.assertTrue(paths, f'missing semantic {label} receipt')
        return json.loads(paths[-1].read_text())

    def assert_failure_preserved(self, original_status):
        identity = self.owner.current.__dict__.copy()
        config = (self.root / '2012').read_bytes()
        creation = copy.deepcopy(self.owner.creation)
        self.assertEqual(self.owner.finish(original_status), original_status)
        self.assertTrue((self.root / '2012').exists(), 'failed consumer config must be preserved')
        self.assertEqual((self.root / '2012').read_bytes(), config)
        self.assertEqual(self.native.observe(2012).__dict__, identity)
        self.assertEqual(self.owner.creation, creation)
        self.assertEqual((self.root / '2012.state').read_text(), 'stopped')
        self.assertEqual([call[0] for call in self.native.calls], ['create', 'stop'])
        receipt = self.last_receipt('failure-preservation')
        self.assertEqual(receipt['original_status'], original_status)
        self.assertEqual(receipt['stop_status'], 0)
        self.assertEqual(receipt['preservation_status'], 0)
        self.assertEqual(receipt['disposition'], 'preserved')
        self.assertEqual(receipt['state'], 'stopped')
        self.assertEqual(receipt['owned_identity'], identity)
        self.assertEqual(receipt['observed_identity'], identity)
        self.assertEqual(receipt['creation_status'], creation['status'])
        self.assertIsNone(receipt['error'])
        print('FAILURE_PRESERVED', self.id(), original_status, identity['volume_uuid'], flush=True)

    def test_failed_consumer_preserves_owned_resource(self):
        self.assertEqual(self.owner.create(), 0)
        # Actual process consumer fails after successful owned creation.
        result = self.owner_run.execute(['/usr/bin/python3', '-B', '-c', 'raise SystemExit(17)'], seconds=10)
        self.assertEqual(result.returncode, 17)
        self.assert_failure_preserved(result.returncode)

    def test_failed_partial_create_preserves_owned_resource(self):
        self.native.fail['create'] = 29
        status = self.owner.create()
        self.assertEqual(status, 29)
        self.assert_failure_preserved(status)

    def test_failure_finish_leaves_unowned_resource_untouched(self):
        foreign = self.spec.__dict__ | {'tag': 'foreign', 'volume_uuid': 'foreign-volume'}
        path = self.root / '2012'
        path.write_text(json.dumps(foreign))
        before = path.read_bytes()
        self.assertEqual(self.owner.finish(17), 17)
        self.assertEqual(path.read_bytes(), before)
        self.assertEqual(self.native.calls, [])
        receipt = self.last_receipt('failure-preservation')
        self.assertEqual(receipt['disposition'], 'retained-unverified')
        self.assertEqual(receipt['state'], 'unknown')
        self.assertIsNone(receipt['stop_status'])
        self.assertIsNone(receipt['owned_identity'])
        self.assertEqual(receipt['preservation_status'], 70)
        self.assertIn('unowned', receipt['error'])

    def test_failure_finish_leaves_unknown_resource_untouched(self):
        self.owner.create()
        path = self.root / '2012'
        path.write_text('unknown changed config')
        calls = list(self.native.calls)
        self.assertEqual(self.owner.finish(17), 17)
        self.assertEqual(path.read_text(), 'unknown changed config')
        self.assertEqual(self.native.calls, calls)
        self.assertEqual((self.root / '2012.state').read_text(), 'running')
        receipt = self.last_receipt('failure-preservation')
        self.assertEqual(receipt['disposition'], 'retained-unverified')
        self.assertEqual(receipt['state'], 'unknown')
        self.assertIsNone(receipt['stop_status'])
        self.assertIsNone(receipt['observed_identity'])
        self.assertIn('observation', receipt['error'])

    def test_failure_finish_stop_failure_preserves_truthful_state(self):
        self.owner.create()
        config = (self.root / '2012').read_bytes()
        self.native.fail['stop'] = 31
        self.assertEqual(self.owner.finish(17), 17)
        self.assertEqual((self.root / '2012').read_bytes(), config)
        self.assertEqual((self.root / '2012.state').read_text(), 'running')
        self.assertEqual([call[0] for call in self.native.calls], ['create', 'stop'])
        receipt = self.last_receipt('failure-preservation')
        self.assertEqual(receipt['original_status'], 17)
        self.assertEqual(receipt['stop_status'], 31)
        self.assertEqual(receipt['preservation_status'], 31)
        self.assertEqual(receipt['state'], 'unknown')
        self.assertEqual(receipt['disposition'], 'preservation-incomplete')
        self.assertEqual(receipt['observed_identity']['volume_uuid'], self.spec.volume_uuid)

    def test_success_finish_retires_exact_owned_resource(self):
        self.owner.create()
        self.approve()
        self.assertEqual(self.owner.finish(0), 0)
        self.assertFalse((self.root / '2012').exists())
        self.assertFalse((self.root / '2012.state').exists())
        self.assertEqual([call[0] for call in self.native.calls], ['create', 'stop', 'destroy'])
        receipt = self.last_receipt('cleanup-result')
        self.assertEqual(receipt['original_status'], 0)
        self.assertEqual(receipt['cleanup_status'], 0)
        self.assertEqual(receipt['disposition'], 'retired')
        self.assertEqual(receipt['state'], 'absent')

    def test_success_without_external_ack_is_pending_and_never_destroyed(self):
        self.owner.create()
        original=copy.deepcopy(self.owner.creation)
        status=self.owner.finish(0)
        self.assertEqual(status,75,'consumer0 retired without external preservation')
        self.assertTrue((self.root/'2012').exists(),'missing acknowledgement destroyed the config')
        self.assertEqual((self.root/'2012.state').read_text(),'stopped')
        self.assertEqual(self.owner.creation,original)
        self.assertNotIn('destroy',[c[0] for c in self.native.calls])
        self.assertEqual(self.last_receipt('cleanup-result')['disposition'],'awaiting-external-preservation')
        self.assertEqual(self.last_receipt('cleanup-result')['state'],'stopped')

    def assert_finish_rejected(self):
        calls=copy.deepcopy(self.native.calls)
        creation=copy.deepcopy(self.owner.creation)
        pending=self.owner.pending.read_bytes()
        status=self.owner.finish(0)
        receipt=self.last_receipt('cleanup-result')
        print('PRESERVATION_FINISH_REFUSAL',self.id(),json.dumps(receipt,sort_keys=True),
              'actual_state='+(self.root/'2012.state').read_text(),flush=True)
        self.assertNotEqual(status,0)
        self.assertNotEqual(status,75,'rejected preservation is not missing acknowledgement')
        self.assertEqual(receipt['disposition'],'retirement-failed')
        self.assertEqual(receipt['state'],'unknown')
        self.assertEqual(self.native.calls,calls,'refusal must not stop or destroy')
        self.assertEqual(self.owner.creation,creation)
        self.assertEqual(self.owner.pending.read_bytes(),pending)

    def test_finish_running_after_pending_does_not_claim_stopped(self):
        self.owner.create();ackpath,_=self.approve()
        ack=ackpath.read_bytes()
        original=self.native.evidence_identity
        def stopped_identity(spec):
            facts=original(spec)
            if facts['state']!='stopped':
                raise AdmissionError('preservation/finalize requires stopped resource')
            return facts
        self.native.evidence_identity=stopped_identity
        (self.root/'2012.state').write_text('running')
        self.assert_finish_rejected()
        self.assertEqual((self.root/'2012.state').read_text(),'running')
        self.assertEqual(ackpath.read_bytes(),ack)

    def test_finish_wrong_ack_is_rejected_not_pending(self):
        self.owner.create();ackpath,ack=self.approve()
        ack['pending_sha256']='0'*64
        ackpath.write_text(json.dumps(ack,sort_keys=True));raw=ackpath.read_bytes()
        self.assert_finish_rejected()
        self.assertEqual(ackpath.read_bytes(),raw)

    def test_finish_changed_evidence_is_rejected_not_pending(self):
        self.owner.create();ackpath,_=self.approve()
        ack=ackpath.read_bytes()
        result=Path(json.loads(self.owner.pending.read_text())['binding']['result']['path'])
        result.write_text('{"status":17}')
        changed=result.read_bytes()
        self.assert_finish_rejected()
        self.assertEqual(result.read_bytes(),changed)
        self.assertEqual(ackpath.read_bytes(),ack)

    def test_non_json_consumer_artifacts_are_bound_before_retirement(self):
        self.owner.create()
        artifact = self.owner_run.directory / 'private-install.log'
        artifact.write_bytes(b'authentic private consumer output\n')
        artifact.chmod(0o600)
        self.approve()
        pending = json.loads(self.owner.pending.read_text())
        self.assertIn(self.owner.file_fact(artifact), pending['evidence'])
        artifact.write_bytes(b'changed after external copy\n')
        self.assert_finish_rejected()

    def test_direct_cleanup_without_external_ack_cannot_bypass_barrier(self):
        self.owner.create()
        with self.assertRaises(AdmissionError):self.owner.cleanup()
        self.assertTrue((self.root/'2012').exists())
        self.assertNotIn('destroy',[c[0] for c in self.native.calls])

    def test_preservation_ack_binding_negatives_and_actual_order(self):
        self.owner.create();self.assertEqual(self.owner.finish(0),75)
        self.assertEqual(self.native.calls[-1][0],'stop')
        creation=copy.deepcopy(self.owner.creation);config=(self.root/'2012').read_bytes()
        ackpath,ack=self.approve();raw=ackpath.read_bytes()
        for case in ('pending','run','source','resource','result','manifest','time','writable','ancestor','evidence'):
            candidate=copy.deepcopy(ack)
            if case=='pending':candidate['pending_sha256']='0'*64
            elif case=='manifest':candidate['external_manifest_sha256']='0'*64
            elif case=='time':candidate['external_manifest']['copied_at_ns']=0
            elif case in ('run','source','resource','result'):
                # A different pending/result binding cannot reuse a genuine ack.
                candidate['pending_sha256']=sha(case.encode())
            if case=='evidence':
                fact=candidate['external_manifest']['files'][0];p=Path(fact['path']);saved=p.read_bytes();p.write_bytes(saved+b'changed')
            ackpath.write_text(json.dumps(candidate,sort_keys=True));ackpath.chmod(0o600 if case=='writable' else 0o400)
            if case=='ancestor':ackpath.parent.chmod(0o777)
            calls=list(self.native.calls)
            try:
                with self.assertRaises(AdmissionError):self.owner.cleanup()
                self.assertEqual(self.native.calls,calls,'bad ack reached native destroy')
                self.assertEqual((self.root/'2012').read_bytes(),config)
            finally:
                if case=='ancestor':ackpath.parent.chmod(0o700)
                if case=='evidence':p.write_bytes(saved)
        ackpath.write_bytes(raw);ackpath.chmod(0o400)
        # Keep a genuine matching ack while independently changing current facts.
        doc=self.owner.run.context.document;source=doc['source']['tree_sha256']
        doc['source']['tree_sha256']='f'*64
        with self.assertRaises(AdmissionError):self.owner.cleanup()
        doc['source']['tree_sha256']=source
        directory=self.owner.run.directory;wrong=self.root/'wrong-run';wrong.mkdir(mode=0o700)
        self.owner.run.directory=wrong
        with self.assertRaises(AdmissionError):self.owner.cleanup()
        self.owner.run.directory=directory
        row=json.loads((self.root/'2012').read_text());changed=dict(row,volume_uuid='foreign-volume')
        (self.root/'2012').write_text(json.dumps(changed))
        with self.assertRaises(AdmissionError):self.owner.cleanup()
        (self.root/'2012').write_bytes(config)
        result=Path(json.loads(self.owner.pending.read_text())['binding']['result']['path']);result_bytes=result.read_bytes()
        result.write_text('{"status":17}')
        with self.assertRaises(AdmissionError):self.owner.cleanup()
        result.write_bytes(result_bytes)
        self.assertNotIn('destroy',[v[0] for v in self.native.calls])
        self.assertEqual(self.owner.cleanup(),0)
        self.assertEqual(self.owner.creation,creation)
        self.assertEqual([v[0] for v in self.native.calls],['create','stop','destroy'])
        accepted=sorted(self.owner_run.directory.glob('*-preservation-accepted.json'))[-1]
        destroyed=sorted(self.owner_run.directory.glob('*-destroy-result.json'))[-1]
        self.assertLess(accepted.name,destroyed.name)
        self.assertEqual(ackpath.read_bytes(),raw)
        print('PRESERVATION_BARRIER negatives=14 stop_pending_copy_ack_accept_destroy order=actual-records creation_ack_bytes_unchanged',flush=True)

    def test_authorized_rollback_lineage(self):
        self.owner.create()
        original = copy.deepcopy(self.owner.creation)
        self.assertEqual(self.owner.snapshot('original'), 0)
        self.assertEqual(self.owner.rollback('original'), 0)
        self.assertEqual(self.owner.current.volume_uuid, 'rollback-uuid')
        self.assertEqual(self.owner.creation, original)
        self.approve()
        self.assertEqual(self.owner.cleanup(), 0)
        self.assertFalse((self.root / '2012').exists())

    def test_rollback_without_snapshot(self):
        self.owner.create()
        self.refuse(lambda: self.owner.rollback('unknown'), 'snapshot')

    def test_foreign_numeric_id_survives(self):
        foreign = self.root / '2010'
        foreign.write_bytes(b'foreign numeric ID: preserve bytes')
        before = foreign.read_bytes()
        self.owner.create()
        self.approve()
        self.assertEqual(self.owner.cleanup(), 0)
        self.assertEqual(foreign.read_bytes(), before)


if __name__ == '__main__':
    sys.negative_control = len(sys.argv) == 3 and sys.argv[2] == '--negative-control'
    if len(sys.argv) != 2 and not sys.negative_control:
        raise SystemExit('requires independently installed context path')
    sys.argv_context = sys.argv[1]
    suite = unittest.TestSuite([Ownership('test_unowned_volume')]) if sys.negative_control else unittest.defaultTestLoader.loadTestsFromTestCase(Ownership)
    result = unittest.TextTestRunner(verbosity=2).run(suite)
    if result.wasSuccessful():
        print(f'WORKFLOW_OWNERSHIP_PASS cases={result.testsRun} native=recording process=actual')
    raise SystemExit(0 if result.wasSuccessful() else 1)
