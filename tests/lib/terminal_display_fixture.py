"""Actual core/native terminal and cold bundle consumers; no PVE/app effects."""
import errno
import json
import os
from pathlib import Path
import pty
import re
import shlex
import subprocess
import sys
import tempfile


SOURCE = Path(sys.argv[1])
WORK = Path(tempfile.mkdtemp(prefix='terminal-display.', dir=os.environ['TMPDIR']))
print('Terminal evidence: ' + str(WORK), flush=True)
CHECKS = []


def serialize(value):
    if isinstance(value, bytes):
        return dict(bytes_hex=value.hex())
    raise TypeError(type(value).__name__)


def check(name, expected, actual):
    ok = expected == actual
    CHECKS.append(dict(name=name, expected=expected, actual=actual, passed=ok))
    print(('PASS ' if ok else 'FAIL ') + name + ('' if ok else repr((expected, actual))), flush=True)


def write(path, text, mode=0o644):
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(text)
    path.chmod(mode)


def run(name, code, term=None, tty=False, path='/usr/bin:/bin'):
    env = dict(PATH=path, HOME=str(WORK / 'home'), TMPDIR=str(WORK),
               BUILD_LOG=str(WORK / 'active.log'), DEBUG_LOGFILE=str(WORK / 'error.log'),
               DEV_MODE_KEEP='true', BASH_ENV='/dev/null')
    if term is not None:
        env['TERM'] = term
    master = slave = None
    if tty:
        master, slave = pty.openpty()
    try:
        # Bash may create a nonexported TERM=dumb when the environment lacks it.
        # Exercise a genuinely unset shell variable as well as a cold environment.
        if term is None:
            code = 'unset TERM; ' + code
        result = subprocess.run(['/bin/bash', '-c', code], env=env,
                                stdin=subprocess.DEVNULL, stdout=slave if tty else subprocess.PIPE,
                                stderr=subprocess.PIPE, timeout=20)
        output = result.stdout
        if tty:
            os.close(slave)
            slave = None
            output = b''
            while True:
                try:
                    data = os.read(master, 65536)
                except OSError as error:
                    if error.errno != errno.EIO:
                        raise
                    break
                if not data:
                    break
                output += data
        facts = dict(status=result.returncode, stdout=output.hex(), stderr=result.stderr.hex(),
                     term=term, tty=tty, code=code)
        (WORK / (name + '.json')).write_text(json.dumps(facts, sort_keys=True))
        return result.returncode, output, result.stderr
    finally:
        if slave is not None:
            os.close(slave)
        if master is not None:
            os.close(master)


def quote(path):
    return shlex.quote(str(path))


# Only persistent-state filesystem literals are mapped. Display/error functions
# and the actual bundle writer/runner are unchanged. Install/runtime libraries
# are declaration-only models: no package, network or application is invoked.
core = (SOURCE / 'misc/core.func').read_text()
for old, new in [('/var/lib/scripts-underground/update-pending', str(WORK / 'pending')),
                 ('/var/lib/scripts-underground/maintenance-locks', str(WORK / 'locks'))]:
    core = core.replace(old, new)
cache = WORK / 'cache'
write(cache / 'core.func', core)
write(cache / 'error_handler.func', (SOURCE / 'misc/error_handler.func').read_text())
write(cache / 'install.func', 'setup_lxc() { :; }\n')
write(cache / 'tools.func', 'setup_uv() { :; }\n')
write(cache / 'github.func', 'clone_and_deploy_gh_commit() { :; }\n')
(WORK / 'home').mkdir()
bundle = WORK / 'update'
generate = f'''
set -euo pipefail
source {quote(SOURCE / 'misc/bundle.func')}
APP=TerminalProbe NSAPP=terminal-probe REPO_BASE=offline
var_lxc_tmpdir={quote(WORK)}
update_script() {{
  header_info
  printf 'productive:%s:%s\\n' "${{UPDATE_FORCE:-none}}" "${{FORCE_DEPLOY:-none}}" >> {quote(WORK / 'productive')}
  return "${{HOOK_STATUS:-0}}"
}}
_write_bundle update update_script {quote(cache)} \
  'stop_spinner() {{ :; }}' 'cleanup_lxc() {{ :; }}' 'run_update_script "$@"' > {quote(bundle)}
'''
rc, _, err = run('generate', generate)
check('actual bundle writer produces cold update', (0, b''), (rc, err))
for name, args, status, force in [('cold-unset', '', 0, 'none:none'),
                                  ('cold-clean', '--clean', 0, '1:1'),
                                  ('cold-failure', '', 37, 'none:none'),
                                  ('cold-bogus', '--bogus', 65, None)]:
    (WORK / 'productive').unlink(missing_ok=True)
    (WORK / 'pending/terminal-probe').unlink(missing_ok=True)
    rc, out, err = run(name, ('export HOOK_STATUS=37; ' if status == 37 else '') +
                       f'exec /bin/bash {quote(bundle)} {args}')
    check(name + ' exact productive status', status, rc)
    check(name + ' productive consumer', '' if force is None else 'productive:' + force + '\n',
          (WORK / 'productive').read_text() if (WORK / 'productive').exists() else '')
    check(name + ' pending ownership', status == 37, (WORK / 'pending/terminal-probe').exists())
    check(name + ' no terminal diagnostic', False, b'TERM environment variable' in out + err)

