"""Manual NVIDIA consumer: native private PVE config, modeled CLI/CFS IPC, no GPU IO."""
import json
import os
from pathlib import Path
import re
import shlex
import stat
import subprocess
import sys
import tempfile
import shutil

SOURCE = Path(sys.argv[1]).resolve()
WORK = Path(tempfile.mkdtemp(prefix='nvidia-integration.', dir=os.environ['TMPDIR']))
print('NVIDIA integration evidence: ' + str(WORK), flush=True)

if '--inside' not in sys.argv:
    result = subprocess.run(['unshare', '--mount', '--propagation', 'private',
                             sys.executable, '-B', __file__, str(SOURCE), '--inside', str(WORK)],
                            timeout=180, env=os.environ)
    raise SystemExit(result.returncode)

# Cover every native module initialization destination before any Perl import.
WORK.rmdir()
WORK = Path(sys.argv[-1])
for name, target in [('pve', '/etc/pve'), ('locks', '/run/lock/lxc'),
                     ('driver', '/proc/driver'), ('dev', '/dev')]:
    directory = WORK / name
    directory.mkdir()
    subprocess.run(['mount', '--bind', str(directory), target], check=True, timeout=10)
node = os.uname().nodename
(WORK / 'pve/nodes' / node / 'lxc').mkdir(parents=True)
(WORK / 'pve/lxc').symlink_to('nodes/' + node + '/lxc')
(WORK / 'driver/nvidia/gpus').mkdir(parents=True)
(WORK / 'dev/fd').symlink_to('/proc/self/fd')
for name, fd in [('stdin', 0), ('stdout', 1), ('stderr', 2)]:
    (WORK / 'dev' / name).symlink_to('/proc/self/fd/' + str(fd))
for name, major, minor in [('null', 1, 3), ('zero', 1, 5), ('random', 1, 8),
                           ('urandom', 1, 9), ('nvidia2', 195, 2), ('nvidia7', 195, 7),
                           ('nvidiactl', 195, 255), ('nvidia-uvm', 509, 0)]:
    os.mknod(WORK / 'dev' / name, stat.S_IFCHR | 0o600, os.makedev(major, minor))
(WORK / 'dev/dri').mkdir()
config_root = WORK / 'configs'
shutil.copytree('/usr/share/lxc/config', config_root, symlinks=True)
subprocess.run(['mount', '--bind', str(config_root), '/usr/share/lxc/config'], check=True, timeout=10)
for pci, minor in [('0000:01:00.0', 2), ('0000:02:00.0', 7)]:
    directory = WORK / 'driver/nvidia/gpus' / pci
    directory.mkdir()
    (directory / 'information').write_text(f'Model: GPU {minor}\nDevice Minor: {minor}\n')

lib = WORK / 'lib/Test'
lib.mkdir(parents=True)
(lib / 'NvidiaCFS.pm').write_text(r'''
package Test::NvidiaCFS;
use strict; use warnings;
use PVE::LXC::Config; use PVE::Cluster; use PVE::Tools;
my $updates = 0; my $reads = 0; my $raw_reads = 0;
my $original_write = \&PVE::Tools::file_set_contents;
my $original_read = \&PVE::Tools::file_get_contents;
sub record { open(my $f, '>>', "$ENV{NVIDIA_WORK}/cfs.calls") or die $!; print $f "@_\n"; close($f) or die $!; }
no warnings 'redefine';
*PVE::LXC::get_lxc_version = sub { return (int($ENV{NVIDIA_LXC_MAJOR} // 7), 0); };
*PVE::CGroup::get_cgroup_controllers = sub {
    return ({}, ($ENV{NVIDIA_CASE} // '') eq 'v2-unavailable' ? undef : {});
};
*PVE::Tools::file_get_contents = sub {
    if ($_[0] =~ m{/lxc/987654\.conf$} && ++$raw_reads == 3) {
        if (($ENV{NVIDIA_CASE} // '') eq 'dependency-change') {
            open(my $f, '>', "$ENV{NVIDIA_WORK}/configs/changing.conf") or die $!;
            print $f "lxc.cgroup2.devices.allow = a\n"; close($f) or die $!;
        } elsif (($ENV{NVIDIA_CASE} // '') eq 'membership-change') {
            open(my $f, '>', "$ENV{NVIDIA_WORK}/configs/stable.d/new.conf") or die $!;
            print $f "lxc.cgroup2.devices.deny = a\n"; close($f) or die $!;
        }
    }
    return $original_read->(@_);
};
*PVE::Cluster::cfs_update = sub {
    record('refresh', ++$updates, defined($_[0]) ? $_[0] : 'default');
    die "modeled CFS refresh failure\n" if ($ENV{NVIDIA_CASE} // '') eq 'refresh-fail' && $updates == 2;
    die "modeled readback refresh failure\n" if ($ENV{NVIDIA_CASE} // '') eq 'readback-refresh-fail' && $updates == 3;
    if (($ENV{NVIDIA_CASE} // '') eq 'dependency-readback-change' && $updates == 3) {
        open(my $f, '>', "$ENV{NVIDIA_WORK}/configs/changing.conf") or die $!;
        print $f "lxc.cgroup2.devices.allow = a\n"; close($f) or die $!;
    }
};
*PVE::Cluster::cfs_file_version = sub {
    return (1, { parser => \&PVE::LXC::Config::parse_pct_config,
                 writer => \&PVE::LXC::Config::write_pct_config });
};
*PVE::Cluster::get_config = sub {
    record('read', ++$reads);
    my $raw = PVE::Tools::file_get_contents('/etc/pve/' . $_[0]);
    if (($ENV{NVIDIA_CASE} // '') eq 'digest-mismatch' ||
        (($ENV{NVIDIA_CASE} // '') eq 'readback-mismatch' && $reads > 1)) {
        $raw =~ s/hostname: fixture/hostname: substituted/;
    }
    return $raw;
};
*PVE::Tools::file_set_contents = sub {
    record('publish', $_[0]);
    die "modeled publication failure\n" if ($ENV{NVIDIA_CASE} // '') eq 'write-fail';
    return $original_write->(@_);
};
1;
''')

