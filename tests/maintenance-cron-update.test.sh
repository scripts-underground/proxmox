#!/usr/bin/env bash
# Real manager/menu/generated executable; PVE, packages and crontab are recording
# models in a private native mount namespace/chroot. No real CT/package effects.
set -euo pipefail
python3 -B "$(dirname -- "${BASH_SOURCE[0]}")/lib/entrypoint.py" maintenance-cron-update "$@" || exit $?
[[ "${SU_TEST_GUARD_ONLY:-0}" != 1 ]] || exit 0
systemd-detect-virt --vm --quiet || exit 65
: "${TMPDIR:?disk TMPDIR required}"
case "$(findmnt -rn -T "$TMPDIR" -o FSTYPE)" in '' | tmpfs | ramfs) exit 65 ;; esac
ROOT=$(realpath "$(dirname "${BASH_SOURCE[0]}")/..")
exec python3 -B - "$ROOT" << 'PY'
import fcntl,hashlib,json,os,pathlib,shlex,stat,subprocess,sys,tempfile,time
R=pathlib.Path(sys.argv[1]);W=pathlib.Path(tempfile.mkdtemp(prefix='cron-update.',dir=os.environ['TMPDIR']))
print('Cron evidence: '+str(W),flush=True)
checks=[]
def check(name,wanted,actual):
 ok=wanted==actual;checks.append(dict(name=name,expected=wanted,actual=actual,passed=ok));print(('PASS ' if ok else 'FAIL ')+name+(' '+repr((wanted,actual)) if not ok else ''),flush=True)
