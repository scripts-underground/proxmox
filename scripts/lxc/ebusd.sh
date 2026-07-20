#!/usr/bin/env bash
REPO_BASE="${REPO_BASE:-https://raw.githubusercontent.com/scripts-underground/proxmox/main}"

# Copyright (c) 2021-2026 community-scripts ORG
# Author: Joerg Heinemann (heinemannj)
# License: MIT | https://raw.githubusercontent.com/scripts-underground/proxmox/main/LICENSE
# Source: https://github.com/john30/ebusd

APP="ebusd"
var_tags="${var_tags:-automation}"
var_cpu="${var_cpu:-1}"
var_ram="${var_ram:-512}"
var_disk="${var_disk:-2}"
var_os="${var_os:-debian}"
var_version="${var_version:-13}"
var_arm64="${var_arm64:-yes}"
var_unprivileged="${var_unprivileged:-1}"

function install_script() {
  fetch_and_deploy_gh_release "ebusd" "john30/ebusd" "binary" "latest" "" "ebusd-*_$(get_system_arch)-trixie_mqtt1.deb"
  msg_info "Enabling Service"
  systemctl enable -q ebusd
  msg_ok "Enabled Service"
}

function post_install_script() {
  msg_ok "Completed successfully!\n"
  echo -e "${CREATING}${GN}${APP} setup has been successfully initialized!${CL}"
  echo -e "${INFO}${YW} Access it using the following URL:${CL}"
  echo -e "${TAB}${GATEWAY}${BGN}http://${IP}:8880${CL}"
}

function update_script() {
  header_info
  check_container_storage
  check_container_resources
  if [[ ! -f /etc/default/ebusd ]]; then
    msg_error "No ${APP} Installation Found!"
    exit
  fi
  if check_for_gh_release "ebusd" "john30/ebusd"; then
    msg_info "Stopping Service"
    systemctl stop ebusd
    msg_ok "Stopped Service"

    fetch_and_deploy_gh_release "ebusd" "john30/ebusd" "binary" "latest" "" "ebusd-*_$(get_system_arch)-trixie_mqtt1.deb"

    msg_info "Starting Service"
    systemctl start ebusd
    msg_ok "Started Service"
    msg_ok "Updated successfully!"
  fi
  exit
}

# shellcheck disable=SC1090
source <(curl -fsSL "$REPO_BASE/misc/bootstrap/lxc")
