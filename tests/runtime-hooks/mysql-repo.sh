#!/usr/bin/env bash
# runtime-hooks-contract: fixture case-asserted
# Actual manage_tool_repository mysql branch from misc/tools.func with the real get_os_info
# and cleanup_old_repo_files, in a private /etc/apt. The key transport, the fallback-suite
# probe and (for fault legs) dpkg are models. No APT signature or package is involved here;
# native APT trust of repo.mysql.com is proved separately in the receiver.
# STD, TAB3 and prompt are read by the sourced framework and hook functions.
# shellcheck disable=SC2034
set -euo pipefail
ROOT=$(realpath "$(dirname "${BASH_SOURCE[0]}")/../..")
if [[ "${1:-}" == --child ]]; then
  c="$CASE_ROOT"
  mount --bind "$c/apt" /etc/apt
  mount --bind "$c/root" /root
  source "$ROOT/misc/core.func"
  source "$ROOT/misc/tools.func"
  msg_info() { :; }
  msg_ok() { :; }
  msg_error() { printf 'error:%s\n' "$*" >> "$c/messages"; }
  download_gpg_key() {
    printf 'key:%s\n' "$*" >> "$c/events"
    [[ "${KEY_STATUS:-0}" == 0 ]] || return "$KEY_STATUS"
    printf 'KEYRING\n' > "$2"
    if [[ "${WRITE_FAULT:-0}" == 1 ]]; then
      mount --bind /etc/apt/sources.list.d /etc/apt/sources.list.d
      mount -o remount,ro,bind /etc/apt/sources.list.d
    fi
  }
  get_fallback_suite() {
    printf 'fallback:%s\n' "$*" >> "$c/events"
    [[ "${FALLBACK_STATUS:-0}" == 0 ]] || return "$FALLBACK_STATUS"
    printf '%s\n' "${FALLBACK_SUITE:-}"
  }
  dpkg() {
    printf 'dpkg:%s\n' "$*" >> "$c/events"
    [[ "${DPKG_STATUS:-0}" == 0 ]] || return "$DPKG_STATUS"
    printf '%s\n' "${DPKG_ARCH-amd64}"
  }
  curl() { printf 'Codename: trixie\nComponents: mysql-8.4-lts\nArchitectures: amd64\n'; }
  rc=0
  case "$CALL" in
    setup-mysql)
      # Actual setup_mysql on its default Debian 12 / 8.0 official-repository path; every
      # dependency below it is a model that records its arguments.
      STD=""
      is_tool_installed() { return 1; }
      prepare_repository_setup() { return 0; }
      ensure_apt_working() { return 0; }
      install_packages_with_retry() { return 0; }
      cache_installed_version() { return 0; }
      apt-cache() { printf 'mysql-server\n'; }
      mysql() { return 0; }
      manage_tool_repository() { printf '%s\n' "$*" > "$c/repo-args"; }
      setup_mysql || rc=$?
      ;;
    mysql-script)
      # Actual standalone MySQL install hook (scripts/lxc/mysql.sh): only the key transport
      # and its consumers are recorded; this does not validate its other installer flow.
      STD=""
      sed '/^# shellcheck disable=SC1090$/,$d' "$ROOT/scripts/lxc/mysql.sh" > "$c/mysql-hooks.sh"
      source "$c/mysql-hooks.sh"
      TAB3=""
      read() { printf -v prompt n; }
      curl() {
        printf '%s\n' "$*" > "$c/curl-args"
        printf 'KEY\n'
      }
      gpg() { cat > "$c/gpg-input"; }
      lsb_release() { if [[ "$1" == -si ]]; then printf 'Debian\n'; else printf 'bookworm\n'; fi; }
      apt() { return 0; }
      mysql() { return 0; }
      systemctl() { return 0; }
      install_script || rc=$?
      ;;
    plain) manage_tool_repository mysql "$VERSION" "${REPO_URL-https://repo.mysql.com/apt/debian}" "${KEY_URL-https://repo.mysql.com/RPM-GPG-KEY-mysql-2025}" || rc=$? ;;
    cond) if manage_tool_repository mysql "$VERSION" "${REPO_URL-https://repo.mysql.com/apt/debian}" "${KEY_URL-https://repo.mysql.com/RPM-GPG-KEY-mysql-2025}"; then rc=0; else rc=$?; fi ;;
  esac
  printf '%s\n' "$rc" > "$c/rc"
  exit 0
fi

