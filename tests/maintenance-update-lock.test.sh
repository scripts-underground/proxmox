#!/usr/bin/env bash
# Real Bash/flock/files/FDs and original lifecycle owners. Package, network and
# PVE executables are recording boundaries; no CT, backup or app is operated.
set -euo pipefail
ROOT=${TEST_ROOT:-}
[[ -n "$ROOT" ]] || ROOT=$(realpath "$(dirname "${BASH_SOURCE[0]}")/..")

if [[ "${1:-}" == --worker ]]; then
  # shellcheck source=/dev/null
  source "$SUBJECT_CORE"
  if [[ "$ROLE" == detach-benign ]]; then
    _APP_MAINTENANCE_FD=1
    _app_maintenance_ui_detach
    printf 'stdout-alive\n'
    _APP_MAINTENANCE_FD=2
    _app_maintenance_ui_detach
    printf 'stderr-alive\n' >&2
    exit
  fi
  if [[ "$ROLE" == api ]]; then
    case "$ACTION" in
      shadow)
        stat() { return 97; }
        flock() { return 97; }
        mkdir() { return 97; }
        ;;
      allexport) set -a ;;
      varredir) shopt -s varredir_close ;;
    esac
    app_maintenance_acquire "$NSAPP"
    case "$ACTION" in
      borrow | allexport | varredir | shadow)
        (app_maintenance_acquire "$NSAPP")
        [[ "$(declare -p _APP_MAINTENANCE_FD _APP_MAINTENANCE_KEY)" != *'declare -x '* ]]
        command flock -n "$_APP_MAINTENANCE_FD"
        ;;
      different) app_maintenance_acquire different-key ;;
      replaced)
        exec {_APP_MAINTENANCE_FD}>&-
        exec {_APP_MAINTENANCE_FD}< /dev/null
        app_maintenance_acquire "$NSAPP"
        ;;
      path-replaced)
        command mv /var/lib/scripts-underground/maintenance-locks/lock-probe.lock /var/lib/scripts-underground/maintenance-locks/borrow-original.lock
        (
          umask 077
          : > /var/lib/scripts-underground/maintenance-locks/lock-probe.lock
        )
        app_maintenance_acquire "$NSAPP"
        ;;
      exec-child)
        env _APP_MAINTENANCE_FD="$_APP_MAINTENANCE_FD" _APP_MAINTENANCE_KEY="$NSAPP" \
          ROLE=api ACTION=plain /bin/bash "$0" --worker
        ;;
      hold)
        printf 'held\n' >&"$READY_FD"
        read -r -t 20 -u "$GATE_FD" token
        [[ "$token" == finish ]]
        ;;
    esac
    exit
  fi
  source "$ROOT/misc/error_handler.func"
  load_functions
  # Unrelated lock/lifecycle subjects explicitly have known zero requirements.
  LXC_REQUIRED_CPU=${LXC_REQUIRED_CPU-0} LXC_REQUIRED_RAM=${LXC_REQUIRED_RAM-0}
  nproc() {
    printf 'cpu %s\n' "$ACTOR" >> "$CASE_ROOT/probes"
    [[ "${RESOURCE_QUERY_FAIL:-}" != cpu ]] || return 46
    printf '%s\n' "${RESOURCE_CPU:-8}"
  }
  free() {
    printf 'ram %s\n' "$ACTOR" >> "$CASE_ROOT/probes"
    [[ "${RESOURCE_QUERY_FAIL:-}" != ram ]] || return 45
    printf 'total used free\nMem: %s 0 0\n' "${RESOURCE_RAM:-8192}"
  }
  [[ -z "${RESOURCE_INPUT_FILE:-}" ]] || exec < "$RESOURCE_INPUT_FILE"
  export BUILD_LOG="$CASE_ROOT/$ACTOR-build.log" DEBUG_LOGFILE="$CASE_ROOT/$ACTOR-error.log" VERBOSE=no
  if [[ "$ACTION" != ui && "$ACTION" != ui-leak && "$ACTION" != ui-held ]]; then
    msg_info() { :; }
    msg_ok() { :; }
    msg_warn() { :; }
  fi
  pip() { :; }
  pkg_clean() {
    printf 'cleanup %s\n' "$ACTOR" >> "$CASE_ROOT/events"
    if [[ "$ACTION" == cleanup-hold ]]; then
      printf 'cleanup-held\n' >&"$READY_FD"
      read -r -t 20 -u "$GATE_FD" token
      [[ "$token" == finish ]]
    fi
    [[ "$ACTION" != cleanup-fail ]] || return 51
  }
  prepare() {
    printf 'prepare %s pending=%s\n' "$ACTOR" "$(test -e "/var/lib/scripts-underground/update-pending/$NSAPP" && printf yes || printf no)" >> "$CASE_ROOT/events"
    [[ "$ACTION" != prepare-fail ]] || return 43
    [[ "$ACTION" != prepare-exit0 ]] || exit 0
    if [[ "$ACTION" == ui ]]; then msg_info 'Preparing maintenance'; fi
  }
  update_script() {
    printf 'hook %s force=%s\n' "$ACTOR" "${UPDATE_FORCE:-0}" >> "$CASE_ROOT/events"
    case "$ACTION" in
      hold-fail | hold-return | hold-exit)
        printf 'hook-held\n' >&"$READY_FD"
        read -r -t 20 -u "$GATE_FD" token
        [[ "$token" == finish ]]
        [[ "$ACTION" != hold-fail ]] || return 41
        [[ "$ACTION" != hold-exit ]] || exit 0
        ;;
      recovery)
        (
          trap 'printf "recovery-held\n" >& "$READY_FD"; read -r -t 20 -u "$GATE_FD" token' EXIT
          exit 41
        )
        ;;
      productive)
        TEST_HELD="$_APP_MAINTENANCE_FD" bash -c '
          printf "productive %s\n" "$BASHPID" >& "$READY_FD"
          read -r -t 20 -u "$GATE_FD" token
          exec {TEST_HELD}>&-
          printf "productive-closed\n" >& "$READY_FD"
        ' &
        wait "$!"
        ;;
      nested) run_update_script ;;
      hook-borrow | hook-other-key)
        (
          held_fd=$_APP_MAINTENANCE_FD
          held_identity=$(command stat -Lc '%d:%i' "/proc/self/fd/$held_fd")
          if [[ "$ACTION" == hook-other-key ]]; then
            app_maintenance_acquire different-hook-key
          else
            app_maintenance_acquire "$NSAPP"
            [[ "$_APP_MAINTENANCE_FD" == "$held_fd" && "$(command stat -Lc '%d:%i' "/proc/self/fd/$_APP_MAINTENANCE_FD")" == "$held_identity" ]]
            printf 'same-fd-borrow %s\n' "$held_fd" >> "$CASE_ROOT/events"
          fi
        )
        ;;
      inspect-child) env > "$CASE_ROOT/child-environment" ;;
      resource-repeat | resource-required | resource-actual | resource-query)
        case "$ACTION" in
          resource-required) LXC_REQUIRED_RAM=16384 ;;
          resource-actual) RESOURCE_CPU=1 ;;
          resource-query) RESOURCE_QUERY_FAIL=cpu ;;
        esac
        check_container_resources
        env > "$CASE_ROOT/resource-environment"
        # The sourced public runner owns this local; the fixture must not seed it.
        # shellcheck disable=SC2154
        declare -p _lxc_resource_admission > "$CASE_ROOT/resource-cache"
        printf 'resource admitted\n' >> "$CASE_ROOT/events"
        ;;
      ui-held)
        msg_info 'Live owner spinner'
        printf 'spinner %s\n' "$SPINNER_PID" >&"$READY_FD"
        read -r -t 20 -u "$GATE_FD" token
        [[ "$token" == finish ]]
        ;;
      ui | ui-leak)
        msg_info 'Maintaining app'
        if [[ "$ACTION" == ui-leak ]]; then
          bash -c 'printf "leak %s\n" "$BASHPID" >& "$READY_FD"; read -r -t 20 -u "$GATE_FD" token' &
          printf '%s\n' "$!" > "$CASE_ROOT/leak-pid"
        fi
        ;;
      no-op) exit 0 ;;
    esac
  }
  catch_errors
  [[ "${TRANSIENT_SET_A:-0}" != 1 ]] || set -a
  case "$ROLE" in
    update) run_update_script "${@:2}" ;;
    prepare) _run_update_script prepare "${@:2}" ;;
    badprepare) _run_update_script 'not-a-function' "${@:2}" ;;
    undeclared-prepare) _run_update_script undeclared_preparation "${@:2}" ;;
    lxc-silent | lxc-interactive)
      source "$CASE_ROOT/lxc-setup.func"
      curl() { :; }
      ensure_profile_loaded() { :; }
      export var_cpu=0 var_ram=0
      whiptail() { printf 1 >&3; }
      [[ "$ROLE" != lxc-silent ]] || export PHS_SILENT=1
      lxc_setup "${@:2}"
      ;;
    addon-exec)
      source "$ROOT/misc/addon_lxc.func"
      export APP_SLUG=lock-probe ADDON_ACTION=update
      addon_guard_installed
      ;;
    bundle) exec /bin/bash "$CASE_ROOT/update-bundle" ;;
  esac
  exit 97
