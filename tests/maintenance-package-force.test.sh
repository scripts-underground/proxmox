#!/usr/bin/env bash
# Real APT/dpkg transactions in private disk-backed fixture roots; forge/UI modeled.
set -euo pipefail
python3 -B "$(dirname -- "${BASH_SOURCE[0]}")/lib/entrypoint.py" maintenance-package-force "$@" || exit $?
[[ "${SU_TEST_GUARD_ONLY:-0}" != 1 ]] || exit 0
systemd-detect-virt --vm --quiet || exit 65
: "${TMPDIR:?disk TMPDIR required}"
case "$(findmnt -rn -T "$TMPDIR" -o FSTYPE)" in '' | tmpfs | ramfs) exit 65 ;; esac
exec python3 -B "$(dirname -- "${BASH_SOURCE[0]}")/lib/package_force_fixture.py"
