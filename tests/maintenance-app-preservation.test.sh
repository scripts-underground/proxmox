#!/usr/bin/env bash
# Actual update hooks, release deployer and update owner. Filesystem/pending/data
# outcomes are native; only external downloads/build/runtime/service commands model.
set -euo pipefail
systemd-detect-virt --vm --quiet || exit 1
: "${TMPDIR:?disk-backed TMPDIR required}"
case "$(realpath -e "$TMPDIR")" in /tmp | /tmp/*) exit 1 ;; esac
case "$(findmnt -rn -T "$TMPDIR" -o FSTYPE)" in '' | tmpfs | ramfs) exit 1 ;; esac
ROOT=$(realpath "$(dirname "${BASH_SOURCE[0]}")/..")
if [[ "${1:-}" == --child ]]; then
  c="$CASE_ROOT"
  mount --bind "$c/opt" /opt
  mount --bind "$c/app" "/opt/$APP_SLUG"
  mount --bind "$c/state" /var/lib/scripts-underground/update-pending
  source "$ROOT/misc/core.func"
  source "$ROOT/misc/error_handler.func"
  source "$ROOT/misc/tools.func"
  load_functions
  source "$c/update.sh"
  header_info() { :; }
  check_container_storage() { :; }
  check_container_resources() { :; }
  cleanup_lxc() { :; }
  check_for_gh_release() { return 0; }
  setup_ruby() { :; }
  ensure_dependencies() { :; }
  getent() { return 0; }
  systemctl() {
    printf '%s\n' "$*" >> "$c/services"
    if [[ "$1" == start || "$1" == reload ]]; then
      find "$c/app" -type f \( -name row -o -name config.yaml -o -name conf.php \) -exec cat {} \; > "$c/service-consumer"
    fi
  }
  curl() {
    local out='' format=''
    while (($#)); do
      case "$1" in -o)
        out="$2"
        shift
        ;;
      -w)
        format="$2"
        shift
        ;;
      esac
      shift
    done
    printf '{"tag_name":"v2.0.0","assets":[{"name":"CLIProxyAPI_2_linux_amd64.tar.gz","browser_download_url":"https://fixture.invalid/CLIProxyAPI_2_linux_amd64.tar.gz"}]}' > "$out"
    [[ -z "$format" ]] || printf 200
  }
  curl_download() {
    printf 'download\n' >> "$c/downloads"
    command cp "$c/source.tar.gz" "$1"
  }
  npm() {
    printf 'npm %s\n' "$*" >> "$c/builds"
    [[ "$FAULT" != build ]] || return 51
  }
  cp() {
    if [[ "$FAULT" == copy && ("${!#}" == "$c/app/"* || "${!#}" == "/opt/$APP_SLUG/"*) ]]; then
      printf partial > "$c/app/code"
      return 41
    fi
    command cp "$@"
  }
  # Existing backup implementation is real; its owned store and obsolete literal
  # PrivateBin backup destination are both fixture paths for safe baseline RED.
  export BACKUP_DIR="$c/backups" NSAPP="$APP_SLUG"
  catch_errors
  run_update_script
fi
work=$(mktemp -d "$TMPDIR/maintenance-apps.XXXXXX")
trap 'rm -rf -- "$work"' EXIT
failures=0
check() {
  if [[ "$1" == "$2" ]]; then printf 'PASS %s\n' "$3"; else
    printf 'FAIL %s: expected <%s>, got <%s>\n' "$3" "$2" "$1" >&2
    failures=$((failures + 1))
  fi
}
for app in cliproxyapi sure privatebin bytestash; do
  for mode in no yes; do
    for fault in none copy build missing-config; do
      [[ "$fault" != build || "$app" == sure || "$app" == bytestash ]] || continue
      [[ "$fault" != missing-config || "$app" == cliproxyapi || "$app" == privatebin ]] || continue
      c="$work/$app-$mode-$fault"
      mkdir -p "$c/"{app,archive/package,home,tmp,state,units,external-data,backups}
      mkdir -p "$c/opt/$app"
      mkdir -p "$c/app/"{data,plugins,cfg,storage} "$c/archive/package/"{data,plugins,cfg,storage,server,client,bin}
      for path in data/row plugins/row cfg/conf.php storage/row config.yaml; do
        printf 'USER %s\n' "$path" > "$c/app/$path"
        printf 'DEFAULT %s\n' "$path" > "$c/archive/package/$path"
      done
      printf 'USER legacy db\n' > "$c/external-data/row"
      mkdir -p "$c/backups/files$c/external-data"
      printf 'stale legacy db\n' > "$c/backups/files$c/external-data/row"
      printf '%s\n' "$c/external-data" > "$c/backups/.manifest"
      printf 'custom JWT/port/registration\n' > "$c/units/bytestash-backend.service"
      : > "$c/units/sure-worker.service"
      printf 'custom external settings\n' > "$c/settings"
      : > "$c/services"
      : > "$c/downloads"
      printf 'old code\n' > "$c/app/code"
      printf 'new code\n' > "$c/archive/package/code"
      printf '3.4.0\n' > "$c/archive/package/.ruby-version"
      printf 'fixture\n' > "$c/archive/package/server/package.json"
      printf 'fixture\n' > "$c/archive/package/client/package.json"
      printf '#!/usr/bin/env bash\nprintf "bundle %%s\\n" "$*" >> "$CASE_ROOT/builds"\n[[ "$FAULT" != build ]] || exit 51\n' > "$c/archive/package/bin/bundle"
      printf '#!/usr/bin/env bash\nexit 0\n' > "$c/archive/package/bin/rails"
      chmod 0755 "$c/archive/package/bin/"*
      chmod 0700 "$c/app/data" "$c/app/storage"
      chmod 0640 "$c/app/config.yaml" "$c/app/cfg/conf.php"
      if [[ "$fault" == missing-config ]]; then
        if [[ "$app" == privatebin ]]; then rm "$c/app/cfg/conf.php"; else rm "$c/app/config.yaml"; fi
      fi
      printf '# fixture profile\n' > "$c/home/.profile"
      printf 'old\n' > "$c/home/.$app"
      tar -czf "$c/source.tar.gz" -C "$c/archive" package
      sed -n '/^function update_script() {/,/^}/p' "$ROOT/scripts/lxc/$app.sh" |
        sed -e "s|/opt/$app|$c/app|g" -e "s|/opt/data|$c/external-data|g" -e "s|/etc/systemd/system|$c/units|g" \
          -e "s|/tmp/privatebin_conf.bak|$c/obsolete-conf.bak|g" > "$c/update.sh"
      protected_data_path='data/row'
      [[ "$app" != sure ]] || protected_data_path=storage/row
      before=$(stat -c '%d:%i:%a:%u:%g:%Y' "$c/app/$protected_data_path")
      before_dir=$(stat -c '%d:%i:%a:%u:%g:%Y' "$(dirname "$c/app/$protected_data_path")")
      legacy_before=$(stat -c '%d:%i:%a:%u:%g:%Y' "$c/external-data/row")
      rc=0
      env -i PATH="$PATH" HOME="$c/home" TMPDIR="$c/tmp" CASE_ROOT="$c" APP="$app" APP_SLUG="$app" FAULT="$fault" VERBOSE="$mode" \
        BUILD_LOG="$c/helper.log" DEBUG_LOGFILE="$c/error.log" unshare -m --propagation private -- bash "$0" --child > "$c/output" 2>&1 || rc=$?
      expected=0
      case "$fault" in copy) expected=252 ;; build) expected=51 ;; missing-config) expected=1 ;; esac
      check "$rc" "$expected" "$app/$mode/$fault actual hook/owner status"
      check "$(cat "$c/app/$protected_data_path" 2> /dev/null || true)" "USER $protected_data_path" "$app/$mode/$fault stored data bytes"
      check "$(stat -c '%d:%i:%a:%u:%g:%Y' "$c/app/$protected_data_path")" "$before" "$app/$mode/$fault data identity/metadata"
      check "$(stat -c '%d:%i:%a:%u:%g:%Y' "$(dirname "$c/app/$protected_data_path")")" "$before_dir" "$app/$mode/$fault persistent directory identity/metadata"
      check "$(cat "$c/external-data/row")" 'USER legacy db' "$app/$mode/$fault external legacy data untouched"
      check "$(stat -c '%d:%i:%a:%u:%g:%Y' "$c/external-data/row")" "$legacy_before" "$app/$mode/$fault external legacy data identity retained"
      check "$(cat "$c/backups/files$c/external-data/row" 2> /dev/null || true)" 'stale legacy db' "$app/$mode/$fault unrelated backup store is not consumed"
      check "$(cat "$c/settings")" 'custom external settings' "$app/$mode/$fault settings retained"
      check "$(cat "$c/units/bytestash-backend.service")" 'custom JWT/port/registration' "$app/$mode/$fault existing unit defaults retained"
      if [[ "$app" == cliproxyapi ]]; then
        if [[ "$fault" != missing-config ]]; then check "$(cat "$c/app/config.yaml")" 'USER config.yaml' "$app/$mode/$fault custom config retained"; fi
        check "$(cat "$c/app/plugins/row")" 'USER plugins/row' "$app/$mode/$fault plugins retained"
      elif [[ "$app" == privatebin ]]; then
        if [[ "$fault" != missing-config ]]; then check "$(cat "$c/app/cfg/conf.php")" 'USER cfg/conf.php' "$app/$mode/$fault custom PrivateBin config retained"; fi
      fi
      if [[ "$fault" != none ]]; then
        check "$(test -e "$c/state/$app" && printf pending || printf absent)" pending "$app/$mode/$fault failed hook remains pending"
        check "$(grep -Ec '^(start|reload)' "$c/services" || true)" 0 "$app/$mode/$fault never restarts failed update"
        if [[ "$fault" == missing-config ]]; then
          check "$(wc -l < "$c/downloads")" 0 "$app/$mode refuses missing critical config before download"
          if [[ "$app" == privatebin ]]; then printf 'USER cfg/conf.php\n' > "$c/app/cfg/conf.php"; else printf 'USER config.yaml\n' > "$c/app/config.yaml"; fi
        fi
        retry_rc=0
        env -i PATH="$PATH" HOME="$c/home" TMPDIR="$c/tmp" CASE_ROOT="$c" APP="$app" APP_SLUG="$app" FAULT=none VERBOSE="$mode" \
          BUILD_LOG="$c/retry.log" DEBUG_LOGFILE="$c/retry-error.log" unshare -m --propagation private -- bash "$0" --child > "$c/retry-output" 2>&1 || retry_rc=$?
        check "$retry_rc" 0 "$app/$mode/$fault retry status"
        check "$(test -e "$c/state/$app" && printf pending || printf absent)" absent "$app/$mode/$fault retry clears pending"
        downloads_expected=2
        [[ "$fault" != missing-config ]] || downloads_expected=1
        check "$(wc -l < "$c/downloads")" "$downloads_expected" "$app/$mode/$fault retry forces actual provider redeployment"
      fi
      check "$(cat "$c/app/code")" 'new code' "$app/$mode/$fault final code consumer"
      check "$(cat "$c/app/$protected_data_path")" "USER $protected_data_path" "$app/$mode/$fault final data consumer"
    done
  done
done
sed '/^function install_script()/,$d' "$ROOT/scripts/lxc/bytestash.sh" > "$work/bytestash-defaults.sh"
defaults=$(env -i PATH="$PATH" bash -c 'source "$1"; printf "%s:%s" "$var_cpu" "$var_ram"' _ "$work/bytestash-defaults.sh")
custom=$(env -i PATH="$PATH" var_cpu=7 var_ram=7168 bash -c 'source "$1"; printf "%s:%s" "$var_cpu" "$var_ram"' _ "$work/bytestash-defaults.sh")
check "$defaults" 2:2048 'ByteStash fresh defaults match pinned upstream sizing'
check "$custom" 7:7168 'ByteStash caller resource overrides remain unchanged'
metadata=$(
  python3 - "$ROOT/_lxc/bytestash.md" << 'PY'
import pathlib,re,sys
s=pathlib.Path(sys.argv[1]).read_text();print(':'.join(re.search(r'^'+k+r': (\d+)$',s,re.M)[1] for k in ('cpu','ram')))
PY
)
check "$metadata" "$defaults" 'ByteStash catalogue sizing matches actual fresh defaults'
printf '%s failure(s); actual app hooks/helper/update owner; external download/build/service models\n' "$failures"
[[ "$failures" == 0 ]]
