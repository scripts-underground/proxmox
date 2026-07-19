#!/usr/bin/env bash
REPO_BASE="${REPO_BASE:-https://raw.githubusercontent.com/scripts-underground/proxmox/main}"

# Sourced by lxc.bootstrap — never executed directly
# Copyright (c) 2021-2026 community-scripts ORG
# Author: MickLesk (CanbiZ)
# License: MIT | https://raw.githubusercontent.com/scripts-underground/proxmox/main/LICENSE
# Source: https://github.com/bluewave-labs/Checkmate

# shellcheck disable=SC2034
# Read by the framework - shellcheck cannot see the caller
APP="Checkmate"
var_tags="${var_tags:-monitoring;uptime}"
var_cpu="${var_cpu:-2}"
var_ram="${var_ram:-4096}"
var_disk="${var_disk:-10}"
var_os="${var_os:-debian}"
var_version="${var_version:-13}"
var_arm64="${var_arm64:-no}"
var_unprivileged="${var_unprivileged:-1}"

function install_script() {
  msg_info "Installing Dependencies"
  $STD apt install -y \
    build-essential \
    openssl \
    nginx
  msg_ok "Installed Dependencies"

  MONGO_VERSION="8.0" setup_mongodb
  NODE_VERSION="22" setup_nodejs
  fetch_and_deploy_gh_release "checkmate" "bluewave-labs/Checkmate" "tarball"

  msg_info "Configuring Checkmate"
  JWT_SECRET="$(openssl rand -hex 32)"
  cat << EOF > /opt/checkmate/server/.env
CLIENT_HOST="http://${LOCAL_IP}"
JWT_SECRET="${JWT_SECRET}"
DB_CONNECTION_STRING="mongodb://localhost:27017/checkmate_db"
TOKEN_TTL="99d"
ORIGIN="${LOCAL_IP}"
LOG_LEVEL="info"
SERVER_HOST=0.0.0.0
SERVER_PORT=52345
EOF
  cat << EOF > /opt/checkmate/client/.env.local
VITE_APP_API_BASE_URL="/api/v1"
UPTIME_APP_API_BASE_URL="/api/v1"
VITE_APP_LOG_LEVEL="warn"
EOF
  msg_ok "Configured Checkmate"

  msg_info "Installing Checkmate Server"
  cd /opt/checkmate/server || exit
  $STD npm install
  $STD npm run build
  msg_ok "Installed Checkmate Server"

  msg_info "Installing Checkmate Client"
  cd /opt/checkmate/client || exit
  $STD npm install
  VITE_APP_API_BASE_URL="/api/v1" UPTIME_APP_API_BASE_URL="/api/v1" VITE_APP_LOG_LEVEL="warn" $STD npm run build
  msg_ok "Installed Checkmate Client"

  msg_info "Creating Services"
  cat << EOF > /etc/systemd/system/checkmate-server.service
[Unit]
Description=Checkmate Server
After=network.target mongod.service

[Service]
Type=simple
User=root
WorkingDirectory=/opt/checkmate/server
EnvironmentFile=/opt/checkmate/server/.env
ExecStart=/usr/bin/npm start
Restart=on-failure
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF
  cat << EOF > /etc/systemd/system/checkmate-client.service
[Unit]
Description=Checkmate Client
After=network.target

[Service]
Type=simple
User=root
WorkingDirectory=/opt/checkmate/client
ExecStart=/usr/bin/npm run preview -- --host 127.0.0.1 --port 5173
Restart=on-failure
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF
  $STD systemctl enable -q --now checkmate-server
  $STD systemctl enable -q --now checkmate-client
  msg_ok "Created Services"

  msg_info "Configuring Nginx Reverse Proxy"
  cat << 'EOF' > /etc/nginx/sites-available/checkmate
server {
  listen 80 default_server;
  server_name _;

  client_max_body_size 100M;

  # Client UI
  location / {
    proxy_pass http://127.0.0.1:5173;
    proxy_http_version 1.1;
    proxy_set_header Upgrade $http_upgrade;
    proxy_set_header Connection "upgrade";
    proxy_set_header Host $host;
    proxy_set_header X-Real-IP $remote_addr;
    proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
  }

  # API Server
  location /api/v1/ {
    proxy_pass http://127.0.0.1:52345/api/v1/;
    proxy_http_version 1.1;
    proxy_set_header Host $host;
    proxy_set_header X-Real-IP $remote_addr;
    proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
  }
}
EOF
  ln -sf /etc/nginx/sites-available/checkmate /etc/nginx/sites-enabled/checkmate
  rm -f /etc/nginx/sites-enabled/default
  $STD systemctl reload nginx
  msg_ok "Configured Nginx Reverse Proxy"
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

  if [[ ! -d /opt/checkmate ]]; then
    msg_error "No ${APP} Installation Found!"
    exit
  fi

  if check_for_gh_release "checkmate" "bluewave-labs/Checkmate"; then
    msg_info "Stopping Services"
    systemctl stop checkmate-server checkmate-client nginx
    msg_ok "Stopped Services"

    create_backup /opt/checkmate/server/.env \
      /opt/checkmate/client/.env.local

    CLEAN_INSTALL=1 fetch_and_deploy_gh_release "checkmate" "bluewave-labs/Checkmate" "tarball"

    msg_info "Updating Checkmate Server"
    cd /opt/checkmate/server || exit
    $STD npm install
    if [ -f package.json ]; then
      grep -q '"build"' package.json && $STD npm run build || true
    fi
    msg_ok "Updated Checkmate Server"

    msg_info "Updating Checkmate Client"
    cd /opt/checkmate/client || exit
    $STD npm install
    VITE_APP_API_BASE_URL="/api/v1" UPTIME_APP_API_BASE_URL="/api/v1" VITE_APP_LOG_LEVEL="warn" $STD npm run build
    msg_ok "Updated Checkmate Client"

    restore_backup

    msg_info "Starting Services"
    systemctl start checkmate-server checkmate-client nginx
    msg_ok "Started Services"
    msg_ok "Updated successfully!"
  fi
  exit
}

# framework bootstrap
# shellcheck disable=SC1090
# Dynamic URL resolved at runtime - shellcheck cannot follow
source <(curl -fsSL "$REPO_BASE/misc/bootstrap/lxc")
