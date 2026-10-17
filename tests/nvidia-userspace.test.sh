#!/usr/bin/env bash
# NVIDIA packages follow the host version; optional failures must not abort installs.
# Extracted functions read test globals and invoke the stubs below.
# shellcheck disable=SC2034,SC2218
set -euo pipefail
ROOT=$(realpath "$(dirname "${BASH_SOURCE[0]}")/..")
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT
mkdir -p "$work/etc/apt/sources.list.d" "$work/etc/apt/preferences.d" "$work/proc/driver/nvidia" "$work/dev"
sed -n '/^_hwaccel_optional_command() /,/^setup_hwaccel() {/p' "$ROOT/misc/tools.func" | sed '$d' > "$work/optional.sh"
source "$work/optional.sh"
{
  sed -n '/^_nvidia_pick_version() {/,/^}/p' "$ROOT/misc/tools.func"
  sed -n '/^_setup_nvidia_gpu() {/,/^}/p' "$ROOT/misc/tools.func"
} | sed "s|/etc/|$work/etc/|g; s|/proc/driver/nvidia|$work/proc/driver/nvidia|g; s|/dev/nvidia|$work/dev/nvidia|g; s|/usr/lib/|$work/usr/lib/|g; s|/usr/share/|$work/usr/share/|g" > "$work/nvidia.sh"
source "$work/nvidia.sh"
msg_info() { printf 'INFO %s\n' "$*" >> "$work/messages"; }
msg_ok() { printf 'OK %s\n' "$*" >> "$work/messages"; }
msg_warn() { printf 'WARN %s\n' "$*" >> "$work/messages"; }
msg_error() { printf 'ERROR %s\n' "$*" >> "$work/messages"; }
msg_custom() { printf '%s\n' "$*" >> "$work/messages"; }
get_active_logfile() { printf '%s\n' "$work/active.log"; }
silent() {
  printf 'FATAL silent called\n' >&2
  exit 91
}
STD=silent YW=''
apt() {
  printf '%s\n' "$*" >> "$work/apt.calls"
  printf 'apt diagnostic: %s\n' "$*" >&2
  if [[ $* == *update* ]]; then
    [[ ${fail_update:-no} != yes ]]
    return
  fi
  [[ ${fail_install:-no} != yes && ! ($* == *libcuda1=* && ${fail_cuda:-no} == yes) ]]
}
apt-get() { apt "$@"; }
dpkg() {
  printf 'unexpected dpkg\n' >&2
  exit 92
}
setup_deb822_repo() {
  printf '%s|%s|%s|%s|%s|%s\n' "$1" "$2" "$3" "$4" "${5:-}" "${6:-}" >> "$work/repo.calls"
  printf 'URIs: %s\n' "$3" > "$work/etc/apt/sources.list.d/$1.sources"
  if [[ ${fail_repo:-no} == yes ]]; then exit 93; fi
  $STD apt update
}
_add_debian_nonfree() {
  printf 'Components: contrib non-free non-free-firmware\n' > "$work/etc/apt/sources.list.d/non-free.sources"
  $STD apt update
}
apt-cache() {
  [[ $1 == madison ]] || {
    printf 'Candidate: available\n'
    return
  }
  local fixture=native uri
  for uri in "$work/etc/apt/sources.list.d/"cuda-community-scripts.*; do
    [[ -f $uri ]] || continue
    fixture=$(grep '^URIs:' "$uri" | cut -d/ -f7)
  done
  printf '%s|%s\n' "$fixture" "$2" >> "$work/cache.calls"
  if [[ $2 == libnvidia-compute-* ]]; then
    fixture=ubuntu-native
  fi
  if [[ -f $work/$fixture.versions ]]; then
    while IFS= read -r version; do printf ' %s | %s | fixture\n' "$2" "$version"; done < "$work/$fixture.versions"
  fi
}
ldconfig() { printf '%s\n' "${test_libraries:-libcuda.so.1}"; }
update-glx() { $STD apt glx-fallback; }
reset_case() {
  rm -f "$work/etc/apt/sources.list.d/"* "$work/"*.versions "$work/proc/driver/nvidia/version" "$work/dev/"*
  : > "$work/apt.calls"
  : > "$work/repo.calls"
  : > "$work/messages"
  : > "$work/cache.calls"
  : > "$work/active.log"
  printf 'Components: main\n' > "$work/etc/apt/sources.list.d/debian.sources"
  printf 'NVRM version: NVIDIA UNIX x86_64 Kernel Module  535.183.01  Thu\n' > "$work/proc/driver/nvidia/version"
  ln -s /dev/null "$work/dev/nvidia0"
}
reset_case
printf 'deb old-keyring-source\n' > "$work/etc/apt/sources.list.d/cuda-debian13-x86_64.list"
printf 'deb old-framework-source\n' > "$work/etc/apt/sources.list.d/cuda-community-scripts.list"
printf '590.48.01-1\n535.200.01-1\n535.183.01-1\n' > "$work/debian12.versions"
_setup_nvidia_gpu debian trixie 13
grep -q 'libcuda1=535.183.01-1 ' "$work/apt.calls"
[[ $(wc -l < "$work/repo.calls") == 2 ]]
grep -q '/debian13/' <(head -1 "$work/repo.calls")
grep -q '/debian12/' <(tail -1 "$work/repo.calls")
grep -q '/debian12/' "$work/etc/apt/sources.list.d/cuda-community-scripts.sources"
if grep -q '/debian13/' "$work/etc/apt/sources.list.d/"*; then
  printf 'FAIL rejected Debian 13 source remains enabled\n' >&2
  exit 1
