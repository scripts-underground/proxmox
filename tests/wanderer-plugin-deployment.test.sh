#!/usr/bin/env bash
# Native Wanderer plugin outcomes; only through the protected test-VM supervisor.
set -euo pipefail
[[ $# == 2 || $# == 4 ]] || exit 64
systemd-detect-virt --vm -q || exit 77
exec python3 - "$0" "$@" << 'PY'
import copy
import hashlib
import json
import os
import pathlib
import shlex
import subprocess
import sys
import tarfile

script, session, pinned = pathlib.Path(sys.argv[1]).resolve(), pathlib.Path(sys.argv[2]), sys.argv[3]
assert os.geteuid() == 0
assert pathlib.Path('/sys/class/dmi/id/product_uuid').read_text().strip().lower() == '842ad04b-e0af-4a06-b1e1-fd4acd54a592'
assert os.environ['SU_JOB_PRIVATE_PIDNS'] == os.readlink('/proc/self/ns/pid')
raw = (session/'manifest.json').read_bytes()
assert hashlib.sha256(raw).hexdigest() == pinned
manifest = json.loads(raw)
assert script == session/'harness/tests/wanderer-plugin-deployment.test.sh'
assert hashlib.sha256(script.read_bytes()).hexdigest() == next(e['sha256'] for e in manifest['harness']['inventory'] if e['path'] == 'tests/wanderer-plugin-deployment.test.sh')
sys.path.insert(0, str(session/'support'))
from probe import point, tree
from hardening_raw import projection
scenarios = ['install-section', 'main-update', 'main-current-plugin-update', 'download-failure', 'publication-failure',
             'legacy-wrong-layout', 'missing-current-file', 'current-healthy', 'checker-failure', 'cold-hook',
             'meili-deploy-failure', 'meili-stop-failure', 'meili-start-failure', 'plugin-warning-meili-update']
selection = os.environ.get('SU_WANDERER_ONLY', '')
if selection:
    selected = selection.split(',')
    assert len(selected) == len(set(selected)) and set(selected) <= set(scenarios)
    scenarios = [scenario for scenario in scenarios if scenario in selected]
if len(sys.argv) == 4:
    area = session/'wanderer-cases'
    area.mkdir(mode=0o700)
    results = []
    for scenario in scenarios:
        case = area/scenario
        case.mkdir(mode=0o700)
        native = subprocess.run(['unshare', '--mount', '--propagation', 'private', 'bash', str(script), str(session), pinned, scenario, str(case)],
                                capture_output=True, text=True)
        (case/'stdout.log').write_text(native.stdout)
        (case/'stderr.log').write_text(native.stderr)
        document = json.loads((case/'result.json').read_bytes()) if (case/'result.json').exists() else {'error': native.stderr}
        results.append({'scenario': scenario, 'process_status': native.returncode, 'result': document})
        print(('PASS' if native.returncode == 0 else 'FAIL')+' Wanderer/'+scenario, flush=True)
    document = {'status': 'PASS' if all(row['process_status'] == 0 for row in results) else 'FAIL',
                'manifest_sha256': pinned, 'source_tree': manifest['source']['tree'], 'results': results,
                'scope': 'actual hook/provider/recovery/input-consumer outcomes; service/build callbacks modeled; no provider account/WASM/application execution'}
    with (session/'wanderer-controls-results.json').open('x') as out:
        out.write(json.dumps(document, indent=2)+'\n')
    raise SystemExit(0 if document['status'] == 'PASS' else 2)

scenario, case = sys.argv[4], pathlib.Path(sys.argv[5])
assert scenario in scenarios and case == session/'wanderer-cases'/scenario
work = pathlib.Path(os.environ['SU_CONTAINMENT_WORK'])
for name in ['opt', 'lib', 'home', 'tmp', 'incoming']:
    (case/name).mkdir(mode=0o700)
(case/'lib/dpkg').mkdir()
(case/'lib/dpkg/status').write_bytes(pathlib.Path('/var/lib/dpkg/status').read_bytes())
for name, destination, inherited in [('opt', '/opt', 'opt'), ('lib', '/var/lib', 'var-lib'), ('tmp', '/tmp', 'tmp')]:
    old = work/'private'/inherited
    assert (old.stat().st_dev, old.stat().st_ino) == (pathlib.Path(destination).stat().st_dev, pathlib.Path(destination).stat().st_ino)
    subprocess.run(['umount', '--recursive', '--', destination], check=True)
    subprocess.run(['mount', '--no-mtab', '--bind', str(case/name), destination], check=True)
target = pathlib.Path('/opt/wanderer/data/plugins')
target.mkdir(parents=True)
source = pathlib.Path('/opt/wanderer/source')
for name in ['db/data', 'web', 'search']:
    (source/name).mkdir(parents=True)
pathlib.Path('/opt/wanderer/start.sh').write_text('meilisearch --experimental-dumpless-upgrade\n')
(source/'search/native-search').write_bytes(b'protected search\n')
(case/'home/.wanderer').write_bytes(b'1.0.0\n' if scenario in {'main-update', 'download-failure', 'publication-failure'} else b'2.0.0\n')
(case/'home/.meilisearch').write_bytes(b'1.0.0\n')
plugins = ['hammerhead', 'komoot', 'strava']
inputs, originals = {}, {}
routes = {}
assets = []
for plugin in plugins:
    incoming = case/'incoming'/plugin
    incoming.mkdir()
    (incoming/'plugin.json').write_text(json.dumps({'id': plugin, 'version': 'plugin-private-version', 'runtime': {'entrypoint': 'plugin.wasm', 'type': 'wasm'}})+'\n')
    (incoming/'plugin.wasm').write_bytes(b'new '+plugin.encode()+b' payload\n')
    inputs[plugin] = tree(incoming)
    archive = case/('wanderer-plugin-'+plugin+'.tar.gz')
    with tarfile.open(archive, 'w:gz') as out:
        out.add(incoming, arcname=plugin)
    url = 'https://github.com/open-wanderer/wanderer/releases/download/v2.0.0/'+archive.name
    routes[url] = {'file': str(archive)}
    assets.append({'name': archive.name, 'browser_download_url': url})
    if scenario != 'install-section':
        directory = target/plugin
        directory.mkdir()
        current = scenario in {'missing-current-file', 'current-healthy', 'checker-failure', 'meili-deploy-failure',
                               'meili-stop-failure', 'meili-start-failure', 'plugin-warning-meili-update'}
        (directory/'plugin.json').write_bytes((incoming/'plugin.json').read_bytes() if current else json.dumps({'id': plugin, 'version': 'old'}).encode())
        (directory/'plugin.wasm').write_bytes((incoming/'plugin.wasm').read_bytes() if current else b'old '+plugin.encode()+b' payload\n')
        (directory/'custom-settings').write_bytes(b'user '+plugin.encode()+b' state\n')
        (directory/'custom-settings').chmod(0o640)
        os.setxattr(directory/'custom-settings', 'user.wanderer', b'preserve')
        (case/'home'/('.wanderer-plugin-'+plugin)).write_bytes(b'2.0.0\n' if current or scenario == 'legacy-wrong-layout' else b'1.0.0\n')
        originals[plugin] = tree(directory)
(target/'custom-third-party').mkdir()
(target/'custom-third-party/user-data').write_bytes(b'foreign plugin must survive\n')
if scenario == 'legacy-wrong-layout':
    (target/'plugin.json').write_text(json.dumps({'id': 'strava', 'version': 'old-wrong-layout'})+'\n')
    (target/'plugin.wasm').write_bytes(b'preserve misplaced unknown bytes\n')
if scenario == 'missing-current-file':
    (target/'hammerhead/plugin.wasm').unlink()
protected = {'custom': tree(target/'custom-third-party'), 'legacy': {name: point(target/name) for name in ['plugin.json', 'plugin.wasm']}}
for plugin in plugins:
    if scenario != 'install-section':
        protected[plugin] = point(target/plugin/'custom-settings')
incoming_source = case/'incoming/source'
for name in ['db', 'web']:
    (incoming_source/name).mkdir(parents=True)
    (incoming_source/name/'new-source').write_bytes(b'new main source\n')
archive = case/'source.tar.gz'
with tarfile.open(archive, 'w:gz') as out:
    out.add(incoming_source, arcname='wanderer-source')
routes['https://github.com/open-wanderer/wanderer/archive/refs/tags/v2.0.0.tar.gz'] = {'file': str(archive)}
release = {'tag_name': 'v2.0.0', 'draft': False, 'prerelease': False, 'assets': assets}
for endpoint in ['latest', 'tags/v2.0.0']:
    routes['https://api.github.com/repos/open-wanderer/wanderer/releases/'+endpoint] = {'json': release}
routes['https://api.github.com/repos/meilisearch/meilisearch/releases/latest'] = {'json': dict(release, tag_name='v1.0.0', assets=[])}
if scenario.startswith('meili-') or scenario == 'plugin-warning-meili-update':
    routes['https://api.github.com/repos/meilisearch/meilisearch/releases/latest'] = {'json': dict(release, assets=[])}
    routes['https://api.github.com/repos/meilisearch/meilisearch/releases?per_page=15'] = {'json': []}
(case/'routes.json').write_text(json.dumps(routes)+'\n')
for name in ['actions.log', 'fault-events.jsonl', 'requests.jsonl', 'dispatch-errors.jsonl']:
    (case/name).write_bytes(b'')
script_body = (session/'source/scripts/lxc/wanderer.sh').read_text()
cut = script_body.rfind('\nsource <(curl ')
assert cut > 0
definitions = case/'definitions.sh'
definitions.write_text(script_body[:cut]+'\n')
env = dict(os.environ, HOME=str(case/'home'), TMPDIR=str(case/'tmp'),
           SG_CASE=str(case), SG_ID='wanderer-controls', SG_SCENARIO=scenario, SG_MANIFEST=str(session/'manifest.json'),
           SG_MANIFEST_SHA256=pinned, SG_SOURCE=str(session/'source'), SG_HARNESS=str(session/'harness'),
           SG_REVIEW_SUPPORT=str(session/'support'), SG_ROUTES=str(case/'routes.json'), SG_REQUESTS=str(case/'requests.jsonl'),
           SG_DISPATCH_ERRORS=str(case/'dispatch-errors.jsonl'), SG_OBSERVE_ACTIVE='0',
           H_SCENARIO=scenario, H_CASE=str(case), BACKUP_DIR=str(case/'backup'), NSAPP='wanderer', APP='Wanderer')
for name in ['GITHUB_TOKEN', 'GH_TOKEN', 'var_appversion', 'CLEAN_INSTALL', 'FORCE_DEPLOY']:
    env.pop(name, None)
header = 'source '+shlex.quote(str(session/'source/misc/tools.func'))+'\nsource '+shlex.quote(str(session/'harness/tests/lib/safety-gap-common.sh'))+'\nsource '+shlex.quote(str(definitions))+r'''
STD=''
header_info() { :; }
check_container_storage() { :; }
check_container_resources() { :; }
msg_info() { printf 'INFO %s\n' "$*"; }
msg_ok() { printf 'OK %s\n' "$*"; }
msg_warn() { printf 'WARN %s\n' "$*" >&2; }
msg_error() { printf 'ERROR %s\n' "$*" >&2; }
getent() { printf '127.0.0.1 declared fixture\n'; }
systemctl() {
  printf 'service callback %s\n' "$*" >> "$H_CASE/actions.log"
  if [[ "$H_SCENARIO" == meili-stop-failure && "$1" == stop || "$H_SCENARIO" == meili-start-failure && "$1" == start ]]; then
    sg_review_fault actual-meili-service systemctl "$@" status=95
    return 95
  fi
  return 0
}
go() { printf 'build callback go %s\n' "$*" >> "$H_CASE/actions.log"; return 0; }
npm() { printf 'build callback npm %s\n' "$*" >> "$H_CASE/actions.log"; return 0; }
curl() {
  if [[ "$H_SCENARIO" == download-failure && "$SG_INVOCATION" == primary && "$*" == *'/wanderer-plugin-hammerhead.tar.gz'* ]]; then
    sg_review_fault actual-plugin-download curl "$@" status=17
    return 17
  fi
  if [[ "$H_SCENARIO" == checker-failure || "$H_SCENARIO" == plugin-warning-meili-update ]] && [[ "$SG_INVOCATION" == primary && "${app:-}" == wanderer-plugin-hammerhead && "$*" == *'api.github.com/'* ]]; then
    sg_review_fault actual-plugin-checker curl "$@" status=17
    return 17
  fi
  sg_dispatch_curl "$@"
}
mv() {
  if [[ "${*: -2:1}" == */publish ]]; then
    printf 'native publication %s\n' "${*: -1}" >> "$H_CASE/actions.log"
  fi
  if [[ "$H_SCENARIO" == publication-failure && "$SG_INVOCATION" == primary && "${*: -1}" == "$HOME/.wanderer-plugin-hammerhead" && "${*: -2:1}" == */publish ]]; then
    sg_review_fault actual-plugin-marker-publication mv "$@" status=17
    return 17
  fi
  command mv "$@"
}
'''
if scenario in {'meili-start-failure', 'plugin-warning-meili-update'}:
    header += r'''
native_deployer_definition=$(declare -f fetch_and_deploy_gh_release)
eval "${native_deployer_definition/fetch_and_deploy_gh_release/fixture_native_deployer}"
fetch_and_deploy_gh_release() {
  if [[ "$1" == meilisearch ]]; then
    printf 'modeled successful meili deployment\n' >> "$H_CASE/actions.log"
    return 0
  fi
  fixture_native_deployer "$@"
}
'''
expression = 'update_script'
if scenario == 'install-section':
    begin = script_body.index('  msg_info "Installing wanderer plugins"')
    end = script_body.index('  msg_info "Creating Service"', begin)
    header += '\ninstall_plugins_section() {\n'+script_body[begin:end]+'\n}\n'
    expression = 'install_plugins_section'
elif scenario == 'cold-hook':
    native = subprocess.run(['bash', '-c', 'source '+shlex.quote(str(definitions))+'\ndeclare -f update_script'], capture_output=True, text=True, check=True)
    cold = case/'cold-hook.sh'
    cold.write_text(native.stdout)
    # Only the selected hook body is available, as in the framework's cold bundle.
    header = header.replace('source '+shlex.quote(str(definitions)), 'source '+shlex.quote(str(cold)))
def invoke(label):
    native = subprocess.run(['bash', '-c', header+'\nset -e\nif '+expression+'; then status=0; else status=$?; fi\nexit "$status"\n'],
                            env=dict(env, SG_INVOCATION=label), capture_output=True, text=True)
    (case/(label+'-stdout.log')).write_text(native.stdout)
    (case/(label+'-stderr.log')).write_text(native.stderr)
    return native
def snapshot():
    return {'target': tree(target), 'markers': {plugin: point(case/'home'/('.wanderer-plugin-'+plugin)) for plugin in plugins}}
primary = invoke('primary')
after = snapshot()
primary_actions = (case/'actions.log').read_text().splitlines()
retry = invoke('retry') if scenario in {'download-failure', 'publication-failure'} else None
final = snapshot()
requests = [json.loads(line) for line in (case/'requests.jsonl').read_text().splitlines()]
faults = [json.loads(line) for line in (case/'fault-events.jsonl').read_text().splitlines()]
checks = []
def check(name, wanted, actual):
    checks.append({'name': name, 'expected': wanted, 'actual': actual, 'passed': wanted == actual})
expected_status = 252 if scenario == 'meili-deploy-failure' else 95 if scenario in {'meili-stop-failure', 'meili-start-failure'} else 0
check('actual hook returns its checked caller status', expected_status, primary.returncode)
check('all actual transport routes declared', '', (case/'dispatch-errors.jsonl').read_text())
def assess_consumers(observed, expected_plugins=plugins):
    defects = []
    for plugin in expected_plugins:
        for name, node in inputs[plugin]['entries'].items():
            actual = observed['target']['entries'].get(plugin+'/'+name, {})
            for key in ['kind', 'sha256', 'size']:
                if actual.get(key) != node.get(key):
                    defects.append(plugin+'/'+name+'/'+key)
        if observed['markers'][plugin].get('sha256') != hashlib.sha256(b'2.0.0\n').hexdigest():
            defects.append(plugin+'/marker')
    return defects
if scenario in {'download-failure', 'publication-failure'}:
    check('genuine primary fault delivered', True, bool(faults))
    check('failed plugin marker retained', hashlib.sha256(b'1.0.0\n').hexdigest(), after['markers']['hammerhead'].get('sha256'))
    check('failed plugin native payload/configuration retained', projection(originals['hammerhead']),
          projection(dict(after['target']['entries']['hammerhead'], entries={name.removeprefix('hammerhead/'): node for name, node in after['target']['entries'].items() if name.startswith('hammerhead/')})))
    check('partial update has accurate plugin warning', True, 'Failed to install wanderer plugin' in primary.stderr)
    check('partial update does not report all plugins installed', False, 'OK Installed wanderer plugins\n' in primary.stdout)
    check('partial update does not report unconditional update success', False, 'OK Update Successful\n' in primary.stdout)
    check('next actual main-current hook succeeds', 0, retry.returncode)
    check('next invocation really retries failed plugin archive', True,
          any(row['invocation'] == 'retry' and row['url'].endswith('wanderer-plugin-hammerhead.tar.gz') for row in requests))
    check('successful siblings already correct before retry', [], assess_consumers(after, ['komoot', 'strava']))
    check('retry does not download successful sibling archives', [],
          [row['url'] for row in requests if row['invocation'] == 'retry' and row['url'].endswith(('wanderer-plugin-komoot.tar.gz', 'wanderer-plugin-strava.tar.gz'))])
    for plugin in ['komoot', 'strava']:
        check('retry leaves successful sibling marker unchanged/'+plugin, after['markers'][plugin], final['markers'][plugin])
        for name in inputs[plugin]['entries']:
            check('retry leaves successful sibling payload unchanged/'+plugin+'/'+name,
                  after['target']['entries'][plugin+'/'+name], final['target']['entries'][plugin+'/'+name])
check('complete final independent plugin bytes and marker consumers', [], assess_consumers(final))
if scenario == 'current-healthy':
    check('healthy current invocation has no archive transfer', [], [row['url'] for row in requests if '/releases/download/' in row['url']])
    check('healthy current invocation has no service/build activity', '', (case/'actions.log').read_text())
if scenario == 'checker-failure':
    check('actual optional checker fault delivered', True, any(row['kind'] == 'actual-plugin-checker' for row in faults))
    check('optional checker error warning is visible', True, 'Failed to check wanderer plugin' in primary.stderr)
    check('checker error never authorizes plugin archive transfer', [], [row['url'] for row in requests if '/releases/download/' in row['url']])
if scenario in {'main-update', 'main-current-plugin-update', 'download-failure', 'publication-failure',
                'legacy-wrong-layout', 'missing-current-file', 'cold-hook'}:
    stops = [index for index, action in enumerate(primary_actions) if action == 'service callback stop wanderer-web']
    starts = [index for index, action in enumerate(primary_actions) if action == 'service callback start wanderer-web']
    publications = [index for index, action in enumerate(primary_actions) if action.startswith('native publication ')]
    check('one service stop and start around primary plugin mutations', [1, 1], [len(stops), len(starts)])
    check('stop precedes every publication and start follows every publication', True,
          bool(stops and starts and publications) and stops[0] < min(publications) <= max(publications) < starts[0])
if scenario.startswith('meili-'):
    check('required Meilisearch failure never reports unconditional success', False, 'OK Update Successful\n' in primary.stdout)
if scenario == 'plugin-warning-meili-update':
    check('plugin warning survives a later successful Meilisearch update', False, 'OK Update Successful\n' in primary.stdout)
    check('plugin warning remains visible', True, 'Failed to check wanderer plugin' in primary.stderr)
check('unrelated custom plugin preserved', projection(protected['custom']), projection(tree(target/'custom-third-party')))
for name in ['plugin.json', 'plugin.wasm']:
    check('unowned shared-root artifact preserved/'+name, protected['legacy'][name], point(target/name))
for plugin in plugins:
    if scenario != 'install-section':
        check('plugin user state and complete metadata preserved/'+plugin, protected[plugin], point(target/plugin/'custom-settings'))
if not assess_consumers(final):
    specimen = copy.deepcopy(final)
    specimen['target']['entries']['hammerhead/plugin.wasm']['sha256'] = '0'*64
    check('consumer oracle rejects wrong installed WASM bytes', True, bool(assess_consumers(specimen)))
document = {'status': 'PASS' if all(row['passed'] for row in checks) else 'FAIL', 'scenario': scenario,
            'manifest_sha256': pinned, 'checks': checks, 'primary_native_status': primary.returncode,
            'retry_native_status': retry.returncode if retry else None, 'after': after, 'final': final,
            'requests': requests, 'faults': faults, 'actions': (case/'actions.log').read_text().splitlines(),
            'primary_actions': primary_actions,
            'stdout': primary.stdout, 'stderr': primary.stderr}
with (case/'result.json').open('x') as out:
    out.write(json.dumps(document, indent=2)+'\n')
raise SystemExit(0 if document['status'] == 'PASS' else 2)
PY
