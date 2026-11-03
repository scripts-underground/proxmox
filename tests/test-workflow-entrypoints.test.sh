#!/usr/bin/env bash
# Admission/dispatch conformance; native effects are recorded, never real CTs.
set -euo pipefail
exec timeout --signal=TERM --kill-after=5s 1000s python3 -B "$(dirname -- "${BASH_SOURCE[0]}")/lib/entrypoint_cases.py" "$@"