# Preserve the original cold failure as a meaningful RED before helper tests.
if any(not item['passed'] for item in CHECKS):
    (WORK / 'checks.json').write_text(json.dumps(CHECKS, indent=2, default=serialize))
    raise SystemExit(1)

prefix = f'set -Eeuo pipefail; source {quote(SOURCE / "misc/core.func")}; '
bin_dir = WORK / 'bin'
calls = WORK / 'clear-calls'
write(bin_dir / 'clear', '#!/bin/bash\nprintf "clear\\n" >> ' + quote(calls) +
      '\nexec /usr/bin/clear "$@"\n', 0o755)
for tty in (False, True):
    for term in (None, '', 'dumb', 'su-terminal-does-not-exist', 'xterm-256color'):
        calls.unlink(missing_ok=True)
        rc, out, err = run('clear-' + str(tty) + '-' + str(term), prefix + 'terminal_clear',
                           term, tty, str(bin_dir))
        invoked = tty and term not in (None, '', 'dumb')
        check('clear status ' + repr((tty, term)), 0, rc)
        check('clear native invocation ' + repr((tty, term)), invoked, calls.exists())
        check('clear cosmetic diagnostic ' + repr((tty, term)), b'', err)
        check('clear escape output ' + repr((tty, term)), tty and term == 'xterm-256color', b'\x1b[' in out)
rc, native, err = run('native-reference', 'exec /usr/bin/clear', 'xterm-256color', True)
check('supported native clear reference', (0, b''), (rc, err))
rc, actual, err = run('native-core', prefix + 'terminal_clear', 'xterm-256color', True)
check('core emits exact native clear bytes', native, actual)
empty = WORK / 'empty-bin'
empty.mkdir()
for name, path in [('absent', empty), ('failed', bin_dir)]:
    if name == 'failed':
        write(bin_dir / 'clear', '#!/bin/bash\nprintf "cosmetic failure\\n" >&2\nexit 47\n', 0o755)
    rc, out, err = run(name, prefix + 'terminal_clear; printf continued', 'xterm-256color', True, str(path))
    check(name + ' clear is nonfatal and quiet', (0, b'continued', b''), (rc, out, err))
rc, out, err = run('no-shadow', prefix + 'clear() { printf wrong; return 49; }; terminal_clear',
                   'xterm-256color', True)
check('native command is not a caller function', (0, native, b''), (rc, out, err))
state = f'''
trap 'printf productive-error >&2' ERR
set +o > {quote(WORK / 'options-before')}
trap -p ERR > {quote(WORK / 'trap-before')}
terminal_clear
set +o > {quote(WORK / 'options-after')}
trap -p ERR > {quote(WORK / 'trap-after')}
/bin/cmp {quote(WORK / 'options-before')} {quote(WORK / 'options-after')}
/bin/cmp {quote(WORK / 'trap-before')} {quote(WORK / 'trap-after')}
/bin/bash -c 'exit 37'
printf wrong
'''
rc, out, err = run('productive-state', prefix + state, 'xterm-256color', True, str(bin_dir))
check('cosmetic failure preserves productive ERR/status/options', (37, b'', b'productive-error'), (rc, out, err))

# Fixed declaration boundaries keep all PVE/app effects out of these consumers.
# Each custom header is defined before sourcing core, matching bootstrap order.
headers = []
for path in sorted((SOURCE / 'scripts').rglob('*.sh')):
    text = path.read_text()
    if re.search(r'(?m)^\s*(?:terminal_clear|clear)\s*$', text):
        match = re.search(r'(?ms)^(?:function )?header_info(?:\(\))?\s*\{\n.*?^\}', text)
        if match:
            headers.append((path, match.group()))
for path, declaration in headers:
    name = path.relative_to(SOURCE).as_posix()
    rc, out, err = run('header-' + path.stem, 'set -euo pipefail; ' + declaration + '\n' +
                       f'source {quote(SOURCE / "misc/core.func")}; render_header; printf header-reached')
    check(name + ' custom dispatch reaches consumer', (0, b''), (rc, err))
    check(name + ' banner retained', True, b'header-reached' in out and len(out) > 40)
