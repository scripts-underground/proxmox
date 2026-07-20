#!/usr/bin/env bash
REPO_BASE="${REPO_BASE:-https://raw.githubusercontent.com/scripts-underground/proxmox/main}"

# Copyright (c) 2021-2026 community-scripts ORG
# Author: kristocopani
# License: MIT | https://raw.githubusercontent.com/scripts-underground/proxmox/main/LICENSE
# Source: https://lubelogger.com/

# shellcheck disable=SC2034
# Read by the framework - shellcheck cannot see the caller
APP="LubeLogger"
var_tags="${var_tags:-vehicle;maintenance}"
var_cpu="${var_cpu:-2}"
var_ram="${var_ram:-2048}"
var_disk="${var_disk:-8}"
var_os="${var_os:-debian}"
var_version="${var_version:-13}"
var_unprivileged="${var_unprivileged:-1}"

function install_script() {
  msg_info "Installing Dependencies"
  $STD apt install -y jq
  msg_ok "Installed Dependencies"

  fetch_and_deploy_gh_release "lubelogger" "hargata/lubelog" "prebuild" "latest" "/opt/lubelogger" "LubeLogger*linux_x64.zip"

  msg_info "Configuring LubeLogger"
  cd /opt/lubelogger || exit
  chmod 700 /opt/lubelogger/CarCareTracker
  jq '.Kestrel = {"Endpoints": {"Http": {"Url": "http://0.0.0.0:5000"}}}' /opt/lubelogger/appsettings.json > /opt/lubelogger/appsettings_tmp.json
  mv /opt/lubelogger/appsettings_tmp.json /opt/lubelogger/appsettings.json
  msg_ok "Configured LubeLogger"

  msg_info "Creating Service"
  cat << EOF > /etc/systemd/system/lubelogger.service
[Unit]
Description=LubeLogger Daemon
After=network.target

[Service]
User=root
Type=simple
WorkingDirectory=/opt/lubelogger
ExecStart=/opt/lubelogger/CarCareTracker
TimeoutStopSec=20
KillMode=process
Restart=on-failure

[Install]
WantedBy=multi-user.target
EOF
  systemctl enable -q --now lubelogger
  msg_ok "Created Service"
}

function post_install_script() {
  msg_ok "Completed Successfully!\n"
  echo -e "${CREATING}${GN}${APP} setup has been successfully initialized!${CL}"
  echo -e "${INFO}${YW} Access it using the following URL:${CL}"
  echo -e "${TAB}${GATEWAY}${BGN}http://${IP}:5000${CL}"
}

function update_script() {
  header_info
  check_container_storage
  check_container_resources
  if [[ ! -f /opt/lubelogger/CarCareTracker ]]; then
    msg_error "No ${APP} Installation Found!"
    exit
  fi
  if check_for_gh_release "lubelogger" "hargata/lubelog"; then
    msg_info "Stopping Service"
    systemctl stop lubelogger
    msg_ok "Stopped Service"

    msg_info "Backing up Configuration"
    cp /opt/lubelogger/appsettings.json /opt/lubelogger/appsettings_bak.json
    msg_ok "Backed up Configuration"

    CLEAN_INSTALL=1 fetch_and_deploy_gh_release "lubelogger" "hargata/lubelog" "prebuild" "latest" "/opt/lubelogger" "LubeLogger*linux_x64.zip"

    msg_info "Restoring Configuration"
    mv /opt/lubelogger/appsettings_bak.json /opt/lubelogger/appsettings.json
    chmod 700 /opt/lubelogger/CarCareTracker
    msg_ok "Restored Configuration"

    msg_info "Starting Service"
    systemctl start lubelogger
    msg_ok "Started Service"
    msg_ok "Updated Successfully"
  fi
  exit
}

# framework bootstrap
# shellcheck disable=SC1090
# Dynamic URL resolved at runtime - shellcheck cannot follow
source <(curl -fsSL "$REPO_BASE/misc/bootstrap/lxc")
