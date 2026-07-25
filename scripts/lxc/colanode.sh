#!/usr/bin/env bash
REPO_BASE="${REPO_BASE:-https://raw.githubusercontent.com/scripts-underground/proxmox/main}"

# Copyright (c) 2021-2026 community-scripts ORG
# Author: MickLesk (CanbiZ)
# License: MIT | https://raw.githubusercontent.com/scripts-underground/proxmox/main/LICENSE
# Source: https://colanode.com/

# shellcheck disable=SC2034
# Read by the framework - shellcheck cannot see the caller
APP="Colanode"
var_tags="${var_tags:-collaboration;notes;chat}"
var_cpu="${var_cpu:-4}"
var_ram="${var_ram:-4096}"
var_disk="${var_disk:-16}"
var_os="${var_os:-debian}"
var_version="${var_version:-13}"
var_arm64="${var_arm64:-no}"
var_unprivileged="${var_unprivileged:-1}"

function install_script() {
  msg_info "Installing Dependencies"
  $STD apt install -y \
    build-essential \
    redis-server \
    nginx
  msg_ok "Installed Dependencies"

  PG_VERSION="17" PG_MODULES="pgvector" setup_postgresql
  PG_DB_NAME="colanode_db" PG_DB_USER="colanode" PG_DB_EXTENSIONS="vector" setup_postgresql_db
  NODE_VERSION="22" setup_nodejs

  fetch_and_deploy_gh_release "colanode" "colanode/colanode" "tarball"

  msg_info "Building Application"
  cd /opt/colanode || exit
  export NODE_OPTIONS="--max-old-space-size=4096"
  $STD npm install
  $STD npm run build -w @colanode/core
  $STD npm run build -w @colanode/crdt
  $STD npm run build -w @colanode/server
  $STD npm run build -w @colanode/client
  $STD npm run build -w @colanode/ui
  $STD npm run build -w @colanode/web
  $STD npm prune --production
  unset NODE_OPTIONS
  msg_ok "Built Application"

  msg_info "Configuring Application"
  mkdir -p /var/lib/colanode/storage /var/www/colanode
  cp -r /opt/colanode/apps/web/dist/. /var/www/colanode/
  cat << EOF > /opt/colanode/.env
POSTGRES_URL=postgresql://${PG_DB_USER}:${PG_DB_PASS}@127.0.0.1:5432/${PG_DB_NAME}
REDIS_URL=redis://127.0.0.1:6379
NODE_ENV=production
EOF
  msg_ok "Configured Application"

  msg_info "Configuring Nginx"
  create_self_signed_cert "colanode"
  cp /etc/ssl/colanode/colanode.crt /var/www/colanode/colanode.crt
  cat << EOF > /etc/nginx/sites-available/colanode
server {
    listen 4000 ssl;
    server_name _;
    root /var/www/colanode;
    index index.html;

    ssl_certificate /etc/ssl/colanode/colanode.crt;
    ssl_certificate_key /etc/ssl/colanode/colanode.key;

    add_header Cross-Origin-Opener-Policy "same-origin" always;
    add_header Cross-Origin-Embedder-Policy "require-corp" always;

    location ~ ^/(config|client)(/.*)?$ {
        proxy_pass http://127.0.0.1:3000;
        proxy_http_version 1.1;
        proxy_set_header Upgrade \$http_upgrade;
        proxy_set_header Connection "upgrade";
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
    }

    location = /colanode.crt {
        default_type application/x-x509-ca-cert;
    }

    location / {
        try_files \$uri \$uri/ /index.html;
    }
}
EOF
  ln -sf /etc/nginx/sites-available/colanode /etc/nginx/sites-enabled/colanode
  rm -f /etc/nginx/sites-enabled/default
  systemctl reload nginx
  msg_ok "Configured Nginx"

  msg_info "Creating Service"
  cat << EOF > /etc/systemd/system/colanode-server.service
[Unit]
Description=Colanode Server
After=network.target postgresql.service redis-server.service
Requires=postgresql.service redis-server.service

[Service]
Type=simple
User=root
WorkingDirectory=/opt/colanode
EnvironmentFile=/opt/colanode/.env
ExecStart=/usr/bin/node apps/server/dist/index.js
Restart=on-failure
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF
  systemctl enable -q --now colanode-server
  msg_ok "Created Service"
}

function post_install_script() {
  msg_ok "Completed Successfully!\n"
  echo -e "${CREATING}${GN}${APP} setup has been successfully initialized!${CL}"
  echo -e "${INFO}${YW} Access it using the following URLs:${CL}"
  echo -e "${TAB}${GATEWAY}${BGN}https://${IP}:4000${CL} (Web UI)"
  echo -e "${INFO}${YW} Before using: import the self-signed cert into your browser:${CL}"
  echo -e "${TAB}${GATEWAY}${BGN}https://${IP}:4000/colanode.crt${CL}"
  echo -e "${INFO}${YW} Server URL to use inside the app:${CL}"
  echo -e "${TAB}${GATEWAY}${BGN}https://${IP}:4000/config${CL}"
}

function update_script() {
  header_info
  check_container_storage
  check_container_resources

  if [[ ! -d /opt/colanode ]]; then
    msg_error "No ${APP} Installation Found!"
    exit
  fi

  if check_for_gh_release "colanode" "colanode/colanode"; then
    msg_info "Stopping Services"
    systemctl stop colanode-server
    msg_ok "Stopped Services"

    msg_info "Backing up Data"
    cp /opt/colanode/.env /opt/colanode.env.bak
    msg_ok "Backed up Data"

    CLEAN_INSTALL=1 fetch_and_deploy_gh_release "colanode" "colanode/colanode" "tarball"

    msg_info "Rebuilding Application"
    cd /opt/colanode || exit
    export NODE_OPTIONS="--max-old-space-size=4096"
    $STD npm install
    $STD npm run build -w @colanode/core
    $STD npm run build -w @colanode/crdt
    $STD npm run build -w @colanode/server
    $STD npm run build -w @colanode/client
    $STD npm run build -w @colanode/ui
    $STD npm run build -w @colanode/web
    cp -r /opt/colanode/apps/web/dist/. /var/www/colanode/
    $STD npm prune --production
    unset NODE_OPTIONS
    msg_ok "Rebuilt Application"

    msg_info "Restoring Data"
    cp /opt/colanode.env.bak /opt/colanode/.env
    rm -f /opt/colanode.env.bak
    msg_ok "Restored Data"

    msg_info "Starting Services"
    systemctl start colanode-server
    msg_ok "Started Services"
    msg_ok "Updated successfully!"
  fi
  exit
}

# framework bootstrap
# shellcheck disable=SC1090
# Dynamic URL resolved at runtime - shellcheck cannot follow
source <(curl -fsSL "$REPO_BASE/misc/bootstrap/lxc")
