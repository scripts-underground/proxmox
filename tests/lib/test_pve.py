"""Guest-local PVE effect adapter. Existing outer VM access stays external.

One Run lock and NestedOwner hold authority. A private mount namespace shadows
native command paths, so framework PATH resets and timeout children cannot bypass
the typed boundary. The broker invokes original absolute paths OUTSIDE that
namespace. Context supplies facts, never commands. Recording tests inject only
the native subprocess boundary in source code.
"""
from dataclasses import asdict
from contextlib import ExitStack
from decimal import Decimal, InvalidOperation
import http.server
import ipaddress
import json
import os
from pathlib import Path
import re
import socketserver
import socket
import struct
import subprocess
import signal
import threading
import urllib.parse
import urllib.request

from test_context import (AdmissionError, Context, NestedOwner, Resource, Run,
                          absolute, fields, filesystem, load_json, query,
                          read_custody, require, safe_parents, sha)
from test_registry import execution_policy


def validate_native(n, op):
    fields(n, 'bridge address storage template_storage vg pool cpu ram disk template template_sha256 receiver_tmpdir budgets lineage')
    for key in ('bridge', 'storage', 'template_storage', 'vg', 'pool'):
        require(type(n[key]) is str and re.fullmatch('[A-Za-z0-9][A-Za-z0-9_-]{0,39}', n[key]), 'native topology identifier')
    require(len(n['bridge'])<=15,'native bridge interface name length')
    require(type(n['address']) is str,'native bridge address type')
    try:address=ipaddress.IPv4Address(n['address'])
    except ValueError as error:raise AdmissionError('native bridge address invalid') from error
    require(str(address)==n['address'] and address.is_private and not (address.is_loopback or address.is_link_local or address.is_multicast or address.is_unspecified), 'native private bridge address')
    require(len(op['nested']) == 1 and op['nested'][0]['storage'] == n['storage'], 'one explicit native resource required')
    spec=Resource(**op['nested'][0]);spec.validate()
    require(re.fullmatch(r'su-workflow-[a-f0-9]{32}',spec.tag), 'fresh unpredictable native creation token required')
    require(re.fullmatch(r'[a-z0-9](?:[a-z0-9-]{0,61}[a-z0-9])?',spec.hostname), 'native hostname label')
    require(re.fullmatch(r'(?:[a-f0-9]{2}:){5}[a-f0-9]{2}',spec.mac) and int(spec.mac[:2],16)&3==2, 'native locally administered unicast MAC')
    require(spec.volume==f'vm-{spec.ctid}-disk-0','native root volume name')
    for key in ('cpu','ram','disk'):
        require(type(n[key]) is int and 0 < n[key] < 2**31, 'native positive resource request')
    require(type(n['template']) is str and re.fullmatch(r'[A-Za-z0-9][A-Za-z0-9._+-]*\.tar\.(zst|xz|gz)',n['template'])
            and type(n['template_sha256']) is str and re.fullmatch('[a-f0-9]{64}',n['template_sha256']), 'native template identity')
    require(n['receiver_tmpdir'] == '/var/lib/scripts-underground-test/tmp', 'native receiver root')
    fields(n['budgets'], 'root_free workspace_peak thin_peak memory_peak')
    require(all(type(v) is int and v > 0 for v in n['budgets'].values()), 'native peak budget')
    require(n['lineage'] is None or type(n['lineage']) is str, 'native lineage reference')
    if n['lineage'] is not None:
        p = absolute(n['lineage'])
        require(p.is_relative_to(Path(op['runs'])), 'native lineage path scope')


def existing_lineage(context):
    op=context.operation;n=op['native'];spec=Resource(**op['nested'][0])
    require(n['lineage'] is not None,'existing creation lineage required')
    lineage=read_custody(absolute(n['lineage']))
    fields(lineage,'requested observed status source')
    require(type(lineage['status']) is int and lineage['status']==0 and lineage['requested']==asdict(spec)
            and lineage['source']==context.document['source']['tree_sha256'],'existing creation lineage mismatch')
    current=Resource(**lineage['observed']);current.validate()
    require(asdict(current)|{'volume_uuid':spec.volume_uuid}==asdict(spec),'existing requested identity mismatch')
    require(NativePVE.observe_static(spec.ctid,n)==current,'existing current native identity mismatch')
    admit_topology(n)
    return lineage


def publisher_receipt_path(context):
    # Immutable creation lineage and the current publisher have separate custody.
    return Path(context.operation['runs'])/(context.operation['run_id']+'.publisher.json')


def native_config_hash(ctid):
    return sha(Path(f'/etc/pve/lxc/{ctid}.conf').read_bytes())


