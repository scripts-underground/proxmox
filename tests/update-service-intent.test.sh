#!/usr/bin/env bash
set -euo pipefail
systemd-detect-virt --vm -q || exit 77
exec python3 - "$(dirname "${BASH_SOURCE[0]}")/.." << 'PY'
import json,os,pathlib,shlex,shutil,subprocess,time
assert os.geteuid()==0
assert pathlib.Path('/sys/class/dmi/id/product_uuid').read_text().strip().lower()=='4be13420-4459-4200-a1c2-7ac7232ac650'
source=pathlib.Path(os.sys.argv[1]).resolve();root=pathlib.Path('/srv/scripts-underground-tests/evidence')/('service-intent-'+str(time.time_ns()));root.mkdir(mode=0o700);rows=[]
for scenario in ['ordinary-companion-only','both-failure-companion-retry','both-failure-current-retry','start-error-retry','invalid-intent','optional-service','openrc-service']:
 case=root/scenario;case.mkdir(mode=0o700);(case/'lib').mkdir();(case/'lib/dpkg').mkdir();shutil.copy2('/var/lib/dpkg/status',case/'lib/dpkg/status')
 (case/'states.json').write_text(json.dumps({'invidious':True,'invidious-companion':True}));(case/'actions').write_text('')
 code='source '+shlex.quote(str(source/'misc/tools.func'))+'\n'+r'''
msg_warn() { printf 'WARN %s\n' "$*" >&2; }
systemctl() {
 printf '%s\n' "$*" >> "$CASE/actions"
 python3 - "$@" << 'STATE'
import json,os,pathlib,sys
p=pathlib.Path(os.environ['CASE'])/'states.json';states=json.loads(p.read_text());args=sys.argv[1:]
if args[0]=='is-active':raise SystemExit(0 if states[args[-1]] else 3)
for service in args[1:]:
 if args[0]=='start' and os.environ['SCENARIO']=='start-error-retry' and not (p.parent/'fault-delivered').exists():
  (p.parent/'fault-delivered').write_text('delivered\n');raise SystemExit(37)
 states[service]=args[0]=='start'
p.write_text(json.dumps(states))
STATE
}
rc-service() {
 local unit=$1 action=$2
 [[ "$action" != status ]] || action=is-active
 systemctl "$action" "$unit"
}
set -euo pipefail
if [[ "$SCENARIO" == optional-service ]]; then
 _update_services_stop_optional invidious invidious-companion
 _update_services_finish invidious
elif [[ "$SCENARIO" == openrc-service ]]; then
 INIT_SYSTEM=openrc
 _update_services_stop invidious invidious-companion
 _update_services_finish invidious
elif [[ "$SCENARIO" == ordinary-companion-only ]]; then
 _update_services_begin invidious invidious-companion
 systemctl stop invidious-companion
 _update_services_finish invidious
else
 _update_services_begin invidious invidious invidious-companion
 systemctl stop invidious invidious-companion
 if [[ "$SCENARIO" == both-failure-companion-retry ]]; then
  _update_services_begin invidious invidious-companion
 elif [[ "$SCENARIO" == invalid-intent ]]; then
  printf '../other-service\n' > /var/lib/scripts-underground/service-updates/invidious
 fi
 if _update_services_finish invidious; then status=0; else status=$?; fi
 printf '%s\n' "$status" > "$CASE/first-status"
 if [[ "$SCENARIO" == start-error-retry ]]; then
  test -f /var/lib/scripts-underground/service-updates/invidious
  _update_services_finish invidious
 else exit "$status"; fi
fi
'''
 launcher='import subprocess\nsubprocess.run(["mount","--bind",'+repr(str(case/'lib'))+',"/var/lib"],check=True)\n'
 launcher+='raise SystemExit(subprocess.run(["bash","-c",'+repr(code)+'],env='+repr(dict(os.environ,CASE=str(case),SCENARIO=scenario))+').returncode)\n'
 r=subprocess.run(['unshare','--mount','--propagation','private','python3','-c',launcher],capture_output=True,text=True,timeout=60)
 states=json.loads((case/'states.json').read_text());checks=[]
 def check(label,want,actual):checks.append({'name':label,'expected':want,'actual':actual,'passed':want==actual})
 check('native process status',252 if scenario=='invalid-intent' else 0,r.returncode)
 check('actual modeled consumer service states',{'invidious':False,'invidious-companion':False} if scenario=='invalid-intent' else {'invidious':True,'invidious-companion':True},states)
 if scenario=='ordinary-companion-only':check('ordinary companion-only update never calls main service',False,any('invidious' in line.split()[1:] for line in (case/'actions').read_text().splitlines()))
 if scenario=='start-error-retry':check('original start error observed before successful retry','37\n',(case/'first-status').read_text())
 row={'case':scenario,'status':'PASS' if all(c['passed'] for c in checks) else 'FAIL','checks':checks,'stdout':r.stdout,'stderr':r.stderr,'actions':(case/'actions').read_text()};rows.append(row);print(row['status']+' '+scenario,flush=True)
document={'status':'PASS' if all(r['status']=='PASS' for r in rows) else 'FAIL','cases':rows,'scope':'actual intent persistence/checks with modeled native service transport, no running Invidious claim'}
(root/'results.json').write_text(json.dumps(document,indent=2)+'\n');print('EVIDENCE',root/'results.json');raise SystemExit(0 if document['status']=='PASS' else 2)
PY
