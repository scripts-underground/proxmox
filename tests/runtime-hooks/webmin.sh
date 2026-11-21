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
eval "$(declare -f runtime_hooks_failure_services_assert | sed '1s/runtime_hooks_failure_services_assert/webmin_failure_services_assert/')"
runtime_hooks_failure_services_assert() {
  if [[ "$role" == install && "$fault" == listener-* ]]; then
    local attempts=2
    [[ "$fault" != listener-inactive && "$fault" != listener-concurrent ]] || attempts=1
    check "$(grep -Ec '^(start|reload|restart)' "$c/services" || true)" "$attempts" "$app/$variant bounded restart/recovery attempts"
  else webmin_failure_services_assert; fi
}
variants+=(fresh fresh-discovery-disabled invalid-port fresh-spaced fresh-independent fresh-no-port fresh-crlf listener-failure listener-inactive listener-concurrent listener-recovery-failure)
runtime_hooks_variant() {
  case "$variant" in
    checker) fault=checker ;;
    fresh-discovery-disabled) role=install fault=discovery-disabled ;;
    invalid-port) role=install fault=invalid-port ;;
    fresh-* | listener-*) role=install fault=$variant ;;
  esac
}
runtime_hooks_model() {
  addon_release_model
  apt() { printf '%s\n' "$*" >> "$c/packages"; }
  _deploy_release_deb() {
    cat "$1" > "$c/package-consumer"
    if [[ "$APP_ROLE" == install ]]; then
      printf 'port=10000\nlisten=10000\nssl=1\noperator=keep\n' > "$c/etc/webmin/miniserv.conf"
      [[ "$APP_FAULT" != discovery-disabled ]] || sed -i 's/^listen=.*/listen=0/' "$c/etc/webmin/miniserv.conf"
      case "$APP_FAULT" in
        fresh-spaced) printf '  port = 10000  \n listen = 10000 \nssl=1\noperator=keep\n' > "$c/etc/webmin/miniserv.conf" ;;
        fresh-independent) printf ' port = 10000 \n listen = 19002 \nssl=1\noperator=keep\n' > "$c/etc/webmin/miniserv.conf" ;;
        fresh-no-port) printf 'listen=0\nssl=1\noperator=keep' > "$c/etc/webmin/miniserv.conf" ;;
        fresh-crlf) printf 'listen=0\r\nssl=1\r\noperator=keep' > "$c/etc/webmin/miniserv.conf" ;;
      esac
      cp -p "$c/etc/webmin/miniserv.conf" "$c/previous-config"
      cp "$c/previous-config" "$c/running-config"
      printf 'active\n' > "$c/listener-state"
      [[ "$APP_FAULT" != listener-inactive ]] || printf 'inactive\n' > "$c/listener-state"
    fi
  }
  systemctl() {
    printf '%s\n' "$*" >> "$c/services"
    if [[ "$1" == show ]]; then
      [[ "${!#}" == webmin ]] || return 4
      cat "$c/listener-state"
    elif [[ "$1" == restart ]]; then
      [[ "${!#}" == webmin ]] || return 4
      if [[ "$APP_FAULT" == listener-* && ! -e "$c/listener-failed" ]]; then
        : > "$c/listener-failed"
        printf 'failed\n' > "$c/listener-state"
        [[ "$APP_FAULT" != listener-concurrent ]] || printf 'operator=concurrent\n' >> "$c/etc/webmin/miniserv.conf"
        return 48
      fi
      [[ "$APP_FAULT" != listener-recovery-failure ]] || return 49
      cp "$c/etc/webmin/miniserv.conf" "$c/running-config"
      printf 'active\n' > "$c/listener-state"
    fi
  }
}
runtime_hooks_expected() { case "$fault" in checker) expected=17 ;; invalid-port) expected=65 ;; listener-*) expected=48 ;; esac }
webmin_config_value() {
  perl -e 'my ($file,$key)=@ARGV; open my $f,"<",$file or exit 1; my %v; while (<$f>) { s/[\r\n]//g; next if /^#/ || !/\S/; if (/^([^=]+)=(.*)$/) { my ($k,$v)=($1,$2); s/^\s+|\s+$//g for ($k,$v); $v{$k}=$v; } } print $v{$key}//"";' "$1" "$2"
}
runtime_hooks_assert() {
  if [[ "$role" != install ]]; then
    webmin_release_assert
    check "$(grep -c '^port=19001$' "$c/etc/webmin/miniserv.conf" || true)" 1 "$app/$variant update retains operator port instead of baked install default"
    check "$(grep -c '^listen=19002$' "$c/etc/webmin/miniserv.conf" || true)" 1 "$app/$variant update retains operator discovery setting"
  elif [[ "$fault" == invalid-port ]]; then
    check "$(test -e "$c/packages" && printf present || printf absent)" absent "$app invalid listener refuses before package effects"
    check "$(test -e "$c/password-call" && printf present || printf absent)" absent "$app invalid listener refuses before credential effects"
    check "$(cat "$c/package-consumer")" 'old package' "$app invalid listener refuses binary package deployment"
  elif [[ "$fault" == listener-* ]]; then
    local desired=active
    [[ "$fault" != listener-inactive && "$fault" != listener-concurrent && "$fault" != listener-recovery-failure ]] || desired=failed
    check "$(cat "$c/listener-state")" "$desired" "$app/$variant prior activity recovered only with owned rollback"
    if [[ "$fault" != listener-concurrent ]]; then
      check "$(cmp -s "$c/previous-config" "$c/etc/webmin/miniserv.conf" && printf same || printf changed)" same "$app/$variant complete prior configuration restored"
    else
      check "$(grep -c '^operator=concurrent$' "$c/etc/webmin/miniserv.conf" || true)" 1 "$app concurrent operator edit retained"
      check "$(find "$c/etc/webmin" -maxdepth 1 -type d -name '.addon-listener.*' | wc -l)" 1 "$app conflict retains exact recovery stage"
    fi
    [[ "$desired" != active ]] || check "$(cmp -s "$c/previous-config" "$c/running-config" && printf same || printf changed)" same "$app rollback reaches old listener consumer"
    check "$(test -e "$c/addons/$pending_key" && printf present || printf absent)" absent "$app listener failure never certifies completed install"
  else
    check "$(webmin_config_value "$c/running-config" port)" 18443 "$app fresh configured TCP port reaches service consumer"
    local discovery_port=18443
    case "$fault" in discovery-disabled | fresh-no-port | fresh-crlf) discovery_port=0 ;; fresh-independent) discovery_port=19002 ;; esac
    check "$(webmin_config_value "$c/running-config" listen)" "$discovery_port" "$app/$variant UDP discovery follows paired port or stays disabled"
    check "$(webmin_config_value "$c/etc/webmin/miniserv.conf" ssl)" 1 "$app fresh port selection leaves SSL untouched"
    check "$(tr -d '\r' < "$c/etc/webmin/miniserv.conf" | grep -c '^operator=keep$' || true)" 1 "$app port change leaves unrelated config untouched"
    if [[ "$fault" == fresh-crlf ]]; then
      check "$(python3 -c 'import sys; b=open(sys.argv[1],"rb").read(); print(int(b.endswith(b"\r\nport=18443\r\n") and b.replace(b"\r\n",b"").find(b"\n")==-1))' "$c/etc/webmin/miniserv.conf")" 1 "$app appended port preserves CRLF boundaries"
    fi
    check "$(stat -c %a "$c/etc/webmin/miniserv.conf")" 600 "$app port config retains package permissions"
    check "$(cat "$c/password-call")" "$c/etc/webmin root root" "$app reserved password default unchanged"
  fi
  if [[ "$role" == install && "$fault" != listener-concurrent && "$fault" != listener-recovery-failure ]]; then
    check "$(find "$c/etc/webmin" -maxdepth 1 -type d -name '.addon-listener.*' | wc -l)" 0 "$app/$variant resolved listener stages retired"
  fi
}
runtime_hooks_main "$@"
