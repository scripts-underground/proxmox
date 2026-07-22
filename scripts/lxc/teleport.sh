#!/usr/bin/env bash
REPO_BASE="${REPO_BASE:-https://raw.githubusercontent.com/scripts-underground/proxmox/main}"

# Copyright (c) 2021-2026 community-scripts ORG
# Author: Slaviša Arežina (tremor021)
# License: MIT | https://raw.githubusercontent.com/scripts-underground/proxmox/main/LICENSE
# Source: https://goteleport.com/

# shellcheck disable=SC2034
# Read by the framework - shellcheck cannot see the caller
APP="Teleport"
var_tags="${var_tags:-zero-trust}"
var_cpu="${var_cpu:-1}"
var_ram="${var_ram:-1024}"
var_disk="${var_disk:-4}"
var_os="${var_os:-debian}"
var_version="${var_version:-13}"
var_arm64="${var_arm64:-yes}"
var_unprivileged="${var_unprivileged:-1}"

function install_script() {
  msg_info "Installing Dependencies"
  $STD apt install -y apt-transport-https
  msg_ok "Installed Dependencies"

  setup_deb822_repo \
    "teleport" \
    "https://deb.releases.teleport.dev/teleport-pubkey.asc" \
    "https://apt.releases.teleport.dev/debian" \
    "trixie" \
    "stable/v18"

  msg_info "Configuring Teleport"
  $STD apt install -y teleport
  $STD teleport configure -o /etc/teleport.yaml
  systemctl enable -q --now teleport
  sleep 10
  tctl users add teleport-admin --roles=editor,access --logins=root > ~/teleportadmin.txt
  sed -i "s|https://[^:]*:3080|https://${LOCAL_IP}:3080|g" ~/teleportadmin.txt
  msg_ok "Configured Teleport"
}

function post_install_script() {
  msg_ok "Completed successfully!\n"
  echo -e "${CREATING}${GN}${APP} setup has been successfully initialized!${CL}"
  echo -e "${INFO}${YW}Access it using the following URL:${CL}"
  echo -e "${GATEWAY}${BGN}https://${IP}:3080${CL}"
  echo ""
  echo -e "${INFO}${YW}Admin credentials are located at: ~/teleportadmin.txt${CL}"
}

function update_script() {
  header_info
  check_container_storage
  check_container_resources
  if [[ ! -f /etc/teleport.yaml ]]; then
    msg_error "No ${APP} Installation Found!"
    exit
  fi
  msg_info "Updating Teleport"
  $STD apt update
  $STD apt upgrade -y
  msg_ok "Updated successfully!"
  exit
}

# shellcheck disable=SC1090
# Dynamic URL resolved at runtime - shellcheck cannot follow
source <(curl -fsSL "$REPO_BASE/misc/bootstrap/lxc")
