#!/usr/bin/env bash
# Fixture support only. No framework or generic PVE cleanup is sourced here.

sg_init() {
  export SG_ID="${1:?case ID}" SG_VARIANT="${2:?variant}" SG_SESSION="${3:?session}"
  export SG_RECEIPT="${4:?guest receipt}" SG_BASELINE="${5:?historical helper}"
  export SG_CASE="${6:?allocated case root}" SG_SOURCE="${7:?immutable checkout}"
  systemd-detect-virt --vm -q || return 77
  [[ "$(id -u)" == 0 ]] || return 77
  python3 - "$BASHPID" << 'PY'
import hashlib
import json
import os
import pathlib
import socket
import sys

env = os.environ
session = pathlib.Path(env['SG_SESSION'])
case = pathlib.Path(env['SG_CASE'])
receipt = pathlib.Path(env['SG_RECEIPT'])
assert session.is_dir() and session.parent == pathlib.Path('/var/tmp')
assert session.name.startswith('su-hardening-') and session.resolve() == session
assert case.is_dir() and case.resolve() == case and case.is_relative_to(session / 'cases')
assert case.stat().st_uid == 0 and session.stat().st_uid == 0
assert receipt.resolve().is_relative_to(session) and receipt.is_file()
identity = json.loads(receipt.read_text())
assert identity['session'] == str(session)
assert identity['hostname'] == socket.gethostname()
assert identity['dmi_uuid'].lower() == pathlib.Path('/sys/class/dmi/id/product_uuid').read_text().strip().lower()
assert identity['boot_id'] == pathlib.Path('/proc/sys/kernel/random/boot_id').read_text().strip()
assert identity['supervisor_mntns'] != os.readlink('/proc/self/ns/mnt')
assert identity['supervisor_pidns'] == os.readlink('/proc/self/ns/pid')
manifest_path = pathlib.Path(env['SG_MANIFEST'])
assert manifest_path.resolve().is_relative_to(session)
assert hashlib.sha256(manifest_path.read_bytes()).hexdigest() == env['SG_MANIFEST_SHA256']
manifest = json.loads(manifest_path.read_text())
assert manifest['source_role'] == env['SG_SOURCE_ROLE']
assert len(manifest['source']['tree']) == 40 and all(char in '0123456789abcdef' for char in manifest['source']['tree'])
support = pathlib.Path(env['SG_REVIEW_SUPPORT'])
assert support.resolve().is_relative_to(session)
for item in manifest['support']:
    assert hashlib.sha256((support/item['path']).read_bytes()).hexdigest() == item['sha256']
for role, variable in [('source', 'SG_SOURCE'), ('harness', 'SG_HARNESS')]:
    root = pathlib.Path(env[variable])
    assert root.resolve() == root and root.is_relative_to(session)
    expected_paths = {entry['path'] for entry in manifest[role]['inventory']}
    actual_paths = set()
    for directory, dirs, names in os.walk(root, followlinks=False):
        for name in list(dirs):
            if (pathlib.Path(directory) / name).is_symlink():
                dirs.remove(name)
                names.append(name)
        actual_paths.update(str((pathlib.Path(directory) / name).relative_to(root)) for name in names)
    assert actual_paths == expected_paths
    for entry in manifest[role]['inventory']:
        path = root / entry['path']
        data = os.fsencode(os.readlink(path)) if path.is_symlink() else path.read_bytes()
        mode = '120000' if path.is_symlink() else ('100755' if path.stat().st_mode & 0o111 else '100644')
        assert mode == entry['mode']
        assert hashlib.sha256(data).hexdigest() == entry['sha256']
        assert hashlib.sha1(f'blob {len(data)}\0'.encode() + data).hexdigest() == entry['git_blob']
legacy = pathlib.Path(env['SG_BASELINE'])
assert legacy.resolve().is_relative_to(session)
data = legacy.read_bytes()
assert hashlib.sha1(f'blob {len(data)}\0'.encode() + data).hexdigest() == '823880c24ea300fcd78299d7839b96bb05da7e06'
PY
  [[ "$(findmnt -n -o PROPAGATION /)" == private ]] || return 77
  unset GITHUB_TOKEN GH_TOKEN CODEBERG_TOKEN FORCE_DEPLOY CLEAN_INSTALL UV_VERSION
  unset PYTHON_VERSION UV_PROJECT_DIR USE_ORIGINAL_FILENAME var_appversion USE_UVX
  unset DEV_MODE_DRYRUN DEBUG TOOLS_DEBUG XDG_DATA_HOME
  export PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin HOME="$SG_CASE/home" TMPDIR=/tmp
  export SG_ROUTES="$SG_CASE/routes.json" SG_REQUESTS="$SG_CASE/requests.jsonl"
  export SG_DISPATCH_ERRORS="$SG_CASE/dispatch-errors.jsonl" STD='' LC_ALL=C
  local real_awk
  real_awk=$(readlink -f "$(command -v awk)")
  mkdir "$SG_CASE/home" "$SG_CASE/tmp" "$SG_CASE/opt" "$SG_CASE/local-bin"
  mkdir "$SG_CASE/etc" "$SG_CASE/cache" "$SG_CASE/zsh" "$SG_CASE/assets" "$SG_CASE/fs" "$SG_CASE/var-lib"
  mkdir "$SG_CASE/etc/bash_completion.d"
  mkdir "$SG_CASE/etc/alternatives"
  ln -s "$real_awk" "$SG_CASE/etc/alternatives/awk"
  cp -L /etc/os-release "$SG_CASE/etc/os-release"
  # Preserve truthful installed-package metadata for the unchanged live-test child.
  # This is an isolated read snapshot, never a fabricated package/install database.
  mkdir "$SG_CASE/var-lib/dpkg"
  cp -P /var/lib/dpkg/status "$SG_CASE/var-lib/dpkg/status"
  printf '{}\n' > "$SG_ROUTES"
  : > "$SG_REQUESTS"
  : > "$SG_DISPATCH_ERRORS"
  local pair source target
  local bindings=(tmp:/tmp opt:/opt local-bin:/usr/local/bin etc:/etc cache:/var/cache var-lib:/var/lib)
  [[ ! -d /usr/share/zsh/site-functions ]] || bindings+=(zsh:/usr/share/zsh/site-functions)
  for pair in "${bindings[@]}"; do
    source="$SG_CASE/${pair%%:*}"
    target="${pair#*:}"
    mount --bind "$source" "$target" || return 77
    [[ "$(stat -Lc '%d:%i' "$source")" == "$(stat -Lc '%d:%i' "$target")" ]] || return 2
  done
  awk 'BEGIN { exit 0 }' || return 2
  python3 - "$BASHPID" << 'PY'
import hashlib
import json
import os
import pathlib
import socket
import sys

pid = int(sys.argv[1])
env = os.environ
source = pathlib.Path(env['SG_SOURCE'])
identity = json.loads(pathlib.Path(env['SG_RECEIPT']).read_text())
manifest = json.loads(pathlib.Path(env['SG_MANIFEST']).read_text())
observed_names = {'misc/tools.func', 'misc/core.func', 'misc/error_handler.func',
                  'scripts/lxc/romm.sh', 'tests/codeberg-release.test.sh'}
hashes = {entry['path']: {'git_blob': entry['git_blob'], 'sha256': entry['sha256']}
          for entry in manifest['source']['inventory'] if entry['path'] in observed_names}
context = {'worker_pid': pid, 'pgid': os.getpgid(pid), 'hostname': socket.gethostname(),
           'mntns': os.readlink('/proc/self/ns/mnt'), 'supervisor_mntns': identity['supervisor_mntns'],
           'cmdline': pathlib.Path(f'/proc/{pid}/cmdline').read_bytes().replace(b'\0', b' ').decode(),
           'case_id': env['SG_ID'], 'variant': env['SG_VARIANT'], 'case_root': env['SG_CASE'],
            'source_hashes': hashes, 'source_tree': manifest['source']['tree'],
            'harness_tree': manifest['harness']['tree'], 'manifest_sha256': env['SG_MANIFEST_SHA256'],
            'source_role': env['SG_SOURCE_ROLE'], 'dmi_uuid': identity['dmi_uuid'], 'boot_id': identity['boot_id']}
(pathlib.Path(env['SG_CASE']) / 'worker-context.json').write_text(json.dumps(context, indent=2) + '\n')
PY
  export SG_TOOLS="$SG_SOURCE/misc/tools.func"
  [[ "$SG_VARIANT" != legacy ]] || SG_TOOLS="$SG_BASELINE"
  sg_review_instrument
}

