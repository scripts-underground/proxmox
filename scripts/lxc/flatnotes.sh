#!/usr/bin/env bash
REPO_BASE="${REPO_BASE:-https://raw.githubusercontent.com/scripts-underground/proxmox/main}"

# Sourced by lxc.bootstrap — never executed directly
# Copyright (c) 2021-2026 community-scripts ORG
# Author: luismco
# License: MIT | https://raw.githubusercontent.com/scripts-underground/proxmox/main/LICENSE
# Source: https://github.com/dullage/flatnotes

# shellcheck disable=SC2034
APP="Flatnotes"
var_tags="${var_tags:-notes}"
var_cpu="${var_cpu:-1}"
var_ram="${var_ram:-1024}"
var_disk="${var_disk:-4}"
var_os="${var_os:-debian}"
var_version="${var_version:-13}"
var_arm64="${var_arm64:-no}"
var_unprivileged="${var_unprivileged:-1}"

function install_script() {
  fetch_and_deploy_gh_release "flatnotes" "dullage/flatnotes" "tarball"
  USE_UVX="YES" setup_uv
  NODE_VERSION="22" setup_nodejs

  msg_info "Setting up Flatnotes"
  cd /opt/flatnotes || exit
  sed -i 's/^name = ""$/name = "flatnotes"/' pyproject.toml
  $STD /usr/local/bin/uvx migrate-to-uv
  $STD /usr/local/bin/uv sync
  mkdir -p /opt/flatnotes/data
  cd /opt/flatnotes/client || exit
  $STD npm install
  $STD npm run build

  cat << EOF > /opt/flatnotes/.env
FLATNOTES_AUTH_TYPE='none'
FLATNOTES_PATH='/opt/flatnotes/data/'
#FLATNOTES_USERNAME='username'
#FLATNOTES_PASSWORD='password'
#FLATNOTES_SECRET_KEY='secret-key'
EOF
  msg_ok "Setup Flatnotes"

  msg_info "Creating Service"
  cat << EOF > /etc/systemd/system/flatnotes.service
[Unit]
Description=Flatnotes
After=network.target

[Service]
Type=simple
WorkingDirectory=/opt/flatnotes
EnvironmentFile=/opt/flatnotes/.env
ExecStart=/opt/flatnotes/.venv/bin/python -m uvicorn main:app --app-dir server --host 0.0.0.0 --port 8080 --proxy-headers
Restart=on-failure
RestartSec=10

[Install]
WantedBy=multi-user.target
EOF
  systemctl enable -q --now flatnotes
  msg_ok "Created Service"
}

function post_install_script() {
  msg_ok "Completed successfully!\n"
  echo -e "${CREATING}${GN}${APP} setup has been successfully initialized!${CL}"
  echo -e "${INFO}${YW} Access it using the following URL:${CL}"
  echo -e "${TAB}${GATEWAY}${BGN}http://${IP}:8080${CL}"
}

function update_script() {
  header_info
  check_container_storage
  check_container_resources
  if [[ ! -d /opt/flatnotes ]]; then
    msg_error "No ${APP} Installation Found!"
    exit
  fi

  if check_for_gh_release "flatnotes" "dullage/flatnotes"; then
    msg_info "Stopping Service"
    systemctl stop flatnotes
    msg_ok "Stopped Service"

    msg_info "Backing up Configuration and Data"
    cp /opt/flatnotes/.env /opt/flatnotes.env
    cp -r /opt/flatnotes/data /opt/flatnotes_data_backup
    msg_ok "Backed up Configuration and Data"

    fetch_and_deploy_gh_release "flatnotes" "dullage/flatnotes" "tarball"

    msg_info "Updating Flatnotes"
    cd /opt/flatnotes/client || exit
    $STD npm install
    $STD npm run build
    cd /opt/flatnotes || exit
    rm -f uv.lock
    sed -i 's/^name = ""$/name = "flatnotes"/' pyproject.toml
    $STD /usr/local/bin/uvx migrate-to-uv
    $STD /usr/local/bin/uv sync
    msg_ok "Updated Flatnotes"

    msg_info "Restoring Configuration and Data"
    cp /opt/flatnotes.env /opt/flatnotes/.env
    cp -r /opt/flatnotes_data_backup/. /opt/flatnotes/data
    rm -f /opt/flatnotes.env
    rm -r /opt/flatnotes_data_backup
    msg_ok "Restored Configuration and Data"

    msg_info "Starting Service"
    systemctl start flatnotes
    msg_ok "Started Service"
    msg_ok "Updated successfully!"
  fi
  exit
}

# framework bootstrap
# shellcheck disable=SC1090
source <(curl -fsSL "$REPO_BASE/misc/bootstrap/lxc")
