#!/usr/bin/env bash
# Discovery stays inside this registered suite and its context-bound source tree.
set -euo pipefail
systemd-detect-virt --vm --quiet || exit 1
: "${TMPDIR:?disk-backed TMPDIR required}" "${MAINTENANCE_REFERENCES:?immutable source metadata required}"
case "$(findmnt -rn -T "$TMPDIR" -o FSTYPE)" in '' | tmpfs | ramfs) exit 1 ;; esac
ROOT=$(realpath "$(dirname "${BASH_SOURCE[0]}")/..")
source "$ROOT/tests/lib/runtime-hooks/aggregate.sh"
runtime_hooks_aggregate "$ROOT/tests/runtime-hooks"
