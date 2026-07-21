#!/usr/bin/env bash
REPO_BASE="${REPO_BASE:-https://raw.githubusercontent.com/scripts-underground/proxmox/main}"

# Copyright (c) 2021-2026 community-scripts ORG
# Author: MickLesk (CanbiZ)
# License: MIT | https://raw.githubusercontent.com/scripts-underground/proxmox/main/LICENSE
# Source: https://certimate.me/

# shellcheck disable=SC2034
# Read by the framework - shellcheck cannot see the caller
APP="Certimate"
var_tags="${var_tags:-ssl;certificates;acme;automation}"
var_cpu="${var_cpu:-1}"
var_ram="${var_ram:-256}"
var_disk="${var_disk:-2}"
var_os="${var_os:-debian}"
var_version="${var_version:-13}"
var_arm64="${var_arm64:-yes}"
var_unprivileged="${var_unprivileged:-1}"

function install_script() {
  fetch_and_deploy_gh_release "certimate" "certimate-go/certimate" "prebuild" "latest" "/opt/certimate" "certimate_*_linux_amd64.zip"

  msg_info "Creating Service"
  cat << 'EOF' > /etc/systemd/system/certimate.service
[Unit]
Description=Certimate SSL Certificate Manager
After=network.target

[Service]
Type=simple
User=root
WorkingDirectory=/opt/certimate
ExecStart=/opt/certimate/certimate serve --http "0.0.0.0:8090"
Restart=on-failure
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF
  systemctl enable -q --now certimate
  msg_ok "Created Service"
}

function post_install_script() {
  msg_ok "Completed Successfully!\n"
  echo -e "${CREATING}${GN}${APP} setup has been successfully initialized!${CL}"
  echo -e "${INFO}${YW}Access it using the following URL:${CL}"
  echo -e "${GATEWAY}${BGN}http://${IP}:8090${CL}"
}

function update_script() {
  header_info
  check_container_storage
  check_container_resources

  if [[ ! -f /opt/certimate/certimate ]]; then
    msg_error "No ${APP} Installation Found!"
    exit
  fi

  if check_for_gh_release "certimate" "certimate-go/certimate"; then
    msg_info "Stopping Service"
    systemctl stop certimate
    msg_ok "Stopped Service"

    msg_info "Backing up Data"
    cp -r /opt/certimate/pb_data /opt/certimate_pb_data_backup
    msg_ok "Backed up Data"

    fetch_and_deploy_gh_release "certimate" "certimate-go/certimate" "prebuild" "latest" "/opt/certimate" "certimate_*_linux_amd64.zip"

    msg_info "Restoring Data"
    cp -r /opt/certimate_pb_data_backup/. /opt/certimate/pb_data
    rm -rf /opt/certimate_pb_data_backup
    msg_ok "Restored Data"

    msg_info "Starting Service"
    systemctl start certimate
    msg_ok "Started Service"
    msg_ok "Updated successfully!"
  fi
  exit
}

# framework bootstrap
# shellcheck disable=SC1090
# Dynamic URL resolved at runtime - shellcheck cannot follow
source <(curl -fsSL "$REPO_BASE/misc/bootstrap/lxc")

