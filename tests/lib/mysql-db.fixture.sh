#!/usr/bin/env bash
# Actual setup_mysql_db from misc/tools.func with the real silent wrapper, under cold
# env -i shells. Only mysql and (for failure legs) openssl are models: mysql records its
# argv and stdin SQL. No native engine is involved; SQL parsing and grants need a real server.
set -euo pipefail
ROOT=$(realpath "$(dirname "${BASH_SOURCE[0]}")/../..")
if [[ "${1:-}" == --child ]]; then
  c="$CASE_ROOT"
  source "$ROOT/misc/core.func"
  source "$ROOT/misc/tools.func"
  load_functions
  msg_info() { printf 'info:%s\n' "$*" >> "$c/messages"; }
  msg_ok() { printf 'ok:%s\n' "$*" >> "$c/messages"; }
  msg_error() { printf 'error:%s\n' "$*" >> "$c/messages"; }
  count() {
    local n=0
    [[ ! -f "$c/$1.count" ]] || n=$(< "$c/$1.count")
    n=$((n + 1))
    printf '%s\n' "$n" > "$c/$1.count"
    printf '%s' "$n"
  }
  mysql() {
    local n
    n=$(count mysql)
    printf '%s\n' "$*" > "$c/mysql-args.$n"
    cat > "$c/mysql-sql.$n"
    return "${MYSQL_STATUS:-0}"
  }
  mariadb() { return 0; }
  sudo() { return 0; }
  ln() {
    command ln "$@" || return $?
    stat -c '%a %s' "${!#}" >> "$c/credentials-created"
  }
  openssl() {
    local n
    n=$(count openssl)
    case "${OPENSSL_MODE:-real}" in
      real) command openssl "$@" ;;
      fail) return "${OPENSSL_STATUS:-41}" ;;
      empty) return 0 ;;
      junk) printf '+/=+/=\n' ;;
      short) if [[ "$n" == 1 ]]; then printf 'ab+/\n'; else command openssl "$@"; fi ;;
    esac
  }
  finish() {
    local status=$?
    printf '%s\n' "${rc:-$status}" > "$c/rc"
    printf '%s' "${MYSQL_DB_PASS-unset}" > "$c/pass-after"
    printf '%s' "${MYSQL_DB_NAME-unset}" > "$c/name-after"
    bash -c 'printf %s "${MYSQL_DB_PASS-unset}"' > "$c/pass-child" || true
    umask > "$c/umask-after"
  }
  trap finish EXIT
  [[ "$PIPEFAIL" == on ]] || set +o pipefail
  umask "${CALLER_UMASK:-022}"
  case "$CALL" in
    credentials)
      case "$DB_ENGINE" in
        mysql) setup_mysql_db || rc=$? ;;
        mariadb) setup_mariadb_db || rc=$? ;;
        postgresql) setup_postgresql_db || rc=$? ;;
      esac
      ;;
    plain) setup_mysql_db || rc=$? ;;
    cond) if setup_mysql_db; then rc=0; else rc=$?; fi ;;
    errexit)
      setup_mysql_db
      rc=0
      ;;
    prefix) MYSQL_DB_NAME=fleet MYSQL_DB_USER=fleet setup_mysql_db || rc=$? ;;
  esac
  rc=${rc:-0}
  exit 0
fi

