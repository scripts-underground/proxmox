#!/usr/bin/env bash
# Finite app-owned native consumer; existing typed owner retains failed resources.
set -euo pipefail
python3 -B "$(dirname -- "${BASH_SOURCE[0]}")/lib/entrypoint.py" maintenance-edit-mind-native "$@" || exit $?
[[ "${SU_TEST_GUARD_ONLY:-0}" != 1 ]] || exit 0
exec python3 -B "$(dirname -- "${BASH_SOURCE[0]}")/lib/edit_mind_native.py"