def write(p,s,mode=0o644):p.parent.mkdir(parents=True,exist_ok=True);p.write_text(s);p.chmod(mode)
def read(p):return p.read_text() if p.is_file() else '<absent>'
model=r'''#!/usr/bin/python3
import json,os,pathlib,signal,subprocess,sys,time
c=pathlib.Path('/data');name=pathlib.Path(sys.argv[0]).name;a=sys.argv[1:];fault=(c/'fault').read_text();db=c/'targets.json';targets=json.loads(db.read_text())
with (c/'calls').open('a') as f:f.write(json.dumps([name,a])+'\n')
if name=='curl':
 if a[-1].endswith('/misc/bootstrap/pve'):
  print('source /source/misc/core.func')
  if fault=='dependency':print('unset -f _app_maintenance_import_guard')
  sys.exit(0)
 print('curl: (22) absent worker',file=sys.stderr);sys.exit(22)
if name=='whiptail':print((c/'menu').read_text(),file=sys.stderr);sys.exit(0)
if name=='clear':sys.exit(0)
if name=='crontab':
 if '-l' in a:sys.stdout.write((c/'crontab').read_text())
 else:(c/'crontab').write_text(sys.stdin.read())
 sys.exit(0)
if name=='rm':
 if any('EXTERNALLY-MANAGED' in v for v in a):sys.exit(86)
 os.execv('/usr/bin/rm',['rm',*a])
if name in ('chmod','mv','mktemp'):
 if fault==name:sys.exit({'chmod':72,'mv':74,'mktemp':71}[name])
 if name=='mktemp' and fault=='write':
  p=subprocess.run(['/usr/bin/mktemp',*a],capture_output=True,text=True,check=True,timeout=5).stdout.strip();pathlib.Path(p).unlink();pathlib.Path(p).symlink_to('/dev/full');print(p);sys.exit(0)
 os.execv('/usr/bin/'+name,[name,*a])
if name=='timeout':
 t=targets.get(os.environ.get('CTID',''),{});kind=t.get('timeout_kind','gnu')
 if kind=='missing':sys.exit(127)
 if kind=='busybox':print('BusyBox timeout');sys.exit(0)
 if a!=['--version'] and t.get('fixture_deadline'):
  # Explicit fixture boundary: retain the generated request, shorten only the
  # hanging GNU semantics cases, then run the real utility/process group.
  requested=list(a);a=['--kill-after=1','1',*a[2:]]
  with (c/'deadline-substitutions').open('a') as f:f.write(json.dumps(dict(requested=requested,effective=a))+'\n')
 os.execv('/usr/bin/timeout',['timeout',*a])
if name in ('apt','apt-get','apk','pacman','dnf','zypper'):
 t=targets[os.environ['CTID']];rc=t.get('package_rc',0)
 id=os.environ['CTID'];metadata=any(v in a for v in ('update','-Sy','makecache','refresh'));upgrade=any(v in a for v in ('dist-upgrade','upgrade','-Syu','-Su','dup'))
 if metadata:
  t['metadata_count']=t.get('metadata_count',0)+1;db.write_text(json.dumps(targets))
  if t.get('metadata_seconds'):time.sleep(t['metadata_seconds'])
  if t['metadata_count']<=t.get('metadata_failures',0):rc=t.get('metadata_rc',28)
  if t.get('metadata_hang') and t['metadata_count']<=t.get('hang_attempts',3):
   mode=t['metadata_hang'];signal.signal(signal.SIGTERM,signal.SIG_IGN if mode=='kill' else signal.SIG_DFL)
   child=subprocess.Popen(['/usr/bin/python3','-B','-c','import signal,time;signal.signal(signal.SIGTERM,signal.SIG_IGN if '+repr(mode)+'=="kill" else signal.SIG_DFL);time.sleep(300)'])
   (c/('child-'+id+'-'+str(t['metadata_count']))).write_text(str(child.pid))
   with (c/'events').open('a') as f:f.write(json.dumps(dict(id=id,phase='metadata-hang',time=time.monotonic(),pid=os.getpid(),child=child.pid,group=os.getpgrp()))+'\n')
   time.sleep(300)
 if t.get('fail_at') and t['fail_at'] not in a:rc=0
 if upgrade and t.get('require_ready') and not (c/('ready-'+id)).exists():rc=88;(c/'premature-upgrade').write_text(id)
 if not rc and metadata:(c/('ready-'+id)).write_text('configured metadata consumed')
 if not rc and upgrade:(c/('updated-'+id)).write_text(name+' '+ ' '.join(a))
 with (c/'events').open('a') as f:f.write(json.dumps(dict(id=id,phase='metadata' if metadata else 'upgrade',time=time.monotonic(),rc=rc,argv=[name,*a]))+'\n')
 sys.exit(rc)
if name=='ash':os.execv('/bin/sh',['sh',*a])
if name!='pct':sys.exit(86)
if os.environ.get('CRON_ACTOR')=='contender':sys.exit(91)
action=a[0]
if action=='list':
 print('VMID Status Lock Name')
 for id,t in targets.items():print(id,t['state'],'-', 'fixture')
 sys.exit(0)
id=a[1];t=targets[id]
if t.get('barriers') and action in ('exec','shutdown'):
 phase='shutdown' if action=='shutdown' else 'exec-'+str(t.get('exec_count',0)+1)
 if action=='exec':t['exec_count']=t.get('exec_count',0)+1;db.write_text(json.dumps(targets))
 lock=pathlib.Path('/var/lib/scripts-underground/maintenance-locks/cron-update-lxcs.lock');fds=[]
 if lock.exists():
  s=lock.stat()
  for p in pathlib.Path('/proc/self/fd').iterdir():
   try:
    f=p.stat()
    if (f.st_dev,f.st_ino)==(s.st_dev,s.st_ino):fds.append(dict(fd=p.name,info=pathlib.Path('/proc/self/fdinfo',p.name).read_text()))
   except FileNotFoundError:pass
 (c/('barrier-'+phase)).write_text(json.dumps(dict(pid=os.getpid(),fds=fds)))
 end=time.monotonic()+15
 while not (c/('release-'+phase)).exists():
  if time.monotonic()>end:sys.exit(92)
  time.sleep(.02)
if action=='config':
 if t.get('config_rc'):sys.exit(t['config_rc'])
 print('ostype: '+t['os']);print('template: '+str(t.get('template',0)));sys.exit(0)
if action=='status':
 phase='initial' if not t.get('start_seen') else 'post-start' if not t.get('post_start_status_seen') else 'later';rc=t.get('status_rc',0)
 if not rc and phase=='post-start':
  t['post_start_status_seen']=True;db.write_text(json.dumps(targets));rc=t.get('post_start_status_rc',0)
 with (c/'status-results').open('a') as f:f.write(json.dumps(dict(id=id,phase=phase,status=rc,state=t['state']))+'\n')
 if rc:sys.exit(rc)
 print('status: '+t['state']);sys.exit(0)
if action in ('start','shutdown'):
 rc=t.get(action+'_rc',0)
 if not rc:
  if action=='start':t['start_seen']=True
  if not t.get(action+'_unchanged'):t['state']='running' if action=='start' else 'stopped'
  db.write_text(json.dumps(targets))
 sys.exit(rc)
if action=='exec':
 if t['state']!='running':sys.exit(87)
 command=a[2:];command=command[1:] if command[:1]==['--'] else command
 start=time.monotonic();result=subprocess.run(command,env=dict(os.environ,CTID=id),timeout=35)
 with (c/'exec-results').open('a') as f:f.write(json.dumps(dict(id=id,status=result.returncode,seconds=time.monotonic()-start,argv=command))+'\n')
 sys.exit(result.returncode)
sys.exit(86)
'''
launch=r'''
set -euo pipefail
mount --bind /usr "$1/root/usr"
mount -o remount,bind,ro "$1/root/usr"
mount --bind "$1/bin" "$1/root/usr/local/bin"
mount --bind /dev "$1/root/dev"
mount --bind /proc "$1/root/proc"
mount --bind "$2" "$1/root/source"
mount -o remount,bind,ro "$1/root/source"
mount --bind "$1" "$1/root/data"
if [[ -e "$1/read-only-lock" ]]; then
  mount --bind "$1/root/var/lib/scripts-underground/maintenance-locks" "$1/root/var/lib/scripts-underground/maintenance-locks"
  mount -o remount,bind,ro "$1/root/var/lib/scripts-underground/maintenance-locks"
fi
shift 2
exec chroot "$CASE/root" /usr/bin/env PATH=/usr/local/bin:/usr/bin:/bin TMPDIR=/data/scratch PYTHONDONTWRITEBYTECODE=1 TERM=dumb "$@"
'''
def case(name,targets=None):
 c=W/name;c.mkdir();(c/'bin').mkdir();(c/'scratch').mkdir();root=c/'root'
 for n in ('usr','dev','proc','source','data','etc/alternatives','var/log'): (root/n).mkdir(parents=True,exist_ok=True)
 (root/'etc/alternatives/awk').symlink_to('/usr/bin/mawk')
 for n in ('bin','sbin','lib','lib64'):(root/n).symlink_to('usr/'+n)
 for n in ('pct','curl','whiptail','clear','crontab','chmod','mv','mktemp','rm','apt','apt-get','apk','pacman','dnf','zypper','ash','timeout'):write(c/'bin'/n,model,0o755)
 write(c/'fault','');write(c/'menu','Add');write(c/'calls','');write(c/'crontab','MAILTO=operator@example.invalid\n17 3 * * * /unrelated-job\n')
 write(c/'targets.json',json.dumps(targets or {}));write(root/'etc/update-lxcs.conf','# exact operator bytes\n EXCLUDE = 901, 902 # kept\n')
 write(root/'etc/unrelated','operator bytes\n');return c
