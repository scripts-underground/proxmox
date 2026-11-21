#!/usr/bin/env bash
# runtime-hooks-contract: lxc start-on-success
# shellcheck disable=SC2034,SC2154
# Callback inputs/outputs are supplied and consumed by the sourced harness.
set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/../lib/runtime-hooks/harness.sh"
app=discourse
script_type=lxc
variants=(fresh update download build)
hook_paths=()
baseline_runtime_hooks_model() {
  apt() { :; }
  setup_ruby() { :; }
  setup_deb822_repo() { :; }
  setup_postgresql_db() { export PG_DB_NAME PG_DB_USER PG_DB_PASS=fixture-db-secret; }
  setup_nodejs() {
    [[ "$APP_FAULT" != runtime ]] || return 51
    printf '%s\n' "$NODE_VERSION" > "$c/node-version"
  }
  rbenv() { printf ':\n'; }
  corepack() { printf '%s\n' "$*" >> "$c/corepack-calls"; }
  bundle() {
    printf '%s|%s|%s\n' "$PWD" "${RAILS_ENV:-unset}" "$*" >> "$c/bundle-calls"
    [[ "$APP_FAULT" != build ]] || return 52
    [[ "$PATH" == *"$HOME/.rbenv/shims"* && "${RAILS_ENV:-}" == production ]] || return 54
    [[ "${DISCOURSE_DB_PASSWORD:-}" == 'user db secret' ]] || [[ "$APP_ROLE" == install ]]
  }
  yarn() {
    printf '%s\n' "$*" >> "$c/yarn-calls"
    return 55
  }
  pnpm() {
    printf '%s|%s\n' "$PWD" "$*" >> "$c/pnpm-calls"
    [[ "$APP_FAULT" != build ]] || return 52
  }
  git() {
    [[ "$APP_FAULT" != download ]] || return 22
    if [[ "$1" == clone ]]; then
      mkdir -p /opt/discourse
      command cp -a "$c/payload/." /opt/discourse/
    elif [[ "$1" == pull ]]; then printf 'new code\n' > /opt/discourse/code; fi
  }
  runuser() { printf '%s\n' "$*" >> "$c/runuser-calls"; }
  nginx() {
    printf '%s\n' "$*" >> "$c/nginx-calls"
    [[ "$APP_FAULT" != nginx ]] || return 61
  }
  a2ensite() { :; }
}
runtime_hooks_expected() { [[ "$fault" != download ]] || expected=22; }
baseline_runtime_hooks_setup() {
  mkdir -p "$c/home/.rbenv/shims" "$c/etc/nginx/"{sites-available,sites-enabled} "$c/etc/postgresql/16/main"
  for log in corepack-calls bundle-calls yarn-calls pnpm-calls nginx-calls runuser-calls; do : > "$c/$log"; done
  printf 'local all all peer\n' > "$c/etc/postgresql/16/main/pg_hba.conf"
  if [[ "$role" == update ]]; then
    printf "RAILS_ENV=production\nDISCOURSE_DB_NAME=custom-discourse\nDISCOURSE_DB_PASSWORD='user db secret'\nSECRET_KEY_BASE='USER secret'\nDISCOURSE_HOSTNAME=forum.example.test:9443\n" > "$c/opt/discourse/.env"
    printf 'server {\n listen 9443;\n proxy_set_header X-Accel-Mapping /opt/discourse/public/=/downloads/;\n # USER custom rule\n}\n' > "$c/etc/nginx/sites-available/discourse"
    mkdir -p "$c/opt/discourse/public/uploads"
    printf 'USER forum upload\n' > "$c/opt/discourse/public/uploads/file"
  fi
}
baseline_runtime_hooks_assert() {
  runtime_hooks_configuration_assert
  if [[ "$role" == update ]]; then check "$(cat "$c/opt/discourse/public/uploads/file")" 'USER forum upload' "$app/$variant forum uploads retained"; fi
  if [[ "$rc" == 0 ]]; then
    check "$(grep -c 'discourse discourse-sidekiq' "$c/services" || true)" "$([[ "$role" == update ]] && printf 2 || printf 1)" "$app/$variant both service lifecycle participants"
    check "$(stat -c %s "$c/yarn-calls")" 0 "$app/$variant obsolete package manager never invoked"
    check "$(grep -c X-Accel-Mapping "$c/etc/nginx/sites-available/discourse" || true)" 0 "$app/$variant invalid stylesheet mapping removed"
  fi
}
# Selected-source Ruby and libvips inputs stay app-local.
variants+=(vips)
runtime_hooks_model() {
  baseline_runtime_hooks_model
  setup_ruby() {
    [[ -f /opt/discourse/Gemfile ]] || return 58
    printf '%s\n' "${RUBY_VERSION:-unset}" >> "$c/ruby-calls"
  }
  pkg-config() {
    [[ "$*" == '--modversion vips' && -f "$c/vips-installed" ]] || return 1
    cat "$c/vips-installed"
  }
  meson() { printf '%s\n' "$*" >> "$c/vips-calls"; }
  ninja() {
    printf '%s\n' "$*" >> "$c/vips-calls"
    [[ "$*" != *install ]] || printf '8.18.7\n' > "$c/vips-installed"
  }
  ldconfig() { :; }
  sha256sum() {
    if [[ "$1" == -c ]]; then
      cat >> "$c/vips-sha"
      return 0
    fi
    command sha256sum "$@"
  }
  tar() {
    if [[ "$*" == *vips.tar.xz* ]]; then return 0; fi
    command tar "$@"
  }
  git() {
    [[ "$APP_FAULT" != download ]] || return 22
    if [[ "$1" == clone ]]; then
      mkdir -p /opt/discourse
      command cp -a "$c/payload/." /opt/discourse/
    elif [[ "$1" == pull ]]; then
      printf 'new code\n' > /opt/discourse/code
      command cp "$c/payload/Gemfile" /opt/discourse/Gemfile
      mkdir -p /opt/discourse/script
      command cp "$c/payload/script/discourse_vips_worker" /opt/discourse/script/discourse_vips_worker
    fi
  }
  curl() {
    local out='' url='' format='' body tag=v2.0.0
    while (($#)); do
      case "$1" in -o)
        out="$2"
        shift
        ;;
      -w)
        format="$2"
        shift
        ;;
      https:*) url="$1" ;; esac
      shift
    done
    if [[ "$url" == https://cache.ruby-lang.org/pub/ruby/index.txt ]]; then
      printf 'name\turl\tsha1\n'
      printf 'ruby-3.4.4\tu\ts\nruby-4.0.1\tu\ts\nruby-4.0.9\tu\ts\nruby-4.0.9\tu2\ts\nruby-4.0.10\tu\ts\nruby-4.1.0-preview1\tu\ts\nruby-4.1.2\tu\ts\n'
      return 0
    fi
    [[ "$url" != *'/tags/'* ]] || tag=${url##*/}
    body="{\"tag_name\":\"$tag\",\"assets\":[]}"
    if [[ -n "$out" ]]; then printf '%s' "$body" > "$out"; else printf '%s' "$body"; fi
    [[ -z "$format" ]] || printf 200
  }
}
runtime_hooks_setup() {
  baseline_runtime_hooks_setup
  vips_requirement='8, 18'
  [[ "$variant" != vips ]] || vips_requirement='8, 19'
  for log in ruby-calls vips-calls vips-sha; do : > "$c/$log"; done
  ruby_requirement='~> 4.0.0' ruby_expected=4.0.10
  [[ "$mode" != yes ]] || { ruby_requirement=4.0.1 ruby_expected=4.0.1; }
  printf 'source "https://rubygems.org"\n\nruby "%s"\n' "$ruby_requirement" > "$c/payload/Gemfile"
  mkdir -p "$c/payload/script"
  printf 'raise LoadError, "libvips 8.18 or newer is required" if !Vips.at_least_libvips?(%s)\n' "$vips_requirement" > "$c/payload/script/discourse_vips_worker"
  vips_builds=1
  if [[ "$role" == update && "$mode" == yes ]]; then
    printf '8.18.7\n' > "$c/vips-installed"
    vips_builds=0
  fi
}
runtime_hooks_expected() {
  [[ "$fault" != download ]] || expected=22
  [[ "$variant" != vips ]] || expected=65
  return 0
}
runtime_hooks_retry_needed() { [[ "$role" == update && "$expected" != 0 && "$variant" != vips ]]; }
runtime_hooks_assert() {
  baseline_runtime_hooks_assert
  if [[ "$rc" == 0 ]]; then
    check "$(cat "$c/ruby-calls")" "$ruby_expected" "$app/$variant Ruby derived from deployed Gemfile ($ruby_requirement)"
    check "$(grep -c '^setup ' "$c/vips-calls" || true)" "$vips_builds" "$app/$variant libvips built only when the installed one is older than the source requires"
    check "$(grep -c '^5baaead3b0bb20ffdb9e9ff09aa9fda08620923df77b63b436654cb5e0b3bf94  .*/vips.tar.xz$' "$c/vips-sha" || true)" "$vips_builds" "$app/$variant libvips archive checked against its pinned SHA256"
  fi
}

runtime_hooks_main "$@"
