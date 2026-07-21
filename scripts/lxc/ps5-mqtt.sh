#!/usr/bin/env bash
REPO_BASE="${REPO_BASE:-https://raw.githubusercontent.com/scripts-underground/proxmox/main}"

# Sourced by lxc.bootstrap — never executed directly
# Copyright (c) 2021-2026 community-scripts ORG
# Author: liecno (liecno)
# License: MIT | https://raw.githubusercontent.com/scripts-underground/proxmox/main/LICENSE
# Source: https://github.com/FunkeyFlo/ps5-mqtt/

# shellcheck disable=SC2034
# Read by the framework - shellcheck cannot see the caller
APP="PS5-MQTT"
var_tags="${var_tags:-smarthome;automation}"
var_cpu="${var_cpu:-1}"
var_ram="${var_ram:-512}"
var_disk="${var_disk:-3}"
var_os="${var_os:-debian}"
var_version="${var_version:-13}"
var_arm64="${var_arm64:-yes}"
var_unprivileged="${var_unprivileged:-1}"

function install_script() {
  msg_info "Installing Dependencies"
  $STD apt install -y jq ca-certificates
  msg_ok "Installed Dependencies"

  NODE_VERSION="22" NODE_MODULE="playactor" setup_nodejs
  fetch_and_deploy_gh_release "ps5-mqtt" "FunkeyFlo/ps5-mqtt" "tarball"

  msg_info "Configuring ${APP}"
  cd /opt/ps5-mqtt/ps5-mqtt/ || exit
  $STD npm install
  $STD npm run build
  mkdir -p /opt/.config/ps5-mqtt/
  mkdir -p /opt/.config/ps5-mqtt/playactor
  cat << EOF > /opt/.config/ps5-mqtt/config.json
{
  "mqtt": {
      "host": "",
      "port": "",
      "user": "",
      "pass": "",
      "discovery_topic": "homeassistant"
  },

  "device_check_interval": 5000,
  "device_discovery_interval": 60000,
  "device_discovery_broadcast_address": "",

  "include_ps4_devices": false,

  "psn_accounts": [
    {
      "username": "",
      "npsso":""
    }
  ],

  "account_check_interval": 5000,

  "credentialsStoragePath": "/opt/.config/ps5-mqtt/credentials.json",
  "frontendPort": "8645"
}
EOF
  msg_ok "Configured ${APP}"

  msg_info "Creating Service"
  cat << EOF > /etc/systemd/system/ps5-mqtt.service
[Unit]
Description=PS5-MQTT Daemon
After=syslog.target network.target

[Service]
WorkingDirectory=/opt/ps5-mqtt/ps5-mqtt
Environment="CONFIG_PATH=/opt/.config/ps5-mqtt/config.json"
Environment="DEBUG='@ha:ps5:*'"
Restart=always
RestartSec=5
Type=simple
ExecStart=node server/dist/index.js
KillMode=process
SyslogIdentifier=ps5-mqtt

[Install]
WantedBy=multi-user.target
EOF
  systemctl enable -q --now ps5-mqtt
  msg_ok "Created Service"
}

function post_install_script() {
  msg_ok "Completed Successfully!\n"
  echo -e "${CREATING}${GN}${APP} setup has been successfully initialized!${CL}"
  echo -e "${INFO}${YW}Access it using the following URL:${CL}"
  echo -e "${TAB}${GATEWAY}${BGN}http://${IP}:8645${CL}"
}

function update_script() {
  header_info
  check_container_storage
  check_container_resources
  if [[ ! -d /opt/ps5-mqtt ]]; then
    msg_error "No ${APP} Installation Found!"
    exit
  fi
  if check_for_gh_release "ps5-mqtt" "FunkeyFlo/ps5-mqtt"; then
    msg_info "Stopping Service"
    systemctl stop ps5-mqtt
    msg_ok "Stopped Service"

    fetch_and_deploy_gh_release "ps5-mqtt" "FunkeyFlo/ps5-mqtt" "tarball"

    msg_info "Configuring ${APP}"
    cd /opt/ps5-mqtt/ps5-mqtt/ || exit
    $STD npm install
    $STD npm run build
    msg_ok "Configured ${APP}"

    msg_info "Starting Service"
    systemctl start ps5-mqtt
    msg_ok "Started Service"
    msg_ok "Updated Successfully!"
  fi
  exit
}

# framework bootstrap
# shellcheck disable=SC1090
# Dynamic URL resolved at runtime - shellcheck cannot follow
source <(curl -fsSL "$REPO_BASE/misc/bootstrap/lxc")
