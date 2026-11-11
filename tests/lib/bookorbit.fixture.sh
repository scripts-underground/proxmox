#!/usr/bin/env bash
# Actual cold bundles, checked replacement, Node parsing and files; compilation,
# PostgreSQL, systemd properties/control and package provisioning are modeled.
set -euo pipefail
ROOT=$(realpath "$(dirname "${BASH_SOURCE[0]}")/../..")
if [[ "${1:-}" == --child ]]; then
  c="$CASE_ROOT"
  mount --bind "$c/opt" /opt
  mount --bind "$c/srv" /srv
  mount --bind "$c/units" /etc/systemd/system
  mount --bind "$c/local" /usr/local
  mount --bind "$c/cache" /var/cache
  mount --bind /var/lib/scripts-underground "$c/state/scripts-underground"
  mount --rbind "$c/state" /var/lib
  mount --bind "$c/pending" /var/lib/scripts-underground/update-pending
  mount --bind "$c/locks" /var/lib/scripts-underground/maintenance-locks
  mount --bind "$c/bin/systemctl" /usr/bin/systemctl
  source "$ROOT/misc/bundle.func"
  source "$c/hooks.sh"
  : "${var_cpu:?source-selected CPU required}" "${var_ram:?source-selected RAM required}"
  export REPO_BASE=https://fixture.invalid
  export var_lxc_tmpdir="$TMPDIR"
  requirement_prefix=''
  if [[ "$ROLE" == install ]]; then
    printf -v requirement_prefix 'declare -- LXC_REQUIRED_CPU=%q\ndeclare -- LXC_REQUIRED_RAM=%q\n' "$var_cpu" "$var_ram"
  fi
  _write_bundle "$ROLE" "${ROLE}_script" "$ROOT/misc" --script-id bookorbit -- --requirements "$var_cpu" "$var_ram" -- \
    "${requirement_prefix}source \"\$CASE_ROOT/models.sh\"" "$(if [[ "$ROLE" == install ]]; then printf install_script; else printf run_update_script; fi)" > "$c/bundle"
  [[ $(grep -xc "declare -- LXC_REQUIRED_CPU=$var_cpu" "$c/bundle") == 1 ]]
  [[ $(grep -xc "declare -- LXC_REQUIRED_RAM=$var_ram" "$c/bundle") == 1 ]]
  printf '%s:%s\n' "$var_cpu" "$var_ram" > "$c/bundle-requirements"
  exec bash "$c/bundle"
