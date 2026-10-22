#!/usr/bin/env bash
# Cold real bundles/helpers/filesystem. Deno compilation, network and service
# lifecycle are MODELS; EnvironmentFile decoding is the guest's real systemd.
set -euo pipefail
systemd-detect-virt --vm --quiet || exit 1
: "${TMPDIR:?disk-backed TMPDIR required}"
case "$(realpath -e "$TMPDIR")" in /tmp | /tmp/*) exit 1 ;; esac
case "$(findmnt -rn -T "$TMPDIR" -o FSTYPE)" in '' | tmpfs | ramfs) exit 1 ;; esac
ROOT=$(realpath "$(dirname "${BASH_SOURCE[0]}")/..")

if [[ "${1:-}" == --namespace ]]; then
  c=$2
  mount --make-rprivate /
  mount --bind /usr "$c/root/usr"
  mount -o remount,bind,ro "$c/root/usr"
  mount --bind "$c/local" "$c/root/usr/local"
  mount --bind /dev "$c/root/dev"
  mount -t proc proc "$c/root/proc"
  mount --bind "$ROOT" "$c/root/source"
  mount -o remount,bind,ro "$c/root/source"
  chroot "$c/root" /usr/bin/env -i PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin \
    HOME=/root TMPDIR=/work/tmp FIXTURE=/fixture bash /fixture/launch
  exit $?
fi

[[ "${1:-}" == --native || "${1:-}" == --baseline || "${1:-}" == --runtime-lock-only || "${1:-}" == --python-syntax-only ]] || exit 65
# Bash lint does not parse embedded programs, including unexecuted native stages.
# Admit only the feature's direct stdin/quoted-literal Python heredoc form.
globnotes_python_sources=("$ROOT/tests/maintenance-globnotes.test.sh" "$ROOT/tests/maintenance-globnotes-lxc.test.sh")
if [[ "${1:-}" == --python-syntax-only && $# -gt 1 ]]; then globnotes_python_sources=("${@:2}"); fi
python3 - "${globnotes_python_sources[@]}" << 'PY'
import pathlib,re,sys
header=re.compile(r'''^\s*python3\s+-\s+.+?\s+<<\s*(['"])([A-Za-z_][A-Za-z0-9_]*)\1\s*&?\s*$''')
heredoc=re.compile(r'(?<!<)<<-?(?!<)')
interpreter=re.compile(r'\bpython(?:[0-9.]+)?\b')
for filename in sys.argv[1:]:
    lines=pathlib.Path(filename).read_text().splitlines(keepends=True);i=0;count=0
    while i<len(lines):
        start=i;command=lines[i].rstrip('\n');i+=1
        if command.lstrip().startswith('#'):continue
        while command.endswith('\\') and i<len(lines):
            command=command[:-1]+lines[i].rstrip('\n');i+=1
        if not heredoc.search(command):continue
        # PY delimiters also reject an opaque/dynamic interpreter substitution.
        if not interpreter.search(command) and not re.search(r'''<<-?\s*['"]?PY\b''',command):continue
        match=header.fullmatch(command)
        if (match is None or i!=start+1 or len(heredoc.findall(command))!=1
                or re.search(r'[;&|<>`]|\$\(',command.split('<<',1)[0])):
            raise SystemExit(f'{filename}:{start+1}: unrecognized Python heredoc header')
        delimiter=match[2];end=i
        while end<len(lines) and lines[end].rstrip('\n')!=delimiter:end+=1
        if end==len(lines):raise SystemExit(f'{filename}:{start+1}: missing Python heredoc delimiter')
        # Prefix blank lines so the real parser reports original shell line numbers.
        # compile() parses and validates statements; it never executes the body.
        compile('\n'*i+''.join(lines[i:end]),filename,'exec')
        count+=1;print(f'PASS Python heredoc parses: {filename}:{start+1}')
        i=end+1
    if count==0:raise SystemExit(f'{filename}: no literal Python heredocs found')
    print(f'Parsed {count} literal Python heredoc(s): {filename}')
PY
if [[ "${1:-}" == --python-syntax-only ]]; then exit 0; fi
subject=${2:-$ROOT/scripts/lxc/globnotes.sh}
work=$(mktemp -d "$TMPDIR/maintenance-globnotes.XXXXXX")
# Retain failed evidence; the caller may supply an external result directory.
printf 'EVIDENCE %s\n' "$work"
failures=0
check() {
  if [[ "$1" == "$2" ]]; then printf 'PASS %s\n' "$3"; else
    printf 'FAIL %s: expected <%s>, got <%s>\n' "$3" "$2" "$1" >&2
    failures=$((failures + 1))
  fi
}

make_case() {
  c="$work/$1"
  mkdir -p "$c/root"/{usr,dev,proc,source,fixture,work/tmp,etc/systemd/system,etc/globnotes,opt,root,var/cache,var/lib,sys/fs/cgroup/fixture-writers} "$c/local/bin" "$c/root/fixture/archive/source"
  # The service boundary can retain a populated group even after reporting a
  # zero MainPID. This disk fixture models that kernel-facing interface only.
  printf '42\n' > "$c/root/sys/fs/cgroup/fixture-writers/cgroup.procs"
  ln -s usr/bin "$c/root/bin"
  ln -s usr/sbin "$c/root/sbin"
  ln -s usr/lib "$c/root/lib"
  ln -s usr/lib64 "$c/root/lib64"
  cp /etc/{passwd,group,nsswitch.conf} "$c/root/etc/"
  cp -a /etc/alternatives "$c/root/etc/"
  cp -a /etc/pam.d "$c/root/etc/"
  cp /etc/login.defs "$c/root/etc/"
  printf 'globnotes:x:60123:60123::/var/lib/globnotes:/usr/sbin/nologin\n' >> "$c/root/etc/passwd"
  printf 'globnotes:x:60123:\n' >> "$c/root/etc/group"
  printf '2.4.0\n' > "$c/root/fixture/archive/source/VERSION"
  printf 'FROM --platform=$BUILDPLATFORM denoland/deno:2.9.6 AS build\nFROM denoland/deno:alpine-2.9.6\n' > "$c/root/fixture/archive/source/Dockerfile"
  printf '{"nodeModulesDir":"auto"}\n' > "$c/root/fixture/archive/source/deno.json"
  printf '{}\n' > "$c/root/fixture/archive/source/deno.lock"
  mkdir -p "$c/root/fixture/archive/source"/{client,server,shared,plugins}
  printf 'new endpoint\n' > "$c/root/fixture/archive/source/server/main.ts"
  printf 'notice\n' > "$c/root/fixture/archive/source/LICENSE"
  printf 'third party\n' > "$c/root/fixture/archive/source/THIRD-PARTY-NOTICES.md"
  cp "$subject" "$c/root/fixture/subject"
  printf 'none\n' > "$c/root/fixture/fault"
  printf 'v2.4.0\n' > "$c/root/fixture/invocation-pin"
  printf 'inactive\n' > "$c/root/fixture/state"
  printf 'install\n' > "$c/root/fixture/role"
  cat > "$c/root/fixture/start-running" << 'RUNNING'
if [[ -e /fixture/was-active ]]; then
  mkfifo /fixture/hold
  exec 9<> /fixture/hold
  mapfile -d '' -t running < /fixture/running.env0
  env -i "${running[@]}" /opt/globnotes/runtime/deno -c 'read -rt 300 -u 9' &
  printf '%s\n' "$!" > /fixture/pid
  printf 'active\n' > /fixture/state
fi
RUNNING
  cat > "$c/root/fixture/deno" << 'DENO'
#!/usr/bin/env bash
set -euo pipefail
if [[ "$1" == --version ]]; then printf 'deno %s (stable)\n' "$(cat /fixture/pin 2>/dev/null || printf 2.9.6)"; exit; fi
printf '%s|%s|%s|%s\n' "$PWD" "$*" "$DENO_DIR" "$(id -u)" >> /fixture/builds
[[ "$(id -u)" != 0 ]] || exit 89
[[ -d "$DENO_DIR" && -w "$DENO_DIR" ]] || exit 88
[[ ! -e /fixture/was-active || -e /fixture/stopped ]] || exit 87
case "$(cat /fixture/fault):$*" in dependency:install*) exit 71 ;; build:task*) exit 72 ;; esac
if [[ "$1" == task ]]; then mkdir -p client/dist; printf '<html>built</html>\n' > client/dist/index.html; fi
if [[ "$1" == task && $(cat /fixture/fault) == lock-mutate ]]; then printf 'changed dependency graph\n' >> deno.lock; fi
mkdir -p node_modules
printf 'candidate metadata\n' > "$DENO_DIR/meta"
DENO
  chmod 755 "$c/root/fixture/deno"
  chmod 777 "$c/root/fixture"
  cat > "$c/root/fixture/models" << 'MODELS'
msg_info() { printf '%s\n' "$*" >> /fixture/messages; }
msg_ok() { msg_info "$@"; }
msg_warn() { msg_info "$@"; }
msg_error() { printf '%s\n' "$*" >&2; }
render_header() { :; }
header_info() { :; }
check_container_storage() { :; }
check_container_resources() { :; }
stop_spinner() { :; }
cleanup_lxc() { :; }
getent() { if [[ "$1" == hosts ]]; then return 0; fi; command getent "$@"; }
ensure_dependencies() { :; }
setup_nodejs() { :; }
setup_uv() { :; }
clone_and_deploy_gh_commit() { return 92; }
apt() { printf '%s\n' "$*" >> /fixture/apt; }
sleep() { :; }
curl() {
  local out='' format='' url='' x
  while (($#)); do
    case "$1" in -o|--output) out=$2; shift ;; -w|--write-out) format=$2; shift ;; http*) url=$1 ;; esac
    shift
  done
  local fault body tag revision release_id
  fault=$(cat /fixture/fault)
  [[ "$fault" != transport ]] || return 18
  case "$url" in
    */git/ref/tags/*)
      [[ "$fault" != ref-transport ]] || return 18
      printf 'ref\n' >> /fixture/refs
      tag=${url##*/}
      x=aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa
      [[ "$tag" != v2.3.3 ]] || x=eeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeee
      body="{\"ref\":\"refs/tags/$tag\",\"object\":{\"type\":\"tag\",\"sha\":\"$x\"}}"
      ;;
    */git/tags/*)
      x=bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb
      [[ "${url##*/}" != eeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeee ]] || x=dddddddddddddddddddddddddddddddddddddddd
      if [[ "$fault" == retag && $(wc -l < /fixture/refs) -gt 1 ]]; then x=cccccccccccccccccccccccccccccccccccccccc; fi
      body="{\"object\":{\"type\":\"commit\",\"sha\":\"$x\"}}"
      [[ "$fault" != peel-cycle ]] || body='{"object":{"type":"tag","sha":"aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"}}'
      ;;
    *'/_/api/config')
      printf '%s\n' "$url" >> /fixture/health-urls
      [[ ! -e /fixture/expected-health-url || "$url" == "$(cat /fixture/expected-health-url)" ]] || return 7
      [[ "$fault" != health && "$fault" != incomplete-restore ]] || return 22
      # Model the HTTP boundary using the actually published identity files.
      # This is not native application acceptance; the compiler remains modeled.
      tag=$(cat /opt/globnotes/VERSION)
      revision=$(sed -n 's/^GLOBNOTES_REVISION="\([0-9a-f]*\)"$/\1/p' /opt/globnotes/runtime/release.env)
      [[ "$fault" != identity ]] || revision=aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa
      body=$(jq -cn --arg version "$tag" --arg revision "$revision" '{version:$version,revision:$revision}')
      ;;
    *denoland/deno/releases*)
      x=$(cat /fixture/pin 2>/dev/null || printf 2.9.6)
      body="{\"tag_name\":\"v$x\",\"draft\":false,\"prerelease\":false,\"assets\":[{\"browser_download_url\":\"https://fixture.invalid/v$x/deno-x86_64-unknown-linux-gnu.zip\"}]}"
      ;;
    *alexindigo/globnotes/releases*)
      tag=${url##*/}
      [[ "$tag" != latest ]] || tag=v2.4.0
      release_id=240
      [[ "$tag" != v2.3.3 ]] || release_id=233
      [[ "$tag" != v2.2 ]] || release_id=400760129
      printf '%s\n' "$url" >> /fixture/selections
      body="{\"id\":$release_id,\"published_at\":\"2026-10-01T00:00:00Z\",\"url\":\"https://api.github.com/repos/alexindigo/globnotes/releases/$release_id\",\"tag_name\":\"$tag\",\"draft\":false,\"prerelease\":false,\"assets\":[]}"
      [[ "$fault" != synthesized ]] || body="{\"tag_name\":\"$tag\",\"draft\":false,\"prerelease\":false,\"assets\":[]}"
      [[ "$fault" != prerelease ]] || body=${body/\"prerelease\":false/\"prerelease\":true}
      [[ "$fault" != bad-url ]] || body=${body/releases\/$release_id/releases\/999}
      [[ "$fault" != unpublished ]] || body=${body/2026-10-01T00:00:00Z/}
      [[ "$fault" != string-id ]] || body=${body/\"id\":$release_id/\"id\":\"$release_id\"}
      ;;
    *) printf 'unexpected curl %s\n' "$url" >&2; return 97 ;;
  esac
  if [[ -n "$out" ]]; then printf '%s' "$body" > "$out"; else printf '%s' "$body"; fi
  [[ -z "$format" ]] || printf 200
  return 0
}
curl_download() {
  printf '%s|%s|%s\n' "$2" "$HOME" "${var_appversion:-}" >> /fixture/downloads
  [[ "$(cat /fixture/fault)" != download ]] || return 18
  if [[ "$2" == *.zip ]]; then
    cp /fixture/deno.zip "$1"
  else
    tar -czf "$1" -C /fixture/archive source
  fi
}
systemd-run() { [[ "$(cat /fixture/fault)" != env-probe ]] || return 79; cat /fixture/configured.env0; }
stat() { [[ "$(cat /fixture/fault)" != stat-producer ]] || return 81; command stat "$@"; }
systemctl() {
  printf '%s\n' "$*" >> /fixture/services
  local fault state status
  fault=$(cat /fixture/fault)
  state=$(cat /fixture/state)
  case "$*" in
    *MainPID*)
      if [[ "$fault" == stopped-pid && "$state" != active ]]; then printf '42\n'
      elif [[ "$state" == active && -f /fixture/pid ]]; then cat /fixture/pid; else printf '0\n'; fi ;;
    *ControlGroup*)
      if [[ "$state" == active && -f /fixture/pid ]]; then cut -d: -f3 "/proc/$(cat /fixture/pid)/cgroup"
      elif [[ "$fault" == remaining-writer ]]; then printf '/fixture-writers\n'
      else printf '\n'; fi ;;
    *ActiveState*) printf '%s\n' "$state" ;;
    *SubState*) if [[ "$state" == active ]]; then printf running; else printf dead; fi ;;
    *is-active*) [[ "$state" == active ]] ;;
    stop*)
      if [[ -f /fixture/pid ]]; then
        kill "$(cat /fixture/pid)" 2>/dev/null || true
        wait "$(cat /fixture/pid)" 2>/dev/null || true
        command rm -f /fixture/pid
      fi
      case "$fault" in still-active) printf 'active\n' ;; stopped-failed) printf 'failed\n' ;; *) printf 'inactive\n' ;; esac > /fixture/state
      touch /fixture/stopped ;;
    start*|*--now*)
      [[ "$fault" != start || -e /fixture/start-failed ]] || { touch /fixture/start-failed; return 73; }
      printf 'active\n' > /fixture/state
      {
        for path in /opt/globnotes/runtime/dependency-lock /opt/globnotes/runtime/dependency-lock/deno.lock /opt/globnotes /opt/globnotes/runtime /opt/globnotes/runtime/deno /opt/globnotes/runtime/release.env /opt/globnotes/deno.lock; do
          status=0; runuser -u globnotes -- test -w "$path" || status=$?
          printf '%s=%s\n' "$path" "$status"
        done
      } > /fixture/runtime-access
      ;;
    *) return 0 ;;
  esac
}
mv() {
  case "$(cat /fixture/fault):${*: -1}" in
    publish:/opt/globnotes) [[ -e /fixture/publish-failed ]] || { touch /fixture/publish-failed; return 74; } ;;
    cache-publish:/var/cache/globnotes) [[ -e /fixture/cache-publish-failed ]] || { touch /fixture/cache-publish-failed; return 78; } ;;
    marker:/root/.globnotes) return 75 ;;
  esac
  if [[ "$(cat /fixture/fault)" == incomplete-restore && "$*" == *retired-code* && "${*: -1}" == /opt/globnotes ]]; then return 80; fi
  command mv "$@"
}
rm() {
  if [[ "$(cat /fixture/fault)" == cleanup && "$*" == *retired* ]]; then return 76; fi
  command rm "$@"
}
export STD=''
printf '%s\n' "${var_appversion-unset}" >> /fixture/invocations
MODELS
  cat > "$c/root/fixture/launch" << 'LAUNCH'
