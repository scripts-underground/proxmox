#!/usr/bin/env bash
# runtime-hooks-contract: addon intent-preserving
# External installer/Docker models, cold shared-producer lifecycle commands.
# shellcheck disable=SC2034,SC2154
set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/../lib/runtime-hooks/harness.sh"
app=coolify
script_type=addon
variants=(fresh update installer-release-error)
hook_paths=()
runtime_hooks_variant() { [[ "$variant" != installer-release-error ]] || fault=checker; }
runtime_hooks_model() {
  msg_info() { :; }
  msg_ok() { printf 'ok %s\n' "$*"; }
  msg_error() { printf 'error %s\n' "$*"; }
  msg_warn() { printf 'warn %s\n' "$*"; }
  apt() { :; }
  if [[ "$APP_ROLE" == uninstall ]]; then export PATH="$c/bin:$PATH"; else
    docker() { :; }
  fi
  curl() {
    # Exercise the external installer's release failure, not the unchecked
    # process-substitution transport (a separate phase-E application issue).
    if [[ "$APP_FAULT" == checker ]]; then printf 'exit 17\n'; else printf 'printf "new installer consumer\\n" > "$APP_FIXTURE/consumer"\n'; fi
  }
}
runtime_hooks_setup() {
  mkdir -p "$c/app"
  printf 'var_addon_install_path=%q\nvar_addon_installer_url=https://fixture.invalid/install.sh\n' "$c/app" > "$c/context.sh"
  printf 'yes\n' > "$c/stdin"
  printf 'old installer consumer\n' > "$c/consumer"
}
runtime_hooks_expected() { [[ "$fault" != checker ]] || expected=17; }
runtime_hooks_assert() {
  check "$(cat "$c/consumer")" "$([[ "$rc" == 0 ]] && printf 'new installer consumer' || printf 'old installer consumer')" "$app/$variant external installer result reaches consumer"
}
runtime_hooks_retry_assert() { check "$(cat "$c/consumer")" 'new installer consumer' "$app ordinary pending retry executes installer"; }
runtime_hooks_more_cases() {
  for mode in no yes; do
    for fault in none compose network missing agents proxy; do
      c="$work/$mode $fault"
      mkdir -p "$c"/{bin,tmp,app/source,app/services/foreign/data,state}
      printf 'foreign bind data\n' > "$c/app/services/foreign/data/canary"
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
      role=uninstall variant=$fault
      printf 'var_addon_install_path=%q\n' "$c/app" > "$c/context.sh"
      runtime_hooks_prepare
      runtime_hooks_invoke uninstall "$fault" "$c/output" "$c/build.log" "$c/errors.log" || rc=$?
      expected=0
      case "$fault" in compose) expected=47 ;; network) expected=48 ;; missing) expected=1 ;; agents) expected=49 ;; proxy) expected=50 ;; esac
      check "$rc" "$expected" "coolify/$mode/$fault status"
      runtime_hooks_uninstall_assert
      check "$(cat "$c/app/services/foreign/data/canary" 2> /dev/null || true)" 'foreign bind data' "coolify/$mode/$fault retains inside-root bind data"
      for name in foreign-container foreign-volume foreign-network foreign-unused-network coolify-user-app; do
        check "$(test -e "$c/state/$name" && printf kept || printf lost)" kept "coolify/$fault retains $name"
      done
      if [[ "$fault" == none ]]; then
        for name in coolify-container coolify-volume coolify-network coolify-sentinel coolify-proxy-error-pages coolify-proxy; do
          check "$(test -e "$c/state/$name" && printf present || printf absent)" absent "coolify/$mode removes $name"
        done
        check "$(cat "$c/app/data" 2> /dev/null || true)" 'saved configuration' "coolify retains install directory after Docker success"
        check "$(grep -Fxc "warn Retained directory $c/app; it may contain deployment data." "$c/output" || true)" 1 "coolify notice names the exact retained directory and deployment data"
        printf -v remove_command 'rm -rf -- %q' "$c/app"
        check "$(grep -Fxc "warn To remove it manually: $remove_command" "$c/output" || true)" 1 "coolify notice provides a shell-quoted removal command"
      else
        check "$(cat "$c/app/data" 2> /dev/null || true)" 'saved configuration' "coolify/$fault retains configuration on failure"
        check "$(grep -c 'has been uninstalled' "$c/output" || true)" 0 "coolify/$fault no false success"
      fi
    done
  done
}
runtime_hooks_main "$@"