def invoke(c,argv,stdin='',menu=None,fault='',actor='',pass_fds=()):
 if menu:write(c/'menu',menu)
 write(c/'fault',fault)
 n=len(list(c.glob('result-*.json')))
 r=subprocess.run(['unshare','--mount','--propagation','private','/bin/bash','-c',launch,'_',str(c),str(R),*argv],input=stdin,env=dict(os.environ,CASE=str(c),CRON_ACTOR=actor),pass_fds=pass_fds,capture_output=True,text=True,timeout=135)
 write(c/f'result-{n}.json',json.dumps(dict(argv=argv,status=r.returncode,stdout=r.stdout,stderr=r.stderr),indent=2));return r
manager=['/bin/bash','/source/scripts/pve/cron-update-lxcs.sh']
def calls(c):return [json.loads(v) for v in read(c/'calls').splitlines()]
def effects(c):return [v for v in calls(c) if v[0]=='pct' and v[1][0] in ('start','exec','shutdown','stop','destroy')]
c=case('add');before=read(c/'root/etc/update-lxcs.conf');r=invoke(c,manager,'y\ny\n',menu='Add');worker=c/'bin/update-lxcs.sh'
check('manager Add publishes available local worker',0,r.returncode)
check('manager installs executable bytes',True,worker.is_file() and os.access(worker,os.X_OK))
if not worker.is_file():
 print('RED unavailable-worker consumer: '+r.stderr,flush=True);sys.exit(1)
payload=worker.read_bytes();digest=hashlib.sha256(payload).hexdigest()
check('review displays actual installed worker',True,payload.decode() in r.stdout)
check('review displays installed SHA256',True,digest in r.stdout)
check('manager keeps exact existing config',before,read(c/'root/etc/update-lxcs.conf'))
check('Sunday schedule and unrelated crontab retained','MAILTO=operator@example.invalid\n17 3 * * * /unrelated-job\n0 0 * * 0 /usr/local/bin/update-lxcs.sh >>/var/log/update-lxcs-cron.log 2>&1\n',read(c/'crontab'))
check('no separate remote worker request',[],[v for v in calls(c) if v[0]=='curl' and not v[1][-1].endswith('/misc/bootstrap/pve')])
for menu,stdin,fault in [('Add','n\nn\n',''),('Add','y\nn\n',''),('Add','',''),('Add','n\ny\n','chmod'),('Add','n\ny\n','mv'),('Add','n\ny\n','mktemp'),('Add','n\ny\n','write'),('Update','n\n',''),('Update','',''),('Update','y\n','chmod'),('Update','y\n','mv'),('Update','y\n','mktemp'),('Update','y\n','write')]:
 # Force a changed installed worker, then observe complete manager preservation.
 write(worker,'#!/bin/bash\nprintf old-worker\n',0o755);old=worker.read_bytes();cron=read(c/'crontab');conf=read(c/'root/etc/update-lxcs.conf')
 r=invoke(c,manager,stdin,menu=menu,fault=fault)
 check(menu+'/'+(fault or ('EOF' if not stdin else 'decline'))+' previous executable retained',old,worker.read_bytes())
 check(menu+'/'+fault+' config retained',conf,read(c/'root/etc/update-lxcs.conf'))
 check(menu+'/'+fault+' crontab retained',cron,read(c/'crontab'))
 check(menu+'/'+fault+' owned stages removed',[],sorted(p.name for p in (c/'bin').glob('.update-lxcs.*'))+sorted(p.name for p in (c/'scratch').iterdir()))
 if fault:check(menu+'/'+fault+' actual failure status',{'chmod':72,'mv':74,'mktemp':71,'write':1}[fault],r.returncode)
