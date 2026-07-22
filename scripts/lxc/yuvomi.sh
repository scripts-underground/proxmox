#!/usr/bin/env bash
REPO_BASE="${REPO_BASE:-https://raw.githubusercontent.com/scripts-underground/proxmox/main}"

# Sourced by lxc.bootstrap — never executed directly
# Copyright (c) 2021-2026 community-scripts ORG
# Author: MickLesk (CanbiZ)
# License: MIT | https://raw.githubusercontent.com/scripts-underground/proxmox/main/LICENSE
# Source: https://github.com/ulsklyc/yuvomi

# shellcheck disable=SC2034
# Read by the framework - shellcheck cannot see the caller
APP="Yuvomi"
var_tags="${var_tags:-family;planner;calendar}"
var_cpu="${var_cpu:-2}"
var_ram="${var_ram:-1024}"
var_disk="${var_disk:-8}"
var_os="${var_os:-debian}"
var_version="${var_version:-13}"
var_arm64="${var_arm64:-yes}"
var_unprivileged="${var_unprivileged:-1}"

function install_script() {
  msg_info "Installing Dependencies"
  $STD apt install -y \
    python3 \
    make \
    g++ \
    libsqlcipher-dev
  msg_ok "Installed Dependencies"

  NODE_VERSION="22" setup_nodejs

  fetch_and_deploy_gh_release "yuvomi" "ulsklyc/yuvomi" "tarball"

  msg_info "Installing Node.js Dependencies"
  cd /opt/yuvomi || exit
  $STD npm ci --omit=dev
  msg_ok "Installed Node.js Dependencies"

  msg_info "Configuring Yuvomi"
  mkdir -p /opt/yuvomi/data /opt/yuvomi/backups
  SESSION_SECRET=$(openssl rand -hex 32)
  DB_ENCRYPT_KEY=$(openssl rand -hex 32)
  cat << EOF > /opt/yuvomi/.env
PORT=3000
NODE_ENV=production
DB_PATH=/opt/yuvomi/data/yuvomi.db
DB_ENCRYPTION_KEY=${DB_ENCRYPT_KEY}
SESSION_SECRET=${SESSION_SECRET}
RATE_LIMIT_WINDOW_MS=60000
RATE_LIMIT_MAX_ATTEMPTS=5
RATE_LIMIT_BLOCK_DURATION_MS=900000
EOF
  msg_ok "Configured Yuvomi"

  msg_info "Creating Service"
  cat << EOF > /etc/systemd/system/yuvomi.service
[Unit]
Description=Yuvomi Family Planner
After=network.target

[Service]
Type=simple
User=root
WorkingDirectory=/opt/yuvomi
EnvironmentFile=/opt/yuvomi/.env
ExecStart=/usr/bin/node server/index.js
Restart=on-failure
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF
  systemctl enable -q --now yuvomi
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

  if [[ ! -d /opt/yuvomi ]]; then
    msg_error "No ${APP} Installation Found!"
    exit
  fi

  if check_for_gh_release "yuvomi" "ulsklyc/yuvomi"; then
    msg_info "Stopping Service"
    systemctl stop yuvomi
    msg_ok "Stopped Service"

    create_backup /opt/yuvomi/data /opt/yuvomi/.env

    CLEAN_INSTALL=1 fetch_and_deploy_gh_release "yuvomi" "ulsklyc/yuvomi" "tarball"

    msg_info "Installing Node.js Dependencies"
    cd /opt/yuvomi || exit
    $STD npm ci --omit=dev
    msg_ok "Installed Node.js Dependencies"

    restore_backup

    msg_info "Starting Service"
    systemctl start yuvomi
    msg_ok "Started Service"
    msg_ok "Updated successfully!"
  fi
  exit
}

# framework bootstrap
# shellcheck disable=SC1090
# Dynamic URL resolved at runtime - shellcheck cannot follow
source <(curl -fsSL "$REPO_BASE/misc/bootstrap/lxc")
