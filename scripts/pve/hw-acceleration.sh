#!/usr/bin/env bash
REPO_BASE="${REPO_BASE:-https://raw.githubusercontent.com/scripts-underground/proxmox/main}"
#
# Title: Proxmox LXC Hardware Passthrough & GPU Acceleration Setup
# Description: Enables hardware passthrough for USB, Intel, NVIDIA, AMD GPUs inside privileged LXC containers.
#              Installs optional drivers/tools inside the container (vainfo, intel-gpu-tools, OpenCL, etc.)
#              Only supports PRIVILEGED containers for GPU passthrough.
# License: MIT
# Author: MickLesk (CanbiZ)
# Repo: https://raw.githubusercontent.com/scripts-underground/proxmox
#
# Usage: bash -c "$(wget -qLO - https://raw.githubusercontent.com/scripts-underground/proxmox/main/scripts/pve/hw-acceleration.sh)"
#
# Requires:
#   - Proxmox VE 8.1+
#   - Privileged LXC Containers
#   - GPU device available on host
#
# Features:
#   - USB Serial Passthrough
#   - Intel VAAPI passthrough + (optional) non-free drivers
#   - NVIDIA GPU passthrough for LXC (binds /dev/nvidia*)
#   - AMD GPU passthrough (experimental)
#   - Container driver installation via APT
#   - User group assignments (video/render)
#   - Interactive menu system via whiptail
#
# Proxmox LXC Hardware Passthrough & GPU Acceleration Setup
# https://raw.githubusercontent.com/scripts-underground/proxmox

set -euo pipefail

# NVIDIA is optional. Load declarations once in a fresh strict shell so a failed
# source (including an explicit exit) cannot terminate unrelated feature paths.
_NVIDIA_HELPERS_READY=0
unset -f nvidia_helper_contents nvidia_gpu_available nvidia_validate_driver_version \
  nvidia_validate_cuda_version nvidia_select_gpu_minor nvidia_lxc_passthrough
