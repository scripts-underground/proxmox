#!/usr/bin/env bash
REPO_BASE="${REPO_BASE:-https://raw.githubusercontent.com/scripts-underground/proxmox/main}"

# Sourced by lxc.bootstrap — never executed directly
# Copyright (c) 2021-2026 community-scripts ORG
# Author: phof
# License: MIT | https://raw.githubusercontent.com/scripts-underground/proxmox/main/LICENSE
# Source: https://github.com/spliit-app/spliit

# shellcheck disable=SC2034
# Read by the framework - shellcheck cannot see the caller
APP="Spliit"
var_tags="${var_tags:-finance;expense-sharing}"
var_cpu="${var_cpu:-2}"
var_ram="${var_ram:-2048}"
var_disk="${var_disk:-8}"
var_os="${var_os:-debian}"
var_version="${var_version:-13}"
var_arm64="${var_arm64:-no}"
var_unprivileged="${var_unprivileged:-1}"

function install_script() {
  msg_info "Installing Dependencies"
  $STD apt install -y git
  msg_ok "Installed Dependencies"

  PG_VERSION="16" setup_postgresql
  PG_DB_NAME="spliit" PG_DB_USER="spliit" setup_postgresql_db
  NODE_VERSION="22" setup_nodejs

  fetch_and_deploy_gh_release "spliit" "spliit-app/spliit" "tarball"

  msg_info "Configuring Application"
  cat << EOF > /opt/spliit/.env
POSTGRES_PRISMA_URL=postgresql://${PG_DB_USER}:${PG_DB_PASS}@localhost:5432/${PG_DB_NAME}?schema=public
POSTGRES_URL_NON_POOLING=postgresql://${PG_DB_USER}:${PG_DB_PASS}@localhost:5432/${PG_DB_NAME}?schema=public
NEXT_PUBLIC_DEFAULT_CURRENCY_CODE=
NEXT_TELEMETRY_DISABLED=1
NODE_ENV=production
PORT=3000
HOSTNAME=0.0.0.0
EOF
  msg_ok "Configured Application"

  msg_info "Building Application"
  cd /opt/spliit || exit
  $STD npm ci --ignore-scripts
  $STD npx prisma generate
  $STD npm run build
  msg_ok "Built Application"

  msg_info "Running Database Migrations"
  cd /opt/spliit || exit
  $STD npx prisma migrate deploy
  msg_ok "Ran Database Migrations"

  msg_info "Creating Service"
  cat << EOF > /etc/systemd/system/spliit.service
[Unit]
Description=Spliit
After=network.target postgresql.service
Requires=postgresql.service

[Service]
Type=simple
User=root
WorkingDirectory=/opt/spliit
EnvironmentFile=/opt/spliit/.env
ExecStart=/usr/bin/npm run start
Restart=on-failure
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF
  systemctl enable -q --now spliit
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

  if [[ ! -d /opt/spliit ]]; then
    msg_error "No ${APP} Installation Found!"
    exit
  fi

  if check_for_gh_release "spliit" "spliit-app/spliit"; then
    msg_info "Stopping Service"
    systemctl stop spliit
    msg_ok "Stopped Service"

    create_backup /opt/spliit/.env

    CLEAN_INSTALL=1 fetch_and_deploy_gh_release "spliit" "spliit-app/spliit" "tarball"

    restore_backup

    msg_info "Building Application"
    cd /opt/spliit || exit
    $STD npm ci --ignore-scripts
    $STD npx prisma generate
    $STD npm run build
    msg_ok "Built Application"

    msg_info "Running Database Migrations"
    cd /opt/spliit || exit
    $STD npx prisma migrate deploy
    msg_ok "Ran Database Migrations"

    msg_info "Starting Service"
    systemctl start spliit
    msg_ok "Started Service"
    msg_ok "Updated successfully!"
  fi
  exit
}

# framework bootstrap
# shellcheck disable=SC1090
# Dynamic URL resolved at runtime - shellcheck cannot follow
source <(curl -fsSL "$REPO_BASE/misc/bootstrap/lxc")
