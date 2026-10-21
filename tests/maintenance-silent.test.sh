#!/usr/bin/env bash
# Guest-only: real silent/status/log/state and real fatal error-handler outcomes.
set -euo pipefail
systemd-detect-virt --vm --quiet || {
  printf 'Run this test inside an isolated Linux VM.\n' >&2
  exit 1
}
: "${TMPDIR:?provide an existing disk-backed fixture directory}"
case "$TMPDIR" in
  /tmp | /tmp/*)
    printf 'TMPDIR must not use the guest temporary root.\n' >&2
    exit 1
    ;;
esac
export TMPDIR
TMPDIR=$(realpath -e -- "$TMPDIR")
[[ -d "$TMPDIR" && -w "$TMPDIR" ]]
case "$TMPDIR" in
  /tmp | /tmp/*)
    printf 'TMPDIR must not resolve into the guest temporary root.\n' >&2
    exit 1
    ;;
esac
tmp_fstype=$(findmnt --noheadings --raw --output FSTYPE --target "$TMPDIR")
case "$tmp_fstype" in
  '' | *$'\n'* | tmpfs | ramfs)
    printf 'TMPDIR requires a disk-backed filesystem, observed <%s>.\n' "$tmp_fstype" >&2
    exit 1
    ;;
esac
ROOT=$(realpath "$(dirname "${BASH_SOURCE[0]}")/..")

if [[ "${1:-}" == --case ]]; then
  mode="$2" kind="$3" case_root="$4"
  export HOME="$case_root/home" BUILD_LOG="$case_root/active.log"
  export DEBUG_LOGFILE="$case_root/error.log" DEV_MODE_KEEP=true
  unset INSTALL_LOG CTID _CORE_FUNC_LOADED __FUNCTIONS_LOADED
  unset lockfile _UPDATE_PENDING_FLAG CONTAINER_INSTALLING _HOST_LOGFILE
  source "$ROOT/misc/core.func"
  source "$ROOT/misc/error_handler.func"
  load_functions
  # UI-only isolation: never inspect/kill a retained spinner or touch its PID file.
  # silent, logging, trap setup and error_handler remain the actual subjects.
  stop_spinner() { :; }
  export VERBOSE="$mode"
  set_std_mode
  catch_errors
  effect=before
  payload() {
    effect=after
    cd "$case_root/cwd"
    umask 0077
    printf 'payload-out\n'
    printf 'payload-err\n' >&2
    printf '%s\n' "$BASHPID" > "$case_root/command-pid"
    return "${payload_status:-0}"
  }
  pipeline_payload() {
    if [[ -o pipefail ]]; then
      printf 'on\n' > "$case_root/pipeline-option"
    else
      printf 'off\n' > "$case_root/pipeline-option"
    fi
    bash -c 'exit 41' | cat
  }
  case "$kind" in
    success)
      expected_pid="$BASHPID"
      $STD payload
      [[ "$effect" == after && "$PWD" == "$case_root/cwd" && "$(umask)" == 0077 ]]
      [[ "$(< "$case_root/command-pid")" == "$expected_pid" ]]
      printf 'same-shell\n' > "$case_root/reached"
      ;;
    handled-if | handled-or)
      payload_status=37
      rc=0
      if [[ "$kind" == handled-if ]]; then
        if $STD payload; then rc=0; else rc=$?; fi
      else
        $STD payload || rc=$?
      fi
      [[ "$rc" == 37 && "$effect" == after ]]
      payload_status=0
      $STD payload
      printf 'retry-reached\n' > "$case_root/reached"
      ;;
    unhandled)
      payload_status=37
      $STD payload
      printf 'incorrectly-reached\n' > "$case_root/reached"
      ;;
    stale-error)
      payload_status=37
      rc=0
      $STD payload || rc=$?
      [[ "$rc" == 37 ]]
      printf 'handled-first\n' > "$case_root/recovered"
      bash -c 'exit 43'
      printf 'incorrectly-reached\n' > "$case_root/reached"
      ;;
    pipeline | pipeline-off)
      expected_pipeline=41
      if [[ "$kind" == pipeline-off ]]; then
        set +o pipefail
        expected_pipeline=0
      fi
      rc=0
      $STD pipeline_payload || rc=$?
      [[ "$rc" == "$expected_pipeline" ]]
      printf 'pipeline-status-retained\n' > "$case_root/reached"
      ;;
    pipeline-unhandled)
      $STD pipeline_payload
      printf 'incorrectly-reached\n' > "$case_root/reached"
      ;;
    state-on | state-off | state-mixed | state-on-failure | state-off-failure | state-mixed-failure | state-none | state-mutate | state-mutate-failure)
      case "$kind" in
        state-on | state-on-failure | state-none | state-mutate | state-mutate-failure) set -Eeuo pipefail ;;
        state-off | state-off-failure) set +Eeuo pipefail ;;
        state-mixed | state-mixed-failure)
          set -Eu
          set +e +o pipefail
          ;;
      esac
      trap 'printf "caller-trap\n" >> "$case_root/caller-err"' ERR
      [[ "$kind" != state-none ]] || trap - ERR
      # Direct files avoid command substitution changing errexit/trap observation.
      set +o > "$case_root/options-before"
      trap -p ERR > "$case_root/trap-before"
      state_command=payload
      if [[ "$kind" == state-mutate* ]]; then
        mutation_payload() {
          payload
          set +Eeuo pipefail
          trap ':' ERR
          return "${payload_status:-0}"
        }
        state_command=mutation_payload
      fi
      if [[ "$kind" == *-failure ]]; then
        payload_status=37
        rc=0
        silent "$state_command" || rc=$?
        [[ "$rc" == 37 ]] || exit 94
      else
        silent "$state_command"
      fi
      set +o > "$case_root/options-after"
      trap -p ERR > "$case_root/trap-after"
      cmp "$case_root/options-before" "$case_root/options-after" || exit 91
      cmp "$case_root/trap-before" "$case_root/trap-after" || exit 92
      [[ ! -s "$case_root/caller-err" ]] || exit 93
      printf 'state-retained\n' > "$case_root/reached"
      ;;
    *) exit 64 ;;
  esac
  exit 0
fi

work=$(mktemp -d "$TMPDIR/maintenance-silent.XXXXXX")
trap 'rm -rf -- "$work"' EXIT
failures=0
check() {
  if [[ "$1" == "$2" ]]; then
    printf 'PASS %s\n' "$3"
  else
    printf 'FAIL %s: expected <%s>, got <%s>\n' "$3" "$2" "$1" >&2
    failures=$((failures + 1))
  fi
}
for mode in no yes; do
  for kind in success handled-if handled-or unhandled stale-error pipeline pipeline-off pipeline-unhandled state-on state-off state-mixed state-on-failure state-off-failure state-mixed-failure state-none state-mutate state-mutate-failure; do
    case_root="$work/$mode-$kind"
    mkdir -p "$case_root/home" "$case_root/cwd"
    rc=0
    timeout --signal=TERM --kill-after=5 30 env -i PATH="$PATH" TMPDIR="$TMPDIR" BASH_ENV=/dev/null \
      bash "$0" --case "$mode" "$kind" "$case_root" > "$case_root/stdout" 2> "$case_root/stderr" || rc=$?
    expected=0
    case "$kind" in unhandled) expected=37 ;; stale-error) expected=43 ;; pipeline-unhandled) expected=41 ;; esac
    check "$rc" "$expected" "$mode/$kind exact native child status"
    if [[ "$rc" != "$expected" ]]; then
      cat "$case_root/stdout" "$case_root/stderr" >&2
    fi
    if [[ "$kind" == pipeline* ]]; then
      expected_option=on
      [[ "$kind" != pipeline-off ]] || expected_option=off
      observed_option=missing
      if [[ -f "$case_root/pipeline-option" ]]; then
        observed_option=$(< "$case_root/pipeline-option")
      fi
      check "$observed_option" "$expected_option" "$mode/$kind command observes caller pipefail setting"
    fi
    if [[ "$kind" == unhandled || "$kind" == stale-error || "$kind" == pipeline-unhandled ]]; then
      check "$(test -e "$case_root/reached" && printf yes || printf no)" no "$mode/$kind cannot continue"
      if grep -Fq "Exit Code : $expected " "$case_root/error.log"; then
        check yes yes "$mode/$kind actual fatal handler recorded exact status"
      else
        check no yes "$mode/$kind actual fatal handler recorded exact status"
      fi
    else
      check "$(test -s "$case_root/reached" && printf yes || printf no)" yes "$mode/$kind consumer continuation reached"
    fi
    if [[ "$kind" == stale-error ]]; then
      check "$(test -s "$case_root/recovered" && printf yes || printf no)" yes "$mode handled first error before unrelated failure"
      if grep -Fq "Command   : bash -c 'exit 43'" "$case_root/error.log"; then
        check yes yes "$mode later fatal command is not stale payload"
      else
        check no yes "$mode later fatal command is not stale payload"
      fi
    fi
    if [[ "$kind" == success || "$kind" == handled-if || "$kind" == handled-or ]]; then
      if [[ "$mode" == no ]]; then
        if grep -Fq payload-out "$case_root/active.log" && grep -Fq payload-err "$case_root/active.log"; then
          check yes yes "quiet/$kind captures both output streams in actual active log"
        else
          check no yes "quiet/$kind captures both output streams in actual active log"
        fi
        check "$(wc -c < "$case_root/stdout")" 0 "quiet/$kind does not leak command output"
        check "$(wc -c < "$case_root/stderr")" 0 "quiet/$kind does not emit handled-failure diagnostics"
      else
        if grep -Fq payload-out "$case_root/stdout" && grep -Fq payload-err "$case_root/stderr"; then
          check yes yes "verbose/$kind keeps existing STD passthrough"
        else
          check no yes "verbose/$kind keeps existing STD passthrough"
        fi
      fi
    fi
  done
done
printf '%s failure(s)\n' "$failures"
[[ "$failures" == 0 ]]
