#!/usr/bin/env bash
# Native tar/zstd/filesystem/update owner; network/build/service commands modeled.
set -euo pipefail
systemd-detect-virt --vm --quiet || exit 1
: "${TMPDIR:?}" "${MAINTENANCE_NEXT_REFERENCES:?}"
ROOT=$(realpath "$(dirname "${BASH_SOURCE[0]}")/..")
if [[ "${1:-}" == --child ]]; then
  c="$CASE_DIR"
  mount --bind "$c/opt" /opt
  mount --bind "$c/cache" /var/cache
  mount --bind "$c/state" /var/lib/scripts-underground/update-pending
  source "$ROOT/misc/core.func"
  source "$ROOT/misc/error_handler.func"
  source "$ROOT/misc/tools.func"
  load_functions
  source "$c/hook"
  header_info() { :; }
  check_container_storage() { :; }
  check_container_resources() { :; }
  cleanup_lxc() { :; }
  ensure_dependencies() { :; }
  setup_nodejs() { :; }
  systemctl() { printf '%s\n' "$*" >> "$c/services"; }
  check_for_gh_release() {
    [[ "$FAULT" != metadata ]] || return 37
    return 0
  }
  pnpm() { [[ "$FAULT" != build ]] || return 52; }
  curl() {
    local out='' format='' url=''
    while (($#)); do
      case "$1" in -o)
        out="$2"
        shift
        ;;
      -w)
        format="$2"
        shift
        ;;
      https:*) url="$1" ;; esac
      shift
    done
    if [[ "$url" == *raw.githubusercontent.com* ]]; then
      cat "$MAINTENANCE_NEXT_REFERENCES/zigbee2mqtt/package.json"
      return 0
    fi
    if [[ -n "$out" ]]; then printf '{"tag_name":"2.14.2","assets":[]}' > "$out"; else printf '{"tag_name":"2.14.2","assets":[]}'; fi
    [[ -z "$format" ]] || printf 200
  }
  curl_download() {
    [[ "$FAULT" != download ]] || return 22
    command tar -czf "$1" -C "$c" payload
  }
  tar() {
    if [[ "$FAULT" == source && "$*" == '-cf - -C /opt zigbee2mqtt' ]]; then
      command tar "$@"
      return 42
    fi
    command tar "$@"
  }
  zstd() {
    [[ "$FAULT" != sink ]] || return 53
    command zstd "$@"
  }
  cp() {
    if [[ "$FAULT" == copy && "${!#}" == /opt/zigbee2mqtt* && "$*" == *'/deploy-source.'* ]]; then
      command cp -a -- "$3" "${!#}"
      return 41
    fi
    command cp "$@"
  }
  catch_errors
  run_update_script
  exit
fi
work=$(mktemp -d "$TMPDIR/zigbee-native.XXXXXX")
trap 'rm -rf -- "$work"' EXIT
failures=0
check() { if [[ "$1" == "$2" ]]; then printf 'PASS %s\n' "$3"; else
  printf 'FAIL %s expected <%s>, got <%s>\n' "$3" "$2" "$1" >&2
  failures=$((failures + 1))
fi; }
for mode in no yes; do
  for fault in none source sink download copy build metadata; do
    c="$work/$mode-$fault"
    mkdir -p "$c/"{opt/zigbee2mqtt/data,home,cache,state,payload/data}
    printf '2.14.2\n' > "$c/home/.zigbee2mqtt"
    printf 'USER serial and MQTT secret\n' > "$c/opt/zigbee2mqtt/data/configuration.yaml"
    printf 'USER coordinator database\n' > "$c/opt/zigbee2mqtt/data/database.db"
    printf 'USER backup before update\n' > "$c/opt/zigbee2mqtt/code"
    cp "$MAINTENANCE_NEXT_REFERENCES/zigbee2mqtt/package.json" "$c/payload/package.json"
    cp "$MAINTENANCE_NEXT_REFERENCES/zigbee2mqtt/pnpm-workspace.yaml" "$c/payload/pnpm-workspace.yaml"
    printf 'UPSTREAM config default\n' > "$c/payload/data/configuration.yaml"
    printf 'new code\n' > "$c/payload/code"
    python3 - "$ROOT/scripts/lxc/zigbee2mqtt.sh" "$c" << 'PY'
