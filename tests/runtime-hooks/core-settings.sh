#!/usr/bin/env bash
# Actual creation/defaults owners with recording external commands.
set -euo pipefail
ROOT=$(realpath "$(dirname "${BASH_SOURCE[0]}")/../..")
if [[ "${1:-}" == --child ]]; then
  c="$CASE_ROOT"
  source "$ROOT/misc/core.func"
  load_functions
  python3 - "$ROOT/misc/build.func" "$c/functions" << 'PY'
import pathlib,re,sys
s=pathlib.Path(sys.argv[1]).read_text()
# A legacy subject's forbidden scratch literal is redirected, not executed in RAM.
s=s.replace('/tmp/${NSAPP:-app}.vars.new.XXXXXX','"${TMPDIR}/${NSAPP:-app}.vars.new.XXXXXX"').replace('mktemp -p /tmp ', 'mktemp -p "$TMPDIR" ')
functions=re.findall(r'^([a-zA-Z_][a-zA-Z_0-9]*)\(\) \{\n.*?^}',s,re.M|re.S)
names=set(functions)-{'build_container','_lxc_bootstrap','lxc_setup','_lxc_setup'}
out=[m.group() for m in re.finditer(r'^([a-zA-Z_][a-zA-Z_0-9]*)\(\) \{\n.*?^}',s,re.M|re.S) if m[1] in names]
pathlib.Path(sys.argv[2]).write_text('\n\n'.join(out)+'\n')
PY
  source "$c/functions"
  declare -A _VARS_IN=()
  msg_info() { :; }
  msg_ok() { :; }
  msg_warn() { printf 'WARN %s\n' "$*" >> "$c/messages"; }
  msg_error() { printf 'ERROR %s\n' "$*" >> "$c/messages"; }
  msg_debug() { :; }
  case "$KIND" in
    id)
      pvesh() { printf '100\n'; }
      lvs() { [[ "$FAULT" != query ]] || return 42; }
      get_valid_container_id "$VALUE" > "$c/value"
      ;;
    hostname) validate_hostname "$VALUE" ;;
    base)
      export NEXTID=3191 NSAPP=probe timezone=UTC var_os=debian var_version=13
      export APP_DEFAULT_CPU=2 var_cpu=$VALUE var_ram=1024 var_disk=4
      lvs() { :; }
      base_settings
      ;;
    options)
      export CTID=3191 HN=probe BRG=vmbr0 NET=dhcp CORE_COUNT=2 RAM_SIZE=1024 CT_TYPE=1
      export NS='1.1.1.1 2606:4700:4700::1111' SD='one.example two.example' TAGS='first;second'
      export MAC='' GATE='' MTU='' VLAN='' IPV6_METHOD=none
      export PW='--literal spaces * $token' CONTAINER_STORAGE=local PCT_DISK_SIZE=4
      export CT_TIMEZONE=host PROTECT_CT=no
      case "$FAULT" in
        id) CTID=03191 ;;
        hostname) HN=probe. ;;
        bridge) BRG='vmbr0,firewall=0' ;;
        cpu) CORE_COUNT='2 -delete' ;;
        net) NET='dhcp,firewall=0' ;;
        dns) NS='1.1.1.1 --delete' ;;
        tags) TAGS='first --delete' ;;
        password) : ;;
      esac
      declare -a PCT_OPTIONS=()
      _pct_create_options
      printf '%s\0' "${PCT_OPTIONS[@]}" > "$c/argv"
      ;;
    state)
      CTID=3191
      pct() {
        printf '%s\n' "$*" >> "$c/effects"
        case "$FAULT" in
          query) return 42 ;;
          stopped) printf 'status: stopped\n' ;;
          malformed) printf 'surprise\n' ;;
          *) printf 'status: running\n' ;;
        esac
      }
      sleep() { :; }
      _wait_container_running
      ;;
    network)
      export CTID=3191 BRG=vmbr0
      pct() {
        printf '%s\n' "$*" >> "$c/effects"
        case "$1" in
          exec)
            case "$FAULT" in query) return 43 ;; assigned) printf '    inet 192.0.2.7/24 scope global eth0\n' ;; esac
            ;;
          status) printf 'status: running\n' ;;
          config) printf 'net0: name=eth0,bridge=vmbr0,ip=dhcp\n' ;;
        esac
      }
      ip() { printf bridge-observation >> "$c/effects"; }
      journalctl() { printf journal-observation >> "$c/effects"; }
      sleep() { :; }
      _wait_container_network
      ;;
    create)
      export CTID=3191 TEMPLATE_STORAGE=local TEMPLATE=probe.tar.zst LOGFILE="$c/create.log"
      PCT_OPTIONS=(-hostname probe)
      if [[ "$FAULT" == log ]]; then
        mkdir "$c/logdir"
        LOGFILE="$c/logdir"
      fi
      pct() {
        if [[ "$FAULT" == unrelated ]]; then
          printf 'unrelated command failed\n'
        else printf 'timedatectl: command failed (status 23)\n'; fi
        return 23
      }
      _pct_create
      ;;
    defaults)
      export APP=Probe NSAPP=probe CT_TYPE=1 CORE_COUNT=2 RAM_SIZE=1024 DISK_SIZE=4 HN=probe
      export BRG=vmbr0 NET=dhcp TAGS='first;second' PW='--literal secret'
      export TEMPLATE_STORAGE=local CONTAINER_STORAGE=local
      var_lxc_secret=$'line one;$(never-run) # quote\047\\\nline two\n'
      export var_lxc_feature=selected
      export var_ctid=3191 var_initial_confirm=yes LXC_SCRIPT_ID=foreign
      umask 0022
      saved=$(_build_current_app_vars_tmp)
      printf '%s' "$saved" > "$c/saved"
      printf '%s' "$var_lxc_secret" > "$c/original-secret"
      case "$FAULT" in
        explicit) export var_lxc_secret=explicit ;;
        *) var_lxc_secret='script-default' ;;
      esac
      _load_vars_file_to_map "$saved" app
      printf '%s' "${_VARS_IN[var_lxc_secret]-missing}" > "$c/map-secret"
      load_vars_file "$saved" yes app
      printf '%s' "$var_lxc_secret" > "$c/loaded-secret"
      get_app_defaults_path() { printf '%s/defaults/probe.vars\n' "$c"; }
      whiptail() { return 0; }
      maybe_offer_save_app_defaults
      stat -c '%a' "$c/defaults/probe.vars" > "$c/mode"
      printf '# scripts-underground defaults base64-v1\nvar_cpu=%%invalid%%\n' > "$c/defaults/probe.vars"
      cp "$c/defaults/probe.vars" "$c/invalid-before"
      failed=0
      maybe_offer_save_app_defaults || failed=$?
      printf '%s' "$failed" > "$c/invalid-rc"
      cmp "$c/invalid-before" "$c/defaults/probe.vars"
      load_vars_file "$saved" yes general
      _build_vars_diff "$saved" "$c/changed" > "$c/diff"
      ;;
    conffiles)
      python3 - "$ROOT/misc/install.func" "$c/apt-functions" "$c" << 'PY'