CHECKS = []


def check(name, expected, actual):
    passed = expected == actual
    CHECKS.append(dict(name=name, passed=passed, expected=expected, actual=actual))
    print(('PASS ' if passed else 'FAIL ') + 'NVIDIA ' + name +
          ('' if passed else repr((expected, actual))), flush=True)


def quote(value):
    return shlex.quote(str(value))


base = ('arch: amd64\nostype: debian\nhostname: fixture\nmemory: 512\nswap: 512\nunprivileged: 0\n'
        'rootfs: owned:vm-987654-disk-0,size=4G\n'
        'lxc.mount.entry: /dev/foreign dev/foreign none bind,optional,create=file\n'
        'lxc.cgroup2.devices.allow: c 42:* rwm\n')
sections = ('\n[pve:pending]\nmemory: 1024\n'
            '\n[saved]\nhostname: snapshot\nmemory: 256\nsnaptime: 1234\n'
            'rootfs: owned:vm-987654-disk-0,size=4G\n'
            'lxc.mount.entry: /dev/snapshot dev/snapshot none bind\n')
conf = WORK / 'pve/nodes' / node / 'lxc/987654.conf'
helper = SOURCE / 'tools/pve/gpu-nvidia.func'
script = (SOURCE / 'scripts/pve/hw-acceleration.sh').read_text()
startup, marker, _ = script.rpartition('\nmain\n')
assert marker, 'fixed main boundary'
prefix = f'''
set -Eeuo pipefail
export PERL5LIB={quote(WORK / 'lib')} NVIDIA_WORK={quote(WORK)}
perl() {{
 if [[ "$NVIDIA_CASE" == policy-unreadable ]]; then
  /usr/bin/setpriv --bounding-set=-dac_override,-dac_read_search /usr/bin/perl -MTest::NvidiaCFS "$@"
 else /usr/bin/perl -MTest::NvidiaCFS "$@"; fi
}}
nvidia-smi() {{
 printf 'smi %s\\n' "$*" >> {quote(WORK / 'events')}
 if [[ "$NVIDIA_CASE" == second-fail && "${{ctid:-}}" == 987655 ]]; then return 37; fi
 case "$NVIDIA_CASE" in
  query-fail) return 37;;
 esac
 case "$*" in
  *query-gpu=driver_version*)
   case "$NVIDIA_CASE" in
    empty-version) :;; bad-version) printf 'evil[1+1]\\n';;
    old-driver) printf '470.1\\n';; mixed-driver) printf '550.1\\n560.1\\n';;
    *) printf '550.54.14\\n550.54.14\\n';; esac;;
  '-q')
   case "$NVIDIA_CASE" in
    old-cuda) printf 'CUDA Version : 10.2\\n';;
    bad-cuda) printf 'CUDA Version : N/A\\n';;
    duplicate-cuda) printf 'CUDA Version : 12.4\\nCUDA Version : 12.4\\n';;
    new-cuda-label) printf 'CUDA UMD Version : 13.0\\n';;
    *) printf 'CUDA Version : 12.4\\n';; esac;;
  *) printf 'unestablished CLI arguments: %s\\n' "$*" >&2; return 88;;
 esac
}}
whiptail() {{
 printf 'select\\n' >> {quote(WORK / 'events')}
 case "$NVIDIA_CASE" in cancel) return 1;; escape) return 255;;
  empty-selection) :;; wrong-selection) printf '6' >&2;; bad-selection) printf '../bad' >&2;;
  *) printf '%s' "${{NVIDIA_MINOR:-7}}" >&2;; esac
}}
stat() {{
 case "$NVIDIA_CASE" in stat-fail) return 41;; stat-bad) printf 'not-hex\\n';;
 stat-overflow) printf 'ffffffff:7\\n';; stat-minor) printf 'c3:2\\n';;
 *) /usr/bin/stat "$@";; esac
}}
cat() {{
 if [[ "$NVIDIA_CASE" == record-fail && "$*" == /proc/driver/nvidia/* ]]; then return 42; fi
 /bin/cat "$@"
}}
'''


def run(name, code, text=base + sections, answer='', scenario='ok', conditional=True, major=7):
    conf.write_text(text)
    (WORK / 'cfs.calls').unlink(missing_ok=True)
    env = dict(os.environ, NVIDIA_CASE=scenario, NVIDIA_LXC_MAJOR=str(major), TMPDIR=os.environ['TMPDIR'], TERM='dumb')
    call = ('if ' + code + '; then rc=0; else rc=$?; fi; exit "$rc"') if conditional else code
    common = SOURCE / 'tools/pve/gpu-config.func'
    common_source = f'\nsource {quote(common)}\n' if common.is_file() else '\n'
    result = subprocess.run(['/bin/bash', '-c', prefix + common_source + f'\nsource {quote(helper)}\n' + call],
                            input=answer, text=True, capture_output=True, env=env, timeout=15)
    facts = dict(status=result.returncode, stdout=result.stdout, stderr=result.stderr,
                  before=text, after=conf.read_bytes().decode() if conf.exists() else None, calls=(WORK / 'cfs.calls').read_text()
                 if (WORK / 'cfs.calls').exists() else '')
    (WORK / (name + '.json')).write_text(json.dumps(facts, indent=2))
    return facts


