#!/usr/bin/env bash
REPO_BASE="${REPO_BASE:-https://raw.githubusercontent.com/scripts-underground/proxmox/main}"

# Copyright (c) 2021-2026 community-scripts ORG
# Author: MickLesk (CanbiZ)
# License: MIT | https://raw.githubusercontent.com/scripts-underground/proxmox/main/LICENSE
# Source: https://github.com/danny-avila/LibreChat

APP="LibreChat"
var_tags="${var_tags:-ai;chat}"
var_cpu="${var_cpu:-4}"
var_ram="${var_ram:-6144}"
var_disk="${var_disk:-20}"
var_os="${var_os:-debian}"
var_version="${var_version:-13}"
var_arm64="${var_arm64:-yes}"
var_unprivileged="${var_unprivileged:-1}"

function install_script() {
  MONGO_VERSION="8.0" setup_mongodb
  setup_meilisearch
  PG_VERSION="17" PG_MODULES="pgvector" setup_postgresql
  PG_DB_NAME="ragapi" PG_DB_USER="ragapi" PG_DB_EXTENSIONS="vector" setup_postgresql_db
  NODE_VERSION="24" setup_nodejs
  UV_PYTHON="3.12" setup_uv

  fetch_and_deploy_gh_tag "librechat" "danny-avila/LibreChat"
  fetch_and_deploy_gh_release "rag-api" "danny-avila/rag_api" "tarball"

  msg_info "Installing LibreChat Dependencies"
  cd /opt/librechat || exit
  $STD npm ci
  msg_ok "Installed LibreChat Dependencies"

  msg_info "Building Frontend"
  $STD npm run frontend
  $STD npm prune --production
  $STD npm cache clean --force
  msg_ok "Built Frontend"

  msg_info "Installing RAG API Dependencies"
  cd /opt/rag-api || exit
  $STD uv venv --python 3.12 --seed .venv
  $STD .venv/bin/pip install -r requirements.lite.txt
  mkdir -p /opt/rag-api/uploads
  msg_ok "Installed RAG API Dependencies"

  msg_info "Configuring LibreChat"
  JWT_SECRET=$(openssl rand -hex 32)
  JWT_REFRESH_SECRET=$(openssl rand -hex 32)
  CREDS_KEY=$(openssl rand -hex 32)
  CREDS_IV=$(openssl rand -hex 16)
  cat << EOF > /opt/librechat/.env
HOST=0.0.0.0
PORT=3080
MONGO_URI=mongodb://127.0.0.1:27017/LibreChat
DOMAIN_CLIENT=http://${LOCAL_IP}:3080
DOMAIN_SERVER=http://${LOCAL_IP}:3080
NO_INDEX=true
TRUST_PROXY=1
JWT_SECRET=${JWT_SECRET}
JWT_REFRESH_SECRET=${JWT_REFRESH_SECRET}
SESSION_EXPIRY=1000 * 60 * 15
REFRESH_TOKEN_EXPIRY=(1000 * 60 * 60 * 24) * 7
CREDS_KEY=${CREDS_KEY}
CREDS_IV=${CREDS_IV}
ALLOW_EMAIL_LOGIN=true
ALLOW_REGISTRATION=true
ALLOW_SOCIAL_LOGIN=false
ALLOW_SOCIAL_REGISTRATION=false
ALLOW_PASSWORD_RESET=false
ALLOW_UNVERIFIED_EMAIL_LOGIN=true
SEARCH=true
MEILI_NO_ANALYTICS=true
MEILI_HOST=http://127.0.0.1:7700
MEILI_MASTER_KEY=${MEILISEARCH_MASTER_KEY}
RAG_PORT=8000
RAG_API_URL=http://127.0.0.1:8000
APP_TITLE=LibreChat
ENDPOINTS=openAI,agents,assistants,anthropic,google
# OPENAI_API_KEY=your-key-here
# OPENAI_MODELS=
# ANTHROPIC_API_KEY=your-key-here
# GOOGLE_KEY=your-key-here
EOF
  msg_ok "Configured LibreChat"

  msg_info "Configuring RAG API"
  cat << EOF > /opt/rag-api/.env
VECTOR_DB_TYPE=pgvector
DB_HOST=127.0.0.1
DB_PORT=5432
POSTGRES_DB=${PG_DB_NAME}
POSTGRES_USER=${PG_DB_USER}
POSTGRES_PASSWORD=${PG_DB_PASS}
RAG_HOST=0.0.0.0
RAG_PORT=8000
JWT_SECRET=${JWT_SECRET}
RAG_UPLOAD_DIR=/opt/rag-api/uploads/
EOF
  msg_ok "Configured RAG API"

  msg_info "Creating Services"
  cat << EOF > /etc/systemd/system/librechat.service
[Unit]
Description=LibreChat
After=network.target mongod.service meilisearch.service rag-api.service

[Service]
Type=simple
User=root
WorkingDirectory=/opt/librechat
EnvironmentFile=/opt/librechat/.env
ExecStart=/usr/bin/npm run backend
Restart=on-failure
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF
  cat << EOF > /etc/systemd/system/rag-api.service
[Unit]
Description=LibreChat RAG API
After=network.target postgresql.service

[Service]
Type=simple
User=root
WorkingDirectory=/opt/rag-api
EnvironmentFile=/opt/rag-api/.env
ExecStart=/opt/rag-api/.venv/bin/uvicorn main:app --host 0.0.0.0 --port 8000
Restart=on-failure
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF
  systemctl enable -q --now rag-api librechat
  msg_ok "Created Services"
}

