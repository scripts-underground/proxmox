#!/usr/bin/env bash
# Actual repository/certificate/cache/context owners, native GPG/OpenSSL/files.
set -euo pipefail
ROOT=$(realpath "$(dirname "${BASH_SOURCE[0]}")/../..")
if [[ "${1:-}" == --child ]]; then
  c="$CASE_ROOT"
  source "$ROOT/misc/core.func"
  sed -e "s|/etc/apt/|$c/apt/|g" -e "s|/etc/ssl/|$c/ssl/|g" "$ROOT/misc/tools.func" > "$c/tools.func"
  source "$c/tools.func"
  load_functions
  export STD='' APPLICATION=Probe
  msg_info() { :; }
  msg_ok() { :; }
  msg_warn() { printf 'WARN %s\n' "$*" >> "$c/messages"; }
  msg_error() { printf 'ERROR %s\n' "$*" >> "$c/messages"; }
  debug_log() { :; }
  ensure_dependencies() { :; }
  sleep() { :; }
  rc=0
  case "$KIND" in
    repo)
      mkdir -p "$c/apt/keyrings" "$c/apt/sources.list.d"
      cp /usr/share/keyrings/debian-archive-keyring.gpg "$c/apt/keyrings/probe.gpg"
      chmod 640 "$c/apt/keyrings/probe.gpg"
      printf 'old sources\n' > "$c/apt/sources.list.d/probe.sources"
      cp "$c/apt/keyrings/probe.gpg" "$c/original-key"
      stat -c '%a:%u:%g:%i' "$c/apt/keyrings/probe.gpg" > "$c/before-metadata"
      curl() {
        printf curl >> "$c/effects"
        local dest=''
        while (($#)); do
          if [[ "$1" == -o ]]; then
            dest="$2"
            shift
          fi
          shift
        done
        [[ "$FAULT" != transfer ]] || {
          printf partial > "$dest"
          return 18
        }
        if [[ "$FAULT" == invalid ]]; then printf invalid > "$dest"; else cp "$c/original-key" "$dest"; fi
      }
      apt() { printf apt >> "$c/effects"; }
      local_key="$c/apt/keyrings/probe.gpg"
      case "$FAULT" in missing) local_key="$c/missing.gpg" ;; empty) : > "$local_key" ;; esac
      key="$local_key"
      [[ "$FAULT" != transfer && "$FAULT" != invalid && "$FAULT" != remote ]] || key=https://keys.example.invalid/key
      CURL_RETRIES=1 setup_deb822_repo probe "$key" https://example.invalid/debian stable || rc=$?
      [[ ! -e "$local_key" ]] || stat -c '%a:%u:%g:%i' "$local_key" > "$c/after-metadata"
      ;;
    cert)
      hostname() { case "$1" in -f) printf '%s\n' "${CERT_DNS:-probe.example.invalid}" ;; -I) printf '%s\n' "${CERT_IP:-}" ;; esac }
      openssl() {
        if [[ "${RENEW:-0}" == 1 && "$1 $2" == 'x509 -checkend' ]]; then return 1; fi
        if [[ "${FAULT:-}" == generation && "${RENEW:-0}" == 1 && "$1" == req ]]; then return 42; fi
        command openssl "$@"
      }
      mkdir -p "$c/ssl/probe"
      if [[ "$FAULT" == operator ]]; then
        command openssl req -new -newkey rsa:2048 -days 1 -nodes -x509 -subj /CN=operator -keyout "$c/ssl/probe/probe.key" -out "$c/ssl/probe/probe.crt" 2> "$c/openssl.log"
      fi
      create_self_signed_cert Probe || rc=$?
      if [[ -s "$c/ssl/probe/probe.crt" ]]; then
        cp "$c/ssl/probe/probe.crt" "$c/first.crt"
        cp "$c/ssl/probe/probe.key" "$c/first.key"
        if [[ "$FAULT" == renewal || "$FAULT" == generation || "$FAULT" == edited || "$FAULT" == publication || "$FAULT" == operator ]]; then
          [[ "$FAULT" != edited ]] || printf '\n' >> "$c/ssl/probe/probe.crt"
          cp "$c/ssl/probe/probe.crt" "$c/before.crt"
          cp "$c/ssl/probe/probe.key" "$c/before.key"
          if [[ "$FAULT" == publication ]]; then
            cp() {
              if [[ "$*" == *'/payload/'*'probe.key'* ]]; then return 43; fi
              command cp "$@"
            }
          fi
          RENEW=1 create_self_signed_cert Probe || rc=$?
        fi
        command openssl x509 -noout -subject -ext subjectAltName -in "$c/ssl/probe/probe.crt" > "$c/certificate"
        command openssl x509 -noout -pubkey -in "$c/ssl/probe/probe.crt" > "$c/cert-public"
        command openssl pkey -pubout -in "$c/ssl/probe/probe.key" > "$c/key-public"
      fi
      ;;
    bundle-context)
      source "$ROOT/misc/bundle.func"
      export APP=Probe NSAPP=probe APP_SLUG=probe REPO_BASE=offline
      export var_lxc_tmpdir="$c/receiving" var_addon_tmpdir="$c/receiving"
      mkdir -p "$c/libraries"
      cp "$ROOT/misc/"*.func "$c/libraries/"
      sed "s|/var/lib/scripts-underground|$c/state|g" "$ROOT/misc/core.func" > "$c/libraries/core.func"
      sed "s|/etc/apt/apt.conf.d|$c/apt.conf.d|g" "$ROOT/misc/install.func" > "$c/libraries/install.func"
      sed "s|/root/|$c/root/|g" "$ROOT/misc/error_handler.func" > "$c/libraries/error_handler.func"
      mkdir -p "$c/root" "$c/apt.conf.d"
      : > "$c/cold-install.log"
      [[ "$FAULT" != policy ]] || printf 'operator policy\n' > "$c/apt.conf.d/99scripts-underground-conffiles"
      install_script() {
        printf '%s:%s:%s:%s\n' "${SUDO_USER-unset}" "${SUDO_UID-unset}" "${SUDO_GID-unset}" "${SUDO_COMMAND-unset}" > "$CASE_ROOT/context"
      }
      # The actual serialized init/library closure is the subject. For update,
      # inline a self-contained hook, as required by the bundle API.
      update_script() {
        printf '%s:%s:%s:%s\n' "${SUDO_USER-unset}" "${SUDO_UID-unset}" "${SUDO_GID-unset}" "${SUDO_COMMAND-unset}" > "$CASE_ROOT/context"
      }
      if [[ "$PROFILE:$ROLE" == lxc:update ]]; then
        _bundle_contents lxc update update_script "$c/libraries" --requirements 1 256 -- run_update_script > "$c/bundle"
      else
        _bundle_contents "$PROFILE" install install_script "$c/libraries" install_script > "$c/bundle"
      fi
      env -i PATH="$PATH" HOME="$HOME" TMPDIR="$TMPDIR" CASE_ROOT="$c" \
        SESSION_ID=fixture INSTALL_LOG="$c/cold-install.log" \
        SUDO_USER=caller SUDO_UID=123 SUDO_GID=456 SUDO_COMMAND=provision \
        DEBUG_LOGFILE="$c/cold-errors.log" BUILD_LOG="$c/cold-build.log" bash "$c/bundle" > "$c/cold-output" 2>&1 || rc=$?
      ;;
    context)
      printf '%s:%s:%s:%s\n' "${SUDO_USER-unset}" "${SUDO_UID-unset}" "${SUDO_GID-unset}" "${SUDO_COMMAND-unset}" > "$c/context"
      printf '%s:%s:%s\n' "$HOME" "$USER" "$LOGNAME" > "$c/user-context"
      export SUDO_USER=again SUDO_UID=123 SUDO_GID=456 SUDO_COMMAND=again
      load_functions
      printf '%s\n' "${SUDO_USER-unset}" > "$c/reentry"
      ;;
    cleanup)
      command() { case "$*" in '-v yarn') return 0 ;; '-v '*) return 1 ;; *) builtin command "$@" ;; esac }
      pkg_clean() { :; }
      is_alpine() { return 1; }
      rm() { printf '%s\n' "$*" >> "$c/removals"; }
      cleanup_lxc
      ;;
  esac
  printf '%s' "$rc" > "$c/rc"
  exit 0
