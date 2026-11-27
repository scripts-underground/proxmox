#!/usr/bin/env bash
# shellcheck disable=SC2034,SC2154
# Generated REA bundles with real checksum, staging, activation and pending
# state. Package, build, Java and network effects are modeled.
set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/../lib/runtime-hooks/harness.sh"
app=rea
script_type=lxc
variants=(fresh dependencies current update pending broken missing download checksum runtime install-unpublished install-published update-unpublished update-published)
hook_paths=(/srv/rea rea /home/rea account /usr/local/lib local/lib)

runtime_hooks_variant() {
  case "$variant" in
    dependencies) role=install fault=dependencies ;;
    checksum) fault=checksum ;;
    install-* | update-*) role=${variant%-*} fault=${variant##*-} ;;
  esac
}

runtime_hooks_setup() {
  local pin path digest
  mkdir -p "$c/account/.ssh" "$c/local/lib"
  for pin in node ghidra jadx apktool; do
    path="$c/payload/$pin"
    printf '%s fixture\n' "$pin" > "$path"
    digest=$(sha256sum "$path")
    printf 'var_lxc_%s_sha256=%s\n' "$pin" "${digest%% *}" >> "$c/context.sh"
  done
  if [[ "$role" == update ]]; then
    mkdir -p "$c/rea/"{bin,jobs,releases/old/bin}
    printf 'saved job\n' > "$c/rea/jobs/job"
    printf 'export REA_FIXTURE_SETTING=operator\n' > "$c/rea/environment.sh"
    printf 'operator key fixture\n' > "$c/account/.ssh/authorized_keys"
    chmod 0600 "$c/account/.ssh/authorized_keys"
    install -m 0755 /bin/true "$c/rea/releases/old/bin/rea"
    install -m 0755 /bin/true "$c/rea/releases/old/bin/apktool"
    ln -s releases/old "$c/rea/current"
    ln -s ../current/bin/rea "$c/rea/bin/rea"
    ln -s ../current/bin/apktool "$c/rea/bin/apktool"
    : > "$c/rea/releases/old/pins"
    if [[ "$variant" == pending || "$variant" == broken ]]; then printf 'normal\n' > "$c/state/$app"; fi
    if [[ "$variant" == broken ]]; then rm -- "$c/rea/current" "$c/rea/bin/rea" "$c/rea/bin/apktool"; fi
    if [[ "$variant" == missing ]]; then rm -- "$c/rea/current"; fi
  fi
  if [[ "$fault" == unpublished || "$fault" == published ]]; then
    mkdir -p "$c/launcher-bin"
    printf '#!/bin/sh\nprintf "rea\\n"\n' > "$c/launcher-bin/id"
    chmod 0755 "$c/launcher-bin/id"
  fi
}