for name, code, scenario, status, answer in [
    ('driver', 'nvidia_validate_driver_version', 'ok', 0, ''),
    ('driver-absent', 'unset -f nvidia-smi; nvidia_validate_driver_version', 'ok', 127, ''),
    ('driver-failed', 'nvidia_validate_driver_version', 'query-fail', 37, ''),
    ('driver-empty', 'nvidia_validate_driver_version', 'empty-version', 65, ''),
    ('driver-malformed', 'nvidia_validate_driver_version', 'bad-version', 65, ''),
    ('driver-ambiguous', 'nvidia_validate_driver_version', 'mixed-driver', 65, ''),
    ('driver-old-no', 'nvidia_validate_driver_version', 'old-driver', 1, 'no\n'),
    ('driver-old-eof', 'nvidia_validate_driver_version', 'old-driver', 1, ''),
    ('driver-old-yes', 'nvidia_validate_driver_version', 'old-driver', 0, 'yes\n'),
    ('cuda', 'nvidia_validate_cuda_version', 'ok', 0, ''),
    ('cuda-absent', 'unset -f nvidia-smi; nvidia_validate_cuda_version', 'ok', 127, ''),
    ('cuda-new-label', 'nvidia_validate_cuda_version', 'new-cuda-label', 0, ''),
    ('cuda-failed', 'nvidia_validate_cuda_version', 'query-fail', 37, ''),
    ('cuda-malformed', 'nvidia_validate_cuda_version', 'bad-cuda', 65, ''),
    ('cuda-duplicate', 'nvidia_validate_cuda_version', 'duplicate-cuda', 65, ''),
    ('cuda-old-no', 'nvidia_validate_cuda_version', 'old-cuda', 1, '\n'),
    ('cuda-old-yes', 'nvidia_validate_cuda_version', 'old-cuda', 0, 'y\n'),
    ('selected', 'nvidia_select_gpu_minor', 'ok', 0, ''),
    ('selected-cancel', 'nvidia_select_gpu_minor', 'cancel', 1, ''),
    ('selected-escape', 'nvidia_select_gpu_minor', 'escape', 1, ''),
    ('selected-empty', 'nvidia_select_gpu_minor', 'empty-selection', 65, ''),
    ('selected-unlisted', 'nvidia_select_gpu_minor', 'wrong-selection', 65, ''),
    ('selected-malformed', 'nvidia_select_gpu_minor', 'bad-selection', 65, '')]:
    for conditional in (False, True):
        label = name + '-' + str(conditional)
        facts = run(label, code, scenario=scenario, answer=answer, conditional=conditional)
        check(label + ' status', status, facts['status'])
        check(label + ' no config mutation', facts['before'], facts['after'])
        if name == 'selected':
            check(label + ' actual sparse minor only', '7', facts['stdout'])

facts = run('sparse-availability', 'nvidia_gpu_available')
check('sparse numbered character availability', 0, facts['status'])
facts = run('record-failed', 'nvidia_select_gpu_minor', scenario='record-fail')
check('failed proc producer retains status', 42, facts['status'])
for device in ('nvidia7', 'nvidiactl', 'nvidia-uvm'):
    path = WORK / 'dev' / device
    saved = WORK / (device + '.saved')
    path.rename(saved)
    try:
        if device == 'nvidia-uvm':
            facts = run('optional-absent', 'nvidia_lxc_passthrough 987654 7')
            check('absent optional companion succeeds', 0, facts['status'])
        else:
            facts = run('missing-' + device, 'nvidia_lxc_passthrough 987654 7')
            check('missing ' + device + ' refuses before publication', (69, base + sections),
                  (facts['status'], facts['after']))
        path.write_text('not a character node')
        facts = run('noncharacter-' + device, 'nvidia_lxc_passthrough 987654 7')
        check('noncharacter ' + device + ' refuses before publication', (69, base + sections),
              (facts['status'], facts['after']))
        path.unlink()
    finally:
        saved.rename(path)
for value in ('', '../7', '$(false)', '999999999999999999999999999999'):
    facts = run('minor-invalid-' + str(len(value)), 'nvidia_lxc_passthrough 987654 ' + quote(value))
    check('invalid minor ' + repr(value), (65, base + sections), (facts['status'], facts['after']))
for ctid in ('../987654', '0', '99999999999999999999999999'):
    facts = run('ctid-invalid-' + str(len(ctid)), 'nvidia_lxc_passthrough ' + quote(ctid) + ' 7')
    check('invalid CTID ' + repr(ctid), (65, base + sections), (facts['status'], facts['after']))
gpu_directory = WORK / 'driver/nvidia/gpus/0000:02:00.0'
gpu_directory.rename(WORK / 'second-gpu')
try:
    facts = run('single-gpu', 'nvidia_select_gpu_minor')
    check('single GPU returns actual minor', (0, '2'), (facts['status'], facts['stdout']))
    info = WORK / 'driver/nvidia/gpus/0000:01:00.0/information'
    original = info.read_text()
    for name, record in [('bad-record', 'Model: GPU\nDevice Minor: bad\n'),
                          ('duplicate-record', 'Model: GPU\nDevice Minor: 2\nDevice Minor: 7\n')]:
        info.write_text(record)
        facts = run(name, 'nvidia_select_gpu_minor')
        check(name + ' refuses', 65, facts['status'])
    info.write_text(original)
finally:
    (WORK / 'second-gpu').rename(gpu_directory)
inventory = WORK / 'driver/nvidia/gpus'
inventory.rename(WORK / 'saved-inventory')
try:
    facts = run('no-inventory', 'nvidia_select_gpu_minor')
    check('missing inventory refuses', 1, facts['status'])
    inventory.mkdir()
    facts = run('empty-inventory', 'nvidia_select_gpu_minor')
    check('empty inventory refuses', 1, facts['status'])
    inventory.rmdir()
finally:
    (WORK / 'saved-inventory').rename(inventory)
facts = run('missing-ct', 'rm /etc/pve/lxc/987654.conf; nvidia_lxc_passthrough 987654 7')
check('missing CT refuses', True, facts['status'] != 0)

