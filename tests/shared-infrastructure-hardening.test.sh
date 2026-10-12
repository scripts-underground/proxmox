#!/usr/bin/env bash
# Finite protected H groups; production helpers receive no testing flags.
set -euo pipefail
ROOT=$(realpath "$(dirname "${BASH_SOURCE[0]}")/..")
# shellcheck source=tests/lib/safety-gap-common.sh
source "$ROOT/tests/lib/safety-gap-common.sh"
if [[ "${1:-}" == --variant ]]; then
  exec python3 "$SG_REVIEW_SUPPORT/hardening-case.py" "$2"
fi
sg_init "$@"
exec python3 "$SG_REVIEW_SUPPORT/hardening-group.py" "${BASH_SOURCE[0]}"
