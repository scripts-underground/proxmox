#!/usr/bin/env bash
# Jellyfin owns its FFmpeg dependency on both install and update.
set -euo pipefail

ROOT=$(realpath "$(dirname "${BASH_SOURCE[0]}")/..")
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT
export work STD='' GN=''
mkdir -p "$work/usr/lib/jellyfin" "$work/etc/logrotate.d"
for hook in install update; do
  sed '/^# framework bootstrap/,$d' "$ROOT/scripts/lxc/jellyfin.sh" |
    sed "s#/usr/lib/#$work/usr/lib/#g; s#/etc/logrotate.d/#$work/etc/logrotate.d/#g" > "$work/$hook.sh"
done

msg_custom() { :; }
msg_info() { :; }
msg_ok() { :; }
header_info() { :; }
check_container_storage() { :; }
check_container_resources() { :; }
ensure_dependencies() { :; }
setup_deb822_repo() { :; }
setup_hwaccel() { :; }
get_os_info() { printf 'ubuntu\n'; }
grep() { return 0; } # Exercise the Ubuntu update path without Intel downloads.
ln() { printf '%s\n' "$*" >> "$work/links.log"; }
chown() { :; }
sleep() { :; }
systemctl() { :; }
apt() {
  printf '%s\n' "$*" >> "$work/apt.log"
  local arg
  for arg in "$@"; do
    case "$arg" in
      jellyfin-ffmpeg*)
        printf 'FAIL script selected an FFmpeg package: %s\n' "$arg" >&2
        return 42
        ;;
    esac
  done
}
export -f msg_custom msg_info msg_ok header_info check_container_storage \
  check_container_resources ensure_dependencies setup_deb822_repo setup_hwaccel \
  get_os_info grep ln chown sleep systemctl apt

failures=0
for hook in install update; do
  : > "$work/apt.log"
  : > "$work/links.log"
  if bash -c 'set -euo pipefail; source "$work/$1.sh"; "${1}_script"' _ "$hook"; then
    if /usr/bin/grep -qx 'install -y jellyfin' "$work/apt.log"; then
      printf 'PASS %s lets apt select and replace Jellyfin dependencies\n' "$hook"
    else
      printf 'FAIL %s must install jellyfin with dependency replacement allowed\n' "$hook" >&2
      failures=$((failures + 1))
    fi
    for binary in ffmpeg ffprobe; do
      /usr/bin/grep -qx -- "-sf $work/usr/lib/jellyfin-ffmpeg/$binary /usr/bin/$binary" "$work/links.log"
    done
    printf 'PASS %s keeps stable FFmpeg and FFprobe symlinks\n' "$hook"
  else
    printf 'FAIL %s hook rejected package-owned FFmpeg selection\n' "$hook" >&2
    failures=$((failures + 1))
  fi
done
printf '%s failure(s)\n' "$failures"
[[ $failures == 0 ]]
