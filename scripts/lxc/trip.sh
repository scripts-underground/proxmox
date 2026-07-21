#!/usr/bin/env bash
REPO_BASE="${REPO_BASE:-https://raw.githubusercontent.com/scripts-underground/proxmox/main}"

# Copyright (c) 2021-2026 community-scripts ORG
# Author: CrazyWolf13
# License: MIT | https://raw.githubusercontent.com/scripts-underground/proxmox/main/LICENSE
# Source: https://github.com/itskovacs/TRIP

# shellcheck disable=SC2034
# Read by the framework - shellcheck cannot see the caller
APP="TRIP"
var_tags="${var_tags:-maps;travel}"
var_cpu="${var_cpu:-1}"
var_ram="${var_ram:-1024}"
var_disk="${var_disk:-4}"
var_os="${var_os:-debian}"
var_version="${var_version:-13}"
var_arm64="${var_arm64:-yes}"
var_unprivileged="${var_unprivileged:-1}"

function install_script() {
  msg_info "Installing Dependencies"
  $STD apt install -y \
    build-essential
  msg_ok "Installed Dependencies"

  NODE_VERSION="22" setup_nodejs
  PYTHON_VERSION="3.12" setup_uv
  fetch_and_deploy_gh_release "trip" "itskovacs/TRIP" "tarball"

  msg_info "Building Frontend"
  cd /opt/trip/src || exit
  $STD npm install
  $STD npm run build
  msg_ok "Built Frontend"

  msg_info "Setting up Backend"
  cd /opt/trip/backend || exit
  $STD uv venv --clear /opt/trip/.venv
  $STD uv pip install --python /opt/trip/.venv/bin/python -r trip/requirements.txt
  msg_ok "Set up Backend"

  msg_info "Configuring Application"
  mkdir -p /opt/trip/frontend
  cp -r /opt/trip/src/dist/trip/browser/* /opt/trip/frontend/
  mkdir -p /opt/trip_storage/{attachments,backups,assets}

  cat << EOF > /opt/trip.env
# TRIP Configuration
# https://itskovacs.github.io/trip/docs/getting-started/configuration/
ATTACHMENTS_FOLDER=/opt/trip_storage/attachments
BACKUPS_FOLDER=/opt/trip_storage/backups
ASSETS_FOLDER=/opt/trip_storage/assets
FRONTEND_FOLDER=/opt/trip/frontend
SQLITE_FILE=/opt/trip_storage/trip.sqlite
EOF
  msg_ok "Configured Application"

  msg_info "Creating Service"
  cat << EOF > /etc/systemd/system/trip.service
[Unit]
Description=TRIP - Minimalist POI Map Tracker and Trip Planner
After=network.target

[Service]
Type=simple
WorkingDirectory=/opt/trip/backend
EnvironmentFile=/opt/trip.env
ExecStart=/opt/trip/.venv/bin/fastapi run /opt/trip/backend/trip/main.py --host 0.0.0.0 --port 8000
Restart=on-failure
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF
  systemctl enable -q --now trip
  msg_ok "Created Service"
}

function post_install_script() {
  msg_ok "Completed Successfully!\n"
  echo -e "${CREATING}${GN}${APP} setup has been successfully initialized!${CL}"
  echo -e "${INFO}${YW} Access it using the following URL:${CL}"
  echo -e "${TAB}${GATEWAY}${BGN}http://${IP}:8000${CL}"
}

function update_script() {
  header_info
  check_container_storage
  check_container_resources
  if [[ ! -d /opt/trip ]]; then
    msg_error "No ${APP} Installation Found!"
    exit
  fi

  if check_for_gh_release "trip" "itskovacs/TRIP"; then
    msg_info "Stopping Service"
    systemctl stop trip
    msg_ok "Stopped Service"

    CLEAN_INSTALL=1 fetch_and_deploy_gh_release "trip" "itskovacs/TRIP" "tarball"

    msg_info "Updating Frontend"
    cd /opt/trip/src || exit
    $STD npm install
    $STD npm run build
    mkdir -p /opt/trip/frontend
    cp -r /opt/trip/src/dist/trip/browser/* /opt/trip/frontend/
    msg_ok "Updated Frontend"

    msg_info "Updating Backend"
    cd /opt/trip/backend || exit
    $STD uv pip install --python /opt/trip/.venv/bin/python -r trip/requirements.txt
    msg_ok "Updated Backend"

    msg_info "Starting Service"
    systemctl start trip
    msg_ok "Started Service"
    msg_ok "Updated successfully!"
  fi
  exit
}

# framework bootstrap
# shellcheck disable=SC1090
# Dynamic URL resolved at runtime - shellcheck cannot follow
source <(curl -fsSL "$REPO_BASE/misc/bootstrap/lxc")
