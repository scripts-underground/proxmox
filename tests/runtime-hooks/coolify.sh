#!/usr/bin/env bash
# Cold actual addon uninstall; Docker is a stateful model, not native proof.
set -euo pipefail
ROOT=$(realpath "$(dirname "${BASH_SOURCE[0]}")/../..")
if [[ "${1:-}" == --child ]]; then
  source "$ROOT/misc/core.func"
  load_functions
  curl() { :; }
  source "${ADDON_OWNER_ROOT:-$ROOT}/scripts/addon/coolify.sh"
  unset -f curl
  msg_info() { :; }
  msg_ok() { printf 'ok %s\n' "$*"; }
  msg_error() { printf 'error %s\n' "$*"; }
  export PATH="$CASE_ROOT/bin:$PATH"
  uninstall_script
  exit
fi
systemd-detect-virt --vm --quiet || exit 1
: "${TMPDIR:?disk-backed TMPDIR required}"
case "$(findmnt -rn -T "$TMPDIR" -o FSTYPE)" in '' | tmpfs | ramfs) exit 1 ;; esac
work=$(mktemp -d "$TMPDIR/coolify-uninstall.XXXXXXXX")
trap 'rm -rf -- "$work"' EXIT
failures=0
check() {
  if [[ "$1" == "$2" ]]; then printf 'PASS %s\n' "$3"; else
    printf 'FAIL %s expected <%s> got <%s>\n' "$3" "$2" "$1" >&2
    failures=$((failures + 1))
  fi
}
for mode in no yes; do
  for fault in none compose network missing agents proxy; do
    c="$work/$mode-$fault"
    mkdir -p "$c"/{bin,tmp,app/source,state}
    for name in docker-compose.yml docker-compose.prod.yml docker-compose.custom.yml docker-compose.postgres-upgrade.yml .env; do
      : > "$c/app/source/$name"
    done
    [[ "$fault" != missing ]] || rm "$c/app/source/docker-compose.prod.yml"
    printf 'saved configuration\n' > "$c/app/data"
    mkdir -p "$c/app/proxy"
    : > "$c/app/proxy/docker-compose.yml"
    for name in foreign-container foreign-volume foreign-network foreign-unused-network coolify-user-app coolify-container coolify-volume coolify-network coolify-sentinel coolify-proxy-error-pages coolify-proxy; do : > "$c/state/$name"; done
    cat > "$c/bin/docker" << 'MODEL'
#!/usr/bin/env bash
set -euo pipefail
printf '%s\n' "$*" >> "$CASE_ROOT/events"
case "$1 $2" in
  'compose --env-file')
    [[ "$FAULT" != compose ]] || exit 47
    [[ "$*" == *'-f docker-compose.yml -f docker-compose.prod.yml -f docker-compose.custom.yml -f docker-compose.postgres-upgrade.yml down --volumes'* ]] || exit 91
    [[ "$PWD" == "$CASE_ROOT/app/source" ]] || exit 92
    rm -f "$CASE_ROOT/state/coolify-container" "$CASE_ROOT/state/coolify-volume"
    ;;
  'network ls') printf 'coolify\nforeign-network\nforeign-unused-network\n' ;;
  'container ls')
    [[ "$*" == 'container ls -a --filter label=coolify.managed=true --format {{.Names}}' ]] || exit 97
    printf 'coolify-sentinel\ncoolify-proxy-error-pages\ncoolify-user-app\n'
    ;;
  'container rm')
    [[ "$FAULT" != agents ]] || exit 49
    case "${!#}" in coolify-sentinel | coolify-proxy-error-pages) rm "$CASE_ROOT/state/${!#}" ;; *) exit 95 ;; esac
    ;;
  'compose -f')
    [[ "$FAULT" != proxy ]] || exit 50
    [[ "$3" == "$CASE_ROOT/app/proxy/docker-compose.yml" ]] || exit 96
    rm "$CASE_ROOT/state/coolify-proxy"
    ;;
  'network rm')
    [[ "$3" == coolify ]] || exit 93
    [[ "$FAULT" != network ]] || exit 48
    rm "$CASE_ROOT/state/coolify-network"
    ;;
  'ps -aq') printf 'foreign-container\ncoolify-container\n' ;;
  'stop foreign-container' | 'rm foreign-container') rm -f "$CASE_ROOT/state/foreign-container" ;;
  'network prune') rm -f "$CASE_ROOT/state/foreign-unused-network" ;;
  *) exit 94 ;;
esac
MODEL
    chmod +x "$c/bin/docker"
    rc=0
    env -i PATH="$PATH" HOME="$c" TMPDIR="$c/tmp" CASE_ROOT="$c" FAULT="$fault" VERBOSE="$mode" \
      ADDON_OWNER_ROOT="${ADDON_OWNER_ROOT:-$ROOT}" var_addon_install_path="$c/app" BUILD_LOG="$c/build.log" \
      bash "$0" --child > "$c/output" 2>&1 || rc=$?
    expected=0
    case "$fault" in compose) expected=47 ;; network) expected=48 ;; missing) expected=1 ;; agents) expected=49 ;; proxy) expected=50 ;; esac
    check "$rc" "$expected" "coolify/$mode/$fault status"
    for name in foreign-container foreign-volume foreign-network foreign-unused-network coolify-user-app; do
      check "$(test -e "$c/state/$name" && printf kept || printf lost)" kept "coolify/$fault retains $name"
    done
    if [[ "$fault" == none ]]; then
      for name in coolify-container coolify-volume coolify-network coolify-sentinel coolify-proxy-error-pages coolify-proxy; do
        check "$(test -e "$c/state/$name" && printf present || printf absent)" absent "coolify/$mode removes $name"
      done
      check "$(test -e "$c/app" && printf present || printf absent)" absent "coolify removes app after Docker success"
    else
      check "$(cat "$c/app/data" 2> /dev/null || true)" 'saved configuration' "coolify/$fault retains configuration on failure"
      check "$(grep -c 'has been uninstalled' "$c/output" || true)" 0 "coolify/$fault no false success"
    fi
  done
done
printf 'RUNTIME_HOOKS_RESULT failures=%s\n' "$failures"
[[ "$failures" == 0 ]]
