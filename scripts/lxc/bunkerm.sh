#!/usr/bin/env bash
REPO_BASE="${REPO_BASE:-https://raw.githubusercontent.com/scripts-underground/proxmox/main}"

# Copyright (c) 2021-2026 community-scripts ORG
# Author: MickLesk (CanbiZ)
# License: MIT | https://raw.githubusercontent.com/scripts-underground/proxmox/main/LICENSE
# Source: https://bunkerai.dev/

# shellcheck disable=SC2034
# Read by the framework - shellcheck cannot see the caller
APP="BunkerM"
var_tags="${var_tags:-mqtt;iot;mosquitto}"
var_cpu="${var_cpu:-2}"
var_ram="${var_ram:-2048}"
var_disk="${var_disk:-8}"
var_os="${var_os:-debian}"
var_version="${var_version:-13}"
var_arm64="${var_arm64:-no}"
var_unprivileged="${var_unprivileged:-1}"

function install_script() {
  msg_info "Installing Dependencies"
  $STD apt install -y \
    build-essential \
    mosquitto \
    mosquitto-clients \
    libmosquitto-dev \
    nginx \
    supervisor \
    python3 \
    python3-dev \
    python3-venv \
    python3-pip \
    libffi-dev \
    libssl-dev \
    gcc \
    openssl
  msg_ok "Installed Dependencies"

  NODE_VERSION="20" setup_nodejs

  fetch_and_deploy_gh_release "bunkerm" "bunkeriot/BunkerM" "tarball"

  msg_info "Setting up Python Environment"
  python3 -m venv /opt/venv
  /opt/venv/bin/pip install --upgrade pip > /dev/null 2>&1
  $STD /opt/venv/bin/pip install --no-cache-dir \
    psutil \
    paho-mqtt \
    fastapi \
    python-dotenv \
    pydantic \
    pydantic-settings \
    "uvicorn[standard]" \
    flask \
    flask-cors \
    pytz \
    statistics \
    python-multipart \
    "passlib[bcrypt]" \
    python-jwt \
    PyJWT \
    slowapi \
    secure \
    python-decouple \
    starlette-context \
    structlog \
    python-json-logger \
    aiofiles \
    types-aiofiles \
    typing-extensions \
    "sqlalchemy[asyncio]>=2.0.30" \
    "aiosqlite>=0.20.0" \
    "alembic>=1.13.0" \
    "httpx>=0.27.0" \
    "numpy>=1.26.0" \
    "websockets>=12.0" \
    "apscheduler>=3.10.0" \
    cryptography \
    pyOpenSSL \
    "python-jose[cryptography]" \
    fastapi-jwt-auth \
    fastapi-limiter
  msg_ok "Set up Python Environment"

  msg_info "Building Frontend"
  cd /opt/bunkerm/frontend || exit
  rm -f package-lock.json
  export NODE_OPTIONS="--max-old-space-size=4096"
  $STD npm install
  AUTH_SECRET="build-time-placeholder" NEXT_TELEMETRY_DISABLED=1 $STD npm run build
  unset NODE_OPTIONS
  mkdir -p /nextjs
  cp -r /opt/bunkerm/frontend/.next/standalone/. /nextjs/
  cp -r /opt/bunkerm/frontend/.next/static /nextjs/.next/static
  cp -r /opt/bunkerm/frontend/public /nextjs/public
  msg_ok "Built Frontend"

  msg_info "Setting up Application"
  mkdir -p /app
  cp -r /opt/bunkerm/backend/app/. /app/
  touch /app/monitor/__init__.py
  msg_ok "Set up Application"

  msg_info "Configuring Mosquitto"
  mkdir -p /etc/mosquitto/conf.d /var/lib/mosquitto/db /var/log/mosquitto /tmp/mosquitto_backups /tmp/dynsec_backups
  cp /opt/bunkerm/backend/mosquitto/config/mosquitto.conf /etc/mosquitto/mosquitto.conf
  cp -r /opt/bunkerm/backend/etc/mosquitto/conf.d/. /etc/mosquitto/conf.d/
  cp /opt/bunkerm/backend/mosquitto/dynsec/dynamic-security.json /var/lib/mosquitto/dynamic-security.json
  touch /etc/mosquitto/mosquitto_passwd
  id -u mosquitto &> /dev/null || useradd -r -s /usr/sbin/nologin mosquitto
  chown -R mosquitto:mosquitto /var/lib/mosquitto /var/log/mosquitto /etc/mosquitto
  chmod 664 /etc/mosquitto/mosquitto_passwd
  msg_ok "Configured Mosquitto"

  msg_info "Configuring Nginx"
  mkdir -p /run/nginx /etc/nginx/conf.d /var/log/nginx /var/lib/history
  cp /opt/bunkerm/nginx.conf /etc/nginx/nginx.conf
  cp /opt/bunkerm/default-next.conf /etc/nginx/conf.d/default.conf
  msg_ok "Configured Nginx"

  msg_info "Configuring Supervisor"
  mkdir -p /var/log/supervisor /var/log/api /etc/bunkerm /nextjs/data
  cp /opt/bunkerm/supervisord-next.conf /etc/supervisor/conf.d/bunkerm.conf
  msg_ok "Configured Supervisor"

  msg_info "Creating Environment"
  MQTT_USERNAME="bunker"
  MQTT_PASSWORD="bunker"
  JWT_SECRET=$(openssl rand -base64 48 | tr -dc 'a-zA-Z0-9' | cut -c1-48)
  API_KEY=$(openssl rand -base64 48 | tr -dc 'a-zA-Z0-9' | cut -c1-48)
  AUTH_SECRET=$(openssl rand -base64 48 | tr -dc 'a-zA-Z0-9' | cut -c1-48)
  cat << EOF > /etc/bunkerm/bunkerm.env
MQTT_BROKER=localhost
MQTT_PORT=1900
MQTT_USERNAME=${MQTT_USERNAME}
MQTT_PASSWORD=${MQTT_PASSWORD}
JWT_SECRET=${JWT_SECRET}
API_KEY=${API_KEY}
AUTH_SECRET=${AUTH_SECRET}
HOST_ADDRESS=${LOCAL_IP}
FRONTEND_URL=http://${LOCAL_IP}:2000
ALLOWED_ORIGINS=*
ALLOWED_HOSTS=*
RATE_LIMIT_PER_MINUTE=100
LOG_LEVEL=INFO
API_LOG_FILE=/var/log/api/api_activity.log
BROKER_LOG_PATH=/var/log/mosquitto/mosquitto.log
CLIENT_LOG_PATH=/var/log/api/api_activity.log
MOSQUITTO_PASSWD_PATH=/etc/mosquitto/mosquitto_passwd
MOSQUITTO_CONF_PATH=/etc/mosquitto/mosquitto.conf
MOSQUITTO_BACKUP_DIR=/tmp/mosquitto_backups
CONFIG_API_PORT=1005
DYNSEC_PATH=/var/lib/mosquitto/dynamic-security.json
DYNSEC_BACKUP_DIR=/tmp/dynsec_backups
MAX_UPLOAD_SIZE=10485760
PYTHONPATH=/app/monitor
NODE_ENV=production
BUNKERAI_API_KEY=
BUNKERAI_WS_URL=wss://api.bunkerai.dev/connect
EOF
  msg_ok "Created Environment"

  msg_info "Creating Service"
  cat << EOF > /etc/systemd/system/bunkerm.service
[Unit]
Description=BunkerM MQTT Management Platform
After=network.target

[Service]
Type=simple
User=root
EnvironmentFile=/etc/bunkerm/bunkerm.env
ExecStart=/usr/bin/supervisord -c /etc/supervisor/conf.d/bunkerm.conf -n
Restart=on-failure
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF
  systemctl enable -q --now bunkerm
  msg_ok "Created Service"
}

