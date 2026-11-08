#!/usr/bin/env bash
# Real cold bundles, files, native ELF processes and kernel ownership. apt,
# release transport, executable version text and systemd lifecycle are models.
set -euo pipefail
if [[ "${1:-}" == --fixture-child ]]; then
  [[ -f /fixture/owned ]] || exit 65
  source /fixture/scenario.sh
  exit
fi
python3 -B "$(dirname -- "${BASH_SOURCE[0]}")/lib/entrypoint.py" maintenance-kosmozoo-current "$@" || exit $?
[[ "${SU_TEST_GUARD_ONLY:-0}" != 1 ]] || exit 0
[[ "$EUID" == 0 ]] || exit 65
: "${TMPDIR:?disk-backed TMPDIR required}"
case "$(findmnt -rn -T "$TMPDIR" -o FSTYPE)" in '' | tmpfs | ramfs) exit 65 ;; esac
ROOT=$(realpath "$(dirname "${BASH_SOURCE[0]}")/..")
work=$(mktemp -d "$TMPDIR/kosmozoo-current.XXXXXXXX")
printf 'Evidence: %s\n' "$work"
failures=0 seed_count=0
check() {
  if [[ "$1" == "$2" ]]; then printf 'PASS %s\n' "$3"; else
    printf 'FAIL %s: expected <%s>, got <%s>\n' "$3" "$2" "$1" >&2
    failures=$((failures + 1))
  fi
}
curl() { :; }
source "$ROOT/scripts/lxc/kosmozoo.sh"
unset -f curl
source "$ROOT/misc/bundle.func"
export APP=Kosmozoo NSAPP=kosmozoo REPO_BASE=https://fixture.invalid
export var_lxc_tmpdir=/data/testtmp

