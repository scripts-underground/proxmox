#!/usr/bin/env bash
REPO_BASE="${REPO_BASE:-https://raw.githubusercontent.com/scripts-underground/proxmox/main}"

# Copyright (c) 2021-2026 community-scripts ORG
# Author: tteck (tteckster)
# License: MIT | https://raw.githubusercontent.com/scripts-underground/proxmox/main/LICENSE
# Source: https://home.tdarr.io/

# shellcheck disable=SC2034
# Read by the framework - shellcheck cannot see the caller
APP="Tdarr"
var_tags="${var_tags:-arr}"
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
  $STD apt install -y handbrake-cli
  msg_ok "Installed Dependencies"

  msg_info "Installing Tdarr"
  mkdir -p /opt/tdarr
  cd /opt/tdarr || exit
  ARCH_STRING=$(uname -m)
  [[ "$ARCH_STRING" == "x86_64" ]] && ARCH_STRING="x64"
  [[ "$ARCH_STRING" == "aarch64" ]] && ARCH_STRING="arm64"
  RELEASE=$(curl_with_retry "https://f000.backblazeb2.com/file/tdarrs/versions.json" "-" | grep -oP '(?<="Tdarr_Updater": ")[^"]+' | grep "linux_${ARCH_STRING}" | head -n 1)
  curl_with_retry "$RELEASE" "Tdarr_Updater.zip"
  $STD unzip Tdarr_Updater.zip
  chmod +x Tdarr_Updater
  $STD ./Tdarr_Updater
  rm -rf /opt/tdarr/Tdarr_Updater.zip
  [[ -f /opt/tdarr/Tdarr_Server/Tdarr_Server ]] || {
    msg_error "Tdarr_Updater failed — tdarr.io may be blocked by local DNS"
    exit 250
  }
  msg_ok "Installed Tdarr"

  setup_hwaccel

  msg_info "Creating Service"
  cat << EOF > /etc/systemd/system/tdarr-server.service
[Unit]
Description=Tdarr Server Daemon
After=network.target
# Enable if using ZFS, edit and enable if other FS mounting is required to access directory
#Requires=zfs-mount.service

[Service]
User=root
Group=root
Type=simple
WorkingDirectory=/opt/tdarr/Tdarr_Server
ExecStartPre=/opt/tdarr/Tdarr_Updater
ExecStart=/opt/tdarr/Tdarr_Server/Tdarr_Server
TimeoutStopSec=20
KillMode=process
Restart=on-failure

[Install]
WantedBy=multi-user.target
EOF

  cat << EOF > /etc/systemd/system/tdarr-node.service
[Unit]
Description=Tdarr Node Daemon
After=network.target
Requires=tdarr-server.service

[Service]
User=root
Group=root
Type=simple
WorkingDirectory=/opt/tdarr/Tdarr_Node
ExecStart=/opt/tdarr/Tdarr_Node/Tdarr_Node
TimeoutStopSec=20
KillMode=process
Restart=on-failure

[Install]
WantedBy=multi-user.target
EOF
  systemctl enable -q --now tdarr-server tdarr-node
  msg_ok "Created Service"
}

function post_install_script() {
  msg_ok "Completed Successfully!\n"
  echo -e "${CREATING}${GN}${APP} setup has been successfully initialized!${CL}"
  echo -e "${INFO}${YW}Access it using the following URL:${CL}"
  echo -e "${GATEWAY}${BGN}http://${IP}:8265${CL}"
}

function update_script() {
  header_info
  check_container_storage
  check_container_resources
  if [[ ! -d /opt/tdarr ]]; then
    msg_error "No ${APP} Installation Found!"
    exit
  fi
  msg_info "Updating Tdarr"
  $STD apt update
  $STD apt upgrade -y
  rm -rf /opt/tdarr/Tdarr_Updater
  cd /opt/tdarr || exit
  ARCH_STRING=$(uname -m)
  [[ "$ARCH_STRING" == "x86_64" ]] && ARCH_STRING="x64"
  [[ "$ARCH_STRING" == "aarch64" ]] && ARCH_STRING="arm64"
  RELEASE=$(curl_with_retry "https://f000.backblazeb2.com/file/tdarrs/versions.json" "-" | grep -oP '(?<="Tdarr_Updater": ")[^"]+' | grep "linux_${ARCH_STRING}" | head -n 1)
  curl_with_retry "$RELEASE" "Tdarr_Updater.zip"
  $STD unzip Tdarr_Updater.zip
  chmod +x Tdarr_Updater
  $STD ./Tdarr_Updater
  rm -rf /opt/tdarr/Tdarr_Updater.zip
  [[ -f /opt/tdarr/Tdarr_Server/Tdarr_Server ]] || {
    msg_error "Tdarr_Updater failed — tdarr.io may be blocked by local DNS"
    exit 250
  }
  msg_ok "Updated Tdarr"
  msg_ok "Updated successfully!"
  exit
}

# shellcheck disable=SC1090
# Dynamic URL resolved at runtime - shellcheck cannot follow
source <(curl -fsSL "$REPO_BASE/misc/bootstrap/lxc")
