#!/usr/bin/env bash
REPO_BASE="${REPO_BASE:-https://raw.githubusercontent.com/scripts-underground/proxmox/main}"

# Sourced by lxc.bootstrap — never executed directly
# Copyright (c) 2021-2026 community-scripts ORG
# Author: HydroshieldMKII
# License: MIT | https://raw.githubusercontent.com/scripts-underground/proxmox/main/LICENSE
# Source: https://github.com/HydroshieldMKII/Guardian

# shellcheck disable=SC2034
APP="Guardian"
var_tags="${var_tags:-media;monitoring}"
var_cpu="${var_cpu:-2}"
var_ram="${var_ram:-2048}"
var_disk="${var_disk:-6}"
var_os="${var_os:-debian}"
var_version="${var_version:-13}"
var_arm64="${var_arm64:-yes}"
var_unprivileged="${var_unprivileged:-1}"

function install_script() {
  msg_info "Installing Dependencies"
  $STD apt install -y sqlite3
  msg_ok "Installed Dependencies"

  NODE_VERSION="24" setup_nodejs
  fetch_and_deploy_gh_release "guardian" "HydroshieldMKII/Guardian" "tarball" "latest" "/opt/guardian"

  msg_info "Configuring Guardian"
  cd /opt/guardian/backend || exit
  $STD npm ci
  $STD npm run build
  cd /opt/guardian/frontend || exit
  $STD npm ci
  export DEPLOYMENT_MODE=standalone
  $STD npm run build
  msg_ok "Configured Guardian"

  msg_info "Creating Service"
  cat << EOF > /etc/systemd/system/guardian-backend.service
[Unit]
Description=Guardian Backend
After=network.target

[Service]
WorkingDirectory=/opt/guardian/backend
ExecStart=/usr/bin/node dist/main.js
Restart=always
RestartSec=3
[Install]
WantedBy=multi-user.target
EOF

  cat << EOF > /etc/systemd/system/guardian-frontend.service
[Unit]
Description=Guardian Frontend
After=guardian-backend.service network.target
Wants=guardian-backend.service

[Service]
WorkingDirectory=/opt/guardian/frontend
Environment=DEPLOYMENT_MODE=standalone
ExecStart=/usr/bin/npm run start
Restart=always
RestartSec=3
[Install]
WantedBy=multi-user.target
EOF

  systemctl enable -q --now guardian-backend
  systemctl enable -q --now guardian-frontend
  msg_ok "Created Service"
}

function post_install_script() {
  msg_ok "Completed Successfully!\n"
  echo -e "${CREATING}${GN}${APP} setup has been successfully initialized!${CL}"
  echo -e "${INFO}${YW}Access it using the following URL:${CL}"
  echo -e "${TAB}${GATEWAY}${BGN}http://${IP}:3000${CL}"
}

function update_script() {
  header_info
  check_container_storage
  check_container_resources

  if [[ ! -d "/opt/guardian" ]]; then
    msg_error "No ${APP} Installation Found!"
    exit
  fi

  if check_for_gh_release "guardian" "HydroshieldMKII/Guardian"; then
    msg_info "Stopping Services"
    systemctl stop guardian-backend guardian-frontend
    msg_ok "Stopped Services"

    if [[ -f "/opt/guardian/backend/plex-guard.db" ]]; then
      msg_info "Backing up Database"
      cp "/opt/guardian/backend/plex-guard.db" "/tmp/plex-guard.db.backup"
      msg_ok "Backed up Database"
    fi

    [[ -f "/opt/guardian/.env" ]] && cp "/opt/guardian/.env" "/opt"
    CLEAN_INSTALL=1 fetch_and_deploy_gh_release "guardian" "HydroshieldMKII/Guardian" "tarball" "latest" "/opt/guardian"
    [[ -f "/opt/.env" ]] && mv "/opt/.env" "/opt/guardian"

    if [[ -f "/tmp/plex-guard.db.backup" ]]; then
      msg_info "Restoring Database"
      cp "/tmp/plex-guard.db.backup" "/opt/guardian/backend/plex-guard.db"
      rm "/tmp/plex-guard.db.backup"
      msg_ok "Restored Database"
    fi

    msg_info "Updating Guardian"
    cd /opt/guardian/backend || exit
    $STD npm ci
    $STD npm run build

    cd /opt/guardian/frontend || exit
    $STD npm ci
    export DEPLOYMENT_MODE=standalone
    $STD npm run build
    msg_ok "Updated Guardian"

    msg_info "Starting Services"
    systemctl start guardian-backend guardian-frontend
    msg_ok "Started Services"
    msg_ok "Updated successfully!"
  fi
  exit
}

# shellcheck disable=SC1090
source <(curl -fsSL "$REPO_BASE/misc/bootstrap/lxc")
