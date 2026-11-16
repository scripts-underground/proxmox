#!/usr/bin/env bash
# Repository-backed source/shim/install/publication/cold-command chain. Only the
# CT guard, package CLI and transport are models; framework membership is real.
set -euo pipefail
: "${TMPDIR:?disk-backed TMPDIR required}"
ROOT=$(realpath "$(dirname "${BASH_SOURCE[0]}")/../..")
work=$(mktemp -d "$TMPDIR/addon-producer-chain.XXXXXX")
trap 'rm -rf -- "$work"' EXIT
for fault in none missing api; do
  c="$work/$fault"
  mkdir -p "$c/bin" "$c/upper" "$c/overlay-work" "$c/sbin" "$c/state" "$c/tmp" "$c/home"
  cat > "$c/models.sh" << 'MODEL'
grep() {
  if [[ "$*" == '-q container=lxc /proc/1/environ' ]]; then return 0; fi
  command grep "$@"
}
apt() { printf 'package CLI %s\n' "$*" >> "$CASE_ROOT/packages"; }
curl() {
  local url='' output='' arg file
  while (($#)); do
    arg=$1; shift
    case "$arg" in
      -o) output=$1; shift ;;
      --connect-timeout) shift ;;
      https://repository.invalid/*) url=$arg ;;
    esac
  done
  [[ -n "$url" ]] || return 97
  file=${url#https://repository.invalid/}
  printf '%s\n' "$file" >> "$CASE_ROOT/fetches"
  # Fail only the assembly download, after the shim already loaded this library.
  if [[ "$FAULT" == missing && "$file" == misc/github.func && -n "$output" ]]; then return 22; fi
  if [[ "$FAULT" == api && "$file" == misc/tools.func && -n "$output" ]]; then
    printf 'setup_uv() { :; }\n# %0120d\n' 0 > "$output"
    return 0
  fi
  [[ -f "$ROOT/$file" ]] || return 22
  if [[ -n "$output" ]]; then command cat "$ROOT/$file" > "$output"; else command cat "$ROOT/$file"; fi
}
export -f grep apt curl
MODEL
  cat > "$c/addon.sh" << 'ADDON'
#!/usr/bin/env bash
REPO_BASE=https://repository.invalid
APP="Producer Chain"
var_addon_message="${var_addon_message:-new source default}"
install_script() {
  [[ ":$PATH:" == *:/usr/local/bin:* ]]
  printf 'installed\n' >> "$CASE_ROOT/app"
}
post_install_script() {
  [[ -s /var/lib/scripts-underground/addons/producer-chain && -x /usr/bin/update-producer-chain && -x /usr/bin/uninstall-producer-chain ]]
  printf 'post-install\n' > "$CASE_ROOT/post"
}
update_script() {
  printf '%s\n' "$var_addon_message" > "$CASE_ROOT/consumer"
  printf '%s|%s|%s\n' "$NSAPP" "$HOME" "${UPDATE_FORCE:-0}" > "$CASE_ROOT/context"
}
uninstall_script() { [[ "$HOME" == /root ]]; rm -- "$CASE_ROOT/app"; }
source <(curl -fsSL "$REPO_BASE/misc/bootstrap/addon_lxc") --script-id producer-chain -- "$@"
ADDON
  rc=0
  env ROOT="$ROOT" CASE_ROOT="$c" FAULT="$fault" TMPDIR="$c/tmp" NSAPP=foreign PATH=/usr/bin:/bin \
    BASH_ENV="$c/models.sh" BUILD_LOG="$c/active.log" DEBUG_LOGFILE="$c/error.log" \
    unshare --mount --propagation private bash -c '
      set -euo pipefail
      # Keep executable bytes read-only below a disk-backed private alias layer.
      mount --bind /usr/bin "$CASE_ROOT/bin"
      mount -t overlay overlay -o "lowerdir=$CASE_ROOT/bin,upperdir=$CASE_ROOT/upper,workdir=$CASE_ROOT/overlay-work" /usr/bin
      mount --bind "$CASE_ROOT/sbin" /usr/local/sbin
      mount --bind "$CASE_ROOT/home" /root
      for name in addons maintenance-locks update-pending; do
        mkdir -p "$CASE_ROOT/state/$name" "/var/lib/scripts-underground/$name"
        if [[ "$name" == maintenance-locks ]]; then chmod 0700 "$CASE_ROOT/state/$name"; fi
        mount --bind "$CASE_ROOT/state/$name" "/var/lib/scripts-underground/$name"
      done
      rc=0
      var_addon_message="saved setting with spaces" bash "$CASE_ROOT/addon.sh" > "$CASE_ROOT/install.log" 2>&1 || rc=$?
      printf "%s\n" "$rc" > "$CASE_ROOT/status"
      if [[ "$FAULT" != none ]]; then
        [[ "$rc" != 0 && ! -e /var/lib/scripts-underground/addons/producer-chain ]]
        [[ ! -e "$CASE_ROOT/app" && ! -e "$CASE_ROOT/post" ]]
        [[ ! -e "$CASE_ROOT/active.log" ]]
        [[ ! -e /usr/local/sbin/update_producer-chain && ! -e /usr/local/sbin/uninstall_producer-chain ]]
      else
        [[ -s "$CASE_ROOT/app" && -s "$CASE_ROOT/post" ]]
        [[ "$rc" == 0 && -s /var/lib/scripts-underground/addons/producer-chain ]]
        [[ -x /usr/bin/update-producer-chain && -x /usr/bin/uninstall-producer-chain ]]
        fetch_count=$(wc -l < "$CASE_ROOT/fetches")
        env -i PATH="$PATH" NSAPP=foreign ROOT="$ROOT" CASE_ROOT="$CASE_ROOT" FAULT="$FAULT" \
          BASH_ENV="$CASE_ROOT/models.sh" TMPDIR="$TMPDIR" BUILD_LOG="$CASE_ROOT/update.log" \
          DEBUG_LOGFILE="$CASE_ROOT/update-error.log" /usr/bin/update-producer-chain
        [[ "$(cat "$CASE_ROOT/consumer")" == "saved setting with spaces" ]]
        [[ "$(cat "$CASE_ROOT/context")" == "producer-chain|/root|0" ]]
        [[ "$(wc -l < "$CASE_ROOT/fetches")" == "$fetch_count" ]]
        [[ ! -e /var/lib/scripts-underground/update-pending/producer-chain ]]
        marker=/var/lib/scripts-underground/addons/producer-chain
        marker_hash=$(sha256sum "$marker")
        pending=/var/lib/scripts-underground/update-pending/producer-chain
        printf "unfinished original bytes\n" > "$pending"
        pending_hash=$(sha256sum "$pending")
        mkfifo "$CASE_ROOT/release"
        exec 3<> "$CASE_ROOT/release"
        bash -c '\''source "$ROOT/misc/core.func"; app_maintenance_begin producer-chain || exit; : > "$CASE_ROOT/ready"; read -r -t 30 _ <&3'\'' &
        holder=$!
        trap '\''kill "$holder" 2>/dev/null || true; wait "$holder" 2>/dev/null || true'\'' EXIT
        for ((i=0; i<100; i++)); do [[ ! -e "$CASE_ROOT/ready" ]] || break; sleep 0.02; done
        [[ -e "$CASE_ROOT/ready" ]]
        for operation in update uninstall refresh install; do
          rc=0
          case "$operation" in
            update) /usr/bin/update-producer-chain > "$CASE_ROOT/busy-$operation.log" 2>&1 || rc=$? ;;
            uninstall) /usr/bin/uninstall-producer-chain > "$CASE_ROOT/busy-$operation.log" 2>&1 || rc=$? ;;
            refresh) ADDON_ACTION=refresh bash "$CASE_ROOT/addon.sh" > "$CASE_ROOT/busy-$operation.log" 2>&1 || rc=$? ;;
            install)
              mv "$marker" "$CASE_ROOT/saved-marker"
              bash "$CASE_ROOT/addon.sh" > "$CASE_ROOT/busy-$operation.log" 2>&1 || rc=$?
              mv "$CASE_ROOT/saved-marker" "$marker"
              ;;
          esac
          [[ "$rc" == 75 && "$(sha256sum "$pending")" == "$pending_hash" ]]
        done
        printf "release\n" >&3; wait "$holder"; exec 3>&-
        trap - EXIT
        [[ "$(wc -l < "$CASE_ROOT/app")" == 1 ]]

        # Known legacy declaration shape, with code that must never be sourced.
        for role in update uninstall; do
          if [[ "$role" == uninstall ]]; then
            sed -i "/^declare -- NSAPP=/d; /^declare -- ADDON_SCRIPT_ID=/d" "/usr/local/sbin/${role}_producer-chain"
          fi
          printf '\''touch "$CASE_ROOT/old-code-executed"\n'\'' >> "/usr/local/sbin/${role}_producer-chain"
        done
        ADDON_ACTION=refresh bash "$CASE_ROOT/addon.sh" > "$CASE_ROOT/refresh.log" 2>&1
        [[ ! -e "$CASE_ROOT/old-code-executed" && "$(wc -l < "$CASE_ROOT/app")" == 1 ]]
        [[ "$(sha256sum "$pending")" == "$pending_hash" ]]
        [[ "$(sha256sum "$marker")" == "$marker_hash" ]]
        ADDON_ACTION=update bash "$CASE_ROOT/addon.sh" --clean > "$CASE_ROOT/argv.log" 2>&1
        [[ "$(cat "$CASE_ROOT/consumer")" == "saved setting with spaces" ]]
        [[ "$(cat "$CASE_ROOT/context")" == "producer-chain|/root|1" && ! -e "$pending" ]]

        # Missing marker and broken command each need explicit recovery.
        mv "$marker" "$CASE_ROOT/saved-marker"
        rc=0; bash "$CASE_ROOT/addon.sh" > "$CASE_ROOT/unmarked.log" 2>&1 || rc=$?
        [[ "$rc" == 65 && "$(wc -l < "$CASE_ROOT/app")" == 1 ]]
        ADDON_ACTION=refresh bash "$CASE_ROOT/addon.sh" > "$CASE_ROOT/unmarked-refresh.log" 2>&1
        [[ ! -e "$marker" ]] || { printf "FAIL refresh invented an install-completion marker\n" >&2; exit 1; }
        [[ "$(wc -l < "$CASE_ROOT/app")" == 1 ]]
        mv "$CASE_ROOT/saved-marker" "$marker"
        cp /usr/local/sbin/uninstall_producer-chain "$CASE_ROOT/complete-uninstall"
        printf "#!/bin/bash\nexit 0\n" > /usr/local/sbin/uninstall_producer-chain
        rc=0; bash "$CASE_ROOT/addon.sh" > "$CASE_ROOT/truncated.log" 2>&1 || rc=$?
        [[ "$rc" == 65 ]]
        cp "$CASE_ROOT/complete-uninstall" /usr/local/sbin/uninstall_producer-chain
        rm /usr/local/sbin/uninstall_producer-chain
        rc=0; bash "$CASE_ROOT/addon.sh" > "$CASE_ROOT/broken.log" 2>&1 || rc=$?
        [[ "$rc" == 65 ]]
        ADDON_ACTION=refresh bash "$CASE_ROOT/addon.sh" > "$CASE_ROOT/repair.log" 2>&1
        [[ -x /usr/bin/uninstall-producer-chain ]]
        printf "foreign workload\n" > "$CASE_ROOT/foreign"
        env -u HOME -u USER -u LOGNAME /usr/bin/uninstall-producer-chain > "$CASE_ROOT/uninstall.log" 2>&1
        [[ -s "$CASE_ROOT/foreign" && ! -e "$CASE_ROOT/app" && ! -e "$marker" ]]
        [[ ! -e /usr/local/sbin/update_producer-chain && ! -e /usr/local/sbin/uninstall_producer-chain ]]
      fi
    ' > "$c/output" 2>&1 || rc=$?
  if [[ "$rc" != 0 ]]; then
    cat "$c/output" "$c/install.log" >&2
    for log in "$c"/busy-*.log "$c"/refresh.log "$c"/argv.log "$c"/repair.log "$c"/uninstall.log; do
      [[ ! -f "$log" ]] || {
        printf 'LOG %s\n' "${log##*/}" >&2
        cat "$log" >&2
      }
    done
    exit "$rc"
  fi
  ! grep -Fxq misc/addon.func "$c/fetches"
  if [[ "$fault" == none ]]; then
    grep -Fxq misc/bundle.func "$c/fetches"
    [[ "$(grep -Fxc misc/addon_lxc.func "$c/fetches")" -ge 4 ]]
  fi
  printf 'PASS repository-backed addon producer chain %s\n' "$fault"
done
