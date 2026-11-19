#!/usr/bin/env bash
# Sourced inside the existing owned live-runtime CT. Real engines and consumers.
work="${work:?owned native evidence directory required}"
ensure_dependencies gnupg sudo
printf 'NATIVE_DATABASE_EVIDENCE %s\n' "$work"
# Observe the URL at the real repository-key boundary without printing key bytes.
eval "$(declare -f download_gpg_key | sed '1s/download_gpg_key/_native_download_gpg_key/')"
download_gpg_key() {
  printf '%s\n' "$1" >> "$work/database-key-urls.log"
  _native_download_gpg_key "$@"
}
curl() {
  local arg
  for arg in "$@"; do
    case "$arg" in https://*/ACCC4CF8.asc) printf '%s\n' "$arg" >> "$work/database-key-urls.log" ;; esac
  done
  command curl "$@"
}
PG_VERSION=16 setup_postgresql
grep -Fx 'https://apt.postgresql.org/pub/repos/apt/ACCC4CF8.asc' "$work/database-key-urls.log"
PG_DB_NAME=core_native PG_DB_USER=core_native PG_DB_SCHEMA_PERMS=true PG_DB_CREDS_FILE="$work/postgres.creds" setup_postgresql_db
[[ "$PG_DB_PASS" =~ ^[A-Za-z0-9]{13}$ ]]
[[ "$(stat -c %a "$work/postgres.creds")" == 600 ]]
PGPASSWORD="$PG_DB_PASS" psql -X -v ON_ERROR_STOP=1 -h 127.0.0.1 -U core_native -d core_native \
  -c "CREATE TABLE native_consumer (id integer PRIMARY KEY, value text NOT NULL); INSERT INTO native_consumer VALUES (1, 'U4 retained consumer');" > "$work/postgres-write.log"
systemctl restart postgresql
PGPASSWORD="$PG_DB_PASS" psql -X -At -v ON_ERROR_STOP=1 -h 127.0.0.1 -U core_native -d core_native \
  -c 'SELECT value FROM native_consumer WHERE id=1' > "$work/postgres-read.log"
grep -Fx 'U4 retained consumer' "$work/postgres-read.log"
printf 'PASS native PGDG trust, generated credentials, authenticated write/restart/read consumer\n'

# The selected current official package must pass its own pre-main ISA checks.
# This is genuine package admission, not a full ClickHouse service proof.
clickhouse_native_stage=$(_tools_stage_dir native-clickhouse)
_clickhouse_stage_package latest "$clickhouse_native_stage" > "$work/clickhouse-admission.log" 2>&1
cat "$clickhouse_native_stage/version" > "$work/clickhouse-selected.log"
"$clickhouse_native_stage/payload/usr/bin/clickhouse" server --version >> "$work/clickhouse-selected.log"
printf 'PASS native authenticated selected ClickHouse package CPU admission\n'

# A historical patch upgrade with actual on-disk Meilisearch data. No selected
# version is changed to latest and no dumpless-upgrade assumption is involved.
fetch_and_deploy_gh_release meilisearch meilisearch/meilisearch singlefile 1.12.0 /usr/bin meilisearch-linux-amd64
mkdir -p /var/lib/meilisearch/data /var/lib/meilisearch/dumps /var/lib/meilisearch/snapshots
cat > /etc/meilisearch.toml << 'TOML'
env = "development"
http_addr = "127.0.0.1:7700"
db_path = "/var/lib/meilisearch/data"
dump_dir = "/var/lib/meilisearch/dumps"
snapshot_dir = "/var/lib/meilisearch/snapshots"
no_analytics = true
TOML
cat > /etc/systemd/system/meilisearch.service << 'UNIT'
[Unit]
Description=Owned U4 Meilisearch consumer
After=network.target
[Service]
ExecStart=/usr/bin/meilisearch --config-file-path /etc/meilisearch.toml
Restart=on-failure
[Install]
WantedBy=multi-user.target
UNIT
systemctl daemon-reload
systemctl enable --now meilisearch
curl -fsS --retry 10 --retry-connrefused --retry-delay 1 http://127.0.0.1:7700/health > "$work/meilisearch-health.log"
curl -fsS -H 'Content-Type: application/json' -X POST 'http://127.0.0.1:7700/indexes/probe/documents?primaryKey=id' \
  --data '[{"id":"u4","title":"U4 retained consumer"}]' > "$work/meilisearch-task.log"
