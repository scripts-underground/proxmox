"""Actual manual GPU providers; only lower-level hardware/CT/package effects modeled."""
import os
from pathlib import Path
import shlex
import stat
import subprocess


def exercise_gpu_contract(source, work, run, check, base, sections):
    quote = lambda value: shlex.quote(str(value))
    for name, major, minor in [('dri/renderD128', 226, 128), ('fb0', 29, 0), ('kfd', 247, 0)]:
        path = work / 'dev' / name
        os.mknod(path, stat.S_IFCHR | 0o600, os.makedev(major, minor))
    apt = work / 'apt'
    (apt / 'sources.list.d').mkdir(parents=True)
    (apt / 'sources.list').write_text('deb https://fixture.invalid stable main\n')
    subprocess.run(['mount', '--bind', str(apt), '/etc/apt'], check=True, timeout=10)
    models = work / 'provider-models'
    models.mkdir()
    (models / 'os-release').write_text('ID=debian\n')
    binaries = models / 'bin'
    binaries.mkdir()
    programs = {
        'apt-get': r'''#!/bin/bash
printf 'apt-get %s\n' "$*" >> "$GPU_TEST_ROOT/effects"
case "$1" in update) exit "${GPU_TEST_UPDATE_RC:-0}";; install) exit "${GPU_TEST_INSTALL_RC:-0}";; *) exit 89;; esac
''',
        'adduser': r'''#!/bin/bash
printf 'adduser %s\n' "$*" >> "$GPU_TEST_ROOT/effects"
if [[ "${!#}" == "${GPU_TEST_GROUP:-none}" ]]; then exit "${GPU_TEST_GROUP_RC:-45}"; fi
exit 0
''',
        'grep': r'''#!/bin/bash
args=()
for arg in "$@"; do
 if [[ "$arg" == /etc/os-release ]]; then
  [[ -z "${GPU_TEST_OS_GREP_RC:-}" ]] || exit "$GPU_TEST_OS_GREP_RC"
  arg="$GPU_TEST_ROOT/os-release"
 fi
 args+=("$arg")
done
exec /usr/bin/grep "${args[@]}"
''',
    }
    for name, text in programs.items():
        path = binaries / name
        path.write_text(text)
        path.chmod(0o755)
    shell = models / 'transport.func'
    shell.write_text(r'''
gpu_test_pct() {
 [[ "$1" == exec && "$3" == -- ]] || return 89
 shift 3
 case "$*" in
  *'/etc/os-release'*)
   [[ -z "${GPU_TEST_OS_RC:-}" ]] || return "$GPU_TEST_OS_RC"
   if [[ -n "${GPU_TEST_OS_RAW:-}" ]]; then printf '%s' "$GPU_TEST_OS_RAW"; return 0; fi;;
  *'non-free.list'*) [[ -z "${GPU_TEST_SETUP_RC:-}" ]] || return "$GPU_TEST_SETUP_RC";;
 esac
 "$@"
}
pct() { gpu_test_pct "$@"; }
''')

    def provider(vendor, action, env=None):
        settings = {'ROOT': str(models), **(env or {})}
        exports = ' '.join('GPU_TEST_' + key + '=' + quote(value) for key, value in settings.items())
        return (f'export {exports} PATH={quote(binaries)}:"$PATH"\n'
                f'source {quote(source / "tools/pve/gpu-intel.func")}\n'
                f'source {quote(source / "tools/pve/gpu-amd.func")}\n'
                f'source {quote(shell)}\n'
                'intel_gpu_available() { return 0; }\namd_gpu_available() { return 0; }\n' + action)

    for vendor, function, marker in [
        ('intel', 'passthrough_intel_to_lxc', '/dev/dri/renderD128 dev/dri/renderD128 '),
        ('amd', 'passthrough_amd_to_lxc', '/dev/kfd dev/kfd '),
    ]:
        facts = run('provider-' + vendor + '-native', provider(vendor, function + ' 987654'))
        active = facts['after'].split('[pve:pending]')[0]
        check(vendor + ' actual provider native status', 0, facts['status'])
        check(vendor + ' actual provider active consumer', True, marker in active)
        check(vendor + ' snapshot is not the configuration target', False,
              marker in facts['after'].split('[saved]')[-1])
        repeated = run('provider-' + vendor + '-repeat', provider(vendor, function + ' 987654'), text=facts['after'])
        check(vendor + ' actual provider idempotency', (0, facts['after']),
              (repeated['status'], repeated['after']))
        if vendor == 'amd':
            check('AMD allowance uses actual KFD metadata', True, 'c 247:* rwm' in active)
            check('AMD does not invent fixed KFD major', False, 'c 238:* rwm' in active)
            foreign = base + '# foreign mention /dev/kfd\n' + sections
            mention = run('provider-amd-comment', provider(vendor, function + ' 987654'), text=foreign)
            check('AMD comment is not active idempotency evidence', True,
                  marker in mention['after'].split('[pve:pending]')[0])
        failed = run('provider-' + vendor + '-publication', provider(vendor, function + ' 987654'), scenario='write-fail')
        check(vendor + ' native publication failure propagates', True, failed['status'] != 0)
        check(vendor + ' publication failure has no applied success', False, 'applied' in failed['stdout'].lower())
        device_major = 226 if vendor == 'intel' else 247
        denied = base + f'lxc.cgroup2.devices.allow: a\nlxc.cgroup2.devices.deny: c {device_major}:* w\n' + sections
        result = run('provider-' + vendor + '-foreign-denial', provider(vendor, function + ' 987654'), text=denied)
        check(vendor + ' common policy refuses foreign denial', (True, denied), (result['status'] != 0, result['after']))
        device = '/dev/dri/renderD128' if vendor == 'intel' else '/dev/kfd'
        readonly = base + 'dev4: ' + device + ',deny-write=1\n' + sections
        result = run('provider-' + vendor + '-readonly', provider(vendor, function + ' 987654'), text=readonly)
        check(vendor + ' common policy preserves structured intent', (True, readonly), (result['status'] != 0, result['after']))
        (models / 'os-release').write_text('ID=alpine\n')
        (models / 'effects').unlink(missing_ok=True)
        try:
            result = run('provider-' + vendor + '-alpine', provider(vendor, 'install_' + vendor + '_tools_in_ct 987654'))
            check(vendor + ' typed Alpine skip is successful', 0, result['status'])
            check(vendor + ' typed Alpine skip has no package effects', False, (models / 'effects').exists())
        finally:
            (models / 'os-release').write_text('ID=debian\n')

        faults = [
            ('os-transport-one', {'OS_RC': '1'}, 1),
            ('os-transport', {'OS_RC': '43'}, 43),
            ('os-read', {'OS_GREP_RC': '2'}, 2),
            ('os-malformed', {'OS_RAW': 'not-a-typed-os'}, 65),
            ('update', {'UPDATE_RC': '41'}, 41),
            ('install', {'INSTALL_RC': '42'}, 42),
        ]
        if vendor == 'intel':
            faults.append(('setup', {'SETUP_RC': '44'}, 44))
        else:
            faults.extend([('video-group', {'GROUP': 'video', 'GROUP_RC': '45'}, 45),
                           ('render-group', {'GROUP': 'render', 'GROUP_RC': '46'}, 46)])
        for name, env, status in faults:
            code = provider(vendor, 'install_' + vendor + '_tools_in_ct 987654', env)
            result = run('provider-' + vendor + '-' + name, code)
            check(vendor + ' actual ' + name + ' retains status', status, result['status'])
            check(vendor + ' actual ' + name + ' has no Installed claim', False,
                  'installed' in result['stdout'].lower())
        if vendor == 'intel':
            result = run('provider-intel-optional-group', provider(vendor, 'install_intel_tools_in_ct 987654',
                         {'GROUP': 'render', 'GROUP_RC': '46'}))
            check('Intel intentional optional membership remains returning success', 0, result['status'])
            check('Intel optional membership failure is visible', True, '46' in result['stderr'])

    saved = sections[sections.index('[saved]'):]
    for name, active, pending, allowed in [
        ('lxc-replacement', '', 'lxc.mount.entry: /dev/pending dev/pending none bind\n', False),
        ('dev-change', '', 'dev4: /dev/nvidia2,deny-write=1\n', False),
        ('delete-lxc', '', 'delete: lxc\n', False),
        ('forced-delete-lxc', '', 'delete: !lxc\n', False),
        ('delete-dev', 'dev4: /dev/nvidia2\n', 'delete: dev4\n', False),
        ('ostype-change', '', 'ostype: ubuntu\n', False),
        ('privilege-change', '', 'unprivileged: 1\n', False),
        ('console-change', '', 'console: 0\n', False),
        ('console-delete-change', 'console: 0\n', 'delete: console\n', False),
        ('unrelated', '', 'memory: 1024\ndelete: hostname; swap\n', True),
        ('defaults', 'console: 1\n', 'unprivileged: 0\ndelete: !console, dev99\n', True),
        ('device-noop', 'dev4: /dev/nvidia2\n', 'dev4: /dev/nvidia2\n', True),
        ('device-property-noop', 'dev4: /dev/nvidia2,deny-write=0,gid=44\n', 'dev4: /dev/nvidia2,gid=44,deny-write=0\n', True),
        ('delete-and-replace-noop', 'dev4: /dev/nvidia2\n', 'delete: !dev4\ndev4: /dev/nvidia2\n', True),
        ('privilege-default-delete', '', 'delete: !unprivileged\n', True),
        ('ostype-noop', '', 'ostype: debian\n', True),
    ]:
        original = base + active + '\n[pve:pending]\n' + pending + '\n' + saved
        facts = run('pending-' + name, 'nvidia_lxc_passthrough 987654 7', text=original)
        check('pending ' + name + ' candidate admission', allowed, facts['status'] == 0)
        if not allowed:
            check('pending ' + name + ' refused bytes preserved', original, facts['after'])
        else:
            check('pending ' + name + ' native active consumer', True,
                  '/dev/nvidia7 dev/nvidia7 ' in facts['after'].split('[pve:pending]')[0])
            check('pending ' + name + ' pending bytes/values retained', True,
                  all(line in facts['after'].split('[pve:pending]')[1].split('[saved]')[0]
                      for line in pending.splitlines()))
    no_lxc = ''.join(line + '\n' for line in base.splitlines() if not line.startswith('lxc.'))
    original = no_lxc + '\n[pve:pending]\ndelete: lxc\n\n' + saved
    facts = run('pending-candidate-created-deletion', 'nvidia_lxc_passthrough 987654 7', text=original)
    check('candidate-created lxc makes pending deletion material', (True, original), (facts['status'] != 0, facts['after']))
    seed = run('pending-lxc-noop-seed', 'nvidia_lxc_passthrough 987654 7')
    active = seed['after'].split('[pve:pending]')[0]
    pairs = ''.join(line + '\n' for line in active.splitlines() if line.startswith('lxc.'))
    original = active + '[pve:pending]\nmemory: 1024\n' + pairs + '\n' + saved
    facts = run('pending-lxc-exact-noop', 'nvidia_lxc_passthrough 987654 7', text=original)
    check('pending exact ordered lxc no-op is admitted', 0, facts['status'])
    check('pending exact ordered lxc no-op retains active consumer', True,
          '/dev/nvidia7 dev/nvidia7 ' in facts['after'].split('[pve:pending]')[0])
