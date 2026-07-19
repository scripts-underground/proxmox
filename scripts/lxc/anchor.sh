#!/usr/bin/env bash
REPO_BASE="${REPO_BASE:-https://raw.githubusercontent.com/scripts-underground/proxmox/main}"

# Sourced by lxc.bootstrap — never executed directly
# Copyright (c) 2021-2026 community-scripts ORG
# Author: MickLesk (CanbiZ)
# License: MIT | https://raw.githubusercontent.com/scripts-underground/proxmox/main/LICENSE
# Source: https://github.com/ZhFahim/anchor

# shellcheck disable=SC2034
# Read by the framework - shellcheck cannot see the caller
APP="Anchor"
var_tags="${var_tags:-notes;productivity;sync}"
var_cpu="${var_cpu:-2}"
var_ram="${var_ram:-2048}"
var_disk="${var_disk:-10}"
var_os="${var_os:-debian}"
var_version="${var_version:-13}"
var_arm64="${var_arm64:-yes}"
var_unprivileged="${var_unprivileged:-1}"

function install_script() {
  msg_info "Installing Node.js"
  NODE_VERSION="24" NODE_MODULE="pnpm" setup_nodejs
  msg_ok "Installed Node.js"

  msg_info "Setting up PostgreSQL"
  PG_VERSION="17" setup_postgresql
  PG_DB_NAME="anchor" PG_DB_USER="anchor" setup_postgresql_db
  msg_ok "Set up PostgreSQL"

  fetch_and_deploy_gh_release "anchor" "ZhFahim/anchor" "tarball"

  msg_info "Building Server"
  cd /opt/anchor/server || exit
  $STD pnpm install --frozen-lockfile
  $STD pnpm prisma generate
  $STD pnpm build
  [[ -d src/generated ]] && mkdir -p dist/src && cp -R src/generated dist/src/
  msg_ok "Built Server"

  msg_info "Building Web Interface"
  cd /opt/anchor/web || exit
  $STD pnpm install --frozen-lockfile
  SERVER_URL=http://127.0.0.1:3001 $STD pnpm build
  cp -r .next/static .next/standalone/.next/static
  cp -r public .next/standalone/public
  msg_ok "Built Web Interface"

  msg_info "Configuring Application"
  JWT_SECRET=$(openssl rand -base64 32)
  cat << EOF > /opt/anchor/.env
APP_URL=http://${LOCAL_IP}:3000
JWT_SECRET=${JWT_SECRET}
DATABASE_URL=postgresql://anchor:${PG_DB_PASS}@localhost:5432/anchor
PG_HOST=localhost
PG_USER=anchor
PG_PASSWORD=${PG_DB_PASS}
PG_DATABASE=anchor
PG_PORT=5432
EOF
  msg_ok "Configured Application"

  msg_info "Running Database Migrations"
  cd /opt/anchor/server || exit
  set -a && source /opt/anchor/.env && set +a
  $STD pnpm prisma migrate deploy
  msg_ok "Ran Database Migrations"

  msg_info "Creating Services"
  cat << EOF > /etc/systemd/system/anchor-server.service
[Unit]
Description=Anchor API Server
After=network.target postgresql.service

[Service]
Type=simple
User=root
WorkingDirectory=/opt/anchor/server
EnvironmentFile=/opt/anchor/.env
ExecStart=/usr/bin/node dist/src/main.js
Restart=on-failure
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF
  cat << EOF > /etc/systemd/system/anchor-web.service
[Unit]
Description=Anchor Web Interface
After=network.target anchor-server.service

[Service]
Type=simple
User=root
WorkingDirectory=/opt/anchor/web/.next/standalone
EnvironmentFile=/opt/anchor/.env
Environment=PORT=3000 HOSTNAME=0.0.0.0 NODE_ENV=production
ExecStart=/usr/bin/node server.js
Restart=on-failure
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF
  systemctl enable -q --now anchor-server anchor-web
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

  if [[ ! -f ~/.anchor ]]; then
    msg_error "No ${APP} Installation Found!"
    exit
  fi

  if check_for_gh_release "anchor" "ZhFahim/anchor"; then
    msg_info "Stopping Services"
    systemctl stop anchor-web anchor-server
    msg_ok "Stopped Services"

    create_backup /opt/anchor/.env

    CLEAN_INSTALL=1 fetch_and_deploy_gh_release "anchor" "ZhFahim/anchor" "tarball"

    msg_info "Building Server"
    cd /opt/anchor/server || exit
    $STD pnpm install --frozen-lockfile
    $STD pnpm prisma generate
    $STD pnpm build
    [[ -d src/generated ]] && mkdir -p dist/src && cp -R src/generated dist/src/
    msg_ok "Built Server"

    msg_info "Building Web Interface"
    cd /opt/anchor/web || exit
    $STD pnpm install --frozen-lockfile
    SERVER_URL=http://127.0.0.1:3001 $STD pnpm build
    cp -r .next/static .next/standalone/.next/static
    cp -r public .next/standalone/public
    msg_ok "Built Web Interface"

    restore_backup

    msg_info "Running Database Migrations"
    cd /opt/anchor/server || exit
    set -a && source /opt/anchor/.env && set +a
    $STD pnpm prisma migrate deploy
    msg_ok "Ran Database Migrations"

    msg_info "Starting Services"
    systemctl start anchor-server anchor-web
    msg_ok "Started Services"
    msg_ok "Updated ${APP}"
  fi
  exit
}

# framework bootstrap
# shellcheck disable=SC1090
# Dynamic URL resolved at runtime - shellcheck cannot follow
source <(curl -fsSL "$REPO_BASE/misc/bootstrap/lxc")
