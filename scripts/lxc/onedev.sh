#!/usr/bin/env bash
REPO_BASE="${REPO_BASE:-https://raw.githubusercontent.com/scripts-underground/proxmox/main}"
# Sourced by lxc.bootstrap — never executed directly
# Copyright (c) 2021-2026 community-scripts ORG
# Author: kristocopani
# License: MIT | https://raw.githubusercontent.com/scripts-underground/proxmox/main/LICENSE
# Source: https://onedev.io/
# shellcheck disable=SC2034
APP="OneDev"
var_tags="${var_tags:-git}"
var_cpu="${var_cpu:-2}"
var_ram="${var_ram:-2048}"
var_disk="${var_disk:-4}"
var_os="${var_os:-debian}"
var_version="${var_version:-13}"
var_arm64="${var_arm64:-yes}"
var_unprivileged="${var_unprivileged:-1}"

function install_script() {
  msg_info "Installing Dependencies"
  $STD apt install -y git git-lfs
  msg_ok "Installed Dependencies"

  JAVA_VERSION="21" setup_java

  msg_info "Installing OneDev"
  cd /opt || exit
  curl -fsSL "https://code.onedev.io/onedev/server/~site/onedev-latest.tar.gz" -o onedev-latest.tar.gz
  tar -xzf onedev-latest.tar.gz
  mv /opt/onedev-latest /opt/onedev
  $STD /opt/onedev/bin/server.sh install
  rm -rf /opt/onedev-latest.tar.gz
  msg_ok "Installed OneDev"
}

function post_install_script() {
  msg_ok "Completed Successfully!\n"
  echo -e "${CREATING}${GN}${APP} setup has been successfully initialized!${CL}"
  echo -e "${INFO}${YW} Access it using the following URL:${CL}"
  echo -e "${TAB}${GATEWAY}${BGN}http://${IP}:6610${CL}"
}

function update_script() {
  header_info
  check_container_storage
  check_container_resources
  if [[ ! -f /etc/systemd/system/onedev.service ]]; then
    msg_error "No ${APP} Installation Found!"
    exit
  fi
  if check_for_gh_release "onedev" "theonedev/onedev"; then
    JAVA_VERSION="21" setup_java
    msg_info "Stopping Service"
    systemctl stop onedev
    msg_ok "Stopped Service"
    msg_info "Updating OneDev"
    cd /opt || exit
    curl -fsSL "https://code.onedev.io/onedev/server/~site/onedev-latest.tar.gz" -o onedev-latest.tar.gz
    tar -xzf onedev-latest.tar.gz
    $STD /opt/onedev-latest/bin/upgrade.sh /opt/onedev
    rm -rf /opt/onedev-latest
    rm -rf /opt/onedev-latest.tar.gz
    msg_ok "Updated OneDev"
    msg_info "Starting Service"
    systemctl start onedev
    msg_ok "Started Service"
    msg_ok "Updated successfully!"
  fi
  exit
}

# shellcheck disable=SC1090
source <(curl -fsSL "$REPO_BASE/misc/bootstrap/lxc")
