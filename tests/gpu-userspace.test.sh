#!/usr/bin/env bash
# Userspace follows mapped GPUs; optional packages never turn a GPU into install failure.
# Extracted functions consume globals and intentionally replace later test stubs.
# shellcheck disable=SC2034,SC2218
set -euo pipefail
ROOT=$(realpath "$(dirname "${BASH_SOURCE[0]}")/..")
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT
mkdir -p "$work/dev/dri" "$work/sys/class/drm" "$work/releases"
sed -n '/^_hwaccel_optional_command() /,/^# Helper: Add Debian non-free repositories/p' "$ROOT/misc/tools.func" |
  sed "s|/dev/dri|$work/dev/dri|g; s|/dev/nvidia|$work/dev/nvidia|g; s|/dev/kfd|$work/dev/kfd|g; s|/sys/class/drm|$work/sys/class/drm|g; s|/tmp/gh_rel.json|$work/releases/gh_rel.json|g" > "$work/gpu.sh"
# Source current main too, for the red control before the optional helper exists.
if [[ ! -s $work/gpu.sh ]]; then
  sed -n '/^setup_hwaccel() {/,/^# Helper: Add Debian non-free repositories/p' "$ROOT/misc/tools.func" > "$work/gpu.sh"
fi
source "$work/gpu.sh"
msg_info() { :; }
msg_ok() { :; }
msg_custom() { :; }
msg_warn() { printf '%s\n' "$*" >> "$work/warnings"; }
get_active_logfile() { printf '%s\n' "$work/active.log"; }
silent() {
  printf 'FATAL silent called\n' >&2
  exit 91
}
STD=silent
apt() {
  printf '%s\n' "$*" >> "$work/apt.calls"
  printf 'apt diagnostic: %s\n' "$*" >&2
  [[ $* != *missing* && $* != *broken* && ${apt_fail:-no} != yes ]]
}
apt-cache() {
  if [[ $* == *missing* ]]; then printf 'Candidate: (none)\n'; else printf 'Candidate: 1.0\n'; fi
}
_hwaccel_apt_optional good missing broken
grep -q 'install good$' "$work/apt.calls"
grep -q 'unavailable.*missing' "$work/warnings"
grep -q 'could not be installed.*broken' "$work/warnings"
grep -q 'apt diagnostic' "$work/active.log"
[[ $STD == silent ]]
# Nested framework helpers also use the direct logger, not silent().
optional_nested() { $STD apt -y install missing; }
if _hwaccel_optional_command optional_nested; then exit 1; fi
printf 'PASS optional batch fallback, warning classification, direct active logging and nested STD containment\n'

_add_debian_nonfree() { :; }
_add_debian_nonfree_firmware() { :; }
fetch_and_deploy_gh_release() {
  printf '%s|%s|%s\n' "$1" "$4" "${6:-}" >> "$work/releases.calls"
  if [[ $1 == libigdgmm12 ]]; then
    cp "$work/metadata" "$work/releases/gh_rel.json"
  fi
  if [[ ${fetch_fail:-no} == yes ]]; then exit 92; fi
}
for intel in _setup_intel_arc _setup_intel_modern; do
  printf '[{"body":"Compiler: https://github.com/intel/intel-graphics-compiler/releases/tag/v2.7.1"}]\n' > "$work/metadata"
  : > "$work/releases.calls"
  : > "$work/apt.calls"
  "$intel" debian trixie
  grep -q '^intel-igc-core|v2.7.1|' "$work/releases.calls"
  grep -q '^intel-igc-opencl|v2.7.1|' "$work/releases.calls"
  [[ $(head -1 "$work/apt.calls") == '-y install ocl-icd-libopencl1' ]]
  grep -q 'mesa-vulkan-drivers' "$work/apt.calls"
  grep -q 'libvpl2' "$work/apt.calls"
  printf '{"body":"no compiler pin"}\n' > "$work/metadata"
  : > "$work/releases.calls"
  "$intel" debian trixie
  [[ $(wc -l < "$work/releases.calls") == 1 ]]
  printf '{"body":"https://github.com/intel/intel-graphics-compiler/releases/tag/latest"}\n' > "$work/metadata"
  : > "$work/releases.calls"
  "$intel" debian trixie
  [[ $(wc -l < "$work/releases.calls") == 1 ]]
  fetch_fail=yes "$intel" debian trixie
