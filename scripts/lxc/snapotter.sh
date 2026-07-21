#!/usr/bin/env bash
REPO_BASE="${REPO_BASE:-https://raw.githubusercontent.com/scripts-underground/proxmox/main}"

# Sourced by lxc.bootstrap — never executed directly
# Copyright (c) 2021-2026 community-scripts ORG
# Author: MickLesk (CanbiZ)
# License: MIT | https://raw.githubusercontent.com/scripts-underground/proxmox/main/LICENSE
# Source: https://snapotter.com

# shellcheck disable=SC2034
# Read by the framework - shellcheck cannot see the caller
APP="SnapOtter"
var_tags="${var_tags:-media;image}"
var_cpu="${var_cpu:-2}"
var_ram="${var_ram:-4096}"
var_disk="${var_disk:-20}"
var_os="${var_os:-debian}"
var_version="${var_version:-13}"
var_arm64="${var_arm64:-no}"
var_unprivileged="${var_unprivileged:-1}"

function install_script() {
  msg_info "Installing Dependencies"
  $STD apt install -y \
    imagemagick \
    ghostscript \
    potrace \
    libopenjp2-tools \
    libegl1 \
    libgl1 \
    libglib2.0-0 \
    libsm6 \
    libxext6 \
    libxrender1 \
    libwayland-client0 \
    libwayland-cursor0 \
    libwayland-egl1 \
    libxkbcommon0 \
    libxkbcommon-x11-0 \
    libxcursor1 \
    python3 \
    python3-dev \
    gcc \
    g++
  msg_ok "Installed Dependencies"

  PYTHON_VERSION="3.11" setup_uv
  NODE_VERSION="22" NODE_MODULE="pnpm" setup_nodejs
  PG_VERSION="17" setup_postgresql
  PG_DB_NAME="snapotter" PG_DB_USER="snapotter" setup_postgresql_db

  msg_info "Installing Redis"
  $STD apt install -y redis-server
  if grep -q '^appendonly ' /etc/redis/redis.conf; then
    sed -i 's/^appendonly .*/appendonly yes/' /etc/redis/redis.conf
  else
    echo 'appendonly yes' >> /etc/redis/redis.conf
  fi
  $STD systemctl enable --now redis-server
  msg_ok "Installed Redis"

  fetch_and_deploy_gh_release "caire" "esimov/caire" "prebuild" "latest" "/usr/local/bin" "caire-*-linux-amd64.tar.gz"
  fetch_and_deploy_gh_release "snapotter" "snapotter-hq/SnapOtter" "prebuild" "latest" "/opt/snapotter" "snapotter-*-linux-amd64.tar.gz"

  msg_info "Setting up Python Environment"
  mkdir -p /opt/snapotter_data/ai/models/rembg
  $STD uv python install 3.11
  $STD uv venv --seed --python 3.11 /opt/snapotter_data/ai/venv
  ln -sfn /opt/snapotter /app
  msg_ok "Set up Python Environment"

  msg_info "Configuring SnapOtter"
  mkdir -p /opt/snapotter_data/files
  mkdir -p /tmp/snapotter-workspace

  cat << EOF > /opt/snapotter_data/.env
PORT=1349
NODE_ENV=production
DATABASE_URL=postgres://${PG_DB_USER}:${PG_DB_PASS}@127.0.0.1:5432/${PG_DB_NAME}
REDIS_URL=redis://127.0.0.1:6379
WORKSPACE_PATH=/tmp/snapotter-workspace
FILES_STORAGE_PATH=/opt/snapotter_data/files
PYTHON_VENV_PATH=/opt/snapotter_data/ai/venv
MODELS_PATH=/opt/snapotter_data/ai/models
DATA_DIR=/opt/snapotter_data
FEATURE_MANIFEST_PATH=/opt/snapotter/docker/feature-manifest.json
U2NET_HOME=/opt/snapotter_data/ai/models/rembg
AUTH_ENABLED=true
DEFAULT_USERNAME=admin
DEFAULT_PASSWORD=admin
LOG_LEVEL=info
TRUST_PROXY=true
FILE_MAX_AGE_HOURS=72
CLEANUP_INTERVAL_MINUTES=60
ANALYTICS_ENABLED=false
EOF
  msg_ok "Configured SnapOtter"

  msg_info "Creating Service"
  PNPM_BIN="$(command -v pnpm)"
  cat << EOF > /etc/systemd/system/snapotter.service
[Unit]
Description=SnapOtter Service
Wants=network-online.target
After=network-online.target postgresql.service redis-server.service
Requires=postgresql.service redis-server.service

[Service]
Type=simple
User=root
WorkingDirectory=/opt/snapotter
EnvironmentFile=/opt/snapotter_data/.env
ExecStart=${PNPM_BIN} --filter @snapotter/api run start
Restart=on-failure
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF
  systemctl daemon-reload
  systemctl enable -q --now snapotter
  msg_ok "Created Service"
}

