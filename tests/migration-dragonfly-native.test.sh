#!/usr/bin/env bash
# Actual published package, cold bundles, service and authenticated RESP consumer.
set -euo pipefail
python3 -B "$(dirname -- "${BASH_SOURCE[0]}")/lib/entrypoint.py" migration-dragonfly-native "$@" || exit $?
[[ "${SU_TEST_GUARD_ONLY:-0}" != 1 ]] || exit 0
ROOT=$(realpath "$(dirname "${BASH_SOURCE[0]}")/..")
: "${TMPDIR:?disk-backed receiver TMPDIR required}"
[[ "$EUID" == 0 && "$TMPDIR" == /var/lib/scripts-underground-test/tmp ]] || exit 65
case "$(findmnt -rn -T "$TMPDIR" -o FSTYPE)" in '' | tmpfs | ramfs) exit 65 ;; esac
work=$(mktemp -d "$TMPDIR/dragonfly-native.XXXXXXXX")
printf 'NATIVE_EVIDENCE %s\n' "$work"
native_evidence_exit() {
  local status=$? capture=0
  trap - EXIT
  if [[ -d "$work" ]]; then
    journalctl -u dragonfly --no-pager > "$work/journal.log" 2>&1 || capture=$?
    tar -czf "$work.evidence.tar.gz" -C "$work" . || capture=$?
    if [[ "$capture" == 0 ]]; then
      printf 'DRAGONFLY_NATIVE_EVIDENCE_TGZ_SHA256 '
      sha256sum "$work.evidence.tar.gz" || capture=$?
      printf 'DRAGONFLY_NATIVE_EVIDENCE_TGZ_BASE64 '
      base64 -w0 "$work.evidence.tar.gz" || capture=$?
      printf '\n'
    fi
  fi
  [[ "$status" != 0 ]] || status=$capture
  exit "$status"
}
trap native_evidence_exit EXIT
[[ ! -e /etc/dragonfly && ! -e /usr/bin/dragonfly && ! -e /var/lib/dragonfly ]] || exit 65
publisher=$REPO_BASE
curl() { :; }
source "$ROOT/scripts/lxc/dragonfly.sh"
unset -f curl
source "$ROOT/misc/bundle.func"
export APP=Dragonfly NSAPP=dragonfly REPO_BASE="$publisher" var_lxc_tmpdir="$TMPDIR" var_appversion=v2.1
_write_bundle install install_script "$ROOT/misc" 'install_script' > "$work/install.sh"
_write_bundle update update_script "$ROOT/misc" --script-id dragonfly -- --requirements "$var_cpu" "$var_ram" -- 'run_update_script "$@"' > "$work/update.sh"
grep -Fx 'declare -- LXC_SCRIPT_ID=dragonfly' "$work/update.sh"
grep -Fx 'declare -- LXC_REQUIRED_CPU=2' "$work/update.sh"
grep -Fx 'declare -- LXC_REQUIRED_RAM=1024' "$work/update.sh"
timeout --signal=TERM --kill-after=30 600 bash "$work/install.sh" > "$work/install.log" 2>&1
install -m 0755 "$work/update.sh" /usr/local/sbin/update
ln -s /usr/local/sbin/update /usr/bin/update
python3 -B "$ROOT/tests/lib/dragonfly_native.py" "$work"
