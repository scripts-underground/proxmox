"""Cold writer/install/stage/recovery bodies; native PVE/OS effects are models."""
import json
import os
from pathlib import Path
import re
import shlex
import shutil
import subprocess
import sys
import tempfile

source, owner = map(Path, sys.argv[1:])
build = (owner / 'misc/build.func').read_text()
core = (owner / 'misc/core.func').read_text()
work = Path(tempfile.mkdtemp(prefix='post-build-order.', dir=os.environ['TMPDIR']))
checks = []
q = lambda value: shlex.quote(str(value))


def function(text, name):
    match = re.search(r'(?ms)^(?:function )?' + re.escape(name) + r'\(\) \{\n.*?^\}', text)
    return match.group() if match else ''


def check(label, expected, actual):
    passed = expected == actual
    checks.append(dict(label=label, expected=expected, actual=actual, passed=passed))
    print(('PASS ' if passed else 'FAIL ') + label +
          ('' if passed else f': expected {expected!r}, got {actual!r}'), flush=True)


# Preserve the actual stage owner, its caller syntax and its full result/recovery
# region. Hardware/network/base-package preparation is explicitly outside this
# fixture. The install process is a cold command emitted by the actual writer.
body = function(build, 'build_container')
prefix = body[:body.index('  NET_STRING=')]
creator_call, = [line for line in body.splitlines() if line.strip().startswith('create_lxc_container')]
install = body[body.index('  local install_tmpdir='):]
startup = body[body.index('  # Wait for network (skip for Alpine initially)'):
               body.index('  # Function to get correct GID inside container')]
creator = function(build, 'create_lxc_container')
creator_end = creator[creator.index('  # Verify container exists'):]
bootstrap = function(build, '_lxc_bootstrap')

cases = [
    ('normal', '', 0), ('absent', '', 0), ('hook-command', '', 37),
    ('hook-return', '', 38), ('create-failure', '', 43), ('install-failure', '', 100),
    ('repair', '4\n', 0), ('repair-failure', '4\n', 100),
    ('repair-preparation', '4\n', 47), ('repair-hook-failure', '4\n', 37),
    ('verbose-rebuild', '3\n', 0), ('oom-rebuild', '4\n', 0),
    ('dns-rebuild', '4\n', 0), ('rebuild-failure', '3\n', 100),
    ('authentik', '', 0), ('urbackupserver', '', 0),
    ('restart-delay', '', 0), ('restart-timeout', '', 1), ('restart-producer', '', 1),
    ('restart-transient', '', 0), ('startup-transient', '', 0),
    ('repair-restart-timeout', '4\n', 1),
]

