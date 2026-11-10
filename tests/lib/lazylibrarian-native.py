"""Application-owned bundle consumer. Never exports config, keys or app logs."""
import hashlib
import json
import os
from pathlib import Path
import subprocess
import tempfile

from entrypoint import admit_direct
from lazylibrarian_privacy_doc import procedure
from test_inputs import bindings


REMOTE = r'''
import base64,configparser,hashlib,hmac,json,os,pathlib,secrets,signal,sqlite3,stat,subprocess,sys,tarfile,threading,time,urllib.parse,urllib.request
P=pathlib.Path('/var/lib/ll-privacy-proof')
SERVICE='lazylibrarian.service'
DEFAULT=pathlib.Path('/opt/LazyLibrarian/config.ini')
POLICY=pathlib.Path('/etc/systemd/system/lazylibrarian.service.d/10-scripts-underground-private-config.conf')
# Pinned ConfigItem identifiers, types, defaults and owned fixture values.
# All consumers use field IDs; values, especially keys, are never case-normalized.
FIELDS={
 'API_ENABLED':('API','api_enabled',bool,False,True),
 'API_KEY':('API','api_key',str,'',None),
 'HTTP_PORT':('WEBSERVER','http_port',int,5299,5299),
 'HTTP_HOST':('WEBSERVER','http_host',str,'0.0.0.0','127.0.0.1'),
 'LAUNCH_BROWSER':('GENERAL','launch_browser',bool,True,False),
 'TELEMETRY_ENABLE':('TELEMETRY','telemetry_enable',bool,False,False),
 'LOGSIZE':('LOGGING','logsize',int,204800,204801),
}
def field(name):
 assert name in FIELDS,'unknown private fixture field'
 return FIELDS[name]
def cmd(*args,seconds=90):
 r=subprocess.run(args,capture_output=True,text=True,timeout=seconds)
 assert r.returncode==0,'checked native command failed: '+args[0]
 return r.stdout.strip()
def show(name):return cmd('systemctl','show',SERVICE,'--property='+name,'--value')
def wait(fn,seconds=90):
 end=time.monotonic()+seconds
 while not fn():
  assert time.monotonic()<end,'native wait deadline';time.sleep(.02)
def emit(label,data):
 row=dict(label=label,**data)
 with (P/(label+'.json')).open('w') as f:json.dump(row,f,sort_keys=True)
 print(json.dumps(row,sort_keys=True),flush=True)
 return row
def private_write(path,raw):
 fd=os.open(path,os.O_WRONLY|os.O_CREAT|os.O_TRUNC|os.O_NOFOLLOW,0o600)
 with os.fdopen(fd,'wb') as f:f.write(raw)
 os.chmod(path,0o600)
def actual():return pathlib.Path((P/'selected').read_text())
def family(path):return [pathlib.Path(str(path)+suffix) for suffix in ('','.new','.bak','.bak2')]
def config(path):
 parser=configparser.ConfigParser(interpolation=None)
 with path.open() as stream:parser.read_file(stream)
 assert not parser.defaults(),'physical config proof refuses DEFAULT inheritance'
 return parser
def physical(name,path=None):
 section,option,kind,default,seed_value=field(name)
 parser=config(actual() if path is None else path)
 assert parser.has_section(section) and parser.has_option(section,option),'required physical field absent: '+name
 value=parser.get(section,option)
 if kind is bool:
  assert value.lower() in parser.BOOLEAN_STATES,'invalid boolean field: '+name
  return parser.BOOLEAN_STATES[value.lower()]
 return kind(value)
def same_key():return hmac.compare_digest(physical('API_KEY'),(P/'key').read_text())
def expected_setting():return json.loads((P/'expected.json').read_text())['LOGSIZE']
def remember_setting(value):private_write(P/'expected.json',json.dumps(dict(LOGSIZE=value)).encode())
def next_setting(old):
 value=old+1
 if value==field('LOGSIZE')[3]:value+=1
 assert value!=old and value!=field('LOGSIZE')[3]
 return value
def api_field(command,name,value=None):
 section,option,kind,default,seed_value=field(name)
 values=dict(name=name,group=section)
 if value is not None:values['value']=str(value)
 return api(command,**values).strip()
def memory_setting():
 response=api_field('readCFG','LOGSIZE')
 assert response.startswith('[') and response.endswith(']'),'invalid LOGSIZE API response'
 return int(response[1:-1])
def api(command,**values):
 key=(P/'key').read_text()
 body=urllib.parse.urlencode(dict(apikey=key,cmd=command,**values)).encode()
 request=urllib.request.Request('http://127.0.0.1:5299/api',data=body,headers={'Content-Type':'application/x-www-form-urlencoded'})
 with urllib.request.urlopen(request,timeout=20) as response:return response.read().decode()
def ready():
 def available():
  try:
   with urllib.request.urlopen('http://127.0.0.1:5299/',timeout=5) as response:ui=response.read()
   return b'LazyLibrarian' in ui and api('getIndex').strip() in ('[]','{}')
  except (OSError,ValueError):return False
 wait(available)
 assert show('UMask')=='0077' and same_key()
 pid=int(show('MainPID'));status=pathlib.Path('/proc/'+str(pid)+'/status').read_text()
 fields=dict(line.split(':',1) for line in status.splitlines() if ':' in line)
 assert fields['Umask'].strip()=='0077' and fields['Uid'].split()==['0']*4
 return pid
def reloaded():
 ready()
 assert physical('LOGSIZE')==expected_setting() and memory_setting()==expected_setting()
 assert same_key()
def thread_status(pid):
 rows=[]
 for path in pathlib.Path('/proc/'+str(pid)+'/task').glob('*/status'):
  try:
   d=dict(line.split(':',1) for line in path.read_text().splitlines() if ':' in line)
   rows.append(dict(tid=int(path.parent.name),state=d['State'].strip().split()[0],tracer=int(d['TracerPid'].strip())))
  except FileNotFoundError:continue
 return rows
def creation(path,pidfn,seconds=90):
 end=time.monotonic()+seconds
 while time.monotonic()<end:
  try:
   s=path.lstat();pid=pidfn();threads=thread_status(pid)
   held=[r for r in threads if r['tracer']>0 and r['state'] in ('t','T')]
   if held and s.st_size==0:
    assert stat.S_ISREG(s.st_mode) and stat.S_IMODE(s.st_mode)==0o600
    return dict(mode=stat.S_IMODE(s.st_mode),inode=s.st_ino,device=s.st_dev,uid=s.st_uid,gid=s.st_gid,bytes_before_return=s.st_size,held_threads=held)
  except (FileNotFoundError,ProcessLookupError,ValueError):pass
  time.sleep(.01)
 raise AssertionError('no creation-time open-exit observation')
def detach(pid,tracer):
 assert pathlib.Path('/proc/'+str(tracer)+'/exe').resolve()==pathlib.Path('/usr/bin/strace')
 command=pathlib.Path('/proc/'+str(tracer)+'/cmdline').read_bytes()
 assert str(P).encode() in command or str(actual()).encode() in command
 os.kill(tracer,signal.SIGINT)
 wait(lambda:all(row['tracer']==0 for row in thread_status(pid)),15)
def snapshot():
 return {str(p):dict(raw=base64.b64encode(p.read_bytes()).decode(),inode=p.stat().st_ino,uid=p.stat().st_uid,gid=p.stat().st_gid,mode=p.stat().st_mode&0o777) for p in family(actual()) if p.exists()}
def observe(label):
 pid=ready();modes={}
 env=dict(item.split(b'=',1) for item in pathlib.Path('/proc/'+str(pid)+'/environ').read_bytes().split(b'\0') if b'=' in item)
 assert env.get(b'LL_PRIVACY_SENTINEL')==b'retained'
 for p in family(actual()):
  if p.exists():
   s=p.lstat();assert stat.S_ISREG(s.st_mode) and s.st_uid==0 and s.st_mode&0o777==0o600
   modes[p.name]=dict(mode=s.st_mode&0o777,inode=s.st_ino)
 assert pathlib.Path(str(actual())+'.bak').exists() and pathlib.Path(str(actual())+'.bak2').exists()
 data=pathlib.Path((P/'datadir').read_text());canary=data/'privacy-canary'
 if not canary.exists():private_write(canary,b'owned root application-data canary')
 assert canary.read_bytes()==b'owned root application-data canary' and canary.stat().st_uid==0
 db=sqlite3.connect('file:'+str(data/'lazylibrarian.db')+'?mode=ro',uri=True)
 try:assert db.execute('pragma integrity_check').fetchone()==('ok',)
 finally:db.close()
 return emit(label,dict(pid=pid,invocation=show('InvocationID'),key_equal=True,modes=modes,native_ui_api=True,root_data=True,operator_environment_consumed=True))
def save(label,instrument=True,fault=False):
 pid=ready();path=pathlib.Path(str(actual())+'.new');assert not path.exists()
 before=snapshot();old=physical('LOGSIZE');assert old==expected_setting()
 if not instrument:assert all(row['tracer']==0 for row in thread_status(pid))
 value=next_setting(old)
 trace=P/(label+'.trace');tracer=None;record={};errors=[]
 if instrument:
  action='inject=openat:error=EACCES:when=1' if fault else 'inject=openat:delay_exit=3s'
  with (P/(label+'.attach')).open('wb') as err:
   tracer=subprocess.Popen(['strace','-f','-p',str(pid),'-e','trace=openat','-P',str(path),'-e',action,'-o',str(trace)],stdout=subprocess.DEVNULL,stderr=err)
  wait(lambda:bool(thread_status(pid)) and all(r['tracer']==tracer.pid for r in thread_status(pid)),15)
  if not fault:
   def watch():
    try:record.update(creation(path,lambda:pid))
    except BaseException as error:errors.append(type(error).__name__)
   worker=threading.Thread(target=watch);worker.start()
 try:
  assert api_field('writeCFG','LOGSIZE',value)=='OK'
  if instrument and not fault:worker.join(timeout=15);assert not worker.is_alive() and not errors and record
 finally:
  if tracer is not None:
   if tracer.poll() is None:tracer.send_signal(signal.SIGINT)
   tracer.wait(timeout=15)
   assert all(r['tracer']==0 for r in thread_status(pid))
 if fault:
  assert snapshot()==before and not path.exists() and 'EACCES' in trace.read_text()
  assert physical('LOGSIZE')==old and memory_setting()==value and same_key()
  emit(label,dict(failed_writer_retains_active_and_backups=True,key_equal=same_key(),trace=trace.read_text()))
  return
 assert memory_setting()==value
 assert physical('LOGSIZE')==value and same_key()
 after=snapshot();assert after[str(actual())+'.bak']==before[str(actual())]
 if str(actual())+'.bak' in before:assert after[str(actual())+'.bak2']==before[str(actual())+'.bak']
 assert all(row['mode']==0o600 and row['uid']==0 for row in after.values())
 if instrument:
  assert 'DELAYED' in trace.read_text() and '0666' in trace.read_text()
  assert after[str(actual())]['inode']==record['inode']
 remember_setting(value)
 emit(label,dict(creation=record,rotations_private=True,key_equal=True,setting_roundtrip=True,instrumented=instrument,trace=trace.read_text() if instrument else None))
def seed(path):
 key=(P/'key').read_text() if (P/'key').exists() else secrets.token_hex(16)
 private_write(P/'key',key.encode())
 parser=configparser.ConfigParser(interpolation=None)
 for name in FIELDS:
  section,option,kind,default,value=field(name)
  if name=='API_KEY':value=key
  if not parser.has_section(section):parser.add_section(section)
  parser.set(section,option,str(value))
 with path.open('w') as stream:parser.write(stream)
 path.chmod(0o600);private_write(P/'selected',str(path).encode());private_write(P/'datadir',str(path.parent).encode())
 remember_setting(field('LOGSIZE')[4])
def checkpoint():
 pending=P/'checkpoint.pending'
 if not pending.exists():return
 expected=json.loads(pending.read_text())
 for name,row in expected.items():
  p=pathlib.Path(name);s=p.lstat()
  assert p.read_bytes()==base64.b64decode(row['raw']) and (s.st_ino,s.st_uid,s.st_gid)==(row['inode'],row['uid'],row['gid']) and s.st_mode&0o777==0o600
 private_write(P/'checkpoint.result',b'config bytes, owners, inodes unchanged; all modes600')
 pending.unlink()
def migrate(label,kind):
 cmd('systemctl','stop',SERVICE)
 assert show('MainPID')=='0'
 source=actual().read_bytes();default_before=DEFAULT.read_bytes()
 if POLICY.exists():assert POLICY.read_bytes()==b'[Service]\nUMask=0077\n';POLICY.unlink()
 unit=pathlib.Path('/etc/systemd/system/'+SERVICE)
 unit.write_bytes(unit.read_bytes().replace(b'UMask=0077',b'UMask=0002'))
 data=DEFAULT.parent if kind=='default' else P/('data-'+kind)
 data.mkdir(mode=0o700,exist_ok=True)
 selected=DEFAULT if kind=='default' else data/'config.ini' if kind=='datadir' else P/'custom config/selected.ini'
 selected.parent.mkdir(mode=0o700,exist_ok=True)
 private_write(P/'selected',str(selected).encode());private_write(P/'datadir',str(data).encode())
 for index,path in enumerate(family(selected)):
  private_write(path,source+('\n# owned generation '+str(index)+'\n').encode());path.chmod(0o664)
 argv=['/opt/LazyLibrarian/venv/bin/python3','/opt/LazyLibrarian/LazyLibrarian.py','--nojobs','--nolaunch','--datadir='+str(data)]
 if kind!='datadir':argv.append('--config='+str(selected))
 quoted=' '.join('"'+arg.replace('\\','\\\\').replace('"','\\"')+'"' for arg in argv)
 operator=pathlib.Path('/etc/systemd/system/'+SERVICE+'.d/50-operator.conf')
 operator.write_text('[Service]\nEnvironment=LL_PRIVACY_SENTINEL=retained\nWorkingDirectory=/opt/LazyLibrarian\nRestartSec=17\nExecStart=\nExecStart='+quoted+'\nExecStartPre=\nExecStartPre=/usr/bin/python3 '+str(P/'probe.py')+' checkpoint\n')
 baseline=snapshot()
 if (P/'checkpoint.result').exists():(P/'checkpoint.result').unlink()
 private_write(P/'checkpoint.pending',json.dumps(baseline,sort_keys=True).encode())
 before_unit=unit.read_bytes();before_operator=operator.read_bytes()
 cmd('systemctl','daemon-reload')
 result=subprocess.run(['/bin/bash',str(P/'upgrade.sh')],env=dict(os.environ,CONFIG_FILE=str(selected)),capture_output=True,text=True,timeout=180)
 private_write(P/(label+'.procedure-log'),(result.stdout+result.stderr).encode())
 assert result.returncode==0 and (P/'checkpoint.result').exists() and not (P/'checkpoint.pending').exists(),'native documented migration failed'
 assert unit.read_bytes()==before_unit and operator.read_bytes()==before_operator
 if kind!='default':assert DEFAULT.read_bytes()==default_before
 reloaded();save(label+'-save-1');save(label+'-save-2');save(label+'-ordinary',False);observe(label+'-outcome')
 emit(label,dict(selected_explicitly=True,custom_path=kind!='default',config_precedence=kind=='selected',datadir_only=kind=='datadir',all_four_prestart_bytes_owners_inodes=True,unit_operator_bytes=True,default_untouched=kind!='default',key_equal=True))
def startup_trace_argv(target,trace,command):
 return ['/usr/bin/strace','-D','-I','2','-f','-e','trace=openat','-P',str(target),'-e','inject=openat:delay_exit=3s','-o',str(trace),*command]
def startup_unit():
 command=['/opt/LazyLibrarian/venv/bin/python3','/opt/LazyLibrarian/LazyLibrarian.py','--nojobs','--nolaunch']
 argv=startup_trace_argv(pathlib.Path(str(DEFAULT)+'.new'),P/'startup.trace',command)
 # Fixed test-only argv; systemd double-quote and percent escaping, not shell execution.
 rendered=' '.join('"'+arg.replace('\\','\\\\').replace('"','\\"').replace('%','%%')+'"' for arg in argv)
 return '[Service]\nExecStart=\nExecStart='+rendered+'\n'
def qualify():
 w=P/'qualification';w.mkdir(mode=0o700);target=w/'config.new';returned=w/'returned';readyfile=w/'ready'
 code="""import os,pathlib,sys,threading
w=pathlib.Path(sys.argv[1]);os.umask(0o077);go=threading.Event()
def writer():
 go.wait()
 with (w/'config.new').open('w') as f:(w/'returned').write_text('returned');f.write('owned data')
t=threading.Thread(target=writer);t.start();(w/'ready').write_text('ready');sys.stdin.buffer.read(1);go.set();t.join()
"""
 child=subprocess.Popen(['python3','-B','-c',code,str(w)],stdin=subprocess.PIPE,stdout=subprocess.PIPE,stderr=subprocess.PIPE)
 wait(readyfile.exists,15)
 with (w/'attach').open('wb') as err:
  tracer=subprocess.Popen(['strace','-f','-p',str(child.pid),'-e','trace=openat','-P',str(target),'-e','inject=openat:delay_exit=3s','-o',str(w/'trace')],stdout=subprocess.DEVNULL,stderr=err)
 wait(lambda:len(thread_status(child.pid))==2 and all(r['tracer']==tracer.pid for r in thread_status(child.pid)),15)
 child.stdin.write(b'g');child.stdin.flush()
 observed=creation(target,lambda:child.pid,15);assert not returned.exists()
 child.communicate(timeout=15);tracer.wait(timeout=15)
 assert child.returncode==0 and tracer.returncode==0 and 'DELAYED' in (w/'trace').read_text()
 assert observed['inode']==target.stat().st_ino
 ordinary=w/'ordinary'
 subprocess.run(['python3','-B','-c','import os,pathlib,sys;os.umask(0o077);pathlib.Path(sys.argv[1]).write_text("ordinary")',str(ordinary)],check=True,timeout=10)
 assert stat.S_IMODE(ordinary.stat().st_mode)==0o600
 # Share the actual startup argv AND qualify detach while its finite writer lives.
 w2=w/'startup';w2.mkdir(mode=0o700);target2=w2/'config.new'
 startup="""import os,pathlib,select,sys,threading,time
w=pathlib.Path(sys.argv[1]);os.umask(0o077);go=threading.Event();finish=threading.Event();ordinary=threading.Event()
def writer():
 go.wait()
 if finish.is_set():return
 with (w/'config.new').open('w') as f:(w/'returned').write_text('returned');f.write('owned')
 (w/'complete').write_text('complete');count=0
 while not finish.wait(.03):
  count+=1;(w/'progress').write_text(str(count))
  if ordinary.is_set():
   (w/'ordinary').write_text('ordinary');ordinary.clear();(w/'ordinary-complete').write_text('complete')
t=threading.Thread(target=writer);t.start();(w/'ready').write_text('ready');end=time.monotonic()+35
try:
 while time.monotonic()<end:
  readable,_,_=select.select([0],[],[],.1)
  if not readable:continue
  control=os.read(0,1)
  if control==b'g':go.set()
  elif control==b'o':ordinary.set()
  elif control in (b'q',b''):break
finally:
 finish.set();go.set();t.join(timeout=5);assert not t.is_alive()
"""
 argv=startup_trace_argv(target2,w2/'trace',['python3','-B','-c',startup,str(w2)])
 proc=subprocess.Popen(argv,stdin=subprocess.PIPE,stdout=subprocess.DEVNULL,stderr=subprocess.DEVNULL)
 def progress():
  try:return int((w2/'progress').read_text())
  except (FileNotFoundError,ValueError):return 0
 try:
  wait((w2/'ready').exists,15)
  wait(lambda:len(thread_status(proc.pid))==2 and all(r['tracer']>0 for r in thread_status(proc.pid)),15)
  proc.stdin.write(b'g');proc.stdin.flush()
  observed2=creation(target2,lambda:proc.pid,15);assert not (w2/'returned').exists()
  wait((w2/'complete').exists,15);wait(lambda:progress()>=2,5)
  tracers={r['tracer'] for r in thread_status(proc.pid)};assert len(tracers)==1
  old_progress=progress();detach(proc.pid,next(iter(tracers)))
  assert proc.poll() is None and all(r['tracer']==0 for r in thread_status(proc.pid))
  wait(lambda:progress()>old_progress,5)
  proc.stdin.write(b'o');proc.stdin.flush();wait((w2/'ordinary-complete').exists,5)
  assert (w2/'ordinary').stat().st_mode&0o777==0o600 and all(r['tracer']==0 for r in thread_status(proc.pid))
  assert target2.stat().st_ino==observed2['inode'] and 'DELAYED' in (w2/'trace').read_text()
  detached=dict(all_threads_untraced=True,writer_alive=True,progress_before=old_progress,progress_after=progress(),ordinary_mode=0o600)
 finally:
  if proc.poll() is None:proc.stdin.write(b'q');proc.stdin.flush()
  proc.wait(timeout=15)
 assert proc.returncode==0
 emit('receiver-observer',dict(attach_threads=True,path_filter_delay_exit=True,before_return=observed,startup_before_return=observed2,ordinary_after_detach=True,startup_detach=detached,startup_argv=argv,finite_writer_status=proc.returncode))
def bootstrap():
 assert os.geteuid()==0 and os.environ['TMPDIR']=='/var/lib/scripts-underground-test/tmp'
 P.mkdir(mode=0o700)
def inspect_archives():
 meta=json.loads((P/'fixture.json').read_text())
 assert meta['commit']=='8b6ba44398f6c74c4dd29b13dc2047b771e27488' and meta['uv']=='0.13.7' and meta['python']=='3.12.16'
 for name,row in meta['artifacts'].items():
  p=P/name;assert p.stat().st_size==row['bytes'] and hashlib.sha256(p.read_bytes()).hexdigest()==row['sha256']
 with tarfile.open(P/'uv.tar.gz') as archive:archive.extractall(P,filter='data')
 cmd('install','-m','0755',str(P/'uv-x86_64-unknown-linux-gnu/uv'),'/usr/local/bin/uv')
 (P/'python').mkdir(mode=0o700)
 with tarfile.open(P/'python.tar.gz') as archive:archive.extractall(P/'python',filter='data')
 emit('fixture-inputs',dict(source_commit=meta['commit'],uv=cmd('/usr/local/bin/uv','--version'),python=cmd(str(P/'python'/meta['python_directory']/'bin/python3.12'),'--version'),controlled_git_transport=True))
def identity(label):
 ready()
 return emit(label,dict(pid_namespace=os.readlink('/proc/1/ns/pid'),pid1_birth=pathlib.Path('/proc/1/stat').read_text().split(') ',1)[1].split()[19],boot_id=pathlib.Path('/proc/sys/kernel/random/boot_id').read_text().strip(),service_invocation=show('InvocationID')))
def units(verify):
 paths=[pathlib.Path('/etc/systemd/system/'+SERVICE),POLICY,POLICY.with_name('50-operator.conf')]
 rows={str(p):dict(raw=base64.b64encode(p.read_bytes()).decode(),mode=p.stat().st_mode&0o777,uid=p.stat().st_uid,gid=p.stat().st_gid) for p in paths}
 if verify:
  assert rows==json.loads((P/'updater-protected').read_text())
  assert cmd('git','-C','/opt/LazyLibrarian','rev-parse','HEAD')=='8b6ba44398f6c74c4dd29b13dc2047b771e27488'
  emit('cold-updater-preservation',dict(base_operator_policy_bytes_and_metadata=True,same_commit_controlled_origin=True))
 else:private_write(P/'updater-protected',json.dumps(rows,sort_keys=True).encode())
def conflict():
 p=pathlib.Path('/etc/systemd/system/'+SERVICE+'.d/99-private-conflict.conf');private_write(p,b'[Service]\nUMask=0002\n');cmd('systemctl','daemon-reload')
 result=subprocess.run(['/bin/bash',str(P/'upgrade.sh')],env=dict(os.environ,CONFIG_FILE=str(actual())),capture_output=True,timeout=120)
 assert result.returncode!=0 and show('ActiveState')=='inactive' and show('MainPID')=='0' and p.read_bytes()==b'[Service]\nUMask=0002\n'
 p.unlink();cmd('systemctl','daemon-reload')
 result=subprocess.run(['/bin/bash',str(P/'upgrade.sh')],env=dict(os.environ,CONFIG_FILE=str(actual())),capture_output=True,timeout=120)
 assert result.returncode==0;reloaded();emit('native-conflict-retry',dict(conflict_refused_stopped=True,operator_bytes_preserved=True,normal_retry=True,key_equal=same_key()))
action=sys.argv[1]
if action=='bootstrap':bootstrap()
elif action=='archives':inspect_archives()
elif action=='qualify':qualify()
elif action=='startup-unit':print(startup_unit(),end='')
elif action=='seed':seed(pathlib.Path(sys.argv[2]))
elif action=='startup-observer':
 private_write(P/'startup-observer.ready',b'ready')
 observed=creation(pathlib.Path(str(DEFAULT)+'.new'),lambda:int(show('MainPID')))
 private_write(P/'startup-creation.json',json.dumps(observed,sort_keys=True).encode())
elif action=='fresh':
 source_commit=(P/'fresh-source.commit').read_text().strip()
 assert source_commit=='8b6ba44398f6c74c4dd29b13dc2047b771e27488'
 emit('fresh-source-provenance',dict(source_commit=source_commit,verified_before_seed_and_app_install=True))
 pid=ready();record=json.loads((P/'startup-creation.json').read_text());tracers={r['tracer'] for r in thread_status(pid) if r['tracer']}
 assert len(tracers)==1;detach(pid,next(iter(tracers)))
 trace=P/'startup.trace';assert 'DELAYED' in trace.read_text()
 p=pathlib.Path('/etc/systemd/system/'+SERVICE+'.d/90-startup-trace.conf');p.unlink();cmd('systemctl','daemon-reload')
 emit('startup-preload-creation',dict(creation=record,trace=trace.read_text(),detached=True))
 reloaded();save('fresh-save-1');save('fresh-save-2');save('fresh-ordinary',False);observe('fresh-outcome')
elif action=='migrate':migrate(sys.argv[2],sys.argv[3])
elif action=='checkpoint':checkpoint()
elif action=='conflict':conflict()
elif action=='save':save(sys.argv[2],sys.argv[3]!='ordinary',sys.argv[3]=='fault')
elif action=='observe':observe(sys.argv[2])
elif action=='identity':identity(sys.argv[2])
elif action=='reloaded':reloaded();emit(sys.argv[2],dict(persisted_setting_reloaded=True,key_equal=True))
elif action=='units':units(sys.argv[2]=='verify')
else:raise AssertionError('unknown private probe action')
'''


