#!/usr/bin/env bash
# shellcheck disable=SC2034,SC2154
set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/../lib/runtime-hooks/addon-release.sh"
app=filebrowser-quantum
release_app=$app release_mode=singlefile release_asset=linux-amd64-filebrowser
addon_release_setup() { :; }
addon_release_consumer_assert() { check "$("$c/local/bin/filebrowser")" 'selected v2.0.0' "$app selected executable consumer"; }
runtime_hooks_main "$@"