def admit_scope(context, phase):
    """Read-only operation admission, before any Run/lock/listener/effect.

    Phase comes from the source execution policy/call site, never a context flag.
    Run's second absence/current check still closes races after this preflight.
    """
    op = context.operation
    rule=execution_policy(op['suite'],op['mode'])
    require(phase in (rule.public_phase,rule.direct_phase),'source workflow phase mismatch')
    require('native' in op, 'native scope facts absent')
    n = op['native']
    validate_native(n, op)
    if phase=='delegated':
        require(rule.direct_phase=='delegated','delegated scope mismatch')
        return
    if phase=='create':
        require(NativePVE.observe_static(op['nested'][0]['ctid'],n) is None,'native ID already present; cannot adopt')
        if rule.owner=='runtime':
            require(n['lineage'] is not None and not absolute(n['lineage']).exists(),'exclusive new runtime lineage path required')
        admit_resources(context)
    elif phase in ('existing','publisher','strong-browser'):
        existing_lineage(context)
        if phase=='publisher':
            publisher=read_custody(publisher_receipt_path(context))
            fields(publisher,'url source pid birth')
            url=urllib.parse.urlsplit(publisher['url'])
            require(url.scheme=='http' and url.hostname==n['address'] and url.port and not url.username and not url.password,'publisher bridge binding')
            require(publisher['source']==context.document['source']['tree_sha256'] and publisher['url']==os.environ.get('SU_TEST_REPO_BASE')
                    and os.environ.get('SU_TEST_CTID')==str(op['nested'][0]['ctid']),'bundle publisher/ID binding')
            require(Path('/proc/'+str(publisher['pid'])+'/stat').read_text().split()[21]==publisher['birth'],'publisher process identity')
    elif phase not in ('strong-public','strong-direct'):
        raise AdmissionError('native workflow phase absent')
    if op['suite'] == 'calibre-web-automated':
        books = [i for i in op['inputs'] if i['path'].endswith('.epub')]
        require(len(books) == 1 and os.environ.get('TEST_BOOK', books[0]['path']) == books[0]['path'], 'one exact admitted TEST_BOOK required before effects')
    if phase.startswith('strong-'):
        _,strong=strong_input(context)
        require(all(strong['topology'][k]==n[k] for k in ('bridge','storage','template_storage','vg','pool')),'strong/shared topology mismatch')
        f=strong['fixtures'].get(str(op['nested'][0]['ctid']))
        require(f is not None,'strong native fixture missing')
        if phase!='strong-browser':
            if f['lv_uuid'] is None:require(NativePVE.observe_static(op['nested'][0]['ctid'],n) is None,'strong fixture ID present without lineage')
            else:existing_lineage(context)
        if phase!='strong-direct':
            argv=globnotes_guard_argv(context)
            if op['suite']=='maintenance-globnotes-lxc' and op['mode']=='native-app':argv[-1]='all'
            result=subprocess.run(argv,env=dict(os.environ,SU_TEST_CONTEXT=str(context.path),SU_TEST_GUARD_ONLY='1'),capture_output=True,text=True,timeout=120)
            require(result.returncode==0,'original strong native protection refused: '+result.stderr)


def strong_input(context):
    matches = []
    for item in context.operation['inputs']:
        if item['path'].endswith('.json'):
            path = absolute(item['path'])
            data = read_custody(path)
            if type(data) is dict and set(data) == {'version','workspace','source','vm','protected','fixtures','topology'}:
                matches.append((path,data))
    require(len(matches) == 1, 'one admitted strong native manifest required')
    return matches[0]


def globnotes_guard_argv(context):
    path, data = strong_input(context)
    ctid = str(context.operation['nested'][0]['ctid'])
    require(ctid in data['fixtures'], 'strong native fixture not selected')
    return ['/bin/bash',str(Path(context.document['source']['path'])/'tests/maintenance-globnotes-lxc.test.sh'),
            '--native','--guard-manifest',str(path),'--ctid',ctid,'--origin','http://globnotes.home','--cdp','http://127.0.0.1:9335',
            '--evidence',str(Path(data['workspace'])/'artifacts'/('workflow-'+context.operation['run_id'])),'--stage','guard']


def admit_resources(context):
    n = context.operation['native']
    admit_topology(n)
    require(n['cpu'] <= (os.cpu_count() or 1),'native CPU envelope')
    require(n['budgets']['memory_peak'] >= n['ram']*1024**2 and n['budgets']['thin_peak'] >= n['disk']*1024**3,'native resource peak envelope')
    root = os.statvfs('/')
    workspace = os.statvfs(context.operation['runs'])
    require(root.f_bavail * root.f_frsize > n['budgets']['root_free'], 'native root peak admission')
    require(workspace.f_bavail * workspace.f_frsize > n['budgets']['workspace_peak'], 'native workspace peak admission')
    mem = dict(line.split(':', 1) for line in Path('/proc/meminfo').read_text().splitlines() if ':' in line)
    require(int(mem['MemAvailable'].split()[0]) * 1024 > n['budgets']['memory_peak'], 'native combined memory admission')
    template = Path(query(['/usr/sbin/pvesm', 'path', n['template_storage'] + ':vztmpl/' + n['template']]))
    require(not template.is_symlink() and sha(template.read_bytes()) == n['template_sha256'], 'admitted template changed')
    pool = load_json(query(['/usr/sbin/lvs','-a','--reportformat','json','--units','b','--nosuffix','-o','vg_name,lv_name,lv_size,pool_lv,origin,lv_attr,segtype,data_percent,metadata_percent']))['report'][0]['lv']
    rows = [r for r in pool if r['vg_name'] == n['vg'] and r['lv_name'] == n['pool']]
    require(len(rows) == 1 and float(rows[0]['metadata_percent']) < 80, 'native thin metadata admission')
    free = float(rows[0]['lv_size']) * (100 - float(rows[0]['data_percent'])) / 100
    require(free > n['budgets']['thin_peak'] + 2 * 1024**3, 'native thin peak plus reserve admission')
    # Logical allocations consume the envelope even when inactive, foreign or
    # snapshots with almost no mapped data. Physical free alone overcommits.
    allocated=[r for r in pool if r['vg_name']==n['vg'] and r['pool_lv']==n['pool']]
    try:
        sizes=[Decimal(r['lv_size']) for r in allocated]
        capacity=Decimal(rows[0]['lv_size'])
        require(capacity.is_finite() and all(v.is_finite() and v>=0 for v in sizes),'invalid thin allocation report')
        require(capacity-sum(sizes,Decimal(0)) >= n['disk']*1024**3+2*1024**3,'virtual thin capacity would overcommit root plus reserve')
    except (InvalidOperation,KeyError,TypeError) as error:
        raise AdmissionError('invalid thin allocation report') from error


def bridge_network(n):
    links=load_json(query(['/usr/sbin/ip','-j','-d','link','show','dev',n['bridge']]))
    require(len(links)==1 and links[0].get('linkinfo',{}).get('info_kind')=='bridge','declared native bridge unavailable')
    rows=load_json(query(['/usr/sbin/ip','-j','address','show','dev',n['bridge']]))
    addresses=[a for r in rows for a in r.get('addr_info',[]) if a.get('family')=='inet' and a.get('local')==n['address']]
    require(len(addresses)==1,'declared bridge address mismatch')
    interface=ipaddress.IPv4Interface(n['address']+'/'+str(addresses[0]['prefixlen']))
    require(interface.ip not in (interface.network.network_address,interface.network.broadcast_address),'native bridge host address required')
    return interface.network


