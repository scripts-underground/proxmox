#!/usr/bin/env bash
REPO_BASE="${REPO_BASE:-https://raw.githubusercontent.com/scripts-underground/proxmox/main}"

# Copyright (c) 2021-2026 community-scripts ORG
# Author: tteck (tteckster)
# License: MIT | https://raw.githubusercontent.com/scripts-underground/proxmox/main/LICENSE
# Source: https://mosquitto.org/

# shellcheck disable=SC2034
APP="MQTT"
var_tags="${var_tags:-mqtt;iot;broker}"
var_cpu="${var_cpu:-1}"
var_ram="${var_ram:-512}"
var_disk="${var_disk:-2}"
var_os="${var_os:-debian}"
var_version="${var_version:-13}"
var_arm64="${var_arm64:-yes}"
var_unprivileged="${var_unprivileged:-1}"

function install_script() {
  msg_info "Installing Mosquitto MQTT Broker"
  setup_deb822_repo \
    "mqtt" \
    "https://repo.mosquitto.org/debian/mosquitto-repo.gpg" \
    "https://repo.mosquitto.org/debian" \
    "trixie"
  $STD apt install -y \
    mosquitto \
    mosquitto-clients
  msg_ok "Installed Mosquitto MQTT Broker"

  msg_info "Configuring Mosquitto MQTT Broker"
  cat << EOF > /etc/mosquitto/conf.d/default.conf
allow_anonymous false
persistence true
password_file /etc/mosquitto/passwd
listener 1883
EOF
  msg_ok "Configured Mosquitto MQTT Broker"
}

function post_install_script() {
  msg_ok "Completed Successfully!\n"
  echo -e "${CREATING}${GN}${APP} setup has been successfully initialized!${CL}"
  echo -e "${INFO}${YW} Access it using the following URL:${CL}"
  echo -e "${GATEWAY}${BGN}mqtt://${IP}:1883${CL}"
}

function update_script() {
  header_info
  check_container_storage
  check_container_resources

  if [[ ! -f /etc/mosquitto/conf.d/default.conf ]]; then
    msg_error "No ${APP} Installation Found!"
    exit
  fi

  msg_info "Updating ${APP} LXC"
  $STD apt update
  $STD apt upgrade -y
  msg_ok "Updated Successfully"
  exit
}

# shellcheck disable=SC1090
source <(curl -fsSL "$REPO_BASE/misc/bootstrap/lxc")
