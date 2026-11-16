#!/usr/bin/env bash
# External installer/Docker models, cold shared-producer lifecycle commands.
# shellcheck disable=SC2034,SC2154
set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/../lib/runtime-hooks/harness.sh"
app=dokploy
script_type=addon
variants=(fresh update release-transport-error)
hook_paths=()
runtime_hooks_variant() { [[ "$variant" != release-transport-error ]] || fault=checker; }
runtime_hooks_model() {
  msg_info() { :; }
  msg_ok() { printf 'ok %s\n' "$*"; }
  msg_error() { printf 'error %s\n' "$*"; }
  msg_warn() { printf 'warn %s\n' "$*"; }
  apt() { :; }
  if [[ "$APP_ROLE" == uninstall ]]; then export PATH="$c/bin:$PATH"; else
    docker() { printf 'Docker version fixture\n'; }
  fi
  curl() {
    [[ "$APP_FAULT" != checker ]] || return 17
    printf 'download completed\n' >> "$c/requests"
    printf 'printf "new installer consumer\\n" > "$APP_FIXTURE/consumer"\n'
  }
}
runtime_hooks_setup() {
  mkdir -p "$c/app"
  printf 'var_addon_install_path=%q\nvar_addon_installer_url=https://fixture.invalid/install.sh\n' "$c/app" > "$c/context.sh"
  printf 'yes\n' > "$c/stdin"
  printf 'old installer consumer\n' > "$c/consumer"
  : > "$c/requests"
}
runtime_hooks_expected() { [[ "$fault" != checker ]] || expected=17; }
runtime_hooks_assert() {
  if [[ "$role" == install || "$mode" == yes ]]; then
    check "$(cat "$c/consumer")" "$([[ "$rc" == 0 ]] && printf 'new installer consumer' || printf 'old installer consumer')" "$app/$variant external installer consumer"
  fi
  if [[ "$fault" == checker ]]; then check "$(stat -c %s "$c/requests")" 0 "$app release transport failure does not publish downloaded source"; fi
}
runtime_hooks_retry_assert() {
  check "$(grep -c '^download completed$' "$c/requests")" 1 "$app pending retry repeats the release transport"
  # Quiet STD currently redirects producer bytes from this pipeline. Phase E
  # owns that application defect; status/transport proof is not consumer proof.
  if [[ "$mode" == yes ]]; then check "$(cat "$c/consumer")" 'new installer consumer' "$app verbose pending retry executes installer"; fi
}
runtime_hooks_more_cases() {
  for mode in no yes; do
    for fault in none query scale remove network volume empty; do
      c="$work/$mode $fault"
      mkdir -p "$c"/{bin,tmp,app/compose/foreign/files,state/service,state/container,state/network,state/volume,state/secret}
      printf 'saved configuration\n' > "$c/app/data"
      printf 'foreign bind data\n' > "$c/app/compose/foreign/files/canary"
      for resource in 'container foreign-container' 'volume foreign-volume' 'network foreign-network' 'network foreign-unused-network' 'service dokploy-extra-service' 'volume dokploy-extra-volume'; do
        read -r kind name <<< "$resource"
        : > "$c/state/$kind/$name"
      done
      if [[ "$fault" != empty ]]; then
        for kind in service volume; do
          for name in dokploy dokploy-postgres dokploy-redis; do : > "$c/state/$kind/$name"; done
        done
        : > "$c/state/container/dokploy-traefik"
        : > "$c/state/network/dokploy-network"
        for name in dokploy_postgres_password dokploy_auth_secret; do : > "$c/state/secret/$name"; done
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
    rm -f "$CASE_ROOT/state/$1/${!#}"
    ;;
  'ps -aq') printf 'foreign-container\ndokploy-traefik\n' ;;
  'stop foreign-container' | 'rm foreign-container') rm -f "$CASE_ROOT/state/container/foreign-container" ;;
  'network prune') rm -f "$CASE_ROOT/state/network/foreign-unused-network" ;;
  *) exit 92 ;;
esac
MODEL
      chmod +x "$c/bin/docker"
      rc=0
      role=uninstall variant=$fault
      printf 'var_addon_install_path=%q\n' "$c/app" > "$c/context.sh"
      runtime_hooks_prepare
      runtime_hooks_invoke uninstall "$fault" "$c/output" "$c/build.log" "$c/errors.log" || rc=$?
      expected=0
      case "$fault" in query) expected=46 ;; scale) expected=47 ;; remove) expected=48 ;; network) expected=49 ;; volume) expected=50 ;; esac
      check "$rc" "$expected" "dokploy/$mode/$fault status"
      runtime_hooks_uninstall_assert
      check "$(cat "$c/app/compose/foreign/files/canary" 2> /dev/null || true)" 'foreign bind data' "dokploy/$mode/$fault retains inside-root bind data"
      for resource in 'container foreign-container' 'volume foreign-volume' 'network foreign-network' 'network foreign-unused-network' 'service dokploy-extra-service' 'volume dokploy-extra-volume'; do
        read -r kind name <<< "$resource"
        check "$(test -e "$c/state/$kind/$name" && printf kept || printf lost)" kept "dokploy/$fault retains $kind $name"
      done
      if [[ "$expected" == 0 ]]; then
        for resource in 'service dokploy' 'service dokploy-postgres' 'service dokploy-redis' 'container dokploy-traefik' 'network dokploy-network' 'volume dokploy' 'volume dokploy-postgres' 'volume dokploy-redis' 'secret dokploy_postgres_password' 'secret dokploy_auth_secret'; do
          read -r kind name <<< "$resource"
          check "$(test -e "$c/state/$kind/$name" && printf present || printf absent)" absent "dokploy/$fault removes $kind $name"
        done
        if [[ "$fault" == none ]]; then
          for name in dokploy dokploy-postgres dokploy-redis; do
            check "$(grep -Fxc "service scale --detach=false $name=0" "$c/events" || true)" 1 "dokploy converges $name before service removal"
            check "$(grep -Fxc "service rm $name" "$c/events" || true)" 1 "dokploy explicitly removes service $name"
            check "$(grep -Fxc "volume rm $name" "$c/events" || true)" 1 "dokploy explicitly removes volume $name"
          done
        fi
        check "$(cat "$c/app/data" 2> /dev/null || true)" 'saved configuration' "dokploy retains install directory after Docker success"
        check "$(grep -Fxc "warn Retained directory $c/app; it may contain deployment data." "$c/output" || true)" 1 "dokploy notice names the exact retained directory and deployment data"
        printf -v remove_command 'rm -rf -- %q' "$c/app"
        check "$(grep -Fxc "warn To remove it manually: $remove_command" "$c/output" || true)" 1 "dokploy notice provides a shell-quoted removal command"
      else
        check "$(cat "$c/app/data" 2> /dev/null || true)" 'saved configuration' "dokploy/$fault retains configuration on failure"
        check "$(grep -c 'has been uninstalled' "$c/output" || true)" 0 "dokploy/$fault no false success"
      fi
    done
  done
}
runtime_hooks_main "$@"