#!/usr/bin/env bash
set -euo pipefail
run_cold_bundle() {
  local invocation_env=()
  [[ ! -e /fixture/invocation-pin ]] || invocation_env+=("var_appversion=$(cat /fixture/invocation-pin)")
  env -i PATH="$PATH" HOME=/root TMPDIR=/work/tmp LOCAL_IP=192.0.2.1 BUILD_LOG=/fixture/framework.log \
    DEBUG_LOGFILE=/fixture/error.log "${invocation_env[@]}" bash "$1"
}
if [[ -e /fixture/execute-persistent-update ]]; then
  # Execute the actual bundle baked in the initial host context, not a newly
  # generated hook which could accidentally lose the initial install input.
  run_cold_bundle /fixture/persistent-update
  exit $?
fi
source /source/misc/bundle.func
sed '/^source <(curl/,$d' /fixture/subject > /fixture/hooks
[[ ! -e /fixture/host-install-pin ]] || var_appversion=$(cat /fixture/host-install-pin)
source /fixture/hooks
APP=Globnotes NSAPP=globnotes REPO_BASE=offline SESSION_ID=globnotes-proof
var_lxc_tmpdir=/work/tmp
var_lxc_globnotes_index_path=$(cat /fixture/index-input)
mkdir -p /fixture/libs
cp /source/misc/{core,error_handler,install,tools,github}.func /fixture/libs/
# Only hook execution, never the node's full container setup pipeline.
role=$(cat /fixture/role)
if [[ "$role" == update ]]; then
  pipeline='source /fixture/models; source /fixture/start-running; run_update_script --clean'
  [[ ! -e /fixture/no-force ]] || pipeline='source /fixture/models; source /fixture/start-running; run_update_script'
