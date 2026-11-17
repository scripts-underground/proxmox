#!/usr/bin/env bash
# shellcheck disable=SC2034,SC2154
set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/../lib/runtime-hooks/addon-release.sh"
app=webmin
release_app=webmin release_mode=binary release_asset=webmin_2_all.deb
hook_paths=(/usr/share/webmin webmin-share)
addon_release_setup() {
  printf 'var_addon_default_port=18443\n' > "$c/context.sh"
  [[ "$variant" != invalid-port ]] || printf 'var_addon_default_port=70000\n' > "$c/context.sh"
  mkdir -p "$c/webmin-share" "$c/etc/webmin"
  printf 'port=19001\nlisten=19002\nssl=1\noperator=keep\n' > "$c/etc/webmin/miniserv.conf"
  chmod 0600 "$c/etc/webmin/miniserv.conf"
  cat > "$c/webmin-share/changepass.pl" << 'MODEL'
#!/usr/bin/env bash
printf '%s\n' "$*" > "$APP_FIXTURE/password-call"
MODEL
  chmod +x "$c/webmin-share/changepass.pl"
}
addon_release_consumer_assert() { check "$(cat "$c/package-consumer")" 'selected v2.0.0' "$app selected package consumer"; }
eval "$(declare -f runtime_hooks_assert | sed '1s/runtime_hooks_assert/webmin_release_assert/')"
variants+=(fresh fresh-discovery-disabled invalid-port)
runtime_hooks_variant() {
  case "$variant" in checker) fault=checker ;; fresh-discovery-disabled) role=install fault=discovery-disabled ;; invalid-port) role=install fault=invalid-port ;; esac
}
runtime_hooks_model() {
  addon_release_model
  apt() { printf '%s\n' "$*" >> "$c/packages"; }
  _deploy_release_deb() {
    cat "$1" > "$c/package-consumer"
    if [[ "$APP_ROLE" == install ]]; then
      printf 'port=10000\nlisten=10000\nssl=1\noperator=keep\n' > "$c/etc/webmin/miniserv.conf"
      [[ "$APP_FAULT" != discovery-disabled ]] || sed -i 's/^listen=.*/listen=0/' "$c/etc/webmin/miniserv.conf"
    fi
  }
  systemctl() {
    printf '%s\n' "$*" >> "$c/services"
    if [[ "$1" == restart ]]; then cp "$c/etc/webmin/miniserv.conf" "$c/running-config"; fi
  }
}
runtime_hooks_expected() { case "$fault" in checker) expected=17 ;; invalid-port) expected=65 ;; esac }
runtime_hooks_assert() {
  if [[ "$role" != install ]]; then
    webmin_release_assert
    check "$(grep -c '^port=19001$' "$c/etc/webmin/miniserv.conf" || true)" 1 "$app/$variant update retains operator port instead of baked install default"
    check "$(grep -c '^listen=19002$' "$c/etc/webmin/miniserv.conf" || true)" 1 "$app/$variant update retains operator discovery setting"
  elif [[ "$fault" == invalid-port ]]; then
    check "$(test -e "$c/packages" && printf present || printf absent)" absent "$app invalid listener refuses before package effects"
    check "$(test -e "$c/password-call" && printf present || printf absent)" absent "$app invalid listener refuses before credential effects"
  else
    check "$(grep -c '^port=18443$' "$c/running-config" 2> /dev/null || true)" 1 "$app fresh configured TCP port reaches service consumer"
    local discovery_port=18443
    [[ "$fault" != discovery-disabled ]] || discovery_port=0
    check "$(grep -c "^listen=${discovery_port}$" "$c/running-config" 2> /dev/null || true)" 1 "$app/$variant UDP discovery follows paired port or stays disabled"
    check "$(grep -c '^ssl=1$' "$c/etc/webmin/miniserv.conf" || true)" 1 "$app fresh port selection leaves SSL untouched"
    check "$(grep -c '^operator=keep$' "$c/etc/webmin/miniserv.conf" || true)" 1 "$app port change leaves unrelated config untouched"
    check "$(stat -c %a "$c/etc/webmin/miniserv.conf")" 600 "$app port config retains package permissions"
    check "$(cat "$c/password-call")" "$c/etc/webmin root root" "$app reserved password default unchanged"
  fi
}
runtime_hooks_main "$@"