for name, text, scenario in [
    ('native', base + sections, 'ok'),
    ('unprivileged', (base + sections).replace('unprivileged: 0', 'unprivileged: 1'), 'ok'),
    ('locked', base + 'lock: backup\n' + sections, 'ok'),
    ('unknown', base + 'unknown_option: value\n' + sections, 'ok'),
    ('duplicate', base + 'memory: 2048\n' + sections, 'ok'),
    ('duplicate-section', base + sections + '\n[saved]\nhostname: lost\n', 'ok'),
    ('discarded', base + 'snapstate: prepare\n' + sections, 'ok'),
    ('unused-loss', base + 'unused0: owned:vm-987654-disk-0\n' + sections, 'ok'),
    ('conflict', base + 'lxc.mount.entry: /dev/other dev/nvidia7 none bind\n' + sections, 'ok'),
    ('absolute-conflict', base + 'lxc.mount.entry: /dev/other /dev/nvidia7 none bind\n' + sections, 'ok'),
    ('refresh', base + sections, 'refresh-fail'),
    ('digest', base + sections, 'digest-mismatch'),
    ('write', base + sections, 'write-fail'),
    ('readback', base + sections, 'readback-mismatch'),
    ('readback-refresh', base + sections, 'readback-refresh-fail'),
    ('stat', base + sections, 'stat-fail'),
    ('stat-data', base + sections, 'stat-bad'),
    ('stat-overflow', base + sections, 'stat-overflow'),
    ('stat-minor', base + sections, 'stat-minor')]:
    facts = run(name, 'nvidia_lxc_passthrough 987654 7', text=text, scenario=scenario)
    if name == 'native':
        check(name + ' status', 0, facts['status'])
        active = facts['after'].split('[pve:pending]')[0]
        check(name + ' active /dev consumer', True,
              'lxc.mount.entry: /dev/nvidia7 dev/nvidia7 none bind,optional,create=file' in active)
        check(name + ' no other card selected', False, '/dev/nvidia2' in active)
        check(name + ' shared control consumer', True, '/dev/nvidiactl dev/nvidiactl ' in active)
        check(name + ' foreign pair order', True, active.index('/dev/foreign') < active.index('/dev/nvidia7')
              if '/dev/nvidia7' in active else False)
        check(name + ' truthful message', False, 'Installed NVIDIA GPU tools' in facts['stdout'])
        check('native CFS cache readback after publication', True, 'read 2\n' in facts['calls'])
        parse = ('use JSON::PP; my $f=shift; print JSON::PP->new->canonical->encode('
                 'PVE::LXC::Config::parse_pct_config($f,PVE::Tools::file_get_contents($f),1));')
        native = subprocess.run(['/usr/bin/perl', '-MTest::NvidiaCFS', '-e', parse, str(conf)],
                                env=dict(os.environ, PERL5LIB=str(WORK / 'lib'), NVIDIA_WORK=str(WORK)),
                                text=True, capture_output=True, timeout=15)
        check('native installed parser status', 0, native.returncode)
        if native.returncode == 0:
            parsed = json.loads(native.stdout)
            check('native pending unchanged', {'memory': 1024}, parsed['pending'])
            check('native snapshot unchanged', {'hostname': 'snapshot', 'memory': 256, 'snaptime': 1234,
                  'rootfs': 'owned:vm-987654-disk-0,size=4G',
                  'lxc': [['lxc.mount.entry', '/dev/snapshot dev/snapshot none bind']]}, parsed['snapshots']['saved'])
        again = run('repeat', 'nvidia_lxc_passthrough 987654 7', text=facts['after'])
        check('repeat status and no new bytes', (0, facts['after']), (again['status'], again['after']))
        check('repeat does not publish', False, 'publish ' in again['calls'])
        second = run('second-card', 'nvidia_lxc_passthrough 987654 2', text=again['after'])
        check('second card preserves both mappings', True,
              '/dev/nvidia2 dev/nvidia2 ' in second['after'] and '/dev/nvidia7 dev/nvidia7 ' in second['after'])
    else:
        check(name + ' refuses', True, facts['status'] != 0)
        if name not in ('readback', 'readback-refresh'):
            check(name + ' preserves original bytes', text, facts['after'])
        check(name + ' no false success', False, 'configured' in facts['stdout'].lower())
        if name == 'unused-loss':
            check('normalization refusal identifies lost field', True, 'config/unused0' in facts['stderr'])

facts = run('snapshot-named-active', 'nvidia_lxc_passthrough 987654 7',
            text=base + sections.replace('[saved]', '[active]'))
check('snapshot named active is not the active section', 0, facts['status'])
equivalent = (base + 'lxc.cgroup2.devices.allow: c 195:* mrw\n'
              'lxc.mount.entry: /dev/nvidia7 dev/nvidia7 none create=file,optional,bind 0 0\n' + sections)
facts = run('equivalent-config', 'nvidia_lxc_passthrough 987654 7', text=equivalent)
check('equivalent config status', 0, facts['status'])
active = facts['after'].split('[pve:pending]')[0]
check('equivalent mount is not duplicated', 1, active.count('/dev/nvidia7 dev/nvidia7'))
check('equivalent permission set is not duplicated', 1, len(re.findall(r'c 195:\* [rwm]+', active)))

sys.path.insert(0, str(SOURCE / 'tests/lib'))
from nvidia_policy_cases import exercise_policy
exercise_policy(WORK, run, check, base, sections)
from gpu_contract_fixture import exercise_gpu_contract
exercise_gpu_contract(SOURCE, WORK, run, check, base, sections)
from intel_sources_fixture import exercise_intel_sources
exercise_intel_sources(SOURCE, WORK, run, check, base, sections)