r=invoke(c,manager,'y\n',menu='Update');check('Update replaces worker from executing manager',payload,worker.read_bytes());check('Update status',0,r.returncode)
# Real generated bytes are executed cold and offline for every modeled target.
def worker_case(name,targets,config='EXCLUDE=\n',args=(),expected=0):
 c=case(name,targets);write(c/'bin/update-lxcs.sh',payload.decode(),0o755);write(c/'root/etc/update-lxcs.conf',config)
 r=invoke(c,['/usr/local/bin/update-lxcs.sh',*args]);check(name+' exit status',expected,r.returncode)
 check(name+' no transport or destructive lifecycle',[],[v for v in calls(c) if v[0]=='curl' or v[0]=='pct' and v[1][0] in ('stop','destroy')])
 check(name+' unrelated bytes retained','operator bytes\n',read(c/'root/etc/unrelated'))
 check(name+' no Python policy deletion attempted',[],[v for v in calls(c) if v[0]=='rm' and any('EXTERNALLY-MANAGED' in a for a in v[1])])
 return c,r
c,r=worker_case('no-targets',{})
check('empty PVE list no effects',[],effects(c))
targets={str(100+i):dict(os=osname,state='running') for i,osname in enumerate(('debian','ubuntu','devuan','alpine','archlinux','fedora','rocky','centos','alma','opensuse'))}
c,r=worker_case('distros',targets)
for id,t in targets.items():
 expected={'debian':'apt','ubuntu':'apt','devuan':'apt','alpine':'apk','archlinux':'pacman','fedora':'dnf','rocky':'dnf','centos':'dnf','alma':'dnf','opensuse':'zypper'}[t['os']]
 check(id+' actual package producer consumed',True,read(c/('updated-'+id)).startswith(expected+' '))
check('running targets never stopped',[],[v for v in effects(c) if v[1][0]!='exec'])
c,r=worker_case('distro-failures',{id:dict(t,package_rc=23) for id,t in targets.items()},expected=23)
for id in targets:check(id+' failing native command retained and next target reached',True,any(v[0]=='pct' and v[1][:2]==['exec',id] for v in calls(c)) and not (c/('updated-'+id)).exists())
c,r=worker_case('apt-upgrade-failure',{'100':dict(os='debian',state='running',package_rc=24,fail_at='dist-upgrade')},expected=24)
check('apt metadata then upgrade producer actually reached',2,len([v for v in calls(c) if v[0]=='apt']))
check('failed apt upgrade no successful outcome',False,(c/'updated-100').exists())
c,r=worker_case('selection',{str(i):dict(os='debian',state='running',template=int(i==104)) for i in range(100,106)},' # comment\n EXCLUDE = 100, 101 # literal values\n',('102','103'))
check('args/config/template skipped before effects',['105'],[v[1][1] for v in effects(c)])
for config,args in [('EXCLUDE=100,bad\n',()),('EXCLUDE=$(touch /etc/injected)\n',()),('EXCLUDE=100,,101\n',()),('OTHER=100\n',()),('EXCLUDE=\n',('100;id',))]:
 c,r=worker_case('invalid-'+str(len(checks)),{'100':dict(os='debian',state='stopped')},config,args,65)
 check('invalid input rejected before pct effects',[],effects(c));check('config never sourced',False,(c/'root/etc/injected').exists())
for name,fields,expected,operations,state in [
 ('stopped',{},0,['start','exec','exec','shutdown'],'stopped'),
 ('start-failure',{'start_rc':31},31,['start'],'stopped'),
 ('start-not-running',{'start_unchanged':True},1,['start'],'stopped'),
 ('package-failure',{'package_rc':23,'fail_at':'dist-upgrade'},23,['start','exec','exec','shutdown'],'stopped'),
 ('shutdown-failure',{'shutdown_rc':32},32,['start','exec','exec','shutdown'],'running'),
 ('both-failures',{'package_rc':23,'fail_at':'dist-upgrade','shutdown_rc':32},23,['start','exec','exec','shutdown'],'running'),
 ('shutdown-not-stopped',{'shutdown_unchanged':True},1,['start','exec','exec','shutdown'],'running'),
 ('unknown-os',{'os':'unknown'},0,[],'stopped'),
 ('unknown-state',{'state':'suspended'},1,[],'suspended'),
 ('config-failure',{'config_rc':37},37,[],'stopped'),
 ('status-failure',{'status_rc':38},38,[],'stopped')]:
 t=dict(os='debian',state='stopped');t.update(fields)
 c,r=worker_case(name,{'100':t,'101':dict(os='alpine',state='running')},expected=expected)
 check(name+' exact selected lifecycle',operations,[v[1][0] for v in effects(c) if v[1][1]=='100'])
 check(name+' original/restored state',state,json.loads(read(c/'targets.json'))['100']['state'])
 check(name+' next independent target updates',True,(c/'updated-101').is_file())
 for v in effects(c):
  if v[1][0]=='shutdown':check(name+' bounded graceful no force',['shutdown','100','--timeout','60','--forceStop','0'],v[1])
 if name=='unknown-os':check('unknown OS explicitly skipped',True,'skip' in r.stdout.lower())
 if expected:check(name+' reports failed outcome',True,str(expected) in r.stdout+r.stderr)
