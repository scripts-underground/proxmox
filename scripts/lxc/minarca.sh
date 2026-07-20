#!/usr/bin/env bash
REPO_BASE="${REPO_BASE:-https://raw.githubusercontent.com/scripts-underground/proxmox/main}"

# Copyright (c) 2021-2026 community-scripts ORG
# Author: Slaviša Arežina (tremor021)
# License: MIT | https://raw.githubusercontent.com/scripts-underground/proxmox/main/LICENSE
# Source: https://minarca.org/en_CA

# shellcheck disable=SC2034
APP="Minarca"
var_tags="${var_tags:-backup}"
var_cpu="${var_cpu:-2}"
var_ram="${var_ram:-4096}"
var_disk="${var_disk:-10}"
var_os="${var_os:-debian}"
var_version="${var_version:-13}"
var_arm64="${var_arm64:-no}"
var_unprivileged="${var_unprivileged:-1}"
var_fuse="${var_fuse:-yes}"

function install_script() {
  msg_info "Installing Dependencies"
  $STD apt install -y \
    apt-transport-https \
    ca-certificates \
    lsb-release
  msg_ok "Installed Dependencies"

  msg_info "Setting up Minarca Repository"
  setup_deb822_repo \
    "minarca" \
    "https://www.ikus-soft.com/archive/minarca/public.key" \
    "https://nexus.ikus-soft.com/repository/apt-release-trixie/" \
    "trixie" \
    "main" \
    "amd64"
  msg_ok "Minarca Repository setup successfully"

  msg_info "Installing Minarca"
  $STD apt install -y minarca-server
  $STD systemctl enable -q --now minarca-server
  msg_ok "Installed Minarca"
}

function post_install_script() {
  msg_ok "Completed Successfully!\n"
  echo -e "${CREATING}${GN}${APP} setup has been successfully initialized!${CL}"
  echo -e "${INFO}${YW} Access it using the following URL:${CL}"
  echo -e "${TAB}${GATEWAY}${BGN}http://${IP}:8080${CL}"
}

function update_script() {
  header_info
  check_container_storage
  check_container_resources

  if [[ ! -d /opt/minarca-server ]]; then
    msg_error "No ${APP} Installation Found!"
    exit
  fi

  msg_info "Stopping Service"
  systemctl stop minarca-server
  msg_ok "Stopped Service"

  msg_info "Updating ${APP} LXC"
  $STD apt update
  $STD apt --only-upgrade install -y minarca-server
  msg_ok "Updated ${APP} LXC"

  msg_info "Starting Service"
  systemctl start minarca-server
  msg_ok "Started Service"

  msg_ok "Updated successfully!"
  exit
}

# shellcheck disable=SC1090
source <(curl -fsSL "$REPO_BASE/misc/bootstrap/lxc")
