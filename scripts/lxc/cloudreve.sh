#!/usr/bin/env bash
REPO_BASE="${REPO_BASE:-https://raw.githubusercontent.com/scripts-underground/proxmox/main}"

# Sourced by lxc.bootstrap — never executed directly
# Copyright (c) 2021-2026 community-scripts ORG
# Author: MickLesk (CanbiZ)
# License: MIT | https://raw.githubusercontent.com/scripts-underground/proxmox/main/LICENSE
# Source: https://cloudreve.org/

# shellcheck disable=SC2034
APP="Cloudreve"
var_tags="${var_tags:-cloud}"
var_cpu="${var_cpu:-1}"
var_ram="${var_ram:-1024}"
var_disk="${var_disk:-10}"
var_os="${var_os:-debian}"
var_version="${var_version:-13}"
var_arm64="${var_arm64:-yes}"
var_unprivileged="${var_unprivileged:-1}"

function install_script() {
  fetch_and_deploy_gh_release "cloudreve" "cloudreve/cloudreve" "prebuild" "latest" "/opt/cloudreve" "*linux_$(get_system_arch).tar.gz"

  msg_info "Setup Service"
  cat << 'EOF' > /etc/systemd/system/cloudreve.service
[Unit]
Description=Cloudreve Service
After=network.target

[Service]
Type=simple
ExecStart=/opt/cloudreve/cloudreve
Restart=on-failure
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF
  systemctl enable -q --now cloudreve
  msg_ok "Service Setup"
}

function post_install_script() {
  msg_ok "Completed Successfully!\n"
  echo -e "${CREATING}${GN}${APP} setup has been successfully initialized!${CL}"
  echo -e "${INFO}${YW} Access it using the following URL:${CL}"
  echo -e "${TAB}${GATEWAY}${BGN}http://${IP}:5212${CL}"
}

function update_script() {
  header_info
  check_container_storage
  check_container_resources
  if [[ ! -d /opt/cloudreve ]]; then
    msg_error "No ${APP} Installation Found!"
    exit
  fi
  if check_for_gh_release "cloudreve" "cloudreve/cloudreve"; then
    msg_info "Stopping Service"
    systemctl stop cloudreve
    msg_ok "Stopped Service"
    CLEAN_INSTALL=1 fetch_and_deploy_gh_release "cloudreve" "cloudreve/cloudreve" "prebuild" "latest" "/opt/cloudreve" "*linux_$(get_system_arch).tar.gz"
    msg_info "Starting Service"
    systemctl start cloudreve
    msg_ok "Started Service"
    msg_ok "Updated successfully!"
  fi
  exit
}

# shellcheck disable=SC1090
source <(curl -fsSL "$REPO_BASE/misc/bootstrap/lxc")
