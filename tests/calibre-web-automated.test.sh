#!/usr/bin/env bash
# Normal CWA install + actual service/path/HTTP/upload/ingest consumers.
set -euo pipefail
python3 -B "$(dirname -- "${BASH_SOURCE[0]}")/lib/entrypoint.py" calibre-web-automated "$@" || exit $?
[[ "${SU_TEST_GUARD_ONLY:-0}" != 1 ]] || exit 0
source "$(dirname -- "${BASH_SOURCE[0]}")/lib/test-common.sh"
run_app_suite calibre-web-automated "$@"
