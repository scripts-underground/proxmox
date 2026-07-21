#!/usr/bin/env bash
REPO_BASE="${REPO_BASE:-https://raw.githubusercontent.com/scripts-underground/proxmox/main}"

# Copyright (c) 2021-2026 community-scripts ORG
# Author: Slaviša Arežina (tremor021)
# License: MIT | https://raw.githubusercontent.com/scripts-underground/proxmox/main/LICENSE
# Source: https://openarchiver.com/ | Github: https://github.com/LogicLabs-OU/OpenArchiver

# shellcheck disable=SC2034
APP="Open-Archiver"
var_tags="${var_tags:-os}"
var_cpu="${var_cpu:-2}"
var_ram="${var_ram:-3072}"
var_disk="${var_disk:-8}"
var_os="${var_os:-debian}"
var_version="${var_version:-13}"
var_arm64="${var_arm64:-yes}"
var_unprivileged="${var_unprivileged:-1}"

function install_script() {
  LOCAL_IP=$(hostname -I | awk '{print $1}')

  msg_info "Installing Dependencies"
  $STD apt install -y valkey
  msg_ok "Installed Dependencies"

  NODE_VERSION="22" NODE_MODULE="pnpm" setup_nodejs
  PG_VERSION="17" setup_postgresql
  PG_DB_NAME="openarchiver_db" PG_DB_USER="openarchiver" setup_postgresql_db

  setup_meilisearch
  fetch_and_deploy_gh_release "openarchiver" "LogicLabs-OU/OpenArchiver" "tarball"
  JWT_KEY="$(openssl rand -hex 32)"
  SECRET_KEY="$(openssl rand -hex 32)"

  msg_info "Setting up Open Archiver"
  mkdir -p /opt/openarchiver-data
  cd /opt/openarchiver || exit
  cp .env.example .env
  sed -i "s|^NODE_ENV=.*|NODE_ENV=production|g" /opt/openarchiver/.env
  sed -i "s|^POSTGRES_DB=.*|POSTGRES_DB=$PG_DB_NAME|g" /opt/openarchiver/.env
  sed -i "s|^POSTGRES_USER=.*|POSTGRES_USER=$PG_DB_USER|g" /opt/openarchiver/.env
  sed -i "s|^POSTGRES_PASSWORD=.*|POSTGRES_PASSWORD=$PG_DB_PASS|g" /opt/openarchiver/.env
  sed -i "s|^DATABASE_URL=.*|DATABASE_URL=\"postgresql://$PG_DB_USER:$PG_DB_PASS@localhost:5432/$PG_DB_NAME\"|g" /opt/openarchiver/.env
  sed -i "s|^MEILI_HOST=.*|MEILI_HOST=http://localhost:7700|g" /opt/openarchiver/.env
  sed -i "s|^MEILI_MASTER_KEY=.*|MEILI_MASTER_KEY=$MEILISEARCH_MASTER_KEY|g" /opt/openarchiver/.env
  sed -i "s|^REDIS_HOST=.*|REDIS_HOST=localhost|g" /opt/openarchiver/.env
  sed -i "s|^REDIS_USER=.*|REDIS_USER=|g" /opt/openarchiver/.env
  sed -i "s|^REDIS_PASSWORD=.*|REDIS_PASSWORD=|g" /opt/openarchiver/.env
  sed -i "s|^STORAGE_LOCAL_ROOT_PATH=.*|STORAGE_LOCAL_ROOT_PATH=/opt/openarchiver-data|g" /opt/openarchiver/.env
  sed -i "s|^JWT_SECRET=.*|JWT_SECRET=$JWT_KEY|g" /opt/openarchiver/.env
  sed -i "s|^ENCRYPTION_KEY=.*|ENCRYPTION_KEY=$SECRET_KEY|g" /opt/openarchiver/.env
  sed -i "s|^TIKA_URL=.*|TIKA_URL=|g" /opt/openarchiver/.env
  sed -i "s|^ORIGIN=.*|ORIGIN=http://$LOCAL_IP:3000|g" /opt/openarchiver/.env
  $STD pnpm install --shamefully-hoist --frozen-lockfile --prod=false
  $STD pnpm rebuild
  $STD pnpm run build:oss
  $STD pnpm db:migrate
  msg_ok "Setup Open Archiver"

  msg_info "Creating Service"
  cat << EOF > /etc/systemd/system/openarchiver.service
[Unit]
Description=Open Archiver Service
After=network-online.target

[Service]
Type=simple
User=root
EnvironmentFile=/opt/openarchiver/.env
WorkingDirectory=/opt/openarchiver
ExecStart=/usr/bin/pnpm docker-start:oss
Restart=on-failure

[Install]
WantedBy=multi-user.target
EOF
  systemctl enable -q --now openarchiver
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
  if [[ ! -d /opt/openarchiver ]]; then
    msg_error "No ${APP} Installation Found!"
    exit
  fi

  setup_meilisearch

  if check_for_gh_release "openarchiver" "LogicLabs-OU/OpenArchiver"; then
    msg_info "Stopping Services"
    systemctl stop openarchiver
    msg_ok "Stopped Services"

    cp /opt/openarchiver/.env /opt/openarchiver.env
    CLEAN_INSTALL=1 fetch_and_deploy_gh_release "openarchiver" "LogicLabs-OU/OpenArchiver" "tarball"
    mv /opt/openarchiver.env /opt/openarchiver/.env

    msg_info "Updating Open Archiver"
    cd /opt/openarchiver || exit
    $STD pnpm install --shamefully-hoist --frozen-lockfile --prod=false
    $STD pnpm rebuild
    $STD pnpm run build:oss
    $STD pnpm db:migrate
    msg_ok "Updated Open Archiver"

    if grep -q '^ExecStart=/usr/bin/pnpm docker-start$' /etc/systemd/system/openarchiver.service; then
      sed -i 's|^ExecStart=/usr/bin/pnpm docker-start$|ExecStart=/usr/bin/pnpm docker-start:oss|' /etc/systemd/system/openarchiver.service
      systemctl daemon-reload
    fi

    msg_info "Starting Services"
    systemctl start openarchiver
    msg_ok "Started Services"
    msg_ok "Updated successfully!"
  fi

  exit
}

# shellcheck disable=SC1090
# Dynamic URL resolved at runtime
source <(curl -fsSL "$REPO_BASE/misc/bootstrap/lxc")
