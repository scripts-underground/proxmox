#!/usr/bin/env bash
# Normal Odysseus install + actual service/path/port80 consumers.
set -euo pipefail
python3 -B "$(dirname -- "${BASH_SOURCE[0]}")/lib/entrypoint.py" odysseus "$@" || exit $?
[[ "${SU_TEST_GUARD_ONLY:-0}" != 1 ]] || exit 0
source "$(dirname -- "${BASH_SOURCE[0]}")/lib/test-common.sh"
run_app_suite odysseus "$@"
