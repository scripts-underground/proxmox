#!/usr/bin/env bash
REPO_BASE="${REPO_BASE:-https://raw.githubusercontent.com/scripts-underground/proxmox/main}"

# Sourced by lxc.bootstrap — never executed directly
# Copyright (c) 2021-2026 community-scripts ORG
# Author: MickLesk (CanbiZ)
# License: MIT | https://raw.githubusercontent.com/scripts-underground/proxmox/main/LICENSE
# Source: https://www.grampsweb.org/ | Github: https://github.com/gramps-project/gramps-web

# shellcheck disable=SC2034
# Read by the framework - shellcheck cannot see the caller
APP="gramps-web"
var_tags="${var_tags:-genealogy;family;collaboration}"
var_cpu="${var_cpu:-2}"
var_ram="${var_ram:-4096}"
var_disk="${var_disk:-20}"
var_os="${var_os:-debian}"
var_version="${var_version:-13}"
var_arm64="${var_arm64:-yes}"
var_unprivileged="${var_unprivileged:-1}"

function install_script() {
  msg_info "Installing Dependencies"
  $STD apt install -y \
    appstream \
    build-essential \
    ffmpeg \
    gettext \
    gobject-introspection \
    gir1.2-gexiv2-0.10 \
    gir1.2-gtk-3.0 \
    gir1.2-osmgpsmap-1.0 \
    gir1.2-pango-1.0 \
    git \
    graphviz \
    libcairo2-dev \
    libgirepository1.0-dev \
    libglib2.0-dev \
    libicu-dev \
    libopencv-dev \
    pkg-config \
    poppler-utils \
    python3-dev \
    tesseract-ocr
  msg_ok "Installed Dependencies"

  PYTHON_VERSION="3.12" setup_uv
  NODE_VERSION="22" NODE_MODULE="corepack" setup_nodejs

  fetch_and_deploy_gh_release "gramps-web-api" "gramps-project/gramps-web-api" "tarball" "latest" "/opt/gramps-web-api"
  fetch_and_deploy_gh_release "gramps-web" "gramps-project/gramps-web" "tarball" "latest" "/opt/gramps-web/frontend"

  msg_info "Setting up Gramps Web"
  mkdir -p \
    /opt/gramps-web/config \
    /opt/gramps-web/data/cache/export \
    /opt/gramps-web/data/cache/persistent \
    /opt/gramps-web/data/cache/report \
    /opt/gramps-web/data/cache/request \
    /opt/gramps-web/data/cache/thumbnail \
    /opt/gramps-web/data/gramps/grampsdb \
    /opt/gramps-web/data/indexdir \
    /opt/gramps-web/data/media \
    /opt/gramps-web/data/users

  SECRET_KEY="$(openssl rand -hex 32)"
  cat << EOF > /opt/gramps-web/config/config.cfg
TREE="Gramps Web"
SECRET_KEY="${SECRET_KEY}"
BASE_URL="http://${LOCAL_IP}:5000"
USER_DB_URI="sqlite:////opt/gramps-web/data/users/users.sqlite"
SEARCH_INDEX_DB_URI="sqlite:////opt/gramps-web/data/indexdir/search_index.db"
MEDIA_BASE_DIR="/opt/gramps-web/data/media"
STATIC_PATH="/opt/gramps-web/frontend/dist"
THUMBNAIL_CACHE_CONFIG={"CACHE_TYPE":"FileSystemCache","CACHE_DIR":"/opt/gramps-web/data/cache/thumbnail","CACHE_THRESHOLD":1000,"CACHE_DEFAULT_TIMEOUT":0}
REQUEST_CACHE_CONFIG={"CACHE_TYPE":"FileSystemCache","CACHE_DIR":"/opt/gramps-web/data/cache/request","CACHE_THRESHOLD":1000,"CACHE_DEFAULT_TIMEOUT":0}
PERSISTENT_CACHE_CONFIG={"CACHE_TYPE":"FileSystemCache","CACHE_DIR":"/opt/gramps-web/data/cache/persistent","CACHE_THRESHOLD":0,"CACHE_DEFAULT_TIMEOUT":0}
REPORT_DIR="/opt/gramps-web/data/cache/report"
EXPORT_DIR="/opt/gramps-web/data/cache/export"
EOF
  $STD uv venv -c -p python3.12 /opt/gramps-web/venv
  source /opt/gramps-web/venv/bin/activate
  $STD uv pip install --no-cache-dir --upgrade pip setuptools wheel
  $STD uv pip install --no-cache-dir gunicorn
  $STD uv pip install --no-cache-dir /opt/gramps-web-api

  GRAMPS_VERSION=$(/opt/gramps-web/venv/bin/python3 -c "import gramps.version; print('%s%s' % (gramps.version.VERSION_TUPLE[0], gramps.version.VERSION_TUPLE[1]))" 2> /dev/null || echo "60")
  GRAMPS_PLUGINS_DIR="/opt/gramps-web/data/gramps/gramps${GRAMPS_VERSION}/plugins"
  mkdir -p "$GRAMPS_PLUGINS_DIR"

  msg_info "Installing Gramps Addons (gramps${GRAMPS_VERSION})"
  $STD wget -q https://github.com/gramps-project/addons/archive/refs/heads/master.zip -O /tmp/gramps-addons.zip
  for addon in FilterRules JSON; do
    unzip -p /tmp/gramps-addons.zip "addons-master/gramps${GRAMPS_VERSION}/download/${addon}.addon.tgz" |
      tar -xz -C "$GRAMPS_PLUGINS_DIR"
  done
  rm -f /tmp/gramps-addons.zip
  msg_ok "Installed Gramps Addons"

  cd /opt/gramps-web/frontend || exit
  export COREPACK_ENABLE_DOWNLOAD_PROMPT=0

  $STD npm install
  $STD npm run build
  cd /opt/gramps-web-api || exit
  GRAMPS_API_CONFIG=/opt/gramps-web/config/config.cfg \
    ALEMBIC_CONFIG=/opt/gramps-web-api/alembic.ini \
    GRAMPSHOME=/opt/gramps-web/data \
    GRAMPS_DATABASE_PATH=/opt/gramps-web/data/gramps/grampsdb \
    $STD /opt/gramps-web/venv/bin/python3 -m gramps_webapi user migrate
  msg_ok "Set up Gramps Web"

  msg_info "Creating Service"
  cat << EOF > /etc/systemd/system/gramps-web.service
[Unit]
Description=Gramps Web Service
After=network.target

[Service]
Type=simple
User=root
WorkingDirectory=/opt/gramps-web-api
Environment=GRAMPS_API_CONFIG=/opt/gramps-web/config/config.cfg
Environment=GRAMPSHOME=/opt/gramps-web/data
Environment=GRAMPS_DATABASE_PATH=/opt/gramps-web/data/gramps/grampsdb
Environment=PATH=/opt/gramps-web/venv/bin:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin
ExecStart=/opt/gramps-web/venv/bin/gunicorn -w 2 -b 0.0.0.0:5000 gramps_webapi.wsgi:app --timeout 120 --limit-request-line 8190
Restart=on-failure
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF
  systemctl enable -q --now gramps-web
  msg_ok "Created Service"
}