def admit_topology(n):
    bridge_network(n)
    for storage,expected in [(n['storage'],dict(type='lvmthin',vgname=n['vg'],thinpool=n['pool'])),(n['template_storage'],dict(type='dir'))]:
        actual=load_json(query(['/usr/bin/pvesh','get','/storage/'+storage,'--output-format','json']))
        require(actual.get('storage')==storage and not actual.get('disable',0) and all(actual.get(k)==v for k,v in expected.items()),'declared PVE storage configuration mismatch')
        require(('rootdir' if storage==n['storage'] else 'vztmpl') in actual.get('content','').split(','),'declared storage content mismatch')


class NativePVE:
    PROGRAMS = {'pct': '/usr/sbin/pct', 'pvesm': '/usr/sbin/pvesm',
                'pveam': '/usr/bin/pveam', 'lxc-attach': '/usr/bin/lxc-attach'}

    def __init__(self, run, call=None):
        self.run = run
        self.n = run.context.operation['native']
        self.call = call or self._process
        self.owner = NestedOwner(run, Resource(**run.context.operation['nested'][0]), self)
        self.create_args = None
        self.refusals = 0
        from mounted_root import MountedRoot
        self.mount=MountedRoot(self)

    def child(self,argv,env,log,seconds=None,stderr=None):
        """Bind birth before releasing a finite source-owned private-ns child."""
        reader,writer=os.pipe()
        gate='import os,sys;fd=int(sys.argv[1]);token=os.read(fd,6);os.close(fd);assert token==b"ready\\n";os.execvpe(sys.argv[2],sys.argv[2:],os.environ)'
        child=subprocess.Popen(['/usr/bin/python3','-B','-c',gate,str(reader),*argv],env=env,cwd=self.run.context.document['source']['path'],stdout=log,stderr=stderr if stderr is not None else subprocess.STDOUT,stdin=subprocess.DEVNULL,pass_fds=(reader,),start_new_session=True)
        os.close(reader)
        try:
            self.mount.bind_consumer(child.pid)
            self.run.record('framework-child',dict(pid=child.pid,birth=self.mount.consumer['birth'],argv=argv,cgroup=Path('/proc/'+str(child.pid)+'/cgroup').read_text()))
            os.write(writer,b'ready\n')
        finally:os.close(writer)
        try:return child.wait(timeout=seconds or self.run.context.operation['deadline'])
        except subprocess.TimeoutExpired:
            os.killpg(child.pid,signal.SIGTERM)
            child.wait(timeout=10)
            return 124

    def _process(self, tool, args):
        # This object/broker stays outside the command-shadow mount namespace.
        result = subprocess.run([self.PROGRAMS[tool], *args], capture_output=True, text=True,
                                timeout=min({'shutdown':150,'status':20,'destroy':120}.get(args[0] if args else '',self.run.context.operation['deadline']),self.run.context.operation['deadline']),
                                umask=0o022,
                                env=dict(os.environ, TMPDIR=self.run.context.operation['tmpdir']))
        self.run.record('native-result', dict(tool=tool, argv=args, status=result.returncode,
                                            stdout=result.stdout, stderr=result.stderr))
        if tool == 'pct' and args[:1] == ['create']:
            p = Path('/etc/pve/lxc/' + args[1] + '.conf')
            config = p.read_text() if p.exists() else None
            volumes = query(['/usr/sbin/lvs','--reportformat','json','-o','vg_name,lv_name,lv_uuid'])
            self.run.record('native-create-config', dict(status=result.returncode, config=config, volumes=load_json(volumes)))
        return result

    @staticmethod
    def observe_static(ctid, n):
        config_path = Path(f'/etc/pve/lxc/{ctid}.conf')
        require(not Path(f'/etc/pve/qemu-server/{ctid}.conf').exists(), 'nested ID belongs to a VM')
        require(not config_path.is_symlink(), 'native config symlink')
        volumes = load_json(query(['/usr/sbin/lvs', '--reportformat', 'json', '-o', 'vg_name,lv_name,lv_uuid']))['report'][0]['lv']
        matches = [r for r in volumes if r['vg_name'] == n['vg'] and r['lv_name'] == f'vm-{ctid}-disk-0']
        same_id = [r for r in volumes if re.fullmatch(r'vm-' + str(ctid) + r'-disk-\d+',r['lv_name'])]
        if not config_path.exists():
            require(not same_id, 'unowned root volume without config')
            return None
        require(len(matches) == len(same_id) == 1, 'unknown native root volume')
        config = dict(line.split(': ', 1) for line in config_path.read_text().splitlines() if ': ' in line and not line.startswith('#'))
        net = dict(p.split('=', 1) for p in config.get('net0', '').split(',') if '=' in p)
        require(net.get('bridge') == n['bridge'] and config.get('unprivileged') == '1'
                and config.get('cores') == str(n['cpu']) and config.get('memory') == str(n['ram'])
                and 'nesting=1' in config.get('features', '').split(','), 'native config resources changed')
        root = config.get('rootfs', '').split(',')[0]
        require(root == f'{n["storage"]}:vm-{ctid}-disk-0', 'native root storage changed')
        tags = config.get('tags', '').replace(',', ';').split(';')
        tags = [t for t in tags if t.startswith('su-workflow-')]
        require(len(tags) == 1, 'native creation tag missing/ambiguous')
        return Resource(ctid, tags[0], net.get('hwaddr', '').lower(), config.get('hostname', ''),
                        n['storage'], f'vm-{ctid}-disk-0', matches[0]['lv_uuid'])

    def observe(self, ctid):
        return self.observe_static(ctid, self.n)

    def evidence_identity(self,spec):
        require(self.observe(spec.ctid)==spec,'preservation current native identity mismatch')
        state=query(['/usr/sbin/pct','status',str(spec.ctid)])
        require(state=='status: stopped','preservation/finalize requires stopped resource')
        config=Path(f'/etc/pve/lxc/{spec.ctid}.conf').read_text()
        return dict(config_sha256=sha(config.encode()),config=config,state=state,volume_uuid=spec.volume_uuid)

    def receiving_argv(self,argv,environment=None):
        # pct/lxc-attach may supply no login environment. Root receiver facts,
        # not the outer run HOME/credentials; explicit child env overrides stay
        # later in argv and retain the consumer's intentional scope.
        from receiving_context import validate
        runtime=validate({} if environment is None else environment,self.run.context,self.owner.spec.ctid)
        return ['env','-i','HOME=/root','PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin',
                'TMPDIR='+self.n['receiver_tmpdir'],*[k+'='+runtime[k] for k in sorted(runtime)],*argv]

    def prepare_receiver(self):
        """Start's receiving postcondition, before framework packages/services.

        PID1-started services do not inherit pct exec's environment. Keep this
        at the common typed start boundary for app and runtime consumers.
        """
        self.owner.checked()
        self.verify_service_policy()
        body = '''umask 022
for d in /var /var/lib /var/lib/scripts-underground-test; do
  test ! -L "$d"
  if test -e "$d"; then
    test -d "$d"; test "$(stat -c %u "$d")" = 0
    m=$(stat -c %a "$d"); test "$((0$m & 022))" = 0
  else mkdir -m 0755 -- "$d"; fi
done
test ! -L "$1"
if test ! -e "$1"; then mkdir -m 1777 -- "$1"; fi
test -d "$1"; test "$(stat -c %u "$1")" = 0
test "$(stat -c %a "$1")" = 1777
fs=$(stat -f -c %T "$1"); test "$fs" != tmpfs; test "$fs" != ramfs
runuser -u nobody -- env TMPDIR="$1" sh -ec 'f=$(mktemp "$TMPDIR/receiver-proof.XXXXXX"); test -f "$f"; rm -- "$f"'
systemctl show-environment | grep -Fx "TMPDIR=$1"
'''
        args=['exec',str(self.owner.spec.ctid),'--',*self.receiving_argv(['/bin/sh','-ec',body,'--',self.n['receiver_tmpdir']])]
        result=self.call('pct',args)
        require(result.returncode==0,'native start receiver preparation failed')
        self.owner.checked()

    def prepare_service_policy(self):
        from receiver_service import prepare
        prepare(self)

    def verify_service_policy(self):
        from receiver_service import verify_live
        return verify_live(self)

    @staticmethod
    def options(args):
        require(len(args) % 2 == 0, 'native option pairs required')
        options = {}
        for key, value in zip(args[::2], args[1::2]):
            require(key.startswith('-') and key.lstrip('-') not in options, 'duplicate/invalid native option')
            options[key.lstrip('-')] = value
        return options

    def check_create(self, args):
        spec, n = self.owner.spec, self.n
        require(len(args) >= 3 and args[:2] == ['create', str(spec.ctid)], 'native create ID mismatch')
        require(args[2] == n['template_storage'] + ':vztmpl/' + n['template'], 'native template storage mismatch')
        o = self.options(args[3:])
        expected = dict(hostname=spec.hostname, cores=str(n['cpu']), memory=str(n['ram']),
                        unprivileged='1', rootfs=n['storage'] + ':' + str(n['disk']), onboot='1')
        require(all(o.get(k) == v for k, v in expected.items()), 'native create resources mismatch')
        require(set(o) <= set(expected) | {'tags', 'features', 'net0', 'timezone', 'ostype', 'nameserver', 'arch'}, 'native create unknown option')
        require(set(o.get('tags', '').replace(';', ',').split(',')) == {'community-script', spec.tag}, 'native create tag mismatch')
        require(set(o.get('features', '').split(',')) == {'nesting=1', 'keyctl=1'}, 'native create features mismatch')
        net = self.options_net(o.get('net0', ''))
        require(net.get('bridge') == n['bridge'] and net.get('ip') == 'dhcp'
                and net.get('hwaddr', '').lower() == spec.mac.lower() and net.get('name') == 'eth0', 'native create network mismatch')
        require(set(net) <= {'name', 'bridge', 'ip', 'hwaddr', 'type', 'ip6', 'firewall'}, 'native create network extras')
        require(net.get('ip6', 'manual') in ('manual', 'dhcp') and net.get('type', 'veth') == 'veth', 'native create network type')

    @staticmethod
    def options_net(value):
        pairs = value.split(',')
        require(all('=' in p for p in pairs), 'network option shape')
        result = dict(p.split('=', 1) for p in pairs)
        require(len(result) == len(pairs), 'duplicate network option')
        return result

    def invoke(self, action, spec, args=()):
        require(self.mount.active is None and not self.mount.unverified and self.mount.mounted() is None,'owned mount must be verified unmounted before lifecycle effects')
        if action=='destroy':self.owner.verify_preservation()
        if action == 'create':
            require(self.create_args is not None, 'framework create argv required')
            self.check_create(self.create_args)
            return self.call('pct', self.create_args).returncode
        argv = [action, str(spec.ctid), *args]
        if action == 'stop':
            argv=['shutdown',str(spec.ctid),'--timeout','120','--forceStop','0']
        if action == 'exec':
            argv = ['exec', str(spec.ctid), '--', *self.receiving_argv(args)]
        try:
            result = self.call('pct', argv)
            if action == 'stop' and result.returncode == 0:
                state = self.call('pct', ['status', str(spec.ctid)])
                require(state.returncode == 0 and state.stdout.strip() == 'status: stopped', 'stop state not proven')
                require(self.observe(spec.ctid)==spec,'native identity changed while stopping')
                retained=self.call('pct',['set',str(spec.ctid),'--onboot','0'])
                require(retained.returncode==0,'safe stopped retention onboot0 failed')
        except subprocess.TimeoutExpired as error:
            if action!='stop':raise
            self.run.record('shutdown-timeout',dict(argv=error.cmd,requested_shutdown=argv,seconds=error.timeout,status=124,identity=asdict(spec)))
            return 124
        if action == 'destroy' and result.returncode == 0:
            require(self.observe(spec.ctid) is None, 'config/root volume removal not proven')
        return result.returncode

    def dispatch(self, tool, args, peer=None,environment=None):
        self.run.context.recheck()
        require(tool in self.PROGRAMS and type(args) is list and all(type(a) is str and '\x00' not in a for a in args), 'native typed argv')
        try:
            require(args, 'native action missing')
            from receiving_context import validate
            runtime=validate({} if environment is None else environment,self.run.context,self.owner.spec.ctid)
            receiving=tool=='lxc-attach' or (tool=='pct' and args[0]=='exec')
            require(receiving or not runtime,'runtime data only permitted for receiving commands')
            if receiving and peer is not None:
                consumer=self.mount.peer(peer)
                self.run.record('receiving-request-context',dict(tool=tool,target=self.owner.spec.ctid,consumer=consumer,environment=runtime))
            if tool in ('pvesm', 'pveam'):
                self.storage(tool, args)
                return self.call(tool, args)
            if tool == 'lxc-attach':
                require(args[:3] == ['-n', str(self.owner.spec.ctid), '--'] and len(args) > 3, 'attach target mismatch')
                self.owner.checked()
                return self.call(tool, args[:3] + self.receiving_argv(args[3:],runtime))
            action = args[0]
            if action == 'list':
                require(args == ['list'], 'list arguments')
                return self.call(tool, args)
            require(len(args) >= 2 and args[1] == str(self.owner.spec.ctid), 'native target ID mismatch')
            if action == 'create':
                self.check_create(args)
                self.create_args = args
                rc = self.owner.create()
                return subprocess.CompletedProcess(args, rc, '', '')
            if action in ('status', 'config') and self.owner.creation is None:
                require(self.observe(self.owner.spec.ctid) is None, 'precreation resource appeared')
                return self.call(tool, args)
            self.owner.checked()
            if action=='stop':
                require(args==['stop',str(self.owner.spec.ctid)],'framework stop arguments')
                return subprocess.CompletedProcess(args,self.invoke('stop',self.owner.current),'','')
            if action in ('mount','unmount'):
                require(args==[action,str(self.owner.spec.ctid)],'owned mount arguments')
                return self.mount.open(peer) if action=='mount' else self.mount.close(peer)
            if action in ('start','exec','push','pull'):
                require(self.mount.active is None and not self.mount.unverified and self.mount.mounted() is None,'root mount must be verified unmounted before start/receiver effects')
            # Framework error handling never owns retirement. Even a swallowed
            # refusal marks the whole consumer failed, retaining A's failure path.
            require(action in ('status', 'config', 'start', 'exec', 'push', 'pull', 'set'), 'framework lifecycle action not authorized')
            if action == 'set':
                options = self.options(args[2:])
                require(set(options) <= {'description', 'onboot'} and options.get('onboot', '0') == '0', 'native set changes ownership/resources')
            if action == 'exec':
                command=3 if args[2:3]==['--'] else 2
                require(len(args)>command and not args[command].startswith('-'),'native exec command missing/unsupported option')
                args = args[:2] + ['--'] + self.receiving_argv(args[command:],runtime)
            if action in ('push', 'pull'):
                require(len(args) == 4, 'file transport argv shape')
                host = absolute(args[2] if action == 'push' else args[3])
                require(host.is_relative_to(Path(self.run.context.operation['tmpdir'])) or host.is_relative_to(self.run.directory)
                        or str(host) == self.n['lineage'], 'transport host path scope')
            if action == 'start':self.prepare_service_policy()
            result = self.call(tool, args)
            if action == 'start' and result.returncode == 0:
                self.prepare_receiver()
            return result
        except (AdmissionError, OSError) as error:
            self.refusals += 1
            self.run.record('native-refusal', dict(tool=tool, argv=args, reason=str(error)))
            raise

    def storage(self, tool, args):
        action = args[0]
        if tool == 'pvesm':
            if action == 'status':
                require(args == ['status'] or args[1:] in (['-content', 'rootdir'], ['-content', 'vztmpl'], ['-storage', self.n['storage']]), 'storage status scope')
            elif action == 'list':
                require(args == ['list', self.n['template_storage'], '--content', 'vztmpl'], 'storage activation/fallback refused')
            elif action == 'path':
                require(args == ['path', self.n['template_storage'] + ':vztmpl/' + self.n['template']], 'storage path scope')
            else:
                raise AdmissionError('storage mutation not admitted')
        else:
            require(args in (['list', self.n['template_storage']], ['available', '-section', 'system']), 'catalogue/download mutation not admitted')