sg_review_instrument() {
  mkdir "$SG_CASE/command-shims"
  : > "$SG_CASE/command-events.jsonl"
  : > "$SG_CASE/fault-events.jsonl"
  local name
  for name in cp mv mkdir rm rmdir chmod chown; do
    printf '#!/bin/bash\nexec /usr/bin/python3 %q %q "$@"\n' "$SG_REVIEW_SUPPORT/probe.py" "$name" > "$SG_CASE/command-shims/$name"
    /usr/bin/chmod 755 "$SG_CASE/command-shims/$name"
  done
  export PATH="$SG_CASE/command-shims:$PATH" SG_OBSERVE_ACTIVE=0 SG_INVOCATION=primary
}

sg_review_capture() { python3 "$SG_REVIEW_SUPPORT/capture.py" "$@"; }

sg_review_summary() {
  # Keep exact per-scenario consumer files. Do not recursively embed those
  # JSON files inside another witness, then embed that witness in each result.
  python3 - "$1" "$2" << 'PY'
import hashlib,json,os,pathlib,sys
case=pathlib.Path(os.environ['SG_CASE']); references=[]
for path in sorted((case/'fs').glob('*/'+sys.argv[2]+'.json')):
    references.append({'path':str(path),'sha256':hashlib.sha256(path.read_bytes()).hexdigest()})
pathlib.Path(sys.argv[1]).write_text(json.dumps({'raw_consumer_references':references},indent=2)+'\n')
PY
}

