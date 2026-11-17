#!/usr/bin/env bash
# shellcheck disable=SC2034,SC2154
set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/../lib/runtime-hooks/harness.sh"
app=homebrew script_type=addon
variants=(fresh download empty installer-failure occupied update missing missing-user brew-failure uninstall)
hook_paths=()
runtime_hooks_variant() {
  case "$variant" in
    download | empty | installer-failure | occupied) role=install fault=$variant ;;
    missing-user | brew-failure) fault=$variant ;;
    uninstall) role=uninstall ;;
  esac
}
runtime_hooks_setup() {
  mkdir -p "$c/opt/brew" "$c/external/brew-user" "$c/etc/profile.d"
  printf 'var_addon_brew_home=/opt/brew\n' > "$c/context.sh"
  printf 'unrelated parent data\n' > "$c/opt/brew/foreign"
  printf 'new-first-account:x:1002:1002::/home/new:/bin/bash\nbrew-owner:x:1001:1001::/home/owner:/bin/bash\n' > "$c/etc/passwd"
  : > "$c/su"
  : > "$c/packages"
  : > "$c/installer"
  : > "$c/brew"
  cat > "$c/brew-model" << 'BREW'
#!/bin/bash
printf '%s\n' "$*" >> "$APP_FIXTURE/brew"
[[ "$1" != shellenv ]] || printf 'export BREW_TEST=loaded\n'
[[ "$APP_FAULT" != brew-failure ]] || exit 44
BREW
  chmod 755 "$c/brew-model"
  if [[ "$role" != install || "$variant" == occupied ]]; then
    mkdir -p "$c/opt/brew/.linuxbrew/bin"
    cp "$c/brew-model" "$c/opt/brew/.linuxbrew/bin/brew"
  fi
  [[ "$variant" != missing ]] || rm -rf "$c/opt/brew/.linuxbrew"
  if [[ "$role" == uninstall ]]; then
    printf '# Homebrew (Linuxbrew)\nif true; then\n  echo integration\nfi\n# foreign shell setup\n' > "$c/external/brew-user/.bashrc"
    printf 'managed profile\n' > "$c/etc/profile.d/homebrew.sh"
  fi
}
runtime_hooks_model() {
  apt() { printf '%s\n' "$*" >> "$c/packages"; }
  groupadd() { :; }
  groupdel() { printf '%s\n' "$*" >> "$c/deleted-group"; }
  usermod() { :; }
  getent() {
    if [[ "$1" == passwd ]]; then
      [[ "$APP_FAULT" != missing-user ]] || return 2
      local name=brew-owner uid=1001
      [[ "$2" != new-first-account ]] || {
        name=new-first-account
        uid=1002
      }
      printf '%s:x:%s:1001::%s:/bin/bash\n' "$name" "$uid" "$c/external/brew-user"
    else command getent "$@"; fi
  }
  stat() {
    if [[ "$*" == '-c %u /opt/brew/.linuxbrew' ]]; then printf '1001\n'; else command stat "$@"; fi
  }
  su() {
    printf '%s\n' "$*" >> "$c/su"
    local cmd=''
    while (($#)); do
      [[ "$1" != -c ]] || {
        cmd=$2
        shift
      }
      shift
    done
    export c
    export -f curl
    bash -c "$cmd"
  }
  curl() {
    local out=''
    while (($#)); do
      [[ "$1" != -o ]] || {
        out=$2
        shift
      }
      shift
    done
    [[ -n "$out" ]] || return 22
    [[ "$APP_FAULT" != empty ]] || {
      : > "$out"
      return 0
    }
    cat > "$out" << 'INSTALLER'
#!/bin/bash
set -euo pipefail
printf '%s\n' "$*" >> "$APP_FIXTURE/installer"
[[ "$APP_FAULT" != installer-failure ]] || exit 43
prefix=${1#--path=}
mkdir -p "$prefix/bin"
cp "$APP_FIXTURE/brew-model" "$prefix/bin/brew"
INSTALLER
    [[ "$APP_FAULT" != download ]] || return 22
  }
}
runtime_hooks_expected() {
  case "$variant" in
    download) expected=22 ;;
    empty) expected=251 ;;
    installer-failure) expected=43 ;;
    occupied) expected=65 ;;
    missing) expected=233 ;;
    missing-user) expected=254 ;;
    brew-failure) expected=44 ;;
  esac
}
runtime_hooks_assert() {
  check "$(cat "$c/opt/brew/foreign" 2> /dev/null || true)" 'unrelated parent data' "$app/$variant never removes prefix parent data"
  check "$(test -e "$c/deleted-group" && printf present || printf absent)" absent "$app/$variant does not delete a shared group"
  check "$(find "$c/tmp" -name 'homebrew-installer.*' | wc -l)" 0 "$app/$variant retires its exact installer stage"
  if [[ "$variant" == fresh ]]; then
    check "$(cat "$c/installer")" '--path=/opt/brew/.linuxbrew' "$app official installer receives selected prefix"
    check "$(test -x "$c/opt/brew/.linuxbrew/bin/brew" && printf present || printf absent)" present "$app selected executable exists"
    check "$(grep -Fc '/opt/brew/.linuxbrew/bin/brew' "$c/etc/profile.d/homebrew.sh" || true)" 1 "$app profile consumes selected executable"
  fi
  case "$variant" in
    update | brew-failure | uninstall)
      check "$(grep -c 'brew-owner' "$c/su" || true)" "$([[ "$variant" == uninstall ]] && printf 0 || printf 1)" "$app/$variant maintenance uses installed prefix owner, not first account"
      check "$(grep -c 'new-first-account' "$c/su" || true)" 0 "$app/$variant cannot drift to another login account"
      ;;
    download | empty | occupied)
      check "$(stat -c %s "$c/installer")" 0 "$app/$variant cannot execute partial installer"
      ;;
    missing | missing-user) check "$(stat -c %s "$c/su")" 0 "$app/$variant refuses before target account effects" ;;
  esac
  if [[ "$variant" == uninstall ]]; then
    check "$(cat "$c/external/brew-user/.bashrc")" '# foreign shell setup' "$app uninstall removes only owner shell integration"
    check "$(test -e "$c/opt/brew/.linuxbrew" && printf present || printf absent)" absent "$app uninstall removes selected prefix only"
  fi
}
runtime_hooks_retry_needed() { return 1; }
runtime_hooks_main "$@"
