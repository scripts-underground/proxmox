#!/usr/bin/env bash
# Actual init abstraction, actual hooks and generated owners. External service
# commands are source-characterized models (OpenRC0.62/systemd257), not app installs.
set -euo pipefail
systemd-detect-virt --vm --quiet || exit 1
: "${TMPDIR:?disk-backed TMPDIR required}"
case "$(realpath -e "$TMPDIR")" in /tmp | /tmp/*) exit 1 ;; esac
case "$(findmnt -rn -T "$TMPDIR" -o FSTYPE)" in '' | tmpfs | ramfs) exit 1 ;; esac
ROOT=$(realpath "$(dirname "${BASH_SOURCE[0]}")/..")
work=$(mktemp -d "$TMPDIR/maintenance-service-uninstall.XXXXXX")
trap 'rm -rf -- "$work"' EXIT
failures=0
check() {
  if [[ "$1" == "$2" ]]; then printf 'PASS %s\n' "$3"; else
    printf 'FAIL %s: expected <%s>, got <%s>\n' "$3" "$2" "$1" >&2
    failures=$((failures + 1))
  fi
}
cat > "$work/model.sh" << 'MODEL'
header_info() { :; }
systemctl() {
  printf 'systemctl %s\n' "$*" >> "$CASE_ROOT/calls"
  local verb="$1" unit="${@: -1}" state
  case "$verb" in -q) verb="$2" ;; esac
  unit=${unit%.service}
  case "$verb" in
    show)
      case "$FAULT" in query-one) return 1 ;; query) return 47 ;; second-query) [[ "$unit" != scanopy-server ]] || return 47 ;; malformed) printf 'LoadState=loaded\nActiveState=unknown\nUnitFileState=enabled\n'; return 0 ;; esac
      if [[ ! -e "$CASE_ROOT/units/$unit.service" ]]; then
        printf 'LoadState=not-found\nActiveState=inactive\nUnitFileState=\n'
      else
        state=active
        [[ ! -e "$CASE_ROOT/stopped" && ! -e "$CASE_ROOT/stopped-$unit" ]] || state=inactive
        printf 'LoadState=loaded\nActiveState=%s\nUnitFileState=' "$state"
        if [[ -e "$CASE_ROOT/enabled" && ! -e "$CASE_ROOT/disabled-$unit" ]]; then printf 'enabled\n'; else printf 'disabled\n'; fi
      fi
      ;;
    stop | disable)
      [[ -e "$CASE_ROOT/units/$unit.service" ]] || return 1
      if [[ "$verb" == stop || " $* " == *' --now '* ]]; then
        [[ "$FAULT" != stop ]] || return 48
        [[ "$FAULT:$unit" != second-stop:scanopy-server ]] || return 48
        : > "$CASE_ROOT/stopped-$unit"
      fi
      if [[ "$verb" == disable ]]; then
        [[ "$FAULT" != disable ]] || return 49
        : > "$CASE_ROOT/disabled-$unit"
      fi
      ;;
    restart)
      [[ -e "$CASE_ROOT/units/$unit.service" ]] || return 5
      [[ "$FAULT" != restart ]] || return 51
      rm -f "$CASE_ROOT/stopped" "$CASE_ROOT/stopped-$unit"
      ;;
    daemon-reload) : ;;
    *) return 97 ;;
  esac
}
rc-service() {
  printf 'rc-service %s\n' "$*" >> "$CASE_ROOT/calls"
  if [[ "$1" == --list ]]; then
    case "$FAULT" in query-one) return 1 ;; query) return 47 ;; empty-list) return 0 ;; malformed) printf 'not a service name\n'; return 0 ;; esac
    printf 'other-service\n'
    [[ ! -e "$CASE_ROOT/units/$SERVICE.service" ]] || printf '%s\n' "$SERVICE"
    return 0
  fi
  [[ -e "$CASE_ROOT/units/$1.service" ]] || return 1
  case "$2" in
    status)
      [[ "$FAULT" != status-query ]] || return 46
      case "$FAULT" in state4) return 4 ;; state8) return 8 ;; state16) return 16 ;; state32) return 32 ;; esac
      [[ ! -e "$CASE_ROOT/stopped" ]] || return 3
      return 0
      ;;
    stop)
      [[ "$FAULT" != stop ]] || return 48
      : > "$CASE_ROOT/stopped"
      ;;
    restart)
      [[ "$FAULT" != restart ]] || return 51
      rm -f "$CASE_ROOT/stopped"
      ;;
    *) return 97 ;;
  esac
}
rc-status() {
  printf 'rc-status %s\n' "$*" >> "$CASE_ROOT/calls"
  [[ "$FAULT" != runlevel-query ]] || return 50
  printf 'default\n'
}
rc-update() {
  printf 'rc-update %s\n' "$*" >> "$CASE_ROOT/calls"
  case "$1" in
    show)
      [[ "$FAULT" != registration-query ]] || return 45
      [[ "$FAULT" != runlevel-query ]] || return 50
      if [[ "$FAULT" == registration-malformed ]]; then printf 'not a registration\n'; return 0; fi
      [[ ! -e "$CASE_ROOT/enabled" ]] || printf ' %s | default\n' "$SERVICE"
      ;;
    del)
      [[ "$FAULT" != disable ]] || return 49
      [[ -e "$CASE_ROOT/enabled" ]] || return 1
      rm -f "$CASE_ROOT/enabled"
      ;;
    *) return 97 ;;
  esac
}
MODEL
sed -n '/^svc_enable() {/,/^# SECTION 4:/p' "$ROOT/misc/install.func" > "$work/init.func"
if grep -q '^svc_prepare_uninstall() {' "$work/init.func"; then
  source "$ROOT/misc/core.func"
  source "$work/init.func"
  source "$work/model.sh"
  load_functions
  for init in systemd openrc; do
    for mode in no yes; do
      for direct_case in stop-only state4 state8 state16 state32 empty-list registration-malformed; do
        [[ "$init" == openrc || "$direct_case" == stop-only ]] || continue
        c="$work/helper-$init-$mode-$direct_case"
        mkdir -p "$c/units" "$c/tmp"
        : > "$c/units/custom-maint-service.service"
        : > "$c/enabled"
        export CASE_ROOT="$c" SERVICE=custom-maint-service FAULT="$direct_case" INIT_SYSTEM="$init" VERBOSE="$mode" BUILD_LOG="$c/direct.log"
        set_std_mode
        action=disable
        [[ "$direct_case" != stop-only ]] || action=stop
        rc=0 before_running=stale
        svc_prepare_uninstall "$SERVICE" "$action" before_running > "$c/output" 2>&1 || rc=$?
        expected=0
        case "$direct_case" in empty-list | registration-malformed) expected=22 ;; esac
        check "$rc" "$expected" "helper/$init/$mode/$direct_case exact status"
        if [[ "$expected" == 0 ]]; then
          check "$(if [[ -e "$c/stopped" || -e "$c/stopped-$SERVICE" ]]; then printf stopped; else printf active; fi)" stopped "helper/$init/$mode/$direct_case service quiesced"
          if [[ "$direct_case" == stop-only ]]; then
            check "$(test -e "$c/enabled" && printf enabled || printf disabled)" enabled "helper/$init/$mode stop-only retains registration"
            check "$before_running" yes "helper/$init/$mode returns actual prior-running state"
          fi
        fi
      done
    done
  done
fi
for app in actual-budget-prometheus-exporter adguardhome-sync phpmyadmin netvisor; do
  script="$ROOT/scripts/addon/$app.sh"
  [[ "$app" != netvisor ]] || script="$ROOT/scripts/lxc/netvisor.sh"
  for init in systemd openrc; do
    [[ "$init" != openrc || "$app" == adguardhome-sync || "$app" == phpmyadmin ]] || continue
    for mode in no yes; do
      for fault in absent stopped disabled query-one query malformed stop disable status-query runlevel-query registration-query restart second-stop second-query none; do
        # Shared Apache must only stop, never disable.
        [[ "$app:$init:$fault" != phpmyadmin:systemd:disable ]] || continue
        case "$fault" in status-query | runlevel-query | registration-query) [[ "$init" == openrc ]] || continue ;; restart) [[ "$app:$init" == phpmyadmin:systemd ]] || continue ;; second-stop | second-query) [[ "$app" == netvisor ]] || continue ;; esac
        c="$work/$app-$init-$mode-$fault"
        mkdir -p "$c"/{stage,sbin,bin,markers,app,units,home,tmp,lighttpd}
        printf 'retained app bytes\n' > "$c/app/data"
        printf 'retained config\n' > "$c/config"
        printf 'lighttpd app config\n' > "$c/lighttpd/lighttpd.conf"
        : > "$c/markers/$app"
        service=custom-maint-service
        case "$app" in actual-budget-prometheus-exporter) service="$app" ;; phpmyadmin)
          service=apache2
          [[ "$init" != openrc ]] || service=lighttpd
          ;;
        netvisor) service=scanopy-server ;; esac
        : > "$c/units/$service.service"
        [[ "$app" != netvisor ]] || : > "$c/units/scanopy-daemon.service"
        : > "$c/enabled"
        case "$fault" in absent) rm -f "$c/units/"* ;; stopped) : > "$c/stopped" ;; disabled)
          : > "$c/stopped"
          rm -f "$c/enabled"
          ;;
        esac
        cp "$ROOT/misc/core.func" "$c/stage/core.func"
        cp "$ROOT/misc/error_handler.func" "$c/stage/error_handler.func"
        sed -n '/^svc_enable() {/,/^# SECTION 4:/p' "$ROOT/misc/install.func" > "$c/stage/install.func"
        printf '\npkg_install() { :; }; setup_lxc() { :; }\n' >> "$c/stage/install.func"
        printf 'setup_uv() { :; }; fetch_and_deploy_gh_release() { :; }\n' > "$c/stage/tools.func"
        printf 'clone_and_deploy_gh_commit() { :; }\n' > "$c/stage/github.func"
        cat "$work/model.sh" >> "$c/stage/github.func"
        printf 'addon_baseline() { :; }\n' > "$c/stage/addon.func"
        sed -n '/^function uninstall_script() {/,/^}/p' "$script" |
          sed -e "s|/etc/systemd/system|$c/units|g" -e "s|/etc/init.d|$c/units|g" -e "s|/etc/lighttpd|$c/lighttpd|g" \
            -e "s|/opt/scanopy|$c/app|g" -e "s|/usr/bin/scanopy|$c/bin/scanopy|g" > "$c/hook.sh"
        (
          export APP="$app" APP_SLUG="$app" NSAPP="$app" REPO_BASE=offline CTID=2110 SESSION_ID=l2
          export ADDON_MARKER_DIR="$c/markers" TMPDIR="$c/tmp" var_lxc_tmpdir="$c/tmp"
          export var_addon_service="$service" var_addon_install_path="$c/app" var_addon_config_path="$c/config"
          export var_addon_service_path="$c/units/$service.service" var_addon_install_dir_debian="$c/app" var_addon_install_dir_alpine="$c/app"
          source "$c/hook.sh"
          if [[ "$app" != netvisor ]]; then
            sed -e "s|/usr/local/sbin|$c/sbin|g" -e "s|/usr/bin|$c/bin|g" "$ROOT/misc/addon_lxc.func" > "$c/owner.func"
            source "$c/owner.func"
            _addon_bundle_write uninstall uninstall_script "$c/stage"
          else
            sed -e "s|/usr/local/sbin|$c/sbin|g" -e "s|/usr/bin|$c/bin|g" "$ROOT/misc/bundle.func" > "$c/owner.func"
            source "$c/owner.func"
            _framework_cache_ensure() { :; }
            _framework_cache_dir() { printf '%s\n' "$c/stage"; }
            msg_debug() { :; }
            pct() { case "$1" in push) cp -- "$3" "$4" ;; exec)
              shift 3
              command "$@"
              ;;
            esac }
            build_bundle uninstall uninstall_script "$c/sbin/uninstall_$app" 0755
          fi
        ) > "$c/generate-output" 2>&1
        cp "$c/sbin/uninstall_$app" "$c/rerun"
        rc=0
        family=debian
        [[ "$init" != openrc ]] || family=alpine
        env -i PATH="$PATH" TMPDIR="$c/tmp" HOME="$c/home" CASE_ROOT="$c" SERVICE="$service" FAULT="$fault" INIT_SYSTEM="$init" OS_FAMILY="$family" \
          VERBOSE="$mode" BUILD_LOG="$c/active.log" DEBUG_LOGFILE="$c/error.log" bash "$c/sbin/uninstall_$app" > "$c/output" 2>&1 || rc=$?
        expected=0
        case "$fault" in query-one) expected=1 ;; query | second-query) expected=47 ;; malformed) expected=22 ;; stop | second-stop) expected=48 ;; disable) expected=49 ;; status-query) expected=46 ;; runlevel-query) expected=50 ;; registration-query) expected=45 ;; restart) expected=51 ;; esac
        label="$app/$init/$mode/$fault"
        check "$rc" "$expected" "$label actual generated uninstall status"
        if [[ "$expected" != 0 ]]; then
          for path in app/data sbin/uninstall_"$app"; do check "$(test -e "$c/$path" && printf present || printf absent)" present "$label retains $path"; done
          [[ "$app" == netvisor ]] || check "$(test -e "$c/markers/$app" && printf present || printf absent)" present "$label retains installed marker"
          check "$(grep -c "exit code $expected" "$c/active.log" || true)" 1 "$label logs exact fatal status"
          check "$(cat "$c/app/data" 2> /dev/null || true)" 'retained app bytes' "$label preserves actual prior bytes"
        else
          check "$(test -e "$c/app/data" && printf present || printf absent)" absent "$label removes owned app only after service preparation"
          check "$(test -e "$c/sbin/uninstall_$app" && printf present || printf absent)" absent "$label returns to success-only command cleanup"
          if [[ "$app:$init" == phpmyadmin:systemd && "$fault" != none ]]; then
            check "$(grep -c '^systemctl restart' "$c/calls" || true)" 0 "$label never starts absent/stopped shared Apache"
          fi
          if [[ "$app:$init" == phpmyadmin:openrc ]]; then
            check "$(grep -c 'rc-service .* restart' "$c/calls" || true)" 0 "$label never restarts removed Lighttpd or shared PHP-FPM"
          fi
          if [[ "$app:$fault" == netvisor:none ]]; then
            check "$(test -e "$c/stopped-scanopy-daemon" && test -e "$c/stopped-scanopy-server" && printf both || printf missing)" both "$label independently stops both actual hook service consumers"
          fi
          if [[ "$fault" == none || "$fault" == absent || "$fault" == disabled ]]; then
            rc=0
            env -i PATH="$PATH" TMPDIR="$c/tmp" HOME="$c/home" CASE_ROOT="$c" SERVICE="$service" FAULT=none INIT_SYSTEM="$init" OS_FAMILY="$family" \
              VERBOSE="$mode" BUILD_LOG="$c/rerun.log" DEBUG_LOGFILE="$c/rerun-error.log" bash "$c/rerun" > "$c/rerun-output" 2>&1 || rc=$?
            check "$rc" 0 "$label successful saved hook rerun is idempotent"
          fi
        fi
      done
    done
  done
done
python3 - "$ROOT" << 'PY'
import pathlib,re,subprocess,sys
p=pathlib.Path(sys.argv[1]);names=('actual-budget-prometheus-exporter adguardhome-sync coder-code-server copyparty cronmaster dockge filebrowser-quantum filebrowser glances immich-public-proxy jellystat mqttx nextcloud-exporter olivetin phpmyadmin pihole-exporter portainer prometheus-paperless-ngx-exporter qbittorrent-exporter sparkyfitness-garmin webmin').split()
paths=[p/'scripts/addon'/f'{n}.sh' for n in names]+[p/'scripts/lxc/netvisor.sh']
for f in paths:
 s=re.search(r'^function uninstall_script\(\) \{\n.*?^\}',f.read_text(),re.M|re.S)[0]
 assert 'svc_prepare_uninstall ' in s,str(f)
 assert not re.search(r'(systemctl[^\n]*(?:stop|disable)|rc-service[^\n]*stop|rc-update[^\n]*del)[^\n]*\|\| true',s),str(f)
 if f.stem=='netvisor':assert not re.search(r'^\s*exit\b',s,re.M)
print('L2_ALL_22_CALLERS_ADOPTED=0')
current=(p/'misc/install.func').read_text();old=subprocess.check_output(['git','show','HEAD:misc/install.func'],cwd=p,text=True)
for name in ('svc_enable','svc_disable','svc_start','svc_stop','svc_restart','svc_status','svc_reload_daemon'):
 pattern=rf'^{name}\(\) \{{\n.*?^\}}'
 assert re.search(pattern,current,re.M|re.S)[0]==re.search(pattern,old,re.M|re.S)[0],name
for name in ('arcane','coolify','crowdsec','dokploy','homebrew','komodo','pyenv','runtipi'):
 file=f'scripts/addon/{name}.sh';old=subprocess.check_output(['git','show',f'HEAD:{file}'],cwd=p,text=True)
 pattern=r'^function uninstall_script\(\) \{\n.*?^\}'
 assert re.search(pattern,(p/file).read_text(),re.M|re.S)[0]==re.search(pattern,old,re.M|re.S)[0],file
print('L2_EXISTING_HELPERS_AND_OTHER_8_HOOKS_UNCHANGED=0')
PY
printf '%s failure(s); native helpers/hooks/bundles/files/statuses, service commands modeled\n' "$failures"
[[ "$failures" == 0 ]]