function post_install_script() {
  msg_ok "Completed Successfully!\n"
  echo -e "${CREATING}${GN}${APP} setup has been successfully initialized!${CL}"
  echo -e "${INFO}${YW} Access it using the following URLs:${CL}"
  echo -e "${TAB}${GATEWAY}${BGN}http://${IP}:2000${CL} (Web UI)"
  echo -e "${TAB}${GATEWAY}${BGN}mqtt://${IP}:1900${CL} (MQTT Broker)"
}

function update_script() {
  header_info
  check_container_storage
  check_container_resources

  if [[ ! -d /opt/bunkerm ]]; then
    msg_error "No ${APP} Installation Found!"
    exit
  fi

  if check_for_gh_release "bunkerm" "bunkeriot/BunkerM"; then
    msg_info "Stopping Services"
    systemctl stop bunkerm
    msg_ok "Stopped Services"

    msg_info "Backing up Data"
    cp /etc/bunkerm/bunkerm.env /opt/bunkerm.env.bak
    cp /var/lib/mosquitto/dynamic-security.json /opt/bunkerm.dynsec.bak 2> /dev/null || true
    msg_ok "Backed up Data"

    CLEAN_INSTALL=1 fetch_and_deploy_gh_release "bunkerm" "bunkeriot/BunkerM" "tarball"

    msg_info "Rebuilding Frontend"
    cd /opt/bunkerm/frontend || exit
    export NODE_OPTIONS="--max-old-space-size=4096"
    NODE_ENV=development $STD npm ci
    AUTH_SECRET="build-time-placeholder" NEXT_TELEMETRY_DISABLED=1 $STD npm run build
    unset NODE_OPTIONS
    mkdir -p /nextjs
    cp -r /opt/bunkerm/frontend/.next/standalone/. /nextjs/
    cp -r /opt/bunkerm/frontend/.next/static /nextjs/.next/static
    cp -r /opt/bunkerm/frontend/public /nextjs/public
    msg_ok "Rebuilt Frontend"

    msg_info "Updating Backend"
    mkdir -p /app
    cp -r /opt/bunkerm/backend/app/. /app/
    touch /app/monitor/__init__.py
    msg_ok "Updated Backend"

    msg_info "Restoring Data"
    cp /opt/bunkerm.env.bak /etc/bunkerm/bunkerm.env
    cp /opt/bunkerm.dynsec.bak /var/lib/mosquitto/dynamic-security.json 2> /dev/null || true
    rm -f /opt/bunkerm.env.bak /opt/bunkerm.dynsec.bak
    msg_ok "Restored Data"

    msg_info "Starting Services"
    systemctl start bunkerm
    msg_ok "Started Services"
    msg_ok "Updated successfully!"
  fi
  exit
}

# framework bootstrap
# shellcheck disable=SC1090
# Dynamic URL resolved at runtime - shellcheck cannot follow
source <(curl -fsSL "$REPO_BASE/misc/bootstrap/lxc")

