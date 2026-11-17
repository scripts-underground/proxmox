#!/usr/bin/env bash
# Completed external installer bytes, real cold commands, modeled package effects.
# shellcheck disable=SC2034,SC2154
set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/../lib/runtime-hooks/harness.sh"
app=crowdsec script_type=addon
variants=(fresh transport empty installer package update uninstall)
hook_paths=()
runtime_hooks_variant() {
  case "$variant" in
    fresh) role=install ;;
    transport | empty | installer) role=install fault=$variant ;;
    package) role=install fault=package ;;
    uninstall) role=uninstall ;;
  esac
}
runtime_hooks_setup() {
  mkdir -p "$c/bin" "$c/etc/apt/sources.list.d"
  : > "$c/packages"
  printf 'foreign repository\n' > "$c/etc/apt/sources.list.d/foreign.list"
  printf 'owned repository\n' > "$c/etc/apt/sources.list.d/crowdsec_crowdsec.list"
  cat > "$c/bin/curl" << 'MODEL'
#!/usr/bin/env bash
set -euo pipefail
out=''
while (($#)); do
  if [[ "$1" == -o ]]; then out=$2; shift; fi
  shift
done
emit() {
  [[ "$APP_FAULT" != empty ]] || return 0
  if [[ "$APP_FAULT" == installer ]]; then printf 'exit 17\n'; else
    printf 'printf "repository configured\\n" > "$APP_FIXTURE/consumer"\n'
  fi
}
if [[ -n "$out" ]]; then emit > "$out"; else emit; fi
[[ "$APP_FAULT" != transport ]] || exit 22
MODEL
  chmod +x "$c/bin/curl"
}
runtime_hooks_model() {
  export PATH="$c/bin:$PATH"
  apt() {
    printf '%s\n' "$*" >> "$c/packages"
    [[ "$APP_FAULT" != package || "$*" != 'install -y crowdsec' ]] || return 43
  }
}
runtime_hooks_expected() {
  case "$fault" in transport) expected=22 ;; empty) expected=251 ;; installer) expected=17 ;; package) expected=43 ;; esac
}
runtime_hooks_assert() {
  check "$(find "$c/tmp" -maxdepth 1 -name 'crowdsec-installer.*' | wc -l)" 0 "$app/$variant owned installer stage retired"
  check "$(cat "$c/etc/apt/sources.list.d/foreign.list")" 'foreign repository' "$app/$variant foreign repository retained"
  if [[ "$role" == install ]]; then
    local outcome=absent
    [[ "$fault" != none && "$fault" != package ]] || outcome=present
    check "$(test -f "$c/consumer" && printf present || printf absent)" "$outcome" "$app/$variant only completed successful producer executes"
    check "$(test -f "$c/addons/$pending_key" && printf present || printf absent)" "$([[ "$expected" == 0 ]] && printf present || printf absent)" "$app/$variant marker reflects actual install outcome"
    if [[ "$fault" == transport || "$fault" == empty || "$fault" == installer ]]; then
      check "$(grep -c '^install -y crowdsec' "$c/packages" || true)" 0 "$app/$variant failed repository setup prevents app packages"
    elif [[ "$expected" == 0 ]]; then
      check "$(grep -c '^install -y crowdsec-firewall-bouncer-iptables$' "$c/packages" || true)" 1 "$app completed repository setup reaches package consumer"
    fi
  elif [[ "$role" == update ]]; then
    check "$(cat "$c/packages")" $'update\ninstall --only-upgrade -y crowdsec crowdsec-firewall-bouncer-iptables' "$app update retains package-owned lifecycle"
  else
    check "$(cat "$c/packages")" 'remove --purge -y crowdsec crowdsec-firewall-bouncer-iptables' "$app uninstall retains package-owned lifecycle"
    check "$(test -e "$c/etc/apt/sources.list.d/crowdsec_crowdsec.list" && printf present || printf absent)" absent "$app uninstall removes only owned repository"
  fi
}
runtime_hooks_main "$@"
