#!/usr/bin/env bash
# Runs ONLY under the owner's unshare --mount. Broker stays outside this namespace.
set -euo pipefail
root=$1
shift
export SU_TEST_SOURCE_ROOT="$root"
mount --make-rprivate /
for tool in /usr/sbin/pct /usr/sbin/pvesm /usr/bin/pveam /usr/bin/lxc-attach; do
  test -f "$tool"
  mount --bind "$root/tests/lib/native-command.py" "$tool"
done
mount --bind /tmp /tmp
mount -o remount,bind,ro /tmp
umask 022
exec "$@"
