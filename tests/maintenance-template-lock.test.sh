#!/usr/bin/env bash
# Real kernel flock/FD/inode outcomes. Only PVE storage/CT commands are modeled.
# --baseline accepts an owned old build.func with ONLY its forbidden lock literal
# redirected to LEGACY_LOCK_ROOT on disk; never execute the original RAM write.
set -euo pipefail
systemd-detect-virt --vm --quiet || exit 1
: "${TMPDIR:?provide disk-backed TMPDIR}"
case "$(realpath -e "$TMPDIR")" in /tmp | /tmp/*) exit 1 ;; esac
case "$(findmnt -nr -T "$TMPDIR" -o FSTYPE)" in '' | tmpfs | ramfs) exit 1 ;; esac
ROOT=$(realpath "$(dirname "${BASH_SOURCE[0]}")/..")

if [[ "${1:-}" == --model ]]; then
  shift
  tool=$1
  shift
  # shellcheck source=/dev/null
  source "$MODEL_FUNCTIONS"
  declare -F "$tool" > /dev/null || exit 97
  printf '%s\t%s\t%s\t%s\t%s\n' "$CREATOR" "$tool" "${1:-}" "$(< "/proc/$PPID/comm")" "$*" >> "$CASE_ROOT/commands"
  "$tool" "$@"
  exit $?
fi

if [[ "${1:-}" == --worker ]]; then
  source "$ROOT/misc/core.func"
  source "$SUBJECT/error_handler.func"
  source "$SUBJECT/functions.sh"
  load_functions
  color
  export BUILD_LOG="$CASE_ROOT/$CREATOR.log" DEBUG_LOGFILE="$CASE_ROOT/$CREATOR-error.log"
  export SESSION_ID="$CREATOR" CTID=19091 PCT_OSTYPE="${TEST_OS_TYPE:-alpine}" PCT_OSVERSION="${TEST_OS_VERSION:-3}"
  export CONTAINER_STORAGE=local PCT_OPTIONS='-rootfs local:1' STD='' VERBOSE=no
  export var_os="${TEST_OS:-alpine}" TEMPLATE_STORAGE="$TEST_STORAGE"
  export MODEL_TTY
  MODEL_TTY=$(readlink /proc/self/fd/2)
  if [[ "${LOCK_ACTION:-}" != '' ]]; then
    # Core deliberately renders Alpine messages without a spinner even on a TTY.
    # Use its normal Debian UI branch for the real spinner inheritance control.
    export var_os=debian PCT_OSTYPE=debian
    export TEMPLATE="$TEST_TEMPLATE"
    export TEMPLATE_PATH="$CASE_ROOT/$TEST_STORAGE/template/cache/$TEST_TEMPLATE"
    msg_info 'Spinner before acquisition'
    printf '%s\n' "${SPINNER_PID:-}" > "$CASE_ROOT/$CREATOR-spinner"
    catch_errors
    printf '%s\n' "$BASHPID" > "$CASE_ROOT/$CREATOR-worker"
    if declare -F _template_lock_acquire > /dev/null; then
      _template_lock_acquire || exit $?
      held_fd=$_TEMPLATE_LOCK_FD
      held_path=$_TEMPLATE_LOCK_PATH
    else
      baseline_acquire
      held_fd=9
      held_path=${lockfile:?baseline acquisition sets its path}
    fi
    stat -Lc '%d:%i' "/proc/self/fd/$held_fd" > "$CASE_ROOT/$CREATOR-inode"
    printf '%s\n' "$held_path" > "$CASE_ROOT/$CREATOR-lock"
    printf '%s\n' "$BASHPID" > "$CASE_ROOT/$CREATOR-held"
    case "$LOCK_ACTION" in
      err) false ;;
      exit) exit 37 ;;
      app-exit)
        export lockfile="$CASE_ROOT/app-owned"
        printf keep > "$lockfile"
        exit 37
        ;;
      productive)
        python3 "$SUBJECT/producer.py" "$CASE_ROOT" "$CREATOR" &
        wait "$!"
        ;;
      hold)
        for ((i = 0; i < ${HOLD_TICKS:-400}; i++)); do
          [[ ! -f "$CASE_ROOT/$CREATOR-release" ]] || break
          sleep .025
        done
        ;;
    esac
    if declare -F _template_lock_release > /dev/null; then _template_lock_release; else exec 9>&-; fi
    printf released > "$CASE_ROOT/$CREATOR-released"
    # A live post-release process makes inherited-descriptor leaks observable.
    sleep .2
    exit 0
  fi
  check_storage_support() { :; }
  _test_probe() {
    printf '%s\n' "$3" >> "$CASE_ROOT/probes-required"
    if python3 "$SUBJECT/probe.py" "$CASE_ROOT" "$1" "$2" "$3" >> "$CASE_ROOT/observed"; then :; else
      printf 'PROBE_ERROR %s %s\n' "$3" "$?" >> "$CASE_ROOT/observed"
    fi
  }
  resolve_storage_preselect() {
    export STORAGE_RESULT="$2" STORAGE_INFO=fixture
  }
  execute_optional_hook() { :; }
  qm() { return 1; }
  pvesm() {
    case "$1" in
      path)
        [[ "${FAIL_PATH_LOOKUP:-0}" == 0 ]] || return 48
        printf '%s/%s\n' "$CASE_ROOT/${2%%:*}/template/cache" "${2##*/}"
        ;;
      list)
        # Native volume_list activates checked storage before listing. Model
        # exactly that preparation, not the lock or archive classification.
        [[ "${FAIL_STORAGE:-0}" == 0 ]] || return 47
        [[ "${SKIP_CACHE_PREPARE:-0}" != 0 ]] || mkdir -p "$CASE_ROOT/$2/template/cache"
        ;;
      status) printf 'Name Type Status\nlocal dir active\nother dir active\nalias dir active\n' ;;
      *) return 97 ;;
    esac
  }
  pveam() {
    local f count=0 hold=0
    case "$1" in
      list)
        [[ ! -e "$CASE_ROOT/$CREATOR-list-count" ]] || count=$(< "$CASE_ROOT/$CREATOR-list-count")
        count=$((count + 1))
        printf '%s\n' "$count" > "$CASE_ROOT/$CREATOR-list-count"
        if ((count == 1)); then
          _test_probe free "$2" discovery
        else
          _test_probe held "$2" final-list
          [[ "${MISSING_FINAL_LIST:-0}" == 0 ]] || return 0
        fi
        for f in "$CASE_ROOT/$2/template/cache/"*.tar.*; do
          [[ -f "$f" ]] && printf '%s:vztmpl/%s 2M\n' "$2" "${f##*/}"
        done
        return 0
        ;;
      update) return 0 ;;
      available)
        if [[ "${DISCOVERY_BARRIER:-0}" == 1 ]]; then
          printf ready > "$CASE_ROOT/$CREATOR-discovered"
          for ((i = 0; i < 200; i++)); do
            [[ ! -e "$CASE_ROOT/a-discovered" || ! -e "$CASE_ROOT/b-discovered" ]] || break
            sleep .025
          done
          [[ -e "$CASE_ROOT/a-discovered" && -e "$CASE_ROOT/b-discovered" ]] || return 98
        fi
        printf 'system %s\n' "$TEST_TEMPLATE"
        ;;
      download)
        count=0
        [[ ! -e "$CASE_ROOT/$CREATOR-download-$2-count" ]] || count=$(< "$CASE_ROOT/$CREATOR-download-$2-count")
        count=$((count + 1))
        printf '%s\n' "$count" > "$CASE_ROOT/$CREATOR-download-$2-count"
        printf '%s download-start %s %s\n' "$CREATOR" "$2" "$(date +%s%N)" >> "$CASE_ROOT/timeline"
        # Independent contender sees the real kernel lock, never a stubbed flock.
        _test_probe held "$2" download
        printf '%s\n' "$BASHPID" > "$CASE_ROOT/$CREATOR-producer"
        if [[ "${NONPRODUCTIVE_CONTROL:-0}" == 1 ]]; then
          python3 "$SUBJECT/ui_holder.py" "$CASE_ROOT" "$CREATOR" &
        fi
        hold=${HOLD_PUBLISHER:-0}
        if [[ "${HOLD_CACHE_PUBLISH:-0}" == 1 ]]; then
          case "${TEST_ROUTE:-}:$2" in
            repair:other) ((count < 2)) || hold=1 ;;
            fallback:local) hold=1 ;;
          esac
        fi
        if [[ "$hold" == 1 ]]; then
          printf held > "$CASE_ROOT/$CREATOR-publisher-held"
          for ((i = 0; i < 600; i++)); do
            [[ ! -e "$CASE_ROOT/$CREATOR-finish-publisher" ]] || break
            sleep .025
          done
          [[ -e "$CASE_ROOT/$CREATOR-finish-publisher" ]] || return 98
        fi
        sleep "${PUBLISH_DELAY:-0.4}"
        [[ "${FAIL_DOWNLOAD:-0}" == 0 ]] || return 42
        if [[ "${REPAIR_FAILURE:-0}" != 0 && "$2" == other && "$count" -ge 2 ]]; then return "$REPAIR_FAILURE"; fi
        if [[ "${LOCAL_REPAIR_FAILURE:-0}" != 0 && "$2" == local && "$count" -ge 2 ]]; then return "$LOCAL_REPAIR_FAILURE"; fi
        if [[ "${FALLBACK_FAILURE:-0}" != 0 && "$2" == local ]]; then return "$FALLBACK_FAILURE"; fi
        cp "$CASE_ROOT/payload.tar.xz" "$CASE_ROOT/$2/template/cache/.publish-$CREATOR"
        [[ "${BAD_PUBLISH:-0}" == 0 ]] || printf corrupt > "$CASE_ROOT/$2/template/cache/.publish-$CREATOR"
        if [[ "${REPAIR_BAD:-0}" == 1 && "$2" == other && "$count" -ge 2 || "${FALLBACK_BAD:-0}" == 1 && "$2" == local ]]; then
          printf corrupt > "$CASE_ROOT/$2/template/cache/.publish-$CREATOR"
        fi
        mv "$CASE_ROOT/$2/template/cache/.publish-$CREATOR" "$CASE_ROOT/$2/template/cache/$3"
        printf '%s download-end %s %s\n' "$CREATOR" "$2" "$(date +%s%N)" >> "$CASE_ROOT/timeline"
        ;;
      *) return 97 ;;
    esac
  }
  pct() {
    case "$1" in
      status) return 1 ;;
      create)
        _test_probe free "${3%%:*}" pct-create
        local count=0
        [[ ! -f "$CASE_ROOT/$CREATOR-create-count" ]] || count=$(< "$CASE_ROOT/$CREATOR-create-count")
        count=$((count + 1))
        printf '%s\n' "$count" > "$CASE_ROOT/$CREATOR-create-count"
        if [[ "${TEST_ROUTE:-initial}" == repair && "$count" == 1 ]]; then
          printf corrupt > "$CASE_ROOT/$TEST_STORAGE/template/cache/$TEST_TEMPLATE"
          printf 'corrupt template\n'
          if [[ "${REPAIR_LOCK_FAULT:-0}" == 1 ]]; then
            local identity path
            identity=$(< "$CASE_ROOT/$CREATOR-lock-identity")
            path=${identity#*$'\n'}
            printf unsafe > "$path"
          fi
          return 1
        fi
        if [[ "${TEST_ROUTE:-initial}" == fallback && "${3%%:*}" != local ]]; then return 1; fi
        if [[ "${TEST_ROUTE:-initial}" == stack && "$count" -le 3 ]]; then
          printf 'unsupported template version\n'
          return 1
        fi
        mkdir -p /etc/pve/lxc
        printf 'rootfs: fixture\n' > "/etc/pve/lxc/$CTID.conf"
        ;;
      list) printf 'VMID\n%s\n' "$CTID" ;;
      *) return 97 ;;
    esac
  }
  apt-get() { return 0; }
  apt-cache() { printf 'Candidate: 99.0\n'; }
  dpkg-query() { printf '1.0\n'; }
  prompt_confirm() { [[ "${TEST_ROUTE:-}" == stack ]]; }
  export MODEL_FUNCTIONS="$CASE_ROOT/$CREATOR-models.sh"
  declare -f _test_probe pvesm pveam pct qm apt-get apt-cache dpkg-query > "$MODEL_FUNCTIONS"
  unset -f pvesm pveam pct qm apt-get apt-cache dpkg-query
  export PATH="$SUBJECT/bin:$PATH"
  catch_errors
  tar() {
    _test_probe held "$TEMPLATE_STORAGE" tar
    command tar "$@"
  }
  xz() {
    _test_probe held "$TEMPLATE_STORAGE" xz
    command xz "$@"
  }
  if [[ "${CACHE_ACTION:-}" != '' ]]; then
    export TEMPLATE="$TEST_TEMPLATE" ONLINE_TEMPLATE="${TEST_ONLINE:-$TEST_TEMPLATE}"
    printf '1\n' > "$CASE_ROOT/$CREATOR-list-count"
    case "$CACHE_ACTION" in
      selection)
        TEMPLATE_PATH="$CASE_ROOT/$TEST_STORAGE/template/cache/old.tar.xz"
        _template_prepare_archive initial
        ;;
      corrupt-local)
        ONLINE_TEMPLATE=''
        _template_prepare_archive initial
        ;;
    esac
  else
    printf '%s\n' "$BASHPID" > "$CASE_ROOT/$CREATOR-worker"
    create_lxc_container
  fi
  exit 0