class Broker:
    def __init__(self, native):
        self.native = native

    def __enter__(self):
        native = self.native
        class Handler(socketserver.StreamRequestHandler):
            def handle(self):
                try:
                    pid, uid, _ = struct.unpack('3i', self.request.getsockopt(socket.SOL_SOCKET, socket.SO_PEERCRED, 12))
                    require(uid == 0, 'native broker requires guest root peer')
                    request = load_json(self.rfile.readline(1024 * 1024).decode())
                    fields(request, 'tool argv environment')
                    require(type(request['environment']) is dict,'receiving request environment type')
                    result = native.dispatch(request['tool'], request['argv'],peer=pid,environment=request['environment'])
                    data = dict(status=result.returncode, stdout=result.stdout, stderr=result.stderr)
                except (AdmissionError, OSError, subprocess.SubprocessError) as error:
                    data = dict(status=65, stdout='', stderr='NATIVE_REFUSED: ' + str(error))
                self.wfile.write(json.dumps(data).encode() + b'\n')
        # Linux abstract socket avoids AF_UNIX's108-byte pathname limit without
        # creating RAM scratch or changing the disk-backed run directory.
        self.path = '@su-workflow-' + sha(str(native.run.directory).encode())[:24]
        self.server = socketserver.UnixStreamServer('\0' + self.path[1:], Handler)
        c=native.run.context
        native.run.record('broker-channel',dict(schema=1,run=str(native.run.directory),socket=self.path,pid=native.mount.pid,birth=native.mount.birth,namespace=native.mount.namespace,
                          context_sha256=sha(c.path.read_bytes()),source=c.document['source']['tree_sha256'],resource=asdict(native.owner.current) if native.owner.current else None))
        self.thread = threading.Thread(target=self.server.serve_forever, daemon=True)
        self.thread.start()
        return self.path

    def __exit__(self, *unused):
        self.server.shutdown()
        self.server.server_close()
        self.thread.join(timeout=5)