fi

systemd-detect-virt --vm --quiet || exit 1
[[ "$EUID" == 0 ]] || exit 1
: "${TMPDIR:?provide private disk-backed TMPDIR}" "${ALPINE_BUSYBOX:?provide verified Alpine BusyBox}"
case "$(realpath -e "$TMPDIR")" in /tmp | /tmp/*) exit 1 ;; esac
case "$(findmnt -nr -T "$TMPDIR" -o FSTYPE)" in '' | tmpfs | ramfs) exit 1 ;; esac
if [[ "${1:-}" != --inside ]]; then
  mode=${1:---native}
  [[ "$mode" == --native || "$mode" == --baseline || "$mode" == --review-baseline || "$mode" == --ui-no-detach ]] || exit 64
  SUBJECT_CORE="$ROOT/misc/core.func"
  [[ "$mode" != --baseline ]] || SUBJECT_CORE="$(realpath -e "${2:?original framework directory}")/core.func"
  if [[ "$mode" == --review-baseline ]]; then
    SUBJECT_CORE="$(realpath -e "${2:?preserved pre-review subjects}")/core.func"
    export BATCH_SCRIPT="${SUBJECT_CORE%/*}/update-apps.sh"
  elif [[ "$mode" == --ui-no-detach ]]; then
    SUBJECT_CORE=$(realpath -e "${2:?owned core with only UI detach call removed}")
  fi
  export SUBJECT_CORE TEST_MODE="$mode" work
  work=$(mktemp -d "$TMPDIR/update-lock.XXXXXXXX")
  printf 'Evidence: %s; mode=%s\n' "$work" "$mode"
  unshare --mount --net --pid --fork --mount-proc --propagation private bash "$0" --inside
  exit
fi

# Hide all real framework metadata while preserving disk source and TMPDIR access.
mkdir -p "$work/metadata" "$work/home" "$work/cache" "$work/sbin"
managed=/var/lib/scripts-underground
for needed in "$ROOT" "$TMPDIR" "$SUBJECT_CORE" "$ALPINE_BUSYBOX"; do
  if [[ "$needed" == "$managed/"* ]]; then
    relative=${needed#"$managed/"} first=${relative%%/*}
    if [[ ! -d "$work/metadata/$first" ]]; then
      mkdir "$work/metadata/$first"
      mount --bind "$managed/$first" "$work/metadata/$first"
    fi
  fi
done
mount --rbind "$work/metadata" "$managed"
mount --bind "$work/home" /root
mount --bind "$work/cache" /var/cache
mount --bind "$work/sbin" /usr/local/sbin
export ROOT
python3 - "$0" << 'PY'
import hashlib,json,os,pathlib,pty,select,signal,subprocess,sys,time,threading
script=pathlib.Path(sys.argv[1]).resolve();root=pathlib.Path(os.environ['ROOT']);work=pathlib.Path(os.environ['work'])
baseline=os.environ['TEST_MODE']=='--baseline';core=os.environ['SUBJECT_CORE'];bb=os.environ['ALPINE_BUSYBOX']
pending=pathlib.Path('/var/lib/scripts-underground/update-pending');locks=pathlib.Path('/var/lib/scripts-underground/maintenance-locks')
results=[]
def check(ok,name):
 results.append({'name':name,'ok':bool(ok)});print(('PASS ' if ok else 'FAIL ')+name,flush=True)
def command(argv,**kw):return subprocess.run(argv,timeout=25,capture_output=True,**kw)
def case(name):
 p=work/name;p.mkdir(mode=0o700);(p/'events').touch();return p
def line(fd):
 assert select.select([fd],[],[],25)[0],'fixture barrier timeout'
 data=b''
 while not data.endswith(b'\n'):
  b=os.read(fd,1);assert b,'fixture early EOF';data+=b
 return data.decode().strip()
def start(c,actor='A',action='plain',role='update',key='lock-probe',extra=None,args=(),tty=None):
 r,w=os.pipe();g,h=os.pipe()
 env={'PATH':os.environ['PATH'],'TEST_ROOT':str(root),'TMPDIR':str(c),'HOME':'/root','TERM':'xterm','SUBJECT_CORE':core,'CASE_ROOT':str(c),'ACTOR':actor,'ACTION':action,'ROLE':role,'NSAPP':key,'APP':'LockProbe','READY_FD':str(w),'GATE_FD':str(g)}
 if extra:env.update(extra)
 out=open(c/(actor+'.log'),'ab',buffering=0)
 p=subprocess.Popen(['/bin/bash',str(script),'--worker',*args],env=env,stdout=out if tty is None else tty,stderr=out if tty is None else tty,pass_fds=(w,g),start_new_session=True)
 os.close(w);os.close(g);out.close();return p,r,h
def finish(pipes,release=False):
 p,r,h=pipes
 if release:os.write(h,b'finish\n')
 status=p.wait(timeout=25);os.close(r);os.close(h);return status
def run(c,actor='B',**kw):return finish(start(c,actor,**kw))
def snapshot(path):
 if not path.exists():return None
 s=path.stat();return [s.st_dev,s.st_ino,s.st_mode,s.st_size,s.st_mtime_ns,path.read_bytes().hex()]
def events(c):return (c/'events').read_text()
for action in ('hold-fail',) if baseline else ('hold-fail','hold-return','hold-exit','recovery','cleanup-hold','no-op'):
 c=case(action)
 if action=='no-op':
  check(run(c,action=action)==0 and not (pending/'lock-probe').exists(),'no-op successful terminal cleanup');continue
 a=start(c,action=action);barrier=line(a[1]);before=snapshot(pending/'lock-probe');inode=snapshot(locks/'lock-probe.lock')
 status=run(c)
 check(status==75,action+' second owner refuses75')
 check(snapshot(pending/'lock-probe')==before and snapshot(locks/'lock-probe.lock')==inode,action+' contender leaves owner pending/inode intact')
 check('hook B' not in events(c) and 'cleanup B' not in events(c),action+' refusal runs no hook/cleanup')
 probes=(c/'probes').read_text() if (c/'probes').exists() else ''
 check('cpu B' not in probes and 'ram B' not in probes,action+' busy75 precedes every resource measurement')
 status_a=finish(a,True);expected=41 if action in ('hold-fail','recovery') else 0
 check(status_a==expected,action+' original owner terminal status')
 if expected:
  check((pending/'lock-probe').exists(),action+' failed owner retains pending')
  check(run(c,'C')==0 and 'hook C force=1' in events(c),action+' later consumer forced unfinished recovery')
 else:check(not (pending/'lock-probe').exists(),action+' success retires pending after cleanup')
if baseline:
 (work/'results.json').write_text(json.dumps(results,indent=2));print('BASELINE_INTENDED_FAILURES',sum(not r['ok'] for r in results));sys.exit(1 if any(not r['ok'] for r in results) else 0)

# Preparation is owned but precedes pending and FORCE admission.
for action,expected in [('resource-repeat',0),('resource-required',1),('resource-actual',1),('resource-query',46)]:
 c=case(action);answer=c/'answer';answer.write_text('yes\nno\n' if action=='resource-repeat' else 'no\n')
 extra={'LXC_REQUIRED_CPU':'2','LXC_REQUIRED_RAM':'1024','RESOURCE_CPU':'1' if action=='resource-repeat' else '8','RESOURCE_INPUT_FILE':str(answer),'TRANSIENT_SET_A':'1','_lxc_resource_admission':'2 1024 1 8192'}
 status=run(c,action=action,extra=extra)
 out=(c/'B.log').read_text()
 check(status==expected,action+' exact resource/cache result')
 check(out.count('Continue update')==(1 if action!='resource-query' else 0),action+' prompts once only when inputs require consent')
 if action=='resource-repeat':
  child=(c/'resource-environment').read_text();cache=(c/'resource-cache').read_text()
  check('_lxc_resource_admission=' not in child and not cache.startswith('declare -ax'), 'set-a resource cache is local nonexported data')
  answer.write_text('no\n')
  check(run(c,'Next',action=action,extra=extra)==1 and 'hook Next' not in events(c),'fresh independent invocation cannot inherit prior matching consent')
 else:check('resource admitted' not in events(c),action+' changed tuple or failed probe cannot reuse consent')
for prior in (False,True):
 c=case('resource-prior-'+str(prior));pending.mkdir(exist_ok=True);flag=pending/'lock-probe';flag.unlink(missing_ok=True)
 if prior:flag.write_text('original pending bytes')
 before=snapshot(flag);answer=c/'answer';answer.write_text('no\n')
 status=run(c,extra={'LXC_REQUIRED_CPU':'99','LXC_REQUIRED_RAM':'99999','RESOURCE_INPUT_FILE':str(answer),'_lxc_resource_admission':'99 99999 8 8192'},args=('--clean',))
 check(status==1 and snapshot(flag)==before,'central resource refusal preserves prior pending '+str(prior))
 check('hook ' not in events(c) and 'cleanup ' not in events(c),'central resource refusal has no hook/new pending/cleanup '+str(prior))
flag.unlink(missing_ok=True)

c=case('preparation');pending.mkdir(exist_ok=True);(pending/'lock-probe').write_text('retained')
before=snapshot(pending/'lock-probe')
check(run(c,role='prepare',action='prepare-fail')==43 and snapshot(pending/'lock-probe')==before and 'hook ' not in events(c) and 'cleanup ' not in events(c),'prepare failure preserves exact prior pending/status without app cleanup')
check(run(c,'C',role='prepare',args=('--bogus',))==65 and events(c).count('prepare ')==1,'bad public options precede preparation')
check(run(c,'D',role='prepare')==0 and 'prepare D pending=yes' in events(c) and 'hook D force=1' in events(c),'preparation then forced pending admission')
check(run(c,'E',action='cleanup-fail')==0 and not (pending/'lock-probe').exists(),'noncritical cleanup failure preserves success/pending retirement')
before=events(c)
check(run(c,'Bad',role='badprepare')==70 and events(c)==before and not (pending/'lock-probe').exists(),'invalid literal preparation refuses before ownership effects')
check(run(c,'Undeclared',role='undeclared-prepare')==70 and events(c)==before,'undeclared literal preparation refuses before effects')
check(run(c,'Borrow',action='hook-borrow')==0 and 'same-fd-borrow ' in events(c),'real fresh wrapper to hook subshell borrows identical FD/inode')
check(run(c,'OtherKey',action='hook-other-key')==70 and (pending/'lock-probe').exists(),'hook different-key borrow refuses70 and retains pending')
run(c,'AfterBorrow')
check(run(c,'F',action='nested')==70 and (pending/'lock-probe').exists(),'wrapper refuses in-lineage re-entry70')
run(c,'G')

# Transient obligations belong to the fresh owner, never a foreign exec context.
for allexport in (False,True):
 for action in ('prepare-exit0','prepare-fail','inspect-child'):
  c=case('transient-'+str(allexport)+'-'+action);foreign=c/'other-app-pending';foreign.write_text('foreign unfinished update')
  extra={'_UPDATE_PENDING_FLAG':str(foreign),'_UPDATE_CLEANUP':'1','TRANSIENT_SET_A':str(int(allexport))}
  status=run(c,role='prepare',action=action,extra=extra)
  check(status==(43 if action=='prepare-fail' else 0),'transient '+str(allexport)+' '+action+' original status')
  check(foreign.exists() and foreign.read_text()=='foreign unfinished update','transient '+str(allexport)+' '+action+' preserves foreign app flag')
  if action.startswith('prepare-'):check('cleanup B' not in events(c),'transient '+str(allexport)+' '+action+' arms no foreign cleanup')
  else:
   child=(c/'child-environment').read_text()
   check('_UPDATE_PENDING_FLAG=' not in child and '_UPDATE_CLEANUP=' not in child,'transient '+str(allexport)+' exec child receives no cleanup obligations')
c=case('foreign-refusal');foreign=c/'other-pending';foreign.write_text('keep')
a=start(c,action='hold-return');line(a[1])
check(run(c,role='prepare',action='prepare-exit0',extra={'_UPDATE_PENDING_FLAG':str(foreign),'_UPDATE_CLEANUP':'1'})==75 and foreign.read_text()=='keep','busy refusal preserves foreign state before preparation')
check(finish(a,True)==0,'foreign-refusal outer owner completes normally')

# Real lxc_setup dispatch, extracted without its source-time host bootstrap.
c=case('dispatch');text=(root/'misc/build.func').read_text();parts=[]
for name in ('lxc_setup','_lxc_setup'):
 if name+'() {\n' in text:
  start_at=text.index(name+'() {\n');end=text.index('\n}\n',start_at)+3;parts.append(text[start_at:end])
(c/'lxc-setup.func').write_text('\n'.join(parts))
context_bin=c/'lxc-bin';context_bin.mkdir()
for name in ('flock','stat','mkdir','date','tput','stty','bash','grep','tr','awk','hostname','ip'):
 target=command(['/bin/bash','-c','type -P "$1"','_',name]).stdout.decode().strip()
 if target:os.symlink(target,context_bin/name)
a=start(c,action='hold-return');line(a[1])
for role in ('lxc-silent','lxc-interactive','prepare'):
 extra={'PATH':str(context_bin)} if role.startswith('lxc-') else None
 check(run(c,role=role,extra=extra)==75 and 'prepare B' not in events(c),role+' enters fresh shared owner')
check(run(c,'Other',key='different-app')==0,'different app key progresses while original owner held')
check(finish(a,True)==0,'dispatch owner completed')

# Native public helper: borrowing, environment/exec isolation, shadowing and options.
c=case('api')
for action in ('borrow','allexport','varredir','shadow'):
 check(run(c,action,role='api',action=action)==0,action+' real held FD survives/borrows with no exported state')
check(run(c,'different',role='api',action='different')==70,'different-key lineage refuses70')
check(run(c,'replaced',role='api',action='replaced')==69,'reused descriptor identity mismatch refuses69')
check(run(c,'path-replaced',role='api',action='path-replaced')==69,'replaced lock path cannot borrow an unrelated inode')
check(run(c,'exec',role='api',action='exec-child')==75,'exec child discards exported state and contends independently')
check(run(c,'import',role='api',extra={'_APP_MAINTENANCE_FD':'999','_APP_MAINTENANCE_KEY':'other'})==0,'imported owner variables never grant lineage')
check(run(c,'benign',role='detach-benign')==0 and 'stdout-alive' in (c/'benign.log').read_text() and 'stderr-alive' in (c/'benign.log').read_text(),'UI detach ignores malformed imported stdout/stderr FDs')
for key in ('','../escape','Upper','_bad','a'*65,'a/b','é'):
 check(run(c,'bad-key',role='api',key=key)==65,'invalid canonical key refused '+repr(key))

# Each unsafe object is test-owned. Production must neither repair nor replace it.
for fault in ('symlink','dangling','directory','fifo','hardlink','content','mode','owner','leaf-mode','parent-mode'):
 c=case('unsafe-'+fault);target=locks/('unsafe-'+fault+'.lock');key='unsafe-'+fault
 if fault in ('symlink','dangling'):target.symlink_to(c/('missing' if fault=='dangling' else 'target'));(c/'target').touch()
 elif fault=='directory':target.mkdir()
 elif fault=='fifo':os.mkfifo(target)
 else:target.touch(mode=0o600)
 if fault=='hardlink':os.link(target,locks/'unsafe-hardlink-second.lock')
 if fault=='content':target.write_text('retain')
 if fault=='mode':target.chmod(0o644)
 if fault=='owner':os.chown(target,12345,12345)
 changed=locks if fault=='leaf-mode' else locks.parent if fault=='parent-mode' else None
 if changed:oldmode=changed.stat().st_mode&0o777;changed.chmod(0o755 if fault=='leaf-mode' else 0o777)
 before=target.lstat()
 check(run(c,role='api',key=key)==69,fault+' unsafe infrastructure refuses69')
 after=target.lstat();check((before.st_ino,before.st_mode,before.st_uid,before.st_size)==(after.st_ino,after.st_mode,after.st_uid,after.st_size),fault+' existing object preserved')
 if changed:changed.chmod(oldmode)
c=case('missing-tool');binpath=c/'bin';binpath.mkdir()
for name in ('stat','mkdir'):os.symlink('/usr/bin/'+name,binpath/name)
check(run(c,role='api',key='missing-tool',extra={'PATH':str(binpath)})==69 and not (locks/'missing-tool.lock').exists(),'missing executable flock fails before lock creation')
for target in ('directory','lock'):
 c=case('stat-'+target);bp=c/'bin';bp.mkdir()
 suffix='maintenance-locks' if target=='directory' else 'stat-lock.lock'
 stub=bp/'stat';stub.write_text('#!/bin/bash\n[[ "${!#}" != */'+suffix+' ]] || exit 47\nexec /usr/bin/stat "$@"\n');stub.chmod(0o700)
 status=run(c,role='api',key='stat-lock',extra={'PATH':str(bp)+':'+os.environ['PATH']})
 check(status==69 and 'cannot inspect '+target in (c/'B.log').read_text() and '/var/lib/scripts-underground/maintenance-locks' in (c/'B.log').read_text(),'failed '+target+' stat reports actionable path (producer failure modeled)')

