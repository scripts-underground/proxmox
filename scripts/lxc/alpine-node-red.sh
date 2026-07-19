#!/usr/bin/env bash
REPO_BASE="${REPO_BASE:-https://raw.githubusercontent.com/scripts-underground/proxmox/main}"

# Sourced by lxc.bootstrap — never executed directly
# Copyright (c) 2021-2026 community-scripts ORG
# Author: MickLesk (CanbiZ)
# License: MIT | https://raw.githubusercontent.com/scripts-underground/proxmox/main/LICENSE
# Source: https://nodered.org/

# shellcheck disable=SC2034
# Read by the framework - shellcheck cannot see the caller
APP="Alpine-Node-RED"
var_tags="${var_tags:-alpine;automation}"
var_cpu="${var_cpu:-1}"
var_ram="${var_ram:-256}"
var_disk="${var_disk:-1}"
var_os="${var_os:-alpine}"
var_version="${var_version:-3.23}"
var_arm64="${var_arm64:-yes}"
var_unprivileged="${var_unprivileged:-1}"

function install_script() {
  msg_info "Installing Dependencies"
  $STD apk add --no-cache \
    git \
    nodejs \
    npm
  msg_ok "Installed Dependencies"

  msg_info "Creating Node-RED User"
  adduser -D -H -s /sbin/nologin -G users nodered
  msg_ok "Created Node-RED User"

  msg_info "Installing Node-RED"
  $STD npm install -g --unsafe-perm node-red
  msg_ok "Installed Node-RED"

  msg_info "Configuring Node-RED"
  mkdir -p /home/nodered
  chown -R nodered:users /home/nodered
  chmod 750 /home/nodered
  msg_ok "Configured Node-RED"

  msg_info "Creating Service"
  cat << 'EOF' > /etc/init.d/nodered
#!/sbin/openrc-run
description="Node-RED Service"

command="/usr/local/bin/node-red"
command_args="--max-old-space-size=128 -v"
command_user="nodered"
pidfile="/var/run/nodered.pid"
command_background="yes"

depend() {
    use net
}
EOF
  chmod +x /etc/init.d/nodered
  $STD rc-update add nodered default
  $STD rc-service nodered start
  msg_ok "Created Service"
}

function post_install_script() {
  msg_ok "Completed Successfully!\n"
  echo -e "${CREATING}${GN}${APP} setup has been successfully initialized!${CL}"
  echo -e "${INFO}${YW} Access it using the following URL:${CL}"
  echo -e "${TAB}${GATEWAY}${BGN}http://${IP}:1880${CL}"
}

function update_script() {
  header_info
  msg_info "Updating Alpine Packages"
  $STD apk -U upgrade
  msg_ok "Updated Alpine Packages"

  msg_info "Updating Node.js and npm"
  $STD apk upgrade nodejs npm
  msg_ok "Updated Node.js and npm"

  msg_info "Updating Node-RED"
  $STD npm install -g --unsafe-perm node-red
  msg_ok "Updated Node-RED"

  msg_info "Restarting Node-RED"
  $STD rc-service nodered restart
  msg_ok "Restarted Node-RED"
  msg_ok "Updated successfully!"
  exit 0
}

# framework bootstrap
# shellcheck disable=SC1090
# Dynamic URL resolved at runtime - shellcheck cannot follow
source <(curl -fsSL "$REPO_BASE/misc/bootstrap/lxc")