function post_install_script() {
  msg_ok "Completed Successfully!\n"
  echo -e "${CREATING}${GN}${APP} setup has been successfully initialized!${CL}"
  echo -e "${INFO}${YW}Access it using the following URL:${CL}"
  echo -e "${GATEWAY}${BGN}http://${IP}:1349${CL}"
}

function update_script() {
  header_info
  check_container_storage
  check_container_resources

  if [[ ! -d /opt/snapotter ]]; then
    msg_error "No ${APP} Installation Found!"
    exit
  fi

  NEEDS_V2_MIGRATION=false
  grep -q '^DB_PATH=' /opt/snapotter_data/.env 2> /dev/null && NEEDS_V2_MIGRATION=true
  UPDATE_AVAILABLE=false
  check_for_gh_release "snapotter" "snapotter-hq/SnapOtter" && UPDATE_AVAILABLE=true

  if [[ "$NEEDS_V2_MIGRATION" == true || "$UPDATE_AVAILABLE" == true ]]; then
    msg_info "Stopping Service"
    systemctl stop snapotter
    msg_ok "Stopped Service"

    PG_VERSION="17" setup_postgresql
    if ! sudo -u postgres psql -tAc "SELECT 1 FROM pg_database WHERE datname = 'snapotter'" | grep -qx '1'; then
      PG_DB_NAME="snapotter" PG_DB_USER="snapotter" setup_postgresql_db
    else
      PG_DB_NAME="snapotter"
      PG_DB_USER="snapotter"
      PG_DB_PASS=$(sed -n 's|^DATABASE_URL=postgres://snapotter:\([^@]*\)@.*|\1|p' /opt/snapotter_data/.env | head -n1)
      if [[ -z "$PG_DB_PASS" ]]; then
        msg_error "SnapOtter's PostgreSQL database exists, but its password is not available in /opt/snapotter_data/.env"
        exit 1
      fi
    fi

    msg_info "Installing Redis"
    $STD apt install -y redis-server
    if grep -q '^appendonly ' /etc/redis/redis.conf; then
      sed -i 's/^appendonly .*/appendonly yes/' /etc/redis/redis.conf
    else
      echo 'appendonly yes' >> /etc/redis/redis.conf
    fi
    $STD systemctl enable --now redis-server
    msg_ok "Installed Redis"

    msg_info "Migrating SnapOtter Configuration"
    sed -i '/^DB_PATH=/d; /^DATABASE_URL=/d; /^REDIS_URL=/d; /^SQLITE_MIGRATE_PATH=/d' /opt/snapotter_data/.env
    cat << EOF >> /opt/snapotter_data/.env
DATABASE_URL=postgres://${PG_DB_USER}:${PG_DB_PASS}@127.0.0.1:5432/${PG_DB_NAME}
REDIS_URL=redis://127.0.0.1:6379
EOF
    if [[ -f /opt/snapotter_data/snapotter.db ]]; then
      echo 'SQLITE_MIGRATE_PATH=/opt/snapotter_data/snapotter.db' >> /opt/snapotter_data/.env
    fi
    if ! grep -q '^Requires=postgresql.service redis-server.service$' /etc/systemd/system/snapotter.service; then
      sed -i '/^After=/c\After=network-online.target postgresql.service redis-server.service' /etc/systemd/system/snapotter.service
      sed -i '/^\[Unit\]/a Wants=network-online.target\nRequires=postgresql.service redis-server.service' /etc/systemd/system/snapotter.service
    fi
    systemctl daemon-reload
    msg_ok "Migrated SnapOtter Configuration"

    if [[ "$UPDATE_AVAILABLE" == true ]]; then
      CLEAN_INSTALL=1 fetch_and_deploy_gh_release "snapotter" "snapotter-hq/SnapOtter" "prebuild" "latest" "/opt/snapotter" "snapotter-*-linux-amd64.tar.gz"
    fi

    msg_info "Updating SnapOtter"
    $STD uv python install 3.11
    $STD uv venv --seed --python 3.11 /opt/snapotter_data/ai/venv
    ln -sfn /opt/snapotter /app
    msg_ok "Updated SnapOtter"

    msg_info "Starting Service"
    systemctl start snapotter
    msg_ok "Started Service"
    msg_ok "Updated successfully!"
  fi
  exit
}

# framework bootstrap
# shellcheck disable=SC1090
# Dynamic URL resolved at runtime - shellcheck cannot follow
source <(curl -fsSL "$REPO_BASE/misc/bootstrap/lxc")
