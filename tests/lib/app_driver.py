"""Normal app consumers over the shared guest/native owner; no product hook calls."""
import hashlib
from html.parser import HTMLParser
import http.cookiejar
import io
import json
import os
from pathlib import Path
import re
import subprocess
import sys
import time
import urllib.parse
import urllib.request
import uuid
import zipfile
import xml.etree.ElementTree as ET

from entrypoint import admit_direct
from test_context import AdmissionError, Run, require, sha
from test_pve import Broker, NativePVE, Publisher, bridge_network


CONSUMERS = {
    'calibre-web-automated': (['calibre-web-automated', 'cwa-ingest', 'cwa-auto-zipper', 'cwa-metadata-detector'],
                              ['abc'], ['/app/calibre-web-automated', '/config', '/calibre-library', '/cwa-book-ingest']),
    'odysseus': (['odysseus'], [], ['/opt/odysseus']),
}


def checked(native, argv):
    result = native.dispatch('pct', ['exec', str(native.owner.spec.ctid), '--', *argv])
    require(result.returncode == 0, 'consumer command failed: ' + repr(argv[:3]))
    return result.stdout.strip()


class CSRF(HTMLParser):
    def __init__(self, page):
        super().__init__()
        self.token = None
        self.feed(page)
        require(self.token, 'CSRF token missing')

    def handle_starttag(self, tag, attrs):
        row = dict(attrs)
        if tag == 'input' and row.get('name') == 'csrf_token':
            self.token = row.get('value')


def cwa_ingest(run, native, base):
    inputs = run.context.operation['inputs']
    choices = [i for i in inputs if i['path'].endswith('.epub')]
    require(len(choices) == 1, 'one admitted EPUB input required')
    book = Path(choices[0]['path'])
    require(os.environ.get('TEST_BOOK', str(book)) == str(book), 'TEST_BOOK not the admitted bytes')
    raw = book.read_bytes()
    require(sha(raw) == choices[0]['sha256'], 'selected book changed')
    with zipfile.ZipFile(io.BytesIO(raw)) as archive:
        container = ET.fromstring(archive.read('META-INF/container.xml'))
        package = next(e.attrib['full-path'] for e in container.iter() if e.tag.endswith('rootfile'))
        metadata = ET.fromstring(archive.read(package))
        title = next(e.text for e in metadata.iter() if e.tag.endswith('}title'))
    def session(label):
        jar = http.cookiejar.LWPCookieJar(str(run.directory / (label + '.cookies')))
        opener = urllib.request.build_opener(urllib.request.HTTPCookieProcessor(jar))
        page = opener.open(base + '/login', timeout=15).read().decode()
        payload = urllib.parse.urlencode(dict(csrf_token=CSRF(page).token, username='admin', password='admin123', remember_me='on', next='/')).encode()
        opener.open(base + '/login', payload, timeout=15).read()
        jar.save(ignore_discard=True)
        Path(jar.filename).chmod(0o600)
        return opener
    def count(opener):
        page = opener.open(base + '/', timeout=15).read().decode()
        match = re.search(r'Books\s*\((\d+)\)', page)
        require(match, 'authenticated Books count missing')
        return int(match[1]), page
    opener = session('upload')
    before, page = count(opener)
    boundary = 'su-' + uuid.uuid4().hex
    body = (f'--{boundary}\r\nContent-Disposition: form-data; name="csrf_token"\r\n\r\n{CSRF(page).token}\r\n'
            f'--{boundary}\r\nContent-Disposition: form-data; name="btn-upload"; filename="selected.epub"\r\nContent-Type: application/epub+zip\r\n\r\n').encode() + raw + f'\r\n--{boundary}--\r\n'.encode()
    request = urllib.request.Request(base + '/upload', body, {'Content-Type': 'multipart/form-data; boundary=' + boundary})
    with opener.open(request, timeout=30) as response:
        require(response.status == 200, 'upload not accepted')
        response.read()
    # Actual end consumer: library DB row + resulting EPUB bytes, not upload200.
    consumer = '''import hashlib,json,pathlib,sqlite3,sys
p=pathlib.Path('/calibre-library'); db=sqlite3.connect('file:'+str(p/'metadata.db')+'?mode=ro',uri=True)
rows=[]
for i,title,path,name in db.execute("select b.id,b.title,b.path,d.name from books b join data d on b.id=d.book where d.format='EPUB' and b.title=?",(sys.argv[1],)):
 f=p/path/(name+'.epub')
 if f.is_file():rows.append(dict(id=i,title=title,path=str(f),bytes=f.stat().st_size,sha256=hashlib.sha256(f.read_bytes()).hexdigest()))
print(json.dumps(rows))'''
    end = time.monotonic() + 180
    for attempt in range(90):
        after, _ = count(session('poll-' + str(attempt)))
        rows = json.loads(checked(native, ['python3', '-c', consumer, title]))
        if after > before and rows and all(r['bytes'] > 0 for r in rows):
            for row in rows:
                target = run.directory / ('consumed-' + str(row['id']) + '.epub')
                result = native.dispatch('pct', ['pull', str(native.owner.spec.ctid), row['path'], str(target)])
                require(result.returncode == 0 and target.stat().st_size == row['bytes']
                        and sha(target.read_bytes()) == row['sha256'], 'consumed EPUB evidence changed')
                target.chmod(0o600)
            snapshot = native.n['receiver_tmpdir'] + '/library-' + uuid.uuid4().hex + '.sqlite'
            checked(native, ['python3', '-c', 'import sqlite3,sys; a=sqlite3.connect("file:/calibre-library/metadata.db?mode=ro",uri=True); b=sqlite3.connect(sys.argv[1]); a.backup(b); b.close(); a.close()', snapshot])
            result = native.dispatch('pct', ['pull', str(native.owner.spec.ctid), snapshot, str(run.directory / 'library.sqlite')])
            require(result.returncode == 0, 'library DB evidence transfer failed')
            (run.directory / 'library.sqlite').chmod(0o600)
            checked(native, ['rm', '--', snapshot])
            run.record('cwa-ingest-consumer', dict(input=str(book), input_sha256=sha(raw), title=title, before=before, after=after, library=rows))
            print('CWA_INGEST_PASS', before, after, sha(raw), flush=True)
            return
        require(time.monotonic() < end, 'upload accepted but book count/ingest consumer unchanged')
        time.sleep(2)
    raise AdmissionError('ingest deadline exhausted')


