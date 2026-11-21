#!/usr/bin/env bash
# runtime-hooks-contract: addon intent-preserving
# Completed external installer bytes, real cold commands, modeled package effects.
# shellcheck disable=SC2034,SC2154
set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/../lib/runtime-hooks/harness.sh"
app=crowdsec script_type=addon
variants=(fresh transport empty syntax installer package update uninstall cleanup-failure installer-cleanup-failure)
hook_paths=()
runtime_hooks_variant() {
  case "$variant" in
    fresh) role=install ;;
    transport | empty | syntax | installer) role=install fault=$variant ;;
    package) role=install fault=package ;;
    cleanup-failure | installer-cleanup-failure) role=install fault=$variant ;;
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
  if [[ "$APP_FAULT" == syntax ]]; then printf 'if then\n'; return 0; fi
  printf 'printf "installer entered\\n" >> "$APP_FIXTURE/installer-entries"\n'
  if [[ "$APP_FAULT" == installer || "$APP_FAULT" == installer-cleanup-failure ]]; then printf 'exit 17\n'; else
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
  rm() {
    if [[ "$APP_FAULT" == *cleanup-failure && "${!#}" == */crowdsec-installer.* ]]; then return 44; fi
    command rm "$@"
  }
  apt() {
    printf '%s\n' "$*" >> "$c/packages"
    [[ "$APP_FAULT" != package || "$*" != 'install -y crowdsec' ]] || return 43
  }
}
runtime_hooks_expected() {
  case "$fault" in transport) expected=22 ;; empty) expected=251 ;; syntax) expected=2 ;; installer | installer-cleanup-failure) expected=17 ;; package) expected=43 ;; cleanup-failure) expected=44 ;; esac
}
runtime_hooks_assert() {
  local remaining=0
  [[ "$fault" != *cleanup-failure ]] || remaining=1
  check "$(find "$c/tmp" -maxdepth 1 -name 'crowdsec-installer.*' | wc -l)" "$remaining" "$app/$variant exact installer stage outcome"
  check "$(cat "$c/etc/apt/sources.list.d/foreign.list")" 'foreign repository' "$app/$variant foreign repository retained"
  if [[ "$role" == install ]]; then
    local outcome=absent
    [[ "$fault" != none && "$fault" != package && "$fault" != cleanup-failure ]] || outcome=present
    check "$(test -f "$c/consumer" && printf present || printf absent)" "$outcome" "$app/$variant only completed successful producer executes"
    check "$(test -f "$c/addons/$pending_key" && printf present || printf absent)" "$([[ "$expected" == 0 ]] && printf present || printf absent)" "$app/$variant marker reflects actual install outcome"
    if [[ "$fault" == transport || "$fault" == empty || "$fault" == syntax || "$fault" == installer || "$fault" == *cleanup-failure ]]; then
      check "$(grep -c '^install -y crowdsec' "$c/packages" || true)" 0 "$app/$variant failed repository setup prevents app packages"
    elif [[ "$expected" == 0 ]]; then
      check "$(grep -c '^install -y crowdsec-firewall-bouncer-iptables$' "$c/packages" || true)" 1 "$app completed repository setup reaches package consumer"
    fi
    if [[ "$fault" == *cleanup-failure ]]; then
      check "$(test -f "$c/addon-owned-files/$pending_key" && printf retained || printf absent)" retained "$app/$variant stage custody survives failed cleanup"
      local recovery=0 entries
      entries=$(wc -l < "$c/installer-entries")
      runtime_hooks_invoke uninstall cleanup-failure "$c/cleanup-output" "$c/cleanup.log" "$c/cleanup-errors.log" || recovery=$?
      check "$recovery" 44 "$app/$variant cold required cleanup preserves failure"
      check "$(test -e "$c/local/sbin/uninstall" && printf retained || printf absent)" retained "$app/$variant failed cleanup keeps command"
      check "$(test -f "$c/addon-owned-files/$pending_key" && printf retained || printf absent)" retained "$app/$variant failed cleanup keeps custody"
      printf 'foreign stage\n' > "$c/tmp/crowdsec-installer.foreign"
      recovery=0
      runtime_hooks_invoke uninstall none "$c/recover-output" "$c/recover.log" "$c/recover-errors.log" || recovery=$?
      check "$recovery" 0 "$app/$variant cold exact cleanup succeeds"
      check "$(wc -l < "$c/installer-entries")" "$entries" "$app/$variant cleanup never repeats installer"
      check "$(find "$c/tmp" -maxdepth 1 -name 'crowdsec-installer.*' | wc -l)" 1 "$app/$variant only unrelated stage remains"
      check "$(cat "$c/tmp/crowdsec-installer.foreign")" 'foreign stage' "$app/$variant unrelated stage untouched"
      local item
      for item in local/sbin/update local/sbin/uninstall "addon-owned-files/$pending_key"; do
        check "$(test -e "$c/$item" && printf present || printf absent)" absent "$app/$variant recovery retires $item"
      done
    fi
  elif [[ "$role" == update ]]; then
    check "$(cat "$c/packages")" $'update\ninstall --only-upgrade -y crowdsec crowdsec-firewall-bouncer-iptables' "$app update retains package-owned lifecycle"
  else
    check "$(cat "$c/packages")" 'remove --purge -y crowdsec crowdsec-firewall-bouncer-iptables' "$app uninstall retains package-owned lifecycle"
    check "$(test -e "$c/etc/apt/sources.list.d/crowdsec_crowdsec.list" && printf present || printf absent)" absent "$app uninstall removes only owned repository"
  fi
}
runtime_hooks_main "$@"
