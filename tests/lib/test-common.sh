#!/usr/bin/env bash
# Guest-local source-owned consumer dispatch. No SSH, shell strings or numeric cleanup.
set -euo pipefail
run_app_suite() {
  local suite=$1
  shift
  exec python3 -B "$(dirname -- "${BASH_SOURCE[0]}")/app_driver.py" "$suite" "$@"
}
