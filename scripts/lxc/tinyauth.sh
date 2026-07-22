#!/usr/bin/env bash
REPO_BASE="${REPO_BASE:-https://raw.githubusercontent.com/scripts-underground/proxmox/main}"

# Sourced by lxc.bootstrap — never executed directly
# Copyright (c) 2021-2026 community-scripts ORG
# Author: MickLesk (CanbiZ)
# License: MIT | https://raw.githubusercontent.com/scripts-underground/proxmox/main/LICENSE
# Source: https://tinyauth.app/

# shellcheck disable=SC2034
# Read by the framework - shellcheck cannot see the caller
APP="Tinyauth"
var_tags="${var_tags:-auth}"
var_cpu="${var_cpu:-1}"
var_ram="${var_ram:-512}"
var_disk="${var_disk:-4}"
var_os="${var_os:-debian}"
var_version="${var_version:-13}"
var_arm64="${var_arm64:-yes}"
var_unprivileged="${var_unprivileged:-1}"

function install_script() {
  msg_info "Installing Dependencies"
  $STD apt install -y \
    openssl \
    apache2-utils
  msg_ok "Installed Dependencies"

  fetch_and_deploy_gh_release "tinyauth" "tinyauthapp/tinyauth" "singlefile" "latest" "/opt/tinyauth" "tinyauth-$(get_system_arch)"

  msg_info "Setting up Tinyauth"
  PASS=$(openssl rand -base64 8 | tr -dc 'a-zA-Z0-9' | head -c 8)
  USER=$(htpasswd -Bbn "tinyauth" "${PASS}")
  cat << EOF > /opt/tinyauth/credentials.txt
Tinyauth Credentials
Username: tinyauth
Password: ${PASS}
EOF
  msg_ok "Set up Tinyauth"

  read -r -p "Enter your Tinyauth subdomain (e.g. https://tinyauth.example.com): " app_url

  msg_info "Creating Service"
  cat << EOF > /opt/tinyauth/.env
TINYAUTH_DATABASE_PATH=/opt/tinyauth/database.db
TINYAUTH_AUTH_USERS='${USER}'
TINYAUTH_APPURL=${app_url}
EOF
  cat << EOF > /etc/systemd/system/tinyauth.service
[Unit]
Description=Tinyauth Service
After=network.target

[Service]
Type=simple
EnvironmentFile=/opt/tinyauth/.env
ExecStart=/opt/tinyauth/tinyauth
WorkingDirectory=/opt/tinyauth
Restart=on-failure

[Install]
WantedBy=multi-user.target
EOF
  systemctl enable -q --now tinyauth
  msg_ok "Created Service"
}

function post_install_script() {
  msg_ok "Completed Successfully!\n"
  echo -e "${CREATING}${GN}${APP} setup has been successfully initialized!${CL}"
  echo -e "${INFO}${YW}Access it using the following URL:${CL}"
  echo -e "${GATEWAY}${BGN}http://${IP}:3000${CL}"
}

function update_script() {
  header_info
  check_container_storage
  check_container_resources

  if [[ ! -d /opt/tinyauth ]]; then
    msg_error "No ${APP} Installation Found!"
    exit
  fi

  if check_for_gh_release "tinyauth" "tinyauthapp/tinyauth"; then
    msg_info "Stopping Service"
    systemctl stop tinyauth
    msg_ok "Stopped Service"

    fetch_and_deploy_gh_release "tinyauth" "tinyauthapp/tinyauth" "singlefile" "latest" "/opt/tinyauth" "tinyauth-$(get_system_arch)"

    msg_info "Starting Service"
    systemctl start tinyauth
    msg_ok "Started Service"
    msg_ok "Updated successfully!"
  fi
  exit
}

# framework bootstrap
# shellcheck disable=SC1090
# Dynamic URL resolved at runtime - shellcheck cannot follow
source <(curl -fsSL "$REPO_BASE/misc/bootstrap/lxc")
