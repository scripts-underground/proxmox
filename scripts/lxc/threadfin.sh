#!/usr/bin/env bash
REPO_BASE="${REPO_BASE:-https://raw.githubusercontent.com/scripts-underground/proxmox/main}"

# Copyright (c) 2021-2026 community-scripts ORG
# Author: tteck (tteckster)
# License: MIT | https://raw.githubusercontent.com/scripts-underground/proxmox/main/LICENSE
# Source: https://github.com/Threadfin/Threadfin

# shellcheck disable=SC2034
# Read by the framework - shellcheck cannot see the caller
APP="Threadfin"
var_tags="${var_tags:-media}"
var_cpu="${var_cpu:-1}"
var_ram="${var_ram:-1024}"
var_disk="${var_disk:-4}"
var_os="${var_os:-debian}"
var_version="${var_version:-13}"
var_arm64="${var_arm64:-yes}"
var_unprivileged="${var_unprivileged:-1}"
var_gpu="${var_gpu:-yes}"

function install_script() {
  setup_hwaccel

  msg_info "Installing Dependencies"
  $STD apt install -y \
    ffmpeg \
    vlc
  msg_ok "Installed Dependencies"

  ARCH=$(uname -m)
  [[ "$ARCH" == "x86_64" ]] && ARCH="amd64"
  [[ "$ARCH" == "aarch64" ]] && ARCH="arm64"
  fetch_and_deploy_gh_release "threadfin-app" "threadfin/threadfin" "singlefile" "latest" "/opt/threadfin" "Threadfin_linux_${ARCH}"
  mv /opt/threadfin/threadfin-app /opt/threadfin/threadfin

  msg_info "Creating Service"
  cat << EOF > /etc/systemd/system/threadfin.service
[Unit]
Description=Threadfin: M3U Proxy for Plex DVR and Emby/Jellyfin Live TV
After=syslog.target network.target
[Service]
Type=simple
WorkingDirectory=/opt/threadfin
ExecStart=/opt/threadfin/threadfin
TimeoutStopSec=20
KillMode=process
Restart=on-failure
[Install]
WantedBy=multi-user.target
EOF
  systemctl enable -q --now threadfin
  msg_ok "Created Service"
}

function post_install_script() {
  msg_ok "Completed Successfully!\n"
  echo -e "${CREATING}${GN}${APP} setup has been successfully initialized!${CL}"
  echo -e "${INFO}${YW}Access it using the following URL:${CL}"
  echo -e "${TAB}${GATEWAY}${BGN}http://${IP}:34400/web${CL}"
}

function update_script() {
  header_info
  check_container_storage
  check_container_resources
  if [[ ! -d /opt/threadfin ]]; then
    msg_error "No ${APP} Installation Found!"
    exit
  fi

  if check_for_gh_release "threadfin-app" "threadfin/threadfin"; then
    msg_info "Stopping Service"
    systemctl stop threadfin
    msg_ok "Stopped Service"

    ARCH=$(uname -m)
    [[ "$ARCH" == "x86_64" ]] && ARCH="amd64"
    [[ "$ARCH" == "aarch64" ]] && ARCH="arm64"
    fetch_and_deploy_gh_release "threadfin-app" "threadfin/threadfin" "singlefile" "latest" "/opt/threadfin" "Threadfin_linux_${ARCH}"
    mv /opt/threadfin/threadfin-app /opt/threadfin/threadfin

    msg_info "Starting Service"
    systemctl start threadfin
    msg_ok "Started Service"
    msg_ok "Updated successfully!"
  fi
  exit
}

# framework bootstrap
# shellcheck disable=SC1090
# Dynamic URL resolved at runtime - shellcheck cannot follow
source <(curl -fsSL "$REPO_BASE/misc/bootstrap/lxc")
