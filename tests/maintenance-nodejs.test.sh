#!/usr/bin/env bash
# Actual setup_nodejs/download_gpg_key/cache paths; external package/crypto/network
# commands modeled inside private disk-backed mounts, including deleted cwd.
set -euo pipefail
systemd-detect-virt --vm --quiet || exit 1
: "${TMPDIR:?disk-backed TMPDIR required}"
ROOT=$(realpath "$(dirname "${BASH_SOURCE[0]}")/..")
if [[ "${1:-}" == --child ]]; then
  mount --bind "$CASE_ROOT/opt" /opt
  mount --bind "$CASE_ROOT/apt" /etc/apt
  mount --bind "$CASE_ROOT/cache" /var/cache
  source "$ROOT/misc/core.func"
  source "$ROOT/misc/tools.func"
  load_functions
  msg_info() { :; }
  msg_ok() { :; }
  msg_warn() { printf '%s\n' "$*" >> "$CASE_ROOT/warnings"; }
  debug_log() { :; }
  cleanup_legacy_install() { :; }
  is_tool_installed() { printf '22\n'; }
  ensure_apt_working() { printf 'apt-refresh\n' >> "$CASE_ROOT/calls"; }
  apt-get() { printf 'upgrade-key=%s\n' "$(cat /etc/apt/keyrings/nodesource.gpg)" >> "$CASE_ROOT/calls"; }
  curl() {
    local out=''
    while (($#)); do
      case "$1" in -o)
        out="$2"
        shift
        ;;
      esac
      shift
    done
    printf 'key-fetch\n' >> "$CASE_ROOT/calls"
    [[ "$KEY_FAULT" != yes ]] || return 7
    printf 'refreshed key\n' > "$out"
  }
  gpg() {
    # Crypto is modeled in this ordering fixture; the dedicated key suite uses
    # real GPG. Accept only this model's complete key at the validation boundary.
    if [[ " $* " == *' --show-keys '* ]]; then
      grep -qx 'refreshed key' "${@: -1}"
      return $?
    fi
    while [[ "$1" != -o ]]; do shift; done
    cat > "$2"
  }
  npm() {
    local cwd
    cwd=$(pwd -P 2> /dev/null) || cwd=missing
    printf 'npm-cwd=%s args=%s\n' "$cwd" "$*" >> "$CASE_ROOT/calls"
    [[ "$1" != list ]] || return 1
    return 0
  }
  sleep() { :; }
  mkdir -p "$CASE_ROOT/deleted"
  cd "$CASE_ROOT/deleted"
  rmdir "$CASE_ROOT/deleted"
  NODE_VERSION=22 NODE_MODULE='yarn@1.22.22,pnpm' CURL_RETRIES=1 setup_nodejs
  exit 0
fi
case "$(realpath -e "$TMPDIR")" in /tmp | /tmp/*) exit 1 ;; esac
case "$(findmnt -rn -T "$TMPDIR" -o FSTYPE)" in '' | tmpfs | ramfs) exit 1 ;; esac
work=$(mktemp -d "$TMPDIR/maintenance-node.XXXXXX")
trap 'rm -rf -- "$work"' EXIT
failures=0
check() { if [[ "$1" == "$2" ]]; then printf 'PASS %s\n' "$3"; else
  printf 'FAIL %s: expected <%s>, got <%s>\n' "$3" "$2" "$1" >&2
  failures=$((failures + 1))
fi; }
for mode in no yes; do
  for fault in no yes; do
    c="$work/$mode-$fault"
    mkdir -p "$c/opt" "$c/apt/keyrings" "$c/cache" "$c/tmp"
    printf 'old key\n' > "$c/apt/keyrings/nodesource.gpg"
    rc=0
    env -i PATH="$PATH" TMPDIR="$c/tmp" CASE_ROOT="$c" KEY_FAULT="$fault" VERBOSE="$mode" BUILD_LOG="$c/log" \
      unshare -m --propagation private -- bash "$0" --child > "$c/output" 2>&1 || rc=$?
    check "$rc" 0 "$mode/key-fault-$fault setup outcome"
    check "$(grep -c '^key-fetch$' "$c/calls" || true)" 1 "$mode/$fault actual key helper invoked once"
    if [[ "$fault" == no ]]; then
      check "$(cat "$c/apt/keyrings/nodesource.gpg")" 'refreshed key' "$mode fresh bytes reach keyring consumer"
      check "$(grep -c '^upgrade-key=refreshed key$' "$c/calls" || true)" 1 "$mode upgrade sees refreshed key"
      check "$(
        python3 - "$c/calls" << 'PY'
import pathlib,sys
rows=pathlib.Path(sys.argv[1]).read_text().splitlines();print('yes' if 'key-fetch' in rows and rows.index('key-fetch')<rows.index('apt-refresh') else 'no')
PY
      )" yes "$mode refresh precedes apt metadata"
    else
      check "$(cat "$c/apt/keyrings/nodesource.gpg")" 'old key' "$mode failed refresh retains prior key"
      check "$(grep -c 'Could not refresh.*NodeSource' "$c/warnings" 2> /dev/null || true)" 1 "$mode failed refresh reports noncritical warning"
    fi
    check "$(grep -c '^npm-cwd=missing' "$c/calls" || true)" 0 "$mode/$fault npm never runs in deleted cwd"
    check "$(grep -c 'npm-cwd=/opt args=install -g npm@11.11.0' "$c/calls" || true)" 1 "$mode/$fault existing npm pin retained"
    check "$(grep -c 'install -g yarn@1.22.22' "$c/calls" || true)" 1 "$mode/$fault requested module pin retained"
    check "$(grep -c 'install -g pnpm@\^10' "$c/calls" || true)" 1 "$mode/$fault existing pnpm major retained"
  done
done
printf '%s failure(s); actual helpers/files/order/cwd, external commands modeled\n' "$failures"
[[ "$failures" == 0 ]]