done
printf 'PASS Intel prerequisite order, pinned IGC from array metadata, unresolved pin skips OpenCL, contained release failures\n'
for intel in _setup_intel_arc _setup_intel_modern _setup_intel_legacy; do
  apt_fail=yes "$intel" ubuntu noble
done
printf 'PASS all Intel paths tolerate missing optional packages\n'

_setup_rocm() { printf 'rocm\n' >> "$work/rocm.calls"; }
_setup_amd_gpu ubuntu noble
[[ ! -e $work/rocm.calls ]]
ln -s /dev/null "$work/dev/kfd"
_setup_amd_gpu ubuntu noble
[[ $(wc -l < "$work/rocm.calls") == 1 ]]
rm "$work/dev/kfd"
printf 'PASS AMD ROCm requires mapped kfd\n'

# Exercise ROCm's own guard, repository failure and apt retries in a private tree.
mkdir -p "$work/etc/apt/preferences.d"
sed -n '/^_setup_rocm() {/,/^}/p' "$ROOT/misc/tools.func" |
  sed "s|/dev/kfd|$work/dev/kfd|g; s|/etc/|$work/etc/|g; s|/opt/rocm|$work/opt/rocm|g" > "$work/rocm.sh"
source "$work/rocm.sh"
dpkg() { printf 'amd64\n'; }
setup_deb822_repo() {
  printf '%s\n' "$*" >> "$work/repo.calls"
  [[ ${repo_fail:-no} != yes ]]
}
sleep() { :; }
usermod() { :; }
_setup_rocm ubuntu noble
[[ ! -e $work/repo.calls ]]
ln -s /dev/null "$work/dev/kfd"
repo_fail=yes _setup_rocm ubuntu noble
apt_fail=yes _setup_rocm ubuntu noble
: > "$work/apt.calls"
_setup_rocm ubuntu noble
grep -q 'rocm-opencl-runtime rocm-hip-runtime rocm-smi-lib' "$work/apt.calls"
rm "$work/dev/kfd"
printf 'PASS ROCm own kfd guard, repository failure, update retries and direct runtime install\n'

# Only filesystem roots are redirected; device/vendor checks and subtype lookup run.
for spec in 'card0 0x8086 0000:00:02.0' 'renderD128 0x8086 0000:00:02.0' 'card1 0x1002 0000:01:00.0'; do
  read -r node vendor address <<< "$spec"
  mkdir -p "$work/sys/devices/$address" "$work/sys/class/drm/$node"
  printf '%s\n' "$vendor" > "$work/sys/devices/$address/vendor"
  ln -s "$work/sys/devices/$address" "$work/sys/class/drm/$node/device"
  ln -s /dev/null "$work/dev/dri/$node"
done
ln -s /dev/null "$work/dev/nvidia1"
get_os_info() {
  case $1 in id) printf 'ubuntu' ;; codename) printf 'noble' ;; version) printf '24.04' ;; esac
}
cache_installed_version() { :; }
_setup_gpu_permissions() { printf '%s\n' "$*" > "$work/permissions"; }
_setup_intel_arc() { printf 'arc\n' >> "$work/setup.calls"; }
_setup_intel_modern() { printf 'modern\n' >> "$work/setup.calls"; }
_setup_intel_legacy() { printf 'legacy\n' >> "$work/setup.calls"; }
_setup_amd_gpu() { printf 'amd\n' >> "$work/setup.calls"; }
_setup_nvidia_gpu() { printf 'nvidia\n' >> "$work/setup.calls"; }
ldconfig() { printf '%s\n' "${test_libraries:-libva.so.2 libvulkan.so.1 libcuda.so.1}"; }
lspci() {
  printf '%s\n' "$*" >> "$work/pci.calls"
  printf '%s\n' "${test_description:-Intel Arc A770}"
}
ENABLE_GPU=yes GPU_TYPE=INTEL INSTALL_NVIDIA_DRIVERS=yes CTTYPE=1 GN='' TAB3=''
setup_hwaccel app < /dev/null
[[ $(cat "$work/setup.calls") == arc && $HWACCEL_VENDOR == intel && $HWACCEL_VENDORS == intel ]]
grep -q -- '-s 0000:00:02.0' "$work/pci.calls"
[[ $(cat "$work/permissions") == '1 app' ]]
printf 'PASS selected mapped Intel only, per-device PCI subtype and deduplicated setup\n'
: > "$work/setup.calls"
GPU_TYPE='INTEL AMD NVIDIA'
test_description='Intel HD Graphics 4600' setup_hwaccel
[[ $(cat "$work/setup.calls") == $'legacy\namd\nnvidia' ]]
[[ $HWACCEL_VENDOR == nvidia && $HWACCEL_VENDORS == 'intel amd nvidia' ]]
[[ $(bash -c 'printf "%s|%s" "$HWACCEL_VENDOR" "$HWACCEL_VENDORS"') == 'nvidia|intel amd nvidia' ]]
# No UVM or control node is needed to report existing NVIDIA userspace usable.
for INSTALL_NVIDIA_DRIVERS in no YES n; do
  : > "$work/setup.calls"
  GPU_TYPE=NVIDIA setup_hwaccel
  [[ ! -s $work/setup.calls && $HWACCEL_VENDOR == nvidia ]]
