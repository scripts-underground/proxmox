#!/usr/bin/env bash
REPO_BASE="${REPO_BASE:-https://raw.githubusercontent.com/scripts-underground/proxmox/main}"
# Sourced by lxc.bootstrap — never executed directly
# Copyright (c) 2021-2026 community-scripts ORG
# Author: vhsdream
# License: MIT | https://raw.githubusercontent.com/scripts-underground/proxmox/main/LICENSE
# Source: https://github.com/fccview/jotty
# shellcheck disable=SC2034
APP="jotty"
var_tags="${var_tags:-tasks;notes}"
var_cpu="${var_cpu:-1}"
var_ram="${var_ram:-1024}"
var_disk="${var_disk:-4}"
var_os="${var_os:-debian}"
var_version="${var_version:-13}"
var_arm64="${var_arm64:-yes}"
var_unprivileged="${var_unprivileged:-1}"
function install_script() {
  NODE_VERSION="22" NODE_MODULE="yarn" setup_nodejs
  fetch_and_deploy_gh_release "jotty" "fccview/jotty" "prebuild" "latest" "/opt/jotty" "jotty_*_prebuild.tar.gz"
  msg_info "Setup jotty"
  mkdir -p /opt/jotty/data/{users,checklists,notes}
  cat << 'EOF' > /opt/jotty/.env
NODE_ENV=production
EOF
  msg_ok "Setup jotty"
  msg_info "Creating Service"
  cat << 'EOF' > /etc/systemd/system/jotty.service
[Unit]
Description=jotty server
After=network.target
[Service]
WorkingDirectory=/opt/jotty
EnvironmentFile=/opt/jotty/.env
ExecStart=/usr/bin/node server.js
Restart=on-abnormal
[Install]
WantedBy=multi-user.target
EOF
  systemctl enable -q --now jotty
  msg_ok "Created Service"
}
function post_install_script() {
  msg_ok "Completed Successfully!\n"
  echo -e "${CREATING}${GN}${APP} setup has been successfully initialized!${CL}"
  echo -e "${INFO}${YW} Access it using the following URL:${CL}"
  echo -e "${TAB}${GATEWAY}${BGN}http://${IP}:3000${CL}"
}
function update_script() {
  header_info
  check_container_storage
  check_container_resources
  if [[ ! -d /opt/jotty ]]; then
    msg_error "No ${APP} Installation Found!"
    exit
  fi
  if check_for_gh_release "jotty" "fccview/jotty"; then
    NODE_VERSION="22" NODE_MODULE="yarn" setup_nodejs
    msg_info "Stopping Service"
    systemctl stop jotty
    msg_ok "Stopped Service"
    create_backup /opt/jotty/.env /opt/jotty/data
    CLEAN_INSTALL=1 fetch_and_deploy_gh_release "jotty" "fccview/jotty" "prebuild" "latest" "/opt/jotty" "jotty_*_prebuild.tar.gz"
    restore_backup
    msg_info "Starting Service"
    systemctl start jotty
    msg_ok "Started Service"
    msg_ok "Updated successfully!"
  fi
  exit
}
# shellcheck disable=SC1090
source <(curl -fsSL "$REPO_BASE/misc/bootstrap/lxc")
