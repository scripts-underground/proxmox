#!/usr/bin/env bash
# Actual pkg_update and the actual pre-bundle apt provisioning fragment of build.func.
# apt-get, pct transport, mirror reachability, prompt input and the /etc, /var/lib/apt
# locations are explicit models: no native Devuan template, CDN or deb822 claim.
# APT_FAILOVER_OWNER_ROOT may name another tree to reproduce an older owner.
set -euo pipefail
ROOT=$(realpath "$(dirname "${BASH_SOURCE[0]}")/../..")
if [[ "${1:-}" == --child ]]; then
  c="$CASE_ROOT"
  # shellcheck source=/dev/null
  source "$ROOT/misc/core.func"
  # shellcheck source=/dev/null
  source "$ROOT/misc/bundle.func"
  load_functions
  msg_info() { printf 'info: %s\n' "${1:-}"; }
  msg_ok() { printf 'ok: %s\n' "${1:-}"; }
  msg_warn() { printf 'warn: %s\n' "${1:-}"; }
  msg_error() { printf 'error: %s\n' "${1:-}"; }
  msg_custom() { printf 'custom: %s\n' "${3:-}"; }
  read() {
    printf 'prompt\n' >> "$c/events"
    builtin read "$@"
  }
  # The caller may still hold an ID left by an earlier detect_os.
  [[ -z "${AMBIENT_ID:-}" ]] || export ID="$AMBIENT_ID"
  export PATH="$c/bin:$PATH"
  # shellcheck source=/dev/null
  source "$c/owner.sh"
  rc=0
  if [[ "$OWNER" == pkg ]]; then
    # shellcheck disable=SC2034
    PKG_MANAGER=apt
    pkg_update || rc=$?
  else
    # shellcheck disable=SC2034
    CTID=2225 var_os="$VAR_OS" _ct_env='export LC_ALL=C.UTF-8 LANG=C.UTF-8 DEBIAN_FRONTEND=noninteractive;'
    # Explicit prepared receiving root: package consumers must see it, not the creator TMPDIR.
    mkdir -m 1777 "$c/receiver root"
    _receiving_tmpdir="$c/receiver root"
    pct() {
      printf 'pct-exec\n' >> "$c/events"
      [[ "$1" == exec && "$3" == -- ]] || return 97
      shift 3
      [[ "$*" != *try_mirrors* ]] || printf 'pct-mirror-payload\n' >> "$c/events"
      if [[ "${PCT_FAULT:-}" == probe && "$*" == *'${ID-}'* ]]; then
        return 255
      fi
      "$@"
    }
    run_base || rc=$?
  fi
  exit "$rc"
fi

