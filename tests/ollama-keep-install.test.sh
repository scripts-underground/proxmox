#!/usr/bin/env bash
# A failed Ollama download leaves the installed files in place.
set -euo pipefail

ROOT=$(realpath "$(dirname "${BASH_SOURCE[0]}")/..")
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT
mkdir "$work/stages"
export TMPDIR="$work/stages"

# Both literal roots and resolved mutation operands must stay in this fixture.
# An incomplete rewrite must fail before the hook can touch system paths.
guard_rewritten() {
  if sed -e "s#$work/#SCRATCH/#g" -e 's#"\$[[:alnum:]_]*"/#VARIABLE/#g' "$1" | grep -nE "(^|[[:space:]=\"'(])/[[:alnum:]_]"; then
    return 99
  fi
}
scratch_paths() {
  local operand normalized
  for operand in "$@"; do
    [[ "$operand" != -* ]] || continue
    normalized=$(realpath -m -- "$operand")
    [[ "$normalized" == "$work" || "$normalized" == "$work/"* ]] || return 99
  done
}
cp() {
  scratch_paths "$@" || return 99
  if [[ "${fail_copy:-0}" == 1 && "$*" == *--remove-destination* ]]; then
    return 28
  fi
  command cp "$@"
}
rm() { scratch_paths "$@" && command rm "$@"; }

printf 'prefix=/usr/local\n' > "$work/unmapped"
guard_rc=0
guard_rewritten "$work/unmapped" > "$work/guard.log" || guard_rc=$?
[[ "$guard_rc" == 99 ]]
guard_rc=0
scratch_paths /usr/local > "$work/guard-path.log" || guard_rc=$?
[[ "$guard_rc" == 99 ]]
printf 'PASS incomplete path rewrites and non-scratch copy/removal operands are rejected\n'

msg_info() { :; }
msg_ok() { :; }
msg_error() { :; }
header_info() { :; }
check_container_storage() { :; }
check_container_resources() { :; }
ensure_dependencies() { :; }
get_system_arch() { echo "${test_arch:-amd64}"; }
check_for_gh_release() {
  printf '%s\n' "${3:-}" > "$fixture/pin"
  export CHECK_UPDATE_RELEASE=v0.17.1
  return "$check_status"
}
systemctl() {
  case "$1" in
    show) printf '{ path=%s ; argv[]=%s serve ; }\n' "$service_executable" "$service_executable" ;;
    is-active) return "$inactive" ;;
    *) printf '%s\n' "$*" >> "$fixture/service.log" ;;
  esac
}

# Stubbed downloads record their isolated HOME and destination. The payload shape
# matches the public prebuild helper: main has bin + lib; ROCm's lib is stripped.
fetch_and_deploy_gh_release() {
  printf '%s|%s|%s|%s|%s|%s\n' "$1" "$4" "$5" "$6" "${CLEAN_INSTALL:-}" "$HOME" >> "$fixture/fetch.log"
  [[ "$5" != "$prefix" && "$HOME" != "$fixture/home" ]] || return 93
  [[ "${var_appversion:-}" == "$4" && "${FORCE_DEPLOY:-}" == 1 && "$3" == prebuild && "$2" == ollama/ollama ]] || return 94
  case "$1" in
    ollama-com)
      [[ "$6" == "ollama-linux-${test_arch:-amd64}.tar.zst" && "$CLEAN_INSTALL" == 1 ]] || return 95
      [[ "$fail_asset" != main ]] || return 250
      mkdir -p "$5/bin" "$5/lib/ollama"
      chmod 700 "$5"
      printf hidden-runtime > "$5/.release"
      printf '\177ELFnew-binary' > "$5/bin/ollama"
      chmod 755 "$5/bin/ollama"
      printf new-library > "$5/lib/ollama/runtime.so"
      printf '%s' "$main_version" > "$HOME/.ollama-com"
      ;;
    ollama-rocm)
      [[ "$6" == ollama-linux-amd64-rocm.tar.zst && "$CLEAN_INSTALL" == 0 && "$5" == "$HOME/payload/lib" ]] || return 96
      [[ "$fail_asset" != rocm ]] || return 250
      mkdir -p "$5/ollama/$rocm_layout"
      printf new-rocm > "$5/ollama/$rocm_layout/runtime.so"
      printf '%s' "$rocm_version" > "$HOME/.ollama-rocm"
      ;;
    *) return 97 ;;
  esac
}

