#!/usr/bin/env bash
REPO_BASE="${REPO_BASE:-https://raw.githubusercontent.com/scripts-underground/proxmox/main}"

# Sourced by lxc.bootstrap — never executed directly
# Copyright (c) 2021-2026 community-scripts ORG
# Author: Michelle Zitzerman (Sinofage)
# License: MIT | https://raw.githubusercontent.com/scripts-underground/proxmox/main/LICENSE
# Source: https://beszel.dev/

# shellcheck disable=SC2034
APP="Beszel"
var_tags="${var_tags:-monitoring}"
var_cpu="${var_cpu:-1}"
var_ram="${var_ram:-512}"
var_disk="${var_disk:-5}"
var_os="${var_os:-debian}"
var_version="${var_version:-13}"
var_arm64="${var_arm64:-yes}"
var_unprivileged="${var_unprivileged:-1}"

function install_script() {
  msg_info "Installing Dependencies"
  $STD apt install -y curl sudo
  msg_ok "Installed Dependencies"
  fetch_and_deploy_gh_release "beszel" "henrygd/beszel" "prebuild" "latest" "/opt/beszel" "beszel_linux_$(get_system_arch).tar.gz"
  msg_info "Creating Service"
  cat << 'EOF' > /etc/systemd/system/beszel-hub.service
[Unit]
Description=Beszel Hub Service
After=network.target

[Service]
WorkingDirectory=/opt/beszel
ExecStart=/opt/beszel/beszel serve --http "0.0.0.0:8090"
Restart=always
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF
  systemctl enable -q --now beszel-hub
  msg_ok "Created Service"
}

function post_install_script() {
  msg_ok "Completed Successfully!\n"
  echo -e "${CREATING}${GN}${APP} setup has been successfully initialized!${CL}"
  echo -e "${INFO}${YW} Access it using the following URL:${CL}"
  echo -e "${TAB}${GATEWAY}${BGN}http://${IP}:8090${CL}"
}

function update_script() {
  header_info
  check_container_storage
  check_container_resources
  if [[ ! -d /opt/beszel ]]; then
    msg_error "No ${APP} Installation Found!"
    exit
  fi
  if check_for_gh_release "beszel" "henrygd/beszel"; then
    msg_info "Stopping Service"
    systemctl stop beszel-hub
    msg_ok "Stopped Service"
    fetch_and_deploy_gh_release "beszel" "henrygd/beszel" "prebuild" "latest" "/opt/beszel" "beszel_linux_$(get_system_arch).tar.gz"
    msg_info "Starting Service"
    systemctl start beszel-hub
    msg_ok "Started Service"
    msg_ok "Updated successfully!"
  fi
  exit
}

# shellcheck disable=SC1090
source <(curl -fsSL "$REPO_BASE/misc/bootstrap/lxc")