fi
: "${TMPDIR:?disk TMPDIR required}"
systemd-detect-virt --vm --quiet || exit 65
work=$(mktemp -d "$TMPDIR/core-packages.XXXXXX")
trap 'rm -rf -- "$work"' EXIT
failures=0
check() {
  if [[ "$1" == "$2" ]]; then printf 'PASS %s\n' "$3"; else
    printf 'FAIL %s: expected <%s>, got <%s>\n' "$3" "$2" "$1" >&2
    failures=$((failures + 1))
  fi
}
n=0
go() {
  n=$((n + 1))
  c="$work/$n"
  mkdir -p "$c/home"
  : > "$c/effects"
  : > "$c/messages"
  env -i PATH="$PATH" HOME="$c/home" USER=chosen LOGNAME=chosen TMPDIR="$TMPDIR" CASE_ROOT="$c" KIND="$KIND" FAULT="${FAULT:-normal}" \
    SUDO_USER=caller SUDO_UID=123 SUDO_GID=456 SUDO_COMMAND=provision BUILD_LOG="$c/build.log" DEBUG_LOGFILE="$c/errors.log" \
    CERT_IP=192.0.2.5 "$@" bash "$0" --child > "$c/output" 2>&1
  rc=$(cat "$c/rc")
}
KIND=repo
for FAULT in normal remote; do
  go
  check "$rc" 0 "$FAULT key admitted"
  check "$(grep -c '^Signed-By: ' "$c/apt/sources.list.d/probe.sources")" 1 "$FAULT key reaches source consumer"
  if [[ "$FAULT" == normal ]]; then
    check "$(cat "$c/before-metadata")" "$(cat "$c/after-metadata" 2> /dev/null || true)" 'local key keeps mode owner and inode'
    check "$(cat "$c/effects")" apt 'local key is never downloaded'
    check "$(sed -n 's/^Signed-By: //p' "$c/apt/sources.list.d/probe.sources")" "$c/apt/keyrings/probe.gpg" 'local key referenced in place'
  fi