else
  pipeline='source /fixture/models; install_script'
  [[ ! -e /fixture/conditional ]] || pipeline='source /fixture/models; if install_script; then exit 0; else exit $?; fi'
fi
_write_bundle "$role" "${role}_script" /fixture/libs "$pipeline" > /fixture/bundle
cp /fixture/bundle /fixture/baked-bundle
if [[ -e /fixture/persist-update ]]; then
  _write_bundle update update_script /fixture/libs 'source /fixture/models; source /fixture/start-running; run_update_script' > /fixture/persistent-update
fi
# Inputs are baked, not inherited through the execution environment.
run_cold_bundle /fixture/bundle
LAUNCH
  printf '\n' > "$c/root/fixture/index-input"
  printf 'GLOBNOTES_HOST=0.0.0.0\0GLOBNOTES_PORT=80\0GLOBNOTES_PATH=/var/lib/globnotes/notes\0DENO_DIR=/var/cache/globnotes\0' > "$c/root/fixture/configured.env0"
  # ZIP construction is tooling, not a fake release/deployment helper.
  python3 - "$c/root/fixture" << 'PY'
import pathlib, sys, zipfile
p = pathlib.Path(sys.argv[1])
with zipfile.ZipFile(p / 'deno.zip', 'w') as z:
    z.write(p / 'deno', 'deno')