: "${TMPDIR:?disk-backed TMPDIR required}"
systemd-detect-virt --vm --quiet || exit 1
case "$(realpath -e "$TMPDIR")" in /tmp | /tmp/*) exit 1 ;; esac
case "$(findmnt -rn -T "$TMPDIR" -o FSTYPE)" in '' | tmpfs | ramfs) exit 1 ;; esac
work=$(mktemp -d "$TMPDIR/mysql-repo.XXXXXX")
trap 'rm -rf -- "$work"' EXIT
failures=0
check() {
  if [[ "$1" == "$2" ]]; then printf 'PASS %s\n' "$3"; else
    printf 'FAIL %s: expected <%s>, got <%s>\n' "$3" "$2" "$1" >&2
    failures=$((failures + 1))
  fi
}
n=0
# go LABEL ENV...: run one cold child with a private /etc/apt that holds stale MySQL
# repository state and an unrelated source. Sets c, rc and L.
go() {
  local label="$1"
  n=$((n + 1))
  c="$work/$n"
  mkdir -p "$c/apt/sources.list.d" "$c/apt/keyrings" "$c/apt/trusted.gpg.d" "$c/root" "$c/receiver-root"
  printf 'receiver credentials must survive\n' > "$c/receiver-root/mysql.creds"
  : > "$c/events"
  : > "$c/messages"
  printf 'Types: deb\n' > "$c/apt/sources.list.d/debian.sources"
  printf 'deb stale\n' > "$c/apt/sources.list.d/mysql-old.list"
  printf 'stale\n' > "$c/apt/sources.list.d/mysql.sources"
  printf 'stale\n' > "$c/apt/keyrings/mysql.gpg"
  printf 'stale\n' > "$c/apt/trusted.gpg.d/mysql-legacy.gpg"
  if [[ "${BLOCK:-0}" == 1 ]]; then
    rm -f "$c/apt/sources.list.d/mysql.sources"
    mkdir "$c/apt/sources.list.d/mysql.sources"
    printf 'keep\n' > "$c/apt/sources.list.d/mysql.sources/member"
  fi
  rc=missing
  env -i PATH="$PATH" HOME="$c" TMPDIR="$TMPDIR" CASE_ROOT="$c" ROOT="$ROOT" CALL="$CALL" VERSION=8.0 \
    _OS_ID=debian _OS_CODENAME=bookworm _OS_VERSION=12 _OS_VERSION_FULL='12 (bookworm)' BUILD_LOG="$c/build.log" "${@:2}" \
    timeout 30s unshare -m --propagation private -- bash -c '
      mount --bind "$CASE_ROOT/receiver-root" /root
      unshare -m --propagation private -- bash "$1" --child
    ' bash "$0" < /dev/null > "$c/output" 2>&1 || true
  [[ ! -f "$c/rc" ]] || rc=$(< "$c/rc")
  L="$label/$CALL"
}
sources() { cat "$c/apt/sources.list.d/mysql.sources" 2> /dev/null || true; }
expected_sources() { printf 'Types: deb\nURIs: https://repo.mysql.com/apt/debian/\nSuites: %s\nComponents: %s\nArchitectures: amd64\nSigned-By: /etc/apt/keyrings/mysql.gpg' "$1" "$2"; }
absent_sources() { check "$(test -e "$c/apt/sources.list.d/mysql.sources" && printf present || printf absent)" absent "$L no repository file after failure"; }
for CALL in plain cond; do
  # Ordinary Debian 12 / MySQL 8.0 (setup_mysql's default official-repository input)
  go debian12-8.0
  check "$rc" 0 "$L status"
  check "$(sources)" "$(expected_sources bookworm mysql-8.0)" "$L exact deb822 repository"
  check "$(cat "$c/events")" "$(printf 'dpkg:--print-architecture\nkey:https://repo.mysql.com/RPM-GPG-KEY-mysql-2025 /etc/apt/keyrings/mysql.gpg dearmor')" "$L checked selection before key transport, no fallback probe"
  check "$(cat "$c/apt/keyrings/mysql.gpg")" KEYRING "$L keyring published at the Signed-By path"
  check "$(ls "$c/apt/sources.list.d" | tr '\n' ' ')" 'debian.sources mysql.sources ' "$L stale MySQL files cleaned, unrelated source kept"
  check "$(ls "$c/apt/trusted.gpg.d" | wc -l)" 0 "$L stale trusted keys cleaned"
  # Component selection is preserved
  for pair in '8.0.36:mysql-8.0' '8.4:mysql-8.4-lts' '8.4.2:mysql-8.4-lts' '9.0:mysql-9.0'; do
    go "version-${pair%%:*}" VERSION="${pair%%:*}"
    check "$rc" 0 "$L status"
    check "$(sources)" "$(expected_sources bookworm "${pair##*:}")" "$L component ${pair##*:}"
  done
  # Debian suite mapping
  for pair in 'bullseye:bullseye' 'trixie:trixie' 'forky:trixie' 'sid:trixie'; do
    version=8.0
    component=mysql-8.0
    if [[ "${pair##*:}" == trixie ]]; then
      version=8.4
      component=mysql-8.4-lts
    fi
    go "debian-${pair%%:*}" _OS_CODENAME="${pair%%:*}" VERSION="$version"
    check "$(sources)" "$(expected_sources "${pair##*:}" "$component")" "$L suite ${pair##*:}"
  done
  # Non-Debian suite comes from the probe; its failure is returned
  go ubuntu _OS_ID=ubuntu _OS_CODENAME=noble FALLBACK_SUITE=jammy
  check "$(sources)" "$(expected_sources jammy mysql-8.0)" "$L probed suite used"
  check "$(grep -c '^fallback:ubuntu noble https://repo.mysql.com/apt/debian$' "$c/events" || true)" 1 "$L probe receives distro, codename and repository"
  go ubuntu-probe-fails _OS_ID=ubuntu _OS_CODENAME=noble FALLBACK_STATUS=9
  check "$rc" 9 "$L probe failure status"
  check "$(sources)" stale "$L probe failure preserves prior source"
  go ubuntu-probe-empty _OS_ID=ubuntu _OS_CODENAME=noble FALLBACK_SUITE=
  check "$rc" 65 "$L empty probe result refused"
  check "$(sources)" stale "$L empty probe preserves prior source"
  # Required inputs and producers
  go missing-key KEY_URL=
  check "$rc" 65 "$L missing key URL status"
  check "$(cat "$c/events")" '' "$L missing key URL does no work"
  check "$(cat "$c/apt/keyrings/mysql.gpg")" stale "$L missing key URL leaves existing state"
  go missing-repo REPO_URL=
  check "$rc" 65 "$L missing repository URL status"
  check "$(cat "$c/events")" '' "$L missing repository URL does no work"
  go key-fails KEY_STATUS=7
  check "$rc" 7 "$L key failure status"
  absent_sources
  check "$(grep -c '^error:Failed to import MySQL GPG key' "$c/messages" || true)" 1 "$L key failure reported"
  go missing-codename _OS_CODENAME=
  check "$rc" 65 "$L missing codename status"
  check "$(sources)" stale "$L missing codename preserves prior source"
  go dpkg-fails DPKG_STATUS=5
  check "$rc" 5 "$L architecture failure status"
  check "$(sources)" stale "$L failed architecture preserves prior source"
  go dpkg-empty DPKG_ARCH=
  check "$rc" 65 "$L empty architecture refused"
  check "$(sources)" stale "$L empty architecture preserves prior source"
  BLOCK=1 go cleanup-fails
  BLOCK=0
  check "$rc" 1 "$L cleanup failure status"
  check "$(cat "$c/events")" 'dpkg:--print-architecture' "$L no key work after failed cleanup"
  go write-fails WRITE_FAULT=1
  check "$([[ "$rc" != 0 && "$rc" != missing ]] && printf nonzero || printf '%s' "$rc")" nonzero "$L failed sources write is returned"
  absent_sources
done
# Producer-side witnesses: the key URL actually passed by the setup_mysql call site and
# fetched by the standalone hook is the renewed key.
CALL=setup-mysql
go setup-mysql-call-site
check "$rc" 0 "$L status"
check "$(cat "$c/repo-args")" 'mysql 8.0 https://repo.mysql.com/apt/debian https://repo.mysql.com/RPM-GPG-KEY-mysql-2025' "$L passes the renewed key URL and unchanged 8.0 official repository"
CALL=mysql-script
go mysql-script-key
check "$rc" 0 "$L status"
check "$(cat "$c/receiver-root/mysql.creds")" 'receiver credentials must survive' "$L receiver root credentials untouched"
check "$(test -f "$c/root/mysql.creds" && printf present || printf absent)" present "$L installer writes only case-local root credentials"
check "$(cat "$c/curl-args")" '-fsSL https://repo.mysql.com/RPM-GPG-KEY-mysql-2025' "$L fetches the renewed key over verified HTTPS"
check "$(cat "$c/gpg-input")" KEY "$L key bytes reach gpg --dearmor"
check "$(grep -c '^Components: mysql-8.0$' "$c/apt/sources.list.d/mysql.sources" || true)" 1 "$L component unchanged"
printf '%s failure(s); actual mysql branch, get_os_info and cleanup_old_repo_files in a private /etc/apt; key transport, fallback probe and dpkg are models, no APT signature/package claim\n' "$failures"
printf 'RUNTIME_HOOKS_RESULT failures=%s\n' "$failures"
[[ "$failures" == 0 ]]
