#!/usr/bin/env bash
REPO_BASE="${REPO_BASE:-https://raw.githubusercontent.com/scripts-underground/proxmox/main}"

# Copyright (c) 2021-2026 community-scripts ORG
# Author: MickLesk (CanbiZ)
# License: MIT | https://raw.githubusercontent.com/scripts-underground/proxmox/main/LICENSE
# Source: https://nxvms.com/download/releases/linux

# shellcheck disable=SC2034
# Read by the framework - shellcheck cannot see the caller
APP="NxWitness"
var_tags="${var_tags:-nvr}"
var_cpu="${var_cpu:-2}"
var_ram="${var_ram:-2048}"
var_disk="${var_disk:-8}"
var_os="${var_os:-ubuntu}"
var_version="${var_version:-24.04}"
var_arm64="${var_arm64:-yes}"
var_unprivileged="${var_unprivileged:-0}"
var_gpu="${var_gpu:-yes}"

function install_script() {
  setup_hwaccel

  msg_info "Installing Dependencies"
  $STD apt install -y \
    make \
    net-tools \
    ffmpeg \
    cifs-utils \
    libtalloc2 \
    libwbclient0 \
    keyutils
  msg_ok "Installed Dependencies"

  msg_info "Setup Nx Witness"
  cd /tmp || exit
  BASE_URL="https://updates.networkoptix.com/default/index.html"
  RELEASE=$(curl -fsSL "$BASE_URL" | grep -oP '(?<=<b>)[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+(?=</b>)' | head -n 1)
  DETAIL_PAGE=$(curl -fsSL "$BASE_URL#note_$RELEASE")
  ARCH=$(dpkg --print-architecture)
  [[ "$ARCH" == "arm64" ]] && URL_ARCH="arm" || URL_ARCH="linux"
  [[ "$ARCH" == "arm64" ]] && DEB_ARCH="arm64" || DEB_ARCH="x64"
  DOWNLOAD_URL=$(echo "$DETAIL_PAGE" | grep -oP "https://updates.networkoptix.com/default/${RELEASE}/${URL_ARCH}/nxwitness-server-[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+-linux_${DEB_ARCH}\.deb" | head -n 1)
  curl -fsSL "$DOWNLOAD_URL" -o "nxwitness-server-${RELEASE}-linux_${DEB_ARCH}.deb"
  export DEBIAN_FRONTEND=noninteractive
  $STD dpkg -i nxwitness-server-${RELEASE}-linux_${DEB_ARCH}.deb
  rm -f /tmp/nxwitness-server-${RELEASE}-linux_${DEB_ARCH}.deb
  echo "${RELEASE}" > /opt/${APP}_version.txt
  msg_ok "Setup Nx Witness"
}

function post_install_script() {
  msg_ok "Completed successfully!\n"
  echo -e "${CREATING}${GN}${APP} setup has been successfully initialized!${CL}"
  echo -e "${INFO}${YW}Access it using the following URL:${CL}"
  echo -e "${GATEWAY}${BGN}http://${IP}:7001/${CL}"
}

function update_script() {
  header_info
  check_container_storage
  check_container_resources
  if [[ ! -f /etc/systemd/system/networkoptix-mediaserver.service ]]; then
    msg_error "No ${APP} Installation Found!"
    exit
  fi
  BASE_URL="https://updates.networkoptix.com/default/index.html"
  RELEASE=$(curl -fsSL "$BASE_URL" | grep -oP '(?<=<b>)[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+(?=</b>)' | head -n 1)
  DETAIL_PAGE=$(curl -fsSL "$BASE_URL#note_$RELEASE")
  ARCH=$(dpkg --print-architecture)
  [[ "$ARCH" == "arm64" ]] && URL_ARCH="arm" || URL_ARCH="linux"
  [[ "$ARCH" == "arm64" ]] && DEB_ARCH="arm64" || DEB_ARCH="x64"
  DOWNLOAD_URL=$(echo "$DETAIL_PAGE" | grep -oP "https://updates.networkoptix.com/default/${RELEASE}/${URL_ARCH}/nxwitness-server-[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+-linux_${DEB_ARCH}\.deb" | head -n 1)
  if [[ ! -f /opt/${APP}_version.txt ]] || [[ "${RELEASE}" != "$(cat /opt/${APP}_version.txt)" ]]; then
    msg_info "Stopping Service"
    systemctl stop networkoptix-root-tool networkoptix-mediaserver
    msg_ok "Stopped Service"

    msg_info "Updating ${APP} to ${RELEASE}"
    cd /tmp || exit
    curl -fsSL "$DOWNLOAD_URL" -o "nxwitness-server-${RELEASE}-linux_${DEB_ARCH}.deb"
    export DEBIAN_FRONTEND=noninteractive
    export DEBCONF_NOWARNINGS=yes
    $STD dpkg -i nxwitness-server-${RELEASE}-linux_${DEB_ARCH}.deb
    rm -f /tmp/nxwitness-server-${RELEASE}-linux_${DEB_ARCH}.deb
    echo "${RELEASE}" > /opt/${APP}_version.txt
    msg_ok "Updated ${APP}"

    msg_info "Starting Service"
    systemctl start networkoptix-root-tool networkoptix-mediaserver
    msg_ok "Started Service"
    msg_ok "Updated successfully!"
  else
    msg_ok "No update required. ${APP} is already at ${RELEASE}"
  fi
  exit
}

# framework bootstrap
# shellcheck disable=SC1090
# Dynamic URL resolved at runtime - shellcheck cannot follow
source <(curl -fsSL "$REPO_BASE/misc/bootstrap/lxc")
