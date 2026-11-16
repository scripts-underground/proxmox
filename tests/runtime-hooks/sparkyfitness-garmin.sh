#!/usr/bin/env bash
# shellcheck disable=SC2034,SC2154
set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/../lib/runtime-hooks/addon-release.sh"
app=sparkyfitness-garmin
release_app=$app release_mode=tarball release_asset=unused.tar.gz
addon_release_setup() { mkdir -p "$c/payload/SparkyFitnessGarmin"; }
addon_release_consumer_assert() { check "$(cat "$c/opt/$app/code")" 'new code' "$app selected source consumer"; }
runtime_hooks_main "$@"
