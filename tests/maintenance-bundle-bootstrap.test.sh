#!/usr/bin/env bash
# The install bootstrap must not replace already inlined framework/error handlers.
# Network responses model the actual deployed baseline; cache/state paths in the
# core subject are mapped to a disk fixture. The bootstrap itself is unmodified.
set -euo pipefail
systemd-detect-virt --vm --quiet || exit 1
: "${TMPDIR:?provide a disk-backed temporary directory}"
case "$(realpath -e "$TMPDIR")" in /tmp | /tmp/*) exit 1 ;; esac
case "$(findmnt -rn -T "$TMPDIR" -o FSTYPE)" in '' | tmpfs | ramfs) exit 1 ;; esac
ROOT=$(realpath "$(dirname "${BASH_SOURCE[0]}")/..")
if [[ "${1:-}" == --child ]]; then
  source "$FIXTURE/core.func"
  source "$ROOT/misc/error_handler.func"
  get_lxc_ip() { :; }
  curl() {
    printf '%s\n' "${!#}" >> "$FIXTURE/fetches"
    case "${!#}" in
      */core.func) cat "$FIXTURE/old-core.func" ;;
      */error_handler.func) cat "$FIXTURE/old-error.func" ;;
      *) return 97 ;;
    esac
  }
  source "$ROOT/misc/install.func"
  stop_spinner() { :; }
  msg_info() { printf 'cleanup\n' >> "$FIXTURE/events"; }
  msg_ok() { :; }
  msg_warn() { :; }
  apt-get() { :; }
  pip() { :; }
  uv() { :; }
  npm() { :; }
  yarn() { :; }
  pnpm() { :; }
  go() { :; }
  cargo() { :; }
  gem() { :; }
  composer() { :; }
  update_script() { exit 0; }
  run_update_script
fi
work=$(mktemp -d "$TMPDIR/maintenance-bundle-bootstrap.XXXXXX")
trap 'rm -rf -- "$work"' EXIT
mkdir -p "$work/home/.cache/pip" "$work/tmp" "$work/vartmp" "$work/state"
printf 'cached\n' > "$work/home/.cache/pip/proof"
: > "$work/fetches"
: > "$work/events"
git -C "$ROOT" show 59149630ec9f1805295f1d01f43ba5cbafe4b77a:misc/core.func > "$work/old-core.func"
git -C "$ROOT" show 59149630ec9f1805295f1d01f43ba5cbafe4b77a:misc/error_handler.func > "$work/old-error.func"
sed -e 's|/var/lib/scripts-underground/update-pending|${FIXTURE}/state|g' \
  -e 's|/var/tmp|${FIXTURE}/vartmp|g' -e 's|/tmp|${FIXTURE}/tmp|g' -e 's|/root|${FIXTURE}/home|g' \
  "$ROOT/misc/core.func" > "$work/core.func"
rc=0
timeout --signal=TERM --kill-after=5s 25s env -i PATH="$PATH" FIXTURE="$work" \
  TMPDIR="$work/tmp" HOME="$work/home" BUILD_LOG="$work/active.log" DEBUG_LOGFILE="$work/error.log" \
  NSAPP=bootstrap-probe APP=BootstrapProbe DEV_MODE_KEEP=true REPO_BASE=https://fixture.invalid \
  bash "$0" --child > "$work/output" 2>&1 || rc=$?
failures=0
check() {
  if [[ "$1" == "$2" ]]; then printf 'PASS %s\n' "$3"; else
    printf 'FAIL %s: expected <%s>, got <%s>\n' "$3" "$2" "$1" >&2
    failures=$((failures + 1))
  fi
}
check "$rc" 0 'actual update hook success exits zero after install bootstrap'
[[ "$rc" == 0 ]] || cat "$work/output" >&2
check "$(wc -l < "$work/fetches")" 0 'inlined core/error APIs require no remote framework fetch'
check "$(grep -c '^cleanup$' "$work/events" || true)" 1 'actual inlined EXIT handler owns success-exit cleanup once'
check "$(test -e "$work/home/.cache/pip/proof" && printf present || printf absent)" absent 'consumer observes cache cleanup after the real install bootstrap'
check "$(test -e "$work/state/bootstrap-probe" && printf present || printf absent)" absent 'actual success clears its owned pending flag'
printf '%s failure(s); filesystem literals mapped, remote baseline response modeled\n' "$failures"
[[ "$failures" == 0 ]]