fi
: "${TMPDIR:?disk-backed scratch required}" "${RUNTIME_NODE:?}" "${RUNTIME_EXTRA_REFERENCES:?}"
systemd-detect-virt --vm --quiet || exit 1
case "$(findmnt -rn -T "$TMPDIR" -o FSTYPE)" in '' | tmpfs | ramfs) exit 1 ;; esac
work=$(mktemp -d "$TMPDIR/bookorbit-fixture.XXXXXX")
trap 'rm -rf -- "$work"' EXIT
# Compare actual V8 configuration with this exact Node binary's explicit flag,
# not an assumed heap-size-limit overhead or a string-only budget assertion.
NODE_OPTIONS='' "$RUNTIME_NODE" --max-old-space-size=2048 -p 'require("node:v8").getHeapStatistics().heap_size_limit' > "$work/build-heap-limit"
failures=0
check() {
  if [[ "$1" == "$2" ]]; then printf 'PASS BookOrbit %s\n' "$3"; else
    printf 'FAIL BookOrbit %s expected <%s>, got <%s>\n' "$3" "$2" "$1" >&2
    failures=$((failures + 1))
  fi
}
for verbose in no yes; do
  for variant in fresh fresh-caller update update-caller build download copy invalid missing db missing-table overlap alias override stopped whitespace inherited quoted relative external trailing env-symlink env-hardlink env-directory late-db changed-set root-logical root-physical root-alias root-code-alias root-caller-code root-remap url-encoded url-ipv6 url-duplicate url-unknown url-override url-escape url-readwrite url-tls url-missing url-reserved; do
    c="$work/$verbose-$variant"
    mkdir -p "$c/"{opt,srv,units,local,cache,state/scripts-underground,pending,locks,home,bin,external,payload/server/src/db/migrations/meta,payload/server/bin/kepubify,payload/server/requirements,payload/client/dist}
    chmod 0700 "$c/locks" "$c/pending"
    mkdir -p "$c/local/bin"
    for n in effects services pnpm packages db build-node caller-node; do : > "$c/$n"; done
    cp "$work/build-heap-limit" "$c/build-heap-limit"
    caller_env=()
    case "$variant" in *-caller) caller_env=('NODE_OPTIONS=--max-old-space-size=384 --stack-trace-limit=17') ;; esac
    cp "$RUNTIME_EXTRA_REFERENCES/bookorbit/package.json" "$c/payload/package.json"
    cp "$RUNTIME_EXTRA_REFERENCES/bookorbit/pnpm-workspace.yaml" "$c/payload/pnpm-workspace.yaml"
    cp "$RUNTIME_EXTRA_REFERENCES/bookorbit/server/requirements/kobo-cloudscraper.txt" "$c/payload/server/requirements/kobo-cloudscraper.txt"
    printf 'locked\n' > "$c/payload/pnpm-lock.yaml"
    printf 'new client bytes\n' > "$c/payload/client/dist/index.html"
    printf 'migration\n' > "$c/payload/server/src/db/migrations/0000.sql"
    printf '{}\n' > "$c/payload/server/src/db/migrations/meta/_journal.json"
    printf 'binary fixture\n' > "$c/payload/server/bin/kepubify/linux-x64"
    printf 'incoming source default\n' > "$c/payload/.env"
    role=update
    case "$variant" in fresh*) role=install ;; esac
    mkdir -p "$c/opt/bookorbit/custom data" "$c/opt/bookorbit/custom library" "$c/opt/bookorbit/caller keep" "$c/opt/bookorbit/legacy" "$c/opt/bookorbit/server/public"
    printf 'USER code\n' > "$c/opt/bookorbit/code"
    printf 'USER persistent bytes\n' > "$c/opt/bookorbit/custom data/row"
    printf 'USER book bytes\n' > "$c/opt/bookorbit/custom library/book.epub"
    chmod 0640 "$c/opt/bookorbit/custom library/book.epub" "$c/opt/bookorbit/custom data/row"
    printf 'USER caller\n' > "$c/opt/bookorbit/caller keep/row"
    printf 'USER legacy\n' > "$c/opt/bookorbit/legacy/row"
    printf 'USER outside\n' > "$c/external/row"
    printf 'old client\n' > "$c/opt/bookorbit/server/public/index.html"
    cp "$c/payload/package.json" "$c/opt/bookorbit/package.json"
    printf '{}\n' > "$c/opt/bookorbit/server/package.json"
    cat > "$c/opt/bookorbit/.env" << 'ENV'
NODE_ENV=production
PORT=4555
APP_URL=http://example.test:4555
CLIENT_URL=http://example.test:4555
DATABASE_URL=postgres://fixture:fixture@localhost/bookorbit
JWT_SECRET=retained-jwt
SETUP_BOOTSTRAP_TOKEN=retained-setup
EMAIL_ENCRYPTION_KEY=retained-email
MIGRATION_ENCRYPTION_KEY=retained-migration
BOOK_REQUEST_ENCRYPTION_KEY=retained-request
NODE_OPTIONS=--max-old-space-size=896
APP_DATA_PATH=/opt/bookorbit/custom data
BOOK_DOCK_PATH=/opt/bookorbit/custom data/dock
MIGRATION_IMPORT_ROOT=/opt/bookorbit/custom data/import
APP_VERSION=vold
ENV
    chmod 0600 "$c/opt/bookorbit/.env"
    printf '%s\n' "$variant" > "$c/variant"
    cat > "$c/local/bin/psql" << SH