class Publisher:
    """Read-only in-memory public projection; never exposes Git/private scratch."""
    def __init__(self, run):
        self.run = run

    def __enter__(self):
        self.run.context.recheck()
        source = self.run.context.document['source']
        root = Path(source['path'])
        public = {}
        for row in source['files']:
            require(row['kind'] == 'file', 'public projection does not follow symlinks')
            raw = (root / row['path']).read_bytes()
            require(sha(raw) == row['sha256'], 'publisher source hash')
            public['/' + row['path']] = raw
        public['/__source_manifest.json'] = json.dumps(source['files'], sort_keys=True).encode()
        class Handler(http.server.BaseHTTPRequestHandler):
            def do_GET(self):
                raw = public.get(urllib.parse.urlsplit(self.path).path)
                if raw is None:
                    self.send_error(404)
                    return
                self.send_response(200)
                self.send_header('Content-Length', str(len(raw)))
                self.end_headers()
                self.wfile.write(raw)
            def log_message(self, *args):
                pass
        self.server = http.server.ThreadingHTTPServer((self.run.context.operation['native']['address'], 0), Handler)
        self.thread = threading.Thread(target=self.server.serve_forever, daemon=True)
        self.thread.start()
        self.url = 'http://%s:%d' % self.server.server_address
        self.run.record('publisher', dict(url=self.url, pid=os.getpid(), birth=Path('/proc/self/stat').read_text().split()[21],
                                          argv=Path('/proc/self/cmdline').read_bytes().decode().split('\0'), source=source['tree_sha256']))
        with urllib.request.urlopen(self.url + '/__source_manifest.json', timeout=5) as response:
            require(response.read() == public['/__source_manifest.json'], 'served manifest mismatch')
        for name in ('misc/core.func', 'misc/bootstrap/lxc'):
            with urllib.request.urlopen(self.url + '/' + name, timeout=5) as response:
                require(sha(response.read()) == sha(public['/' + name]), 'served framework bytes mismatch')
        return self.url

    def __exit__(self, *unused):
        self.server.shutdown()
        self.server.server_close()
        self.thread.join(timeout=5)
        self.run.record('publisher-retired', dict(url=self.url))