# The full real startup/dispatch remains the consumer; only operator inputs and
# external hardware/service tools are replaced. Real helper bodies stay loaded.
states = WORK / 'ct-states'
states.mkdir()
# A component-owned emitter may carry non-prefix private dependencies and data.
# This independent fake module makes the actual caller consume that contract.
private_module = r'''
_owned_gpu_dependency() { [[ "$_owned_gpu_value" == owned-data ]] || return 61; printf 'private-closure:%s\n' "$_owned_gpu_value" >> "$NVIDIA_WORK/events"; }
nvidia_gpu_available() { return 0; }
nvidia_validate_driver_version() { _owned_gpu_dependency; }
nvidia_validate_cuda_version() { return 0; }
nvidia_select_gpu_minor() { printf 7; }
nvidia_lxc_passthrough() { printf 'owned-passthrough %s\n' "$*" >> "$NVIDIA_WORK/effects"; }
nvidia_helper_contents() {
 printf 'declare -- _owned_gpu_value=owned-data\n' || return $?
 declare -f _owned_gpu_dependency nvidia_gpu_available nvidia_validate_driver_version nvidia_validate_cuda_version nvidia_select_gpu_minor nvidia_lxc_passthrough || return $?
}
'''
(WORK / 'private-component.func').write_text(private_module)
for name, scenario, features, answer in [
    ('main-ok', 'ok', 'nvidia', 'n\n'),
    ('main-query-fail', 'query-fail', 'nvidia', 'y\n'),
    ('main-cancel', 'cancel', 'nvidia', 'y\n'),
    ('main-mixed', 'write-fail', 'usb nvidia', 'y\n'),
    ('main-multi', 'second-fail', 'nvidia', 'y\n'),
    ('main-siblings', 'ok', 'intel amd', 'n\n'),
    ('main-library-missing', 'ok', 'nvidia', 'y\n'),
    ('main-missing-nv-usb', 'library-missing', 'usb', 'n\n'),
    ('main-missing-nv-intel', 'library-missing', 'intel', 'n\n'),
    ('main-missing-nv-selected', 'library-missing', 'nvidia', 'y\n'),
    ('main-partial-nv-amd', 'library-partial', 'amd', 'n\n'),
    ('main-partial-nv-selected', 'library-partial', 'nvidia', 'y\n'),
    ('main-old-api-amd', 'library-old-api', 'amd', 'n\n'),
    ('main-old-api-selected', 'library-old-api', 'nvidia', 'y\n'),
    ('main-exit-zero-intel', 'library-exit-zero', 'intel', 'n\n'),
    ('main-exit-zero-selected', 'library-exit-zero', 'nvidia', 'y\n'),
    ('main-malformed-nv-usb', 'library-malformed', 'usb', 'n\n'),
    ('main-exit-nv-intel', 'library-exit', 'intel', 'n\n'),
    ('main-private-component', 'private-component', 'nvidia', 'n\n'),
    ('main-no-emitter-selected', 'no-emitter', 'nvidia', 'y\n'),
    ('main-no-emitter-intel', 'no-emitter', 'intel', 'n\n'),
    ('main-emitter-fail-selected', 'emitter-fail', 'nvidia', 'y\n'),
    ('main-emitter-fail-usb', 'emitter-fail', 'usb', 'n\n'),
    ('main-emitter-exit-selected', 'emitter-exit', 'nvidia', 'y\n'),
    ('main-emitter-exit-intel', 'emitter-exit', 'intel', 'n\n'),
    ('main-emitter-empty-selected', 'emitter-empty', 'nvidia', 'y\n'),
    ('main-emitter-partial-selected', 'emitter-partial', 'nvidia', 'y\n'),
    ('main-common-missing-usb', 'common-missing', 'usb', 'n\n'),
    ('main-common-missing-intel', 'common-missing', 'intel', 'y\n'),
    ('main-common-missing-amd', 'common-missing', 'amd', 'y\n'),
    ('main-common-missing-nvidia', 'common-missing', 'nvidia', 'y\n'),
    ('main-common-partial-intel', 'common-partial', 'intel', 'y\n'),
    ('main-common-exit-amd', 'common-exit', 'amd', 'y\n'),
    ('main-common-emitter-fail-nvidia', 'common-emitter-fail', 'nvidia', 'y\n'),
    ('main-common-emitter-partial-intel', 'common-emitter-partial', 'intel', 'y\n'),
    ('main-real-intel-tools-fail', 'real-intel-install', 'intel', 'y\n'),
    ('main-real-amd-tools-fail', 'real-amd-install', 'amd', 'y\n'),
    ('main-real-intel-config-fail', 'write-fail', 'intel', 'y\n'),
    ('main-real-amd-config-fail', 'write-fail', 'amd', 'y\n'),
    ('main-real-intel-os-fail', 'real-os-fail', 'intel', 'y\n'),
    ('main-real-amd-group-fail', 'real-group-fail', 'amd', 'y\n'),
    ('main-real-intel-optional-group', 'real-optional-group', 'intel', 'n\n'),
    ('main-real-amd-without-nvidia', 'library-missing', 'amd', 'n\n'),
    ('main-probe-nv-usb', 'availability-exit', 'usb', '1\n987654\nn\n'),
    ('main-intel-tools-fail', 'ok', 'intel', 'y\n'),
    ('main-amd-tools-fail', 'ok', 'amd', 'y\n'),
    ('main-restart-eof', 'ok', 'nvidia', ''),
    ('main-operator', 'ok', 'nvidia', '3\n987654\nn\n'),
    ('main-running-requested', 'ok', 'nvidia', 'y\n'),
    ('main-stopped-requested', 'ok', 'nvidia', 'y\n'),
    ('main-status-failed', 'ok', 'nvidia', 'y\n'),
    ('main-status-unknown', 'ok', 'nvidia', 'y\n'),
    ('main-reboot-fail', 'ok', 'nvidia', 'y\n')]:
    conf.write_text(base + sections)
    (conf.parent / '987655.conf').write_text(base + sections)
    (WORK / 'events').unlink(missing_ok=True)
    calls = WORK / 'effects'
    calls.unlink(missing_ok=True)
    reboot_effects = WORK / 'reboot-effects'
    reboot_effects.unlink(missing_ok=True)
    for ctid in ('987654', '987655'):
        (states / ctid).write_text('stopped' if name == 'main-stopped-requested' else 'running')
        (states / (ctid + '.reboots')).write_text('0')
    if name == 'main-probe-nv-usb':
        os.mknod(WORK / 'dev/ttyUSB0', stat.S_IFCHR | 0o600, os.makedev(188, 0))
    operator_overrides = '' if name in ('main-operator', 'main-probe-nv-usb') else f'''
header_info() {{ :; }}
prompt_features() {{ SELECTED_FEATURES=({features}); }}
select_lxc_cts() {{ SELECTED_CTIDS={'"987654 987655"' if name == 'main-multi' else '987654'}; }}
'''
    common_stale = ('gpu_config_node() { return 0; }; gpu_write_lxc_config() { printf "stale-common\\n" >> "$NVIDIA_WORK/events"; }'
                    if scenario.startswith('common-') else ':')
    real_setup = ''
    if name.startswith('main-real-'):
        settings = {'ROOT': str(WORK / 'provider-models')}
        if scenario in ('real-intel-install', 'real-amd-install'):
            settings['INSTALL_RC'] = '42'
        elif scenario == 'real-os-fail':
            settings['OS_RC'] = '43'
        elif scenario in ('real-group-fail', 'real-optional-group'):
            settings.update(GROUP='render', GROUP_RC='46')
        # Replace the isolated returned-status stubs with the actual providers.
        real_setup = (f'source {quote(SOURCE / "tools/pve/gpu-intel.func")}\n' +
                      f'source {quote(SOURCE / "tools/pve/gpu-amd.func")}\n' +
                      'intel_gpu_available() { return 0; }; amd_gpu_available() { return 0; }\n' +
                      'export ' + ' '.join('GPU_TEST_' + key + '=' + quote(value) for key, value in settings.items()) +
                      f' PATH={quote(WORK / "provider-models/bin")}:"$PATH"\n' +
                      f'source {quote(WORK / "provider-models/transport.func")}\n')
    code = prefix + f'''
REPO_BASE=offline
curl() {{ case "${{!#}}" in
 */bootstrap/pve) /bin/cat {quote(SOURCE / 'misc/bootstrap/pve')};;
 */core.func) /bin/cat {quote(SOURCE / 'misc/core.func')};;
 */error_handler.func) /bin/cat {quote(SOURCE / 'misc/error_handler.func')};; *) return 89;; esac; }}
wget() {{ case "${{!#}}" in
 */gpu-config.func)
  case "$NVIDIA_CASE" in
   common-missing) return 22;;
   common-partial) /bin/cat {quote(SOURCE / 'tools/pve/gpu-config.func')}; printf '\nreturn 1\n';;
   common-exit) /bin/cat {quote(SOURCE / 'tools/pve/gpu-config.func')}; printf '\nexit 0\n';;
   common-emitter-fail) /bin/cat {quote(SOURCE / 'tools/pve/gpu-config.func')}; printf '\ngpu_config_contents() {{ declare -f gpu_config_node; return 37; }}\n';;
   common-emitter-partial) /bin/cat {quote(SOURCE / 'tools/pve/gpu-config.func')}; printf '\ngpu_config_contents() {{ declare -f gpu_config_node; }}\n';;
   *) /bin/cat {quote(SOURCE / 'tools/pve/gpu-config.func')};; esac;;
 */gpu-nvidia.func)
   case "$NVIDIA_CASE" in
    private-component) /bin/cat {quote(WORK / 'private-component.func')};;
    no-emitter) /bin/cat {quote(helper)}; printf '\nunset -f nvidia_helper_contents\n';;
    emitter-fail) /bin/cat {quote(helper)}; printf '\nnvidia_helper_contents() {{ declare -f nvidia_gpu_available; return 37; }}\n';;
    emitter-exit) /bin/cat {quote(helper)}; printf '\nnvidia_helper_contents() {{ declare -f nvidia_gpu_available; exit 0; }}\n';;
    emitter-empty) /bin/cat {quote(helper)}; printf '\nnvidia_helper_contents() {{ :; }}\n';;
    emitter-partial) /bin/cat {quote(helper)}; printf '\nnvidia_helper_contents() {{ declare -f nvidia_gpu_available; }}\n';;
   library-missing) return 22;;
   library-partial) /bin/cat {quote(helper)}; printf '\\nreturn 1\\n';;
   library-malformed) printf 'function broken() {{\\n';;
   library-exit) /bin/cat {quote(helper)}; printf '\\nexit 1\\n';;
   library-exit-zero) /bin/cat {quote(helper)}; printf '\\nexit 0\\n';;
   library-old-api) printf 'function nvidia_gpu_available() {{ return 0; }}\\nfunction check_nvidia_driver_status() {{ return 0; }}\\n';;
   availability-exit) /bin/cat {quote(helper)}; printf '\\nfunction nvidia_gpu_available() {{ exit 1; }}\\n';;
   *) /bin/cat {quote(helper)};; esac;;
 */gpu-intel.func) /bin/cat {quote(SOURCE / 'tools/pve/gpu-intel.func')};;
 */gpu-amd.func) /bin/cat {quote(SOURCE / 'tools/pve/gpu-amd.func')};; *) return 89;; esac; }}
pveversion() {{ :; }}
{'nvidia_validate_driver_version() { printf "stale-public\\n" >> "$NVIDIA_WORK/events"; }; nvidia_validate_cuda_version() { return 0; }; nvidia_select_gpu_minor() { printf 7; }; nvidia_lxc_passthrough() { return 0; }' if scenario.startswith('emitter-') else ':'}
{common_stale}
{startup}
{operator_overrides}
apply_usb_passthrough() {{ printf 'usb\\n' >> {quote(calls)}; }}
passthrough_intel_to_lxc() {{ printf 'intel %s\\n' "$*" >> {quote(calls)}; }}
install_intel_tools_in_ct() {{ printf 'intel-tools %s\\n' "$*" >> {quote(calls)}; {'return 45' if name == 'main-intel-tools-fail' else ':'}; }}
passthrough_amd_to_lxc() {{ printf 'amd %s\\n' "$*" >> {quote(calls)}; }}
install_amd_tools_in_ct() {{ printf 'amd-tools %s\\n' "$*" >> {quote(calls)}; {'return 46' if name == 'main-amd-tools-fail' else ':'}; }}
{real_setup}
pct() {{
 printf '%s\\n' "$*" >> {quote(calls)}
  case "$1" in
   exec) gpu_test_pct "$@";;
  list) printf 'VMID Status Lock Name\\n987654 running - fixture\\n987655 running - sibling\\n';;
  status)
   {'printf "status: running\\n"; return 1' if name == 'main-status-failed' else ':'}
   {'printf "status: unknown\\n"; return 0' if name == 'main-status-unknown' else ':'}
   printf 'status: %s\\n' "$(< {quote(states)}/"$2")";;
  reboot)
   [[ "$(< {quote(states)}/"$2")" == running ]] || return 44
   {'return 43' if name == 'main-reboot-fail' else ':'}
   local counter
   counter=$(< {quote(states)}/"$2.reboots")
   printf '%s' "$((counter + 1))" > {quote(states)}/"$2.reboots"
   printf 'rebooted %s\\n' "$2" >> {quote(reboot_effects)};;
  *) return 89;;
 esac
}}
{'unset -f nvidia_lxc_passthrough' if name == 'main-library-missing' else ':'}
main
printf 'operator-selection:%s:%s\\n' "${{SELECTED_FEATURES[*]}}" "$SELECTED_CTIDS"
'''
    result = subprocess.run(['/bin/bash', '-c', code], text=True, input=answer, capture_output=True,
                             timeout=20, env=dict(os.environ, NVIDIA_CASE=scenario, TERM='dumb'))
    if name == 'main-probe-nv-usb':
        (WORK / 'dev/ttyUSB0').unlink()
    effects = calls.read_text() if calls.exists() else ''
    actual_reboots = reboot_effects.read_text() if reboot_effects.exists() else ''
    final_state = (states / '987654').read_text()
    reboot_count = int((states / '987654.reboots').read_text())
    (WORK / (name + '.json')).write_text(json.dumps(dict(status=result.returncode, stdout=result.stdout,
                                                        stderr=result.stderr, effects=effects,
                                                         actual_reboots=actual_reboots,
                                                         config=conf.read_bytes().decode(),
                                                        state=final_state, reboot_count=reboot_count), indent=2))
    expected_status = 0 if name in ('main-ok', 'main-restart-eof', 'main-siblings', 'main-operator',
                                   'main-missing-nv-usb', 'main-missing-nv-intel', 'main-partial-nv-amd',
                                    'main-old-api-amd', 'main-exit-zero-intel',
                                    'main-private-component', 'main-no-emitter-intel',
                                     'main-emitter-fail-usb', 'main-emitter-exit-intel',
                                     'main-common-missing-usb', 'main-real-intel-optional-group',
                                     'main-real-amd-without-nvidia',
                                   'main-malformed-nv-usb', 'main-exit-nv-intel', 'main-probe-nv-usb',
                                   'main-running-requested', 'main-stopped-requested') else {
        'main-reboot-fail': 43, 'main-status-unknown': 65}.get(name, 1)
    check(name + ' status', expected_status, result.returncode)
    if scenario.startswith('common-') and features != 'usb':
        check(name + ' no GPU producer effects', False, (WORK / 'events').exists())
        check(name + ' no config or CT effects', (base + sections, ''), (conf.read_text(), effects))
        check(name + ' precise missing common-owner diagnostic', True,
              'Shared GPU configuration support unavailable' in result.stderr)
    if name.startswith('main-real-'):
        marker = '/dev/dri/renderD128 dev/dri/renderD128 ' if features == 'intel' else '/dev/kfd dev/kfd '
        if 'config-fail' in name:
            check(name + ' refusal retains original bytes', base + sections, conf.read_text())
            check(name + ' config failure stops tools', False, 'exec ' in effects)
        else:
            check(name + ' actual native active consumer', True, marker in conf.read_text().split('[pve:pending]')[0])
            if name not in ('main-real-intel-optional-group', 'main-real-amd-without-nvidia'):
                check(name + ' actual failure retains known partial', True, 'Partial changes retained' in result.stderr)
                check(name + ' no false Updated or Installed', False,
                      'Updated:' in result.stdout or 'Installed' in result.stdout)
            elif name == 'main-real-intel-optional-group':
                check(name + ' optional membership warning', True, '46' in result.stderr)
            else:
                check(name + ' actual unrelated vendor completes', True, 'Updated:' in result.stdout and 'Installed ROCm' in result.stdout)
        check(name + ' actual failed stage never reboots', False,
              bool(re.search(r'^(?:status|reboot) ', effects, re.M)))
    if name == 'main-private-component':
        check(name + ' public function consumes private dependency/data', 'private-closure:owned-data\n',
              (WORK / 'events').read_text() if (WORK / 'events').exists() else '')
        check(name + ' actual caller reaches emitted component consumer', 'owned-passthrough 987654 7\n', effects)
        check(name + ' reported configured after consumer', True, 'Updated:' in result.stdout)
    if name.endswith('-selected') and (scenario.startswith('emitter-') or scenario == 'no-emitter'):
        check(name + ' no stale public producer borrowed', False, (WORK / 'events').exists())
        check(name + ' no config mutation', base + sections, conf.read_text())
        check(name + ' clear unavailable diagnostic', True,
              'NVIDIA helper' in result.stderr and ('unavailable' in result.stderr or 'API' in result.stderr))
    if name not in ('main-reboot-fail', 'main-multi', 'main-running-requested'):
        check(name + ' no unintended reboot', False, 'reboot ' in effects)
    if scenario in ('query-fail', 'cancel', 'write-fail') or name in ('main-missing-nv-selected', 'main-partial-nv-selected'):
        check(name + ' no false Updated', False, 'Updated:' in result.stdout)
    if name == 'main-multi':
        check(name + ' only complete target rebooted', 'rebooted 987654\n', actual_reboots)
        check(name + ' failed target unchanged', base + sections, (conf.parent / '987655.conf').read_text())
    if name == 'main-query-fail':
        check(name + ' failed producer stops selection', False,
              'select\n' in ((WORK / 'events').read_text() if (WORK / 'events').exists() else ''))
    if name == 'main-mixed':
        check(name + ' retained changes are not denied', False, 'No passthrough applied.' in result.stderr)
    if name == 'main-siblings':
        check(name + ' existing API argument order',
              'intel 987654\nintel-tools 987654\namd 987654\namd-tools 987654\n', effects)
    if name == 'main-reboot-fail':
        check(name + ' no false Restarted', False, 'Restarted container' in result.stdout)
    if name in ('main-ok', 'main-restart-eof', 'main-stopped-requested', 'main-status-failed',
                'main-status-unknown', 'main-reboot-fail'):
        check(name + ' no modeled reboot effect', (0, ''), (reboot_count, actual_reboots))
    if name in ('main-ok', 'main-restart-eof'):
        check(name + ' No/EOF never queries or controls state', '', effects)
    if name in ('main-status-failed', 'main-status-unknown'):
        check(name + ' query failure does not claim Restarted', False, 'Restarted container' in result.stdout)
    if name == 'main-stopped-requested':
        check(name + ' positively stopped remains stopped', 'stopped', final_state)
        check(name + ' configuration retained for next start', True,
              '/dev/nvidia7 dev/nvidia7 ' in conf.read_text())
        check(name + ' no false Restarted', False, 'Restarted container' in result.stdout)
    if name == 'main-running-requested':
        check(name + ' actual modeled reboot consumed', (1, 'rebooted 987654\n'),
              (reboot_count, actual_reboots))
        check(name + ' success follows modeled effect', True, 'Restarted container 987654' in result.stdout)
    if name == 'main-operator':
        check(name + ' no nvidia0 fixture', False, (WORK / 'dev/nvidia0').exists())
        check(name + ' real availability menu displays NVIDIA', True, ' [3] NVIDIA GPU' in result.stdout)
        check(name + ' actual operator selections', True, 'operator-selection:nvidia:987654' in result.stdout)
        check(name + ' native config consumer receives selected minor', True,
              '/dev/nvidia7 dev/nvidia7 ' in conf.read_text().split('[pve:pending]')[0])
        check(name + ' pct list modeled, no reboot effect', ('list\n', ''), (effects, actual_reboots))
    if name in ('main-intel-tools-fail', 'main-amd-tools-fail'):
        check(name + ' known passthrough retained as partial', True, 'Partial changes retained' in result.stderr)
        check(name + ' partial is not a completed target', False, 'Updated:' in result.stdout)
        check(name + ' no state or reboot effects', False, 'status ' in effects or 'reboot ' in effects)
    if name in ('main-missing-nv-selected', 'main-partial-nv-selected', 'main-library-missing',
                'main-old-api-selected', 'main-exit-zero-selected'):
        check(name + ' unavailable NVIDIA has no producer effects', False, (WORK / 'events').exists())
        check(name + ' unavailable NVIDIA preserves config bytes', base + sections, conf.read_text())

