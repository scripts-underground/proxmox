#!/usr/bin/env bash
REPO_BASE="${REPO_BASE:-https://raw.githubusercontent.com/scripts-underground/proxmox/main}"

# Sourced by lxc.bootstrap — never executed directly
# Copyright (c) 2021-2026 community-scripts ORG
# Author: mikolaj92
# License: MIT | https://raw.githubusercontent.com/scripts-underground/proxmox/main/LICENSE
# Source: https://github.com/janeczku/calibre-web

# shellcheck disable=SC2034
# Read by the framework - shellcheck cannot see the caller
APP="calibre-web"
var_tags="${var_tags:-media;books}"
var_cpu="${var_cpu:-2}"
var_ram="${var_ram:-2048}"
var_disk="${var_disk:-8}"
var_os="${var_os:-debian}"
var_version="${var_version:-13}"
var_arm64="${var_arm64:-yes}"
var_unprivileged="${var_unprivileged:-1}"

function install_script() {
  msg_info "Installing Dependencies"
  $STD apt install -y \
    build-essential \
    python3 \
    python3-dev \
    libldap2-dev \
    libsasl2-dev \
    libssl-dev \
    imagemagick \
    libpango-1.0-0 \
    libharfbuzz0b \
    libpangoft2-1.0-0 \
    fonts-liberation
  msg_ok "Installed Dependencies"

  msg_info "Installing Calibre (for eBook conversion)"
  $STD apt install -y calibre
  msg_ok "Installed Calibre"

  fetch_and_deploy_gh_release "Calibre-Web" "janeczku/calibre-web" "prebuild" "latest" "/opt/calibre-web" "calibre-web*.tar.gz"
  setup_uv

  msg_info "Installing Python Dependencies"
  cd /opt/calibre-web || exit
  $STD uv venv
  $STD uv pip install --python /opt/calibre-web/.venv/bin/python --no-cache-dir --upgrade pip setuptools wheel
  $STD uv pip install --python /opt/calibre-web/.venv/bin/python --no-cache-dir -r requirements.txt
  msg_ok "Installed Python Dependencies"

  msg_info "Creating Service"
  mkdir -p /opt/calibre-web/data
  cat << EOF > /etc/systemd/system/calibre-web.service
[Unit]
Description=Calibre-Web Service
After=network.target

[Service]
Type=simple
User=root
Environment="QTWEBENGINE_CHROMIUM_FLAGS=--no-sandbox"
WorkingDirectory=/opt/calibre-web
ExecStart=/opt/calibre-web/.venv/bin/python /opt/calibre-web/cps.py
Restart=on-failure
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF
  systemctl enable -q --now calibre-web
  msg_ok "Created Service"
}

function post_install_script() {
  msg_ok "Completed successfully!\n"
  echo -e "${CREATING}${GN}${APP} setup has been successfully initialized!${CL}"
  echo -e "${INFO}${YW}Access it using the following URL:${CL}"
  echo -e "${GATEWAY}${BGN}http://${IP}:8083${CL}"
}

function update_script() {
  header_info
  check_container_storage
  check_container_resources

  if [[ ! -d /opt/calibre-web ]]; then
    msg_error "No ${APP} Installation Found!"
    exit
  fi

  if check_for_gh_release "Calibre-Web" "janeczku/calibre-web"; then
    msg_info "Stopping Service"
    systemctl stop calibre-web
    msg_ok "Stopped Service"

    create_backup /opt/calibre-web/app.db \
      /opt/calibre-web/data

    CLEAN_INSTALL=1 fetch_and_deploy_gh_release "Calibre-Web" "janeczku/calibre-web" "prebuild" "latest" "/opt/calibre-web" "calibre-web*.tar.gz"
    setup_uv

    msg_info "Installing Dependencies"
    cd /opt/calibre-web || exit
    $STD uv venv --clear /opt/calibre-web/.venv
    $STD uv pip install --python /opt/calibre-web/.venv/bin/python --no-cache-dir --upgrade pip setuptools wheel
    $STD uv pip install --python /opt/calibre-web/.venv/bin/python --no-cache-dir -r requirements.txt
    msg_ok "Installed Dependencies"

    restore_backup

    msg_info "Starting Service"
    systemctl start calibre-web
    msg_ok "Started Service"
    msg_ok "Updated successfully!"
  fi
  exit
}

# framework bootstrap
# shellcheck disable=SC1090
# Dynamic URL resolved at runtime - shellcheck cannot follow
source <(curl -fsSL "$REPO_BASE/misc/bootstrap/lxc")
