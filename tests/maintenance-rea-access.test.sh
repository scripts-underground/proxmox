#!/usr/bin/env bash
# Test locals supply context to the sourced application hooks.
# shellcheck disable=SC2034
set -euo pipefail

ROOT=$(cd -- "${BASH_SOURCE[0]%/*}/.." && pwd -P)
if [[ ${1-} == --setup-probe ]]; then
  work=$2
  export REA_INSTALL_SSH_SETUP=1
else
  work=$(mktemp -d)
  trap 'rm -rf -- "$work"' EXIT
fi
cd "$ROOT"
failures=0
check() {
  if "$@"; then
    printf 'PASS %s\n' "$*"
  else
    printf 'FAIL %s\n' "$*" >&2
    failures=$((failures + 1))
  fi
}

# Model the installation paths, not the shared helper. Load its actual bundle
# inventory and exercise the real publisher under the fixture's private paths.
source misc/bundle.func
inventory=$(_framework_library_inventory lxc)
read -r access_owner access_sentinel < <(grep '^ssh-access\.func ' <<< "$inventory")
sed -e '/^source <(/,$d' -e "/^# Defined only for explicit source setup/,\$s@/srv/rea@$work/rea@g; s@/usr/local/lib@$work/lib@g" scripts/lxc/rea.sh > "$work/app.sh"
sed -e "s@/usr/local/sbin/configure-ssh-access@$work/sbin/configure-ssh-access@g; s@/usr/bin/configure-ssh-access@$work/bin/configure-ssh-access@g" \
  "misc/$access_owner" > "$work/access.func"
source "$work/app.sh"

opt_in() { [[ ${var_ssh_access_account-} == rea ]]; }
completion() (
  local LXC_SSH_ACCESS_MODE=$1 IP=2001:db8::123 output
  output=$(post_install_script)
  [[ $output == *'rea@2001:db8::123'* && $output == *'ssh-keygen -lf /etc/ssh/ssh_host_ed25519_key.pub'* && $output == *'configure-ssh-access rea'* ]] || return 1
  [[ $output == *'cat /etc/ssh/ssh_host_ed25519_key.pub'*'~/.ssh/known_hosts'*'2001:db8::123 ssh-ed25519 <public-key-blob>'* ]] || return 1
  case "$1" in
    key | both) [[ $output == *"($1)"* && $output == *'~/.ssh/known_hosts'*'ssh -T -o BatchMode=yes -o StrictHostKeyChecking=yes rea@2001:db8::123 /srv/rea/bin/rea mcp'* ]] ;;
    password) [[ $output == *'(password)'* && $output == *'~/.ssh/known_hosts'*'ssh -o StrictHostKeyChecking=yes rea@2001:db8::123'* && $output != *'BatchMode=yes'* ]] ;;
    pending) [[ $output == *pending* && $output != *'configured'* && $output != *'BatchMode=yes'* ]] ;;
  esac
)

mkdir -p "$work/"{bin,lib,rea/current}
printf 'rea_pins() { printf "fixture pins\\n"; }\n' > "$work/lib/rea-deploy.sh"
printf 'fixture pins\n' > "$work/rea/current/pins"
: > "$work/rea/environment.sh"
OS_TYPE=debian OS_VERSION=13 STD=''
get_system_arch() { printf amd64; }
id() { [[ $* == rea ]]; }
msg_info() { :; }
msg_ok() { :; }
msg_error() { printf '%s\n' "$*" >&2; }
runuser() { [[ "$1 $2 $3" == '-u rea --' ]]; }
apt() {
  [[ "$*" == 'install -y whiptail' ]] || return 67
  [[ $(cat "$work/owner") == rea ]] || return 70
  printf 'whiptail\n' >> "$work/packages"
  return "${PACKAGE_STATUS:-0}"
}

install_declares_whiptail() (
  local rc=0
  pkg_install() {
    [[ " $* " == *' whiptail '* ]] || return 67
    return 42
  }
  install_script || rc=$?
  [[ $rc == 42 ]]
)
_load_ssh_access() {
  source "$work/access.func" || return $?
  declare -F "$access_sentinel" > /dev/null || return $?
  ssh_access_host_api
}

if [[ ${1-} == --setup-probe ]]; then
  # shellcheck source=/dev/null
  source <(sed -n '/^_lxc_bootstrap() {/,/^}/p; /^_lxc_run_ssh_setup() {/,/^}/p; /^_lxc_setup() {/,/^}/p' misc/build.func)
  variables() { NSAPP=rea; }
  curl() { :; }
  color() { :; }
  render_header() { :; }
  catch_errors() { set -Eeuo pipefail; }
  _lxc_script_identity_args() { :; }
  ensure_profile_loaded() { :; }
  set_std_mode() { :; }
  command() {
    [[ $* != '-v pveversion' ]] || return 1
    builtin command "$@"
  }
  app_maintenance_begin() { printf '%s\n' "$1" > "$work/owner"; }
  run_update_script() {
    echo 'unexpected software update admission' >&2
    exit 76
  }
  execute_optional_hook() { "$1"; }
  export PHS_SILENT=1
  if [[ $3 == conditional ]]; then _lxc_bootstrap || exit "$?"; else _lxc_bootstrap; fi
  exit 77
fi

ordinary_update_preserves_access() (
  unset REA_INSTALL_SSH_SETUP
  update_script || return $?
  [[ ! -e $work/packages && ! -e $work/sbin/configure-ssh-access ]]
)

explicit_setup_uses_shared_owner() (
  local expected="$work/expected" command="$work/sbin/configure-ssh-access"
  bash "${BASH_SOURCE[0]}" --setup-probe "$work" ordinary || return $?
  [[ -x $command ]] && [[ $(readlink "$work/bin/configure-ssh-access") == "$command" ]] || return 1
  _load_ssh_access && ssh_access_command_contents rea > "$expected" && cmp -s "$expected" "$command" || return 1
  bash "${BASH_SOURCE[0]}" --setup-probe "$work" conditional && cmp -s "$expected" "$command" && [[ $(cat "$work/packages") == $'whiptail\nwhiptail' ]]
)

explicit_setup_dependency_failure() (
  local rc caller command="$work/sbin/configure-ssh-access"
  for caller in ordinary conditional; do
    rc=0
    PACKAGE_STATUS=42 bash "${BASH_SOURCE[0]}" --setup-probe "$work" "$caller" || rc=$?
    [[ $rc == 42 ]] && cmp -s "$work/expected" "$command" || return 1
  done
)

check opt_in
check install_declares_whiptail
for mode in key both password pending; do check completion "$mode"; done
check ordinary_update_preserves_access
check explicit_setup_uses_shared_owner
check explicit_setup_dependency_failure
printf '%s failure(s)\n' "$failures"
[[ $failures == 0 ]]
