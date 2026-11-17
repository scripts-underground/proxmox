#!/usr/bin/env bash
# shellcheck disable=SC2034,SC2154
set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/../lib/runtime-hooks/addon-release.sh"
app=mqttx
release_app=$app release_mode=tarball release_asset=unused.tar.gz
addon_release_setup() {
  printf 'var_addon_app_dir=/opt/mqttx\n' > "$c/context.sh"
  mkdir -p "$c/payload/web"
  mkdir -p "$c/etc/nginx/"{sites-available,sites-enabled}
  printf 'foreign site\n' > "$c/etc/nginx/sites-available/foreign"
  ln -s "$c/etc/nginx/sites-available/foreign" "$c/etc/nginx/sites-enabled/foreign"
  if [[ "$role" == uninstall || "$variant" == install-conflict ]]; then
    printf 'operator mqttx site\n' > "$c/etc/nginx/sites-available/mqttx-web"
    ln -s "$c/etc/nginx/sites-available/mqttx-web" "$c/etc/nginx/sites-enabled/mqttx-web"
    mkdir -p "$c/opt/mqttx"
    printf 'old app\n' > "$c/opt/mqttx/data"
    printf 'operator unit\n' > "$c/etc/systemd/system/mqttx-web.service"
  fi
}
addon_release_consumer_assert() { check "$(cat "$c/opt/$app/code")" 'new code' "$app selected source consumer"; }
eval "$(declare -f runtime_hooks_assert | sed '1s/runtime_hooks_assert/mqttx_release_assert/')"
variants+=(fresh install-test install-reload uninstall uninstall-test uninstall-reload install-conflict)
runtime_hooks_variant() {
  case "$variant" in
    checker) fault=checker ;;
    uninstall) role=uninstall ;;
    uninstall-test | uninstall-reload) role=uninstall fault=$variant ;;
    install-test | install-reload) role=install fault=$variant ;;
    install-conflict) role=install fault=install-conflict ;;
  esac
}
runtime_hooks_model() {
  addon_release_model
  dpkg() { return 0; }
  apt() { printf '%s\n' "$*" >> "$c/packages"; }
  nginx() {
    printf '%s\n' "$*" >> "$c/nginx-calls"
    [[ "$APP_FAULT" != uninstall-test && "$APP_FAULT" != install-test ]] || return 46
  }
  systemctl() {
    printf '%s\n' "$*" >> "$c/service-attempts"
    [[ ("$APP_FAULT" != uninstall-reload && "$APP_FAULT" != install-reload) || "$*" != 'reload nginx' ]] || return 47
    printf '%s\n' "$*" >> "$c/services"
    if [[ "$1" == show ]]; then printf 'LoadState=loaded\nActiveState=active\nUnitFileState=enabled\n'; fi
  }
}
runtime_hooks_expected() {
  case "$fault" in checker) expected=17 ;; uninstall-test | install-test) expected=46 ;; uninstall-reload | install-reload) expected=47 ;; install-conflict) expected=65 ;; esac
}
runtime_hooks_assert() {
  if [[ "$role" == update ]]; then
    mqttx_release_assert
    return
  fi
  check "$(cat "$c/etc/nginx/sites-available/foreign")" 'foreign site' "$app/$variant foreign site bytes retained"
  check "$(readlink "$c/etc/nginx/sites-enabled/foreign")" "$c/etc/nginx/sites-available/foreign" "$app/$variant foreign site stays enabled"
  check "$(grep -Ec '^(stop|disable) nginx' "$c/services" || true)" 0 "$app/$variant never stops or disables shared nginx"
  if [[ "$role" == install && "$variant" != install-conflict ]]; then
    local outcome=absent
    [[ "$expected" != 0 ]] || outcome=present
    check "$(test -e "$c/etc/nginx/sites-available/mqttx-web" && printf present || printf absent)" "$outcome" "$app/$variant available site reflects accepted configuration"
    check "$({ test -e "$c/etc/nginx/sites-enabled/mqttx-web" || test -L "$c/etc/nginx/sites-enabled/mqttx-web"; } && printf present || printf absent)" "$outcome" "$app/$variant enabled site reflects accepted configuration"
    check "$(test -e "$c/addons/$pending_key" && printf present || printf absent)" "$outcome" "$app/$variant install marker follows shared server acceptance"
  elif [[ "$expected" != 0 ]]; then
    check "$(cat "$c/etc/nginx/sites-available/mqttx-web" 2> /dev/null || true)" 'operator mqttx site' "$app/$variant failure retains available site"
    check "$(readlink "$c/etc/nginx/sites-enabled/mqttx-web" || true)" "$c/etc/nginx/sites-available/mqttx-web" "$app/$variant failure retains enabled site"
    check "$(cat "$c/etc/systemd/system/mqttx-web.service" 2> /dev/null || true)" 'operator unit' "$app/$variant failure retains app unit"
    check "$(cat "$c/opt/mqttx/data" 2> /dev/null || true)" 'old app' "$app/$variant failure retains app bytes"
    if [[ "$role" == install ]]; then
      check "$(stat -c %s "$c/downloads")" 0 "$app occupied site refuses before source deployment"
      check "$(stat -c %s "$c/services")" 0 "$app occupied site refuses before service effects"
    fi
  else
    check "$(test -e "$c/etc/nginx/sites-available/mqttx-web" && printf present || printf absent)" absent "$app uninstall removes owned available site"
    check "$({ test -e "$c/etc/nginx/sites-enabled/mqttx-web" || test -L "$c/etc/nginx/sites-enabled/mqttx-web"; } && printf present || printf absent)" absent "$app uninstall removes owned enabled site"
    check "$(test -e "$c/opt/mqttx" && printf present || printf absent)" absent "$app successful uninstall retires app bytes"
  fi
  check "$(find "$c/etc/nginx/sites-available" -maxdepth 1 -name '.mqttx-uninstall.*' | wc -l)" 0 "$app/$variant resolved site stage retired"
}
runtime_hooks_main "$@"
