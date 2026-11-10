#!/usr/bin/env bash
# One existing runtime/bundle owner; only app probes and redacted result records.
set -euo pipefail
python3 -B "$(dirname -- "${BASH_SOURCE[0]}")/lib/entrypoint.py" maintenance-lazylibrarian-native "$@" || exit $?
[[ "${SU_TEST_GUARD_ONLY:-0}" != 1 ]] || exit 0
exec python3 -B "$(dirname -- "${BASH_SOURCE[0]}")/lib/lazylibrarian-native.py"
