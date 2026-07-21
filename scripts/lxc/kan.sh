#!/usr/bin/env bash
REPO_BASE="${REPO_BASE:-https://raw.githubusercontent.com/scripts-underground/proxmox/main}"

# Sourced by lxc.bootstrap — never executed directly
# Copyright (c) 2021-2026 community-scripts ORG
# Author: MickLesk (CanbiZ)
# License: MIT | https://raw.githubusercontent.com/scripts-underground/proxmox/main/LICENSE
# Source: https://kan.bn | GitHub: https://github.com/kanbn/kan

# shellcheck disable=SC2034
# Read by the framework - shellcheck cannot see the caller
APP="Kan"
var_tags="${var_tags:-project-management;kanban}"
var_cpu="${var_cpu:-4}"
var_ram="${var_ram:-4096}"
var_disk="${var_disk:-12}"
var_os="${var_os:-debian}"
var_version="${var_version:-13}"
var_arm64="${var_arm64:-yes}"
var_unprivileged="${var_unprivileged:-1}"

function install_script() {
  msg_info "Installing Dependencies"
  $STD apt install -y build-essential git gpg
  msg_ok "Installed Dependencies"

  NODE_VERSION="20" NODE_MODULE="pnpm" setup_nodejs
  PG_VERSION="16" setup_postgresql
  PG_DB_NAME="kan" PG_DB_USER="kan" setup_postgresql_db
  fetch_and_deploy_gh_tag "kan" "kanbn/kan" "latest" "/opt/kan"

  msg_info "Configuring Kan (Patience)"
  cd /opt/kan || exit

  mkdir -p data

  local BETTER_AUTH_SECRET
  BETTER_AUTH_SECRET=$(openssl rand -base64 26 | tr -dc 'a-zA-Z0-9' | head -c 32)
  cat << EOF > /opt/kan/.env
BETTER_AUTH_TRUSTED_ORIGINS=http://$LOCAL_IP:3000
NEXT_PUBLIC_BASE_URL=http://$LOCAL_IP:3000
BETTER_AUTH_SECRET=$BETTER_AUTH_SECRET
POSTGRES_URL=postgres://$PG_DB_USER:$PG_DB_PASS@localhost:5432/$PG_DB_NAME
NEXT_PUBLIC_ALLOW_CREDENTIALS=true
TRELLO_APP_API_KEY=
TRELLO_APP_API_SECRET=
HOSTNAME=0.0.0.0
PORT=3000
NODE_ENV=production
EOF

  $STD pnpm install --ignore-scripts --prod=false

  export CI=true
  find /opt/kan/packages /opt/kan/apps -name 'tsconfig.json' -exec sed -i 's|"@kan/tsconfig/|"../../tooling/typescript/|g' {} +
  export NEXT_PUBLIC_USE_STANDALONE_OUTPUT=true
  $STD pnpm build --filter=@kan/web
  unset NEXT_PUBLIC_USE_STANDALONE_OUTPUT CI
  msg_ok "Configured Kan"

  msg_info "Setting up Standalone"
  mkdir -p /opt/kan/apps/web/.next/standalone/apps/web/.next/static
  cp -r /opt/kan/apps/web/.next/static/* /opt/kan/apps/web/.next/standalone/apps/web/.next/static/
  cp -r /opt/kan/apps/web/public /opt/kan/apps/web/.next/standalone/apps/web/public
  msg_ok "Set up Standalone"

  msg_info "Running Database Migrations"
  cd /opt/kan/packages/db || exit
  $STD pnpm exec drizzle-kit migrate
  msg_ok "Ran Database Migrations"

  msg_info "Creating Service"
  cat << EOF > /etc/systemd/system/kan.service
[Unit]
Description=Kan Board
Requires=postgresql.service
After=network.target postgresql.service

[Service]
Type=simple
User=root
WorkingDirectory=/opt/kan/apps/web/.next/standalone
EnvironmentFile=/opt/kan/.env
ExecStart=/usr/bin/node apps/web/server.js
Restart=on-failure
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF
  systemctl enable -q --now kan
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

  if [[ ! -d /opt/kan ]]; then
    msg_error "No ${APP} Installation Found!"
    exit
  fi

  if check_for_gh_tag "kan" "kanbn/kan"; then
    msg_info "Stopping Service"
    systemctl stop kan
    msg_ok "Stopped Service"

    msg_info "Backing up Data"
    cp /opt/kan/.env /opt/kan.env.bak
    msg_ok "Backed up Data"

    fetch_and_deploy_gh_tag "kan" "kanbn/kan" "latest" "/opt/kan"

    msg_info "Restoring Configuration"
    cp /opt/kan.env.bak /opt/kan/.env
    rm -f /opt/kan.env.bak
    msg_ok "Restored Configuration"

    msg_info "Building Application"
    cd /opt/kan || exit
    set -a && source /opt/kan/.env && set +a
    export NEXT_PUBLIC_USE_STANDALONE_OUTPUT=true
    $STD pnpm install --ignore-scripts --prod=false
    export CI=true
    find /opt/kan/packages /opt/kan/apps -name 'tsconfig.json' -exec sed -i 's|"@kan/tsconfig/|"../../tooling/typescript/|g' {} +
    $STD pnpm build --filter=@kan/web
    unset NEXT_PUBLIC_USE_STANDALONE_OUTPUT CI
    msg_ok "Built Application"

    msg_info "Setting up Standalone"
    mkdir -p /opt/kan/apps/web/.next/standalone/apps/web/.next/static
    cp -r /opt/kan/apps/web/.next/static/* /opt/kan/apps/web/.next/standalone/apps/web/.next/static/
    cp -r /opt/kan/apps/web/public /opt/kan/apps/web/.next/standalone/apps/web/public
    msg_ok "Set up Standalone"

    msg_info "Running Database Migrations"
    cd /opt/kan/packages/db || exit
    $STD pnpm exec drizzle-kit migrate
    msg_ok "Ran Database Migrations"

    msg_info "Starting Service"
    systemctl start kan
    msg_ok "Started Service"
    msg_ok "Updated successfully!"
  fi
  exit
}

# framework bootstrap
# shellcheck disable=SC1090
# Dynamic URL resolved at runtime - shellcheck cannot see the caller
source <(curl -fsSL "$REPO_BASE/misc/bootstrap/lxc")
