#!/usr/bin/env bash
# Actual template/finalization owners; PVE commands are bounded recording models.
set -euo pipefail
ROOT=$(realpath "$(dirname "${BASH_SOURCE[0]}")/../..")
if [[ "${1:-}" == --child ]]; then
  c="$CASE_ROOT"
  source "$ROOT/misc/core.func"
  load_functions
  python3 - "$ROOT/misc/build.func" "$c/functions" "$c" << 'PY'
import pathlib,re,sys
s=pathlib.Path(sys.argv[1]).read_text()
functions=re.findall(r'^(?:_template_[a-z_]+|complete_install)\(\) \{\n.*?^}',s,re.M|re.S)
assert functions
s='\n\n'.join(functions)
s=s.replace('/var/lib/scripts-underground/template-locks',sys.argv[3]+'/template-locks')
s=s.replace('/etc/systemd/system/ping-instances.service',sys.argv[3]+'/ping-instances.service')
pathlib.Path(sys.argv[2]).write_text(s+'\n')
PY
  source "$c/functions"
  msg_info() { :; }
  msg_ok() { printf 'OK %s\n' "$*" >> "$c/messages"; }
  msg_warn() { printf 'WARN %s\n' "$*" >> "$c/messages"; }
  msg_error() { printf 'ERROR %s\n' "$*" >> "$c/messages"; }
  msg_custom() { :; }
  rc=0
  case "$KIND" in
    template)
      export TEMPLATE=debian-13-standard_fixture_amd64.tar.gz TEMPLATE_STORAGE=fixture ONLINE_TEMPLATE=''
      mkdir -p "$c/cache"
      export TEMPLATE_PATH="$c/cache/$TEMPLATE"
      truncate -s 1100000 "$TEMPLATE_PATH"
      cp "$TEMPLATE_PATH" "$c/original"
      _template_resolve_path() { :; }
      _template_catalog_names() {
        printf catalogue >> "$c/effects"
        [[ "$FAULT" != recoverable ]] || printf '%s\n' "$TEMPLATE"
      }
      pveam() {
        case "$1" in
          download)
            printf download >> "$c/effects"
            truncate -s 1100000 "$c/content"
            tar -cf "$TEMPLATE_PATH" -C "$c" content
            ;;
          list) printf 'fixture:vztmpl/%s\n' "$TEMPLATE" ;;
        esac
      }
      _template_prepare_archive initial || rc=$?
      printf '%s' "$rc" > "$c/rc"
      ;;
    finalization)
      export CTID=3191 APP=Probe
      : > "$c/ping-instances.service"
      pct() {
        case "$1" in
          exec) printf '    inet 192.0.2.5/24 scope global eth0\n' ;;
          set)
            printf notes >> "$c/effects"
            [[ "$FAULT" != notes ]] || return 42
            ;;
        esac
      }
      systemctl() {
        printf monitor >> "$c/effects"
        [[ "$FAULT" != monitor ]] || return 43
      }
      execute_optional_hook() {
        printf hook >> "$c/effects"
        [[ "$FAULT" != hook ]] || return 44
      }
      # Normal lifecycle call, not an if-condition suppressing hook errexit.
      complete_install
      printf 0 > "$c/rc"
      ;;
  esac
  exit 0
fi
: "${TMPDIR:?disk TMPDIR required}"
systemd-detect-virt --vm --quiet || exit 65
work=$(mktemp -d "$TMPDIR/core-creation.XXXXXX")
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
  : > "$c/effects"
  : > "$c/messages"
  status=0
  env -i PATH="$PATH" HOME="$c/home" TMPDIR="$TMPDIR" CASE_ROOT="$c" KIND="$KIND" FAULT="$FAULT" \
    BUILD_LOG="$c/build.log" DEBUG_LOGFILE="$c/errors.log" bash "$0" --child > "$c/output" 2>&1 || status=$?
  if [[ -f "$c/rc" ]]; then rc=$(cat "$c/rc"); else rc=$status; fi
}
KIND=template FAULT=unavailable go
check "$((rc != 0))" 1 'corrupt unlisted initial template explicitly refuses'
check "$(cmp -s "$c/original" "$c/cache/debian-13-standard_fixture_amd64.tar.gz" && echo retained || echo lost)" retained 'unrecoverable user-only archive retained'
check "$(grep -c download "$c/effects" || true)" 0 'no recoverable source means no destructive download attempt'
KIND=template FAULT=recoverable go
check "$rc" 0 'exact catalogue source repairs initial corrupt local archive'
check "$(grep -c download "$c/effects" || true)" 1 'recovery downloads through existing archive owner'
check "$(tar -tf "$c/cache/debian-13-standard_fixture_amd64.tar.gz" > /dev/null 2>&1 && echo valid || echo invalid)" valid 'recovery publishes an actually readable archive'
for FAULT in notes monitor hook; do
  KIND=finalization go
  if [[ "$FAULT" == hook ]]; then
    check "$rc" 44 'required post-install hook failure stays fatal and exact'
    check "$(grep -c 'OK Completed Successfully' "$c/messages" || true)" 0 'failed required hook cannot report application success'
  else
    check "$rc" 0 "$FAULT optional failure does not change finished app outcome"
    check "$(grep -c hook "$c/effects" || true)" 1 "$FAULT optional failure does not skip required hook"
    check "$(grep -c WARN "$c/messages" || true)" 1 "$FAULT restoration failure reported rather than claimed successful"
  fi
done
printf 'RUNTIME_HOOKS_RESULT failures=%s\n' "$failures"
[[ "$failures" == 0 ]]