#!/usr/bin/env bash
[[ "\$PGDATABASE" == bookorbit && "\$PGUSER" == fixture && "\$PGPASSWORD" == fixture && "\$PGHOST" == localhost && "\$PGPORT" == 5432 ]] || {
  case "\$(cat '$c/variant')" in
    url-encoded) [[ "\$PGDATABASE" == 'book orbit' && "\$PGUSER" == 'fixture user' && "\$PGPASSWORD" == 'fixture:p%@' && "\$PGHOST" == localhost && "\$PGPORT" == 5544 && "\$PGAPPNAME" == 'fixture proof' && "\$PGOPTIONS" == *'statement_timeout=9000'* ]] || exit 67 ;;
    url-ipv6) [[ "\$PGDATABASE" == bookorbit && "\$PGUSER" == fixture && "\$PGPASSWORD" == fixture && "\$PGHOST" == ::1 && "\$PGPORT" == 5432 ]] || exit 67 ;;
    *) exit 67 ;;
  esac
}
[[ "\$PGOPTIONS" == *default_transaction_read_only=on* ]] || exit 68
[[ "\$PGSSLMODE" == disable && "\$PGCONNECT_TIMEOUT" == 5 && "\$PGPASSFILE" == /dev/null ]] || exit 68
[[ "\$(cat '$c/variant')" != db && "\$(cat '$c/variant')" != missing-table ]] || exit 1
if [[ "\$(cat '$c/variant')" == late-db && -s '$c/db' ]]; then exit 1; fi
printf 'query\n' >> '$c/db'
case "\$(cat '$c/variant')" in
  changed-set)
    if [[ \$(wc -l < '$c/db') == 2 ]]; then printf '["/opt/bookorbit/other library"]\n'; else printf '["/opt/bookorbit/custom library"]\n'; fi ;;
  root-physical) printf '["/srv/bookorbit/custom library","/srv/bookorbit/escape"]\n' ;;
  root-alias) printf '["/srv/bookorbit/library alias","/srv/bookorbit/escape"]\n' ;;
  root-code-alias) printf '["/srv/bookorbit/code alias/future"]\n' ;;
  *) printf '["/opt/bookorbit/custom library"]\n' ;;
