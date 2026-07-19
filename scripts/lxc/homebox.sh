#!/usr/bin/env bash
REPO_BASE="${REPO_BASE:-https://raw.githubusercontent.com/scripts-underground/proxmox/main}"
# Sourced by lxc.bootstrap — never executed directly
# Copyright (c) 2021-2026 community-scripts ORG
# Author: tteck (tteckster)
# License: MIT | https://raw.githubusercontent.com/scripts-underground/proxmox/main/LICENSE
# Source: https://homebox.app/
# shellcheck disable=SC2034
APP="HomeBox"
var_tags="${var_tags:-inventory;household}"
var_cpu="${var_cpu:-2}"
var_ram="${var_ram:-1024}"
var_disk="${var_disk:-4}"
var_os="${var_os:-debian}"
var_version="${var_version:-13}"
var_arm64="${var_arm64:-yes}"
var_unprivileged="${var_unprivileged:-1}"
function install_script() {
  ARCH=$(uname -m)
  [[ "$ARCH" == "aarch64" ]] && ARCH="arm64"
  fetch_and_deploy_gh_release "homebox" "sysadminsmedia/homebox" "prebuild" "latest" "/opt/homebox" "homebox_Linux_${ARCH}.tar.gz"
  msg_info "Setting up HomeBox"
  AUTH_KEY=$(openssl rand -base64 32)
  cat << EOF > /opt/homebox/.env
HBOX_PORT=7745
HBOX_WEB_PORT=7745
HBOX_AUTH_API_KEY_PEPPER=${AUTH_KEY}
EOF
  msg_ok "Configured Homebox"
  msg_info "Creating Service"
  cat << 'EOF' > /etc/systemd/system/homebox.service
[Unit]
Description=Start Homebox Service
After=network.target
[Service]
WorkingDirectory=/opt/homebox
ExecStart=/opt/homebox/homebox
EnvironmentFile=/opt/homebox/.env
Restart=on-failure
[Install]
WantedBy=multi-user.target
EOF
  systemctl enable -q --now homebox
  msg_ok "Created Service"
}
function post_install_script() {
  msg_ok "Completed Successfully!\n"
  echo -e "${CREATING}${GN}${APP} setup has been successfully initialized!${CL}"
  echo -e "${INFO}${YW} Access it using the following URL:${CL}"
  echo -e "${TAB}${GATEWAY}${BGN}http://${IP}:7745${CL}"
}
function update_script() {
  header_info
  check_container_storage
  check_container_resources
  if [[ ! -d /opt/homebox ]]; then
    msg_error "No ${APP} Installation Found!"
    exit
  fi
  if check_for_gh_release "homebox" "sysadminsmedia/homebox"; then
    msg_info "Stopping Service"
    systemctl stop homebox
    msg_ok "Stopped Service"
    ARCH=$(uname -m)
    [[ "$ARCH" == "aarch64" ]] && ARCH="arm64"
    CLEAN_INSTALL=1 fetch_and_deploy_gh_release "homebox" "sysadminsmedia/homebox" "prebuild" "latest" "/opt/homebox" "homebox_Linux_${ARCH}.tar.gz"
    msg_info "Starting Service"
    systemctl start homebox
    msg_ok "Started Service"
    msg_ok "Updated successfully!"
  fi
  exit
}
# shellcheck disable=SC1090
source <(curl -fsSL "$REPO_BASE/misc/bootstrap/lxc")
