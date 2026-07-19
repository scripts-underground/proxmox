#!/usr/bin/env bash
REPO_BASE="${REPO_BASE:-https://raw.githubusercontent.com/scripts-underground/proxmox/main}"

# Sourced by lxc.bootstrap — never executed directly
# Copyright (c) 2021-2026 community-scripts ORG
# Author: Slaviša Arežina (tremor021)
# License: MIT | https://raw.githubusercontent.com/scripts-underground/proxmox/main/LICENSE
# Source: https://github.com/tinyauthapp/tinyauth

# shellcheck disable=SC2034
# Read by the framework - shellcheck cannot see the caller
APP="Alpine-Tinyauth"
var_tags="${var_tags:-alpine;auth}"
var_cpu="${var_cpu:-1}"
var_ram="${var_ram:-256}"
var_disk="${var_disk:-2}"
var_os="${var_os:-alpine}"
var_version="${var_version:-3.23}"
var_arm64="${var_arm64:-yes}"
var_unprivileged="${var_unprivileged:-1}"

function install_script() {
  msg_info "Installing Dependencies"
  $STD apk add --no-cache openssl apache2-utils
  msg_ok "Installed Dependencies"

  msg_info "Installing Tinyauth"
  mkdir -p /opt/tinyauth
  RELEASE=$(curl -s https://api.github.com/repos/tinyauthapp/tinyauth/releases/latest | grep "tag_name" | awk '{print substr($2, 3, length($2)-4) }')
  curl -fsSL "https://github.com/tinyauthapp/tinyauth/releases/download/v${RELEASE}/tinyauth-$(get_system_arch)" -o /opt/tinyauth/tinyauth
  chmod +x /opt/tinyauth/tinyauth
  PASS=$(openssl rand -base64 8 | tr -dc 'a-zA-Z0-9' | head -c 8)
  USER=$(htpasswd -Bbn "tinyauth" "${PASS}")
  cat << EOF > /opt/tinyauth/credentials.txt
Tinyauth Credentials
Username: tinyauth
Password: ${PASS}
EOF
  echo "${RELEASE}" > ~/.tinyauth
  msg_ok "Installed Tinyauth"

  read -r -p "${TAB3}Enter your Tinyauth subdomain (e.g. https://tinyauth.example.com): " app_url
  cat << EOF > /opt/tinyauth/.env
TINYAUTH_DATABASE_PATH=/opt/tinyauth/database.db
TINYAUTH_AUTH_USERS='${USER}'
TINYAUTH_APPURL=${app_url}
EOF

  msg_info "Creating Service"
  cat << 'EOF' > /etc/init.d/tinyauth
#!/sbin/openrc-run
description="Tinyauth Service"
set -a
ENV_FILE="/opt/tinyauth/.env"
[ -f "$ENV_FILE" ] && . "$ENV_FILE"
set +a
command="/opt/tinyauth/tinyauth"
directory="/opt/tinyauth"
command_user="root"
command_background="true"
pidfile="/var/run/tinyauth.pid"
depend() {
    use net
}
EOF
  chmod +x /etc/init.d/tinyauth
  $STD rc-update add tinyauth default
  msg_ok "Enabled Tinyauth Service"
  msg_info "Starting Tinyauth"
  $STD service tinyauth start
  msg_ok "Started Tinyauth"
}

function post_install_script() {
  msg_ok "Completed Successfully!\n"
  echo -e "${CREATING}${GN}${APP} setup has been successfully initialized!${CL}"
  echo -e "${INFO}${YW} Access it using the following URL:${CL}"
  echo -e "${TAB}${GATEWAY}${BGN}http://${IP}:3000${CL}"
}

function update_script() {
  header_info
  if [[ ! -d /opt/tinyauth ]]; then
    msg_error "No ${APP} Installation Found!"
    exit
  fi
  msg_info "Updating Tinyauth"
  RELEASE=$(curl -s https://api.github.com/repos/tinyauthapp/tinyauth/releases/latest | grep "tag_name" | awk '{print substr($2, 3, length($2)-4) }')
  curl -fsSL "https://github.com/tinyauthapp/tinyauth/releases/download/v${RELEASE}/tinyauth-$(get_system_arch)" -o /opt/tinyauth/tinyauth
  chmod +x /opt/tinyauth/tinyauth
  echo "${RELEASE}" > ~/.tinyauth
  msg_ok "Updated Tinyauth"
  msg_ok "Updated successfully!"
  exit 0
}

# framework bootstrap
# shellcheck disable=SC1090
# Dynamic URL resolved at runtime - shellcheck cannot follow
source <(curl -fsSL "$REPO_BASE/misc/bootstrap/lxc")