def admit_delegated(context_path, suite, mode):
    """A sealed delegation binds actual CT namespaces/root/source, not CT DMI."""
    require(execution_policy(suite,mode).direct_phase=='delegated','delegation not permitted for this source consumer')
    require(os.environ.get('SU_TEST_DELEGATION'),'checked nested delegation required')
    path = absolute(os.environ['SU_TEST_DELEGATION'])
    d = read_custody(path)
    fields(d, 'schema context_sha256 suite mode resource namespaces root source')
    require(d['schema'] == 1 and d['suite'] == suite and d['mode'] == mode, 'delegated scope')
    context_path = absolute(str(context_path))
    original = read_custody(context_path)
    require(sha(context_path.read_bytes()) == d['context_sha256'], 'delegated context hash')
    require(d['namespaces'] == {name: os.readlink('/proc/self/ns/' + name) for name in ('mnt', 'pid', 'user')}, 'delegated namespace mismatch')
    s = Path('/').stat()
    require(d['root'] == [s.st_dev, s.st_ino], 'delegated root mismatch')
    from test_context import source_files
    source = original['source']
    require(d['source'] == source['tree_sha256'] and source_files(Path(source['path'])) == source['files'], 'delegated source mismatch')
    require(sha(Path(source['history']).read_bytes())==source['history_sha256'],'delegated public history mismatch')
    op = next((o for o in original['operations'] if (o['suite'], o['mode']) == (suite, mode)), None)
    require(op is not None and d['resource'] in op['nested'], 'delegated resource lineage')
    validate_native(op['native'],op)
    require(op['native']['lineage'] is not None, 'delegated creation lineage absent')
    lineage = read_custody(absolute(op['native']['lineage']))
    fields(lineage, 'requested observed status source')
    require(type(lineage['status']) is int and lineage['status'] == 0 and lineage['requested'] == d['resource']
            and lineage['source'] == d['source'], 'delegated immutable creation lineage')
    require(os.environ.get('TMPDIR') == op['native']['receiver_tmpdir'], 'delegated TMPDIR mismatch')
    return Context(original, context_path, op)


def record_runtime_inputs(run,native):
    from app_driver import checked
    facts=checked(native,['/bin/sh','-ec','dpkg-query -W; printf "\\nRECEIVER\\n"; stat -c "%a %U:%G %n" "$1"; df -B1 /; systemctl show-environment; printf "\\nAPT INPUTS\\n"; for f in /etc/apt/sources.list /etc/apt/sources.list.d/*.sources /etc/apt/sources.list.d/*.list; do if test -f "$f"; then printf "INPUT %s\\n" "$f"; cat "$f"; fi; done','--',native.n['receiver_tmpdir']])
    run.record('runtime-system-inputs',dict(facts=facts))