: "${TMPDIR:?disk-backed TMPDIR required}"
systemd-detect-virt --vm --quiet || exit 1
case "$(realpath -e "$TMPDIR")" in /tmp | /tmp/*) exit 1 ;; esac
case "$(findmnt -rn -T "$TMPDIR" -o FSTYPE)" in '' | tmpfs | ramfs) exit 1 ;; esac
work=$(mktemp -d "$TMPDIR/mysql-db.XXXXXX")
trap 'rm -rf -- "$work"' EXIT
failures=0
check() {
  if [[ "$1" == "$2" ]]; then printf 'PASS %s\n' "$3"; else
    printf 'FAIL %s: expected <%s>, got <%s>\n' "$3" "$2" "$1" >&2
    failures=$((failures + 1))
  fi
}
n=0
# go LABEL ENV...: run one fresh cold child (errexit, nounset and the selected pipefail).
# Sets c, rc and L. The cold shell has no APPLICATION and no ambient MYSQL_DB_* values.
go() {
  local label="$1"
  n=$((n + 1))
  c="$work/$n"
  mkdir -p "$c/home"
  : > "$c/messages"
  env -i PATH="$PATH" HOME="$c/home" TMPDIR="$TMPDIR" CASE_ROOT="$c" ROOT="$ROOT" VERBOSE="$STD_MODE" \
    BUILD_LOG="$c/build.log" DEBUG_LOGFILE="$c/errors.log" PIPEFAIL="$PF" CALL="$CALL" "${@:2}" \
    timeout 30s bash "$0" --child < /dev/null > "$c/output" 2>&1 || true
  rc=missing
  [[ ! -f "$c/rc" ]] || rc=$(< "$c/rc")
  L="$label/$STD_MODE/pipefail-$PF/$CALL"
}
rd() { cat "$1" 2> /dev/null || true; }
sql_calls() { if [[ -f "$c/mysql.count" ]]; then cat "$c/mysql.count"; else printf 0; fi; }
has_file() { if [[ -e "$1" ]]; then printf present; else printf absent; fi; }
creds_default() { printf '%s' "$c/home/fleet.creds"; }
nothing_published() {
  check "$(rd "$c/pass-after")" unset "$L no password exported"
  check "$(grep -c '^ok:' "$c/messages" || true)" 0 "$L no success message"
}
for STD_MODE in no yes; do
  for PF in on off; do
    for CALL in plain cond errexit; do
      tag="$STD_MODE-$PF-$CALL"
      # Missing required inputs
      go missing-name MYSQL_DB_USER=u APP=Fleet
      check "$rc" 65 "$L missing name status"
      check "$(sql_calls)" 0 "$L missing name no SQL"
      nothing_published
      check "$(has_file "$(creds_default)")" absent "$L missing name no credentials file"
      go missing-user MYSQL_DB_NAME=d APP=Fleet
      check "$rc" 65 "$L missing user status"
      check "$(sql_calls)" 0 "$L missing user no SQL"
      go missing-both APP=Fleet
      check "$rc" 65 "$L missing both status"
      # Default credentials path needs baked APP and HOME; explicit path does not
      go no-app MYSQL_DB_NAME=d MYSQL_DB_USER=u
      check "$rc" 65 "$L missing APP and path status"
      check "$(sql_calls)" 0 "$L missing APP no SQL"
      go poisoned-application MYSQL_DB_NAME=d MYSQL_DB_USER=u APPLICATION=Poison
      check "$rc" 65 "$L APPLICATION is not the identity source"
      go explicit-path MYSQL_DB_NAME=d MYSQL_DB_USER=u MYSQL_DB_CREDS_FILE="$work/explicit-$tag.creds"
      check "$rc" 0 "$L explicit credentials path without APP status"
      check "$(has_file "$work/explicit-$tag.creds")" present "$L explicit credentials path used"

      # Generated password: shape, same-shell and child visibility, one value everywhere
      go generated MYSQL_DB_NAME=fleet MYSQL_DB_USER=fleet APP=Fleet
      check "$rc" 0 "$L generated status"
      pw=$(rd "$c/pass-after")
      check "$(printf '%s' "$pw" | grep -Ec '^[A-Za-z0-9]{13}$' || true)" 1 "$L generated 13-char alphanumeric"
      check "$(rd "$c/pass-child")" "$pw" "$L password visible to child process"
      check "$(rd "$c/name-after")" fleet "$L name exported"
      check "$(cat "$(creds_default)")" "$(printf 'MySQL Credentials\nDatabase: fleet\nUser: fleet\nPassword: %s' "$pw")" "$L default Fleet credentials block"
      check "$(sql_calls)" 1 "$L one mysql session"
      check "$(grep -c "IDENTIFIED BY '$pw';" "$c/mysql-sql.1" || true)" 1 "$L SQL carries the same password"
      check "$(grep -c -F -e "$pw" "$c/mysql-args.1" || true)" 0 "$L password absent from mysql argv"
      check "$(grep -c '^ok:' "$c/messages" || true)" 1 "$L success message once"
      check "$(cat "$c/mysql-sql.1")" "$(printf "SET SESSION sql_mode='NO_BACKSLASH_ESCAPES';\nCREATE DATABASE \`fleet\` CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;\nCREATE USER 'fleet'@'%%' IDENTIFIED BY '%s';\nGRANT ALL ON \`fleet\`.* TO 'fleet'@'%%';\nFLUSH PRIVILEGES;" "$pw")" "$L exact SQL with percent host and database-only grant"
      check "$(cat "$c/mysql-args.1")" '-u root' "$L root login, SQL on stdin"

      # Entropy failures
      go entropy-fail MYSQL_DB_NAME=d MYSQL_DB_USER=u APP=Fleet OPENSSL_MODE=fail OPENSSL_STATUS=41
      check "$rc" 41 "$L entropy failure status"
      check "$(sql_calls)" 0 "$L entropy failure no SQL"
      check "$(has_file "$(creds_default)")" absent "$L entropy failure no credentials"
      nothing_published
      go entropy-empty MYSQL_DB_NAME=d MYSQL_DB_USER=u APP=Fleet OPENSSL_MODE=empty
      check "$rc" 1 "$L empty entropy refused"
      check "$(sql_calls)" 0 "$L empty entropy no SQL"
      go entropy-junk MYSQL_DB_NAME=d MYSQL_DB_USER=u APP=Fleet OPENSSL_MODE=junk
      check "$rc" 1 "$L no-alphanumeric entropy refused"
      check "$(sql_calls)" 0 "$L junk entropy no SQL"
      go entropy-short MYSQL_DB_NAME=d MYSQL_DB_USER=u APP=Fleet OPENSSL_MODE=short
      check "$rc" 0 "$L short first batch is extended"
      check "$(rd "$c/openssl.count")" 2 "$L second checked batch requested"
      check "$(printf '%s' "$(rd "$c/pass-after")" | grep -Ec '^ab[A-Za-z0-9]{11}$' || true)" 1 "$L extended password is 13 alphanumerics"

      # Supplied password: exact, never truncated, never regenerated
      for sup in "p" "it's" 'a\b' 'x\' "x\\'" "q''q" 'dq"q' 'b`t' 'semi;--#' '100%_x' 'dollar $HOME &' ' sp ace ' 'abcdefghijklmnopqrstuvwxyz0123456789'; do
        go supplied MYSQL_DB_NAME=d MYSQL_DB_USER=u APP=Fleet MYSQL_DB_PASS="$sup"
        expected_sql=${sup//\'/\'\'}
        check "$rc" 0 "$L supplied <$sup> status"
        check "$(grep -c '^CREATE USER ' "$c/mysql-sql.1" || true)" 1 "$L supplied <$sup> one CREATE USER"
        check "$(sed -n "s/^CREATE USER 'u'@'%' IDENTIFIED BY '\\(.*\\)';\$/\\1/p" "$c/mysql-sql.1")" "$expected_sql" "$L supplied <$sup> SQL value is only quote-doubled"
        check "$(rd "$c/pass-after")" "$sup" "$L supplied <$sup> same-shell value"
        check "$(rd "$c/pass-child")" "$sup" "$L supplied <$sup> child value"
        check "$(sed -n 's/^Password: //p' "$(creds_default)")" "$sup" "$L supplied <$sup> credentials value"
        check "$(has_file "$c/openssl.count")" absent "$L supplied <$sup> no entropy request"
      done

      # Identifiers and values: quote and backtick doubling; grant wildcard escapes
      go quoted-user MYSQL_DB_NAME=d MYSQL_DB_USER="o'brien" APP=Fleet MYSQL_DB_PASS=x
      check "$(grep -c "^CREATE USER 'o''brien'@'%' IDENTIFIED BY 'x';\$" "$c/mysql-sql.1" || true)" 1 "$L user quote doubled in CREATE USER"
      check "$(grep -c "^GRANT ALL ON \`d\`.\* TO 'o''brien'@'%';\$" "$c/mysql-sql.1" || true)" 1 "$L user quote doubled in GRANT"
      check "$(sed -n 's/^User: //p' "$(creds_default)")" "o'brien" "$L credentials keep user bytes"
      go backtick-db MYSQL_DB_NAME='a`b' MYSQL_DB_USER=u APP=Fleet MYSQL_DB_PASS=x
      check "$(grep -c '^CREATE DATABASE `a``b` CHARACTER SET' "$c/mysql-sql.1" || true)" 1 "$L backtick doubled in CREATE DATABASE"
      check "$(grep -c '^GRANT ALL ON `a``b`\.\* TO' "$c/mysql-sql.1" || true)" 1 "$L backtick doubled in GRANT"
      go wildcard-db MYSQL_DB_NAME='my_db%x\y' MYSQL_DB_USER=u APP=Fleet MYSQL_DB_PASS=x
      check "$(grep -c '^CREATE DATABASE `my_db%x\\y` CHARACTER SET' "$c/mysql-sql.1" || true)" 1 "$L CREATE DATABASE keeps the literal name"
      check "$(grep -c '^GRANT ALL ON `my\\_db\\%x\\\\y`\.\* TO' "$c/mysql-sql.1" || true)" 1 "$L GRANT escapes _ % and backslash"
      check "$(sed -n 's/^Database: //p' "$(creds_default)")" 'my_db%x\y' "$L credentials keep database bytes"

      # mysql failure: exact status, no credentials, nothing published, nothing printed
      for status in 1 127; do
        go "mysql-$status" MYSQL_DB_NAME=d MYSQL_DB_USER=u APP=Fleet MYSQL_STATUS=$status
        check "$rc" "$status" "$L mysql status $status propagated"
        check "$(has_file "$(creds_default)")" absent "$L mysql failure writes no credentials"
        nothing_published
      done
      go mysql-secret MYSQL_DB_NAME=d MYSQL_DB_USER=u APP=Fleet MYSQL_DB_PASS=secretvalue MYSQL_STATUS=5
      check "$rc" 5 "$L supplied-password mysql failure status"
      check "$(cat "$c/messages" "$c/output" | grep -c -F secretvalue || true)" 0 "$L supplied password is not printed on failure"

      # Credentials append failure after DDL: reported, nothing published, no rollback
      mkdir -p "$work/dir-creds-$tag"
      go creds-fail MYSQL_DB_NAME=d MYSQL_DB_USER=u APP=Fleet MYSQL_DB_CREDS_FILE="$work/dir-creds-$tag"
      check "$([[ "$rc" != 0 && "$rc" != missing ]] && printf nonzero || printf '%s' "$rc")" nonzero "$L credentials failure status"
      check "$(sql_calls)" 1 "$L DDL already ran; no rollback or retry"
      nothing_published
      check "$(grep -c '^error:Failed to write the MySQL credentials file' "$c/messages" || true)" 1 "$L actionable credentials error"

      # Existing credentials are appended to, never replaced
      printf 'USER existing line\n' > "$work/existing-$tag.creds"
      chmod 640 "$work/existing-$tag.creds"
      go existing-creds MYSQL_DB_NAME=d MYSQL_DB_USER=u APP=Fleet MYSQL_DB_PASS=x MYSQL_DB_CREDS_FILE="$work/existing-$tag.creds"
      check "$rc" 0 "$L existing credentials status"
      check "$(head -n1 "$work/existing-$tag.creds")" 'USER existing line' "$L existing credentials bytes retained"
      check "$(stat -c %a "$work/existing-$tag.creds")" 640 "$L existing credentials mode retained"
      check "$(grep -c '^MySQL Credentials$' "$work/existing-$tag.creds")" 1 "$L labeled block appended"
    done
  done
done

# The database helpers share one private append contract, including public-parent paths.
STD_MODE=yes PF=on CALL=credentials
for engine in mysql mariadb postgresql; do
  case "$engine" in mysql) prefix=MYSQL ;; mariadb) prefix=MARIADB ;; postgresql) prefix=PG ;; esac
  for mask in 000 022 077; do
    path="$work/$engine-$mask.creds"
    go private-creds DB_ENGINE="$engine" CALLER_UMASK="$mask" APP=Fleet APPLICATION=Fleet \
      "${prefix}_DB_NAME=d" "${prefix}_DB_USER=u" "${prefix}_DB_PASS=x" "${prefix}_DB_CREDS_FILE=$path"
    check "$rc" 0 "$L $engine new file status"
    check "$(stat -c %a "$path")" 600 "$L $engine new credentials private with umask $mask"
    check "$(grep -c '^Password: x$' "$path")" 1 "$L $engine exact password saved"
    check "$(rd "$c/umask-after")" "0$mask" "$L $engine caller umask preserved"
    chmod 640 "$path"
    go existing-private-creds DB_ENGINE="$engine" CALLER_UMASK="$mask" APP=Fleet APPLICATION=Fleet \
      "${prefix}_DB_NAME=d" "${prefix}_DB_USER=u" "${prefix}_DB_PASS=y" "${prefix}_DB_CREDS_FILE=$path"
    check "$rc" 0 "$L $engine append status"
    check "$(stat -c %a "$path")" 640 "$L $engine operator mode preserved"
    check "$(grep -c '^Password: [xy]$' "$path")" 2 "$L $engine prior and new credentials retained"
  done
done

# Default ACLs override umask. Observe each real link publication before any write.
for engine in mysql mariadb postgresql; do
  case "$engine" in mysql) prefix=MYSQL ;; mariadb) prefix=MARIADB ;; postgresql) prefix=PG ;; esac
  for acl in basic named; do
    parent="$work/$engine-$acl"
    mkdir "$parent"
    python3 - "$parent" "$acl" << 'PY'
import os,struct,sys
rows=[(1,7,0xffffffff),(4,5,0xffffffff),(32,5,0xffffffff)]
if sys.argv[2]=='named':rows=[(1,7,0xffffffff),(2,4,65534),(4,5,0xffffffff),(16,5,0xffffffff),(32,5,0xffffffff)]
raw=struct.pack('<I',2)+b''.join(struct.pack('<HHI',*entry) for entry in rows)
os.setxattr(sys.argv[1],'system.posix_acl_default',raw)
assert os.getxattr(sys.argv[1],'system.posix_acl_default')==raw
PY
    for mask in 000 022 077; do
      path="$parent/$mask.creds"
      go default-acl DB_ENGINE="$engine" CALLER_UMASK="$mask" APP=Fleet APPLICATION=Fleet \
        "${prefix}_DB_NAME=d" "${prefix}_DB_USER=u" "${prefix}_DB_PASS=x" "${prefix}_DB_CREDS_FILE=$path"
      check "$rc" 0 "$L $engine $acl ACL status"
      check "$(stat -c %a "$path")" 600 "$L $engine $acl default ACL creates private credentials with umask $mask"
      check "$(rd "$c/credentials-created")" '600 0' "$L $engine $acl new file is private and empty at atomic publication"
      check "$(grep -c '^Password: x$' "$path")" 1 "$L $engine $acl password published"
      check "$(rd "$c/umask-after")" "0$mask" "$L $engine $acl caller umask preserved"
      chmod 640 "$path"
      go existing-acl DB_ENGINE="$engine" CALLER_UMASK="$mask" APP=Fleet APPLICATION=Fleet \
        "${prefix}_DB_NAME=d" "${prefix}_DB_USER=u" "${prefix}_DB_PASS=y" "${prefix}_DB_CREDS_FILE=$path"
      check "$rc" 0 "$L $engine $acl existing-file append status"
      check "$(stat -c %a "$path")" 640 "$L $engine $acl existing mode unchanged"
      check "$(grep -c '^Password: [xy]$' "$path")" 2 "$L $engine $acl existing credentials retained"
      check "$(has_file "$c/credentials-created")" absent "$L $engine $acl existing file is not recreated"
      check "$(find "$parent" -maxdepth 1 -name '.credentials.*' | wc -l)" 0 "$L $engine $acl no private staging file retained"
    done
  done
done

# Fleet's actual calling form: prefix assignments only supply NAME/USER
for STD_MODE in no yes; do
  for PF in on off; do
    CALL=prefix
    go prefix-form APP=Fleet
    check "$rc" 0 "$L prefix call status"
    pw=$(rd "$c/pass-after")
    check "$(printf '%s' "$pw" | grep -Ec '^[A-Za-z0-9]{13}$' || true)" 1 "$L generated password survives the prefix-assignment call"
    check "$(rd "$c/pass-child")" "$pw" "$L generated password visible to child after prefix call"
  done
done
printf '%s failure(s); actual setup_mysql_db and silent wrapper, mysql/openssl-failure models; no native MySQL parsing or grant claim\n' "$failures"
[[ "$failures" == 0 ]]