setup_case() {
  fixture="$work/$1"
  mkdir -p "$fixture/home" "$fixture/usr/local/bin" "$fixture/etc/systemd/system" "$fixture/models"
  case "$2" in
    old) prefix="$fixture/usr/local/lib/ollama" ;;
    upstream) prefix="$fixture/usr/local" ;;
    new) prefix="$fixture/opt/ollama" ;;
  esac
  mkdir -p "$prefix/bin" "$prefix/lib/ollama"
  chmod 755 "$prefix"
  if [[ "$EUID" == 0 ]]; then chown 12345:12346 "$prefix"; fi
  executable="$prefix/bin/ollama"
  service_executable="$executable"
  printf '\177ELFold-binary' > "$executable"
  chmod 755 "$executable"
  printf old-library > "$prefix/lib/ollama/runtime.so"
  if [[ "$2" == old ]]; then
    ln -s "$executable" "$fixture/usr/local/bin/ollama"
  elif [[ "$2" == new ]]; then
    printf 'custom-wrapper port=8080' > "$fixture/usr/local/bin/ollama"
  fi
  printf 'custom-unit port=11434 HOME=/custom' > "$fixture/etc/systemd/system/ollama.service"
  printf 'OLLAMA_HOST=0.0.0.0:8080\nOLLAMA_MODELS=/custom' > "$fixture/etc/ollama.env"
  printf model-data > "$fixture/models/weights"
  printf '0.16.0' > "$fixture/home/.ollama-com"
  : > "$fixture/service.log"
  : > "$fixture/fetch.log"
  # Point the update hook's system paths into the scratch directory.
  sed -n '/^function update_script() {/,/^}/p' "$ROOT/scripts/lxc/ollama.sh" |
    sed -e "s#/usr/local#$fixture/usr/local#g" -e "s#/opt/ollama#$fixture/opt/ollama#g" -e "s#/root/#$fixture/root/#g" > "$fixture/update.sh"
  guard_rewritten "$fixture/update.sh"
  source "$fixture/update.sh"
  export HOME="$fixture/home"
  export APP=Ollama var_lxc_release=v0.17.1
  unset var_appversion
  check_status=0 inactive=0 fail_asset=none fail_copy=0 main_version=0.17.1 rocm_version=0.17.1 test_arch=amd64 rocm_layout=rocm
  inventory > "$fixture/before"
}

inventory() {
  stat -c '%a:%u:%g' "$prefix"
  sha256sum "$fixture/etc/ollama.env" "$fixture/etc/systemd/system/ollama.service" "$fixture/models/weights"
  if [[ "$prefix" != "$fixture/usr/local" ]]; then
    if [[ -L "$fixture/usr/local/bin/ollama" ]]; then
      readlink "$fixture/usr/local/bin/ollama"
    else
      sha256sum "$fixture/usr/local/bin/ollama"
    fi
  fi
}

run_update() {
  rc=0
  (update_script) > "$fixture/output" 2>&1 || rc=$?
  inventory > "$fixture/after"
  cmp "$fixture/before" "$fixture/after"
}

for layout in old upstream new; do
  setup_case "failed-main-$layout" "$layout"
  fail_asset=main
  run_update
  [[ "$rc" == 250 && ! -s "$fixture/service.log" && -s "$fixture/fetch.log" ]]
  [[ "$(< "$executable")" == $'\177ELFold-binary' && "$(< "$HOME/.ollama-com")" == 0.16.0 ]]
  [[ "$(< "$prefix/lib/ollama/runtime.so")" == old-library ]]
  printf 'PASS failed main download keeps %s binary, libraries, marker, configuration and service untouched\n' "$layout"
done

