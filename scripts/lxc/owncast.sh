#!/usr/bin/env bash
REPO_BASE="${REPO_BASE:-https://raw.githubusercontent.com/scripts-underground/proxmox/main}"

# Copyright (c) 2021-2026 community-scripts ORG
# Author: tteck (tteckster)
# License: MIT | https://raw.githubusercontent.com/scripts-underground/proxmox/main/LICENSE
# Source: https://owncast.online/

APP="Owncast"
var_tags="${var_tags:-broadcasting}"
var_cpu="${var_cpu:-2}"
var_ram="${var_ram:-2048}"
var_disk="${var_disk:-10}"
var_os="${var_os:-debian}"
var_version="${var_version:-13}"
var_arm64="${var_arm64:-yes}"
var_unprivileged="${var_unprivileged:-1}"

function install_script() {
  msg_info "Installing Dependencies"
  $STD apt install -y ffmpeg
  msg_ok "Installed Dependencies"

  ARCH=$(uname -m)
  [[ "$ARCH" == "x86_64" ]] && ARCH="64bit"
  [[ "$ARCH" == "aarch64" ]] && ARCH="arm64"
  fetch_and_deploy_gh_release "owncast" "owncast/owncast" "prebuild" "latest" "/opt/owncast" "owncast*linux-${ARCH}.zip"

  msg_info "Creating Service"
  cat << 'EOF' > /etc/systemd/system/owncast.service
[Unit]
Description=Owncast Service
After=network.target

[Service]
Type=simple
WorkingDirectory=/opt/owncast
ExecStart=/opt/owncast/owncast
Restart=on-failure

[Install]
WantedBy=multi-user.target
EOF
  systemctl enable -q --now owncast
  msg_ok "Created Service"
}

function post_install_script() {
  msg_ok "Completed successfully!\n"
  echo -e "${CREATING}${GN}${APP} setup has been successfully initialized!${CL}"
  echo -e "${INFO}${YW}Access it using the following URL:${CL}"
  echo -e "${GATEWAY}${BGN}http://${IP}:8080/admin${CL}"
}

function update_script() {
  header_info
  check_container_storage
  check_container_resources
  if [[ ! -d /opt/owncast ]]; then
    msg_error "No ${APP} Installation Found!"
    exit
  fi
  if check_for_gh_release "owncast" "owncast/owncast"; then
    msg_info "Stopping Service"
    systemctl stop owncast
    msg_ok "Stopped Service"

    ARCH=$(uname -m)
    [[ "$ARCH" == "x86_64" ]] && ARCH="64bit"
    [[ "$ARCH" == "aarch64" ]] && ARCH="arm64"
    fetch_and_deploy_gh_release "owncast" "owncast/owncast" "prebuild" "latest" "/opt/owncast" "owncast*linux-${ARCH}.zip"

    msg_info "Starting Service"
    systemctl start owncast
    msg_ok "Started Service"
    msg_ok "Updated successfully!"
  fi
  exit
}

# shellcheck disable=SC1090
# Dynamic URL resolved at runtime
source <(curl -fsSL "$REPO_BASE/misc/bootstrap/lxc")