# BusyBox executes actual helper commands, never function-substituted flock/stat.
c=case('busybox');binpath=c/'bin';binpath.mkdir()
for name in ('flock','stat','mkdir'):os.symlink(bb,binpath/name)
bbpath=str(binpath)+':'+os.environ['PATH']
for first,second in ((bbpath,os.environ['PATH']),(os.environ['PATH'],bbpath)):
 a=start(c,action='hold',role='api',extra={'PATH':first});line(a[1])
 check(run(c,role='api',extra={'PATH':second})==75,'native BusyBox/util-linux owner interoperation')
 check(finish(a,True)==0,'native provider owner completes')
check(run(c,role='api',action='borrow',extra={'PATH':bbpath})==0,'BusyBox path/FD stat and OFD re-flock borrow')

# Original cold writers, with only source-time OS/package bootstrap modeled.
c=case('cold-writers');stage=c/'stage';stage.mkdir()
for name,src in [('core',pathlib.Path(core)),('error_handler',root/'misc/error_handler.func')]:
 (stage/(name+'.func')).write_bytes(src.read_bytes())
for name,body in [('install','setup_lxc() { :; }; pkg_install() { :; }\n'),('tools','setup_uv() { :; }; fetch_and_deploy_gh_release() { :; }\n'),('github','clone_and_deploy_gh_commit() { :; }\n')]:
 (stage/(name+'.func')).write_text(body)