sg_review_fault() {
  python3 - "$@" << 'PY'
import json,os,pathlib,sys,time
with (pathlib.Path(os.environ['SG_CASE'])/'fault-events.jsonl').open('a') as out:
    out.write(json.dumps({'kind':sys.argv[1],'argv':sys.argv[2:],'scenario':os.environ.get('SG_SCENARIO','default'),
                         'invocation':os.environ.get('SG_INVOCATION','primary'),'epoch':time.time()})+'\n')
PY
}

sg_load() {
  # shellcheck source=/dev/null
  source "$SG_TOOLS"
  msg_info() { printf 'INFO %s\n' "$*"; }
  msg_ok() { printf 'OK %s\n' "$*"; }
  msg_warn() { printf 'WARN %s\n' "$*" >&2; }
  msg_error() { printf 'ERROR %s\n' "$*" >&2; }
  ensure_usr_local_bin_persist() { :; }
  getent() { printf '127.0.0.1 deterministic-fixture\n'; }
  curl() { sg_dispatch_curl "$@"; }
  git() { sg_reject_transport git "$@"; }
  trap 'printf "%s\n" "$?" > "$SG_CASE/worker-exit.txt"' EXIT
  trap -p > "$SG_CASE/traps.txt"
  export SG_OBSERVE_ACTIVE=1
}

sg_reject_transport() {
  python3 - "$@" << 'PY'
import json
import os
import pathlib
import sys
with pathlib.Path(os.environ['SG_DISPATCH_ERRORS']).open('a') as stream:
    stream.write(json.dumps({'error': 'unexpected external transport', 'argv': sys.argv[1:]}) + '\n')
print('Fixture rejects unexpected external transport', file=sys.stderr)
raise SystemExit(97)
PY
}

