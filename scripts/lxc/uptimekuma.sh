#!/usr/bin/env bash
REPO_BASE="${REPO_BASE:-https://raw.githubusercontent.com/scripts-underground/proxmox/main}"
# Sourced by lxc.bootstrap — never executed directly
# Copyright (c) 2021-2026 community-scripts ORG
# Author: tteck (tteckster)
# License: MIT | https://raw.githubusercontent.com/scripts-underground/proxmox/main/LICENSE
# Source: https://uptime.kuma.pet/ | Github: https://github.com/louislam/uptime-kuma
# shellcheck disable=SC2034
APP="Uptime Kuma"
var_tags="${var_tags:-analytics;monitoring}"
var_cpu="${var_cpu:-1}"
var_ram="${var_ram:-1024}"
var_disk="${var_disk:-4}"
var_os="${var_os:-debian}"
var_version="${var_version:-13}"
var_arm64="${var_arm64:-yes}"
var_unprivileged="${var_unprivileged:-1}"

function install_script() {
  msg_info "Installing Dependencies"
  $STD apt install -y chromium
  msg_ok "Installed Dependencies"

  NODE_VERSION="22" setup_nodejs
  fetch_and_deploy_gh_release "uptime-kuma" "louislam/uptime-kuma" "tarball"

  msg_info "Installing Uptime Kuma"
  cd /opt/uptime-kuma || exit
  $STD npm ci --omit dev
  $STD npm run download-dist
  msg_ok "Installed Uptime Kuma"

  msg_info "Creating Service"
  ln -s /usr/bin/chromium /opt/uptime-kuma/chromium
  cat << EOF > /etc/systemd/system/uptime-kuma.service
[Unit]
Description=uptime-kuma

[Service]
Type=simple
Restart=always
User=root
WorkingDirectory=/opt/uptime-kuma
ExecStart=/usr/bin/npm start

[Install]
WantedBy=multi-user.target
EOF
  systemctl enable -q --now uptime-kuma
  msg_ok "Created Service"
}

function post_install_script() {
  msg_ok "Completed Successfully!\n"
  echo -e "${CREATING}${GN}${APP} setup has been successfully initialized!${CL}"
  echo -e "${INFO}${YW}Access it using the following URL:${CL}"
  echo -e "${GATEWAY}${BGN}http://${IP}:3001${CL}"
}

function update_script() {
  header_info
  check_container_storage
  check_container_resources
  if [[ ! -d /opt/uptime-kuma ]]; then
    msg_error "No ${APP} Installation Found!"
    exit
  fi

  NODE_VERSION="22" setup_nodejs

  ensure_dependencies chromium
  if [[ ! -L /opt/uptime-kuma/chromium ]]; then
    ln -s /usr/bin/chromium /opt/uptime-kuma/chromium
  fi

  if check_for_gh_release "uptime-kuma" "louislam/uptime-kuma"; then
    msg_info "Stopping Service"
    systemctl stop uptime-kuma
    msg_ok "Stopped Service"

    fetch_and_deploy_gh_release "uptime-kuma" "louislam/uptime-kuma" "tarball"

    msg_info "Updating Uptime Kuma"
    cd /opt/uptime-kuma || exit
    $STD npm install --omit dev
    $STD npm run download-dist
    msg_ok "Updated Uptime Kuma"

    msg_info "Starting Service"
    systemctl start uptime-kuma
    msg_ok "Started Service"
    msg_ok "Updated successfully!"
  fi
  exit
}

# shellcheck disable=SC1090
source <(curl -fsSL "$REPO_BASE/misc/bootstrap/lxc")
