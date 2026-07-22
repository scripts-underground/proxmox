#!/usr/bin/env bash
REPO_BASE="${REPO_BASE:-https://raw.githubusercontent.com/scripts-underground/proxmox/main}"

# Sourced by lxc.bootstrap — never executed directly
# Copyright (c) 2021-2026 community-scripts ORG
# Author: tteck (tteckster)
# License: MIT | https://raw.githubusercontent.com/scripts-underground/proxmox/main/LICENSE
# Source: https://transmissionbt.com/

# shellcheck disable=SC2034
# Read by the framework - shellcheck cannot see the caller
APP="Transmission"
var_tags="${var_tags:-torrent}"
var_cpu="${var_cpu:-2}"
var_ram="${var_ram:-2048}"
var_disk="${var_disk:-8}"
var_os="${var_os:-debian}"
var_version="${var_version:-13}"
var_arm64="${var_arm64:-yes}"
var_unprivileged="${var_unprivileged:-1}"

function install_script() {
  msg_info "Installing Transmission"
  $STD apt install -y transmission-daemon
  systemctl stop transmission-daemon
  sed -i '{s/"rpc-whitelist-enabled": true/"rpc-whitelist-enabled": false/g; s/"rpc-host-whitelist-enabled": true,/"rpc-host-whitelist-enabled": false,/g}' /etc/transmission-daemon/settings.json
  systemctl start transmission-daemon
  msg_ok "Installed Transmission"
}

function post_install_script() {
  msg_ok "Completed Successfully!\n"
  echo -e "${CREATING}${GN}${APP} setup has been successfully initialized!${CL}"
  echo -e "${INFO}${YW} Access it using the following URL:${CL}"
  echo -e "${TAB}${GATEWAY}${BGN}http://${IP}:9091/transmission${CL}"
}

function update_script() {
  header_info
  check_container_storage
  check_container_resources
  if [[ ! -f /etc/transmission-daemon/settings.json ]]; then
    msg_error "No ${APP} Installation Found!"
    exit
  fi
  msg_info "Updating Transmission"
  $STD apt update
  $STD apt -y upgrade
  msg_ok "Updated Transmission"
  msg_ok "Updated successfully!"
  exit
}

# framework bootstrap
# shellcheck disable=SC1090
# Dynamic URL resolved at runtime - shellcheck cannot follow
source <(curl -fsSL "$REPO_BASE/misc/bootstrap/lxc")