for name, code in [('stub', 'render_header'), ('fallback', 'unset -f header_info; render_header')]:
    rc, out, err = run('header-' + name, prefix + 'APP=FallbackProbe; load_functions; ' + code)
    check(name + ' generic header dispatch', (0, b''), (rc, err))
    check(name + ' app name', True, b'FallbackProbe' in out)

# Real VM menu branches, with only the dialog and productive settings callbacks
# modeled. No VM lifecycle body runs.
vm = (SOURCE / 'scripts/vm/proxmox-ve-vm.sh').read_text()
menu = re.search(r'(?ms)^function start_script\(\) \{\n.*?^\}', vm).group()
for branch, answer in [('default', 0), ('advanced', 1)]:
    code = prefix + f'''
source {quote(SOURCE / 'misc/vm.func')}
load_functions
vm_init_colors
whiptail() {{ return {answer}; }}
default_settings() {{ printf settings-default; }}
advanced_settings() {{ printf settings-advanced; }}
{menu}
start_script
'''
    rc, out, err = run('vm-menu-' + branch, code)
    check('VM actual ' + branch + ' menu status', (0, b''), (rc, err))
    check('VM actual ' + branch + ' callback', True, ('settings-' + branch).encode() in out)
addon_header = next(body for path, body in headers if path.name == 'filebrowser.sh')
rc, out, err = run('addon-init', 'set -euo pipefail; ' + addon_header + '\n' + prefix +
                   f'APP=FileBrowser; source {quote(SOURCE / "misc/addon_lxc.func")}; addon_init; printf "slug:%s" "$APP_SLUG"')
check('actual addon init preserves custom header dispatch', (0, b''), (rc, err))
check('actual addon init slug consumer', True, b'slug:filebrowser' in out and len(out) > 40)

# Existing PVE bootstrap executes before the first header, not just before later
# administrative loops. Stop at the declared UI/log boundary, before any effects.
transport = f'''
curl() {{ case "${{!#}}" in
 */bootstrap/pve) /bin/cat {quote(SOURCE / 'misc/bootstrap/pve')} ;;
 */core.func) /bin/cat {quote(SOURCE / 'misc/core.func')} ;;
 */error_handler.func) /bin/cat {quote(SOURCE / 'misc/error_handler.func')} ;;
 *) return 89 ;; esac; }}
pveversion() {{ :; }}
'''
for name, boundary in [('clean-lxcs', 'whiptail --backtitle'), ('fstrim', 'LOGFILE=')]:
    text = (SOURCE / ('scripts/pve/' + name + '.sh')).read_text()
    before, marker, _ = text.partition(boundary)
    assert marker and 'misc/bootstrap/pve' in before
    rc, out, err = run('early-pve-' + name, 'set -euo pipefail; REPO_BASE=offline; ' + transport + before +
                       '\nheader_info; printf early-reached')
    check(name + ' real early bootstrap/header status', (0, b''), (rc, err))
    check(name + ' real early banner consumer', True, b'early-reached' in out and len(out) > 40)

# Cron's entire manager reaches only the real bootstrap and menu cancellation.
# curl is a literal local source transport; whiptail records then cancels.
cron = SOURCE / 'scripts/pve/cron-update-lxcs.sh'
code = f'''
set -euo pipefail
curl() {{
 case "${{!#}}" in
 */bootstrap/pve) printf 'bootstrap\\n' >> {quote(WORK / 'cron-order')}; /bin/cat {quote(SOURCE / 'misc/bootstrap/pve')} ;;
 */core.func) /bin/cat {quote(SOURCE / 'misc/core.func')} ;;
 */error_handler.func) /bin/cat {quote(SOURCE / 'misc/error_handler.func')} ;;
 *) return 89 ;; esac
}}
pveversion() {{ :; }}
whiptail() {{ printf 'menu\\n' >> {quote(WORK / 'cron-order')}; return 1; }}
source {quote(cron)}
'''
rc, out, err = run('cron-manager', code)
check('cron manager cancellation status', (0, b''), (rc, err))
check('cron bootstrap precedes actual menu', 'bootstrap\nmenu\n', (WORK / 'cron-order').read_text())
check('cron actual banner remains', True, b'______' in out)
check('all executable clear callers adopted', [],
      [str(p.relative_to(SOURCE)) for p in [SOURCE / 'misc/core.func', SOURCE / 'misc/build.func',
       *sorted((SOURCE / 'scripts').rglob('*.sh'))]
       if re.search(r'(?m)^\s*clear\s*$', p.read_text())])
(WORK / 'checks.json').write_text(json.dumps(CHECKS, indent=2, default=serialize))
print(str(len(CHECKS)) + ' terminal checks; ' + str(sum(not v['passed'] for v in CHECKS)) + ' failure(s)', flush=True)
raise SystemExit(any(not v['passed'] for v in CHECKS))
