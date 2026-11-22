#!/usr/bin/env bash
# shellcheck disable=SC2034,SC2154
# Cold generated bundles and real release/replacement owners; native browser is separate.
set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/../lib/runtime-hooks/harness.sh"
app=byparr
script_type=lxc
variants=(fresh update selected current clean pending pinned-fresh pinned-update pinned-clean secure-readonly lookup download build runtime)
hook_paths=()
runtime_hooks_model() {
  chown() { command chown "$@"; }
  if [[ -f "$c/pinned" ]]; then var_appversion=v2.0.0; fi
  if [[ -f "$c/readonly" ]]; then
    mount --bind /opt/Byparr/.env /opt/Byparr/.env
    mount -o remount,bind,ro /opt/Byparr/.env
  fi
  apt() { :; }
  setup_uv() { :; }
  dpkg() { printf 'ii ffmpeg 1\n'; }
  git() { return 22; }
  uv() {
    printf '%s\n' "$*" >> "$c/uv-calls"
    case "$*" in
      'sync --link-mode copy')
        [[ "$APP_FAULT" != build ]] || return 52
        ;;
      'run playwright install-deps firefox') : > "$c/browser-deps" ;;
      'run python -c '*)
        shift 2
        PYTHONPATH="$c/browser-modules" python3 "$@"
        ;;
      'run python -m invisible_playwright fetch' | 'run python -m camoufox fetch')
        [[ "$4" == "$(cat "$c/browser-module")" ]] || return 54
        : > "$c/browser-ready"
        ;;
      *) return 53 ;;
    esac
  }
  systemctl() {
    if [[ "$1" == start && "$APP_FAULT" == runtime ]]; then
      printf 'failed-start %s\n' "${!#}" >> "$c/services"
      return 51
    fi
    printf '%s\n' "$*" >> "$c/services"
    case "$*" in
      'enable -q --now byparr' | 'start byparr')
        test -f "$c/browser-ready"
        test -f "$c/browser-deps"
        ;;
    esac
  }
  curl() {
    [[ "$APP_FAULT" != lookup ]] || return 22
    local output='' format='' url=''
    while (($#)); do
      case "$1" in
        -o)
          output=$2
          shift
          ;;
        -w)
          format=$2
          shift
          ;;
        https://api.github.com/*) url=$1 ;;
      esac
      shift
    done
    local body='{"tag_name":"v3.1.1","assets":[]}'
    if [[ "$url" == */tags/v2.0.0 ]]; then body='{"tag_name":"v2.0.0","assets":[]}'; fi
    if [[ "$url" == */latest ]]; then
      if [[ "$APP_FIXTURE" == *-selected && -f "$c/latest-read" ]]; then
        body='{"tag_name":"v3.1.2","assets":[]}'
      fi
      : > "$c/latest-read"
    fi
    if [[ -n "$output" ]]; then printf '%s' "$body" > "$output"; else printf '%s' "$body"; fi
    [[ -z "$format" ]] || printf 200
  }
  curl_download() {
    [[ "$APP_FAULT" != download ]] || return 22
    tar -czf "$1" -C "$c" payload
  }
}
runtime_hooks_variant() {
  [[ "$variant" != lookup ]] || fault=lookup
  [[ "$variant" != pinned-fresh ]] || role=install
}
runtime_hooks_expected() {
  [[ "$variant" != lookup ]] || expected=22
}
runtime_hooks_setup() {
  : > "$c/uv-calls"
  local browser=invisible_playwright
  case "$variant" in pinned-*)
    browser=camoufox
    : > "$c/pinned"
    ;;
  esac
  printf '%s\n' "$browser" > "$c/browser-module"
  mkdir -p "$c/browser-modules/$browser"
  : > "$c/browser-modules/$browser/__init__.py"
  printf 'incoming default must not replace existing settings\n' > "$c/payload/.env"
  if [[ "$role" == update ]]; then
    mv "$c/opt/byparr" "$c/opt/Byparr"
    printf 'PORT=8192\nBROWSER_LOCALE=en-US\nOWUI_API_KEY=existing-fixture-key\n' > "$c/opt/Byparr/.env"
    chmod 0644 "$c/opt/Byparr/.env"
    stat -c %i "$c/opt/Byparr/.env" > "$c/env-inode"
    sha256sum "$c/opt/Byparr/.env" | cut -d ' ' -f 1 > "$c/env-sha"
    case "$variant" in
      current | clean | pending | secure-readonly) printf '3.1.1\n' > "$c/home/.byparr" ;;
      pinned-clean)
        printf '2.0.0\n' > "$c/home/.byparr"
        printf 'interrupted\n' > "$c/state/byparr"
        ;;
    esac
    case "$variant" in clean | pending) printf 'interrupted\n' > "$c/state/byparr" ;; esac
    if [[ "$variant" == secure-readonly ]]; then
      chmod 0600 "$c/opt/Byparr/.env"
      : > "$c/readonly"
    fi
  else
    # No fresh configuration is supplied by upstream; the fixture matches that.
    rm "$c/payload/.env"
  fi
}
runtime_hooks_assert() {
  if [[ "$role" == update ]]; then
    check "$(sha256sum "$c/opt/Byparr/.env" 2> /dev/null | cut -d ' ' -f 1 || true)" "$(cat "$c/env-sha")" "$app/$variant existing configuration bytes retained"
    check "$(stat -c %i "$c/opt/Byparr/.env" 2> /dev/null || true)" "$(cat "$c/env-inode")" "$app/$variant configuration inode retained"
    check "$(stat -c %a "$c/opt/Byparr/.env" 2> /dev/null || true)" 600 "$app/$variant private environment mode"
  fi
  if [[ "$variant" == lookup ]]; then
    check "$(wc -l < "$c/services")" 0 "$app/lookup failure does not stop the running app"
    check "$(cat "$c/home/.byparr")" old "$app/lookup failure retains release marker"
  fi
  if [[ "$rc" == 0 && "$variant" != current && "$variant" != secure-readonly ]]; then
    check "$(test -f "$c/browser-ready" && printf yes || true)" yes "$app/$variant selected browser fetched"
    check "$(test -f "$c/browser-deps" && printf yes || true)" yes "$app/$variant selected browser native dependencies provisioned"
  fi
  if [[ "$variant" == current || "$variant" == secure-readonly ]]; then check "$(wc -l < "$c/uv-calls")" 0 "$app/$variant no unnecessary environment rebuild"; fi
  case "$variant" in pinned-*) if [[ "$rc" == 0 ]]; then check "$(cat "$c/home/.byparr")" 2.0.0 "$app/$variant exact pin deployed with its browser module"; fi ;; esac
  if [[ "$variant" == selected && "$rc" == 0 ]]; then check "$(cat "$c/home/.byparr")" 3.1.1 "$app/selected checker tag reaches deployment without a second latest selection"; fi
}
runtime_hooks_retry_assert() {
  check "$(sha256sum "$c/opt/Byparr/.env" | cut -d ' ' -f 1)" "$(cat "$c/env-sha")" "$app/$variant retry retains settings"
  check "$(stat -c %i "$c/opt/Byparr/.env")" "$(cat "$c/env-inode")" "$app/$variant retry retains configuration inode"
  check "$(tail -1 "$c/services")" 'start byparr' "$app/$variant pending retry starts configured browser service"
}
runtime_hooks_more_cases() {
  local api_path
  api_path=$(
    python3 - "$ROOT/_lxc/byparr.md" << 'PY'
from pathlib import Path
import re, sys
from urllib.parse import urlsplit
text = Path(sys.argv[1]).read_text()
host = re.search(r'Configure.*`(http://[^`]+)`.*FlareSolverr URL', text)[1]
# Prowlarr's GenerateFlareSolverrRequest appends /v1 to Settings.Host.
print(urlsplit(host.rstrip('/') + '/v1').path)
PY
  )
  check "$api_path" /v1 "$app/documented FlareSolverr host resolves to the actual API route"
}
runtime_hooks_main "$@"
