#!/usr/bin/env bash
REPO_BASE="${REPO_BASE:-https://raw.githubusercontent.com/scripts-underground/proxmox/main}"

# Copyright (c) 2021-2026 community-scripts ORG
# Author: tteck (tteckster)
# Co-Author: MickLesk (Canbiz)
# License: MIT | https://raw.githubusercontent.com/scripts-underground/proxmox/main/LICENSE
# Source: https://github.com/pymedusa/Medusa
# shellcheck disable=SC2034

APP="Medusa"
var_tags="${var_tags:-media}"
var_cpu="${var_cpu:-2}"
var_ram="${var_ram:-1024}"
var_disk="${var_disk:-6}"
var_os="${var_os:-debian}"
var_version="${var_version:-13}"
var_arm64="${var_arm64:-yes}"
var_unprivileged="${var_unprivileged:-1}"

function install_script() {
  msg_info "Installing Dependencies"
  $STD apt install -y git-core mediainfo
  cat << EOF > /etc/apt/sources.list.d/non-free.list
deb https://deb.debian.org/debian bookworm main contrib non-free non-free-firmware
EOF
  $STD apt update
  $STD apt install -y unrar
  rm /etc/apt/sources.list.d/non-free.list
  msg_ok "Installed Dependencies"

  msg_info "Installing Medusa"
  $STD git clone https://github.com/pymedusa/Medusa.git /opt/medusa
  msg_ok "Installed Medusa"

  msg_info "Creating Service"
  cat << EOF > /etc/systemd/system/medusa.service
[Unit]
Description=Medusa Daemon
After=network.target

[Service]
Type=simple
ExecStart=/usr/bin/python3 /opt/medusa/start.py -q --nolaunch --datadir=/opt/medusa
TimeoutStopSec=25
KillMode=process
Restart=on-failure

[Install]
WantedBy=multi-user.target
EOF
  systemctl enable -q --now medusa
  msg_ok "Created Service"
}

function post_install_script() {
  msg_ok "Completed successfully!\n"
  echo -e "${CREATING}${GN}${APP} setup has been successfully initialized!${CL}"
  echo -e "${INFO}${YW}Access it using the following URL:${CL}"
  echo -e "${GATEWAY}${BGN}http://${IP}:8081${CL}"
}

function update_script() {
  header_info
  check_container_storage
  check_container_resources
  if [[ ! -d /opt/medusa ]]; then
    msg_error "No ${APP} Installation Found!"
    exit
  fi
  msg_info "Stopping Service"
  systemctl stop medusa
  msg_ok "Stopped Service"

  msg_info "Updating ${APP}"
  cd /opt/medusa || exit
  output=$(git pull --no-rebase)
  if echo "$output" | grep -q "Already up to date."; then
    msg_ok "$APP is already up to date."
    exit
  fi
  msg_ok "Updated successfully!"

  msg_info "Starting Service"
  systemctl start medusa
  msg_ok "Started Service"
  exit
}
# shellcheck disable=SC1090
source <(curl -fsSL "$REPO_BASE/misc/bootstrap/lxc")
