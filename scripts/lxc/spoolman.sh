#!/usr/bin/env bash
REPO_BASE="${REPO_BASE:-https://raw.githubusercontent.com/scripts-underground/proxmox/main}"

# Sourced by lxc.bootstrap — never executed directly
# Copyright (c) 2021-2026 community-scripts ORG
# Author: MickLesk (Canbiz)
# License: MIT | https://raw.githubusercontent.com/scripts-underground/proxmox/main/LICENSE
# Source: https://github.com/Donkie/Spoolman

# shellcheck disable=SC2034
# Read by the framework - shellcheck cannot see the caller
APP="Spoolman"
var_tags="${var_tags:-3d-printing}"
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
    build-essential \
    libpq-dev \
    libffi-dev
  msg_ok "Installed Dependencies"

  PYTHON_VERSION="3.14" setup_uv
  fetch_and_deploy_gh_release "spoolman" "Donkie/Spoolman" "prebuild" "latest" "/opt/spoolman" "spoolman.zip"

  msg_info "Setting up Spoolman"
  cd /opt/spoolman || exit
  $STD uv sync --locked --no-install-project
  $STD uv sync --locked
  cp .env.example .env
  msg_ok "Setup Spoolman"

  msg_info "Creating Service"
  cat << EOF > /etc/systemd/system/spoolman.service
[Unit]
Description=Spoolman
After=network.target

[Service]
Type=simple
WorkingDirectory=/opt/spoolman
EnvironmentFile=/opt/spoolman/.env
ExecStart=/usr/bin/bash /opt/spoolman/scripts/start.sh
Restart=always
User=root

[Install]
WantedBy=multi-user.target
EOF
  systemctl enable -q --now spoolman
  msg_ok "Created Service"
}

function post_install_script() {
  msg_ok "Completed Successfully!\n"
  echo -e "${CREATING}${GN}${APP} setup has been successfully initialized!${CL}"
  echo -e "${INFO}${YW} Access it using the following URL:${CL}"
  echo -e "${TAB}${GATEWAY}${BGN}http://${IP}:7912${CL}"
}

function update_script() {
  header_info
  check_container_storage
  check_container_resources
  if [[ ! -d /opt/spoolman ]]; then
    msg_error "No ${APP} Installation Found!"
    exit
  fi

  PYTHON_VERSION="3.14" setup_uv

  if check_for_gh_release "spoolman" "Donkie/Spoolman"; then
    msg_info "Stopping Service"
    systemctl stop spoolman
    msg_ok "Stopped Service"

    msg_info "Creating Backup"
    [ -d /opt/spoolman_bak ] && rm -rf /opt/spoolman_bak
    mv /opt/spoolman /opt/spoolman_bak
    msg_ok "Created Backup"

    fetch_and_deploy_gh_release "spoolman" "Donkie/Spoolman" "prebuild" "latest" "/opt/spoolman" "spoolman.zip"

    msg_info "Updating Spoolman"
    cd /opt/spoolman || exit
    $STD uv sync --locked --no-install-project
    $STD uv sync --locked
    cp /opt/spoolman_bak/.env /opt/spoolman
    sed -i 's|^ExecStart=.*|ExecStart=/usr/bin/bash /opt/spoolman/scripts/start.sh|' /etc/systemd/system/spoolman.service
    systemctl daemon-reload
    msg_ok "Updated Spoolman"

    msg_info "Starting Service"
    systemctl start spoolman
    msg_ok "Started Service"
    msg_ok "Updated successfully!"
  fi
  exit
}

# shellcheck disable=SC1090
source <(curl -fsSL "$REPO_BASE/misc/bootstrap/lxc")