if _nv_source=$(wget -qO- "$REPO_BASE/tools/pve/gpu-nvidia.func"); then
  if _nv_functions=$(BASH_ENV=/dev/null /bin/bash -euo pipefail -c '
    source /dev/stdin >&2
    declare -F nvidia_helper_contents >/dev/null
    nvidia_helper_contents
    printf "\n# NVIDIA_DECLARATIONS_COMPLETE\n"
  ' <<< "$_nv_source"); then
    if [[ "$_nv_functions" == *$'\n# NVIDIA_DECLARATIONS_COMPLETE' && -n "${_nv_functions%$'\n# NVIDIA_DECLARATIONS_COMPLETE'}" ]]; then
      # shellcheck disable=SC1090
      if source /dev/stdin <<< "${_nv_functions%$'\n# NVIDIA_DECLARATIONS_COMPLETE'}"; then
        _NVIDIA_HELPERS_READY=1
      fi
    fi
  fi
fi
unset _nv_source _nv_functions
# shellcheck disable=SC1090
# Dynamic URL resolved at runtime - shellcheck cannot follow
source <(wget -qO- "$REPO_BASE/tools/pve/gpu-intel.func")
# shellcheck disable=SC1090
# Dynamic URL resolved at runtime - shellcheck cannot follow
source <(wget -qO- "$REPO_BASE/tools/pve/gpu-amd.func")

function header_info() {
  terminal_clear
  cat << "EOF"

   __ ___      __  ___              __             __  _
  / // / | /| / / / _ |___________ / /__ _______ _/ /_(_)__  ___
 / _  /| |/ |/ / / __ / __/ __/ -_) / -_) __/ _ `/ __/ / _ \/ _ \
/_//_/ |__/|__/ /_/ |_\__/\__/\__/_/\__/_/  \_,_/\__/_/\___/_//_/

   LXC Hardware Integration Tool for Proxmox VE
EOF
}

function msg() {
  local type="$1"
  shift
  case "$type" in
    info) printf " \033[36m➤\033[0m %s\n" "$@" ;;
    ok) printf " \033[32m✔\033[0m %s\n" "$@" ;;
    warn) printf " \033[33m⚠\033[0m %s\n" "$@" >&2 ;;
    err) printf " \033[31m✘\033[0m %s\n" "$@" >&2 ;;
  esac
}

function prompt_features() {
  local features=()
  printf "\nAvailable features:\n"
  if [[ -e /dev/ttyUSB0 || -e /dev/ttyACM0 ]]; then
    echo " [1] USB Passthrough"
    features+=("usb")
  fi
  if [[ -e /dev/dri/renderD128 ]]; then
    echo " [2] Intel iGPU (VAAPI)"
    features+=("intel")
  fi
  if [[ "$_NVIDIA_HELPERS_READY" == 1 ]] && declare -F nvidia_gpu_available > /dev/null && (nvidia_gpu_available); then
    echo " [3] NVIDIA GPU"
    features+=("nvidia")
  fi
  if [[ -e /dev/kfd ]]; then
    echo " [4] AMD GPU (ROCm)"
    features+=("amd")
  fi

  if [[ ${#features[@]} -eq 0 ]]; then
    msg err "No supported hardware found on host."
    exit 1
  fi

  echo
  read -rp "Enter number(s) separated by space (e.g. 1 3): " choices
  SELECTED_FEATURES=()
  for i in $choices; do
    case "$i" in
      1) SELECTED_FEATURES+=("usb") ;;
      2) SELECTED_FEATURES+=("intel") ;;
      3) SELECTED_FEATURES+=("nvidia") ;;
      4) SELECTED_FEATURES+=("amd") ;;
    esac
  done

  if [[ ${#SELECTED_FEATURES[@]} -eq 0 ]]; then
    msg warn "No valid feature selected."
    exit 1
  fi
}

function select_lxc_cts() {
  mapfile -t containers < <(pct list | awk 'NR>1 {print $1 "|" $2}')
  if [[ ${#containers[@]} -eq 0 ]]; then
    msg warn "No LXC containers found."
    exit 1
  fi

  echo
  echo "Available Containers:"
  for entry in "${containers[@]}"; do
    ctid="${entry%%|*}"
    name="${entry##*|}"
    echo " [$ctid] $name"
  done

  echo
  read -rp "Enter container ID(s) separated by space: " SELECTED_CTIDS
  if [[ -z "$SELECTED_CTIDS" ]]; then
    msg warn "No containers selected."
    exit 1
  fi
}

function apply_usb_passthrough() {
  local conf="$1"
  grep -q "ttyUSB" "$conf" 2> /dev/null && return
  cat << EOF >> "$conf"
# USB Passthrough
lxc.cgroup2.devices.allow: a
lxc.cap.drop:
lxc.cgroup2.devices.allow: c 188:* rwm
lxc.cgroup2.devices.allow: c 189:* rwm
lxc.mount.entry: /dev/serial/by-id  dev/serial/by-id  none bind,optional,create=dir
lxc.mount.entry: /dev/ttyUSB0       dev/ttyUSB0       none bind,optional,create=file
lxc.mount.entry: /dev/ttyUSB1       dev/ttyUSB1       none bind,optional,create=file
lxc.mount.entry: /dev/ttyACM0       dev/ttyACM0       none bind,optional,create=file
lxc.mount.entry: /dev/ttyACM1       dev/ttyACM1       none bind,optional,create=file
EOF
}

function nvidia_support_available() {
  local api
  if [[ "$_NVIDIA_HELPERS_READY" != 1 ]]; then
    msg err "NVIDIA helper load failed; NVIDIA integration unavailable"
    return 1
  fi
  for api in nvidia_gpu_available nvidia_validate_driver_version nvidia_validate_cuda_version nvidia_select_gpu_minor nvidia_lxc_passthrough; do
    if ! declare -F "$api" > /dev/null; then
      msg err "NVIDIA helper API unavailable: $api"
      return 1
    fi
  done
  if ! (nvidia_gpu_available); then
    msg err "NVIDIA availability check failed; no NVIDIA effects applied"
    return 1
  fi
}

function main() {
  header_info
  prompt_features
  select_lxc_cts

  local updated_cts=() partial_cts=() failed_cts=() result=0 gpu_minor restart='' rc state

  for ctid in $SELECTED_CTIDS; do
    local conf="/etc/pve/lxc/${ctid}.conf"
    local updated=0
    local failed=0

    for feature in "${SELECTED_FEATURES[@]}"; do
      case "$feature" in
        usb)
          msg info "Applying USB passthrough to CT $ctid..."
          if apply_usb_passthrough "$conf"; then updated=1; else failed=1; fi
          ;;
        intel)
          msg info "Applying Intel VAAPI passthrough to CT $ctid..."
          if passthrough_intel_to_lxc "$ctid"; then
            updated=1
            if ! install_intel_tools_in_ct "$ctid"; then failed=1; fi
          else failed=1; fi
          ;;
        amd)
          msg info "Applying AMD GPU passthrough to CT $ctid..."
          if passthrough_amd_to_lxc "$ctid"; then
            updated=1
            if ! install_amd_tools_in_ct "$ctid"; then failed=1; fi
          else failed=1; fi
          ;;
        nvidia)
          msg info "Checking NVIDIA GPU on host..."
          if ! nvidia_support_available; then
            failed=1
          elif ! nvidia_validate_driver_version; then
            failed=1
          elif ! nvidia_validate_cuda_version; then
            failed=1
          elif ! gpu_minor=$(nvidia_select_gpu_minor); then
            failed=1
          elif nvidia_lxc_passthrough "$ctid" "$gpu_minor"; then
            updated=1
          else
            failed=1
          fi
          ;;
      esac
    done

    if [[ "$failed" == 1 ]]; then
      result=1
      failed_cts+=("$ctid")
      [[ "$updated" == 0 ]] || partial_cts+=("$ctid")
    elif [[ "$updated" -eq 1 ]]; then
      updated_cts+=("$ctid")
    fi
  done

  echo
  if [[ ${#failed_cts[@]} -gt 0 ]]; then
    msg warn "Failed or declined hardware integration: ${failed_cts[*]}"
  fi
  if [[ ${#partial_cts[@]} -gt 0 ]]; then
    msg warn "Partial changes retained; automatic restart skipped: ${partial_cts[*]}"
  fi
  if [[ ${#updated_cts[@]} -gt 0 ]]; then
    msg ok "Updated: ${updated_cts[*]}"
    read -rp "Restart updated container(s)? [y/N]: " restart || restart=''
    if [[ "${restart,,}" == "y" ]]; then
      for ctid in "${updated_cts[@]}"; do
        if state=$(pct status "$ctid"); then
          case "$state" in
            'status: running')
              if pct reboot "$ctid"; then
                msg ok "Restarted container $ctid"
              else
                rc=$?
                msg err "Restart failed for container $ctid (status $rc)"
                [[ "$result" != 0 ]] || result=$rc
              fi
              ;;
            'status: stopped')
              msg info "Container $ctid is stopped; configuration applies on next start."
              ;;
            *)
              msg err "Unknown state for container $ctid; restart skipped"
              [[ "$result" != 0 ]] || result=65
              ;;
          esac
        else
          rc=$?
          msg err "State query failed for container $ctid (status $rc); restart skipped"
          [[ "$result" != 0 ]] || result=$rc
        fi
      done
    else
      msg info "Configuration applies on the next start or restart for: ${updated_cts[*]}"
    fi
  else
    msg warn "No container completed hardware integration."
  fi
  return "$result"
}

# framework bootstrap
# shellcheck disable=SC1090
# Dynamic URL resolved at runtime - shellcheck cannot follow
source <(curl -fsSL "$REPO_BASE/misc/bootstrap/pve") 2> /dev/null

main
