#!/usr/bin/env bash
# App-owned consumer over the existing runtime/publisher and preservation owner.
set -euo pipefail
python3 -B "$(dirname -- "${BASH_SOURCE[0]}")/lib/entrypoint.py" maintenance-bookorbit-native "$@" || exit $?
[[ "${SU_TEST_GUARD_ONLY:-0}" != 1 ]] || exit 0
exec python3 -B "$(dirname -- "${BASH_SOURCE[0]}")/lib/bookorbit-native.py"
