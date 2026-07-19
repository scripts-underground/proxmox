#!/usr/bin/env bash
REPO_BASE="${REPO_BASE:-https://raw.githubusercontent.com/scripts-underground/proxmox/main}"

# Sourced by lxc.bootstrap — never executed directly
# Copyright (c) 2021-2026 community-scripts ORG
# Author: Lucas Zampieri (zampierilucas)
# License: MIT | https://raw.githubusercontent.com/scripts-underground/proxmox/main/LICENSE
# Source: https://github.com/Cleanuparr/Cleanuparr

# shellcheck disable=SC2034
APP="Cleanuparr"
var_tags="${var_tags:-arr}"
var_cpu="${var_cpu:-2}"
var_ram="${var_ram:-1024}"
var_disk="${var_disk:-4}"
var_os="${var_os:-debian}"
var_version="${var_version:-13}"
var_arm64="${var_arm64:-yes}"
var_unprivileged="${var_unprivileged:-1}"

function install_script() {
  fetch_and_deploy_gh_release "Cleanuparr" "Cleanuparr/Cleanuparr" "prebuild" "latest" "/opt/cleanuparr" "*linux-$(get_system_arch).zip"

  msg_info "Creating Service"
  cat << 'EOF' > /etc/systemd/system/cleanuparr.service
[Unit]
Description=Cleanuparr Daemon
After=syslog.target network.target

[Service]
Type=simple
User=root
WorkingDirectory=/opt/cleanuparr
ExecStart=/opt/cleanuparr/Cleanuparr
Restart=on-failure
RestartSec=5
Environment="PORT=11011"
Environment="CONFIG_DIR=/opt/cleanuparr/config"

[Install]
WantedBy=multi-user.target
EOF
  systemctl enable -q --now cleanuparr
  msg_ok "Created Service"
}

function post_install_script() {
  msg_ok "Completed Successfully!\n"
  echo -e "${CREATING}${GN}${APP} setup has been successfully initialized!${CL}"
  echo -e "${INFO}${YW} Access it using the following URL:${CL}"
  echo -e "${TAB}${GATEWAY}${BGN}http://${IP}:11011${CL}"
}

function update_script() {
  header_info
  check_container_storage
  check_container_resources
  if [[ ! -d /opt/cleanuparr ]]; then
    msg_error "No ${APP} Installation Found!"
    exit
  fi
  if check_for_gh_release "Cleanuparr" "Cleanuparr/Cleanuparr"; then
    msg_info "Stopping Service"
    systemctl stop cleanuparr
    msg_ok "Stopped Service"
    CLEAN_INSTALL=1 fetch_and_deploy_gh_release "Cleanuparr" "Cleanuparr/Cleanuparr" "prebuild" "latest" "/opt/cleanuparr" "*linux-$(get_system_arch).zip"
    msg_info "Starting Service"
    systemctl start cleanuparr
    msg_ok "Started Service"
    msg_ok "Updated successfully!"
  fi
  exit
}

# shellcheck disable=SC1090
source <(curl -fsSL "$REPO_BASE/misc/bootstrap/lxc")
