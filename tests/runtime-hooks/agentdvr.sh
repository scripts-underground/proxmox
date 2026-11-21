#!/usr/bin/env bash
# runtime-hooks-contract: lxc start-on-success
# shellcheck disable=SC2034,SC2154
# Callback inputs/outputs are supplied and consumed by the sourced harness.
set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/../lib/runtime-hooks/harness.sh"
app=agentdvr
script_type=lxc
variants=(fresh update current missing-marker pending download runtime)
hook_paths=()
runtime_hooks_model() {
  apt() { :; }
  setup_hwaccel() { :; }
  uname() { printf 'x86_64\n'; }
  curl() {
    if [[ "$*" == *DownloadLocation4* ]]; then
      printf 'https://fixture.invalid/Agent_Linux64_2_0_0_0.zip\n'
    else
      [[ "$APP_FAULT" != download ]] || return 22
      command cp "$c/release.zip" "${!#}"
      printf 'download\n' >> "$c/downloads"
    fi
  }
  systemctl() {
    if [[ "$1" == start && "$APP_FAULT" == runtime ]]; then
      printf 'failed-start %s\n' "${!#}" >> "$c/services"
      return 51
    fi
    printf '%s\n' "$*" >> "$c/services"
  }
}
runtime_hooks_variant() {
  [[ "$variant" != download ]] || fault=download
  [[ "$variant" != runtime ]] || fault=runtime
}
runtime_hooks_expected() {
  [[ "$variant" != download ]] || expected=22
}
runtime_hooks_setup() {
  : > "$c/downloads"
  python3 - "$c/release.zip" << 'PY'
import sys,zipfile
with zipfile.ZipFile(sys.argv[1], 'w') as archive:
    archive.writestr('Agent', '#!/bin/sh\necho new-agent\n')
PY
  mkdir -p "$c/opt/agentdvr/agent/Media/XML"
  printf 'saved settings\n' > "$c/opt/agentdvr/agent/Media/XML/config.json"
  if [[ "$role" == update ]]; then
    printf '#!/bin/sh\necho old-agent\n' > "$c/opt/agentdvr/agent/Agent"
    chmod 0755 "$c/opt/agentdvr/agent/Agent"
    case "$variant" in
      current | pending) printf 'https://fixture.invalid/Agent_Linux64_2_0_0_0.zip\n' > "$c/home/.agentdvr" ;;
      missing-marker) rm "$c/home/.agentdvr" ;;
    esac
    if [[ "$variant" == pending ]]; then
      printf 'interrupted update\n' > "$c/state/agentdvr"
      rm "$c/opt/agentdvr/agent/Agent"
    fi
  fi
}
runtime_hooks_assert() {
  check "$(cat "$c/opt/agentdvr/agent/Media/XML/config.json")" 'saved settings' "$app/$variant native archive keeps saved configuration"
  if [[ "$rc" == 0 ]]; then
    if [[ "$variant" == current ]]; then
      check "$(wc -l < "$c/downloads")" 0 "$app/current unforced same release is a no-op"
      check "$("$c/opt/agentdvr/agent/Agent")" old-agent "$app/current existing executable retained"
    else
      check "$("$c/opt/agentdvr/agent/Agent" 2> /dev/null || true)" new-agent "$app/$variant executable consumer sees deployment"
      check "$(wc -l < "$c/downloads")" 1 "$app/$variant exactly one release downloaded"
    fi
  fi
}
runtime_hooks_retry_assert() {
  check "$("$c/opt/agentdvr/agent/Agent")" new-agent "$app/$variant pending retry redeploys executable"
  check "$(tail -1 "$c/services")" 'start AgentDVR' "$app/$variant retry starts service even after marker publication"
  check "$(cat "$c/opt/agentdvr/agent/Media/XML/config.json")" 'saved settings' "$app/$variant retry retains settings"
}
runtime_hooks_main "$@"
