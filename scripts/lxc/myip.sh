#!/usr/bin/env bash
REPO_BASE="${REPO_BASE:-https://raw.githubusercontent.com/scripts-underground/proxmox/main}"
# Sourced by lxc.bootstrap — never executed directly
# Copyright (c) 2021-2026 community-scripts ORG
# Author: Slaviša Arežina (tremor021)
# License: MIT | https://raw.githubusercontent.com/scripts-underground/proxmox/main/LICENSE
# Source: https://ipcheck.ing/
# shellcheck disable=SC2034
APP="MyIP"
var_tags="${var_tags:-network}"
var_cpu="${var_cpu:-2}"
var_ram="${var_ram:-1024}"
var_disk="${var_disk:-4}"
var_os="${var_os:-debian}"
var_version="${var_version:-13}"
var_arm64="${var_arm64:-yes}"
var_unprivileged="${var_unprivileged:-1}"
function install_script() {
  NODE_VERSION="24" setup_nodejs
  fetch_and_deploy_gh_release "myip" "jason5ng32/MyIP" "tarball"
  msg_info "Configuring MyIP"
  cd /opt/myip || exit
  cp .env.example .env
  $STD npm install
  $STD npm run build
  msg_ok "Configured MyIP"
  msg_info "Creating Service"
  cat << EOF > /etc/systemd/system/myip.service
[Unit]
Description=MyIP Service
After=network.target

[Service]
Type=simple
User=root
WorkingDirectory=/opt/myip
ExecStart=/usr/bin/npm start
EnvironmentFile=/opt/myip/.env
Restart=on-failure
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF
  systemctl enable -q --now myip
  msg_ok "Service created"
}
function post_install_script() {
  msg_ok "Completed successfully!\n"
  echo -e "${CREATING}${GN}${APP} setup has been successfully initialized!${CL}"
  echo -e "${INFO}${YW}Access it using the following URL:${CL}"
  echo -e "${TAB}${GATEWAY}${BGN}http://${IP}:18966${CL}"
}
function update_script() {
  header_info
  check_container_storage
  check_container_resources
  if [[ ! -d /opt/myip ]]; then
    msg_error "No ${APP} Installation Found!"
    exit
  fi
  NODE_VERSION="24" setup_nodejs
  if check_for_gh_release "myip" "jason5ng32/MyIP"; then
    msg_info "Stopping Services"
    systemctl stop myip
    msg_ok "Stopped Services"
    cp /opt/myip/.env /opt
    CLEAN_INSTALL=1 fetch_and_deploy_gh_release "myip" "jason5ng32/MyIP" "tarball"
    mv /opt/.env /opt/myip
    msg_info "Starting Services"
    systemctl start myip
    msg_ok "Started Services"
    msg_ok "Updated successfully!"
  fi
  exit
}
# framework bootstrap
# shellcheck disable=SC1090
source <(curl -fsSL "$REPO_BASE/misc/bootstrap/lxc")
