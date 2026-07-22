#!/usr/bin/env bash
REPO_BASE="${REPO_BASE:-https://raw.githubusercontent.com/scripts-underground/proxmox/main}"

# Sourced by lxc.bootstrap — never executed directly
# Copyright (c) 2021-2026 community-scripts ORG
# Author: twingate-andrewb
# Co-Author: MickLesk (CanbiZ)
# License: MIT | https://raw.githubusercontent.com/scripts-underground/proxmox/main/LICENSE
# Source: https://www.twingate.com/docs/

# shellcheck disable=SC2034
# Read by the framework - shellcheck cannot see the caller
APP="Twingate-Connector"
var_tags="${var_tags:-network;connector;twingate}"
var_cpu="${var_cpu:-1}"
var_ram="${var_ram:-1024}"
var_disk="${var_disk:-3}"
var_os="${var_os:-ubuntu}"
var_version="${var_version:-24.04}"
var_arm64="${var_arm64:-yes}"
var_unprivileged="${var_unprivileged:-1}"

function install_script() {
  msg_info "Getting Setup Information"
  install -d -m 0700 /etc/twingate
  access_token=""
  refresh_token=""
  network=""
  while [[ -z "$access_token" ]]; do
    read -rp "Please enter your access token: " access_token
  done
  while [[ -z "$refresh_token" ]]; do
    read -rp "Please enter your refresh token: " refresh_token
  done
  while [[ -z "$network" ]]; do
    read -rp "Please enter your network name: " network
  done
  msg_ok "Got Setup Information"

  msg_info "Setting up Twingate Repository"
  curl -fsSL "https://packages.twingate.com/apt/gpg.key" | gpg --dearmor -o /usr/share/keyrings/twingate-connector-keyring.gpg
  echo "deb [signed-by=/usr/share/keyrings/twingate-connector-keyring.gpg] https://packages.twingate.com/apt/ /" > /etc/apt/sources.list.d/twingate.list
  $STD apt update
  msg_ok "Set up Twingate Repository"

  msg_info "Setting up Twingate Connector"
  $STD apt install -y twingate-connector
  msg_ok "Set up Twingate Connector"

  msg_info "Configuring Twingate Connector"
  cat << EOF > /etc/twingate/connector.conf
TWINGATE_NETWORK=${network}
TWINGATE_ACCESS_TOKEN=${access_token}
TWINGATE_REFRESH_TOKEN=${refresh_token}
TWINGATE_LABEL_HOSTNAME=$(hostname)
TWINGATE_LABEL_DEPLOYED_BY=proxmox
EOF
  chmod 600 /etc/twingate/connector.conf
  msg_ok "Configured Twingate Connector"

  msg_info "Starting Service"
  systemctl enable -q --now twingate-connector
  msg_ok "Started Service"
}

function post_install_script() {
  msg_ok "Completed Successfully!\n"
  echo -e "${CREATING}${GN}${APP} setup has been successfully initialized!${CL}"
  echo -e "${INFO}${YW} If you need to update your access or refresh tokens, they can be found in /etc/twingate/connector.conf${CL}"
}

function update_script() {
  header_info
  check_container_storage
  check_container_resources

  if [[ ! -f /lib/systemd/system/twingate-connector.service ]]; then
    msg_error "No ${APP} Installation Found!"
    exit
  fi

  msg_info "Updating Twingate Connector"
  $STD apt update
  $STD apt install -y --only-upgrade twingate-connector
  $STD systemctl restart twingate-connector
  msg_ok "Updated successfully!"
  exit
}

# framework bootstrap
# shellcheck disable=SC1090
# Dynamic URL resolved at runtime - shellcheck cannot follow
source <(curl -fsSL "$REPO_BASE/misc/bootstrap/lxc")
