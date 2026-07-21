#!/usr/bin/env bash
REPO_BASE="${REPO_BASE:-https://raw.githubusercontent.com/scripts-underground/proxmox/main}"

# Copyright (c) 2021-2026 community-scripts ORG
# Author: MickLesk (CanbiZ)
# License: MIT | https://raw.githubusercontent.com/scripts-underground/proxmox/main/LICENSE
# Source: https://github.com/teableio/teable

# shellcheck disable=SC2034
APP="Teable"
var_tags="${var_tags:-database;no-code;spreadsheet}"
var_cpu="${var_cpu:-4}"
var_ram="${var_ram:-10240}"
var_disk="${var_disk:-25}"
var_os="${var_os:-debian}"
var_version="${var_version:-13}"
var_arm64="${var_arm64:-yes}"
var_unprivileged="${var_unprivileged:-1}"

function install_script() {
  msg_info "Installing Dependencies"
  $STD apt install -y \
    build-essential \
    python3 \
    git
  msg_ok "Installed Dependencies"

  NODE_VERSION="24" NODE_MODULE="pnpm" setup_nodejs
  PG_VERSION="16" setup_postgresql
  PG_DB_NAME="teable" PG_DB_USER="teable" setup_postgresql_db

  fetch_and_deploy_gh_release "teable" "teableio/teable" "tarball"

  msg_info "Setting up Teable"
  cd /opt/teable || exit
  TEABLE_VERSION=$(cat ~/.teable)
  echo "NEXT_PUBLIC_BUILD_VERSION=\"${TEABLE_VERSION}\"" >> apps/nextjs-app/.env
  export HUSKY=0
  export NODE_OPTIONS="--max-old-space-size=8192"
  $STD pnpm install --frozen-lockfile
  $STD pnpm -F @teable/db-main-prisma prisma-generate --schema ./prisma/postgres/schema.prisma
  msg_ok "Set up Teable"

  msg_info "Building Teable"
  NODE_ENV=production NEXT_BUILD_ENV_TYPECHECK=false \
    $STD pnpm -r --filter '!playground' run build
  msg_ok "Built Teable"

  msg_info "Running Database Migrations"
  PRISMA_DATABASE_URL="postgresql://teable:${PG_DB_PASS}@localhost:5432/teable?schema=public" \
    $STD pnpm -F @teable/db-main-prisma prisma-migrate deploy --schema ./prisma/postgres/schema.prisma
  msg_ok "Ran Database Migrations"

  msg_info "Configuring Teable"
  mkdir -p /opt/teable/.assets /opt/teable/.temporary
  SECRET_KEY=$(openssl rand -base64 32)
  cat << EOF > /opt/teable/.env
PRISMA_DATABASE_URL=postgresql://teable:${PG_DB_PASS}@localhost:5432/teable?schema=public&statement_cache_size=1
PUBLIC_ORIGIN=http://${LOCAL_IP}:3000
SECRET_KEY=${SECRET_KEY}
PORT=3000
NODE_ENV=production
NEXT_TELEMETRY_DISABLED=1
BACKEND_CACHE_PROVIDER=sqlite
BACKEND_CACHE_SQLITE_URI=sqlite:///opt/teable/.assets/.cache.db
NEXTJS_DIR=apps/nextjs-app
EOF
  ln -sf /opt/teable /app
  rm -rf /opt/teable/static
  if [ -d "/opt/teable/apps/nestjs-backend/static/static" ]; then
    ln -sf /opt/teable/apps/nestjs-backend/static/static /opt/teable/static
  else
    ln -sf /opt/teable/apps/nestjs-backend/static /opt/teable/static
  fi
  msg_ok "Configured Teable"

  msg_info "Creating Service"
  cat << EOF > /etc/systemd/system/teable.service
[Unit]
Description=Teable
After=network.target postgresql.service

[Service]
Type=simple
WorkingDirectory=/opt/teable
EnvironmentFile=/opt/teable/.env
ExecStart=/usr/bin/node apps/nestjs-backend/dist/index.js
Restart=on-failure
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF
  systemctl enable -q --now teable
  msg_ok "Created Service"
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

  if [[ ! -d /opt/teable ]]; then
    msg_error "No ${APP} Installation Found!"
    exit
  fi

  if check_for_gh_release "teable" "teableio/teable"; then
    msg_info "Stopping Service"
    systemctl stop teable
    msg_ok "Stopped Service"

    msg_info "Backing up Configuration"
    cp /opt/teable/.env /opt/teable.env.bak
    msg_ok "Backed up Configuration"

    CLEAN_INSTALL=1 fetch_and_deploy_gh_release "teable" "teableio/teable" "tarball"

    msg_info "Restoring Configuration"
    mv /opt/teable.env.bak /opt/teable/.env
    msg_ok "Restored Configuration"

    msg_info "Rebuilding Teable"
    cd /opt/teable || exit
    TEABLE_VERSION=$(cat ~/.teable)
    echo "NEXT_PUBLIC_BUILD_VERSION=\"${TEABLE_VERSION}\"" >> apps/nextjs-app/.env
    export HUSKY=0
    export NODE_OPTIONS="--max-old-space-size=8192"
    $STD pnpm install --frozen-lockfile
    $STD pnpm -F @teable/db-main-prisma prisma-generate --schema ./prisma/postgres/schema.prisma
    NODE_ENV=production NEXT_BUILD_ENV_TYPECHECK=false \
      $STD pnpm -r --filter '!playground' run build
    msg_ok "Rebuilt Teable"

    msg_info "Running Database Migrations"
    source /opt/teable/.env
    $STD pnpm -F @teable/db-main-prisma prisma-migrate deploy --schema ./prisma/postgres/schema.prisma
    msg_ok "Ran Database Migrations"

    msg_info "Starting Service"
    systemctl start teable
    msg_ok "Started Service"
    msg_ok "Updated successfully!"
  else
    msg_ok "No update available."
  fi
  exit
}

# shellcheck disable=SC1090
source <(curl -fsSL "$REPO_BASE/misc/bootstrap/lxc")
