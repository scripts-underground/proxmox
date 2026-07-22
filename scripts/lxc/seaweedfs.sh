#!/usr/bin/env bash
REPO_BASE="${REPO_BASE:-https://raw.githubusercontent.com/scripts-underground/proxmox/main}"

# Sourced by lxc.bootstrap — never executed directly
# Copyright (c) 2021-2026 community-scripts ORG
# Author: MickLesk (CanbiZ)
# License: MIT | https://raw.githubusercontent.com/scripts-underground/proxmox/main/LICENSE
# Source: https://github.com/seaweedfs/seaweedfs

# shellcheck disable=SC2034
# Read by the framework - shellcheck cannot see the caller
APP="SeaweedFS"
var_tags="${var_tags:-storage;s3;filesystem}"
var_cpu="${var_cpu:-2}"
var_ram="${var_ram:-2048}"
var_disk="${var_disk:-16}"
var_os="${var_os:-debian}"
var_version="${var_version:-13}"
var_arm64="${var_arm64:-yes}"
var_fuse="${var_fuse:-yes}"
var_unprivileged="${var_unprivileged:-1}"

function install_script() {
  msg_info "Installing Dependencies"
  $STD apt install -y fuse3
  msg_ok "Installed Dependencies"

  fetch_and_deploy_gh_release "seaweedfs" "seaweedfs/seaweedfs" "prebuild" "latest" "/opt/seaweedfs" "linux_$(get_system_arch).tar.gz"

  msg_info "Setting up SeaweedFS"
  mkdir -p /opt/seaweedfs-data
  ln -sf /opt/seaweedfs/weed /usr/local/bin/weed
  msg_ok "Set up SeaweedFS"

  msg_info "Creating Service"
  cat << EOF > /etc/systemd/system/seaweedfs.service
[Unit]
Description=SeaweedFS Server
After=network.target

[Service]
Type=simple
User=root
WorkingDirectory=/opt/seaweedfs
ExecStart=/opt/seaweedfs/weed server -dir=/opt/seaweedfs-data -master.port=9333 -volume.port=8080 -filer -s3
Restart=on-failure
RestartSec=5
LimitNOFILE=65536

[Install]
WantedBy=multi-user.target
EOF
  systemctl enable -q --now seaweedfs
  msg_ok "Created Service"
}

function post_install_script() {
  msg_ok "Completed Successfully!\n"
  echo -e "${CREATING}${GN}${APP} setup has been successfully initialized!${CL}"
  echo -e "${INFO}${YW}Access it using the following URL:${CL}"
  echo -e "${GATEWAY}${BGN}http://${IP}:9333${CL}"
}

function update_script() {
  header_info
  check_container_storage
  check_container_resources

  if [[ ! -f /opt/seaweedfs/weed ]]; then
    msg_error "No ${APP} Installation Found!"
    exit
  fi

  if check_for_gh_release "seaweedfs" "seaweedfs/seaweedfs"; then
    msg_info "Stopping Service"
    systemctl stop seaweedfs
    msg_ok "Stopped Service"

    fetch_and_deploy_gh_release "seaweedfs" "seaweedfs/seaweedfs" "prebuild" "latest" "/opt/seaweedfs" "linux_$(get_system_arch).tar.gz"

    msg_info "Starting Service"
    systemctl start seaweedfs
    msg_ok "Started Service"
    msg_ok "Updated successfully!"
  fi
  exit
}

# framework bootstrap
# shellcheck disable=SC1090
# Dynamic URL resolved at runtime - shellcheck cannot follow
source <(curl -fsSL "$REPO_BASE/misc/bootstrap/lxc")
