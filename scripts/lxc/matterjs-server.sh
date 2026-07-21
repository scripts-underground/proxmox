#!/usr/bin/env bash
REPO_BASE="${REPO_BASE:-https://raw.githubusercontent.com/scripts-underground/proxmox/main}"

# Sourced by lxc.bootstrap — never executed directly
# Copyright (c) 2021-2026 community-scripts ORG
# Author: MickLesk (CanbiZ)
# License: MIT | https://raw.githubusercontent.com/scripts-underground/proxmox/main/LICENSE
# Source: https://github.com/matter-js/matterjs-server

# shellcheck disable=SC2034
APP="MatterJS-Server"
var_tags="${var_tags:-matter;iot;smarthome;homeassistant}"
var_cpu="${var_cpu:-2}"
var_ram="${var_ram:-1024}"
var_disk="${var_disk:-4}"
var_os="${var_os:-debian}"
var_version="${var_version:-13}"
var_arm64="${var_arm64:-yes}"
var_unprivileged="${var_unprivileged:-1}"

function install_script() {
  NODE_VERSION="24" setup_nodejs

  msg_info "Installing MatterJS-Server"
  mkdir -p /opt/matter-server
  cd /opt/matter-server || exit
  $STD npm install matter-server
  mkdir -p /var/lib/matterjs-server
  msg_ok "Installed MatterJS-Server"

  msg_info "Configuring Network"
  cat << EOF > /etc/sysctl.d/60-ipv6-ra-rio.conf
net.ipv6.conf.default.accept_ra=1
net.ipv6.conf.default.accept_ra_rtr_pref=1
net.ipv6.conf.default.accept_ra_rt_info_max_plen=64
net.ipv6.conf.eth0.accept_ra=1
net.ipv6.conf.eth0.accept_ra_rtr_pref=1
net.ipv6.conf.eth0.accept_ra_rt_info_max_plen=64
EOF
  $STD sysctl -p /etc/sysctl.d/60-ipv6-ra-rio.conf
  msg_ok "Configured Network"

  msg_info "Creating Service"
  cat << EOF > /etc/systemd/system/matterjs-server.service
[Unit]
Description=MatterJS Server
After=network.target

[Service]
Type=simple
User=root
ExecStart=/usr/bin/node /opt/matter-server/node_modules/matter-server/dist/esm/MatterServer.js --storage-path /var/lib/matterjs-server
Restart=on-failure
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF
  systemctl enable -q --now matterjs-server
  msg_ok "Created Service"
}

function post_install_script() {
  msg_ok "Completed Successfully!\n"
  echo -e "${CREATING}${GN}${APP} setup has been successfully initialized!${CL}"
  echo -e "${INFO}${YW}Access it using the following URL:${CL}"
  echo -e "${GATEWAY}${BGN}http://${IP}:5580${CL}"
}

function update_script() {
  header_info
  check_container_storage
  check_container_resources

  if [[ ! -d /opt/matter-server ]]; then
    msg_error "No ${APP} Installation Found!"
    exit
  fi

  NODE_VERSION="24" setup_nodejs

  CURRENT=$(cat /opt/matter-server/node_modules/matter-server/package.json | grep '"version"' | head -1 | sed 's/.*"\([^"]*\)".*/\1/')
  LATEST=$(npm view matter-server version 2> /dev/null)
  if [[ $CURRENT != "$LATEST" ]]; then
    msg_info "Stopping Service"
    systemctl stop matterjs-server
    msg_ok "Stopped Service"

    msg_info "Updating ${APP} from v${CURRENT} to v${LATEST}"
    cd /opt/matter-server || exit
    $STD npm install matter-server@latest
    msg_ok "Updated ${APP}"

    msg_info "Starting Service"
    systemctl start matterjs-server
    msg_ok "Started Service"
    msg_ok "Updated successfully!"
  else
    msg_ok "No update required. ${APP} is already at v${LATEST}"
  fi
  exit
}

# shellcheck disable=SC1090
source <(curl -fsSL "$REPO_BASE/misc/bootstrap/lxc")
