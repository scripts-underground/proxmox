#!/usr/bin/env bash
REPO_BASE="${REPO_BASE:-https://raw.githubusercontent.com/scripts-underground/proxmox/main}"

# Sourced by lxc.bootstrap — never executed directly
# Copyright (c) 2021-2026 community-scripts ORG
# Author: MickLesk (CanbiZ)
# License: MIT | https://raw.githubusercontent.com/scripts-underground/proxmox/main/LICENSE
# Source: https://github.com/diced/zipline

# shellcheck disable=SC2034
# Read by the framework - shellcheck cannot see the caller
APP="Zipline"
var_tags="${var_tags:-file;sharing}"
var_cpu="${var_cpu:-2}"
var_ram="${var_ram:-2048}"
var_disk="${var_disk:-5}"
var_os="${var_os:-debian}"
var_version="${var_version:-13}"
var_arm64="${var_arm64:-yes}"
var_unprivileged="${var_unprivileged:-1}"

function install_script() {
  msg_info "Installing Node.js"
  NODE_VERSION="24" NODE_MODULE="pnpm" setup_nodejs
  msg_ok "Installed Node.js"

  msg_info "Setting up PostgreSQL"
  PG_VERSION="17" setup_postgresql
  PG_DB_NAME="ziplinedb" PG_DB_USER="zipline" setup_postgresql_db
  msg_ok "Set up PostgreSQL"

  fetch_and_deploy_gh_release "zipline" "diced/zipline" "tarball"

  SECRET_KEY="$(openssl rand -base64 42 | tr -dc 'a-zA-Z0-9')"
  echo "Zipline Secret Key: ${SECRET_KEY}" >> ~/zipline.creds

  msg_info "Installing Zipline (Patience)"
  cd /opt/zipline || exit
  cat << EOF > /opt/zipline/.env
DATABASE_URL=postgres://$PG_DB_USER:$PG_DB_PASS@localhost:5432/$PG_DB_NAME
CORE_SECRET=$SECRET_KEY
CORE_HOSTNAME=0.0.0.0
CORE_PORT=3000
CORE_RETURN_HTTPS=false
DATASOURCE_TYPE=local
DATASOURCE_LOCAL_DIRECTORY=/opt/zipline-uploads
EOF
  mkdir -p /opt/zipline-uploads
  $STD pnpm install
  $STD pnpm build
  msg_ok "Installed Zipline"

  msg_info "Creating Service"
  cat << EOF > /etc/systemd/system/zipline.service
[Unit]
Description=Zipline Service
After=network.target

[Service]
WorkingDirectory=/opt/zipline
ExecStart=/usr/bin/pnpm start
Restart=on-failure

[Install]
WantedBy=multi-user.target
EOF
  systemctl enable -q --now zipline
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

  if [[ ! -d /opt/zipline ]]; then
    msg_error "No ${APP} Installation Found!"
    exit
  fi

  NODE_VERSION="24" NODE_MODULE="pnpm" setup_nodejs

  if check_for_gh_release "zipline" "diced/zipline"; then
    msg_info "Stopping Service"
    systemctl stop zipline
    msg_ok "Service Stopped"

    mkdir -p /opt/zipline-uploads
    if [ -d /opt/zipline/uploads ] && [ "$(ls -A /opt/zipline/uploads)" ]; then
      cp -R /opt/zipline/uploads/* /opt/zipline-uploads/
    fi
    cp /opt/zipline/.env /opt/
    CLEAN_INSTALL=1 fetch_and_deploy_gh_release "zipline" "diced/zipline" "tarball"

    msg_info "Updating ${APP}"
    cd /opt/zipline || exit
    mv /opt/.env /opt/zipline/.env
    $STD pnpm install
    $STD pnpm build
    msg_ok "Updated ${APP}"

    msg_info "Starting Service"
    systemctl start zipline
    msg_ok "Started Service"
    msg_ok "Updated successfully!"
  fi
  exit
}

# framework bootstrap
# shellcheck disable=SC1090
# Dynamic URL resolved at runtime - shellcheck cannot follow
source <(curl -fsSL "$REPO_BASE/misc/bootstrap/lxc")
