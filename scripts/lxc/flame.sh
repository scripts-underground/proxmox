#!/usr/bin/env bash
REPO_BASE="${REPO_BASE:-https://raw.githubusercontent.com/scripts-underground/proxmox/main}"
source <(curl -fsSL "$REPO_BASE/misc/build.func")

# Sourced by lxc.bootstrap — never executed directly
# Copyright (c) 2021-2026 community-scripts ORG
# Author: CrazyWolf13
# License: MIT | https://github.com/community-scripts/ProxmoxVED/raw/main/LICENSE
# Source: https://github.com/pawelmalak/flame

APP="Flame"
var_tags="${var_tags:-dashboard;startpage}"
var_cpu="${var_cpu:-2}"
var_ram="${var_ram:-2048}"
var_disk="${var_disk:-4}"
var_os="${var_os:-debian}"
var_version="${var_version:-13}"
var_arm64="${var_arm64:-no}"
var_unprivileged="${var_unprivileged:-1}"

function update_script() {
  header_info
  check_container_storage
  check_container_resources

  if [[ ! -d /opt/flame ]]; then
    msg_error "No ${APP} Installation Found!"
    exit
  fi

  if check_for_gh_release "flame" "pawelmalak/flame"; then
    msg_info "Stopping Service"
    systemctl stop flame
    msg_ok "Stopped Service"

    msg_info "Backing up Data"
    cp -r /opt/flame/data /opt/flame_data_backup
    cp /opt/flame/.env /opt/flame.env.bak
    msg_ok "Backed up Data"

    CLEAN_INSTALL=1 fetch_and_deploy_gh_release "flame" "pawelmalak/flame" "tarball"

    msg_info "Restoring Data"
    cp -r /opt/flame_data_backup/. /opt/flame/data
    cp /opt/flame.env.bak /opt/flame/.env
    sed -i "s/^VERSION=.*/VERSION=$(cat ~/.flame)/" /opt/flame/.env
    rm -rf /opt/flame_data_backup /opt/flame.env.bak
    msg_ok "Restored Data"

    msg_info "Rebuilding Application"
    cd /opt/flame
    mkdir -p data public
    $STD npm install --production
    cd /opt/flame/client
    $STD npm install --production
    $STD npm run build
    cd /opt/flame
    cp -r client/build/. public/
    msg_ok "Rebuilt Application"

    msg_info "Starting Service"
    systemctl start flame
    msg_ok "Started Service"
    msg_ok "Updated successfully!"
  fi
  exit
}

function install_script() {
  color
  verb_ip6
  catch_errors
  setting_up_container
  network_check
  update_os

  msg_info "Installing Dependencies"
  $STD apt-get install -y \
    build-essential \
    python3
  msg_ok "Installed Dependencies"

  NODE_VERSION="22" setup_nodejs

  fetch_and_deploy_gh_release "flame" "pawelmalak/flame" "tarball"

  msg_info "Setting up Flame"
  cd /opt/flame
  mkdir -p data public
  $STD npm install --production
  cd /opt/flame/client
  $STD npm install --production
  $STD npm run build
  cd /opt/flame
  cp -r client/build/. public/
  FLAME_VERSION=$(cat ~/.flame)
  cat <<EOF >/opt/flame/.env
NODE_ENV=production
VERSION=${FLAME_VERSION}
PASSWORD=
EOF
  msg_ok "Set up Flame"

  msg_info "Creating Service"
  cat <<EOF >/etc/systemd/system/flame.service
[Unit]
Description=Flame Startpage
After=network.target

[Service]
Type=simple
User=root
WorkingDirectory=/opt/flame
ExecStart=/usr/bin/node server.js
Restart=on-failure
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF
  systemctl enable -q --now flame
  msg_ok "Created Service"
}

function post_install_script() {
  msg_ok "Completed Successfully!\n"
  echo -e "${CREATING}${GN}${APP} setup has been successfully initialized!${CL}"
  echo -e "${INFO}${YW} Access it using the following URL:${CL}"
  echo -e "${TAB}${GATEWAY}${BGN}http://${IP}:5005${CL}"
}

source <(curl -fsSL "$REPO_BASE/misc/bootstrap/lxc")
