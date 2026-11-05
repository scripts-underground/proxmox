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
import hashlib,json,os,pathlib,shlex,subprocess,sys,tempfile,time
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
 if a[-1].endswith('/misc/bootstrap/pve'):print(':');sys.exit(0)
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
 kind=targets.get(os.environ.get('CTID',''),{}).get('timeout_kind','gnu')
 if kind=='missing':sys.exit(127)
 if kind=='busybox':print('BusyBox timeout');sys.exit(0)
 os.execv('/usr/bin/timeout',['timeout',*a])
if name in ('apt','apt-get','apk','pacman','dnf','zypper'):
 t=targets[os.environ['CTID']];rc=t.get('package_rc',0)
 id=os.environ['CTID'];metadata=any(v in a for v in ('update','-Sy','makecache','refresh'));upgrade=any(v in a for v in ('dist-upgrade','upgrade','-Syu','-Su','dup'))
 if metadata:
  t['metadata_count']=t.get('metadata_count',0)+1;db.write_text(json.dumps(targets))
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
action=a[0]
if action=='list':
 print('VMID Status Lock Name')
 for id,t in targets.items():print(id,t['state'],'-', 'fixture')
 sys.exit(0)
id=a[1];t=targets[id]
if action=='config':
 if t.get('config_rc'):sys.exit(t['config_rc'])
 print('ostype: '+t['os']);print('template: '+str(t.get('template',0)));sys.exit(0)
if action=='status':
 if t.get('status_rc'):sys.exit(t['status_rc'])
 print('status: '+t['state']);sys.exit(0)
if action in ('start','shutdown'):
 rc=t.get(action+'_rc',0)
 if not rc and not t.get(action+'_unchanged'):t['state']='running' if action=='start' else 'stopped';db.write_text(json.dumps(targets))
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
def invoke(c,argv,stdin='',menu=None,fault=''):
 if menu:write(c/'menu',menu)
 write(c/'fault',fault)
 n=len(list(c.glob('result-*.json')))
 r=subprocess.run(['unshare','--mount','--propagation','private','/bin/bash','-c',launch,'_',str(c),str(R),*argv],input=stdin,env=dict(os.environ,CASE=str(c)),capture_output=True,text=True,timeout=135)
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
def events(c,id):return [json.loads(v) for v in read(c/'events').splitlines() if json.loads(v)['id']==id]
def upgrades(c,id):return [v for v in events(c,id) if v['phase']=='upgrade']
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
 ('readiness-timeout',dict(metadata_hang='term'),124),
 ('readiness-kill-group',dict(metadata_hang='kill',hang_attempts=1,metadata_failures=99),28)]:
 t=dict(os='debian',state='stopped',require_ready=True,**t);start=time.monotonic();c,r=worker_case(name,{'100':t,'101':dict(os='alpine',state='running')},expected=expected);elapsed=time.monotonic()-start
 check(name+' no upgrade on failed readiness',0,len(upgrades(c,'100')) if (c/'events').exists() else 0)
 check(name+' no premature upgrade',False,(c/'premature-upgrade').exists());check(name+' later target still updates',True,(c/'updated-101').exists())
 check(name+' restoration only checked started target',['100'],[v[1][1] for v in effects(c) if v[1][0]=='shutdown'])
 check(name+' final state retained','running' if t.get('shutdown_rc') else 'stopped',json.loads(read(c/'targets.json'))['100']['state'])
 check(name+' finite attempts',0 if name.startswith('timeout-') else 3,json.loads(read(c/'targets.json'))['100'].get('metadata_count',0))
 check(name+' finite total wall time',True,elapsed<110)
 children=[int(p.read_text()) for p in c.glob('child-*')]
 for pid in children:
  p=pathlib.Path('/proc')/str(pid)/'stat';check(name+' timed metadata descendant no longer running',True,not p.exists() or p.read_text().split(') ',1)[1].split()[0]=='Z')
 if name in ('readiness-timeout','readiness-kill-group'):
  results=[json.loads(v) for v in read(c/'exec-results').splitlines() if json.loads(v)['id']=='100'];timeouts=[v for v in results if v['status'] in (124,137)]
  check(name+' real native timeout observed',3 if name=='readiness-timeout' else 1,len(timeouts))
  check(name+' TERM/KILL bound is real',True,all((18<=v['seconds']<30) for v in timeouts))
  if name=='readiness-kill-group':check('KILL deadline status survives inner shell',137,timeouts[0]['status'] if timeouts else None)
c,r=worker_case('running-no-boot-wait',{'100':dict(os='debian',state='running',metadata_failures=1,timeout_kind='missing')},expected=28)
check('already running has no new timeout/readiness path',[],[v for v in calls(c) if v[0]=='timeout']);check('already running retains one normal metadata attempt',1,json.loads(read(c/'targets.json'))['100']['metadata_count'])
write(W/'checks.json',json.dumps(checks,indent=2,default=lambda v:dict(bytes_sha256=hashlib.sha256(v).hexdigest())));failed=sum(not x['passed'] for x in checks);print(f'{len(checks)} checks, {failed} failure(s)',flush=True);sys.exit(bool(failed))
PY
