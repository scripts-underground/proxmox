#!/usr/bin/env bash
# Real release-helper regression; run inside a disposable guest.
set -euo pipefail
systemd-detect-virt -q
ROOT=$(realpath "$(dirname "${BASH_SOURCE[0]}")/..")
source "$ROOT/misc/core.func"
source "$ROOT/misc/error_handler.func"
source "$ROOT/misc/tools.func"
load_functions
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT
export HOME="$work/home" INSTALL_LOG="$work/helper.log"
mkdir "$HOME"
target="$work/assets"

fetch_and_deploy_gh_release force-probe astral-sh/uv prebuild 0.12.13 \
  "$target" 'uv-x86_64-unknown-linux-gnu.tar.gz'
test "$(< "$HOME/.force-probe")" == 0.12.13
"$target/uv" --version | grep -q 0.12.13

# Reproduce a correct version marker with a damaged/missing served payload.
printf 'damaged fixture payload' > "$target/uv"
fetch_and_deploy_gh_release force-probe astral-sh/uv prebuild 0.12.13 \
  "$target" 'uv-x86_64-unknown-linux-gnu.tar.gz'
test "$(< "$target/uv")" == 'damaged fixture payload'
printf 'PASS normal same-version deployment remains idempotent\n'

FORCE_DEPLOY=1 CLEAN_INSTALL=1 fetch_and_deploy_gh_release force-probe astral-sh/uv prebuild 0.12.13 \
  "$target" 'uv-x86_64-unknown-linux-gnu.tar.gz'
"$target/uv" --version | grep -q 0.12.13
test "$(< "$HOME/.force-probe")" == 0.12.13
printf 'PASS explicit redeployment repairs the same version without falsifying its marker\n'