esac
SH
    chmod 0755 "$c/local/bin/psql"
    case "$variant" in
      invalid) printf 'APP_DATA_PATH="unterminated\n' >> "$c/opt/bookorbit/.env" ;;
      missing) rm "$c/opt/bookorbit/.env" ;;
      env-symlink)
        mv "$c/opt/bookorbit/.env" "$c/external/environment"
        ln -s "$c/external/environment" "$c/opt/bookorbit/.env"
        ;;
      env-hardlink) ln "$c/opt/bookorbit/.env" "$c/external/environment" ;;
      env-directory)
        mv "$c/opt/bookorbit/.env" "$c/external/environment"
        mkdir "$c/opt/bookorbit/.env"
        ;;
      overlap) printf 'APP_DATA_PATH=/opt/bookorbit/server/public/user\n' >> "$c/opt/bookorbit/.env" ;;
      alias)
        ln -s server/public "$c/opt/bookorbit/alias"
        printf 'APP_DATA_PATH=/opt/bookorbit/alias/future\n' >> "$c/opt/bookorbit/.env"
        ;;
      quoted) sed -i 's|^APP_DATA_PATH=.*|APP_DATA_PATH="/opt/bookorbit/custom data"|' "$c/opt/bookorbit/.env" ;;
      relative) sed -i 's|^APP_DATA_PATH=.*|APP_DATA_PATH=../custom data|' "$c/opt/bookorbit/.env" ;;
      external) printf 'BOOK_DOCK_PATH=%s\n' "$c/external" >> "$c/opt/bookorbit/.env" ;;
      trailing)
        mkdir "$c/opt/bookorbit/custom import "
        printf 'USER imports\n' > "$c/opt/bookorbit/custom import /row"
        printf 'MIGRATION_IMPORT_ROOT="../custom import "\n' >> "$c/opt/bookorbit/.env"
        ;;
      url-encoded) sed -i 's|^DATABASE_URL=.*|DATABASE_URL=postgresql://fixture%20user:fixture%3Ap%25%40@localhost:5544/book%20orbit?application_name=fixture%20proof\&statement_timeout=9000\&client_encoding=UTF8\&sslmode=disable|' "$c/opt/bookorbit/.env" ;;
      url-ipv6) sed -i 's|^DATABASE_URL=.*|DATABASE_URL=postgres://fixture:fixture@[::1]/bookorbit|' "$c/opt/bookorbit/.env" ;;
      url-duplicate) sed -i 's|^DATABASE_URL=.*|DATABASE_URL=postgres://fixture:fixture@localhost/bookorbit?application_name=first\&application_name=second|' "$c/opt/bookorbit/.env" ;;
      url-unknown) sed -i 's|^DATABASE_URL=.*|DATABASE_URL=postgres://fixture:fixture@localhost/bookorbit?unknown=value|' "$c/opt/bookorbit/.env" ;;
      url-override) sed -i 's|^DATABASE_URL=.*|DATABASE_URL=postgres://fixture:fixture@localhost/bookorbit?user=root|' "$c/opt/bookorbit/.env" ;;
      url-escape) sed -i 's|^DATABASE_URL=.*|DATABASE_URL=postgres://fixture:bad%Q0@localhost/bookorbit|' "$c/opt/bookorbit/.env" ;;
      url-readwrite) sed -i 's|^DATABASE_URL=.*|DATABASE_URL=postgres://fixture:fixture@localhost/bookorbit?options=-c%20default_transaction_read_only%3Doff|' "$c/opt/bookorbit/.env" ;;
      url-tls) sed -i 's|^DATABASE_URL=.*|DATABASE_URL=postgres://fixture:fixture@localhost/bookorbit?sslmode=require|' "$c/opt/bookorbit/.env" ;;
      url-missing) sed -i 's|^DATABASE_URL=.*|DATABASE_URL=postgres://localhost/bookorbit|' "$c/opt/bookorbit/.env" ;;
      url-reserved) sed -i 's|^DATABASE_URL=.*|DATABASE_URL=postgres://fixture:fixture@localhost/book%2Forbit|' "$c/opt/bookorbit/.env" ;;
    esac
    case "$variant" in
      root-*)
        mv "$c/opt/bookorbit" "$c/srv/bookorbit"
        ln -s ../srv/bookorbit "$c/opt/bookorbit"
        ln -s 'custom library' "$c/opt/bookorbit/library alias"
        ln -s server/public "$c/opt/bookorbit/code alias"
        ln -s "$c/external" "$c/opt/bookorbit/escape"
        ;;
    esac
    printf '[Service]\nEnvironmentFile=/opt/bookorbit/.env\n' > "$c/units/bookorbit.service"
    env_before=missing
    [[ ! -f "$c/opt/bookorbit/.env" ]] || env_before=$(sed '/^APP_VERSION=/d' "$c/opt/bookorbit/.env" | sha256sum | cut -d' ' -f1)
    env_metadata=$(stat -c '%i:%a:%u:%g:%h:%F' "$c/opt/bookorbit/.env" 2> /dev/null || true)
    env_access=$(stat -c '%a:%u:%g' "$c/opt/bookorbit/.env" 2> /dev/null || true)
    target_metadata=$(stat -c '%i:%a:%u:%g:%h:%F' "$c/external/environment" 2> /dev/null || true)
    target_bytes=$(sha256sum "$c/external/environment" 2> /dev/null | cut -d' ' -f1 || true)
    env_link=$(readlink "$c/opt/bookorbit/.env" || true)
    data_before=$(stat -c '%d:%i:%a:%u:%g' "$c/opt/bookorbit/custom data/row")
    library_before=$(stat -c '%d:%i:%a:%u:%g' "$c/opt/bookorbit/custom library/book.epub")
    unit_before=$(sha256sum "$c/units/bookorbit.service" | cut -d' ' -f1)
    cat > "$c/bin/systemctl" << 'SH'
#!/usr/bin/env bash
if [[ "$1" == show ]]; then
  cat <<'PROPERTIES'
LoadState=loaded
WorkingDirectory=/opt/bookorbit/server
RootDirectory=
RootImage=
EnvironmentFiles=/opt/bookorbit/.env (ignore_errors=no)
Environment=
PassEnvironment=
UnsetEnvironment=
ExecStart={ path=/usr/bin/node ; argv[]=/usr/bin/node /opt/bookorbit/server/dist/main.js ; ignore_errors=no ; }
PROPERTIES
  [[ "$VARIANT" != override ]] || printf 'RootDirectory=/foreign\n'
elif [[ "$1" == show-environment ]]; then printf 'LANG=C.UTF-8\n'; else
  printf '%s\n' "$*" >> "$CASE_ROOT/services"
  if [[ "$*" == 'stop bookorbit' && "$VARIANT" == root-remap ]]; then
    mv /srv/bookorbit /srv/remapped
    ln -sfn ../srv/remapped /opt/bookorbit
  fi
fi
SH
    chmod 0755 "$c/bin/systemctl"
    cat > "$c/build-observe.cjs" << 'JS'
