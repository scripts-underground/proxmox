#!/usr/bin/env bash
# shellcheck disable=SC2034,SC2154
# Callback state is supplied by the shared cold-hook harness.
set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/../lib/runtime-hooks/harness.sh"
app=booklore
script_type=lxc
variants=(fresh update selected current current-missing pending legacy checker missing-config missing-install download build backend missing-jar jar-copy runtime)
hook_paths=()
runtime_hooks_model() {
  setup_java() { :; }
  setup_nodejs() {
    [[ "${NODE_MAX_OLD_SPACE_SIZE:-}" == 1536 ]] || return 54
    printf '%s\n' "$NODE_MAX_OLD_SPACE_SIZE" > "$c/node-heap"
  }
  setup_mariadb() { :; }
  setup_yq() { :; }
  setup_mariadb_db() { export MARIADB_DB_NAME MARIADB_DB_USER MARIADB_DB_PASS=fixture-secret; }
  cp() {
    if [[ "$APP_FAULT" == jar-copy && "${!#}" == /opt/booklore/dist/* ]]; then
      printf 'partial backend\n' > "${!#}"
      return 41
    fi
    command cp "$@"
  }
  get_latest_github_release() { printf 'v9.9.9\n'; }
  yq() {
    printf '%s\n' "$*" >> "$c/versions"
    printf '%s\n' "$1" > src/main/resources/build-version
  }
  npm() {
    printf '%s\n' "$*" >> "$c/builds"
    [[ "$APP_FAULT" != build ]] || return 52
    if [[ "$1" == run ]]; then
      [[ "${NG_BUILD_MAX_WORKERS:-}" == 1 && "${NG_BUILD_PARALLEL_TS:-}" == 0 ]] || return 54
      [[ "$*" == 'run build -- --configuration=production' ]] || return 55
      mkdir -p dist/booklore/browser
      printf 'new frontend\n' > dist/booklore/browser/index.html
    fi
  }
  systemctl() {
    printf '%s\n' "$*" >> "$c/services"
    case "$*" in
      'is-active --quiet nginx') return 0 ;;
      'start booklore') [[ "$APP_FAULT" != runtime ]] || return 51 ;;
    esac
  }
  curl() {
    [[ "$APP_FAULT" != checker ]] || return 28
    local out='' format='' url='' tag=v2.0.0
    [[ "$(cat "$c/variant")" != selected ]] || tag=v1.9.0
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
        https:*) url=$1 ;;
      esac
      shift
    done
    [[ "$url" != *'/tags/'* ]] || tag=${url##*/}
    local body="{\"tag_name\":\"$tag\",\"assets\":[]}"
    if [[ -n "$out" ]]; then printf '%s' "$body" > "$out"; else printf '%s' "$body"; fi
    [[ -z "$format" ]] || printf 200
  }
}
runtime_hooks_variant() {
  case "$variant" in checker | missing-config | missing-install | backend | missing-jar | jar-copy) fault=$variant ;; esac
}
runtime_hooks_expected() {
  case "$fault" in
    checker) expected=28 ;;
    missing-config | missing-install | missing-jar) expected=1 ;;
    backend) expected=53 ;;
    jar-copy) expected=41 ;;
  esac
}
runtime_hooks_setup() {
  printf '%s\n' "$variant" > "$c/variant"
  for log in builds versions; do : > "$c/$log"; done
  mkdir -p "$c/payload/booklore-api/src/main/resources" "$c/payload/booklore-ui" "$c/opt/booklore_storage/"{data,books,bookdrop}
  printf 'app:\n  version: development\n' > "$c/payload/booklore-api/src/main/resources/application.yaml"
  cat > "$c/payload/booklore-api/gradlew" << 'SH'
#!/usr/bin/env bash
set -euo pipefail
[[ "$APP_FAULT" != backend ]] || exit 53
[[ -f src/main/resources/static/index.html ]]
mkdir -p build/libs
[[ "$APP_FAULT" != missing-jar ]] || exit 0
printf 'new backend\n' > build/libs/booklore-api-0.0.1-SNAPSHOT.jar
SH
  chmod 0755 "$c/payload/booklore-api/gradlew"
  if [[ "$role" == update ]]; then
    mkdir -p "$c/opt/booklore/dist"
    stat -c %i "$c/opt/booklore" > "$c/root-inode"
    printf 'old backend\n' > "$c/opt/booklore/dist/app.jar"
    printf 'DATABASE_PASSWORD=USER-original-secret\nAPP_PATH_CONFIG=/opt/booklore_storage/data\nAPP_BOOKDROP_FOLDER=/opt/booklore_storage/bookdrop\nBOOKLORE_PORT=8181\n' > "$c/opt/booklore_storage/.env"
    chmod 0644 "$c/opt/booklore_storage/.env"
    stat -c %i "$c/opt/booklore_storage/.env" > "$c/env-inode"
    sha256sum "$c/opt/booklore_storage/.env" | cut -d' ' -f1 > "$c/env-before"
    printf 'USER book\n' > "$c/opt/booklore_storage/books/book.epub"
    printf '[Service]\nExecStart=/usr/bin/java -Xmx1G -jar /opt/booklore/dist/app.jar\n' > "$c/etc/systemd/system/booklore.service"
    cp "$c/etc/systemd/system/booklore.service" "$c/unit-before"
    case "$variant" in
      current) printf '2.0.0\n' > "$c/home/.booklore" ;;
      current-missing)
        printf '2.0.0\n' > "$c/home/.booklore"
        rm "$c/opt/booklore/dist/app.jar"
        ;;
      pending)
        printf '2.0.0\n' > "$c/home/.booklore"
        printf 'original pending\n' > "$c/state/booklore"
        ;;
      legacy)
        printf 'DATABASE_PASSWORD=USER-original-secret\nBOOKLORE_DATA_PATH="/opt/booklore_storage/data with spaces"\nBOOKLORE_BOOKDROP_PATH=/opt/booklore_storage/bookdrop\nBOOKLORE_PORT=8181\n' > "$c/opt/booklore_storage/.env"
        ;;
      missing-config) rm "$c/opt/booklore_storage/.env" ;;
      missing-install) mv "$c/opt/booklore" "$c/opt/absent-booklore" ;;
    esac
  fi
}
runtime_hooks_configuration() {
  if [[ "$variant" == legacy ]]; then
    check "$(grep '^APP_PATH_CONFIG=' "$c/opt/booklore_storage/.env" || true)" 'APP_PATH_CONFIG="/opt/booklore_storage/data with spaces"' "$app/$variant legacy path quoting retained"
    check "$(grep '^APP_BOOKDROP_FOLDER=' "$c/opt/booklore_storage/.env" || true)" 'APP_BOOKDROP_FOLDER=/opt/booklore_storage/bookdrop' "$app/$variant legacy bookdrop alias retained"
    check "$(grep '^BOOKLORE_PORT=' "$c/opt/booklore_storage/.env")" BOOKLORE_PORT=8181 "$app/$variant configured port retained"
  else
    check "$(sha256sum "$c/opt/booklore_storage/.env" | cut -d' ' -f1)" "$(cat "$c/env-before")" "$app/$variant existing environment bytes retained"
  fi
  check "$(stat -c %i "$c/opt/booklore_storage/.env")" "$(cat "$c/env-inode")" "$app/$variant existing environment inode retained"
  check "$(stat -c %a "$c/opt/booklore_storage/.env")" 600 "$app/$variant existing secrets private"
  check "$(cat "$c/opt/booklore_storage/books/book.epub")" 'USER book' "$app/$variant existing book bytes retained"
}
runtime_hooks_assert() {
  if [[ "$role" == update && "$variant" != missing-config && "$variant" != missing-install ]]; then runtime_hooks_configuration; fi
  if [[ "$role" == update && "$variant" != missing-install ]]; then
    check "$(stat -c %i "$c/opt/booklore")" "$(cat "$c/root-inode")" "$app/$variant live application root stays in place"
    check "$(cmp -s "$c/unit-before" "$c/etc/systemd/system/booklore.service" && printf same || printf changed)" same "$app/$variant custom service options retained"
  fi
  case "$fault" in
    download | build | backend | missing-jar | jar-copy)
      check "$(cat "$c/opt/booklore/dist/app.jar")" 'old backend' "$app/$variant failed build retains the previous runtime"
      ;;
  esac
  if [[ "$variant" == checker || "$variant" == current || "$variant" == missing-config || "$variant" == missing-install ]]; then
    check "$(stat -c %s "$c/services")" 0 "$app/$variant no service effects"
    check "$(stat -c %s "$c/builds")" 0 "$app/$variant no build effects"
  fi
  if [[ "$rc" == 0 && "$variant" != current ]]; then
    local version=v2.0.0
    [[ "$variant" != selected ]] || version=v1.9.0
    check "$(grep -c "$version" "$c/versions" || true)" 1 "$app/$variant build labels the selected source"
    check "$(cat "$c/opt/booklore/dist/app.jar")" 'new backend' "$app/$variant completed backend reaches runtime path"
    check "$(cat "$c/opt/booklore/booklore-api/src/main/resources/static/index.html")" 'new frontend' "$app/$variant frontend embedded"
    check "$(grep -Ec 'nginx|apt-get' "$c/services" || true)" 0 "$app/$variant unrelated proxy untouched"
  fi
  if [[ "$role" == install && "$rc" == 0 ]]; then
    check "$(stat -c %a "$c/opt/booklore_storage/.env")" 600 "$app/$variant fresh secrets private"
  fi
}
runtime_hooks_failure_services_assert() {
  local count=0
  [[ "$fault" != runtime ]] || count=1
  check "$(grep -Ec '^(start|restart)|--now' "$c/services" || true)" "$count" "$app/$variant failure never starts an incomplete build"
}
runtime_hooks_retry_needed() {
  [[ "$role" == update && "$expected" != 0 && "$fault" != missing-config && "$fault" != missing-install ]]
}
runtime_hooks_retry_assert() {
  runtime_hooks_configuration
  check "$(cat "$c/opt/booklore/dist/app.jar")" 'new backend' "$app/$variant pending retry repairs backend"
}
runtime_hooks_main "$@"