c=case('fresh');(c/'root/etc/update-lxcs.conf').unlink();r=invoke(c,manager,'n\ny\n',menu='Add');check('fresh Add status',0,r.returncode);check('fresh config empty exclusion',True,read(c/'root/etc/update-lxcs.conf').endswith('EXCLUDE=\n'))
c=case('custom-schedule');write(c/'bin/update-lxcs.sh','#!/bin/bash\nexit 7\n',0o755);write(c/'crontab','MAILTO=operator@example.invalid\n4 5 * * 1 /usr/local/bin/update-lxcs.sh 900\n');before=read(c/'crontab');r=invoke(c,manager,'y\n',menu='Update');check('Update keeps exact custom schedule',before,read(c/'crontab'))
c=case('run-failure',{'100':dict(os='debian',state='running',package_rc=23),'101':dict(os='alpine',state='running')});write(c/'bin/update-lxcs.sh',payload.decode(),0o755);r=invoke(c,manager,menu='Run');check('manager Run failure status',23,r.returncode);check('manager does not claim failed Run completed',False,'Run completed' in r.stdout);check('manager log contains package failure',True,'failed (23)' in read(c/'root/var/log/update-lxcs-cron.log'));check('manager failed Run still updates next target',True,(c/'updated-101').exists())
c=case('run-remove',{'100':dict(os='debian',state='running')});write(c/'bin/update-lxcs.sh',payload.decode(),0o755)
r=invoke(c,manager,menu='Run');check('manager Run consumes installed worker',0,r.returncode);check('manager Run actual package outcome',True,(c/'updated-100').exists());check('manager Run log consumer',True,'100' in read(c/'root/var/log/update-lxcs-cron.log'))
conf=read(c/'root/etc/update-lxcs.conf');cron=read(c/'crontab');r=invoke(c,manager,menu='Remove');check('Remove status',0,r.returncode);check('Remove executable absent',False,(c/'bin/update-lxcs.sh').exists());check('Remove config preserved',conf,read(c/'root/etc/update-lxcs.conf'));check('Remove unrelated cron preserved',cron,read(c/'crontab'))
def events(c,id):return [json.loads(v) for v in (c/'events').read_text().splitlines() if json.loads(v)['id']==id] if (c/'events').is_file() else []
def upgrades(c,id):return [v for v in events(c,id) if v['phase']=='upgrade']
begin=len(checks)
for name,shutdown_rc in [('post-start-query-error',0),('post-start-query-and-restore-error',32)]:
 c,r=worker_case(name,{'100':dict(os='debian',state='stopped',post_start_status_rc=29,shutdown_rc=shutdown_rc),'101':dict(os='alpine',state='running')},expected=29)
 status=[json.loads(v) for v in (c/'status-results').read_text().splitlines() if json.loads(v)['id']=='100']
 check(name+' fault is first POST-start query only',[('initial',0),('post-start',29)],[(v['phase'],v['status']) for v in status[:2]])
 check(name+' owned start reaches shared restoration',['start','shutdown'],[v[1][0] for v in effects(c) if v[1][1]=='100'])
 check(name+' no package or metadata effects',[],[v for v in effects(c) if v[1][1]=='100' and v[1][0]=='exec'])
 check(name+' metadata never attempted',0,json.loads(read(c/'targets.json'))['100'].get('metadata_count',0))
 check(name+' final state','running' if shutdown_rc else 'stopped',json.loads(read(c/'targets.json'))['100']['state'])
 check(name+' next independent target updated',True,(c/'updated-101').exists())
 check(name+' observation operation reported',True,'start observation failed (29)' in r.stdout+r.stderr)
 if shutdown_rc:check(name+' restoration failure separately reported',True,'restoration failed (32)' in r.stdout+r.stderr)
 else:check(name+' actual stopped restoration observed',True,len(status)==3 and status[-1]['status']==0 and status[-1]['state']=='stopped')
 for v in effects(c):
  if v[1][0]=='shutdown':check(name+' bounded graceful owned restore',['shutdown','100','--timeout','60','--forceStop','0'],v[1])
if any(not x['passed'] for x in checks[begin:]):
 write(W/'checks.json',json.dumps(checks,indent=2,default=lambda v:dict(bytes_sha256=hashlib.sha256(v).hexdigest())));print('RED successful owned start followed by query failure bypasses restoration',flush=True);sys.exit(1)
print('Deadline fixtures: requested production120s/5s; only hanging cases explicitly use real GNU1s/1s. Slow metadata is unscaled23s.',flush=True)
start=time.monotonic();c,r=worker_case('slow-metadata',{'100':dict(os='debian',state='stopped',metadata_seconds=23,require_ready=True)},expected=0);elapsed=time.monotonic()-start
check('slow metadata unscaled elapsed above old20s and below120s',True,22<elapsed<120)
check('slow metadata completes in one attempt',1,json.loads(read(c/'targets.json'))['100']['metadata_count'])
check('slow metadata gets exactly one upgrade',1,len(upgrades(c,'100')))
check('slow metadata is not a shortened deadline fixture',False,(c/'deadline-substitutions').exists())
check('slow metadata actual generated timeout is120/5',[['--kill-after=5','120']], [v[1][:2] for v in calls(c) if v[0]=='timeout' and v[1]!=['--version']])
check('slow metadata restores stopped state','stopped',json.loads(read(c/'targets.json'))['100']['state'])
if r.returncode:
 write(W/'checks.json',json.dumps(checks,indent=2,default=lambda v:dict(bytes_sha256=hashlib.sha256(v).hexdigest())));print('RED actual23-second metadata exceeds original20-second budget; no upgrade',flush=True);sys.exit(1)
