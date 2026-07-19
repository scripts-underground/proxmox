#!/usr/bin/env bash
REPO_BASE="${REPO_BASE:-https://raw.githubusercontent.com/scripts-underground/proxmox/main}"

# Sourced by lxc.bootstrap — never executed directly
# Copyright (c) 2021-2026 community-scripts ORG
# Author: tteck (tteckster)
# License: MIT | https://raw.githubusercontent.com/scripts-underground/proxmox/main/LICENSE
# Source: https://www.zigbee2mqtt.io/

# shellcheck disable=SC2034
# Read by the framework - shellcheck cannot see the caller
APP="Alpine-Zigbee2MQTT"
var_tags="${var_tags:-alpine;iot}"
var_cpu="${var_cpu:-2}"
var_ram="${var_ram:-1024}"
var_disk="${var_disk:-4}"
var_os="${var_os:-alpine}"
var_version="${var_version:-3.23}"
var_arm64="${var_arm64:-yes}"
var_unprivileged="${var_unprivileged:-1}"

function install_script() {
  msg_info "Installing Alpine-Zigbee2MQTT"
  $STD apk add zigbee2mqtt
  msg_ok "Installed Alpine-Zigbee2MQTT"
  msg_info "Enabling Zigbee2MQTT Service"
  $STD rc-update add zigbee2mqtt default
  msg_ok "Enabled Zigbee2MQTT Service"
  msg_info "Starting Zigbee2MQTT"
  $STD rc-service zigbee2mqtt start
  msg_ok "Started Zigbee2MQTT"
}

function post_install_script() {
  msg_ok "Completed Successfully!\n"
  echo -e "${CREATING}${GN}${APP} setup has been successfully initialized!${CL}"
  echo -e "${INFO}${YW} Zigbee2MQTT has been installed.${CL}"
}

function update_script() {
  header_info
  msg_info "Updating $APP LXC"
  $STD apk -U upgrade
  msg_ok "Updated $APP LXC"
  msg_info "Restarting Zigbee2MQTT"
  rc-service zigbee2mqtt restart
  msg_ok "Restarted Zigbee2MQTT"
  msg_ok "Updated successfully!"
  exit 0
}

# framework bootstrap
# shellcheck disable=SC1090
# Dynamic URL resolved at runtime - shellcheck cannot follow
source <(curl -fsSL "$REPO_BASE/misc/bootstrap/lxc")
