#!/usr/bin/env bash
# Deterministic release-provider regressions. Run inside a disposable guest.
set -euo pipefail

ROOT=$(realpath "$(dirname "${BASH_SOURCE[0]}")/..")
source "$ROOT/misc/tools.func"

if [[ "${1:-}" == --bundle || "${1:-}" == --live ]]; then
  source "$ROOT/misc/core.func"
  source "$ROOT/misc/error_handler.func"
  if [[ "${1:-}" == --bundle ]]; then source "$ROOT/misc/bundle.func"; fi
  load_functions
fi
work=$(mktemp -d)
cleanup() {
  if declare -F stop_spinner > /dev/null; then stop_spinner || true; fi
  rm -rf -- "$work"
}
trap cleanup EXIT
trap 'exit 130' INT
trap 'exit 143' TERM
failures=0

# Invoke on the disposable PVE guest against an explicitly supplied test CT.
if [[ "${1:-}" == --bundle ]]; then
  CTID="${2:?supply the disposable container ID}"
  export REPO_BASE="${3:?supply the HTTP-served candidate tree}"
  SESSION_ID=$(openssl rand -hex 4)
  export APP='Codeberg Provider Probe'
  export NSAPP=codeberg-provider-probe
  var_lxc_probe_target="/opt/provider-probe-$SESSION_ID"
  # Keep the marker identity as isolated as the session-specific target.
  var_lxc_probe_app="readeck-probe-$SESSION_ID"
  update_script() {
    fetch_and_deploy_codeberg_release "$var_lxc_probe_app" readeck/readeck singlefile \
      0.23.4 "$var_lxc_probe_target" 'readeck-*-linux-amd64'
    "$var_lxc_probe_target/$var_lxc_probe_app" version
    test "$(< "$HOME/.$var_lxc_probe_app")" == 0.23.4
    printf 'PASS self-contained Codeberg update bundle\n'
  }
  destination="/root/provider-update-$SESSION_ID.sh"
  build_bundle update update_script "$destination" 0700 update_script
  pct exec "$CTID" -- bash "$destination"
  exit 0
fi

# Exercise real public releases and the actual framework logging wrappers.
if [[ "${1:-}" == --live ]]; then
  export HOME="$work/home" INSTALL_LOG="$work/provider.log"
  mkdir "$HOME"
  for spec in \
    'autocaliweb|gelbphoenix/autocaliweb|tarball|README.md|' \
    'endurain|endurain-project/endurain|tarball|README.md|' \
    'forgejo|forgejo/forgejo|singlefile|forgejo|forgejo-*-linux-amd64' \
    'readeck|readeck/readeck|singlefile|readeck|readeck-*-linux-amd64'; do
    IFS='|' read -r app repo mode required pattern <<< "$spec"
    target="$work/$app"
    expected=$(get_latest_codeberg_release "$repo")
    check_for_codeberg_release "$app" "$repo"
    selected="$CHECK_UPDATE_RELEASE"
    VERBOSE=yes set_std_mode
    fetch_and_deploy_codeberg_release "$app" "$repo" "$mode" "$selected" "$target" "$pattern"
    test -s "$target/$required"
    test "$(< "$HOME/.$app")" == "$expected"
    printf 'configuration sentinel' > "$target/.provider-test"
    printf '0.0.0' > "$HOME/.$app"
    VERBOSE=no set_std_mode
    CLEAN_INSTALL=1 fetch_and_deploy_codeberg_release "$app" "$repo" "$mode" "$selected" "$target" "$pattern"
    test "$(< "$target/.provider-test")" == 'configuration sentinel'
    test "$(< "$HOME/.$app")" == "$expected"
    if check_for_codeberg_release "$app" "$repo"; then
      printf 'unexpected update immediately after deployment\n' >&2
      exit 1
    else
      test "$?" -eq 1
    fi
    if [[ "$app" == forgejo ]]; then
      "$target/forgejo" --version
    elif [[ "$app" == readeck ]]; then
      "$target/readeck" version
    fi
    printf 'PASS live install/update %s (%s)\n' "$app" "$expected"
  done
  exit 0
