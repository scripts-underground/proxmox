#!/usr/bin/env bash
# shellcheck disable=SC2034,SC2154
set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/../lib/runtime-hooks/addon-release.sh"
app=bookstack
script_type=lxc
release_app=bookstack release_mode=tarball release_asset=source.tar.gz
variants=(fresh selected current clean pending checker download build migrate runtime missing-config missing-install missing-runtime)
hook_paths=()
runtime_hooks_variant() {
  case "$variant" in checker | download | build | migrate | runtime) fault=$variant ;; esac
}
runtime_hooks_expected() {
  case "$fault" in checker) expected=17 ;; migrate) expected=53 ;; esac
  case "$variant" in missing-config | missing-install) expected=1 ;; esac
}
runtime_hooks_model() {
  addon_release_model
  [[ ! -f "$c/clean" ]] || CLEAN_INSTALL=1 UPDATE_FORCE=1 FORCE_DEPLOY=1
  apt() { :; }
  setup_php() { printf 'php\n' >> "$c/provisioning"; }
  setup_composer() { printf 'composer\n' >> "$c/provisioning"; }
  setup_mariadb() { printf 'mariadb\n' >> "$c/provisioning"; }
  setup_mariadb_db() { export MARIADB_DB_NAME MARIADB_DB_USER MARIADB_DB_PASS=fixture-secret; }
  a2enmod() { :; }
  a2ensite() { :; }
  a2dissite() { :; }
  chown() { command chown "$@"; }
  env_audit() {
    [[ "$*" == *'/opt/bookstack'* ]] || return 0
    local file mode
    for file in /opt/bookstack/.env*; do
      [[ -f "$file" ]] || continue
      if grep -q 'fixture-secret' "$file"; then
        mode=$(stat -c %a "$file")
        (((8#$mode & 7) == 0)) || printf 'exposed\n' >> "$c/exposures"
      fi
    done
  }
  sed() {
    command sed "$@"
    env_audit "$@"
  }
  chmod() {
    command chmod "$@"
    env_audit "$@"
  }
  cp() {
    command cp "$@"
    env_audit "$@"
  }
  php() {
    printf '%s\n' "$*" >> "$c/artisan"
    [[ "$APP_FAULT" != migrate || "$*" != *migrate* ]] || return 53
    if [[ "$*" == *key:generate* ]]; then
      command sed -i 's|APP_KEY=.*|APP_KEY=fixture-key|' .env
    fi
    env_audit /opt/bookstack/.env
  }
  composer() { "$c/local/bin/composer" "$@"; }
  curl_download() {
    [[ "$APP_FAULT" != download ]] || return 22
    addon_release_download "$@"
  }
  systemctl() {
    printf '%s\n' "$*" >> "$c/services"
    [[ "$APP_FAULT" != runtime || "$*" != 'start apache2' ]] || return 51
  }
}
runtime_hooks_setup() {
  for log in requests downloads provisioning exposures artisan; do : > "$c/$log"; done
  mkdir -p "$c/etc/apache2/sites-available" "$c/payload/"{public/uploads,storage/uploads,themes,bootstrap/cache}
  printf 'APP_URL=http://localhost\nAPP_KEY=\nDB_DATABASE=default\nDB_USERNAME=default\nDB_PASSWORD=default\n' > "$c/payload/.env.example"
  printf 'new public code\n' > "$c/payload/public/index.php"
  printf 'incoming defaults\n' > "$c/payload/public/uploads/canary"
  printf 'incoming defaults\n' > "$c/payload/storage/uploads/canary"
  printf 'incoming defaults\n' > "$c/payload/themes/canary"
  cat > "$c/local/bin/composer" << 'SH'
#!/usr/bin/env bash
set -euo pipefail
printf '%s\n' "$*" >> "$APP_FIXTURE/composer"
[[ "$APP_FAULT" != build ]] || exit 52
mkdir -p vendor
printf 'dependencies\n' > vendor/autoload.php
SH
  chmod 0755 "$c/local/bin/composer"
  : > "$c/composer"
  if [[ "$role" == update ]]; then
    mkdir -p "$c/opt/bookstack/"{public/uploads,storage/uploads,themes,bootstrap/cache,vendor}
    printf 'old public code\n' > "$c/opt/bookstack/public/index.php"
    printf 'old dependencies\n' > "$c/opt/bookstack/vendor/autoload.php"
    printf 'DB_PASSWORD=fixture-secret\nAPP_KEY=original-key\nAPP_URL=http://custom.local:8181\n' > "$c/opt/bookstack/.env"
    chmod 0644 "$c/opt/bookstack/.env"
    stat -c %i "$c/opt/bookstack/.env" > "$c/env-inode"
    for path in public/uploads storage/uploads themes; do
      printf 'USER canary\n' > "$c/opt/bookstack/$path/canary"
      stat -c %i "$c/opt/bookstack/$path" >> "$c/data-inodes"
    done
    printf 'custom apache settings\n' > "$c/etc/apache2/sites-available/bookstack.conf"
    case "$variant" in
      current | clean | pending | missing-runtime) printf '2.0.0\n' > "$c/home/.bookstack" ;;
    esac
    [[ "$variant" != clean ]] || : > "$c/clean"
    [[ "$variant" != pending ]] || printf 'interrupted\n' > "$c/state/bookstack"
    [[ "$variant" != missing-runtime ]] || rm "$c/opt/bookstack/vendor/autoload.php"
    [[ "$variant" != missing-config ]] || rm "$c/opt/bookstack/.env"
    [[ "$variant" != missing-install ]] || mv "$c/opt/bookstack" "$c/absent-bookstack"
  fi
}
runtime_hooks_assert() {
  case "$variant" in missing-config | missing-install) return 0 ;; esac
  if [[ "$role" == update ]]; then
    runtime_hooks_configuration_assert
    check "$(stat -c %i "$c/opt/bookstack/.env")" "$(cat "$c/env-inode")" "$app/$variant configuration inode retained"
    check "$(stat -c %a "$c/opt/bookstack/.env")" 640 "$app/$variant existing secret mode hardened"
    check "$(stat -c '%u:%g' "$c/opt/bookstack/.env")" 0:33 "$app/$variant web reader owns no secret file"
    check "$(stat -c %s "$c/provisioning")" 0 "$app/$variant installed database and runtime not reprovisioned"
    local inodes='' path
    for path in public/uploads storage/uploads themes; do
      check "$(cat "$c/opt/bookstack/$path/canary" 2> /dev/null || true)" 'USER canary' "$app/$variant $path bytes retained"
      inodes+="$(stat -c %i "$c/opt/bookstack/$path")"$'\n'
    done
    check "${inodes%$'\n'}" "$(cat "$c/data-inodes")" "$app/$variant persistent directories stay in place"
    check "$(cat "$c/etc/apache2/sites-available/bookstack.conf")" 'custom apache settings' "$app/$variant service settings retained"
  fi
  if [[ "$role" == install || "$rc" == 0 ]]; then
    check "$(stat -c %s "$c/exposures")" 0 "$app/$variant secrets never world-readable during writes"
  fi
  if [[ "$variant" == current || "$variant" == checker ]]; then
    check "$(stat -c %s "$c/services")" 0 "$app/$variant no service effects"
    check "$(stat -c %s "$c/downloads")" 0 "$app/$variant no deployment"
  elif [[ "$rc" == 0 ]]; then
    check "$(cat "$c/opt/bookstack/public/index.php")" 'new public code' "$app/$variant selected source reaches document root"
    check "$(cat "$c/opt/bookstack/vendor/autoload.php")" dependencies "$app/$variant dependency consumer ready"
    if [[ "$variant" == selected ]]; then
      check "$(grep -c '/releases/latest$' "$c/requests" || true)" 1 "$app one release selection"
      check "$(grep -c '/releases/tags/v2.0.0$' "$c/requests" || true)" 1 "$app selected raw tag deployed"
    fi
  fi
  if [[ "$role" == install && "$rc" == 0 ]]; then
    check "$(stat -c '%a %u:%g' "$c/opt/bookstack/.env")" '640 0:33' "$app fresh config has private web-readable ownership"
  fi
}
runtime_hooks_failure_services_assert() {
  local starts=0
  [[ "$fault" != runtime ]] || starts=1
  check "$(grep -Ec '^(start|reload|restart)|--now' "$c/services" || true)" "$starts" "$app/$variant failed stage does not activate partial app"
}
runtime_hooks_retry_needed() { [[ "$expected" != 0 && "$variant" != missing-config && "$variant" != missing-install ]]; }
runtime_hooks_retry_assert() {
  runtime_hooks_configuration_assert
  check "$(stat -c %i "$c/opt/bookstack/.env")" "$(cat "$c/env-inode")" "$app retry retains config inode"
  check "$(cat "$c/opt/bookstack/vendor/autoload.php")" dependencies "$app pending retry repairs dependencies"
}
runtime_hooks_main "$@"