# Full startup/exit under a space/glob TMPDIR: no utility scratch is needed.
# Preserve both shell-splitting lookalikes and pre-existing tmp.* user contents.
space_tmp = WORK / 'cleanup canary* temp'
space_tmp.mkdir()
canaries = [WORK / 'cleanup', WORK / 'canary-owned']
canaries.append(space_tmp / 'tmp.operator-kept')
for directory in canaries:
    directory.mkdir()
    (directory / 'keep').write_text('owned canary')
before_tmp = {str(p.relative_to(space_tmp)): p.read_bytes().hex() if p.is_file() else None
              for p in space_tmp.rglob('*')}
cleanup_code = prefix + f'''
REPO_BASE=offline
curl() {{ case "${{!#}}" in
 */bootstrap/pve) /bin/cat {quote(SOURCE / 'misc/bootstrap/pve')};;
 */core.func) /bin/cat {quote(SOURCE / 'misc/core.func')};;
 */error_handler.func) /bin/cat {quote(SOURCE / 'misc/error_handler.func')};; *) return 89;; esac; }}
wget() {{ case "${{!#}}" in
 */gpu-config.func) /bin/cat {quote(SOURCE / 'tools/pve/gpu-config.func')};;
 */gpu-nvidia.func) /bin/cat {quote(helper)};;
 */gpu-intel.func) /bin/cat {quote(SOURCE / 'tools/pve/gpu-intel.func')};;
 */gpu-amd.func) /bin/cat {quote(SOURCE / 'tools/pve/gpu-amd.func')};; *) return 89;; esac; }}
pveversion() {{ :; }}
{startup}
trap -p EXIT > {quote(WORK / 'owned-exit-trap')}
exec 9> {quote(WORK / 'cleanup.trace')}
BASH_XTRACEFD=9
PS4='+ '
set -x
'''
cleanup = subprocess.run(['/bin/bash', '-c', cleanup_code], cwd=WORK, text=True, capture_output=True,
                         timeout=15, env=dict(os.environ, TMPDIR=str(space_tmp), NVIDIA_CASE='ok', TERM='dumb'))
