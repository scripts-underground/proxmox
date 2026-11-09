#!/usr/bin/env bash
# Cold bundle/helper/filesystem consumers; HTTP/package/service effects modeled.
set -euo pipefail
python3 -B "$(dirname -- "${BASH_SOURCE[0]}")/lib/entrypoint.py" migration-dragonfly "$@" || exit $?
[[ "${SU_TEST_GUARD_ONLY:-0}" != 1 ]] || exit 0
systemd-detect-virt --vm --quiet || exit 65
: "${TMPDIR:?disk-backed TMPDIR required}"
case "$(findmnt -rn -T "$TMPDIR" -o FSTYPE)" in '' | tmpfs | ramfs) exit 65 ;; esac
ROOT=$(realpath "$(dirname "${BASH_SOURCE[0]}")/..")
exec python3 -B "$ROOT/tests/lib/dragonfly_fixture.py" "$ROOT"
