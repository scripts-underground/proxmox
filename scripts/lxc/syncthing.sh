#!/usr/bin/env bash
REPO_BASE="${REPO_BASE:-https://raw.githubusercontent.com/scripts-underground/proxmox/main}"

# Copyright (c) 2021-2026 community-scripts ORG
# Author: tteck (tteckster)
# License: MIT | https://raw.githubusercontent.com/scripts-underground/proxmox/main/LICENSE
# Source: https://syncthing.net/

# shellcheck disable=SC2034
# Read by the framework - shellcheck cannot see the caller
APP="Syncthing"
var_tags="${var_tags:-sync}"
var_cpu="${var_cpu:-2}"
var_ram="${var_ram:-2048}"
var_disk="${var_disk:-8}"
var_os="${var_os:-debian}"
var_version="${var_version:-13}"
var_arm64="${var_arm64:-yes}"
var_unprivileged="${var_unprivileged:-1}"

function install_script() {
  msg_info "Setting up Syncthing"
  setup_deb822_repo \
    "syncthing" \
    "https://syncthing.net/release-key.gpg" \
    "https://apt.syncthing.net/" \
    "syncthing" \
    "stable-v2"
  $STD apt install -y syncthing
  systemctl enable -q --now syncthing@root
  sleep 5
  sed -i "{s/127.0.0.1:8384/0.0.0.0:8384/g}" /root/.local/state/syncthing/config.xml
  systemctl restart syncthing@root
  msg_ok "Setup Syncthing"
}

function post_install_script() {
  msg_ok "Completed Successfully!\n"
  echo -e "${CREATING}${GN}${APP} setup has been successfully initialized!${CL}"
  echo -e "${INFO}${YW} Access it using the following URL:${CL}"
  echo -e "${TAB}${GATEWAY}${BGN}http://${IP}:8384${CL}"
}

function update_script() {
  header_info
  check_container_storage
  check_container_resources

  if [[ ! -f /etc/apt/sources.list.d/syncthing.list && ! -f /etc/apt/sources.list.d/syncthing.sources ]]; then
    msg_error "No ${APP} Installation Found!"
    exit
  fi

  msg_info "Updating Syncthing"
  $STD apt update
  $STD apt upgrade -y
  msg_ok "Updated successfully!"
  exit
}

# framework bootstrap
# shellcheck disable=SC1090
# Dynamic URL resolved at runtime - shellcheck cannot follow
source <(curl -fsSL "$REPO_BASE/misc/bootstrap/lxc")
