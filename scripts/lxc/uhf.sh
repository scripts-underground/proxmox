#!/usr/bin/env bash
REPO_BASE="${REPO_BASE:-https://raw.githubusercontent.com/scripts-underground/proxmox/main}"

# Copyright (c) 2021-2026 community-scripts ORG
# Author: zackwithak13
# License: MIT | https://raw.githubusercontent.com/scripts-underground/proxmox/main/LICENSE
# Source: https://www.uhfapp.com/server | Github: https://github.com/swapplications/uhf-server-dist

# shellcheck disable=SC2034
# Read by the framework - shellcheck cannot see the caller
APP="UHF"
var_tags="${var_tags:-media}"
var_cpu="${var_cpu:-2}"
var_ram="${var_ram:-2048}"
var_disk="${var_disk:-8}"
var_os="${var_os:-debian}"
var_version="${var_version:-13}"
var_arm64="${var_arm64:-yes}"
var_unprivileged="${var_unprivileged:-1}"
var_gpu="${var_gpu:-yes}"

function install_script() {
  local ARCH
  ARCH=$(uname -m)
  [[ "$ARCH" == "x86_64" ]] && ARCH="x64"
  [[ "$ARCH" == "aarch64" ]] && ARCH="arm64"

  setup_hwaccel

  msg_info "Installing Dependencies"
  setup_ffmpeg
  msg_ok "Installed Dependencies"

  msg_info "Setting Up UHF Server Environment"
  mkdir -p /etc/uhf-server
  mkdir -p /var/lib/uhf-server/data
  mkdir -p /var/lib/uhf-server/recordings
  cat << EOF > /etc/uhf-server/.env
API_HOST=0.0.0.0
API_PORT=7568
RECORDINGS_DIR=/var/lib/uhf-server/recordings
DB_PATH=/var/lib/uhf-server/data/db.json
LOG_LEVEL=INFO
EOF
  msg_ok "Set Up UHF Server Environment"

  fetch_and_deploy_gh_release "comskip" "swapplications/comskip" "prebuild" "latest" "/opt/comskip" "comskip-${ARCH}-*.zip"
  fetch_and_deploy_gh_release "uhf-server" "swapplications/uhf-server-dist" "prebuild" "latest" "/opt/uhf-server" "UHF.Server-linux-${ARCH}-*.zip"

  msg_info "Creating Service"
  cat << EOF > /etc/systemd/system/uhf-server.service
[Unit]
Description=UHF Server service
After=syslog.target network-online.target
[Service]
Type=simple
WorkingDirectory=/opt/uhf-server
EnvironmentFile=/etc/uhf-server/.env
ExecStart=/opt/uhf-server/uhf-server
[Install]
WantedBy=multi-user.target
EOF
  systemctl enable -q --now uhf-server
  msg_ok "Created Service"
}

function post_install_script() {
  msg_ok "Completed successfully!\n"
  echo -e "${CREATING}${GN}${APP} setup has been successfully initialized!${CL}"
  echo -e "${INFO}${YW}Access it using the following URL:${CL}"
  echo -e "${GATEWAY}${BGN}http://${IP}:7568${CL}"
}

function update_script() {
  header_info
  check_container_storage
  check_container_resources
  if [[ ! -d /opt/uhf-server ]]; then
    msg_error "No ${APP} Installation Found!"
    exit
  fi
  if check_for_gh_release "uhf-server" "swapplications/uhf-server-dist"; then
    msg_info "Stopping Service"
    systemctl stop uhf-server
    msg_ok "Stopped Service"

    msg_info "Updating LXC"
    $STD apt update
    $STD apt -y upgrade
    msg_ok "Updated LXC"

    msg_info "Updating UHF Server"
    if dpkg -l ffmpeg 2>&1 | grep -q "ii"; then
      apt remove ffmpeg -y && apt autoremove -y
    fi
    setup_ffmpeg

    local ARCH
    ARCH=$(uname -m)
    [[ "$ARCH" == "x86_64" ]] && ARCH="x64"
    [[ "$ARCH" == "aarch64" ]] && ARCH="arm64"

    fetch_and_deploy_gh_release "comskip" "swapplications/comskip" "prebuild" "latest" "/opt/comskip" "comskip-${ARCH}-*.zip"
    fetch_and_deploy_gh_release "uhf-server" "swapplications/uhf-server-dist" "prebuild" "latest" "/opt/uhf-server" "UHF.Server-linux-${ARCH}-*.zip"
    msg_ok "Updated UHF Server"

    msg_info "Starting Service"
    systemctl start uhf-server
    msg_ok "Started Service"
    msg_ok "Updated successfully!"
  fi
  exit
}

# framework bootstrap
# shellcheck disable=SC1090
# Dynamic URL resolved at runtime - shellcheck cannot follow
source <(curl -fsSL "$REPO_BASE/misc/bootstrap/lxc")
