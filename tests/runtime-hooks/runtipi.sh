#!/usr/bin/env bash
# runtime-hooks-contract: addon intent-preserving
# shellcheck disable=SC2034,SC2154
set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/../lib/runtime-hooks/harness.sh"
app=runtipi script_type=addon
variants=(fresh temp-unset temp-empty decline download empty daemon-failure installer-failure update uninstall stop-failure down-failure missing-compose)
hook_paths=()
runtime_hooks_variant() {
  case "$variant" in
    temp-unset | temp-empty | decline | download | empty | daemon-failure | installer-failure) role=install fault=$variant ;;
    uninstall) role=uninstall ;;
    stop-failure | down-failure | missing-compose) role=uninstall fault=$variant ;;
  esac
}
runtime_hooks_setup() {
  printf 'var_addon_install_path=%q\nvar_addon_default_port=18080\n' '/opt/runtipi custom' > "$c/context.sh"
  printf 'y\n' > "$c/stdin"
  [[ "$variant" != decline ]] || printf 'n\n' > "$c/stdin"
  printf 'foreign installer\n' > "$c/opt/install.sh"
  : > "$c/docker"
  : > "$c/docker.jsonl"
  : > "$c/packages"
  : > "$c/installer-ran"
  : > "$c/cli"
  : > "$c/resources"
  cat > "$c/cli-model" << 'CLI'
#!/usr/bin/env bash
set -euo pipefail
printf '%s\n' "$*" >> "$APP_FIXTURE/cli"
[[ "$APP_FAULT" != stop-failure || "$1" != stop ]] || exit 46
CLI
  chmod 755 "$c/cli-model"
  if [[ "$role" != install ]]; then
    mkdir -p "$c/opt/runtipi custom/user-config"
    cp "$c/cli-model" "$c/opt/runtipi custom/runtipi-cli"
    [[ "$variant" == missing-compose ]] || printf 'owned compose\n' > "$c/opt/runtipi custom/docker-compose.yml"
    printf 'operator layer\n' > "$c/opt/runtipi custom/user-config/tipi-compose.yml"
    printf 'private env\n' > "$c/opt/runtipi custom/.env"
    printf 'app data\n' > "$c/opt/runtipi custom/data"
  fi
}
runtime_hooks_model() {
  case "$APP_FAULT" in temp-unset) unset TMPDIR ;; temp-empty) TMPDIR='' ;; esac
  mktemp() {
    # Only observe the production fallback; never allocate in guest RAM or /.
    if [[ "$*" == *runtipi-installer.* ]]; then
      printf '%s\n' "$*" >> "$c/temp-selection"
      case "$1" in
        /tmp/runtipi-installer.*) command mktemp "$c/tmp/runtipi-installer.XXXXXXXX" ;;
        /runtipi-installer.*) return 98 ;;
        *) command mktemp "$@" ;;
      esac
    else command mktemp "$@"; fi
  }
  apt() { printf '%s\n' "$*" >> "$c/packages"; }
  docker() {
    printf '%s\n' "$*" >> "$c/docker"
    jq -cn --args '$ARGS.positional' -- "$@" >> "$c/docker.jsonl"
    [[ "$APP_FAULT/$1" != daemon-failure/info ]] || return 48
    if [[ "$1" != compose && "$1" != info ]]; then
      [[ "$APP_FAULT" != inventory-failure ]] || return 48
      [[ "$1" != container || ! -s "$c/resources" ]] || printf 'exact-project-resource\n'
      return 0
    fi
    [[ "$APP_FAULT" != down-failure || " $* " != *' down '* ]] || return 47
    [[ " $* " != *' down '* ]] || : > "$c/resources"
  }
  ln() {
    [[ "$APP_FAULT" != settings-publish-failure || "${!#}" != "$var_addon_install_path/state/settings.json" ]] || return 42
    command ln "$@"
  }
  rm() {
    [[ "$APP_FAULT" != cleanup-failure || "${!#}" != "$var_addon_install_path/state/settings.json" ]] || return 44
    command rm "$@"
  }
  curl() {
    local out=''
    while (($#)); do
      [[ "$1" != -o ]] || {
        out=$2
        shift
      }
      shift
    done
    [[ "$APP_FAULT" != empty ]] || {
      : > "$out"
      return 0
    }
    cat > "$out" << 'INSTALLER'
#!/usr/bin/env bash
set -euo pipefail
printf '%s\n' "$PWD|$*" >> "$APP_FIXTURE/installer-ran"
cp state/settings.json "$APP_FIXTURE/entry-settings.json"
[[ "$APP_FAULT" != installer-failure ]] || exit 49
if [[ " ${*} " != *' --update '* ]]; then mkdir -p runtipi; cd runtipi; fi
mkdir -p state
cp "$APP_FIXTURE/cli-model" ./runtipi-cli
[[ -e state/settings.json ]] || printf '{}\n' > state/settings.json
printf 'owned compose\n' > docker-compose.yml
printf 'native env\n' > .env
printf 'launched\n' > "$APP_FIXTURE/resources"
[[ "$APP_FAULT" != exposed-failure ]] || exit 49
INSTALLER
    [[ "$APP_FAULT" != download ]] || return 22
  }
}
runtime_hooks_expected() {
  case "$variant" in
    decline | missing-compose) expected=1 ;;
    download) expected=22 ;;
    empty) expected=251 ;;
    daemon-failure) expected=48 ;;
    installer-failure) expected=49 ;;
    stop-failure) expected=46 ;;
    down-failure) expected=47 ;;
  esac
}
runtime_hooks_assert() {
  check "$(cat "$c/opt/install.sh" 2> /dev/null || true)" 'foreign installer' "$app/$variant never owns shared /opt/install.sh"
  if [[ "$variant" == fresh || "$variant" == temp-unset || "$variant" == temp-empty ]]; then
    check "$(cat "$c/installer-ran")" '/opt/runtipi custom|--update' "$app installer consumes selected working root without an extra runtipi child"
    check "$(jq -r '.port' "$c/opt/runtipi custom/state/settings.json" 2> /dev/null || true)" 18080 "$app native settings contract receives configured port before launch"
    check "$(jq -r '.port' "$c/entry-settings.json" 2> /dev/null || true)" 18080 "$app installer entry consumes selected port, not a later repair"
    check "$(jq -sc '[.[] | select(.[0] == "info")] | length' "$c/docker.jsonl")" 1 "$app positively checks the Docker daemon before state or installer effects"
    check "$(test -x "$c/opt/runtipi custom/runtipi-cli" && printf present || printf absent)" present "$app CLI is published at selected root"
    if [[ "$variant" != fresh ]]; then
      check "$(cat "$c/temp-selection" 2> /dev/null || true)" '/tmp/runtipi-installer.XXXXXXXX' "$app/$variant production fallback is selected without writing there in the VM"
    fi
  fi
  if [[ "$role" == install ]]; then
    check "$(test -e "$c/etc/docker/daemon.json" && printf present || printf absent)" absent "$app/$variant never changes shared Docker daemon defaults"
    check "$(find "$c/tmp" -name 'runtipi-installer.*' | wc -l)" 0 "$app/$variant retires only its exact external installer stage"
    case "$variant" in
      decline | download | empty | daemon-failure)
        check "$(stat -c %s "$c/installer-ran")" 0 "$app/$variant never executes an unaccepted producer"
        check "$(stat -c %s "$c/packages")" 0 "$app/$variant has no dependency effects"
        ;;
    esac
    if [[ "$variant" == daemon-failure ]]; then
      check "$(test -e "$c/opt/runtipi custom" && printf present || printf absent)" absent "$app failed daemon admission leaves selected install root absent"
    fi
  fi
  if [[ "$role" == uninstall ]]; then
    if [[ "$expected" != 0 ]]; then
      check "$(cat "$c/opt/runtipi custom/data" 2> /dev/null || true)" 'app data' "$app/$variant retains all app data on teardown failure"
    else
      check "$(cat "$c/opt/runtipi custom/data" 2> /dev/null || true)" 'app data' "$app successful uninstall preserves unlisted app data"
    fi
    if [[ "$variant" == uninstall || "$variant" == down-failure ]]; then
      check "$(grep -Fc -- '--project-name runtipi' "$c/docker" || true)" 1 "$app/$variant scopes native compose project"
      check "$(grep -Fc -- '-f /opt/runtipi custom/user-config/tipi-compose.yml' "$c/docker" || true)" 1 "$app/$variant consumes selected operator layer"
      check "$(jq -sc '.[0] == ["compose","--project-name","runtipi","-f","/opt/runtipi custom/docker-compose.yml","-f","/opt/runtipi custom/user-config/tipi-compose.yml","--env-file","/opt/runtipi custom/.env","down","--remove-orphans"]' "$c/docker.jsonl")" true "$app/$variant complete Compose argv retains each selected path as one operand"
    fi
  fi
}
runtime_hooks_retry_needed() { return 1; }
runtime_hooks_more_cases() {
  local install_status uninstall_status desired attempt_root
  for mode in no yes; do
    for variant in settings-publish-failure installer-failure exposed-failure exposed-missing inventory-failure down-failure cleanup-failure; do
      c="$work/runtipi-partial-$mode-$variant"
      role=install fault=$variant
      case "$variant" in exposed-missing | inventory-failure | down-failure | cleanup-failure) fault=exposed-failure ;; esac
      mkdir -p "$c/opt" "$c/local/bin" "$c/home"
      : > "$c/services"
      runtime_hooks_setup
      runtime_hooks_prepare
      install_status=0
      runtime_hooks_invoke install "$fault" "$c/output" "$c/build.log" "$c/errors.log" || install_status=$?
      check "$install_status" "$([[ "$variant" == settings-publish-failure ]] && printf 42 || printf 49)" "$app/$variant intended install failure"
      attempt_root="$c/opt/runtipi custom"
      mkdir -p "$attempt_root"
      printf 'operator recovery data\n' > "$attempt_root/operator"
      if [[ "$variant" == exposed-missing ]]; then
        cp "$attempt_root/docker-compose.yml" "$c/restored-compose"
        rm "$attempt_root/docker-compose.yml"
      fi
      # No manifest plus failed inventory is not absence, even with empty stdout.
      [[ "$variant" != inventory-failure ]] || rm "$attempt_root/docker-compose.yml"
      : > "$c/docker"
      : > "$c/docker.jsonl"
      uninstall_status=0 desired=0
      case "$variant" in exposed-missing) desired=1 ;; inventory-failure) desired=48 ;; down-failure) desired=47 ;; cleanup-failure) desired=44 ;; esac
      runtime_hooks_invoke uninstall "$variant" "$c/uninstall-output" "$c/uninstall.log" "$c/uninstall-errors.log" || uninstall_status=$?
      check "$uninstall_status" "$desired" "$app/$variant cold uninstall exact recovery status"
      check "$(cat "$attempt_root/operator" 2> /dev/null || true)" 'operator recovery data' "$app/$variant never removes unknown root contents"
      check "$(test -e "$c/local/sbin/uninstall" && printf present || printf absent)" "$([[ "$desired" == 0 ]] && printf absent || printf present)" "$app/$variant success-only command retirement"
      check "$(test -e "$c/addon-install-attempts/runtipi" && printf present || printf absent)" "$([[ "$desired" == 0 ]] && printf absent || printf present)" "$app/$variant success-only custody retirement"
      if [[ "$variant" == settings-publish-failure || "$variant" == installer-failure ]]; then
        check "$(test -e "$attempt_root/state" && printf present || printf absent)" absent "$app/$variant bounded empty state cleanup"
      fi
      if [[ "$desired" != 0 ]]; then
        if [[ "$variant" == exposed-missing || "$variant" == inventory-failure ]]; then
          [[ "$variant" != inventory-failure ]] || printf 'owned compose\n' > "$c/restored-compose"
          cp "$c/restored-compose" "$attempt_root/docker-compose.yml"
        fi
        uninstall_status=0
        runtime_hooks_invoke uninstall none "$c/retry-output" "$c/retry.log" "$c/retry-errors.log" || uninstall_status=$?
        check "$uninstall_status" 0 "$app/$variant explicit cold recovery succeeds"
        check "$(test -e "$c/local/sbin/uninstall" && printf present || printf absent)" absent "$app/$variant successful retry retires commands"
        check "$(test -e "$attempt_root/state/settings.json" && printf present || printf absent)" absent "$app/$variant retry removes exact owned settings"
        check "$(grep -c ' down ' "$c/docker" || true)" "$([[ "$variant" == down-failure ]] && printf 2 || printf 1)" "$app/$variant completed down not replayed after cleanup interruption"
      fi
    done
  done
}
runtime_hooks_main "$@"