(c/'bundle-models.sh').write_text('''msg_info() { :; }; msg_ok() { :; }; msg_warn() { :; }
pkg_clean() { printf 'cleanup %s\\n' "$ACTOR" >> "$CASE_ROOT/events"; }
addon_baseline() { printf 'prepare %s\\n' "$ACTOR" >> "$CASE_ROOT/events"; }
''')
(stage/'addon.func').write_text((root/'misc/addon_lxc.func').read_text()+'\nsource "$CASE_ROOT/bundle-models.sh"\n')
build='''set -euo pipefail
source "$1/misc/bundle.func"
source "$1/misc/addon_lxc.func"
APP=LockProbe NSAPP=lock-probe APP_SLUG=lock-probe REPO_BASE=offline
var_lxc_tmpdir=$2
update_script() {
  printf 'hook %s force=%s\\n' "$ACTOR" "${UPDATE_FORCE:-0}" >> "$CASE_ROOT/events"
  if [[ "$ACTION" == hold ]]; then printf 'bundle-held\\n' >& "$READY_FD"; read -r -t 20 -u "$GATE_FD" token; fi
}
_write_bundle update update_script "$2/stage" --requirements 0 0 -- 'source "$CASE_ROOT/bundle-models.sh"' 'run_update_script "$@"' > "$2/update-bundle"
_addon_bundle_contents update update_script "$2/stage" > /usr/local/sbin/update_lock-probe
chmod 0700 /usr/local/sbin/update_lock-probe
'''
built=command(['/bin/bash','-c',build,'_',str(root),str(c)]);assert built.returncode==0,built.stderr
markers=pathlib.Path('/var/lib/scripts-underground/addons');markers.mkdir();(markers/'lock-probe').touch()
a=start(c,action='hold',role='bundle');check(line(a[1])=='bundle-held','real cold LXC writer enters hook under owner')
for role in ('bundle','addon-exec'):
 before=events(c);check(run(c,role=role)==75 and events(c)==before,role+' cold contender refuses before preparation/hook/cleanup')
