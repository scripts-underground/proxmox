#!/usr/bin/env bash
REPO_BASE="${REPO_BASE:-https://raw.githubusercontent.com/scripts-underground/proxmox/main}"

# Copyright (c) 2021-2026 community-scripts ORG
# Author: tteck (tteckster)
# License: MIT | https://raw.githubusercontent.com/scripts-underground/proxmox/main/LICENSE
# Source: https://sftpgo.com/

# shellcheck disable=SC2034
# Read by the framework - shellcheck cannot see the caller
APP="SFTPGo"
var_tags="${var_tags:-ftp;sftp}"
var_cpu="${var_cpu:-2}"
var_ram="${var_ram:-2048}"
var_disk="${var_disk:-4}"
var_os="${var_os:-debian}"
var_version="${var_version:-13}"
var_arm64="${var_arm64:-yes}"
var_unprivileged="${var_unprivileged:-1}"

function install_script() {
  msg_info "Installing Dependencies"
  $STD apt install -y sqlite3
  msg_ok "Installed Dependencies"

  setup_deb822_repo \
    "sftpgo" \
    "https://oss.sftpgo.com/apt/gpg.key" \
    "https://oss.sftpgo.com/apt" \
    "./"

  msg_info "Installing SFTPGo"
  $STD apt install -y sftpgo
  msg_ok "Installed SFTPGo"
}

function post_install_script() {
  msg_ok "Completed Successfully!\n"
  echo -e "${CREATING}${GN}${APP} setup has been successfully initialized!${CL}"
  echo -e "${INFO}${YW}Access it using the following URL:${CL}"
  echo -e "${GATEWAY}${BGN}http://${IP}:8080/web/admin${CL}"
}

function update_script() {
  header_info
  check_container_storage
  check_container_resources
  if [[ ! -d /etc/sftpgo ]]; then
    msg_error "No ${APP} Installation Found!"
    exit
  fi

  setup_deb822_repo \
    "sftpgo" \
    "https://oss.sftpgo.com/apt/gpg.key" \
    "https://oss.sftpgo.com/apt" \
    "./"

  msg_info "Updating SFTPGo"
  $STD apt update
  $STD apt upgrade -y
  msg_ok "Updated SFTPGo"
  msg_ok "Updated successfully!"
  exit
}

# framework bootstrap
# shellcheck disable=SC1090
# Dynamic URL resolved at runtime - shellcheck cannot follow
source <(curl -fsSL "$REPO_BASE/misc/bootstrap/lxc")
