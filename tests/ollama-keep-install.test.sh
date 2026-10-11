#!/usr/bin/env bash
# A failed Ollama download leaves the installed files in place.
set -euo pipefail

ROOT=$(realpath "$(dirname "${BASH_SOURCE[0]}")/..")
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT

# Point the update hook's system paths into the scratch directory.
mkdir -p "$work/usr/local/lib/ollama/bin" "$work/usr/local/bin"
printf 'old-binary' > "$work/usr/local/lib/ollama/bin/ollama"
printf 'old-link' > "$work/usr/local/bin/ollama"
sed -n '/^function update_script() {/,/^}/p' "$ROOT/scripts/lxc/ollama.sh" |
  sed -e "s#/usr/local/#$work/usr/local/#g" -e "s#/root/\.ollama#$work/root-ollama#g" > "$work/update.sh"

msg_info() { :; }
msg_ok() { :; }
msg_error() { :; }
header_info() { :; }
check_container_storage() { :; }
check_container_resources() { :; }
check_for_gh_release() { return 0; }
ensure_dependencies() { :; }
systemctl() { :; }

# Stubbed failed download: record what the fetch saw, then fail like the real one.
fetch_and_deploy_gh_release() {
  printf 'clean=%s bin=%s link=%s\n' "${CLEAN_INSTALL:-}" \
    "$(cat "$work/usr/local/lib/ollama/bin/ollama" 2> /dev/null || echo missing)" \
    "$(cat "$work/usr/local/bin/ollama" 2> /dev/null || echo missing)" > "$work/fetch.log"
  return 250
}

source "$work/update.sh"
rc=0
(update_script) || rc=$?
[[ "$(< "$work/fetch.log")" == "clean=1 bin=old-binary link=old-link" ]]
printf 'PASS fetch runs with CLEAN_INSTALL=1 and the old install still in place\n'

[[ "$rc" == 250 ]]
[[ "$(< "$work/usr/local/lib/ollama/bin/ollama")" == old-binary ]]
[[ "$(< "$work/usr/local/bin/ollama")" == old-link ]]
printf 'PASS failed download keeps the installed files and exits 250\n'
