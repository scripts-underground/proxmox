#!/usr/bin/env bash
REPO_BASE="${REPO_BASE:-https://raw.githubusercontent.com/scripts-underground/proxmox/main}"

# Copyright (c) 2021-2026 community-scripts ORG
# Author: MickLesk (Canbiz)
# License: MIT | https://raw.githubusercontent.com/scripts-underground/proxmox/main/LICENSE
# Source: https://github.com/usememos/memos

APP="Memos"
var_tags="${var_tags:-notes}"
var_cpu="${var_cpu:-1}"
var_ram="${var_ram:-1024}"
var_disk="${var_disk:-3}"
var_os="${var_os:-debian}"
var_version="${var_version:-13}"
var_arm64="${var_arm64:-yes}"
var_unprivileged="${var_unprivileged:-1}"

function install_script() {
  msg_info "Installing Dependencies"
  $STD apt install -y curl sudo mc
  msg_ok "Installed Dependencies"

  fetch_and_deploy_gh_release "memos" "usememos/memos" "prebuild" "latest" "/opt/memos" "memos_*_linux_$(get_system_arch).tar.gz"

  chmod +x /opt/memos/memos

  msg_info "Creating Service"
  cat << EOF > /etc/systemd/system/memos.service
[Unit]
Description=Memos Service
After=network.target

[Service]
Type=simple
User=root
ExecStart=/opt/memos/memos --mode prod --port 9030
Restart=on-failure

[Install]
WantedBy=multi-user.target
EOF
  systemctl enable -q --now memos
  msg_ok "Created Service"
}

function post_install_script() {
  msg_ok "Completed successfully!\n"
  echo -e "${CREATING}${GN}${APP} setup has been successfully initialized!${CL}"
  echo -e "${INFO}${YW}Access it using the following URL:${CL}"
  echo -e "${GATEWAY}${BGN}http://${IP}:9030${CL}"
}

function update_script() {
  header_info
  check_container_storage
  check_container_resources
  if [[ ! -d /opt/memos ]]; then
    msg_error "No ${APP} Installation Found!"
    exit
  fi
  if check_for_gh_release "memos" "usememos/memos"; then
    msg_info "Stopping service"
    systemctl stop memos
    msg_ok "Service stopped"

    CLEAN_INSTALL=1 fetch_and_deploy_gh_release "memos" "usememos/memos" "prebuild" "latest" "/opt/memos" "memos_*_linux_$(get_system_arch).tar.gz"

    chmod +x /opt/memos/memos

    msg_info "Starting service"
    systemctl start memos
    msg_ok "Service started"
    msg_ok "Updated successfully!"
  fi
  exit
}

# shellcheck disable=SC1090
source <(curl -fsSL "$REPO_BASE/misc/bootstrap/lxc")
