#!/usr/bin/env bash
set -euo pipefail
systemd-detect-virt --vm -q || exit 77
exec python3 - "$(dirname "${BASH_SOURCE[0]}")/.." << 'PY'
import json
import os
import pathlib
import re
import shutil
import stat
import subprocess
import time

assert os.geteuid() == 0
assert pathlib.Path('/sys/class/dmi/id/product_uuid').read_text().strip().lower() == '4be13420-4459-4200-a1c2-7ac7232ac650'
source = pathlib.Path(os.sys.argv[1]).resolve()
area = pathlib.Path('/srv/scripts-underground-tests/evidence')/('gpu-runtime-'+str(time.time_ns()))
area.mkdir(mode=0o700)
def extract(path, names):
    text = path.read_text()
    rows = []
    for name in names:
        match = re.search(r'^'+re.escape(name)+r'\(\) [({]\n.*?^[})]', text, re.M | re.S)
        assert match is not None, name
        rows.append(match.group(0))
    return '\n'.join(rows)
tools = source/'misc/tools.func'
definitions = extract(tools, ['setup_hwaccel', '_setup_gpu_permissions', '_setup_intel_legacy'])
for name in ['_hwaccel_optional_command', '_hwaccel_apt_optional']:
    if re.search(r'^'+name+r'\(\)', tools.read_text(), re.M):
        definitions += '\n'+extract(tools, [name])
