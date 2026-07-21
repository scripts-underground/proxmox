#!/usr/bin/env bash
REPO_BASE="${REPO_BASE:-https://raw.githubusercontent.com/scripts-underground/proxmox/main}"

# Sourced by lxc.bootstrap — never executed directly
# Copyright (c) 2021-2026 community-scripts ORG
# Author: kristocopani
# License: MIT | https://raw.githubusercontent.com/scripts-underground/proxmox/main/LICENSE
# Source: https://thelounge.chat/

# shellcheck disable=SC2034
# Read by the framework - shellcheck cannot see the caller
APP="The-Lounge"
var_tags="${var_tags:-irc}"
var_cpu="${var_cpu:-2}"
var_ram="${var_ram:-2048}"
var_disk="${var_disk:-4}"
var_os="${var_os:-debian}"
var_version="${var_version:-13}"
var_arm64="${var_arm64:-yes}"
var_unprivileged="${var_unprivileged:-1}"

function install_script() {
  NODE_VERSION="22" setup_nodejs
  fetch_and_deploy_gh_release "thelounge" "thelounge/thelounge-deb" "binary"
  systemctl enable -q --now thelounge
}

function post_install_script() {
  msg_ok "Completed Successfully!\n"
  echo -e "${CREATING}${GN}${APP} setup has been successfully initialized!${CL}"
  echo -e "${INFO}${YW} Access it using the following URL:${CL}"
  echo -e "${TAB}${GATEWAY}${BGN}http://${IP}:9000${CL}"
}

function update_script() {
  header_info
  check_container_storage
  check_container_resources

  if [[ ! -f /usr/lib/systemd/system/thelounge.service ]]; then
    msg_error "No ${APP} Installation Found!"
    exit
  fi

  if check_for_gh_release "thelounge" "thelounge/thelounge-deb"; then
    msg_info "Stopping Service"
    systemctl stop thelounge
    msg_ok "Stopped Service"

    NODE_VERSION="22" setup_nodejs
    fetch_and_deploy_gh_release "thelounge" "thelounge/thelounge-deb" "binary"

    msg_info "Starting Service"
    systemctl start thelounge
    msg_ok "Started Service"
    msg_ok "Updated successfully!"
  fi
  exit
}

# framework bootstrap
# shellcheck disable=SC1090
# Dynamic URL resolved at runtime - shellcheck cannot follow
source <(curl -fsSL "$REPO_BASE/misc/bootstrap/lxc")
