#!/usr/bin/env bash
REPO_BASE="${REPO_BASE:-https://raw.githubusercontent.com/scripts-underground/proxmox/main}"

# Sourced by lxc.bootstrap — never executed directly
# Copyright (c) 2021-2026 community-scripts ORG
# Author: Slaviša Arežina (tremor021)
# License: MIT | https://raw.githubusercontent.com/scripts-underground/proxmox/main/LICENSE
# Source: https://github.com/rustmailer/bichon

# shellcheck disable=SC2034
APP="Bichon"
var_tags="${var_tags:-email;archive}"
var_cpu="${var_cpu:-1}"
var_ram="${var_ram:-512}"
var_disk="${var_disk:-4}"
var_os="${var_os:-debian}"
var_version="${var_version:-13}"
var_arm64="${var_arm64:-yes}"
var_unprivileged="${var_unprivileged:-1}"

function install_script() {
  ARCH=$(uname -m)
  fetch_and_deploy_gh_release "bichon" "rustmailer/bichon" "prebuild" "latest" "/opt/bichon" "bichon-*-${ARCH}-unknown-linux-gnu.tar.gz"

  read -r -p "${TAB3}Enter the public URL for Bichon (e.g., https://bichon.yourdomain.com) or leave empty to use container IP: " bichon_url
  if [[ -z "$bichon_url" ]]; then
    BICHON_PUBLIC_URL="http://$LOCAL_IP:15630"
  else
    BICHON_PUBLIC_URL="$bichon_url"
  fi

  msg_info "Setting up Bichon"
  mkdir -p /opt/bichon-data
  BICHON_ENC_PASSWORD=$(openssl rand -base64 32 | tr -d "=+/" | cut -c1-32)
  cat << EOF > /opt/bichon/bichon.env
BICHON_ROOT_DIR=/opt/bichon-data
BICHON_LOG_LEVEL=info
BICHON_ENCRYPT_PASSWORD=$BICHON_ENC_PASSWORD
BICHON_PUBLIC_URL=$BICHON_PUBLIC_URL
BICHON_CORS_ORIGINS=$BICHON_PUBLIC_URL
EOF
  msg_ok "Setup Bichon"

  msg_info "Creating Service"
  cat << EOF > /etc/systemd/system/bichon.service
[Unit]
Description=Bichon service
After=network.target

[Service]
Type=simple
User=root
EnvironmentFile=/opt/bichon/bichon.env
WorkingDirectory=/opt/bichon
ExecStart=/opt/bichon/bichon-server
Restart=on-failure
RestartSec=5
LimitNOFILE=65536

[Install]
WantedBy=multi-user.target
EOF
  systemctl enable -q --now bichon
  msg_ok "Created Service"
}

function post_install_script() {
  msg_ok "Completed Successfully!\n"
  echo -e "${CREATING}${GN}${APP} setup has been successfully initialized!${CL}"
  echo -e "${INFO}${YW} Access it using the following URL:${CL}"
  echo -e "${TAB}${GATEWAY}${BGN}http://${IP}:15630${CL}"
}

function update_script() {
  header_info
  check_container_storage
  check_container_resources
  if [[ ! -d /opt/bichon ]]; then
    msg_error "No ${APP} Installation Found!"
    exit
  fi
  if check_for_gh_release "bichon" "rustmailer/bichon"; then
    msg_info "Stopping Service"
    systemctl stop bichon
    msg_ok "Stopped Service"
    ARCH=$(uname -m)
    fetch_and_deploy_gh_release "bichon" "rustmailer/bichon" "prebuild" "latest" "/opt/bichon" "bichon-*-${ARCH}-unknown-linux-gnu.tar.gz"
    msg_info "Starting Service"
    systemctl start bichon
    msg_ok "Started Service"
    msg_ok "Updated successfully!"
  fi
  exit
}

# shellcheck disable=SC1090
source <(curl -fsSL "$REPO_BASE/misc/bootstrap/lxc")