import pathlib,subprocess,sys
p,c=map(pathlib.Path,sys.argv[1:]);text=subprocess.check_output(['bash','-c','curl() { :; }; source "$1"; declare -f update_script','cold',str(p)],text=True);(c/'hook').write_text(text)
PY
    rc=0
    env CASE_DIR="$c" FAULT="$fault" MAINTENANCE_NEXT_REFERENCES="$MAINTENANCE_NEXT_REFERENCES" TMPDIR="$TMPDIR" HOME="$c/home" APP=Zigbee2MQTT NSAPP=zigbee2mqtt VERBOSE="$mode" FORCE_DEPLOY=1 UPDATE_FORCE=1 BUILD_LOG="$c/build.log" DEBUG_LOGFILE="$c/errors.log" \
      unshare -m --propagation private -- bash "$0" --child > "$c/output" 2>&1 || rc=$?
    expected=0
    case "$fault" in source) expected=42 ;; sink) expected=53 ;; download) expected=250 ;; copy) expected=252 ;; build) expected=52 ;; metadata) expected=37 ;; esac
    check "$rc" "$expected" "zigbee/$mode/$fault exact cold-hook status"
    if [[ "$expected" != 0 ]]; then check "$(test -f "$c/state/zigbee2mqtt" && printf retained || printf lost)" retained "zigbee/$mode/$fault failed update retains pending truth"; fi
    check "$(cat "$c/opt/zigbee2mqtt/data/configuration.yaml" 2> /dev/null || true)" 'USER serial and MQTT secret' "zigbee/$mode/$fault settings retained"
    check "$(cat "$c/opt/zigbee2mqtt/data/database.db" 2> /dev/null || true)" 'USER coordinator database' "zigbee/$mode/$fault data retained"
    if [[ "$fault" == source || "$fault" == sink ]]; then
      count=$(
        python3 - "$c/opt/backups" << 'PY'
import pathlib,sys
print(len(list(pathlib.Path(sys.argv[1]).glob('*.tar.zst'))))
PY
      )
      check "$count" 0 "zigbee/$mode/$fault only owned partial backup removed"
    fi
    if [[ "$fault" == none ]]; then
      status=0
      python3 - "$c/opt/backups" << 'PY' || status=$?
import io,pathlib,subprocess,sys,tarfile
files=list(pathlib.Path(sys.argv[1]).glob('*.tar.zst'));assert len(files)==1
data=subprocess.check_output(['zstd','-dc',str(files[0])]);archive=tarfile.open(fileobj=io.BytesIO(data));assert archive.extractfile('zigbee2mqtt/data/configuration.yaml').read()==b'USER serial and MQTT secret\n'
PY
      check "$status" 0 "zigbee/$mode real decompression yields actual saved settings"
      rc=0
      env CASE_DIR="$c" FAULT=none MAINTENANCE_NEXT_REFERENCES="$MAINTENANCE_NEXT_REFERENCES" TMPDIR="$TMPDIR" HOME="$c/home" APP=Zigbee2MQTT NSAPP=zigbee2mqtt VERBOSE="$mode" FORCE_DEPLOY=1 UPDATE_FORCE=1 BUILD_LOG="$c/build.log" DEBUG_LOGFILE="$c/errors.log" \
        unshare -m --propagation private -- bash "$0" --child > "$c/repeated-output" 2>&1 || rc=$?
      check "$rc" 0 "zigbee/$mode repeated same-version backup succeeds"
      status=0
      python3 - "$c/opt/backups" << 'PY' || status=$?
import io,pathlib,subprocess,sys,tarfile
files=list(pathlib.Path(sys.argv[1]).glob('*.tar.zst'));assert len(files)==2
for p in files:
 data=subprocess.check_output(['zstd','-dc',str(p)]);archive=tarfile.open(fileobj=io.BytesIO(data));assert archive.extractfile('zigbee2mqtt/data/database.db').read()==b'USER coordinator database\n'
PY
      check "$status" 0 "zigbee/$mode both unique same-version archives retain native data"
    fi
    rm -rf -- "$c"
  done
done
printf '%s failure(s); native tar/zstd/files/pending owner; network/build/services modeled\n' "$failures"
[[ "$failures" == 0 ]]