for layer_dir in rocm rocm_v7; do
  setup_case "failed-$layer_dir" new
  mkdir -p "$prefix/lib/ollama/$layer_dir"
  printf old-rocm > "$prefix/lib/ollama/$layer_dir/runtime.so"
  fail_asset=rocm
  run_update
  [[ "$rc" == 250 && ! -s "$fixture/service.log" ]]
  [[ "$(wc -l < "$fixture/fetch.log")" == 2 ]]
  [[ "$(< "$executable")" == $'\177ELFold-binary' && "$(< "$HOME/.ollama-com")" == 0.16.0 ]]
  [[ "$(< "$prefix/lib/ollama/$layer_dir/runtime.so")" == old-rocm ]]
  printf 'PASS failed %s download also leaves the main runtime and version untouched\n' "$layer_dir"
done

for layout in old upstream new; do
  setup_case "success-$layout" "$layout"
  run_update
  [[ "$rc" == 0 && "$(< "$executable")" == $'\177ELFnew-binary' ]]
  [[ "$(< "$prefix/lib/ollama/runtime.so")" == new-library && "$(< "$HOME/.ollama-com")" == 0.17.1 ]]
  [[ "$(< "$prefix/.release")" == hidden-runtime ]]
  [[ "$(< "$fixture/service.log")" == $'stop ollama\nstart ollama' && "$(< "$fixture/pin")" == v0.17.1 ]]
  printf 'PASS %s update preserves port, env, unit, model data and launcher while updating runtime\n' "$layout"
done

for old_layer in rocm rocm_v7; do
  for new_layer in rocm rocm_v7; do
    setup_case "success-$old_layer-$new_layer" new
    mkdir -p "$prefix/lib/ollama/$old_layer"
    printf old-rocm > "$prefix/lib/ollama/$old_layer/runtime.so"
    rocm_layout=$new_layer
    run_update
    [[ "$rc" == 0 && "$(< "$prefix/lib/ollama/$new_layer/runtime.so")" == new-rocm ]]
    [[ "$(< "$HOME/.ollama-rocm")" == 0.17.1 ]]
    printf 'PASS %s to %s layer update without requiring a currently mapped kfd device\n' "$old_layer" "$new_layer"
  done
done

setup_case inactive-arm64 new
inactive=3 test_arch=arm64 var_appversion=v0.17.1
run_update
[[ "$rc" == 0 && ! -s "$fixture/service.log" && "$(< "$fixture/pin")" == v0.17.1 ]]
printf 'PASS arm64 update honors the runtime pin and preserves an inactive service\n'

for status in 1 22; do
  setup_case "release-check-$status" new
  check_status=$status
  run_update
  if [[ "$status" == 1 ]]; then [[ "$rc" == 0 ]]; else [[ "$rc" == "$status" ]]; fi
  [[ ! -s "$fixture/fetch.log" && ! -s "$fixture/service.log" && "$(< "$executable")" == $'\177ELFold-binary' ]]
done
printf 'PASS already-current is a no-op and release-check errors propagate\n'

for layer in main rocm; do
  setup_case "release-mismatch-$layer" new
  if [[ "$layer" == main ]]; then
    main_version=0.16.9
  else
    mkdir -p "$prefix/lib/ollama/rocm"
    rocm_version=0.16.9
  fi
  run_update
  [[ "$rc" == 250 && ! -s "$fixture/service.log" && "$(< "$executable")" == $'\177ELFold-binary' ]]
done
printf 'PASS older-release fallback cannot replace the selected main or ROCm release\n'

for layout in old upstream new; do
  for state in active inactive; do
    setup_case "failed-copy-$layout-$state" "$layout"
    fail_copy=1
    [[ "$state" != inactive ]] || inactive=3
    run_update
    [[ "$rc" == 250 && "$(< "$HOME/.ollama-com")" == 0.16.0 ]]
    if [[ "$state" == active ]]; then
      [[ "$(< "$fixture/service.log")" == $'stop ollama\nstart ollama' ]]
    else
      [[ ! -s "$fixture/service.log" ]]
    fi
    [[ -z "$(find "$TMPDIR" -mindepth 1 -print -quit)" ]]
    # The unfinished-update flag belongs to run_update_script; the nonzero
    # hook status leaves it set, and a retry must still be able to deploy.
    fail_copy=0
    : > "$fixture/service.log"
    run_update
    [[ "$rc" == 0 && "$(< "$executable")" == $'\177ELFnew-binary' ]]
    printf 'PASS failed copy restores %s %s service state, cleans staging and permits retry\n' "$layout" "$state"
  done
done
