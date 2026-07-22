#!/usr/bin/env bash
REPO_BASE="${REPO_BASE:-https://raw.githubusercontent.com/scripts-underground/proxmox/main}"

# Copyright (c) 2021-2026 community-scripts ORG
# Author: Dominik Siebel (dsiebel)
# License: MIT | https://raw.githubusercontent.com/scripts-underground/proxmox/main/LICENSE
# Source: https://github.com/toniebox-reverse-engineering/teddycloud

# shellcheck disable=SC2034
APP="TeddyCloud"
var_tags="${var_tags:-media}"
var_cpu="${var_cpu:-2}"
var_ram="${var_ram:-1024}"
var_disk="${var_disk:-8}"
var_os="${var_os:-debian}"
var_version="${var_version:-13}"
var_arm64="${var_arm64:-no}"
var_unprivileged="${var_unprivileged:-1}"

function install_script() {
  msg_info "Installing Dependencies"
  $STD apt install -y \
    libubsan1 \
    ffmpeg \
    ca-certificates
  msg_ok "Installed Dependencies"

  fetch_and_deploy_gh_release "teddycloud" "toniebox-reverse-engineering/teddycloud" "prebuild" "latest" "/opt/teddycloud" "teddycloud.amd64.release*.zip"

  msg_info "Creating Service"
  cat << EOF > /etc/systemd/system/teddycloud.service
[Unit]
Description=TeddyCloud Server
After=network.target

[Service]
User=root
Type=simple
ExecStart=/opt/teddycloud/teddycloud
WorkingDirectory=/opt/teddycloud
Restart=on-failure

[Install]
WantedBy=multi-user.target
EOF
  systemctl enable --now -q teddycloud
  msg_ok "Created Service"
}

function post_install_script() {
  msg_ok "Completed successfully!\n"
  echo -e "${CREATING}${GN}${APP} setup has been successfully initialized!${CL}"
  echo -e "${INFO}${YW}Access it using the following URL:${CL}"
  echo -e "${GATEWAY}${BGN}http://${IP}${CL}"
}

function update_script() {
  header_info
  check_container_storage
  check_container_resources
  if [[ ! -d /opt/teddycloud ]]; then
    msg_error "No ${APP} Installation Found!"
    exit
  fi

  if check_for_gh_release "teddycloud" "toniebox-reverse-engineering/teddycloud"; then
    msg_info "Stopping Service"
    systemctl stop teddycloud
    msg_ok "Stopped Service"

    create_backup /opt/teddycloud/certs /opt/teddycloud/config /opt/teddycloud/data

    CLEAN_INSTALL=1 fetch_and_deploy_gh_release "teddycloud" "toniebox-reverse-engineering/teddycloud" "prebuild" "latest" "/opt/teddycloud" "teddycloud.amd64.release*.zip"

    restore_backup

    msg_info "Starting Service"
    systemctl start teddycloud
    msg_ok "Started Service"
    msg_ok "Updated successfully!"
  fi
  exit
}

# shellcheck disable=SC1090
source <(curl -fsSL "$REPO_BASE/misc/bootstrap/lxc")
