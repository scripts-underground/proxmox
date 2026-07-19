#!/usr/bin/env bash
REPO_BASE="${REPO_BASE:-https://raw.githubusercontent.com/scripts-underground/proxmox/main}"

# Sourced by lxc.bootstrap — never executed directly
# Copyright (c) 2021-2026 community-scripts ORG
# Author: pshankinclarke (lazarillo)
# License: MIT | https://raw.githubusercontent.com/scripts-underground/proxmox/main/LICENSE
# Source: https://valkey.io/

# shellcheck disable=SC2034
# Read by the framework - shellcheck cannot see the caller
APP="Alpine-Valkey"
var_tags="${var_tags:-alpine;database}"
var_cpu="${var_cpu:-1}"
var_ram="${var_ram:-256}"
var_disk="${var_disk:-1}"
var_os="${var_os:-alpine}"
var_version="${var_version:-3.23}"
var_arm64="${var_arm64:-yes}"
var_unprivileged="${var_unprivileged:-1}"

function install_script() {
  msg_info "Installing Valkey"
  $STD apk add valkey
  msg_ok "Installed Valkey"
  MAXMEMORY_MB=$((MEMTOTAL_MB * 75 / 100))
  cat << EOF > /etc/valkey/valkey.conf
maxmemory ${MAXMEMORY_MB}mb
maxmemory-policy allkeys-lru
maxmemory-samples 10
EOF
  msg_info "Enabling Valkey Service"
  $STD rc-update add valkey default
  msg_ok "Enabled Valkey Service"
  msg_info "Starting Valkey"
  $STD rc-service valkey start
  msg_ok "Started Valkey"
}

function post_install_script() {
  msg_ok "Completed Successfully!\n"
  echo -e "${CREATING}${GN}${APP} setup has been successfully initialized!${CL}"
  echo -e "${INFO}${YW} Valkey is running on port 6379${CL}"
}

function update_script() {
  header_info
  msg_info "Updating $APP LXC"
  $STD apk -U upgrade
  msg_ok "Updated $APP LXC"
  msg_info "Restarting Valkey"
  rc-service valkey restart
  msg_ok "Restarted Valkey"
  msg_ok "Updated successfully!"
  exit 0
}

# framework bootstrap
# shellcheck disable=SC1090
# Dynamic URL resolved at runtime - shellcheck cannot follow
source <(curl -fsSL "$REPO_BASE/misc/bootstrap/lxc")
