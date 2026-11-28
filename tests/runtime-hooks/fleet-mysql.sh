#!/usr/bin/env bash
# Actual Fleet hooks and actual generated cold bundles (real _write_bundle, real tools.func
# bytes inlined, no APPLICATION in the receiver) with the real setup_mysql_db and silent
# wrapper. The MySQL engine, package, release, systemd and HTTP boundaries are explicit
# models; the Fleet binary model only records its environment for prepare db.
set -euo pipefail
ROOT=$(realpath "$(dirname "${BASH_SOURCE[0]}")/../..")
if [[ "${1:-}" == --child ]]; then
  c="$CASE_ROOT"
  mount --bind "$c/opt" /opt
  mount --bind "$c/units" /etc/systemd/system
  source "$c/hooks.sh"
  source "$ROOT/misc/bundle.func"
  # shellcheck disable=SC2034
  NSAPP=fleet
  export var_lxc_tmpdir="$c/tmp"
  role=install hook=install_script
  pipeline=(install_script)
  if [[ "$VARIANT" == update || "$VARIANT" == current ]]; then
    role=update hook=update_script
    pipeline=('run_update_script "$@"')
  fi
  _write_bundle "$role" "$hook" "$c/cache" --script-id fleet -- --requirements 2 2048 -- "${pipeline[@]}" > "$c/$role"
  cp "$c/$role" "$c/generated-bundle"
  # A different cold receiver: only the baked context, no creator exports.
  exec env -i PATH="$PATH" ROOT="$ROOT" HOME="$HOME" CASE_ROOT="$c" VARIANT="$VARIANT" LOCAL_IP=10.20.30.40 \
    MYSQL_STATUS="$MYSQL_STATUS" VERBOSE="$VERBOSE" BUILD_LOG="$c/build.log" DEBUG_LOGFILE="$c/errors.log" \
    bash "$c/$role"
fi

