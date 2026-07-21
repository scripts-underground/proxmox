#!/usr/bin/env bash
REPO_BASE="${REPO_BASE:-https://raw.githubusercontent.com/scripts-underground/proxmox/main}"

# Copyright (c) 2021-2026 community-scripts ORG
# Author: Slaviša Arežina (tremor021)
# License: MIT | https://raw.githubusercontent.com/scripts-underground/proxmox/main/LICENSE
# Source: https://www.getoutline.com/

# shellcheck disable=SC2034
APP="Outline"
var_tags="${var_tags:-documentation}"
var_cpu="${var_cpu:-2}"
var_ram="${var_ram:-4096}"
var_disk="${var_disk:-8}"
var_os="${var_os:-debian}"
var_version="${var_version:-13}"
var_arm64="${var_arm64:-yes}"
var_unprivileged="${var_unprivileged:-1}"

function install_script() {
  LOCAL_IP=$(hostname -I | awk '{print $1}')
  export LOCAL_IP

  msg_info "Installing Dependencies"
  $STD apt install -y mkcert git redis-server
  msg_ok "Installed Dependencies"

  NODE_VERSION="24" NODE_MODULE="corepack" setup_nodejs
  PG_VERSION="16" setup_postgresql
  PG_DB_NAME="outline" PG_DB_USER="outline" setup_postgresql_db

  fetch_and_deploy_gh_release "outline" "outline/outline" "tarball"

  msg_info "Configuring Outline (Patience)"
  SECRET_KEY="$(openssl rand -hex 32)"
  cd /opt/outline || exit
  cp .env.sample .env
  export NODE_ENV=development
  sed -i 's/NODE_ENV=production/NODE_ENV=development/g' /opt/outline/.env
  sed -i "s/generate_a_new_key/${SECRET_KEY}/g" /opt/outline/.env
  sed -i "s/user:pass@postgres/${PG_DB_USER}:${PG_DB_PASS}@localhost/g" /opt/outline/.env
  sed -i 's/redis:6379/localhost:6379/g' /opt/outline/.env
  sed -i "5s#URL=#URL=http://${LOCAL_IP}#g" /opt/outline/.env
  sed -i 's/FORCE_HTTPS=true/FORCE_HTTPS=false/g' /opt/outline/.env
  export NODE_OPTIONS="--max-old-space-size=3584"
  export COREPACK_ENABLE_DOWNLOAD_PROMPT=0

  $STD yarn install --immutable
  export NODE_ENV=production
  sed -i 's/NODE_ENV=development/NODE_ENV=production/g' /opt/outline/.env
  $STD yarn build
  msg_ok "Configured Outline"

  msg_info "Creating Service"
  cat << EOF > /etc/systemd/system/outline.service
[Unit]
Description=Outline Service
After=network.target

[Service]
Type=simple
User=root
WorkingDirectory=/opt/outline
ExecStart=/usr/bin/yarn start
Restart=always
EnvironmentFile=/opt/outline/.env

[Install]
WantedBy=multi-user.target
EOF
  systemctl enable -q --now outline
  msg_ok "Created Service"
}

function post_install_script() {
  msg_ok "Completed successfully!\n"
  echo -e "${CREATING}${GN}${APP} setup has been successfully initialized!${CL}"
  echo -e "${INFO}${YW}Access it using the following URL:${CL}"
  echo -e "${GATEWAY}${BGN}http://${IP}:3000${CL}"
}

function update_script() {
  header_info
  check_container_storage
  check_container_resources
  if [[ ! -d /opt/outline ]]; then
    msg_error "No ${APP} Installation Found!"
    exit
  fi

  NODE_VERSION="24" NODE_MODULE="corepack" setup_nodejs

  if check_for_gh_release "outline" "outline/outline"; then
    msg_info "Stopping Services"
    systemctl stop outline
    msg_ok "Services Stopped"

    msg_info "Creating backup"
    cp /opt/outline/.env /opt
    msg_ok "Backup created"

    CLEAN_INSTALL=1 fetch_and_deploy_gh_release "outline" "outline/outline" "tarball"

    msg_info "Updating Outline"
    cd /opt/outline || exit
    mv /opt/.env /opt/outline
    export NODE_ENV=development
    export NODE_OPTIONS="--max-old-space-size=3584"
    export COREPACK_ENABLE_DOWNLOAD_PROMPT=0

    $STD yarn install --immutable
    export NODE_ENV=production
    $STD yarn build
    msg_ok "Updated Outline"

    msg_info "Starting Services"
    systemctl start outline
    msg_ok "Started Services"
    msg_ok "Updated successfully!"
  fi
  exit
}

# framework bootstrap
# shellcheck disable=SC1090
source <(curl -fsSL "$REPO_BASE/misc/bootstrap/lxc")