sg_dispatch_curl() {
  python3 - "$@" << 'PY'
import json
import os
import pathlib
import shutil
import sys
import time

args = sys.argv[1:]
url = next((arg for arg in args if arg.startswith('https://')), '')
output = None
writeout = None
for index, arg in enumerate(args):
    if arg in ('-o', '--output'):
        output = args[index + 1]
    elif arg in ('-w', '--write-out'):
        writeout = args[index + 1]
routes = json.loads(pathlib.Path(os.environ['SG_ROUTES']).read_text())
route = routes.get(url)
record = {'url': url, 'argv': args, 'output': output, 'pid': os.getpid(), 'time': time.time(),
          'scenario': os.environ.get('SG_SCENARIO', 'default'), 'invocation': os.environ.get('SG_INVOCATION', 'primary')}
if route is None:
    record['error'] = 'unexpected fixture request'
    with pathlib.Path(os.environ['SG_DISPATCH_ERRORS']).open('a') as stream:
        stream.write(json.dumps(record) + '\n')
    print(f'Fixture dispatcher rejects unexpected URL: {url}', file=sys.stderr)
    raise SystemExit(97)
status = route.get('status', 200)
record.update({'http_status': status, 'curl_status': route.get('curl_status', 0), 'recognized_error': route.get('recognized_error')})
with pathlib.Path(os.environ['SG_REQUESTS']).open('a') as stream:
    stream.write(json.dumps(record) + '\n')
body = pathlib.Path(route['file']).read_bytes() if 'file' in route else json.dumps(route.get('json', {})).encode()
if output and output != '-':
    allowed = [os.environ['SG_CASE'] + '/', '/tmp/', '/opt/', '/usr/local/bin/', '/etc/', '/var/cache/', '/var/lib/']
    if not any(output.startswith(prefix) for prefix in allowed):
        raise SystemExit('unsafe fixture output path')
    pathlib.Path(output).write_bytes(body)
elif status < 400:
    sys.stdout.buffer.write(body)
if writeout:
    sys.stdout.write(str(status))
if status >= 400 and any(arg.startswith('-') and not arg.startswith('--') and 'f' in arg for arg in args):
    raise SystemExit(22)
raise SystemExit(route.get('curl_status', 0))
PY
}

sg_release_routes() {
  python3 - "$@" << 'PY'
import json
import os
import pathlib
import sys
import urllib.parse

host, repo, tag, artifact, filename, mode = sys.argv[1:]
routes_path = pathlib.Path(os.environ['SG_ROUTES'])
routes = json.loads(routes_path.read_text())
encoded = urllib.parse.quote(tag, safe='')
api = f'https://api.github.com/repos/{repo}/releases' if host == 'github' else f'https://codeberg.org/api/v1/repos/{repo}/releases'
asset = f'https://github.com/{repo}/releases/download/{tag}/{filename}' if host == 'github' else f'https://codeberg.org/{repo}/releases/download/{tag}/{filename}'
release = {'draft': False, 'prerelease': False, 'tag_name': tag, 'name': tag,
           'assets': [{'name': filename, 'browser_download_url': asset}] if filename else []}
routes[api] = {'json': [release]}
routes[api + '/latest'] = {'json': release}
routes[api + '/tags/' + encoded] = {'json': release}
if filename:
    routes[asset] = {'file': artifact}
if mode == 'tarball':
    routes[f'https://codeberg.org/{repo}/archive/{encoded}.tar.gz'] = {'file': artifact}
routes_path.write_text(json.dumps(routes, indent=2) + '\n')
PY
}

sg_add_route() {
  python3 - "$@" << 'PY'
import json
import os
import pathlib
import sys

url, status, reason = sys.argv[1:]
path = pathlib.Path(os.environ['SG_ROUTES'])
routes = json.loads(path.read_text())
routes[url] = {'status': int(status), 'json': {'message': reason}, 'recognized_error': reason}
path.write_text(json.dumps(routes, indent=2) + '\n')
PY
}