PY
}

run_case() {
  rc=0
  timeout --signal=TERM --kill-after=5 35 unshare --mount --pid --fork bash "$0" --namespace "$c" > "$c/output" 2>&1 || rc=$?
}

runtime_lock_contract() {
  local label=$1 app="$c/root/opt/globnotes"
  check "$(test -f "$app/runtime/dependency-lock/deno.lock" && cmp -s "$app/deno.lock" "$app/runtime/dependency-lock/deno.lock" && printf same || printf missing-or-changed)" same "$label runtime lock is exact released seed"
  check "$(stat -c '%u:%a' "$app/runtime/dependency-lock" 2> /dev/null || true)" 60123:750 "$label private writable lock directory"
  check "$(stat -c '%u:%a' "$app/runtime/dependency-lock/deno.lock" 2> /dev/null || true)" 60123:600 "$label initial runtime lock permissions"
  check "$(grep -c -- '--lock=/opt/globnotes/runtime/dependency-lock/deno.lock' "$c/root/etc/systemd/system/globnotes.service" || true)" 1 "$label unit selects absolute runtime lock"
  check "$(cat "$c/root/fixture/runtime-access" 2> /dev/null || true)" $'/opt/globnotes/runtime/dependency-lock=0\n/opt/globnotes/runtime/dependency-lock/deno.lock=0\n/opt/globnotes=1\n/opt/globnotes/runtime=1\n/opt/globnotes/runtime/deno=1\n/opt/globnotes/runtime/release.env=1\n/opt/globnotes/deno.lock=1' "$label native nonroot access is narrowly bounded"
  check "$(sha256sum "$app/deno.lock" | cut -d ' ' -f1)" "$(cut -d ' ' -f1 "$app/runtime/released-lock.sha256" 2> /dev/null || true)" "$label released lock hash recorded"
}

if [[ "${1:-}" == --runtime-lock-only ]]; then
  make_case lock-install
  run_case
  check "$rc" 0 'runtime lock cold install status'
  runtime_lock_contract install
  seed=$c
  make_case lock-update
  cp -a "$seed/root/opt/globnotes" "$c/root/opt/"
  cp -a "$seed/root/var/lib/globnotes" "$c/root/var/lib/"
  cp -a "$seed/root/var/cache/globnotes" "$c/root/var/cache/"
  cp -a "$seed/root/etc/globnotes/env" "$c/root/etc/globnotes/"
  cp -a "$seed/root/etc/systemd/system/globnotes.service" "$c/root/etc/systemd/system/"
  mkdir -p "$c/root/opt/globnotes-builds"
  printf '2.3.3\n' > "$c/root/root/.globnotes"
  printf 'update\n' > "$c/root/fixture/role"
  run_case
  check "$rc" 0 'runtime lock cold update status'
  runtime_lock_contract update
  for role in install update; do
    make_case "lock-mutate-$role"
    if [[ "$role" == update ]]; then
      cp -a "$seed/root/opt/globnotes" "$c/root/opt/"
      cp -a "$seed/root/var/lib/globnotes" "$c/root/var/lib/"
      cp -a "$seed/root/var/cache/globnotes" "$c/root/var/cache/"
      cp -a "$seed/root/etc/globnotes/env" "$c/root/etc/globnotes/"
      cp -a "$seed/root/etc/systemd/system/globnotes.service" "$c/root/etc/systemd/system/"
      mkdir -p "$c/root/opt/globnotes-builds"
      printf '2.3.3\n' > "$c/root/root/.globnotes"
      printf 'update\n' > "$c/root/fixture/role"
    fi
    printf 'lock-mutate\n' > "$c/root/fixture/fault"
    run_case
    check "$rc" 250 "$role refuses changed released lock after build"
  done
  printf 'FAILURES %s\n' "$failures"
  [[ "$failures" == 0 ]]
  exit
fi

