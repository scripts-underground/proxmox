#!/usr/bin/env bash
# Every discovered key file must reach the checklist and selected-key output.
set -euo pipefail
ROOT=$(realpath "$(dirname "${BASH_SOURCE[0]}")/..")
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT
export TMPDIR="$work"

# Keep the production discovery/selection flow, redirecting only filesystem roots.
sed "s|/root/.ssh|$work/root/.ssh|g; s|/etc/ssh|$work/etc/ssh|g" "$ROOT/misc/ssh-access.func" > "$work/ssh.sh"
sed -n '/^_load_ssh_access() {/,/^}/p; /^configure_ssh_settings() {/,/^}/p' "$ROOT/misc/build.func" >> "$work/ssh.sh"
source "$work/ssh.sh"
mkdir -p "$work/root/.ssh" "$work/etc/ssh/authorized_keys.d"
ssh-keygen -q -t ed25519 -N '' -f "$work/fixture"
read -r type blob _ < "$work/fixture.pub"
files=(
  "$work/root/.ssh/authorized_keys"
  "$work/root/.ssh/authorized_keys2"
  "$work/root/.ssh/id_ed25519.pub"
  "$work/root/.ssh/work key.pub"
  "$work/etc/ssh/authorized_keys"
  "$work/etc/ssh/authorized_keys.d/"$'team\nkey'
)
for i in "${!files[@]}"; do
  printf '# ignored comment\n%s %s fixture-%s\n' "$type" "$blob" "$i" > "${files[$i]}"
  printf '%s %s fixture-%s\n' "$type" "$blob" "$i" >> "$work/expected"
done
sort -u -o "$work/expected" "$work/expected"
printf '\n' >> "$work/expected"

exit_script() { exit 1; }
whiptail() {
  local title='' arg
  for arg in "$@"; do
    case "$arg" in
      'SSH KEY SOURCE' | 'SELECT HOST KEYS' | 'SSH ACCESS') title="$arg" ;;
    esac
  done
  case "$title" in
    'SSH KEY SOURCE')
      printf '%s\n' "$*" > "$work/source-menu"
      printf '%s\n' "$mode" >&2
      ;;
    'SELECT HOST KEYS')
      while [[ "$1" != --checklist ]]; do shift; done
      shift 5
      printf '%s\0' "$@" > "$work/checklist"
      while [[ $# -gt 0 ]]; do
        printf '"%s" ' "$1" >&2
        shift 3
      done
      ;;
    'SSH ACCESS') return 1 ;;
    *) return 1 ;;
  esac
}

mode=found
configure_ssh_settings
if grep -Fq "Select from detected keys (${#files[@]})" "$work/source-menu"; then
  :
else
  printf 'FAIL not every default key was offered\n' >&2
  cat "$work/source-menu" >&2
  exit 1
fi
mapfile -d '' -t offered < "$work/checklist"
[[ ${#offered[@]} == $((${#files[@]} * 3)) ]]
for i in "${!files[@]}"; do
  [[ "${offered[$((i * 3))]}" == "K$((i + 1))" ]]
  [[ "${offered[$((i * 3 + 1))]}" == *"— ${files[$i]##*/}" ]]
done
printf 'PASS all default files reach the checklist, including spaces and newlines\n'
cmp "$work/expected" "$SSH_KEYS_FILE"
[[ "$SSH" == no ]]
printf 'PASS selecting every offered key provisions keys from every file\n'
rm "$SSH_MAP_FILE" "$SSH_KEYS_FILE" "$work/checklist" "${files[@]}"

mode=none
configure_ssh_settings
grep -Fq 'No host keys detected; choose manual/none:' "$work/source-menu"
[[ ! -s "$SSH_KEYS_FILE" && "$SSH" == no ]]
if [[ -e "$work/checklist" ]]; then
  printf 'FAIL checklist offered without any keys\n' >&2
  exit 1
fi
rm "$SSH_MAP_FILE" "$SSH_KEYS_FILE"
printf 'PASS missing default files retain the no-keys flow\n'

# Exercise the real Step 17, setup dispatcher and bootstrap. Shorten the
# wizard to that step only; preceding selections are not under test here.
sed -n '/^advanced_settings() {/,/^}/p; /^setup_script() {/,/^}/p; /^_lxc_setup() {/,/^}/p; /^_lxc_bootstrap() {/,/^}/p' \
  "$ROOT/misc/build.func" | sed 's/local STEP=1$/local STEP=17/;s/local MAX_STEP=28$/local MAX_STEP=17/' > "$work/setup.sh"
export ROOT work
failed=0
for fault in loader write cancel; do
  for caller in ordinary conditional; do
    rc=0
    fault=$fault caller=$caller bash -c '
      cd "$work"
      source "$ROOT/misc/core.func"
      source "$work/ssh.sh"
      source "$work/setup.sh"
      pveversion() { :; }; pvesh() { printf "9876\n"; }; systemctl() { return 1; }
      pve_check() { :; }; shell_check() { :; }; root_check() { :; }; arch_check() { :; }; ssh_check() { :; }
      variables() { APP=fixture NSAPP=fixture var_os=debian var_version=13 REPO_BASE=fixture; }
      color() { :; }; render_header() { :; }; catch_errors() { set -Ee -o pipefail; }
      header_info_fallback() { :; }; run_preflight() { :; }; get_app_defaults_path() { echo nonexisting; }
      base_settings() { :; }; log_section() { :; }; log_msg() { :; }; terminal_clear() { :; }
      ensure_global_default_vars_file() { :; }; maybe_offer_save_app_defaults() { :; }
      curl() { :; }; _lxc_script_identity_args() { :; }
      _load_ssh_access() { [[ "$fault" != loader ]] || return 68; }
      mktemp() { [[ "$fault" != write ]] || return 73; command mktemp "$@"; }
      whiptail() { return 255; }
      build_container() { echo CREATE_REACHED; }
      complete_install() { :; }
      mode=advanced
      if [[ $caller == conditional ]]; then _lxc_bootstrap || exit "$?"; else _lxc_bootstrap; fi
    ' > "$work/setup.log" 2>&1 || rc=$?
    case $fault in loader) expected=68 ;; write) expected=73 ;; cancel) expected=0 ;; esac
    if [[ $rc == "$expected" ]] && ! grep -Fq 'CREATE_REACHED' "$work/setup.log" &&
      { { [[ $fault == cancel ]] && grep -Fq 'User exited script' "$work/setup.log"; } ||
        { [[ $fault != cancel ]] && ! grep -Fq 'User exited script' "$work/setup.log"; }; }; then
      printf 'PASS root picker %s (%s) status %s; no create\n' "$fault" "$caller" "$rc"
    else
      printf 'FAIL root picker %s (%s) status %s expected %s\n' "$fault" "$caller" "$rc" "$expected" >&2
      failed=1
    fi
  done
done
exit "$failed"
