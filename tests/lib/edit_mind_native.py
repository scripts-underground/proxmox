"""Finite Edit-Mind consumer over existing typed ownership; never an inference test."""
import hashlib
import json
import os
from pathlib import Path
import subprocess
import sys
from contextlib import ExitStack

from entrypoint import admit_direct
from test_context import Run, require
from test_inputs import bindings
from test_pve import NativePVE, Publisher
from edit_mind_native_guard import Guard, TrialStopped


P = '/var/lib/edit-mind-native-proof'
COMMIT = '39ac8460e21f5140b88abc7a6f116c71d9011f7f'
CREATOR_PACKAGES = ('sudo', 'curl', 'mc', 'gnupg2', 'jq')
PROBE_PACKAGES = ('bash', 'ca-certificates', 'python3', 'git', 'xz-utils', 'unzip', 'iproute2')
BOOTSTRAP = ('export LC_ALL=C.UTF-8 LANG=C.UTF-8 DEBIAN_FRONTEND=noninteractive; '
             'apt update; apt install -y '+ ' '.join(CREATOR_PACKAGES+PROBE_PACKAGES)+
             '; for tool in sudo curl mc gpg jq bash python3 git xz unzip ip; do command -v "$tool" || exit 69; done; '
             'gpg --version >/dev/null; curl --version >/dev/null; jq --version >/dev/null')


class NativeStageFailure(RuntimeError):
    def __init__(self, status, stage):
        self.status = status
        super().__init__('native stage failed: '+stage+' status='+str(status))

SQL_JS = r'''
const {createRequire}=require('node:module');
const req=createRequire('/opt/edit-mind/package.json');
const {PrismaClient}=req('@prisma/client');
if(req('@prisma/client/package.json').version!=='6.19.3')throw Error('Prisma version');
const db=new PrismaClient();
const id='su-edit-mind-native';
const media='/media/videos/su-proof-unwatched/film.mp4';
const thumb='/media/videos/su-proof-unwatched/thumb.jpg';
(async()=>{
 const user=await db.user.findUniqueOrThrow({where:{email:'su-edit-mind-native@example.invalid'}});
 if(process.argv[2]==='seed'){
  await db.folder.create({data:{id:id+'-folder',path:'/media/videos/su-proof-folder',userId:user.id,status:'indexed',watcherEnabled:false,includePatterns:[],excludePatterns:[],videoCount:0}});
  await db.job.create({data:{id:id+'-job',userId:user.id,folderId:id+'-folder',videoPath:media,thumbnailPath:thumb,status:'done',stage:'starting',overallProgress:100,progress:100,fileSize:1n}});
  await db.video.create({data:{id:id+'-video',userId:user.id,folderId:id+'-folder',source:media,thumbnailUrl:thumb,name:'Owned synthetic media',shottedAt:new Date('2026-01-01'),duration:1n}});
  await db.chat.create({data:{id:id+'-chat',userId:user.id,title:'Owned synthetic chat'}});
  await db.export.create({data:{id:id+'-export',userId:user.id,status:'ready',filePath:media,progress:100}});
  await db.chatMessage.create({data:{id:id+'-message',chatId:id+'-chat',sender:'assistant',stitchedVideoPath:media,exportId:id+'-export',text:'Owned synthetic state'}});
 }
 const result={folder:await db.folder.findUniqueOrThrow({where:{id:id+'-folder'}}),job:await db.job.findUniqueOrThrow({where:{id:id+'-job'}}),video:await db.video.findUniqueOrThrow({where:{id:id+'-video'}}),message:await db.chatMessage.findUniqueOrThrow({where:{id:id+'-message'}}),export:await db.export.findUniqueOrThrow({where:{id:id+'-export'}})};
 const version=await db.$queryRawUnsafe('SHOW server_version_num');
 if(Math.floor(Number(version[0].server_version_num)/10000)!==16)throw Error('PostgreSQL major');
 console.log(JSON.stringify({rows:result,pg_major:16,prisma:'6.19.3'},(_,v)=>typeof v==='bigint'?v.toString():v));
})().catch(e=>{console.error(e.message);process.exitCode=1}).finally(()=>db.$disconnect());
'''