// Native process/environment consumers; pnpm lifecycle and compilation producers
// remain models. Children receive no replacement env or heap CLI option.
const fs = require('node:fs');
const assert = require('node:assert/strict');
const v8 = require('node:v8');
const {spawnSync} = require('node:child_process');
const [target, phase] = process.argv.slice(2);
const heap = v8.getHeapStatistics().heap_size_limit;
assert.equal(process.versions.node.split('.')[0], '24');
assert.equal(process.env.NODE_OPTIONS, '--max-old-space-size=2048');
assert.equal(heap, Number(fs.readFileSync(process.env.CASE_ROOT + '/build-heap-limit', 'utf8')));
fs.appendFileSync(process.env.CASE_ROOT + '/build-node', JSON.stringify({
  target, phase, options: process.env.NODE_OPTIONS, heap_size_limit: heap,
}) + '\n');
if (phase === 'launcher') {
  const phases = target === 'server'
    ? ['prebuild-types', 'prebuild-plugin-api', 'prebuild-swagger', 'build']
    : ['build-only'];
  for (const childPhase of phases) {
    const child = spawnSync('/bin/bash', ['-c', 'exec "$RUNTIME_NODE" "$CASE_ROOT/build-observe.cjs" "$1" "$2"', '--', target, childPhase], {stdio: 'inherit'});
    assert.ifError(child.error);
    assert.equal(child.signal, null);
    assert.equal(child.status, 0);
  }
}
JS
    cat > "$c/models.sh" << 'MODELS'
