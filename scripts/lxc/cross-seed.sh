#!/usr/bin/env bash
REPO_BASE="${REPO_BASE:-https://raw.githubusercontent.com/scripts-underground/proxmox/main}"

# Sourced by lxc.bootstrap — never executed directly
# Copyright (c) 2021-2026 community-scripts ORG
# Author: Jakub Matraszek (jmatraszek)
# License: MIT | https://raw.githubusercontent.com/scripts-underground/proxmox/main/LICENSE
# Source: https://www.cross-seed.org/

# shellcheck disable=SC2034
# Read by the framework - shellcheck cannot see the caller
APP="cross-seed"
var_tags="${var_tags:-arr}"
var_cpu="${var_cpu:-1}"
var_ram="${var_ram:-1024}"
var_disk="${var_disk:-2}"
var_os="${var_os:-debian}"
var_version="${var_version:-13}"
var_arm64="${var_arm64:-yes}"
var_unprivileged="${var_unprivileged:-1}"

function install_script() {
  msg_info "Installing Dependencies"
  $STD apt install -y build-essential
  msg_ok "Installed Dependencies"

  NODE_VERSION="24" setup_nodejs

  msg_info "Setup Cross-Seed"
  $STD npm install cross-seed@latest -g
  $STD cross-seed gen-config
  msg_ok "Setup Cross-Seed"

  msg_info "Creating Service"
  cat << EOF > /etc/systemd/system/cross-seed.service
[Unit]
Description=Cross-Seed daemon Service
After=network.target

[Service]
ExecStart=/usr/bin/cross-seed daemon
Restart=on-failure
RestartSec=30
User=root

[Install]
WantedBy=multi-user.target
EOF
  systemctl enable -q --now cross-seed
  msg_ok "Created Service"
}

function post_install_script() {
  msg_ok "Completed Successfully!\n"
  echo -e "${CREATING}${GN}${APP} setup has been successfully initialized!${CL}"
  echo -e "${INFO}${YW} Access it using the following URL:${CL}"
  echo -e "${TAB}${GATEWAY}${BGN}http://${IP}:2468${CL}"
}

function update_script() {
  header_info
  check_container_storage
  check_container_resources

  NODE_VERSION="24" setup_nodejs
  $STD apt install -y build-essential

  if command -v cross-seed &> /dev/null; then
    current_version=$(cross-seed --version)
    latest_version=$(npm show cross-seed version)
    if [ "$current_version" != "$latest_version" ]; then
      msg_info "Updating cross-seed from v${current_version} to v${latest_version}"
      $STD npm install -g cross-seed@latest
      systemctl restart cross-seed
      msg_ok "Updated successfully!"
    else
      msg_ok "cross-seed is already at v${current_version}"
    fi
  else
    msg_error "No ${APP} Installation Found!"
    exit
  fi
  exit
}

# framework bootstrap
# shellcheck disable=SC1090
# Dynamic URL resolved at runtime - shellcheck cannot follow
source <(curl -fsSL "$REPO_BASE/misc/bootstrap/lxc")