def framework_env(run, native, url, socket):
    n, spec = native.n, native.owner.spec
    env = dict(PATH='/usr/local/go/bin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin', HOME=str(run.directory), TERM='xterm',
               TMPDIR=run.context.operation['tmpdir'], REPO_BASE=url, mode='default', PHS_SILENT='1', UNATTENDED='1',
               dev_mode='keep', SU_TEST_NATIVE_SOCKET=str(socket), SU_TEST_RUN_DIRECTORY=str(run.directory), PYTHONDONTWRITEBYTECODE='1')
    values = dict(ctid=spec.ctid, brg=n['bridge'], net='dhcp', mac=spec.mac, hostname=spec.hostname, tags=spec.tag,
                  cpu=n['cpu'], ram=n['ram'], disk=n['disk'], os='debian', version='13', unprivileged=1, nesting=1,
                  container_storage=n['storage'], template_storage=n['template_storage'], lxc_tmpdir=n['receiver_tmpdir'],
                  verbose='yes', gpu='no', timezone='UTC')
    env.update({'var_' + k: str(v) for k, v in values.items()})
    if run.context.operation['suite']=='odysseus':
        env['var_ns']=n['address']+' 1.1.1.1'
    return env


def app_consumers(run,native,suite):
    services, users, paths = CONSUMERS[suite]
    for service in services:
        require(checked(native, ['systemctl', 'is-active', service]) == 'active', 'service inactive')
        facts=dict(v.split('=',1) for v in checked(native,['systemctl','show',service,'-p','MainPID','-p','Type','-p','SubState','-p','ExecMainCode','-p','ExecMainStatus','-p','ExecMainStartTimestampMonotonic','-p','ExecMainExitTimestampMonotonic','-p','Environment','-p','EnvironmentFiles','-p','UnsetEnvironment']).splitlines())
        pid=facts['MainPID'];require(pid.isdigit(),'service MainPID invalid')
        if int(pid)>0:
            receiver = checked(native, ['python3', '-c', 'import pathlib,sys; e=pathlib.Path("/proc/"+sys.argv[1]+"/environ").read_bytes().split(b"\\0"); print(next((v.decode() for v in e if v.startswith(b"TMPDIR=")),""))', pid])
            require(receiver == 'TMPDIR=' + native.n['receiver_tmpdir'], 'service disk TMPDIR not inherited')
            proof='live-mainpid-environment'
        else:
            require(facts['SubState']=='exited' and facts['ExecMainCode']=='1' and facts['ExecMainStatus']=='0' and int(facts['ExecMainStartTimestampMonotonic'])>0 and int(facts['ExecMainExitTimestampMonotonic'])>=int(facts['ExecMainStartTimestampMonotonic']),'active-exited service execution not proven')
            require('TMPDIR' not in facts['UnsetEnvironment'] and not re.search(r'TMPDIR=(?!'+re.escape(native.n['receiver_tmpdir'])+r'(?: |$))',facts['Environment']),'explicit service TMPDIR override conflicts')
            require(list(run.directory.glob('*-static-service-consumer.json')),'active-exited service needs real static global policy proof')
            receiver=None;proof='active-exited-execution-plus-manager-policy; no-live-environment'
        run.record('app-service-consumer', dict(service=service, pid=pid, tmpdir=receiver,proof=proof,facts=facts,unit=checked(native, ['systemctl', 'cat', service])))
    for user in users:checked(native, ['id', user])
    for path in paths:checked(native, ['test', '-d', path])
    app_user = 'abc' if suite == 'calibre-web-automated' else (checked(native, ['systemctl','show','odysseus','-p','User','--value']) or 'root')
    checked(native, ['runuser','-u',app_user,'--','env','TMPDIR='+native.n['receiver_tmpdir'],'/bin/sh','-ec','f=$(mktemp "$TMPDIR/su-receiver-proof.XXXXXX"); test -f "$f"; rm -- "$f"'])
    run.record('receiving-temp-consumer',dict(user=app_user,path=native.n['receiver_tmpdir'],write_remove_status=0))
    upstream = checked(native, ['git', '-C', '/opt/odysseus', 'rev-parse', 'HEAD']) if suite == 'odysseus' else checked(native, ['cat', '/app/calibre-web-automated/CWA_RELEASE'])
    upstream_fact=dict(suite=suite,selected=upstream)
    if suite=='odysseus':
        source=Path(run.context.document['source']['path'])/'scripts/lxc/odysseus.sh'
        pins=re.findall(r'^var_lxc_pinned_commit="\$\{var_lxc_pinned_commit:-([a-f0-9]{7,40})\}"$',source.read_text(),re.M)
        require(len(pins)==1,'admitted Odysseus source pin ambiguous')
        resolved=checked(native,['git','-C','/opt/odysseus','rev-parse',pins[0]+'^{commit}'])
        require(re.fullmatch('[a-f0-9]{40}',resolved) and upstream==resolved,'installed Odysseus commit differs from admitted pin')
        upstream_fact.update(pin=pins[0],resolved=resolved)
    run.record('app-upstream',upstream_fact)
    addresses = checked(native, ['hostname', '-I']).split()
    import ipaddress
    network=bridge_network(native.n)
    ips = [ip for ip in addresses if ipaddress.ip_address(ip) in network]
    require(len(ips) == 1, 'container private address ambiguous')
    base = 'http://' + ips[0]
    with urllib.request.urlopen(base + '/', timeout=15) as response:require(200 <= response.status < 400, 'port80 HTTP consumer failed')
    if suite == 'calibre-web-automated':
        cwa_ingest(run, native, base)
        for service in ('calibre-web-automated', 'cwa-ingest'):
            logs = checked(native, ['journalctl', '-u', service, '--no-pager', '-n', '100'])
            require(not re.search(r'chown.*invalid user|Connection refused.*:8083|Calibre library path missing', logs), 'forbidden application log error')
    run.record('app-consumers', dict(suite=suite, services=services, users=users, paths=paths, http80=base, status=0))
    print('ODYSSEUS_CONSUMER_PASS' if suite == 'odysseus' else 'CWA_CONSUMER_PASS', flush=True)