prepare_cold_case() {
  mkdir -p "$c/root/"{usr,etc/systemd/system,opt,root,var/log,var/lib,data/testtmp,data/state,data/cache,data/plugins,data/tmp,proc,dev,sys,fixture,sources/images}
  ln -s usr/bin "$c/root/bin"
  ln -s usr/sbin "$c/root/sbin"
  ln -s usr/lib "$c/root/lib"
  ln -s usr/lib64 "$c/root/lib64"
  mknod "$c/root/dev/null" c 1 3
  mknod "$c/root/dev/urandom" c 1 9
  ln -s /proc/self/fd "$c/root/dev/fd"
  chmod 0666 "$c/root/dev/"{null,urandom}
  printf 'owned fixture\n' > "$c/root/fixture/owned"
  printf 'root:x:0:0:root:/root:/bin/bash\nkosmozoo:x:3456:3457:service:/data:/usr/sbin/nologin\noperator:x:3459:3457:operator:/data:/usr/sbin/nologin\n' > "$c/root/etc/passwd"
  printf 'root:x:0:\nkosmozoo:x:3457:\nmedia:x:3458:kosmozoo,operator\nextra:x:3460:\n' > "$c/root/etc/group"
  printf 'passwd: files\ngroup: files\n' > "$c/root/etc/nsswitch.conf"
  # /usr is bound read-only; resolve its awk alternative inside this owned /etc.
  mkdir -p "$c/root/etc/alternatives"
  ln -s "$(readlink -e "$(command -v awk)")" "$c/root/etc/alternatives/awk"
  cp "$0" "$c/root/fixture/test.sh"
  cp /usr/bin/sleep "$c/root/fixture/new"
  printf '\nNEW\n' >> "$c/root/fixture/new"
  cp /usr/bin/sleep "$c/root/fixture/old"
  printf '\nOLD\n' >> "$c/root/fixture/old"
  sha256sum "$c/root/fixture/new" | cut -d ' ' -f1 > "$c/root/fixture/digest"
  var_lxc_kosmozoo_state=/data/state var_lxc_kosmozoo_cache=/data/cache
  var_lxc_kosmozoo_hosts=${seed:-} var_lxc_kosmozoo_initial_release=latest
  _write_bundle install install_script "$ROOT/misc" 'source /fixture/models.sh' 'install_script' > "$c/root/fixture/install.sh"
  _write_bundle update update_script "$ROOT/misc" --requirements "${var_cpu-}" "${var_ram-}" -- 'source /fixture/models.sh' 'run_update_script' > "$c/root/fixture/update.sh"
  cat > "$c/root/fixture/models.sh" << 'MODELS'
STD='' VERBOSE=no
msg_info() { :; }
msg_ok() { printf 'OK %s\n' "$*"; }
msg_error() { printf 'ERROR %s\n' "$*" >&2; }
render_header() { :; }
header_info() { :; }
check_container_storage() { :; }
ownership_point() { :; }
cleanup_lxc() { ownership_point outer-cleanup; }
get_system_arch() { ownership_point architecture || return $?; printf amd64; }
apt() { printf 'apt %s\n' "$*" >> /fixture/events; }
ensure_dependencies() { :; }
sleep() { SECONDS=$((SECONDS + 100)); }
_gh_release_json() {
  ownership_point selection || return $?
  printf 'select %s\n' "$2" >> /fixture/events
  local v=${2#v} digest
  [[ "$v" != latest ]] || v=0.2.2
  digest=$(cat /fixture/digest)
  if [[ -f /fixture/ownership-versions.json ]]; then digest=$(command jq -er --arg v "$v" '.versions[$v].sha256' /fixture/ownership-versions.json) || return 65; fi
  [[ "$FAULT" != missing-digest ]] || digest=''
  jq -n --arg tag "v$v" --arg digest "$digest" --arg fault "$FAULT" '{id:100,tag_name:$tag,draft:false,prerelease:false,published_at:"2026-10-20T08:49:44Z",assets:([{id:200,name:"kosmozoo-linux-x86_64",size:100,digest:("sha256:"+$digest),browser_download_url:("https://github.com/alexindigo/kosmozoo/releases/download/"+$tag+"/kosmozoo-linux-x86_64")}] + (if $fault=="checksum-missing" then [] else [{id:201,name:"SHA256SUMS",browser_download_url:("https://github.com/alexindigo/kosmozoo/releases/download/"+$tag+"/SHA256SUMS")}] end))}' > "$4"
  if [[ "$FAULT" == checksum-selection && ! "$4" =~ ^/opt/kosmozoo/\.stage\.[^/]+/selected\.json$ ]]; then
    command jq '.assets[1].id=202' "$4" > "$4.changed"; command mv "$4.changed" "$4"
  fi
}
curl_download() {
  ownership_point download || return $?
  printf 'download\n' >> /fixture/events
  [[ "$FAULT" != download ]] || return 41
  if [[ "$2" == */SHA256SUMS ]]; then
    local digest=$(cat /fixture/digest) v=${2%/*}
    v=${v##*/}; v=${v#v}
    if [[ -f /fixture/ownership-versions.json ]]; then digest=$(command jq -er --arg v "$v" '.versions[$v].sha256' /fixture/ownership-versions.json) || return 65; fi
    [[ "$FAULT" != checksum-mismatch ]] || digest=$(printf '%064d' 0)
    printf '%s  kosmozoo-linux-x86_64\n' "$digest" > "$1"
    case "$FAULT" in
      checksum-duplicate) command cat "$1" >> "$1.duplicate"; command cat "$1.duplicate" >> "$1" ;;
      checksum-malformed) printf 'not a checksum\n' > "$1" ;;
      checksum-filename) printf '%s  other\n' "$digest" > "$1" ;;
      checksum-nul) printf '\000' >> "$1" ;;
      identity-change) printf operator > /fixture/runtime-user ;;
    esac
    return 0
  fi
  if [[ -f /fixture/ownership-versions.json ]]; then
    local tag=${2%/*} selected
    tag=${tag##*/}; tag=${tag#v}
    selected=$(command jq -er --arg v "$tag" '.versions[$v].path' /fixture/ownership-versions.json) || return 65
    command cp -- "$selected" "$1"
  else command cp /fixture/new "$1"; fi
  [[ "$FAULT" != digest ]] || printf BAD >> "$1"
}
busctl() {
  case "${!#}" in
    Version) printf '{"type":"s","data":"257-model"}' ;;
    TimeoutStopUSec) printf '{"type":"t","data":45000000}' ;;
    SendSIGKILL) if [[ "$FAULT" == stop-override ]]; then printf '{"type":"b","data":true}'; else printf '{"type":"b","data":false}'; fi ;;
    EnvironmentFiles) printf '{"type":"a(sb)","data":[["/etc/kosmozoo/env",false]]}' ;;
    *) return 97 ;;
  esac
}
systemd-run() {
  printf 'probe %s\n' "$*" >> /fixture/events
  [[ "$FAULT" != probe-fail ]] || return 57
  cat /fixture/environment
}
timeout() {
  if [[ "${!#}" == --version ]]; then
    local -a a=("$@")
    local binary=${a[${#a[@]}-2]} v=0.2.2 hash
    if [[ "$binary" == */kosmozoo-probe.*/kosmozoo ]]; then
      local option uid=0 gid=0 groups=''
      for option in "${a[@]}"; do
        case "$option" in --reuid=*) uid=${option#*=} ;; --regid=*) gid=${option#*=} ;; --groups=*) groups=${option#*=} ;; esac
      done
      [[ "$(stat -c '%u:%a' "$binary")" == "$uid:700" ]] || return 97
      local -a credentials=(setpriv "--reuid=$uid" "--regid=$gid")
      if [[ -n "$groups" ]]; then credentials+=("--groups=$groups"); else credentials+=(--clear-groups); fi
      command "${credentials[@]}" /bin/sh -c 'test -r "$1" && test -x "$1"' sh "$binary" || return 97
      local private_stage
      for private_stage in /opt/kosmozoo/.stage.*; do [[ "$(stat -c '%u:%a' "$private_stage")" == 0:700 ]] || return 97; done
      printf 'runtime-projection uid=%s gid=%s groups=%s\n' "$uid" "$gid" "$groups" >> /fixture/events
    fi
    cmp -s "$binary" /fixture/old && v=${CURRENT_VERSION:-0.2.1}
    if [[ -f /fixture/ownership-versions.json ]]; then
      hash=$(command sha256sum "$binary") || return $?
      v=$(command jq -er --arg h "${hash%% *}" '.binaries[$h]' /fixture/ownership-versions.json) || return 65
    fi
    [[ "$FAULT" != version || "$binary" == /opt/kosmozoo/kosmozoo ]] || v=0.2.21
    printf 'kosmozoo v%s (2172670) (input 1d4ab9b2ea1db4884a627cc0970a87447ceb4424cc0166a838c57984cd2291ea; Deno 2.9.6; x86_64-unknown-linux-gnu)\n' "$v"
    return 0
  fi
  while (($#)); do
    case "$1" in systemctl) shift; systemctl "$@"; return $? ;; systemd-run) shift; systemd-run "$@"; return $? ;; busctl) shift; busctl "$@"; return $? ;; esac
    shift
  done
  return 97
}
systemctl() {
  printf 'systemctl %s\n' "$*" >> /fixture/events
  [[ "${!#}" != dbus.socket ]] || return 0
  local p=0 active property=${4:-}
  [[ ! -f /fixture/pid ]] || p=$(cat /fixture/pid)
  active=$(cat /fixture/active)
  case "$1" in
    show) case "$property" in
      ExecStart) printf '{ path=/opt/kosmozoo/kosmozoo ; argv[]=/opt/kosmozoo/kosmozoo serve ; ignore_errors=no ; }' ;;
      User) if [[ -f /fixture/runtime-user ]]; then cat /fixture/runtime-user; elif [[ -f /etc/systemd/system/kosmozoo.service ]] && grep -q '^User=kosmozoo$' /etc/systemd/system/kosmozoo.service; then printf kosmozoo; else printf root; fi ;;
      Group) [[ ! -f /fixture/runtime-group ]] || cat /fixture/runtime-group ;;
      SupplementaryGroups) [[ ! -f /fixture/runtime-groups ]] || cat /fixture/runtime-groups ;;
      DynamicUser) if [[ "$FAULT" == dynamic ]]; then printf yes; else printf no; fi ;;
      RootDirectory | RootImage) : ;;
      PrivateUsers) printf no ;;
      WorkingDirectory) printf /opt/kosmozoo ;; MainPID) printf '%s' "$p" ;; ActiveState) printf '%s' "$active" ;;
      ControlGroup | Environment | PassEnvironment | UnsetEnvironment) : ;; *) return 97 ;;
    esac ;;
    is-enabled) cat /fixture/enabled; [[ "$(cat /fixture/enabled)" == enabled ]] ;;
    is-active) [[ "$active" == active ]] ;;
    daemon-reload) return 0 ;;
    enable) [[ "$FAULT" != enable ]] || return 51; printf enabled > /fixture/enabled ;;
    disable) [[ "$FAULT" != disable ]] || return 52; printf disabled > /fixture/enabled ;;
    stop)
      ownership_point stop || return $?
      [[ "$FAULT" != stop-linger ]] || { printf deactivating > /fixture/active; return 53; }
      if [[ "$p" != 0 ]]; then kill -TERM "$p" 2>/dev/null || true; fi
      printf 0 > /fixture/pid; printf inactive > /fixture/active ;;
    start)
      ownership_point start || return $?
      if [[ "$FAULT" == start ]]; then printf failed > /fixture/active; printf 0 > /fixture/pid; printf 'candidate touched state\n' >> /data/state/user; return 55; fi
      local -a runtime_env=()
      local setting runtime_state=/data/state runtime_bind=0.0.0.0 runtime_port=80 fd
      while IFS= read -r -d '' setting; do
        runtime_env+=("$setting")
        case "$setting" in KOZMOZOO_STATE=*) runtime_state=${setting#*=} ;; KOZMOZOO_BIND=*) runtime_bind=${setting#*=} ;; KOZMOZOO_PORT=*) runtime_port=${setting#*=} ;; esac
      done < /fixture/environment
      mkdir -p "$runtime_state"
      local user uid gid groups extra
      user=$(systemctl show kosmozoo -p User --value)
      uid=$(id -u "$user"); gid=$(systemctl show kosmozoo -p Group --value); gid=${gid:-$(id -g "$user")}
      if [[ "$uid" == 0 ]]; then groups=''; else groups="$gid,3458"; fi
      for extra in $(systemctl show kosmozoo -p SupplementaryGroups --value); do
        extra=$(getent group "$extra" | cut -d: -f3)
        groups+="${groups:+,}$extra"
      done
      local -a runtime_credentials=(setpriv "--reuid=$uid" "--regid=$gid")
      if [[ -n "$groups" ]]; then runtime_credentials+=("--groups=$groups"); else runtime_credentials+=(--clear-groups); fi
      (
        # PID1-started services do not inherit productive maintenance descriptors.
        for fd in /proc/"$BASHPID"/fd/*; do fd=${fd##*/}; if ((fd >= 3)); then eval "exec ${fd}>&-"; fi; done
        case "$FAULT" in
          process-uid) runtime_credentials=(setpriv --reuid=3459 "--regid=$gid" "--groups=$groups") ;;
          process-gid) runtime_credentials=(setpriv "--reuid=$uid" --regid=3458 "--groups=$groups") ;;
          process-groups) runtime_credentials=(setpriv "--reuid=$uid" "--regid=$gid" --groups=0) ;;
        esac
        exec "${runtime_credentials[@]}" env -i PATH=/usr/bin:/bin "${runtime_env[@]}" /opt/kosmozoo/kosmozoo 900
      ) &
      p=$!; printf '%s' "$p" > /fixture/pid
      command sleep 0.03
      printf active > /fixture/active
      runtime_port=${runtime_port#"${runtime_port%%[!0]*}"}; runtime_port=${runtime_port:-0}
      jq -n --argjson pid "$p" --arg bind "$runtime_bind" --argjson port "$runtime_port" --arg version "${PIN:-0.2.2}" '{protocol:"kosmozoo-runtime",version:1,instance:"00000000-0000-4000-8000-000000000001",sourceVersion:"fixture",mode:"serve",status:"ready",binding:{hostname:$bind,port:$port},configuredBind:$bind,app:{version:$version,revision:"2172670"},ownerPid:$pid}' > /fixture/runtime.json
      "${runtime_credentials[@]}" /bin/sh -c 'umask 077; cat > "$1"' sh "$runtime_state/engine-instance.json" < /fixture/runtime.json
      [[ "$FAULT" != private-owner ]] || chown 1234:1234 "$runtime_state/engine-instance.json"
      [[ "$FAULT" != private-mode ]] || chmod 0644 "$runtime_state/engine-instance.json" ;;
    *) return 97 ;;
  esac
}
curl() { [[ "$FAULT" != readiness && "$FAULT" != disable ]] || return 56; jq 'del(.ownerPid)' /fixture/runtime.json; }
ss() { printf 'LISTEN 0 128 0.0.0.0:80 *:* users:(("kosmozoo",pid=%s,fd=3))\n' "$(cat /fixture/pid)"; }
mv() {
  local dest=${!#}
  if [[ "$dest" == /opt/kosmozoo/kosmozoo ]]; then
    if [[ "${@: -2:1}" == */previous ]]; then ownership_point recovery || return $?; else ownership_point publication || return $?; fi
  fi
  case "$FAULT:$dest" in publish:/opt/kosmozoo/kosmozoo) return 61 ;; marker:/root/.kosmozoo) return 63 ;; esac
  command mv "$@"
}
rm() { [[ "$FAULT" != cleanup || "${!#}" != /opt/kosmozoo/activation-attempt.json ]] || return 64; command rm "$@"; }
[[ ! -f /fixture/ownership-models.sh ]] || source /fixture/ownership-models.sh
MODELS
}

