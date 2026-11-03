#!/usr/bin/env bash
# Shared-owner contract regression. Native PVE effects are recording boundaries.
set -euo pipefail
exec timeout --signal=TERM --kill-after=5s 1000s python3 -B "$(dirname -- "${BASH_SOURCE[0]}")/lib/ownership_cases.py" "$@"
