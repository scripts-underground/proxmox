#!/usr/bin/env bash
REPO_BASE="${REPO_BASE:-https://raw.githubusercontent.com/scripts-underground/proxmox/main}"
# Sourced by lxc.bootstrap — never executed directly
# Copyright (c) 2021-2026 community-scripts ORG
# Author: MickLesk (Canbiz)
# License: MIT | https://raw.githubusercontent.com/scripts-underground/proxmox/main/LICENSE
# Source: https://github.com/gnmyt/myspeed
# shellcheck disable=SC2034
APP="MySpeed"
var_tags="${var_tags:-tracking}"
var_cpu="${var_cpu:-1}"
var_ram="${var_ram:-1024}"
var_disk="${var_disk:-4}"
var_os="${var_os:-debian}"
var_version="${var_version:-13}"
var_arm64="${var_arm64:-yes}"
var_unprivileged="${var_unprivileged:-1}"
function install_script() {
  msg_info "Installing Dependencies"
  $STD apt install -y build-essential ca-certificates python3-setuptools
  msg_ok "Installed Dependencies"
  NODE_VERSION="22" setup_nodejs
  fetch_and_deploy_gh_release "myspeed" "gnmyt/myspeed" "prebuild" "latest" "/opt/myspeed" "MySpeed-*.zip"
  msg_info "Configuring MySpeed"
  cd /opt/myspeed || exit
  $STD npm install
  msg_ok "Installed MySpeed"
  msg_info "Creating Service"
  cat << 'EOF' > /etc/systemd/system/myspeed.service
[Unit]
Description=MySpeed
After=network.target
[Service]
Type=simple
ExecStart=/usr/bin/node server
Restart=always
User=root
Environment=NODE_ENV=production
WorkingDirectory=/opt/myspeed
[Install]
WantedBy=multi-user.target
EOF
  systemctl enable -q --now myspeed
  msg_ok "Created Service"
}
function post_install_script() {
  msg_ok "Completed Successfully!\n"
  echo -e "${CREATING}${GN}${APP} setup has been successfully initialized!${CL}"
  echo -e "${INFO}${YW} Access it using the following URL:${CL}"
  echo -e "${TAB}${GATEWAY}${BGN}http://${IP}:5216${CL}"
}
function update_script() {
  header_info
  check_container_storage
  check_container_resources
  if [[ ! -d /opt/myspeed ]]; then
    msg_error "No ${APP} Installation Found!"
    exit
  fi
  if check_for_gh_release "myspeed" "gnmyt/myspeed"; then
    msg_info "Stopping Service"
    systemctl stop myspeed
    msg_ok "Stopped Service"
    CLEAN_INSTALL=1 fetch_and_deploy_gh_release "myspeed" "gnmyt/myspeed" "prebuild" "latest" "/opt/myspeed" "MySpeed-*.zip"
    cd /opt/myspeed || exit
    $STD npm install
    msg_info "Starting Service"
    systemctl start myspeed
    msg_ok "Started Service"
    msg_ok "Updated successfully!"
  fi
  exit
}
# shellcheck disable=SC1090
source <(curl -fsSL "$REPO_BASE/misc/bootstrap/lxc")
