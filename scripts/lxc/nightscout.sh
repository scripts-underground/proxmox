#!/usr/bin/env bash
REPO_BASE="${REPO_BASE:-https://raw.githubusercontent.com/scripts-underground/proxmox/main}"

# Sourced by lxc.bootstrap — never executed directly
# Copyright (c) 2021-2026 community-scripts ORG
# Author: aendel
# License: MIT | https://raw.githubusercontent.com/scripts-underground/proxmox/main/LICENSE
# Source: https://github.com/nightscout/cgm-remote-monitor

# shellcheck disable=SC2034
# Read by the framework - shellcheck cannot see the caller
APP="Nightscout"
var_tags="${var_tags:-health}"
var_cpu="${var_cpu:-2}"
var_ram="${var_ram:-2048}"
var_disk="${var_disk:-10}"
var_os="${var_os:-debian}"
var_version="${var_version:-13}"
var_arm64="${var_arm64:-yes}"
var_unprivileged="${var_unprivileged:-1}"

function install_script() {
  msg_info "Installing Dependencies"
  $STD apt install -y \
    build-essential \
    libssl-dev \
    openssl
  msg_ok "Installed Dependencies"

  MONGO_VERSION="8.0" setup_mongodb
  NODE_VERSION="22" setup_nodejs
  fetch_and_deploy_gh_release "nightscout" "nightscout/cgm-remote-monitor" "tarball"

  msg_info "Installing Nightscout"
  $STD npm install --prefix /opt/nightscout
  msg_ok "Installed Nightscout"

  msg_info "Creating Service"
  useradd -s /bin/bash -m nightscout
  chown -R nightscout:nightscout /opt/nightscout
  API_SECRET=$(openssl rand -hex 16)
  cat << EOF > /opt/nightscout/my.env
MONGO_CONNECTION=mongodb://127.0.0.1:27017/nightscout
BASE_URL=http://localhost:1337
API_SECRET=${API_SECRET}
DISPLAY_UNITS=mg/dl
ENABLE=careportal boluscalc food bwp cage sage iage iob cob basal ar2 rawbg pushover bgi pump openaps pvb linear custom
INSECURE_USE_HTTP=true
EOF
  chown nightscout:nightscout /opt/nightscout/my.env
  cat << EOF > /etc/systemd/system/nightscout.service
[Unit]
Description=Nightscout CGM Service
After=network.target mongodb.service

[Service]
Type=simple
User=nightscout
WorkingDirectory=/opt/nightscout
EnvironmentFile=/opt/nightscout/my.env
ExecStart=/usr/bin/npm start
Restart=always

[Install]
WantedBy=multi-user.target
EOF
  systemctl enable -q --now nightscout
  msg_ok "Created Service"

  cat << EOF > ~/nightscout.creds
Nightscout Credentials
API_SECRET: ${API_SECRET}
EOF
}

function post_install_script() {
  msg_ok "Completed Successfully!\n"
  echo -e "${CREATING}${GN}${APP} setup has been successfully initialized!${CL}"
  echo -e "${INFO}${YW}Access it using the following URL:${CL}"
  echo -e "${GATEWAY}${BGN}http://${IP}:1337${CL}"
}

function update_script() {
  header_info
  check_container_storage
  check_container_resources
  if [[ ! -d /opt/nightscout ]]; then
    msg_error "No ${APP} Installation Found!"
    exit
  fi

  if check_for_gh_release "nightscout" "nightscout/cgm-remote-monitor"; then
    msg_info "Stopping Service"
    systemctl stop nightscout
    msg_ok "Stopped Service"

    fetch_and_deploy_gh_release "nightscout" "nightscout/cgm-remote-monitor" "tarball"

    msg_info "Updating Nightscout"
    cd /opt/nightscout || exit
    $STD npm install
    msg_ok "Updated Nightscout"

    msg_info "Starting Service"
    systemctl start nightscout
    msg_ok "Started Service"
    msg_ok "Updated successfully!"
  fi
  exit
}

# framework bootstrap
# shellcheck disable=SC1090
# Dynamic URL resolved at runtime - shellcheck cannot follow
source <(curl -fsSL "$REPO_BASE/misc/bootstrap/lxc")