def receiving_outcome(run,native):
    """Fresh installs must consume the sender's real log/flag runtime context."""
    contexts=[json.loads(p.read_text()) for p in run.directory.glob('*-receiving-request-context.json')]
    attach=[v for v in contexts if v['tool']=='lxc-attach']
    require(len(attach)==1,'one authenticated receiving installer context required')
    environment=attach[0]['environment'];sid=environment.get('SESSION_ID');log=environment.get('INSTALL_LOG')
    require(sid and log=='/root/.install-'+sid+'.log' and environment.get('CTID')==str(native.owner.spec.ctid),'fresh receiving sender/log binding missing')
    checked(native,['test','-s',log])
    flag='/root/.install-'+sid+'.failed';checked(native,['test','!','-e',flag])
    target=run.directory/'receiving-install.log'
    result=native.dispatch('pct',['pull',str(native.owner.spec.ctid),log,str(target)])
    require(result.returncode==0 and target.is_file() and target.stat().st_size>0,'actual receiving install log not preserved')
    target.chmod(0o600)
    run.record('receiving-install-outcome',dict(session=sid,path=log,flag=flag,failure_flag_absent=True,bytes=target.stat().st_size,sha256=sha(target.read_bytes()),context=environment))


def creation_package_consumers(run,native):
    """Use the normal created app for native repository and TLS consumers."""
    import tarfile
    result=native.dispatch('pct',['config',str(native.owner.spec.ctid)])
    require(result.returncode==0,'native create configuration query failed')
    servers=re.findall(r'^nameserver: (.+)$',result.stdout,re.M)
    require(len(servers)==1 and servers[0].split()==[native.n['address'],'1.1.1.1'],'native create DNS list not persisted')
    # DHCP may replace resolv.conf after PVE consumes the requested create settings.
    resolver=checked(native,['cat','/etc/resolv.conf'])
    run.record('native-create-dns-consumer',dict(nameservers=servers[0].split(),observed_config=result.stdout,guest_resolver=resolver))
    source=Path(run.context.document['source']['path'])
    archive=run.directory/'core-creation-subject.tar'
    files=['misc/core.func','misc/error_handler.func','misc/install.func','misc/tools.func','tests/lib/core-creation.native.sh']
    with tarfile.open(archive,'x') as tar:
        for name in files:tar.add(source/name,arcname=name,recursive=False)
    target=native.n['receiver_tmpdir']+'/core-creation-subject'
    checked(native,['mkdir','-m','0700','--',target])
    require(native.dispatch('pct',['push',str(native.owner.spec.ctid),str(archive),target+'/source.tar']).returncode==0,'core creation subject push')
    checked(native,['tar','-xf',target+'/source.tar','-C',target])
    result=native.dispatch('pct',['exec',str(native.owner.spec.ctid),'--','bash',target+'/tests/lib/core-creation.native.sh',target])
    run.record('core-creation-packages-consumer',dict(status=result.returncode,stdout=result.stdout,stderr=result.stderr))
    evidence=re.findall(r'^CORE_NATIVE_EVIDENCE (.+)$',result.stdout,re.M)
    require(len(evidence)==1 and re.fullmatch(re.escape(native.n['receiver_tmpdir'])+r'/core-native\.[a-zA-Z0-9]+\.evidence\.tar\.gz',evidence[0]),'core consumer evidence identity')
    saved=run.directory/'core-creation-native-evidence.tar.gz'
    require(native.dispatch('pct',['pull',str(native.owner.spec.ctid),evidence[0],str(saved)]).returncode==0,'core consumer evidence pull')
    saved.chmod(0o600)
    run.record('core-creation-native-evidence',dict(path=str(saved),bytes=saved.stat().st_size,sha256=sha(saved.read_bytes())))
    require(result.returncode==0 and 'CORE_CREATION_PACKAGES_NATIVE_PASS' in result.stdout,'native creation/packages consumer failed')
    print(result.stdout,end='',flush=True)


