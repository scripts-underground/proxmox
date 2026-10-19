#!/usr/bin/env bash
# Actual version selection/installer/files/cache consumer; downloaded Go programs
# are tiny modeled artifacts, not a claim that an application compiles or runs.
set -euo pipefail
systemd-detect-virt --vm --quiet || exit 1
: "${TMPDIR:?disk-backed TMPDIR required}"
case "$(findmnt -rn -T "$TMPDIR" -o FSTYPE)" in '' | tmpfs | ramfs) exit 1 ;; esac
ROOT=$(realpath "$(dirname "${BASH_SOURCE[0]}")/..")
if [[ "${1:-}" == --child ]]; then
  c="$GO_CASE"
  mount --bind "$c/local" /usr/local
  source "$ROOT/misc/tools.func"
  export STD=''
  msg_info() { :; }
  msg_ok() { :; }
  msg_error() { printf '%s\n' "$*" >&2; }
  cache_installed_version() { printf '%s\n' "$2" > "$c/cache"; }
  ensure_usr_local_bin_persist() { :; }
  remove_old_tool_version() {
    printf removed >> "$c/removals"
    rm -rf /usr/local/go /usr/local/bin/go
  }
  curl_with_retry() {
    printf '%s\n' "$1" >> "$c/requests"
    if [[ "$1" == *'?mode=json'* ]]; then
      cp "$c/list.json" "$2"
      [[ "$GO_FAULT" != metadata ]] || return 47
    elif [[ "$1" == *VERSION* ]]; then
      printf 'go9.99.0\n'
    else
      [[ "$GO_FAULT" != download ]] || return 48
      version=${1##*/go}
      version=${version%%.linux-*}
      printf '%s\n' "$version" >> "$c/selected"
      mkdir -p "$c/artifact/go/bin"
      printf '#!/usr/bin/env bash\nprintf "go version go%s linux/amd64\\n"\n' "$version" > "$c/artifact/go/bin/go"
      cp "$c/artifact/go/bin/go" "$c/artifact/go/bin/gofmt"
      chmod 0755 "$c/artifact/go/bin/"*
      tar -czf "$2" -C "$c/artifact" go
    fi
  }
  rc=0
  GO_VERSION="$GO_PIN" GO_PROJECT_DIR="$c/source" setup_go || rc=$?
  printf '%s\n' "$rc" > "$c/status"
  if [[ -x /usr/local/bin/go ]]; then /usr/local/bin/go version > "$c/consumer"; fi
  exit
fi
work=$(mktemp -d "$TMPDIR/go-minimum.XXXXXX")
trap 'rm -rf -- "$work"' EXIT
failures=0
check() {
  if [[ "$1" == "$2" ]]; then printf 'PASS %s\n' "$3"; else
    printf 'FAIL %s expected <%s>, got <%s>\n' "$3" "$2" "$1" >&2
    failures=$((failures + 1))
  fi
}
for kind in satisfying newer-major language minimum toolchain toolchain-satisfying legacy legacy-initial explicit malformed duplicate invalid-toolchain metadata invalid-list no-match download; do
  c="$work/$kind"
  mkdir -p "$c/local/bin" "$c/source"
  installed=1.22.0 pin='' fault=none expected=0 wanted=1.26.8
  printf 'module fixture\ngo 1.26.0\n' > "$c/source/go.mod"
  case "$kind" in
    satisfying) installed=1.26.3 wanted=1.26.3 ;;
    newer-major) installed=1.27.2 wanted=1.27.2 ;;
    language) printf 'module fixture\ngo 1.26\n' > "$c/source/go.mod" ;;
    minimum) printf 'module fixture\ngo 1.26.4\n' > "$c/source/go.mod" ;;
    toolchain) printf 'module fixture\ngo 1.25\ntoolchain go1.26.5\n' > "$c/source/go.mod" ;;
    toolchain-satisfying)
      printf 'module fixture\ngo 1.25\ntoolchain go1.26.2\n' > "$c/source/go.mod"
      installed=1.26.3 wanted=1.26.3
      ;;
    legacy | legacy-initial)
      printf 'module fixture\ngo 1.20\n' > "$c/source/go.mod"
      installed=1.18.0 wanted=1.20.14
      [[ "$kind" != legacy-initial ]] || wanted=1.20
      ;;
    explicit)
      printf 'invalid go metadata\n' > "$c/source/go.mod"
      pin=1.19.1 wanted=1.19.1
      ;;
    malformed | duplicate | invalid-toolchain)
      expected=65 wanted="$installed"
      case "$kind" in malformed) printf 'go nope\n' > "$c/source/go.mod" ;; duplicate) printf 'go 1.26\ngo 1.25\n' > "$c/source/go.mod" ;; invalid-toolchain) printf 'go 1.26\ntoolchain go1.27rc1\n' > "$c/source/go.mod" ;; esac
      ;;
    metadata | invalid-list | no-match) fault="$kind" expected=250 wanted="$installed" ;;
    download) fault=download expected=250 wanted="$installed" ;;
  esac
  printf '#!/usr/bin/env bash\nprintf "go version go%s linux/amd64\\n"\n' "$installed" > "$c/local/bin/go"
  chmod 0755 "$c/local/bin/go"
  : > "$c/requests"
  : > "$c/removals"
  python3 - "$c/list.json" "$kind" << 'PY'
import json,pathlib,sys
out=pathlib.Path(sys.argv[1]);kind=sys.argv[2]
versions=['1.27.2','1.26.0','1.26.8','1.26.4','1.26.99rc1','1.20','1.20.14']
if kind=='legacy-initial':versions=['1.20']
if kind=='no-match':versions=['1.27.2']
rows=[{'version':'go'+v,'stable':'rc' not in v,'files':[{'os':'linux','arch':'amd64','kind':'archive'}]} for v in versions]
out.write_text('not-json' if kind=='invalid-list' else json.dumps(rows))
PY
  GO_CASE="$c" GO_PIN="$pin" GO_FAULT="$fault" unshare -m --propagation private -- bash "$0" --child > "$c/output" 2>&1
  check "$(cat "$c/status")" "$expected" "$kind exact helper status"
  check "$(cat "$c/consumer" 2> /dev/null || true)" "go version go$wanted linux/amd64" "$kind installed executable consumer"
  if [[ "$expected" != 0 || "$kind" == satisfying || "$kind" == newer-major || "$kind" == toolchain-satisfying ]]; then
    check "$(stat -c %s "$c/removals")" 0 "$kind preserves prior installation"
  fi
  if [[ "$kind" == satisfying || "$kind" == newer-major || "$kind" == toolchain-satisfying || "$kind" == malformed || "$kind" == duplicate || "$kind" == invalid-toolchain ]]; then
    check "$(stat -c %s "$c/requests")" 0 "$kind needs no network or implicit global latest"
  fi
done
printf '%s failure(s); actual minimum selection/install/files/cache; artifact executables modeled\n' "$failures"
[[ "$failures" == 0 ]]
