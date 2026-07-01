#!/usr/bin/env bash
# shellcheck disable=SC2034,SC2155
REPO_BASE="${REPO_BASE:-https://raw.githubusercontent.com/scripts-underground/proxmox/main}"

# Copyright (c) 2021-2026 community-scripts ORG
# Author: MickLesk (CanbiZ)
# License: MIT | https://raw.githubusercontent.com/scripts-underground/proxmox/main/LICENSE
# Source: https://github.com/toeverything/AFFiNE


# Read by the framework - shellcheck cannot see the caller\n# shellcheck disable=SC2034\nAPP="AFFiNE"
var_tags="${var_tags:-knowledge;notes;workspace}"
var_cpu="${var_cpu:-4}"
var_ram="${var_ram:-8192}"
var_disk="${var_disk:-20}"
var_os="${var_os:-debian}"
var_version="${var_version:-13}"
var_arm64="${var_arm64:-no}"
var_unprivileged="${var_unprivileged:-1}"

function install_script() {
  msg_info "Installing Dependencies"
  $STD apt install -y \
    build-essential \
    git \
    pkg-config \
    openssl \
    libssl-dev \
    libjemalloc2 \
    redis-server \
    nginx
  msg_ok "Installed Dependencies"

  PG_VERSION="16" PG_MODULES="pgvector" setup_postgresql
  PG_DB_NAME="affine" PG_DB_USER="affine" setup_postgresql_db
  NODE_VERSION="22" setup_nodejs
  setup_rust

  fetch_and_deploy_gh_release "affine_app" "toeverything/AFFiNE" "tarball" "latest" "/opt/affine"

  msg_info "Setting up Directories"
  rm -rf /root/.affine
  mkdir -p /root/.affine/{storage,config}
  msg_ok "Set up Directories"

  msg_info "Configuring Environment"
  SECRET_KEY=$(openssl rand -hex 32)
  cat << EOF > /opt/affine/.env
NODE_ENV=production
AFFINE_SERVER_PORT=3010
AFFINE_SERVER_HOST=${LOCAL_IP}
AFFINE_SERVER_EXTERNAL_URL=http://${LOCAL_IP}
DATABASE_URL=postgresql://${PG_DB_USER}:${PG_DB_PASS}@localhost:5432/${PG_DB_NAME}
REDIS_SERVER_HOST=localhost
REDIS_SERVER_PORT=6379
AFFINE_INDEXER_ENABLED=false
SECRET_KEY=${SECRET_KEY}
EOF
  msg_ok "Configured Environment"

  msg_info "Building AFFiNE (Patience)"
  cd /opt/affine || exit
  source /root/.profile
  export PATH="/root/.cargo/bin:$PATH"
  export COREPACK_ENABLE_DOWNLOAD_PROMPT=0
  export VITE_CORE_COMMIT_SHA=$(cat ~/.affine_app)
  $STD git init -q
  $STD git config user.email "build@local"
  $STD git config user.name "Build"
  $STD git add -A
  $STD git commit -q -m "initial"
  mkdir -p /opt/affine/.turbo
  cat << TURBO > /opt/affine/.turbo/config.json
{
  "concurrency": 1
}
TURBO
  $STD corepack enable
  $STD corepack prepare yarn@4.12.0 --activate
  $STD yarn config set enableTelemetry 0
  export NODE_OPTIONS="--max-old-space-size=4096"
  export TSC_COMPILE_ON_ERROR=true
  $STD yarn install
  $STD npm install -g typescript
  $STD yarn affine @affine/native build
  $STD yarn affine @affine/server-native build

  ln -sf /opt/affine/packages/backend/native/server-native.node \
    /opt/affine/packages/backend/native/server-native.x64.node
  ln -sf /opt/affine/packages/backend/native/server-native.node \
    /opt/affine/packages/backend/native/server-native.arm64.node
  ln -sf /opt/affine/packages/backend/native/server-native.node \
    /opt/affine/packages/backend/native/server-native.armv7.node

  $STD yarn affine init
  $STD yarn affine build -p @affine/reader
  $STD yarn affine build -p @affine/server
  export NODE_OPTIONS="--max-old-space-size=4096"
  $STD yarn affine build -p @affine/web
  $STD yarn affine build -p @affine/admin
  mkdir -p /opt/affine/packages/backend/server/static
  cp -r /opt/affine/packages/frontend/apps/web/dist/* /opt/affine/packages/backend/server/static/
  mkdir -p /opt/affine/packages/backend/server/static/admin
  cp -r /opt/affine/packages/frontend/admin/dist/* /opt/affine/packages/backend/server/static/admin/
  mkdir -p /opt/affine/packages/backend/server/static/mobile
  cat << 'MANIFEST' > /opt/affine/packages/backend/server/static/mobile/assets-manifest.json
{"publicPath":"/","js":[],"css":[],"gitHash":"","description":""}
MANIFEST
  msg_ok "Built AFFiNE"

  msg_info "Running Initial Migration"
  cd /opt/affine/packages/backend/server || exit
  set -a && source /opt/affine/.env && set +a
  $STD node ./scripts/self-host-predeploy.js
  msg_ok "Ran Initial Migration"

  msg_info "Creating Services"
  cat << EOF > /etc/systemd/system/affine-web.service
[Unit]
Description=AFFiNE Web Server
After=network.target postgresql.service redis-server.service
Requires=postgresql.service redis-server.service

[Service]
Type=simple
WorkingDirectory=/opt/affine/packages/backend/server
EnvironmentFile=/opt/affine/.env
Environment=LD_PRELOAD=libjemalloc.so.2
Environment=NODE_OPTIONS=--max-old-space-size=1024
ExecStart=/usr/bin/node ./dist/main.js
Restart=always
RestartSec=10

[Install]
WantedBy=multi-user.target
EOF

  cat << EOF > /etc/systemd/system/affine-worker.service
[Unit]
Description=AFFiNE Background Worker
After=network.target postgresql.service redis-server.service
Requires=postgresql.service redis-server.service

[Service]
Type=simple
WorkingDirectory=/opt/affine/packages/backend/server
EnvironmentFile=/opt/affine/.env
Environment=LD_PRELOAD=libjemalloc.so.2
Environment=NODE_OPTIONS=--max-old-space-size=1024
ExecStart=/usr/bin/node ./dist/main.js --worker
Restart=always
RestartSec=10

[Install]
WantedBy=multi-user.target
EOF

  systemctl enable -q --now redis-server affine-web affine-worker
  msg_ok "Created Services"

  msg_info "Creating Admin User"
  ADMIN_PASS=$(openssl rand -base64 12)
  for i in {1..30}; do
    if curl -s http://localhost:3010/info > /dev/null 2>&1; then
      break
    fi
    sleep 2
  done
  ADMIN_RESPONSE=$(curl -s -X POST http://localhost:3010/api/setup/create-admin-user \
    -H "Content-Type: application/json" \
    -d "{\"email\":\"admin@affine.local\",\"password\":\"${ADMIN_PASS}\"}")
  if echo "$ADMIN_RESPONSE" | grep -q '"id"'; then
    {
      echo "AFFiNE Credentials"
      echo "=================="
      echo "Email: admin@affine.local"
      echo "Password: ${ADMIN_PASS}"
    } > ~/affine.creds
    msg_ok "Created Admin User"
  else
    msg_warn "Admin creation skipped (may already exist)"
  fi

  msg_info "Configuring Nginx"
  cat << EOF > /etc/nginx/sites-available/affine.conf
upstream affine_backend {
    server 127.0.0.1:3010;
}

server {
    listen 80;
    server_name _;

    client_max_body_size 100M;

    location / {
        proxy_pass http://affine_backend;
        proxy_http_version 1.1;
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
        proxy_set_header Upgrade \$http_upgrade;
        proxy_set_header Connection "upgrade";
        proxy_redirect off;
        proxy_buffering off;
    }
}
EOF
  ln -sf /etc/nginx/sites-available/affine.conf /etc/nginx/sites-enabled/
  rm -f /etc/nginx/sites-enabled/default
  systemctl enable -q --now nginx
  msg_ok "Configured Nginx"
}

function post_install_script() {
  msg_ok "Completed Successfully!\n"
  echo -e "${CREATING}${GN}${APP} setup has been successfully initialized!${CL}"
  echo -e "${INFO}${YW} Access it using the following URL:${CL}"
  echo -e "${TAB}${GATEWAY}${BGN}http://${IP}:3010/sign-in${CL}"
}

function update_script() {
  header_info
  check_container_storage
  check_container_resources

  if [[ ! -d /opt/affine ]]; then
    msg_error "No ${APP} Installation Found!"
    exit
  fi

  if check_for_gh_release "affine_app" "toeverything/AFFiNE"; then
    msg_info "Stopping Services"
    systemctl stop affine-web affine-worker
    msg_ok "Stopped Services"

    msg_info "Backing up Data"
    cp -r /root/.affine/storage /root/.affine_storage_backup 2> /dev/null || true
    cp -r /root/.affine/config /root/.affine_config_backup 2> /dev/null || true
    msg_ok "Backed up Data"

    CLEAN_INSTALL=1 fetch_and_deploy_gh_release "affine_app" "toeverything/AFFiNE" "tarball" "latest" "/opt/affine"

    msg_info "Rebuilding Application (Patience)"
    cd /opt/affine || exit
    source /root/.profile
    export PATH="/root/.cargo/bin:/root/.rbenv/shims:$PATH"

    set -a && source /opt/affine/.env && set +a

    export COREPACK_ENABLE_DOWNLOAD_PROMPT=0
    export VITE_CORE_COMMIT_SHA=$(cat ~/.affine_app)

    # Initialize git repo (required for build process)
    git init -q
    git config user.email "build@local"
    git config user.name "Build"
    git add -A
    git commit -q -m "update"

    # Force Turbo to run sequentially
    mkdir -p /opt/affine/.turbo
    cat << TURBO > /opt/affine/.turbo/config.json
{
  "concurrency": 1
}
TURBO

    $STD corepack enable
    $STD corepack prepare yarn@4.12.0 --activate
    $STD yarn config set enableTelemetry 0

    export NODE_OPTIONS="--max-old-space-size=2048"
    $STD yarn install
    $STD npm install -g typescript

    $STD yarn affine @affine/native build
    $STD yarn affine @affine/server-native build

    # Create architecture-specific symlinks
    ln -sf /opt/affine/packages/backend/native/server-native.node \
      /opt/affine/packages/backend/native/server-native.x64.node
    ln -sf /opt/affine/packages/backend/native/server-native.node \
      /opt/affine/packages/backend/native/server-native.arm64.node
    ln -sf /opt/affine/packages/backend/native/server-native.node \
      /opt/affine/packages/backend/native/server-native.armv7.node

    $STD yarn affine init
    $STD yarn affine build -p @affine/reader
    $STD yarn affine build -p @affine/server

    export NODE_OPTIONS="--max-old-space-size=4096"
    $STD yarn affine build -p @affine/web
    $STD yarn affine build -p @affine/admin

    # Copy web assets
    mkdir -p /opt/affine/packages/backend/server/static
    cp -r /opt/affine/packages/frontend/apps/web/dist/* /opt/affine/packages/backend/server/static/
    mkdir -p /opt/affine/packages/backend/server/static/admin
    cp -r /opt/affine/packages/frontend/admin/dist/* /opt/affine/packages/backend/server/static/admin/

    # Mobile manifest placeholder
    mkdir -p /opt/affine/packages/backend/server/static/mobile
    echo '{"publicPath":"/","js":[],"css":[],"gitHash":"","description":""}' \
      > /opt/affine/packages/backend/server/static/mobile/assets-manifest.json

    # Run migrations
    cd /opt/affine/packages/backend/server || exit
    set -a && source /opt/affine/.env && set +a
    $STD node ./scripts/self-host-predeploy.js

    msg_info "Restoring Data"
    cp -r /root/.affine_storage_backup/. /root/.affine/storage/ 2> /dev/null || true
    cp -r /root/.affine_config_backup/. /root/.affine/config/ 2> /dev/null || true
    rm -rf /root/.affine_storage_backup /root/.affine_config_backup
    msg_ok "Restored Data"

    msg_info "Starting Services"
    systemctl start affine-web affine-worker
    msg_ok "Started Services"
    msg_ok "Updated Successfully!"
  fi
  exit
}

# framework bootstrap
# Dynamic URL resolved at runtime - shellcheck cannot follow\n# shellcheck disable=SC1090\nsource <(curl -fsSL "$REPO_BASE/misc/bootstrap/lxc")