run_case() {
  local status=0
  export c
  timeout --signal=TERM --kill-after=5 60 unshare --mount --pid --fork --propagation private bash -c '
    set -euo pipefail
    mount --bind "$c/root" "$c/root"
    mount --bind /usr "$c/root/usr"
    mount -o remount,bind,ro "$c/root/usr"
    mount -t proc proc "$c/root/proc"
    mount --bind "$c/root/data/cache" "$c/root/data/cache"
    env -i PATH=/usr/sbin:/usr/bin:/bin HOME=/root TMPDIR=/data/testtmp chroot "$c/root" /bin/bash /fixture/test.sh --fixture-child
  ' > "$c/output" 2>&1 || status=$?
  check "$status" 0 "${c##*/} cold consumer"
  if [[ "$status" != 0 ]]; then cat "$c/output" >&2; fi
}

# Every seed check executes a full cold hook. Positive inputs reach the modeled
# first start, with real rendered env; refusals must precede apt and all app writes.
seed_case() {
  local label=$1 seed=$2 expected=$3
  c="$work/seed-$label"
  prepare_cold_case
  chown 3456:3457 "$c/root/data" "$c/root/data/"{state,cache,plugins,tmp}
  if [[ "$label" == denied ]]; then
    mkdir "$c/root/sources/blocked"
    chmod 000 "$c/root/sources/blocked"
  fi
  if [[ "$label" == group ]]; then
    chown 0:3458 "$c/root/sources/images"
    chmod 0750 "$c/root/sources/images"
  fi
  printf '%s' "$expected" > "$c/root/fixture/expected"
  cat > "$c/root/fixture/scenario.sh" << 'SEED'
set -euo pipefail
export FAULT=start PIN=0.2.2 LOCAL_IP=127.0.0.1
: > /fixture/events
printf inactive > /fixture/active; printf disabled > /fixture/enabled; printf 0 > /fixture/pid
printf '%s\0' HOME=/data TMPDIR=/data/tmp KOZMOZOO_STATE=/data/state KOZMOZOO_CACHE=/data/cache KOZMOZOO_HOSTS= KOZMOZOO_PLUGINS=/data/plugins KOZMOZOO_BIND=0.0.0.0 KOZMOZOO_PORT=80 > /fixture/environment
expected=$(cat /fixture/expected)
status=0
if [[ -f /fixture/drop-dac ]]; then
  capsh --drop=cap_dac_override,cap_dac_read_search -- -c 'bash /fixture/install.sh' > /fixture/hook.log 2>&1 || status=$?
else
  bash /fixture/install.sh > /fixture/hook.log 2>&1 || status=$?
fi
printf 'SEED_OBSERVED expected=%s status=%s\n' "$expected" "$status"
[[ ! -f /etc/kosmozoo/env ]] || sha256sum /etc/kosmozoo/env
if [[ "$expected" == REFUSE ]]; then
  [[ "$status" == 65 && ! -e /etc/kosmozoo/env && ! -e /opt/kosmozoo && ! -e /root/.kosmozoo ]]
  ! grep -q '^apt\|^select\|systemctl start kosmozoo' /fixture/events
  grep -q 'KOZMOZOO_HOSTS\|Folder seed' /fixture/hook.log
  [[ ! -e /missing-source ]]
else
  [[ "$status" == 1 ]]
  grep -Fx "KOZMOZOO_HOSTS=\"$expected\"" /etc/kosmozoo/env
  [[ "$(stat -c %a /etc/kosmozoo/env)" == 600 ]]
  [[ "$(cat /fixture/enabled)" == disabled && -f /opt/kosmozoo/activation-attempt.json ]]
fi
printf 'SEED_OUTCOME %s status=%s\n' "$expected" "$status"
SEED
  run_case
}
seed_case bare 'studio=comfy.home' 'studio=comfy.home:80'
seed_case trim ' studio = comfy.home , local = folder:/sources/images ' 'studio=comfy.home:80,local=folder:/sources/images'
seed_case one 'studio=host:1' 'studio=host:1'
seed_case max 'studio=host:65535' 'studio=host:65535'
seed_case zeros 'studio=host:00080' 'studio=host:80'
seed_case empty '' ''
seed_case folder 'local=folder:/sources/images' 'local=folder:/sources/images'
seed_case denied 'local=folder:/sources/blocked' REFUSE
for bad in 'host:0' 'host:65536' 'host:' 'host:abc' 'host:-1' 'host:1.2' 'folder:relative' 'folder:/missing-source' 'folder:/fixture/owned'; do
  seed_case "bad-$((++seed_count))" "studio=$bad" REFUSE
