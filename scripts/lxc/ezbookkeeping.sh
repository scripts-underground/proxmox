#!/usr/bin/env bash
REPO_BASE="${REPO_BASE:-https://raw.githubusercontent.com/scripts-underground/proxmox/main}"
# Sourced by lxc.bootstrap — never executed directly
# Copyright (c) 2021-2026 community-scripts ORG
# Author: Slaviša Arežina (tremor021)
# License: MIT | https://raw.githubusercontent.com/scripts-underground/proxmox/main/LICENSE
# Source: https://ezbookkeeping.mayswind.net/
# shellcheck disable=SC2034
APP="ezBookkeeping"
var_tags="${var_tags:-finance}"
var_cpu="${var_cpu:-1}"
var_ram="${var_ram:-512}"
var_disk="${var_disk:-2}"
var_os="${var_os:-debian}"
var_version="${var_version:-13}"
var_arm64="${var_arm64:-yes}"
var_unprivileged="${var_unprivileged:-1}"
function install_script() {
  fetch_and_deploy_gh_release "ezbookkeeping" "mayswind/ezbookkeeping" "prebuild" "latest" "/opt/ezbookkeeping" "ezbookkeeping-*-linux-$(get_system_arch).tar.gz"
  msg_info "Setting up ezBookkeeping"
  SECRET_KEY=$(openssl rand -base64 32)
  sed -i "s/cert_key_file =/cert_key_file = \/etc\/ssl\/ezbookkeeping\/ezbookkeeping.key/" /opt/ezbookkeeping/conf/ezbookkeeping.ini
  sed -i "s/domain = localhost/domain = ${LOCAL_IP}/" /opt/ezbookkeeping/conf/ezbookkeeping.ini
  sed -i "s/secret_key =/secret_key = ${SECRET_KEY}/" /opt/ezbookkeeping/conf/ezbookkeeping.ini
  msg_ok "Configured ezBookkeeping"
  msg_info "Creating service"
  cat << 'EOF' > /etc/systemd/system/ezbookkeeping.service
[Unit]
Description=ezBookkeeping Service
After=network.target
[Service]
WorkingDirectory=/opt/ezbookkeeping
ExecStart=/opt/ezbookkeeping/ezbookkeeping server run
Restart=always
[Install]
WantedBy=multi-user.target
EOF
  systemctl enable -q --now ezbookkeeping
  msg_ok "Created service"
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
  if [[ ! -d /opt/ezbookkeeping ]]; then
    msg_error "No ${APP} Installation Found!"
    exit
  fi
  if check_for_gh_release "ezbookkeeping" "mayswind/ezbookkeeping"; then
    msg_info "Stopping Service"
    systemctl stop ezbookkeeping
    msg_ok "Stopped Service"
    CLEAN_INSTALL=1 fetch_and_deploy_gh_release "ezbookkeeping" "mayswind/ezbookkeeping" "prebuild" "latest" "/opt/ezbookkeeping" "ezbookkeeping-*-linux-$(get_system_arch).tar.gz"
    msg_info "Starting Service"
    systemctl start ezbookkeeping
    msg_ok "Started Service"
    msg_ok "Updated successfully!"
  fi
  exit
}
# shellcheck disable=SC1090
source <(curl -fsSL "$REPO_BASE/misc/bootstrap/lxc")