fi

msg_info() { :; }
msg_ok() { :; }
msg_warn() { printf '%s\n' "$*" >&2; }
msg_error() { printf '%s\n' "$*" >&2; }
ensure_dependencies() { command -v jq > /dev/null; }
getent() { return 0; }
sleep() { :; }

curl() {
  local output='' url='' arg
  printf '%s\n' "$*" >> "$CASE_ROOT/requests"
  while (($#)); do
    arg="$1"
    shift
    case "$arg" in
      -o)
        output="$1"
        shift
        ;;
      https://*) url="$arg" ;;
    esac
  done
  if [[ "$url" == */releases/tags/* ]]; then
    printf '%s' "$PIN_JSON" > "$output"
  else
    printf '%s' "$RELEASES_JSON" > "$output"
  fi
  if [[ "${UNPREFIXED_PIN_MISSING:-0}" == 1 && "$url" == */tags/1.0.0 ]]; then
    printf '404'
  else
    printf '%s' "${HTTP_STATUS:-200}"
  fi
  return "${CURL_STATUS:-0}"
}

curl_download() {
  if [[ "${DOWNLOAD_FAIL:-0}" == 1 ]]; then
    printf 'partial download' > "$1"
    return 1
  fi
  cp "$ASSET" "$1"
}

assert_eq() {
  if [[ "$1" != "$2" ]]; then
    printf 'expected <%s>, got <%s>\n' "$2" "$1" >&2
    return 1
  fi
}

stable='{"draft":false,"prerelease":false,"tag_name":"v2.0.0","assets":[{"browser_download_url":"https://codeberg.org/test/app/releases/download/v2.0.0/app.tar.gz"}]}'
RELEASES_JSON="[{\"draft\":true,\"prerelease\":false,\"tag_name\":\"v9.0.0\"},{\"draft\":false,\"prerelease\":true,\"tag_name\":\"v3.0.0-rc1\"},$stable]"
PIN_JSON="$stable"
STD=''

run_case() {
  local name="$1" fn="$2" rc
  set +e
  (
    set -euo pipefail
    CASE_ROOT="$work/$name"
    mkdir "$CASE_ROOT"
    export HOME="$CASE_ROOT/home" TMPDIR="$CASE_ROOT/tmp"
    mkdir "$HOME" "$TMPDIR"
    mkdir "$CASE_ROOT/archive" "$CASE_ROOT/archive/app"
    printf 'new payload' > "$CASE_ROOT/archive/app/content"
    tar -czf "$CASE_ROOT/asset.tar.gz" -C "$CASE_ROOT/archive" app
    ASSET="$CASE_ROOT/asset.tar.gz"
    "$fn"
    if [[ -n "$(ls -A "$TMPDIR")" ]]; then
      printf 'temporary staging leaked in %s\n' "$TMPDIR" >&2
      exit 1
    fi
    if [[ -n "$(find "$CASE_ROOT" \( -name '.codeberg-*' -o -name '.release-publish.*' -o -name '.release-restore.*' \) -print -quit)" ]]; then
      printf 'deployment staging leaked\n' >&2
      exit 1
    fi
  )
  rc=$?
  set -e
  if [[ "$rc" == 0 ]]; then
    printf 'PASS %s\n' "$name"
  else
    printf 'FAIL %s (exit %s)\n' "$name" "$rc"
    failures=$((failures + 1))
  fi
}

stable_selection() {
  assert_eq "$(get_latest_codeberg_release test/app)" '2.0.0'
  check_for_codeberg_release 'Test App' test/app
  assert_eq "$CHECK_UPDATE_RELEASE" 'v2.0.0'
  fetch_and_deploy_codeberg_release 'Test App' test/app tarball latest "$CASE_ROOT/target"
  assert_eq "$(< "$CASE_ROOT/target/content")" 'new payload'
  assert_eq "$(< "$HOME/.testapp")" '2.0.0'
}

timeouts() {
  codeberg_api_call https://codeberg.org/api/v1/repos/test/app/releases "$CASE_ROOT/result"
  grep -q -- '--connect-timeout 10' "$CASE_ROOT/requests"
  grep -q -- '--max-time 60' "$CASE_ROOT/requests"
}

word_prefix() {
  RELEASES_JSON='[{"draft":false,"prerelease":false,"tag_name":"version/2","assets":[]}]'
  assert_eq "$(get_latest_codeberg_release test/app)" 'version/2'
  printf 'version/2\n' > "$HOME/.testapp"
  set +e
  check_for_codeberg_release 'Test App' test/app
  local rc=$?
  set -e
  assert_eq "$rc" 1
}

pin_outside_first_page() {
  PIN_JSON='{"draft":false,"prerelease":false,"tag_name":"v1.0.0","assets":[]}'
  check_for_codeberg_release app test/app v1.0.0
  assert_eq "$CHECK_UPDATE_RELEASE" v1.0.0
  grep -q '/releases/tags/v1.0.0' "$CASE_ROOT/requests"
}

encoded_pin() {
  PIN_JSON='{"draft":false,"prerelease":false,"tag_name":"version/2","assets":[]}'
  check_for_codeberg_release app test/app 'version/2'
  assert_eq "$CHECK_UPDATE_RELEASE" 'version/2'
  grep -q '/releases/tags/version%2F2' "$CASE_ROOT/requests"
}

normalized_pin() {
  PIN_JSON='{"draft":false,"prerelease":false,"tag_name":"v1.0.0","assets":[]}'
  UNPREFIXED_PIN_MISSING=1
  check_for_codeberg_release app test/app 1.0.0
  assert_eq "$CHECK_UPDATE_RELEASE" 'v1.0.0'
  printf '1.0.0' > "$HOME/.app"
  fetch_and_deploy_codeberg_release app test/app tarball 1.0.0 "$CASE_ROOT/target"
  test ! -e "$CASE_ROOT/target"
}

empty_metadata() {
  RELEASES_JSON='[]'
  set +e
  get_latest_codeberg_release test/app
  local rc=$?
  set -e
  assert_eq "$rc" 250
}

stale_selection() {
  CHECK_UPDATE_RELEASE=old
  printf '2.0.0' > "$HOME/.app"
  set +e
  check_for_codeberg_release app test/app
  local rc=$?
  set -e
  assert_eq "$rc" 1
  assert_eq "$CHECK_UPDATE_RELEASE" ''
}

clean_and_merge() {
  mkdir "$CASE_ROOT/target"
  printf 'configuration' > "$CASE_ROOT/target/.env"
  printf 'old asset' > "$CASE_ROOT/target/old"
  fetch_and_deploy_codeberg_release app test/app tarball latest "$CASE_ROOT/target"
  assert_eq "$(< "$CASE_ROOT/target/.env")" 'configuration'
  assert_eq "$(< "$CASE_ROOT/target/old")" 'old asset'
  printf '1.0.0' > "$HOME/.app"
  CLEAN_INSTALL=1 fetch_and_deploy_codeberg_release app test/app tarball latest "$CASE_ROOT/target"
  test ! -e "$CASE_ROOT/target/old"
  assert_eq "$(< "$CASE_ROOT/target/.env")" 'configuration'
  assert_eq "$(< "$CASE_ROOT/target/content")" 'new payload'
}

rollback_publish() {
  mkdir "$CASE_ROOT/target"
  printf 'old payload' > "$CASE_ROOT/target/content"
  printf 'old version' > "$HOME/.app"
  mv() {
    local source="${*: -2:1}" destination="${*: -1}"
    if [[ "$source" == */publish && "$destination" == "$CASE_ROOT/target/content" ]]; then
      printf 'real leaf publication fault\n' > "$CASE_ROOT/publication-fault"
      return 1
    fi
    command mv "$@"
  }
  set +e
  CLEAN_INSTALL=1 fetch_and_deploy_codeberg_release app test/app tarball latest "$CASE_ROOT/target"
  local rc=$?
  set -e
  assert_eq "$rc" 252
  test -s "$CASE_ROOT/publication-fault"
  assert_eq "$(< "$CASE_ROOT/target/content")" 'old payload'
  assert_eq "$(< "$HOME/.app")" 'old version'
}

replace_running_binary() {
  mkdir "$CASE_ROOT/target"
  cp /usr/bin/sleep "$CASE_ROOT/target/app"
  "$CASE_ROOT/target/app" 1 &
  local pid=$!
  ASSET=/usr/bin/true
  fetch_and_deploy_codeberg_release app test/app singlefile latest "$CASE_ROOT/target" '*.tar.gz'
  "$CASE_ROOT/target/app"
  wait "$pid"
  assert_eq "$(< "$HOME/.app")" '2.0.0'
}

quiet_binary_fallback() {
  source "$ROOT/misc/core.func"
  source "$ROOT/misc/error_handler.func"
  load_functions
  export STD=silent
  INSTALL_LOG="$CASE_ROOT/quiet.log"
  RELEASES_JSON='[{"draft":false,"prerelease":false,"tag_name":"v2.0.0","assets":[{"browser_download_url":"https://codeberg.org/test/app/releases/download/v2.0.0/app-amd64.deb"}]}]'
  apt() { return 7; }
  dpkg() {
    if [[ "$1" == --print-architecture ]]; then
      printf 'amd64\n'
    else
      printf 'dpkg fallback reached\n' > "$CASE_ROOT/fallback"
    fi
  }
  fetch_and_deploy_codeberg_release app test/app binary latest "$CASE_ROOT/target"
  test -s "$CASE_ROOT/fallback"
  assert_eq "$(< "$HOME/.app")" '2.0.0'
}

prebuild_zip() {
  PIN_JSON='{"draft":false,"prerelease":false,"tag_name":"v2.0.0","assets":[{"browser_download_url":"https://codeberg.org/test/app/releases/download/v2.0.0/app.zip"}]}'
  (cd "$CASE_ROOT/archive" && zip -qr "$CASE_ROOT/asset.zip" app)
  ASSET="$CASE_ROOT/asset.zip"
  fetch_and_deploy_codeberg_release app test/app prebuild v2.0.0 "$CASE_ROOT/target" '*.zip'
  assert_eq "$(< "$CASE_ROOT/target/content")" 'new payload'
}

prebuild_tar() {
  fetch_and_deploy_codeberg_release app test/app prebuild latest "$CASE_ROOT/target" '*.tar.gz'
  assert_eq "$(< "$CASE_ROOT/target/content")" 'new payload'
}

parallel_deployments() {
  printf 'first binary' > "$CASE_ROOT/first.bin"
  printf 'second binary' > "$CASE_ROOT/second.bin"
  (
    RELEASES_JSON='[{"draft":false,"prerelease":false,"tag_name":"v1.0.0","assets":[{"browser_download_url":"https://codeberg.org/test/first/releases/download/v1.0.0/app.bin"}]}]'
    ASSET="$CASE_ROOT/first.bin"
    fetch_and_deploy_codeberg_release first test/first singlefile latest "$CASE_ROOT/first" '*.bin'
  ) &
  local first_pid=$!
  (
    RELEASES_JSON='[{"draft":false,"prerelease":false,"tag_name":"v2.0.0","assets":[{"browser_download_url":"https://codeberg.org/test/second/releases/download/v2.0.0/app.bin"}]}]'
    ASSET="$CASE_ROOT/second.bin"
    fetch_and_deploy_codeberg_release second test/second singlefile latest "$CASE_ROOT/second" '*.bin'
  ) &
  local second_pid=$!
  wait "$first_pid"
  wait "$second_pid"
  assert_eq "$(< "$HOME/.first")" '1.0.0'
  assert_eq "$(< "$HOME/.second")" '2.0.0'
  assert_eq "$(< "$CASE_ROOT/first/first")" 'first binary'
  assert_eq "$(< "$CASE_ROOT/second/second")" 'second binary'
}

tag_mode() {
  fetch_and_deploy_codeberg_release app test/app tag 'version/2' "$CASE_ROOT/target"
  assert_eq "$(< "$HOME/.app")" 'version/2'
  assert_eq "$(< "$CASE_ROOT/target/content")" 'new payload'
}

malformed_metadata() {
  RELEASES_JSON='not json'
  set +e
  fetch_and_deploy_codeberg_release app test/app tarball latest "$CASE_ROOT/target"
  local rc=$?
  set -e
  assert_eq "$rc" 250
  test ! -e "$HOME/.app"
  test ! -e "$CASE_ROOT/target"
}

partial_http_success() {
  CURL_STATUS=18
  set +e
  codeberg_api_call https://codeberg.org/api/v1/repos/test/app/releases "$CASE_ROOT/result"
  local rc=$?
  set -e
  assert_eq "$rc" 22
}

preserve_failed_extract() {
  ASSET="$CASE_ROOT/broken.tar.gz"
  printf 'not an archive' > "$ASSET"
  mkdir "$CASE_ROOT/target"
  printf 'old payload' > "$CASE_ROOT/target/content"
  printf 'old version' > "$HOME/.app"
  set +e
  CLEAN_INSTALL=1 fetch_and_deploy_codeberg_release app test/app tarball latest "$CASE_ROOT/target"
  local rc=$?
  set -e
  assert_eq "$rc" 251
  assert_eq "$(< "$CASE_ROOT/target/content")" 'old payload'
  assert_eq "$(< "$HOME/.app")" 'old version'
}

preserve_failed_copy() {
  mkdir "$CASE_ROOT/target"
  printf 'old payload' > "$CASE_ROOT/target/content"
  printf 'old version' > "$HOME/.app"
  cp() {
    case "$*" in
      *'/app/content'* | *'/app/.'*)
        printf 'real incoming preparation fault\n' > "$CASE_ROOT/copy-fault"
        return 1
        ;;
      *) command cp "$@" ;;
    esac
  }
  set +e
  CLEAN_INSTALL=1 fetch_and_deploy_codeberg_release app test/app tarball latest "$CASE_ROOT/target"
  local rc=$?
  set -e
  assert_eq "$rc" 252
  test -s "$CASE_ROOT/copy-fault"
  assert_eq "$(< "$CASE_ROOT/target/content")" 'old payload'
  assert_eq "$(< "$HOME/.app")" 'old version'
}