done
printf -v long '%020000d' 0
seed_case long-overflow "studio=host:${long}18446744073709551617" REFUSE
seed_case long-zero "studio=host:$long" REFUSE
seed_case long-valid "studio=host:${long}80" 'studio=host:80'
seed_case duplicate 'studio=host:80,studio=other:80' REFUSE
seed_case control $'studio=host:80\n' REFUSE
seed_case trailing 'studio=host:80,' REFUSE
seed_case middle 'studio=host:80,,other=host:80' REFUSE
seed_case group 'local=folder:/sources/images' 'local=folder:/sources/images'

seed=''
for scenario in install update no-op download digest missing-digest version publish start marker readiness enable disable cleanup disabled-entry stopped-download floor stop-override; do
  c="$work/$scenario"
  prepare_cold_case
  printf '%s' "$scenario" > "$c/root/fixture/selected-case"
  cat > "$c/root/fixture/scenario.sh" << 'CASE'
set -euo pipefail
scenario=$(cat /fixture/selected-case)
export FAULT=none PIN=0.2.2 CURRENT_VERSION=0.2.1
: > /fixture/events
printf inactive > /fixture/active; printf enabled > /fixture/enabled; printf 0 > /fixture/pid
printf '%s\0' HOME=/data TMPDIR=/data/tmp KOZMOZOO_STATE=/data/state KOZMOZOO_CACHE=/data/cache KOZMOZOO_HOSTS= KOZMOZOO_PLUGINS=/data/plugins KOZMOZOO_BIND=0.0.0.0 KOZMOZOO_PORT=80 > /fixture/environment
printf 'user state\n' > /data/state/user; printf 'user cache\n' > /data/cache/user
chown 1234:1234 /data/cache/user
before=$(stat -c '%d:%i:%a:%u:%g' /data/state /data/cache /data/cache/user)
mount_before=$(grep ' /data/cache ' /proc/self/mountinfo)
source /fixture/models.sh
kind=update
if [[ "$scenario" == install ]]; then kind=install; chown 3456:3457 /data /data/state /data/cache /data/plugins /data/tmp; before=$(stat -c '%d:%i:%a:%u:%g' /data/state /data/cache /data/cache/user); else
  mkdir -p /opt/kosmozoo /etc/kosmozoo
  command cp /fixture/old /opt/kosmozoo/kosmozoo
  printf '0.2.1\n' > /root/.kosmozoo
  printf 'OPERATOR ENV\n' > /etc/kosmozoo/env
  printf 'OPERATOR UNIT\n' > /etc/systemd/system/kosmozoo.service
  operator=$(stat -c '%d:%i:%a:%u:%g:%y' /etc/kosmozoo/env /etc/systemd/system/kosmozoo.service)
  if [[ "$scenario" == no-op ]]; then command cp /fixture/new /opt/kosmozoo/kosmozoo; printf '0.2.2\n' > /root/.kosmozoo; fi
  systemctl start kosmozoo
