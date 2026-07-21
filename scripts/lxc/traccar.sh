#!/usr/bin/env bash
REPO_BASE="${REPO_BASE:-https://raw.githubusercontent.com/scripts-underground/proxmox/main}"

# Copyright (c) 2021-2026 community-scripts ORG
# Author: tteck (tteckster)
# License: MIT | https://raw.githubusercontent.com/scripts-underground/proxmox/main/LICENSE
# Source: https://www.traccar.org/

# shellcheck disable=SC2034
# Read by the framework - shellcheck cannot see the caller
APP="Traccar"
var_tags="${var_tags:-gps;tracker}"
var_cpu="${var_cpu:-1}"
var_ram="${var_ram:-1024}"
var_disk="${var_disk:-2}"
var_os="${var_os:-debian}"
var_version="${var_version:-13}"
var_arm64="${var_arm64:-yes}"
var_unprivileged="${var_unprivileged:-1}"

function install_script() {
  msg_info "Configuring Traccar"
  ARCH=$(uname -m)
  [[ "$ARCH" == "x86_64" ]] && ARCH="64"
  [[ "$ARCH" == "aarch64" ]] && ARCH="arm"
  fetch_and_deploy_gh_release "traccar" "traccar/traccar" "prebuild" "latest" "/opt/traccar" "traccar-linux-${ARCH}-*.zip"
  cd /opt/traccar || exit
  $STD ./traccar.run
  rm -f /opt/traccar/README.txt /opt/traccar/traccar.run
  systemctl enable -q --now traccar
  msg_ok "Configured Traccar"
}

function post_install_script() {
  msg_ok "Completed Successfully!\n"
  echo -e "${CREATING}${GN}${APP} setup has been successfully initialized!${CL}"
  echo -e "${INFO}${YW}Access it using the following URL:${CL}"
  echo -e "${TAB}${GATEWAY}${BGN}http://${IP}:8082${CL}"
}

function update_script() {
  header_info
  check_container_storage
  check_container_resources
  if [[ ! -d /opt/traccar ]]; then
    msg_error "No ${APP} Installation Found!"
    exit
  fi

  if check_for_gh_release "traccar" "traccar/traccar"; then
    msg_info "Stopping Service"
    systemctl stop traccar
    msg_ok "Stopped Service"

    msg_info "Creating backup"
    mv /opt/traccar/conf/traccar.xml /opt
    [[ -d /opt/traccar/data ]] && mv /opt/traccar/data /opt
    [[ -d /opt/traccar/media ]] && mv /opt/traccar/media /opt
    msg_ok "Backup created"

    ARCH=$(uname -m)
    [[ "$ARCH" == "x86_64" ]] && ARCH="64"
    [[ "$ARCH" == "aarch64" ]] && ARCH="arm"
    CLEAN_INSTALL=1 fetch_and_deploy_gh_release "traccar" "traccar/traccar" "prebuild" "latest" "/opt/traccar" "traccar-linux-${ARCH}-*.zip"

    msg_info "Perform Update"
    cd /opt/traccar || exit
    $STD ./traccar.run
    msg_ok "App-Update completed"

    msg_info "Restoring data"
    mv /opt/traccar.xml /opt/traccar/conf
    [[ -d /opt/data ]] && mv /opt/data /opt/traccar
    [[ -d /opt/media ]] && mv /opt/media /opt/traccar
    rm -f /opt/traccar/README.txt /opt/traccar/traccar.run
    msg_ok "Data restored"

    msg_info "Starting Service"
    systemctl start traccar
    msg_ok "Started Service"
    msg_ok "Updated successfully!"
  fi
  exit
}

# shellcheck disable=SC1090
# Dynamic URL resolved at runtime - shellcheck cannot follow
source <(curl -fsSL "$REPO_BASE/misc/bootstrap/lxc")
