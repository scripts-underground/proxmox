#!/usr/bin/env bash
# shellcheck disable=SC2034,SC2154
set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/../lib/runtime-hooks/addon-release.sh"
app=olivetin
release_app=olivetin release_mode=binary release_asset=OliveTin_linux_amd64.deb
addon_release_setup() { :; }
addon_release_consumer_assert() { check "$(cat "$c/package-consumer")" 'selected v2.0.0' "$app selected package consumer"; }
runtime_hooks_main "$@"