# Snapshot the bundle caller before either hook changes anything. The real
# silent wrapper remains untouched in both modes, including its return status.
caller_node_declaration=$(declare -p NODE_OPTIONS 2> /dev/null || true)
fixture_caller_unchanged() {
  [[ "$(declare -p NODE_OPTIONS 2> /dev/null || true)" == "$caller_node_declaration" ]] || return 71
}
fixture_caller_node() {
  fixture_caller_unchanged || return $?
  "$RUNTIME_NODE" - "$1" "${NODE_OPTIONS+x}" "${NODE_OPTIONS-}" << 'JS'
const fs = require('node:fs');
const assert = require('node:assert/strict');
const [phase, present, value] = process.argv.slice(2);
assert.equal(Object.hasOwn(process.env, 'NODE_OPTIONS'), present === 'x');
assert.equal(process.env.NODE_OPTIONS ?? '', value);
fs.appendFileSync(process.env.CASE_ROOT + '/caller-node', JSON.stringify({
  phase, present, value, heap_size_limit: require('node:v8').getHeapStatistics().heap_size_limit,
}) + '\n');
JS
}
header_info() { :; }
check_container_storage() { :; }
check_container_resources() { :; }
cleanup_lxc() { :; }
setup_nodejs() { printf runtime >> "$CASE_ROOT/effects"; }
setup_postgresql() { printf database >> "$CASE_ROOT/effects"; }
setup_postgresql_db() { export PG_DB_NAME=bookorbit PG_DB_USER=fixture PG_DB_PASS=fixture; }
setup_uv() { :; }
node() { "$RUNTIME_NODE" "$@"; }
apt() { printf '%s\n' "$*" >> "$CASE_ROOT/packages"; printf apt >> "$CASE_ROOT/effects"; }
corepack() { printf '%s\n' "$*" >> "$CASE_ROOT/pnpm"; }
pnpm() {
  printf '%s\n' "$*" >> "$CASE_ROOT/pnpm"
  case "$*" in
    'install --frozen-lockfile --filter client... --filter server...') fixture_caller_node dependency-install || return $? ;;
    '--config.verify-deps-before-run=false --filter client run build-only') "$RUNTIME_NODE" "$CASE_ROOT/build-observe.cjs" client launcher || return $? ;;
    '--config.verify-deps-before-run=false --filter server run build') "$RUNTIME_NODE" "$CASE_ROOT/build-observe.cjs" server launcher || return $? ;;
  esac
  [[ "$VARIANT" != build ]] || return 52
  mkdir -p /opt/bookorbit/client/dist /opt/bookorbit/server/dist
  printf 'new client bytes\n' > /opt/bookorbit/client/dist/index.html
}
uv() {
  fixture_caller_node after-build || return $?
  if [[ "$1" == venv ]]; then mkdir -p "${!#}/bin"; touch "${!#}/bin/python"; fi
}
cp() {
  fixture_caller_unchanged || return $?
  if [[ "$VARIANT" == copy && "$*" == *'/deploy-source.'* ]]; then return 41; fi
  command cp "$@"
}
curl() {
  local out='' format=''
  while (($#)); do case "$1" in -o) out="$2"; shift ;; -w) format="$2"; shift ;; esac; shift; done
  printf '{"tag_name":"v3.7.0","assets":[]}' > "$out"
  [[ -z "$format" ]] || printf 200
}
curl_download() {
  printf download >> "$CASE_ROOT/effects"
  [[ "$VARIANT" != download ]] || return 22
  tar -czf "$1" -C "$CASE_ROOT" payload
}
# shellcheck disable=SC2034
CLEAN_INSTALL_KEEP_PATHS=('caller keep')
CLEAN_INSTALL_KEEP=legacy
if [[ "$VARIANT" == root-caller-code ]]; then CLEAN_INSTALL_KEEP_PATHS+=('code alias/future'); fi
MODELS
    if [[ "$role" == install ]]; then rm -rf "$c/opt/bookorbit"; fi
    # Extract only actual cold hook definitions; framework bootstrap is not run.
    bash -c 'unset var_cpu var_ram var_disk; curl() { :; }; source "$1"; declare -p var_cpu var_ram var_disk; declare -f install_script update_script' hook-source "$ROOT/scripts/lxc/bookorbit.sh" > "$c/hooks.sh"
    rc=0
    env -i "${caller_env[@]}" PATH="$c/bin:$PATH" CASE_ROOT="$c" HOME="$c/home" TMPDIR="$TMPDIR" RUNTIME_NODE="$RUNTIME_NODE" VARIANT="$variant" ROLE="$role" VERBOSE="$verbose" APP=BookOrbit NSAPP=bookorbit LOCAL_IP=10.20.30.40 BUILD_LOG="$c/build.log" DEBUG_LOGFILE="$c/errors.log" \
      timeout 50s unshare -m --propagation private -- bash "$0" --child > "$c/output" 2>&1 || rc=$?
    expected=0
    case "$variant" in build) expected=52 ;; download) expected=250 ;; copy) expected=252 ;; invalid | missing | db | missing-table | overlap | alias | override | env-symlink | env-hardlink | env-directory | late-db | changed-set | root-code-alias | root-caller-code | root-remap | url-duplicate | url-unknown | url-override | url-escape | url-readwrite | url-tls | url-missing | url-reserved) expected=65 ;; esac
    check "$rc" "$expected" "$verbose/$variant actual generated cold-hook status"
    check "$(cat "$c/bundle-requirements")" '2:4096' "$verbose/$variant actual source-selected cold bundle CPU/RAM"
    if [[ "$rc" != "$expected" ]]; then tail -n 5 "$c/output"; fi
    if [[ "$role" == install && "$rc" == 0 ]]; then
      check "$(grep -c '^PORT=80$' "$c/opt/bookorbit/.env" || true)" 1 'fresh HTTP80 config'
      check "$(stat -c %a "$c/opt/bookorbit/.env")" 600 'fresh environment private'
      check "$(stat -c %a "$c/home/bookorbit.creds")" 600 'fresh setup token private'
      check "$(grep -Ec '^(EMAIL|MIGRATION|BOOK_REQUEST)_ENCRYPTION_KEY=[a-f0-9]{64}$' "$c/opt/bookorbit/.env" || true)" 3 'fresh independent encryption keys'
      check "$(grep -c '^NODE_OPTIONS=--max-old-space-size=2048$' "$c/opt/bookorbit/.env" || true)" 1 'fresh runtime options unchanged by build budget'
    elif [[ "$role" == update ]]; then
      after=missing
      [[ ! -f "$c/opt/bookorbit/.env" ]] || after=$(sed '/^APP_VERSION=/d' "$c/opt/bookorbit/.env" | sha256sum | cut -d' ' -f1)
      check "$after" "$env_before" "$variant existing keys/port/config byte-preserved"
      check "$(stat -c '%a:%u:%g' "$c/opt/bookorbit/.env" 2> /dev/null || true)" "$env_access" "$variant config access metadata preserved"
      check "$(stat -c '%d:%i:%a:%u:%g' "$c/opt/bookorbit/custom data/row" 2> /dev/null || true)" "$data_before" "$variant data inode/metadata survived"
      check "$(cat "$c/opt/bookorbit/custom data/row" 2> /dev/null || true)" 'USER persistent bytes' "$variant actual data bytes survived"
      check "$(stat -c '%d:%i:%a:%u:%g' "$c/opt/bookorbit/custom library/book.epub" 2> /dev/null || true)" "$library_before" "$variant database library inode survived"
      check "$(cat "$c/opt/bookorbit/custom library/book.epub" 2> /dev/null || true)" 'USER book bytes' "$variant book bytes survived"
      check "$(cat "$c/opt/bookorbit/caller keep/row" 2> /dev/null || true)" 'USER caller' "$variant literal inherited keep survives"
      check "$(cat "$c/opt/bookorbit/legacy/row" 2> /dev/null || true)" 'USER legacy' "$variant legacy inherited keep survives"
      if [[ "$variant" == trailing ]]; then check "$(cat "$c/opt/bookorbit/custom import /row" 2> /dev/null || true)" 'USER imports' 'source resolves import-root value without trimming'; fi
      check "$(sha256sum "$c/units/bookorbit.service" | cut -d' ' -f1)" "$unit_before" "$variant operator unit unchanged"
      if [[ "$expected" == 65 && "$variant" != late-db && "$variant" != changed-set && "$variant" != root-remap ]]; then
        check "$(stat -c %s "$c/effects")" 0 "$variant refusal precedes runtime effects"
        check "$(stat -c %s "$c/services")" 0 "$variant refusal precedes service effects"
        check "$(cat "$c/opt/bookorbit/code")" 'USER code' "$variant refusal precedes replacement"
      fi
      case "$variant" in
        env-symlink | env-hardlink | env-directory)
          check "$(stat -c '%i:%a:%u:%g:%h:%F' "$c/opt/bookorbit/.env")" "$env_metadata" "$variant config alias inode/type/metadata unchanged"
          check "$(stat -c '%i:%a:%u:%g:%h:%F' "$c/external/environment")" "$target_metadata" "$variant config target inode/metadata unchanged"
          check "$(sha256sum "$c/external/environment" | cut -d' ' -f1)" "$target_bytes" "$variant target bytes unchanged"
          check "$(readlink "$c/opt/bookorbit/.env" || true)" "$env_link" "$variant link target unchanged"
          check "$(grep -c '/opt/bookorbit/.env must be a single-link regular file' "$c/output" || true)" 1 "$variant specific config path diagnostic"
          ;;
        late-db | changed-set | root-remap)
          check "$(cat "$c/effects")" runtime 'late discovery failure follows runtime setup'
          check "$(cat "$c/services")" 'stop bookorbit' 'late discovery failure leaves stopped service'
          check "$(cat "$c/opt/bookorbit/code")" 'USER code' 'late discovery failure leaves source untouched'
          if [[ "$variant" == late-db ]]; then
            check "$(grep -c 'discovery failed after service stop; configuration/data retained' "$c/output" || true)" 1 'late discovery diagnostic identifies retained state and stopped service'
          else
            check "$(grep -Ec 'configuration/library roots changed|application root changed' "$c/output" || true)" 1 'changed successful discovery refuses before replacement'
            check "$(wc -l < "$c/db")" 2 'two successful SQL discovery calls'
            check "$(stat -c %s "$c/packages")" 0 'no package work after changed discovery'
            check "$(stat -c %s "$c/pnpm")" 0 'no build work after changed discovery'
          fi
          check "$(grep -c 'no app effects' "$c/output" || true)" 0 'late discovery never claims before-effects refusal'
          ;;
      esac
      case "$variant" in
        root-*)
          printf 'BOOKORBIT_ROOT_OUTCOME mode=%s variant=%s status=%s library=%s source=%s\n' "$verbose" "$variant" "$rc" \
            "$(if [[ -f "$c/opt/bookorbit/custom library/book.epub" ]]; then printf present; else printf missing; fi)" \
            "$(if grep -qx 'new client bytes' "$c/opt/bookorbit/server/public/index.html"; then printf changed; else printf old; fi)"
          check "$(readlink "$c/opt/bookorbit")" "$(if [[ "$variant" == root-remap ]]; then printf ../srv/remapped; else printf ../srv/bookorbit; fi)" 'logical root alias retained at selected physical root'
          if [[ "$rc" == 0 ]]; then
            check "$(cat "$c/opt/bookorbit/server/public/index.html")" 'new client bytes' 'physical root received changed source witness'
            if [[ "$variant" == root-alias ]]; then check "$(readlink "$c/opt/bookorbit/library alias")" 'custom library' 'in-tree alias retained with referent'; fi
            case "$variant" in root-physical | root-alias) check "$(readlink "$c/opt/bookorbit/escape")" "$c/external" 'escaping alias retained without touching external target' ;; esac
          fi
          ;;
      esac
      if [[ "$rc" != 0 ]]; then check "$(test -e "$c/pending/bookorbit" && printf present || printf absent)" present "$variant failure retains pending"; fi
      if [[ "$variant" == build || "$variant" == copy || "$variant" == download ]]; then
        printf 'update\n' > "$c/variant"
        retry=0
        env -i PATH="$c/bin:$PATH" CASE_ROOT="$c" HOME="$c/home" TMPDIR="$TMPDIR" RUNTIME_NODE="$RUNTIME_NODE" VARIANT=update ROLE=update VERBOSE="$verbose" APP=BookOrbit NSAPP=bookorbit LOCAL_IP=10.20.30.40 BUILD_LOG="$c/build.log" DEBUG_LOGFILE="$c/errors.log" \
          timeout 50s unshare -m --propagation private -- bash "$0" --child > "$c/retry-output" 2>&1 || retry=$?
        check "$retry" 0 "$variant normal pending retry succeeds without app dependencies"
        if [[ "$retry" != 0 ]]; then tail -n 5 "$c/retry-output"; fi
        check "$(test -e "$c/pending/bookorbit" && printf present || printf absent)" absent "$variant successful retry clears pending"
        check "$(stat -c '%d:%i:%a:%u:%g' "$c/opt/bookorbit/custom library/book.epub" 2> /dev/null || true)" "$library_before" "$variant retry retains original book inode"
      fi
    fi
    check "$(cat "$c/external/row")" 'USER outside' "$variant external data untouched"
    if [[ "$rc" == 0 ]]; then
      check "$(
        "$RUNTIME_NODE" - "$c/build-node" << 'JS'