function post_install_script() {
  msg_ok "Completed Successfully!\n"
  echo -e "${CREATING}${GN}${APP} setup has been successfully initialized!${CL}"
  echo -e "${INFO}${YW} Access it using the following URL:${CL}"
  echo -e "${TAB}${GATEWAY}${BGN}http://${IP}:3080${CL}"
}

function update_script() {
  header_info
  check_container_storage
  check_container_resources

  if [[ ! -d /opt/librechat ]]; then
    msg_error "No ${APP} Installation Found!"
    exit
  fi

  if check_for_gh_tag "librechat" "danny-avila/LibreChat" "v"; then
    msg_info "Stopping Services"
    systemctl stop librechat rag-api
    msg_ok "Stopped Services"

    msg_info "Backing up Configuration"
    cp /opt/librechat/.env /opt/librechat.env.bak
    msg_ok "Backed up Configuration"

    CLEAN_INSTALL=1 fetch_and_deploy_gh_tag "librechat" "danny-avila/LibreChat"

    msg_info "Installing Dependencies"
    cd /opt/librechat || exit
    $STD npm ci
    msg_ok "Installed Dependencies"

    msg_info "Building Frontend"
    $STD npm run frontend
    $STD npm prune --production
    $STD npm cache clean --force
    msg_ok "Built Frontend"

    msg_info "Restoring Configuration"
    cp /opt/librechat.env.bak /opt/librechat/.env
    rm -f /opt/librechat.env.bak
    msg_ok "Restored Configuration"

    msg_info "Starting Services"
    systemctl start rag-api librechat
    msg_ok "Started Services"
    msg_ok "Updated LibreChat Successfully!"
  fi

  if check_for_gh_release "rag-api" "danny-avila/rag_api"; then
    msg_info "Stopping RAG API"
    systemctl stop rag-api
    msg_ok "Stopped RAG API"

    msg_info "Backing up RAG API Configuration"
    cp /opt/rag-api/.env /opt/rag-api.env.bak
    msg_ok "Backed up RAG API Configuration"

    CLEAN_INSTALL=1 fetch_and_deploy_gh_release "rag-api" "danny-avila/rag_api" "tarball"

    msg_info "Updating RAG API Dependencies"
    cd /opt/rag-api || exit
    $STD .venv/bin/pip install -r requirements.lite.txt
    msg_ok "Updated RAG API Dependencies"

    msg_info "Restoring RAG API Configuration"
    cp /opt/rag-api.env.bak /opt/rag-api/.env
    rm -f /opt/rag-api.env.bak
    msg_ok "Restored RAG API Configuration"

    msg_info "Starting RAG API"
    systemctl start rag-api
    msg_ok "Started RAG API"
    msg_ok "Updated RAG API Successfully!"
  fi
  exit
}

# shellcheck disable=SC1090
source <(curl -fsSL "$REPO_BASE/misc/bootstrap/lxc")
