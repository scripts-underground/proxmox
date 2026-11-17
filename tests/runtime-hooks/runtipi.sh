#!/usr/bin/env bash
# shellcheck disable=SC2034,SC2154
set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/../lib/runtime-hooks/harness.sh"
app=runtipi script_type=addon
variants=(fresh decline download empty installer-failure update uninstall stop-failure down-failure missing-compose)
hook_paths=()
runtime_hooks_variant() {
  case "$variant" in
    decline | download | empty | installer-failure) role=install fault=$variant ;;
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
  : > "$c/packages"
  : > "$c/installer-ran"
  : > "$c/cli"
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
  apt() { printf '%s\n' "$*" >> "$c/packages"; }
  docker() {
    printf '%s\n' "$*" >> "$c/docker"
    [[ "$APP_FAULT" != down-failure || " $* " != *' down '* ]] || return 47
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
[[ "$APP_FAULT" != installer-failure ]] || exit 49
if [[ " ${*} " != *' --update '* ]]; then mkdir -p runtipi; cd runtipi; fi
mkdir -p state
cp "$APP_FIXTURE/cli-model" ./runtipi-cli
[[ -e state/settings.json ]] || printf '{}\n' > state/settings.json
INSTALLER
    [[ "$APP_FAULT" != download ]] || return 22
  }
}
runtime_hooks_expected() {
  case "$variant" in
    decline | missing-compose) expected=1 ;;
    download) expected=22 ;;
    empty) expected=251 ;;
    installer-failure) expected=49 ;;
    stop-failure) expected=46 ;;
    down-failure) expected=47 ;;
  esac
}
runtime_hooks_assert() {
  check "$(cat "$c/opt/install.sh" 2> /dev/null || true)" 'foreign installer' "$app/$variant never owns shared /opt/install.sh"
  if [[ "$variant" == fresh ]]; then
    check "$(cat "$c/installer-ran")" '/opt/runtipi custom|--update' "$app installer consumes selected working root without an extra runtipi child"
    check "$(jq -r '.port' "$c/opt/runtipi custom/state/settings.json" 2> /dev/null || true)" 18080 "$app native settings contract receives configured port before launch"
    check "$(test -x "$c/opt/runtipi custom/runtipi-cli" && printf present || printf absent)" present "$app CLI is published at selected root"
  fi
  if [[ "$role" == install ]]; then
    check "$(test -e "$c/etc/docker/daemon.json" && printf present || printf absent)" absent "$app/$variant never changes shared Docker daemon defaults"
    check "$(find "$c/tmp" -name 'runtipi-installer.*' | wc -l)" 0 "$app/$variant retires only its exact external installer stage"
    case "$variant" in
      decline | download | empty)
        check "$(stat -c %s "$c/installer-ran")" 0 "$app/$variant never executes an unaccepted producer"
        check "$(stat -c %s "$c/packages")" 0 "$app/$variant has no dependency effects"
        ;;
    esac
  fi
  if [[ "$role" == uninstall ]]; then
    if [[ "$expected" != 0 ]]; then
      check "$(cat "$c/opt/runtipi custom/data" 2> /dev/null || true)" 'app data' "$app/$variant retains all app data on teardown failure"
    else
      check "$(test -e "$c/opt/runtipi custom/data" && printf present || printf absent)" absent "$app successful uninstall removes owned app data"
    fi
    if [[ "$variant" == uninstall || "$variant" == down-failure ]]; then
      check "$(grep -Fc -- '--project-name runtipi' "$c/docker" || true)" 1 "$app/$variant scopes native compose project"
      check "$(grep -Fc -- '-f /opt/runtipi custom/user-config/tipi-compose.yml' "$c/docker" || true)" 1 "$app/$variant consumes selected operator layer"
    fi
  fi
}
runtime_hooks_retry_needed() { return 1; }
runtime_hooks_main "$@"
