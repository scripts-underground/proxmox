#!/usr/bin/env bash
# Selected GPU nodes and their context must survive the host/container boundary.
# Extracted functions consume globals and intentionally replace later test stubs.
# shellcheck disable=SC2034,SC2218
set -euo pipefail
: "${TMPDIR:?disk-backed TMPDIR required}"
case "$(realpath -e "$TMPDIR")" in /tmp | /tmp/*) exit 1 ;; esac
case "$(findmnt -rn -T "$TMPDIR" -o FSTYPE)" in '' | tmpfs | ramfs) exit 1 ;; esac
ROOT=$(realpath "$(dirname "${BASH_SOURCE[0]}")/..")
work=${work:-$(mktemp -d)}
export ROOT work

# Interactive legs use a real PTY so the production tty/default rules run unchanged.
if [[ ${1:-} == select ]]; then
  source "$work/gpu.sh"
  msg_ok() { :; }
  msg_custom() { :; }
  detect_gpu_devices() {
    INTEL_DEVICES=(/dev/dri/renderD128 /dev/dri/card0)
    AMD_DEVICES=(/dev/dri/renderD129 /dev/dri/card1 /dev/kfd)
    NVIDIA_DEVICES=(/dev/nvidia0 /dev/nvidia1 /dev/nvidiactl /dev/nvidia-uvm)
  }
  ENABLE_GPU=yes PHS_SILENT=0 YW='' CTID=9876 LXC_CONFIG=$work/selected.conf
  printf 'dev3: /dev/dri/renderD129,gid=44\ndev8: /dev/other,gid=44\n' > "$LXC_CONFIG"
  configure_gpu_passthrough
  [[ $GPU_TYPE == 'AMD NVIDIA' ]]
  grep -q '^dev9: /dev/dri/card1,gid=44,uid=0,mode=0660$' "$LXC_CONFIG"
  grep -q '/dev/kfd,' "$LXC_CONFIG"
  grep -q '/dev/nvidia1,' "$LXC_CONFIG"
  grep -q '/dev/nvidiactl,' "$LXC_CONFIG"
  if grep -qE '/dev/nvidia0,|/dev/dri/card0,|/dev/dri/renderD128,' "$LXC_CONFIG"; then exit 1; fi
  [[ $(grep -c '/dev/dri/renderD129,' "$LXC_CONFIG") == 1 ]]
  cp "$LXC_CONFIG" "$work/selected-before.conf"
  configure_gpu_passthrough
  cmp "$LXC_CONFIG" "$work/selected-before.conf"
  options=(intel amd nvidia) indices=()
  _gpu_select_indices indices options test
  [[ ${indices[*]} == '0 1 2' ]]
  _gpu_select_indices indices options test
  [[ ${indices[*]} == '0 1 2' ]]
  printf 'PASS interactive multi-type/per-NVIDIA-card selection, dedup and default-all parsing\n'
  exit
fi
trap 'rm -rf "$work"' EXIT
sed -n '/^  is_gpu_app() {/,/^  }/p; /^  detect_gpu_devices() {/,/^  }/p; /^  configure_gpu_passthrough() {/,/^  }/p; /^_gpu_select_indices() {/,/^}/p' \
  "$ROOT/misc/build.func" > "$work/gpu.sh"
source "$work/gpu.sh"
msg_debug() { :; }
msg_custom() { :; }
msg_info() { :; }
msg_ok() { printf '%s\n' "$*" >> "$work/ok.log"; }
msg_warn() { printf '%s\n' "$*" >> "$work/warn.log"; }
msg_error() { printf '%s\n' "$*" >&2; }
ENABLE_GPU=no var_gpu=yes
if is_gpu_app; then exit 1; fi
ENABLE_GPU=yes var_gpu=no
is_gpu_app
unset ENABLE_GPU
var_gpu=yes
is_gpu_app
printf 'PASS ENABLE_GPU overrides the script default\n'

# Redirect only filesystem roots; real character-device checks and vendor reads remain.
mkdir -p "$work/dev/dri" "$work/dev/nvidia-caps" "$work/sys/class/drm"
for spec in 'renderD128 0x8086' 'card0 0x8086' 'renderD129 0x1002' 'card1 0x1002' 'card2 0xbeef'; do
  read -r node vendor <<< "$spec"
  mkdir -p "$work/sys/class/drm/$node/device"
  printf '%s\n' "$vendor" > "$work/sys/class/drm/$node/device/vendor"
  ln -s /dev/null "$work/dev/dri/$node"
done
for node in kfd nvidia0 nvidia1 nvidiactl nvidia-uvm nvidia-caps/nvidia-cap1; do
  ln -s /dev/null "$work/dev/$node"
done
touch "$work/dev/dri/renderD999" "$work/dev/nvidia2"
sed -n '/^  detect_gpu_devices() {/,/^  }/p' "$ROOT/misc/build.func" |
  sed "s|/dev/|$work/dev/|g; s|/sys/|$work/sys/|g" > "$work/detect.sh"
source "$work/detect.sh"
detect_gpu_devices
[[ ${INTEL_DEVICES[*]} == "$work/dev/dri/renderD128 $work/dev/dri/card0" ]]
[[ ${AMD_DEVICES[*]} == "$work/dev/dri/renderD129 $work/dev/dri/card1 $work/dev/kfd" ]]
[[ ${NVIDIA_DEVICES[*]} == "$work/dev/nvidia0 $work/dev/nvidia1 $work/dev/nvidiactl $work/dev/nvidia-uvm $work/dev/nvidia-caps/nvidia-cap1" ]]
rm "$work/dev/nvidia0" "$work/dev/nvidia1"
detect_gpu_devices
[[ ${#NVIDIA_DEVICES[@]} == 0 ]]
printf 'PASS DRM sysfs ownership, AMD kfd and numbered-NVIDIA requirement\n'

source "$work/gpu.sh"
detect_gpu_devices() {
  INTEL_DEVICES=(/dev/dri/card0) AMD_DEVICES=(/dev/dri/card1 /dev/kfd)
  NVIDIA_DEVICES=(/dev/nvidia0 /dev/nvidia1 /dev/nvidiactl)
}
ENABLE_GPU=yes PHS_SILENT=1 YW='' CTID=9876 LXC_CONFIG=$work/all.conf
: > "$LXC_CONFIG"
configure_gpu_passthrough < /dev/null
[[ $GPU_TYPE == 'INTEL AMD NVIDIA' && $(wc -l < "$LXC_CONFIG") == 6 ]]
cp "$LXC_CONFIG" "$work/all-before.conf"
configure_gpu_passthrough < /dev/null
cmp "$LXC_CONFIG" "$work/all-before.conf"
ENABLE_GPU=no
configure_gpu_passthrough
[[ -z $GPU_TYPE ]]
ENABLE_GPU=yes
detect_gpu_devices() { INTEL_DEVICES=() AMD_DEVICES=() NVIDIA_DEVICES=(); }
configure_gpu_passthrough
[[ -z $GPU_TYPE ]]
printf 'PASS unattended all, repeated mapping, disabled and no-GPU context\n'
printf '2,3,3\n2,2,0,garbage\n2,3\n2\n\ngarbage\n' > "$work/input"
timeout 20 script -qec 'bash "$ROOT/tests/gpu-passthrough.test.sh" select' /dev/null \
  < "$work/input" > "$work/interactive.log" 2>&1
grep -o 'PASS.*' "$work/interactive.log"

# Run the actual GID owner with transport stubs: no real container is touched.
sed -n '/^fix_gpu_gids() {/,/^}/p' "$ROOT/misc/build.func" > "$work/gids.sh"
source "$work/gids.sh"
sleep() { :; }
pct() {
  printf '%s\n' "$*" >> "$work/pct.log"
  case "$1" in
    exec)
      if [[ $* == *'getent group video'* ]]; then
        printf '%s' "${video_gid_mock:-}"
      elif [[ $* == *'getent group render'* ]]; then printf '%s' "${render_gid_mock:-}"; fi
      ;;
    stop | set | start) [[ $1 != "${fail_pct:-}" ]] ;;
    status) printf 'status: running\n' ;;
  esac
}
GPU_TYPE='AMD NVIDIA' CT_TYPE=0 video_gid_mock=27 render_gid_mock=105
LXC_CONFIG=$work/gids.conf
cat > "$LXC_CONFIG" << 'EOF'
dev0: /dev/dri/card1,gid=44,uid=0,mode=0660
dev1: /dev/dri/renderD129,gid=44
dev2: /dev/kfd,gid=44
dev3: /dev/nvidia1,gid=44
dev4: /dev/nvidia-caps/nvidia-cap1,gid=44
dev5: /dev/unrelated,gid=44
EOF
fix_gpu_gids
grep -q -- '--dev0 /dev/dri/card1,uid=0,mode=0660,gid=27' "$work/pct.log"
grep -q -- '--dev1 /dev/dri/renderD129,gid=105,uid=0,mode=0660' "$work/pct.log"
grep -q -- '--dev2 /dev/kfd,gid=105,uid=0,mode=0660' "$work/pct.log"
grep -q -- '--dev3 /dev/nvidia1,gid=27,uid=0,mode=0660' "$work/pct.log"
grep -q -- '--dev4 /dev/nvidia-caps/nvidia-cap1,gid=27,uid=0,mode=0660' "$work/pct.log"
if grep -qE -- '--dev5|chmod|chgrp' "$work/pct.log"; then exit 1; fi
printf 'dev0: /dev/kfd,uid=0,mode=0660,gid=105\n' > "$LXC_CONFIG"
: > "$work/pct.log"
: > "$work/ok.log"
fix_gpu_gids
if grep -qE '^stop |^start |^set ' "$work/pct.log"; then exit 1; fi
[[ -s $work/ok.log ]]
video_gid_mock='' render_gid_mock=''
printf 'dev0: /dev/kfd,gid=99\ndev1: /dev/nvidia1,gid=99\n' > "$LXC_CONFIG"
: > "$work/pct.log"
fix_gpu_gids
grep -q -- '--dev0 /dev/kfd,gid=104,uid=0,mode=0660' "$work/pct.log"
grep -q -- '--dev1 /dev/nvidia1,gid=44,uid=0,mode=0660' "$work/pct.log"
grep -q 'addgroup -S video' "$work/pct.log"
grep -q 'addgroup -S render' "$work/pct.log"
for fail_pct in stop set start; do
  : > "$work/pct.log"
  : > "$work/warn.log"
  : > "$work/ok.log"
  fix_gpu_gids
  [[ -s $work/warn.log && ! -s $work/ok.log ]]
  if [[ $fail_pct == set ]]; then grep -q '^start ' "$work/pct.log"; fi
done
unset fail_pct
printf 'PASS pct-set GIDs, kfd/NVIDIA, fallbacks/Alpine, no-change and warning-only failures\n'

sed -n '/^_setup_gpu_permissions() {/,/^}/p' "$ROOT/misc/tools.func" > "$work/permissions.sh"
source "$work/permissions.sh"
getent() { return 0; }
usermod() {
  printf '%s\n' "$*" >> "$work/usermod.log"
  printf 'quiet error\n' >&2
  return 1
}
chmod() { printf 'MUTATED\n' >> "$work/mutated"; }
chgrp() { printf 'MUTATED\n' >> "$work/mutated"; }
sed() { printf 'MUTATED\n' >> "$work/mutated"; }
_setup_gpu_permissions 0 app 2> "$work/permissions.err"
_setup_gpu_permissions 1 '' 2>> "$work/permissions.err"
[[ ! -s $work/permissions.err && ! -e $work/mutated ]]
grep -q -- '-aG render app' "$work/usermod.log"
grep -q -- '-aG video app' "$work/usermod.log"
grep -q -- '-aG render root' "$work/usermod.log"
unset -f sed chmod chgrp
printf 'PASS guest permission setup is quiet group-membership-only for both CT types\n'

# Observe the consumer of a real generated bundle, including quoted multi-type context.
source "$ROOT/misc/bundle.func"
SESSION_ID="gpu-test-$$" cache="$TMPDIR/framework-gpu-test-$$"
test ! -e "$cache"
mkdir -m 700 "$cache"
trap 'rm -rf "$work" "$cache"' EXIT
var_lxc_tmpdir="$work/receiving-tmp"
printf 'load_functions() { :; }; color() { :; }\n' > "$cache/core.func"
printf 'catch_errors() { :; }\n' > "$cache/error_handler.func"
printf 'setup_lxc() { :; }\n' > "$cache/install.func"
printf 'setup_uv() { :; }\n' > "$cache/tools.func"
printf 'clone_and_deploy_gh_commit() { :; }\n' > "$cache/github.func"
_framework_cache_ensure() { :; }
pct() {
  [[ "$2" == 9876 ]] || return 99
  case "$1" in
    push)
      [[ "$3" == "$TMPDIR/update-bundle-$SESSION_ID".* && "$4" == "$work/bundle.sh".* ]] || return 99
      cp -- "$3" "$4"
      ;;
    exec)
      [[ "$3" == -- ]] || return 99
      shift 3
      case "$1" in mktemp | chmod | mv | rm) ;; *) return 99 ;; esac
      local argument
      for argument in "${@:2}"; do
        case "$argument" in "$work/"* | 0700 | -f | --) ;; *) return 99 ;; esac
      done
      "$@"
      ;;
    *) return 99 ;;
  esac
}
APP=Probe NSAPP=probe REPO_BASE=offline CTID=9876
ENABLE_GPU=yes GPU_TYPE='AMD NVIDIA' INSTALL_NVIDIA_DRIVERS=no CT_TYPE=0
update_script() { printf '%s|%s|%s|%s\n' "$ENABLE_GPU" "$GPU_TYPE" "$INSTALL_NVIDIA_DRIVERS" "$CTTYPE"; }
build_bundle update update_script "$work/bundle.sh" 0700 update_script
[[ $(bash "$work/bundle.sh") == 'yes|AMD NVIDIA|no|0' ]]
unset ENABLE_GPU GPU_TYPE INSTALL_NVIDIA_DRIVERS CT_TYPE
build_bundle update update_script "$work/bundle.sh" 0700 update_script
[[ $(bash "$work/bundle.sh") == 'no|||1' ]]
printf 'PASS generated bundles preserve selected-GPU context and safe defaults\n'
