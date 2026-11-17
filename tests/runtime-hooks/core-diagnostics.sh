#!/usr/bin/env bash
# Actual Bash commands, same-shell silent and fatal handler; only UI paths isolated.
set -euo pipefail
ROOT=$(realpath "$(dirname "${BASH_SOURCE[0]}")/../..")
if [[ "${1:-}" == --child ]]; then
  c=$CASE_ROOT
  source "$ROOT/misc/core.func"
  sed "s|/root/|$c/root/|g" "$ROOT/misc/error_handler.func" > "$c/error.func"
  source "$c/error.func"
  load_functions
  stop_spinner() { :; }
  msg_error() { printf 'ERROR %s\n' "$*"; }
  export BUILD_LOG="$c/active.log" DEBUG_LOGFILE="$c/debug.log" DEV_MODE_KEEP=true
  export INSTALL_LOG="$c/active.log" SESSION_ID=diagnostics
  export VERBOSE=$MODE
  unset CTID
  set_std_mode
  MY_SECRET='native-private-value'
  GITHUB_TOKEN='fixture-private-token'
  : > "$INSTALL_LOG"
  emit_failure() {
    printf 'prior-context\n'
    printf 'password=literal-not-in-env\nAuthorization: Bearer literal-bearer-value\n'
    printf 'https://operator:literal-url-password@example.invalid/\n'
    printf 'known %s and %s\n' "$MY_SECRET" "$GITHUB_TOKEN"
    printf '%120000s\n' x
    printf 'final-useful-cause: native fixture refused\n'
    return 255
  }
  catch_errors
  case "$KIND" in
    generic) bash -c 'exit 255' ;;
    missing) core_u6_missing_executable ;;
    nested127) bash -c 'exit 127' ;;
    quoted127) 'core u6 missing executable' ;;
    quiet) silent emit_failure --token 'literal-arg-secret' ;;
    retry)
      silent emit_failure || :
      bash -c 'exit 43'
      ;;
    command-secret) error_handler 255 'password=literal-command-secret bash -c true' ;;
    diagnostic-failure)
      _error_redact() { return 42; }
      DEBUG_LOGFILE=$c/root
      error_handler 255 literal_native_command
      ;;
    producer)
      printf '#!/bin/bash\nexit 255\n' > "$c/dpkg"
      chmod +x "$c/dpkg"
      "$c/dpkg"
      ;;
  esac
  exit 99
fi
: "${TMPDIR:?disk-backed fixture root required}"
work=$(mktemp -d "$TMPDIR/core-diagnostics.XXXXXXXX")
trap 'rm -rf -- "$work"' EXIT
failures=0
check() {
  if [[ "$1" == "$2" ]]; then printf 'PASS %s\n' "$3"; else
    printf 'FAIL %s: expected <%s>, got <%s>\n' "$3" "$2" "$1" >&2
    failures=$((failures + 1))
  fi
}
for mode in no yes; do
  for kind in generic missing nested127 quoted127 quiet retry command-secret diagnostic-failure producer; do
    c=$work/$mode-$kind
    mkdir -p "$c/root" "$c/home"
    status=0
    env -i PATH="$PATH" HOME="$c/home" TMPDIR="$TMPDIR" CASE_ROOT="$c" MODE="$mode" KIND="$kind" \
      bash "$0" --child > "$c/output" 2>&1 || status=$?
    expected=255
    case "$kind" in missing | nested127 | quoted127) expected=127 ;; retry) expected=43 ;; esac
    check "$status" "$expected" "$mode/$kind exact producer status"
    check "$(cat "$c/root/.install-diagnostics.failed" 2> /dev/null || true)" "$expected" "$mode/$kind existing failure-flag owner"
    check "$(grep -c 'DPKG: Fatal internal error' "$c/output" || true)" 0 "$mode/$kind no status-only DPKG claim"
    if [[ "$kind" == missing ]]; then
      check "$(grep -c 'core_u6_missing_executable.*not.*PATH' "$c/output" || true)" 1 "$mode missing command identified only from unambiguous producer"
    elif [[ "$kind" == nested127 || "$kind" == quoted127 ]]; then
      check "$(grep -c 'is not installed\|not on PATH' "$c/output" || true)" 0 "$mode/$kind no guessed missing command"
    fi
    if [[ "$kind" == quiet ]]; then
      check "$(grep -c 'final-useful-cause: native fixture refused' "$c/output" || true)" 1 "$mode useful final output survives minified line"
      check "$(test "$(wc -c < "$c/output")" -lt 16000 && printf yes || printf no)" yes "$mode diagnostic rendering is bounded"
      for secret in native-private-value fixture-private-token literal-not-in-env literal-bearer-value literal-url-password literal-arg-secret; do
        check "$(grep -Fl "$secret" "$c/output" "$c/debug.log" | wc -l)" 0 "$mode terminal/debug summary redacts sensitive data"
      done
      check "$(grep -c 'Failed command.*emit_failure' "$c/active.log" || true)" 1 "$mode actual silent producer recorded without global trace state"
    fi
    if [[ "$kind" == command-secret ]]; then
      check "$(grep -Fl literal-command-secret "$c/output" "$c/debug.log" | wc -l)" 0 "$mode rendered command is redacted before terminal/debug sinks"
    fi
    if [[ "$kind" == retry ]]; then
      check "$(grep -c "Command   : bash -c 'exit 43'" "$c/debug.log" || true)" 1 "$mode handled failure cannot become stale producer"
    fi
  done
done
printf 'RUNTIME_HOOKS_RESULT failures=%s\n' "$failures"
[[ "$failures" == 0 ]]
