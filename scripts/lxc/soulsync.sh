#!/usr/bin/env bash
REPO_BASE="${REPO_BASE:-https://raw.githubusercontent.com/scripts-underground/proxmox/main}"

# Sourced by lxc.bootstrap — never executed directly
# Copyright (c) 2021-2026 community-scripts ORG
# Author: MickLesk (CanbiZ)
# License: MIT | https://raw.githubusercontent.com/scripts-underground/proxmox/main/LICENSE
# Source: https://github.com/Nezreka/SoulSync

# shellcheck disable=SC2034
# Read by the framework - shellcheck cannot see the caller
APP="SoulSync"
var_tags="${var_tags:-music;automation;media}"
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
    gcc \
    libffi-dev \
    libssl-dev \
    libchromaprint-tools \
    ffmpeg
  msg_ok "Installed Dependencies"

  UV_PYTHON="3.11" setup_uv
  NODE_VERSION="24" setup_nodejs

  fetch_and_deploy_gh_release "soulsync" "Nezreka/SoulSync" "tarball"

  msg_info "Setting up Application"
  cd /opt/soulsync || exit
  $STD uv venv /opt/soulsync/.venv --python 3.11
  $STD uv pip install -r requirements.txt --python /opt/soulsync/.venv/bin/python
  mkdir -p /opt/soulsync/{config,data,logs}
  msg_ok "Set up Application"

  msg_info "Building WebUI"
  cd /opt/soulsync/webui || exit
  $STD npm ci
  $STD npm run build
  msg_ok "Built WebUI"

  msg_info "Creating Service"
  cat << EOF > /etc/systemd/system/soulsync.service
[Unit]
Description=SoulSync Music Discovery
After=network.target

[Service]
Type=simple
User=root
WorkingDirectory=/opt/soulsync
ExecStart=/opt/soulsync/.venv/bin/python web_server.py
Environment=PYTHONPATH=/opt/soulsync PYTHONUNBUFFERED=1 DATABASE_PATH=/opt/soulsync/data/music_library.db
Restart=on-failure
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF
  systemctl enable -q --now soulsync
  msg_ok "Created Service"
}

function post_install_script() {
  msg_ok "Completed Successfully!\n"
  echo -e "${CREATING}${GN}${APP} setup has been successfully initialized!${CL}"
  echo -e "${INFO}${YW}Access it using the following URL:${CL}"
  echo -e "${GATEWAY}${BGN}http://${IP}:8008${CL}"
}

function update_script() {
  header_info
  check_container_storage
  check_container_resources

  if [[ ! -f ~/.soulsync ]]; then
    msg_error "No ${APP} Installation Found!"
    exit
  fi

  NODE_VERSION="24" setup_nodejs

  if check_for_gh_release "soulsync" "Nezreka/SoulSync"; then
    msg_info "Stopping Service"
    systemctl stop soulsync
    msg_ok "Stopped Service"

    create_backup /opt/soulsync/config /opt/soulsync/data

    CLEAN_INSTALL=1 fetch_and_deploy_gh_release "soulsync" "Nezreka/SoulSync" "tarball"

    restore_backup

    msg_info "Updating Python Dependencies"
    cd /opt/soulsync || exit
    $STD uv venv --clear /opt/soulsync/.venv --python 3.11
    $STD uv pip install -r requirements.txt
    msg_ok "Updated Python Dependencies"

    msg_info "Building WebUI"
    cd /opt/soulsync/webui || exit
    $STD npm ci
    $STD npm run build
    msg_ok "Built WebUI"

    msg_info "Starting Service"
    systemctl start soulsync
    msg_ok "Started Service"
    msg_ok "Updated ${APP}"
  fi
  exit
}

# framework bootstrap
# shellcheck disable=SC1090
# Dynamic URL resolved at runtime - shellcheck cannot follow
source <(curl -fsSL "$REPO_BASE/misc/bootstrap/lxc")
