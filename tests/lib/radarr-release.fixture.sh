#!/usr/bin/env bash
# Shared Arr cold actual hooks, including the persisted writer output. Only architecture,
# release, package and service effects are modeled; app paths are private mounts.
set -euo pipefail
ROOT=$(realpath "$(dirname "${BASH_SOURCE[0]}")/../..")
if [[ "${1:-}" == --child ]]; then
  c="$CASE_ROOT"
  mount --bind "$c/opt" /opt
  mount --bind "$c/units" /etc/systemd/system
  # Retain the disk workspace while hiding all other guest application state.
  mount --bind /var/lib/scripts-underground "$c/state/scripts-underground"
  mount --rbind "$c/state" /var/lib
  source "$ROOT/misc/tools.func"
  source "$c/hooks.sh"
  if [[ "$ROLE" == bundle ]]; then
    source "$ROOT/misc/bundle.func"
    # shellcheck disable=SC2034
    NSAPP="$SLUG"
    # shellcheck disable=SC2034
    var_lxc_tmpdir="$TMPDIR"
    # The real writer serializes the actual app hook. Modeled library init loads
    # the same effect models as a direct cold hook, after the real tools library.
    _write_bundle update update_script "$c/cache" --script-id "$SLUG" -- --requirements 2 1024 -- 'run_update_script "$@"' > "$c/update"
    exec bash "$c/update"
  fi
  source "$c/models.sh"
  "${ROLE}_script"
  exit 0
fi

: "${TMPDIR:?disk-backed TMPDIR required}"
systemd-detect-virt --vm --quiet || exit 1
case "$(realpath -e "$TMPDIR")" in /tmp | /tmp/*) exit 1 ;; esac
case "$(findmnt -rn -T "$TMPDIR" -o FSTYPE)" in '' | tmpfs | ramfs) exit 1 ;; esac
work=$(mktemp -d "$TMPDIR/arr-release.XXXXXX")
trap 'rm -rf -- "$work"' EXIT
failures=0
check() {
  if [[ "$1" == "$2" ]]; then printf 'PASS %s\n' "$3"; else
    printf 'FAIL %s: expected <%s>, got <%s>\n' "$3" "$2" "$1" >&2
    failures=$((failures + 1))
  fi
}
for slug in radarr prowlarr lidarr; do
  dependencies='install -y sqlite3 libicu-dev'
  update_clean=1
  case "$slug" in
    radarr) app=Radarr key=Radarr version=6.4.4.10685 ;;
    prowlarr) app=Prowlarr key=prowlarr version=2.7.0.5723 ;;
    lidarr)
      app=Lidarr key=lidarr version=3.1.6.5079
      dependencies='install -y sqlite3 libchromaprint-tools libicu-dev mediainfo'
      update_clean='unset'
      ;;
  esac
  for arch in amd64 arm64; do
    alias=x64
    [[ "$arch" != arm64 ]] || alias=arm64
    for role in install update bundle; do
      c="$work/$slug-$arch-$role"
      mkdir -p "$c/"{opt,units,state/scripts-underground,cache}
      [[ "$role" == install ]] || mkdir -p "$c/state/$slug"
      # Drop only the transport footer; every app declaration and hook is original.
      sed '/^# framework bootstrap/,$d' "$ROOT/scripts/lxc/$slug.sh" > "$c/hooks.sh"
      cat > "$c/models.sh" << 'MODELS'
export STD=''
unset CLEAN_INSTALL
dpkg() { printf '%s\n' "$TEST_ARCH"; }
uname() {
  if [[ "$TEST_ARCH" == amd64 ]]; then printf 'x86_64\n'; else printf 'aarch64\n'; fi
}
msg_info() { :; }
msg_ok() { :; }
msg_error() { printf '%s\n' "$*" >&2; }
header_info() { :; }
check_container_storage() { :; }
check_container_resources() { :; }
apt() { printf '%s\n' "$*" >> "$CASE_ROOT/packages"; }
systemctl() { printf '%s\n' "$*" >> "$CASE_ROOT/services"; }
check_for_gh_release() { [[ "$*" == "$RELEASE_KEY $APP/$APP" ]]; }
run_update_script() { update_script; }
fetch_and_deploy_gh_release() {
  [[ "$1:$2:$3:$4:$5" == "$RELEASE_KEY:$APP/$APP:prebuild:latest:/opt/$APP" ]] || return 64
  printf '%s\n' "$6" >> "$CASE_ROOT/pattern"
  printf '%s\n' "${CLEAN_INSTALL:-unset}" >> "$CASE_ROOT/clean"
  # Match the requested pattern against published-name fixtures, not a second
  # invocation of get_system_arch or the script's text.
  local asset selected='' count=0
  for asset in "$APP.master.$RELEASE_VERSION.linux-core-"{x64,arm64}.tar.gz; do
    if [[ "$asset" == $6 ]]; then selected="$asset"; count=$((count + 1)); fi
  done
  [[ "$count" == 1 ]] || return 252
  mkdir -p "/opt/$APP"
  printf '%s\n' "$selected" > "/opt/$APP/selected-asset"
}
get_system_arch > "$CASE_ROOT/default-arch"
MODELS
      printf 'load_functions() { source "$CASE_ROOT/models.sh"; }\ncolor() { :; }\n' > "$c/cache/core.func"
      printf 'catch_errors() { :; }\n' > "$c/cache/error_handler.func"
      printf 'setup_lxc() { :; }\n' > "$c/cache/install.func"
      cp "$ROOT/misc/tools.func" "$c/cache/tools.func"
      printf 'clone_and_deploy_gh_commit() { :; }\n' > "$c/cache/github.func"
      rc=0
      CASE_ROOT="$c" SLUG="$slug" RELEASE_KEY="$key" RELEASE_VERSION="$version" TEST_ARCH="$arch" ROLE="$role" timeout 30s unshare -mn --propagation private -- bash "$0" --child > "$c/output" 2>&1 || rc=$?
      label="$app $arch $role"
      check "$rc" 0 "$label cold hook status"
      check "$(cat "$c/default-arch")" "$arch" "$label unaliased helper stays dpkg-compatible"
      check "$(cat "$c/pattern")" "$app.master.*.linux-core-$alias.tar.gz" "$label release pattern reaches deployer"
      check "$(cat "$c/opt/$app/selected-asset" 2> /dev/null || true)" "$app.master.$version.linux-core-$alias.tar.gz" "$label selects published asset"
      clean="$update_clean"
      [[ "$role" != install ]] || clean='unset'
      check "$(cat "$c/clean")" "$clean" "$label CLEAN_INSTALL contract"
      if [[ "$role" == install ]]; then
        check "$(cat "$c/packages")" "$dependencies" "$label dependency call unchanged"
        check "$(cat "$c/services" 2> /dev/null || true)" "enable -q --now $slug" "$label service call unchanged"
      else
        check "$(cat "$c/services")" "$(printf 'stop %s\nstart %s' "$slug" "$slug")" "$label service sequence unchanged"
      fi
      if [[ "$role" == bundle ]]; then
        check "$(grep -Fc 'get_system_arch both x64 arm64' "$c/update")" 1 "$label baked updater has one explicit selector"
        check "$(grep -Fc '$(get_system_arch).tar.gz' "$c/update" || true)" 0 "$label baked updater has no stale default selector"
        check "$(test -s "$c/update" && printf present)" present "$label updater persists after hook execution"
      fi
    done
  done
done
printf '%s failure(s); actual Radarr/Prowlarr/Lidarr cold hooks/written updater; release/package/service/detection modeled\n' "$failures"
[[ "$failures" == 0 ]]
