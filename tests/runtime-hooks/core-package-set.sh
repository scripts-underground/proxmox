#!/usr/bin/env bash
# runtime-hooks-contract: fixture case-asserted
# Real package helper; APT/dpkg are returning models, never host package effects.
set -euo pipefail
ROOT=$(realpath "$(dirname "${BASH_SOURCE[0]}")/../..")
source "$ROOT/misc/tools.func"
export STD=''
msg_warn() { :; }
msg_error() { :; }
sleep() { :; }
dpkg() { :; }
get_os_info() { printf trixie; }
apt-cache() { :; }
apt() {
  if [[ "$1" == update || "$*" == '--fix-broken install -y' ]]; then return 0; fi
  calls=$((calls + 1))
  [[ "$fault" != batch ]] || return 0
  # Only individual requests can succeed after all required-set batches fail.
  [[ "$*" != *Dpkg::Options* ]] || return 46
  case "$fault:$*" in
    all:* | mixed:*server* | single:*) return 47 ;;
  esac
  return 0
}
failures=0
check() {
  if [[ "$1" == "$2" ]]; then printf 'PASS %s\n' "$3"; else
    printf 'FAIL %s: expected <%s>, got <%s>\n' "$3" "$2" "$1" >&2
    failures=$((failures + 1))
  fi
}
for fault in batch individual mixed all single; do
  calls=0 status=0 marker=prior
  packages=(required-server required-client)
  [[ "$fault" != single ]] || packages=(required-server)
  if install_packages_with_retry "${packages[@]}"; then marker=selected; else status=$?; fi
  case "$fault" in
    batch | individual)
      check "$status" 0 "$fault complete required set succeeds"
      check "$marker" selected "$fault consumer publishes after complete installation"
      ;;
    *)
      check "$status" 46 "$fault retains terminal required-set APT failure"
      check "$marker" prior "$fault consumer cannot publish a partial installation"
      ;;
  esac
  [[ "$fault" != batch ]] || check "$calls" 1 'successful batch has no fallback'
done
printf 'RUNTIME_HOOKS_RESULT failures=%s\n' "$failures"
[[ "$failures" == 0 ]]
