#!/usr/bin/env bash
set -euo pipefail
systemd-detect-virt --vm -q || exit 77
exec python3 - "$(dirname "${BASH_SOURCE[0]}")/.." << 'PY'
import hashlib
import json
import os
import pathlib
import shlex
import shutil
import subprocess
import tarfile
import time

assert os.geteuid() == 0
assert pathlib.Path('/sys/class/dmi/id/product_uuid').read_text().strip().lower() == '4be13420-4459-4200-a1c2-7ac7232ac650'
source = pathlib.Path(os.sys.argv[1]).resolve()
area = pathlib.Path('/srv/scripts-underground-tests/evidence')/('release-assets-'+str(time.time_ns()))
area.mkdir(mode=0o700)
results = []
for scenario in ['coherent-layers', 'missing-layer', 'cross-release-url', 'digest-error', 'escaping-alias', 'publication-error']:
    case = area/scenario
    case.mkdir(mode=0o700)
    for name in ['opt', 'lib', 'home', 'tmp', 'incoming', 'runtime']:
        (case/name).mkdir(mode=0o700)
    (case/'lib/dpkg').mkdir()
    shutil.copy2('/var/lib/dpkg/status', case/'lib/dpkg/status')
    target = case/'opt/asset-test'
    target.mkdir()
    (target/'server').write_bytes(b'original executable\n')
    (target/'server').chmod(0o755)
    (target/'user-config').write_bytes(b'preserved administrator data\n')
    (target/'user-config').chmod(0o600)
    marker = case/'home/.asset-test'
    marker.write_bytes(b'1.0.0\n')
    (case/'incoming/server').write_bytes(b'new executable from complete cohort\n')
    (case/'incoming/server').chmod(0o755)
    (case/'incoming/libtest.so.2').write_bytes(b'library implementation\n')
    os.symlink('../foreign' if scenario == 'escaping-alias' else 'libtest.so.2', case/'incoming/libtest.so')
    (case/'runtime/runtime.so').write_bytes(b'same-build runtime layer\n')
    for name, tree in [('server.tar.gz', 'incoming'), ('runtime.tar.gz', 'runtime')]:
        with tarfile.open(case/name, 'w:gz') as archive:
            archive.add(case/tree, arcname='bundle')
    release = {'tag_name': 'v2.0.0', 'draft': False, 'prerelease': False, 'assets': []}
    for name in ['server.tar.gz', 'runtime.tar.gz']:
        release['assets'].append({'name': name, 'browser_download_url': 'https://github.com/fixture/app/releases/download/v2.0.0/'+name,
                                 'digest': 'sha256:'+hashlib.sha256((case/name).read_bytes()).hexdigest()})
    if scenario == 'missing-layer': release['assets'].pop()
    if scenario == 'cross-release-url': release['assets'][0]['browser_download_url'] = 'https://github.com/fixture/app/releases/download/v1.0.0/server.tar.gz'
    if scenario == 'digest-error': release['assets'][0]['digest'] = 'sha256:'+'0'*64
    (case/'release.json').write_text(json.dumps(release)+'\n')
    (case/'requests').write_text('')
    header = 'source '+shlex.quote(str(source/'misc/tools.func'))+'\n'+r'''
STD=''
msg_info() { :; }
msg_ok() { :; }
msg_debug() { :; }
msg_warn() { printf 'WARN %s\n' "$*" >&2; }
msg_error() { printf 'ERROR %s\n' "$*" >&2; }
curl_download() {
  printf '%s\n' "$2" >> "$CASE/requests"
  cp -- "$CASE/${2##*/}" "$1"
}
mv() {
  if [[ "$SCENARIO" == publication-error && "${*: -1}" == /opt/asset-test/server && "${*: -2:1}" == */publish ]]; then
    printf 'actual publication fault 17\n' >> "$CASE/requests"
    return 17
  fi
  command mv "$@"
}
release=$(cat -- "$CASE/release.json")
if CLEAN_INSTALL=0 _gh_deploy_verified_assets asset-test fixture/app "$release" /opt/asset-test 2.0.0 flat server server.tar.gz runtime.tar.gz; then status=0; else status=$?; fi
printf '%s\n' "$status" > "$CASE/helper-status"
exit "$status"
'''
    code = 'import pathlib,subprocess,os\ncase=pathlib.Path('+repr(str(case))+')\n'
    code += 'for name,destination in [("opt","/opt"),("lib","/var/lib"),("tmp","/tmp")]: subprocess.run(["mount","--bind",str(case/name),destination],check=True)\n'
    code += 'raise SystemExit(subprocess.run(["bash","-c",'+repr(header)+'],env=dict(os.environ,CASE=str(case),SCENARIO='+repr(scenario)+',HOME=str(case/"home"),TMPDIR=str(case/"tmp")),capture_output=False).returncode)\n'
    native = subprocess.run(['unshare', '--mount', '--propagation', 'private', 'python3', '-c', code], capture_output=True, text=True, timeout=120)
    checks = []
    def check(name, expected, actual): checks.append({'name':name,'expected':expected,'actual':actual,'passed':expected==actual})
    expected = {'coherent-layers': 0, 'missing-layer': 252, 'cross-release-url': 250, 'digest-error': 250, 'escaping-alias': 251, 'publication-error': 252}[scenario]
    check('actual helper result', expected, native.returncode)
    check('administrator data preserved', b'preserved administrator data\n'.hex(), (target/'user-config').read_bytes().hex())
    check('administrator data mode preserved', 0o600, (target/'user-config').stat().st_mode & 0o777)
    check('real version marker follows complete publication', '2.0.0\n' if expected == 0 else '1.0.0\n', marker.read_text())
    check('actual executable bytes', b'new executable from complete cohort\n'.hex() if expected == 0 else b'original executable\n'.hex(), (target/'server').read_bytes().hex())
    if expected == 0:
        check('runtime layer included in same committed cohort', b'same-build runtime layer\n'.hex(), (target/'runtime.so').read_bytes().hex())
        check('library ABI alias safely materialized', [True, False, b'library implementation\n'.hex()],
              [(target/'libtest.so').is_file(), (target/'libtest.so').is_symlink(), (target/'libtest.so').read_bytes().hex()])
    if scenario == 'publication-error': check('actual owner fault delivered', True, 'actual publication fault 17' in (case/'requests').read_text())
    row = {'scenario':scenario,'status':'PASS' if all(check['passed'] for check in checks) else 'FAIL', 'checks':checks,
           'native_status':native.returncode,'stdout':native.stdout,'stderr':native.stderr,'requests':(case/'requests').read_text()}
    (case/'result.json').write_text(json.dumps(row,indent=2)+'\n')
    results.append(row)
    print(row['status']+' '+scenario,flush=True)
document = {'status':'PASS' if all(row['status']=='PASS' for row in results) else 'FAIL','results':results,
            'scope':'native verified asset preparation/publication with synthetic payloads; no application or GPU inference claim'}
(area/'results.json').write_text(json.dumps(document,indent=2)+'\n')
print('EVIDENCE '+str(area/'results.json'))
raise SystemExit(0 if document['status']=='PASS' else 2)
PY