def main():
    context = admit_direct('maintenance-lazylibrarian-native', [])
    _, inputs = bindings(context)
    fixture = Path(inputs['LAZYLIBRARIAN_FIXTURE'])
    root = Path(context.document['source']['path'])
    ctid = str(context.operation['nested'][0]['ctid'])
    work = Path(tempfile.mkdtemp(prefix='ll-privacy-native.', dir=os.environ['TMPDIR']))
    target = '/var/lib/ll-privacy-proof'

    def pct(*args, seconds=120):
        result = subprocess.run(['/usr/sbin/pct', *args], capture_output=True, text=True, timeout=seconds)
        if result.returncode:
            raise RuntimeError('native typed command failed: ' + args[0])
        return result.stdout

    def execute(*argv, seconds=120):
        return pct('exec', ctid, '--', *argv, seconds=seconds)

    def push(raw, name):
        stage = work / name
        stage.write_bytes(raw)
        pct('push', ctid, str(stage), target + '/' + name)
        actual = execute('sha256sum', target + '/' + name).split()[0]
        assert actual == hashlib.sha256(raw).hexdigest()
        stage.unlink()

    def probe(*args, seconds=180):
        out = execute('/usr/bin/python3', target + '/probe.py', *args, seconds=seconds)
        print(out, end='', flush=True)
        return [json.loads(line) for line in out.splitlines() if line.startswith('{')]

    execute('/usr/bin/python3', '-B', '-c', REMOTE, 'bootstrap')
    push(REMOTE.encode(), 'probe.py')
    push(procedure(root).encode(), 'upgrade.sh')
    for path in sorted(fixture.iterdir()):
        push(path.read_bytes(), path.name)
    execute('/bin/sh', '-ec', 'export DEBIAN_FRONTEND=noninteractive; apt install -y strace', seconds=180)
    probe('qualify')
    probe('archives')
    # Source/tool selection and Git transport are explicit fixture inputs only.
    setup = r'''
set -euo pipefail
ROOT="$1"
P=/var/lib/ll-privacy-proof
source <(sed '/^# framework bootstrap/,$d' "$ROOT/scripts/lxc/lazylibrarian.sh")
source "$ROOT/misc/bundle.func"
export APP=LazyLibrarian NSAPP=lazylibrarian REPO_BASE="$2"
export var_lxc_tmpdir=/var/lib/scripts-underground-test/tmp
prefix='export UV_VERSION=0.13.7 UV_PYTHON_INSTALL_DIR=/var/lib/ll-privacy-proof/python UV_PYTHON_DOWNLOADS=never; '
prefix+='git() { if [[ "$*" == "clone https://gitlab.com/LazyLibrarian/LazyLibrarian /opt/LazyLibrarian" ]]; then /usr/bin/git clone /var/lib/ll-privacy-proof/upstream.bundle /opt/LazyLibrarian || return; local commit; commit=$(/usr/bin/git -C /opt/LazyLibrarian rev-parse HEAD) || return; [[ "$commit" == 8b6ba44398f6c74c4dd29b13dc2047b771e27488 ]] || return 65; printf "%s\n" "$commit" > /var/lib/ll-privacy-proof/fresh-source.commit; /usr/bin/python3 /var/lib/ll-privacy-proof/probe.py seed /opt/LazyLibrarian/config.ini; else /usr/bin/git "$@"; fi; }; '
prefix+='systemctl() { if [[ "$*" == "enable -q --now lazylibrarian" ]]; then /usr/bin/python3 /var/lib/ll-privacy-proof/probe.py startup-observer > /var/lib/ll-privacy-proof/startup-observer.log 2>&1 & local observer=$!; while [[ ! -f /var/lib/ll-privacy-proof/startup-observer.ready ]]; do sleep .02; done; /usr/bin/systemctl "$@"; wait "$observer"; else /usr/bin/systemctl "$@"; fi; }; '
_write_bundle install install_script "$ROOT/misc" "${prefix}install_script" > "$P/install.sh"
_write_bundle update update_script "$ROOT/misc" --requirements "${var_cpu-}" "${var_ram-}" -- "${prefix}run_update_script \"\$@\"" > "$P/update.sh"
chmod 0700 "$P/install.sh" "$P/update.sh"
mkdir -p /etc/systemd/system/lazylibrarian.service.d
cat > /etc/systemd/system/lazylibrarian.service.d/50-operator.conf <<'UNIT'
[Service]
Environment=LL_PRIVACY_SENTINEL=retained
ExecStart=
ExecStart=/opt/LazyLibrarian/venv/bin/python3 /opt/LazyLibrarian/LazyLibrarian.py --nojobs --nolaunch
UNIT
/usr/bin/python3 "$P/probe.py" startup-unit > /etc/systemd/system/lazylibrarian.service.d/90-startup-trace.conf
timeout 1200s bash "$P/install.sh" > "$P/install.log" 2>&1
'''
    execute('/bin/bash', '-c', setup, '--', str(root), os.environ['SU_TEST_REPO_BASE'], seconds=1250)
    probe('fresh')
    probe('migrate', 'legacy-default', 'default')
    probe('migrate', 'legacy-selected', 'selected')
    probe('migrate', 'legacy-datadir', 'datadir')
    probe('conflict')
    probe('save', 'native-open-failure', 'fault')
    probe('save', 'native-writer-retry', 'ordinary')
    before = probe('identity', 'before-service-restart')[-1]
    execute('systemctl', 'restart', 'lazylibrarian')
    probe('reloaded', 'service-reload-before-mutation')
    probe('save', 'after-service-restart', 'ordinary')
    probe('observe', 'after-service-restart-outcome')
    after = probe('identity', 'after-service-restart')[-1]
    assert before['service_invocation'] != after['service_invocation']
    # The actual unchanged updater pulls this fixture's same-commit bundle origin.
    probe('units', 'remember')
    execute('/bin/sh', '-ec', 'timeout 600s bash /var/lib/ll-privacy-proof/update.sh > /var/lib/ll-privacy-proof/update.log 2>&1', seconds=650)
    probe('units', 'verify')
    probe('reloaded', 'updater-reload-before-mutation')
    probe('save', 'after-cold-updater', 'ordinary')
    probe('observe', 'after-cold-updater-outcome')
    before = probe('identity', 'before-ct-stop')[-1]
    pct('stop', ctid, seconds=150)
    assert pct('status', ctid).strip() == 'status: stopped'
    pct('start', ctid, seconds=150)
    after = probe('identity', 'after-ct-start')[-1]
    probe('reloaded', 'ct-reload-before-mutation')
    assert before['pid_namespace'] != after['pid_namespace'] and before['pid1_birth'] != after['pid1_birth']
    assert before['service_invocation'] != after['service_invocation']
    probe('save', 'after-ct-start-save-1', 'ordinary')
    probe('save', 'after-ct-start-save-2', 'ordinary')
    probe('observe', 'after-ct-start-outcome')
    print('LL_PRIVACY_NATIVE_PASS actual guide/app/saves/creation/rotations/restarts; keys retained inside CT', flush=True)


if __name__ == '__main__':
    main()
