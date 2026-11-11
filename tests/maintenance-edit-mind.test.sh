#!/usr/bin/env bash
# App-owned cold-bundle fixture; the shared dispatcher remains the execution owner.
set -euo pipefail
python3 -B "$(dirname -- "${BASH_SOURCE[0]}")/lib/entrypoint.py" maintenance-edit-mind "$@" || exit $?
[[ "${SU_TEST_GUARD_ONLY:-0}" != 1 ]] || exit 0
exec python3 -B "$(dirname -- "${BASH_SOURCE[0]}")/lib/edit-mind.fixture.py"
