#!/usr/bin/env bash
REPO_BASE="${REPO_BASE:-https://raw.githubusercontent.com/scripts-underground/proxmox/main}"

# Copyright (c) 2021-2026 community-scripts ORG
# Author: Slavisa Arezina (tremor021)
# License: MIT | https://raw.githubusercontent.com/scripts-underground/proxmox/main/LICENSE
# Source: https://www.grandstream.com/products/networking-solutions/wi-fi-management/product/gwn-manager

# shellcheck disable=SC2034
APP="GWN-Manager"
var_tags="${var_tags:-network;management}"
var_cpu="${var_cpu:-2}"
var_ram="${var_ram:-6144}"
var_disk="${var_disk:-8}"
var_os="${var_os:-debian}"
var_version="${var_version:-13}"
var_arm64="${var_arm64:-no}"
var_unprivileged="${var_unprivileged:-1}"

function install_script() {
  msg_info "Installing Dependencies"
  $STD apt install -y xfonts-utils fontconfig
  msg_ok "Installed Dependencies"

  msg_info "Setting up GWN Manager (Patience)"
  RELEASE=$(curl -fsSL https://www.grandstream.com/support/tools#gwntools |
    grep -oP 'https://firmware\.grandstream\.com/GWN_Manager-[^"]+-Ubuntu\.tar\.gz')
  download_file "$RELEASE" "/tmp/gwnmanager.tar.gz"
  cd /tmp || exit
  tar -xzf gwnmanager.tar.gz --strip-components=1
  $STD ./install
  msg_ok "Setup GWN Manager"

  msg_info "Creating Service"
  cat << EOF > /etc/systemd/system/gwnmanager.service
[Unit]
Description=GWN Manager
After=network.target
Requires=network.target

[Service]
Type=simple
WorkingDirectory=/gwn
ExecStart=/gwn/gwn start
Restart=on-failure
RestartSec=10

[Install]
WantedBy=multi-user.target
EOF
  systemctl enable -q gwnmanager
  msg_ok "Created Service"
}

function update_script() {
  header_info
  check_container_storage
  check_container_resources
  if [[ ! -d /gwn ]]; then
    msg_error "No ${APP} Installation Found!"
    exit
  fi
  msg_info "The app offers a built-in updater. Please use it."
  exit
}

function post_install_script() {
  msg_ok "Completed successfully!\n"
  echo -e "${CREATING}${GN}${APP} setup has been successfully initialized!${CL}"
  echo -e "${INFO}${YW}Access it using the following URL:${CL}"
  echo -e "${GATEWAY}${BGN}https://${IP}:8443${CL}"
}

# shellcheck disable=SC1090
source <(curl -fsSL "$REPO_BASE/misc/bootstrap/lxc")