definitions += '\n'+extract(source/'misc/core.func', ['color', 'formatting', 'silent'])
results = []
for scenario in ['nvidia-one-only', 'manual-nvidia', 'empty-dri', 'mapped-intel', 'quiet-legacy-fallback',
                  'nvidia-version-exact', 'nvidia-version-mismatch', 'nvidia-version-query-error',
                  'nvidia-ubuntu-exact', 'nvidia-ubuntu-transition', 'nvidia-plan-prefix-error']:
    case = area/scenario
    case.mkdir(mode=0o700)
    for name in ['dev', 'sys', 'etc', 'tmp', 'home', 'proc-driver']:
        (case/name).mkdir(mode=0o700)
    (case/'dev/dri').mkdir()
    for name, major, minor in [('null', 1, 3), ('zero', 1, 5)]:
        os.mknod(case/'dev'/name, stat.S_IFCHR | 0o666, os.makedev(major, minor))
    for name, target in [('fd', '/proc/self/fd'), ('stdin', 'fd/0'), ('stdout', 'fd/1'), ('stderr', 'fd/2')]:
        os.symlink(target, case/'dev'/name)
    if scenario in {'nvidia-one-only', 'manual-nvidia'}:
        for index, name in enumerate(['nvidia1', 'nvidiactl', 'nvidia-uvm']):
            os.mknod(case/'dev'/name, stat.S_IFCHR | 0o660, os.makedev(240, index))
    if scenario == 'mapped-intel':
        os.mknod(case/'dev/dri/renderD128', stat.S_IFCHR | 0o660, os.makedev(240, 10))
        vendor = case/'sys/class/drm/renderD128/device'
        vendor.mkdir(parents=True)
        (vendor/'vendor').write_text('0x8086\n')
    for name in ['group', 'passwd', 'nsswitch.conf', 'os-release']:
        (case/'etc'/name).write_bytes((pathlib.Path('/etc')/name).read_bytes())
    shutil.copytree('/etc/alternatives', case/'etc/alternatives', symlinks=True)
    for name in ['apt/sources.list.d', 'apt/preferences.d', 'profile.d', 'ld.so.conf.d', 'keyrings']:
        (case/'etc'/name).mkdir(parents=True, exist_ok=True)
    (case/'etc/apt/sources.list.d/cuda-user.sources').write_text('administrator source sentinel\n')
    (case/'proc-driver/nvidia').mkdir()
    (case/'proc-driver/nvidia/version').write_text('NVRM version: NVIDIA UNIX x86_64 Kernel Module 550.163.01\n')
    (case/'actions').write_text('')
    header = definitions+r'''
STD=''
color
formatting
msg_info() { :; }
msg_ok() { :; }
msg_debug() { :; }
msg_custom() { :; }
msg_warn() { printf 'WARN %s\n' "$*" >&2; }
msg_error() { printf 'ERROR %s\n' "$*" >&2; }
get_active_logfile() { printf '%s/log\n' "$CASE"; }
explain_exit_code() { printf 'fixture package failure\n'; }
get_os_info() { case "$1" in id) printf ubuntu ;; codename) printf jammy ;; version) printf 22.04 ;; esac; }
lspci() { printf '%s\n' '0000:00:02.0 VGA controller: Intel GPU' '0000:01:00.0 VGA controller: AMD GPU' '0000:02:00.0 3D controller: NVIDIA GPU'; }
lscpu() { printf 'Vendor ID: AuthenticAMD\n'; }
ldconfig() { printf '%s\n' 'libcuda.so.1 (libc6,x86-64) => /usr/lib/libcuda.so.1' 'libvulkan.so.1 (libc6,x86-64) => /usr/lib/libvulkan.so.1'; }
cache_installed_version() { printf 'cache %s\n' "$*" >> "$CASE/actions"; }
usermod() { printf 'membership %s\n' "$*" >> "$CASE/actions"; }
_setup_intel_arc() { printf 'stack intel-arc\n' >> "$CASE/actions"; }
_setup_intel_modern() { printf 'stack intel\n' >> "$CASE/actions"; }
_setup_amd_gpu() { printf 'stack amd\n' >> "$CASE/actions"; }
_setup_amd_apu() { printf 'stack amd-apu\n' >> "$CASE/actions"; }
_setup_nvidia_gpu() { printf 'stack nvidia\n' >> "$CASE/actions"; }
apt() {
  printf 'apt %s\n' "$*" >> "$CASE/actions"
  if [[ "$*" == *--simulate* ]]; then
    if [[ "$SCENARIO" == nvidia-ubuntu-transition && "$*" == *0ubuntu0.24.04.2* ]]; then
      printf 'Inst libnvidia-compute-580 (580.999.01-0ubuntu1 fixture [amd64])\n'
    else
      for arg in "$@"; do
        if [[ "$arg" == *=* && "$arg" != -* ]]; then printf 'Inst %s (%s fixture [amd64])\n' "${arg%%=*}" "${arg#*=}"; fi
      done
    fi
    if [[ "$SCENARIO" == nvidia-plan-prefix-error ]]; then printf 'fault plan status=17\n' >> "$CASE/actions"; return 17; fi
  fi
  if [[ "$*" == *i965-va-driver* ]]; then printf 'fault apt status=17\n' >> "$CASE/actions"; return 17; fi
}
apt-get() { apt "$@"; }
apt-cache() {
  if [[ "$1" == madison ]]; then
    if [[ "$SCENARIO" == nvidia-ubuntu-* ]]; then
      [[ "$2" == libnvidia-compute-550 ]] || return 0
      if [[ "$SCENARIO" == nvidia-ubuntu-transition && ! -f "$CASE/repo-ready" ]]; then
        printf '%s | 550.163.01-0ubuntu0.24.04.2 | fixture\n' "$2"
      else
        printf '%s | 550.163.01-0ubuntu1 | fixture\n' "$2"
      fi
    elif [[ "$SCENARIO" == nvidia-version-mismatch ]]; then
      printf '%s | 590.110.01-1 | fixture\n' "$2"
    else
      printf '%s | 550.179.01-1 | fixture\n%s | 550.163.01-1 | fixture\n' "$2" "$2"
    fi
    if [[ "$SCENARIO" == nvidia-version-query-error ]]; then printf 'fault madison status=17\n' >> "$CASE/actions"; return 17; fi
  else printf 'Candidate: (none)\n'; fi
}
setup_deb822_repo() { printf 'repository %s\n' "$*" >> "$CASE/actions"; }
_hwaccel_cuda_repo() { printf 'repository %s\n' "$*" >> "$CASE/actions"; printf 'ready\n' > "$CASE/repo-ready"; }
_add_debian_nonfree() { :; }
printf '%s\n' 'parent-entered' > "$CASE/parent-status"
'''
    expression = 'setup_hwaccel root; printf "%s\\n" "${HWACCEL_VENDOR-unset}" > "$CASE/vendor"'
    if scenario == 'quiet-legacy-fallback':
        expression = 'STD=silent; _setup_intel_legacy ubuntu jammy; printf "continued\\n" > "$CASE/parent-status"'
    if scenario.startswith(('nvidia-version-', 'nvidia-ubuntu-')) or scenario=='nvidia-plan-prefix-error':
        header += '\n'+extract(tools, ['_setup_nvidia_gpu'])
        for name in ['_hwaccel_nvidia_version','_hwaccel_nvidia_plan']:
            if re.search(r'^'+name+r'\(\)', tools.read_text(), re.M): header += '\n'+extract(tools, [name])
        expression = '_setup_nvidia_gpu debian trixie 13'
        if scenario.startswith('nvidia-ubuntu-'): expression='_setup_nvidia_gpu ubuntu noble 24.04'
    code = 'import pathlib,subprocess,sys\n'
    code += 'case=pathlib.Path('+repr(str(case))+')\n'
    code += 'for name in ["dev","sys","etc","tmp"]: subprocess.run(["mount","--bind",str(case/name),"/"+name],check=True)\n'
    code += 'subprocess.run(["mount","--bind",str(case/"proc-driver"),"/proc/driver"],check=True)\n'
    code += 'command='+repr(header+'\nset -e\n'+expression)+'\n'
    code += 'raise SystemExit(subprocess.run(["bash","-c",command],env=dict(__import__("os").environ,CASE=str(case),SCENARIO='+repr(scenario)+',HOME=str(case/"home"),ENABLE_GPU="yes",GPU_TYPE='+repr('INTEL' if scenario == 'mapped-intel' else 'NVIDIA')+',INSTALL_NVIDIA_DRIVERS='+repr('no' if scenario == 'manual-nvidia' else 'yes')+'),capture_output=False).returncode)\n'
    native = subprocess.run(['unshare', '--mount', '--propagation', 'private', 'python3', '-c', code],
                            input='', capture_output=True, text=True, timeout=30)
    actions = (case/'actions').read_text().splitlines()
    checks = []
    def check(name, expected, actual):
        checks.append({'name': name, 'expected': expected, 'actual': actual, 'passed': expected == actual})
    check('native parent result', 0, native.returncode)
    stacks = [row for row in actions if row.startswith('stack ')]
    if scenario == 'nvidia-one-only': check('only mapped nvidia1 stack configured', ['stack nvidia'], stacks)
    if scenario in {'manual-nvidia', 'empty-dri'}: check('unmapped/manual stacks never provisioned', [], stacks)
    if scenario == 'mapped-intel': check('unrelated visible PCI vendors never provisioned', ['stack intel'], stacks)
    if scenario in {'nvidia-one-only', 'manual-nvidia', 'mapped-intel', 'empty-dri'}:
        check('configured prerequisite vendor follows mapped nodes', 'intel' if scenario == 'mapped-intel' else 'none' if scenario == 'empty-dri' else 'nvidia',
              (case/'vendor').read_text().strip() if (case/'vendor').exists() else None)
    if scenario == 'quiet-legacy-fallback':
        check('actual failed batch reached', True, any(row.startswith('apt ') and 'i965-va-driver' in row for row in actions))
        check('healthy packages attempted individually after quiet failure', True, any(row == 'apt -y install va-driver-all' for row in actions))
        check('quiet optional failure cannot exit parent', 'continued\n', (case/'parent-status').read_text())
    if scenario.startswith(('nvidia-version-','nvidia-ubuntu-')) or scenario=='nvidia-plan-prefix-error':
        installs = [row for row in actions if row.startswith('apt ') and 'install' in row and '--simulate' not in row and ('libcuda' in row or 'libnvidia-compute' in row)]
        if scenario == 'nvidia-version-exact':
            check('exact full host version preferred over newer same-series version', True, bool(installs) and all('550.163.01-1' in row and '550.179.01' not in row for row in installs))
        elif scenario.startswith('nvidia-ubuntu-'):
            check('Ubuntu package roles and coherent real-series revision',True,bool(installs) and all(
                'libnvidia-compute-550=550.163.01-0ubuntu1' in row and 'libnvidia-encode-550=' in row and 'libnvidia-decode-550=' in row and
                'libcuda1=' not in row and '580' not in row and '0ubuntu0.24.04.2' not in row for row in installs))
            if scenario=='nvidia-ubuntu-transition':
                check('actual foreign-series transition plan observed and rejected',True,any('--simulate' in row and '0ubuntu0.24.04.2' in row for row in actions))
        else:
            check('mismatching or failed version query never authorizes userspace install', [], installs)
        check('administrator repository preserved', 'administrator source sentinel\n', (case/'etc/apt/sources.list.d/cuda-user.sources').read_text())
        if scenario == 'nvidia-version-query-error': check('actual prefix/error query delivered', True, 'fault madison status=17' in actions)
        if scenario == 'nvidia-plan-prefix-error': check('actual prefix/error plan delivered', True, 'fault plan status=17' in actions)
    document = {'scenario': scenario, 'native_status': native.returncode, 'checks': checks, 'actions': actions,
                'stdout': native.stdout, 'stderr': native.stderr, 'status': 'PASS' if all(row['passed'] for row in checks) else 'FAIL'}
    (case/'result.json').write_text(json.dumps(document, indent=2)+'\n')
    results.append(document)
    print(document['status']+' '+scenario, flush=True)
result = {'status': 'PASS' if all(row['status'] == 'PASS' for row in results) else 'FAIL', 'results': results,
          'scope': 'actual dispatcher/legacy/silent with native private nodes; modeled driver and package callbacks, not hardware proof'}
(area/'results.json').write_text(json.dumps(result, indent=2)+'\n')
print('EVIDENCE '+str(area/'results.json'))
raise SystemExit(0 if result['status'] == 'PASS' else 2)
PY