done
for FAULT in transfer invalid missing empty; do
  go
  check "$((rc != 0))" 1 "$FAULT key refuses"
  check "$(cat "$c/apt/sources.list.d/probe.sources")" 'old sources' "$FAULT key preserves working sources"
  if [[ "$FAULT" == transfer || "$FAULT" == invalid ]]; then
    check "$(cmp -s "$c/original-key" "$c/apt/keyrings/probe.gpg" && echo preserved || echo lost)" preserved "$FAULT preserves previous remote key"
  fi
done
KIND=cert FAULT=normal go CERT_IP='' CERT_DNS=averylonglabel012345678901234567890123456789012345678901234567890.example.invalid
check "$rc" 0 'long FQDN with no IP generates a certificate'
if [[ -f "$c/certificate" ]]; then
  check "$(grep -c 'DNS:averylonglabel.*example.invalid' "$c/certificate")" 1 'full FQDN is a DNS SAN'
  check "$(cmp -s "$c/cert-public" "$c/key-public" && echo matched || echo mismatch)" matched 'certificate and private key match'
  check "$(stat -c %a "$c/ssl/probe/probe.key")" 600 'private key created private'
fi
for FAULT in renewal operator edited generation publication; do
  KIND=cert go
  case "$FAULT" in
    renewal)
      check "$rc" 0 'owned expiring certificate renews'
      check "$(cmp -s "$c/first.crt" "$c/ssl/probe/probe.crt" && echo unchanged || echo renewed)" renewed 'renewal publishes new certificate bytes'
      ;;
    operator)
      check "$(cmp -s "$c/first.crt" "$c/ssl/probe/probe.crt" && echo preserved || echo changed)" preserved 'unmarked operator pair preserved'
      ;;
    edited)
      check "$(cmp -s "$c/before.crt" "$c/ssl/probe/probe.crt" && echo preserved || echo changed)" preserved 'operator edited owned pair no longer renews'
      ;;
    generation | publication)
      check "$((rc != 0))" 1 "$FAULT renewal failure returned"
      check "$(cmp -s "$c/before.crt" "$c/ssl/probe/probe.crt" && cmp -s "$c/before.key" "$c/ssl/probe/probe.key" && echo preserved || echo changed)" preserved "$FAULT retains previous pair"
      ;;
  esac
