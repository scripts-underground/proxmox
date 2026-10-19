#!/usr/bin/env bash
# Fail real producer boundaries even when the public builder is conditional.
set -euo pipefail
systemd-detect-virt --vm --quiet || exit 1
: "${TMPDIR:?provide a disk-backed temporary directory}"
case "$(realpath -e "$TMPDIR")" in /tmp | /tmp/*) exit 1 ;; esac
case "$(findmnt -rn -T "$TMPDIR" -o FSTYPE)" in '' | tmpfs | ramfs) exit 1 ;; esac
ROOT=$(realpath "$(dirname "${BASH_SOURCE[0]}")/..")
if [[ "${1:-}" == --child ]]; then
  fault="$2" style="$3" c="$CASE_ROOT"
  source "$ROOT/misc/bundle.func"
  export APP=Writer NSAPP=writer REPO_BASE=offline SESSION_ID=writer CTID=2110
  export var_lxc_fixture_private=fixture-only-value
  msg_debug() { :; }
  msg_error() { printf '%s\n' "$*" >&2; }
  install_script() { :; }
  _framework_cache_ensure() {
    [[ "$fault" != missing ]] || rm -- "$TMPDIR/framework-writer/install.func"
    [[ "$fault" != hook ]] || unset -f install_script
  }
  cat() {
    [[ "$fault" != cat || "${1:-}" != */tools.func ]] || return 47
    command cat "$@"
  }
  mktemp() {
    local path
    [[ "$fault" != allocate ]] || return 49
    path=$(command mktemp "$@") || return $?
    printf '%s\n' "$path" > "$c/stage-path"
    if [[ "$fault" == write ]]; then
      rm -- "$path"
      ln -s /dev/full "$path"
    fi
    printf '%s\n' "$path"
  }
  printf() {
    [[ "$fault" != printf || "$1" != 'declare -- APP=%q\n' ]] || return 48
    builtin printf "$@"
  }
  pct() {
    printf '%s\n' "$*" >> "$c/published"
    case "$1" in
      push)
        if [[ "$fault" == push ]]; then
          printf 'partial transport\n' > "$4"
          return 53
        fi
        cp -- "$3" "$4"
        ;;
      exec)
        shift 3
        case "$1:$fault" in chmod:chmod) return 54 ;; mv:publish) return 55 ;; esac
        if [[ "$1" == mktemp ]]; then
          local receiver
          receiver=$(command "$@") || return $?
          printf '%s\n' "$receiver" > "$c/receiver-stage"
          printf '%s\n' "$receiver"
        else
          command "$@"
        fi
        ;;
    esac
  }
  if [[ "$style" == conditional ]]; then
    # Every producer must check itself even when callers deliberately handle rc.
    if build_bundle install install_script "$c/destination" 0700 install_script; then
      exit 0
    else
      exit $?
    fi
  fi
  build_bundle install install_script "$c/destination" 0700 install_script
  exit 0
fi
work=$(mktemp -d "$TMPDIR/maintenance-writer.XXXXXX")
trap 'rm -rf -- "$work"' EXIT
failures=0
check() {
  if [[ "$1" == "$2" ]]; then printf 'PASS %s\n' "$3"; else
    printf 'FAIL %s: expected <%s>, got <%s>\n' "$3" "$2" "$1" >&2
    failures=$((failures + 1))
  fi
}
for style in conditional plain; do
  for fault in allocate cat missing printf hook write push chmod publish none; do
    c="$work/$style-$fault"
    mkdir -p "$c/tmp/framework-writer"
    for lib in core error_handler install tools github; do printf '# fixture library\n' > "$c/tmp/framework-writer/$lib.func"; done
    printf 'previous valid command\n' > "$c/destination"
    cp "$c/destination" "$c/previous"
    rc=0
    TMPDIR="$c/tmp" CASE_ROOT="$c" bash "$0" --child "$fault" "$style" > "$c/output" 2>&1 || rc=$?
    expected=0
    [[ "$fault" != cat ]] || expected=47
    [[ "$fault" != printf ]] || expected=48
    [[ "$fault" != allocate ]] || expected=49
    [[ "$fault" != push ]] || expected=53
    [[ "$fault" != chmod ]] || expected=54
    [[ "$fault" != publish ]] || expected=55
    [[ "$fault" != missing && "$fault" != write && "$fault" != hook ]] || expected=1
    check "$rc" "$expected" "$style/$fault exact producer status"
    stage=''
    [[ ! -e "$c/stage-path" ]] || stage=$(cat "$c/stage-path")
    check "$(if [[ -e "$stage" || -L "$stage" ]]; then printf present; else printf absent; fi)" absent "$style/$fault owned private stage removed"
    if [[ "$fault" != none && "$fault" != push && "$fault" != chmod && "$fault" != publish ]]; then
      check "$(test -e "$c/published" && printf reached || printf absent)" absent "$fault never publishes a partial bundle"
    fi
    if [[ "$fault" != none ]]; then
      check "$(cmp -s "$c/previous" "$c/destination" && printf same || printf changed)" same "$style/$fault receiving previous command preserved"
      check "$(stat -c %a "$c/destination")" "$(stat -c %a "$c/previous")" "$style/$fault receiving previous mode preserved"
    else
      check "$(wc -l < "$c/published")" 4 'success stages, transports, sets mode and publishes'
    fi
    if [[ -f "$c/receiver-stage" ]]; then
      check "$(test -e "$(cat "$c/receiver-stage")" && printf present || printf absent)" absent "$style/$fault owned receiving stage removed"
    fi
  done
done
printf '%s failure(s); actual writer, missing cache and ENOSPC sink; pct modeled\n' "$failures"
[[ "$failures" == 0 ]]