check(finish(a,True)==0,'cold writer owner completes')
check(run(c,role='addon-exec')==0 and 'prepare B' in events(c),'installed addon exec reaches owned literal preparation runner')

# Whole batch script; every PVE/network/backup executable is a recording boundary.
batch_bin=work/'batch-bin';batch_bin.mkdir();storage=work/'storage.cfg';storage.write_text('dir: local\n    content backup\n')
subprocess.run(['mount','--bind',str(storage),'/etc/pve/storage.cfg'],check=True,timeout=10)
model='''#!/bin/bash
set -u
tool=${0##*/}
printf '%s %s\\n' "$tool" "$*" >> "$CASE_ROOT/commands"
case "$tool:${1:-}" in
 curl:*)
  case "${!#}" in
   */core.func) cat "$SUBJECT_CORE" ;;
   */bootstrap/pve) printf '%s\\n' 'load_functions; color; msg_info() { :; }; msg_ok() { printf "OK %s\\n" "$*"; }; msg_error() { printf "ERROR %s\\n" "$*"; }' ;;
    *) [[ "${METADATA_FAIL:-0}" != 1 ]] || exit 47; if [[ -f "$CASE_ROOT/resource-source" ]]; then cat "$CASE_ROOT/resource-source"; else printf 'var_cpu="4"\\nvar_ram="4096"\\n'; fi ;;
  esac ;;
 pct:list) printf 'VMID Status Lock Name\\n500 stopped fixture\\n' ;;
 pct:status) printf 'status: %s\\n' "$(cat "$CASE_ROOT/power-$2" 2>/dev/null || printf stopped)" ;;
 pct:config)
  fixture_cpu=2 fixture_ram=1024
  [[ ! -f "$CASE_ROOT/resource-config" ]] || read -r fixture_cpu fixture_ram < "$CASE_ROOT/resource-config"
  printf 'ostype: debian\\ncores: %s\\nmemory: %s\\ntags: community-script\\nrootfs: local:fixture\\n' "$fixture_cpu" "$fixture_ram" ;;
 pct:pull)
  if [[ -n "${BATCH_BUNDLE:-}" ]]; then cp "$BATCH_BUNDLE" "${!#}"; else printf '%s\\n' 'bash -c "$(curl -fsSL https://raw.githubusercontent.com/scripts-underground/proxmox/main/ct/probe.sh)"' > "${!#}"; fi ;;
 pct:exec)
   if [[ "$*" == 'exec '*' -- nproc' ]]; then
    fixture_cpu=8 fixture_ram=8192
    [[ ! -f "$CASE_ROOT/resource-config" ]] || read -r fixture_cpu fixture_ram < "$CASE_ROOT/resource-config"
    printf '%s\\n' "$fixture_cpu"; exit
   elif [[ "$*" == 'exec '*' -- free -m' ]]; then
    fixture_cpu=8 fixture_ram=8192
    [[ ! -f "$CASE_ROOT/resource-config" ]] || read -r fixture_cpu fixture_ram < "$CASE_ROOT/resource-config"
    printf 'total used free\\nMem: %s 0 0\\n' "$fixture_ram"; exit
   fi
  if [[ "$*" == *'-c '* ]]; then
   if [[ "$BATCH_RESULT" == busy ]]; then
    ROLE=update ACTION=plain ACTOR=Batch /bin/bash "$TEST_SCRIPT" --worker
    exit $?
   fi
   if [[ "$BATCH_RESULT" == mixed ]]; then [[ "$2" == 501 ]] && exit 0; exit 75; fi
   exit "$BATCH_RESULT"
  fi
  [[ "${!#}" != hostname ]] || printf 'fixture\\n'
  ;;
 vzdump:*)
   cid=$1; printf 'backup retained\\n' > "$CASE_ROOT/backup"
   while (($#)); do
    if [[ "$1" == --notes-template || "$1" == -notes-template ]]; then printf '%s' "$2" > "$CASE_ROOT/backup-note-$cid"; break; fi
    shift
   done
   ;;
 pvesh:*)
   python3 - "$CASE_ROOT" "$@" <<'INVENTORY'
import json,pathlib,sys
c=pathlib.Path(sys.argv[1]);a=sys.argv[2:];cid=a[a.index('--vmid')+1]
rows=[dict(volid='local:backup/vzdump-lxc-'+cid+'-2026_01_01-00_00_00.tar.zst',vmid=int(cid),format='tar.zst',content='backup',subtype='lxc',notes='old')]
p=c/('backup-note-'+cid)
if p.exists():rows.append(dict(rows[0],volid='local:backup/vzdump-lxc-'+cid+'-2026_11_07-18_00_00.tar.zst',notes=p.read_text()))
print(json.dumps(rows))
INVENTORY
   ;;
 pct:set)
  [[ "${FAIL_SET:-0}" != 1 ]] || exit 47
  if [[ -f "$CASE_ROOT/resource-config" ]]; then printf '%s %s\\n' "$4" "$6" > "$CASE_ROOT/resource-config"; printf '%s %s\\n' "$4" "$6" >> "$CASE_ROOT/resource-sets"; fi ;;
 pct:start) [[ "${FAIL_START:-0}" != 1 ]] || exit 48; printf running > "$CASE_ROOT/power-$2" ;;
 pct:stop | pct:shutdown) printf stopped > "$CASE_ROOT/power-$2" ;;
 pct:reboot)
   [[ "$(cat "$CASE_ROOT/power-$2" 2>/dev/null || printf stopped)" == running ]] || exit 60
   printf rebooted > "$CASE_ROOT/rebooted-$2"
   ;;
 pct:* | sleep:* | clear:*) : ;;
 *) exit 97 ;;
esac
'''
for name in ('pct','vzdump','pvesh','curl','sleep','clear'):(batch_bin/name).write_text(model);(batch_bin/name).chmod(0o700)
for result in ('busy','75','75-no-backup','mixed','41','0','running'):
 c=case('batch-'+result);(c/'commands').touch();a=None
 if result=='running':(c/'power-500').write_text('running')
 if result=='busy':a=start(c,action='hold-return');line(a[1])
 env=dict(os.environ,PATH=str(batch_bin)+':'+os.environ['PATH'],CASE_ROOT=str(c),TEST_SCRIPT=str(script),TEST_ROOT=str(root),SUBJECT_CORE=core,NSAPP='lock-probe',APP='LockProbe',READY_FD='0',GATE_FD='0',BATCH_RESULT='75' if result.startswith('75') else '0' if result=='running' else result,TMPDIR=str(c),FAIL_SET='1' if result=='75-set-failed' else '0',FAIL_START='1' if result=='75-start-failed' else '0',var_backup='no' if result=='75-no-backup' else 'yes',var_backup_storage='local',var_container='500,501' if result=='mixed' else '500',var_unattended='yes',var_skip_confirm='yes',var_auto_reboot='yes')
 p=command(['/bin/bash',os.environ.get('BATCH_SCRIPT',str(root/'scripts/pve/update-apps.sh'))],env=env,cwd=c)
 skipped=result=='busy' or result.startswith('75') or result=='mixed'
 (c/'batch.log').write_bytes(p.stdout+p.stderr);trace=(c/'commands').read_text();check(p.returncode==(75 if skipped else 1 if result=='41' else 0),'whole batch reports exact outcome '+result)
 if result=='busy' or result.startswith('75'):
  check(all(x not in trace for x in ('pct shutdown','pct stop','pct restore','pct reboot','reboot-required','pct set ')),'batch '+result+' leaves running resources/data alone after75')
  check('not updated' in p.stdout.decode() and 'temporarily unavailable/busy' in p.stderr.decode() and (c/'backup').exists()==(result!='75-no-backup'),'batch '+result+' reports honest skip and preserves actual backup presence')
  check('partially complete' in p.stdout.decode() and 'this batch started it; it is left running' in p.stderr.decode() and 'requested build resources' not in p.stderr.decode(),'batch '+result+' reports actual successful start without sizing instructions')
 elif result=='mixed':check('pct reboot' not in trace and 'pct shutdown 500' not in trace and (c/'power-501').read_text()=='stopped','batch keeps owned-start CT stopped before final partial75')
 elif result=='41':check('pct stop' in trace and 'pct restore' in trace,'ordinary non75 batch failure retains backup restore path')
 elif result=='running':check((c/'rebooted-500').read_text()=='rebooted' and 'pct shutdown' not in trace,'running requested reboot reaches stateful consumer')
 else:check('pct shutdown' in trace and 'pct set ' not in trace and 'pct reboot' not in trace and (c/'power-500').read_text()=='stopped','successful owned start stays stopped without resizing or invalid reboot')
 if a:check(finish(a,True)==0,'batch never disturbed real concurrent owner')