fi
grep -q 'non-free' "$work/etc/apt/sources.list.d/"*.sources
if grep -q '^Package: \*$' "$work/etc/apt/preferences.d/nvidia-cuda-pin"; then
  printf 'FAIL NVIDIA pin covers all packages\n' >&2
  exit 1
fi
grep -q '^Package: libcuda.*libnvidia-' "$work/etc/apt/preferences.d/nvidia-cuda-pin"
[[ $STD == silent ]]
[[ ! -e $work/etc/apt/sources.list.d/cuda-debian13-x86_64.list && ! -e $work/etc/apt/sources.list.d/cuda-community-scripts.list ]]
grep -q '|/||amd64$' "$work/repo.calls"
printf 'PASS trixie tries debian13 then debian12, exact host release wins, sources isolated and pin scoped\n'

reset_case
printf '590.48.01-1\n580.126.20-1\n' > "$work/debian11.versions"
printf '590.48.01-1\n535.200.01-1\n' > "$work/debian12.versions"
_setup_nvidia_gpu debian bullseye 11
grep -q 'libcuda1=535.200.01-1 ' "$work/apt.calls"
grep -q 'differs from.*535.183.01' "$work/messages"
grep -q '/debian11/' <(head -1 "$work/repo.calls")
if grep -q 'libcuda1=590\|libcuda1=580' "$work/apt.calls"; then
  printf 'FAIL NVIDIA fallback crossed driver series\n' >&2
  exit 1
fi
printf 'PASS bullseye candidate order and same-series fallback warn without crossing series\n'

reset_case
printf '535.183.01-1\n' > "$work/native.versions"
_setup_nvidia_gpu debian bookworm 12
grep -q 'libcuda1=535.183.01-1 ' "$work/apt.calls"
[[ $(wc -l < "$work/repo.calls") == 1 ]]
[[ ! -e $work/etc/apt/sources.list.d/cuda-community-scripts.sources ]]
grep -q 'Debian non-free' "$work/messages"
printf 'PASS bookworm removes rejected CUDA source before Debian non-free fallback\n'

reset_case
printf '590.48.01-1\n' > "$work/native.versions"
_setup_nvidia_gpu debian sid 13
if grep -q 'install.*\(libcuda\|libnvidia\|nvidia-smi\)' "$work/apt.calls"; then
  printf 'FAIL NVIDIA packages installed without a matching series\n' >&2
  exit 1
fi
grep -q 'No NVIDIA 535.x' "$work/messages"
[[ ! -e $work/etc/apt/sources.list.d/cuda-community-scripts.sources ]]
printf 'PASS no same-series version installs no NVIDIA packages, including nvidia-smi\n'

for os_release in 22.04 24.04; do
  reset_case
  printf '590.48.01-1\n535.200.01-1\n535.183.01-1\n' > "$work/ubuntu${os_release/./}.versions"
  _setup_nvidia_gpu ubuntu noble "$os_release"
  grep -q 'libcuda1=535.183.01-1 ' "$work/apt.calls"
  [[ $(wc -l < "$work/repo.calls") == 1 ]]
done
printf 'PASS Ubuntu CUDA candidate matches OS and prefers exact host release\n'

for reason in absent failed; do
  reset_case
  if [[ $reason == failed ]]; then printf '535.183.01-1\n' > "$work/ubuntu2404.versions"; fi
  printf '590.48.01-0ubuntu1\n535.200.01-0ubuntu1\n535.183.01-0ubuntu1\n' > "$work/ubuntu-native.versions"
  fail_cuda=yes _setup_nvidia_gpu ubuntu noble 24.04
  grep -q 'libnvidia-compute-535=535.183.01-0ubuntu1' "$work/apt.calls"
  grep -q 'nvidia-utils-535=535.183.01-0ubuntu1' "$work/apt.calls"
  [[ ! -e $work/etc/apt/sources.list.d/cuda-community-scripts.sources ]]
