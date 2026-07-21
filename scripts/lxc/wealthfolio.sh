#!/usr/bin/env bash
REPO_BASE="${REPO_BASE:-https://raw.githubusercontent.com/scripts-underground/proxmox/main}"

# Sourced by lxc.bootstrap — never executed directly
# Copyright (c) 2021-2026 community-scripts ORG
# Author: CrazyWolf13
# License: MIT | https://raw.githubusercontent.com/scripts-underground/proxmox/main/LICENSE
# Source: https://wealthfolio.app/

# shellcheck disable=SC2034
# Read by the framework - shellcheck cannot see the caller
APP="Wealthfolio"
var_tags="${var_tags:-finance;portfolio}"
var_cpu="${var_cpu:-1}"
var_ram="${var_ram:-512}"
var_disk="${var_disk:-4}"
var_os="${var_os:-debian}"
var_version="${var_version:-13}"
var_arm64="${var_arm64:-no}"
var_unprivileged="${var_unprivileged:-1}"

function install_script() {
  msg_info "Installing Dependencies"
  $STD apt install -y argon2
  msg_ok "Installed Dependencies"

  fetch_and_deploy_gh_release "wealthfolio" "wealthfolio/wealthfolio" "prebuild" "latest" "/opt/wealthfolio" "wealthfolio-server-*-linux-amd64.tar.gz"

  msg_info "Installing Wealthfolio"
  install -m 755 /opt/wealthfolio/wealthfolio-server /usr/local/bin/wealthfolio-server
  msg_ok "Installed Wealthfolio"

  msg_info "Configuring Wealthfolio"
  mkdir -p /opt/wealthfolio_data
  SECRET_KEY=$(openssl rand -base64 32)
  WF_PASSWORD=$(openssl rand -base64 18 | tr -dc 'a-zA-Z0-9' | cut -c1-16)
  WF_PASSWORD_HASH=$(echo -n "$WF_PASSWORD" | argon2 "$(openssl rand -base64 16)" -id -e)
  cat << EOF > /opt/wealthfolio/.env
WF_LISTEN_ADDR=0.0.0.0:8080
WF_DB_PATH=/opt/wealthfolio_data/wealthfolio.db
WF_SECRET_KEY=${SECRET_KEY}
WF_AUTH_PASSWORD_HASH=${WF_PASSWORD_HASH}
WF_STATIC_DIR=/opt/wealthfolio/dist
WF_REQUEST_TIMEOUT_MS=30000
WF_CORS_ALLOW_ORIGINS=http://${LOCAL_IP}:8080
EOF
  echo "WF_PASSWORD=${WF_PASSWORD}" > ~/wealthfolio.creds
  msg_ok "Configured Wealthfolio"

  msg_info "Creating Service"
  cat << EOF > /etc/systemd/system/wealthfolio.service
[Unit]
Description=Wealthfolio Investment Tracker
After=network.target

[Service]
Type=simple
User=root
WorkingDirectory=/opt/wealthfolio
EnvironmentFile=/opt/wealthfolio/.env
ExecStart=/usr/local/bin/wealthfolio-server
Restart=on-failure
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF
  systemctl enable -q --now wealthfolio
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

  if [[ ! -d /opt/wealthfolio ]]; then
    msg_error "No ${APP} Installation Found!"
    exit
  fi

  if grep -q '^WF_CORS_ALLOW_ORIGINS=\*' /opt/wealthfolio/.env 2> /dev/null; then
    sed -i "s|^WF_CORS_ALLOW_ORIGINS=\*$|WF_CORS_ALLOW_ORIGINS=http://${LOCAL_IP}:8080|" /opt/wealthfolio/.env
  fi

  if check_for_gh_release "wealthfolio" "wealthfolio/wealthfolio"; then
    msg_info "Stopping Service"
    systemctl stop wealthfolio
    msg_ok "Stopped Service"

    msg_info "Backing up Data"
    cp -r /opt/wealthfolio_data /opt/wealthfolio_data_backup
    cp /opt/wealthfolio/.env /opt/wealthfolio_env_backup
    msg_ok "Backed up Data"

    CLEAN_INSTALL=1 fetch_and_deploy_gh_release "wealthfolio" "wealthfolio/wealthfolio" "prebuild" "latest" "/opt/wealthfolio" "wealthfolio-server-*-linux-amd64.tar.gz"
    install -m 755 /opt/wealthfolio/wealthfolio-server /usr/local/bin/wealthfolio-server

    msg_info "Restoring Data"
    cp -r /opt/wealthfolio_data_backup/. /opt/wealthfolio_data
    cp /opt/wealthfolio_env_backup /opt/wealthfolio/.env
    rm -rf /opt/wealthfolio_data_backup /opt/wealthfolio_env_backup
    msg_ok "Restored Data"

    msg_info "Starting Service"
    systemctl start wealthfolio
    msg_ok "Started Service"
    msg_ok "Updated successfully!"
  fi
  exit
}

# framework bootstrap
# shellcheck disable=SC1090
# Dynamic URL resolved at runtime - shellcheck cannot follow
source <(curl -fsSL "$REPO_BASE/misc/bootstrap/lxc")