: "${TMPDIR:?disk-backed TMPDIR required}"
systemd-detect-virt --vm --quiet || exit 1
case "$(realpath -e "$TMPDIR")" in /tmp | /tmp/*) exit 1 ;; esac
case "$(findmnt -rn -T "$TMPDIR" -o FSTYPE)" in '' | tmpfs | ramfs) exit 1 ;; esac
OWNER_ROOT=$(realpath -e "${APT_FAILOVER_OWNER_ROOT:-$ROOT}")
work=$(mktemp -d "$TMPDIR/apt-failover.XXXXXX")
trap 'rm -rf -- "$work"' EXIT
failures=0
check() {
  if [[ "$1" == "$2" ]]; then printf 'PASS %s\n' "$3"; else
    printf 'FAIL %s: expected <%s>, got <%s>\n' "$3" "$2" "$1" >&2
    failures=$((failures + 1))
  fi
}
in_list() {
  local word
  for word in $2; do
    [[ "$word" != "$1" ]] || return 0
  done
  return 1
}
count() { grep -c -- "$1" "$2" || true; }

debian_eu='ftp.de.debian.org ftp.fr.debian.org ftp.nl.debian.org ftp.uk.debian.org ftp.ch.debian.org ftp.se.debian.org ftp.it.debian.org ftp.fau.de ftp.halifax.rwth-aachen.de debian.mirror.lrz.de mirror.init7.net debian.ethz.ch mirrors.dotsrc.org debian.mirrors.ovh.net'
debian_other='ftp.us.debian.org ftp.ca.debian.org debian.csail.mit.edu mirrors.ocf.berkeley.edu mirrors.wikimedia.org debian.osuosl.org mirror.cogentco.com ftp.au.debian.org ftp.jp.debian.org ftp.tw.debian.org ftp.kr.debian.org ftp.hk.debian.org ftp.sg.debian.org mirror.aarnet.edu.au mirror.nitc.ac.in'
ubuntu_eu='de.archive.ubuntu.com fr.archive.ubuntu.com se.archive.ubuntu.com nl.archive.ubuntu.com it.archive.ubuntu.com ch.archive.ubuntu.com mirrors.xtom.de'
ubuntu_other='us.archive.ubuntu.com archive.ubuntu.com mirrors.edge.kernel.org mirror.csclub.uwaterloo.ca mirrors.ocf.berkeley.edu mirror.math.princeton.edu au.archive.ubuntu.com jp.archive.ubuntu.com kr.archive.ubuntu.com tw.archive.ubuntu.com mirror.aarnet.edu.au'

# Name, ID model, initial apt status, first call fails, later behavior, prompt input, expectation.
scenarios=(
  'devuan-rc1 devuan 1 1 original skip unsupported'
  'devuan-rc2 devuan 2 1 original skip unsupported'
  'devuan-rc100 devuan 100 1 original skip unsupported'
  'unknown-rc100 unknown 100 1 original skip unsupported'
  'noid-rc100 noid 100 1 original skip unsupported'
  'idfail-rc100 idfail 100 1 original skip unsupported'
  'ambient-debian-rc100 ambdebian 100 1 original skip unsupported'
  'ambient-ubuntu-rc2 ambubuntu 2 1 original skip unsupported'
  'success-devuan devuan 100 0 original skip success'
  'success-debian debian 100 0 original skip success'
  'success-ubuntu ubuntu 100 0 original skip success'
  'debian-fallback debian 1 0 mirror skip fallback'
  'ubuntu-fallback ubuntu 100 0 mirror skip fallback'
  'debian-exhausted debian 100 0 none skip exhausted'
  'ubuntu-exhausted ubuntu 2 0 none skip exhausted'
  'debian-custom debian 100 0 custom custom.example.org custom'
)

for owner in pkg base; do
  modes=(no)
  [[ "$owner" != pkg ]] || modes=(no yes)
  for mode in "${modes[@]}"; do
    for scenario in "${scenarios[@]}"; do
      read -r name id apt_rc fail_first apt_mode prompt expect <<< "$scenario"
      c="$work/$owner-$mode-$name"
      label="$owner/STD-verbose-$mode/$name"
      mkdir -p "$c"/{bin,etc/apt/apt.conf.d,var/lib/apt/lists,tmp,home}
      : > "$c/events"
      : > "$c/apt-tmp"
      printf 'canary\n' > "$c/var/lib/apt/lists/canary"
      printf 'Europe/Berlin\n' > "$c/etc/timezone"
      printf '%s\n' "$prompt" > "$c/prompt"
      orig_host=original.example.invalid
      pct_fault=
      ambient=
      case "$id" in
        devuan)
          orig_host=deb.devuan.org
          printf 'NAME="Devuan GNU/Linux"\nID=devuan\nID_LIKE=debian\n' > "$c/etc/os-release"
          ;;
        debian) printf 'ID=debian\n' > "$c/etc/os-release" ;;
        ubuntu) printf 'ID=ubuntu\n' > "$c/etc/os-release" ;;
        unknown) printf 'ID="unknown-os"\n' > "$c/etc/os-release" ;;
        noid) printf 'NAME="No ID here"\n' > "$c/etc/os-release" ;;
        ambdebian | ambubuntu)
          printf 'NAME="No ID here"\n' > "$c/etc/os-release"
          ambient=${id#amb}
          ;;
        idfail)
          if [[ "$owner" == pkg ]]; then
            : # os-release is absent
          else
            printf 'ID=debian\n' > "$c/etc/os-release"
            pct_fault=probe
          fi
          ;;
      esac
      case "$id" in
        devuan)
          printf 'deb http://deb.devuan.org/merged daedalus main contrib\n\ndeb http://deb.devuan.org/merged daedalus-updates main contrib\n\ndeb http://deb.devuan.org/merged daedalus-security main contrib\n' > "$c/etc/apt/sources.list"
          ;;
        ubuntu) printf 'deb http://%s/ubuntu noble main\n' "$orig_host" > "$c/etc/apt/sources.list" ;;
        debian) printf 'deb http://%s/debian bookworm main\n' "$orig_host" > "$c/etc/apt/sources.list" ;;
        *) printf 'deb http://%s/pool stable main\n' "$orig_host" > "$c/etc/apt/sources.list" ;;
      esac
      cp "$c/etc/apt/sources.list" "$c/sources-before"

      cat > "$c/bin/apt-get" << 'SHIM'
#!/bin/sh
host=$(sed -n 's|^deb http[s]*://\([^/]*\)/.*|\1|p' "$CASE_ROOT/etc/apt/sources.list" | head -n 1)
printf 'apt-get %s host=%s\n' "$1" "$host" >> "$CASE_ROOT/events"
exists=no
{ [ -n "${TMPDIR:-}" ] && [ -d "$TMPDIR" ]; } && exists=yes
f=$(mktemp "$TMPDIR/apt.XXXXXX") || exists=mktemp-failed
rm -f "$f"
printf 'tmpdir=%s exists=%s\n' "${TMPDIR-unset}" "$exists" >> "$CASE_ROOT/apt-tmp"
[ "$1" = update ] || exit 0
n=$(grep -c '^apt-get update' "$CASE_ROOT/events")
ok=0
case "$APT_MODE" in
  original) [ "$host" != "$ORIG_HOST" ] || ok=1 ;;
  mirror) { [ -n "$host" ] && [ "$host" != "$ORIG_HOST" ]; } && ok=1 ;;
  custom) [ "$host" != custom.example.org ] || ok=1 ;;
esac
{ [ "$n" = 1 ] && [ "$APT_FAIL_FIRST" = 1 ]; } && ok=0
[ "$ok" = 1 ] && exit 0
printf 'E: Unable to fetch http://%s/\n' "$host"
[ "$n" = 1 ] && exit "$APT_RC"
exit 100
SHIM
      printf '#!/bin/sh\nexit 0\n' > "$c/bin/timeout"
      chmod +x "$c/bin/apt-get" "$c/bin/timeout"

      rewrite() {
        sed -e "s|/etc/|$c/etc/|g" -e "s|/var/lib/apt/|$c/var/lib/apt/|g" -e 's|< /dev/tty|< "$PROMPT_FILE"|g'
      }
      if [[ "$owner" == pkg ]]; then
        sed -n '/^pkg_update() {/,/^}/p' "$OWNER_ROOT/misc/install.func" | rewrite > "$c/owner.sh"
        grep -q 'apt-get update' "$c/owner.sh" || {
          printf 'FAIL %s: actual pkg_update was not extracted\n' "$label" >&2
          exit 1
        }
      else
        {
          printf 'run_base() {\n'
          awk '
            !started && ($0 == "    local apt_base_rc=0" || index($0, "    pct exec \"$CTID\" -- bash -c \"${_ct_env} apt-get update") == 1) { started = 1 }
            started { print }
            started && ($0 == "    fi" || $0 == "    }") { exit }
          ' "$OWNER_ROOT/misc/build.func"
          printf '}\n'
        } | rewrite > "$c/owner.sh"
        grep -q 'try_mirrors' "$c/owner.sh" || {
          printf 'FAIL %s: actual pre-bundle fragment was not extracted\n' "$label" >&2
          exit 1
        }
      fi
      # Every real system path must be redirected into the case directory before execution.
      if sed -e "s|$c/etc/||g" -e "s|$c/var/lib/apt/||g" "$c/owner.sh" | grep -Eq '/etc/|/var/lib/apt/|/dev/tty'; then
        printf 'FAIL %s: unredirected system path in extracted owner\n' "$label" >&2
        exit 1
      fi

      rc=0
      env -i PATH="$PATH" HOME="$c/home" TMPDIR="$c/tmp" ROOT="$ROOT" CASE_ROOT="$c" OWNER="$owner" VERBOSE="$mode" \
        BUILD_LOG="$c/build.log" DEBUG_LOGFILE="$c/errors.log" APT_MODE="$apt_mode" APT_RC="$apt_rc" APT_FAIL_FIRST="$fail_first" \
        ORIG_HOST="$orig_host" PROMPT_FILE="$c/prompt" PCT_FAULT="$pct_fault" VAR_OS="$id" AMBIENT_ID="$ambient" \
        timeout 30s bash "$0" --child < /dev/null > "$c/output" 2>&1 || rc=$?

      final_host=$(sed -n 's|^deb http[s]*://\([^/]*\)/.*|\1|p' "$c/etc/apt/sources.list" | head -n 1)
      updates=$(count '^apt-get update' "$c/events")
      installs=$(count '^apt-get install' "$c/events")
      prompts=$(count '^prompt$' "$c/events")
      pcts=$(count '^pct-exec$' "$c/events")
      payloads=$(count '^pct-mirror-payload$' "$c/events")
      by_hash=$(test -e "$c/etc/apt/apt.conf.d/99no-by-hash" && printf present || printf absent)
      lists=$(test -e "$c/var/lib/apt/lists/canary" && printf kept || printf wiped)
      unchanged=$(cmp -s "$c/etc/apt/sources.list" "$c/sources-before" && printf unchanged || printf changed)
      if [[ "$owner" == base ]]; then
        apt_calls=$(count '^apt-get ' "$c/events")
        check "$(grep -c . "$c/apt-tmp" || true):$(grep -Fxvc "tmpdir=$c/receiver root exists=yes" "$c/apt-tmp" || true)" "$apt_calls:0" "$label every apt consumer uses the explicit receiving root as scratch"
      fi
      case "$expect" in
        unsupported)
          check "$rc" "$apt_rc" "$label returns the exact initial APT status"
          [[ "$rc" == "$apt_rc" ]] || tail -n 6 "$c/output" >&2
          check "$unchanged" unchanged "$label sources are not rewritten"
          check "$by_hash" absent "$label no By-Hash setting"
          check "$lists" kept "$label APT lists are not wiped"
          check "$updates:$installs" 1:0 "$label no fallback APT work"
          check "$prompts" 0 "$label no mirror prompt"
          check "$(count 'Package sources were not changed' "$c/output")" 1 "$label one actionable diagnostic"
          check "$(count "status $apt_rc" "$c/output")" 1 "$label diagnostic names the initial status"
          if [[ "$owner" == base ]]; then
            check "$pcts:$payloads" 2:0 "$label only the initial command and ID probe, no remote mirror payload"
          fi
          if [[ "$id" == idfail ]]; then
            check "$(count 'could not be read' "$c/output")" 1 "$label unreadable ID is reported, not defaulted to Debian"
          else
            check "$(count 'supports only Debian and Ubuntu' "$c/output")" 1 "$label unsupported ID is reported"
          fi
          ;;
        success)
          check "$rc" 0 "$label ordinary success is unchanged"
          check "$unchanged:$by_hash:$lists" unchanged:absent:kept "$label no failover effects"
          check "$updates:$prompts" 1:0 "$label one update, no prompt"
          if [[ "$owner" == base ]]; then
            check "$pcts:$installs" 1:1 "$label one provisioning command with its package install"
          fi
          ;;
        fallback)
          check "$rc" 0 "$label supported failover still succeeds"
          [[ "$rc" == 0 ]] || tail -n 6 "$c/output" >&2
          check "$updates:$prompts" 2:0 "$label initial failure then first catalogue attempt"
          check "$by_hash" present "$label By-Hash setting retained"
          first=$(grep '^apt-get update' "$c/events" | sed -n 2p | sed 's/.*host=//')
          eu=$debian_eu other=$debian_other
          [[ "$id" != ubuntu ]] || {
            eu=$ubuntu_eu
            other=$ubuntu_other
          }
          check "$(in_list "$final_host" "$eu $other" && printf catalogue || printf foreign)" catalogue "$label final host is in the $id catalogue"
          check "$(in_list "$first" "$other" && printf outside-region || printf other)" outside-region "$label first attempt keeps non-regional phase order"
          ;;
        exhausted)
          check "$rc" 1 "$label exhausted catalogue still reaches the prompt and fails with 1"
          check "$prompts" 1 "$label one mirror prompt"
          if [[ "$id" == ubuntu ]]; then
            check "$(count 'launchpad.net/ubuntu' "$c/output")" 1 "$label Ubuntu mirror advice"
          else
            check "$(count 'debian.org/mirror' "$c/output")" 1 "$label Debian mirror advice"
          fi
          check "$(count 'supports only Debian and Ubuntu' "$c/output")" 0 "$label supported distro is not refused"
          ;;
        custom)
          check "$rc" 0 "$label custom mirror from the prompt succeeds"
          check "$prompts:$final_host" 1:custom.example.org "$label prompt answer is applied"
          ;;
      esac
    done
  done
done
printf '%s failure(s); actual pkg_update and actual pre-bundle apt fragment; apt-get/pct/reachability/prompt models, no native Devuan or deb822 claim\n' "$failures"
[[ "$failures" == 0 ]]

printf 'RUNTIME_HOOKS_RESULT failures=0\n'