const fs = require('node:fs');
const rows = fs.readFileSync(process.argv[2], 'utf8').trim().split('\n').map(JSON.parse);
console.log(rows.map(r => r.target + '/' + r.phase).join(','));
JS
      )" 'client/launcher,client/build-only,server/launcher,server/prebuild-types,server/prebuild-plugin-api,server/prebuild-swagger,server/build' "$verbose/$variant native child Node heap and modeled lifecycle inheritance"
      check "$(
        "$RUNTIME_NODE" - "$c/caller-node" "${caller_env[0]-}" << 'JS'
const fs = require('node:fs');
const assert = require('node:assert/strict');
const rows = fs.readFileSync(process.argv[2], 'utf8').trim().split('\n').map(JSON.parse);
const expected = process.argv[3].replace(/^NODE_OPTIONS=/, '');
assert(rows.some(r => r.phase === 'dependency-install'));
assert(rows.some(r => r.phase === 'after-build'));
assert(rows.every(r => r.present === (expected ? 'x' : '') && r.value === expected));
assert(rows.every(r => r.heap_size_limit === rows[0].heap_size_limit));
console.log('restored');
JS
      )" restored "$verbose/$variant caller flags and native heap unchanged outside build phase"
      check "$(grep -c djvulibre-bin "$c/packages" || true)" 1 "$variant DjVu dependency installed"
      check "$(grep -c 'install --frozen-lockfile --filter client... --filter server...' "$c/pnpm" || true)" 1 "$variant frozen core-only closure"
      check "$(grep -c -- '--config.verify-deps-before-run=false.*run build' "$c/pnpm" || true)" 2 "$variant prebuild-aware filtered commands"
      check "$(cat "$c/opt/bookorbit/server/public/index.html")" 'new client bytes' "$variant actual public contents replaced"
      check "$(test -e "$c/opt/bookorbit/server/public/dist" && printf nested || printf correct)" correct "$variant no nested dist publication"
    fi
    rm -rf -- "$c"
  done
done
printf 'BookOrbit focused failures=%s; native file/parser/replacement/Node heap consumers, package/build/lifecycle/PG/systemd producers modeled\n' "$failures"
[[ "$failures" == 0 ]]
