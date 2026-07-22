#!/usr/bin/env bash
REPO_BASE="${REPO_BASE:-https://raw.githubusercontent.com/scripts-underground/proxmox/main}"

# Sourced by lxc.bootstrap — never executed directly
# Copyright (c) 2021-2026 community-scripts ORG
# Author: MickLesk (CanbiZ)
# License: MIT | https://raw.githubusercontent.com/scripts-underground/proxmox/main/LICENSE
# Source: https://ui.com/

# shellcheck disable=SC2034
# Read by the framework - shellcheck cannot see the caller
APP="UniFi-OS-Server"
var_tags="${var_tags:-network}"
var_cpu="${var_cpu:-2}"
var_ram="${var_ram:-4096}"
var_disk="${var_disk:-20}"
var_os="${var_os:-debian}"
var_version="${var_version:-13}"
var_arm64="${var_arm64:-yes}"
var_unprivileged="${var_unprivileged:-0}"

function install_script() {
  PLATFORM="linux-$(uname -m)"
  PLATFORM="${PLATFORM/x86_64/x64}"
  PLATFORM="${PLATFORM/aarch64/arm64}"

  msg_info "Installing dependencies"
  $STD apt install -y \
    podman \
    uidmap \
    slirp4netns
  msg_ok "Installed dependencies"

  msg_info "Installing sysctl wrapper"
  cat << 'EOF' > /usr/local/sbin/sysctl
#!/bin/sh
/usr/sbin/sysctl "$@" || true
exit 0
EOF
  chmod +x /usr/local/sbin/sysctl
  msg_ok "Sysctl wrapper installed"

  msg_info "Fetching latest UniFi OS Server"
  API_URL="https://fw-update.ui.com/api/firmware-latest"
  TEMP_JSON="$(mktemp)"
  if ! curl -fsSL "$API_URL" -o "$TEMP_JSON"; then
    rm -f "$TEMP_JSON"
    msg_error "Failed to fetch data from Ubiquiti API"
    exit 250
  fi
  LATEST=$(jq -r --arg platform "$PLATFORM" '
    ._embedded.firmware
    | map(select(.product == "unifi-os-server"))
    | map(select(.platform == $platform))
    | sort_by(.version_major, .version_minor, .version_patch)
    | last
  ' "$TEMP_JSON")
  UOS_VERSION=$(echo "$LATEST" | jq -r '.version' | sed 's/^v//')
  UOS_URL=$(echo "$LATEST" | jq -r '._links.data.href')
  rm -f "$TEMP_JSON"
  if [[ -z "$UOS_URL" || -z "$UOS_VERSION" || "$UOS_URL" == "null" ]]; then
    msg_error "Failed to parse UniFi OS Server version or download URL"
    exit 250
  fi
  msg_ok "Found UniFi OS Server ${UOS_VERSION}"

  msg_info "Downloading UniFi OS Server installer"
  mkdir -p /usr/local/sbin
  curl -fsSL "$UOS_URL" -o /usr/local/sbin/unifi-os-server.bin
  chmod +x /usr/local/sbin/unifi-os-server.bin
  msg_ok "Downloaded UniFi OS Server installer"

  msg_info "Installing UniFi OS Server (this takes a few minutes)"
  $STD /usr/local/sbin/unifi-os-server.bin <<< "y"
  msg_ok "UniFi OS Server installed"
}

function post_install_script() {
  msg_ok "Completed successfully!\n"
  echo -e "${CREATING}${GN}${APP} setup has been successfully initialized!${CL}"
  echo -e "${INFO}${YW}Access it using the following URL:${CL}"
  echo -e "${GATEWAY}${BGN}https://${IP}:11443${CL}"
}

function update_script() {
  header_info
  check_container_storage
  check_container_resources
  if [[ ! -f /usr/local/sbin/unifi-os-server.bin && ! -d /data/unifi ]]; then
    msg_error "No ${APP} Installation Found!"
    exit
  fi
  msg_error "UniFi OS Server can only be updated via the built-in updater."
  exit
}

# framework bootstrap
# shellcheck disable=SC1090
# Dynamic URL resolved at runtime - shellcheck cannot follow
source <(curl -fsSL "$REPO_BASE/misc/bootstrap/lxc")
