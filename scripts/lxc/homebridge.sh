#!/usr/bin/env bash
REPO_BASE="${REPO_BASE:-https://raw.githubusercontent.com/scripts-underground/proxmox/main}"

# Sourced by lxc.bootstrap — never executed directly
# Copyright (c) 2021-2026 community-scripts ORG
# Author: tteck (tteckster)
# License: MIT | https://raw.githubusercontent.com/scripts-underground/proxmox/main/LICENSE
# Source: https://homebridge.io/

# shellcheck disable=SC2034
# Read by the framework - shellcheck cannot see the caller
APP="Homebridge"
var_tags="${var_tags:-smarthome;homekit}"
var_cpu="${var_cpu:-1}"
var_ram="${var_ram:-1024}"
var_disk="${var_disk:-4}"
var_os="${var_os:-debian}"
var_version="${var_version:-13}"
var_arm64="${var_arm64:-yes}"
var_unprivileged="${var_unprivileged:-1}"

function install_script() {
  msg_info "Installing Dependencies"
  $STD apt install -y avahi-daemon
  msg_ok "Installed Dependencies"

  msg_info "Setting up Homebridge Repository"
  setup_deb822_repo \
    "homebridge" \
    "https://repo.homebridge.io/KEY.gpg" \
    "https://repo.homebridge.io" \
    "stable"
  msg_ok "Set up Homebridge Repository"

  msg_info "Installing Homebridge"
  $STD apt install -y homebridge
  msg_ok "Installed Homebridge"
}

function post_install_script() {
  msg_ok "Completed Successfully!\n"
  echo -e "${CREATING}${GN}${APP} setup has been successfully initialized!${CL}"
  echo -e "${INFO}${YW} Access it using the following URL:${CL}"
  echo -e "${TAB}${GATEWAY}${BGN}http://${IP}:8581${CL}"
}

function update_script() {
  header_info
  check_container_storage
  check_container_resources

  if ! dpkg -s homebridge > /dev/null 2>&1; then
    msg_error "No ${APP} Installation Found!"
    exit
  fi

  msg_info "Updating ${APP} LXC"
  $STD apt update
  $STD apt install -y homebridge
  msg_ok "Updated successfully!"
  exit
}

# framework bootstrap
# shellcheck disable=SC1090
# Dynamic URL resolved at runtime - shellcheck cannot follow
source <(curl -fsSL "$REPO_BASE/misc/bootstrap/lxc")
