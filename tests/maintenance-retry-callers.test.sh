#!/usr/bin/env bash
# Actual Frigate/Immich hook retry fragments; dependency commands are models.
set -euo pipefail
systemd-detect-virt --vm --quiet || exit 1
: "${TMPDIR:?disk TMPDIR required}"
ROOT=$(realpath "$(dirname "${BASH_SOURCE[0]}")/..")
work=$(mktemp -d "$TMPDIR/retry-callers.XXXXXX")
trap 'rm -rf -- "$work"' EXIT
python3 - "$ROOT" "$work" << 'PY'
import pathlib,re,sys
root,out=map(pathlib.Path,sys.argv[1:]);text=(root/'scripts/lxc/frigate.sh').read_text();start=text.index('  for i in {1..3}; do',text.index('Building Python Wheels'));end=text.index('  NODE_VERSION=',start);(out/'frigate').write_text(text[start:end])
text=(root/'scripts/lxc/immich.sh').read_text();loops=list(re.finditer(r'(?m)^([ ]*)for attempt in (?:\$\(seq 1 3\)|1 2 3); do\n',text));assert len(loops)==8,len(loops)
for i,m in enumerate(loops):
 end=re.search(r'(?m)^'+re.escape(m[1])+r'done\s*$',text[m.end():]);assert end
 (out/f'immich-{i}').write_text(text[m.start():m.end()+end.end()]+'\n')
PY
failures=0
check() {
  if [[ "$1" == "$2" ]]; then printf 'PASS %s\n' "$3"; else
    printf 'FAIL %s expected <%s>, got <%s>\n' "$3" "$2" "$1" >&2
    failures=$((failures + 1))
  fi
}
for fragment in frigate immich-{0..7}; do
  for mode in no yes; do
    for outcome in retry exhausted; do
      c="$work/$fragment-$mode-$outcome"
      mkdir "$c"
      printf 0 > "$c/attempts"
      cat > "$c/run" << 'SH'
set -euo pipefail
source "$ROOT/misc/core.func"
source "$ROOT/misc/error_handler.func"
load_functions
catch_errors
msg_ok() { printf 'SUCCESS %s\n' "$*" >> "$CASE_DIR/events"; }
msg_warn() { :; }; msg_error() { printf 'ERROR %s\n' "$*" >> "$CASE_DIR/events"; }
sleep() { :; }
model_command() {
  local n
  n=$(< "$CASE_DIR/attempts"); n=$((n + 1)); printf '%s' "$n" > "$CASE_DIR/attempts"
  [[ "$OUTCOME" == retry && "$n" == 3 ]] && return 0
  return 47
}
pip3() { model_command; }
sudo() { model_command; }
ML_PYTHON=python3.13 VIRTUAL_ENV="$CASE_DIR/venv" UV_HTTP_TIMEOUT=300
source "$FRAGMENT"
printf continued > "$CASE_DIR/continued"
SH
      rc=0
      env ROOT="$ROOT" FRAGMENT="$work/$fragment" CASE_DIR="$c" OUTCOME="$outcome" TMPDIR="$TMPDIR" HOME="$c" VERBOSE="$mode" BUILD_LOG="$c/build.log" DEBUG_LOGFILE="$c/error.log" \
        bash "$c/run" > "$c/output" 2>&1 || rc=$?
      expected=0
      [[ "$outcome" != exhausted ]] || expected=47
      check "$rc" "$expected" "$fragment/$mode/$outcome exact final command status"
      check "$(< "$c/attempts")" 3 "$fragment/$mode/$outcome all three attempts reached"
      if [[ "$outcome" == exhausted ]]; then
        check "$(test -e "$c/continued" && printf false-success || printf stopped)" stopped "$fragment/$mode exhaustion never continues"
        successes=0
        [[ ! -f "$c/events" ]] || successes=$(grep -c '^SUCCESS' "$c/events" || true)
        check "$successes" 0 "$fragment/$mode exhaustion never reports build success"
      else
        check "$(cat "$c/continued" 2> /dev/null || true)" continued "$fragment/$mode reachable recovery continues"
      fi
    done
  done
done
printf '%s failure(s); native hook fragments/statuses; wheel/Python/ML commands modeled\n' "$failures"
[[ "$failures" == 0 ]]
