#!/usr/bin/env bash
# shellcheck disable=SC2034
REPO_BASE="${REPO_BASE:-https://raw.githubusercontent.com/scripts-underground/proxmox/main}"

# Sourced by lxc.bootstrap — never executed directly
# Copyright (c) 2021-2026 community-scripts ORG
# Author: tteck (tteckster)
# License: MIT | https://raw.githubusercontent.com/scripts-underground/proxmox/main/LICENSE
# Source: https://www.openhab.org/

# shellcheck disable=SC2034
# Read by the framework - shellcheck cannot see the caller
APP="openHAB"
var_tags="${var_tags:-automation}"
var_cpu="${var_cpu:-2}"
var_ram="${var_ram:-2048}"
var_disk="${var_disk:-8}"
var_os="${var_os:-debian}"
var_version="${var_version:-13}"
var_arm64="${var_arm64:-yes}"
var_unprivileged="${var_unprivileged:-1}"

function install_script() {
  JAVA_VERSION="21" setup_java

  msg_info "Installing openHAB"
  setup_deb822_repo \
    "openhab" \
    "https://openhab.jfrog.io/artifactory/api/gpg/key/public" \
    "https://openhab.jfrog.io/artifactory/openhab-linuxpkg" \
    "stable" \
    "main"
  $STD apt install -y openhab
  msg_ok "Installed openHAB"

  msg_info "Initializing openHAB directories"
  mkdir -p /var/lib/openhab/{tmp,etc,cache}
  mkdir -p /etc/openhab
  mkdir -p /var/log/openhab
  chown -R openhab:openhab /var/lib/openhab /etc/openhab /var/log/openhab
  msg_ok "Initialized openHAB directories"

  msg_info "Starting Service"
  systemctl daemon-reload
  systemctl enable -q --now openhab
  msg_ok "Started Service"
}

function post_install_script() {
  msg_ok "Completed Successfully!\n"
  echo -e "${CREATING}${GN}${APP} setup has been successfully initialized!${CL}"
  echo -e "${INFO}${YW}Access it using one of the following URLs:${CL}"
  echo -e "${GATEWAY}${BGN}https://${IP}:8443${CL}"
  echo -e "${GATEWAY}${BGN}http://${IP}:8080${CL}"
}

function update_script() {
  header_info
  check_container_storage
  check_container_resources
  if [[ ! -f /usr/lib/systemd/system/openhab.service ]]; then
    msg_error "No ${APP} Installation Found!"
    exit
  fi
  msg_info "Updating ${APP} LXC"
  $STD apt update
  $STD apt upgrade -y
  msg_ok "Updated successfully!"
  exit
}

# framework bootstrap
# shellcheck disable=SC1090
# Dynamic URL resolved at runtime - shellcheck cannot follow
source <(curl -fsSL "$REPO_BASE/misc/bootstrap/lxc")
