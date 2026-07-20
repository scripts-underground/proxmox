#!/usr/bin/env bash
REPO_BASE="${REPO_BASE:-https://raw.githubusercontent.com/scripts-underground/proxmox/main}"

# Copyright (c) 2021-2026 community-scripts ORG
# Author: tteck (tteckster)
# License: MIT | https://raw.githubusercontent.com/scripts-underground/proxmox/main/LICENSE
# Source: https://meshcentral.com/ | Github: https://github.com/Ylianst/MeshCentral

# shellcheck disable=SC2034
# Read by the framework - shellcheck cannot see the caller
APP="MeshCentral"
var_tags="${var_tags:-remote-management}"
var_cpu="${var_cpu:-1}"
var_ram="${var_ram:-512}"
var_disk="${var_disk:-4}"
var_os="${var_os:-debian}"
var_version="${var_version:-13}"
var_unprivileged="${var_unprivileged:-1}"

function install_script() {
  msg_info "Installing Dependencies"
  $STD apt install -y ca-certificates
  msg_ok "Installed Dependencies"

  NODE_VERSION="22" setup_nodejs

  msg_info "Installing MeshCentral"
  mkdir -p /opt/meshcentral
  cd /opt/meshcentral || exit
  $STD npm install meshcentral
  $STD node node_modules/meshcentral --install
  msg_ok "Installed MeshCentral"
}

function post_install_script() {
  msg_ok "Completed successfully!\n"
  echo -e "${CREATING}${GN}${APP} setup has been successfully initialized!${CL}"
  echo -e "${INFO}${YW}Access it using the following URL:${CL}"
  echo -e "${GATEWAY}${BGN}http://${IP}${CL}"
}

function update_script() {
  header_info
  check_container_storage
  check_container_resources
  if [[ ! -d /opt/meshcentral ]]; then
    msg_error "No ${APP} Installation Found!"
    exit
  fi
  msg_info "Updating ${APP} LXC"
  $STD apt update
  $STD apt -y upgrade
  msg_ok "Updated successfully!"
  exit
}

# framework bootstrap
# shellcheck disable=SC1090
# Dynamic URL resolved at runtime - shellcheck cannot see the caller
source <(curl -fsSL "$REPO_BASE/misc/bootstrap/lxc")
