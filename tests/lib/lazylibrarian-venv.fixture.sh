#!/usr/bin/env bash
# Actual cold hooks, uv/Python/venv/install/import and generated ExecStart consumer.
# App source, OS packages, setup_uv provisioning and systemctl are models.
set -euo pipefail
ROOT=$(realpath "$(dirname "${BASH_SOURCE[0]}")/../..")
if [[ "${1:-}" == --child ]]; then
  c="$CASE_ROOT"
  mount --bind "$c/opt" /opt
  mount --bind "$c/units" /etc/systemd/system
  mount --bind "$c/state" /var/lib/scripts-underground/update-pending
  # shellcheck source=/dev/null
  source <(sed "s|/var/lib/scripts-underground/maintenance-locks|$c/locks|g" "$ROOT/misc/core.func")
  source "$ROOT/misc/error_handler.func"
  load_functions
  source "$c/hooks.sh"
  header_info() { :; }
  check_container_storage() { :; }
  check_container_resources() { :; }
  cleanup_lxc() { :; }
  # shellcheck disable=SC2034
  LXC_REQUIRED_CPU=0 LXC_REQUIRED_RAM=0
  apt() { printf '%s\n' "$*" >> "$c/packages"; }
  setup_uv() {
    [[ "$PYTHON_VERSION" == 3.12 && ! -v VIRTUAL_ENV && ! -v CONDA_PREFIX ]]
    printf '%s\n' "$PYTHON_VERSION" >> "$c/python-requests"
  }
  git() {
    printf '%s\n' "$*" >> "$c/git-calls"
    if [[ "$1" == clone ]]; then
      [[ "$*" == 'clone https://gitlab.com/LazyLibrarian/LazyLibrarian /opt/LazyLibrarian' ]]
      mkdir /opt/LazyLibrarian
      cp -a "$c/payload/." /opt/LazyLibrarian/
    else
      [[ "$*" == '-C /opt/LazyLibrarian pull origin master' ]]
      printf '2.0.0\n' > /opt/LazyLibrarian/version.txt
      printf 'TOKEN = "updated"\n' > /opt/LazyLibrarian/src/ll_venv_probe.py
    fi
  }
  systemctl() { printf '%s\n' "$*" >> "$c/services"; }
  if [[ "$ROLE" == consume ]]; then
    python3 - "$c" "$EXPECTED_TOKEN" << 'PY'
import importlib.util,json,pathlib,shlex,subprocess,sys
c=pathlib.Path(sys.argv[1]); expected=sys.argv[2]
assert importlib.util.find_spec('ll_venv_probe') is None, 'global interpreter contaminated'
unit=pathlib.Path('/etc/systemd/system/lazylibrarian.service').read_text()
commands=[line.removeprefix('ExecStart=') for line in unit.splitlines() if line.startswith('ExecStart=')]
command,=commands
argv=shlex.split(command)
assert argv==['/opt/LazyLibrarian/venv/bin/python3','/opt/LazyLibrarian/LazyLibrarian.py']
result=subprocess.run(argv,check=True,capture_output=True,text=True,timeout=15)
d=json.loads(result.stdout)
assert d['prefix']=='/opt/LazyLibrarian/venv' and d['base_prefix']!=d['prefix']
assert d['version']==[3,12] and d['token']==expected
assert pathlib.Path(d['module']).is_relative_to('/opt/LazyLibrarian/venv/lib/python3.12/site-packages')
assert d['distribution']==('1.0.0' if expected=='installed' else '2.0.0')
assert not pathlib.Path('/opt/.venv').exists() and not pathlib.Path('/opt/LazyLibrarian/.venv').exists()
outside=subprocess.run([str(c/'bin/python3.12'),'-I','-c',"import importlib.util; assert importlib.util.find_spec('ll_venv_probe') is None"],check=True,timeout=15)
(c/(expected+'.json')).write_text(json.dumps(d,sort_keys=True)+'\n')
print('PASS LazyLibrarian '+expected+' real package and generated ExecStart interpreter consumer '+result.stdout.strip())
PY
    exit 0
  fi
  catch_errors
  if [[ "$ROLE" == install ]]; then install_script; else run_update_script; fi
  exit 0
fi

