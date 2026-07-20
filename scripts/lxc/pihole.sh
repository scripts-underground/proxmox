#!/usr/bin/env bash
REPO_BASE="${REPO_BASE:-https://raw.githubusercontent.com/scripts-underground/proxmox/main}"

# Copyright (c) 2021-2026 community-scripts ORG
# Author: tteck (tteckster)
# License: MIT | https://raw.githubusercontent.com/scripts-underground/proxmox/main/LICENSE
# Source: https://pi-hole.net/

# shellcheck disable=SC2034
APP="Pihole"
var_tags="${var_tags:-adblock}"
var_cpu="${var_cpu:-1}"
var_ram="${var_ram:-512}"
var_disk="${var_disk:-2}"
var_os="${var_os:-debian}"
var_version="${var_version:-13}"
var_arm64="${var_arm64:-yes}"
var_unprivileged="${var_unprivileged:-1}"

function install_script() {
  msg_info "Installing Dependencies"
  $STD apt-get install -y curl
  msg_ok "Installed Dependencies"

  msg_info "Installing Pi-hole"
  $STD bash -c "$(curl -fsSL https://install.pi-hole.net)" -- --unattended
  msg_ok "Installed Pi-hole"

  msg_info "Configuring Web Interface"
  sed -i 's/^WEBTHEME=.*/WEBTHEME=Pi-hole Dark/' /etc/pihole/setupVars.conf
  msg_ok "Configured Web Interface"
}

function post_install_script() {
  msg_ok "Completed Successfully!\n"
  echo -e "${CREATING}${GN}${APP} setup has been successfully initialized!${CL}"
  echo -e "${INFO}${YW}Access it using the following URL:${CL}"
  echo -e "${TAB}${GATEWAY}${BGN}http://${IP}/admin${CL}"
  echo -e "${INFO}${YW}Login with the password in ${CL}${GN}/etc/pihole/setupVars.conf${CL}"
}

function update_script() {
  header_info
  check_container_storage
  check_container_resources
  if [[ ! -d /etc/pihole ]]; then
    msg_error "No ${APP} Installation Found!"
    exit
  fi
  msg_info "Updating Pi-hole"
  set +e
  $STD apt-get update
  $STD apt-get upgrade -y
  /usr/local/bin/pihole -up
  msg_ok "Updated Pi-hole"
  exit
}

# framework bootstrap
# shellcheck disable=SC1090
source <(curl -fsSL "$REPO_BASE/misc/bootstrap/lxc")
