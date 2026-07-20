#!/usr/bin/env bash
REPO_BASE="${REPO_BASE:-https://raw.githubusercontent.com/scripts-underground/proxmox/main}"

# Sourced by lxc.bootstrap — never executed directly
# Copyright (c) 2021-2026 community-scripts ORG
# Author: tteck (tteckster)
# License: MIT | https://raw.githubusercontent.com/scripts-underground/proxmox/main/LICENSE
# Source: https://gotify.net/

# shellcheck disable=SC2034
# Read by the framework - shellcheck cannot see the caller
APP="Gotify"
var_tags="${var_tags:-notifications;messaging}"
var_cpu="${var_cpu:-1}"
var_ram="${var_ram:-512}"
var_disk="${var_disk:-2}"
var_os="${var_os:-debian}"
var_version="${var_version:-13}"
var_arm64="${var_arm64:-yes}"
var_unprivileged="${var_unprivileged:-1}"

function install_script() {
  msg_info "Installing Dependencies"
  $STD apt install -y curl sudo mc
  msg_ok "Installed Dependencies"

  fetch_and_deploy_gh_release "gotify" "gotify/server" "prebuild" "latest" "/opt/gotify" "gotify-linux-$(get_system_arch).zip"

  chmod +x "/opt/gotify/gotify-linux-$(get_system_arch)"

  msg_info "Creating Service"
  cat << EOF > /etc/systemd/system/gotify.service
[Unit]
Description=Gotify
Requires=network.target
After=network.target

[Service]
Type=simple
User=root
WorkingDirectory=/opt/gotify
ExecStart=/opt/gotify/gotify-linux-$(get_system_arch)
Restart=always
RestartSec=3

[Install]
WantedBy=multi-user.target
EOF
  systemctl enable -q --now gotify
  msg_ok "Created Service"
}

function post_install_script() {
  msg_ok "Completed Successfully!\n"
  echo -e "${CREATING}${GN}${APP} setup has been successfully initialized!${CL}"
  echo -e "${INFO}${YW} Access it using the following URL:${CL}"
  echo -e "${TAB}${GATEWAY}${BGN}http://${IP}:80${CL}"
}

function update_script() {
  header_info
  check_container_storage
  check_container_resources
  if [[ ! -d /opt/gotify ]]; then
    msg_error "No ${APP} Installation Found!"
    exit
  fi
  if check_for_gh_release "gotify" "gotify/server"; then
    msg_info "Stopping ${APP}"
    systemctl stop gotify
    msg_ok "Stopped ${APP}"

    CLEAN_INSTALL=1 fetch_and_deploy_gh_release "gotify" "gotify/server" "prebuild" "latest" "/opt/gotify" "gotify-linux-$(get_system_arch).zip"

    chmod +x "/opt/gotify/gotify-linux-$(get_system_arch)"

    msg_info "Starting ${APP}"
    systemctl start gotify
    msg_ok "Started ${APP}"
    msg_ok "Updated successfully!"
  fi
  exit
}

# framework bootstrap
# shellcheck disable=SC1090
# Dynamic URL resolved at runtime - shellcheck cannot see the caller
source <(curl -fsSL "$REPO_BASE/misc/bootstrap/lxc")