REMOTE = r'''
import hashlib,http.cookiejar,json,os,pathlib,re,secrets,subprocess,sys,time,urllib.parse,urllib.request
P=pathlib.Path('/var/lib/edit-mind-native-proof');A=pathlib.Path('/opt/edit-mind')
UNITS=['edit-mind-chroma','edit-mind-ml','edit-mind-jobs','edit-mind-web']
MEDIA=pathlib.Path('/media/videos/su-proof-unwatched');FOLDER=pathlib.Path('/media/videos/su-proof-folder')
def q(*args,seconds=30,env=None):
 r=subprocess.run(args,capture_output=True,text=True,timeout=seconds,env=env)
 if r.returncode:raise RuntimeError('native command failed: '+args[0])
 return r.stdout.strip()
def fact(p):
 s=p.stat();return dict(sha256=hashlib.sha256(p.read_bytes()).hexdigest(),inode=s.st_ino,mode=s.st_mode,uid=s.st_uid,gid=s.st_gid,bytes=s.st_size)
def environment():
 pid=q('systemctl','show','edit-mind-web','-p','MainPID','--value')
 env=dict(p.decode().split('=',1) for p in pathlib.Path('/proc',pid,'environ').read_bytes().split(b'\0') if b'=' in p)
 assert env['NODE_ENV']=='production' and env['TMPDIR']=='/var/lib/scripts-underground-test/tmp'
 return env
def provenance():
 expected=json.loads((P/'reference.json').read_text())
 for row in expected['files']:
  p=A/row['path'];assert p.is_file() and hashlib.sha256(p.read_bytes()).hexdigest()==row['sha256'],row['path']
 return dict(source_files=len(expected['files']),commit='39ac8460e21f5140b88abc7a6f116c71d9011f7f')
REQUIRED_LISTENERS={3745,4000,8765,8000,5432,6379}
EAGER={'edit-mind-jobs':['Text model ready','Visual model ready','Audio model ready','All embedding models loaded'],
       'edit-mind-ml':['Loaded 6 plugins','BLIP model loaded successfully','Model download complete','Server listening on']}
def tcp_listeners(text):
 ports=set()
 for line in text.splitlines():
  fields=line.split()
  if len(fields)<5 or fields[0]!='LISTEN':continue
  local=fields[3]
  if ':' not in local:continue
  port=local.rsplit(':',1)[1]
  if port.isdigit() and 0<int(port)<=65535:ports.add(int(port))
 return ports
def unit_snapshot(ask):
 result={}
 for unit in UNITS:
  values=dict(line.split('=',1) for line in ask('systemctl','show',unit,'-p','InvocationID','-p','ActiveState','-p','NRestarts').splitlines() if '=' in line)
  invocation=values.get('InvocationID','');active=values.get('ActiveState','unknown');restarts=values.get('NRestarts','')
  result[unit]=dict(invocation=invocation if re.fullmatch('[a-f0-9]{32}',invocation) else '',
                    active=active if active in {'active','inactive','activating','deactivating','failed','reloading','maintenance'} else 'unknown',
                    restarts=int(restarts) if restarts.isdigit() else None)
 return result
def journal(unit,phase,ask,invocation=None):
 args=['journalctl','--no-pager','-o','cat','-b','-u',unit]
 if invocation:args.append('_SYSTEMD_INVOCATION_ID='+invocation)
 log=ask(*args)
 (P/('readiness-'+phase+'-'+unit+('.current.journal' if invocation else '.boot.journal'))).write_text(log)
 return log
def save_readiness(facts):
 raw=json.dumps(facts,sort_keys=True);assert len(raw)<=8192
 (P/('readiness-'+facts['phase']+'.json')).write_text(raw)
def readiness_error(facts,status):
 facts['check_status']=status;save_readiness(facts)
 missing=[unit+':'+marker for unit,values in facts['eager_markers'].items() for marker,ok in values.items() if not ok]
 return RuntimeError('readiness '+status+' phase='+facts['phase']+' missing_ports='+str(facts['missing_listeners'])+
                     ' missing_markers='+str(missing)+' states='+json.dumps(facts['states'],sort_keys=True))
def ready(phase='startup'):
 assert phase in {'startup','before','after'}
 started=time.monotonic();end=started+900
 facts=dict(phase=phase,elapsed=0,check_status='waiting',states={},snapshot_states={},stable_invocations=False,
            eager_markers={unit:{marker:False for marker in markers} for unit,markers in EAGER.items()},
            present_listeners=[],missing_listeners=sorted(REQUIRED_LISTENERS))
 def ask(*args):
  remaining=end-time.monotonic()
  if remaining<=0:raise TimeoutError('readiness deadline')
  return q(*args,seconds=min(20,remaining))
 while time.monotonic()<end:
  try:
   before=unit_snapshot(ask)
   boot={unit:journal(unit,phase,ask) for unit in UNITS}
   current={unit:journal(unit,phase,ask,before[unit]['invocation']) if before[unit]['invocation'] else '' for unit in UNITS}
   ports=tcp_listeners(ask('ss','-H','-lnt'));after=unit_snapshot(ask)
  except (OSError,ValueError,RuntimeError,subprocess.SubprocessError) as error:
   facts['elapsed']=round(time.monotonic()-started,3);facts['observation_error']=type(error).__name__
   raise readiness_error(facts,'deadline' if time.monotonic()>=end else 'observation-error') from None
  facts.update(elapsed=round(time.monotonic()-started,3),states=after,snapshot_states=before,
               stable_invocations=all(before[u]['invocation'] and before[u]['invocation']==after[u]['invocation'] for u in UNITS),
               eager_markers={u:{marker:marker in current[u] for marker in markers} for u,markers in EAGER.items()},
               present_listeners=sorted(ports&REQUIRED_LISTENERS),missing_listeners=sorted(REQUIRED_LISTENERS-ports))
  for unit in EAGER:
   if before[unit]['invocation']!=after[unit]['invocation']:
    facts['eager_markers'][unit]={marker:False for marker in EAGER[unit]}
  combined='\n'.join([*boot.values(),*current.values()])
  if re.search(r'Failed to (?:load|initialize)|Model load failed|Model download failed|Failed to setup cache|Error embedding|Traceback',combined,re.I):
   raise readiness_error(facts,'init-error')
  if any(v['restarts'] not in (None,0) for v in [*before.values(),*after.values()]) or re.search(r'Scheduled restart job|restart counter is at',combined,re.I):
   raise readiness_error(facts,'automatic-restart')
  if any(v['active']=='failed' for v in after.values()):raise readiness_error(facts,'failed-unit')
  if not facts['stable_invocations']:facts['check_status']='invocation-changed'
  elif all(v['active']=='active' and v['restarts']==0 for v in [*before.values(),*after.values()]) and all(ok for values in facts['eager_markers'].values() for ok in values.values()) and not facts['missing_listeners']:
   if time.monotonic()>=end:raise readiness_error(facts,'deadline')
   facts['check_status']='ready';save_readiness(facts)
   return dict(eager_control_flow=True,lazy_face_weights='deferred',loaded_whisper='deferred',
               invocations={u:v['invocation'] for u,v in after.items()},listeners=facts['present_listeners'])
  else:facts['check_status']='waiting'
  save_readiness(facts)
  time.sleep(min(1,max(0,end-time.monotonic())))
 facts['elapsed']=round(time.monotonic()-started,3)
 raise readiness_error(facts,'deadline')
def require_listeners(phase):
 facts=json.loads((P/('readiness-'+phase+'.json')).read_text())
 ports=tcp_listeners(q('ss','-H','-lnt'))
 facts.update(present_listeners=sorted(ports&REQUIRED_LISTENERS),missing_listeners=sorted(REQUIRED_LISTENERS-ports))
 if facts['missing_listeners']:raise readiness_error(facts,'post-consumers-listeners-missing')
 facts['check_status']='consumers-listeners-ready';save_readiness(facts)
def login(register=False):
 credential=P/'credential.json'
 if register:
  assert not credential.exists();credential.write_text(json.dumps(dict(email='su-edit-mind-native@example.invalid',password=secrets.token_urlsafe(32))));credential.chmod(0o600)
 values=json.loads(credential.read_text());jar=http.cookiejar.CookieJar();opener=urllib.request.build_opener(urllib.request.HTTPCookieProcessor(jar))
 if register:values.update(name='Owned synthetic user',confirmationPassword=values['password'])
 with opener.open('http://127.0.0.1:3745/auth/'+('register' if register else 'login'),urllib.parse.urlencode(values).encode(),timeout=20) as r:r.read()
 assert any(c.name=='__session' for c in jar),'actual login did not issue production session'
 return opener
def sql(action):
 return json.loads(q('/usr/bin/node',str(P/'sql.cjs'),action,env=environment()))
def vector(seed=False):
 import chromadb
 client=chromadb.HttpClient(host='127.0.0.1',port=8000);result={}
 for name,dim in [('video_content',768),('video_content_visual',512),('video_content_audio',512)]:
  collection=client.get_or_create_collection(name=name,embedding_function=None)
  metadata=dict(source=str(MEDIA/'film.mp4'),thumbnailUrl=str(MEDIA/'thumb.jpg'),startTime=0,endTime=1,faces='',objects='',emotions='[]',description='Owned synthetic scene',shotType='wide',duration=1,createdAt=1767225600000,aspectRatio='16:9')
  v=[1.0]+[0.0]*(dim-1)
  if seed:collection.add(ids=['su-edit-mind-scene'],embeddings=[v],metadatas=[metadata],documents=['Owned synthetic scene'])
  row=collection.get(ids=['su-edit-mind-scene'],include=['embeddings','metadatas','documents'])
  assert row['ids']==['su-edit-mind-scene'] and row['metadatas']==[metadata] and row['documents']==['Owned synthetic scene']
  assert row['embeddings'].tolist()==[v]
  result[name]=dict(ids=row['ids'],vector=v,metadata=metadata,document=row['documents'])
 return result
def seed():
 assert not MEDIA.exists() and not FOLDER.exists()
 MEDIA.mkdir();FOLDER.mkdir();(FOLDER/'owned-sentinel.txt').write_text('nonmedia owned sentinel')
 q('ffmpeg','-v','error','-f','lavfi','-i','color=c=black:s=16x16:r=1','-frames:v','1','-c:v','mpeg4',str(MEDIA/'film.mp4'))
 q('ffmpeg','-v','error','-i',str(MEDIA/'film.mp4'),'-frames:v','1',str(MEDIA/'thumb.jpg'))
 login(True);sql('seed');vector(True)
def assets():
 roots=[A/'ml-models',pathlib.Path('/root/.EasyOCR'),pathlib.Path('/ml-models/embedding-models')]
 rows=[]
 for root in roots:
  if root.exists():
   for p in sorted(root.rglob('*')):
    if p.is_file() and not p.name.endswith(('.lock','.metadata','.incomplete')):rows.append(dict(path=str(p),target=str(p.resolve()),bytes=p.stat().st_size,sha256=hashlib.sha256(p.read_bytes()).hexdigest()))
 assert any(p['path'].endswith('yolov8s.pt') for p in rows)
 assert any('blip-image-captioning-base' in p['path'] and p['path'].endswith(('pytorch_model.bin','model.safetensors')) for p in rows)
 assert any(p['path'].endswith('model.bin') and 'whisper' in p['path'] for p in rows)
 assert any('EasyOCR' in p['path'] and p['path'].endswith('.pth') for p in rows)
 # HF snapshots/ref paths and Xenova cache paths are artifact provenance, not a
 # packet capture. Preserve official selected-file URL metadata inside this CT.
 official=json.loads((P/'official-models.json').read_text());selected=[]
 for model in official['models']:
  matches=[]
  for file in model['files']:
   digest=(file.get('lfs') or {}).get('sha256')
   for row in rows:
    if digest and row['sha256']==digest:
     matches.append(dict(repo=model['repo'],revision=model['revision'],provenance_url='https://huggingface.co/'+model['repo']+'/resolve/'+model['revision']+'/'+file['path'],**row))
  assert matches,'startup model bytes do not match closed official metadata: '+model['repo']
  selected.extend(matches)
 (P/'selected-artifacts.json').write_text(json.dumps(dict(files=rows,official_selected=selected,urls_are_content_provenance_not_wire_trace=True),sort_keys=True))
 return rows
def observe(label):
 readiness=ready(label);provenance();opener=login();db=sql('read');vectors=vector()
 assert db['rows']['folder']['path']==str(FOLDER) and db['rows']['folder']['videoCount']==0
 assert not any(p.suffix.lower() in {'.mp4','.mkv','.mov','.avi','.webm','.jpg'} for p in FOLDER.rglob('*'))
 paths=[MEDIA/'film.mp4',MEDIA/'thumb.jpg',FOLDER/'owned-sentinel.txt',A/'.env',A/'.env.system',A/'apps/web/.env.production']
 state=dict(files={str(p):fact(p) for p in paths},units={u:fact(pathlib.Path('/etc/systemd/system',u+'.service')) for u in UNITS},sql=db,vectors=vectors)
 for path in (MEDIA/'film.mp4',MEDIA/'thumb.jpg'):
  url='http://127.0.0.1:3745/media/file?'+urllib.parse.urlencode(dict(source=str(path)))
  with opener.open(url,timeout=20) as r:assert r.status==200 and r.read()==path.read_bytes()
 for endpoint,field,key in [('api/folders/su-edit-mind-native-folder','folder','id'),('api/videos/su-edit-mind-native-video','video','id')]:
  with opener.open('http://127.0.0.1:3745/'+endpoint,timeout=20) as r:d=json.load(r)
  assert d[field][key]=='su-edit-mind-native-'+field
  if field=='video':assert d['processedJob']['overallProgress']==100 and d['processedJob']['progress']==100 and d['processedJob']['status']=='done' and d['scenes'][0]['id']=='su-edit-mind-scene' and not d['isProcessing']
 require_listeners(label)
 if label=='before':
  (P/'baseline.json').write_text(json.dumps(state,sort_keys=True));(P/'assets-before.json').write_text(json.dumps(assets(),sort_keys=True))
 else:
  assert state==json.loads((P/'baseline.json').read_text())
  assert not pathlib.Path('/var/lib/scripts-underground/update-pending/edit-mind').exists()
  before=json.loads((P/'assets-before.json').read_text());current={r['path']:r for r in assets()}
  assert all(current.get(row['path'])==row for row in before)
 print(json.dumps(dict(label=label,actual_authenticated_media=True,actual_prisma=True,pg_major=16,sql_path_columns=7,actual_chroma=True,app_folder_video_scene_progress=True,files_units_keys_retained=True,readiness=readiness),sort_keys=True))
action=sys.argv[1]
if action=='provenance':print(json.dumps(provenance(),sort_keys=True))
elif action=='ready':print(json.dumps(ready(),sort_keys=True))
elif action=='seed':seed()
elif action in ('before','after'):observe(action)
else:raise RuntimeError('unknown finite native probe action')
'''


