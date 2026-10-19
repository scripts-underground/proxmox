#!/usr/bin/env bash
# Actual addon serializer/publication under its real conditional-caller contract.
set -euo pipefail
systemd-detect-virt --vm --quiet || exit 1
: "${TMPDIR:?provide disk-backed TMPDIR}"
case "$(realpath -e "$TMPDIR")" in /tmp | /tmp/*) exit 1 ;; esac
case "$(findmnt -rn -T "$TMPDIR" -o FSTYPE)" in '' | tmpfs | ramfs) exit 1 ;; esac
ROOT=$(realpath "$(dirname "${BASH_SOURCE[0]}")/..")
work=$(mktemp -d "$TMPDIR/maintenance-addon-writer.XXXXXX")
trap 'rm -rf -- "$work"' EXIT
failures=0
check() {
  if [[ "$1" == "$2" ]]; then printf 'PASS %s\n' "$3"; else
    printf 'FAIL %s: expected <%s>, got <%s>\n' "$3" "$2" "$1" >&2
    failures=$((failures + 1))
  fi
}
for fault in cat missing context write chmod link publish none; do
  c="$work/$fault"
  mkdir -p "$c/stage" "$c/sbin" "$c/bin"
  printf 'load_functions() { :; }; color() { :; }; run_update_script() { update_script; }\n' > "$c/stage/core.func"
  printf 'catch_errors() { :; }\n' > "$c/stage/error_handler.func"
  printf 'pkg_install() { :; }\n' > "$c/stage/install.func"
  printf 'fetch_and_deploy_gh_release() { :; }\n' > "$c/stage/tools.func"
  printf 'clone_and_deploy_gh_commit() { :; }\n' > "$c/stage/github.func"
  printf 'addon_baseline() { :; }\n' > "$c/stage/addon.func"
  printf '#!/bin/bash\nprintf "PREVIOUS_VALID\\n"\n' > "$c/sbin/update_probe"
  chmod 0755 "$c/sbin/update_probe"
  cp -p "$c/sbin/update_probe" "$c/previous"
  [[ "$fault" != missing ]] || rm "$c/stage/tools.func"
  sed -e "s|/usr/local/sbin|$c/sbin|g" -e "s|/usr/bin|$c/bin|g" "$ROOT/misc/addon_lxc.func" > "$c/subject.func"
  rc=0
  (
    source "$c/subject.func"
    export APP=Probe APP_SLUG=probe REPO_BASE=offline
    update_script() { printf 'NEW_RESULT\n'; }
    cat() {
      [[ "$fault" != cat || "${1:-}" != */tools.func ]] || return 47
      if [[ "$fault" == write ]]; then command cat "$@" > /dev/full; else command cat "$@"; fi
    }
    printf() {
      [[ "$fault" != context || "$1" != 'declare -- APP=%q\n' ]] || return 48
      builtin printf "$@"
    }
    chmod() {
      [[ "$fault" != chmod ]] || return 49
      command chmod "$@"
    }
    ln() {
      [[ "$fault" != link ]] || return 50
      command ln "$@"
    }
    mv() {
      [[ "$fault" != publish ]] || return 51
      command mv "$@"
    }
    mktemp() {
      local path
      path=$(command mktemp "$@") || return $?
      builtin printf '%s\n' "$path" >> "$c/owned-stages"
      builtin printf '%s\n' "$path"
    }
    if _addon_bundle_write update update_script "$c/stage"; then exit 0; else exit $?; fi
  ) > "$c/output" 2>&1 || rc=$?
  case "$fault" in cat) expected=47 ;; missing | write) expected=1 ;; context) expected=48 ;; chmod) expected=49 ;; link) expected=50 ;; publish) expected=51 ;; none) expected=0 ;; esac
  check "$rc" "$expected" "$fault exact addon producer/publication status"
  if [[ "$fault" != none ]]; then
    check "$(cmp -s "$c/previous" "$c/sbin/update_probe" && printf same || printf changed)" same "$fault previous valid bundle bytes preserved"
    check "$(stat -c %a "$c/sbin/update_probe")" 755 "$fault previous bundle mode preserved"
  else
    check "$(bash "$c/sbin/update_probe")" NEW_RESULT 'success atomically publishes executable consumer result'
  fi
  if [[ -f "$c/owned-stages" ]]; then
    while IFS= read -r stage; do
      check "$(test -e "$stage" && printf present || printf absent)" absent "$fault owned stage removed"
    done < "$c/owned-stages"
  fi
done
printf '%s failure(s); actual addon writer/files/publication, injected fault boundaries\n' "$failures"
[[ "$failures" == 0 ]]
