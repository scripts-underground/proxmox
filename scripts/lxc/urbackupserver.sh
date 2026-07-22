#!/usr/bin/env bash
REPO_BASE="${REPO_BASE:-https://raw.githubusercontent.com/scripts-underground/proxmox/main}"

# Copyright (c) 2021-2026 community-scripts ORG
# Author: Kristian Skov
# License: MIT | https://raw.githubusercontent.com/scripts-underground/proxmox/main/LICENSE
# Source: https://www.urbackup.org/

# shellcheck disable=SC2034
# Read by the framework - shellcheck cannot see the caller
APP="UrBackup Server"
var_tags="${var_tags:-backup}"
var_cpu="${var_cpu:-1}"
var_ram="${var_ram:-1024}"
var_disk="${var_disk:-16}"
var_os="${var_os:-debian}"
var_version="${var_version:-13}"
var_arm64="${var_arm64:-yes}"
var_unprivileged="${var_unprivileged:-0}"

function install_script() {
  msg_info "Installing Dependencies"
  $STD apt install -y debconf-utils
  msg_ok "Installed Dependencies"

  setup_deb822_repo \
    "urbackup" \
    "https://download.opensuse.org/repositories/home:uroni/Debian_13/Release.key" \
    "http://download.opensuse.org/repositories/home:/uroni/Debian_13/" \
    "./" \
    ""

  msg_info "Setting up UrBackup Server"
  mkdir -p /opt/urbackup/backups
  echo "urbackup-server urbackup/backuppath string /opt/urbackup/backups" | debconf-set-selections
  $STD apt install -y urbackup-server
  msg_ok "Setup UrBackup Server"
}

function post_build_script() {
  pct set "$CTID" -features fuse=1,nesting=1
  pct reboot "$CTID"
}

function post_install_script() {
  msg_ok "Completed Successfully!\n"
  echo -e "${CREATING}${GN}${APP} setup has been successfully initialized!${CL}"
  echo -e "${INFO}${YW} Access it using the following IP:${CL}"
  echo -e "${TAB}${GATEWAY}${BGN}${IP}:55414${CL}"
}

function update_script() {
  header_info
  check_container_storage
  check_container_resources

  if [[ ! -d /var/urbackup ]]; then
    msg_error "No ${APP} Installation Found!"
    exit
  fi

  msg_info "Updating UrBackup Server"
  $STD apt update
  $STD apt upgrade -y
  msg_ok "Updated successfully!"
  exit
}

# framework bootstrap
# shellcheck disable=SC1090
# Dynamic URL resolved at runtime - shellcheck cannot follow
source <(curl -fsSL "$REPO_BASE/misc/bootstrap/lxc")