fi
case "$scenario" in
  no-op) oldpid=$(cat /fixture/pid) ;;
  disabled-entry) printf disabled > /fixture/enabled ;;
  stopped-download) systemctl stop kosmozoo; printf disabled > /fixture/enabled; FAULT=download ;;
  floor) FAULT=start ;;
  install | update) : ;;
  *) FAULT=$scenario ;;
esac
invoke() {
  local status=0
  env -i PATH=/usr/sbin:/usr/bin:/bin HOME=/root TMPDIR=/data/testtmp LOCAL_IP=127.0.0.1 FAULT="$FAULT" PIN="$PIN" var_appversion="$PIN" CURRENT_VERSION=0.2.1 bash "/fixture/$kind.sh" > /fixture/hook.log 2>&1 || status=$?
  printf '%s' "$status" > /fixture/status
}
invoke
status=$(cat /fixture/status)
case "$scenario" in
  install | update | no-op | disabled-entry) expected_status=0 ;;
  download | stopped-download) expected_status=250 ;;
  digest | missing-digest | version | stop-override) expected_status=65 ;;
  publish) expected_status=61 ;;
  start | floor) expected_status=55 ;;
  marker) expected_status=63 ;;
  enable) expected_status=51 ;;
  cleanup) expected_status=64 ;;
  readiness | disable) expected_status=1 ;;
  *) exit 97 ;;
