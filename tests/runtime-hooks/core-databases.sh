#!/usr/bin/env bash
# runtime-hooks-contract: fixture case-asserted
# Actual database owners; SQL, repository transport, packages and init are models.
set -euo pipefail
ROOT=$(realpath "$(dirname "${BASH_SOURCE[0]}")/../..")
if [[ "${1:-}" == --child ]]; then
  c="$CASE_ROOT"
  source "$ROOT/misc/core.func"
  source "$ROOT/misc/tools.func"
  load_functions
  export STD='' APPLICATION=Probe
  if [[ "${NO_APP:-0}" == 1 ]]; then
    unset APP APPLICATION
    export PG_DB_CREDS_FILE="$c/explicit.creds" MARIADB_DB_CREDS_FILE="$c/explicit.creds"
  fi
  msg_info() { :; }
  msg_ok() { :; }
  msg_warn() { :; }
  msg_error() { printf '%s\n' "$*" >> "$c/messages"; }
  openssl() {
    local n=0
    [[ ! -f "$c/entropy-count" ]] || n=$(< "$c/entropy-count")
    printf '%s' "$((n + 1))" > "$c/entropy-count"
    case "$FAULT" in
      short) if [[ "$n" == 0 ]]; then printf 'ab+/\n'; else printf 'CDEFGHIJKLMNOPQRSTUVWXYZ\n'; fi ;;
      fail) return 42 ;;
      empty) return 0 ;;
      *) command openssl "$@" ;;
    esac
  }
  mariadb() { printf sql >> "$c/effects"; }
  sudo() { printf sql >> "$c/effects"; }
  is_unattended() { return 0; }
  rc=0
  case "$KIND" in
    password)
      case "$ENGINE" in
        mariadb)
          MARIADB_DB_NAME=probe MARIADB_DB_USER=probe setup_mariadb_db || rc=$?
          value="${MARIADB_DB_PASS:-}"
          ;;
        postgresql)
          PG_DB_NAME=probe PG_DB_USER=probe setup_postgresql_db || rc=$?
          value="${PG_DB_PASS:-}"
          ;;
        prompt) value=$(prompt_password Password generate 1 0) || rc=$? ;;
      esac
      printf '%s' "$value" > "$c/value"
      ;;
    pg-key)
      # No VM engine or configuration is borrowed by this fixture.
      command() { if [[ "$*" == '-v psql' ]]; then return 1; else builtin command "$@"; fi; }
      get_os_info() { case "$1" in id) echo debian ;; codename) echo trixie ;; esac }
      prepare_repository_setup() { :; }
      verify_repo_available() { return 0; }
      setup_deb822_repo() {
        printf '%s\n' "$2" > "$c/key-url"
        return 43
      }
      apt() {
        printf apt >> "$c/effects"
        return 44
      }
      setup_postgresql || rc=$?
      ;;
    mysql)
      mkdir -p "$c/apt/sources.list.d" "$c/apt/keyrings"
      mount --bind "$c/apt" /etc/apt
      get_os_info() { case "$1" in id) echo debian ;; codename) echo trixie ;; esac }
      is_tool_installed() { printf '%s' "${INSTALLED:-}"; }
      download_gpg_key() { printf key > "$2"; }
      dpkg() { printf amd64; }
      curl() {
        [[ "$FAULT" != metadata ]] || return 18
        printf 'Codename: trixie\nComponents: mysql-8.4-lts\nArchitectures: amd64\n'
      }
      cleanup_old_repo_files() { printf cleanup >> "$c/effects"; }
      prepare_repository_setup() { :; }
      ensure_apt_working() { :; }
      apt() {
        printf apt >> "$c/effects"
        [[ "$FAULT" == package-partial && "$1" == install ]] || return 0
        [[ "$*" != *Dpkg::Options* ]] || return 46
        [[ "$*" != *server* ]] || return 47
      }
      if [[ "$FAULT" != package-partial ]]; then
        install_packages_with_retry() {
          printf 'install:%s\n' "$*" >> "$c/packages"
          return 49
        }
      else
        sleep() { :; }
      fi
      upgrade_packages_with_retry() {
        printf 'upgrade:%s\n' "$*" >> "$c/packages"
        return 49
      }
      remove_old_tool_version() { printf purge >> "$c/effects"; }
      cache_installed_version() { printf '%s\n' "$*" > "$c/cached"; }
      setup_mysql || rc=$?
      ;;
    clickhouse)
      get_os_info() { echo debian; }
      dpkg() { printf '%s' "${ARCH:-amd64}"; }
      download_gpg_key() { printf fixture-key > "$2"; }
      curl_download() {
        case "$2" in
          */InRelease) cp "$c/Release" "$1" ;;
          */Packages.gz) cp "$c/Packages.gz" "$1" ;;
          */pool/*.deb) cp "$c/common.deb" "$1" ;;
          *) return 46 ;;
        esac
      }
      gpgv() { cp "$c/Release" "$4"; }
      prepare_repository_setup() {
        printf repo >> "$c/effects"
        return 47
      }
      ensure_dependencies() { printf dependencies >> "$c/effects"; }
      ensure_apt_working() {
        printf apt >> "$c/effects"
        return 47
      }
      stop_all_services() { printf stop >> "$c/effects"; }
      remove_old_tool_version() { printf purge >> "$c/effects"; }
      setup_clickhouse || rc=$?
      ;;
  esac
  printf '%s' "$rc" > "$c/rc"
  exit 0
fi
: "${TMPDIR:?disk TMPDIR required}"
systemd-detect-virt --vm --quiet || exit 65
work=$(mktemp -d "$TMPDIR/core-databases.XXXXXX")
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
  if [[ "$KIND" == clickhouse ]]; then
    mkdir -p "$c/package/DEBIAN" "$c/package/usr/bin"
    printf 'Package: clickhouse-common-static\nVersion: 25.8.1.5101\nArchitecture: %s\nMaintainer: Fixture <fixture@example.invalid>\nDescription: Instruction-admission fixture\n' "${ARCH:-amd64}" > "$c/package/DEBIAN/control"
    cat > "$c/package/usr/bin/clickhouse" << 'BIN'
#!/bin/sh
printf '%s\n' "$*" >> "$CASE_ROOT/binary-calls"
if test "$FAULT" = isa; then echo 'Instruction check fail. The CPU does not support AVX2 instruction set.' >&2; exit 1; fi
echo 'ClickHouse server version 25.8.1.5101 (official build).'
BIN
    chmod +x "$c/package/usr/bin/clickhouse"
    dpkg-deb --build "$c/package" "$c/common.deb" > "$c/package-build.log"
    printf 'Package: clickhouse-common-static\nVersion: 25.8.1.5101\nArchitecture: %s\nFilename: pool/main/c/clickhouse/common.deb\nSHA256: %s\n\n' "${ARCH:-amd64}" "$(sha256sum "$c/common.deb" | cut -d' ' -f1)" | gzip -c > "$c/Packages.gz"
    printf 'SHA256:\n %s %s main/binary-%s/Packages.gz\n' "$(sha256sum "$c/Packages.gz" | cut -d' ' -f1)" "$(wc -c < "$c/Packages.gz")" "${ARCH:-amd64}" > "$c/Release"
  fi
  env -i PATH="$PATH" HOME="$c/home" TMPDIR="$TMPDIR" CASE_ROOT="$c" KIND="$KIND" ENGINE="${ENGINE:-}" FAULT="${FAULT:-normal}" ARCH="${ARCH:-amd64}" \
    BUILD_LOG="$c/build.log" DEBUG_LOGFILE="$c/errors.log" "$@" unshare -m --propagation private -- bash "$0" --child > "$c/output" 2>&1
  rc=$(cat "$c/rc")
}
KIND=password
for ENGINE in mariadb postgresql prompt; do
  length=13
  [[ "$ENGINE" != prompt ]] || length=16
  FAULT=short go
  check "$rc" 0 "$ENGINE completes short entropy"
  check "$(wc -c < "$c/value")" "$length" "$ENGINE complete requested length"
  for FAULT in fail empty; do
    go
    wanted=42
    [[ "$FAULT" != empty ]] || wanted=1
    check "$rc" "$wanted" "$ENGINE $FAULT exact returning status"
    check "$(cat "$c/effects")" '' "$ENGINE $FAULT no SQL effect"
    check "$(cat "$c/value")" '' "$ENGINE $FAULT no partial password"
  done
done
for ENGINE in mariadb postgresql; do
  FAULT=normal go NO_APP=1 PG_DB_PASS=Exact_User_Password MARIADB_DB_PASS=Exact_User_Password
  check "$rc" 0 "$ENGINE explicit credentials path does not require app globals"
  check "$(cat "$c/value")" Exact_User_Password "$ENGINE explicit password retained exactly"
  check "$(test -e "$c/entropy-count" && printf generated || printf untouched)" untouched "$ENGINE explicit password never regenerated"
done
KIND=pg-key FAULT=normal go
check "$(cat "$c/key-url")" https://apt.postgresql.org/pub/repos/apt/ACCC4CF8.asc 'canonical PGDG key owner'
check "$rc" 43 'PostgreSQL repository failure is returned before package effects'
check "$(cat "$c/effects")" '' 'PostgreSQL key failure does not reach apt'
KIND=mysql FAULT=normal go
check "$(sed -n 's/^Suites: //p' "$c/apt/sources.list.d/mysql.sources")" trixie 'MySQL Debian 13 uses its native repository suite'
check "$(cat "$c/packages")" 'install:mysql-community-server mysql-community-client' 'fresh MySQL never silently changes engine after a failed install'
check "$rc" 49 'MySQL package failure is returned'
KIND=mysql FAULT=package-partial go
check "$rc" 46 'MySQL consumes actual required-set failure, not successful client fallback'
check "$(test -e "$c/cached" && cat "$c/cached" || true)" '' 'partial MySQL install cannot publish its version cache'
KIND=mysql FAULT=metadata go
check "$rc" 18 'incomplete MySQL metadata status retained'
check "$(cat "$c/effects")" '' 'failed metadata has no repository or package effects'
KIND=mysql FAULT=normal go INSTALLED=8.0
check "$rc" 65 'installed unsupported MySQL line refuses rather than upgrading its major'
check "$(cat "$c/effects")" '' 'installed MySQL refusal neither purges nor changes engine'
KIND=mysql FAULT=normal go INSTALLED=8.4
check "$(cat "$c/effects" | grep -c purge || true)" 0 'existing MySQL version never purged by the default request'
check "$(cat "$c/packages")" 'upgrade:mysql-community-server mysql-community-client' 'existing MySQL remains on its installed engine'
KIND=mysql FAULT=normal go INSTALLED=8.4 USE_MYSQL_REPO=false
check "$rc" 49 'existing MySQL distro update retains its exact failure'
check "$(cat "$c/packages")" 'upgrade:mysql-server mysql-client' 'distro update never switches installed MySQL to the default MariaDB package'
KIND=clickhouse FAULT=isa go CLICKHOUSE_VERSION=25.8.1.5101
check "$rc" 236 'selected ClickHouse CPU refusal status'
check "$(cat "$c/effects")" '' 'ClickHouse CPU refusal precedes package/repository/service effects'
check "$(cat "$c/binary-calls")" 'server --version' 'ClickHouse executes the exact selected package instruction checker'
KIND=clickhouse FAULT=compatible go CLICKHOUSE_VERSION=25.8.1.5101
check "$rc" 100 'compatible historical ClickHouse reaches the existing repository owner'
check "$(cat "$c/binary-calls")" 'server --version' 'historical ClickHouse is admitted by its build, not a blanket AVX2 rule'
KIND=clickhouse FAULT=compatible ARCH=arm64 go CLICKHOUSE_VERSION=25.8.1.5101
check "$rc" 100 'selected ARM package is admitted without an x86 AVX2 assertion'
check "$(cat "$c/binary-calls")" 'server --version' 'ARM adapter executes its selected package admission model'
bash "$ROOT/tests/lib/core-meilisearch.fixture.sh" || failures=$((failures + 1))
printf 'RUNTIME_HOOKS_RESULT failures=%s\n' "$failures"
[[ "$failures" == 0 ]]
