#!/usr/bin/env bash
# runtime-hooks-contract: fixture case-asserted
# Cold actual lifecycle regions and writer; PVE, OS setup and diagnostics modeled.
set -euo pipefail
systemd-detect-virt --vm --quiet || exit 1
: "${TMPDIR:?disk TMPDIR required}"
case "$(findmnt -rn -T "$TMPDIR" -o FSTYPE)" in '' | tmpfs | ramfs) exit 1 ;; esac
ROOT=$(realpath "$(dirname "${BASH_SOURCE[0]}")/../..")
exec python3 -B "$ROOT/tests/lib/core-post-build-order.fixture.py" "$ROOT" "${POST_BUILD_OWNER_ROOT:-$ROOT}"
