#!/usr/bin/env bash
REPO_BASE="${REPO_BASE:-https://raw.githubusercontent.com/scripts-underground/proxmox/main}"

# Sourced by lxc.bootstrap — never executed directly
# Copyright (c) 2021-2026 community-scripts ORG
# Author: tteck (tteckster)
# License: MIT | https://raw.githubusercontent.com/scripts-underground/proxmox/main/LICENSE
# Source: https://github.com/TriliumNext/Trilium

# shellcheck disable=SC2034
# Read by the framework - shellcheck cannot see the caller
APP="Trilium"
var_tags="${var_tags:-notes}"
var_cpu="${var_cpu:-1}"
var_ram="${var_ram:-512}"
var_disk="${var_disk:-2}"
var_os="${var_os:-debian}"
var_version="${var_version:-13}"
var_arm64="${var_arm64:-yes}"
var_unprivileged="${var_unprivileged:-1}"

function install_script() {
  RELEASE_ARCH=$(uname -m)
  [[ "$RELEASE_ARCH" == "x86_64" ]] && RELEASE_ARCH="x64"
  [[ "$RELEASE_ARCH" == "aarch64" ]] && RELEASE_ARCH="arm64"

  fetch_and_deploy_gh_release "Trilium" "TriliumNext/Trilium" "prebuild" "latest" "/opt/trilium" "TriliumNotes-Server-*linux-${RELEASE_ARCH}.tar.xz"

  msg_info "Creating Service"
  cat << EOF > /etc/systemd/system/trilium.service
[Unit]
Description=Trilium Daemon
After=syslog.target network.target

[Service]
User=root
Type=simple
ExecStart=/opt/trilium/trilium.sh
WorkingDirectory=/opt/trilium/
TimeoutStopSec=20
Restart=always

[Install]
WantedBy=multi-user.target
EOF
  systemctl enable -q --now trilium
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
  if [[ ! -d /opt/trilium ]]; then
    msg_error "No ${APP} Installation Found!"
    exit
  fi
  if check_for_gh_release "Trilium" "TriliumNext/Trilium"; then
    if [[ -d /opt/trilium/db ]]; then
      DB_PATH="/opt/trilium/db"
      DB_RESTORE_PATH="/opt/trilium/db"
    elif [[ -d /opt/trilium/assets/db ]]; then
      DB_PATH="/opt/trilium/assets/db"
      DB_RESTORE_PATH="/opt/trilium/assets/db"
    else
      msg_error "Database not found in either /opt/trilium/db or /opt/trilium/assets/db"
      exit
    fi

    msg_info "Stopping Service"
    systemctl stop trilium
    sleep 1
    msg_ok "Stopped Service"

    msg_info "Backing up Database"
    mkdir -p /opt/trilium_backup
    cp -r "${DB_PATH}" /opt/trilium_backup/
    msg_ok "Backed up Database"

    RELEASE_ARCH=$(uname -m)
    [[ "$RELEASE_ARCH" == "x86_64" ]] && RELEASE_ARCH="x64"
    [[ "$RELEASE_ARCH" == "aarch64" ]] && RELEASE_ARCH="arm64"

    CLEAN_INSTALL=1 fetch_and_deploy_gh_release "Trilium" "TriliumNext/Trilium" "prebuild" "latest" "/opt/trilium" "TriliumNotes-Server-*linux-${RELEASE_ARCH}.tar.xz"

    msg_info "Restoring Database"
    mkdir -p "$(dirname "${DB_RESTORE_PATH}")"
    cp -r "/opt/trilium_backup/$(basename "${DB_PATH}")" "${DB_RESTORE_PATH}"
    rm -rf /opt/trilium_backup
    msg_ok "Restored Database"

    msg_info "Starting Service"
    systemctl start trilium
    sleep 1
    msg_ok "Started Service"
    msg_ok "Updated successfully!"
  fi
  exit
}

# framework bootstrap
# shellcheck disable=SC1090
# Dynamic URL resolved at runtime - shellcheck cannot follow
source <(curl -fsSL "$REPO_BASE/misc/bootstrap/lxc")
