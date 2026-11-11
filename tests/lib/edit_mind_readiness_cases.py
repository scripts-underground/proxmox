"""Actual emitted readiness policy over deterministic external service/log/socket facts."""
import ast
import json
from pathlib import Path

JOBS='Text model ready\nVisual model ready\nAudio model ready\nAll embedding models loaded'
ML='Loaded 6 plugins\nBLIP model loaded successfully\nModel download complete\nServer listening on'
PORTS=(3745,4000,8765,8000,5432,6379)


def emitted(root):
    tree=ast.parse((root/'tests/lib/edit_mind_native.py').read_text())
    remote=next(n.value.value for n in tree.body if isinstance(n,ast.Assign) and any(isinstance(t,ast.Name) and t.id=='REMOTE' for t in n.targets))
    ns={};exec(compile(remote.split('\naction=sys.argv[1]',1)[0],'actual-emitted-readiness','exec'),ns)
    return remote,ns


def producers(ns, directory, mode):
    directory.mkdir();ns['P']=directory
    state=dict(tick=0,props=0,changed=False,history=[],socket_reads=0)
    def endpoint_rows(ports):
        return '\n'.join('LISTEN 0 511 '+('[::]:'+str(p) if p%2 else '0.0.0.0:'+str(p))+' *:*' for p in ports)
    def success(invocation=None):
        if mode=='change-timeout':return False
        if mode=='change' and invocation=='a'*32:return True
        return mode in {'positive','current-error','boot-error','boot-restart','restart','failed','timeout'} or state['tick']>=2
    def q(*args,**kwargs):
        if args[0]=='systemctl':
            if args[1]=='is-active':return 'active'
            state['props']+=1
            if mode=='change' and state['props']>4:state['changed']=True
            invocation=('b' if state['changed'] or mode=='change-timeout' and state['tick'] else 'a')*32
            active='failed' if mode=='failed' and args[2]=='edit-mind-ml' else 'active'
            restarts='1' if mode=='restart' and args[2]=='edit-mind-jobs' else '0'
            if '--value' in args:return {'InvocationID':invocation,'NRestarts':restarts}[args[args.index('-p')+1]]
            return 'InvocationID='+invocation+'\nActiveState='+active+'\nNRestarts='+restarts
        if args[0]=='journalctl':
            unit=args[args.index('-u')+1]
            invocation=next((s.split('=',1)[1] for s in args if s.startswith('_SYSTEMD_INVOCATION_ID=')),None)
            log=JOBS if unit=='edit-mind-jobs' else ML if unit=='edit-mind-ml' else ''
            if invocation and not success(invocation):log='new invocation still loading'
            if mode=='boot-error' and invocation is None:log+='\nModel load failed private-secret-sentinel'
            if mode=='boot-restart' and invocation is None:log+='\nScheduled restart job, restart counter is at 1.'
            if mode=='current-error' and invocation:log+='\nFailed to initialize EasyOCR reader private-secret-sentinel'
            return log
        if args[0]=='ss':
            state['socket_reads']+=1
            ports=list(PORTS)
            if mode=='timeout' or mode=='stale' and state['tick']<2:ports.remove(4000);ports.append(40000)
            return endpoint_rows(ports)
        raise AssertionError(args)
    def sleep(seconds):
        p=directory/'readiness-after.json'
        if p.exists():state['history'].append(json.loads(p.read_text()))
        state['tick']+=901 if mode=='timeout' else 450 if mode=='change-timeout' else 1
    ns['q']=q
    ns['time']=type('Clock',(),dict(monotonic=staticmethod(lambda:float(state['tick'])),sleep=staticmethod(sleep)))
    return state,q