done
KIND=context FAULT=normal go
check "$(cat "$c/context")" unset:unset:unset:unset 'root context clears all sudo-origin variables'
check "$(cat "$c/reentry")" unset 'root context normalization precedes initialization cache'
check "$(cat "$c/user-context")" "$c/home:chosen:chosen" 'normalization preserves supplied HOME USER LOGNAME'
# Public custody ancestors are deliberately private. Pass an already opened
# regular source FD rather than chmodding that infrastructure for a non-root test.
env -i PATH="$PATH" HOME="${HOME:-/nonexistent}" SUDO_USER=caller SUDO_UID=123 SUDO_GID=456 SUDO_COMMAND=provision \
  setpriv --reuid 65534 --regid 65534 --clear-groups bash -c \
  'source /dev/fd/3; load_functions; printf "%s:%s:%s:%s\n" "${SUDO_USER-unset}" "${SUDO_UID-unset}" "${SUDO_GID-unset}" "${SUDO_COMMAND-unset}"' \
  3< "$ROOT/misc/core.func" > "$work/nonroot"
check "$(cat "$work/nonroot")" caller:123:456:provision 'non-root context is unchanged'
for variant in lxc:install lxc:update addon:install; do
  KIND=bundle-context go PROFILE="${variant%:*}" ROLE="${variant#*:}"
  check "$rc" 0 "$variant cold bundle reaches its hook"
  check "$(cat "$c/context" 2> /dev/null || true)" unset:unset:unset:unset "$variant root context normalized before hook"
done
for variant in lxc:install addon:install; do
  KIND=bundle-context FAULT=policy go PROFILE="${variant%:*}" ROLE="${variant#*:}"
  # INIT_FLAG_DIAGNOSTIC: report from the outer observer, not its captured child.
  if [[ ! -f "$c/root/.install-fixture.failed" ]]; then
    cat "$c/cold-output"
    find "$c/root" -maxdepth 1 -type f -printf 'INIT_FLAG_FILE %f\n'
  fi
  check "$rc" 65 "$variant invalid existing policy refuses at initialized error boundary"
  check "$(cat "$c/root/.install-fixture.failed" 2> /dev/null || true)" 65 "$variant initialization failure writes actual install failure flag"
  check "$(test -e "$c/context" && echo executed || echo skipped)" skipped "$variant failed initialization cannot reach app hook"
  check "$(cat "$c/apt.conf.d/99scripts-underground-conffiles")" 'operator policy' "$variant preserves conflicting operator policy bytes"
done
KIND=cleanup go
for cache in /usr/local/share/.cache/yarn /root/.yarn/berry/cache; do
  check "$(grep -cF "$cache" "$c/removals" || true)" 1 "cleanup owns exact $cache"
done
check "$(grep -cF "$TMPDIR" "$c/removals" || true)" 0 'cache cleanup does not sweep shared temporary context'
printf 'RUNTIME_HOOKS_RESULT failures=%s\n' "$failures"
[[ "$failures" == 0 ]]
