#!/usr/bin/env bash
# Repository-backed source/shim/install/publication/cold-command chain. Only the
# CT guard, package CLI and transport are models; framework membership is real.
set -euo pipefail
: "${TMPDIR:?disk-backed TMPDIR required}"
ROOT=$(realpath "$(dirname "${BASH_SOURCE[0]}")/../..")
work=$(mktemp -d "$TMPDIR/addon-producer-chain.XXXXXX")
trap 'rm -rf -- "$work"' EXIT
for fault in none missing; do
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
  [[ -f "$ROOT/$file" ]] || return 22
  if [[ -n "$output" ]]; then command cat "$ROOT/$file" > "$output"; else command cat "$ROOT/$file"; fi
}
export -f grep apt curl
MODEL
  cat > "$c/addon.sh" << 'ADDON'
#!/usr/bin/env bash
REPO_BASE=https://repository.invalid
APP="Producer Chain"
var_addon_message='saved setting with spaces'
install_script() { printf 'installed\n' > "$CASE_ROOT/app"; }
post_install_script() { printf 'post-install\n' > "$CASE_ROOT/post"; }
update_script() { printf '%s\n' "$var_addon_message" > "$CASE_ROOT/consumer"; }
uninstall_script() { rm -- "$CASE_ROOT/app"; }
source <(curl -fsSL "$REPO_BASE/misc/bootstrap/addon_lxc")
ADDON
  rc=0
  env ROOT="$ROOT" CASE_ROOT="$c" FAULT="$fault" TMPDIR="$c/tmp" \
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
      bash "$CASE_ROOT/addon.sh" > "$CASE_ROOT/install.log" 2>&1 || rc=$?
      printf "%s\n" "$rc" > "$CASE_ROOT/status"
      [[ -s "$CASE_ROOT/app" && -s "$CASE_ROOT/post" ]]
      if [[ "$FAULT" == missing ]]; then
        [[ "$rc" != 0 && ! -e /var/lib/scripts-underground/addons/producer-chain ]]
        [[ ! -e /usr/local/sbin/update_producer-chain && ! -e /usr/local/sbin/uninstall_producer-chain ]]
      else
        [[ "$rc" == 0 && -s /var/lib/scripts-underground/addons/producer-chain ]]
        [[ -x /usr/bin/update-producer-chain && -x /usr/bin/uninstall-producer-chain ]]
        fetch_count=$(wc -l < "$CASE_ROOT/fetches")
        env -i PATH="$PATH" HOME="$CASE_ROOT" ROOT="$ROOT" CASE_ROOT="$CASE_ROOT" FAULT="$FAULT" \
          BASH_ENV="$CASE_ROOT/models.sh" TMPDIR="$TMPDIR" BUILD_LOG="$CASE_ROOT/update.log" \
          DEBUG_LOGFILE="$CASE_ROOT/update-error.log" /usr/bin/update-producer-chain
        [[ "$(cat "$CASE_ROOT/consumer")" == "saved setting with spaces" ]]
        [[ "$(wc -l < "$CASE_ROOT/fetches")" == "$fetch_count" ]]
        [[ ! -e /var/lib/scripts-underground/update-pending/producer-chain ]]
      fi
    ' > "$c/output" 2>&1 || rc=$?
  if [[ "$rc" != 0 ]]; then
    cat "$c/output" "$c/install.log" >&2
    exit "$rc"
  fi
  ! grep -Fxq misc/addon.func "$c/fetches"
  if [[ "$fault" == none ]]; then
    grep -Fxq misc/bundle.func "$c/fetches"
    [[ "$(grep -Fxc misc/addon_lxc.func "$c/fetches")" == 2 ]]
  fi
  printf 'PASS repository-backed addon producer chain %s\n' "$fault"
done
