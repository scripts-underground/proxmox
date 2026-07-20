#!/usr/bin/env bash
REPO_BASE="${REPO_BASE:-https://raw.githubusercontent.com/scripts-underground/proxmox/main}"

# Copyright (c) 2021-2026 community-scripts ORG
# Author: tteck (tteckster)
# License: MIT | https://raw.githubusercontent.com/scripts-underground/proxmox/main/LICENSE
# Source: https://github.com/bluenviron/mediamtx

# shellcheck disable=SC2034
# Read by the framework - shellcheck cannot see the caller
APP="MediaMTX"
var_tags="${var_tags:-media}"
var_cpu="${var_cpu:-2}"
var_ram="${var_ram:-2048}"
var_disk="${var_disk:-4}"
var_os="${var_os:-debian}"
var_version="${var_version:-13}"
var_arm64="${var_arm64:-yes}"
var_unprivileged="${var_unprivileged:-1}"
var_gpu="${var_gpu:-yes}"

function install_script() {
  msg_info "Installing Dependencies"
  $STD apt install -y ca-certificates
  msg_ok "Installed Dependencies"

  fetch_and_deploy_gh_release "mediamtx" "bluenviron/mediamtx" "prebuild" "latest" "/opt/mediamtx" "mediamtx*linux_$(get_system_arch).tar.gz"

  msg_info "Creating Service"
  cat << EOF > /etc/systemd/system/mediamtx.service
[Unit]
Description=MediaMTX Service
After=network.target

[Service]
Type=simple
User=root
WorkingDirectory=/opt/mediamtx
ExecStart=/opt/mediamtx/mediamtx
Restart=on-failure

[Install]
WantedBy=multi-user.target
EOF
  systemctl enable -q --now mediamtx
  msg_ok "Created Service"
}

function post_install_script() {
  msg_ok "Completed Successfully!\n"
  echo -e "${CREATING}${GN}${APP} setup has been successfully initialized!${CL}"
  echo -e "${INFO}${YW} Access it using the following URL:${CL}"
  echo -e "${TAB}${GATEWAY}${BGN}http://${IP}:8889${CL}"
}

function update_script() {
  header_info
  check_container_storage
  check_container_resources
  if [[ ! -d /opt/mediamtx ]]; then
    msg_error "No ${APP} Installation Found!"
    exit
  fi

  if check_for_gh_release "mediamtx" "bluenviron/mediamtx"; then
    msg_info "Stopping Service"
    systemctl stop mediamtx
    msg_ok "Stopped Service"

    cp /opt/mediamtx/mediamtx.yml /tmp/mediamtx.yml.bak
    fetch_and_deploy_gh_release "mediamtx" "bluenviron/mediamtx" "prebuild" "latest" "/opt/mediamtx" "mediamtx*linux_$(get_system_arch).tar.gz"
    cp /tmp/mediamtx.yml.bak /opt/mediamtx/mediamtx.yml

    msg_info "Starting Service"
    systemctl start mediamtx
    msg_ok "Started Service"
    msg_ok "Updated successfully!"
  fi
  exit
}

# framework bootstrap
# shellcheck disable=SC1090
# Dynamic URL resolved at runtime - shellcheck cannot follow
source <(curl -fsSL "$REPO_BASE/misc/bootstrap/lxc")