def main(suite,context=None):
    if context is None:context = admit_direct(suite, [])
    with Run(context) as run:
        native = NativePVE(run)
        status = 70
        try:
            with Publisher(run) as url, Broker(native) as sock:
                root = Path(context.document['source']['path'])
                target=root/'scripts/lxc'/(suite+'.sh')
                argv = ['/usr/bin/unshare', '--mount', '--propagation', 'private', '/bin/bash', str(root / 'tests/lib/native-launch.sh'),
                        str(root), '/bin/bash', str(target)]
                with (run.directory / 'install.log').open('x') as log:
                    status = native.child(argv,framework_env(run,native,url,sock),log)
                run.record('framework-stage-result',dict(status=status,phase='normal-framework',process_exit_explicit=True))
                status = status or (65 if native.refusals else 0)
                require(status == 0, 'framework install failed; inspect preserved log')
                receiving_outcome(run,native)
                app_consumers(run,native,suite)
                if suite=='odysseus':creation_package_consumers(run,native)
                status = 0
        except (AdmissionError, OSError, ValueError, subprocess.SubprocessError) as error:
            run.record('app-failure', dict(status=status or 70, error=str(error)))
            print(str(error), file=sys.stderr)
            status = status or 70
        if native.mount.active is not None and not native.mount.close_attempted:
            try:native.mount.close()
            except (AdmissionError,OSError,subprocess.SubprocessError) as error:
                run.record('mount-preservation-refused',dict(error=str(error)));status=status or 70
        # A's corrected failed-run STOP/PRESERVE versus successful retirement.
        return native.owner.finish(status)


if __name__ == '__main__':
    try:
        raise SystemExit(main(sys.argv[1]))
    except (AdmissionError, OSError) as error:
        print('CONTEXT_REFUSED:', error, file=sys.stderr)
        raise SystemExit(65)
