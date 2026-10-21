#!/usr/bin/env bash
# Actual setup/parser/cache/install consumer; downloaded uv artifacts/network are
# modeled, extraction and selected executable bytes are real private files.
set -euo pipefail
systemd-detect-virt --vm --quiet || exit 1
: "${TMPDIR:?disk-backed TMPDIR required}"
ROOT=$(realpath "$(dirname "${BASH_SOURCE[0]}")/..")
if [[ "${1:-}" == --child ]]; then
  mount --bind "$CASE_ROOT/bin" /usr/local/bin
  mount --bind "$CASE_ROOT/cache" /var/cache
  cp /etc/os-release "$CASE_ROOT/etc/os-release"
  cp -a /etc/alternatives/awk "$CASE_ROOT/etc/alternatives/awk"
  mount --bind "$CASE_ROOT/etc" /etc
  mount --bind "$CASE_ROOT/share" /usr/share
  [[ "$(awk 'BEGIN { print "ready" }')" == ready ]]
  source "$ROOT/misc/tools.func"
  export HOME="$CASE_ROOT/home" STD=''
  msg_info() { :; }
  msg_ok() { :; }
  msg_warn() { :; }
  msg_error() { printf '%s\n' "$*" >&2; }
  ensure_dependencies() { :; }
  ensure_usr_local_bin_persist() { :; }
  getent() { return 0; }
  sleep() { :; }
  get_latest_github_release() {
    printf 'latest\n' >> "$CASE_ROOT/calls"
    printf '0.13.1\n'
  }
  curl() {
    local out='' url=''
    while (($#)); do
      case "$1" in -o)
        out="$2"
        shift
        ;;
      https:*) url="$1" ;; esac
      shift
    done
    printf '%s\n' "$url" >> "$CASE_ROOT/calls"
    if [[ "$url" == *'&page=2' && -f "$CASE_ROOT/releases-page2.json" ]]; then
      cp "$CASE_ROOT/releases-page2.json" "$out"
      [[ "${SECOND_PAGE_FAULT:-0}" == 0 ]] || {
        printf '200'
        return 18
      }
    else cp "$CASE_ROOT/releases.json" "$out"; fi
    printf '200'
    return "$LOOKUP_FAULT"
  }
  curl_with_retry() {
    local v="${1#*/download/}"
    v=${v%%/*}
    printf '%s\n' "$v" > "$CASE_ROOT/selected"
    mkdir -p "$CASE_ROOT/artifact/uv-fixture"
    printf '#!/bin/sh\nif [ "$1" = --version ]; then printf "uv %s\\n"; fi\n' "$v" > "$CASE_ROOT/artifact/uv-fixture/uv"
    chmod 0755 "$CASE_ROOT/artifact/uv-fixture/uv"
    tar -czf "$2" -C "$CASE_ROOT/artifact" uv-fixture
  }
  setup_uv
  /usr/local/bin/uv --version > "$CASE_ROOT/consumer"
  exit 0
fi
case "$(realpath -e "$TMPDIR")" in /tmp | /tmp/*) exit 1 ;; esac
case "$(findmnt -rn -T "$TMPDIR" -o FSTYPE)" in '' | tmpfs | ramfs) exit 1 ;; esac
work=$(mktemp -d "$TMPDIR/maintenance-uvrange.XXXXXX")
trap 'rm -rf -- "$work"' EXIT
failures=0
check() { if [[ "$1" == "$2" ]]; then printf 'PASS %s\n' "$3"; else
  printf 'FAIL %s: expected <%s>, got <%s>\n' "$3" "$2" "$1" >&2
  failures=$((failures + 1))
fi; }
specs=('>=0.12.15, <0.13' '~=0.12.15' '<0.12.15' '>=0.12.15,<0.13,!=0.12.24' '>9.0' '>=0.12 || <0.13' '==0.12.13' '>=0.12.15,<0.13' '>=0.12.15,<0.13' '~=0.12' '<=0.12.23' '>0.12.23,<=0.12.24' '>=0.12.15,' '>=0.12.15,<0.13,!=0.12.24,!=0.12.23' '>=0.11,<0.12' '>=0.11,<0.12')
versions=(0.12.24 0.12.24 0.12.14 0.12.23 none none 0.12.13 none 0.11.9 0.13.1 0.12.23 0.12.24 none none 0.11.9 none)
statuses=(0 0 0 0 250 65 0 18 0 0 0 0 65 250 0 18)
for i in "${!specs[@]}"; do
  c="$work/$i"
  mkdir -p "$c"/{bin,cache,home,project,tmp,etc/bash_completion.d,etc/alternatives,share/zsh/site-functions}
  printf "[project]\nrequired-version = '==9.9.9'\n[tool.uv] # correct section\nrequired-version = '%s' # range\n" "${specs[$i]}" > "$c/project/pyproject.toml"
  printf '[{"tag_name":"0.13.1","draft":false,"prerelease":false},{"tag_name":"0.12.23","draft":false,"prerelease":false},{"tag_name":"0.12.24","draft":false,"prerelease":false},{"tag_name":"0.12.14","draft":false,"prerelease":false},{"tag_name":"0.12.99rc1","draft":false,"prerelease":true},{"tag_name":"0.12.98","draft":true,"prerelease":false}]\n' > "$c/releases.json"
  if [[ "$i" -ge 14 ]]; then
    python3 - "$c/releases.json" << 'PY'
import json,pathlib,sys
pathlib.Path(sys.argv[1]).write_text(json.dumps([{'tag_name':f'0.13.{i}','draft':False,'prerelease':False} for i in range(100)]))
PY
    printf '[{"tag_name":"0.11.9","draft":false,"prerelease":false}]\n' > "$c/releases-page2.json"
  fi
  lookup=0 override=''
  [[ "$i" != 7 ]] || lookup=18
  [[ "$i" != 8 ]] || override=0.11.9
  second_fault=0
  [[ "$i" != 15 ]] || second_fault=18
  rc=0
  env -i PATH="$PATH" TMPDIR="$c/tmp" CASE_ROOT="$c" LOOKUP_FAULT="$lookup" SECOND_PAGE_FAULT="$second_fault" UV_VERSION="$override" UV_PROJECT_DIR="$c/project" \
    unshare -m --propagation private -- bash "$0" --child > "$c/output" 2>&1 || rc=$?
  check "$rc" "${statuses[$i]}" "case-$i actual setup status"
  if [[ "${versions[$i]}" != none ]]; then
    check "$(cat "$c/consumer" 2> /dev/null || true)" "uv ${versions[$i]}" "case-$i installed executable observes compatible version"
    check "$(cat "$c/cache/app-versions/uv_version.txt" 2> /dev/null || true)" "${versions[$i]}" "case-$i cache records same selection"
  else
    check "$(test -e "$c/consumer" && printf reached || printf absent)" absent "case-$i incompatible latest never reaches consumer"
  fi
done
source "$ROOT/misc/tools.func"
mkdir -p "$work/parse"
printf '[tool.uv]\nrequired-version = "==9.9.9"\n' > "$work/parse/pyproject.toml"
printf 'required-version = "==0.12.13" # preferred\n' > "$work/parse/uv.toml"
check "$(_uv_required_version "$work/parse")" 0.12.13 'exact compatibility wrapper retains precedence/quotes'
printf 'required-version = ">=0.12.13,<0.13"\n' > "$work/parse/uv.toml"
rc=0
_uv_required_version "$work/parse" > /dev/null || rc=$?
check "$rc" 1 'range remains non-exact through compatibility wrapper'
printf 'python-preference = "managed"\n' > "$work/parse/uv.toml"
rc=0
_uv_required_version "$work/parse" > /dev/null || rc=$?
check "$rc" 1 'uv.toml without requirement masks pyproject requirement'
for value in '"==0.12.13" # comment' "'==0.12.13'" 0.12.13; do
  printf 'required-version = %s\n' "$value" > "$work/parse/uv.toml"
  check "$(_uv_required_version "$work/parse")" 0.12.13 "exact wrapper preserves $value"
done
printf '%s failure(s); actual helper/install outcomes, external release artifacts modeled\n' "$failures"
[[ "$failures" == 0 ]]
