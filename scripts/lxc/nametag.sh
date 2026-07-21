#!/usr/bin/env bash
# shellcheck disable=SC2034
REPO_BASE="${REPO_BASE:-https://raw.githubusercontent.com/scripts-underground/proxmox/main}"

# Copyright (c) 2021-2026 community-scripts ORG
# Author: MickLesk (CanbiZ)
# License: MIT | https://raw.githubusercontent.com/scripts-underground/proxmox/main/LICENSE
# Source: https://github.com/mattogodoy/nametag

# shellcheck disable=SC2034
# Read by the framework - shellcheck cannot see the caller
APP="Nametag"
var_tags="${var_tags:-contacts;crm}"
var_cpu="${var_cpu:-2}"
var_ram="${var_ram:-2048}"
var_disk="${var_disk:-8}"
var_os="${var_os:-debian}"
var_version="${var_version:-13}"
var_arm64="${var_arm64:-yes}"
var_unprivileged="${var_unprivileged:-1}"

function install_script() {
  PG_VERSION="16" setup_postgresql
  PG_DB_NAME="nametag_db" PG_DB_USER="nametag" setup_postgresql_db
  NODE_VERSION="20" setup_nodejs
  fetch_and_deploy_gh_release "nametag" "mattogodoy/nametag" "tarball" "latest" "/opt/nametag"

  msg_info "Setting up Application"
  cd /opt/nametag || exit
  $STD npm ci
  DATABASE_URL="postgresql://${PG_DB_USER}:${PG_DB_PASS}@127.0.0.1:5432/${PG_DB_NAME}" $STD npx prisma generate
  DATABASE_URL="postgresql://${PG_DB_USER}:${PG_DB_PASS}@127.0.0.1:5432/${PG_DB_NAME}" $STD npx prisma migrate deploy
  msg_ok "Set up Application"

  msg_info "Configuring Nametag"
  NEXTAUTH_SECRET=$(openssl rand -base64 32)
  CRON_SECRET=$(openssl rand -base64 16)
  mkdir -p /opt/nametag/data/photos
  cat << EOF > /opt/nametag/.env
DATABASE_URL=postgresql://${PG_DB_USER}:${PG_DB_PASS}@127.0.0.1:5432/${PG_DB_NAME}
NEXTAUTH_URL=http://${LOCAL_IP}:3000
NEXTAUTH_SECRET=${NEXTAUTH_SECRET}
CRON_SECRET=${CRON_SECRET}
PHOTO_STORAGE_PATH=/opt/nametag/data/photos
NODE_ENV=production
EOF
  msg_ok "Configured Nametag"

  msg_info "Building Application"
  cd /opt/nametag || exit
  set -a
  source /opt/nametag/.env
  set +a
  $STD npm run build
  cp -r /opt/nametag/.next/static /opt/nametag/.next/standalone/.next/static
  cp -r /opt/nametag/public /opt/nametag/.next/standalone/public
  msg_ok "Built Application"

  msg_info "Running Production Seed"
  cd /opt/nametag || exit
  $STD npx esbuild prisma/seed.production.ts --platform=node --format=cjs --outfile=prisma/seed.production.js --bundle --external:@prisma/client --external:pg --minify
  $STD node prisma/seed.production.js
  msg_ok "Ran Production Seed"

  msg_info "Creating Service"
  cat << EOF > /etc/systemd/system/nametag.service
[Unit]
Description=Nametag - Personal Relationships Manager
After=network.target postgresql.service

[Service]
Type=simple
WorkingDirectory=/opt/nametag
EnvironmentFile=/opt/nametag/.env
ExecStart=/usr/bin/node /opt/nametag/.next/standalone/server.js
Restart=on-failure
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF
  systemctl enable -q --now nametag
  msg_ok "Created Service"

  msg_info "Setting up Cron Jobs"
  cat << EOF > /etc/cron.d/nametag
0 8 * * * root curl -sf -H "Authorization: Bearer ${CRON_SECRET}" http://127.0.0.1:3000/api/cron/send-reminders >/dev/null 2>&1
0 3 * * * root curl -sf -H "Authorization: Bearer ${CRON_SECRET}" http://127.0.0.1:3000/api/cron/purge-deleted >/dev/null 2>&1
EOF
  chmod 644 /etc/cron.d/nametag
  msg_ok "Set up Cron Jobs"
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

  if [[ ! -d /opt/nametag ]]; then
    msg_error "No ${APP} Installation Found!"
    exit
  fi

  if check_for_gh_release "nametag" "mattogodoy/nametag"; then
    msg_info "Stopping Service"
    systemctl stop nametag
    msg_ok "Stopped Service"

    msg_info "Backing up Data"
    cp /opt/nametag/.env /opt/nametag.env.bak
    cp -r /opt/nametag/data /opt/nametag_data_bak
    msg_ok "Backed up Data"

    CLEAN_INSTALL=1 fetch_and_deploy_gh_release "nametag" "mattogodoy/nametag" "tarball" "latest" "/opt/nametag"

    cp /opt/nametag.env.bak /opt/nametag/.env

    msg_info "Rebuilding Application"
    cd /opt/nametag || exit
    $STD npm ci
    set -a
    source /opt/nametag/.env
    set +a
    $STD npx prisma generate
    $STD npm run build
    cp -r /opt/nametag/.next/static /opt/nametag/.next/standalone/.next/static
    cp -r /opt/nametag/public /opt/nametag/.next/standalone/public
    msg_ok "Rebuilt Application"

    msg_info "Restoring Data"
    cp /opt/nametag.env.bak /opt/nametag/.env
    cp -r /opt/nametag_data_bak/. /opt/nametag/data/
    rm -f /opt/nametag.env.bak
    rm -rf /opt/nametag_data_bak
    msg_ok "Restored Data"

    msg_info "Running Migrations"
    cd /opt/nametag || exit
    $STD npx prisma migrate deploy
    msg_ok "Ran Migrations"

    msg_info "Starting Service"
    systemctl start nametag
    msg_ok "Started Service"
    msg_ok "Updated Successfully!"
  fi
  exit
}

# framework bootstrap
# shellcheck disable=SC1090
# Dynamic URL resolved at runtime - shellcheck cannot follow
source <(curl -fsSL "$REPO_BASE/misc/bootstrap/lxc")