# Establish positive consumer contracts before negative fault assertions. The
# obsolete baseline must fail these, never be implemented as a legacy branch.
for flavor in default separate literals root-level; do
  make_case "install-$flavor"
  state=/var/lib/globnotes/notes/.globnotes
  if [[ "$flavor" == separate ]]; then state='/var/lib/globnotes/app state'; fi
  if [[ "$flavor" == literals ]]; then state='/var/lib/globnotes/a "quote" \ $dollar `tick` # %'; fi
  if [[ "$flavor" == root-level ]]; then state=/globnotes-state; fi
  [[ "$flavor" == default ]] || printf '%s\n' "$state" > "$c/root/fixture/index-input"
  run_case
  check "$rc" 0 "cold install/$flavor native-Deno hook status"
  check "$(test -x "$c/root/opt/globnotes/runtime/deno" && printf yes || printf no)" yes "$flavor source-pinned runtime is published"
  check "$(test -d "$c/root$state" && printf yes || printf no)" yes "$flavor persistent state directory reaches filesystem"
  if [[ "$rc" == 0 ]]; then
    # Native parser consumes exactly the bytes generated by the actual hook.
    systemd-run --quiet --wait --pipe --collect --property=User=nobody \
      --property="EnvironmentFile=$c/root/etc/globnotes/env" \
      --property="EnvironmentFile=$c/root/opt/globnotes/runtime/release.env" /usr/bin/env -0 > "$c/decoded.env0"
    decoded=$(tr '\0' '\n' < "$c/decoded.env0" | grep '^GLOBNOTES_INDEX_PATH=' || true)
    if [[ "$flavor" == default ]]; then check "$decoded" '' 'default leaves app-native state default unset'; else check "$decoded" "GLOBNOTES_INDEX_PATH=$state" "$flavor actual systemd literal decoding"; fi
    check "$(tr '\0' '\n' < "$c/decoded.env0" | grep '^GLOBNOTES_PATH=')" 'GLOBNOTES_PATH=/var/lib/globnotes/notes' "$flavor native probe retains first EnvironmentFile"
    check "$(tr '\0' '\n' < "$c/decoded.env0" | grep '^GLOBNOTES_PORT=')" 'GLOBNOTES_PORT=80' "$flavor fresh standard-port choice remains explicit"
    check "$(tr '\0' '\n' < "$c/decoded.env0" | grep '^GLOBNOTES_REVISION=')" 'GLOBNOTES_REVISION=bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb' "$flavor native probe loads generated revision last"
    check "$(cat "$c/root/root/.globnotes")" 2.4.0 "$flavor installed marker follows health"
    check "$(stat -c %u "$c/root/opt/globnotes/server/main.ts")" 0 "$flavor service cannot own code"
    check "$(stat -c %u "$c/root/opt/globnotes/client/dist/index.html")" 60123 "$flavor HTML stamping permission"
    check "$(stat -c %u "$c/root/opt/globnotes/node_modules")" 60123 "$flavor automatic dependency materialization permission"
    check "$(stat -c %u "$c/root/var/cache/globnotes")" 60123 "$flavor cache ownership"
    runtime_lock_contract "$flavor"
    check "$(grep -c '^declare -- var_lxc_globnotes_index_path=' "$c/root/fixture/baked-bundle")" 1 "$flavor override declaration is baked into real bundle"
    check "$(grep -c 'v2.9.6/deno-' "$c/root/fixture/downloads")" 1 "$flavor app override does not override dependency pin"
    check "$(test -e "$c/root/root/.deno" && printf leaked || printf isolated)" isolated "$flavor Deno helper marker stays in private HOME"
    [[ "$flavor" != default ]] || seed=$c
  fi
done

make_case canonical-code-alias
ln -s /opt/globnotes "$c/root/alias"
printf '/alias/state\n' > "$c/root/fixture/index-input"
run_case
check "$rc" 65 'canonical existing-ancestor alias into replaceable code rejected'
check "$(test -e "$c/root/fixture/apt" && printf reached || printf untouched)" untouched 'canonical alias validation precedes effects'

if [[ "${1:-}" == --baseline && -z "${seed:-}" ]]; then
  saved_subject=$subject
  subject="$ROOT/scripts/lxc/globnotes.sh"
  make_case baseline-native-seed
  run_case
  check "$rc" 0 'native reference seed for obsolete update-hook RED controls'
  [[ "$rc" != 0 ]] || seed=$c
  subject=$saved_subject
fi

# Reject unsafe roots before account/package/configuration effects.
for invalid in relative / /var/lib/globnotes/notes /var/lib/globnotes/notes/visible /opt/globnotes/state /var/cache/globnotes/state /etc/globnotes/state /opt/globnotes-builds/state $'/var/lib/bad\npath'; do
  make_case "invalid-$RANDOM"
  printf '%s\n' "$invalid" > "$c/root/fixture/index-input"
  run_case
  check "$rc" 65 "invalid state <$invalid> fails before effects"
  check "$(test -e "$c/root/fixture/apt" && printf reached || printf untouched)" untouched 'invalid input never reaches package boundary'
done

for fault in synthesized prerelease bad-url unpublished string-id transport ref-transport peel-cycle retag download dependency build lock-mutate; do
  make_case "install-fault-$fault"
  printf '%s\n' "$fault" > "$c/root/fixture/fault"
  run_case
  expected=250
  case "$fault" in transport | ref-transport) expected=18 ;; dependency) expected=71 ;; build) expected=72 ;; esac
  check "$rc" "$expected" "fresh/$fault exact checked failure"
  check "$(test -e "$c/root/root/.globnotes" && printf advanced || printf absent)" absent "fresh/$fault never advances real installed marker"
  check "$(test -e "$c/root/opt/globnotes" && printf published || printf absent)" absent "fresh/$fault never publishes failed source"
done

