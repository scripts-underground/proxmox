#!/usr/bin/env bash
REPO_BASE="${REPO_BASE:-https://raw.githubusercontent.com/scripts-underground/proxmox/main}"
# Sourced by lxc.bootstrap — never executed directly
# Copyright (c) 2021-2026 community-scripts ORG
# Author: DragoQC
# License: MIT | https://raw.githubusercontent.com/scripts-underground/proxmox/main/LICENSE
# Source: https://discopanel.app/
# shellcheck disable=SC2034
APP="DiscoPanel"
var_tags="${var_tags:-gaming}"
var_cpu="${var_cpu:-2}"
var_ram="${var_ram:-2048}"
var_disk="${var_disk:-8}"
var_os="${var_os:-debian}"
var_version="${var_version:-13}"
var_arm64="${var_arm64:-yes}"
var_unprivileged="${var_unprivileged:-1}"
function install_script() {
  fetch_and_deploy_gh_release "discopanel" "nickheyer/discopanel" "prebuild" "latest" "/opt/discopanel" "discopanel-linux-$(get_system_arch).tar.gz"
  setup_docker
  msg_info "Creating Service"
  cat << EOF > /etc/systemd/system/discopanel.service
[Unit]
Description=DiscoPanel Service
After=network.target
[Service]
WorkingDirectory=/opt/discopanel
ExecStart=/opt/discopanel/discopanel-linux-$(get_system_arch)
Restart=always
[Install]
WantedBy=multi-user.target
EOF
  systemctl enable -q --now discopanel
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
  if [[ ! -d /opt/discopanel ]]; then
    msg_error "No ${APP} Installation Found!"
    exit
  fi
  if check_for_gh_release "discopanel" "nickheyer/discopanel"; then
    msg_info "Stopping Service"
    systemctl stop discopanel
    msg_ok "Stopped Service"
    CLEAN_INSTALL=1 fetch_and_deploy_gh_release "discopanel" "nickheyer/discopanel" "prebuild" "latest" "/opt/discopanel" "discopanel-linux-$(get_system_arch).tar.gz"
    msg_info "Starting Service"
    systemctl start discopanel
    msg_ok "Started Service"
    msg_ok "Updated successfully!"
  fi
  exit
}
# shellcheck disable=SC1090
source <(curl -fsSL "$REPO_BASE/misc/bootstrap/lxc")