for osname in ('debian','ubuntu','devuan','alpine','archlinux','fedora','rocky','centos','alma','opensuse'):
 c,r=worker_case('delayed-'+osname,{'100':dict(os=osname,state='stopped',metadata_failures=1,require_ready=True)},expected=0)
 e=events(c,'100');m=[v for v in e if v['phase']=='metadata'];u=upgrades(c,'100')
 check(osname+' delayed metadata attempted twice',2,len(m));check(osname+' upgrade occurs exactly once',1,len(u));check(osname+' no premature upgrade',False,(c/'premature-upgrade').exists())
 check(osname+' successful metadata precedes upgrade',True,bool(m and u and m[-1]['rc']==0 and m[-1]['time']<=u[0]['time']))
 check(osname+' bounded retry delay used',True,len(m)==2 and 4.5<=m[1]['time']-m[0]['time']<12)
 check(osname+' restored after ready upgrade','stopped',json.loads(read(c/'targets.json'))['100']['state'])
 if r.returncode or len(m)!=2 or len(u)!=1:
  write(W/'checks.json',json.dumps(checks,indent=2,default=lambda v:dict(bytes_sha256=hashlib.sha256(v).hexdigest())));print('RED configured-metadata readiness reaches upgrade only after actual delayed metadata consumer',flush=True);sys.exit(1)
for name,t,expected in [
 ('readiness-exhausted',dict(metadata_failures=99),28),
 ('readiness-restore-failed',dict(metadata_failures=99,shutdown_rc=32),28),
 ('timeout-missing',dict(timeout_kind='missing'),69),
 ('timeout-unsafe',dict(timeout_kind='busybox'),69),
 ('readiness-timeout',dict(metadata_hang='term',fixture_deadline=True),124),
 ('readiness-kill-group',dict(metadata_hang='kill',hang_attempts=1,metadata_failures=99,fixture_deadline=True),28)]:
 t=dict(os='debian',state='stopped',require_ready=True,**t);start=time.monotonic();c,r=worker_case(name,{'100':t,'101':dict(os='alpine',state='running')},expected=expected);elapsed=time.monotonic()-start
 check(name+' no upgrade on failed readiness',0,len(upgrades(c,'100')) if (c/'events').exists() else 0)
 check(name+' no premature upgrade',False,(c/'premature-upgrade').exists());check(name+' later target still updates',True,(c/'updated-101').exists())
 check(name+' restoration only checked started target',['100'],[v[1][1] for v in effects(c) if v[1][0]=='shutdown'])
 check(name+' final state retained','running' if t.get('shutdown_rc') else 'stopped',json.loads(read(c/'targets.json'))['100']['state'])
 check(name+' finite attempts',0 if name.startswith('timeout-') else 3,json.loads(read(c/'targets.json'))['100'].get('metadata_count',0))
 check(name+' finite fixture wall time (<110s)',True,elapsed<110)
 children=[int(p.read_text()) for p in c.glob('child-*')]
 for pid in children:
  p=pathlib.Path('/proc')/str(pid)/'stat';check(name+' timed metadata descendant no longer running',True,not p.exists() or p.read_text().split(') ',1)[1].split()[0]=='Z')
 if name in ('readiness-timeout','readiness-kill-group'):
  results=[json.loads(v) for v in read(c/'exec-results').splitlines() if json.loads(v)['id']=='100'];timeouts=[v for v in results if v['status'] in (124,137)]
  check(name+' real native explicitly scaled timeout observed',3 if name=='readiness-timeout' else 1,len(timeouts))
  check(name+' explicit1s/1s TERM/KILL bound is real',True,all((0.8<=v['seconds']<6) for v in timeouts))
  substitutions=[json.loads(v) for v in (c/'deadline-substitutions').read_text().splitlines()]
  check(name+' every actual generated request is120/5',True,len(substitutions)==3 and all(v['requested'][:2]==['--kill-after=5','120'] for v in substitutions))
  check(name+' only native fixture deadlines substituted',True,all(v['effective'][:2]==['--kill-after=1','1'] and v['effective'][2:]==v['requested'][2:] for v in substitutions))
  if name=='readiness-kill-group':check('KILL deadline status survives inner shell',137,timeouts[0]['status'] if timeouts else None)
