#!/usr/bin/env bash
# shellcheck disable=SC2034,SC2154
set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/../lib/runtime-hooks/addon-release.sh"
app=bitmagnet
script_type=lxc
release_app=bitmagnet release_mode=tarball release_asset=unused.tar.gz
variants=(fresh fresh-key selected no-update clean pending checker download build backup runtime missing missing-config)
hook_paths=(/tmp/backup.sql legacy-backup.sql)
runtime_hooks_variant() {
  case "$variant" in
    checker | backup) fault=$variant ;;
    fresh-key) role=install ;;
  esac
}
runtime_hooks_expected() {
  case "$variant" in checker) expected=17 ;; backup) expected=53 ;; missing | missing-config) expected=1 ;; esac
}
runtime_hooks_model() {
  addon_release_model
  chown() { command chown "$@"; }
  apt() { :; }
  setup_postgresql_db() { export PG_DB_NAME=bitmagnet PG_DB_USER=bitmagnet PG_DB_PASS=fixture-secret; }
  if [[ -f "$c/clean" ]]; then CLEAN_INSTALL=1 UPDATE_FORCE=1 FORCE_DEPLOY=1; fi
  curl_download() {
    [[ "$APP_FAULT" != download ]] || return 22
    addon_release_download "$@"
  }
  # Only the database subprocess is modeled. The hook owns backup publication.
  runuser() {
    [[ "$APP_FAULT" != backup ]] || return 53
    printf '%s\n' "$*" >> "$c/backup-commands"
    printf 'fixture database backup\n'
  }
  su() {
    [[ "$APP_FAULT" != backup ]] || return 53
    printf '%s\n' "$*" | tr -s '[:space:]' ' ' >> "$c/backup-commands"
    printf 'fixture database backup\n' > "$c/legacy-backup.sql"
  }
  cat() {
    local pid=$BASHPID output
    output=$(readlink "/proc/$pid/fd/1")
    if [[ "$output" == "$c/etc/"* ]]; then
      printf '%s %s\n' "$output" "$(stat -Lc '%a %u %g' "/proc/$pid/fd/1")" >> "$c/creation-observations"
    fi
    command cat "$@"
  }
  printf() {
    local pid=$BASHPID output
    output=$(readlink "/proc/$pid/fd/1")
    if [[ "$output" == "$c/etc/"* ]]; then
      command printf '%s %s\n' "$output" "$(stat -Lc '%a %u %g' "/proc/$pid/fd/1")" >> "$c/creation-observations"
    fi
    command printf "$@"
  }
  mv() {
    if [[ "${!#}" == "$c/etc/bitmagnet.env" ]]; then
      local arg source=''
      for arg in "$@"; do [[ "$arg" == -* || "$arg" == "$c/etc/bitmagnet.env" ]] || source=$arg; done
      printf '%s\n' "$(stat -c '%a %u %g' "$source")" >> "$c/publication-observations"
    fi
    command mv "$@"
  }
  systemctl() {
    if [[ "$1" == start && "$APP_FAULT" == runtime ]]; then
      printf 'failed-start %s\n' "${!#}" >> "$c/services"
      return 51
    fi
    printf '%s\n' "$*" >> "$c/services"
  }
}
runtime_hooks_setup() {
  for log in requests downloads creation-observations publication-observations backup-commands; do : > "$c/$log"; done
  mkdir -p "$c/opt/bitmagnet" "$c/etc" "$c/local/bin"
  printf 'POSTGRES_HOST=localhost\nPOSTGRES_USER=bitmagnet\nPOSTGRES_NAME=bitmagnet\nPOSTGRES_PASSWORD=existing-secret\nTMDB_ENABLED=false\n' > "$c/etc/bitmagnet.env"
  cp "$c/etc/bitmagnet.env" "$c/expected-env"
  stat -c '%i' "$c/etc/bitmagnet.env" > "$c/env-inode"
  chmod 0644 "$c/etc/bitmagnet.env"
  chown 65534:65534 "$c/etc/bitmagnet.env"
  printf 'log:\n  json: true\n' > "$c/opt/bitmagnet/config.yml"
  printf 'stale config backup\n' > "$c/opt/config.yml"
  printf 'stale environment backup\n' > "$c/opt/.env"
  cp "$c/opt/bitmagnet/config.yml" "$c/expected-config"
  stat -c '%i' "$c/opt/bitmagnet/config.yml" > "$c/config-inode"
  printf 'incoming config default\n' > "$c/payload/config.yml"
  printf 'incoming environment default\n' > "$c/payload/.env"
  printf '#!/bin/sh\nprintf "old-bitmagnet\\n"\n' > "$c/opt/bitmagnet/bitmagnet"
  chmod 0755 "$c/opt/bitmagnet/bitmagnet"
  cat > "$c/local/bin/go" << 'GO'
#!/usr/bin/env bash
[[ "$APP_FAULT" != build ]] || exit 52
tag=${*: -1}
tag=${tag##*=}
printf '#!/bin/sh\nprintf "%s\\n"\n' "$tag" > bitmagnet
chmod 0755 bitmagnet
GO
  chmod 0755 "$c/local/bin/go"
  case "$variant" in no-update | clean | pending) printf '2.0.0\n' > "$c/home/.bitmagnet" ;; *) printf '1.0.0\n' > "$c/home/.bitmagnet" ;; esac
  if [[ "$variant" == clean ]]; then : > "$c/clean"; fi
  if [[ "$variant" == pending ]]; then
    printf 'interrupted\n' > "$c/state/bitmagnet"
    rm "$c/opt/bitmagnet/bitmagnet"
  fi
  if [[ "$role" == install ]]; then
    rm "$c/etc/bitmagnet.env"
    [[ "$variant" != fresh-key ]] || printf 'fixture-tmdb-key\n' > "$c/stdin"
  fi
  [[ "$variant" != missing ]] || mv "$c/opt/bitmagnet" "$c/absent-bitmagnet"
  [[ "$variant" != missing-config ]] || rm "$c/etc/bitmagnet.env"
}
runtime_hooks_assert() {
  case "$variant" in missing | missing-config) return 0 ;; esac
  if [[ "$role" == install ]]; then
    check "$(cat "$c/publication-observations")" '600 0 0' "$app fresh publishes an already-private root-owned file"
    check "$(grep -c "^$c/etc/\\.bitmagnet\\.env\\.[^ ]* 600 0 0$" "$c/creation-observations" || true)" 1 "$app writes secrets only into private staging"
    check "$(grep -c "^$c/etc/bitmagnet.env " "$c/creation-observations" || true)" 0 "$app never streams secrets into the public pathname"
    if [[ "$variant" == fresh-key ]]; then
      check "$(grep -c '^TMDB_API_KEY=fixture-tmdb-key$' "$c/etc/bitmagnet.env" || true)" 1 "$app explicit TMDB key retained"
    else check "$(grep -c '^TMDB_ENABLED=false$' "$c/etc/bitmagnet.env" || true)" 1 "$app EOF retains disabled TMDB default"; fi
  else
    check "$(cmp -s "$c/expected-env" "$c/etc/bitmagnet.env" && printf same || printf different)" same "$app/$variant complete secret bytes retained"
    check "$(stat -c '%i' "$c/etc/bitmagnet.env")" "$(cat "$c/env-inode")" "$app/$variant secret inode retained"
    runtime_hooks_configuration_assert
    check "$(cmp -s "$c/expected-config" "$c/opt/bitmagnet/config.yml" && printf same || printf different)" same "$app/$variant current config retained"
    check "$(stat -c '%i' "$c/opt/bitmagnet/config.yml" 2> /dev/null || true)" "$(cat "$c/config-inode")" "$app/$variant config inode retained"
  fi
  check "$(stat -c '%a %u %g' "$c/etc/bitmagnet.env" 2> /dev/null || true)" '600 0 0' "$app/$variant root-only runtime secrets"
  if [[ "$variant" == checker || "$variant" == no-update ]]; then
    check "$(stat -c %s "$c/downloads")" 0 "$app/$variant no deployment"
    check "$(stat -c %s "$c/services")" 0 "$app/$variant no service effects"
  elif [[ "$rc" == 0 ]]; then
    check "$("$c/opt/bitmagnet/bitmagnet" 2> /dev/null || true)" v2.0.0 "$app/$variant selected-source executable consumer"
    if [[ "$role" == update ]]; then
      check "$(stat -c '%a %u %g' "$c/opt/backup.sql")" '600 0 0' "$app backup private at publication"
      check "$(cat "$c/opt/backup.sql")" 'fixture database backup' "$app backup consumer"
      check "$(grep -c -- '--data-only --on-conflict-do-nothing --rows-per-insert=1000 --table=metadata_sources' "$c/backup-commands" || true)" 1 "$app existing merge-friendly backup policy retained"
      if [[ "$variant" != clean && "$variant" != pending ]]; then
        check "$(grep -c '/releases/latest$' "$c/requests" || true)" 1 "$app one release selection"
        check "$(grep -c '/releases/tags/v2.0.0$' "$c/requests" || true)" 1 "$app selected raw tag deployed"
      fi
    fi
  fi
}
runtime_hooks_retry_needed() { [[ "$role" == update && "$expected" != 0 && "$variant" != missing && "$variant" != missing-config ]]; }
runtime_hooks_retry_assert() {
  local selected=v2.0.0
  if [[ $(grep -c '/releases/latest$' "$c/requests") -gt 1 ]]; then selected=v9.0.0; fi
  check "$("$c/opt/bitmagnet/bitmagnet")" "$selected" "$app independent retry restores its newly selected executable"
  check "$(cmp -s "$c/expected-env" "$c/etc/bitmagnet.env" && printf same || printf different)" same "$app retry retains secrets"
  check "$(stat -c '%i' "$c/etc/bitmagnet.env")" "$(cat "$c/env-inode")" "$app retry retains secret inode"
}
runtime_hooks_main "$@"
