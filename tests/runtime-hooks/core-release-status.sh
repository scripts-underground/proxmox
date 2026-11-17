#!/usr/bin/env bash
# Actual checker/selection owners and cold addon hooks; HTTP/package effects modeled.
set -euo pipefail
ROOT=$(realpath "$(dirname "${BASH_SOURCE[0]}")/../..")
if [[ "${1:-}" == --child ]]; then
  c=$CASE_ROOT
  source "$ROOT/misc/tools.func"
  export HOME=$c/home STD=''
  mkdir -p "$HOME"
  printf '1.2.3\n' > "$HOME/.probe"
  CHECK_UPDATE_RELEASE=stale
  ensure_dependencies() { return "${DEPENDENCY_STATUS:-0}"; }
  getent() { return 0; }
  msg_info() { :; }
  msg_ok() { printf '%s\n' "$*" >> "$c/messages"; }
  msg_warn() { printf '%s\n' "$*" >> "$c/messages"; }
  msg_error() { printf '%s\n' "$*" >> "$c/messages"; }
  prompt_for_github_token() { return 1; }
  sleep() { :; }
  git() { return 22; }
  curl() {
    local out='' url='' body
    while (($#)); do
      case "$1" in -o)
        out=$2
        shift
        ;;
      https:*) url=$1 ;; esac
      shift
    done
    body='{"tag_name":"v1.2.3","draft":false,"prerelease":false,"assets":[]}'
    case "$url" in
      */tags\?*) body='[{"name":"v1.2.3"}]' ;;
      *codeberg.org* | *gitlab.com*/releases\?*) body="[$body]" ;;
    esac
    [[ "${BAD_JSON:-0}" != 1 ]] || body='{broken'
    printf '%s' "$body" > "$out"
    printf 200
    return "${TRANSFER_STATUS:-0}"
  }
  case "$KIND" in
    checker)
      [[ "$CHECKER" != check_for_gh_tag ]] || printf 'v1.2.3\n' > "$HOME/.probe"
      rc=0
      if [[ "${PIN_VERSION:-}" != '' && "$CHECKER" != check_for_gh_tag ]]; then
        "$CHECKER" probe owner/probe "$PIN_VERSION" || rc=$?
      else
        "$CHECKER" probe owner/probe || rc=$?
      fi
      printf '%s' "$CHECK_UPDATE_RELEASE" > "$c/selected"
      exit "$rc"
      ;;
    addon)
      sed "s|/var/lib/scripts-underground/update-pending|$c/pending|g; s|/var/lib/scripts-underground/maintenance-locks|$c/locks|g" "$ROOT/misc/core.func" > "$c/core.func"
      source "$c/core.func"
      sed "s|/root/|$c/flags/|g" "$ROOT/misc/error_handler.func" > "$c/error.func"
      source "$c/error.func"
      load_functions
      msg_info() { :; }
      msg_ok() { printf '%s\n' "$*" >> "$c/messages"; }
      msg_warn() { printf '%s\n' "$*" >> "$c/messages"; }
      msg_error() { printf '%s\n' "$*" >> "$c/messages"; }
      stop_spinner() { :; }
      cleanup_lxc() { :; }
      # Both real hooks have a status-aware else branch, before any app effects.
      sed -n '/^function update_script() {/,/^}/p' "$ROOT/scripts/addon/$ADDON.sh" > "$c/hook"
      source "$c/hook"
      export BUILD_LOG="$c/active.log" DEBUG_LOGFILE="$c/debug.log" DEV_MODE_KEEP=true
      # shellcheck disable=SC2034 # consumed by sourced core/error owners
      APP=Probe NSAPP=probe SESSION_ID=release-status LXC_REQUIRED_CPU=0 LXC_REQUIRED_RAM=0
      # shellcheck disable=SC2034 # consumed by the actual sourced cronmaster hook
      var_addon_repo=owner/probe
      printf '1.2.3\n' > "$HOME/.$ADDON"
      systemctl() { printf service >> "$c/effects"; }
      _gh_deploy_archive_binary() { printf deploy >> "$c/effects"; }
      fetch_and_deploy_gh_release() { printf deploy >> "$c/effects"; }
      catch_errors
      run_update_script
      ;;
    refs)
      # Native ls-remote reads real local ref objects; only its transport is local.
      git() { command git ls-remote --tags "$REF_REPOSITORY"; }
      curl() {
        local out=''
        while (($#)); do
          if [[ "$1" == -o ]]; then
            out=$2
            shift
          fi
          shift
        done
        printf '{"message":"Forbidden"}' > "$out"
        printf 403
        return 22
      }
      rc=0
      _gh_release_json owner/probe "$REQUESTED" '' "$c/metadata" || rc=$?
      if [[ "$rc" == 0 ]]; then cat "$c/metadata"; fi
      exit "$rc"
      ;;
  esac
  exit 99
fi
: "${TMPDIR:?disk-backed fixture root required}"
work=$(mktemp -d "$TMPDIR/core-release-status.XXXXXXXX")
trap 'rm -rf -- "$work"' EXIT
failures=0
check() {
  if [[ "$1" == "$2" ]]; then printf 'PASS %s\n' "$3"; else
    printf 'FAIL %s: expected <%s>, got <%s>\n' "$3" "$2" "$1" >&2
    failures=$((failures + 1))
  fi
}
for checker in check_for_gh_release check_for_gh_tag check_for_codeberg_release check_for_gl_release; do
  for kind in no-update force curl1 partial18 dependency1 malformed; do
    c=$work/$checker-$kind
    mkdir -p "$c"
    transfer=0 dependency=0 force=0 bad=0
    case "$kind" in curl1) transfer=1 ;; partial18) transfer=18 ;; dependency1) dependency=1 ;; force) force=1 ;; malformed) bad=1 ;; esac
    rc=0
    env -i PATH="$PATH" HOME="$c" TMPDIR="$TMPDIR" CASE_ROOT="$c" KIND=checker CHECKER="$checker" \
      TRANSFER_STATUS="$transfer" DEPENDENCY_STATUS="$dependency" UPDATE_FORCE="$force" BAD_JSON="$bad" \
      bash "$0" --child > "$c/output" 2>&1 || rc=$?
    case "$kind" in
      no-update) check "$rc" 1 "$checker verified no-update is exactly1" ;;
      force) check "$rc" 0 "$checker force still reports due" ;;
      *)
        check "$((rc > 1))" 1 "$checker/$kind failure cannot masquerade as no update"
        check "$(cat "$c/selected" 2> /dev/null || true)" '' "$checker/$kind clears stale selected release"
        if [[ "$kind" == partial18 && "$checker" != check_for_codeberg_release ]]; then
          check "$rc" 18 "$checker retains native partial-transfer status"
        fi
        ;;
    esac
  done