c,r=worker_case('running-no-boot-wait',{'100':dict(os='debian',state='running',metadata_failures=1,timeout_kind='missing')},expected=28)
check('already running has no new timeout/readiness path',[],[v for v in calls(c) if v[0]=='timeout']);check('already running retains one normal metadata attempt',1,json.loads(read(c/'targets.json'))['100']['metadata_count'])
# Every entry path must enter the same native owner before config or PVE reads.
begin=len(checks)
c=case('concurrent-owner',{'100':dict(os='debian',state='stopped',barriers=True)})
write(c/'bin/update-lxcs.sh',payload.decode(),0o755);write(c/'root/etc/update-lxcs.conf','EXCLUDE=\n')
holder=subprocess.Popen(['unshare','--mount','--propagation','private','/bin/bash','-c',launch,'_',str(c),str(R),'/usr/local/bin/update-lxcs.sh'],env=dict(os.environ,CASE=str(c)),stdout=subprocess.PIPE,stderr=subprocess.PIPE,text=True)
lock=c/'root/var/lib/scripts-underground/maintenance-locks/cron-update-lxcs.lock'
def lock_metadata(p):
 s=p.lstat();return (s.st_dev,s.st_ino,s.st_uid,stat.S_IMODE(s.st_mode),s.st_nlink,s.st_size)
original=None
try:
 for phase in ('exec-1','exec-2','shutdown'):
  end=time.monotonic()+12
  while not (c/('barrier-'+phase)).exists() and holder.poll() is None and time.monotonic()<end:time.sleep(.02)
  check(phase+' holder reaches bounded actual PVE boundary',True,(c/('barrier-'+phase)).exists())
  if not (c/('barrier-'+phase)).exists():break
  proof=json.loads(read(c/('barrier-'+phase)))
  check(phase+' productive PVE child inherits real flock FD',True,any('FLOCK' in v['info'] and 'WRITE' in v['info'] for v in proof['fds']))
  if lock.exists():
   current=lock_metadata(lock);original=original or current
   check(phase+' stable empty private inode',original,current);check(phase+' root600 one-link empty',(0,0o600,1,0),current[2:])
   with lock.open('ab') as fd:
    try:fcntl.flock(fd,fcntl.LOCK_EX|fcntl.LOCK_NB);busy=False
    except BlockingIOError:busy=True
   check(phase+' independent native flock observes active owner',True,busy)
  else:check(phase+' native stable inode exists',True,False)
  before=len(calls(c));contender=invoke(c,['/usr/local/bin/update-lxcs.sh'],actor='contender')
  check(phase+' valid concurrent worker returns75',75,contender.returncode)
  check(phase+' valid contender has no PVE/package effects',[],[v for v in calls(c)[before:] if v[0] in ('pct','apt','apt-get','apk','pacman','dnf','zypper')])
  # Malformed input must not displace the busy result. Manual Run uses the same
  # installed executable, including its native owner and offline definitions.
  write(c/'root/etc/update-lxcs.conf','EXCLUDE=bad\n');before=len(calls(c))
  contender=invoke(c,manager if phase=='exec-2' else ['/usr/local/bin/update-lxcs.sh'],menu='Run' if phase=='exec-2' else None,actor='contender')
  check(phase+' concurrent installed worker returns75',75,contender.returncode)
  check(phase+' contender no PVE/package/lifecycle effects',[],[v for v in calls(c)[before:] if v[0] in ('pct','apt','apt-get','apk','pacman','dnf','zypper')])
  write(c/'root/etc/update-lxcs.conf','EXCLUDE=\n');write(c/('release-'+phase),'release')
finally:
 for phase in ('exec-1','exec-2','shutdown'):write(c/('release-'+phase),'release')
 try:out,err=holder.communicate(timeout=20)
 except subprocess.TimeoutExpired:
  holder.kill();out,err=holder.communicate(timeout=5);check('bounded holder completes without forced cleanup',True,False)
 write(c/'holder.json',json.dumps(dict(status=holder.returncode,stdout=out,stderr=err)))
check('first owner completes successfully',0,holder.returncode)
check('first owner actual upgrade outcome',True,(c/'updated-100').exists())
check('first owner graceful restored outcome','stopped',json.loads(read(c/'targets.json'))['100']['state'])
if lock.exists():check('inode retained after holder exit',original,lock_metadata(lock))
if any(not x['passed'] for x in checks[begin:]):
 write(W/'checks.json',json.dumps(checks,indent=2,default=lambda v:dict(bytes_sha256=hashlib.sha256(v).hexdigest())));print('RED concurrent cold worker has no native owner before effects',flush=True);sys.exit(1)
