#!/usr/bin/env bash
REPO_BASE="${REPO_BASE:-https://raw.githubusercontent.com/scripts-underground/proxmox/main}"

# Copyright (c) 2021-2026 community-scripts ORG
# Author: MickLesk (CanbiZ)
# License: MIT | https://raw.githubusercontent.com/scripts-underground/proxmox/main/LICENSE
# Source: https://bookorbit.app

APP="BookOrbit"
var_tags="${var_tags:-books;library;reading}"
var_cpu="${var_cpu:-2}"
var_ram="${var_ram:-2048}"
var_disk="${var_disk:-10}"
var_os="${var_os:-debian}"
var_version="${var_version:-13}"
var_unprivileged="${var_unprivileged:-1}"

function install_script() {
  msg_info "Installing Dependencies"
  $STD apt install -y \
    build-essential \
    ffmpeg \
    poppler-utils
  msg_ok "Installed Dependencies"

  PG_VERSION="16" PG_MODULES="pgvector" setup_postgresql
  PG_DB_NAME="bookorbit" PG_DB_USER="bookorbit" PG_DB_EXTENSIONS="uuid-ossp,pg_trgm,vector" setup_postgresql_db
  NODE_VERSION="24" NODE_MODULE="corepack" setup_nodejs
  setup_uv

  fetch_and_deploy_gh_release "bookorbit" "bookorbit/bookorbit" "tarball"

  msg_info "Building Application"
  cd /opt/bookorbit || exit
  PNPM_VERSION=$(jq -r '.packageManager | ltrimstr("pnpm@")' /opt/bookorbit/package.json)

  $STD corepack prepare "pnpm@${PNPM_VERSION}" --activate
  $STD pnpm install --frozen-lockfile
  $STD pnpm --filter client run build-only
  $STD pnpm --filter server run build
  cp -r /opt/bookorbit/client/dist /opt/bookorbit/server/public
  mkdir -p /opt/bookorbit/server/migrations
  cp -r /opt/bookorbit/server/src/db/migrations/. /opt/bookorbit/server/migrations/
  chmod +x /opt/bookorbit/server/bin/kepubify/*
  msg_ok "Built Application"

  msg_info "Setting up Python Runtime"
  $STD uv venv /opt/bookorbit-python
  $STD uv pip install --python /opt/bookorbit-python/bin/python -r /opt/bookorbit/server/requirements/kobo-cloudscraper.txt
  msg_ok "Set up Python Runtime"

  msg_info "Configuring Application"
  mkdir -p /opt/bookorbit-data/covers /opt/bookorbit-data/book-bucket /opt/bookorbit-books
  APP_VER=$(cat ~/.bookorbit)
  JWT_SECRET=$(openssl rand -hex 32)
  SETUP_BOOTSTRAP_TOKEN=$(openssl rand -hex 16)
  cat << EOF > ~/bookorbit.creds

Setup Token: ${SETUP_BOOTSTRAP_TOKEN}
EOF
  cat << EOF > /opt/bookorbit/.env
NODE_ENV=production
PORT=3000
DATABASE_URL=postgres://${PG_DB_USER}:${PG_DB_PASS}@127.0.0.1:5432/${PG_DB_NAME}
JWT_SECRET=${JWT_SECRET}
SETUP_BOOTSTRAP_TOKEN=${SETUP_BOOTSTRAP_TOKEN}
APP_URL=http://${LOCAL_IP}:3000
CLIENT_URL=http://${LOCAL_IP}:3000
NODE_OPTIONS=--max-old-space-size=2048
APP_DATA_PATH=/opt/bookorbit-data
KOBO_CLOUDSCRAPER_PYTHON=/opt/bookorbit-python/bin/python
BOOK_DOCK_PATH=/opt/bookorbit-data/book-bucket
APP_VERSION=v${APP_VER}
EOF
  msg_ok "Configured Application"

  msg_info "Creating Service"
  cat << EOF > /etc/systemd/system/bookorbit.service
[Unit]
Description=BookOrbit Service
After=network.target postgresql.service
Requires=postgresql.service

[Service]
Type=simple
User=root
WorkingDirectory=/opt/bookorbit/server
EnvironmentFile=/opt/bookorbit/.env
ExecStartPre=/usr/bin/node /opt/bookorbit/server/dist/scripts/migrate.js
ExecStart=/usr/bin/node /opt/bookorbit/server/dist/main.js
Restart=on-failure
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF
  systemctl enable -q --now bookorbit
  msg_ok "Created Service"
}

function post_install_script() {
  msg_ok "Completed Successfully!\n"
  echo -e "${CREATING}${GN}${APP} setup has been successfully initialized!${CL}"
  echo -e "${INFO}${YW} Access it using the following URL:${CL}"
  echo -e "${TAB}${GATEWAY}${BGN}http://${IP}:3000${CL}"
  echo -e "${INFO}${YW} Setup Token is stored in ~/bookorbit.creds inside the container${CL}"
}

function update_script() {
  header_info
  check_container_storage
  check_container_resources

  if [[ ! -d /opt/bookorbit ]]; then
    msg_error "No ${APP} Installation Found!"
    exit
  fi

  NODE_VERSION="24" NODE_MODULE="corepack" setup_nodejs

  if check_for_gh_release "bookorbit" "bookorbit/bookorbit"; then
    msg_info "Stopping Service"
    systemctl stop bookorbit
    msg_ok "Stopped Service"

    create_backup /opt/bookorbit/.env

    CLEAN_INSTALL=1 fetch_and_deploy_gh_release "bookorbit" "bookorbit/bookorbit" "tarball"

    msg_info "Rebuilding Application"
    cd /opt/bookorbit || exit
    PNPM_VERSION=$(jq -r '.packageManager | ltrimstr("pnpm@")' /opt/bookorbit/package.json)

    $STD corepack prepare "pnpm@${PNPM_VERSION}" --activate
    $STD pnpm install --frozen-lockfile
    $STD pnpm --filter client run build-only
    $STD pnpm --filter server run build
    cp -r /opt/bookorbit/client/dist /opt/bookorbit/server/public
    mkdir -p /opt/bookorbit/server/migrations
    cp -r /opt/bookorbit/server/src/db/migrations/. /opt/bookorbit/server/migrations/
    chmod +x /opt/bookorbit/server/bin/kepubify/*
    restore_backup
    APP_VER=$(cat ~/.bookorbit)
    sed -i "s/^APP_VERSION=.*/APP_VERSION=v$APP_VER/" /opt/bookorbit/.env
    msg_ok "Rebuilt Application"

    msg_info "Updating Kobo Python Runtime"
    $STD uv pip install --python /opt/bookorbit-python/bin/python -r /opt/bookorbit/server/requirements/kobo-cloudscraper.txt
    msg_ok "Updated Kobo Python Runtime"

    msg_info "Starting Service"
    systemctl start bookorbit
    msg_ok "Started Service"
    msg_ok "Updated successfully!"
  fi
  exit
}

# shellcheck disable=SC1090
source <(curl -fsSL "$REPO_BASE/misc/bootstrap/lxc")