esac
[[ "$status" == "$expected_status" ]]
case "$scenario" in
  install | update | disabled-entry | no-op)
    [[ "$status" == 0 && "$(cat /root/.kosmozoo)" == 0.2.2 && ! -e /opt/kosmozoo/activation-attempt.json ]]
    if [[ "$scenario" == disabled-entry ]]; then [[ "$(cat /fixture/enabled)" == disabled ]]; else [[ "$(cat /fixture/enabled)" == enabled ]]; fi ;;
  start | marker | readiness | enable | floor)
    [[ "$status" != 0 && "$(cat /fixture/active)" == inactive && "$(cat /fixture/enabled)" == disabled ]]
    command cmp /fixture/old /opt/kosmozoo/kosmozoo
    [[ "$(cat /root/.kosmozoo)" == 0.2.1 && -f /opt/kosmozoo/activation-attempt.json ]]
    case "$scenario" in start | floor) grep -Fxq 'candidate touched state' /data/state/user ;; esac ;;
  disable) [[ "$status" != 0 && -f /opt/kosmozoo/activation-attempt.json ]]; command cmp /fixture/new /opt/kosmozoo/kosmozoo ;;
  cleanup) [[ "$status" == 64 && "$(cat /fixture/active)" == active && "$(cat /root/.kosmozoo)" == 0.2.2 ]]; command cmp /fixture/new /opt/kosmozoo/kosmozoo ;;
  stopped-download) [[ "$status" != 0 && "$(cat /fixture/active)" == inactive && "$(cat /fixture/enabled)" == disabled ]]; command cmp /fixture/old /opt/kosmozoo/kosmozoo ;;
  *) [[ "$status" != 0 && "$(cat /fixture/active)" == active && "$(cat /root/.kosmozoo)" == 0.2.1 ]]; command cmp /fixture/old /opt/kosmozoo/kosmozoo; [[ ! -e /opt/kosmozoo/activation-attempt.json ]] ;;
esac
if [[ "$scenario" == floor ]]; then
  prior=$(sha256sum /opt/kosmozoo/activation-attempt.json)
  FAULT=none PIN=0.2.1 invoke
  [[ "$(cat /fixture/status)" == 65 && "$(sha256sum /opt/kosmozoo/activation-attempt.json)" == "$prior" ]]
  [[ "$(cat /fixture/active)" == inactive ]]
  FAULT=none PIN=0.2.2 invoke
  [[ "$(cat /fixture/status)" == 0 && ! -e /opt/kosmozoo/activation-attempt.json ]]
fi
if [[ "$scenario" == no-op ]]; then [[ "$(cat /fixture/pid)" == "$oldpid" ]]; ! grep -Eq '^download|systemctl stop' /fixture/events; fi
if [[ "$scenario" != install ]]; then
  [[ "$(cat /etc/kosmozoo/env)" == 'OPERATOR ENV' && "$(cat /etc/systemd/system/kosmozoo.service)" == 'OPERATOR UNIT' ]]
  [[ "$(stat -c '%d:%i:%a:%u:%g:%y' /etc/kosmozoo/env /etc/systemd/system/kosmozoo.service)" == "$operator" ]]
  if [[ "$(cat /fixture/status)" == 0 ]]; then [[ ! -e /var/lib/scripts-underground/update-pending/kosmozoo ]]; else [[ -f /var/lib/scripts-underground/update-pending/kosmozoo ]]; fi
