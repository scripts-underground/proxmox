#!/usr/bin/env bash
# Plain lifecycle/cache outcomes. Default RED maps filesystem literals in subject
# copies; --native uses unmodified source in private disk-backed bind fixtures.
# Package/language executables are modeled; their real caches are never touched.
set -euo pipefail
systemd-detect-virt --vm --quiet || exit 1
: "${TMPDIR:?provide an existing disk-backed temporary directory}"
TMPDIR=$(realpath -e -- "$TMPDIR")
export TMPDIR
case "$TMPDIR" in /tmp | /tmp/*) exit 1 ;; esac
case "$(findmnt -rn -T "$TMPDIR" -o FSTYPE)" in '' | tmpfs | ramfs) exit 1 ;; esac
ROOT=$(realpath "$(dirname "${BASH_SOURCE[0]}")/..")

if [[ "${1:-}" == --child ]]; then
  kind="$2" native="$3" mode="$4"
  if [[ "$native" == 1 ]]; then
    mount --bind "$FIXTURE_HOME" /root
    mount --bind "$FIXTURE_VAR_TMP" /var/tmp
    mount --bind "$FIXTURE_CACHE" /var/cache
    mkdir -p /var/lib/scripts-underground/update-pending
    mount --bind "$FIXTURE_STATE" /var/lib/scripts-underground/update-pending
    source "$ROOT/misc/core.func"
  else
    source "$CASE_ROOT/core-subject.func"
  fi
  source "$ROOT/misc/error_handler.func"
  if [[ "$kind" != fallback ]]; then
    # Keep actual install definitions/OS reads, excluding only its network bootstrap.
    sed '/^_bootstrap$/d' "$ROOT/misc/install.func" > "$CASE_ROOT/install-definitions.sh"
    source "$CASE_ROOT/install-definitions.sh"
  fi
  load_functions
  stop_spinner() { :; }
  msg_info() { printf 'cleanup-enter\n' >> "$CASE_ROOT/events"; }
  msg_ok() { :; }
  msg_warn() { printf 'warning %s\n' "$*" >> "$CASE_ROOT/events"; }
  apt() { printf 'apt %s\n' "$*" >> "$CASE_ROOT/commands"; }
  apt-get() {
    printf 'apt-get %s\n' "$*" >> "$CASE_ROOT/commands"
    [[ "$kind" != pkg-exit ]] || exit 49
    [[ "$kind" != pkg-fail ]] || return 47
  }
  dnf() { printf 'dnf %s\n' "$*" >> "$CASE_ROOT/commands"; }
  pip() { :; }
  uv() { :; }
  npm() { :; }
  yarn() { :; }
  pnpm() { printf 'pnpm %s\n' "$*" >> "$CASE_ROOT/commands"; }
  go() { printf 'go %s\n' "$*" >> "$CASE_ROOT/commands"; }
  cargo() { :; }
  gem() { :; }
  composer() { :; }
  if [[ "$kind" == nonapt ]]; then
    export PKG_MANAGER=dnf
  fi
  export VERBOSE="$mode"
  set_std_mode
  catch_errors
  check_for_gh_release() { return 1; }
  update_script() {
    printf 'hook\n' >> "$CASE_ROOT/events"
    case "$kind" in
      exit) exit 0 ;;
      no-op)
        if check_for_gh_release; then
          printf 'deployment\n' > "$CASE_ROOT/deployment"
        fi
        exit 0
        ;;
      hook-cleanup)
        cleanup_lxc
        exit 0
        ;;
      failure)
        bash -c 'exit 37'
        printf 'incorrectly-reached\n' > "$CASE_ROOT/after-failure"
        ;;
    esac
    return 0
  }
  run_update_script
fi

native=0
[[ "${1:-}" != --native ]] || native=1
work=$(mktemp -d "$TMPDIR/maintenance-cleanup.XXXXXX")
trap 'rm -rf -- "$work"' EXIT
mkdir -p "$work/subjects"
sed -e 's|/var/lib/scripts-underground/update-pending|${FIXTURE_STATE}|g' \
  -e 's|/var/cache/apk|${FIXTURE_CACHE}/apk|g' \
  -e 's|/var/tmp|${FIXTURE_VAR_TMP}|g' \
  -e 's|/tmp|${FIXTURE_TMP}|g' -e 's|/root|${FIXTURE_HOME}|g' \
  "$ROOT/misc/core.func" > "$work/subjects/core.func"
failures=0
check() {
  if [[ "$1" == "$2" ]]; then printf 'PASS %s\n' "$3"; else
    printf 'FAIL %s: expected <%s>, got <%s>\n' "$3" "$2" "$1" >&2
    failures=$((failures + 1))
  fi
}
for mode in no yes; do
  for kind in return exit no-op hook-cleanup failure pkg-fail pkg-exit nonapt fallback systemlike; do
    root="$work/$mode-$kind"
    mkdir -p "$root/home" "$root/tmp" "$root/var-tmp" "$root/cache/apk" "$root/state"
    cp "$work/subjects/core.func" "$root/core-subject.func"
    for path in .cache/pip .cache/uv .npm/_cacache .npm/_logs .cache/yarn .yarn/cache .cargo/registry/cache .gem/cache .composer/cache; do
      mkdir -p "$root/home/$path"
      printf 'cached\n' > "$root/home/$path/payload"
    done
    mkdir -p "$root/home/go/pkg/mod" "$root/home/.cargo/registry/src"
    printf 'module data\n' > "$root/home/go/pkg/mod/keep"
    printf 'source data\n' > "$root/home/.cargo/registry/src/keep"
    printf 'unrelated\n' > "$root/unrelated"
    selected_tmp="$root/tmp"
    [[ "$kind" != systemlike ]] || selected_tmp="$root/usr/lib/python3.13"
    mkdir -p "$selected_tmp/nested"
    printf 'user tmp content\n' > "$selected_tmp/tmp-user-data"
    printf 'library content\n' > "$selected_tmp/nested/tempfile.py"
    printf 'shared temp content\n' > "$root/var-tmp/tempfile-user-data"
    : > "$root/events"
    : > "$root/commands"
    prefix=()
    [[ "$native" != 1 ]] || prefix=(unshare -m --propagation private --)
    rc=0
    timeout --signal=TERM --kill-after=5s 25s env -i PATH="$PATH" BASH_ENV=/dev/null \
      TMPDIR="$selected_tmp" HOME="$root/home" CASE_ROOT="$root" \
      FIXTURE_HOME="$root/home" FIXTURE_TMP="$root/tmp" FIXTURE_VAR_TMP="$root/var-tmp" \
      FIXTURE_CACHE="$root/cache" FIXTURE_STATE="$root/state" \
      BUILD_LOG="$root/active.log" DEBUG_LOGFILE="$root/error.log" DEV_MODE_KEEP=true NSAPP=cleanup-probe APP=CleanupProbe \
      "${prefix[@]}" bash "$0" --child "$kind" "$native" "$mode" > "$root/output" 2>&1 || rc=$?
    expected=0
    [[ "$kind" != failure ]] || expected=37
    check "$rc" "$expected" "$mode/$kind original exit status"
    [[ "$rc" == "$expected" ]] || cat "$root/output" >&2
    expected_cleanup=1
    [[ "$kind" != failure ]] || expected_cleanup=0
    check "$(grep -c '^cleanup-enter$' "$root/events" || true)" "$expected_cleanup" "$mode/$kind cleanup runs exactly when due, once"
    flag=absent
    [[ ! -e "$root/state/cleanup-probe" ]] || flag=present
    expected_flag=absent
    [[ "$kind" != failure ]] || expected_flag=present
    check "$flag" "$expected_flag" "$mode/$kind pending state follows hook outcome"
    if [[ "$kind" != failure && "$kind" != pkg-exit ]]; then
      check "$(test -e "$root/home/.cache/pip/payload" && printf present || printf absent)" absent "$mode/$kind real language cache removed after install definitions"
      if [[ "$kind" == nonapt ]]; then
        check "$(grep -c '^dnf ' "$root/commands" || true)" 2 "$mode/$kind real package abstraction selects dnf"
      elif [[ "$kind" == fallback ]]; then
        check "$(grep -c '^apt ' "$root/commands" || true)" 3 "$mode/$kind standalone apt fallback retained"
      else
        check "$(grep -c '^apt-get ' "$root/commands" || true)" 2 "$mode/$kind real pkg_clean selected without duplicate apt cleanup"
      fi
    fi
    check "$(cat "$root/home/go/pkg/mod/keep" "$root/home/.cargo/registry/src/keep" "$root/unrelated")" $'module data\nsource data\nunrelated' "$mode/$kind noncache data preserved"
    check "$(test -e "$root/after-failure" && printf reached || printf absent)" absent "$mode/$kind failed hook cannot continue"
    check "$(cat "$selected_tmp/tmp-user-data" "$selected_tmp/nested/tempfile.py" "$root/var-tmp/tempfile-user-data" 2> /dev/null || true)" $'user tmp content\nlibrary content\nshared temp content' "$mode/$kind unrelated tmp/tempfile files preserved"
    if [[ "$kind" == no-op ]]; then
      check "$(test -e "$root/deployment" && printf reached || printf absent)" absent "$mode/no-op no deployment still classifies as successful cleanup"
    fi
  done
done
printf '%s failure(s); native-source=%s; package/language executables modeled\n' "$failures" "$native"
[[ "$failures" == 0 ]]