: "${TMPDIR:?disk-backed TMPDIR required}"
systemd-detect-virt --vm --quiet || exit 1
case "$(realpath -e "$TMPDIR")" in /tmp | /tmp/*) exit 1 ;; esac
case "$(findmnt -rn -T "$TMPDIR" -o FSTYPE)" in '' | tmpfs | ramfs) exit 1 ;; esac
work=$(mktemp -d "$TMPDIR/fleet-mysql.XXXXXX")
trap 'rm -rf -- "$work"' EXIT
failures=0
check() {
  if [[ "$1" == "$2" ]]; then printf 'PASS %s\n' "$3"; else
    printf 'FAIL %s: expected <%s>, got <%s>\n' "$3" "$2" "$1" >&2
    failures=$((failures + 1))
  fi
}
env_line() { sed -n "s/^$2=//p" "$1"; }
for mode in no yes; do
  for variant in install mysql-fail update current; do
    c="$work/$mode-$variant"
    label="Fleet/$mode/$variant"
    mkdir -p "$c/"{opt,units,cache,home,tmp}
    : > "$c/events"
    : > "$c/messages"
    sed '/^# framework bootstrap/,$d' "$ROOT/scripts/lxc/fleet.sh" > "$c/hooks.sh"
    cat > "$c/models.sh" << 'MODELS'
source "$ROOT/misc/core.func"
load_functions
msg_info() { printf 'info:%s\n' "$*" >> "$CASE_ROOT/messages"; }
msg_ok() { printf 'ok:%s\n' "$*" >> "$CASE_ROOT/messages"; }
msg_error() { printf 'error:%s\n' "$*" >> "$CASE_ROOT/messages"; }
header_info() { :; }
check_container_storage() { :; }
check_container_resources() { :; }
run_update_script() { update_script; }
sleep() { :; }
setup_mysql() { printf 'setup_mysql\n' >> "$CASE_ROOT/events"; }
mysql() {
  printf 'mysql:%s\n' "$*" >> "$CASE_ROOT/events"
  cat > "$CASE_ROOT/mysql-sql"
  return "$MYSQL_STATUS"
}
apt() { printf 'apt:%s\n' "$*" >> "$CASE_ROOT/events"; }
systemctl() { printf 'systemctl:%s\n' "$*" >> "$CASE_ROOT/events"; }
curl() {
  case "$*" in
    *healthz*) return 0 ;;
    *api/v1/setup*) printf '{"token":"model-token"}' ;;
  esac
}
check_for_gh_release() {
  printf 'check_for_gh_release:%s\n' "$*" >> "$CASE_ROOT/events"
  [[ "$VARIANT" != current ]]
}
fetch_and_deploy_gh_release() {
  printf 'fetch:%s\n' "$*" >> "$CASE_ROOT/events"
  cat > /opt/fleet/fleet << 'FLEETBIN'
#!/usr/bin/env bash
printf '%s|%s|%s|%s\n' "$*" "$FLEET_MYSQL_USERNAME" "$FLEET_MYSQL_DATABASE" "$FLEET_MYSQL_PASSWORD" >> "$CASE_ROOT/prepare-db"
FLEETBIN
}
MODELS
    # Real writer and real tools.func bytes; only the framework entry libraries are minimal
    # models that load these effect models after the real core wrapper.
    printf 'load_functions() { source "$CASE_ROOT/models.sh"; }\ncolor() { :; }\n' > "$c/cache/core.func"
    printf 'catch_errors() { :; }\n' > "$c/cache/error_handler.func"
    printf 'setup_lxc() { :; }\n' > "$c/cache/install.func"
    cp "$ROOT/misc/tools.func" "$c/cache/tools.func"
    printf 'clone_and_deploy_gh_commit() { :; }\n' > "$c/cache/github.func"
    cp "$ROOT/misc/ssh-access.func" "$c/cache/"
    mkdir -p "$c/opt/fleet"
    if [[ "$variant" == update || "$variant" == current ]]; then
      cat > "$c/opt/fleet/.env" << 'ENV'
FLEET_MYSQL_ADDRESS=127.0.0.1:3306
FLEET_MYSQL_DATABASE=fleet
FLEET_MYSQL_USERNAME=fleet
FLEET_MYSQL_PASSWORD=existingpass1
FLEET_SERVER_ADDRESS=0.0.0.0:8080
FLEET_SERVER_TLS=false
FLEET_SERVER_PRIVATE_KEY=0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef
FLEET_REDIS_ADDRESS=127.0.0.1:6379
FLEET_LOGGING_JSON=true
FLEET_ADMIN_EMAIL=admin@fleet.local
FLEET_ADMIN_PASSWORD=existingadmin1!
ENV
      printf 'MySQL Credentials\nDatabase: fleet\nUser: fleet\nPassword: existingpass1\n' > "$c/home/fleet.creds"
      printf '#!/bin/sh\n' > "$c/opt/fleet/fleet"
      chmod +x "$c/opt/fleet/fleet"
      sha256sum "$c/opt/fleet/.env" "$c/home/fleet.creds" > "$c/before.sha"
    fi
    status=0
    [[ "$variant" != mysql-fail ]] || status=7
    rc=0
    env -i PATH="$PATH" ROOT="$ROOT" HOME="$c/home" TMPDIR="$c/tmp" CASE_ROOT="$c" VARIANT="$variant" MYSQL_STATUS="$status" VERBOSE="$mode" \
      timeout 60s unshare -mn --propagation private -- bash "$0" --child < /dev/null > "$c/output" 2>&1 || rc=$?
    expected=0
    [[ "$variant" != mysql-fail ]] || expected=7
    check "$rc" "$expected" "$label actual generated cold bundle status"
    [[ "$rc" == "$expected" ]] || tail -n 5 "$c/output"
    check "$(grep -c '^declare -- APPLICATION=' "$c/generated-bundle" || true)" 0 "$label bundle does not bake APPLICATION"
    check "$(grep -c '^declare -- APP=Fleet$' "$c/generated-bundle" || true)" 1 "$label bundle bakes APP"
    case "$variant" in
      install)
        pw=$(sed -n 's/^Password: //p' "$c/home/fleet.creds" 2> /dev/null || true)
        check "$(printf '%s' "$pw" | grep -Ec '^[A-Za-z0-9]{13}$' || true)" 1 "$label generated 13-character password in fleet.creds"
        check "$(cat "$c/home/fleet.creds")" "$(printf 'MySQL Credentials\nDatabase: fleet\nUser: fleet\nPassword: %s' "$pw")" "$label credentials block for APP Fleet"
        check "$(env_line "$c/opt/fleet/.env" FLEET_MYSQL_PASSWORD)" "$pw" "$label .env carries the helper password"
        check "$(cat "$c/prepare-db")" "prepare db --no-prompt|fleet|fleet|$pw" "$label prepare-db process receives the helper password"
        check "$(grep -c "IDENTIFIED BY '$pw';" "$c/mysql-sql" || true)" 1 "$label SQL carries the same password"
        check "$(grep -c "^CREATE USER 'fleet'@'%' IDENTIFIED BY" "$c/mysql-sql" || true)" 1 "$label percent-host account"
        check "$(grep -c '^GRANT ALL ON `fleet`\.\* TO' "$c/mysql-sql" || true)" 1 "$label database-only grant"
        check "$(env_line "$c/opt/fleet/.env" FLEET_MYSQL_ADDRESS)" 127.0.0.1:3306 "$label existing consumer address retained"
        check "$(env_line "$c/opt/fleet/.env" FLEET_SERVER_PRIVATE_KEY | grep -Ec '^[0-9a-f]{64}$' || true)" 1 "$label private key generated"
        check "$(test -f "$c/units/fleet.service" && printf present || printf absent)" present "$label service unit written after migrations"
        check "$(cat "$c/events")" "$(printf 'setup_mysql\nmysql:-u root\napt:install -y redis-server\nfetch:fleet fleetdm/fleet prebuild latest /opt/fleet fleet_v*_linux.tar.gz\nsystemctl:enable -q --now fleet redis-server')" "$label provisioning precedes consumers"
        check "$(test -e "$c/install" && printf present || printf absent)" absent "$label generated installer self-removes"
        ;;
      mysql-fail)
        check "$(cat "$c/events")" "$(printf 'setup_mysql\nmysql:-u root')" "$label failure stops before dependencies, release and service"
        check "$(test -e "$c/opt/fleet/.env" && printf present || printf absent)" absent "$label no .env after failed provisioning"
        check "$(test -e "$c/prepare-db" && printf present || printf absent)" absent "$label prepare-db not reached"
        check "$(test -e "$c/units/fleet.service" && printf present || printf absent)" absent "$label no service unit"
        check "$(test -e "$c/home/fleet.creds" && printf present || printf absent)" absent "$label no credentials for a failed database"
        check "$(grep -c '^ok:Set up MySQL Database' "$c/messages" || true)" 0 "$label no database success message"
        ;;
      update)
        check "$(cat "$c/events")" "$(printf 'check_for_gh_release:fleet fleetdm/fleet\nsystemctl:stop fleet\nfetch:fleet fleetdm/fleet prebuild latest /opt/fleet fleet_v*_linux.tar.gz\nsystemctl:start fleet')" "$label update never provisions the database"
        check "$(sha256sum "$c/opt/fleet/.env" "$c/home/fleet.creds")" "$(cat "$c/before.sha")" "$label .env and credentials unchanged"
        check "$(cat "$c/prepare-db")" 'prepare db --no-prompt|fleet|fleet|existingpass1' "$label migrations use the preserved .env password"
        check "$(test -e "$c/mysql-sql" && printf present || printf absent)" absent "$label no SQL reached the engine"
        check "$(test -f "$c/update" && printf retained || printf missing)" retained "$label generated updater remains installed"
        ;;
      current)
        check "$(cat "$c/events")" 'check_for_gh_release:fleet fleetdm/fleet' "$label current release is a no-op"
        check "$(sha256sum "$c/opt/fleet/.env" "$c/home/fleet.creds")" "$(cat "$c/before.sha")" "$label .env and credentials unchanged"
        check "$(test -e "$c/prepare-db" && printf present || printf absent)" absent "$label no migrations on no-op"
        ;;
    esac
  done
done
printf '%s failure(s); actual Fleet hooks, generated cold bundles and setup_mysql_db; engine/package/release/systemd/HTTP and the Fleet binary are models, no native MySQL or Fleet claim\n' "$failures"
printf 'RUNTIME_HOOKS_RESULT failures=%s\n' "$failures"
[[ "$failures" == 0 ]]
