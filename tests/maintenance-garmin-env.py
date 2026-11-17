# Executed by maintenance-current-hardening with its admitted fixture context.
# Exercise generated hooks without contacting Garmin or creating tokens.
garmin_source = (R/'scripts/lxc/garmin-grafana.sh').read_text()
for label, role, initial, answer, expected in (
    ('fresh-yes', 'install', '', 'y\n', 'True'),
    ('fresh-no', 'install', '', 'n\n', 'False'),
    ('legacy-yes', 'update', 'GARMIN_IS_CN=True\n', '', 'True'),
    ('legacy-no', 'update', 'GARMIN_IS_CN=False\n', '', 'False'),
    ('release-yes', 'update', 'GARMIN_IS_CN=True\n', '', 'True'),
    ('release-no', 'update', 'GARMIN_IS_CN=False\n', '', 'False'),
    ('explicit-wins', 'update', 'GARMIN_IS_CN=True\nGARMINCONNECT_IS_CN=False\n', '', 'False'),
    ('explicit-true', 'update', 'GARMIN_IS_CN=False\nGARMINCONNECT_IS_CN=True\n', '', 'True'),
    ('explicit-empty', 'update', 'GARMIN_IS_CN=True\nGARMINCONNECT_IS_CN=\n', '', 'False'),
    ('neither', 'update', 'OTHER=preserved\n', '', 'False'),
):
 c=W/('garmin-'+label);c.mkdir()
 for name in ('stage','tmp','home','opt/garmin-grafana/.garminconnect','etc/influxdb','etc/grafana/provisioning/datasources','etc/grafana/provisioning/dashboards'):(c/name).mkdir(parents=True,exist_ok=True)
 if role=='update':initial+='INFLUXDB_USERNAME=testuser\nINFLUXDB_PASSWORD=testpass\nINFLUXDB_DATABASE=GarminStats\n'
 envfile=c/'opt/garmin-grafana/.env';envfile.write_text(initial)
 write(c/'etc/influxdb/influxdb.conf','# index-version = "inmem"\n')
 live=c/'opt/garmin-grafana'
 write(live/'Grafana_Dashboard/Garmin-Grafana-Dashboard.json','${DS_GARMIN_STATS}\n')
 write(live/'Grafana_Datasource/influxdb.yaml','influxdb:8086 influxdb_user influxdb_secret_password GarminStats\n')
 # Only the hook's app/system paths are redirected; the hook is otherwise exact.
 start=garmin_source.index('function '+role+'_script() {');end=garmin_source.index('\n}\n',start)+3
 hook=garmin_source[start:end].replace('/opt/garmin-grafana',str(live)).replace('/etc/influxdb',str(c/'etc/influxdb')).replace('/etc/grafana',str(c/'etc/grafana'))
 write(c/'hook.sh',hook)
 for n in ('core','error_handler','install','tools','github'):write(c/'stage'/f'{n}.func','')
 write(c/'stage/core.func','load_functions() { :; }\ncolor() { :; }\n')
 write(c/'stage/error_handler.func','catch_errors() { :; }\n')
 write(c/'stage/install.func',install_fixture(R))
 write(c/'stage/tools.func','setup_uv() { :; }\n')
 write(c/'stage/github.func','clone_and_deploy_gh_commit() { :; }\n')
 fixture='''STD=\nheader_info() { :; }\ncheck_container_storage() { :; }\ncheck_container_resources() { :; }\nsetup_deb822_repo() { :; }\napt() { :; }\nsystemctl() { :; }\ninflux() { :; }\ngrafana-cli() { :; }\nuv() { :; }\nget_latest_github_release() { printf 1; }\nfetch_and_deploy_from_url() { :; }\nfetch_and_deploy_gh_release() { :; }\ncheck_for_gh_release() { [[ "${UPGRADE:-no}" == yes ]]; }\nmsg_info() { :; }\nmsg_ok() { if [[ "$*" == "Wrote Environment Configuration" ]]; then exit 0; fi; }\nmsg_error() { :; }\n'''
 write(c/'models.sh',fixture)
 # The service model retains its initial process environment until a lifecycle
 # action. A real uv env-file consumer runs only on start/restart, not just
 # because the installer rewrote the file.
 write(c/'services','')
 probe='import os; print(os.getenv("GARMINCONNECT_IS_CN") in ["True", "true", "TRUE", "t", "T", "yes", "Yes", "YES", "1"])'
 initial_consumer=subprocess.run(['uv','run','--offline','--no-project','--env-file',str(envfile),'python3','-c',probe],capture_output=True,text=True,timeout=30,env=dict(PATH=os.environ['PATH'],HOME=str(c/'home'),TMPDIR=str(c/'tmp')))
 check('garmin/'+label+'/initial consumer status',0,initial_consumer.returncode)
 write(c/'running-region',initial_consumer.stdout)
 reader='command uv run --offline --no-project --env-file '+shlex.quote(str(envfile))+' python3 -c '+shlex.quote(probe)+' > '+shlex.quote(str(c/'running-region'))
 with (c/'models.sh').open('a') as model:
  model.write('systemctl() { printf "%s\\n" "$*" >> '+shlex.quote(str(c/'services'))+'; if [[ "$*" == "restart garmin-grafana" || "$*" == "start garmin-grafana" ]]; then '+reader+'; fi; }\n')
 compose='source '+shlex.quote(str(R/'misc/bundle.func'))+'\nsource '+shlex.quote(str(c/'hook.sh'))+'\nexport APP=garmin-grafana NSAPP=garmin-grafana REPO_BASE=offline var_lxc_tmpdir='+shlex.quote(str(c/'tmp'))+'\n'
 compose+='_write_bundle '+role+' '+role+'_script '+shlex.quote(str(c/'stage'))+' '+shlex.quote('source '+shlex.quote(str(c/'models.sh')))+' '+shlex.quote(role+'_script')+'\n'
 with (c/'bundle').open('w') as out:subprocess.run(['bash','-ceu',compose],stdout=out,check=True,timeout=20)
 result=subprocess.run(['bash',str(c/'bundle')],input=answer,text=True,capture_output=True,timeout=40,env=dict(PATH=os.environ['PATH'],HOME=str(c/'home'),TMPDIR=str(c/'tmp'),UPGRADE='yes' if label.startswith('release-') else 'no'))
 check('garmin/'+label+'/bundle status',0,result.returncode)
 # uv's real --env-file reader is the installer/service's upstream environment
 # transport; the boolean expression is from upstream v0.5.0 commit 44fe4a8e.
 probe='import os; print(os.getenv("GARMINCONNECT_IS_CN") in ["True", "true", "TRUE", "t", "T", "yes", "Yes", "YES", "1"])'
 consumer=subprocess.run(['uv','run','--offline','--no-project','--env-file',str(envfile),'python3','-c',probe],capture_output=True,text=True,timeout=30,env=dict(PATH=os.environ['PATH'],HOME=str(c/'home'),TMPDIR=str(c/'tmp')))
 check('garmin/'+label+'/consumer status',0,consumer.returncode)
 check('garmin/'+label+'/upstream boolean',expected,consumer.stdout.strip())
 if role=='update':
  check('garmin/'+label+'/existing bytes',True,envfile.read_text().startswith(initial))
  if 'GARMINCONNECT_IS_CN=' in initial:check('garmin/'+label+'/explicit unchanged',initial,envfile.read_text())
  actions=(c/'services').read_text().splitlines()
  if label.startswith('legacy-'):
   check('garmin/'+label+'/no-release migration restarts service',['restart garmin-grafana'],actions)
   check('garmin/'+label+'/restarted consumer sees region',expected,(c/'running-region').read_text().strip())
   before=envfile.read_text()
   repeated=subprocess.run(['bash',str(c/'bundle')],input='',text=True,capture_output=True,timeout=40,env=dict(PATH=os.environ['PATH'],HOME=str(c/'home'),TMPDIR=str(c/'tmp'),UPGRADE='no'))
   check('garmin/'+label+'/repeated update status',0,repeated.returncode)
   check('garmin/'+label+'/migration idempotent',before,envfile.read_text())
   check('garmin/'+label+'/repeat does not restart',actions,(c/'services').read_text().splitlines())
  elif label.startswith('release-'):
   check('garmin/'+label+'/release lifecycle',['stop garmin-grafana','start garmin-grafana','restart grafana-server'],actions)
   check('garmin/'+label+'/release consumer sees region',expected,(c/'running-region').read_text().strip())
  else:
   check('garmin/'+label+'/unchanged config needs no service action',[],actions)
   check('garmin/'+label+'/unchanged running environment',initial_consumer.stdout,(c/'running-region').read_text())