done
: > "$work/setup.calls"
GPU_TYPE=NVIDIA INSTALL_NVIDIA_DRIVERS=yes test_libraries=libva.so.2 setup_hwaccel
[[ $HWACCEL_VENDOR == none && -z $HWACCEL_VENDORS ]]
printf 'PASS mixed mapped vendors, NVIDIA any-node/libcuda usability and literal yes installation policy\n'

# Main prompts on an unset/empty choice; EOF and an empty answer default to yes.
unset INSTALL_NVIDIA_DRIVERS
: > "$work/setup.calls"
GPU_TYPE=NVIDIA setup_hwaccel < /dev/null
[[ $(cat "$work/setup.calls") == nvidia ]]
for reply in '' n no; do
  : > "$work/setup.calls"
  GPU_TYPE=NVIDIA INSTALL_NVIDIA_DRIVERS='' setup_hwaccel <<< "$reply"
  if [[ -z $reply ]]; then
    [[ $(cat "$work/setup.calls") == nvidia ]]
  else
    [[ ! -s $work/setup.calls ]]
  fi
done
for INSTALL_NVIDIA_DRIVERS in yes no; do
  : > "$work/setup.calls"
  GPU_TYPE=NVIDIA setup_hwaccel < /dev/null
  if [[ $INSTALL_NVIDIA_DRIVERS == yes ]]; then
    [[ $(cat "$work/setup.calls") == nvidia ]]
  else
    [[ ! -s $work/setup.calls ]]
  fi
done
printf 'PASS NVIDIA unset/EOF and empty input install by default; explicit no skips and yes installs\n'

# An AMD CPU and host-visible PCI GPUs cannot manufacture a mapped GPU.
rm "$work/dev/dri/"* "$work/dev/nvidia1"
ln -s /dev/null "$work/dev/nvidiactl"
: > "$work/setup.calls"
GPU_TYPE=NVIDIA INSTALL_NVIDIA_DRIVERS=yes setup_hwaccel
[[ $HWACCEL_VENDOR == nvidia && $(cat "$work/setup.calls") == nvidia ]]
rm "$work/dev/nvidiactl"
: > "$work/setup.calls"
# Use the real warning function to observe the terminal spinner-stop contract.
sed -n '/^msg_warn() {/,/^}/p' "$ROOT/misc/core.func" > "$work/warn.sh"
source "$work/warn.sh"
stop_spinner() { spinner_active=no; }
log_msg() { printf '%s\n' "$*" >> "$work/warnings"; }
YWB='' CL='' spinner_active=yes
GPU_TYPE='INTEL AMD NVIDIA' setup_hwaccel
[[ ! -s $work/setup.calls && $HWACCEL_VENDOR == none && -z $HWACCEL_VENDORS && $spinner_active == no ]]
ENABLE_GPU=no setup_hwaccel
[[ $HWACCEL_VENDOR == none && -z $HWACCEL_VENDORS ]]
printf 'PASS control-only NVIDIA node, no mapped GPUs and disabled GPU reset exported state\n'

# Exercise the pciutils-missing branch without changing PATH or the real guest.
ln -s /dev/null "$work/dev/dri/card0"
command() {
  if [[ $* == '-v lspci' ]]; then return 1; fi
  builtin command "$@"
}
: > "$work/apt.calls"
GPU_TYPE=INTEL INSTALL_NVIDIA_DRIVERS=no setup_hwaccel
grep -q 'install pciutils' "$work/apt.calls"
printf 'PASS pciutils is requested through optional installation before Intel subtype detection\n'