: "${TMPDIR:?disk-backed TMPDIR required}"
systemd-detect-virt --vm --quiet || exit 1
case "$(realpath -e "$TMPDIR")" in /tmp | /tmp/*) exit 1 ;; esac
case "$(findmnt -rn -T "$TMPDIR" -o FSTYPE)" in '' | tmpfs | ramfs) exit 1 ;; esac
# Prerequisites are independently staged by the assigned VM owner, not fetched here.
uv=$(command -v uv)
python=$(realpath "$(command -v python3.12)")
work=$(mktemp -d "$TMPDIR/lazylibrarian-venv.XXXXXX")
trap 'rm -rf -- "$work"' EXIT
failures=0
check() {
  if [[ "$1" == "$2" ]]; then printf 'PASS %s\n' "$3"; else
    printf 'FAIL %s: expected <%s>, got <%s>\n' "$3" "$2" "$1" >&2
    failures=$((failures + 1))
  fi
}
for mode in no yes; do
  c="$work/$mode"
  mkdir -p "$c/"{opt,units,state,home,cache,bin,payload/src}
  ln -s "$uv" "$c/bin/uv"
  ln -s "$python" "$c/bin/python3.12"
  sed '/^# framework bootstrap/,$d' "$ROOT/scripts/lxc/lazylibrarian.sh" > "$c/hooks.sh"
  cat > "$c/payload/pyproject.toml" << 'TOML'
[build-system]
requires = []
build-backend = "fixture_backend"
backend-path = ["."]
TOML
  # Owned dependency-free wheel producer, not LazyLibrarian's backend/dependencies.
  cat > "$c/payload/fixture_backend.py" << 'PY'
import base64,hashlib,pathlib,zipfile
def build_wheel(wheel_directory,config_settings=None,metadata_directory=None):
    version=pathlib.Path('version.txt').read_text().strip()
    dist='ll_venv_probe-'+version+'.dist-info'
    name='ll_venv_probe-'+version+'-py3-none-any.whl'
    files={'ll_venv_probe.py':pathlib.Path('src/ll_venv_probe.py').read_bytes(),
           dist+'/METADATA':('Metadata-Version: 2.1\nName: ll-venv-probe\nVersion: '+version+'\n').encode(),
           dist+'/WHEEL':b'Wheel-Version: 1.0\nGenerator: owned-test-fixture\nRoot-Is-Purelib: true\nTag: py3-none-any\n'}
    record=''.join(p+',sha256='+base64.urlsafe_b64encode(hashlib.sha256(data).digest()).decode().rstrip('=')+','+str(len(data))+'\n' for p,data in files.items())
    files[dist+'/RECORD']=(record+dist+'/RECORD,,\n').encode()
    with zipfile.ZipFile(pathlib.Path(wheel_directory)/name,'w') as wheel:
        for p,data in files.items():wheel.writestr(p,data)
    return name
PY
  printf '1.0.0\n' > "$c/payload/version.txt"
  printf 'TOKEN = "installed"\n' > "$c/payload/src/ll_venv_probe.py"
  cat > "$c/payload/LazyLibrarian.py" << 'PY'
import importlib.metadata,json,sys,ll_venv_probe
print(json.dumps(dict(prefix=sys.prefix,base_prefix=sys.base_prefix,version=list(sys.version_info[:2]),module=ll_venv_probe.__file__,token=ll_venv_probe.TOKEN,distribution=importlib.metadata.version('ll-venv-probe')),sort_keys=True))
PY
  invoke() {
    env -i PATH="$c/bin:/usr/local/bin:/usr/bin:/bin" HOME="$c/home" TMPDIR="$TMPDIR" \
      UV_OFFLINE=1 UV_PYTHON_DOWNLOADS=never UV_NO_CONFIG=1 UV_CACHE_DIR="$c/cache" \
      CASE_ROOT="$c" ROLE="$1" EXPECTED_TOKEN="${2:-}" APP=LazyLibrarian NSAPP=lazylibrarian \
      VERBOSE="$mode" BUILD_LOG="$c/$1.log" DEBUG_LOGFILE="$c/$1-errors.log" \
      timeout 60s unshare -mn --propagation private -- bash "$0" --child < /dev/null
  }
  rc=0
  invoke install > "$c/install-output" 2>&1 || rc=$?
  check "$rc" 0 "LazyLibrarian/$mode initial cold hook"
  if [[ "$rc" != 0 ]]; then
    cat "$c/install-output" "$c/install.log" 2> /dev/null || true
    continue
  fi
  rc=0
  invoke consume installed > "$c/installed-output" 2>&1 || rc=$?
  cat "$c/installed-output"
  check "$rc" 0 "LazyLibrarian/$mode installed package consumer"
  unit_before=$(sha256sum "$c/units/lazylibrarian.service")
  interpreter_before=$(stat -c '%d:%i' "$c/opt/LazyLibrarian/venv/bin/python3")
  rc=0
  invoke update > "$c/update-output" 2>&1 || rc=$?
  check "$rc" 0 "LazyLibrarian/$mode unchanged update cold hook"
  if [[ "$rc" != 0 ]]; then
    cat "$c/update-output" "$c/update.log" 2> /dev/null || true
    continue
  fi
  rc=0
  invoke consume updated > "$c/updated-output" 2>&1 || rc=$?
  cat "$c/updated-output"
  check "$rc" 0 "LazyLibrarian/$mode updated package consumer"
  check "$(stat -c '%d:%i' "$c/opt/LazyLibrarian/venv/bin/python3")" "$interpreter_before" "LazyLibrarian/$mode existing update interpreter retained"
  check "$(sha256sum "$c/units/lazylibrarian.service")" "$unit_before" "LazyLibrarian/$mode generated unit unchanged by update"
  check "$(cat "$c/python-requests")" "$(printf '3.12\n3.12')" "LazyLibrarian/$mode both hooks keep Python3.12 request"
  check "$(cat "$c/services")" "$(printf 'enable -q --now lazylibrarian\nstop lazylibrarian\nstart lazylibrarian')" "LazyLibrarian/$mode service calls unchanged (modeled)"
  check "$(test -e "$c/state/lazylibrarian" && printf present || printf absent)" absent "LazyLibrarian/$mode successful update clears pending"
done
printf '%s failure(s); real offline uv/Python3.12/venv/package/ExecStart interpreter; app source/packages/setup_uv/systemctl modeled\n' "$failures"
[[ "$failures" == 0 ]]