fi
grep -Fxq 'user state' /data/state/user
[[ "$(cat /data/cache/user)" == 'user cache' && "$(stat -c '%d:%i:%a:%u:%g' /data/state /data/cache /data/cache/user)" == "$before" ]]
[[ "$(grep ' /data/cache ' /proc/self/mountinfo)" == "$mount_before" ]]
printf 'COLD_OUTCOME %s primary=%s final=%s\n' "$scenario" "$status" "$(cat /fixture/status)"
CASE
  run_case
done
# Additional credential and integrity controls use the same cold bundle consumer.
# Root administration and runtime credentials are deliberately distinct.
for contract in checksum-missing checksum-duplicate checksum-malformed checksum-mismatch checksum-filename checksum-selection checksum-nul nonroot custom-group custom-account supplementary-groups override-root override-root-groups dynamic unknown-user probe-fail private-owner private-mode process-uid process-gid process-groups identity-change lock-owner state-owner denied-ancestor denied-tmp noexec-tmp; do
  c="$work/contract-$contract"
  prepare_cold_case
  printf '%s' "$contract" > "$c/root/fixture/contract"
  cat > "$c/root/fixture/scenario.sh" << 'CONTRACT'
set -euo pipefail
contract=$(cat /fixture/contract)
export FAULT=none PIN=0.2.2 CURRENT_VERSION=0.2.1
source /fixture/models.sh
: > /fixture/events
printf inactive > /fixture/active; printf disabled > /fixture/enabled; printf 0 > /fixture/pid
mkdir -p /opt/kosmozoo /etc/kosmozoo
command cp /fixture/old /opt/kosmozoo/kosmozoo
printf '0.2.1\n' > /root/.kosmozoo
printf 'OPERATOR ENV\n' > /etc/kosmozoo/env; chmod 0600 /etc/kosmozoo/env
printf 'OPERATOR UNIT\n' > /etc/systemd/system/kosmozoo.service
printf kosmozoo > /fixture/runtime-user
chown 3456:3457 /data /data/state /data/cache /data/plugins /data/tmp
printf '%s\0' HOME=/data TMPDIR=/data/tmp KOZMOZOO_STATE=/data/state KOZMOZOO_CACHE=/data/cache KOZMOZOO_HOSTS= KOZMOZOO_PLUGINS=/data/plugins KOZMOZOO_BIND=0.0.0.0 KOZMOZOO_PORT=80 > /fixture/environment
case "$contract" in
  checksum-* | dynamic | probe-fail | private-owner | private-mode | process-* | identity-change) FAULT=$contract ;;
  custom-group) printf 3458 > /fixture/runtime-group ;;
  custom-account) printf operator > /fixture/runtime-user; chown 3459:3457 /data /data/state /data/cache /data/plugins /data/tmp ;;
  supplementary-groups) printf extra > /fixture/runtime-groups ;;
  override-root) printf root > /fixture/runtime-user; chown 0:0 /data /data/state /data/cache /data/plugins /data/tmp ;;
  override-root-groups) printf root > /fixture/runtime-user; printf extra > /fixture/runtime-groups; chown 0:0 /data /data/state /data/cache /data/plugins /data/tmp ;;
  unknown-user) printf missing > /fixture/runtime-user ;;
  lock-owner) touch /data/state/engine.lock; chmod 0600 /data/state/engine.lock ;;
  state-owner) chown 1234:1234 /data/state ;;
  denied-ancestor) chmod 0700 /data; chown 0:0 /data ;;
  denied-tmp) chmod 0500 /data/tmp ;;
  noexec-tmp) mount --bind /data/tmp /data/tmp; mount -o remount,bind,noexec /data/tmp ;;
esac
case "$contract" in
  checksum-* | dynamic | probe-fail)
    printf root > /fixture/runtime-user
    chown 0:0 /data /data/state /data/cache /data/plugins /data/tmp ;;
