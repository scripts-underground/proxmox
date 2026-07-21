#!/usr/bin/env bash
REPO_BASE="${REPO_BASE:-https://raw.githubusercontent.com/scripts-underground/proxmox/main}"

# Sourced by lxc.bootstrap — never executed directly
# Copyright (c) 2021-2026 community-scripts ORG
# Author: David Bennett (dbinit)
# License: MIT | https://raw.githubusercontent.com/scripts-underground/proxmox/main/LICENSE
# Source: https://www.resilio.com/

# shellcheck disable=SC2034
APP="Resilio Sync"
var_tags="${var_tags:-sync}"
var_cpu="${var_cpu:-2}"
var_ram="${var_ram:-2048}"
var_disk="${var_disk:-8}"
var_os="${var_os:-debian}"
var_version="${var_version:-13}"
var_arm64="${var_arm64:-yes}"
var_unprivileged="${var_unprivileged:-1}"

function install_script() {
  setup_deb822_repo \
    "resilio" \
    "https://linux-packages.resilio.com/resilio-sync/key.asc" \
    "http://linux-packages.resilio.com/resilio-sync/deb" \
    "resilio-sync" \
    "non-free"

  msg_info "Installing Resilio Sync"
  $STD apt install -y resilio-sync
  sed -i "s/127.0.0.1:8888/0.0.0.0:8888/g" /etc/resilio-sync/config.json
  systemctl enable -q resilio-sync
  systemctl restart resilio-sync
  msg_ok "Installed Resilio Sync"
}

function post_install_script() {
  msg_ok "Completed Successfully!\n"
  echo -e "${CREATING}${GN}${APP} setup has been successfully initialized!${CL}"
  echo -e "${INFO}${YW}Access it using the following URL:${CL}"
  echo -e "${GATEWAY}${BGN}https://${IP}:8888${CL}"
}

function update_script() {
  header_info
  check_container_storage
  check_container_resources
  if [[ ! -d /var/lib/resilio-sync ]]; then
    msg_error "No ${APP} Installation Found!"
    exit
  fi
  msg_info "Updating Resilio Sync"
  $STD apt update
  $STD apt upgrade -y
  msg_ok "Updated successfully!"
  exit
}

# shellcheck disable=SC1090
source <(curl -fsSL "$REPO_BASE/misc/bootstrap/lxc")