# Real producer identity and real metadata source, with configuration writes
# recorded by pct. Observe the retained pair, not merely requested argv.
batch_bundle=work/'batch-current-update'
app_source=(root/'scripts/lxc/changedetection.sh').read_text()
app_declarations=app_source[:app_source.index('function install_script() {')]
producer='''set -euo pipefail
source "$1/misc/bundle.func"
'''+app_declarations+'''
NSAPP=${APP,,}; NSAPP=${NSAPP// /}; var_lxc_tmpdir=$2
update_script() { :; }
_write_bundle update update_script "$3/stage" --script-id changedetection -- 'run_update_script "$@"' > "$4"
'''
p=command(['/bin/bash','-c',producer,'_',str(root),str(work),str(work/'cold-writers'),str(batch_bundle)])
assert p.returncode==0,p.stderr
for label,cpu,ram,metadata_fail in [
 ('cpu-short',1,8192,False),('ram-short',8,1024,False),
 ('enough',8,8192,False),('equal',4,4096,False),
 ('both-short',1,1024,False),('metadata-failed',3,1536,True)]:
 for result in ('75','0','41'):
  c=case('resources-'+label+'-'+result);(c/'commands').touch();(c/'resource-config').write_text(f'{cpu} {ram}\n');(c/'resource-source').write_text(app_source)
  env=dict(os.environ,PATH=str(batch_bin)+':'+os.environ['PATH'],CASE_ROOT=str(c),TEST_SCRIPT=str(script),TEST_ROOT=str(root),SUBJECT_CORE=core,NSAPP='lock-probe',APP='LockProbe',READY_FD='0',GATE_FD='0',BATCH_RESULT=result,BATCH_BUNDLE=str(batch_bundle),METADATA_FAIL=str(int(metadata_fail)),TMPDIR=str(c),REPO_BASE='https://fixture.invalid/batch',var_backup='yes',var_backup_storage='local',var_container='500',var_unattended='yes',var_skip_confirm='yes',var_auto_reboot='yes')
  p=command(['/bin/bash',str(root/'scripts/pve/update-apps.sh')],env=env,cwd=c,input=b'yes\n')
  (c/'batch.log').write_bytes(p.stdout+p.stderr);trace=(c/'commands').read_text();pair=(c/'resource-config').read_text().strip()
  sets=(c/'resource-sets').read_text().splitlines() if (c/'resource-sets').exists() else []
  check(p.returncode==(75 if result=='75' else 1 if result=='41' else 0),label+'/'+result+' whole batch status')
  check('curl -fsSL https://fixture.invalid/batch/scripts/lxc/changedetection.sh\n' in trace,label+'/'+result+' actual produced identity reaches metadata URL')
  check(sets==[] and 'pct set ' not in trace,label+'/'+result+' zero resource setters')
  check(pair==f'{cpu} {ram}',label+'/'+result+' exact unchanged configuration readback')
  if result=='75':check(all(x not in trace for x in ('pct shutdown','pct stop','pct restore','pct reboot','reboot-required')),label+' raw75 performs no automatic rollback/shutdown/restore/reboot')
  elif result=='41':check('pct stop' in trace and 'pct restore' in trace,label+' ordinary failure retains backup restoration')
  else:check('pct shutdown' in trace and 'pct reboot' not in trace and (c/'power-500').read_text()=='stopped',label+' ordinary success retains stopped lifecycle')
  (c/'resource-outcome.json').write_text(json.dumps(dict(initial=[cpu,ram],result=result,final=pair,sets=sets,metadata_failure=metadata_fail),indent=2))
