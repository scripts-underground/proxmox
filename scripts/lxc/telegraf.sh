#!/usr/bin/env bash
REPO_BASE="${REPO_BASE:-https://raw.githubusercontent.com/scripts-underground/proxmox/main}"

# Sourced by lxc.bootstrap — never executed directly
# Copyright (c) 2021-2026 community-scripts ORG
# Author: CrazyWolf13
# License: MIT | https://raw.githubusercontent.com/scripts-underground/proxmox/main/LICENSE
# Source: https://github.com/influxdata/telegraf

# shellcheck disable=SC2034
# Read by the framework - shellcheck cannot see the caller
APP="telegraf"
var_tags="${var_tags:-collector;metrics}"
var_cpu="${var_cpu:-1}"
var_ram="${var_ram:-1024}"
var_disk="${var_disk:-4}"
var_os="${var_os:-debian}"
var_version="${var_version:-13}"
var_arm64="${var_arm64:-yes}"
var_unprivileged="${var_unprivileged:-1}"

function install_script() {
  msg_info "Setting up Telegraf repository"
  setup_deb822_repo \
    "telegraf" \
    "https://repos.influxdata.com/influxdata-archive.key" \
    "https://repos.influxdata.com/debian" \
    "stable"
  msg_ok "Setup Telegraf Repository"

  msg_info "Setting up Telegraf"
  $STD apt install -y telegraf
  msg_ok "Setup Telegraf"
}

function post_install_script() {
  msg_ok "Completed Successfully!\n"
  echo -e "${CREATING}${GN}${APP} setup has been successfully initialized!${CL}"
}

function update_script() {
  header_info
  check_container_storage
  check_container_resources

  if [[ ! -f /etc/telegraf/telegraf.conf ]]; then
    msg_error "No ${APP} Installation Found!"
    exit
  fi

  msg_info "Stopping Service"
  systemctl stop telegraf
  msg_ok "Stopped Service"

  msg_info "Updating Telegraf"
  $STD apt update
  $STD apt upgrade -y telegraf
  msg_ok "Updated Telegraf"

  msg_info "Starting Service"
  systemctl start telegraf
  msg_ok "Started Service"
  msg_ok "Updated successfully!"
  exit
}

# framework bootstrap
# shellcheck disable=SC1090
# Dynamic URL resolved at runtime - shellcheck cannot follow
source <(curl -fsSL "$REPO_BASE/misc/bootstrap/lxc")
