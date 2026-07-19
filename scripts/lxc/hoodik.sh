#!/usr/bin/env bash
REPO_BASE="${REPO_BASE:-https://raw.githubusercontent.com/scripts-underground/proxmox/main}"
# Sourced by lxc.bootstrap — never executed directly
# Copyright (c) 2021-2026 community-scripts ORG
# Author: MickLesk (CanbiZ)
# License: MIT | https://raw.githubusercontent.com/scripts-underground/proxmox/main/LICENSE
# Source: https://github.com/hudikhq/hoodik
# shellcheck disable=SC2034
APP="Hoodik"
var_tags="${var_tags:-cloud;storage}"
var_cpu="${var_cpu:-1}"
var_ram="${var_ram:-512}"
var_disk="${var_disk:-2}"
var_os="${var_os:-debian}"
var_version="${var_version:-13}"
var_arm64="${var_arm64:-yes}"
var_unprivileged="${var_unprivileged:-1}"
function install_script() {
  ARCH=$(uname -m)
  [[ "$ARCH" == "aarch64" ]] && ARCH="arm64"
  fetch_and_deploy_gh_release "hoodik" "hudikhq/hoodik" "prebuild" "latest" "/opt/hoodik" "*${ARCH}.tar.gz"
  msg_info "Configuring Hoodik"
  mkdir -p /opt/hoodik_data
  JWT_SECRET=$(openssl rand -base64 32 | tr -dc 'a-zA-Z0-9' | cut -c1-32)
  cat << EOF > /opt/hoodik/.env
DATA_DIR=/opt/hoodik_data
HTTP_PORT=5443
HTTP_ADDRESS=0.0.0.0
JWT_SECRET=${JWT_SECRET}
APP_URL=http://${LOCAL_IP}:5443
SSL_DISABLED=true
COOKIE_SECURE=false
COOKIE_HTTP_ONLY=false
MAILER_TYPE=none
RUST_LOG=hoodik=info,error=info
EOF
  msg_ok "Configured Hoodik"
  msg_info "Creating Service"
  cat << 'EOF' > /etc/systemd/system/hoodik.service
[Unit]
Description=Hoodik - Encrypted File Storage
After=network.target
[Service]
Type=simple
User=root
WorkingDirectory=/opt/hoodik_data
EnvironmentFile=/opt/hoodik/.env
ExecStart=/opt/hoodik/hoodik
Restart=always
RestartSec=5
[Install]
WantedBy=multi-user.target
EOF
  systemctl enable -q --now hoodik
  msg_ok "Created Service"
}
function post_install_script() {
  msg_ok "Completed Successfully!\n"
  echo -e "${CREATING}${GN}${APP} setup has been successfully initialized!${CL}"
  echo -e "${INFO}${YW} Access it using the following URL:${CL}"
  echo -e "${TAB}${GATEWAY}${BGN}http://${IP}:5443${CL}"
}
function update_script() {
  header_info
  check_container_storage
  check_container_resources
  if [[ ! -d /opt/hoodik ]]; then
    msg_error "No ${APP} Installation Found!"
    exit
  fi
  if check_for_gh_release "hoodik" "hudikhq/hoodik"; then
    msg_info "Stopping Service"
    systemctl stop hoodik
    msg_ok "Stopped Service"
    ARCH=$(uname -m)
    [[ "$ARCH" == "aarch64" ]] && ARCH="arm64"
    CLEAN_INSTALL=1 fetch_and_deploy_gh_release "hoodik" "hudikhq/hoodik" "prebuild" "latest" "/opt/hoodik" "*${ARCH}.tar.gz"
    msg_info "Starting Service"
    systemctl start hoodik
    msg_ok "Started Service"
    msg_ok "Updated successfully!"
  fi
  exit
}
# shellcheck disable=SC1090
source <(curl -fsSL "$REPO_BASE/misc/bootstrap/lxc")