import pathlib,re,sys
s=pathlib.Path(sys.argv[1]).read_text()
out=re.findall(r'^_configure_apt_conffiles\(\) \{\n.*?^}',s,re.M|re.S)
pathlib.Path(sys.argv[2]).write_text('\n'.join(out).replace('/etc/apt/apt.conf.d',sys.argv[3]+'/apt.conf.d'))
PY
      source "$c/apt-functions"
      _configure_apt_conffiles
      mkdir "$c/empty"
      printf 'Dir::Etc::Parts "%s";\nDir::Etc::main "-";\n#include "%s";\n' "$c/empty" "$c/apt.conf.d/99scripts-underground-conffiles" > "$c/apt-select"
      APT_CONFIG="$c/apt-select" apt-config dump > "$c/apt-policy"
      ;;
  esac
  exit 0
fi
: "${TMPDIR:?disk TMPDIR required}"
systemd-detect-virt --vm --quiet || exit 65
work=$(mktemp -d "$TMPDIR/core-settings.XXXXXX")
trap 'rm -rf -- "$work"' EXIT
failures=0
check() {
  if [[ "$1" == "$2" ]]; then printf 'PASS %s\n' "$3"; else
    printf 'FAIL %s: expected <%s>, got <%s>\n' "$3" "$2" "$1" >&2
    failures=$((failures + 1))
  fi
}
n=0
go() {
  n=$((n + 1))
  c="$work/$n"
  mkdir -p "$c/home"
  : > "$c/messages"
  : > "$c/effects"
  rc=0
  env -i PATH="$PATH" HOME="$c/home" TMPDIR="$TMPDIR" CASE_ROOT="$c" KIND="$KIND" FAULT="${FAULT:-}" VALUE="${VALUE:-}" \
    BUILD_LOG="$c/build.log" DEBUG_LOGFILE="$c/errors.log" bash "$0" --child > "$c/output" 2>&1 || rc=$?
}
for VALUE in 0100 99 1000000000 garbage; do
  KIND=id go
  check "$((rc != 0))" 1 "invalid explicit CTID $VALUE refuses without selection"
