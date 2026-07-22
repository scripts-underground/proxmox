#!/usr/bin/env bash
REPO_BASE="${REPO_BASE:-https://raw.githubusercontent.com/scripts-underground/proxmox/main}"

# Sourced by lxc.bootstrap — never executed directly
# Copyright (c) 2021-2026 community-scripts ORG
# Author: michelroegl-brunner
# License: MIT | https://raw.githubusercontent.com/scripts-underground/proxmox/main/LICENSE
# Source: https://github.com/community-scripts/ProxmoxVE-Local

# shellcheck disable=SC2034
# Read by the framework - shellcheck cannot see the caller
APP="PVE-Scripts-Local"
var_tags="${var_tags:-pve-scripts-local}"
var_cpu="${var_cpu:-2}"
var_ram="${var_ram:-4096}"
var_disk="${var_disk:-10}"
var_os="${var_os:-debian}"
var_version="${var_version:-13}"
var_arm64="${var_arm64:-yes}"
var_unprivileged="${var_unprivileged:-1}"

function install_script() {
  msg_info "Installing Dependencies"
  $STD apt install -y \
    build-essential \
    sshpass \
    rsync \
    expect
  msg_ok "Installed Dependencies"

  NODE_VERSION="24" setup_nodejs

  fetch_and_deploy_gh_release "ProxmoxVE-Local" "community-scripts/ProxmoxVE-Local" "tarball"

  msg_info "Installing PVE Scripts local"
  cd /opt/ProxmoxVE-Local || exit
  $STD npm install
  cp .env.example .env
  mkdir -p data
  chmod 755 data

  $STD npx prisma generate
  $STD npx prisma migrate deploy

  $STD npm run build
  msg_ok "Installed PVE Scripts local"

  msg_info "Creating Service"
  cat << EOF > /etc/systemd/system/pvescriptslocal.service
[Unit]
Description=PVEScriptslocal Service
After=network.target

[Service]
WorkingDirectory=/opt/ProxmoxVE-Local
ExecStart=/usr/bin/npm start
Restart=always
RestartSec=10
Environment=NODE_ENV=production
User=root

[Install]
WantedBy=multi-user.target
EOF
  systemctl enable -q --now pvescriptslocal
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
  if [[ ! -d /opt/ProxmoxVE-Local ]]; then
    msg_error "No ${APP} Installation Found!"
    exit
  fi
  msg_error "The app offers a built-in updater. Please use it."
  exit
}

# framework bootstrap
# shellcheck disable=SC1090
# Dynamic URL resolved at runtime - shellcheck cannot follow
source <(curl -fsSL "$REPO_BASE/misc/bootstrap/lxc")