fi

if [[ "${1:-}" != --inside ]]; then
  mode="${1:---native}"
  [[ "$mode" == --native || "$mode" == --baseline || "$mode" == --review-baseline || "$mode" == --pty-baseline ]] || exit 64
  export SUBJECT_BUILD="$ROOT/misc/build.func"
  if [[ "$mode" == --baseline ]]; then
    SUBJECT_BUILD=$(realpath -e "${2:?owned path-instrumented baseline required}")
    [[ "$SUBJECT_BUILD" == "$TMPDIR/"* || "$SUBJECT_BUILD" == "${TMPDIR%/tmp}/"* ]] || exit 65
    ! grep -Fq 'lockfile="/tmp/template.' "$SUBJECT_BUILD" || exit 65
    grep -Fq 'lockfile="${LEGACY_LOCK_ROOT}/template.' "$SUBJECT_BUILD" || exit 65
  fi
  if [[ "$mode" == --review-baseline ]]; then
    SUBJECT_BUILD=$(realpath -e "${2:?preserved review build.func required}")
    ! grep -Fq 'lockfile="/tmp/template.' "$SUBJECT_BUILD" || exit 65
  fi
  if [[ "$mode" == --pty-baseline ]]; then
    export PTY_BASELINE
    PTY_BASELINE=$(realpath -e "${2:?preserved safe test transport required}")
  fi
  export TEST_MODE="$mode"
  export work
  work=$(mktemp -d "$TMPDIR/template-lock.XXXXXXXX")
  # Retain evidence/timelines on disk; all fixture processes die with PID ns.
  printf 'Evidence: %s; mode=%s\n' "$work" "$mode"
  cat > "$work/audit.py" << 'PY'