try:
    for mode in ('yes', 'no'):
        for name, answer, expected in cases:
            c = work / (name + '-' + mode)
            (c / 'cache').mkdir(parents=True)
            (c / 'receiver').mkdir()
            (c / 'config').mkdir()
            (c / 'config/9876.conf').write_text('rootfs: modeled\n')
            (c / 'events').touch()
            # Tiny offline bootstrap/OS libraries are explicit fixture models;
            # assembly, baked hook, strict cold execution and host result logic
            # remain real. No extracted install hook crosses the exec boundary.
            (c / 'cache/core.func').write_text('load_functions() { :; }; color() { :; }\n')
            (c / 'cache/error_handler.func').write_text('catch_errors() { :; }\n')
            (c / 'cache/install.func').write_text('\n'.join(
                f'{fn}() {{ :; }}' for fn in ('setup_lxc', 'setting_up_container',
                'network_check', 'update_os', 'motd_ssh', 'cleanup_lxc')) + '\n')
            (c / 'cache/tools.func').write_text('setup_uv() { :; }\n')
            (c / 'cache/github.func').write_text('clone_and_deploy_gh_commit() { :; }\n')
            (c / 'cache/ssh-access.func').write_bytes((owner / 'misc/ssh-access.func').read_bytes())
            final_creator = creator_end.replace('/etc/pve/lxc/', str(c / 'config') + '/')
            consumer = ''
            postinstall = 'post_install_script() { record postinstall; printf "URL=http://%s:55414\\n" "$IP"; }'
            if name in ('authentik', 'urbackupserver') or 'restart-' in name:
                app = 'urbackupserver' if 'restart-' in name else name
                app_source = (source / f'scripts/lxc/{app}.sh').read_text()
                hook = function(app_source, 'post_build_script')
                consumer = hook.replace('post_build_script() {', 'post_build_script() {\n  record "post:$CTID"', 1)
                postinstall = function(app_source, 'post_install_script').replace(
                    'post_install_script() {', 'post_install_script() {\n  record postinstall', 1)
            finalization = function(build, 'complete_install').replace(
                '/etc/systemd/system/ping-instances.service', str(c / 'absent-ping.service'))
            script = f'''#!/usr/bin/env bash
set -Eeuo pipefail
c={q(c)}
export c CASE_NAME={q(name)}
source {q(owner / 'misc/core.func')}
source {q(owner / 'misc/bundle.func')}
{bootstrap}
{function(build, '_prepare_container_bundles')}
{function(build, '_finish_container_build')}
{function(build, '_apply_lxc_ssh_access')}
{function(build, '_wait_for_container_network')}
{finalization}
{prefix}
  CONTAINER_INSTALLING=true
{creator_call}
  pct start "$CTID"
{startup}
{install}
create_lxc_container() {{
  pct create "$CTID"
{final_creator}
record() {{ printf '%s\\n' "$*" >> "$c/events"; }}
variables() {{ :; }}; color() {{ :; }}; render_header() {{ :; }}
catch_errors() {{ set -Eeuo pipefail; trap error_handler ERR; }}
# Diagnostics are a model; the actual ordinary call/strict failure boundary is
# not replaced with a conditional or a status-extracting wrapper.
error_handler() {{ local status=$?; record "error:$status"; exit "$status"; }}
_lxc_setup() {{ :; }}
{postinstall}
sleep() {{ record "sleep:$1"; }}
msg_info() {{ :; }}; msg_debug() {{ :; }}; msg_warn() {{ :; }}; msg_dev() {{ :; }}
msg_error() {{ printf '%s\\n' "$*"; }}
msg_ok() {{ record "ok:$*"; }}
_framework_cache_ensure() {{ :; }}
_framework_cache_dir() {{ printf '%s' "$c/cache"; }}
_prepare_receiving_context() {{ :; }}
_receiving_exec() {{ record repair-packages; }}
get_valid_container_id() {{ record allocate; printf '9876\\n'; }}
pct() {{
  case "$1" in
    create)
      record create
      [[ "$CASE_NAME" != create-failure ]] || return 43
      rm -f "$c/running" "$c/installed"
      ;;
    start)
      record start
      [[ ! -e "$c/running" ]] || return 255
      touch "$c/running"
      ;;
    stop) record stop; rm -f "$c/running" ;;
    destroy) record destroy ;;
    status) printf 'status: running\\n' ;;
    list) printf '9876 modeled\\n' ;;
    push) cp -- "$3" "$4" ;;
    pull) return 1 ;;
    set)
      record "set:$*"
      if [[ "$3" == -description ]]; then
        record describe; record "describe-IP:$IP"; printf '%s' "$DESCRIPTION" > "$c/description"
      fi
      ;;
    reboot)
      record "reboot:$CTID"; test -f "$c/installed"
      touch "$c/reboot"; printf '0\\n' > "$c/address-polls"
      ;;
    exec)
      shift 2
      [[ "${{1-}}" != -- ]] || shift
      case "$1" in
        ip)
          local polls=0
          [[ ! -e "$c/address-polls" ]] || read -r polls < "$c/address-polls"
          if [[ "${{2-}}" != -6 ]]; then
            polls=$((polls + 1)); printf '%s\\n' "$polls" > "$c/address-polls"
          fi
          [[ "$CASE_NAME" != restart-producer || ! -e "$c/reboot" ]] || return 29
          if [[ "$CASE_NAME" == startup-transient ||
                ( "$CASE_NAME" == restart-transient && -e "$c/reboot" ) ]]; then
            [[ "$polls" -ge 3 ]] || return 29
          fi
          [[ "${{2-}}" != -6 ]] || return 0
          if [[ -e "$c/reboot" ]]; then
            [[ "$CASE_NAME" != *restart-timeout ]] || return 0
            [[ "$CASE_NAME" != restart-delay || "$polls" -ge 3 ]] || return 0
          fi
          printf '    inet 192.0.2.87/24 scope global eth0\\n'
          ;;
        ping | ping6) return 0 ;;
        test) return 1 ;;
        bash) record data-copy; test -f "$c/installed" ;;
        systemctl) record services; test -f "$c/installed" ;;
        *) command "$@" ;;
      esac ;;
    *) return 97 ;;
  esac
}}
build_bundle_original=$(declare -f build_bundle)
eval "${{build_bundle_original/build_bundle ()/fixture_build_bundle ()}}"
build_bundle() {{
  printf '%s|%s|%s\\n' "${{5-}} ${{6-}}" "${{7-}} ${{8-}}" "${{9-}} ${{10-}}" >> "$c/preparations"
  if [[ "$CASE_NAME" == repair-preparation && -e "$c/attempt" ]]; then return 47; fi
  fixture_build_bundle "$@"
}}
install_script() {{
  local attempt=0 status=0
  [[ ! -e "$c/attempt" ]] || read -r attempt < "$c/attempt"
  attempt=$((attempt + 1)); printf '%s\\n' "$attempt" > "$c/attempt"
  case "$CASE_NAME:$attempt" in
    install-failure:* | repair-failure:* | rebuild-failure:2) status=100 ;;
    repair*:1) status=100 ;;
    verbose-rebuild:1 | rebuild-failure:1) status=1 ;;
    oom-rebuild:1) status=137 ;;
    dns-rebuild:1) status=6 ;;
  esac
  printf 'install:%s\\n' "$status" >> "$c/events"
  ((status == 0)) || return "$status"
  printf installed > "$c/installed"
}}
lxc-attach() {{
  shift 3
  command "$@"
}}
post_build_script() {{
  record "post:$CTID"
  if [[ -f "$c/installed" ]]; then record post-ready; else record post-before-install; fi
  case "$CASE_NAME" in
    hook-command | repair-hook-failure) $STD bash -c 'exit 37'; record MASKED ;;
    hook-return) return 38 ;;
  esac
  record post-finished
}}
{consumer}
[[ "$CASE_NAME" != absent ]] || unset -f post_build_script
APP=Probe NSAPP=probe REPO_BASE=offline CTID=9876 CT_TYPE=1 SESSION_ID=postbuild CONTAINER_STORAGE=modeled
var_cpu=4 var_ram=8192
var_lxc_tmpdir="$c/receiver" var_os=debian RAM_SIZE=1024 CORE_COUNT=1 DISK_SIZE=8
VERBOSE={q(mode)} BUILD_LOG="$c/build.log" combined_log="$c/combined.log"
_HOST_LOGFILE="$c/quiet.log"
DEV_MODE_KEEP=false
case "$CASE_NAME" in install-failure) DEV_MODE_KEEP=true ;; esac
DEV_MODE_BREAKPOINT=false DEV_MODE_MOTD=false
GN='' CL='' BL='' TAB='' YW='' RD='' YWB='' HOLD='' DGN='' BFR='' CM='' INFO='' CREATING='' GATEWAY='' BGN=''
IP=198.51.100.99 BRG=vmbr0
set_std_mode
_lxc_bootstrap --script-id probe --
record SUCCESS
'''
            command = c / 'cold.sh'
            command.write_text(script)
            result = subprocess.run(['bash', str(command)], cwd=c, input=answer,
                                    text=True, capture_output=True, timeout=30,
                                    env=dict(os.environ, TMPDIR=str(c)))
            (c / 'stdout').write_text(result.stdout)
            (c / 'stderr').write_text(result.stderr)
            events = (c / 'events').read_text().splitlines()
            label = name + '/' + mode
            check(label + ' exact status', expected, result.returncode)
            posts = [i for i, value in enumerate(events) if value.startswith('post:')]
            should_post = name not in ('absent', 'create-failure', 'install-failure',
                                       'repair-failure', 'repair-preparation', 'rebuild-failure')
            check(label + ' exactly-once successful-install dispatch', int(should_post), len(posts))
            if posts:
                check(label + ' install success precedes hook', True,
                      'install:0' in events[:posts[0]])
            check(label + ' no masked intermediate failure', False, 'MASKED' in events)
            if expected == 0:
                for marker in ('describe', 'postinstall', 'SUCCESS'):
                    check(label + ' successful finalization marker ' + marker, True, marker in events)
            else:
                for marker in ('describe', 'postinstall', 'SUCCESS'):
                    check(label + ' no finalization marker after failure ' + marker, False, marker in events)
            if expected == 0 and posts:
                check(label + ' hook before finalization', True,
                      'describe' in events and posts[0] < events.index('describe'))
            if name in ('verbose-rebuild', 'oom-rebuild', 'dns-rebuild'):
                check(label + ' both rebuild preparations preserve provenance', True,
                      len((c / 'preparations').read_text().splitlines()) == 2 and
                      set((c / 'preparations').read_text().splitlines()) ==
                      {'--script-id probe|-- --requirements|4 8192'})
            if name == 'authentik':
                check(label + ' installed data and services consumed', True,
                      'data-copy' in events and 'services' in events)
            if name == 'urbackupserver':
                check(label + ' installed CT reboot effect', True, 'reboot:9876' in events)
            if 'restart-' in name:
                check(label + ' one real hook reboot model', 1, events.count('reboot:9876'))
                if expected == 0:
                    check(label + ' printed shipped URL consumes eventual address', True,
                          '192.0.2.87:55414' in result.stdout)
                    check(label + ' description consumes readiness before publication', True,
                          'describe-IP:192.0.2.87' in events and (c / 'description').is_file())
                    check(label + ' only existing wait retries delayed address', 2, events.count('sleep:1'))
                else:
                    check(label + ' no partial URL or description after failure', True,
                          ':55414' not in result.stdout and not (c / 'description').exists())
                    check(label + ' no completion success after failure', False,
                          any(value.startswith('ok:Completed Successfully!') for value in events))
                    if expected == 1:
                        check(label + ' original timeout diagnostic', True,
                              'No IP assigned to CT 9876 after 20s' in result.stdout)
                        check(label + ' original twenty one-second waits', 20, events.count('sleep:1'))
                        check(label + ' no premature installation completion', False,
                              any('Installation completed successfully' in value for value in events))
            if name == 'startup-transient':
                check(label + ' startup transport failures retry before install', True,
                      events.count('sleep:1') == 2 and events.index('sleep:1') < events.index('install:0'))
            if result.returncode != expected:
                print('DIAG ' + result.stderr[-1000:], flush=True)
    # Both address families use one checked-probe owner, including IPv6 DAD.
    for probe in ('v6-transport', 'v6-tentative', 'v6-dadfailed'):
        c = work / probe
        c.mkdir()
        script = f'''set -Eeuo pipefail
c={q(c)}
CTID=9876 BRG=vmbr0 YW='' CL=''
trap 'exit $?' ERR
msg_info() {{ :; }}; msg_error() {{ printf '%s\\n' "$*"; }}
sleep() {{ printf '%s\\n' "$1" >> "$c/sleeps"; }}
pct() {{
  local polls=0
  [[ ! -e "$c/polls" ]] || read -r polls < "$c/polls"
  if [[ "$5" == -4 ]]; then
    printf '%s\\n' "$((polls + 1))" > "$c/polls"
    return 0
  fi
  if [[ "$polls" -lt 3 ]]; then
    case {q(probe)} in
      v6-transport) printf '    inet6 2001:db8::bad/64 scope global\\n'; return 29 ;;
      v6-tentative) printf '    inet6 2001:db8::bad/64 scope global tentative\\n'; return 0 ;;
      v6-dadfailed) printf '    inet6 2001:db8::bad/64 scope global dadfailed\\n'; return 0 ;;
    esac
  fi
  printf '    inet6 2001:db8::87/64 scope global\\n'
}}
{function(build, '_wait_for_container_network')}
IP=stale
_wait_for_container_network IP
printf '%s\\n' "$IP" > "$c/address"
'''
        result = subprocess.run(['bash', '-c', script], cwd=c, capture_output=True,
                                text=True, timeout=15, env=dict(os.environ, TMPDIR=str(c)))
        check(probe + ' later usable address reached', 0, result.returncode)
        check(probe + ' only usable raw address published', '2001:db8::87\n',
              (c / 'address').read_text() if (c / 'address').exists() else '')
        check(probe + ' existing wait retries twice', ['1', '1'],
              (c / 'sleeps').read_text().splitlines() if (c / 'sleeps').exists() else [])
    # Actual creator retry/upgrade region, including both storage branches. Its
    # intentional status protocol must survive restoration of stage errexit.
    retry_region = creator[creator.index('  # First attempt'):]
    for storage in ('local', 'su-files'):
        for upgrade_status in (0, 2, 3, 'verbose', 'declined'):
            c = work / f'creator-{storage}-{upgrade_status}'
            c.mkdir()
            (c / '9876.conf').write_text('rootfs: modeled\n')
            region = retry_region.replace('/etc/pve/lxc/', str(c) + '/')
            script = f'''set -Eeuo pipefail
c={q(c)}
CTID=9876 TEMPLATE_STORAGE={q(storage)} TEMPLATE=debian-template PCT_OPTIONS=''
LOGFILE="$c/create.log" BL='' CL='' GN=''
trap 'printf "%s\\n" "$-" > "$c/exit-flags"' EXIT
msg_info() {{ :; }}; msg_debug() {{ :; }}; msg_warn() {{ :; }}
msg_ok() {{ printf '%s\\n' "$*" >> "$c/success"; }}
msg_error() {{ printf '%s\\n' "$*"; }}
pct() {{
  case "$1" in
    create) printf '%s\\n' {q('unsupported Debian version' if isinstance(upgrade_status, int) else 'creation failed')}; return 17 ;;
    list) printf '9876 modeled\\n' ;;
    *) return 98 ;;
  esac
}}
_template_prepare_archive() {{ :; }}
whiptail() {{ return {1 if upgrade_status == 'declined' else 0}; }}
offer_lxc_stack_upgrade_and_maybe_retry() {{ return {upgrade_status if isinstance(upgrade_status, int) else 97}; }}
post_build_script() {{ printf early > "$c/hook"; }}
{function(core, 'execute_optional_hook')}
create_lxc_container() {{
{region}
stage() {{
{creator_call}
}}
stage
printf complete > "$c/complete"
'''
            result = subprocess.run(['bash', '-c', script], cwd=c, capture_output=True,
                                    text=True, timeout=15, env=dict(os.environ, TMPDIR=str(c)))
            expected = 0 if upgrade_status == 0 else 231 if isinstance(upgrade_status, int) else 209
            label = f'creator/{storage}/upgrade-{upgrade_status}'
            check(label + ' classified status', expected, result.returncode)
            check(label + ' completion only on success', expected == 0, (c / 'complete').exists())
            check(label + ' no after-install hook in creator', False, (c / 'hook').exists())
            check(label + ' diagnostic tracing restored', False, 'x' in (c / 'exit-flags').read_text())
    failures = sum(not item['passed'] for item in checks)
    print(f'{len(checks)} checks; {failures} failure(s)', flush=True)
    print(f'RUNTIME_HOOKS_RESULT failures={failures}', flush=True)
    if failures:
        sys.exit(1)
except BaseException:
    print('Evidence: ' + str(work), flush=True)
    raise
else:
    # Cleanup belongs to completed success, never an interrupted prefix of checks.
    shutil.rmtree(work)
