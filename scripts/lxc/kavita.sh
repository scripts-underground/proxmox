#!/usr/bin/env bash
REPO_BASE="${REPO_BASE:-https://raw.githubusercontent.com/scripts-underground/proxmox/main}"
# Sourced by lxc.bootstrap — never executed directly
# Copyright (c) 2021-2026 community-scripts ORG
# Author: tteck (tteckster)
# License: MIT | https://raw.githubusercontent.com/scripts-underground/proxmox/main/LICENSE
# Source: https://www.kavitareader.com/
# shellcheck disable=SC2034
APP="Kavita"
var_tags="${var_tags:-reader}"
var_cpu="${var_cpu:-2}"
var_ram="${var_ram:-2048}"
var_disk="${var_disk:-8}"
var_os="${var_os:-debian}"
var_version="${var_version:-13}"
var_arm64="${var_arm64:-yes}"
var_unprivileged="${var_unprivileged:-1}"
function install_script() {
  msg_info "Installing Dependencies"
  $STD apt install -y libicu-dev
  msg_ok "Installed Dependencies"
  ARCH=$(uname -m)
  [[ "$ARCH" == "x86_64" ]] && ARCH="x64"
  [[ "$ARCH" == "aarch64" ]] && ARCH="arm64"
  fetch_and_deploy_gh_release "Kavita" "Kareadita/Kavita" "prebuild" "latest" "/opt/Kavita" "kavita-linux-${ARCH}.tar.gz"
  chmod +x /opt/Kavita/Kavita && chown root:root /opt/Kavita/Kavita
  msg_info "Creating Service"
  cat << 'EOF' > /etc/systemd/system/kavita.service
[Unit]
Description=Kavita Daemon
After=network.target
[Service]
Type=simple
WorkingDirectory=/opt/Kavita
ExecStart=/opt/Kavita/Kavita
Restart=on-failure
[Install]
WantedBy=multi-user.target
EOF
  systemctl enable -q --now kavita
  msg_ok "Created Service"
}
function post_install_script() {
  msg_ok "Completed Successfully!\n"
  echo -e "${CREATING}${GN}${APP} setup has been successfully initialized!${CL}"
  echo -e "${INFO}${YW} Access it using the following URL:${CL}"
  echo -e "${TAB}${GATEWAY}${BGN}http://${IP}:5000${CL}"
}
function update_script() {
  header_info
  check_container_storage
  check_container_resources
  if [[ ! -d /opt/Kavita ]]; then
    msg_error "No ${APP} Installation Found!"
    exit
  fi
  if check_for_gh_release "Kavita" "Kareadita/Kavita"; then
    msg_info "Stopping Service"
    systemctl stop kavita
    msg_ok "Stopped Service"
    ARCH=$(uname -m)
    [[ "$ARCH" == "x86_64" ]] && ARCH="x64"
    [[ "$ARCH" == "aarch64" ]] && ARCH="arm64"
    CLEAN_INSTALL=1 fetch_and_deploy_gh_release "Kavita" "Kareadita/Kavita" "prebuild" "latest" "/opt/Kavita" "kavita-linux-${ARCH}.tar.gz"
  chmod +x /opt/Kavita/Kavita && chown root:root /opt/Kavita/Kavita
    msg_info "Starting Service"
    systemctl start kavita
    msg_ok "Started Service"
    msg_ok "Updated successfully!"
  fi
  exit
}
# shellcheck disable=SC1090
source <(curl -fsSL "$REPO_BASE/misc/bootstrap/lxc")
