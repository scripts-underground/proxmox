#!/usr/bin/env bash
REPO_BASE="${REPO_BASE:-https://raw.githubusercontent.com/scripts-underground/proxmox/main}"

# Sourced by lxc.bootstrap — never executed directly
# Copyright (c) 2021-2026 community-scripts ORG
# Author: tteck (tteckster)
# License: MIT | https://raw.githubusercontent.com/scripts-underground/proxmox/main/LICENSE
# Source: https://lidarr.audio/

# shellcheck disable=SC2034
# Read by the framework - shellcheck cannot see the caller
APP="Lidarr"
var_tags="${var_tags:-arr;torrent;usenet}"
var_cpu="${var_cpu:-2}"
var_ram="${var_ram:-1024}"
var_disk="${var_disk:-4}"
var_os="${var_os:-debian}"
var_version="${var_version:-13}"
var_arm64="${var_arm64:-yes}"
var_unprivileged="${var_unprivileged:-1}"

function install_script() {
  msg_info "Installing Dependencies"
  $STD apt install -y \
    sqlite3 \
    libchromaprint-tools \
    libicu-dev \
    mediainfo
  msg_ok "Installed Dependencies"

  fetch_and_deploy_gh_release "lidarr" "Lidarr/Lidarr" "prebuild" "latest" "/opt/Lidarr" "Lidarr.master.*.linux-core-$(get_system_arch).tar.gz"

  msg_info "Configuring Lidarr"
  mkdir -p /var/lib/lidarr/
  chmod 775 /var/lib/lidarr/
  chmod 775 /opt/Lidarr
  msg_ok "Configured Lidarr"

  msg_info "Creating Service"
  cat << EOF > /etc/systemd/system/lidarr.service
[Unit]
Description=Lidarr Daemon
After=syslog.target network.target

[Service]
UMask=0002
Type=simple
ExecStart=/opt/Lidarr/Lidarr -nobrowser -data=/var/lib/lidarr/
TimeoutStopSec=20
KillMode=process
Restart=on-failure

[Install]
WantedBy=multi-user.target
EOF
  systemctl enable -q --now lidarr
  msg_ok "Created Service"
}

function post_install_script() {
  msg_ok "Completed Successfully!\n"
  echo -e "${CREATING}${GN}${APP} setup has been successfully initialized!${CL}"
  echo -e "${INFO}${YW} Access it using the following URL:${CL}"
  echo -e "${TAB}${GATEWAY}${BGN}http://${IP}:8686${CL}"
}

function update_script() {
  header_info
  check_container_storage
  check_container_resources

  if [[ ! -d /var/lib/lidarr/ ]]; then
    msg_error "No ${APP} Installation Found!"
    exit
  fi

  if check_for_gh_release "lidarr" "Lidarr/Lidarr"; then
    msg_info "Stopping Service"
    systemctl stop lidarr
    msg_ok "Stopped Service"

    fetch_and_deploy_gh_release "lidarr" "Lidarr/Lidarr" "prebuild" "latest" "/opt/Lidarr" "Lidarr.master.*.linux-core-$(get_system_arch).tar.gz"
    chmod 775 /opt/Lidarr

    msg_info "Starting Service"
    systemctl start lidarr
    msg_ok "Started Service"
    msg_ok "Updated successfully!"
  fi
  exit
}

# framework bootstrap
# shellcheck disable=SC1090
# Dynamic URL resolved at runtime - shellcheck cannot follow
source <(curl -fsSL "$REPO_BASE/misc/bootstrap/lxc")
