"""App harness proofs: real owner/adapter, only external PVE/tool producers modeled."""
import ast
from contextlib import contextmanager
import json
import os
from pathlib import Path
import re
import subprocess
import threading
from types import SimpleNamespace
from unittest.mock import patch


def bootstrap_literal(source):
    tree=ast.parse(source)
    return next(n.args[2].value for n in ast.walk(tree) if isinstance(n,ast.Call) and
                isinstance(n.func,ast.Name) and n.func.id=='execute' and len(n.args)==3 and
                all(isinstance(a,ast.Constant) for a in n.args) and n.args[0].value=='/bin/sh')


def creator_baseline(test, root, old=False):
    source=(root/'misc/build.func').read_text()
    section=source.split('elif [[ "$var_os" =~ ^(debian|ubuntu|devuan)$ ]]; then',1)[1].split('\n  else\n',1)[0]
    direct=[row for row in re.findall(r'apt-get install -y ([a-z0-9 -]+) >/dev/null',section) if 'sudo' in row.split()]
    alternate=re.findall(r'APT_BASE="([a-z0-9 -]+)"',section)
    test.assertEqual(len(direct),2);test.assertEqual(len(alternate),1)
    packages=tuple(direct[0].split())
    test.assertTrue(all(tuple(row.split())==packages for row in direct+alternate))
    test.assertIn("export LC_ALL=C.UTF-8 LANG=C.UTF-8 DEBIAN_FRONTEND=noninteractive;",section)
    text=(root/'tests/lib/edit_mind_native.py').read_text()
    if old:
        bootstrap=bootstrap_literal(text)
        missing=sorted(set(packages)-set(bootstrap.split()))
        test.assertEqual(missing,['gnupg2','mc','sudo'])
        print('CREATOR_BASELINE_RED missing='+','.join(missing),flush=True)
        return
    import edit_mind_native as app
    test.assertEqual(app.CREATOR_PACKAGES,packages)
    test.assertFalse(set(app.CREATOR_PACKAGES)&set(app.PROBE_PACKAGES))
    test.assertIn('export LC_ALL=C.UTF-8 LANG=C.UTF-8 DEBIAN_FRONTEND=noninteractive;',app.BOOTSTRAP)
    test.assertIn("execute('/bin/sh','-ec',BOOTSTRAP)",text)
    work=test.run_owner.directory/'creator-minimal';work.mkdir();binary=work/'bin';binary.mkdir()
    # No gpg or ambient PATH escape exists initially. apt models package/tool
    # production only; command/API observation and receiver shell are actual.
    tools={'sudo':'sudo','curl':'curl','mc':'mc','gnupg2':'gpg','jq':'jq','bash':'bash',
           'python3':'python3','git':'git','xz-utils':'xz','unzip':'unzip','iproute2':'ip',
           'ca-certificates':None}
    provision=[]
    for package in app.CREATOR_PACKAGES+app.PROBE_PACKAGES:
        tool=tools[package]
        if tool:provision.append('printf "#!/bin/sh\\nexit 0\\n" > "$BIN/'+tool+'"; /bin/chmod 755 "$BIN/'+tool+'"')
    models='apt() { printf "%s\\n" "$*" >> "$PROOF/apt-argv"; if [ "$1" = install ]; then '+ '; '.join(provision)+'; fi; };\n'
    env=dict(PATH=str(binary),BIN=str(binary),PROOF=str(work),TMPDIR=os.environ['TMPDIR'])
    before=subprocess.run(['/bin/sh','-ec','command -v gpg'],env=env,capture_output=True,text=True,timeout=5)
    test.assertNotEqual(before.returncode,0)
    p=subprocess.run(['/bin/sh','-ec',models+app.BOOTSTRAP],env=env,capture_output=True,text=True,timeout=10)
    test.assertEqual(p.returncode,0,(p.stdout,p.stderr))
    installed=(work/'apt-argv').read_text().splitlines()
    test.assertEqual(installed,['update','install -y '+' '.join(app.CREATOR_PACKAGES+app.PROBE_PACKAGES)])
    test.assertTrue((binary/'gpg').exists())
    generator=next(n.value.value for n in ast.walk(ast.parse(text)) if isinstance(n,ast.Assign) and
                   any(isinstance(t,ast.Name) and t.id=='generate' for t in n.targets))
    test.assertEqual(generator.count('export APPLICATION="$APP"'),2)
    test.assertIn('setting_up_container network_check update_os install_script motd_ssh setup_lxc cleanup_lxc',generator)
    print('CREATOR_BASELINE_GREEN branches=3 packages=5 probe_extras='+str(len(app.PROBE_PACKAGES))+' initially_no_gpg=1 actual_shell_tool_observation=1 apt_producer=modeled identity_pipeline=unchanged',flush=True)


