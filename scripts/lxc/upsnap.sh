#!/usr/bin/env bash
REPO_BASE="${REPO_BASE:-https://raw.githubusercontent.com/scripts-underground/proxmox/main}"
# Sourced by lxc.bootstrap — never executed directly
# Copyright (c) 2021-2026 community-scripts ORG
# Author: Slaviša Arežina (tremor021)
# License: MIT | https://raw.githubusercontent.com/scripts-underground/proxmox/main/LICENSE
# Source: https://github.com/seriousm4x/UpSnap
# shellcheck disable=SC2034
APP="UpSnap"
var_tags="${var_tags:-network}"
var_cpu="${var_cpu:-1}"
var_ram="${var_ram:-512}"
var_disk="${var_disk:-2}"
var_os="${var_os:-debian}"
var_version="${var_version:-13}"
var_arm64="${var_arm64:-yes}"
var_unprivileged="${var_unprivileged:-1}"
function install_script() {
  msg_info "Installing Dependencies"
  $STD apt install -y \
    nmap \
    samba \
    samba-common-bin \
    openssh-client \
    openssh-server \
    sshpass
  msg_ok "Installed Dependencies"
  fetch_and_deploy_gh_release "upsnap" "seriousm4x/UpSnap" "prebuild" "latest" "/opt/upsnap" "UpSnap_*_linux_$(get_system_arch).zip"
  setcap 'cap_net_raw=+ep' /opt/upsnap/upsnap
  msg_info "Creating Service"
  cat << EOF > /etc/systemd/system/upsnap.service
[Unit]
Description=UpSnap Service
Documentation=https://github.com/seriousm4x/UpSnap/wiki
After=network.target

[Service]
Type=simple
User=root
Restart=on-failure
WorkingDirectory=/opt/upsnap
ExecStart=/opt/upsnap/upsnap serve --http=0.0.0.0:8090

[Install]
WantedBy=multi-user.target
EOF
  systemctl enable -q --now upsnap
  msg_ok "Created Service"
}
function post_install_script() {
  msg_ok "Completed successfully!\n"
  echo -e "${CREATING}${GN}${APP} setup has been successfully initialized!${CL}"
  echo -e "${INFO}${YW}Access it using the following URL:${CL}"
  echo -e "${GATEWAY}${BGN}http://${IP}:8090${CL}"
}
function update_script() {
  header_info
  check_container_storage
  check_container_resources
  if [[ ! -d /opt/upsnap ]]; then
    msg_error "No ${APP} Installation Found!"
    exit
  fi
  if check_for_gh_release "upsnap" "seriousm4x/UpSnap"; then
    msg_info "Stopping Services"
    systemctl stop upsnap
    msg_ok "Stopped Services"
    fetch_and_deploy_gh_release "upsnap" "seriousm4x/UpSnap" "prebuild" "latest" "/opt/upsnap" "UpSnap_*_linux_$(get_system_arch).zip"
    msg_info "Starting Services"
    systemctl start upsnap
    msg_ok "Started Services"
    msg_ok "Updated successfully!"
  fi
  exit
}
# shellcheck disable=SC1090
source <(curl -fsSL "$REPO_BASE/misc/bootstrap/lxc")
