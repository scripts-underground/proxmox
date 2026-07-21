#!/usr/bin/env bash
REPO_BASE="${REPO_BASE:-https://raw.githubusercontent.com/scripts-underground/proxmox/main}"

# Copyright (c) 2021-2026 community-scripts ORG
# Author: tteck (tteckster)
# License: MIT | https://raw.githubusercontent.com/scripts-underground/proxmox/main/LICENSE
# Source: https://github.com/motioneye-project/motioneye

# shellcheck disable=SC2034
# Read by the framework - shellcheck cannot see the caller
APP="Motioneye"
var_tags="${var_tags:-nvr}"
var_cpu="${var_cpu:-2}"
var_ram="${var_ram:-2048}"
var_disk="${var_disk:-8}"
var_os="${var_os:-debian}"
var_version="${var_version:-13}"
var_arm64="${var_arm64:-yes}"
var_unprivileged="${var_unprivileged:-1}"
var_gpu="${var_gpu:-yes}"

function install_script() {
  setup_hwaccel

  msg_info "Installing Dependencies"
  $STD apt install -y git cifs-utils
  msg_ok "Installed Dependencies"

  msg_info "Setup Python3"
  $STD apt install -y \
    python3 \
    python3-dev \
    python3-pip
  rm -rf /usr/lib/python3.*/EXTERNALLY-MANAGED
  msg_ok "Setup Python3"

  msg_info "Installing Motion"
  $STD apt install -y motion
  systemctl stop motion
  $STD systemctl disable motion
  msg_ok "Installed Motion"

  msg_info "Installing FFmpeg"
  $STD apt install -y ffmpeg v4l-utils
  msg_ok "Installed FFmpeg"

  msg_info "Installing MotionEye"
  $STD apt update
  $STD pip install git+https://github.com/motioneye-project/motioneye.git@dev
  mkdir -p /etc/motioneye
  chown -R root:root /etc/motioneye
  chmod -R 777 /etc/motioneye
  curl -fsSL "https://raw.githubusercontent.com/motioneye-project/motioneye/dev/motioneye/extra/motioneye.conf.sample" -o "/etc/motioneye/motioneye.conf"
  mkdir -p /var/lib/motioneye
  msg_ok "Installed MotionEye"

  msg_info "Creating Service"
  curl -fsSL "https://raw.githubusercontent.com/motioneye-project/motioneye/dev/motioneye/extra/motioneye.systemd" -o "/etc/systemd/system/motioneye.service"
  sed -i 's/^User=.*/User=root/' /etc/systemd/system/motioneye.service
  systemctl enable -q --now motioneye
  msg_ok "Created Service"
}

function post_install_script() {
  msg_ok "Completed Successfully!\n"
  echo -e "${CREATING}${GN}${APP} setup has been successfully initialized!${CL}"
  echo -e "${INFO}${YW} Access it using the following URL:${CL}"
  echo -e "${TAB}${GATEWAY}${BGN}http://${IP}:8765${CL}"
}

function update_script() {
  header_info
  check_container_storage
  check_container_resources
  if [[ ! -f /etc/systemd/system/motioneye.service ]]; then
    msg_error "No ${APP} Installation Found!"
    exit
  fi
  msg_info "Updating ${APP} LXC"
  $STD pip install motioneye --upgrade
  msg_ok "Updated successfully!"
  exit
}

# framework bootstrap
# shellcheck disable=SC1090
# Dynamic URL resolved at runtime - shellcheck cannot follow
source <(curl -fsSL "$REPO_BASE/misc/bootstrap/lxc")
