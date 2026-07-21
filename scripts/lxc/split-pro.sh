#!/usr/bin/env bash
REPO_BASE="${REPO_BASE:-https://raw.githubusercontent.com/scripts-underground/proxmox/main}"

# Copyright (c) 2021-2026 community-scripts ORG
# Author: johanngrobe
# License: MIT | https://raw.githubusercontent.com/scripts-underground/proxmox/main/LICENSE
# Source: https://github.com/oss-apps/split-pro

APP="Split-Pro"
var_tags="${var_tags:-finance;expense-sharing}"
var_cpu="${var_cpu:-2}"
var_ram="${var_ram:-4096}"
var_disk="${var_disk:-6}"
var_os="${var_os:-debian}"
var_version="${var_version:-13}"
var_arm64="${var_arm64:-yes}"
var_unprivileged="${var_unprivileged:-1}"

function install_script() {
  NODE_VERSION="22" NODE_MODULE="pnpm" setup_nodejs
  PG_VERSION="17" PG_MODULES="cron" setup_postgresql

  msg_info "Installing Dependencies"
  $STD apt install -y openssl
  msg_ok "Installed Dependencies"

  PG_DB_NAME="splitpro" PG_DB_USER="splitpro" PG_DB_EXTENSIONS="pg_cron" setup_postgresql_db
  fetch_and_deploy_gh_release "split-pro" "oss-apps/split-pro" "tarball"

  msg_info "Installing Dependencies"
  cd /opt/split-pro || exit
  $STD pnpm install --frozen-lockfile
  msg_ok "Installed Dependencies"

  msg_info "Building Split Pro"
  cd /opt/split-pro || exit
  mkdir -p /opt/split-pro_data/uploads
  ln -sf /opt/split-pro_data/uploads /opt/split-pro/uploads
  NEXTAUTH_SECRET=$(openssl rand -base64 32)
  cp .env.example .env
  sed -i "s|^DATABASE_URL=.*|DATABASE_URL=\"postgresql://${PG_DB_USER}:${PG_DB_PASS}@localhost:5432/${PG_DB_NAME}\"|" .env
  sed -i "s|^NEXTAUTH_SECRET=.*|NEXTAUTH_SECRET=\"${NEXTAUTH_SECRET}\"|" .env
  sed -i "s|^NEXTAUTH_URL=.*|NEXTAUTH_URL=\"http://${LOCAL_IP}:3000\"|" .env
  sed -i "s|^NEXTAUTH_URL_INTERNAL=.*|NEXTAUTH_URL_INTERNAL=\"http://localhost:3000\"|" .env
  sed -i "/^POSTGRES_CONTAINER_NAME=/d" .env
  sed -i "/^POSTGRES_USER=/d" .env
  sed -i "/^POSTGRES_PASSWORD=/d" .env
  sed -i "/^POSTGRES_DB=/d" .env
  sed -i "/^POSTGRES_PORT=/d" .env
  $STD pnpm build
  $STD pnpm exec prisma migrate deploy
  msg_ok "Built Split Pro"

  msg_info "Creating Service"
  cat << EOF > /etc/systemd/system/split-pro.service
[Unit]
Description=Split Pro
After=network.target postgresql.service
Requires=postgresql.service

[Service]
Type=simple
User=root
WorkingDirectory=/opt/split-pro
EnvironmentFile=/opt/split-pro/.env
ExecStart=/usr/bin/pnpm start
Restart=on-failure
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF
  systemctl enable -q --now split-pro
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

  if [[ ! -d /opt/split-pro ]]; then
    msg_error "No ${APP} Installation Found!"
    exit
  fi

  if check_for_gh_release "split-pro" "oss-apps/split-pro"; then
    msg_info "Stopping Service"
    systemctl stop split-pro
    msg_ok "Stopped Service"

    msg_info "Backing up Data"
    cp /opt/split-pro/.env /opt/split-pro.env
    msg_ok "Backed up Data"

    CLEAN_INSTALL=1 fetch_and_deploy_gh_release "split-pro" "oss-apps/split-pro" "tarball"

    msg_info "Building Application"
    cd /opt/split-pro || exit
    $STD pnpm install --frozen-lockfile
    $STD pnpm build
    cp /opt/split-pro.env /opt/split-pro/.env
    rm -f /opt/split-pro.env
    ln -sf /opt/split-pro_data/uploads /opt/split-pro/uploads
    $STD pnpm exec prisma migrate deploy
    msg_ok "Built Application"

    msg_info "Starting Service"
    systemctl start split-pro
    msg_ok "Started Service"
    msg_ok "Updated successfully!"
  fi
  exit
}

# framework bootstrap
# shellcheck disable=SC1090
# Dynamic URL resolved at runtime - shellcheck cannot see the caller
source <(curl -fsSL "$REPO_BASE/misc/bootstrap/lxc")