import hashlib,json,pathlib,sys
roots=[pathlib.Path('/var/lib/pve-manager/apl-info'),pathlib.Path('/var/log/pveam.log')]
r={}
for root in roots:
 for p in [root]+(sorted(root.rglob('*')) if root.is_dir() else []):
  if not p.exists():r[str(p)]=None;continue
  s=p.stat();v=[s.st_dev,s.st_ino,s.st_mode,s.st_size,s.st_mtime_ns,s.st_ctime_ns]
  if p.is_file():v.append(hashlib.sha256(p.read_bytes()).hexdigest())
  r[str(p)]=v
out=pathlib.Path(sys.argv[1])
if len(sys.argv)>2:
 assert r==json.loads(out.read_text()),'real node catalogue/log changed'
 print('NODE_CATALOGUE_LOG_BOUNDARY_UNCHANGED')
else:out.write_text(json.dumps(r,sort_keys=True))
PY
  python3 "$work/audit.py" "$work/node-before.json"
  rc=0
  unshare --mount --net --pid --fork --mount-proc bash "$0" --inside || rc=$?
  python3 "$work/audit.py" "$work/node-before.json" verify
  exit "$rc"
fi

mount --make-rprivate /
mkdir -p "$work/metadata" "$work/etc-pve/lxc" "$work/vz/template/cache" "$work/subjects/bin" "$work/legacy"
# Preserve access to the disk workspace while hiding all real framework metadata.
managed=/var/lib/scripts-underground
for needed in "$ROOT" "$(realpath -e "$TMPDIR")"; do
  if [[ "$needed" == "$managed/"* ]]; then
    relative=${needed#"$managed/"}
    first=${relative%%/*}
    if [[ ! -d "$work/metadata/$first" ]]; then
      mkdir "$work/metadata/$first"
      mount --bind "$managed/$first" "$work/metadata/$first"
    fi
  fi
done
mount --rbind "$work/metadata" /var/lib/scripts-underground
[[ -r "$0" && -d "$TMPDIR" ]] || {
  printf 'Cannot preserve source/temp paths under managed metadata\n' >&2
  exit 65
}
mount --bind "$work/etc-pve" /etc/pve
mount --bind "$work/vz" /var/lib/vz
printf 'root:100000:65536\n' > "$work/subuid"
cp "$work/subuid" "$work/subgid"
mount --bind "$work/subuid" /etc/subuid
mount --bind "$work/subgid" /etc/subgid
mount --bind /tmp /tmp
mount -o remount,bind,ro /tmp
export SUBJECT="$work/subjects" LEGACY_LOCK_ROOT="$work/legacy"
for protected in /var/lib/pve-manager /var/log/pveam.log /var/log/pve/tasks; do
  if [[ -e "$protected" ]]; then
    mount --bind "$protected" "$protected"
    mount -o remount,bind,ro "$protected"
  fi
done
for tool in pveam pvesm pct qm apt-get apt-cache dpkg-query; do
  native_path=$(command -v "$tool" || true)
  printf '#!/usr/bin/env bash\nexec bash %q --model %q "$@"\n' "$0" "$tool" > "$SUBJECT/bin/$tool"
  chmod 700 "$SUBJECT/bin/$tool"
  if [[ -n "$native_path" ]]; then mount --bind "$SUBJECT/bin/$tool" "$(realpath -e "$native_path")"; fi
done
flock_native=$(type -P flock)
printf '#!/usr/bin/env bash\nprintf "%%s\\n" "$(date +%%s%%N)" > "$CASE_ROOT/$CREATOR-flock-attempt"\nexec %q "$@"\n' "$flock_native" > "$SUBJECT/bin/flock"
chmod 700 "$SUBJECT/bin/flock"
cp "$ROOT/misc/error_handler.func" "$SUBJECT/error_handler.func"
if [[ "$TEST_MODE" == --baseline ]]; then
  cp "$(dirname "$SUBJECT_BUILD")/error_handler.func" "$SUBJECT/error_handler.func"
fi
python3 - "$SUBJECT_BUILD" "$SUBJECT/functions.sh" << 'PY'
import pathlib,re,sys
s=pathlib.Path(sys.argv[1]).read_text()
functions=re.findall(r'^(?:_template_[a-z_]+|create_lxc_container)\(\) \{\n.*?^}',s,re.M|re.S)
assert functions and functions[-1].startswith('create_lxc_container()')
if '_template_lock_acquire()' not in s:
 start=s.index('  lockfile="${LEGACY_LOCK_ROOT}/template.')
 end=s.index('  LOGFILE=',start)
 functions.append('baseline_acquire() {\n'+s[start:end]+'}\n')
pathlib.Path(sys.argv[2]).write_text('\n\n'.join(functions)+'\n')
PY
cat > "$SUBJECT/probe.py" << 'PY'
import fcntl,glob,os,pathlib,sys
c,expected,storage,operation=sys.argv[1:]
if os.environ.get('PROBE_CRASH')=='1':raise RuntimeError('owned probe crash control')
paths=glob.glob('/var/lib/scripts-underground/template-locks/*')
held=[];inherited=[]
for p in paths:
 identity=os.stat(p)
 for name in os.listdir('/proc/self/fd'):
  try:s=os.fstat(int(name))
  except OSError:continue
  if (s.st_dev,s.st_ino)==(identity.st_dev,identity.st_ino):inherited.append(p)
 fd=os.open(p,os.O_RDWR)
 try:
  try:fcntl.flock(fd,fcntl.LOCK_EX|fcntl.LOCK_NB)
  except BlockingIOError:held.append(p)
 finally:os.close(fd)
ok=bool(set(held)&set(inherited)) if expected=='held' else not inherited
print(('PASS' if ok else 'FAIL')+' '+operation+' '+expected+' '+storage+' held='+repr(held)+' inherited='+repr(inherited),flush=True)
if expected=='held' and inherited:
 p=pathlib.Path(c)/(os.environ['CREATOR']+'-lock-identity')
 s=os.stat(inherited[0]);p.write_text(str(s.st_dev)+':'+str(s.st_ino)+'\n'+inherited[0])
raise SystemExit(0 if ok else 97)
PY
cat > "$SUBJECT/pty.py" << 'PY'
import errno,json,os,pathlib,pty,select,subprocess,sys,time
c=pathlib.Path(os.environ['CASE_ROOT']);name=os.environ['CREATOR']
m,s=pty.openpty()
(c/(name+'-pty.json')).write_text(json.dumps({'pid':os.getpid(),'start':pathlib.Path('/proc/self/stat').read_text().split()[21],'fd':m,'slave':os.ttyname(s)}))
p=subprocess.Popen(['bash',*sys.argv[1:]],stdin=subprocess.DEVNULL,stdout=s,stderr=s)
os.close(s)
deadline=time.monotonic()+float(os.environ.get('WORKER_SECONDS','40'))-1
recorded=False
while True:
 rc=p.poll()
 if rc is not None and not recorded:
  stage=c/(name+'-leader-status.new');stage.write_text(str(rc if rc>=0 else 128-rc));stage.replace(c/(name+'-leader-status'));recorded=True
 if rc is not None and (os.environ.get('KEEP_PTY_MASTER')!='1' or (c/(name+'-close-pty')).exists()):break
 if time.monotonic()>deadline:raise SystemExit('owned PTY release deadline expired')
 if select.select([m],[],[],.05)[0]:
  try:b=os.read(m,65536)
  except OSError as e:
   if e.errno!=errno.EIO:raise
   b=b''
  if b:os.write(1,b)
  else:time.sleep(.025)
os.close(m)
(c/(name+'-pty-closed')).write_text('closed')
rc=p.wait();raise SystemExit(rc if rc>=0 else 128-rc)
PY
if [[ "${PTY_BASELINE:-}" != '' ]]; then
  # Preserve the old close-on-launcher-exit behavior; add only status/FD metadata
  # observations so the new assertions can distinguish a real transport RED.
  python3 - "$PTY_BASELINE" "$SUBJECT/pty.py" << 'PY'
import pathlib,re,sys
s=pathlib.Path(sys.argv[1]).read_text()
b=re.findall(r'''cat > "\$SUBJECT/pty.py" << 'PY'\n(.*?)\nPY''',s,re.S)
assert len(b)==1
old=b[0].replace('import errno,os,pty,select,subprocess,sys','import errno,json,os,pathlib,pty,select,subprocess,sys')
old=old.replace('m,s=pty.openpty()',"c=pathlib.Path(os.environ['CASE_ROOT']);name=os.environ['CREATOR']\nm,s=pty.openpty()\n(c/(name+'-pty.json')).write_text(json.dumps({'pid':os.getpid(),'start':pathlib.Path('/proc/self/stat').read_text().split()[21],'fd':m,'slave':os.ttyname(s)}))")
old=old.replace('os.close(m)',"rc=p.wait()\n(c/(name+'-leader-status')).write_text(str(rc if rc>=0 else 128-rc))\nos.close(m)\n(c/(name+'-pty-closed')).write_text('old-close-on-leader-exit')")
pathlib.Path(sys.argv[2]).write_text(old+'\n')
PY
fi
cat > "$SUBJECT/ui_holder.py" << 'PY'
import errno,json,os,pathlib,sys,time
c=pathlib.Path(sys.argv[1]);name=sys.argv[2]
identity=(c/(name+'-lock-identity')).read_text().splitlines()[0]
fds=[]
for f in os.listdir('/proc/self/fd'):
 try:s=os.fstat(int(f))
 except OSError:continue
 if str(s.st_dev)+':'+str(s.st_ino)==identity:fds.append(int(f))
assert fds,'control did not inherit the real template FD'
tty=os.open(os.environ['MODEL_TTY'],os.O_WRONLY|os.O_NOCTTY)
record={'pid':os.getpid(),'start':pathlib.Path('/proc/self/stat').read_text().split()[21],'identity':identity,'fds':fds}
(c/(name+'-ui.json')).write_text(json.dumps(record))
deadline=time.monotonic()+25;tick=0
while time.monotonic()<deadline:
 try:os.write(tty,b'\rowned nonproductive inherited-FD control')
 except OSError as e:
  (c/(name+'-ui-exit')).write_text('tty-error:'+str(e.errno));raise SystemExit(0)
 tick+=1
 stage=c/(name+'-ui-tick.new');stage.write_text(str(tick));stage.replace(c/(name+'-ui-tick'))
 time.sleep(.05)
(c/(name+'-ui-exit')).write_text('deadline');raise SystemExit(98)
PY
cat > "$SUBJECT/pty_live.py" << 'PY'
import json,os,pathlib,sys
c=pathlib.Path(sys.argv[1]);name=sys.argv[2];r=json.loads((c/(name+'-pty.json')).read_text())
try:
 start=pathlib.Path('/proc/'+str(r['pid'])+'/stat').read_text().split()[21]
 target=os.readlink('/proc/'+str(r['pid'])+'/fd/'+str(r['fd']))
 ok=start==r['start'] and target.endswith('/ptmx') and not (c/(name+'-pty-closed')).exists()
except FileNotFoundError:ok=False
print('live' if ok else 'closed')
PY
cat > "$SUBJECT/stop_ui.py" << 'PY'
import json,os,pathlib,signal,sys,time
c=pathlib.Path(sys.argv[1]);name=sys.argv[2];r=json.loads((c/(name+'-ui.json')).read_text());p=pathlib.Path('/proc')/str(r['pid'])
try:fields=(p/'stat').read_text().split()
except FileNotFoundError:print('absent');raise SystemExit(0)
if fields[2]=='Z':print('absent');raise SystemExit(0)
assert fields[21]==r['start'],'control PID identity changed'
cmd=(p/'cmdline').read_bytes().split(b'\0');assert any(x.endswith(b'/ui_holder.py') for x in cmd) and str(c).encode() in cmd
assert any(str(os.stat(p/'fd'/str(f)).st_dev)+':'+str(os.stat(p/'fd'/str(f)).st_ino)==r['identity'] for f in r['fds'])
os.kill(r['pid'],signal.SIGTERM)
deadline=time.monotonic()+2.5
def running():
 try:f=(p/'stat').read_text().split()
 except FileNotFoundError:return False
 return f[2]!='Z' and f[21]==r['start']
while running() and time.monotonic()<deadline:
 time.sleep(.025)
assert not running(),'control did not stop'
print('stopped:'+str(r['pid']))
PY
cat > "$SUBJECT/producer.py" << 'PY'
import os,pathlib,sys,time
c=pathlib.Path(sys.argv[1]);name=sys.argv[2]
(c/(name+'-productive')).write_text(str(os.getpid()))
deadline=time.monotonic()+15
while not (c/(name+'-finish-producer')).exists():
 if time.monotonic()>deadline:raise SystemExit(98)
 time.sleep(.025)
(c/(name+'-product')).write_text('complete')
PY
cat > "$SUBJECT/scan.py" << 'PY'
import glob,json,os,pathlib,sys
identity=pathlib.Path(sys.argv[1]).read_text().splitlines()[0]
holders=[]
for name in glob.glob('/proc/[0-9]*/fd/*'):
 try:s=os.stat(name)
 except (FileNotFoundError,ProcessLookupError):continue
 if str(s.st_dev)+':'+str(s.st_ino)==identity:holders.append(name)
print(json.dumps(holders))
PY
failures=0
checks=0
check() {
  checks=$((checks + 1))
  if [[ "$1" == "$2" ]]; then printf 'PASS %s\n' "$3"; else
    printf 'FAIL %s: expected <%s>, got <%s>\n' "$3" "$2" "$1" >&2
    failures=$((failures + 1))
  fi
}
start() {
  local creator="$1" storage="$2"
  mkdir -p "$CASE_ROOT/tmp-$creator"
  local -a prefix=()
  [[ "${DROP_DAC:-0}" == 0 ]] || prefix=(setpriv '--bounding-set=-dac_override,-dac_read_search')
  env TMPDIR="$CASE_ROOT/tmp-$creator" CREATOR="$creator" TEST_STORAGE="$storage" \
    "${prefix[@]}" timeout --signal=TERM --kill-after=3 "${WORKER_SECONDS:-40}" python3 -I -B "$SUBJECT/pty.py" "$0" --worker > "$CASE_ROOT/$creator-output" 2>&1 &
  last_pid=$!
}
new_case() {
  export CASE_ROOT="$work/$1" TEST_TEMPLATE=alpine-3-default_3.1-1_amd64.tar.xz
  mkdir -p "$CASE_ROOT/local/template/cache" "$CASE_ROOT/other/template/cache" "$CASE_ROOT/payload/etc"
  printf 'dir: local\n path %s/local\ndir: other\n path %s/other\ndir: alias\n path %s/alias\n' "$CASE_ROOT" "$CASE_ROOT" "$CASE_ROOT" > /etc/pve/storage.cfg
  # Actual valid >1MB archive (uncompressed tar padding survives xz -0 poorly,
  # so random file ensures the compressed archive meets the production threshold).
  dd if=/dev/urandom of="$CASE_ROOT/payload/data" bs=1048576 count=2 status=none
  tar -C "$CASE_ROOT/payload" -cJf "$CASE_ROOT/payload.tar.xz" .
  : > "$CASE_ROOT/timeline"
  : > "$CASE_ROOT/observed"
  : > "$CASE_ROOT/commands"
  : > "$CASE_ROOT/probes-required"
}
observations() {
  python3 - "$1" << 'PY'
import collections,pathlib,sys
c=pathlib.Path(sys.argv[1]);required=(c/'probes-required').read_text().splitlines();observed=(c/'observed').read_text().splitlines()
passes=[l.split()[1] for l in observed if l.startswith('PASS ')]
bad=[l for l in observed if not l.startswith('PASS ')]
ok=bool(required) and not bad and collections.Counter(required)==collections.Counter(passes)
print(0 if ok else 1)
PY
}
await_file() {
  for ((i = 0; i < 200; i++)); do
    [[ ! -e "$1" ]] || return 0
    sleep .025
  done
  return 1
}
export TEST_ROUTE=initial
new_case concurrent
export DISCOVERY_BARRIER=1
start a other
a=$last_pid
start b other
b=$last_pid
ra=0
wait "$a" || ra=$?
rb=0
wait "$b" || rb=$?
unset DISCOVERY_BARRIER
check "$ra/$rb" 0/0 'same cache creators finish'
check "$(grep -c download-start "$CASE_ROOT/timeline" || true)" 1 'different TMPDIR creators publish once'
check "$(observations "$CASE_ROOT")" 0 'positive producer/final-list/pct probes all complete with correct FD outcome'
check "$(awk -F '\t' '$2=="pveam" && $3=="update" && $4=="timeout" {n++} END {print n+0}' "$CASE_ROOT/commands")" 2 'timeout executes both recording catalogue models'
check "$(grep -c '^PASS final-list ' "$CASE_ROOT/observed" || true)" 2 'both final-list endpoints positively observed under hold'
check "$(find /var/lib/scripts-underground/template-locks -type f 2> /dev/null | wc -l)" 1 'one persistent lock inode'

for route in repair fallback; do
  new_case "$route"
  export TEST_ROUTE="$route"
  start a other
  a=$last_pid
  rc=0
  wait "$a" || rc=$?
  check "$rc" 0 "$route creation completes"
  check "$(observations "$CASE_ROOT")" 0 "$route positive probes cover producers/final-list/pct outcomes"
  check "$(grep -c '^PASS final-list ' "$CASE_ROOT/observed" || true)" 2 "$route final-list endpoints are both positively required"
done
export TEST_ROUTE=initial

# Start another creator during the actual repair/fallback publisher. It must
# recheck after waiting and consume that publication, rather than download again.
for route in repair fallback; do
  new_case "wait-$route"
  export TEST_ROUTE="$route" HOLD_CACHE_PUBLISH=1
  start a other
  a=$last_pid
  await_file "$CASE_ROOT/a-publisher-held"
  export TEST_ROUTE=initial
  target=other
  [[ "$route" != fallback ]] || target=local
  start b "$target"
  b=$last_pid
  await_file "$CASE_ROOT/b-flock-attempt" || true
  check "$(test -e "$CASE_ROOT/b-flock-attempt" && test ! -e "$CASE_ROOT/a-finish-publisher" && printf observed || printf absent)" observed "$route consumer starts real flock while producer is held"
  check "$(test -e "$CASE_ROOT/b-create-count" && printf reached || printf blocked)" blocked "$route waiter has not reached pct during publisher hold"
  printf finish > "$CASE_ROOT/a-finish-publisher"
  ra=0
  wait "$a" || ra=$?
  rb=0
  wait "$b" || rb=$?
  check "$ra/$rb" 0/0 "$route waiting consumer completes"
  check "$(grep -c download-start "$CASE_ROOT/timeline" || true)" 2 "$route waiting consumer revalidates without duplicate publication"
  check "$(observations "$CASE_ROOT")" 0 "$route waiter has complete positive consumer observations"
  check "$(grep -c '^PASS final-list ' "$CASE_ROOT/observed" || true)" 3 "$route waiters and publisher all reach held final-list endpoints"
  unset HOLD_CACHE_PUBLISH
done

# Cache aliases collapse by the resolved parent, not by storage spelling.
for alias_kind in symlink bind; do
  new_case "$alias_kind"
  export DISCOVERY_BARRIER=1
  if [[ "$alias_kind" == symlink ]]; then
    ln -s "$CASE_ROOT/other" "$CASE_ROOT/alias"
  else
    mkdir "$CASE_ROOT/alias"
    mount --bind "$CASE_ROOT/other" "$CASE_ROOT/alias"
  fi
  start a other
  a=$last_pid
  start b alias
  b=$last_pid
  ra=0
  wait "$a" || ra=$?
  rb=0
  wait "$b" || rb=$?
  unset DISCOVERY_BARRIER
  check "$ra/$rb" 0/0 "$alias_kind cache alias creators finish"
  check "$(grep -c download-start "$CASE_ROOT/timeline" || true)" 1 "$alias_kind cache aliases share serialization"
done

new_case openeuler
export TEST_OS=openeuler
start a other
a=$last_pid
rc=0
wait "$a" || rc=$?
check "$rc" 0 'openEuler preparation completes'
check "$(tar -tf "$CASE_ROOT/other/template/cache/$TEST_TEMPLATE" | grep -c '^etc/redhat-release$')" 1 'openEuler archive contains actual release file'
check "$(observations "$CASE_ROOT")" 0 'openEuler positive archive validators/xz/final-list/pct probes complete'
unset TEST_OS

lock_available() { [[ -e "$1" ]] && flock -n "$1" true; }
lock_state() {
  if [[ ! -e "$1" ]]; then printf absent; elif lock_available "$1"; then printf free; else printf held; fi
}
export LOCK_ACTION=hold
new_case lifetime
start holder other
holder=$last_pid
await_file "$CASE_ROOT/holder-held"
lockpath=$(< "$CASE_ROOT/holder-lock")
inode=$(< "$CASE_ROOT/holder-inode")
spinner=$(< "$CASE_ROOT/holder-spinner")
check "$(test -n "$spinner" && printf spawned || printf absent)" spawned 'real guest PTY creates an actual spinner'
spinner_state=$(ps -o stat= -p "$spinner" || true)
check "$(if [[ -z "$spinner_state" || "$spinner_state" == Z* ]]; then printf stopped; else printf live; fi)" stopped 'pre-existing real spinner stopped before hold'
touch -d '2000-01-01' "$lockpath"
start waiter other
waiter=$last_pid
await_file "$CASE_ROOT/waiter-worker"
sleep .3
check "$(test -f "$CASE_ROOT/waiter-held" && printf entered || printf blocked)" blocked 'ancient mtime cannot split active lock'
check "$(stat -c '%d:%i' "$lockpath")" "$inode" 'waiter preserves active inode'
# timeout owns a separate process group; signal this owned waiter AND its
# synchronous flock child, so Bash need not defer TERM until flock's 30s return.
kill -TERM -- "-$waiter"
rc=0
wait "$waiter" || rc=$?
check "$rc" 143 'terminated waiter retains signal status'
check "$(test -e "$lockpath" && stat -c '%d:%i' "$lockpath" || printf absent)" "$inode" 'waiter EXIT never unlinks active inode'
check "$(lock_state "$lockpath")" held 'holder still protects after waiter exit'
printf release > "$CASE_ROOT/holder-release"
rc=0
wait "$holder" || rc=$?
check "$rc" 0 'holder releases normally'
check "$(lock_state "$lockpath")" free 'explicit release makes flock available'
check "$(test -e "$lockpath" && stat -c '%d:%i' "$lockpath" || printf absent)" "$inode" 'normal EXIT retains same persistent inode'

for action in err exit app-exit hold productive; do
  new_case "death-$action"
  export LOCK_ACTION="$action"
  start owner other
  owner=$last_pid
  await_file "$CASE_ROOT/owner-held"
  lockpath=$(< "$CASE_ROOT/owner-lock")
  inode=$(< "$CASE_ROOT/owner-inode")
  if [[ "$action" == hold || "$action" == productive ]]; then
    [[ "$action" != productive ]] || await_file "$CASE_ROOT/owner-productive"
    kill -KILL "$(< "$CASE_ROOT/owner-worker")"
  fi
  rc=0
  wait "$owner" || rc=$?
  case "$action" in err) expected=1 ;; exit | app-exit) expected=37 ;; *) expected=137 ;; esac
  check "$rc" "$expected" "$action preserves exact terminal status"
  if [[ "$action" == productive ]]; then
    check "$(lock_state "$lockpath")" held 'surviving productive child retains protection after launcher death'
    printf finish > "$CASE_ROOT/owner-finish-producer"
    await_file "$CASE_ROOT/owner-product"
    for ((i = 0; i < 100; i++)); do
      lock_available "$lockpath" && break
      sleep .025
    done
    check "$(< "$CASE_ROOT/owner-product")" complete 'surviving producer reaches actual consumer file'
  fi
  # A killed shell's current synchronous sleep/stat child may outlive it for a
  # scheduling tick. Observe final FD closure rather than racing that child.
  if [[ "$action" == hold ]]; then
    for ((i = 0; i < 100; i++)); do
      lock_available "$lockpath" && break
      sleep .025
    done
  fi
  check "$(lock_state "$lockpath")" free "$action all productive FDs closed releases kernel lock"
  check "$(test -e "$lockpath" && stat -c '%d:%i' "$lockpath" || printf absent)" "$inode" "$action preserves persistent inode"
  if [[ "$action" == app-exit ]]; then
    check "$(test -f "$CASE_ROOT/app-owned" && cat "$CASE_ROOT/app-owned" || printf absent)" keep 'generic EXIT does not delete caller-owned lockfile data'
  fi
done

new_case independent
export LOCK_ACTION=hold
start one other
one=$last_pid
await_file "$CASE_ROOT/one-held"
start two local
two=$last_pid
await_file "$CASE_ROOT/two-held" || true
check "$(test -e "$CASE_ROOT/two-held" && printf entered || printf blocked)" entered 'distinct storage progresses while first held'
TEST_TEMPLATE=alpine-3-default_3.2-1_amd64.tar.xz start three other
three=$last_pid
await_file "$CASE_ROOT/three-held" || true
check "$(test -e "$CASE_ROOT/three-held" && printf entered || printf blocked)" entered 'distinct template progresses while first held'
for name in one two three; do printf release > "$CASE_ROOT/$name-release"; done
wait "$one"
wait "$two"
wait "$three"
unset LOCK_ACTION

if [[ "$TEST_MODE" != --baseline ]]; then
  if [[ "$TEST_MODE" == --native ]]; then
    new_case wait-timeout
    export LOCK_ACTION=hold HOLD_TICKS=14000 WORKER_SECONDS=340
    start holder other
    holder=$last_pid
    await_file "$CASE_ROOT/holder-held"
    p=$(< "$CASE_ROOT/holder-lock")
    inode=$(< "$CASE_ROOT/holder-inode")
    start waiter other
    waiter=$last_pid
    rc=0
    wait "$waiter" || rc=$?
    check "$rc" 211 'real ten30-second waiter exhaustion retains status211'
    check "$(stat -c '%d:%i' "$p")" "$inode" 'wait timeout preserves active inode'
    check "$(lock_state "$p")" held 'holder still protects after real timeout'
    printf release > "$CASE_ROOT/holder-release"
    wait "$holder"
    unset HOLD_TICKS WORKER_SECONDS LOCK_ACTION
  fi

  for fault in mode symlink; do
    new_case "namespace-$fault"
    p=/var/lib/scripts-underground/template-locks
    if [[ "$fault" == mode ]]; then chmod 755 "$p"; else
      mv "$p" "$p-aside"
      mkdir "$CASE_ROOT/unsafe-directory"
      ln -s "$CASE_ROOT/unsafe-directory" "$p"
    fi
    export LOCK_ACTION=hold
    start unsafe other
    unsafe=$last_pid
    rc=0
    wait "$unsafe" || rc=$?
    check "$rc" 200 "$fault unsafe namespace refused"
    if [[ "$fault" == mode ]]; then
      check "$(stat -c %a "$p")" 755 'existing namespace mode never rewritten'
      chmod 700 "$p"
    else
      check "$(stat -c %a "$CASE_ROOT/unsafe-directory")" 755 'symlink destination mode preserved'
      rm "$p"
      mv "$p-aside" "$p"
    fi
  done
  unset LOCK_ACTION
  # Namespace/file validation controls use real paths, links, modes and owners.
  for fault in directory symlink fifo hardlink mode owner bytes; do
    new_case "unsafe-$fault"
    export LOCK_ACTION=hold
    # Obtain the genuine selected pathname without duplicating the key algorithm.
    start seed other
    seed=$last_pid
    await_file "$CASE_ROOT/seed-held"
    p=$(< "$CASE_ROOT/seed-lock")
    printf release > "$CASE_ROOT/seed-release"
    wait "$seed"
    case "$fault" in
      directory)
        rm "$p"
        mkdir "$p"
        ;;
      symlink)
        rm "$p"
        printf preserve > "$CASE_ROOT/target"
        ln -s "$CASE_ROOT/target" "$p"
        ;;
      fifo)
        rm "$p"
        mkfifo "$p"
        ;;
      hardlink) ln "$p" "$p-second-link" ;;
      mode) chmod 666 "$p" ;;
      owner) chown 65534 "$p" ;;
      bytes) printf preserve > "$p" ;;
    esac
    start unsafe other
    unsafe=$last_pid
    rc=0
    wait "$unsafe" || rc=$?
    check "$rc" 200 "$fault unsafe lock refused before blocking/open effects"
    check "$(grep -Fc "$p" "$CASE_ROOT/unsafe-output" || true)" 1 "$fault lock refusal identifies the offending path"
    if [[ "$fault" == symlink ]]; then check "$(< "$CASE_ROOT/target")" preserve 'lock symlink target bytes untouched'; fi
    # Remove only this test's own tampered fixture before subsequent cases.
    if [[ -d "$p" && ! -L "$p" ]]; then rmdir "$p"; else rm "$p"; fi
    [[ "$fault" != hardlink ]] || rm "$p-second-link"
  done
  unset LOCK_ACTION
  for fault in symlink directory unreadable corrupt storage; do
    new_case "archive-$fault"
    p="$CASE_ROOT/other/template/cache/$TEST_TEMPLATE"
    case "$fault" in
      symlink) ln -s "$CASE_ROOT/payload.tar.xz" "$p" ;;
      directory) mkdir "$p" ;;
      unreadable)
        cp "$CASE_ROOT/payload.tar.xz" "$p"
        chmod 000 "$p"
        export DROP_DAC=1
        ;;
      corrupt) export BAD_PUBLISH=1 ;;
      storage) export FAIL_STORAGE=1 ;;
    esac
    start unsafe other
    unsafe=$last_pid
    rc=0
    wait "$unsafe" || rc=$?
    case "$fault" in corrupt) expected=222 ;; storage) expected=47 ;; *) expected=221 ;; esac
    check "$rc" "$expected" "$fault archive/storage failure preserves status"
    check "$(test -e "$CASE_ROOT/unsafe-create-count" && printf reached || printf absent)" absent "$fault failure never reaches pct create"
    unset DROP_DAC BAD_PUBLISH FAIL_STORAGE
  done
  new_case download-failure
  export FAIL_DOWNLOAD=1
  start unsafe other
  unsafe=$last_pid
  rc=0
  wait "$unsafe" || rc=$?
  check "$rc" 222 'initial download exhausts three attempts with status222'
  check "$(grep -c download-start "$CASE_ROOT/timeline" || true)" 3 'initial retry budget retained'
  unset FAIL_DOWNLOAD
  new_case missing-cache
  rmdir "$CASE_ROOT/other/template/cache"
  start empty other
  empty=$last_pid
  rc=0
  wait "$empty" || rc=$?
  check "$rc" 0 'native-storage preparation model creates missing cache before lock key selection'
  check "$(test -f "$CASE_ROOT/other/template/cache/$TEST_TEMPLATE" && printf published || printf absent)" published 'missing-cache consumer receives valid archive'

  for failure in 42 200 validation local-failure local-validation safety; do
    new_case "repair-outcome-$failure"
    export TEST_ROUTE=repair
    case "$failure" in
      42 | 200) export REPAIR_FAILURE="$failure" ;;
      validation) export REPAIR_BAD=1 ;;
      local-failure) export REPAIR_FAILURE=42 FALLBACK_FAILURE=43 ;;
      local-validation) export REPAIR_FAILURE=42 FALLBACK_BAD=1 ;;
      safety) export REPAIR_LOCK_FAULT=1 ;;
    esac
    start repair other
    pid=$last_pid
    rc=0
    wait "$pid" || rc=$?
    case "$failure" in local-failure) expected=43 ;; local-validation) expected=222 ;; safety) expected=200 ;; *) expected=0 ;; esac
    check "$rc" "$expected" "$failure repair/fallback exact terminal outcome"
    if [[ "$failure" == safety ]]; then
      check "$(grep -c 'download-start local' "$CASE_ROOT/timeline" || true)" 0 'lock safety refusal never becomes local fallback'
    elif [[ "$expected" == 0 ]]; then
      check "$(grep -c 'download-start local' "$CASE_ROOT/timeline" || true)" 1 "$failure non-local failed repair reaches local producer"
      check "$(< "$CASE_ROOT/repair-create-count")" 2 "$failure invalid repaired archive is not reused by pct"
      check "$(test -f "$CASE_ROOT/local/template/cache/$TEST_TEMPLATE" && printf published || printf absent)" published "$failure local consumer receives valid archive"
    fi
    check "$(observations "$CASE_ROOT")" 0 "$failure repair has positive probe outcomes"
    unset REPAIR_FAILURE REPAIR_BAD FALLBACK_FAILURE FALLBACK_BAD REPAIR_LOCK_FAULT
  done

  new_case local-repair-failure
  export TEST_ROUTE=repair REPAIR_FAILURE=42
  # The model scopes repair failure by storage; use a dedicated local fault after
  # the first successful publication, not an initial-download failure.
  export LOCAL_REPAIR_FAILURE=44
  start repair local
  pid=$last_pid
  rc=0
  wait "$pid" || rc=$?
  check "$rc" 44 'local repair failure preserves its native terminal status'
  unset REPAIR_FAILURE LOCAL_REPAIR_FAILURE
  export TEST_ROUTE=initial

  for fault in final-list resolve; do
    new_case "$fault"
    if [[ "$fault" == final-list ]]; then export MISSING_FINAL_LIST=1; else
      export SKIP_CACHE_PREPARE=1
      rmdir "$CASE_ROOT/other/template/cache"
    fi
    start failed other
    pid=$last_pid
    rc=0
    wait "$pid" || rc=$?
    if [[ "$fault" == final-list ]]; then expected=223; else expected=220; fi
    check "$rc" "$expected" "$fault preserves explicit terminal status"
    check "$(test -e "$CASE_ROOT/failed-create-count" && printf reached || printf absent)" absent "$fault cannot reach pct create"
    if [[ "$fault" == resolve ]]; then
      check "$(grep -Fc "$CASE_ROOT/other/template/cache/$TEST_TEMPLATE" "$CASE_ROOT/failed-output" || true)" 1 'resolve refusal identifies the missing cache path'
    else
      check "$(grep -c '^PASS final-list ' "$CASE_ROOT/observed" || true)" 1 'missing final-list endpoint is positively probed under lock'
    fi
    unset MISSING_FINAL_LIST SKIP_CACHE_PREPARE
  done

  new_case storage-cfg-resolver
  export FAIL_PATH_LOOKUP=1
  start cfg other
  pid=$last_pid
  rc=0
  wait "$pid" || rc=$?
  check "$rc" 0 'storage.cfg resolver succeeds when pvesm path is unavailable'
  check "$(test -f "$CASE_ROOT/other/template/cache/$TEST_TEMPLATE" && printf correct || printf absent)" correct 'storage.cfg resolved archive reaches configured consumer path'
  unset FAIL_PATH_LOOKUP

  for action in corrupt-local selection invalid-selection; do
    new_case "owner-$action"
    export CACHE_ACTION="$action"
    cp "$CASE_ROOT/payload.tar.xz" "$CASE_ROOT/other/template/cache/old.tar.xz"
    if [[ "$action" == corrupt-local ]]; then
      cp "$CASE_ROOT/payload.tar.xz" "$CASE_ROOT/other/template/cache/$TEST_TEMPLATE"
      printf 'CORRUPT' | dd of="$CASE_ROOT/other/template/cache/$TEST_TEMPLATE" conv=notrunc status=none
      cp "$CASE_ROOT/other/template/cache/$TEST_TEMPLATE" "$CASE_ROOT/corrupt-before"
    elif [[ "$action" == invalid-selection ]]; then
      TEST_TEMPLATE=invalid/name.tar.xz
      CACHE_ACTION=selection
    fi
    start owner other
    pid=$last_pid
    rc=0
    wait "$pid" || rc=$?
    expected=0
    [[ "$action" != invalid-selection ]] || expected=220
    check "$rc" "$expected" "$action direct actual owner boundary outcome (not unreachable prompt claim)"
    check "$(cmp -s "$CASE_ROOT/payload.tar.xz" "$CASE_ROOT/other/template/cache/old.tar.xz" && printf same || printf changed)" same "$action preserves old selected archive bytes"
    if [[ "$action" == corrupt-local ]]; then
      check "$(cmp -s "$CASE_ROOT/corrupt-before" "$CASE_ROOT/other/template/cache/$TEST_TEMPLATE" && printf same || printf changed)" same 'no-online corrupt local archive retains exact prior bytes'
      check "$(grep -c download-start "$CASE_ROOT/timeline" || true)" 0 'no-online corrupt local archive is not redownloaded'
    fi
    unset CACHE_ACTION
  done

  new_case stack-retry
  export TEST_ROUTE=stack
  start stack other
  pid=$last_pid
  rc=0
  wait "$pid" || rc=$?
  check "$rc" 0 'checked local fallback LXC-stack retry completes'
  check "$(awk -F '\t' '$2=="pct" && $3=="create" {last=$5} END {print last}' "$CASE_ROOT/commands" | cut -d ' ' -f3)" "local:vztmpl/$TEST_TEMPLATE" 'stack retry uses actual selected fallback storage'
  check "$(awk -F '\t' '$2=="apt-get" {n++} END {print n+0}' "$CASE_ROOT/commands")" 2 'stack package update/install boundaries are recording executables'
  export TEST_ROUTE=initial

  for outcome in normal launcher-death inherited-ui-control; do
    new_case "full-cache-$outcome"
    export TEST_OS=ubuntu TEST_OS_TYPE=ubuntu TEST_OS_VERSION=24.04 HOLD_PUBLISHER=1 KEEP_PTY_MASTER=1
    [[ "$outcome" != inherited-ui-control ]] || export NONPRODUCTIVE_CONTROL=1
    TEST_TEMPLATE=ubuntu-24.04-standard_24.04-1_amd64.tar.xz
    start publisher other
    pid=$last_pid
    await_file "$CASE_ROOT/publisher-publisher-held"
    [[ "$outcome" != inherited-ui-control ]] || await_file "$CASE_ROOT/publisher-ui.json"
    holders=$(python3 "$SUBJECT/scan.py" "$CASE_ROOT/publisher-lock-identity")
    check "$(if [[ "$holders" != '[]' ]]; then printf held; else printf absent; fi)" held "$outcome productive publisher positively retains the real inode"
    if [[ "$outcome" != normal ]]; then
      owner=$(< "$CASE_ROOT/publisher-worker")
      owner_cmd=$(tr '\0' ' ' < "/proc/$owner/cmdline")
      [[ "$owner_cmd" == *"$0"* && "$owner_cmd" == *--worker* ]] || exit 98
      kill -KILL "$owner"
    fi
    printf finish > "$CASE_ROOT/publisher-finish-publisher"
    await_file "$CASE_ROOT/publisher-leader-status"
    rc=$(< "$CASE_ROOT/publisher-leader-status")
    expected=0
    [[ "$outcome" == normal ]] || expected=137
    check "$rc" "$expected" "$outcome full non-Alpine PTY launcher status"
    productive=$(< "$CASE_ROOT/publisher-producer")
    for ((i = 0; i < 200; i++)); do
      state=$(ps -o stat= -p "$productive" || true)
      [[ -n "$state" && "$state" != Z* ]] || break
      sleep .025
    done
    check "$(if [[ -z "$state" || "$state" == Z* ]]; then printf ended; else printf live; fi)" ended "$outcome actual productive process has ended before FD assertion"
    for ((i = 0; i < 200; i++)); do
      [[ ! -e "$CASE_ROOT/other/template/cache/$TEST_TEMPLATE" ]] || break
      sleep .025
    done
    check "$(python3 "$SUBJECT/pty_live.py" "$CASE_ROOT" publisher)" live "$outcome PTY master stays live through productive completion"
    if [[ "$outcome" == inherited-ui-control ]]; then
      holders=$(python3 "$SUBJECT/scan.py" "$CASE_ROOT/publisher-lock-identity")
      printf '%s\n' "$holders" > "$CASE_ROOT/fds-before-control-stop.json"
      check "$(if [[ "$holders" != '[]' ]]; then printf detected; else printf absent; fi)" detected 'deliberate nonproductive inherited FD is detected with terminal live'
      identity=$(< "$CASE_ROOT/publisher-lock-identity")
      path=${identity#*$'\n'}
      check "$(lock_state "$path")" held 'deliberate nonproductive control really retains kernel flock'
      before_tick=0
      [[ ! -e "$CASE_ROOT/publisher-ui-tick" ]] || before_tick=$(< "$CASE_ROOT/publisher-ui-tick")
      sleep .12
      after_tick=0
      [[ ! -e "$CASE_ROOT/publisher-ui-tick" ]] || after_tick=$(< "$CASE_ROOT/publisher-ui-tick")
      check "$(if [[ "$after_tick" -gt "$before_tick" ]]; then printf draining; else printf stopped; fi)" draining 'nonproductive control still writes through the live PTY drainer'
      stopped=$(python3 "$SUBJECT/stop_ui.py" "$CASE_ROOT" publisher)
      printf 'OWNED_CONTROL_STOP %s\n' "$stopped"
      check "$(if [[ "$stopped" == stopped:* ]]; then printf identified; else printf absent; fi)" identified 'only identified owned nonproductive control is stopped'
    fi
    holders=$(python3 "$SUBJECT/scan.py" "$CASE_ROOT/publisher-lock-identity")
    printf '%s\n' "$holders" > "$CASE_ROOT/fds-after-productive-end.json"
    check "$holders" '[]' "$outcome no live process retains template FD after productive work"
    identity=$(< "$CASE_ROOT/publisher-lock-identity")
    path=${identity#*$'\n'}
    check "$(lock_state "$path")" free "$outcome full cache-work leaves actual inode immediately available"
    check "$(tar -tf "$CASE_ROOT/other/template/cache/$TEST_TEMPLATE" > /dev/null && printf valid || printf invalid)" valid "$outcome actual publisher consumer receives valid archive"
    check "$(python3 "$SUBJECT/pty_live.py" "$CASE_ROOT" publisher)" live "$outcome FD and flock assertions precede terminal closure"
    printf close > "$CASE_ROOT/publisher-close-pty"
    driver_status=0
    wait "$pid" || driver_status=$?
    check "$driver_status" "$expected" "$outcome PTY driver preserves independently recorded launcher status"
    check "$(test -f "$CASE_ROOT/publisher-pty-closed" && printf closed || printf live)" closed "$outcome terminal closes only after assertion release"
    unset TEST_OS TEST_OS_TYPE TEST_OS_VERSION HOLD_PUBLISHER KEEP_PTY_MASTER NONPRODUCTIVE_CONTROL
  done

  new_case probe-crash-control
  export PROBE_CRASH=1
  start crash other
  pid=$last_pid
  rc=0
  wait "$pid" || rc=$?
  check "$rc" 0 'probe crash control leaves modeled producer status independent of observation failure'
  check "$(observations "$CASE_ROOT")" 1 'missing/crashed probe output is a failed observation contract'
  unset PROBE_CRASH
fi
for commands in "$work"/*/commands; do
  c=${commands%/commands}
  [[ "$c" != "$work/probe-crash-control" ]] || continue
  if [[ -s "$c/probes-required" ]]; then
    check "$(observations "$c")" 0 "$(basename "$c") complete positive probe transcript"
  fi
done
printf '%s checks; %s failure(s); %s; real flock/files/FDs; PVE commands modeled\n' "$checks" "$failures" "$TEST_MODE"
[[ "$failures" == 0 ]]
