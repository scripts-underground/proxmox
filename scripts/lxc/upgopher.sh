#!/usr/bin/env bash
REPO_BASE="${REPO_BASE:-https://raw.githubusercontent.com/scripts-underground/proxmox/main}"

# Sourced by lxc.bootstrap — never executed directly
# Copyright (c) 2021-2026 community-scripts ORG
# Author: Eduard González (wanetty)
# License: MIT | https://raw.githubusercontent.com/scripts-underground/proxmox/main/LICENSE
# Source: https://github.com/wanetty/upgopher

# shellcheck disable=SC2034
# Read by the framework - shellcheck cannot see the caller
APP="Upgopher"
var_tags="${var_tags:-file-sharing}"
var_cpu="${var_cpu:-1}"
var_ram="${var_ram:-512}"
var_disk="${var_disk:-4}"
var_os="${var_os:-debian}"
var_version="${var_version:-13}"
var_arm64="${var_arm64:-yes}"
var_unprivileged="${var_unprivileged:-1}"

function install_script() {
  msg_info "Installing Upgopher"
  fetch_and_deploy_gh_release "upgopher" "wanetty/upgopher" "prebuild" "latest" "/opt/upgopher" "upgopher_*_linux_$(get_system_arch).tar.gz"
  chmod +x /opt/upgopher/upgopher
  mkdir -p /opt/upgopher/uploads
  msg_ok "Installed Upgopher"

  msg_info "Creating Service"
  cat << EOF > /etc/systemd/system/upgopher.service
[Unit]
Description=Upgopher File Server
Documentation=https://github.com/wanetty/upgopher
After=network.target

[Service]
Type=simple
User=root
WorkingDirectory=/opt/upgopher
ExecStart=/opt/upgopher/upgopher -port 9090 -dir /opt/upgopher/uploads
Restart=always
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF
  systemctl enable -q --now upgopher
  msg_ok "Created Service"
}

function update_script() {
  header_info
  check_container_storage
  check_container_resources

  if [[ ! -d /opt/upgopher ]]; then
    msg_error "No ${APP} Installation Found!"
    exit
  fi

  if check_for_gh_release "upgopher" "wanetty/upgopher"; then
    msg_info "Stopping Service"
    systemctl stop upgopher
    msg_ok "Stopped Service"

    fetch_and_deploy_gh_release "upgopher" "wanetty/upgopher" "prebuild" "latest" "/opt/upgopher" "upgopher_*_linux_$(get_system_arch).tar.gz"
    chmod +x /opt/upgopher/upgopher

    msg_info "Starting Service"
    systemctl start upgopher
    msg_ok "Started Service"
    msg_ok "Updated successfully!"
  fi
  exit
}

# framework bootstrap
# shellcheck disable=SC1090
# Dynamic URL resolved at runtime - shellcheck cannot follow
source <(curl -fsSL "$REPO_BASE/misc/bootstrap/lxc")
