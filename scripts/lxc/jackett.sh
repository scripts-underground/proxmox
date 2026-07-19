#!/usr/bin/env bash
REPO_BASE="${REPO_BASE:-https://raw.githubusercontent.com/scripts-underground/proxmox/main}"
# Sourced by lxc.bootstrap — never executed directly
# Copyright (c) 2021-2026 community-scripts ORG
# Author: tteck (tteckster)
# License: MIT | https://raw.githubusercontent.com/scripts-underground/proxmox/main/LICENSE
# Source: https://github.com/Jackett/Jackett
# shellcheck disable=SC2034
APP="Jackett"
var_tags="${var_tags:-torrent}"
var_cpu="${var_cpu:-1}"
var_ram="${var_ram:-512}"
var_disk="${var_disk:-2}"
var_os="${var_os:-debian}"
var_version="${var_version:-13}"
var_arm64="${var_arm64:-yes}"
var_unprivileged="${var_unprivileged:-1}"
function install_script() {
  msg_info "Installing Dependencies"
  $STD apt install -y libicu-dev
  msg_ok "Installed Dependencies"
  ARCH=$(uname -m)
  [[ "$ARCH" == "x86_64" ]] && ARCH="AMDx64"
  [[ "$ARCH" == "aarch64" ]] && ARCH="ARM64"
  fetch_and_deploy_gh_release "jackett" "Jackett/Jackett" "prebuild" "latest" "/opt/Jackett" "Jackett.Binaries.Linux${ARCH}.tar.gz"
  cat << EOF > /opt/.env
DisableRootWarning=true
EOF
  msg_info "Creating Service"
  cat << 'EOF' > /etc/systemd/system/jackett.service
[Unit]
Description=Jackett Daemon
After=network.target
[Service]
SyslogIdentifier=jackett
Restart=always
RestartSec=5
TimeoutStopSec=30
EnvironmentFile=/opt/.env
Type=simple
WorkingDirectory=/opt/Jackett
ExecStart=/bin/sh /opt/Jackett/jackett_launcher.sh
Restart=on-failure
[Install]
WantedBy=multi-user.target
EOF
  systemctl enable -q --now jackett
  msg_ok "Created Service"
}
function post_install_script() {
  msg_ok "Completed Successfully!\n"
  echo -e "${CREATING}${GN}${APP} setup has been successfully initialized!${CL}"
  echo -e "${INFO}${YW} Access it using the following URL:${CL}"
  echo -e "${TAB}${GATEWAY}${BGN}http://${IP}:9117${CL}"
}
function update_script() {
  header_info
  check_container_storage
  check_container_resources
  if [[ ! -d /opt/Jackett ]]; then
    msg_error "No ${APP} Installation Found!"
    exit
  fi
  if check_for_gh_release "jackett" "Jackett/Jackett"; then
    msg_info "Stopping Service"
    systemctl stop jackett
    msg_ok "Stopped Service"
    ARCH=$(uname -m)
    [[ "$ARCH" == "x86_64" ]] && ARCH="AMDx64"
    [[ "$ARCH" == "aarch64" ]] && ARCH="ARM64"
    CLEAN_INSTALL=1 fetch_and_deploy_gh_release "jackett" "Jackett/Jackett" "prebuild" "latest" "/opt/Jackett" "Jackett.Binaries.Linux${ARCH}.tar.gz"
  cat << EOF > /opt/.env
DisableRootWarning=true
EOF
    msg_info "Starting Service"
    systemctl start jackett
    msg_ok "Started Service"
    msg_ok "Updated successfully!"
  fi
  exit
}
# shellcheck disable=SC1090
source <(curl -fsSL "$REPO_BASE/misc/bootstrap/lxc")