task=$(jq -er .taskUid "$work/meilisearch-task.log")
for ((attempt = 0; attempt < 60; attempt++)); do
  curl -fsS "http://127.0.0.1:7700/tasks/$task" > "$work/meilisearch-task-state.log"
  [[ "$(jq -r .status "$work/meilisearch-task-state.log")" != succeeded ]] || break
  sleep 1
done
jq -e '.status=="succeeded"' "$work/meilisearch-task-state.log" > /dev/null
# A real failed export returns failure and leaves the original HTTP data usable.
eval "$(declare -f _meilisearch_request | sed '1s/_meilisearch_request/_native_meilisearch_request/')"
_meilisearch_request() {
  [[ "$1" != */dumps ]] || return 22
  _native_meilisearch_request "$@"
}
status=0
_meilisearch_update 1.12.1 || status=$?
[[ "$status" == 22 && "$(/usr/bin/meilisearch --version)" == 'meilisearch 1.12.0' ]]
curl -fsS --retry 10 --retry-connrefused --retry-delay 1 http://127.0.0.1:7700/indexes/probe/documents/u4 > "$work/meilisearch-after-failure.log"
jq -e '.title=="U4 retained consumer"' "$work/meilisearch-after-failure.log" > /dev/null
# A real client can finish a write between public activation and a later health/
# marker failure. An old snapshot must never replace that acknowledged write.
_meilisearch_request() {
  if [[ "$1" == http://127.0.0.1:7700/version ]]; then
    local result task attempt state
    result=$(_native_meilisearch_request http://127.0.0.1:7700/indexes/probe/documents '' \
      -H 'Content-Type: application/json' -X POST --data '[{"id":"acknowledged","title":"Acknowledged after exposure"}]') || return $?
    task=$(jq -er .taskUid <<< "$result") || return $?
    for ((attempt = 0; attempt < 60; attempt++)); do
      state=$(_native_meilisearch_request "http://127.0.0.1:7700/tasks/$task" '') || return $?
      [[ "$(jq -r .status <<< "$state")" != succeeded ]] || break
      sleep 1
    done
    jq -e '.status=="succeeded"' <<< "$state" > "$work/meilisearch-acknowledged.log" || return $?
    return 22
  fi
  _native_meilisearch_request "$@"
}
status=0
_meilisearch_update 1.12.1 || status=$?
[[ "$status" == 22 && "$(/usr/bin/meilisearch --version)" == 'meilisearch 1.12.1' ]]
curl -fsS http://127.0.0.1:7700/indexes/probe/documents/acknowledged > "$work/meilisearch-after-exposure-failure.log"
jq -e '.title=="Acknowledged after exposure"' "$work/meilisearch-after-exposure-failure.log" > /dev/null
[[ "$(cat "$HOME/.meilisearch")" == 1.12.0 ]]
printf 'PASS native Meilisearch acknowledged public write survives a later update failure; prior marker retained\n'
_meilisearch_request() { _native_meilisearch_request "$@"; }
_meilisearch_update 1.12.1
[[ "$(/usr/bin/meilisearch --version)" == 'meilisearch 1.12.1' ]]
curl -fsS http://127.0.0.1:7700/indexes/probe/documents/u4 > "$work/meilisearch-after-upgrade.log"
jq -e '.title=="U4 retained consumer"' "$work/meilisearch-after-upgrade.log" > /dev/null
curl -fsS http://127.0.0.1:7700/indexes/probe/documents/acknowledged > "$work/meilisearch-after-retry.log"
jq -e '.title=="Acknowledged after exposure"' "$work/meilisearch-after-retry.log" > /dev/null
[[ "$(cat "$HOME/.meilisearch")" == 1.12.1 ]]
printf 'PASS native Meilisearch failed export recovery and patch migration with actual document consumer\n'
