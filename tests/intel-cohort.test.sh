#!/usr/bin/env bash
set -euo pipefail
systemd-detect-virt --vm -q || exit 77
exec python3 - "$(dirname "${BASH_SOURCE[0]}")/.." << 'PY'
import hashlib,json,os,pathlib,shlex,subprocess,time
assert os.geteuid()==0
assert pathlib.Path('/sys/class/dmi/id/product_uuid').read_text().strip().lower()=='4be13420-4459-4200-a1c2-7ac7232ac650'
source=pathlib.Path(os.sys.argv[1]).resolve();root=pathlib.Path('/srv/scripts-underground-tests/evidence')/('intel-cohort-'+str(time.time_ns()));root.mkdir(mode=0o700)
names=['libigdgmm12','intel-opencl-icd','libze-intel-gpu1','intel-igc-core-2','intel-igc-opencl-2'];rows=[]
for scenario in ['complete','missing-notes','ambiguous-notes','latest-pin','igc-query-error','missing-igc-asset','wrong-package','digest-error','download-error','install-error']:
 case=root/scenario;case.mkdir(mode=0o700);(case/'tmp').mkdir();(case/'actions').write_text('')
 releases={repo:{'tag_name':'v2.0.0' if repo.endswith('compute-runtime') else 'v2.31.3','draft':False,'prerelease':False,'body':'https://github.com/intel/intel-graphics-compiler/releases/tag/v2.31.3','assets':[]} for repo in ['intel/compute-runtime','intel/intel-graphics-compiler']}
 for i,name in enumerate(names):
  tree=case/name;(tree/'DEBIAN').mkdir(parents=True)
  package='foreign-package' if scenario=='wrong-package' and i==4 else name
  (tree/'DEBIAN/control').write_text('Package: '+package+'\nVersion: 2.0.0\nArchitecture: amd64\nMaintainer: Fixture <fixture@example.invalid>\nDescription: synthetic dependency contract\n')
  filename=name+'_2.0.0_amd64.deb';subprocess.run(['dpkg-deb','--build',str(tree),str(case/filename)],check=True,capture_output=True)
  repo='intel/compute-runtime' if i<3 else 'intel/intel-graphics-compiler';rel=releases[repo]
  rel['assets'].append({'name':filename,'browser_download_url':'https://github.com/'+repo+'/releases/download/'+rel['tag_name']+'/'+filename,
                        'digest':'sha256:'+hashlib.sha256((case/filename).read_bytes()).hexdigest()})
 cr=releases['intel/compute-runtime'];igc=releases['intel/intel-graphics-compiler']
 if scenario=='missing-notes':cr['body']='no compiler provenance'
 if scenario=='ambiguous-notes':cr['body']+=' https://github.com/intel/intel-graphics-compiler/releases/tag/v9.0.0'
 if scenario=='latest-pin':cr['body']='https://github.com/intel/intel-graphics-compiler/releases/tag/latest'
 if scenario=='missing-igc-asset':igc['assets'].pop()
 if scenario=='digest-error':cr['assets'][0]['digest']='sha256:'+'0'*64
 (case/'compute.json').write_text(json.dumps(cr));(case/'igc.json').write_text(json.dumps(igc))
 body='source '+shlex.quote(str(source/'misc/tools.func'))+'\n'+r'''
STD=''
msg_warn() { printf 'WARN %s\n' "$*" >&2; }
msg_error() { printf 'ERROR %s\n' "$*" >&2; }
get_system_arch() { printf amd64; }
_gh_read_release_metadata() {
 local cohort_fixture
 printf 'metadata %s %s %s\n' "$2" "$3" "$4" >> "$CASE/actions"
 if [[ "$2" == intel/compute-runtime ]]; then cohort_fixture=$(cat "$CASE/compute.json"); else
  [[ "$SCENARIO" != igc-query-error ]] || return 22
  [[ "$3" == v2.31.3 && "$4" == selected ]] || return 97
  cohort_fixture=$(cat "$CASE/igc.json")
 fi
 printf -v "$1" '%s' "$cohort_fixture"
}
curl_download() {
 printf 'download %s\n' "$2" >> "$CASE/actions"
 cp -- "$CASE/${2##*/}" "$1" || return $?
 [[ "$SCENARIO" != download-error ]] || return 37
}
apt() {
 printf 'apt-call\n' >> "$CASE/actions"
 local cohort_file cohort_count=0
 for cohort_file in "$@"; do
  if [[ "$cohort_file" == *.deb ]]; then
   test -f "$cohort_file" || return 98
   dpkg-deb -f "$cohort_file" Package >> "$CASE/actions" || return $?
   ((cohort_count += 1))
  fi
 done
 [[ "$cohort_count" == 5 ]] || return 98
 [[ "$SCENARIO" != install-error ]] || return 37
}
if _setup_intel_compute_cohort; then exit 0; else exit $?; fi
'''
 r=subprocess.run(['bash','-c',body],env=dict(os.environ,CASE=str(case),SCENARIO=scenario,TMPDIR=str(case/'tmp')),capture_output=True,text=True,timeout=60)
 expected={'complete':0,'igc-query-error':22,'missing-igc-asset':252,'download-error':37,'install-error':37}.get(scenario,250)
 actions=(case/'actions').read_text();checks=[]
 def check(label,want,actual):checks.append({'name':label,'expected':want,'actual':actual,'passed':want==actual})
 check('checked native helper result',expected,r.returncode)
 check('only complete selected cohort reaches package manager',1 if scenario in {'complete','install-error'} else 0,actions.count('apt-call'))
 check('no unrelated latest compiler lookup',False,'intel/intel-graphics-compiler latest' in actions)
 if scenario in {'complete','install-error'}:check('all five native package identities delivered in one install',names,[line for line in actions.splitlines() if line in names])
 row={'case':scenario,'status':'PASS' if all(c['passed'] for c in checks) else 'FAIL','checks':checks,'native_status':r.returncode,'actions':actions,'stdout':r.stdout,'stderr':r.stderr}
 (case/'result.json').write_text(json.dumps(row,indent=2)+'\n');rows.append(row);print(row['status']+' '+scenario,flush=True)
document={'status':'PASS' if all(r['status']=='PASS' for r in rows) else 'FAIL','cases':rows,'scope':'actual metadata resolver/selection/digest/dpkg readers; modeled network/package installation, no hardware proof'}
(root/'results.json').write_text(json.dumps(document,indent=2)+'\n');print('EVIDENCE',root/'results.json')
raise SystemExit(0 if document['status']=='PASS' else 2)
PY
