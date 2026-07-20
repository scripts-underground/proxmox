#!/usr/bin/env bash
REPO_BASE="${REPO_BASE:-https://raw.githubusercontent.com/scripts-underground/proxmox/main}"

# Copyright (c) 2021-2026 community-scripts ORG
# Author: johanngrobe
# License: MIT | https://raw.githubusercontent.com/scripts-underground/proxmox/main/LICENSE
# Source: https://codeberg.org/endurain-project/endurain

# shellcheck disable=SC2034
APP="Endurain"
var_tags="${var_tags:-sport;social-media}"
var_cpu="${var_cpu:-2}"
var_ram="${var_ram:-4096}"
var_disk="${var_disk:-5}"
var_os="${var_os:-debian}"
var_version="${var_version:-13}"
var_arm64="${var_arm64:-yes}"
var_unprivileged="${var_unprivileged:-1}"

function install_script() {
  msg_info "Installing Dependencies"
  $STD apt install -y build-essential
  msg_ok "Installed Dependencies"

  PYTHON_VERSION="3.13" setup_uv
  NODE_VERSION="24" setup_nodejs
  PG_VERSION="17" PG_MODULES="postgis" setup_postgresql
  PG_DB_NAME="enduraindb" PG_DB_USER="endurain" setup_postgresql_db
  fetch_and_deploy_codeberg_release "endurain" "endurain-project/endurain" "tarball" "latest" "/opt/endurain"

  msg_info "Setting up Endurain"
  cd /opt/endurain || exit
  rm -rf \
    /opt/endurain/{docs,example.env,screenshot_01.png} \
    /opt/endurain/docker* \
    /opt/endurain/*.yml
  mkdir -p /opt/endurain_data/{data,logs}
  SECRET_KEY=$(openssl rand -hex 32)
  FERNET_KEY=$(openssl rand -base64 32)
  ENDURAIN_HOST=http://${LOCAL_IP}:8080
  cat << EOF > /opt/endurain/.env
DB_PASSWORD=${PG_DB_PASS}

SECRET_KEY=${SECRET_KEY}
FERNET_KEY=${FERNET_KEY}

TZ=Europe/Berlin
ENDURAIN_HOST=${ENDURAIN_HOST}
BEHIND_PROXY=false

POSTGRES_DB=${PG_DB_NAME}
POSTGRES_USER=${PG_DB_USER}
PGDATA=/var/lib/postgresql/${PG_DB_NAME}

DB_DATABASE=${PG_DB_NAME}
DB_USER=${PG_DB_USER}
DB_PORT=5432
DB_HOST=localhost

DATABASE_URL=postgresql+psycopg://${PG_DB_USER}:${PG_DB_PASS}@localhost:5432/${PG_DB_NAME}

BACKEND_DIR="/opt/endurain/backend/app"
FRONTEND_DIR="/opt/endurain/frontend/dist"
DATA_DIR="/opt/endurain_data/data"
LOGS_DIR="/opt/endurain_data/logs"

#SMTP_HOST=smtp.protonmail.ch
#SMTP_PORT=587
#SMTP_USERNAME=your-email@example.com
#SMTP_PASSWORD=your-app-password
#SMTP_SECURE=true
#SMTP_SECURE_TYPE=starttls
EOF
  msg_ok "Setup Endurain"

  msg_info "Building Frontend"
  cd /opt/endurain/frontend || exit
  $STD npm ci --prefer-offline
  $STD npm run build
  cat << EOF > /opt/endurain/frontend/dist/env.js
window.env = {
  ENDURAIN_HOST: "${ENDURAIN_HOST}"
}
EOF
  msg_ok "Built Frontend"

  msg_info "Setting up Backend"
  cd /opt/endurain/backend || exit
  UV_VERSION=$(grep -Po 'required-version\s*=\s*"\K[^"]+' pyproject.toml 2> /dev/null || echo "0.11.18")
  UV_VERSION="$UV_VERSION" setup_uv
  $STD uv sync --frozen --no-dev
  msg_ok "Setup Backend"

  msg_info "Creating Service"
  cat << EOF > /etc/systemd/system/endurain.service
[Unit]
Description=Endurain FastAPI Backend
After=network.target postgresql.service

[Service]
WorkingDirectory=/opt/endurain/backend/app
EnvironmentFile=/opt/endurain/.env
ExecStart=/opt/endurain/backend/.venv/bin/uvicorn main:app --host 0.0.0.0 --port 8080
Restart=always
RestartSec=5
User=root
StandardOutput=journal
StandardError=journal

[Install]
WantedBy=multi-user.target
EOF
  systemctl enable -q --now endurain
  msg_ok "Created Service"
}

function post_install_script() {
  msg_ok "Completed Successfully!\n"
  echo -e "${CREATING}${GN}${APP} setup has been successfully initialized!${CL}"
  echo -e "${INFO}${YW}Access it using the following URL:${CL}"
  echo -e "${GATEWAY}${BGN}http://${IP}:8080${CL}"
}

function update_script() {
  header_info
  check_container_storage
  check_container_resources

  if [[ ! -d /opt/endurain ]]; then
    msg_error "No ${APP} installation found!"
    exit
  fi
  if check_for_codeberg_release "endurain" "endurain-project/endurain"; then
    msg_info "Stopping Service"
    systemctl stop endurain
    msg_ok "Stopped Service"

    create_backup /opt/endurain/.env /opt/endurain/frontend/dist/env.js
    CLEAN_INSTALL=1 fetch_and_deploy_codeberg_release "endurain" "endurain-project/endurain" "tarball" "latest" "/opt/endurain"

    msg_info "Preparing Update"
    cd /opt/endurain || exit
    rm -rf /opt/endurain/{docs,example.env,screenshot_01.png} /opt/endurain/docker* /opt/endurain/*.yml
    msg_ok "Prepared Update"

    msg_info "Updating Frontend"
    cd /opt/endurain/frontend || exit
    $STD npm ci
    $STD npm run build
    msg_ok "Updated Frontend"

    restore_backup

    msg_info "Updating Backend"
    cd /opt/endurain/backend || exit
    UV_VERSION=$(grep -Po 'required-version\s*=\s*"\K[^"]+' pyproject.toml 2> /dev/null || echo "0.11.18")
    UV_VERSION="$UV_VERSION" setup_uv
    $STD uv sync --frozen --no-dev
    msg_ok "Backend Updated"

    msg_info "Starting Service"
    systemctl start endurain
    msg_ok "Started Service"
    msg_ok "Updated successfully!"
  fi
  exit
}

# shellcheck disable=SC1090
source <(curl -fsSL "$REPO_BASE/misc/bootstrap/lxc")