done
printf 'PASS Ubuntu native compute/decode/encode/utils fallback after missing or failed CUDA install\n'

reset_case
printf '590.48.01-0ubuntu1\n' > "$work/ubuntu-native.versions"
_setup_nvidia_gpu ubuntu noble 24.04
if grep -q 'install.*\(libcuda\|libnvidia\|nvidia-utils\)' "$work/apt.calls"; then
  printf 'FAIL Ubuntu native fallback crossed driver series\n' >&2
  exit 1
fi
printf 'PASS Ubuntu native fallback also refuses a different driver series\n'

for failure in fail_install fail_update fail_repo; do
  reset_case
  printf '535.183.01-1\n' > "$work/debian12.versions"
  printf '535.183.01-1\n' > "$work/native.versions"
  (
    export "$failure=yes"
    _setup_nvidia_gpu debian trixie 13
  )
  grep -q '^WARN' "$work/messages"
  if grep -qE 'install .* (libcuda1|libnvcuvid1|libnvidia-encode1|libnvidia-ml1|nvidia-smi)( |$)' "$work/apt.calls"; then
    printf 'FAIL optional NVIDIA failure retried unpinned packages\n' >&2
    exit 1
  fi
  grep -q 'apt diagnostic:' "$work/active.log"
done
reset_case
printf '535.183.01-1\n' > "$work/ubuntu2404.versions"
printf '535.183.01-0ubuntu1\n' > "$work/ubuntu-native.versions"
fail_install=yes _setup_nvidia_gpu ubuntu noble 24.04
grep -q '^WARN' "$work/messages"
printf 'PASS optional repo/update/install failures stay nonfatal, logged and never retry unpinned\n'

reset_case
rm "$work/proc/driver/nvidia/version"
fail_install=yes _setup_nvidia_gpu debian trixie 13
[[ ! -s $work/repo.calls ]]
grep -q 'host driver version not found' "$work/messages"
printf 'PASS missing host version skips NVIDIA repositories and tolerates missing hybrid VA-API packages\n'

reset_case
printf 'NVRM version: NVIDIA UNIX Open Kernel Module for x86_64  590.48.01  Release\n' > "$work/proc/driver/nvidia/version"
printf '590.48.01-1\n' > "$work/debian13.versions"
_setup_nvidia_gpu debian trixie 13
grep -q 'libcuda1=590.48.01-1' "$work/apt.calls"
[[ $(wc -l < "$work/repo.calls") == 1 ]]
printf 'PASS open kernel module version parsed and first matching candidate retained\n'

reset_case
printf '535x183x01-1\n535.183.010-1\n535.183.01-2\n' > "$work/native.versions"
[[ $(_nvidia_pick_version libcuda1 535.183.01) == 535.183.01-2 ]]
printf 'PASS exact matcher requires literal dots and full release boundary\n'

reset_case
rm "$work/etc/apt/sources.list.d/debian.sources"
printf '535.183.01-1\n' > "$work/native.versions"
_setup_nvidia_gpu debian bookworm 12
grep -q 'non-free' "$work/etc/apt/sources.list.d/non-free.sources"
printf 'PASS legacy Debian sources enable non-free through existing optional helper\n'

reset_case
printf 'Components: main non-free-firmware\n' > "$work/etc/apt/sources.list.d/debian.sources"
printf '535.183.01-1\n' > "$work/native.versions"
_setup_nvidia_gpu debian bookworm 12
grep -Eq '^Components:.*[[:space:]]non-free([[:space:]]|$)' "$work/etc/apt/sources.list.d/debian.sources"
printf 'PASS non-free-firmware alone does not count as Debian non-free enabled\n'

reset_case
mkdir -p "$work/usr/lib/mesa-diverted"
printf '535.183.01-1\n' > "$work/debian12.versions"
fail_install=yes _setup_nvidia_gpu debian bookworm 12
grep -q 'glx-fallback' "$work/apt.calls"
grep -q 'Could not restore Mesa' "$work/messages"
rm "$work/dev/nvidia0"
test_libraries='' _setup_nvidia_gpu debian bookworm 12
grep -q 'NVIDIA GPU not usable' "$work/messages"
printf 'PASS GLX failure stays optional and missing devices never report configured\n'