def runtime_dispatch(context, argv):
    """Outer checked owner -> typed exec -> sealed inner namespace/root guard.

    The generic runtime CT is used only for live/setup/bundle fixtures, never a
    full RomM installation. Installed probes require existing trusted lineage.
    """
    from test_context import exclusive_json
    from app_driver import checked
    import tarfile
    rule=execution_policy(context.operation['suite'],context.operation['mode'])
    require(rule.owner=='runtime','runtime execution owner mismatch')
    admit_scope(context,rule.public_phase)
    n = context.operation['native']
    with Run(context) as run, ExitStack() as services:
        native = NativePVE(run)
        status = 70
        try:
            url=services.enter_context(Publisher(run))
            spec = native.owner.spec
            require(native.observe(spec.ctid) is None, 'runtime fixture already exists')
            create = ['create', str(spec.ctid), n['template_storage'] + ':vztmpl/' + n['template'],
                      '-hostname', spec.hostname, '-tags', 'community-script,' + spec.tag,
                      '-features', 'nesting=1,keyctl=1', '-net0', f'name=eth0,bridge={n["bridge"]},ip=dhcp,hwaddr={spec.mac}',
                      '-onboot', '1', '-cores', str(n['cpu']), '-memory', str(n['ram']),
                      '-unprivileged', '1', '-rootfs', n['storage'] + ':' + str(n['disk'])]
            result = native.dispatch('pct', create)
            require(result.returncode == 0, 'generic runtime creation failed')
            require(native.dispatch('pct', ['start', str(spec.ctid)]).returncode == 0, 'generic runtime start failed')
            # Typed start established receiver scratch and PID1 TMPDIR before
            # returning; normal apps and runtime fixtures share that owner.
            checked(native, ['/bin/sh', '-ec', 'export DEBIAN_FRONTEND=noninteractive; apt update; apt install -y bash curl ca-certificates python3 git jq xz-utils unzip'])
            source = context.document['source']
            archive = run.directory / 'source.tar'
            with tarfile.open(archive, 'x') as tar:
                for row in source['files']:
                    tar.add(Path(source['path']) / row['path'], arcname=row['path'], recursive=False)
            checked(native, ['/bin/sh', '-ec', 'umask 022; mkdir -p "$1" "$2" "$3"', '--', source['path'], str(context.path.parent), str(Path(n['lineage']).parent)])
            for host, target in [(archive, n['receiver_tmpdir'] + '/source.tar'), (context.path, str(context.path)),(Path(source['history']),source['history'])]:
                # Copy custody files into the run's private transport scope.
                stage = run.directory / ('transfer-' + host.name)
                stage.write_bytes(host.read_bytes())
                result = native.dispatch('pct', ['push', str(spec.ctid), str(stage), target])
                require(result.returncode == 0, 'runtime source/context push failed')
            checked(native, ['/bin/tar', '-xf', n['receiver_tmpdir'] + '/source.tar', '-C', source['path']])
            observed = native.owner.current
            lineage = dict(requested=asdict(spec), observed=asdict(observed), status=0, source=source['tree_sha256'])
            lineage_file = absolute(n['lineage'])
            safe_parents(lineage_file.parent, root=True)
            exclusive_json(lineage_file, lineage)
            require(native.dispatch('pct', ['push', str(spec.ctid), str(lineage_file), str(lineage_file)]).returncode == 0, 'lineage publication')
            if rule.direct_phase == 'publisher':
                with Broker(native) as sock:
                    exclusive_json(publisher_receipt_path(context), dict(url=url, source=source['tree_sha256'], pid=os.getpid(), birth=Path('/proc/self/stat').read_text().split()[21]))
                    root = Path(source['path'])
                    env = dict(os.environ, SU_TEST_CONTEXT=str(context.path), SU_TEST_CTID=str(spec.ctid), SU_TEST_REPO_BASE=url,
                               SU_TEST_NATIVE_SOCKET=str(sock), TMPDIR=context.operation['tmpdir'], HOME=str(run.directory), PYTHONDONTWRITEBYTECODE='1')
                    command=['/usr/bin/unshare','--mount','--propagation','private','/bin/bash',str(root/'tests/lib/native-launch.sh'),str(root),*argv]
                    with (run.directory/'bundle.stdout').open('x') as out,(run.directory/'bundle.stderr').open('x') as err:
                        rc=native.child(command,env,out,stderr=err)
                    result=subprocess.CompletedProcess(command,rc,(run.directory/'bundle.stdout').read_text(),(run.directory/'bundle.stderr').read_text())
                    run.record('bundle-consumer', dict(status=result.returncode, stdout=result.stdout, stderr=result.stderr))
                    status = result.returncode or (65 if native.refusals else 0)
                    run.record('runtime-consumer',dict(suite=context.operation['suite'],mode=context.operation['mode'],status=status,identity=asdict(native.owner.current),stdout=result.stdout,stderr=result.stderr))
                    record_runtime_inputs(run,native)
                    print(result.stdout, end='')
                return native.owner.finish(status)
            pid = int(query(['/usr/bin/lxc-info', '-n', str(spec.ctid), '-pH']))
            root_stat = Path(f'/proc/{pid}/root').stat()
            delegation = dict(schema=1, context_sha256=sha(context.path.read_bytes()), suite=context.operation['suite'], mode=context.operation['mode'],
                              resource=asdict(spec), namespaces={name: os.readlink(f'/proc/{pid}/ns/{name}') for name in ('mnt', 'pid', 'user')},
                              root=[root_stat.st_dev, root_stat.st_ino], source=source['tree_sha256'])
            delegated = run.directory / 'delegation.json'
            exclusive_json(delegated, delegation)
            destination = str(context.path.parent / 'delegation.json')
            require(native.dispatch('pct', ['push', str(spec.ctid), str(delegated), destination]).returncode == 0, 'delegation publication')
            checked(native, ['/bin/chmod', '0444', str(context.path), str(lineage_file), destination])
            if context.operation['suite'] == 'romm-player-serving' and context.operation['mode'] == 'live-runtime':
                setup = next((op for op in context.document['operations'] if (op['suite'],op['mode']) == ('romm-player-serving','setup')),None)
                require(setup is not None and setup['native'] == n and setup['nested'] == context.operation['nested'], 'player setup must be separately admitted for this exact runtime fixture')
                setup_path = run.directory/'setup-delegation.json'
                exclusive_json(setup_path,dict(delegation,mode='setup'))
                setup_destination = str(context.path.parent/'setup-delegation.json')
                require(native.dispatch('pct',['push',str(spec.ctid),str(setup_path),setup_destination]).returncode == 0,'setup delegation publication')
                checked(native,['chmod','0444',setup_destination])
                result = native.dispatch('pct',['exec',str(spec.ctid),'--','env','SU_TEST_CONTEXT='+str(context.path),
                                               'SU_TEST_DELEGATION='+setup_destination,'TMPDIR='+n['receiver_tmpdir'],'PYTHONDONTWRITEBYTECODE=1',*argv,'--setup'])
                run.record('runtime-setup-consumer',dict(status=result.returncode,stdout=result.stdout,stderr=result.stderr))
                require(result.returncode == 0,'owned player setup failed')
            # Original setup/live assertions execute inside the owned CT. Every
            # mutable runtime/profile/cache/completion/application root is local
            # to that fixture's root volume, not the outer PVE node.
            env = ['env', 'SU_TEST_CONTEXT=' + str(context.path), 'SU_TEST_DELEGATION=' + destination,
                   'TMPDIR=' + n['receiver_tmpdir'], 'REPO_BASE='+url,'PYTHONDONTWRITEBYTECODE=1', *argv]
            result = native.dispatch('pct', ['exec', str(spec.ctid), '--', *env])
            status = result.returncode or (65 if native.refusals else 0)
            run.record('runtime-consumer',dict(suite=context.operation['suite'],mode=context.operation['mode'],status=status,identity=asdict(native.owner.current),stdout=result.stdout,stderr=result.stderr))
            record_runtime_inputs(run,native)
            print(result.stdout, end='')
            print(result.stderr, end='', file=__import__('sys').stderr)
        except (AdmissionError, OSError, ValueError, subprocess.SubprocessError) as error:
            status=status or 70
            run.record('runtime-failure', dict(error=str(error), status=status))
        return native.owner.finish(status)


