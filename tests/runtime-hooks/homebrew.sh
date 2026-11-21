#!/usr/bin/env bash
# shellcheck disable=SC2034,SC2154
set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/../lib/runtime-hooks/harness.sh"
app=homebrew script_type=addon
variants=(fresh literal profile-link canonical invalid-relative invalid-space invalid-colon invalid-dot invalid-double invalid-length invalid-bytes download empty syntax installer-failure occupied update missing missing-user brew-failure uninstall uninstall-link uninstall-edited uninstall-incomplete uninstall-foreign uninstall-system-link)
hook_paths=()
runtime_hooks_variant() {
  case "$variant" in
    literal | profile-link | canonical | invalid-* | download | empty | syntax | installer-failure | occupied) role=install fault=$variant ;;
    missing-user | brew-failure) fault=$variant ;;
    uninstall*) role=uninstall ;;
  esac
}
runtime_hooks_setup() {
  mkdir -p "$c/opt/brew" "$c/external/brew-user" "$c/etc/profile.d"
  printf 'var_addon_brew_home=/opt/brew\n' > "$c/context.sh"
  if [[ "$variant" == literal ]]; then
    printf 'var_addon_brew_home=%q\n' '/opt/$H`x`'"'q" > "$c/context.sh"
  fi
  case "$variant" in
    canonical)
      ln -s brew "$c/opt/alias"
      printf 'var_addon_brew_home=/opt/alias\n' > "$c/context.sh"
      ;;
    invalid-relative) printf 'var_addon_brew_home=relative\n' > "$c/context.sh" ;;
    invalid-space) printf 'var_addon_brew_home=%q\n' '/opt/a b' > "$c/context.sh" ;;
    invalid-colon) printf 'var_addon_brew_home=/opt/a:b\n' > "$c/context.sh" ;;
    invalid-dot) printf 'var_addon_brew_home=/opt/nonexistent/../a\n' > "$c/context.sh" ;;
    invalid-double) printf 'var_addon_brew_home=/opt/nonexistent//a\n' > "$c/context.sh" ;;
    invalid-length) printf 'var_addon_brew_home=/opt/12345678901\n' > "$c/context.sh" ;;
    invalid-bytes) printf 'var_addon_brew_home=/opt/éééééé\n' > "$c/context.sh" ;;
  esac
  printf 'unrelated parent data\n' > "$c/opt/brew/foreign"
  printf 'new-first-account:x:1002:1002::/home/new:/bin/bash\nbrew-owner:x:1001:1001::/home/owner:/bin/bash\n' > "$c/etc/passwd"
  : > "$c/su"
  : > "$c/packages"
  : > "$c/installer"
  : > "$c/brew"
  : > "$c/account-effects"
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
    printf '# before\n\n# Homebrew (Linuxbrew)\nif [ -d "/opt/brew/.linuxbrew" ]; then\n    eval "$(/opt/brew/.linuxbrew/bin/brew shellenv)"\nfi\n# foreign shell setup\n' > "$c/external/brew-user/.bashrc"
    printf '#!/bin/bash\nif [ -d "/opt/brew/.linuxbrew" ]; then\n    eval "$("/opt/brew/.linuxbrew/bin/brew" shellenv)"\nfi\n' > "$c/etc/profile.d/homebrew.sh"
    case "$variant" in
      uninstall-edited) sed -i 's@    eval .*@    echo edited@' "$c/external/brew-user/.bashrc" ;;
      uninstall-incomplete) sed -i '/^fi$/d' "$c/external/brew-user/.bashrc" ;;
      uninstall-foreign) printf 'foreign global profile\n' > "$c/etc/profile.d/homebrew.sh" ;;
      uninstall-system-link)
        mv "$c/etc/profile.d/homebrew.sh" "$c/external/global-profile"
        ln -s "$c/external/global-profile" "$c/etc/profile.d/homebrew.sh"
        ;;
    esac
  fi
  if [[ "$variant" == *link && "$variant" != uninstall-system-link ]]; then
    [[ -e "$c/external/brew-user/.bashrc" ]] || printf '# before\n' > "$c/external/brew-user/.bashrc"
    mv "$c/external/brew-user/.bashrc" "$c/external/actual-profile"
    ln -s ../actual-profile "$c/external/brew-user/.bashrc"
  fi
  [[ ! -f "$c/external/brew-user/.bashrc" ]] || cp -L "$c/external/brew-user/.bashrc" "$c/profile-before"
  [[ ! -f "$c/etc/profile.d/homebrew.sh" ]] || cp -L "$c/etc/profile.d/homebrew.sh" "$c/global-before"
}
runtime_hooks_model() {
  apt() { printf '%s\n' "$*" >> "$c/packages"; }
  groupadd() { printf 'groupadd\n' >> "$c/account-effects"; }
  groupdel() { printf '%s\n' "$*" >> "$c/deleted-group"; }
  usermod() { printf 'usermod\n' >> "$c/account-effects"; }
  useradd() { printf 'useradd\n' >> "$c/account-effects"; }
  chown() { [[ "$APP_FAULT" != prefix-failure ]] || return 45; }
  rmdir() {
    [[ "$APP_FAULT" != cleanup-failure || "${!#}" != /opt/brew/.linuxbrew ]] || return 44
    command rmdir "$@"
  }
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
    printf '%s\0' "$@" >> "$c/su-argv"
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
    [[ "$APP_FAULT" != syntax ]] || {
      printf 'if then\n' > "$out"
      return 0
    }
    cat > "$out" << 'INSTALLER'
#!/bin/bash
set -euo pipefail
printf '%s\n' "$*" >> "$APP_FIXTURE/installer"
[[ "$APP_FAULT" != installer-failure ]] || exit 43
prefix=${1#--path=}
if [[ "$APP_FAULT" == partial-failure ]]; then printf 'external installer data\n' > "$prefix/external"; exit 43; fi
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
    syntax) expected=2 ;;
    invalid-*) expected=65 ;;
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
  if [[ "$variant" == fresh || "$variant" == literal || "$variant" == profile-link || "$variant" == canonical ]]; then
    local selected=/opt/brew/.linuxbrew
    [[ "$variant" != literal ]] || selected='/opt/$H`x`'"'q/.linuxbrew"
    check "$(cat "$c/installer")" "--path=$selected" "$app official installer receives literal selected prefix"
    check "$(test -x "$c/opt/${selected#/opt/}/bin/brew" && printf present || printf absent)" present "$app selected executable exists"
    local profile status
    for profile in "$c/etc/profile.d/homebrew.sh" "$c/external/brew-user/.bashrc" "$c/external/brew-user/.profile"; do
      # Observe future shell consumption, not source text occurrence. /opt is
      # isolated exactly as in the cold bundle. sh is the .profile consumer.
      status=0
      unshare -m --propagation private -- bash -c 'mount --bind "$1/opt" /opt; /bin/sh -c '\''unset BREW_TEST; . "$1"; test "${BREW_TEST:-}" = loaded'\'' observer "$2"' observer "$c" "$profile" > "$c/profile-consumer.log" 2>&1 || status=$?
      check "$status" 0 "$app/$variant literal shellenv reaches consumer $profile"
    done
    check "$(grep -c -- '-s /bin/bash.*new-first-account.*-c' "$c/su" || true)" 3 "$app/$variant profile append executes as resolved account"
  fi
  case "$variant" in
    update | brew-failure | uninstall*)
      check "$(grep -c 'brew-owner' "$c/su" || true)" 1 "$app/$variant maintenance uses installed prefix owner, not first account"
      check "$(grep -c 'new-first-account' "$c/su" || true)" 0 "$app/$variant cannot drift to another login account"
      ;;
    download | empty | syntax | invalid-* | occupied)
      check "$(stat -c %s "$c/installer")" 0 "$app/$variant cannot execute partial installer"
      check "$(stat -c %s "$c/account-effects")" 0 "$app/$variant no account/group effects before admission"
      check "$(test -d "$c/opt/brew/.linuxbrew" && printf present || printf absent)" "$([[ "$variant" == occupied ]] && printf present || printf absent)" "$app/$variant no prefix creation before admission"
      ;;
    missing | missing-user) check "$(stat -c %s "$c/su")" 0 "$app/$variant refuses before target account effects" ;;
  esac
  if [[ "$role" == uninstall ]]; then
    if [[ "$variant" == uninstall-edited || "$variant" == uninstall-incomplete ]]; then
      check "$(cat "$c/external/brew-user/.bashrc")" "$(cat "$c/profile-before")" "$app/$variant preserves unmatched or edited block and tail"
      check "$(grep -ci 'manual' "$c/output" || true)" 1 "$app/$variant reports manual profile cleanup"
    else
      check "$(cat "$c/external/brew-user/.bashrc")" $'# before\n\n# foreign shell setup' "$app/$variant removes only exact complete generated block"
    fi
    check "$(test -e "$c/opt/brew/.linuxbrew" && printf present || printf absent)" absent "$app uninstall removes selected prefix only"
    if [[ "$variant" == uninstall-foreign || "$variant" == uninstall-system-link ]]; then
      check "$(cat "$c/etc/profile.d/homebrew.sh")" "$(cat "$c/global-before")" "$app/$variant retains unowned global profile"
    else check "$(test -e "$c/etc/profile.d/homebrew.sh" && printf present || printf absent)" absent "$app/$variant retires exact global profile"; fi
  fi
  if [[ "$variant" == profile-link || "$variant" == uninstall-link ]]; then
    check "$(readlink "$c/external/brew-user/.bashrc" || true)" ../actual-profile "$app/$variant preserves profile symlink identity"
    check "$(tail -1 "$c/external/actual-profile")" "$([[ "$variant" == profile-link ]] && printf 'fi' || printf '# foreign shell setup')" "$app/$variant modifies actual profile target"
  fi
  if [[ "$variant" == uninstall-system-link ]]; then
    check "$(readlink "$c/etc/profile.d/homebrew.sh" || true)" "$c/external/global-profile" "$app/$variant preserves global symlink"
  fi
}
runtime_hooks_retry_needed() { return 1; }
runtime_hooks_more_cases() {
  local install_status uninstall_status
  for mode in no yes; do
    for variant in installer-failure partial-failure prefix-failure cleanup-failure missing-brew; do
      c="$work/homebrew-partial-$mode-$variant"
      role=install fault=$variant
      [[ "$variant" != cleanup-failure ]] || fault=installer-failure
      [[ "$variant" != missing-brew ]] || fault=none
      mkdir -p "$c/opt" "$c/local/bin" "$c/home"
      : > "$c/services"
      runtime_hooks_setup
      runtime_hooks_prepare
      install_status=0
      runtime_hooks_invoke install "$fault" "$c/output" "$c/build.log" "$c/errors.log" || install_status=$?
      check "$install_status" "$([[ "$variant" == missing-brew ]] && printf 0 || { [[ "$variant" == prefix-failure ]] && printf 45 || printf 43; })" "$app/$variant intended install outcome"
      [[ "$variant" != missing-brew ]] || rm "$c/opt/brew/.linuxbrew/bin/brew"
      uninstall_status=0
      runtime_hooks_invoke uninstall "$variant" "$c/uninstall-output" "$c/uninstall.log" "$c/uninstall-errors.log" || uninstall_status=$?
      if [[ "$variant" == cleanup-failure ]]; then
        check "$uninstall_status" 44 "$app/$variant required cleanup status is preserved"
        check "$(test -x "$c/local/sbin/uninstall" && printf present || printf absent)" present "$app/$variant failed cleanup retains recovery command"
        uninstall_status=0
        runtime_hooks_invoke uninstall none "$c/retry-output" "$c/retry.log" "$c/retry-errors.log" || uninstall_status=$?
      fi
      check "$uninstall_status" 0 "$app/$variant cold no-brew recovery completes"
      check "$(test -e "$c/local/sbin/uninstall" && printf present || printf absent)" absent "$app/$variant successful recovery retires command"
      check "$(test -e "$c/addon-install-attempts/homebrew" && printf present || printf absent)" absent "$app/$variant successful recovery retires custody"
      if [[ "$variant" == partial-failure ]]; then
        check "$(cat "$c/opt/brew/.linuxbrew/external" 2> /dev/null || true)" 'external installer data' "$app/$variant unknown external installer contents retained"
        check "$(grep -ci manual "$c/uninstall-output" || true)" 1 "$app/$variant identifies manual cleanup path"
      elif [[ "$variant" == missing-brew ]]; then
        check "$(test -e "$c/etc/profile.d/homebrew.sh" && printf present || printf absent)" absent "$app/$variant exact global profile cleaned without brew"
        check "$(grep -c Homebrew "$c/external/brew-user/.profile" || true)" 0 "$app/$variant exact account profile cleaned without brew"
      else check "$(test -d "$c/opt/brew/.linuxbrew" && printf present || printf absent)" absent "$app/$variant exact empty prefix retired"; fi
      check "$(cat "$c/opt/brew/foreign")" 'unrelated parent data' "$app/$variant parent data retained"
      check "$(wc -l < "$c/installer")" "$([[ "$variant" == prefix-failure ]] && printf 0 || printf 1)" "$app/$variant cleanup does not replay upstream installer"
    done
  done
}
runtime_hooks_main "$@"
