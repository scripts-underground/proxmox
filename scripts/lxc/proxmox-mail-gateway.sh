#!/usr/bin/env bash
REPO_BASE="${REPO_BASE:-https://raw.githubusercontent.com/scripts-underground/proxmox/main}"

# Sourced by lxc.bootstrap — never executed directly
# Copyright (c) 2021-2026 community-scripts ORG
# Author: thost96 (thost96)
# License: MIT | https://raw.githubusercontent.com/scripts-underground/proxmox/main/LICENSE
# Source: https://www.proxmox.com/en/products/proxmox-mail-gateway

# shellcheck disable=SC2034
# Read by the framework - shellcheck cannot see the caller
APP="Proxmox-Mail-Gateway"
var_tags="${var_tags:-mail}"
var_cpu="${var_cpu:-2}"
var_ram="${var_ram:-4096}"
var_disk="${var_disk:-10}"
var_os="${var_os:-debian}"
var_version="${var_version:-13}"
var_arm64="${var_arm64:-no}"
var_unprivileged="${var_unprivileged:-1}"

function install_script() {
  msg_info "Installing Proxmox Mail Gateway"
  setup_deb822_repo \
    "pmg" \
    "https://enterprise.proxmox.com/debian/proxmox-release-trixie.gpg" \
    "http://download.proxmox.com/debian/pmg" \
    "trixie" \
    "pmg-no-subscription"
  $STD apt install -y proxmox-mailgateway-container
  msg_ok "Installed Proxmox Mail Gateway"
}

function post_install_script() {
  msg_ok "Completed successfully!\n"
  echo -e "${CREATING}${GN}${APP} setup has been successfully initialized!${CL}"
  echo -e "${INFO}${YW}Access it using the following URL:${CL}"
  echo -e "${TAB}${GATEWAY}${BGN}https://${IP}:8006${CL}"
}

function update_script() {
  header_info
  check_container_storage
  check_container_resources
  if [[ ! -e /usr/bin/pmgproxy ]]; then
    msg_error "No ${APP} Installation Found!"
    exit
  fi
  msg_info "Updating Proxmox-Mail-Gateway"
  $STD apt update
  $STD apt upgrade -y
  msg_ok "Updated Proxmox-Mail-Gateway"
  msg_ok "Updated successfully!"
  exit
}

# framework bootstrap
# shellcheck disable=SC1090
# Dynamic URL resolved at runtime - shellcheck cannot follow
source <(curl -fsSL "$REPO_BASE/misc/bootstrap/lxc")