runtime_hooks_model() {
  get_system_arch() { printf amd64; }
  id() { [[ "$*" == rea ]] || command id "$@"; }
  pkg_install() { [[ "$APP_FAULT" != dependencies ]] || return 42; }
  install() {
    # Keep real directory mutations without provisioning a user on this VM.
    if [[ "$1 ${2:-} ${3:-} ${4:-} ${5:-}" == '-d -o rea -g rea' ]]; then
      shift 5
      command install -d "$@"
    else command install "$@"; fi
  }
  curl_with_retry() {
    local pin
    [[ "$3" == '--proto =https --proto-redir =https' ]] || return 70
    printf '%s\n' "$1" >> "$c/downloads"
    [[ "$APP_FAULT" != download ]] || return 22
    if [[ "$APP_FAULT" == checksum ]]; then
      printf 'wrong bytes\n' > "$2"
      return
    fi
    case "$2" in
      */node.tar.xz) pin=node ;;
      */ghidra.zip) pin=ghidra ;;
      */jadx-*.jar) pin=jadx ;;
      */apktool_*.jar) pin=apktool ;;
      *) return 70 ;;
    esac
    command cp "$c/payload/$pin" "$2"
  }
  tar() { printf 'node unpack\n' >> "$c/build-steps"; }
  unzip() { printf 'ghidra unpack\n' >> "$c/build-steps"; }
  mv() {
    if [[ "$APP_FAULT" == unpublished || "$APP_FAULT" == published ]] &&
      [[ $# == 4 && "$1 $2" == '-Tf --' && "$3" == "$c/rea/releases/"*/next && "$4" == "$c/rea/current" ]]; then
      readlink -- "$3" > "$c/candidate" || return "$?"
      if [[ "$APP_FAULT" == published ]]; then command mv "$@" || return "$?"; fi
      # Exit the deploy subshell at the rename boundary, before its caller can
      # execute another statement. The real EXIT trap owns the cleanup.
      exit 99
    fi
    command mv "$@"
  }
  runuser() {
    [[ "$1 $2 $3" == '-u rea --' ]] || return 70
    shift 3
    if [[ "$1" == env ]]; then
      printf 'build\n' >> "$c/build-steps"
      if [[ "$APP_FAULT" == unpublished || "$APP_FAULT" == published ]]; then
        local node_bin="${!#}/tools/node-v${var_lxc_node_version}-linux-x64/bin"
        local scripts="${!#}/runtime/node_modules/rea-agents/scripts"
        mkdir -p "$node_bin" "$scripts"
        printf '%s\n' '#!/bin/sh' 'test -f "$1" && test "$2" = --help && printf "new REA: %s\n" "${REA_FIXTURE_SETTING:-default}"' > "$node_bin/node"
        chmod 0755 "$node_bin/node"
        : > "$scripts/rea.mjs"
      fi
      return
    fi
    [[ -x "$1" ]] || return 127
    if [[ "$2" == doctor ]]; then
      if [[ "$APP_FAULT" == runtime ]]; then
        printf '{}\n'
        return
      fi
      jq -n --arg version "$var_lxc_ghidra_version" '
        {providerInspections:[{id:"ghidra",available:true,providerVersion:$version}],
         checks:["installation","version","headless","java"]|map({name:("ghidra-"+.),ok:true})}'
    fi
  }
  if [[ "$APP_ROLE" == update && "${c##*-}" != missing && ! -e "$c/local/lib/rea-deploy.sh" ]]; then
    sed -n "/cat << *'DEPLOY'/,/^DEPLOY\$/ { /cat << *'DEPLOY'/d; /^DEPLOY\$/d; p; }" "$c/source.sh" > "$c/local/lib/rea-deploy.sh"
    if [[ "${c##*-}" == current || "${c##*-}" == pending ]]; then
      # Populate the exact marker a previous successful generated install writes.
      (
        source "$c/local/lib/rea-deploy.sh"
        rea_pins > "$c/rea/current/pins"
      )
    fi
  fi
}

runtime_hooks_expected() {
  case "$variant" in
    dependencies) expected=42 ;;
    missing | checksum | runtime) expected=1 ;;
    download) expected=22 ;;
    *-unpublished | *-published) expected=99 ;;
  esac
}