after_tmp = {str(p.relative_to(space_tmp)): p.read_bytes().hex() if p.is_file() else None
             for p in space_tmp.rglob('*')}
exit_trap = (WORK / 'owned-exit-trap').read_text()
trace = (WORK / 'cleanup.trace').read_text()
check('private space/glob TMPDIR startup status', 0, cleanup.returncode)
check('private space/glob TMPDIR has no added or lost artifacts', before_tmp, after_tmp)
check('framework EXIT owner retained', "trap -- 'stop_spinner' EXIT\n", exit_trap)
check('actual framework spinner cleanup executes', True, bool(re.search(r'^\++ stop_spinner$', trace, re.M)))
for directory in canaries:
    check('private cleanup preserves ' + directory.name, 'owned canary',
          (directory / 'keep').read_text() if (directory / 'keep').exists() else None)
(WORK / 'cleanup.json').write_text(json.dumps(dict(status=cleanup.returncode, before=before_tmp, after=after_tmp,
                                                stdout=cleanup.stdout, stderr=cleanup.stderr,
                                                exit_trap=exit_trap, trace=trace), indent=2))

(WORK / 'checks.json').write_text(json.dumps(CHECKS, indent=2))
print(f'{len(CHECKS)} NVIDIA checks; {sum(not c["passed"] for c in CHECKS)} failure(s)', flush=True)
raise SystemExit(any(not c['passed'] for c in CHECKS))
