#!/usr/bin/env bash
REPO_BASE="${REPO_BASE:-https://raw.githubusercontent.com/scripts-underground/proxmox/main}"

# Sourced by lxc.bootstrap — never executed directly
# Copyright (c) 2021-2026 community-scripts ORG
# Author: Slaviša Arežina (tremor021)
# License: MIT | https://raw.githubusercontent.com/scripts-underground/proxmox/main/LICENSE
# Source: https://github.com/jordan-dalby/ByteStash

# shellcheck disable=SC2034
# Read by the framework - shellcheck cannot see the caller
APP="ByteStash"
var_tags="${var_tags:-code}"
var_disk="${var_disk:-4}"
var_cpu="${var_cpu:-1}"
var_ram="${var_ram:-1024}"
var_os="${var_os:-debian}"
var_version="${var_version:-13}"
var_arm64="${var_arm64:-yes}"
var_unprivileged="${var_unprivileged:-1}"

function install_script() {
  NODE_VERSION="22" setup_nodejs

  fetch_and_deploy_gh_release "bytestash" "jordan-dalby/ByteStash" "tarball"

  msg_info "Installing ByteStash"
  JWT_SECRET=$(openssl rand -base64 32 | tr -d '/+=')
  cd /opt/bytestash/server || exit
  $STD npm install
  cd /opt/bytestash/client || exit
  $STD npm install
  msg_ok "Installed ByteStash"

  read -rp "${TAB3}Do you want to allow registration of multiple accounts? [y/n]: " allowreg

  msg_info "Creating Services"
  cat << EOF > /etc/systemd/system/bytestash-backend.service
[Unit]
Description=ByteStash Backend Service
After=network.target

[Service]
WorkingDirectory=/opt/bytestash/server
ExecStart=/usr/bin/node src/app.js
Restart=always
Environment=JWT_SECRET=$JWT_SECRET

[Install]
WantedBy=multi-user.target
EOF

  if [[ "$allowreg" =~ ^[Yy]$ ]]; then
    sed -i '8i\Environment=ALLOW_NEW_ACCOUNTS=true' /etc/systemd/system/bytestash-backend.service
  fi

  cat << EOF > /etc/systemd/system/bytestash-frontend.service
[Unit]
Description=ByteStash Frontend Service
After=network.target bytestash-backend.service

[Service]
WorkingDirectory=/opt/bytestash/client
ExecStart=/usr/bin/npx vite --host
Restart=always

[Install]
WantedBy=multi-user.target
EOF

  systemctl enable -q --now bytestash-backend
  systemctl enable -q --now bytestash-frontend
  msg_ok "Created Services"
}

function post_install_script() {
  msg_ok "Completed Successfully!\n"
  echo -e "${CREATING}${GN}${APP} setup has been successfully initialized!${CL}"
  echo -e "${INFO}${YW}Access it using the following URL:${CL}"
  echo -e "${GATEWAY}${BGN}http://${IP}:3000${CL}"
}

function update_script() {
  header_info
  check_container_storage
  check_container_resources
  if [[ ! -d /opt/bytestash ]]; then
    msg_error "No ${APP} Installation Found!"
    exit
  fi

  if check_for_gh_release "bytestash" "jordan-dalby/ByteStash"; then
    msg_info "Stopping Services"
    systemctl stop bytestash-backend bytestash-frontend
    msg_ok "Services Stopped"

    [[ -d /opt/bytestash/data ]] && create_backup /opt/bytestash/data
    [[ -d /opt/data ]] && create_backup /opt/data
    CLEAN_INSTALL=1 fetch_and_deploy_gh_release "bytestash" "jordan-dalby/ByteStash" "tarball"
    restore_backup

    msg_info "Configuring ByteStash"
    cd /opt/bytestash/server || exit
    $STD npm install
    cd /opt/bytestash/client || exit
    $STD npm install
    msg_ok "Updated ByteStash"

    msg_info "Starting Services"
    systemctl start bytestash-backend bytestash-frontend
    msg_ok "Started Services"

    msg_ok "Updated successfully!"
  fi
  exit
}

# framework bootstrap
# shellcheck disable=SC1090
# Dynamic URL resolved at runtime - shellcheck cannot follow
source <(curl -fsSL "$REPO_BASE/misc/bootstrap/lxc")
