#!/usr/bin/env bash
REPO_BASE="${REPO_BASE:-https://raw.githubusercontent.com/scripts-underground/proxmox/main}"

# Sourced by lxc.bootstrap — never executed directly
# Copyright (c) 2021-2026 community-scripts ORG
# Author: tteck (tteckster)
# License: MIT | https://raw.githubusercontent.com/scripts-underground/proxmox/main/LICENSE
# Source: https://www.mongodb.com/de-de

# shellcheck disable=SC2034
APP="MongoDB"
var_tags="${var_tags:-database}"
var_cpu="${var_cpu:-1}"
var_ram="${var_ram:-512}"
var_disk="${var_disk:-4}"
var_os="${var_os:-debian}"
var_version="${var_version:-13}"
var_arm64="${var_arm64:-yes}"
var_unprivileged="${var_unprivileged:-1}"

function install_script() {
  if [[ "$(get_system_arch)" == "arm64" ]]; then
    MONGO_VERSION="8.0" setup_mongodb
  else
    if prompt_confirm "Do you want to install MongoDB 8.0 instead of 7.0?" "n" 60; then
      MONGO_VERSION="8.0" setup_mongodb
    else
      MONGO_VERSION="7.0" setup_mongodb
    fi
  fi
  sed -i 's/bindIp: 127.0.0.1/bindIp: 0.0.0.0/' /etc/mongod.conf
}

function post_install_script() {
  msg_ok "Completed Successfully!\n"
  echo -e "${CREATING}${GN}${APP} setup has been successfully initialized!${CL}"
  echo -e "${INFO}${YW} Access it using the following URL:${CL}"
  echo -e "${TAB}${GATEWAY}${BGN}http://${IP}:27017${CL}"
}

function update_script() {
  header_info
  check_container_storage
  check_container_resources
  if ! command -v mongod &> /dev/null; then
    msg_error "No ${APP} Installation Found!"
    exit
  fi
  msg_info "Updating MongoDB LXC"
  $STD apt update
  $STD apt upgrade -y
  msg_ok "Updated successfully!"
  exit
}

# shellcheck disable=SC1090
source <(curl -fsSL "$REPO_BASE/misc/bootstrap/lxc")
