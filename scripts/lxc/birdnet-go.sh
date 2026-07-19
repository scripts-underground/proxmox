#!/usr/bin/env bash
REPO_BASE="${REPO_BASE:-https://raw.githubusercontent.com/scripts-underground/proxmox/main}"

# Sourced by lxc.bootstrap — never executed directly
# Copyright (c) 2021-2026 community-scripts ORG
# Author: MickLesk (CanbiZ)
# License: MIT | https://raw.githubusercontent.com/scripts-underground/proxmox/main/LICENSE
# Source: https://github.com/tphakala/birdnet-go

# shellcheck disable=SC2034
APP="BirdNET-Go"
var_tags="${var_tags:-monitoring;ai;nature}"
var_cpu="${var_cpu:-4}"
var_ram="${var_ram:-2048}"
var_disk="${var_disk:-12}"
var_os="${var_os:-debian}"
var_version="${var_version:-13}"
var_arm64="${var_arm64:-yes}"
var_unprivileged="${var_unprivileged:-1}"

function install_script() {
  msg_info "Installing Dependencies"
  $STD apt install -y libasound2 sox alsa-utils ffmpeg
  msg_ok "Installed Dependencies"

  fetch_and_deploy_gh_release "birdnet" "tphakala/birdnet-go" "prebuild" "latest" "/opt/birdnet" "birdnet-go-linux-$(get_system_arch)*.tar.gz"

  msg_info "Setting up BirdNET-Go"
  cp /opt/birdnet/birdnet-go /usr/local/bin/birdnet-go
  chmod +x /usr/local/bin/birdnet-go
  cp -r /opt/birdnet/libtensorflowlite_c.so /usr/local/lib/ 2> /dev/null || true
  cp -r /opt/birdnet/libonnxruntime.so /usr/local/lib/ 2> /dev/null || true
  ldconfig
  mkdir -p /opt/birdnet/data/clips
  msg_ok "Set up BirdNET-Go"

  msg_info "Creating Service"
  cat << EOF > /etc/systemd/system/birdnet.service
[Unit]
Description=BirdNET
After=network.target

[Service]
Type=simple
User=root
WorkingDirectory=/opt/birdnet/data
ExecStart=/usr/local/bin/birdnet-go realtime
Restart=on-failure
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF
  systemctl enable -q --now birdnet
  msg_ok "Created Service"
}

function post_install_script() {
  msg_ok "Completed Successfully!\n"
  echo -e "${CREATING}${GN}${APP} setup has been successfully initialized!${CL}"
  echo -e "${INFO}${YW} Access it using the following URL:${CL}"
  echo -e "${TAB}${GATEWAY}${BGN}http://${IP}:8080${CL}"
}

function update_script() {
  header_info
  check_container_storage
  check_container_resources
  if [[ ! -d /opt/birdnet ]]; then
    msg_error "No ${APP} Installation Found!"
    exit
  fi
  if check_for_gh_release "birdnet" "tphakala/birdnet-go"; then
    msg_info "Stopping Service"
    systemctl stop birdnet
    msg_ok "Stopped Service"
    fetch_and_deploy_gh_release "birdnet" "tphakala/birdnet-go" "prebuild" "latest" "/opt/birdnet" "birdnet-go-linux-$(get_system_arch)*.tar.gz"
    cp /opt/birdnet/birdnet-go /usr/local/bin/birdnet-go
    chmod +x /usr/local/bin/birdnet-go
    msg_info "Starting Service"
    systemctl start birdnet
    msg_ok "Started Service"
    msg_ok "Updated successfully!"
  fi
  exit
}

# shellcheck disable=SC1090
source <(curl -fsSL "$REPO_BASE/misc/bootstrap/lxc")
