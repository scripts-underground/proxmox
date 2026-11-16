#!/usr/bin/env bash
# Cold actual addon uninstall; Docker is a stateful model, not native proof.
set -euo pipefail
ROOT=$(realpath "$(dirname "${BASH_SOURCE[0]}")/../..")
if [[ "${1:-}" == --child ]]; then
  source "$ROOT/misc/core.func"
  load_functions
  curl() { :; }
  source "${ADDON_OWNER_ROOT:-$ROOT}/scripts/addon/dokploy.sh"
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
work=$(mktemp -d "$TMPDIR/dokploy-uninstall.XXXXXXXX")
trap 'rm -rf -- "$work"' EXIT
failures=0
check() {
  if [[ "$1" == "$2" ]]; then printf 'PASS %s\n' "$3"; else
    printf 'FAIL %s expected <%s> got <%s>\n' "$3" "$2" "$1" >&2
    failures=$((failures + 1))
  fi
}
for mode in no yes; do
  for fault in none query scale remove network volume empty; do
    c="$work/$mode-$fault"
    mkdir -p "$c"/{bin,tmp,app,state}
    printf 'saved configuration\n' > "$c/app/data"
    for name in foreign-container foreign-volume foreign-network foreign-unused-network dokploy-extra-service dokploy-extra-volume dokploy dokploy-postgres dokploy-redis dokploy-traefik dokploy-network dokploy_postgres_password dokploy_auth_secret; do : > "$c/state/$name"; done
    if [[ "$fault" == empty ]]; then
      rm "$c/state/"{dokploy,dokploy-postgres,dokploy-redis,dokploy-traefik,dokploy-network,dokploy_postgres_password,dokploy_auth_secret}
    fi
    cat > "$c/bin/docker" << 'MODEL'
#!/usr/bin/env bash
set -euo pipefail
printf '%s\n' "$*" >> "$CASE_ROOT/events"
case "$1 $2" in
  'service ls' | 'container ls' | 'volume ls' | 'network ls' | 'secret ls')
    [[ "$FAULT" != query ]] || exit 46
    [[ "$FAULT" != empty ]] || exit 0
    case "$1" in
      service) printf 'dokploy\ndokploy-postgres\ndokploy-redis\ndokploy-extra-service\n' ;;
      container) printf 'dokploy-traefik\nforeign-container\n' ;;
      volume) printf 'dokploy\ndokploy-postgres\ndokploy-redis\nforeign-volume\ndokploy-extra-volume\n' ;;
      network) printf 'dokploy-network\nforeign-network\nforeign-unused-network\n' ;;
      secret) printf 'dokploy_postgres_password\ndokploy_auth_secret\n' ;;
    esac
    ;;
  'service scale') [[ "$FAULT" != scale ]] || exit 47 ;;
  'service rm' | 'container rm' | 'volume rm' | 'network rm' | 'secret rm')
    case "${!#}" in dokploy | dokploy-postgres | dokploy-redis | dokploy-traefik | dokploy-network | dokploy_postgres_password | dokploy_auth_secret) ;; *) exit 91 ;; esac
    [[ "$FAULT" != remove || "$1" != service ]] || exit 48
    [[ "$FAULT" != network || "$1" != network ]] || exit 49
    [[ "$FAULT" != volume || "$1" != volume ]] || exit 50
    rm -f "$CASE_ROOT/state/${!#}"
    ;;
  'ps -aq') printf 'foreign-container\ndokploy-traefik\n' ;;
  'stop foreign-container' | 'rm foreign-container') rm -f "$CASE_ROOT/state/foreign-container" ;;
  'network prune') rm -f "$CASE_ROOT/state/foreign-unused-network" ;;
  *) exit 92 ;;
esac
MODEL
    chmod +x "$c/bin/docker"
    rc=0
    env -i PATH="$PATH" HOME="$c" TMPDIR="$c/tmp" CASE_ROOT="$c" FAULT="$fault" VERBOSE="$mode" \
      ADDON_OWNER_ROOT="${ADDON_OWNER_ROOT:-$ROOT}" var_addon_install_path="$c/app" BUILD_LOG="$c/build.log" \
      bash "$0" --child > "$c/output" 2>&1 || rc=$?
    expected=0
    case "$fault" in query) expected=46 ;; scale) expected=47 ;; remove) expected=48 ;; network) expected=49 ;; volume) expected=50 ;; esac
    check "$rc" "$expected" "dokploy/$mode/$fault status"
    for name in foreign-container foreign-volume foreign-network foreign-unused-network dokploy-extra-service dokploy-extra-volume; do
      check "$(test -e "$c/state/$name" && printf kept || printf lost)" kept "dokploy/$fault retains $name"
    done
    if [[ "$expected" == 0 ]]; then
      for name in dokploy dokploy-postgres dokploy-redis dokploy-traefik dokploy-network dokploy_postgres_password dokploy_auth_secret; do
        check "$(test -e "$c/state/$name" && printf present || printf absent)" absent "dokploy/$fault removes $name"
      done
      if [[ "$fault" == none ]]; then
        for name in dokploy dokploy-postgres dokploy-redis; do
          check "$(grep -Fxc "service scale --detach=false $name=0" "$c/events" || true)" 1 "dokploy converges $name before service removal"
          check "$(grep -Fxc "volume rm $name" "$c/events" || true)" 1 "dokploy explicitly removes volume $name"
        done
      fi
      check "$(test -e "$c/app" && printf present || printf absent)" absent "dokploy removes app after Docker success"
    else
      check "$(cat "$c/app/data" 2> /dev/null || true)" 'saved configuration' "dokploy/$fault retains configuration on failure"
      check "$(grep -c 'has been uninstalled' "$c/output" || true)" 0 "dokploy/$fault no false success"
    fi
  done
done
printf 'RUNTIME_HOOKS_RESULT failures=%s\n' "$failures"
[[ "$failures" == 0 ]]