done
for transfer in 0 1 18; do
  c=$work/gitlab-pinned-$transfer
  mkdir -p "$c"
  rc=0
  env -i PATH="$PATH" HOME="$c" TMPDIR="$TMPDIR" CASE_ROOT="$c" KIND=checker CHECKER=check_for_gl_release \
    PIN_VERSION=v1.2.3 TRANSFER_STATUS="$transfer" bash "$0" --child > "$c/output" 2>&1 || rc=$?
  expected=$transfer
  if [[ "$transfer" == 0 ]]; then expected=1; elif [[ "$transfer" == 1 ]]; then expected=2; fi
  check "$rc" "$expected" 'GitLab pinned request completes before no-update classification or list fallback'
done
for addon in filebrowser cronmaster; do
  for transfer in 0 1 18; do
    c=$work/addon-$addon-$transfer
    mkdir -p "$c/flags"
    rc=0
    env -i PATH="$PATH" HOME="$c" TMPDIR="$TMPDIR" CASE_ROOT="$c" KIND=addon ADDON="$addon" TRANSFER_STATUS="$transfer" \
      bash "$0" --child > "$c/output" 2>&1 || rc=$?
    if [[ "$transfer" == 0 ]]; then expected=0; else
      expected=$transfer
      [[ "$expected" != 1 ]] || expected=2
    fi
    check "$rc" "$expected" "$addon actual cold hook terminal status for curl$transfer"
    check "$(test -e "$c/pending/probe" && printf yes || printf no)" "$(test "$transfer" != 0 && printf yes || printf no)" "$addon real pending owner retains only failed check"
    check "$(test -e "$c/effects" && printf yes || printf no)" no "$addon failed/current checker never reaches app effects"
  done
done
refs=$work/refs.git
command git init --bare --quiet "$refs"
first=$(printf first | command git --git-dir="$refs" hash-object -w --stdin)
second=$(printf second | command git --git-dir="$refs" hash-object -w --stdin)
command git --git-dir="$refs" update-ref refs/tags/1.2.3 "$first"
command git --git-dir="$refs" update-ref refs/tags/v1.2.3 "$second"
for request in 1.2.3 v1.2.3; do
  c=$work/refs-$request
  mkdir -p "$c"
  rc=0
  env -i PATH="$PATH" HOME="$c" TMPDIR="$TMPDIR" CASE_ROOT="$c" KIND=refs REQUESTED="$request" REF_REPOSITORY="$refs" \
    bash "$0" --child > "$c/output" 2>&1 || rc=$?
  check "$rc" 0 "native Git fallback finds literal $request"
  check "$(jq -r .tag_name "$c/output" 2> /dev/null || true)" "$request" 'distinct numeric-v objects never replace the requested tag'
done
command git --git-dir="$refs" update-ref -d refs/tags/1.2.3
c=$work/refs-absent
mkdir -p "$c"
rc=0
env -i PATH="$PATH" HOME="$c" TMPDIR="$TMPDIR" CASE_ROOT="$c" KIND=refs REQUESTED=1.2.3 REF_REPOSITORY="$refs" \
  bash "$0" --child > "$c/output" 2>&1 || rc=$?
check "$((rc > 1))" 1 'missing literal tag cannot infer object identity from numeric-v normalization'
check "$(cat "$c/output")" '' 'unverified alternate emits no selected metadata'
printf 'RUNTIME_HOOKS_RESULT failures=%s\n' "$failures"
[[ "$failures" == 0 ]]
