#!/usr/bin/env bash
# runtime-hooks-contract: fixture case-asserted
# Shared addon persistence declaration, with the real checked replacement owner.
# shellcheck disable=SC2034
set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/../lib/runtime-hooks/harness.sh"
systemd-detect-virt --vm --quiet || exit 1
: "${TMPDIR:?disk-backed TMPDIR required}"
case "$(findmnt -rn -T "$TMPDIR" -o FSTYPE)" in '' | tmpfs | ramfs) exit 1 ;; esac
source "$ROOT/misc/addon_lxc.func"
source "$ROOT/misc/tools.func"
work=$(mktemp -d "$TMPDIR/addon-inputs.XXXXXXXX")
trap 'rm -rf -- "$work"' EXIT
failures=0
for variant in plain normalized linked root-link external absent; do
  c="$work/$variant"
  mkdir -p "$c/live/private" "$c/incoming/private" "$c/external"
  printf 'old code\n' > "$c/live/code"
  printf 'new code\n' > "$c/incoming/code"
  printf 'operator data\n' > "$c/live/inherited keep"
  printf 'incoming default\n' > "$c/incoming/inherited keep"
  printf 'operator secret\n' > "$c/live/private/selected env"
  chmod 0600 "$c/live/private/selected env"
  stat -c '%i:%a' "$c/live/private/selected env" > "$c/metadata"
  printf 'incoming secret\n' > "$c/incoming/private/selected env"
  root="$c/live" input="$c/live/private/selected env"
  case "$variant" in
    normalized) input="$c/live/./private//selected env" ;;
    linked)
      ln -s 'private/selected env' "$c/live/.env"
      input="$c/live/.env"
      printf 'incoming .env\n' > "$c/incoming/.env"
      ;;
    root-link)
      ln -s live "$c/root-link"
      root="$c/root-link"
      input="$root/./private/selected env"
      ;;
    external)
      input="$c/external/selected env"
      printf 'external secret\n' > "$input"
      ;;
    absent) input="$c/live/optional/missing.env" ;;
  esac
  CLEAN_INSTALL_KEEP_PATHS=('inherited keep')
  status=0
  addon_keep_inputs CLEAN_INSTALL_KEEP_PATHS "$root" "$input" || status=$?
  check "$status" 0 "$variant admits configured input closure"
  if [[ "$status" == 0 ]]; then
    _deploy_replace_contents "$c/incoming" "$root" 1
    check "$(cat "$root/code")" 'new code' "$variant publishes new code"
    check "$(cat "$root/inherited keep")" 'operator data' "$variant preserves inherited keeps"
    if [[ "$variant" == external ]]; then
      check "${#CLEAN_INSTALL_KEEP_PATHS[@]}" 1 'external inputs never enter replacement keeps'
      check "$(cat "$input")" 'external secret' 'external input stays unchanged'
    elif [[ "$variant" != absent ]]; then
      check "$(cat "$input")" 'operator secret' "$variant preserves consumed input bytes"
      check "$(stat -c '%i:%a' "$root/private/selected env")" "$(cat "$c/metadata")" "$variant preserves consumed input inode/mode"
    fi
    if [[ "$variant" == linked ]]; then
      check "$(readlink "$root/.env")" 'private/selected env' 'lexical link stays live'
    fi
  fi
done

# The same owner must include the bytes and metadata actually consumed through
# a link, and optional absence must be distinct from an unreadable input.
if ! declare -F addon_runtime_fingerprint > /dev/null; then
  check missing present 'shared complete runtime fingerprint API is required'
else
  c="$work/fingerprint"
  mkdir -p "$c/tree" "$c/external" "$c/unit inputs"
  printf 'old runtime\n' > "$c/tree/code"
  printf 'private config\n' > "$c/external/config"
  chmod 0600 "$c/external/config"
  ln -s ../external/config "$c/tree/config-link"
  printf 'unit\n' > "$c/unit inputs/fragment"
  printf 'drop-in\n' > "$c/unit inputs/drop in"
  INIT_SYSTEM=systemd
  busctl() {
    [[ "${UNIT_QUERY_FAIL:-0}" == 0 ]] || return 47
    case "${!#}" in
      selected.service) printf '{"type":"o","data":["/selected"]}\n' ;;
      LoadState) printf '{"type":"s","data":"loaded"}\n' ;;
      FragmentPath) printf '{"type":"s","data":"%s"}\n' "$c/unit inputs/fragment" ;;
      DropInPaths) printf '{"type":"as","data":["%s"]}\n' "$c/unit inputs/drop in" ;;
      *) return 46 ;;
    esac
  }
  fingerprint() { addon_runtime_fingerprint --tree "$c/tree" --optional "$c/optional" --unit selected.service; }
  before=$(fingerprint)
  check "$(fingerprint)" "$before" 'unchanged consumed inputs have stable digest'
  for change in target-mode target-bytes target-owner link-target tree-bytes optional-present drop-in fragment; do
    case "$change" in
      target-mode) chmod 0644 "$c/external/config" ;;
      target-bytes) printf 'changed secret\n' > "$c/external/config" ;;
      target-owner) command chown 65534 "$c/external/config" ;;
      link-target)
        ln -sfn ../external/alias "$c/tree/config-link"
        cp -p "$c/external/config" "$c/external/alias"
        ;;
      tree-bytes) printf 'new runtime\n' > "$c/tree/code" ;;
      optional-present) printf 'new optional input\n' > "$c/optional" ;;
      drop-in) printf 'new drop-in\n' > "$c/unit inputs/drop in" ;;
      fragment) printf 'new unit\n' > "$c/unit inputs/fragment" ;;
    esac
    after=$(fingerprint)
    check "$([[ "$before" != "$after" ]] && printf changed || printf unchanged)" changed "$change changes consumed-input fingerprint"
    before=$after
  done
  status=0
  addon_runtime_fingerprint --file "$c/missing" > /dev/null || status=$?
  check "$status" 65 'required input absence refuses recovery proof'
  mkfifo "$c/special"
  status=0
  addon_runtime_fingerprint --file "$c/special" > /dev/null || status=$?
  check "$status" 65 'special input refuses without reading it'
  status=0
  UNIT_QUERY_FAIL=1 fingerprint > /dev/null || status=$?
  check "$status" 47 'unit query failure remains a proof failure'
  unset -f busctl
fi
printf 'RUNTIME_HOOKS_RESULT failures=%s\n' "$failures"
[[ "$failures" == 0 ]]
