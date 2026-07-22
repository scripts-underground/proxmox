#!/usr/bin/env bash
REPO_BASE="${REPO_BASE:-https://raw.githubusercontent.com/scripts-underground/proxmox/main}"

# Sourced by lxc.bootstrap — never executed directly
# Copyright (c) 2021-2026 community-scripts ORG
# Author: MickLesk (CanbiZ)
# License: MIT | https://raw.githubusercontent.com/scripts-underground/proxmox/main/LICENSE
# Source: https://github.com/Sync-in/server

# shellcheck disable=SC2034
# Read by the framework - shellcheck cannot see the caller
APP="Sync-in"
var_tags="${var_tags:-files;sync;collaboration}"
var_cpu="${var_cpu:-2}"
var_ram="${var_ram:-2048}"
var_disk="${var_disk:-20}"
var_os="${var_os:-debian}"
var_version="${var_version:-13}"
var_arm64="${var_arm64:-yes}"
var_unprivileged="${var_unprivileged:-1}"

function install_script() {
  NODE_VERSION="22" setup_nodejs
  setup_mariadb
  MARIADB_DB_NAME="sync_in" MARIADB_DB_USER="sync_in" setup_mariadb_db

  msg_info "Installing Sync-in"
  mkdir -p /opt/sync-in/data
  $STD npm install --prefix /opt/sync-in @sync-in/server
  msg_ok "Installed Sync-in"

  msg_info "Configuring Sync-in"
  ENCRYPT_KEY=$(openssl rand -hex 32)
  ACCESS_SECRET=$(openssl rand -hex 32)
  REFRESH_SECRET=$(openssl rand -hex 32)
  cat << EOF > /opt/sync-in/environment.yaml
server:
  port: 8080
mysql:
  url: 'mysql://${MARIADB_DB_USER}:${MARIADB_DB_PASS}@localhost:3306/${MARIADB_DB_NAME}'
auth:
  encryptionKey: '${ENCRYPT_KEY}'
  token:
    access:
      secret: '${ACCESS_SECRET}'
    refresh:
      secret: '${REFRESH_SECRET}'
applications:
  files:
    dataPath: '/opt/sync-in/data'
EOF
  msg_ok "Configured Sync-in"

  msg_info "Running Database Migrations"
  cd /opt/sync-in || exit
  $STD npx sync-in-server migrate-db
  msg_ok "Ran Database Migrations"

  msg_info "Creating Admin User"
  cd /opt/sync-in || exit
  $STD npx sync-in-server create-user
  msg_ok "Created Admin User"

  VERSION=$(node -pe "require('/opt/sync-in/node_modules/@sync-in/server/package.json').version" 2> /dev/null || echo "")
  [[ -n "$VERSION" ]] && echo "$VERSION" > ~/.sync-in

  msg_info "Creating Service"
  cat << EOF > /etc/systemd/system/sync-in.service
[Unit]
Description=Sync-in Server
After=network.target mariadb.service

[Service]
Type=simple
User=root
WorkingDirectory=/opt/sync-in
ExecStart=/opt/sync-in/node_modules/.bin/sync-in-server start
Restart=on-failure
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF
  systemctl enable -q --now sync-in
  msg_ok "Created Service"
}

function post_install_script() {
  msg_ok "Completed Successfully!\n"
  echo -e "${CREATING}${GN}${APP} setup has been successfully initialized!${CL}"
  echo -e "${INFO}${YW}Access it using the following URL:${CL}"
  echo -e "${GATEWAY}${BGN}http://${IP}:8080${CL}"
}

function update_script() {
  header_info
  check_container_storage
  check_container_resources

  if [[ ! -d /opt/sync-in/node_modules/@sync-in ]]; then
    msg_error "No ${APP} Installation Found!"
    exit
  fi

  if check_for_gh_release "sync-in" "Sync-in/server"; then
    msg_info "Stopping Service"
    systemctl stop sync-in
    msg_ok "Stopped Service"

    msg_info "Updating Sync-in"
    $STD npm install --prefix /opt/sync-in "@sync-in/server@${CHECK_UPDATE_RELEASE#v}"
    msg_ok "Updated Sync-in"

    msg_info "Running Database Migrations"
    cd /opt/sync-in || exit
    $STD npx sync-in-server migrate-db
    msg_ok "Ran Database Migrations"

    VERSION=$(node -pe "require('/opt/sync-in/node_modules/@sync-in/server/package.json').version" 2> /dev/null || echo "")
    [[ -n "$VERSION" ]] && echo "$VERSION" > ~/.sync-in

    msg_info "Starting Service"
    systemctl start sync-in
    msg_ok "Started Service"
    msg_ok "Updated successfully!"
  fi
  exit
}

# framework bootstrap
# shellcheck disable=SC1090
# Dynamic URL resolved at runtime - shellcheck cannot follow
source <(curl -fsSL "$REPO_BASE/misc/bootstrap/lxc")
