#!/usr/bin/env bash
REPO_BASE="${REPO_BASE:-https://raw.githubusercontent.com/scripts-underground/proxmox/main}"

# Sourced by lxc.bootstrap — never executed directly
# Copyright (c) 2021-2026 community-scripts ORG
# Author: pespinel
# License: MIT | https://raw.githubusercontent.com/scripts-underground/proxmox/main/LICENSE
# Source: https://strapi.io/

# shellcheck disable=SC2034
# Read by the framework - shellcheck cannot see the caller
APP="Strapi"
var_tags="${var_tags:-cms}"
var_cpu="${var_cpu:-2}"
var_ram="${var_ram:-4096}"
var_disk="${var_disk:-8}"
var_os="${var_os:-debian}"
var_version="${var_version:-13}"
var_arm64="${var_arm64:-yes}"
var_unprivileged="${var_unprivileged:-1}"

function install_script() {
  msg_info "Installing Dependencies"
  $STD apt install -y \
    build-essential \
    python3 \
    python3-setuptools \
    libvips42
  msg_ok "Installed Dependencies"

  NODE_VERSION="24" setup_nodejs

  msg_info "Installing Strapi (Patience)"
  mkdir -p /opt/strapi
  cd /opt/strapi || exit
  $STD npx --yes create-strapi-app@latest . --quickstart --no-run --skip-cloud
  msg_ok "Installed Strapi"

  msg_info "Building Strapi"
  cd /opt/strapi || exit
  export NODE_OPTIONS="--max-old-space-size=3072"
  $STD npm run build
  msg_ok "Built Strapi"

  msg_info "Creating Service"
  cat << EOF > /opt/strapi/.env
HOST=0.0.0.0
PORT=1337
APP_KEYS=$(openssl rand -base64 32)
API_TOKEN_SALT=$(openssl rand -base64 32)
ADMIN_JWT_SECRET=$(openssl rand -base64 32)
TRANSFER_TOKEN_SALT=$(openssl rand -base64 32)
JWT_SECRET=$(openssl rand -base64 32)
EOF
  cat << EOF > /etc/systemd/system/strapi.service
[Unit]
Description=Strapi CMS
After=network.target

[Service]
Type=simple
WorkingDirectory=/opt/strapi
EnvironmentFile=/opt/strapi/.env
ExecStart=/usr/bin/npm run start
Restart=on-failure
Environment=NODE_ENV=production

[Install]
WantedBy=multi-user.target
EOF
  systemctl enable -q --now strapi
  msg_ok "Created Service"
}

function post_install_script() {
  msg_ok "Completed Successfully!\n"
  echo -e "${CREATING}${GN}${APP} setup has been successfully initialized!${CL}"
  echo -e "${INFO}${YW} Access it using the following URL:${CL}"
  echo -e "${TAB}${GATEWAY}${BGN}http://${IP}:1337${CL}"
}

function update_script() {
  header_info
  check_container_storage
  check_container_resources
  if [[ ! -f /etc/systemd/system/strapi.service ]]; then
    msg_error "No ${APP} Installation Found!"
    exit
  fi

  NODE_VERSION="24" setup_nodejs

  msg_info "Stopping Strapi"
  systemctl stop strapi
  msg_ok "Stopped Strapi"

  msg_info "Updating Strapi"
  cd /opt/strapi || exit
  $STD npx @strapi/upgrade minor --yes
  msg_ok "Updated Strapi"

  msg_info "Building Strapi"
  cd /opt/strapi || exit
  export NODE_OPTIONS="--max-old-space-size=3072"
  $STD npm run build
  msg_ok "Built Strapi"

  msg_info "Starting Strapi"
  systemctl start strapi
  msg_ok "Started Strapi"
  msg_ok "Updated successfully!"
  exit
}

# framework bootstrap
# shellcheck disable=SC1090
# Dynamic URL resolved at runtime - shellcheck cannot follow
source <(curl -fsSL "$REPO_BASE/misc/bootstrap/lxc")
