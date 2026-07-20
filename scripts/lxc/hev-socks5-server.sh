#!/usr/bin/env bash
REPO_BASE="${REPO_BASE:-https://raw.githubusercontent.com/scripts-underground/proxmox/main}"

# Sourced by lxc.bootstrap — never executed directly
# Copyright (c) 2021-2026 community-scripts ORG
# Author: miviro
# License: MIT | https://raw.githubusercontent.com/scripts-underground/proxmox/main/LICENSE
# Source: https://github.com/heiher/hev-socks5-server

# shellcheck disable=SC2034
APP="hev-socks5-server"
var_tags="${var_tags:-proxy;socks5}"
var_cpu="${var_cpu:-1}"
var_ram="${var_ram:-512}"
var_disk="${var_disk:-2}"
var_os="${var_os:-debian}"
var_version="${var_version:-13}"
var_arm64="${var_arm64:-yes}"
var_unprivileged="${var_unprivileged:-1}"

function install_script() {
  ARCH=$(uname -m)
  [[ "$ARCH" == "aarch64" ]] && ARCH="arm64"

  msg_info "Installing Dependencies"
  $STD apt install -y openssl
  msg_ok "Installed Dependencies"

  fetch_and_deploy_gh_release "hev-socks5-server" "heiher/hev-socks5-server" "singlefile" "latest" "/opt" "hev-socks5-server-linux-${ARCH}"

  msg_info "Setting up hev-socks5-server"
  mkdir -p /etc/hev-socks5-server
  download_file "https://raw.githubusercontent.com/heiher/hev-socks5-server/refs/heads/main/conf/main.yml" "/etc/hev-socks5-server/main.yml"
  sed -i 's/^#auth:/auth:/; s/^# file: conf\/auth.txt/  file: \/root\/hev.creds/' /etc/hev-socks5-server/main.yml
  PASSWORD=$(openssl rand -base64 16)
  echo "admin $PASSWORD 0" > /root/hev.creds
  msg_ok "Set up hev-socks5-server"

  msg_info "Creating Service"
  cat << EOF > /etc/systemd/system/hev-socks5-server.service
[Unit]
Description=hev-socks5-server Service
After=network.target

[Service]
ExecStart=/opt/hev-socks5-server /etc/hev-socks5-server/main.yml
Restart=always

[Install]
WantedBy=multi-user.target
EOF
  systemctl enable -q --now hev-socks5-server
  msg_ok "Created Service"
}

function post_install_script() {
  msg_ok "Completed successfully!\n"
  echo -e "${CREATING}${GN}${APP} setup has been successfully initialized!${CL}"
  echo -e "${INFO}${YW} Access it with a SOCKS5 client using the following URL:${CL}"
  echo -e "${TAB}${GATEWAY}${BGN}${IP}:1080${CL}"
  echo -e "${INFO}${YW} and the credentials stored at /root/hev.creds${CL}"
}

function update_script() {
  header_info
  check_container_storage
  check_container_resources

  if [[ ! -f /opt/${APP} ]]; then
    msg_error "No ${APP} Installation Found!"
    exit
  fi

  if check_for_gh_release "hev-socks5-server" "heiher/hev-socks5-server"; then
    msg_info "Stopping Service"
    systemctl stop hev-socks5-server
    msg_ok "Stopped Service"

    ARCH=$(uname -m)
    [[ "$ARCH" == "aarch64" ]] && ARCH="arm64"
    fetch_and_deploy_gh_release "hev-socks5-server" "heiher/hev-socks5-server" "singlefile" "latest" "/opt" "hev-socks5-server-linux-${ARCH}"

    msg_info "Starting Service"
    systemctl start hev-socks5-server
    msg_ok "Started Service"
    msg_ok "Updated successfully!"
  fi
  exit
}

# shellcheck disable=SC1090
source <(curl -fsSL "$REPO_BASE/misc/bootstrap/lxc")