def old_red(test, root):
    remote,ns=emitted(root);directory=test.run_owner.directory/'old-readiness-advance'
    state,q=producers(ns,directory,'stale')
    result=ns['ready']()
    test.assertTrue(result['eager_control_flow']);test.assertEqual(state['tick'],0)
    test.assertEqual(state['socket_reads'],0)
    parsed=ast.parse(remote)
    assertion=next(n for n in ast.walk(parsed) if isinstance(n,ast.Assert) and "str(port)" in ast.unparse(n.test))
    predicate=eval(compile(ast.Expression(assertion.test),'actual-old-listener-assertion','eval'),dict(ns,ports=q('ss','-H','-lnt')))
    test.assertTrue(predicate)
    print('INVOCATION_READINESS_RED actual_old_ready_advanced=1 prior_boot_success=1 current_not_ready=1 port4000_absent_40000_present=1 old_listener_predicate_passed=1',flush=True)


def readiness(test, root):
    base=test.run_owner.directory/'readiness-contract';base.mkdir()
    for mode in ('stale','change','positive','current-error','boot-error','boot-restart','restart','failed','timeout','change-timeout'):
        _,ns=emitted(root);state,_=producers(ns,base/mode,mode)
        try:result=ns['ready']('after')
        except RuntimeError as error:
            test.assertIn(mode,{'current-error','boot-error','boot-restart','restart','failed','timeout','change-timeout'})
            test.assertNotIn('private-secret-sentinel',str(error))
            facts=json.loads((base/mode/'readiness-after.json').read_text())
            expected={'current-error':'init-error','boot-error':'init-error','boot-restart':'automatic-restart','restart':'automatic-restart','failed':'failed-unit','timeout':'deadline','change-timeout':'deadline'}[mode]
            test.assertEqual(facts['check_status'],expected)
            if mode=='timeout':
                test.assertEqual(facts['missing_listeners'],[4000]);test.assertIn('4000',str(error))
                test.assertTrue(all(facts['eager_markers']['edit-mind-ml'].values()))
            if mode=='change-timeout':
                test.assertEqual(facts['elapsed'],900)
                test.assertTrue(all(v['invocation']=='b'*32 for v in facts['states'].values()))
        else:
            test.assertIn(mode,{'stale','change','positive'})
            facts=json.loads((base/mode/'readiness-after.json').read_text())
            test.assertEqual(facts['check_status'],'ready');test.assertEqual(facts['missing_listeners'],[])
            test.assertEqual(result['listeners'],sorted(PORTS))
            if mode in {'stale','change'}:test.assertGreaterEqual(state['tick'],2)
            if mode=='stale':test.assertEqual(state['history'][0]['missing_listeners'],[4000])
            if mode=='change':
                test.assertEqual(state['history'][0]['check_status'],'invocation-changed')
                test.assertFalse(any(ok for values in state['history'][0]['eager_markers'].values() for ok in values.values()))
                test.assertTrue(all(value=='b'*32 for value in result['invocations'].values()))
        test.assertLessEqual((base/mode/'readiness-after.json').stat().st_size,8192)
        test.assertTrue(any((base/mode).glob('readiness-after-*.boot.journal')))
        test.assertTrue(any((base/mode).glob('readiness-after-*.current.journal')))
        print('INVOCATION_READINESS_GREEN '+json.dumps(dict(case=mode,status=facts['check_status'],missing_listeners=facts['missing_listeners'],elapsed=facts['elapsed'],diagnostics_persisted=True)),flush=True)
    _,ns=emitted(root)
    rows='LISTEN 0 1 [::]:40000 [::]:4000\nLISTEN 0 1 127.0.0.1:5432 *:*\nESTAB 0 1 *:4000 *:*'
    test.assertEqual(ns['tcp_listeners'](rows),{40000,5432})
    state,q=producers(ns,base/'post-consumers','positive');ns['ready']('after')
    ns['q']=lambda *args,**kwargs:rows if args[0]=='ss' else q(*args,**kwargs)
    with test.assertRaisesRegex(RuntimeError,'post-consumers-listeners-missing'):ns['require_listeners']('after')
    facts=json.loads((base/'post-consumers/readiness-after.json').read_text())
    test.assertIn(4000,facts['missing_listeners'])
    print('INVOCATION_LISTENER_PARSER_GREEN exact_local_TCP=1 peer4000_not_local=1 port40000_not4000=1 post_consumer_diagnostics=1 cases=12',flush=True)
