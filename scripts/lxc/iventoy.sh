#!/usr/bin/env bash
REPO_BASE="${REPO_BASE:-https://raw.githubusercontent.com/scripts-underground/proxmox/main}"

# Copyright (c) 2021-2026 community-scripts ORG
# Author: tteck (tteckster) | MickLesk (CanbiZ)
# License: MIT | https://raw.githubusercontent.com/scripts-underground/proxmox/main/LICENSE
# Source: https://www.iventoy.com/en/index.html

APP="iVentoy"
var_tags="${var_tags:-pxe-tool}"
var_disk="${var_disk:-2}"
var_cpu="${var_cpu:-1}"
var_ram="${var_ram:-512}"
var_os="${var_os:-debian}"
var_version="${var_version:-13}"
var_arm64="${var_arm64:-yes}"
var_unprivileged="${var_unprivileged:-0}"

function install_script() {
  local IVENTOY_ARCH
  if [[ "$(get_system_arch)" == "arm64" ]]; then
    IVENTOY_ARCH="arm64-trial"
  else
    IVENTOY_ARCH="x86_64-free"
  fi

  msg_info "Installing Dependencies"
  $STD apt install -y curl sudo
  msg_ok "Installed Dependencies"

  fetch_and_deploy_gh_release "iventoy" "ventoy/PXE" "prebuild" "latest" "/opt/iventoy" "iventoy-*-linux-${IVENTOY_ARCH}.tar.gz"
  mkdir -p /opt/iventoy/{data,iso}

  msg_info "Creating Service"
  cat << EOF > /etc/systemd/system/iventoy.service
[Unit]
Description=iVentoy PXE Booter
Documentation=https://www.iventoy.com
Wants=network-online.target
After=network-online.target

[Service]
Type=forking
WorkingDirectory=/opt/iventoy
Environment=IVENTOY_API_ALL=1
Environment=IVENTOY_AUTO_RUN=1
Environment=LIBRARY_PATH=/opt/iventoy/lib/lin64
Environment=LD_LIBRARY_PATH=/opt/iventoy/lib/lin64
ExecStart=/bin/sh /opt/iventoy/iventoy.sh -R start
ExecStop=/bin/sh /opt/iventoy/iventoy.sh stop
Restart=on-failure
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF
  systemctl enable -q --now iventoy
  msg_ok "Created Service"
}

function post_install_script() {
  msg_ok "Completed successfully!\n"
  echo -e "${CREATING}${GN}${APP} setup has been successfully initialized!${CL}"
  echo -e "${INFO}${YW}Access it using the following URL:${CL}"
  echo -e "${GATEWAY}${BGN}http://${IP}:26000${CL}"
}

function update_script() {
  header_info
  check_container_storage
  check_container_resources
  if [[ ! -d /opt/iventoy ]]; then
    msg_error "No ${APP} Installation Found!"
    exit
  fi

  local IVENTOY_ARCH
  if [[ "$(get_system_arch)" == "arm64" ]]; then
    IVENTOY_ARCH="arm64-trial"
  else
    IVENTOY_ARCH="x86_64-free"
  fi

  if check_for_gh_release "iventoy" "ventoy/PXE"; then
    msg_info "Stopping iVentoy"
    $STD /opt/iventoy/iventoy.sh stop
    msg_ok "Stopped iVentoy"

    create_backup /opt/iventoy/data /opt/iventoy/iso
    CLEAN_INSTALL=1 fetch_and_deploy_gh_release "iventoy" "ventoy/PXE" "prebuild" "latest" "/opt/iventoy" "iventoy-*-linux-${IVENTOY_ARCH}.tar.gz"
    restore_backup

    msg_info "Starting iVentoy"
    $STD /opt/iventoy/iventoy.sh -R start
    msg_ok "Started iVentoy"
    msg_ok "Updated Successfully"
  fi
  exit
}

# shellcheck disable=SC1090
source <(curl -fsSL "$REPO_BASE/misc/bootstrap/lxc")
