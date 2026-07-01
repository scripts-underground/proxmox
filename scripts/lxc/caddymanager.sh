#!/usr/bin/env bash
REPO_BASE="${REPO_BASE:-https://raw.githubusercontent.com/scripts-underground/proxmox/main}"

# Copyright (c) 2021-2026 community-scripts ORG
# Author: Slaviša Arežina (tremor021)
# License: MIT | https://raw.githubusercontent.com/scripts-underground/proxmox/main/LICENSE
# Source: https://github.com/caddymanager/caddymanager

# shellcheck disable=SC2034
# Read by the framework - shellcheck cannot see the caller
APP="CaddyManager"
var_tags="${var_tags:-}"
var_cpu="${var_cpu:-1}"
var_ram="${var_ram:-1024}"
var_disk="${var_disk:-4}"
var_os="${var_os:-debian}"
var_version="${var_version:-13}"
var_arm64="${var_arm64:-no}"
var_unprivileged="${var_unprivileged:-1}"

function install_script() {
  msg_info "Installing Dependencies"
  $STD apt install -y caddy
  msg_ok "Installed Dependencies"

  NODE_VERSION=22 setup_nodejs
  fetch_and_deploy_gh_release "caddymanager" "caddymanager/caddymanager" "tarball"
  systemctl stop caddy
  systemctl disable -q caddy

  msg_info "Configuring CaddyManager"
  SECRET_JWT=$(openssl rand -hex 32)
  cd /opt/caddymanager/backend || exit
  $STD npm install
  cd /opt/caddymanager/frontend || exit
  $STD npm install
  $STD npm run build

  cat << EOF > /opt/caddymanager/caddymanager.env
PORT=3000
APP_NAME=Caddy Manager
DB_ENGINE=sqlite
SQLITE_DB_PATH=/opt/caddymanager/caddymanager.sqlite
CORS_ORIGIN=${LOCAL_IP}:80
LOG_LEVEL=debug
CADDY_SANDBOX_URL=http://localhost:2019
PING_INTERVAL=30000
PING_TIMEOUT=2000
AUDIT_LOG_MAX_SIZE_MB=100
AUDIT_LOG_RETENTION_DAYS=90
METRICS_HISTORY_MAX=1000
JWT_SECRET=${SECRET_JWT}
JWT_EXPIRATION=24h
EOF
  sed -i 's|/usr/share/caddy|/opt/caddymanager/frontend/dist|g' /opt/caddymanager/frontend/Caddyfile
  msg_ok "Configured CaddyManager"

  msg_info "Creating services"
  cat << EOF > /etc/systemd/system/caddymanager-backend.service
[Unit]
Description=Caddymanager Backend Service
After=network.target

[Service]
WorkingDirectory=/opt/caddymanager/backend
ExecStart=/usr/bin/npm start
Restart=always
EnvironmentFile=/opt/caddymanager/caddymanager.env

[Install]
WantedBy=multi-user.target
EOF

  cat << EOF > /etc/systemd/system/caddymanager-frontend.service
[Unit]
Description=Caddymanager Frontend Service
After=network.target caddymanager-backend.service
Requires=caddymanager-backend.service

[Service]
WorkingDirectory=/opt/caddymanager/frontend
ExecStart=/usr/bin/caddy run --config Caddyfile
Restart=always
EnvironmentFile=/opt/caddymanager/caddymanager.env

[Install]
WantedBy=multi-user.target
EOF
  systemctl enable -q --now caddymanager-backend
  systemctl enable -q --now caddymanager-frontend
  msg_ok "Created services"
}

function post_install_script() {
  msg_ok "Completed Successfully!\n"
  echo -e "${CREATING}${GN}${APP} setup has been successfully initialized!${CL}"
  echo -e "${INFO}${YW} Access it using the following URL:${CL}"
  echo -e "${TAB}${GATEWAY}${BGN}http://${IP}${CL}"
}

function update_script() {
  header_info
  check_container_storage
  check_container_resources
  if [[ ! -d /opt/caddymanager ]]; then
    msg_error "No ${APP} Installation Found!"
    exit
  fi

  if check_for_gh_release "caddymanager" "caddymanager/caddymanager"; then
    msg_info "Stopping Service"
    systemctl stop caddymanager-backend
    systemctl stop caddymanager-frontend
    msg_ok "Stopped Service"

    msg_info "Backing up configuration"
    cp /opt/caddymanager/caddymanager.env /opt/
    cp /opt/caddymanager/caddymanager.sqlite /opt/
    cp /opt/caddymanager/frontend/Caddyfile /opt/
    msg_ok "Backed up configuration"

    CLEAN_INSTALL=1 fetch_and_deploy_gh_release "caddymanager" "caddymanager/caddymanager" "tarball"

    msg_info "Installing CaddyManager"
    cd /opt/caddymanager/backend || exit
    $STD npm install
    cd /opt/caddymanager/frontend || exit
    $STD npm install
    $STD npm run build
    msg_ok "Installed CaddyManager"

    msg_info "Restoring configuration"
    mv /opt/caddymanager.env /opt/caddymanager/
    mv /opt/caddymanager.sqlite /opt/caddymanager/
    mv -f /opt/Caddyfile /opt/caddymanager/frontend/
    msg_ok "Restored configuration"

    msg_info "Starting Service"
    systemctl start caddymanager-backend
    systemctl start caddymanager-frontend
    msg_ok "Started Service"
    msg_ok "Updated successfully!"
  fi
  cleanup_lxc
  exit
}

# framework bootstrap
# shellcheck disable=SC1090
# Dynamic URL resolved at runtime - shellcheck cannot follow
source <(curl -fsSL "$REPO_BASE/misc/bootstrap/lxc")