targets=json.loads(read(c/'targets.json'));targets['100']['barriers']=False;write(c/'targets.json',json.dumps(targets))
r=invoke(c,['/usr/local/bin/update-lxcs.sh']);check('later ordinary worker succeeds after release',0,r.returncode);check('ordinary retry preserves lock inode',original,lock_metadata(lock))
# The public emitter owns its exact closure and emits no source-time state/traps.
c=case('emission-contract')
r=invoke(c,['/bin/bash','-c','source /source/misc/core.func; trap -p > /data/trap-before; _APP_MAINTENANCE_FD=876543210987 _APP_MAINTENANCE_KEY=not-baked; app_maintenance_contents > /data/emitted || exit $?; declare -f _app_maintenance_refuse _app_maintenance_import_guard _app_maintenance_lock app_maintenance_acquire > /data/expected; trap -p > /data/trap-after'])
check('actual public emitter succeeds',0,r.returncode);check('public emitter exact four-definition closure',read(c/'expected'),read(c/'emitted'));check('emission leaves source traps unchanged',read(c/'trap-before'),read(c/'trap-after'));check('emission does not serialize held values',False,'876543210987' in read(c/'emitted') or 'not-baked' in read(c/'emitted'))
r=invoke(c,['/bin/bash','-c','source /data/emitted; trap -p; declare -p _APP_MAINTENANCE_FD _APP_MAINTENANCE_KEY 2>/dev/null; exit 0'])
check('cold emitted definitions have no traps or owner globals','',r.stdout);check('emitting/sourcing definitions has no lock effects',False,(c/'root/var/lib/scripts-underground/maintenance-locks').exists())
r=invoke(c,['/bin/bash','-c','source /source/misc/core.func; app_maintenance_contents > /dev/full || exit $?'])
check('actual emission write failure retains producer status',1,r.returncode)
# Deliberately broken real definition closure must stop Add and Update before
# publication, even though the outer producer is in a conditional return path.
for menu in ('Add','Update'):
 c=case('emission-'+menu);worker=c/'bin/update-lxcs.sh';write(worker,'#!/bin/bash\nexit 7\n',0o755)
 old=worker.read_bytes();cron=read(c/'crontab');conf=read(c/'root/etc/update-lxcs.conf')
 r=invoke(c,manager,'y\ny\n',menu=menu,fault='dependency')
 check(menu+' missing actual core definition emission fails',1,r.returncode)
 check(menu+' emission preserves previous executable',old,worker.read_bytes());check(menu+' emission preserves config',conf,read(c/'root/etc/update-lxcs.conf'));check(menu+' emission preserves crontab',cron,read(c/'crontab'))
 check(menu+' emission failure removes only owned stage',[],sorted(p.name for p in (c/'bin').glob('.update-lxcs.*')))
for name in ('missing-flock','open-failure','unsafe-mode','unsafe-size','unsafe-links','unsafe-path','unsafe-root','import-forgery'):
 c=case(name,{'100':dict(os='debian',state='stopped')});write(c/'bin/update-lxcs.sh',payload.decode(),0o755);write(c/'root/etc/update-lxcs.conf','EXCLUDE=bad\n')
 root=c/'root/var/lib/scripts-underground/maintenance-locks';root.mkdir(parents=True,mode=0o700);lock=root/'cron-update-lxcs.lock';write(lock,'',0o600);before=lock_metadata(lock)
 argv=['/usr/local/bin/update-lxcs.sh'];held=None
 if name=='missing-flock':
  minimal=c/'bin/no-flock';minimal.mkdir()
  for tool in ('bash','stat','mkdir'):(minimal/tool).symlink_to('/usr/bin/'+tool)
  argv=['/usr/bin/env','PATH=/usr/local/bin/no-flock',*argv]
 elif name=='open-failure':write(c/'read-only-lock','')
 elif name=='unsafe-mode':lock.chmod(0o644)
 elif name=='unsafe-size':lock.write_text('operator bytes')
 elif name=='unsafe-links':os.link(lock,root/'alias')
 elif name=='unsafe-path':lock.unlink();lock.symlink_to('/etc/unrelated')
 elif name=='unsafe-root':root.chmod(0o755)
 elif name=='import-forgery':
  held=lock.open('ab');fcntl.flock(held,fcntl.LOCK_EX|fcntl.LOCK_NB)
  # The exec boundary preserves a real parent-held FD but must discard exported
  # private protocol fields. It cannot borrow a forged environment owner.
  argv=['/usr/bin/env','_APP_MAINTENANCE_FD='+str(held.fileno()),'_APP_MAINTENANCE_KEY=cron-update-lxcs','/usr/local/bin/update-lxcs.sh']
 before=lock_metadata(lock);root_before=lock_metadata(root);contents=os.readlink(lock) if lock.is_symlink() else lock.read_bytes()
 try:r=invoke(c,argv,pass_fds=(held.fileno(),) if held else ())
 finally:
  if held:held.close()
 check(name+' native refusal status',75 if name=='import-forgery' else 69,r.returncode)
 check(name+' no PVE/package effect before refusal',[],[v for v in calls(c) if v[0] in ('pct','apt','apt-get','apk','pacman','dnf','zypper')])
 check(name+' existing inode metadata not repaired/replaced',before,lock_metadata(lock));check(name+' existing root not repaired',root_before,lock_metadata(root));check(name+' original bytes/link preserved',contents,os.readlink(lock) if lock.is_symlink() else lock.read_bytes())
 # A denied open must actually reach the append-open operation, not an earlier
 # metadata or command-availability refusal.
 if name=='open-failure':check('read-only bind reaches actual open refusal',True,'cannot open ' in r.stderr and 'Read-only file system' in r.stderr)
 if name=='missing-flock':check('closed PATH has no flock executable',False,(minimal/'flock').exists())
write(W/'checks.json',json.dumps(checks,indent=2,default=lambda v:dict(bytes_sha256=hashlib.sha256(v).hexdigest())));failed=sum(not x['passed'] for x in checks);print(f'{len(checks)} checks, {failed} failure(s)',flush=True);sys.exit(bool(failed))
PY
