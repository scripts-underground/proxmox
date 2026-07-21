#!/usr/bin/env bash
REPO_BASE="${REPO_BASE:-https://raw.githubusercontent.com/scripts-underground/proxmox/main}"

# Copyright (c) 2021-2026 community-scripts ORG
# Author: MickLesk (Canbiz)
# License: MIT | https://raw.githubusercontent.com/scripts-underground/proxmox/main/LICENSE
# Source: https://github.com/Luligu/matterbridge

# shellcheck disable=SC2034
# Read by the framework - shellcheck cannot see the caller
APP="Matterbridge"
var_tags="${var_tags:-matter;smarthome}"
var_cpu="${var_cpu:-1}"
var_ram="${var_ram:-1024}"
var_disk="${var_disk:-4}"
var_os="${var_os:-debian}"
var_version="${var_version:-13}"
var_arm64="${var_arm64:-yes}"
var_unprivileged="${var_unprivileged:-1}"

function install_script() {
  msg_info "Installing Matterbridge"
  mkdir -p /root/Matterbridge
  NODE_VERSION="24" NODE_MODULE="matterbridge" setup_nodejs
  msg_ok "Installed Matterbridge"

  msg_info "Creating Service"
  cat << EOF > /etc/systemd/system/matterbridge.service
[Unit]
Description=matterbridge
After=network-online.target

[Service]
Type=simple
ExecStart=matterbridge -service
WorkingDirectory=/root/Matterbridge
StandardOutput=inherit
StandardError=inherit
Restart=always
RestartSec=10s
TimeoutStopSec=30s

[Install]
WantedBy=multi-user.target
EOF
  systemctl enable -q --now matterbridge
  msg_ok "Created Service"
}

function post_install_script() {
  msg_ok "Completed successfully!\n"
  echo -e "${CREATING}${GN}${APP} setup has been successfully initialized!${CL}"
  echo -e "${INFO}${YW}Access it using the following URL:${CL}"
  echo -e "${GATEWAY}${BGN}http://${IP}:8283${CL}"
}

function update_script() {
  header_info
  check_container_storage
  check_container_resources
  if [[ ! -d /root/Matterbridge ]]; then
    msg_error "No ${APP} Installation Found!"
    exit
  fi
  $STD apt update
  $STD apt upgrade -y
  NODE_VERSION="24" NODE_MODULE="matterbridge" setup_nodejs
  msg_ok "Updated successfully!"
  exit
}

# framework bootstrap
# shellcheck disable=SC1090
# Dynamic URL resolved at runtime - shellcheck cannot follow
source <(curl -fsSL "$REPO_BASE/misc/bootstrap/lxc")
