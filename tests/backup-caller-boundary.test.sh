#!/usr/bin/env bash
set -euo pipefail
systemd-detect-virt --vm -q || exit 77
exec python3 - "$(dirname "${BASH_SOURCE[0]}")/.." << 'PY'
import json,os,pathlib,re,shlex,subprocess,time
assert pathlib.Path('/sys/class/dmi/id/product_uuid').read_text().strip().lower()=='4be13420-4459-4200-a1c2-7ac7232ac650'
source=pathlib.Path(os.sys.argv[1]).resolve();root=pathlib.Path('/srv/scripts-underground-tests/evidence')/('backup-caller-boundary-'+str(time.time_ns()));root.mkdir(mode=0o700);rows=[]
generated=subprocess.run(['go','run','-C','tools/ast','.'],cwd=source,capture_output=True,text=True,timeout=600)
(root/'ast-generation.log').write_text(generated.stdout+generated.stderr);assert generated.returncode==0,generated.stderr
for p in sorted((source/'scripts').glob('*/*.sh')):
 text=p.read_text()
 if '_recover_update_backups' not in text:continue
 ast=json.loads((source/'_ast'/p.parent.name/(p.stem+'.json')).read_text())
 assert ast['source_lines']==text.split('\n'),p
 hook=next(f for f in ast['functions'] if f['name']=='update_script')
 hook_text='\n'.join(text.splitlines()[hook['start_line']-1:hook['end_line']])
 case=root/(p.parent.name+'-'+p.stem);case.mkdir(mode=0o700)
 # Invoke the actual hook conditionally, the context that suppresses errexit.
 # A failed recovery must stop before any callback regardless of release freshness.
 declarations='\n'.join(line for line in text.splitlines()[:text[:text.index('function update_script')].count('\n')] if re.match(r'^(APP|var_(addon|lxc)_\w+)="',line))
 body=declarations+'\n'+hook_text+'\n'+r'''
header_info() { :; }
check_container_storage() { :; }
check_container_resources() { :; }
check_available_storage_bytes() { return 0; }
_recover_update_backups() { printf 'RECOVERY %s\n' "$*"; return 37; }
check_for_gh_release() { printf 'INCORRECT_RELEASE_CALLBACK\n'; return 1; }
check_for_codeberg_release() { check_for_gh_release; }
systemctl() { printf 'INCORRECT_SERVICE_CALLBACK\n'; }
if update_script; then exit 0; else exit $?; fi
'''
 r=subprocess.run(['bash','-c',body],capture_output=True,text=True,timeout=15)
 row={'script':str(p.relative_to(source)),'status':'PASS' if r.returncode==37 and 'RECOVERY' in r.stdout and 'INCORRECT_' not in r.stdout else 'FAIL',
      'process_status':r.returncode,'stdout':r.stdout,'stderr':r.stderr};rows.append(row);print(row['status']+' '+row['script'],flush=True)
document={'status':'PASS' if all(r['status']=='PASS' for r in rows) and len(rows)==78 else 'FAIL','cases':rows,'scope':'actual conditional hooks with modeled recovery failure; native helper data outcomes tested separately'}
(root/'results.json').write_text(json.dumps(document,indent=2)+'\n');print('EVIDENCE',root/'results.json');raise SystemExit(0 if document['status']=='PASS' else 2)
PY
