#!/usr/bin/env bash
# shellcheck disable=SC2034,SC2154
# Callback inputs/outputs are supplied and consumed by the sourced harness.
set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/../lib/runtime-hooks/harness.sh"
app=aliasvault
variants=(fresh update download build copy runtime)
hook_paths=()
runtime_hooks_model() {
  apt() { :; }
  setup_rust() { :; }
  rustup() { :; }
  setup_deb822_repo() { :; }
  setup_postgresql_db() { export PG_DB_NAME PG_DB_USER PG_DB_PASS=fixture-db-secret; }
  nginx() {
    printf '%s\n' "$*" >> "$c/nginx-calls"
    [[ "$APP_FAULT" != nginx ]] || return 61
  }
  setup_nodejs() {
    [[ "$APP_FAULT" != runtime ]] || return 51
    printf '%s\n' "$NODE_VERSION" > "$c/node-version"
  }
  npm() {
    printf '%s|%s\n' "$PWD" "$*" >> "$c/npm-calls"
    [[ "$APP_FAULT" != build ]] || return 52
    if [[ "$PWD" == /opt/aliasvault/apps/web && "$*" == 'run build' ]]; then
      mkdir -p dist
      printf '<html>React source-layout consumer</html>\n' > dist/index.html
      printf '{"ApiUrl":"http://localhost:5100","SupportEmail":""}\n' > dist/appsettings.json
    fi
  }
  dotnet() {
    printf '%s\n' "$*" >> "$c/dotnet-calls"
    [[ "$APP_FAULT" != build ]] || return 52
    [[ "$*" != *AliasVault.Client* ]] || return 56
    case "$*" in *hash-password*) printf 'fixture-hash\n' ;; esac
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
    [[ "$url" != *'/tags/'* ]] || tag=${url##*/}
    body="{\"tag_name\":\"$tag\",\"assets\":[{\"browser_download_url\":\"https://fixture.invalid/wasm-pack-v1-x86_64-unknown-linux-musl.tar.gz\"}]}"
    if [[ -n "$out" ]]; then printf '%s' "$body" > "$out"; else printf '%s' "$body"; fi
    [[ -z "$format" ]] || printf 200
  }
}
runtime_hooks_setup() {
  mkdir -p "$c/home/.cargo" "$c/payload/"{core,apps/server,apps/web,certificates} "$c/etc/nginx/"{sites-available,sites-enabled}
  : > "$c/home/.cargo/env"
  for log in npm-calls dotnet-calls nginx-calls; do : > "$c/$log"; done
  cat > "$c/payload/core/build-and-distribute.sh" << 'SH'
#!/usr/bin/env bash
[[ "$1" == --web ]] || { printf 'Unknown core build target: %s\n' "$1" >&2; exit 64; }
[[ "$APP_FAULT" != build ]] || exit 52
SH
  chmod 0755 "$c/payload/core/build-and-distribute.sh"
  if [[ "$role" == update ]]; then
    mkdir -p "$c/opt/aliasvault/certificates/ssl" "$c/opt/aliasvault/data"
    printf 'USER private key\n' > "$c/opt/aliasvault/certificates/ssl/key.pem"
    printf 'USER database/upload\n' > "$c/opt/aliasvault/data/persisted"
  fi
}
runtime_hooks_assert() {
  runtime_hooks_configuration_assert
  if [[ "$rc" == 0 ]]; then
    check "$(cat "$c/node-version" 2> /dev/null || true)" 24 "$app/$variant selected Node24"
    check "$(cat "$c/opt/aliasvault/client/wwwroot/index.html" 2> /dev/null || true)" '<html>React source-layout consumer</html>' "$app/$variant React build output reaches served root"
  fi
  if [[ "$role" == update ]]; then
    check "$(cat "$c/opt/aliasvault/certificates/ssl/key.pem" 2> /dev/null || true)" 'USER private key' "$app/$variant original certificate key retained"
    check "$(cat "$c/opt/aliasvault/data/persisted" 2> /dev/null || true)" 'USER database/upload' "$app/$variant internal persistent data retained"
  fi
}
runtime_hooks_retry_assert() {
  check "$(cat "$c/opt/aliasvault/certificates/ssl/key.pem" 2> /dev/null || true)" 'USER private key' "$app/$variant retry retains original private key"
  check "$(cat "$c/opt/aliasvault/data/persisted" 2> /dev/null || true)" 'USER database/upload' "$app/$variant retry retains persisted app data"
}
runtime_hooks_main "$@"