@contextmanager
def pve_fixture(test):
    from test_pve import NativePVE
    native,_,create=test.native_fixture();root=native.run.directory
    config=root/'pve.conf';state={'present':False,'running':True,'shutdowns':0,'fail_stop':False,'wait':None}
    trace=[];events=[];record=native.run.record
    def save(label,row):events.append((label,row));return record(label,row)
    native.run.record=save
    spec=native.owner.spec
    raw='\n'.join(['hostname: '+spec.hostname,'tags: '+spec.tag,'cores: 2','memory: 2048',
                  'unprivileged: 1','features: nesting=1,keyctl=1','net0: name=eth0,bridge=vmbr0,hwaddr='+spec.mac,
                  'rootfs: su-thin:vm-2012-disk-0,size=8G','onboot: 1'])+'\n'
    def path(*args):
        p=Path(*args)
        if str(p)=='/etc/pve/lxc/2012.conf':trace.append(['config-read']);return config
        if str(p)=='/etc/pve/qemu-server/2012.conf':return root/'absent-vm.conf'
        return p
    def query(argv):
        trace.append(['query',*argv])
        if argv[0]=='/usr/sbin/lvs':
            rows=[dict(vg_name='su_data',lv_name='vm-2012-disk-0',lv_uuid='stateful-owned-lv')] if state['present'] else []
            return json.dumps(dict(report=[dict(lv=rows)]))
        if argv==['/usr/sbin/pct','status','2012']:return 'status: '+('running' if state['running'] else 'stopped')
        raise AssertionError(argv)
    def external(tool,args):
        trace.append([tool,*args]);action=args[0]
        if action=='create':state['present']=True;config.write_text(raw)
        elif action=='shutdown':
            state['shutdowns']+=1
            if not state['running']:return subprocess.CompletedProcess(args,255,'','CT 2012 not running')
            if state['wait']:state['wait']()
            if state['fail_stop']:return subprocess.CompletedProcess(args,9,'','shutdown failed')
            state['running']=False
        elif action=='status':return subprocess.CompletedProcess(args,0,'status: '+('running' if state['running'] else 'stopped')+'\n','')
        elif action=='set':
            test.assertEqual(args,['set','2012','--onboot','0']);config.write_text(config.read_text().replace('onboot: 1','onboot: 0'))
        elif action=='destroy':raise AssertionError('test must never ACK or destroy')
        return subprocess.CompletedProcess(args,0,'','')
    native._process=external;native.call=external
    native.observe=lambda ctid:NativePVE.observe_static(ctid,native.n)
    with patch('test_pve.Path',path),patch('test_pve.query',query):
        test.assertEqual(native.dispatch('pct',create).returncode,0)
        yield native,state,trace,events


def old_double_stop(test):
    from edit_mind_native_guard import Guard
    with pve_fixture(test) as (native,state,trace,events):
        guard=Guard(native);native.call=guard.call;guard.counter=lambda:0
        with guard:pass
        with guard.route('retention'):result=native.owner.finish(251)
        test.assertEqual(result,251);test.assertEqual(state['shutdowns'],2)
        test.assertEqual(native.owner.cleanup_status,255)
        preservation=next(row for label,row in events if label=='failure-preservation')
        test.assertEqual(preservation['state'],'unknown')
        print('ACTUAL_OWNER_DOUBLE_STOP_RED producer251 result251 shutdowns2 preservation255 state_unknown actual_finish_native_adapter=1 external_PVE=stateful',flush=True)


def retention(test):
    from edit_mind_native_guard import Guard
    cases=[(0,False,False,False),(251,False,False,False),(251,True,False,False),
           (0,True,False,False),(251,True,True,True),(0,False,True,True)]
    for producer,threshold,fail_stop,fail_link in cases:
        with pve_fixture(test) as (native,state,trace,events):
            entered=threading.Event();emergency=threading.Event();normal=threading.Event();release=threading.Event();answers=[]
            state['fail_stop']=fail_stop
            def during_stop():
                entered.set()
                if threshold:test.assertTrue(emergency.wait(3),'shutdown blocked emergency routing')
                else:release.set()
            state['wait']=during_stop
            guard=Guard(native);router=guard.call;native.call=router
            guard.counter=lambda:Guard.STOP_RX if threshold and entered.is_set() else 0
            def normal_call(tool,args):
                normal.set();test.assertTrue(release.wait(3));return subprocess.CompletedProcess(args,42,'','')
            guard.process=normal_call
            def link(argv,**kwargs):
                test.assertEqual(kwargs['timeout'],4)
                test.assertEqual(argv[-8:],['/usr/bin/timeout','2s','/usr/sbin/ip','link','set','dev','eth0','down'])
                trace.append(['emergency',*argv]);emergency.set();release.set()
                return subprocess.CompletedProcess(argv,7 if fail_link else 0,'','')
            with patch('edit_mind_native_guard.subprocess',SimpleNamespace(run=link,SubprocessError=subprocess.SubprocessError)):
                with guard:
                    worker=threading.Thread(target=lambda:answers.append(native.dispatch('pct',['exec','2012','--','/bin/true']).returncode))
                    worker.start();test.assertTrue(normal.wait(3))
                    result=guard.finish(producer)
                    release.set();worker.join(3)
            test.assertFalse(worker.is_alive());test.assertEqual(answers,[42])
            test.assertIs(native.call,router);test.assertEqual(state['shutdowns'],1)
            test.assertTrue(guard.monitor_complete);test.assertFalse(guard.thread.is_alive())
            expected=producer if producer else 9 if fail_stop else 125 if threshold else 75
            test.assertEqual(result,expected)
            complete=next(row for label,row in events if label=='edit-mind-monitor-completion')
            test.assertEqual(complete['retention'],'unknown' if fail_stop else 'stopped')
            if not fail_stop:
                test.assertTrue(any(row[:4]==['pct','set','2012','--onboot'] for row in trace))
                test.assertTrue(any(row[:3]==['pct','status','2012'] for row in trace))
                test.assertTrue(any(row[:2]==['query','/usr/sbin/lvs'] for row in trace))
            if not producer and not threshold and not fail_stop:test.assertIsNotNone(native.owner.pending)
            if fail_stop:test.assertEqual(guard.containment_status,7 if fail_link else 0)
            print('ACTUAL_OWNER_RETENTION_GREEN '+json.dumps(dict(producer=producer,result=result,shutdowns=state['shutdowns'],threshold=threshold,failed_stop=fail_stop,failed_link=fail_link,retention=complete['retention'],monitor_joined=True,trace=trace),sort_keys=True),flush=True)
