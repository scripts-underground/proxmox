#!/usr/bin/env bash
REPO_BASE="${REPO_BASE:-https://raw.githubusercontent.com/scripts-underground/proxmox/main}"

# Copyright (c) 2021-2026 tteck
# Author: tteck (tteckster)
# License: MIT | https://raw.githubusercontent.com/scripts-underground/proxmox/main/LICENSE
# Source: https://alpinelinux.org/

APP="Alpine"
var_tags="${var_tags:-os;alpine}"
var_cpu="${var_cpu:-1}"
var_ram="${var_ram:-512}"
var_disk="${var_disk:-1}"
var_os="${var_os:-alpine}"
var_version="${var_version:-3.23}"
var_arm64="${var_arm64:-no}"
var_unprivileged="${var_unprivileged:-1}"

function install_script() {
  msg_info "Installing Dependencies"
  $STD apk add sudo
  msg_ok "Installed Dependencies"
}

function post_install_script() {
  msg_ok "Completed successfully!\n"
}

function update_script() {
  header_info
  $STD apk -U upgrade
  msg_ok "Updated successfully!"
  exit 0
}

# framework bootstrap
source <(curl -fsSL "$REPO_BASE/misc/bootstrap/lxc")