if [[ -n "${seed:-}" ]]; then
  current_case() {
    make_case "$1"
    cp -a "$seed/root/opt/globnotes" "$c/root/opt/"
    cp -a "$seed/root/var/lib/globnotes" "$c/root/var/lib/"
    cp -a "$seed/root/var/cache/globnotes" "$c/root/var/cache/"
    cp -a "$seed/root/etc/globnotes/env" "$c/root/etc/globnotes/"
    cp -a "$seed/root/etc/systemd/system/globnotes.service" "$c/root/etc/systemd/system/"
    mkdir -p "$c/root/opt/globnotes-builds/unknown-prior" "$c/root/var/cache/globnotes.retired.unknown"
    printf 'unknown evidence\n' > "$c/root/opt/globnotes-builds/unknown-prior/proof"
    printf 'plugin-only import\n' > "$c/root/var/cache/globnotes/plugin-import"
    printf 'old mutable metadata\n' > "$c/root/var/cache/globnotes/meta"
    printf 'old hidden source\n' > "$c/root/opt/globnotes/.obsolete-hidden"
    printf 'old endpoint\n' > "$c/root/opt/globnotes/server/deleted-endpoint.ts"
    printf '2.3.3\n' > "$c/root/opt/globnotes/VERSION"
    printf '2.3.3\n' > "$c/root/root/.globnotes"
    printf 'GLOBNOTES_REVISION="dddddddddddddddddddddddddddddddddddddddd"\n' > "$c/root/opt/globnotes/runtime/release.env"
    printf '{"priorPluginIntegrity":"retained"}\n' > "$c/root/opt/globnotes/runtime/dependency-lock/deno.lock"
    printf 'update\n' > "$c/root/fixture/role"
    mkdir -p "$c/source-before" "$c/cache-before"
    cp -a "$c/root/opt/globnotes/." "$c/source-before/"
    cp -a "$c/root/var/cache/globnotes/." "$c/cache-before/"
    cp -a "$c/root/etc/globnotes/env" "$c/env-before"
    cp -a "$c/root/root/.globnotes" "$c/marker-before"
  }
  preserved() {
    check "$(diff -qr "$c/source-before" "$c/root/opt/globnotes" > /dev/null && printf same || printf changed)" same "$1 byte-correct complete old source/runtime/generated env"
    check "$(diff -qr "$c/cache-before" "$c/root/var/cache/globnotes" > /dev/null && printf same || printf changed)" same "$1 old cache is isolated from failed build"
    check "$(cmp -s "$c/marker-before" "$c/root/root/.globnotes" && printf same || printf changed)" same "$1 truthful old installed marker"
    check "$(cmp -s "$c/env-before" "$c/root/etc/globnotes/env" && printf same || printf changed)" same "$1 operator env byte preservation"
    check "$(cat "$c/root/opt/globnotes/runtime/dependency-lock/deno.lock")" '{"priorPluginIntegrity":"retained"}' "$1 rollback includes prior runtime lock"
  }
  make_case initial-choice-lifetime
  printf 'v2.3.3\n' > "$c/root/fixture/host-install-pin"
  rm "$c/root/fixture/invocation-pin"
  printf '2.3.3\n' > "$c/root/fixture/archive/source/VERSION"
  touch "$c/root/fixture/persist-update"
  run_case
  check "$rc" 0 'cold initial install honors host var_appversion v2.3.3'
  check "$(cat "$c/root/root/.globnotes")" 2.3.3 'initial version is installed, not a rewritten marker fixture'
  check "$(grep -c '^declare -- var_lxc_globnotes_initial_release=v2.3.3$' "$c/root/fixture/persistent-update")" 1 'initial-only release choice has an explicit baked name'
  update_bundle_before=$(sha256sum "$c/root/fixture/persistent-update")
  touch "$c/root/fixture/execute-persistent-update"
  printf '2.4.0\n' > "$c/root/fixture/archive/source/VERSION"
  # This lifetime control uses a stopped service between invocations; running
  # process validation has its own real-exec-environment controls below.
  printf 'inactive\n' > "$c/root/fixture/state"
  run_case
  check "$rc" 0 'plain cold update succeeds without a current invocation pin'
  check "$(cat "$c/root/root/.globnotes")" 2.4.0 'initial v2.3.3 choice does not pin later latest v2.4.0 update'
  check "$(cat "$c/root/opt/globnotes/VERSION")" 2.4.0 'plain update publishes actual latest source bytes'
  mapfile -t invocation_values < "$c/root/fixture/invocations"
  check "${invocation_values[-1]}" unset 'plain update env-i contains no var_appversion override'
  printf 'v2.3.3\n' > "$c/root/fixture/invocation-pin"
  printf '2.3.3\n' > "$c/root/fixture/archive/source/VERSION"
  printf 'inactive\n' > "$c/root/fixture/state"
  run_case
  check "$rc" 0 'current invocation can explicitly select v2.3.3'
  check "$(cat "$c/root/opt/globnotes/VERSION")" 2.3.3 'explicit invocation selects the requested source version'
  check "$(grep -c 'v2.9.6/deno-' "$c/root/fixture/downloads")" 3 'initial, latest and explicit app choices keep the independent Deno pin'
  rm "$c/root/fixture/invocation-pin"
  printf '2.4.0\n' > "$c/root/fixture/archive/source/VERSION"
  printf 'inactive\n' > "$c/root/fixture/state"
  run_case
  check "$rc" 0 'subsequent unpinned invocation returns to latest'
  check "$(cat "$c/root/root/.globnotes")" 2.4.0 'explicit prior invocation does not become a permanent update pin'
  check "$(sha256sum "$c/root/fixture/persistent-update")" "$update_bundle_before" 'all update invocations use identical originally baked bundle bytes'

  # v2.2 is a genuine published stable two-part tag. These are version-shape
  # controls with a native-layout source fixture, not historical v2.2 install
  # compatibility: that old payload does not contain the current VERSION file.
  for role in install update; do
    for version_contract in exact mismatch prerelease; do
      if [[ "$role" == install ]]; then make_case "$role-two-part-$version_contract"; else current_case "$role-two-part-$version_contract"; fi
      printf 'v2.2\n' > "$c/root/fixture/invocation-pin"
      printf '2.2\n' > "$c/root/fixture/archive/source/VERSION"
      [[ "$version_contract" != mismatch ]] || printf '2.2.0\n' > "$c/root/fixture/archive/source/VERSION"
      [[ "$version_contract" != prerelease ]] || printf 'prerelease\n' > "$c/root/fixture/fault"
      run_case
      if [[ "$version_contract" == exact ]]; then
        check "$rc" 0 "$role accepts genuinely stable v2.2 tag shape with exact VERSION2.2"
        check "$(cat "$c/root/root/.globnotes" 2> /dev/null || true)" 2.2 "$role two-part release reaches installed marker consumer"
        check "$(cat "$c/root/opt/globnotes/VERSION" 2> /dev/null || true)" 2.2 "$role preserves exact two-part source VERSION"
      else
        check "$rc" 250 "$role two-part $version_contract remains rejected"
        [[ "$role" != update ]] || preserved "two-part $version_contract"
      fi
    done
  done

  current_case absent-effective-port
  sed -i '/^GLOBNOTES_PORT=/d' "$c/root/etc/globnotes/env"
  cp "$c/root/etc/globnotes/env" "$c/env-before"
  systemd-run --quiet --wait --pipe --collect --property=User=nobody \
    --property="EnvironmentFile=$c/root/etc/globnotes/env" /usr/bin/env -0 > "$c/root/fixture/configured.env0"
  check "$(tr '\0' '\n' < "$c/root/fixture/configured.env0" | grep -c '^GLOBNOTES_PORT=' || true)" 0 'native effective configuration really omits PORT'
  printf 'http://127.0.0.1:8080/_/api/config\n' > "$c/root/fixture/expected-health-url"
  run_case
  check "$rc" 0 'absent effective PORT health uses the app8080 default'
  check "$(sort -u "$c/root/fixture/health-urls")" 'http://127.0.0.1:8080/_/api/config' 'health probes only actual default8080 listener when PORT is absent'
  check "$(cat "$c/root/root/.globnotes")" 2.4.0 'app-default listener health permits truthful marker advancement'
  check "$(cmp -s "$c/env-before" "$c/root/etc/globnotes/env" && printf same || printf changed)" same 'updater does not inject fresh-install PORT80 into operator config'

  for quiescence in remaining-writer stopped-pid still-active stopped-failed; do
    current_case "quiescence-$quiescence"
    printf '%s\n' "$quiescence" > "$c/root/fixture/fault"
    run_case
    if [[ "$quiescence" == stopped-failed ]]; then
      check "$rc" 0 'failed unit with MainPID0 and empty group is quiescent'
      check "$(cat "$c/root/root/.globnotes")" 2.4.0 'empty failed-unit group permits validated publication'
    else
      check "$rc" 75 "$quiescence blocks publication after stop"
      check "$(test -e "$c/root/fixture/builds" && printf built || printf untouched)" untouched "$quiescence never starts cache-writing build"
      preserved "$quiescence"
    fi
  done
  for fault in none dependency build lock-mutate publish cache-publish start health identity marker cleanup retag synthesized bad-url unpublished string-id transport ref-transport peel-cycle env-probe stat-producer; do
    current_case "update-$fault"
    printf '%s\n' "$fault" > "$c/root/fixture/fault"
    run_case
    expected=0
    case "$fault" in dependency) expected=71 ;; build) expected=72 ;; publish) expected=74 ;; cache-publish) expected=78 ;; start) expected=73 ;; health | identity) expected=22 ;; marker) expected=75 ;; cleanup) expected=76 ;; retag | synthesized | bad-url | unpublished | string-id | peel-cycle | lock-mutate) expected=250 ;; transport | ref-transport) expected=18 ;; env-probe) expected=79 ;; stat-producer) expected=81 ;; esac
    check "$rc" "$expected" "cold update/$fault exact status"
    if [[ "$fault" == none || "$fault" == cleanup ]]; then
      runtime_lock_contract "update-$fault"
      check "$(cat "$c/root/root/.globnotes")" 2.4.0 "$fault successful publication advances marker"
      check "$(cat "$c/root/var/cache/globnotes/plugin-import")" 'plugin-only import' "$fault complete old plugin import cache survives build/publication"
      check "$(test -e "$c/root/opt/globnotes/.obsolete-hidden" && printf stale || printf absent)" absent "$fault hidden obsolete source removed"
      check "$(test -e "$c/root/opt/globnotes/server/deleted-endpoint.ts" && printf stale || printf absent)" absent "$fault deleted endpoint removed"
      check "$(cat "$c/root/fixture/state")" inactive "$fault prior stopped service restored after health"
      if [[ "$fault" == none ]]; then
        check "$(find "$c/root/opt/globnotes-builds" -mindepth 1 -maxdepth 1 -type d | wc -l)" 1 'health+marker immediately retire only this operation code/stage'
        check "$(find "$c/root/var/cache" -maxdepth 1 -name 'globnotes.retired.*' | wc -l)" 1 'health+marker immediately retire only this operation cache'
      else
        check "$(test -e "$c/root/var/lib/scripts-underground/update-pending/globnotes" && printf pending || printf cleared)" pending 'cleanup failure remains pending after healthy marker publication'
      fi
    else
      preserved "$fault"
      check "$(test -e "$c/root/var/lib/scripts-underground/update-pending/globnotes" && printf pending || printf cleared)" pending "$fault failed hook retains real framework pending flag"
    fi
    check "$(cat "$c/root/opt/globnotes-builds/unknown-prior/proof")" 'unknown evidence' "$fault unknown prior stages preserved"
  done

  current_case incomplete-restore
  printf 'incomplete-restore\n' > "$c/root/fixture/fault"
  run_case
  check "$rc" 22 'incomplete restore retains original health failure status'
  recovery=$(find "$c/root/opt/globnotes-builds" -mindepth 2 -maxdepth 2 -type d -name retired-code)
  check "$(test -n "$recovery" && diff -qr "$c/source-before" "$recovery" > /dev/null && printf same || printf lost)" same 'incomplete restore retains byte-correct old code/runtime recovery tree'
  [[ -z "$recovery" ]] || check "$(stat -c %a "${recovery%/*}/configured.env0")" 600 'retained complete environment probe is root-private after builder traversal'
  check "$(grep -c 'recovery incomplete (80)' "$c/output")" 1 'incomplete restore reports concrete failure and recovery locations'
  check "$(test -e "$c/root/var/lib/scripts-underground/update-pending/globnotes" && printf pending || printf cleared)" pending 'incomplete recovery is never success'

  for invalid in /var/lib/globnotes/notes /var/lib/globnotes/notes/visible /opt/globnotes/state /var/cache/globnotes/state /etc/globnotes/state /opt/globnotes-builds/state; do
    current_case "update-invalid-$RANDOM"
    printf 'GLOBNOTES_INDEX_PATH=%s\0' "$invalid" >> "$c/root/fixture/configured.env0"
    run_case
    check "$rc" 65 "cold update rejects overlapping state <$invalid>"
    check "$(test -e "$c/root/fixture/stopped" && printf stopped || printf untouched)" untouched 'invalid update roots never stop service'
    preserved 'update root validation'
  done

  for role in install update; do
    for source_fault in version pin-mismatch pin-ambiguous runtime-collision; do
      if [[ "$role" == update ]]; then current_case "$role-source-$source_fault"; else make_case "$role-source-$source_fault"; fi
      case "$source_fault" in
        version) printf '9.9.9\n' > "$c/root/fixture/archive/source/VERSION" ;;
        pin-mismatch) sed -i s/alpine-2.9.6/alpine-2.9.7/ "$c/root/fixture/archive/source/Dockerfile" ;;
        pin-ambiguous) printf 'FROM denoland/deno:latest\n' >> "$c/root/fixture/archive/source/Dockerfile" ;;
        runtime-collision) mkdir "$c/root/fixture/archive/source/runtime" ;;
      esac
      run_case
      expected=65
      [[ "$source_fault" != version ]] || expected=250
      check "$rc" "$expected" "$role/$source_fault selected-source contract fails closed"
      check "$(test -e "$c/root/fixture/stopped" && printf stopped || printf untouched)" untouched "$role/$source_fault validation before service stop"
      [[ "$role" != update ]] || preserved "$source_fault"
    done
  done

  # A real exec environment supplies the prior roots; only service control is
  # modeled. The old process and cache writer must be gone before cache copy.
  for running_fault in none health mismatch; do
    current_case "running-$running_fault"
    cp /usr/bin/bash "$c/root/opt/globnotes/runtime/deno"
    cp /usr/bin/bash "$c/source-before/runtime/deno"
    touch "$c/root/fixture/was-active"
    cp "$c/root/fixture/configured.env0" "$c/root/fixture/running.env0"
    if [[ "$running_fault" == mismatch ]]; then
      printf 'GLOBNOTES_INDEX_PATH=/var/lib/globnotes/unapplied\0' >> "$c/root/fixture/configured.env0"
    else printf '%s\n' "$running_fault" > "$c/root/fixture/fault"; fi
    run_case
    expected=0
    [[ "$running_fault" != health ]] || expected=22
    [[ "$running_fault" != mismatch ]] || expected=65
    check "$rc" "$expected" "prior-running/$running_fault status"
    if [[ "$running_fault" == mismatch ]]; then
      check "$(test -e "$c/root/fixture/stopped" && printf stopped || printf untouched)" untouched 'unapplied roots report before stopping'
      preserved mismatch
    else
      check "$(cat "$c/root/fixture/state")" active "$running_fault prior running state restored"
      [[ "$running_fault" != health ]] || preserved running-health
    fi
  done

  for mode in noop pending; do
    current_case "$mode"
    printf '2.4.0\n' > "$c/root/opt/globnotes/VERSION"
    printf '2.4.0\n' > "$c/root/root/.globnotes"
    printf 'GLOBNOTES_REVISION="bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb"\n' > "$c/root/opt/globnotes/runtime/release.env"
    cp -a "$c/root/opt/globnotes/." "$c/source-before/"
    cp -a "$c/root/root/.globnotes" "$c/marker-before"
    touch "$c/root/fixture/no-force"
    if [[ "$mode" == pending ]]; then
      mkdir -p "$c/root/var/lib/scripts-underground/update-pending"
      touch "$c/root/var/lib/scripts-underground/update-pending/globnotes"
    fi
    run_case
    check "$rc" 0 "$mode real framework update status"
    if [[ "$mode" == noop ]]; then
      check "$(test -e "$c/root/fixture/stopped" && printf stopped || printf untouched)" untouched 'no-op never stops service'
      check "$(test -e "$c/root/fixture/builds" && printf built || printf untouched)" untouched 'no-op never rebuilds'
      preserved noop
    else
      check "$(test -e "$c/root/fixture/builds" && printf built || printf untouched)" built 'real pending retry forces redeploy of same version'
    fi
    check "$(test -e "$c/root/var/lib/scripts-underground/update-pending/globnotes" && printf pending || printf cleared)" cleared "$mode success clears pending"
  done

  for pin_fault in none build; do
    current_case "pin-transition-$pin_fault"
    printf '%s\n' "$pin_fault" > "$c/root/fixture/fault"
    printf '2.9.7\n' > "$c/root/fixture/pin"
    sed -i s/2.9.6/2.9.7/g "$c/root/fixture/archive/source/Dockerfile"
    run_case
    if [[ "$pin_fault" == none ]]; then
      check "$rc" 0 'selected-source changed Deno pin publishes new runtime'
      check "$(grep -c 'v2.9.7/deno-' "$c/root/fixture/downloads")" 1 'runtime request follows changed source pin'
    else
      check "$rc" 72 'changed Deno pin build failure status'
      preserved pin-transition
    fi
  done

  current_case custom-effective-environment
  state='/var/lib/globnotes/state "quote" \ $dollar `tick` # %'
  cache='/var/cache/globnotes effective cache'
  mkdir -p "$c/root$state"
  printf 'protected state\n' > "$c/root$state/config.json"
  mv "$c/root/var/cache/globnotes" "$c/root$cache"
  # This fixture file is an operator input, written in systemd syntax. The
  # actual parser, not the focused systemd-run model, produces the consumed env.
  printf '%s\n' 'GLOBNOTES_HOST="0.0.0.0"' 'GLOBNOTES_PORT="8088"' 'GLOBNOTES_PATH_PREFIX="/my-notes"' \
    'GLOBNOTES_PATH="/var/lib/globnotes/notes"' 'DENO_DIR="/var/cache/globnotes effective cache"' \
    'GLOBNOTES_INDEX_PATH="/var/lib/globnotes/state \"quote\" \\ \$dollar \`tick\` # %"' > "$c/root/etc/globnotes/env"
  cp "$c/root/etc/globnotes/env" "$c/env-before"
  systemd-run --quiet --wait --pipe --collect --property=User=nobody \
    --property="EnvironmentFile=$c/root/etc/globnotes/env" /usr/bin/env -0 > "$c/root/fixture/configured.env0"
  run_case
  check "$rc" 0 'custom env update consumes native systemd parsed roots'
  check "$(cat "$c/root$cache/plugin-import")" 'plugin-only import' 'effective custom cache is copied, not assumed default'
  check "$(cat "$c/root$state/config.json")" 'protected state' 'literal custom persistent state untouched by publication'
  check "$(cat "$c/root/fixture/health-urls")" 'http://127.0.0.1:8088/my-notes/_/api/config' 'health uses effective host port and prefix'
  check "$(cmp -s "$c/env-before" "$c/root/etc/globnotes/env" && printf same || printf changed)" same 'update never rewrites literal operator environment'
fi

for permission in usable denied; do
  make_case "existing-$permission"
  mkdir -p "$c/root/var/lib/globnotes/notes"
  printf 'existing notes\n' > "$c/root/var/lib/globnotes/notes/existing.md"
  chmod 755 "$c/root/var/lib/globnotes" "$c/root/var/lib/globnotes/notes"
  if [[ "$permission" == usable ]]; then chown 60123:60123 "$c/root/var/lib/globnotes/notes"; fi
  before=$(stat -c '%u:%g:%a' "$c/root/var/lib/globnotes/notes")
  run_case
  if [[ "$permission" == usable ]]; then check "$rc" 0 'existing writable notes accepted'; else check "$rc" 77 'existing unwritable notes rejected with access diagnostic'; fi
  check "$(stat -c '%u:%g:%a' "$c/root/var/lib/globnotes/notes")" "$before" "$permission existing notes directory mode/owner preserved"
  check "$(stat -c %u "$c/root/var/lib/globnotes/notes/existing.md")" 0 "$permission existing note owner never recursively changed"
done
make_case conditional-unit-write
touch "$c/root/fixture/conditional"
ln -s /dev/full "$c/root/etc/systemd/system/globnotes.service"
run_case
check "$rc" 1 'conditional cold install propagates actual ENOSPC unit-file write'
check "$(test -e "$c/root/root/.globnotes" && printf advanced || printf absent)" absent 'unit write failure never advances marker'
check "$(test -e "$c/root/fixture/services" && printf reached || printf untouched)" untouched 'failed unit producer never starts service'
printf '%s failure(s); real cold bundles/release helpers/filesystem; compiler and services modeled\n' "$failures"
[[ "$failures" == 0 ]]
