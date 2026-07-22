#!/usr/bin/env bash
REPO_BASE="${REPO_BASE:-https://raw.githubusercontent.com/scripts-underground/proxmox/main}"

# Sourced by lxc.bootstrap — never executed directly
# Copyright (c) 2021-2026 community-scripts ORG
# Author: MickLesk (CanbiZ)
# License: MIT | https://raw.githubusercontent.com/scripts-underground/proxmox/main/LICENSE
# Source: https://github.com/papra-hq/papra

# shellcheck disable=SC2034
APP="Papra"
var_tags="${var_tags:-document-management}"
var_cpu="${var_cpu:-2}"
var_ram="${var_ram:-2048}"
var_disk="${var_disk:-10}"
var_os="${var_os:-debian}"
var_version="${var_version:-13}"
var_arm64="${var_arm64:-yes}"
var_unprivileged="${var_unprivileged:-1}"

function install_script() {
  msg_info "Installing Dependencies"
  $STD apt install -y \
    build-essential \
    tesseract-ocr \
    tesseract-ocr-all
  msg_ok "Installed Dependencies"

  RELEASE=$(curl -fsSL https://api.github.com/repos/papra-hq/papra/releases | grep -oP '"tag_name":\s*"\K@papra/app@[^"]+' | head -n1)
  fetch_and_deploy_gh_release "papra" "papra-hq/papra" "tarball" "${RELEASE}" "/opt/papra"

  pnpm_version=$(grep -oP '"packageManager":\s*"pnpm@\K[^"]+' /opt/papra/package.json)
  NODE_VERSION="26" NODE_MODULE="pnpm@$pnpm_version" setup_nodejs

  msg_info "Installing Papra (Patience)"
  cd /opt/papra || exit
  $STD pnpm install --frozen-lockfile
  $STD pnpm --filter "@papra/app-client..." run build
  $STD pnpm --filter "@papra/app-server..." run build
  ln -sf /opt/papra/apps/papra-client/dist /opt/papra/apps/papra-server/public
  msg_ok "Installed Papra"

  msg_info "Configuring Papra"
  LOCAL_IP=$(hostname -I | awk '{print $1}')
  mkdir -p /opt/papra_data/{db,documents,ingestion}
  [[ ! -f /opt/papra_data/.secret ]] && openssl rand -hex 32 > /opt/papra_data/.secret
  cat << EOF > /opt/papra/apps/papra-server/.env
NODE_ENV=production
SERVER_SERVE_PUBLIC_DIR=true
PORT=1221
DATABASE_URL=file:/opt/papra_data/db/db.sqlite
DOCUMENT_STORAGE_FILESYSTEM_ROOT=/opt/papra_data/documents
PAPRA_CONFIG_DIR=/opt/papra_data
AUTH_SECRET=$(cat /opt/papra_data/.secret)
BETTER_AUTH_SECRET=$(cat /opt/papra_data/.secret)
BETTER_AUTH_TELEMETRY=0
CLIENT_BASE_URL=http://${LOCAL_IP}:1221
SERVER_BASE_URL=http://${LOCAL_IP}:1221
EMAILS_DRY_RUN=true
INGESTION_FOLDER_IS_ENABLED=true
INGESTION_FOLDER_ROOT_PATH=/opt/papra_data/ingestion
EOF
  msg_ok "Configured Papra"

  msg_info "Creating Service"
  cat << EOF > /etc/systemd/system/papra.service
[Unit]
Description=Papra Document Management
After=network.target

[Service]
Type=simple
WorkingDirectory=/opt/papra/apps/papra-server
EnvironmentFile=/opt/papra/apps/papra-server/.env
ExecStartPre=/usr/bin/pnpm run migrate:up
ExecStart=/usr/bin/node dist/index.js

[Install]
WantedBy=multi-user.target
EOF
  systemctl enable -q --now papra
  msg_ok "Created Service"
}

function post_install_script() {
  msg_ok "Completed Successfully!\n"
  echo -e "${CREATING}${GN}${APP} setup has been successfully initialized!${CL}"
  echo -e "${INFO}${YW} Access it using the following URL:${CL}"
  echo -e "${TAB}${GATEWAY}${BGN}http://${IP}:1221${CL}"
}

function update_script() {
  header_info
  check_container_storage
  check_container_resources

  if [[ ! -d /opt/papra ]]; then
    msg_error "No ${APP} Installation Found!"
    exit
  fi

  if check_for_gh_release "papra" "papra-hq/papra"; then
    msg_info "Stopping Service"
    systemctl stop papra
    msg_ok "Stopped Service"

    create_backup /opt/papra/apps/papra-server/.env

    CLEAN_INSTALL=1 fetch_and_deploy_gh_release "papra" "papra-hq/papra" "tarball"

    restore_backup

    pnpm_version=$(grep -oP '"packageManager":\s*"pnpm@\K[^"]+' /opt/papra/package.json)
    NODE_VERSION="26" NODE_MODULE="pnpm@$pnpm_version" setup_nodejs

    msg_info "Building Application"
    cd /opt/papra || exit
    if [[ ! -f /opt/papra/apps/papra-server/.env ]]; then
      msg_warn ".env missing, regenerating from defaults"
      LOCAL_IP=$(hostname -I | awk '{print $1}')
      cat << EOF > /opt/papra/apps/papra-server/.env
NODE_ENV=production
SERVER_SERVE_PUBLIC_DIR=true
PORT=1221
DATABASE_URL=file:/opt/papra_data/db/db.sqlite
DOCUMENT_STORAGE_FILESYSTEM_ROOT=/opt/papra_data/documents
PAPRA_CONFIG_DIR=/opt/papra_data
AUTH_SECRET=$(cat /opt/papra_data/.secret)
BETTER_AUTH_SECRET=$(cat /opt/papra_data/.secret)
BETTER_AUTH_TELEMETRY=0
CLIENT_BASE_URL=http://${LOCAL_IP}:1221
SERVER_BASE_URL=http://${LOCAL_IP}:1221
EMAILS_DRY_RUN=true
INGESTION_FOLDER_IS_ENABLED=true
INGESTION_FOLDER_ROOT_PATH=/opt/papra_data/ingestion
EOF
    fi
    $STD pnpm install --frozen-lockfile
    $STD pnpm --filter "@papra/app-client..." run build
    $STD pnpm --filter "@papra/app-server..." run build
    ln -sf /opt/papra/apps/papra-client/dist /opt/papra/apps/papra-server/public
    msg_ok "Built Application"

    msg_info "Starting Service"
    systemctl start papra
    msg_ok "Started Service"
    msg_ok "Updated successfully!"
  fi
  exit
}

# framework bootstrap
# shellcheck disable=SC1090
# Dynamic URL resolved at runtime - shellcheck cannot follow
source <(curl -fsSL "$REPO_BASE/misc/bootstrap/lxc")
