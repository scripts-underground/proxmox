#!/usr/bin/env bash
REPO_BASE="${REPO_BASE:-https://raw.githubusercontent.com/scripts-underground/proxmox/main}"

# Copyright (c) 2021-2026 community-scripts ORG
# Author: MickLesk (CanbiZ)
# License: MIT | https://raw.githubusercontent.com/scripts-underground/proxmox/main/LICENSE
# Source: https://github.com/baserow/baserow

APP="Baserow"
var_tags="${var_tags:-database;nocode;spreadsheet}"
var_cpu="${var_cpu:-4}"
var_ram="${var_ram:-8192}"
var_disk="${var_disk:-15}"
var_os="${var_os:-debian}"
var_version="${var_version:-13}"
var_arm64="${var_arm64:-no}"
var_unprivileged="${var_unprivileged:-1}"

function install_script() {
  msg_info "Installing Dependencies"
  $STD apt install -y \
    build-essential \
    libpq-dev \
    redis-server \
    gettext \
    xmlsec1 \
    git \
    libffi-dev \
    libssl-dev \
    zlib1g-dev \
    libjpeg-dev \
    libxml2-dev \
    libxslt-dev \
    python3-dev
  msg_ok "Installed Dependencies"

  PG_VERSION="16" PG_MODULES="pgvector" setup_postgresql
  PG_DB_NAME="baserow" PG_DB_USER="baserow" setup_postgresql_db
  NODE_VERSION="24" setup_nodejs
  setup_uv

  fetch_and_deploy_gh_release "baserow" "baserow/baserow" "tarball"

  msg_info "Installing Backend Dependencies"
  cd /opt/baserow/backend
  UV_LINK_MODE="copy"
  $STD uv sync --frozen --no-dev
  msg_ok "Installed Backend Dependencies"

  msg_info "Building Frontend"
  cd /opt/baserow/web-frontend
  NODE_OPTIONS="--max-old-space-size=4096" $STD npm install --legacy-peer-deps
  NODE_OPTIONS="--max-old-space-size=4096" $STD npm run build
  msg_ok "Built Frontend"

  msg_info "Configuring Baserow"
  SECRET_KEY=$(openssl rand -base64 64 | tr -dc 'a-zA-Z0-9' | head -c50)
  cat << EOF > /opt/baserow/.env
DATABASE_HOST=localhost
DATABASE_PORT=5432
DATABASE_NAME=${PG_DB_NAME}
DATABASE_USER=${PG_DB_USER}
DATABASE_PASSWORD=${PG_DB_PASS}
SECRET_KEY=${SECRET_KEY}
BASEROW_JWT_SIGNING_KEY=${SECRET_KEY}
REDIS_HOST=localhost
REDIS_PORT=6379
REDIS_PASSWORD=
REDIS_PROTOCOL=redis
BASEROW_PUBLIC_URL=http://${LOCAL_IP}
PUBLIC_BACKEND_URL=http://${LOCAL_IP}:8000
PUBLIC_WEB_FRONTEND_URL=http://${LOCAL_IP}:3000
PRIVATE_BACKEND_URL=http://localhost:8000
PRIVATE_WEB_FRONTEND_URL=http://localhost:3000
BASEROW_DISABLE_PUBLIC_URL_CHECK=true
DJANGO_SETTINGS_MODULE=baserow.config.settings.base
BASEROW_AMOUNT_OF_WORKERS=2
MEDIA_ROOT=/opt/baserow/media
EOF
  mkdir -p /opt/baserow/media
  msg_ok "Configured Baserow"

  msg_info "Running Migrations"
  cd /opt/baserow/backend
  set -a && source /opt/baserow/.env && set +a
  export PYTHONPATH="/opt/baserow/backend/src:/opt/baserow/premium/backend/src:/opt/baserow/enterprise/backend/src"
  $STD /opt/baserow/backend/.venv/bin/python src/baserow/manage.py migrate
  $STD /opt/baserow/backend/.venv/bin/python src/baserow/manage.py sync_templates
  msg_ok "Ran Migrations"

  msg_info "Creating Services"
  cat << EOF > /etc/systemd/system/baserow-backend.service
[Unit]
Description=Baserow Backend
After=network.target postgresql.service redis-server.service
Requires=postgresql.service redis-server.service

[Service]
Type=simple
User=root
WorkingDirectory=/opt/baserow/backend
EnvironmentFile=/opt/baserow/.env
Environment=PYTHONPATH=/opt/baserow/backend/src:/opt/baserow/premium/backend/src:/opt/baserow/enterprise/backend/src
ExecStart=/opt/baserow/backend/.venv/bin/gunicorn baserow.config.asgi:application -w 2 -k uvicorn.workers.UvicornWorker -b 0.0.0.0:8000
Restart=on-failure
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF

  cat << EOF > /etc/systemd/system/baserow-celery.service
[Unit]
Description=Baserow Celery Worker
After=network.target postgresql.service redis-server.service
Requires=postgresql.service redis-server.service

[Service]
Type=simple
User=root
WorkingDirectory=/opt/baserow/backend
EnvironmentFile=/opt/baserow/.env
Environment=PYTHONPATH=/opt/baserow/backend/src:/opt/baserow/premium/backend/src:/opt/baserow/enterprise/backend/src
ExecStart=/opt/baserow/backend/.venv/bin/celery -A baserow worker -l INFO
Restart=on-failure
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF

  cat << EOF > /etc/systemd/system/baserow-celery-export.service
[Unit]
Description=Baserow Celery Export Worker
After=network.target postgresql.service redis-server.service
Requires=postgresql.service redis-server.service

[Service]
Type=simple
User=root
WorkingDirectory=/opt/baserow/backend
EnvironmentFile=/opt/baserow/.env
Environment=PYTHONPATH=/opt/baserow/backend/src:/opt/baserow/premium/backend/src:/opt/baserow/enterprise/backend/src
ExecStart=/opt/baserow/backend/.venv/bin/celery -A baserow worker -l INFO -Q export
Restart=on-failure
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF

  cat << EOF > /etc/systemd/system/baserow-celery-beat.service
[Unit]
Description=Baserow Celery Beat Scheduler
After=network.target postgresql.service redis-server.service
Requires=postgresql.service redis-server.service

[Service]
Type=simple
User=root
WorkingDirectory=/opt/baserow/backend
EnvironmentFile=/opt/baserow/.env
Environment=PYTHONPATH=/opt/baserow/backend/src:/opt/baserow/premium/backend/src:/opt/baserow/enterprise/backend/src
ExecStart=/opt/baserow/backend/.venv/bin/celery -A baserow beat -l INFO -S redbeat.RedBeatScheduler
Restart=on-failure
RestartSec=5
KillSignal=SIGQUIT

[Install]
WantedBy=multi-target.target
EOF

  cat << EOF > /etc/systemd/system/baserow-frontend.service
[Unit]
Description=Baserow Web Frontend
After=network.target baserow-backend.service

[Service]
Type=simple
User=root
WorkingDirectory=/opt/baserow/web-frontend
EnvironmentFile=/opt/baserow/.env
Environment=HOST=0.0.0.0
Environment=PORT=3000
ExecStart=/usr/bin/node --import ./env-remap.mjs .output/server/index.mjs
Restart=on-failure
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF

  systemctl enable -q --now redis-server baserow-backend baserow-celery baserow-celery-export baserow-celery-beat baserow-frontend
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

  if [[ ! -d /opt/baserow ]]; then
    msg_error "No ${APP} Installation Found!"
    exit
  fi

  if check_for_gh_release "baserow" "baserow/baserow"; then
    msg_info "Stopping Services"
    systemctl stop baserow-backend baserow-celery baserow-celery-beat baserow-celery-export baserow-frontend
    msg_ok "Stopped Services"

    msg_info "Backing up Data"
    cp /opt/baserow/.env /opt/baserow.env.bak
    msg_ok "Backed up Data"

    CLEAN_INSTALL=1 fetch_and_deploy_gh_release "baserow" "baserow/baserow" "tarball"

    msg_info "Restoring Configuration"
    cp /opt/baserow.env.bak /opt/baserow/.env
    rm -f /opt/baserow.env.bak
    msg_ok "Restored Configuration"

    msg_info "Updating Backend Dependencies"
    cd /opt/baserow/backend
    $STD uv sync --frozen --no-dev
    msg_ok "Updated Backend Dependencies"

    msg_info "Updating Frontend"
    cd /opt/baserow/web-frontend
    $STD npm install
    $STD npm run build
    msg_ok "Updated Frontend"

    msg_info "Running Migrations"
    cd /opt/baserow/backend
    set -a && source /opt/baserow/.env && set +a
    export PYTHONPATH="/opt/baserow/backend/src:/opt/baserow/premium/backend/src:/opt/baserow/enterprise/backend/src"
    $STD /opt/baserow/backend/.venv/bin/python src/baserow/manage.py migrate
    msg_ok "Ran Migrations"

    msg_info "Starting Services"
    systemctl start baserow-backend baserow-celery baserow-celery-beat baserow-celery-export baserow-frontend
    msg_ok "Started Services"
    msg_ok "Updated successfully!"
  fi
  exit
}

# framework bootstrap
source <(curl -fsSL "$REPO_BASE/misc/bootstrap/lxc")
