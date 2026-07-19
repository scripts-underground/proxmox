#!/usr/bin/env bash
REPO_BASE="${REPO_BASE:-https://raw.githubusercontent.com/scripts-underground/proxmox/main}"

# Sourced by lxc.bootstrap — never executed directly
# Copyright (c) 2021-2026 community-scripts ORG
# Author: Adrian-RDA
# License: MIT | https://raw.githubusercontent.com/scripts-underground/proxmox/main/LICENSE
# Source: https://github.com/maziggy/bambuddy

# shellcheck disable=SC2034
# Read by the framework - shellcheck cannot see the caller
APP="Bambuddy"
var_tags="${var_tags:-media;3d-printing}"
var_cpu="${var_cpu:-2}"
var_ram="${var_ram:-2048}"
var_disk="${var_disk:-10}"
var_os="${var_os:-debian}"
var_version="${var_version:-13}"
var_arm64="${var_arm64:-yes}"
var_unprivileged="${var_unprivileged:-1}"

function install_script() {
  msg_info "Installing Dependencies"
  $STD apt install -y libglib2.0-0 ffmpeg
  msg_ok "Installed Dependencies"

  PYTHON_VERSION="3.13" setup_uv
  NODE_VERSION="22" setup_nodejs
  fetch_and_deploy_gh_release "bambuddy" "maziggy/bambuddy" "tarball" "latest" "/opt/bambuddy"

  msg_info "Setting up Python Environment"
  cd /opt/bambuddy || exit
  $STD uv venv
  $STD uv pip install -r requirements.txt
  msg_ok "Set up Python Environment"

  msg_info "Building Frontend"
  cd /opt/bambuddy/frontend || exit
  $STD npm install
  $STD npm run build
  msg_ok "Built Frontend"

  msg_info "Configuring Bambuddy"
  mkdir -p /opt/bambuddy/data /opt/bambuddy/logs
  cat << EOF > /opt/bambuddy/.env
DEBUG=false
LOG_LEVEL=INFO
LOG_TO_FILE=true
EOF
  msg_ok "Configured Bambuddy"

  msg_info "Creating Service"
  cat << EOF > /etc/systemd/system/bambuddy.service
[Unit]
Description=Bambuddy - Bambu Lab Print Management
Documentation=https://github.com/maziggy/bambuddy
After=network.target

[Service]
Type=simple
WorkingDirectory=/opt/bambuddy
ExecStart=/opt/bambuddy/.venv/bin/uvicorn backend.app.main:app --host 0.0.0.0 --port 8000
Restart=on-failure
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF
  systemctl enable -q --now bambuddy
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

  if [[ ! -d /opt/bambuddy ]]; then
    msg_error "No ${APP} Installation Found!"
    exit
  fi

  ensure_dependencies ffmpeg

  if check_for_gh_release "bambuddy" "maziggy/bambuddy"; then
    msg_info "Stopping Service"
    systemctl stop bambuddy
    msg_ok "Stopped Service"

    msg_info "Backing up Configuration and Data"
    create_backup /opt/bambuddy/.env \
      /opt/bambuddy/data \
      /opt/bambuddy/bambuddy.db \
      /opt/bambuddy/bambutrack.db \
      /opt/bambuddy/archive
    msg_ok "Backed up Configuration and Data"

    CLEAN_INSTALL=1 fetch_and_deploy_gh_release "bambuddy" "maziggy/bambuddy" "tarball" "latest" "/opt/bambuddy"

    msg_info "Updating Python Dependencies"
    cd /opt/bambuddy || exit
    $STD uv venv --clear
    $STD uv pip install -r requirements.txt
    msg_ok "Updated Python Dependencies"

    msg_info "Rebuilding Frontend"
    cd /opt/bambuddy/frontend || exit
    $STD npm install
    $STD npm run build
    msg_ok "Rebuilt Frontend"

    restore_backup

    msg_info "Starting Service"
    systemctl start bambuddy
    msg_ok "Started Service"
    msg_ok "Updated successfully!"
  fi
  exit
}

# framework bootstrap
# shellcheck disable=SC1090
# Dynamic URL resolved at runtime - shellcheck cannot follow
source <(curl -fsSL "$REPO_BASE/misc/bootstrap/lxc")
