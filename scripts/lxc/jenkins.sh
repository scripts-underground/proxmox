#!/usr/bin/env bash
REPO_BASE="${REPO_BASE:-https://raw.githubusercontent.com/scripts-underground/proxmox/main}"

# Sourced by lxc.bootstrap — never executed directly
# Copyright (c) 2021-2026 community-scripts ORG
# Author: kristocopani
# License: MIT | https://raw.githubusercontent.com/scripts-underground/proxmox/main/LICENSE
# Source: https://www.jenkins.io/

# shellcheck disable=SC2034
# Read by the framework - shellcheck cannot see the caller
APP="Jenkins"
var_tags="${var_tags:-automation}"
var_cpu="${var_cpu:-2}"
var_ram="${var_ram:-1024}"
var_disk="${var_disk:-4}"
var_os="${var_os:-debian}"
var_version="${var_version:-13}"
var_arm64="${var_arm64:-yes}"
var_unprivileged="${var_unprivileged:-1}"

function install_script() {
  msg_info "Installing Dependencies"
  JAVA_VERSION="21" setup_java
  msg_ok "Installed Dependencies"

  msg_info "Setting up Jenkins Repository"
  setup_deb822_repo \
    "jenkins" \
    "https://pkg.jenkins.io/debian/jenkins.io-2026.key" \
    "https://pkg.jenkins.io/debian" \
    "binary/" \
    " "
  $STD apt install -y jenkins
  msg_ok "Set up Jenkins Repository"

  msg_info "Starting Jenkins"
  systemctl enable -q --now jenkins
  msg_ok "Started Jenkins"
}

function post_install_script() {
  msg_ok "Completed successfully!\n"
  echo -e "${CREATING}${GN}${APP} setup has been successfully initialized!${CL}"
  echo -e "${INFO}${YW}Access it using the following URL:${CL}"
  echo -e "${GATEWAY}${BGN}http://${IP}:8080${CL}"
}

function update_script() {
  header_info
  check_container_storage
  check_container_resources
  if [[ ! -d /var/lib/jenkins ]]; then
    msg_error "No ${APP} Installation Found!"
    exit
  fi

  JAVA_VERSION="21" setup_java

  msg_info "Updating Jenkins"
  $STD apt update
  $STD apt upgrade -y
  msg_ok "Updated Jenkins"
  msg_ok "Updated successfully!"
  exit
}

# framework bootstrap
# shellcheck disable=SC1090
# Dynamic URL resolved at runtime - shellcheck cannot follow
source <(curl -fsSL "$REPO_BASE/misc/bootstrap/lxc")
