#!/usr/bin/env bash
REPO_BASE="${REPO_BASE:-https://raw.githubusercontent.com/scripts-underground/proxmox/main}"
source <(curl -fsSL "$REPO_BASE/misc/build.func")

# Sourced by lxc.bootstrap — never executed directly
# Copyright (c) 2021-2026 tteck
# Author: tteck (tteckster)
# License: MIT | https://github.com/community-scripts/ProxmoxVED/raw/main/LICENSE
# Source: https://sonarr.tv/

APP="Sonarr"
var_tags="${var_tags:-arr;media}"
var_cpu="${var_cpu:-2}"
var_ram="${var_ram:-1024}"
var_disk="${var_disk:-4}"
var_os="${var_os:-debian}"
var_version="${var_version:-13}"
var_unprivileged="${var_unprivileged:-1}"

function update_script() {
  header_info
  check_container_storage
  check_container_resources
  if [[ ! -d /opt/Sonarr ]]; then msg_error "No ${APP} Installation Found!"; exit; fi
  if check_for_gh_release "Sonarr" "Sonarr/Sonarr"; then
    msg_info "Stopping Service"
    systemctl stop sonarr
    msg_ok "Stopped Service"
    CLEAN_INSTALL=1 fetch_and_deploy_gh_release "Sonarr" "Sonarr/Sonarr" "prebuild" "latest" "/opt/Sonarr" "Sonarr.main.*.linux-x64.tar.gz"
    msg_info "Starting Service"
    systemctl start sonarr
    msg_ok "Started Service"
    msg_ok "Updated Successfully"
  fi
  exit
}

function install_script() {
  color
  verb_ip6
  catch_errors
  setting_up_container
  network_check
  update_os

  msg_info "Installing Dependencies"
  $STD apt install -y sqlite3
  msg_ok "Installed Dependencies"

  fetch_and_deploy_gh_release "Sonarr" "Sonarr/Sonarr" "prebuild" "latest" "/opt/Sonarr" "Sonarr.main.*.linux-x64.tar.gz"
  mkdir -p /var/lib/sonarr/
  chmod 775 /var/lib/sonarr/

  msg_info "Creating Service"
  cat <<EOF >/etc/systemd/system/sonarr.service
[Unit]
Description=Sonarr Daemon
After=syslog.target network.target

[Service]
Type=simple
ExecStart=/opt/Sonarr/Sonarr -nobrowser -data=/var/lib/sonarr/
TimeoutStopSec=20
KillMode=process
Restart=on-failure

[Install]
WantedBy=multi-user.target
EOF
  systemctl enable -q --now sonarr
  msg_ok "Created Service"
}

function post_install_script() {
  msg_ok "Completed Successfully!\n"
  echo -e "${CREATING}${GN}${APP} setup has been successfully initialized!${CL}"
  echo -e "${INFO}${YW} Access it using the following URL:${CL}"
  echo -e "${TAB}${GATEWAY}${BGN}http://${IP}:8989${CL}"
}

source <(curl -fsSL "$REPO_BASE/misc/bootstrap/lxc")
