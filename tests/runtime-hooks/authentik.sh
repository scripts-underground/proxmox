#!/usr/bin/env bash
# shellcheck disable=SC2034,SC2154
set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/../lib/runtime-hooks/harness.sh"
app=authentik
script_type=lxc
variants=(fresh update legacy current clean pending test-city test-asn configured-test relative-test real-database geoip-check xmlsec-check app-check download build runtime)
hook_paths=()
runtime_hooks_variant() {
  case "$variant" in geoip-check | xmlsec-check | app-check) fault=$variant ;; esac
}
runtime_hooks_expected() {
  case "$fault" in geoip-check | xmlsec-check | app-check) expected=28 ;; esac
}
runtime_hooks_model() {
  [[ ! -f "$c/clean" ]] || UPDATE_FORCE=1 FORCE_DEPLOY=1
  apt() { :; }
  setup_nodejs() { :; }
  setup_yq() { :; }
  setup_go() { :; }
  setup_rust() { :; }
  setup_uv() { :; }
  setup_postgresql_db() { export PG_DB_PASS=fixture-secret; }
  useradd() { :; }
  crontab() { cat > "$c/crontab"; }
  nproc() { printf '1\n'; }
  ldconfig() { :; }
  rustup() { :; }
  make() { :; }
  npm() { [[ "$APP_FAULT" != build ]] || return 52; }
  cargo() {
    mkdir -p target/release
    printf 'new-worker\n' > target/release/authentik
  }
  go() {
    [[ "$1" == build ]] || return 0
    printf 'new-proxy\n' > "$3"
  }
  uv() { mkdir -p .venv; }
  yq() {
    if [[ "$1" == -r ]]; then
      case "$2" in
        *'.geoip'*) cat "$c/configured-city" ;;
        *'.asn'*) printf '/opt/authentik-data/geoip/GeoLite2-ASN.mmdb\n' ;;
      esac
      return 0
    fi
    # Model the YAML editor's publication, not its secret-selection policy.
    printf '%s\n' "$2" >> "${!#}"
    local mode
    mode=$(stat -c %a "${!#}")
    (((8#$mode & 7) == 0)) || printf 'exposed\n' >> "$c/exposures"
  }
  systemctl() {
    printf '%s\n' "$*" >> "$c/services"
    case "$1" in
      is-active | is-enabled) return 1 ;;
      start) [[ "$APP_FAULT" != runtime ]] || return 51 ;;
    esac
  }
  _apt_install_release_package() { :; }
  dpkg-deb() {
    case "$*" in
      *' Package') printf 'geoipupdate\n' ;;
      '--fsys-tarfile '*) tar -cf - --files-from /dev/null ;;
    esac
  }
  dpkg-query() { :; }
  curl() {
    local out='' url='' format='' tag='v7.1.1'
    while (($#)); do
      case "$1" in
        -o)
          out=$2
          shift
          ;;
        -w)
          format=$2
          shift
          ;;
        http*) url=$1 ;;
      esac
      shift
    done
    printf '%s\n' "$url" >> "$c/requests"
    case "$url" in
      *maxmind/geoipupdate*) [[ "$APP_FAULT" != geoip-check ]] || return 28 ;;
      *lsh123/xmlsec*)
        [[ "$APP_FAULT" != xmlsec-check ]] || return 28
        tag=1.3.11
        ;;
      *goauthentik/authentik*)
        [[ "$APP_FAULT" != app-check ]] || return 28
        tag=version/2026.5.2
        ;;
    esac
    local body="{\"tag_name\":\"$tag\",\"assets\":[{\"browser_download_url\":\"https://fixture.invalid/geoipupdate_amd64.deb\"}]}"
    if [[ -n "$out" ]]; then printf '%s' "$body" > "$out"; else printf '%s' "$body"; fi
    [[ -z "$format" ]] || printf 200
  }
  curl_download() {
    [[ "$APP_FAULT" != download ]] || return 22
    printf '%s\n' "$2" >> "$c/downloads"
    if [[ "$1" == *.deb ]]; then printf 'fixture package\n' > "$1"; else tar -czf "$1" -C "$c" payload; fi
  }
}
runtime_hooks_setup() {
  for log in requests downloads exposures; do : > "$c/$log"; done
  printf '/opt/authentik-data/geoip/GeoLite2-City.mmdb\n' > "$c/configured-city"
  mkdir -p "$c/payload/"{web,authentik/lib,authentik/sources/kerberos,tests/geoip} "$c/etc/default" "$c/local/etc" "$c/opt/authentik-data"
  printf '#!/bin/sh\nexit 0\n' > "$c/payload/autogen.sh"
  chmod 0755 "$c/payload/autogen.sh"
  printf 'channel = "stable"\n' > "$c/payload/rust-toolchain.toml"
  printf 'public defaults\n' > "$c/payload/authentik/lib/default.yml"
  printf 'kerberos defaults\n' > "$c/payload/authentik/sources/kerberos/krb5.conf"
  printf 'saved data\n' > "$c/opt/authentik-data/canary"
  if [[ "$role" == update ]]; then
    printf '7.1.1\n' > "$c/home/.geoipupdate"
    # Same xmlsec release avoids an unrelated rebuild unless forced.
    printf '1.3.11\n' > "$c/home/.xmlsec"
    printf 'version/2026.5.0\n' > "$c/home/.authentik"
    mkdir -p "$c/etc/authentik" "$c/opt/xmlsec"
    printf 'secret_key: saved-secret\npostgresql: {password: fixture-secret}\n' > "$c/etc/authentik/config.yml"
    chmod 0644 "$c/etc/authentik/config.yml"
    stat -c %i "$c/etc/authentik/config.yml" > "$c/config-inode"
    sha256sum "$c/etc/authentik/config.yml" | cut -d' ' -f1 > "$c/config-hash"
    printf 'saved runtime settings\n' > "$c/etc/default/authentik-server"
    printf 'saved worker settings\n' > "$c/etc/default/authentik-worker"
    case "$variant" in current | clean | pending) printf 'version/2026.5.2\n' > "$c/home/.authentik" ;; esac
    [[ "$variant" != clean ]] || : > "$c/clean"
    [[ "$variant" != pending ]] || printf 'interrupted\n' > "$c/state/authentik"
    if [[ "$variant" == legacy ]]; then
      printf 'version/2026.2.0\n' > "$c/home/.authentik"
      printf 'saved legacy secrets\n' > "$c/etc/default/authentik"
      chmod 0644 "$c/etc/default/authentik"
    fi
    mkdir -p "$c/opt/authentik-data/geoip"
    case "$variant" in
      test-city) cp "$MAINTENANCE_REFERENCES/authentik/GeoLite2-City-Test.mmdb" "$c/opt/authentik-data/geoip/GeoLite2-City.mmdb" ;;
      test-asn) cp "$MAINTENANCE_REFERENCES/authentik/GeoLite2-ASN-Test.mmdb" "$c/opt/authentik-data/geoip/GeoLite2-ASN.mmdb" ;;
      configured-test)
        printf '/opt/authentik-data/custom city.mmdb\n' > "$c/configured-city"
        cp "$MAINTENANCE_REFERENCES/authentik/GeoLite2-City-Test.mmdb" "$c/opt/authentik-data/custom city.mmdb"
        ;;
      relative-test)
        printf 'data/custom city.mmdb\n' > "$c/configured-city"
        mkdir -p "$c/opt/authentik/data"
        cp "$MAINTENANCE_REFERENCES/authentik/GeoLite2-City-Test.mmdb" "$c/opt/authentik/data/custom city.mmdb"
        sha256sum "$c/opt/authentik/data/custom city.mmdb" | cut -d' ' -f1 > "$c/inside-hash"
        stat -c %i "$c/opt/authentik/data/custom city.mmdb" > "$c/inside-inode"
        ;;
      real-database) printf 'operator database bytes\n' > "$c/opt/authentik-data/geoip/GeoLite2-City.mmdb" ;;
    esac
    find "$c/opt/authentik-data" -type f -print0 | sort -z | xargs -0 sha256sum > "$c/data-before"
    find "$c/opt/authentik-data" -type f -printf '%p %i\n' | sort > "$c/data-inodes"
  fi
}
runtime_hooks_assert() {
  check "$(cat "$c/opt/authentik-data/canary")" 'saved data' "$app/$variant external data retained"
  if [[ "$role" == update ]]; then
    check "$(find "$c/opt/authentik-data" -type f -print0 | sort -z | xargs -0 sha256sum)" "$(cat "$c/data-before")" "$app/$variant all existing database bytes retained"
    check "$(find "$c/opt/authentik-data" -type f -printf '%p %i\n' | sort)" "$(cat "$c/data-inodes")" "$app/$variant database inodes retained"
    case "$variant" in
      test-city | test-asn | configured-test | relative-test) check "$(grep -c 'MaxMind test database' "$c/output" || true)" 1 "$app/$variant warns about known test database" ;;
      real-database | current) check "$(grep -c 'MaxMind test database' "$c/output" || true)" 0 "$app/$variant never labels unknown data as a test database" ;;
    esac
    if [[ "$variant" == relative-test ]]; then
      check "$(sha256sum "$c/opt/authentik/data/custom city.mmdb" 2> /dev/null | cut -d' ' -f1 || true)" "$(cat "$c/inside-hash")" "$app configured in-source database bytes retained"
      check "$(stat -c %i "$c/opt/authentik/data/custom city.mmdb" 2> /dev/null || true)" "$(cat "$c/inside-inode")" "$app configured in-source database inode retained"
    fi
    check "$(stat -c %i "$c/etc/authentik/config.yml")" "$(cat "$c/config-inode")" "$app/$variant config inode retained"
    check "$(stat -c %a "$c/etc/authentik/config.yml")" 640 "$app/$variant secret config hardened"
    if [[ "$variant" == legacy ]]; then
      check "$(sha256sum "$c/etc/authentik/config.bak" | cut -d' ' -f1)" "$(cat "$c/config-hash")" "$app legacy migration backs up exact original configuration"
      check "$(stat -c %a "$c/etc/authentik/config.bak")" 640 "$app legacy configuration backup private"
      check "$(stat -c %a "$c/etc/default/authentik.bak")" 600 "$app legacy environment backup private"
      check "$(cat "$c/etc/default/authentik.bak")" 'saved legacy secrets' "$app legacy environment backup retains secret bytes"
    else
      check "$(sha256sum "$c/etc/authentik/config.yml" | cut -d' ' -f1)" "$(cat "$c/config-hash")" "$app/$variant exact configuration retained"
      check "$(cat "$c/etc/default/authentik-server")" 'saved runtime settings' "$app/$variant server options retained"
      check "$(cat "$c/etc/default/authentik-worker")" 'saved worker settings' "$app/$variant worker options retained"
    fi
  fi
  if [[ "$role" == install && "$rc" == 0 ]]; then
    check "$(stat -c %s "$c/exposures")" 0 "$app fresh secret file never world-readable"
    check "$(stat -c %a "$c/etc/authentik/config.yml")" 640 "$app fresh secret file private to service group"
    check "$(stat -c %a "$c/local/etc/GeoIP.conf")" 600 "$app GeoIP credential file private"
    for service in ldap rac radius; do
      check "$(stat -c %a "$c/etc/default/authentik_$service")" 600 "$app $service token file private"
    done
  fi
  case "$variant" in
    geoip-check | xmlsec-check | app-check)
      check "$(stat -c %s "$c/downloads")" 0 "$app/$variant checker error precedes deployment"
      check "$(stat -c %s "$c/services")" 0 "$app/$variant checker error precedes service effects"
      ;;
  esac
}
runtime_hooks_retry_assert() {
  check "$(cat "$c/opt/authentik/authentik-server")" new-proxy "$app pending retry rebuilds proxy"
  check "$(cat "$c/opt/authentik/authentik-worker")" new-worker "$app pending retry rebuilds worker"
  check "$(sha256sum "$c/etc/authentik/config.yml" | cut -d' ' -f1)" "$(cat "$c/config-hash")" "$app retry retains existing secret bytes"
}
runtime_hooks_failure_services_assert() {
  local starts=0
  [[ "$fault" != runtime ]] || starts=1
  check "$(grep -Ec '^(start|reload|restart)|--now' "$c/services" || true)" "$starts" "$app/$variant failure reaches no later service start"
}
runtime_hooks_more_cases() {
  local case_dir outcome status
  for outcome in complete missing-city; do
    case_dir="$work/post-build-$outcome"
    mkdir -p "$case_dir/opt/authentik/tests/geoip" "$case_dir/bin"
    printf 'ASN fixture\n' > "$case_dir/opt/authentik/tests/geoip/GeoLite2-ASN-Test.mmdb"
    if [[ "$outcome" == complete ]]; then printf 'City fixture\n' > "$case_dir/opt/authentik/tests/geoip/GeoLite2-City-Test.mmdb"; fi
    printf '#!/bin/sh\nexit 0\n' > "$case_dir/bin/chown"
    chmod 0755 "$case_dir/bin/chown"
    bash -c 'curl() { :; }; source "$1"; declare -f post_build_script' hook "$ROOT/scripts/lxc/authentik.sh" > "$case_dir/hook.sh"
    status=0
    env CASE_DIR="$case_dir" PATH="$case_dir/bin:$PATH" unshare -m --propagation private bash -c '
      set -euo pipefail
      mount --bind "$CASE_DIR/opt" /opt
      source "$CASE_DIR/hook.sh"
      msg_info() { :; }; msg_ok() { :; }
      pct() {
        case "$1" in
          status) printf "status: running\n" ;;
          exec)
            shift 3
            if [[ "$1" == systemctl ]]; then printf "%s\n" "$*" >> "$CASE_DIR/services"; else "$@"; fi
            ;;
        esac
      }
      STD="" CTID=3201 CONTAINER_STORAGE=fixture
      post_build_script
    ' > "$case_dir/output" 2>&1 || status=$?
    if [[ "$outcome" == complete ]]; then
      check "$status" 0 "$app post-build selected-source GeoIP fixtures copied"
      check "$(find "$case_dir/opt/authentik-data" -name '*.mmdb' -type f | wc -l)" 0 "$app post-build never installs test databases"
    else
      check "$status" 0 "$app post-build does not require test database fixtures"
      check "$(find "$case_dir/opt/authentik-data" -name '*.mmdb' -type f | wc -l)" 0 "$app absent source fixture never populates live data"
    fi
  done
}
runtime_hooks_main "$@"