function post_install_script() {
  msg_ok "Completed successfully!\n"
  echo -e "${CREATING}${GN}${APP} setup has been successfully initialized!${CL}"
  echo -e "${INFO}${YW}Access it using the following URL:${CL}"
  echo -e "${GATEWAY}${BGN}http://${IP}:5000${CL}"
}

function update_script() {
  header_info
  check_container_storage
  check_container_resources

  if [[ ! -d /opt/gramps-web-api ]] || [[ ! -d /opt/gramps-web/frontend ]]; then
    msg_error "No ${APP} Installation Found!"
    exit
  fi

  PYTHON_VERSION="3.12" setup_uv
  NODE_VERSION="22" NODE_MODULE="corepack" setup_nodejs

  if check_for_gh_release "gramps-web-api" "gramps-project/gramps-web-api"; then
    msg_info "Stopping Service"
    systemctl stop gramps-web
    msg_ok "Stopped Service"

    CLEAN_INSTALL=1 fetch_and_deploy_gh_release "gramps-web-api" "gramps-project/gramps-web-api" "tarball" "latest" "/opt/gramps-web-api"

    msg_info "Updating Gramps Web API"
    $STD uv venv -c -p python3.12 /opt/gramps-web/venv
    source /opt/gramps-web/venv/bin/activate
    $STD uv pip install --no-cache-dir --upgrade pip setuptools wheel
    $STD uv pip install --no-cache-dir gunicorn
    $STD uv pip install --no-cache-dir /opt/gramps-web-api
    msg_ok "Updated Gramps Web API"

    msg_info "Applying Database Migration"
    cd /opt/gramps-web-api || exit
    GRAMPS_API_CONFIG=/opt/gramps-web/config/config.cfg \
      ALEMBIC_CONFIG=/opt/gramps-web-api/alembic.ini \
      GRAMPSHOME=/opt/gramps-web/data \
      GRAMPS_DATABASE_PATH=/opt/gramps-web/data/gramps/grampsdb \
      $STD /opt/gramps-web/venv/bin/python3 -m gramps_webapi user migrate
    msg_ok "Applied Database Migration"

    msg_info "Updating Gramps Addons"
    GRAMPS_VERSION=$(/opt/gramps-web/venv/bin/python3 -c "import gramps.version; print('%s%s' % (gramps.version.VERSION_TUPLE[0], gramps.version.VERSION_TUPLE[1]))" 2> /dev/null || echo "60")
    GRAMPS_PLUGINS_DIR="/opt/gramps-web/data/gramps/gramps${GRAMPS_VERSION}/plugins"
    mkdir -p "$GRAMPS_PLUGINS_DIR"
    $STD wget -q https://github.com/gramps-project/addons/archive/refs/heads/master.zip -O /tmp/gramps-addons.zip
    for addon in FilterRules JSON; do
      unzip -p /tmp/gramps-addons.zip "addons-master/gramps${GRAMPS_VERSION}/download/${addon}.addon.tgz" |
        tar -xz -C "$GRAMPS_PLUGINS_DIR"
    done
    rm -f /tmp/gramps-addons.zip
    msg_ok "Updated Gramps Addons"

    msg_info "Starting Service"
    systemctl start gramps-web
    msg_ok "Started Service"
  fi

  if check_for_gh_release "gramps-web" "gramps-project/gramps-web"; then
    msg_info "Stopping Service"
    systemctl stop gramps-web
    msg_ok "Stopped Service"

    CLEAN_INSTALL=1 fetch_and_deploy_gh_release "gramps-web" "gramps-project/gramps-web" "tarball" "latest" "/opt/gramps-web/frontend"

    msg_info "Updating Gramps Web Frontend"
    cd /opt/gramps-web/frontend || exit
    export COREPACK_ENABLE_DOWNLOAD_PROMPT=0

    create_backup /opt/gramps-web/frontend/dist/config.js

    $STD npm install
    $STD npm run build

    restore_backup

    msg_ok "Updated Gramps Web Frontend"

    msg_info "Starting Service"
    systemctl start gramps-web
    msg_ok "Started Service"
  fi
  exit
}

# framework bootstrap
# shellcheck disable=SC1090
# Dynamic URL resolved at runtime - shellcheck cannot follow
source <(curl -fsSL "$REPO_BASE/misc/bootstrap/lxc")
