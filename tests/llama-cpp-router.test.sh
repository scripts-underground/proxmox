#!/usr/bin/env bash
set -euo pipefail
# Update/preservation contract. Actual router APIs are qualified in the native CT.
exec bash "$(dirname "${BASH_SOURCE[0]}")/model-server-update-contract.test.sh" llama-cpp
