#!/usr/bin/env bash
# Real release-helper regression; run inside a disposable guest.
set -euo pipefail
python3 -B "$(dirname -- "${BASH_SOURCE[0]}")/lib/entrypoint.py" github-force-deploy "$@" || exit $?
[[ "${SU_TEST_GUARD_ONLY:-0}" != 1 ]] || exit 0
systemd-detect-virt -q
ROOT=$(realpath "$(dirname "${BASH_SOURCE[0]}")/..")
source "$ROOT/misc/core.func"
source "$ROOT/misc/error_handler.func"
source "$ROOT/misc/tools.func"
load_functions
work=$(mktemp -d)
native_exit() {
  local status=$? capture=0
  trap - EXIT
  journalctl -u OliveTin.service --no-pager > "$work/package-journal.log" 2>&1 || capture=$?
  local -a evidence=()
  local file
  for file in "$work"/*.log "$work"/*.html; do
    [[ ! -f "$file" ]] || evidence+=("${file##*/}")
  done
  tar -czf "$work.evidence.tar.gz" -C "$work" "${evidence[@]}" || capture=$?
  if [[ $capture == 0 ]]; then
    printf 'CORE_ASSETS_NATIVE_TGZ_SHA256 '
    sha256sum "$work.evidence.tar.gz" || capture=$?
    printf 'CORE_ASSETS_NATIVE_TGZ_BASE64 '
    base64 -w0 "$work.evidence.tar.gz" || capture=$?
    printf '\n'
  fi
  [[ $status != 0 ]] || status=$capture
  exit "$status"
}
trap native_exit EXIT
export HOME="$work/home" INSTALL_LOG="$work/helper.log"
mkdir "$HOME"
target="$work/assets"

# Numeric-v compatibility must return the actual release object, with assets,
# rather than an empty Git-tag fallback. uv publishes unprefixed release tags.
_gh_release_json astral-sh/uv v0.12.13 '' "$work/reverse.json"
jq -e '.tag_name=="0.12.13" and any(.assets[]; .name=="uv-x86_64-unknown-linux-gnu.tar.gz")' "$work/reverse.json" > /dev/null
printf 'PASS reverse numeric-v lookup retains actual uv asset metadata\n'

fetch_and_deploy_gh_release force-probe astral-sh/uv prebuild 0.12.13 \
  "$target" 'uv-x86_64-unknown-linux-gnu.tar.gz' '' "$work/selected.json"
test "$(< "$HOME/.force-probe")" == 0.12.13
"$target/uv" --version | grep -q 0.12.13

# Reproduce a correct version marker with a damaged/missing served payload.
printf 'damaged fixture payload' > "$target/uv"
fetch_and_deploy_gh_release force-probe astral-sh/uv prebuild 0.12.13 \
  "$target" 'uv-x86_64-unknown-linux-gnu.tar.gz' '' "$work/selected.json"
test "$(< "$target/uv")" == 'damaged fixture payload'
printf 'PASS normal same-version deployment remains idempotent\n'

FORCE_DEPLOY=1 CLEAN_INSTALL=1 fetch_and_deploy_gh_release force-probe astral-sh/uv prebuild 0.12.13 \
  "$target" 'uv-x86_64-unknown-linux-gnu.tar.gz' '' "$work/selected.json"
"$target/uv" --version | grep -q 0.12.13
test "$(< "$HOME/.force-probe")" == 0.12.13
printf 'PASS explicit redeployment repairs the same version without falsifying its marker\n'
printf 'RUNTIME_SELECTED_RELEASE '
jq -c '{id,tag_name,published_at,assets:[.assets[]|select(.name=="uv-x86_64-unknown-linux-gnu.tar.gz")|{id,name,size,digest,browser_download_url}]}' "$work/selected.json"
printf 'RUNTIME_EXECUTABLE_VERSION '
"$target/uv" --version
sha256sum "$target/uv" "$HOME/.force-probe"

# A real package service consumer, not a modeled package-manager invocation.
# Capture helper-owned lifecycle calls separately from the app hook's final
# enable/start. The owned CT is fresh; no operator service is touched.
printf 'NATIVE_PACKAGE_EVIDENCE %s\n' "$work"
systemctl() {
  printf '%s\n' "$*" >> "$work/systemctl.log"
  command systemctl "$@"
}
curl() { :; }
source "$ROOT/scripts/addon/olivetin.sh"
unset -f curl
OS_FAMILY=debian install_script
# This package ships its unit in /etc and leaves enablement to its app hook.
# A fresh disabled unit must not be started by the package helper itself.
if grep -E '^(start|restart) ' "$work/systemctl.log"; then exit 1; fi
grep -Fx 'enable --now OliveTin' "$work/systemctl.log"
for attempt in {1..30}; do
  curl -fsS http://127.0.0.1:1337/ -o "$work/olivetin.html" && break
  sleep 1
done
grep -i OliveTin "$work/olivetin.html"
before_pid=$(command systemctl show --value --property=MainPID OliveTin.service)
: > "$work/systemctl.log"
FORCE_DEPLOY=1 fetch_and_deploy_gh_release olivetin OliveTin/OliveTin binary latest
grep -Fx 'restart -- OliveTin.service' "$work/systemctl.log"
after_pid=$(command systemctl show --value --property=MainPID OliveTin.service)
[[ "$before_pid" != 0 && "$after_pid" != 0 && "$before_pid" != "$after_pid" ]]
curl -fsS --retry 10 --retry-connrefused --retry-delay 1 http://127.0.0.1:1337/ -o "$work/olivetin-updated.html"
grep -qi OliveTin "$work/olivetin-updated.html"
command systemctl stop OliveTin.service
: > "$work/systemctl.log"
FORCE_DEPLOY=1 fetch_and_deploy_gh_release olivetin OliveTin/OliveTin binary latest
[[ "$(command systemctl show --value --property=ActiveState OliveTin.service)" == inactive ]]
if grep -E '^(start|restart) ' "$work/systemctl.log"; then exit 1; fi
command systemctl start OliveTin.service
curl -fsS --retry 10 --retry-connrefused --retry-delay 1 http://127.0.0.1:1337/ -o "$work/olivetin-restored.html"
grep -qi OliveTin "$work/olivetin-restored.html"
printf 'PASS native OliveTin app install/HTTP, active package restart and stopped-hook preservation\n'
command systemctl show --property=LoadState,ActiveState,UnitFileState,MainPID OliveTin.service
