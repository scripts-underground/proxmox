#!/usr/bin/env bash
REPO_BASE="${REPO_BASE:-https://raw.githubusercontent.com/scripts-underground/proxmox/main}"

# Sourced by lxc.bootstrap — never executed directly
# Copyright (c) 2021-2026 community-scripts ORG
# Author: vhsdream (vhsdream)
# License: MIT | https://raw.githubusercontent.com/scripts-underground/proxmox/main/LICENSE
# Source: https://github.com/maxdorninger/MediaManager

# shellcheck disable=SC2034
# Read by the framework - shellcheck cannot see the caller
APP="MediaManager"
var_tags="${var_tags:-arr}"
var_cpu="${var_cpu:-2}"
var_ram="${var_ram:-3072}"
var_disk="${var_disk:-4}"
var_os="${var_os:-debian}"
var_version="${var_version:-13}"
var_arm64="${var_arm64:-yes}"
var_unprivileged="${var_unprivileged:-1}"
var_admin_email="${var_admin_email:-admin@example.com}"

function install_script() {
  setup_yq
  NODE_VERSION="24" setup_nodejs
  UV_PYTHON="3.13" setup_uv
  PG_VERSION="17" setup_postgresql
  PG_DB_NAME="mm_db" PG_DB_USER="mm_user" setup_postgresql_db

  fetch_and_deploy_gh_release "MediaManager" "maxdorninger/MediaManager" "tarball" "latest" "/opt/mediamanager"

  msg_info "Configuring MediaManager"
  MM_DIR="/opt/mm"
  MEDIA_DIR="${MM_DIR}/media"
  export CONFIG_DIR="${MM_DIR}/config"
  export FRONTEND_FILES_DIR="${MM_DIR}/web/build"
  export PUBLIC_VERSION=""
  export PUBLIC_API_URL=""
  export BASE_PATH="/web"
  cd /opt/mediamanager/web || exit
  $STD npm install --no-fund --no-audit
  $STD npm run build
  mkdir -p {"$MM_DIR"/web,"$MEDIA_DIR","$CONFIG_DIR"}
  cp -r build "$FRONTEND_FILES_DIR"
  export BASE_PATH=""
  export VIRTUAL_ENV="${MM_DIR}/venv"
  cd /opt/mediamanager || exit
  cp -r {media_manager,alembic*} "$MM_DIR"
  $STD /usr/local/bin/uv sync --locked --active -n -p cpython3.13 --managed-python
  msg_ok "Configured MediaManager"

  msg_info "Creating config and start script"
  SECRET="$(openssl rand -hex 32)"
  sed -e "s/localhost:8/$LOCAL_IP:8/g" \
    -e "s|/data/|$MEDIA_DIR/|g" \
    -e 's/"db"/"localhost"/' \
    -e "s/user = \"MediaManager\"/user = \"$PG_DB_USER\"/" \
    -e "s/password = \"MediaManager\"/password = \"$PG_DB_PASS\"/" \
    -e "s/dbname = \"MediaManager\"/dbname = \"$PG_DB_NAME\"/" \
    -e "/^token_secret/s/=.*/= \"$SECRET\"/" \
    -e "s/admin@example.com/$var_admin_email/" \
    -e '/^admin_emails/s/, .*/]/' \
    /opt/mediamanager/config.example.toml > "$CONFIG_DIR"/config.toml

  mkdir -p "$MEDIA_DIR"/{images,tv,movies,torrents}

  cat << EOF > "$MM_DIR"/start.sh
#!/usr/bin/env bash

export CONFIG_DIR="$CONFIG_DIR"
export FRONTEND_FILES_DIR="$FRONTEND_FILES_DIR"
export LOG_FILE="$CONFIG_DIR/media_manager.log"
export BASE_PATH=""
cd $MM_DIR
source ./venv/bin/activate
/usr/local/bin/uv run alembic upgrade head
/usr/local/bin/uv run fastapi run ./media_manager/main.py --port 8000
EOF
  chmod +x "$MM_DIR"/start.sh
  msg_ok "Created config and start script"

  msg_info "Creating Service"
  cat << EOF > /etc/systemd/system/mediamanager.service
[Unit]
Description=MediaManager Backend Service
After=network.target

[Service]
Type=simple
WorkingDirectory=${MM_DIR}
ExecStart=/usr/bin/bash start.sh

[Install]
WantedBy=multi-user.target
EOF
  systemctl enable -q --now mediamanager
  msg_ok "Created Service"
}

function post_install_script() {
  msg_ok "Completed Successfully!\n"
  echo -e "${CREATING}${GN}${APP} setup has been successfully initialized!${CL}"
  echo -e "${INFO}${YW} Access it using the following URL:${CL}"
  echo -e "${TAB}${GATEWAY}${BGN}http://${IP}:8000${CL}"
  echo -e "${INFO}${YW} Admin email: ${var_admin_email}${CL}"
  echo -e "${INFO}${YW} Config file: /opt/mm/config/config.toml${CL}"
}

function update_script() {
  header_info
  check_container_storage
  check_container_resources
  if [[ ! -d /opt/mediamanager ]]; then
    msg_error "No ${APP} Installation Found!"
    exit
  fi

  UV_PYTHON="3.13" setup_uv

  if check_for_gh_release "mediamanager" "maxdorninger/MediaManager"; then
    msg_info "Stopping Service"
    systemctl stop mediamanager
    msg_ok "Stopped Service"

    fetch_and_deploy_gh_release "MediaManager" "maxdorninger/MediaManager" "tarball" "latest" "/opt/mediamanager"
    msg_info "Updating MediaManager"
    MM_DIR="/opt/mm"
    export CONFIG_DIR="${MM_DIR}/config"
    export FRONTEND_FILES_DIR="${MM_DIR}/web/build"
    export PUBLIC_VERSION=""
    export PUBLIC_API_URL=""
    export BASE_PATH="/web"
    cd /opt/mediamanager/web || exit
    $STD npm install --no-fund --no-audit
    $STD npm run build
    rm -rf "$FRONTEND_FILES_DIR"/build
    cp -r build "$FRONTEND_FILES_DIR"
    export BASE_PATH=""
    export VIRTUAL_ENV="${MM_DIR}/venv"
    cd /opt/mediamanager || exit
    rm -rf "$MM_DIR"/{media_manager,alembic*}
    cp -r {media_manager,alembic*} "$MM_DIR"
    $STD /usr/local/bin/uv sync --locked --active -n -p cpython3.13 --managed-python
    if ! grep -q "LOG_FILE" "$MM_DIR"/start.sh; then
      sed -i "\|build\"$|a\export LOG_FILE=\"$CONFIG_DIR/media_manager.log\"" "$MM_DIR"/start.sh
    fi

    msg_ok "Updated MediaManager"

    msg_info "Starting Service"
    systemctl start mediamanager
    msg_ok "Started Service"
    msg_ok "Updated successfully!"
  fi
  exit
}

# framework bootstrap
# shellcheck disable=SC1090
# Dynamic URL resolved at runtime - shellcheck cannot follow
source <(curl -fsSL "$REPO_BASE/misc/bootstrap/lxc")