esac
before=$(stat -c '%a:%u:%g' /data /data/state /data/cache /data/tmp /etc/kosmozoo/env /etc/systemd/system/kosmozoo.service)
status=0
env -i PATH=/usr/sbin:/usr/bin:/bin HOME=/root TMPDIR=/data/testtmp LOCAL_IP=127.0.0.1 FAULT="$FAULT" PIN="$PIN" var_appversion="$PIN" CURRENT_VERSION=0.2.1 bash /fixture/update.sh > /fixture/hook.log 2>&1 || status=$?
printf 'CONTRACT_OBSERVED %s status=%s\n' "$contract" "$status"
cat /fixture/hook.log
case "$contract" in
  nonroot | custom-group | custom-account | supplementary-groups | override-root | override-root-groups)
    [[ "$status" == 0 && "$(cat /root/.kosmozoo)" == 0.2.2 ]]
    [[ "$(cat /fixture/enabled)" == disabled ]]
    user=$(systemctl show kosmozoo -p User --value)
    [[ "$(stat -c %u /data/state/engine-instance.json)" == "$(id -u "$user")" ]]
    if [[ "$contract" != override-root* ]]; then
      grep -q -- '--property=User=345[69]' /fixture/events
      grep -q 'runtime-projection uid=345[69]' /fixture/events
    fi
    command cmp /fixture/new /opt/kosmozoo/kosmozoo ;;
  private-owner | private-mode | process-*)
    [[ "$status" != 0 && "$(cat /fixture/enabled)" == disabled && -f /opt/kosmozoo/activation-attempt.json ]]
    [[ "$(stat -c '%u:%a' /opt/kosmozoo/activation-attempt.json)" == 0:600 ]]
    command cmp /fixture/old /opt/kosmozoo/kosmozoo ;;
  *)
    [[ "$status" != 0 && "$(cat /fixture/active)" == inactive && ! -e /opt/kosmozoo/activation-attempt.json ]]
    command cmp /fixture/old /opt/kosmozoo/kosmozoo
    [[ "$(cat /root/.kosmozoo)" == 0.2.1 ]]
    ! grep -q 'systemctl stop\|systemctl start kosmozoo' /fixture/events ;;
esac
[[ "$(cat /etc/kosmozoo/env)" == 'OPERATOR ENV' && "$(cat /etc/systemd/system/kosmozoo.service)" == 'OPERATOR UNIT' ]]
[[ "$(stat -c '%a:%u:%g' /data /data/state /data/cache /data/tmp /etc/kosmozoo/env /etc/systemd/system/kosmozoo.service)" == "$before" ]]
printf 'CONTRACT_OUTCOME %s status=%s\n' "$contract" "$status"
CONTRACT
  run_case
done
for fresh in directories account-root inaccessible-state checksum-missing checksum-duplicate checksum-malformed checksum-mismatch checksum-filename checksum-selection checksum-nul; do
  c="$work/fresh-$fresh"
  prepare_cold_case
  printf '%s' "$fresh" > "$c/root/fixture/fresh"
  cat > "$c/root/fixture/scenario.sh" << 'FRESH'
set -euo pipefail
export FAULT=none PIN=0.2.2 LOCAL_IP=127.0.0.1
: > /fixture/events
printf inactive > /fixture/active; printf disabled > /fixture/enabled; printf 0 > /fixture/pid
printf '%s\0' HOME=/data TMPDIR=/data/tmp KOZMOZOO_STATE=/data/state KOZMOZOO_CACHE=/data/cache KOZMOZOO_HOSTS= KOZMOZOO_PLUGINS=/data/plugins KOZMOZOO_BIND=0.0.0.0 KOZMOZOO_PORT=80 > /fixture/environment
fresh=$(cat /fixture/fresh)
case "$fresh" in
  directories) rmdir /data/state /data/plugins /data/tmp; chown 3456:3457 /data /data/cache ;;
  account-root) printf 'root:x:0:0:root:/root:/bin/bash\nkosmozoo:x:0:3457:bad:/data:/bin/bash\n' > /etc/passwd ;;
  checksum-*) FAULT=$fresh; chown 3456:3457 /data /data/state /data/cache /data/plugins /data/tmp ;;
esac
before=$(stat -c '%u:%g:%a' /data /data/cache)
account_before=$(sha256sum /etc/passwd /etc/group)
status=0
bash /fixture/install.sh > /fixture/hook.log 2>&1 || status=$?
printf 'FRESH_OBSERVED %s status=%s\n' "$fresh" "$status"
if [[ "$fresh" == directories ]]; then
  [[ "$status" == 0 && "$(cat /root/.kosmozoo)" == 0.2.2 ]]
  for path in /data/state /data/plugins /data/tmp; do [[ "$(stat -c '%u:%g:%a' "$path")" == 3456:3457:755 ]]; done
  grep -Fxq 'User=kosmozoo' /etc/systemd/system/kosmozoo.service
  grep -Fxq 'AmbientCapabilities=CAP_NET_BIND_SERVICE' /etc/systemd/system/kosmozoo.service
  grep -Fxq 'CapabilityBoundingSet=CAP_NET_BIND_SERVICE' /etc/systemd/system/kosmozoo.service
else
  [[ "$status" == 65 && ! -e /root/.kosmozoo && ! -e /etc/kosmozoo/env ]]
  ! grep -q 'systemctl start kosmozoo' /fixture/events
fi
[[ "$(stat -c '%u:%g:%a' /data /data/cache)" == "$before" ]]
[[ "$(sha256sum /etc/passwd /etc/group)" == "$account_before" ]]
printf 'FRESH_OUTCOME %s status=%s\n' "$fresh" "$status"
FRESH
  run_case
done
source "$ROOT/tests/maintenance-kosmozoo-ownership.func"
kosmozoo_ownership_contracts "$work" 0 "$ROOT"
printf 'KOSMOZOO_CURRENT failures=%s\n' "$failures"
[[ "$failures" == 0 ]]
printf 'KOSMOZOO_CURRENT_PASS\n'
