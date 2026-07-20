#!/usr/bin/env bash
REPO_BASE="${REPO_BASE:-https://raw.githubusercontent.com/scripts-underground/proxmox/main}"

# Copyright (c) 2021-2026 community-scripts ORG
# Author: MickLesk (CanbiZ)
# License: MIT | https://raw.githubusercontent.com/scripts-underground/proxmox/main/LICENSE
# Source: https://github.com/lobehub/lobehub

# shellcheck disable=SC2034
APP="LobeHub"
var_tags="${var_tags:-ai;chat}"
var_cpu="${var_cpu:-6}"
var_ram="${var_ram:-10240}"
var_disk="${var_disk:-15}"
var_os="${var_os:-debian}"
var_version="${var_version:-13}"
var_arm64="${var_arm64:-yes}"
var_unprivileged="${var_unprivileged:-1}"

function install_script() {
  msg_info "Installing Dependencies"
  $STD apt install -y build-essential
  msg_ok "Installed Dependencies"

  PG_VERSION="17" PG_MODULES="pgvector" setup_postgresql

  CODENAME=$(. /etc/os-release && echo "${VERSION_CODENAME:-bookworm}")
  fetch_and_deploy_gh_release "paradedb" "paradedb/paradedb" "binary" "latest" "" "postgresql-17-pg-search_*-1PARADEDB-${CODENAME}_$(get_system_arch).deb"

  msg_info "Configuring pg_search preload library"
  if ! grep -q "shared_preload_libraries.*pg_search" /etc/postgresql/17/main/postgresql.conf; then
    echo "shared_preload_libraries = 'pg_search'" >> /etc/postgresql/17/main/postgresql.conf
  fi
  systemctl restart postgresql
  msg_ok "Configured pg_search preload library"

  PG_DB_NAME="lobehub" PG_DB_USER="lobehub" PG_DB_EXTENSIONS="vector,pg_search" setup_postgresql_db

  NODE_VERSION="24" NODE_MODULE="pnpm" setup_nodejs

  fetch_and_deploy_gh_release "lobehub" "lobehub/lobehub" "tarball"

  msg_info "Building Application"
  cd /opt/lobehub || exit
  export DATABASE_URL="postgres://${PG_DB_USER}:${PG_DB_PASS}@localhost:5432/${PG_DB_NAME}"
  export DATABASE_DRIVER="node"
  KEY_VAULTS_SECRET="$(openssl rand -base64 32)"
  AUTH_SECRET="$(openssl rand -base64 32)"
  export KEY_VAULTS_SECRET
  export AUTH_SECRET
  export APP_URL="http://localhost:3210"
  $STD pnpm install
  $STD pnpm run build:docker
  msg_ok "Built Application"

  msg_info "Configuring Application"
  KEY_VAULTS_SECRET=$(openssl rand -base64 32)
  AUTH_SECRET=$(openssl rand -base64 32)
  cat << EOF > /opt/lobehub/.env
DATABASE_URL=postgres://${PG_DB_USER}:${PG_DB_PASS}@localhost:5432/${PG_DB_NAME}
DATABASE_DRIVER=node
KEY_VAULTS_SECRET=${KEY_VAULTS_SECRET}
AUTH_SECRET=${AUTH_SECRET}
APP_URL=http://${LOCAL_IP}:3210
HOSTNAME=0.0.0.0
PORT=3210
NODE_ENV=production
EOF
  msg_ok "Configured Application"

  msg_info "Setting Up Standalone"
  cp -r /opt/lobehub/.next/static /opt/lobehub/.next/standalone/.next/static
  cp -r /opt/lobehub/public /opt/lobehub/.next/standalone/public
  cp -r /opt/lobehub/scripts/migrateServerDB/* /opt/lobehub/.next/standalone/
  cp -r /opt/lobehub/packages/database/migrations /opt/lobehub/.next/standalone/migrations
  msg_ok "Set Up Standalone"

  msg_info "Running Database Migrations"
  cd /opt/lobehub/.next/standalone || exit
  set -a && source /opt/lobehub/.env && set +a
  $STD node /opt/lobehub/.next/standalone/docker.cjs
  msg_ok "Ran Database Migrations"

  msg_info "Creating Service"
  cat << EOF > /etc/systemd/system/lobehub.service
[Unit]
Description=LobeHub
After=network.target postgresql.service
Requires=postgresql.service

[Service]
Type=simple
User=root
WorkingDirectory=/opt/lobehub/.next/standalone
EnvironmentFile=/opt/lobehub/.env
ExecStart=/usr/bin/node /opt/lobehub/.next/standalone/server.js
Restart=on-failure
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF
  systemctl enable -q --now lobehub
  msg_ok "Created Service"
}

function post_install_script() {
  msg_ok "Completed successfully!\n"
  echo -e "${CREATING}${GN}${APP} setup has been successfully initialized!${CL}"
  echo -e "${INFO}${YW}Access it using the following URL:${CL}"
  echo -e "${GATEWAY}${BGN}http://${IP}:3210${CL}"
}

function update_script() {
  header_info
  check_container_storage
  check_container_resources

  if [[ ! -d /opt/lobehub ]]; then
    msg_error "No ${APP} Installation Found!"
    exit
  fi

  if check_for_gh_release "lobehub" "lobehub/lobehub"; then
    msg_info "Stopping Services"
    systemctl stop lobehub
    msg_ok "Stopped Services"

    msg_info "Backing up Data"
    cp /opt/lobehub/.env /opt/lobehub.env.bak
    msg_ok "Backed up Data"

    CLEAN_INSTALL=1 fetch_and_deploy_gh_release "lobehub" "lobehub/lobehub" "tarball"

    msg_info "Restoring Configuration"
    cp /opt/lobehub.env.bak /opt/lobehub/.env
    rm -f /opt/lobehub.env.bak
    msg_ok "Restored Configuration"

    msg_info "Building Application"
    cd /opt/lobehub || exit
    export NODE_OPTIONS="--max-old-space-size=8192"
    $STD pnpm install
    $STD pnpm run build:docker
    unset NODE_OPTIONS
    msg_ok "Built Application"

    msg_info "Setting Up Standalone"
    cp -r /opt/lobehub/.next/static /opt/lobehub/.next/standalone/.next/static
    cp -r /opt/lobehub/public /opt/lobehub/.next/standalone/public
    cp -r /opt/lobehub/scripts/migrateServerDB/* /opt/lobehub/.next/standalone/
    cp -r /opt/lobehub/packages/database/migrations /opt/lobehub/.next/standalone/migrations
    msg_ok "Set Up Standalone"

    msg_info "Running Database Migrations"
    cd /opt/lobehub/.next/standalone || exit
    set -a && source /opt/lobehub/.env && set +a
    $STD node /opt/lobehub/.next/standalone/docker.cjs
    msg_ok "Ran Database Migrations"

    msg_info "Starting Services"
    systemctl start lobehub
    msg_ok "Started Services"
    msg_ok "Updated successfully!"
  fi
  exit
}

# shellcheck disable=SC1090
source <(curl -fsSL "$REPO_BASE/misc/bootstrap/lxc")