c=case('resources-unknown');(c/'commands').touch();(c/'resource-config').write_text('1 unknown\n');(c/'resource-source').write_text(app_source)
env=dict(env,CASE_ROOT=str(c),BATCH_RESULT='75',METADATA_FAIL='0',TMPDIR=str(c))
p=command(['/bin/bash',str(root/'scripts/pve/update-apps.sh')],env=env,cwd=c);trace=(c/'commands').read_text();(c/'batch.log').write_bytes(p.stdout+p.stderr)
check(p.returncode==65,'unknown actual baseline refuses preparation65')
check('pct set' not in trace and 'bash -c' not in trace,'unknown baseline issues no resource set or updater')
check((c/'resource-config').read_text()=='1 unknown\n','unknown baseline configuration retained')

# Launcher death does not expose a productive child; pending survives until retry.
c=case('death');a=start(c,action='productive');child=int(line(a[1]).split()[1]);os.kill(a[0].pid,signal.SIGKILL);check(a[0].wait(timeout=10)==-9,'positively owned launcher SIGKILL')
check(run(c)==75 and (pending/'lock-probe').exists(),'surviving productive child protects unfinished update')
os.write(a[2],b'finish\n');check(line(a[1])=='productive-closed','productive child closes held FD before release observation');os.close(a[1]);os.close(a[2])
check(run(c,'C')==0 and 'hook C force=1' in events(c),'last productive closure permits forced retry')

