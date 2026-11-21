#!/usr/bin/env bash
# runtime-hooks-contract: fixture case-asserted
# Source-generated install hooks; package, database, build and service effects
# are modeled. Files and their mode at the first secret write are native.
# shellcheck disable=SC2034,SC2154
set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/../lib/runtime-hooks/harness.sh"
systemd-detect-virt --vm --quiet || exit 1
: "${TMPDIR:?disk-backed TMPDIR required}"
case "$(findmnt -rn -T "$TMPDIR" -o FSTYPE)" in '' | tmpfs | ramfs) exit 1 ;; esac
work=$(mktemp -d "$TMPDIR/addon-private-files.XXXXXXXX")
trap 'rm -rf -- "$work"' EXIT
failures=0
for app in adguardhome-sync cronmaster jellystat immich-public-proxy; do
  for variant in absent archive-default; do
    c="$work/$app/$variant"
    mkdir -p "$c/home" "$c/app/app" "$c/config" "$c/units"
    sed -e "s@/etc/systemd/system/@$c/units/@g" -e "s@/etc/init.d/@$c/units/@g" "$ROOT/scripts/addon/$app.sh" > "$c/source.sh"
    (
      curl() { :; }
      source "$c/source.sh"
      source "$ROOT/misc/addon_lxc.func"
      umask 0022
      HOME="$c/home" OS_FAMILY=debian OS_TYPE=debian INIT_SYSTEM=systemd
      LOCAL_IP=127.0.0.1 TAB='' TAB3='' YW='' CL='' STD=''
      var_addon_install_path="$c/app"
      var_addon_config_path="$c/config/selected.env"
      [[ "$app" != immich-public-proxy ]] || var_addon_config_path="$c/app/app"
      var_addon_creds_path="$c/config/credentials"
      var_addon_service_path="$c/service"
      var_addon_service=fixture
      if [[ "$app" == immich-public-proxy ]]; then secret="$var_addon_config_path/.env"; else secret="$var_addon_config_path"; fi
      if [[ "$variant" == archive-default ]]; then
        printf 'archive defaults\n' > "$secret"
        chmod 0644 "$secret"
      fi
      msg_info() { :; }
      msg_ok() { :; }
      msg_warn() { :; }
      node() { printf 'v22.0.0\n'; }
      psql() { :; }
      npm() { :; }
      setup_nodejs() { :; }
      setup_postgresql() { :; }
      get_system_arch() { printf 'amd64\n'; }
      fetch_and_deploy_gh_release() { :; }
      systemctl() { :; }
      rc-service() { :; }
      rc-update() { :; }
      sudo() { printf 'jellystat\n'; }
      openssl() { printf 'fixturecredentialbytes\n'; }
      cat() {
        local destination pid=$BASHPID
        destination=$(readlink "/proc/$pid/fd/1") || return $?
        if [[ "$destination" == "$secret" || "$destination" == "$var_addon_creds_path" || "$destination" == */.addon-private.* ]]; then
          command stat -Lc '%a' "/proc/$pid/fd/1" >> "$c/first-write-modes"
        fi
        command cat "$@"
      }
      install_script < /dev/null
      command stat -Lc '%a' "$secret" > "$c/final-mode"
    ) > "$c/output" 2>&1 || {
      check failed success "$app/$variant generated install completes"
      continue
    }
    check "$(cat "$c/final-mode")" 600 "$app/$variant final config private"
    check "$(sort -u "$c/first-write-modes")" 600 "$app/$variant private before first secret byte"
  done
done

# Required publication failures preserve the old consumer and links are not
# followed into an operator credential. No secret bytes appear in diagnostics.
source "$ROOT/misc/addon_lxc.func"
if ! declare -F addon_write_private_file > /dev/null; then
  check missing present 'shared private-file publication API is required'
else
  c="$work/owner"
  mkdir -p "$c"
  printf 'original\n' > "$c/config"
  chmod 0644 "$c/config"
  status=0
  (
    mv() { return 47; }
    addon_write_private_file "$c/config" <<< 'new secret'
  ) || status=$?
  check "$status" 47 'private publication failure retains original status'
  check "$(cat "$c/config")" original 'failed private publication preserves old file'
  ln -s config "$c/link"
  status=0
  addon_write_private_file "$c/link" <<< 'new secret' || status=$?
  check "$status" 65 'private publication refuses selected symlink'
  check "$(cat "$c/config")" original 'private publication does not write through operator link'
  check "$(find "$c" -name '.addon-private.*' -printf x)" '' 'failed private stages are scoped and removed'
fi
printf 'RUNTIME_HOOKS_RESULT failures=%s\n' "$failures"
[[ "$failures" == 0 ]]