def main():
    context = admit_direct('maintenance-edit-mind-native', [])
    _, inputs = bindings(context)
    root = Path(context.document['source']['path'])
    reference = Path(inputs['EDIT_MIND_REFERENCE'])
    models = json.loads(Path(inputs['EDIT_MIND_MODELS']).read_bytes())
    require(models.get('weight_downloads') == 0 and len(models['models']) == 5, 'closed official model metadata')
    n = context.operation['native']
    require((n['cpu'], n['ram'], n['disk']) == (4,8192,32), 'default native allocation required')
    require(n['budgets']['memory_peak'] >= 9*1024**3 and n['budgets']['workspace_peak'] >= int(3.25*1024**3)
            and n['budgets']['root_free'] >= 4*1024**3, 'unchanged independent native floors')
    require(context.operation['deadline'] == 3600, 'one-hour operation required')
    with Run(context) as run, ExitStack() as lifecycle:
        native = NativePVE(run)
        guard = Guard(native)
        native.call = guard.call
        lifecycle.enter_context(guard)
        status = 70
        ctid = str(native.owner.spec.ctid)
        def invoke(*args):
            guard.check()
            result = native.dispatch('pct', list(args))
            if result.returncode:
                raise NativeStageFailure(result.returncode,args[0])
            return result.stdout
        def execute(*args):return invoke('exec',ctid,'--',*args)
        def push(raw,name):
            path=run.directory/name;path.write_bytes(raw)
            invoke('push',ctid,str(path),P+'/'+name)
            require(execute('sha256sum',P+'/'+name).split()[0]==hashlib.sha256(raw).hexdigest(),'probe transport changed')
        try:
            with Publisher(run) as url:
                s=native.owner.spec
                invoke('create',ctid,n['template_storage']+':vztmpl/'+n['template'],
                       '-hostname',s.hostname,'-tags','community-script,'+s.tag,
                       '-features','nesting=1,keyctl=1','-net0',f'name=eth0,bridge={n["bridge"]},ip=dhcp,hwaddr={s.mac}',
                       '-onboot','1','-cores','4','-memory','8192','-unprivileged','1','-rootfs',n['storage']+':32')
                invoke('start',ctid)
                execute('/bin/sh','-ec',BOOTSTRAP)
                execute('mkdir','-m','0700',P)
                push(REMOTE.encode(),'probe.py');push(SQL_JS.encode(),'sql.cjs')
                from test_context import source_files
                push(json.dumps(dict(files=source_files(reference)),sort_keys=True).encode(),'reference.json')
                push(Path(inputs['EDIT_MIND_MODELS']).read_bytes(),'official-models.json')
                # Actual bundle writer and unchanged hooks; only test release selection
                # and post-fetch provenance adapter are added to the emitted bundle.
                generate=r'''set -euo pipefail
source <(sed '/^# framework bootstrap/,$d' "$1/scripts/lxc/edit-mind.sh")
source "$1/misc/bundle.func"
APP=Edit-Mind NSAPP=edit-mind REPO_BASE="$2"
var_lxc_tmpdir=/var/lib/scripts-underground-test/tmp
_write_bundle install install_script "$1/misc" 'export APPLICATION="$APP"; var_appversion=0.40.1' setting_up_container network_check update_os install_script motd_ssh setup_lxc cleanup_lxc > "$3/install.sh"
_write_bundle update update_script "$1/misc" --script-id edit-mind -- --requirements 4 8192 -- 'export APPLICATION="$APP"; var_appversion=0.40.1; run_update_script "$@"' > "$3/update.sh"
'''
                subprocess.run(['/bin/bash','-c',generate,'--',str(root),url,str(run.directory)],check=True,timeout=30)
                for name in ('install.sh','update.sh'):
                    body=(run.directory/name).read_text()
                    require(body.count('fetch_and_deploy_gh_release() {')==1,'normal fetch helper shape changed')
                    body=body.replace('fetch_and_deploy_gh_release() {','edit_mind_original_fetch() {',1)
                    wrapper='fetch_and_deploy_gh_release() { edit_mind_original_fetch "$@" || return; /usr/bin/python3 '+P+'/probe.py provenance; }; '
                    marker='var_appversion=0.40.1'
                    require(body.count(marker)==1,'test pin prefix changed')
                    body=body.replace(marker,wrapper+marker,1)
                    push(body.encode(),'native-'+name)
                execute('/bin/bash',P+'/native-install.sh')
                execute('install','-m','0755',P+'/native-update.sh','/usr/local/sbin/update')
                execute('ln','-s','/usr/local/sbin/update','/usr/bin/update')
                for action in ('ready','seed','before'):
                    output=execute('/opt/edit-mind/.venv/bin/python','-B',P+'/probe.py',action)
                    run.record('edit-mind-'+action,dict(output=output))
                execute('/bin/bash','/usr/local/sbin/update','--clean')
                output=execute('/opt/edit-mind/.venv/bin/python','-B',P+'/probe.py','after')
                run.record('edit-mind-after',dict(output=output));guard.check();status=0
        except (Exception, KeyboardInterrupt) as error:
            status=getattr(error,'status',124 if guard.reason and 'deadline' in guard.reason else 125 if guard.reason else 70)
            run.record('edit-mind-failure',dict(status=status,error=type(error).__name__+': '+str(error),stage=guard.stage,guard=guard.reason,rx_max=guard.maximum))
            if guard.reason and native.owner.current is not None:
                try:guard.contain()
                except Exception as containment:run.record('edit-mind-containment-failure',dict(error=type(containment).__name__))
        # The real owner stops once while monitoring remains active; ExitStack
        # then joins/records the guard before Run releases its custody lock.
        return guard.finish(status)


if __name__ == '__main__':
    raise SystemExit(main())
