#!/usr/bin/env bash
REPO_BASE="${REPO_BASE:-https://raw.githubusercontent.com/scripts-underground/proxmox/main}"

# Copyright (c) 2021-2026 community-scripts ORG
# Author: Slaviša Arežina (tremor021)
# License: MIT | https://raw.githubusercontent.com/scripts-underground/proxmox/main/LICENSE
# Source: https://joplinapp.org/

# shellcheck disable=SC2034
APP="Joplin-Server"
var_tags="${var_tags:-notes}"
var_cpu="${var_cpu:-2}"
var_ram="${var_ram:-6144}"
var_disk="${var_disk:-20}"
var_os="${var_os:-debian}"
var_version="${var_version:-13}"
var_arm64="${var_arm64:-yes}"
var_unprivileged="${var_unprivileged:-1}"

function install_script() {
  msg_info "Installing Dependencies"
  $STD apt install -y \
    git \
    rsync
  msg_ok "Installed Dependencies"

  PG_VERSION="17" setup_postgresql
  PG_DB_NAME="joplin" PG_DB_USER="joplin" setup_postgresql_db
  NODE_VERSION="24" NODE_MODULE="yarn,npm,pm2" setup_nodejs

  mkdir -p /opt/pm2
  export PM2_HOME=/opt/pm2
  $STD pm2 install pm2-logrotate
  $STD pm2 set pm2-logrotate:max_size 100MB
  $STD pm2 set pm2-logrotate:retain 5
  $STD pm2 set pm2-logrotate:compress true

  fetch_and_deploy_gh_release "joplin-server" "laurent22/joplin" "tarball"

  msg_info "Setting up Joplin Server (Patience)"
  cd /opt/joplin-server || exit
  sed -i "/onenote-converter/d" packages/lib/package.json
  $STD yarn config set --home enableTelemetry 0
  export BUILD_SEQUENCIAL=1
  $STD yarn workspaces focus @joplin/server
  $STD yarn workspaces foreach -R --topological-dev --from @joplin/server run build
  $STD yarn workspaces foreach -R --topological-dev --from @joplin/server run tsc
  cat << EOF > /opt/joplin-server/.env
PM2_HOME=/opt/pm2
NODE_ENV=production
APP_BASE_URL=http://$LOCAL_IP:22300
APP_PORT=22300
DB_CLIENT=pg
POSTGRES_PASSWORD=$PG_DB_PASS
POSTGRES_DATABASE=$PG_DB_NAME
POSTGRES_USER=$PG_DB_USER
POSTGRES_PORT=5432
POSTGRES_HOST=localhost
EOF
  msg_ok "Setup Joplin Server"

  msg_info "Creating Service"
  cat << EOF > /etc/systemd/system/joplin-server.service
[Unit]
Description=Joplin Server Service
After=network.target

[Service]
Type=simple
WorkingDirectory=/opt/joplin-server/packages/server
EnvironmentFile=/opt/joplin-server/.env
ExecStart=/usr/bin/yarn start-prod
Restart=on-failure
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF
  systemctl enable -q --now joplin-server
  msg_ok "Created Service"
}

function post_install_script() {
  msg_ok "Completed Successfully!\n"
  echo -e "${CREATING}${GN}${APP} setup has been successfully initialized!${CL}"
  echo -e "${INFO}${YW}Access it using the following URL:${CL}"
  echo -e "${GATEWAY}${BGN}http://${IP}:22300${CL}"
}

function update_script() {
  header_info
  check_container_storage
  check_container_resources
  if [[ ! -d /opt/joplin-server ]]; then
    msg_error "No ${APP} Installation Found!"
    exit
  fi

  NODE_VERSION="24" NODE_MODULE="yarn,npm,pm2" setup_nodejs

  if check_for_gh_release "joplin-server" "laurent22/joplin"; then
    msg_info "Stopping Services"
    systemctl stop joplin-server
    msg_ok "Stopped Services"

    cp /opt/joplin-server/.env /opt
    CLEAN_INSTALL=1 fetch_and_deploy_gh_release "joplin-server" "laurent22/joplin" "tarball"
    mv /opt/.env /opt/joplin-server

    msg_info "Updating Joplin-Server"
    cd /opt/joplin-server || exit
    sed -i "/onenote-converter/d" packages/lib/package.json
    $STD yarn config set --home enableTelemetry 0
    export BUILD_SEQUENCIAL=1
    $STD yarn workspaces focus @joplin/server
    $STD yarn workspaces foreach -R --topological-dev --from @joplin/server run build
    $STD yarn workspaces foreach -R --topological-dev --from @joplin/server run tsc
    msg_ok "Updated Joplin-Server"

    msg_info "Starting Services"
    systemctl start joplin-server
    msg_ok "Started Services"
    msg_ok "Updated successfully!"
  fi
  exit
}

# framework bootstrap
# shellcheck disable=SC1090
source <(curl -fsSL "$REPO_BASE/misc/bootstrap/lxc")
