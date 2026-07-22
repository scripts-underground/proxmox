#!/usr/bin/env bash
# shellcheck disable=SC2034,SC2155,SC2046
REPO_BASE="${REPO_BASE:-https://raw.githubusercontent.com/scripts-underground/proxmox/main}"

# Copyright (c) 2021-2026 community-scripts ORG
# Author: MickLesk (CanbiZ)
# License: MIT | https://raw.githubusercontent.com/scripts-underground/proxmox/main/LICENSE
# Source: https://github.com/twentyhq/twenty

# shellcheck disable=SC2034
# Read by the framework - shellcheck cannot see the caller
APP="Twenty"
var_tags="${var_tags:-crm;business;contacts}"
var_cpu="${var_cpu:-4}"
var_ram="${var_ram:-10240}"
var_disk="${var_disk:-20}"
var_os="${var_os:-debian}"
var_version="${var_version:-13}"
var_arm64="${var_arm64:-yes}"
var_unprivileged="${var_unprivileged:-1}"

function install_script() {
  msg_info "Installing Dependencies"
  $STD apt install -y \
    build-essential \
    redis-server
  msg_ok "Installed Dependencies"

  PG_VERSION="17" PG_MODULES="pgvector" setup_postgresql
  PG_DB_NAME="twenty_db" PG_DB_USER="twenty" PG_DB_SCHEMA_PERMS="true" PG_DB_EXTENSIONS="vector" setup_postgresql_db
  NODE_VERSION="24" NODE_MODULE="corepack" setup_nodejs

  fetch_and_deploy_gh_release "twenty" "twentyhq/twenty" "tarball"

  msg_info "Building Application"
  cd /opt/twenty || exit
  export COREPACK_ENABLE_DOWNLOAD_PROMPT=0
  $STD corepack prepare yarn@4.9.2 --activate
  yarn install --immutable > /dev/null 2>&1 || $STD yarn install
  export NODE_OPTIONS="--max-old-space-size=4096"
  $STD npx nx run twenty-server:build
  $STD npx nx build twenty-front
  cp -r /opt/twenty/packages/twenty-front/build /opt/twenty/packages/twenty-server/dist/front
  unset NODE_OPTIONS
  msg_ok "Built Application"

  msg_info "Configuring Application"
  APP_SECRET=$(openssl rand -base64 32)
  mkdir -p /opt/twenty/packages/twenty-server/.local-storage
  cat << EOF > /opt/twenty/.env
NODE_PORT=3000
PG_DATABASE_URL=postgresql://${PG_DB_USER}:${PG_DB_PASS}@localhost:5432/${PG_DB_NAME}
REDIS_URL=redis://localhost:6379
SERVER_URL=http://${LOCAL_IP}:3000
APP_SECRET=${APP_SECRET}
STORAGE_TYPE=local
NODE_ENV=production
EOF
  msg_ok "Configured Application"

  msg_info "Running Database Migrations"
  cd /opt/twenty/packages/twenty-server || exit
  set -a && source /opt/twenty/.env && set +a
  $STD yarn database:init:prod
  msg_ok "Ran Database Migrations"

  msg_info "Creating Services"
  cat << EOF > /etc/systemd/system/twenty-server.service
[Unit]
Description=Twenty CRM Server
After=network.target postgresql.service redis-server.service
Requires=postgresql.service redis-server.service

[Service]
Type=simple
User=root
WorkingDirectory=/opt/twenty/packages/twenty-server
EnvironmentFile=/opt/twenty/.env
ExecStart=/usr/bin/node dist/main
Restart=on-failure
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF

  cat << EOF > /etc/systemd/system/twenty-worker.service
[Unit]
Description=Twenty CRM Worker
After=network.target postgresql.service redis-server.service twenty-server.service
Requires=postgresql.service redis-server.service

[Service]
Type=simple
User=root
WorkingDirectory=/opt/twenty/packages/twenty-server
EnvironmentFile=/opt/twenty/.env
Environment=DISABLE_DB_MIGRATIONS=true
Environment=DISABLE_CRON_JOBS_REGISTRATION=true
ExecStart=/usr/bin/node dist/queue-worker/queue-worker
Restart=on-failure
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF
  systemctl enable -q --now redis-server twenty-server twenty-worker
  msg_ok "Created Services"
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

  if [[ ! -d /opt/twenty ]]; then
    msg_error "No ${APP} Installation Found!"
    exit
  fi

  NODE_VERSION="24" NODE_MODULE="corepack" setup_nodejs

  if check_for_gh_release "twenty" "twentyhq/twenty"; then
    msg_info "Stopping Services"
    systemctl stop twenty-worker twenty-server
    msg_ok "Stopped Services"

    create_backup /opt/twenty/.env \
      /opt/twenty/packages/twenty-server/.local-storage
    CLEAN_INSTALL=1 fetch_and_deploy_gh_release "twenty" "twentyhq/twenty" "tarball"
    restore_backup

    msg_info "Building Application"
    cd /opt/twenty || exit
    export COREPACK_ENABLE_DOWNLOAD_PROMPT=0
    $STD corepack prepare yarn@4.9.2 --activate
    export NODE_OPTIONS="--max-old-space-size=3072"
    $STD yarn install --immutable || $STD yarn install
    $STD npx nx run twenty-server:build
    $STD npx nx build twenty-front
    cp -r /opt/twenty/packages/twenty-front/build /opt/twenty/packages/twenty-server/dist/front
    unset NODE_OPTIONS
    msg_ok "Built Application"

    msg_info "Running Database Migrations"
    cd /opt/twenty/packages/twenty-server || exit
    set -a && source /opt/twenty/.env && set +a
    $STD npx ts-node ./scripts/setup-db.ts
    $STD npx -y typeorm migration:run -d dist/database/typeorm/core/core.datasource
    msg_ok "Ran Database Migrations"

    msg_info "Starting Services"
    systemctl start twenty-server twenty-worker
    msg_ok "Started Services"
    msg_ok "Updated successfully!"
  fi
  exit
}

# framework bootstrap
# shellcheck disable=SC1090
# Dynamic URL resolved at runtime - shellcheck cannot follow
source <(curl -fsSL "$REPO_BASE/misc/bootstrap/lxc")
