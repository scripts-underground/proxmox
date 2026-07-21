#!/usr/bin/env bash
REPO_BASE="${REPO_BASE:-https://raw.githubusercontent.com/scripts-underground/proxmox/main}"
# Sourced by lxc.bootstrap — never executed directly
# Copyright (c) 2021-2026 community-scripts ORG
# Author: Jonathan (jd-apprentice)
# License: MIT | https://raw.githubusercontent.com/scripts-underground/proxmox/main/LICENSE
# Source: https://opengist.io/
# shellcheck disable=SC2034
APP="Opengist"
var_tags="${var_tags:-development}"
var_cpu="${var_cpu:-1}"
var_ram="${var_ram:-1024}"
var_disk="${var_disk:-8}"
var_os="${var_os:-debian}"
var_version="${var_version:-13}"
var_arm64="${var_arm64:-yes}"
var_unprivileged="${var_unprivileged:-1}"
function install_script() {
  msg_info "Installing Dependencies"
  $STD apt install -y git
  msg_ok "Installed Dependencies"
  fetch_and_deploy_gh_release "opengist" "thomiceli/opengist" "prebuild" "latest" "/opt/opengist" "opengist*linux-$(get_system_arch).tar.gz"
  mkdir -p /opt/opengist-data
  sed -i 's|opengist-home:.*|opengist-home: /opt/opengist-data|' /opt/opengist/config.yml
  msg_info "Creating Service"
  cat << 'EOF' > /etc/systemd/system/opengist.service
[Unit]
Description=Opengist server to manage your Gists
After=network.target
[Service]
WorkingDirectory=/opt/opengist
ExecStart=/opt/opengist/opengist --config /opt/opengist/config.yml
Restart=always
User=root
[Install]
WantedBy=multi-user.target
EOF
  systemctl enable -q --now opengist
  msg_ok "Created Service"
}
function post_install_script() {
  msg_ok "Completed Successfully!\n"
  echo -e "${CREATING}${GN}${APP} setup has been successfully initialized!${CL}"
  echo -e "${INFO}${YW} Access it using the following URL:${CL}"
  echo -e "${TAB}${GATEWAY}${BGN}http://${IP}:6157${CL}"
}
function update_script() {
  header_info
  check_container_storage
  check_container_resources
  if [[ ! -d /opt/opengist ]]; then
    msg_error "No ${APP} Installation Found!"
    exit
  fi
  if check_for_gh_release "opengist" "thomiceli/opengist"; then
    msg_info "Stopping Service"
    systemctl stop opengist
    msg_ok "Stopped Service"
    msg_info "Creating backup"
    mv /opt/opengist /opt/opengist-backup
    msg_ok "Backup created"
    fetch_and_deploy_gh_release "opengist" "thomiceli/opengist" "prebuild" "latest" "/opt/opengist" "opengist*linux-$(get_system_arch).tar.gz"
    msg_info "Restoring Configuration"
    mv /opt/opengist-backup/config.yml /opt/opengist/config.yml
    msg_ok "Configuration Restored"
    msg_info "Starting Service"
    systemctl start opengist
    msg_ok "Started Service"
    msg_ok "Updated successfully!"
  fi
  exit
}
# shellcheck disable=SC1090
source <(curl -fsSL "$REPO_BASE/misc/bootstrap/lxc")
