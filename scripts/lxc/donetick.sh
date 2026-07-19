#!/usr/bin/env bash
REPO_BASE="${REPO_BASE:-https://raw.githubusercontent.com/scripts-underground/proxmox/main}"
# Sourced by lxc.bootstrap — never executed directly
# Copyright (c) 2021-2026 community-scripts ORG
# Author: fstof
# License: MIT | https://raw.githubusercontent.com/scripts-underground/proxmox/main/LICENSE
# Source: https://github.com/donetick/donetick
# shellcheck disable=SC2034
APP="Donetick"
var_tags="${var_tags:-productivity;tasks}"
var_cpu="${var_cpu:-2}"
var_ram="${var_ram:-2048}"
var_disk="${var_disk:-8}"
var_os="${var_os:-debian}"
var_version="${var_version:-13}"
var_arm64="${var_arm64:-yes}"
var_unprivileged="${var_unprivileged:-1}"
function install_script() {
  msg_info "Installing Dependencies"
  $STD apt install -y ca-certificates
  msg_ok "Installed Dependencies"
  ARCH=$(uname -m)
  [[ "$ARCH" == "aarch64" ]] && ARCH="arm64"
  fetch_and_deploy_gh_release "donetick" "donetick/donetick" "prebuild" "latest" "/opt/donetick" "donetick_Linux_${ARCH}.tar.gz"
  msg_info "Setup Donetick"
  cd /opt/donetick || exit
  TOKEN=$(openssl rand -hex 16)
  sed -i -e "s/change_this_to_a_secure_random_string_32_characters_long/${TOKEN}/g" config/selfhosted.yaml
  msg_ok "Setup Donetick"
  msg_info "Creating Service"
  cat << 'EOF' > /etc/systemd/system/donetick.service
[Unit]
Description=donetick Service
After=network.target
[Service]
Environment="DT_ENV=selfhosted"
WorkingDirectory=/opt/donetick
ExecStart=/opt/donetick/donetick
Restart=always
[Install]
WantedBy=multi-user.target
EOF
  systemctl enable -q --now donetick
  msg_ok "Created Service"
}
function post_install_script() {
  msg_ok "Completed Successfully!\n"
  echo -e "${CREATING}${GN}${APP} setup has been successfully initialized!${CL}"
  echo -e "${INFO}${YW} Access it using the following URL:${CL}"
  echo -e "${TAB}${GATEWAY}${BGN}http://${IP}:2021${CL}"
}
function update_script() {
  header_info
  check_container_storage
  check_container_resources
  if [[ ! -d /opt/donetick ]]; then
    msg_error "No ${APP} Installation Found!"
    exit
  fi
  if check_for_gh_release "donetick" "donetick/donetick"; then
    msg_info "Stopping Service"
    systemctl stop donetick
    msg_ok "Stopped Service"
    ARCH=$(uname -m)
    [[ "$ARCH" == "aarch64" ]] && ARCH="arm64"
    CLEAN_INSTALL=1 fetch_and_deploy_gh_release "donetick" "donetick/donetick" "prebuild" "latest" "/opt/donetick" "donetick_Linux_${ARCH}.tar.gz"
    msg_info "Starting Service"
    systemctl start donetick
    msg_ok "Started Service"
    msg_ok "Updated successfully!"
  fi
  exit
}
# shellcheck disable=SC1090
source <(curl -fsSL "$REPO_BASE/misc/bootstrap/lxc")