sg_make_tar() {
  python3 - "$@" << 'PY'
import io
import pathlib
import sys
import tarfile

archive = pathlib.Path(sys.argv[1])
with tarfile.open(archive, 'w:gz') as stream:
    for item in sys.argv[2:]:
        name, content = item.split('=', 1)
        data = content.encode().replace(b'\\n', b'\n')
        entry = tarfile.TarInfo('app/' + name)
        entry.size, entry.mode, entry.mtime = len(data), 0o644, 0
        stream.addfile(entry, io.BytesIO(data))
PY
}

sg_snapshot() {
  python3 "$SG_REVIEW_SUPPORT/native-snapshot.py" "$@" || return "$?"
  python3 - "$@" << 'PY'
import hashlib
import json
import os
import pathlib
import stat
import sys

def entry(path):
    if not path.exists() and not path.is_symlink():
        return {'exists': False}
    info = path.lstat()
    value = {'exists': True, 'mode': stat.S_IMODE(info.st_mode), 'uid': info.st_uid, 'gid': info.st_gid}
    if path.is_symlink():
        value.update(kind='symlink', target=os.readlink(path))
        try:
            value['resolved'] = str(path.resolve())
        except (OSError, RuntimeError) as error:
            value['resolution_error'] = type(error).__name__
        if path.is_file():
            value['sha256'] = hashlib.sha256(path.read_bytes()).hexdigest()
    elif path.is_file():
        value.update(kind='file', sha256=hashlib.sha256(path.read_bytes()).hexdigest(), text=path.read_text(errors='replace'))
    elif path.is_dir():
        value.update(kind='directory', entries={str(child.relative_to(path)): entry(child) for child in sorted(path.rglob('*'))})
    return value

output = pathlib.Path(sys.argv[1])
values = {}
for argument in sys.argv[2:]:
    name, path = argument.split('=', 1)
    values[name] = entry(pathlib.Path(path))
output.write_text(json.dumps(values, indent=2) + '\n')
PY
}

sg_transport_shims() {
  mkdir "$SG_CASE/shims"
  local common
  common=$(realpath "${BASH_SOURCE[0]}")
  printf '#!/usr/bin/env bash\nsource %q\nsg_dispatch_curl "$@"\n' "$common" > "$SG_CASE/shims/curl"
  printf '#!/usr/bin/env bash\nsource %q\nsg_reject_transport git "$@"\n' "$common" > "$SG_CASE/shims/git"
  printf '#!/usr/bin/env bash\nprintf "127.0.0.1 deterministic-fixture\\n"\n' > "$SG_CASE/shims/getent"
  printf '#!/usr/bin/env bash\nexec /usr/bin/python3 %q "$@"\n' "$SG_REVIEW_SUPPORT/live-cleanup.py" > "$SG_CASE/shims/rm"
  cat > "$SG_CASE/shims/mktemp" << 'SH'
#!/usr/bin/env bash
set -euo pipefail
result=$(/usr/bin/mktemp "$@")
python3 - "$result" "$PPID" <<'PY'
import json
import os
import pathlib
import sys
caller = int(sys.argv[2])
identity = pathlib.Path(f'/proc/{caller}/cmdline').read_bytes().replace(b'\0', b' ').decode()
with pathlib.Path(os.environ['SG_ALLOC_EVENTS']).open('a') as stream:
    stream.write(json.dumps({'path': sys.argv[1], 'caller_pid': caller, 'caller_pgid': os.getpgid(caller),
                             'caller_cmdline': identity, 'allocator_pid': os.getpid()}) + '\n')
PY
printf '%s\n' "$result"
SH
  chmod 755 "$SG_CASE/shims/curl" "$SG_CASE/shims/git" "$SG_CASE/shims/getent" "$SG_CASE/shims/mktemp" "$SG_CASE/shims/rm"
  export PATH="$SG_CASE/shims:/usr/local/bin:/usr/bin:/bin"
}
