#!/usr/bin/env bash
REPO_BASE="${REPO_BASE:-https://raw.githubusercontent.com/scripts-underground/proxmox/main}"

# Copyright (c) 2021-2026 community-scripts ORG
# Author: MickLesk (Canbiz)
# License: MIT | https://raw.githubusercontent.com/scripts-underground/proxmox/main/LICENSE
# Source: https://nextpvr.com/

APP="NextPVR"
var_tags="${var_tags:-pvr}"
var_cpu="${var_cpu:-1}"
var_ram="${var_ram:-1024}"
var_disk="${var_disk:-5}"
var_os="${var_os:-debian}"
var_version="${var_version:-13}"
var_arm64="${var_arm64:-yes}"
var_unprivileged="${var_unprivileged:-1}"
var_gpu="${var_gpu:-yes}"

function install_script() {
  setup_hwaccel

  msg_info "Installing Dependencies (Patience)"
  $STD apt install -y \
    mediainfo \
    libmediainfo-dev \
    libc6 \
    libgdiplus \
    acl \
    dvb-tools \
    libdvbv5-0 \
    dtv-scan-tables \
    libc6-dev \
    libicu-dev \
    ffmpeg
  msg_ok "Installed Dependencies"

  msg_info "Setup NextPVR (Patience)"
  cd /opt || exit
  curl_download "/opt/nextpvr-helper.deb" "https://nextpvr.com/nextpvr-helper.deb"
  $STD dpkg -i nextpvr-helper.deb
  rm -rf /opt/nextpvr-helper.deb
  msg_ok "Installed NextPVR"
}

function post_install_script() {
  msg_ok "Completed successfully!\n"
  echo -e "${CREATING}${GN}${APP} setup has been successfully initialized!${CL}"
  echo -e "${INFO}${YW}Access it using the following URL:${CL}"
  echo -e "${GATEWAY}${BGN}http://${IP}:8866${CL}"
}

function update_script() {
  header_info
  check_container_storage
  check_container_resources
  if [[ ! -d /opt/nextpvr ]]; then
    msg_error "No ${APP} Installation Found!"
    exit
  fi
  msg_info "Stopping Service"
  systemctl stop nextpvr-server
  msg_ok "Stopped Service"

  msg_info "Updating LXC packages"
  $STD apt update
  $STD apt -y upgrade
  msg_ok "Updated LXC packages"

  msg_info "Updating ${APP}"
  cd /opt || exit
  curl_download "/opt/nextpvr-helper.deb" "https://nextpvr.com/nextpvr-helper.deb"
  $STD dpkg -i nextpvr-helper.deb
  rm -rf /opt/nextpvr-helper.deb
  msg_ok "Updated ${APP}"

  msg_info "Starting Service"
  systemctl start nextpvr-server
  msg_ok "Started Service"
  msg_ok "Updated successfully!"
  exit
}

# shellcheck disable=SC1090
# Dynamic URL resolved at runtime
source <(curl -fsSL "$REPO_BASE/misc/bootstrap/lxc")