def pending_owner(context,name):
    """Read-only existing-run admission, not ownership adoption or recreation."""
    require(execution_policy(context.operation['suite'],context.operation['mode']).public_phase=='create','selected consumer cannot finalize a native creation')
    require(re.fullmatch(re.escape(context.operation['run_id'])+r'-[a-f0-9]{32}',name),'finalize run identity')
    root=absolute(context.operation['runs'])/name;safe_parents(root,root=True)
    paths=list(root.glob('preservation-pending-*.json'));require(len(paths)==1,'pending receipt ambiguous')
    p=read_custody(paths[0]);fields(p,'schema created_ns binding evidence')
    binding=p['binding'];run=Run(context,existing=root);run.directory=root
    native=NativePVE(run)
    require(binding['creation']['requested']==context.operation['nested'][0],'pending requested creation mismatch')
    native.owner.creation=binding['creation'];native.owner.current=Resource(**binding['resource']);native.owner.pending=paths[0]
    native.owner.checked()
    require(binding['source']==context.document['source']['tree_sha256'] and binding['context_sha256']==sha(context.path.read_bytes())
            and binding['current']==native.evidence_identity(native.owner.current),'pending source/config/current identity mismatch')
    return run,native


def finalize_runtime(context,name):
    run,native=pending_owner(context,name)
    native.owner.verify_preservation(record=False)  # before Run/lock effects
    with run:
        return native.owner.finish(0)


def runtime_status(context,name):
    root=absolute(context.operation['runs'])
    require(name==context.operation['run_id'] or re.fullmatch(re.escape(context.operation['run_id'])+r'-[a-f0-9]{32}',name),'status run scope')
    roots=[p for p in root.glob(context.operation['run_id']+'-*') if p.is_dir()] if name==context.operation['run_id'] else [root/name]
    results=[]
    for directory in roots:
        safe_parents(directory,root=True)
        selected={}
        for label in ('runtime-consumer','cleanup-result','preservation-state','runtime-failure','terminal'):
            paths=sorted(directory.glob('*-'+label+'.json'))
            if paths:selected[label]=read_custody(paths[-1])
        results.append(dict(run=directory.name,results=selected,pending=[str(p) for p in directory.glob('preservation-pending-*.json')]))
    state=query(['/usr/bin/systemctl','show','su-test-'+context.operation['run_id'],'-p','ActiveState','-p','SubState','-p','Result','-p','ExecMainStatus','-p','MainPID','-p','ControlGroup','-p','MemoryCurrent','-p','MemoryPeak','-p','RuntimeMaxUSec'])
    return dict(source=context.document['source']['tree_sha256'],runs=results,supervisor=state)


def installed_dispatch(context, argv):
    """Probe-only authority cannot install packages or retire an existing app CT.

    Trusted delivery must already have put exact source/context/lineage in the CT.
    This owner adds only one exclusive namespace/root delegation and executes the
    source-fixed installed probe, leaving the original resource owner in charge.
    """
    from test_context import exclusive_json
    rule=execution_policy(context.operation['suite'],context.operation['mode'])
    require(rule.owner=='installed','installed execution owner mismatch')
    admit_scope(context,rule.public_phase)
    lineage=existing_lineage(context)
    with Run(context) as run:
        native = NativePVE(run)
        require(native.n['lineage'] is not None,'installed probe creation lineage required')
        lineage_path = absolute(native.n['lineage'])
        require(lineage['requested'] == asdict(native.owner.spec) and lineage['source'] == context.document['source']['tree_sha256'], 'installed probe lineage scope')
        native.owner.creation = lineage
        native.owner.current = Resource(**lineage['observed'])
        native.owner.checked()
        pid = int(query(['/usr/bin/lxc-info', '-n', str(native.owner.spec.ctid), '-pH']))
        root = Path(f'/proc/{pid}/root').stat()
        data = dict(schema=1, context_sha256=sha(context.path.read_bytes()), suite=context.operation['suite'], mode=context.operation['mode'],
                    resource=asdict(native.owner.spec), namespaces={key:os.readlink(f'/proc/{pid}/ns/{key}') for key in ('mnt','pid','user')},
                    root=[root.st_dev,root.st_ino], source=context.document['source']['tree_sha256'])
        destination = str(context.path.parent / (run.directory.name + '-delegation.json'))
        check = native.dispatch('pct',['exec',str(native.owner.spec.ctid),'--','test','!','-e',destination])
        require(check.returncode == 0, 'probe delegation destination already exists')
        path = run.directory/'delegation.json'
        exclusive_json(path,data)
        require(native.dispatch('pct',['push',str(native.owner.spec.ctid),str(path),destination]).returncode == 0, 'probe delegation publication')
        result = native.dispatch('pct',['exec',str(native.owner.spec.ctid),'--','env','SU_TEST_CONTEXT='+str(context.path),
                                       'SU_TEST_DELEGATION='+destination,'TMPDIR='+native.n['receiver_tmpdir'],'PYTHONDONTWRITEBYTECODE=1',*argv])
        run.record('installed-probe-result',dict(status=result.returncode,stdout=result.stdout,stderr=result.stderr,disposition='retained-by-original-owner'))
        print(result.stdout,end='')
        return result.returncode
