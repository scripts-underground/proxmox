#!/usr/bin/env bash
REPO_BASE="${REPO_BASE:-https://raw.githubusercontent.com/scripts-underground/proxmox/main}"

# Copyright (c) 2021-2026 community-scripts ORG
# Author: Slaviša Arežina (tremor021)
# License: MIT | https://raw.githubusercontent.com/scripts-underground/proxmox/main/LICENSE
# Source: https://inventree.org

# shellcheck disable=SC2034
APP="InvenTree"
var_tags="${var_tags:-inventory}"
var_cpu="${var_cpu:-2}"
var_ram="${var_ram:-2048}"
var_disk="${var_disk:-6}"
var_os="${var_os:-ubuntu}"
var_version="${var_version:-24.04}"
var_unprivileged="${var_unprivileged:-1}"

function install_script() {
  msg_info "Installing Dependencies"
  $STD apt install -y curl gpg
  msg_ok "Installed Dependencies"

  msg_info "Adding InvenTree Repository"
  curl -fsSL https://dl.packager.io/srv/inventree/InvenTree/key | gpg --dearmor -o /etc/apt/trusted.gpg.d/inventree.gpg
  echo "deb [signed-by=/etc/apt/trusted.gpg.d/inventree.gpg] https://dl.packager.io/srv/deb/inventree/InvenTree/stable/ubuntu $(lsb_release -cs) main" > /etc/apt/sources.list.d/inventree.list
  $STD apt update
  msg_ok "Added InvenTree Repository"

  msg_info "Installing InvenTree"
  $STD apt install -y inventree
  msg_ok "Installed InvenTree"
}

function post_install_script() {
  msg_ok "Completed Successfully!\n"
  echo -e "${CREATING}${GN}${APP} setup has been successfully initialized!${CL}"
  echo -e "${INFO}${YW}Access it using the following URL:${CL}"
  echo -e "${GATEWAY}${BGN}http://${IP}${CL}"
}

function update_script() {
  header_info
  check_container_storage
  check_container_resources

  if [[ ! -d "/opt/inventree" ]]; then
    msg_error "No ${APP} Installation Found!"
    exit
  fi

  msg_info "Updating ${APP}"
  $STD apt update
  $STD apt install --only-upgrade inventree -y
  msg_ok "Updated ${APP}"
  msg_ok "Updated Successfully!"
  exit
}

# framework bootstrap
# shellcheck disable=SC1090
source <(curl -fsSL "$REPO_BASE/misc/bootstrap/lxc")