done
VALUE=3191 KIND=id go
check "$rc" 0 'valid explicit CTID accepted'
check "$(cat "$c/value")" 3191 'valid explicit CTID unchanged'
VALUE=3191 KIND=id FAULT=query go
check "$rc" 65 'failed allocation query refuses instead of asserting available'
for VALUE in 09 '1+1' 'a[$(printf executed > "$CASE_ROOT/executed")]'; do
  KIND=base go
  check "$rc" 65 'invalid resource refuses before app-minimum arithmetic'
  check "$(test -e "$c/executed" && echo executed || echo literal)" literal 'resource input is never evaluated as shell arithmetic'
done
for VALUE in probe. .probe probe..example; do
  KIND=hostname go
  check "$((rc != 0))" 1 "invalid hostname $VALUE refuses"
done
for FAULT in id hostname bridge cpu net dns tags; do
  KIND=options go
  check "$rc" 65 "typed $FAULT refuses before pct"
done
KIND=options FAULT=password go
check "$rc" 0 'typed settings assemble argv'
if [[ -f "$c/argv" ]]; then
  value=$(
    python3 - "$c/argv" << 'PY'
import pathlib,sys
a=pathlib.Path(sys.argv[1]).read_bytes().split(b'\0')[:-1]
for k,v in [(b'-password',b'--literal spaces * $token'),(b'-nameserver',b'1.1.1.1 2606:4700:4700::1111'),(b'-searchdomain',b'one.example two.example'),(b'-tags',b'first;second')]:
 assert a[a.index(k)+1]==v,(k,a)
print('preserved')
PY
  ) || value=broken
else value=missing; fi
check "$value" preserved 'password, DNS, search and tags remain literal operands'
for FAULT in query stopped malformed running; do
  KIND=state go
  case "$FAULT" in query) expected=42 ;; running) expected=0 ;; *) expected=65 ;; esac
  check "$rc" "$expected" "$FAULT state has exact truthful result"
  check "$(grep -Ec 'mount|unmount|start|stop' "$c/effects" || true)" 0 'state diagnostics have no lifecycle/mount effects'
done
for FAULT in query absent assigned; do
  KIND=network go
  case "$FAULT" in query) expected=43 ;; absent) expected=65 ;; *) expected=0 ;; esac
  check "$rc" "$expected" "$FAULT network observation preserves producer outcome"
  check "$(grep -Ec 'mount|unmount|start|stop' "$c/effects" || true)" 0 'network diagnostics have no lifecycle/mount effects'
done
for FAULT in timedatectl unrelated log; do
  KIND=create go
  check "$rc" 23 'actual create producer retains native status'
  if [[ "$FAULT" == unrelated ]]; then expected=0; else expected=1; fi
  check "$(grep -c 'timedatectl' "$c/messages" || true)" "$expected" 'timedatectl hint follows actual producer output, not status'
done
for FAULT in saved explicit; do
  KIND=defaults go
  check "$rc" 0 "$FAULT defaults persistence completes"
  if [[ -f "$c/saved" ]]; then
    saved=$(cat "$c/saved")
    check "$(stat -c '%a' "$saved")" 600 'secret staging is private from creation'
    check "$(grep -Ec '^var_(ctid|initial_confirm|install)=' "$saved" || true)" 0 'per-run inputs are never persisted'
    check "$(grep -c '^LXC_SCRIPT_ID=' "$saved" || true)" 0 'derived identity is never persisted'
  fi
  check "$(cat "$c/mode" 2> /dev/null || true)" 600 'published app defaults are private'
  check "$(cat "$c/invalid-rc" 2> /dev/null || true)" 65 'malformed saved data refuses even under a conditional caller'
  check "$(cmp -s "$c/original-secret" "$c/map-secret" && echo same || echo lost)" same 'shared data parser roundtrips multiline literal app secret'
  if [[ "$FAULT" == explicit ]]; then
    check "$(cat "$c/loaded-secret" 2> /dev/null || true)" explicit 'explicit local environment wins saved defaults'
  else
    check "$(cmp -s "$c/original-secret" "$c/loaded-secret" && echo same || echo lost)" same 'saved app settings override source defaults without evaluation'
  fi
  check "$(grep -c 'literal secret\|line one' "$c/diff" 2> /dev/null || true)" 0 'defaults diff does not reveal secret bytes'
done
KIND=conffiles FAULT='' go
check "$rc" 0 'common package initialization establishes conffile preservation'
check "$(grep -c -- '--force-confold' "$c/apt-policy" 2> /dev/null || true)" 1 'raw APT consumers receive preserve-old policy'
printf 'RUNTIME_HOOKS_RESULT failures=%s\n' "$failures"
[[ "$failures" == 0 ]]
