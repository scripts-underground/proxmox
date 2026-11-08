"""Bounded caller input audit, executed by the current-hardening consumer.

Cold bundle generation, provider selection, extraction, files and pending state
are real. HTTP/package/build/service operations use the existing recording models.
The original cases are copied, never modified; every new command is generated
from the current hook rather than patched after generation.
"""
import shutil

check('pre-input assertions retained',1391,len(checks))
input_apps=('endurain','invidious','keycloak','cronmaster','autocaliweb','romm','filebrowser','qui','wanderer')
for app in input_apps:
 for verbose in ('no','yes'):
  for scenario in ('pin-due','pin-current','checker')+(('search-checker','search-due') if app=='wanderer' else ()):
   c=W/('input-'+app+'-'+verbose+'-'+scenario)
   if app in input_apps[:6]:
    template=W/(app+'-'+verbose+'-selected-race')
    shutil.copytree(template,c,symlinks=True)
    # Rebase copied fixture inputs, not the generated command or production code.
    for p in c.rglob('*'):
     if p.is_file() and not p.is_symlink():
      b=p.read_bytes()
      if str(template).encode() in b:p.write_bytes(b.replace(str(template).encode(),str(c).encode()))
    for n in ('requests','downloads','service-calls','services','runtime','builds','companion-consumer'):
     (c/n).unlink(missing_ok=True)
    live=c/'opt'/app
    marker={'keycloak':'keycloak_app'}.get(app,app)
    service_names={'endurain':['endurain'],'invidious':['invidious','invidious-companion'],'keycloak':['keycloak'],'cronmaster':['fixture-cronmaster'],'autocaliweb':['autocaliweb','metadata-change-detector','acw-ingest-service','acw-auto-zipper'],'romm':services}[app]
    model=romm_models if app=='romm' else models
    transport=romm_http if app=='romm' else http
    transport=transport.replace("tag='v2.0' if main else", "tag='v3.0' if main else") if app=='romm' else transport.replace("tag='v2.0'", "tag='v3.0'",1)
    # The independent companion has its own release, never the main request.
    if app=='invidious':transport=transport.replace("if key=='companion':asset=", "if key=='companion':tag='v4.0';asset=")
    write(c/'http.py',transport)
    if app=='invidious':write(c/'home/.invidiouscompanion','4.0\n')
   else:
    for n in ('home','tmp','stage','sbin','bin','incoming','opt/wanderer/source/db','opt/wanderer/source/web','opt/wanderer/source/search','opt/wanderer/data/plugins'):(c/n).mkdir(parents=True,exist_ok=True)
    marker=app;live=c/'opt'/app;service_names=['wanderer-web' if app=='wanderer' else app]
    model=models+r'''
get_system_arch() { printf amd64; }
go() { :; }
apt() { printf 'modeled package search-v4\n' > "$CASE_ROOT/opt/wanderer/source/search/package-consumer"; }
'''
    if app in ('filebrowser','qui'):
     write(c/'bin'/app,'#!/usr/bin/env bash\nprintf old\n',0o711)
     write(c/'incoming'/app,'#!/usr/bin/env bash\nprintf selected-v2\n',0o755)
     model+=r'''
systemctl() {
 printf '%s\n' "$*" >> "$CASE_ROOT/service-calls"
 case "$1" in stop) printf stopped > "$CASE_ROOT/service-$TEST_APP" ;; start) "$CASE_ROOT/bin/$TEST_APP" > "$CASE_ROOT/executable-consumer"; printf running > "$CASE_ROOT/service-$TEST_APP" ;; esac
}
'''
    else:
     write(live/'start.sh','meilisearch --experimental-dumpless-upgrade\n')
     write(live/'source/search/old','search data\n',0o640)
     write(c/'incoming/db/selected-version','2.0\n');write(c/'incoming/web/source','selected web\n')
     # Valid, already-current independent plugins skip deployment after checking.
     for plugin in ('hammerhead','komoot','strava'):
      write(live/'data/plugins'/plugin/'plugin.json',json.dumps(dict(id=plugin,runtime=dict(type='wasm',entrypoint='plugin.wasm'))))
      write(live/'data/plugins'/plugin/'plugin.wasm','operator '+plugin+'\n',0o640)
      write(c/'home'/('.wanderer-plugin-'+plugin),'4.0\n')
     write(c/'home/.meilisearch','4.0\n')
     if scenario.startswith('search-'):write(c/'home/.meilisearch','1.0\n')
     model+=r'''
curl_download() {
 printf '%s\n' "$2" >> "$CASE_ROOT/downloads"
 if [[ "$2" == *meilisearch* ]]; then printf 'modeled search package\n' > "$1"; else command cp "$CASE_ROOT/release.tar.gz" "$1"; fi
}
'''
    pack(c/'incoming',c/'release.tar.gz')
    write(c/'http.py',r'''
import json,os,pathlib,sys
c=pathlib.Path(os.environ['CASE_ROOT']);app=sys.argv[1];args=sys.argv[2:];out=None;fmt=False;url=''
for i,a in enumerate(args):
 if a=='-o':out=args[i+1]
 if a=='-w':fmt=True
 if a.startswith('https://'):url=a
with (c/'requests').open('a') as f:f.write(json.dumps(dict(app=app,url=url))+'\n')
if os.environ['FAULT']=='checker' and app.lower().replace(' ','')==os.environ['TEST_APP']:raise SystemExit(17)
if os.environ['FAULT']=='search-checker' and app=='meilisearch':raise SystemExit(17)
tag='v4.0' if app.startswith('wanderer-plugin-') or app=='meilisearch' else 'v3.0'
if '/tags/' in url:tag=url.rsplit('/',1)[-1]
assets=[dict(name=n,browser_download_url='https://fixture.invalid/'+n) for n in ('linux-amd64-filebrowser.tar.gz','qui_2_linux_x86_64.tar.gz','meilisearch-amd64.deb')]
d=json.dumps(dict(tag_name=tag,draft=False,prerelease=False,assets=assets))
if out:pathlib.Path(out).write_text(d)
else:print(d,end='')
if fmt:print('200',end='')
''')
   if app in input_apps[:5] or app=='wanderer':model=model.replace('systemctl() {\n','systemctl() {\n  printf "%s\\n" "$*" >> "$CASE_ROOT/service-calls"\n',1)
   write(c/'models.sh',model)
   write(c/'home'/('.'+marker),'2.0\n' if scenario=='pin-current' or scenario.startswith('search-') else '1.0\n')
   for s in service_names:write(c/('service-'+s),'running')
   for n in ('pending','locks','maintenance-locks','state','backup','cron-backup','romm-players.backup'):
    p=c/n
    if p.exists():shutil.rmtree(p)
   # Original data and modes must survive; code and main marker are checked separately.
   protected_input={}
   if app in ('filebrowser','qui'):write(c/'operator.conf','original setting\n',0o600)
   candidates=[c/'operator.conf',live/'.env',live/'conf/keycloak.conf',live/'providers/x/p.jar',live/'themes/t/theme.properties',live/'config/config.yml',c/'config/operator.env',live/'dirs.json']
   if app=='romm':candidates += [c/'library/config/config.yml',c/'library/library/roms/original.rom',live/'frontend/dist/assets/ruffle/ruffle.js',live/'frontend/dist/assets/emulatorjs/data/loader.js']
   if app=='wanderer':candidates += list((live/'data/plugins').glob('*/*'))+[live/'source/search/old']
   for p in candidates:
    if p.is_file():protected_input[str(p)]=(p.read_bytes(),p.stat().st_mode&0o777)
   core=(R/'misc/core.func').read_text().replace('/var/lib/scripts-underground/update-pending',str(c/'pending')).replace('/var/lib/scripts-underground/maintenance-locks',str(c/'locks'))
   write(c/'stage/core.func',core)
   for n in ('tools.func','error_handler.func'):write(c/'stage'/n,(R/'misc'/n).read_text())
   write(c/'stage/install.func','pkg_install() { :; }\nsetup_lxc() { :; }\n')
   write(c/'stage/github.func','clone_and_deploy_gh_commit() { :; }\nsource '+shlex.quote(str(c/'models.sh'))+'\n')
   write(c/'stage/addon.func','source '+shlex.quote(str(c/'models.sh'))+'\n')
   kind='addon' if app in ('cronmaster','filebrowser') else 'lxc'
   text=(R/'scripts'/kind/(app+'.sh')).read_text();start=text.index('function update_script() {');end=text.index('\n}\n',start)+3
   hook=text[start:end].replace('/opt',str(c/'opt')).replace('/usr/local/bin/qui',str(c/'bin/qui')).replace('/etc/systemd/system',str(c/'systemd')).replace('/etc/autocaliweb/app.db',str(c/'config/app.db')).replace('/usr/bin/kepubify',str(c/'kepubify')).replace('/etc/angie',str(c/'angie')).replace('/etc/nginx',str(c/'nginx'))
   write(c/'hook.sh',hook)
   compose='source '+shlex.quote(str(R/'misc/bundle.func'))+'\nsource '+shlex.quote(str(R/'misc/addon_lxc.func'))+'\n'
   compose+='export APP='+shlex.quote(app)+' NSAPP='+app+' APP_SLUG='+app+' REPO_BASE=https://fixture.invalid var_lxc_tmpdir='+shlex.quote(str(c/'tmp'))+'\n'
   addon=dict(bin_path=str(c/'bin'/app),dist_path=str(c/'dist'),db_dir=str(c/'db'),db_path=str(c/'db/app.db')) if app=='filebrowser' else dict(install_path=str(live),config_path=str(c/'config/operator.env'),service_path=str(c/'systemd/custom.service'),service='fixture-cronmaster',repo='fixture/cronmaster',backup_dir=str(c/'cron-backup'),creds_path=str(c/'config/creds'),default_port='80') if app=='cronmaster' else {}
   for k,v in addon.items():compose+='export var_addon_'+k+'='+shlex.quote(v)+'\n'
   compose+='source '+shlex.quote(str(c/'hook.sh'))+'\n'
   compose+=('_addon_bundle_contents update update_script ' if kind=='addon' else '_write_bundle update update_script ')+shlex.quote(str(c/'stage'))
   if kind!='addon':compose+=' --requirements 0 0 -- '+shlex.quote('run_update_script "$@"')
   with (c/'sbin/update').open('w') as out:subprocess.run(['bash','-ceu',compose],stdout=out,check=True,timeout=20)
   frozen=hashlib.sha256((c/'sbin/update').read_bytes()).hexdigest()
   env=dict(PATH=os.environ['PATH'],HOME=str(c/'home'),TMPDIR=str(c/'tmp'),CASE_ROOT=str(c),TEST_APP=app,FAULT=scenario if scenario in ('checker','search-checker') else 'none',VERBOSE=verbose,var_appversion='v2.0',BACKUP_DIR=str(c/'backup'),BUILD_LOG=str(c/'input.log'),DEBUG_LOGFILE=str(c/'input-error.log'))
   with (c/'input-output').open('w') as out:result=subprocess.run(['timeout','45s','bash',str(c/'sbin/update')],env=env,stdout=out,stderr=subprocess.STDOUT,timeout=50)
   name='input/'+app+'/'+verbose+'/'+scenario;expected=(22 if app=='autocaliweb' else 17) if scenario in ('checker','search-checker') else 0
   check(name+'/status',expected,result.returncode)
   check(name+'/pending',bool(expected),(c/'pending'/app).is_file())
   requests=[json.loads(line) for line in (c/'requests').read_text().splitlines()] if (c/'requests').exists() else []
   main_requests=[r['url'] for r in requests if r['app'].lower().replace(' ','') in (app,marker)]
   if scenario!='checker':
    check(name+'/requested selection first',True,bool(main_requests) and main_requests[0].endswith('/tags/v2.0'))
    check(name+'/no main latest',False,any(u.endswith('/latest') or u.endswith('/releases') for u in main_requests))
    check(name+'/main marker','2.0\n',read(c/'home'/('.'+marker)))
   if scenario in ('pin-current','checker','search-checker'):
    check(name+'/no service effects',False,(c/'service-calls').exists())
    check(name+'/no downloads',False,(c/'downloads').exists())
   elif scenario=='search-due':
    check(name+'/selected search marker','4.0\n',read(c/'home/.meilisearch'))
    check(name+'/modeled package consumer','modeled package search-v4\n',read(live/'source/search/package-consumer'))
   elif app in ('filebrowser','qui'):
    check(name+'/executable consumer','selected-v2',subprocess.run(['bash',str(c/'bin'/app)],capture_output=True,text=True,check=True,timeout=5).stdout)
    check(name+'/final executable mode',0o755,(c/'bin'/app).stat().st_mode&0o777)
   elif app=='wanderer':check(name+'/source consumer','2.0\n',read(live/'source/db/selected-version'))
   else:check(name+'/source consumer','2.0\n',read(live/'selected-version'))
   for p,(data,mode) in protected_input.items():
    q=pathlib.Path(p);check(name+'/protected bytes/'+str(q.relative_to(c)),data.hex(),q.read_bytes().hex() if q.is_file() else '<absent>');check(name+'/protected mode/'+str(q.relative_to(c)),mode,q.stat().st_mode&0o777 if q.exists() else -1)
   for s in service_names:check(name+'/service/'+s,'running',read(c/('service-'+s)))
   if app in ('invidious','romm','wanderer') and scenario!='checker':
    independent=[r['url'] for r in requests if r['app'].lower().replace(' ','') not in (app,marker)]
    check(name+'/independent requests',True,bool(independent))
    check(name+'/main pin isolated',False,any(u.endswith('/tags/v2.0') for u in independent))
   if scenario in ('checker','search-checker') and result.returncode==expected:
    env.update(FAULT='none',BUILD_LOG=str(c/'retry-input.log'),DEBUG_LOGFILE=str(c/'retry-input-error.log'))
    with (c/'retry-input-output').open('w') as out:retry=subprocess.run(['timeout','45s','bash',str(c/'sbin/update')],env=env,stdout=out,stderr=subprocess.STDOUT,timeout=50)
    check(name+'/ordinary retry status',0,retry.returncode)
    check(name+'/retry pending retired',False,(c/'pending'/app).exists())
    check(name+'/retry selected marker','2.0\n',read(c/'home'/('.'+marker)))
    for p,(data,mode) in protected_input.items():
     q=pathlib.Path(p);check(name+'/retry bytes/'+str(q.relative_to(c)),data.hex(),q.read_bytes().hex() if q.is_file() else '<absent>');check(name+'/retry mode/'+str(q.relative_to(c)),mode,q.stat().st_mode&0o777 if q.exists() else -1)
    for s in service_names:check(name+'/retry service/'+s,'running',read(c/('service-'+s)))
   check(name+'/frozen caller',frozen,hashlib.sha256((c/'sbin/update').read_bytes()).hexdigest())