# PTY stays open beyond launcher completion. A leak control proves detection.
def holders(path):
 ident=(path.stat().st_dev,path.stat().st_ino);found=[]
 for proc in pathlib.Path('/proc').iterdir():
  if not proc.name.isdigit():continue
  try:
   for fd in (proc/'fd').iterdir():
    try:
     st=fd.stat()
     if (st.st_dev,st.st_ino)==ident:found.append([int(proc.name),fd.name])
    except FileNotFoundError:pass
  except (FileNotFoundError,PermissionError,ProcessLookupError):pass
 return found

# Observe the actual UI subject while it is positively alive, not after a later
# stop_spinner or terminal close. --ui-no-detach changes ONLY that spawn-site call.
c=case('live-spinner');master,slave=pty.openpty();stop_drain=threading.Event();progress=threading.Condition();received=[0]
def drain():
 with (c/'terminal.log').open('wb') as capture:
  while not stop_drain.is_set():
   if not select.select([master],[],[],.05)[0]:continue
   try:data=os.read(master,4096)
   except OSError:continue
   if not data:continue
   if capture.tell()<1048576:capture.write(data)
   with progress:received[0]+=len(data);progress.notify_all()
drainer=threading.Thread(target=drain,daemon=True);drainer.start()
def next_frame(before):
 end=time.monotonic()+5
 with progress:
  while received[0]<=before:
   remaining=end-time.monotonic();assert remaining>0,'real spinner stopped producing while PTY master remained open'
   progress.wait(remaining)
def identity(pid):
 p=pathlib.Path('/proc')/str(pid);tail=(p/'stat').read_text().rsplit(')',1)[1].split();args=(p/'cmdline').read_bytes().replace(b'\0',b' ').decode()
 assert tail[0]!='Z' and str(script) in args and '--worker' in args,'not a live owned spinner'
 return [pid,tail[19],args]
a=start(c,action='ui-held',tty=slave);notice=line(a[1]);assert notice.startswith('spinner '),notice
spinner=int(notice.split()[1]);who=identity(spinner);launcher=identity(a[0].pid);next_frame(0)
held_during=holders(locks/'lock-probe.lock')
check(any(pid==a[0].pid for pid,fd in held_during),'alive spinner observation includes the actual maintenance owner')
check(not any(pid==spinner for pid,fd in held_during),'alive actual spinner lacks maintenance inode while owner is held')
before=received[0];os.kill(a[0].pid,signal.SIGKILL);check(a[0].wait(timeout=10)==-9,'only positively identified UI launcher killed')
next_frame(before);check(identity(spinner)==who,'actual spinner survives launcher death and renders with master/drainer alive')
held_after=holders(locks/'lock-probe.lock')
check(not held_after,'last productive FD closed while actual UI still alive (terminal not torn down)')
retry=run(c,'Retry');check(retry==0 and 'hook Retry force=1' in events(c),'fresh consumer acquires/forces pending while original spinner still alive')
check(identity(spinner)==who,'retry did not stop the observed original spinner')
(c/'live-spinner-observation.json').write_text(json.dumps({'launcher':launcher,'spinner':who,'held_during':held_during,'held_after_launcher_death':held_after,'retry_status':retry,'frames_bytes':received[0],'master_open_during_all_assertions':True,'drainer_alive':drainer.is_alive()},indent=2))
assert identity(spinner)==who;os.kill(spinner,signal.SIGTERM)
end=time.monotonic()+5
while holders(locks/'lock-probe.lock') and time.monotonic()<end:select.select([],[],[],.01)
check(not holders(locks/'lock-probe.lock'),'owned UI cleanup releases mutation-control inherited FD')
os.close(a[1]);os.close(a[2]);os.close(slave);stop_drain.set();drainer.join(timeout=2);os.close(master)
if os.environ['TEST_MODE']=='--ui-no-detach':
 failed=sum(not row['ok'] for row in results);(work/'results.json').write_text(json.dumps(results,indent=2))
 print(f'{len(results)} assertions; {failed} UI-call-removal failure(s); all real spinner assertions completed before terminal teardown',flush=True)
 sys.exit(1 if failed else 0)

for control in (False,True):
 c=case('pty-leak' if control else 'pty');master,slave=pty.openpty();a=start(c,action='ui-leak' if control else 'ui',role='prepare',tty=slave)
 if control:leak=int(line(a[1]).split()[1])
 check(a[0].wait(timeout=20)==0,'PTY launcher completes while master remains open')
 os.close(slave);held=holders(locks/'lock-probe.lock');check(bool(held)==control,'PTY FD scan '+('detects deliberate leak' if control else 'finds no inherited UI holder'))
 if control:
  check(any(pid==leak for pid,fd in held) and run(c)==75,'deliberate UI child positively holds native lock')
  os.write(a[2],b'finish\n')
  # Closure is synchronized by waiting for child disappearance or zombie (no FDs).
  end=time.monotonic()+5
  while holders(locks/'lock-probe.lock') and time.monotonic()<end:select.select([],[],[],.01)
 check(not holders(locks/'lock-probe.lock') and run(c,'After')==0,'lock free before PTY master teardown')
 (c/'pty-fd-observations.json').write_text(json.dumps({'before_close':held,'control':control,'master_still_open':True}))
 os.close(master);os.close(a[1]);os.close(a[2])

# Future APP spelling cannot quietly fall outside the real slug contract.
import re
slugs=[]
for kind in ('lxc','addon'):
 for path in (root/'scripts'/kind).glob('*.sh'):
  match=re.search(r'^APP="([^"$]+)"',path.read_text(),re.M)
  assert match,'Cannot prove APP repertoire for '+str(path)
  app=match[1].lower();slug=app.replace(' ','') if kind=='lxc' else re.sub('-+','-',app.replace(' ','-')).rstrip('-')
  assert re.fullmatch('[a-z0-9][a-z0-9._-]{0,63}',slug),str(path)+': '+slug
  slugs.append(slug)
check(bool(slugs),str(len(slugs))+' current LXC/addon literal APP keys fit canonical repertoire')
(work/'results.json').write_text(json.dumps(results,indent=2));failed=sum(not r['ok'] for r in results)
print(f'{len(results)} assertions; {failed} failure(s); real owner/files/processes; package/network/PVE boundaries modeled',flush=True)
sys.exit(1 if failed else 0)
PY
