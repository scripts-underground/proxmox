#!/usr/bin/env bash
REPO_BASE="${REPO_BASE:-https://raw.githubusercontent.com/scripts-underground/proxmox/main}"

# Copyright (c) 2021-2026 community-scripts ORG
# Author: MickLesk (CanbiZ)
# License: MIT | https://raw.githubusercontent.com/scripts-underground/proxmox/main/LICENSE
# Source: https://github.com/ZimengXiong/ExcaliDash

# shellcheck disable=SC2034
# Read by the framework - shellcheck cannot see the caller
APP="ExcaliDash"
var_tags="${var_tags:-documents;drawing;collaboration}"
var_cpu="${var_cpu:-2}"
var_ram="${var_ram:-2048}"
var_disk="${var_disk:-8}"
var_os="${var_os:-debian}"
var_version="${var_version:-13}"
var_arm64="${var_arm64:-no}"
var_unprivileged="${var_unprivileged:-1}"

function install_script() {
  msg_info "Installing Dependencies"
  $STD apt install -y \
    build-essential \
    make \
    nginx
  msg_ok "Installed Dependencies"

  NODE_VERSION="20" setup_nodejs

  fetch_and_deploy_gh_release "excalidash" "ZimengXiong/ExcaliDash" "tarball"

  msg_info "Building Backend"
  cd /opt/excalidash/backend || exit
  $STD npm ci
  $STD npx prisma generate
  $STD npx tsc
  msg_ok "Built Backend"

  msg_info "Building Frontend"
  cd /opt/excalidash/frontend || exit
  $STD npm ci
  $STD npm run build
  msg_ok "Built Frontend"

  msg_info "Configuring Application"
  mkdir -p /opt/excalidash_data
  mkdir -p /var/www/excalidash
  cp -r /opt/excalidash/frontend/dist/. /var/www/excalidash/
  cat << EOF > /opt/excalidash_data/.env
DATABASE_URL=file:/opt/excalidash_data/database.db
PORT=8000
NODE_ENV=production
FRONTEND_URL=http://${LOCAL_IP}
AUTH_MODE=local
TRUST_PROXY=false
RUN_MIGRATIONS=false
JWT_SECRET=$(openssl rand -hex 32)
CSRF_SECRET=$(openssl rand -base64 32)
EOF
  ln -sf /opt/excalidash_data/.env /opt/excalidash/backend/.env
  cd /opt/excalidash/backend || exit
  set -a && source /opt/excalidash_data/.env && set +a
  $STD npx prisma migrate deploy
  msg_ok "Configured Application"

  msg_info "Configuring Nginx"
  cat << EOF > /etc/nginx/sites-available/excalidash
server {
    listen 80;
    server_name _;
    root /var/www/excalidash;
    index index.html;
    client_max_body_size 50M;

    location /api/ {
        proxy_pass http://127.0.0.1:8000/;
        proxy_http_version 1.1;
        proxy_set_header Upgrade \$http_upgrade;
        proxy_set_header Connection "upgrade";
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
        proxy_read_timeout 300s;
        proxy_send_timeout 300s;
    }

    location /socket.io/ {
        proxy_pass http://127.0.0.1:8000/socket.io/;
        proxy_http_version 1.1;
        proxy_set_header Upgrade \$http_upgrade;
        proxy_set_header Connection "upgrade";
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
        proxy_read_timeout 3600s;
        proxy_send_timeout 3600s;
    }

    location / {
        try_files \$uri \$uri/ /index.html;
    }
}
EOF
  ln -sf /etc/nginx/sites-available/excalidash /etc/nginx/sites-enabled/excalidash
  rm -f /etc/nginx/sites-enabled/default
  systemctl reload nginx
  msg_ok "Configured Nginx"

  msg_info "Creating Service"
  cat << EOF > /etc/systemd/system/excalidash.service
[Unit]
Description=ExcaliDash Service
After=network.target

[Service]
Type=simple
User=root
WorkingDirectory=/opt/excalidash/backend
EnvironmentFile=/opt/excalidash/backend/.env
ExecStart=/usr/bin/node dist/index.js
Restart=on-failure
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF
  systemctl enable -q --now excalidash
  msg_ok "Created Service"
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

  if [[ ! -d /opt/excalidash ]]; then
    msg_error "No ${APP} Installation Found!"
    exit
  fi

  if check_for_gh_release "excalidash" "ZimengXiong/ExcaliDash"; then
    msg_info "Stopping Service"
    systemctl stop excalidash
    msg_ok "Stopped Service"

    CLEAN_INSTALL=1 fetch_and_deploy_gh_release "excalidash" "ZimengXiong/ExcaliDash" "tarball"

    ln -sf /opt/excalidash_data/.env /opt/excalidash/backend/.env

    msg_info "Rebuilding Application"
    cd /opt/excalidash/backend || exit
    $STD npm ci
    $STD npx prisma generate
    $STD npx tsc
    cd /opt/excalidash/frontend || exit
    $STD npm ci
    $STD npm run build
    cp -r /opt/excalidash/frontend/dist/. /var/www/excalidash/
    msg_ok "Rebuilt Application"

    msg_info "Running Migrations"
    cd /opt/excalidash/backend || exit
    set -a && source /opt/excalidash_data/.env && set +a
    $STD npx prisma migrate deploy
    msg_ok "Ran Migrations"

    msg_info "Starting Service"
    systemctl start excalidash
    msg_ok "Started Service"
    msg_ok "Updated successfully!"
  fi
  exit
}

# framework bootstrap
# shellcheck disable=SC1090
# Dynamic URL resolved at runtime - shellcheck cannot follow
source <(curl -fsSL "$REPO_BASE/misc/bootstrap/lxc")