singlefile_download_failure() {
  mkdir "$CASE_ROOT/target"
  printf 'old binary' > "$CASE_ROOT/target/app"
  printf 'old version' > "$HOME/.app"
  DOWNLOAD_FAIL=1
  set +e
  fetch_and_deploy_codeberg_release app test/app singlefile latest "$CASE_ROOT/target" '*.tar.gz'
  local rc=$?
  set -e
  assert_eq "$rc" 250
  assert_eq "$(< "$CASE_ROOT/target/app")" 'old binary'
  assert_eq "$(< "$HOME/.app")" 'old version'
}

run_case stable-selection stable_selection
run_case bounded-timeouts timeouts
run_case nonnumeric-v-prefix word_prefix
run_case older-pin pin_outside_first_page
run_case encoded-pin encoded_pin
run_case normalized-pin normalized_pin
run_case empty-release-list empty_metadata
run_case stale-selection-cleared stale_selection
run_case malformed-json malformed_metadata
run_case incomplete-http-200 partial_http_success
run_case failed-extraction-preserves-install preserve_failed_extract
run_case failed-copy-preserves-install preserve_failed_copy
run_case clean-and-merge-semantics clean_and_merge
run_case publish-failure-restores-install rollback_publish
run_case replacing-running-binary replace_running_binary
run_case quiet-binary-fallback quiet_binary_fallback
run_case failed-download-preserves-binary singlefile_download_failure
run_case prebuild-zip prebuild_zip
run_case prebuild-tar prebuild_tar
run_case independent-concurrent-deployments parallel_deployments
run_case direct-tag tag_mode
printf '%s failure(s)\n' "$failures"
test "$failures" -eq 0