runtime_hooks_assert() {
  if [[ "$role" == update ]]; then
    check "$(cat "$c/rea/jobs/job")" 'saved job' "$app/$variant job bytes"
    check "$(cat "$c/rea/environment.sh")" 'export REA_FIXTURE_SETTING=operator' "$app/$variant environment bytes"
    check "$(cat "$c/account/.ssh/authorized_keys")" 'operator key fixture' "$app/$variant key bytes"
    check "$(stat -c %a "$c/account/.ssh/authorized_keys")" 600 "$app/$variant key mode"
  fi
  case "$variant" in
    fresh | update | pending | broken)
      check "$(test -s "$c/rea/current/pins" && printf yes || printf no)" yes "$app/$variant complete active generation"
      check "$(readlink "$c/rea/bin/rea" || true)" ../current/bin/rea "$app/$variant REA launcher link"
      check "$(readlink "$c/rea/bin/apktool" || true)" ../current/bin/apktool "$app/$variant Apktool launcher link"
      check "$(grep -c '^https://' "$c/downloads" 2> /dev/null || true)" 4 "$app/$variant reconstructs every pinned artifact"
      if [[ "$role" == install ]]; then
        check "$(cat "$c/services")" 'enable --now ssh' "$app/$variant enables SSH after activation"
      else
        check "$(test -d "$c/rea/releases/old" && printf yes || printf no)" yes "$app/$variant retains previous release"
      fi
      ;;
    current)
      check "$(readlink "$c/rea/current")" releases/old "$app/$variant current release unchanged"
      check "$(test ! -e "$c/downloads" && printf yes || printf no)" yes "$app/$variant no preparation"
      ;;
    download | checksum | runtime)
      check "$(readlink "$c/rea/current" || true)" releases/old "$app/$variant failed preparation preserves release"
      check "$(find "$c/rea/releases" -mindepth 1 -maxdepth 1 -printf '%f\n')" old "$app/$variant only failed stage removed"
      if [[ "$variant" != runtime ]]; then
        check "$(test ! -e "$c/build-steps" && printf yes || printf no)" yes "$app/$variant failed download never unpacked"
      fi
      ;;
    *-unpublished | *-published)
      local label="$app/$mode/$variant" candidate prior='' output rc=0 setting=default
      candidate=$(cat "$c/candidate" 2> /dev/null || true)
      check "${candidate%/*}" releases "$label reached publication with a candidate"
      if [[ "$role" == update ]]; then
        prior=releases/old setting=operator
        check "$("$c/rea/releases/old/bin/rea" && printf yes || printf no)" yes "$label previous release remains usable"
      fi
      if [[ "$fault" == published ]]; then
        check "$(readlink "$c/rea/current" || true)" "$candidate" "$label current points to the published candidate"
        check "$(test -s "$c/rea/current/pins" && printf yes || printf no)" yes "$label published candidate retained"
        output=$(REA_FIXTURE_SETTING=default PATH="$c/launcher-bin:$PATH" "$c/rea/bin/rea" --help 2>&1) || rc=$?
        check "$rc:$output" "0:new REA: $setting" "$label published launcher works"
      else
        check "$(readlink "$c/rea/current" || true)" "$prior" "$label current unchanged before publication"
        check "$(test ! -e "$c/rea/$candidate" && printf yes || printf no)" yes "$label unpublished candidate removed"
        if [[ "$role" == update ]]; then
          output=$("$c/rea/bin/rea" 2>&1) || rc=$?
          check "$rc:$output" '0:' "$label prior public launcher works"
        else
          check "$(test ! -e "$c/rea/bin/rea" && printf yes || printf no)" yes "$label no usable launcher before first publication"
        fi
      fi
      ;;
    missing | dependencies)
      check "$(test ! -e "$c/downloads" && printf yes || printf no)" yes "$app/$variant no runtime prepared"
      check "$(test ! -e "$c/rea/current" && printf yes || printf no)" yes "$app/$variant no runtime activated"
      ;;
  esac
}

runtime_hooks_retry_needed() { [[ "$variant" == download || "$variant" == checksum || "$variant" == runtime ]]; }
runtime_hooks_retry_assert() {
  check "$(test -s "$c/rea/current/pins" && printf yes || printf no)" yes "$app/$variant pending retry activates complete generation"
}

# The framework normally calls hooks plainly. Also assert their independent
# status contracts with explicit conditionals (which disable Bash errexit).
runtime_hooks_more_cases() (
  c="$work/conditional"
  mkdir -p "$c"
  sed -e '/^source <(/,$d' -e "s@/srv/rea@$c/rea@g;s@/usr/local/lib@$c/local/lib@g;s@/home/rea@$c/account@g" \
    "$ROOT/scripts/lxc/rea.sh" > "$c/hook.sh"
  source "$c/hook.sh"
  OS_TYPE=debian OS_VERSION=13 STD='' APP_FAULT=dependencies APP_ROLE=install
  msg_info() { :; }
  msg_ok() { :; }
  msg_error() { :; }
  systemctl() { printf 'service start\n' >> "$c/services"; }
  chown() { :; }
  runtime_hooks_model
  rc=0
  install_script > "$c/output" 2>&1 || rc=$?
  check "$rc" 42 "$app conditional install propagates dependency fault"
  check "$(test ! -e "$c/services" && printf yes || printf no)" yes "$app conditional install does not enable SSH on dependency failure"
  APP_FAULT=download
  rc=0
  install_script > "$c/output" 2>&1 || rc=$?
  check "$rc" 22 "$app conditional install propagates helper download fault"
  check "$(test ! -e "$c/build-steps" && test ! -e "$c/services" && printf yes || printf no)" yes "$app conditional helper never unpacks or enables SSH on download failure"
  [[ "$failures" == 0 ]]
)

runtime_hooks_main "$@"
